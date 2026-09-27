-- =============================================================================
-- 40_engine / 01 — alarm incidents, classification, and the funnel  STAGE: WOA_ADMIN
-- =============================================================================
-- Implements : US-24..US-26, US-53..US-60 (alarm intelligence, M9), FR-63, FR-64
-- Proves     : T-60 (GATING), T-61 (GATING), T-68 (GATING), T-70, T-86
-- Authority  : ADR-0017 (three classes, UNDETERMINED policy, anti-gaming rule),
--              ADR-0004 (deterministic code decides state), AGENTS.md rule 3
-- Parameter  : <% database %>
--
-- ===================== WHAT THIS DECIDES, AND WHAT IT MAY NOT ================
--
-- Deterministic SQL decides every incident's class. No model classifies an
-- alarm; the model's output is only one of the pieces of EVIDENCE weighed
-- (ADR-0004). Three classes, never two (ADR-0017):
--
--   ACTIONABLE    safety-critical code, OR elevated model evidence on the
--                 component, OR corroborated by another source and not
--                 self-clearing
--   NUISANCE      chattering (>=3 trips), every trip auto-reset, NEVER
--                 recurred within 14 days, NO corroboration, NOT
--                 safety-critical, NOT elevated, the component is actually
--                 MONITORED, it HAS a matched-load reading and that reading is
--                 NOT above normal, and its point-in-time risk is below MEDIUM — all nine
--   UNDETERMINED  everything else. Stays in the queue, ranked below
--                 actionable, never hidden, never suppressible
--
-- NUISANCE is the hardest class to earn ON PURPOSE. It is the only class that
-- could lose a real failure, so every one of its conditions is a guard, and the
-- two AGENTS.md rule-3 guards (safety-critical, elevated risk) are written into
-- the WHERE of the classification rather than applied afterwards.
--
-- ===================== WHAT "ELEVATED" MAY BE BUILT FROM =====================
--
-- Only from signals the system would have at the time: the anomaly detector's
-- flags and the CMS alarm stream. NEVER from GEN_FAILURE_EVENT — ground truth
-- used inside a classifier would make T-60 pass by cheating. Ground truth
-- appears in exactly one place in this file: the T-60 test, which is where it
-- belongs.
--
-- Where no evidence exists (before the anomaly detector's detection window),
-- the absence is NOT read as health. An incident we cannot assess cannot be
-- called nuisance — it is UNDETERMINED. That raises the undetermined rate, and
-- the rate is published (ADR-0017) rather than hidden.
--
-- ===================== THE EVIDENCE, STORED (FR-63, T-68) ====================
--
-- ADR-0017 names four channels. Each incident gets exactly one row per channel
-- in ENG_INCIDENT_EVIDENCE, with a verdict, the measured value and the
-- reference it was compared to, so a human can disagree with the conclusion:
--
--   CORROBORATION     another alarm SOURCE on the turbine within +/-1 day
--   OPERATING_POINT   the component's primary CMS reading AT MATCHED LOAD
--                     (HIGH/FULL bands, 25_ml/01_features) against its own
--                     baseline. Above the class p95 = load does NOT explain it
--   RESET_RECURRENCE  auto-reset, and whether the code came back within 14 days
--   MODEL             anomaly/CMS elevation, the classifier's risk for that
--                     component ON THE INCIDENT DATE, and the highest risk on
--                     the TURBINE from a score dated on or before it (I-19,
--                     FR-32). Never a later score: that is evidence the
--                     system did not have
--
-- The stored verdicts are the inputs the CASE below actually weighed, not a
-- commentary written beside it; DQ-T68-CONSISTENT checks that no NUISANCE
-- incident carries an ACTIONABLE verdict on any channel.
--
-- OPERATING_POINT and the point-in-time risk were NEW in D10. Both may only
-- make NUISANCE harder to earn, never easier — so T-60 (zero real failures
-- hidden) cannot regress because of them. A MISSING matched-load reading also
-- blocks nuisance: absence of evidence is not health, and without the rule
-- DQ-T68-EVIDENCE-CONSISTENT would fail on an incident the CASE had accepted.
-- Measured on first deploy: the two component-level guards blocked 0 of the 35
-- nuisance calls (all read normal at matched load, all under 0.30 risk). The
-- turbine-level guard (I-19) blocked 2: MH-STR-T08's GEN and PIT trips, on a
-- turbine whose other component was already scored HIGH.
--
-- ===================== THE ANTI-GAMING RULE ==================================
--
-- ENG_ALARM_FUNNEL carries compression AND real-failures-suppressed in the SAME
-- ROW. There is no view in this schema that exposes compression without it, so
-- the pairing (T-70) is structural, not a UI convention.
-- =============================================================================

use role WOA_ADMIN;
use database <% database %>;
use warehouse WOA_BUILD_WH;

-- ---------------------------------------------------------------------------
-- 1. Incidents — gaps-and-islands per turbine and alarm code
-- ---------------------------------------------------------------------------
-- A repeat of the same code on the same turbine within 24 HOURS of the
-- previous trip's end continues the incident.
--
-- The first cut used 60 minutes and compressed 340k alarms to 299k incidents
-- (1.1:1) — every chattering episode fragmented. Measured on the stream, repeat
-- SCADA trips of one code on one turbine are a median 5.7h apart (p90 18h), so
-- an episode is a day, not an hour. This characterises the alarm stream; it was
-- NOT chosen to move T-60, which the grouping window barely touches.

create table if not exists ENGINE.ENG_INCIDENT (
    incident_id          varchar(80)   not null,
    turbine_id           varchar(20)   not null,
    site_code            varchar(20),
    component_id         varchar(30),
    component_class_code varchar(3),
    alarm_code           varchar(40)   not null,
    alarm_source         varchar(20),
    alarm_name           varchar(200),
    severity             varchar(20),
    is_safety_critical   boolean       not null,
    incident_start       timestamp_ntz not null,
    incident_end         timestamp_ntz,
    n_alarms             integer       not null,
    all_auto_reset       boolean       not null,
    is_corroborated      boolean       not null,
    is_elevated          boolean       not null,
    has_evidence         boolean       not null,
    incident_class       varchar(20)   not null,
    class_reason         varchar(500)  not null,
    noise_condition      varchar(20),
    built_at             timestamp_ntz not null,
    is_synthetic         boolean       not null default true,
    constraint pk_eng_incident primary key (incident_id)
);

-- One row per incident per ADR-0017 channel (FR-63, T-68). Written only by
-- SP_BUILD_INCIDENTS, in the same run as the classification it explains.
create table if not exists ENGINE.ENG_INCIDENT_EVIDENCE (
    incident_id      varchar(80)   not null,
    channel          varchar(20)   not null,   -- CORROBORATION | OPERATING_POINT | RESET_RECURRENCE | MODEL
    verdict          varchar(20)   not null,   -- SUPPORTS_ACTIONABLE | SUPPORTS_NUISANCE | NO_EVIDENCE
    measured_value   number(18,6),
    reference_value  number(18,6),
    as_of_date       date,
    detail           varchar(500)  not null,
    built_at         timestamp_ntz not null,
    is_synthetic     boolean       not null default true,
    constraint pk_eng_incident_evidence primary key (incident_id, channel)
);

create or replace procedure ENGINE.SP_BUILD_INCIDENTS()
returns varchar
language sql
execute as caller
as
$$
declare
    n_alarms     integer;
    n_incidents  integer;
    n_act        integer;
    n_und        integer;
    n_nui        integer;
begin
    create or replace temporary table ENGINE.ENG_TMP_ISLAND as
    select
        a.*,
        sum(case when a.prev_end is null
                   or datediff(minute, a.prev_end, a.alarm_start) > 1440
                 then 1 else 0 end)
            over (partition by a.turbine_id, a.alarm_code order by a.alarm_start, a.alarm_id
                  rows unbounded preceding) as island_no
    from (
        select
            f.alarm_id, f.turbine_id, f.site_code, f.component_id, f.alarm_code,
            f.alarm_source, f.alarm_start, coalesce(f.alarm_end, f.alarm_start) as alarm_end,
            f.is_auto_reset,
            lag(coalesce(f.alarm_end, f.alarm_start))
                over (partition by f.turbine_id, f.alarm_code order by f.alarm_start, f.alarm_id) as prev_end
        from RAW.FCT_ALARM_NORMALISED f
    ) a;

    create or replace temporary table ENGINE.ENG_TMP_INC as
    select
        i.turbine_id || '|' || i.alarm_code || '|' || to_varchar(min(i.alarm_start), 'YYYYMMDDHH24MISS') as incident_id,
        i.turbine_id,
        max(i.site_code)              as site_code,
        max(i.component_id)           as component_id,
        i.alarm_code,
        max(i.alarm_source)           as alarm_source,
        min(i.alarm_start)            as incident_start,
        max(i.alarm_end)              as incident_end,
        count(*)                      as n_alarms,
        booland_agg(coalesce(i.is_auto_reset, false)) as all_auto_reset
    from ENGINE.ENG_TMP_ISLAND i
    group by i.turbine_id, i.alarm_code, i.island_no;

    -- Evidence, from small daily rollups rather than correlated subqueries
    -- (Snowflake cannot evaluate a correlated EXISTS with a range predicate,
    -- and joining 340k raw alarms per incident would explode anyway).
    --   Corroboration : another SOURCE on the same turbine the same day or the
    --                   day either side. Day grain approximates the 24h window,
    --                   erring towards MORE corroboration, which can only make
    --                   an incident harder to call nuisance — the safe side.
    --   Elevated      : an anomaly flag on the component within +/-3 days, or a
    --                   CMS alarm on the turbine within +/-7 days.
    --   Coverage      : whether the anomaly detector had an opinion at all.
    create or replace temporary table ENGINE.ENG_TMP_SRC_DAY as
    select turbine_id, alarm_start::date as day, alarm_source,
           max(iff(alarm_source = 'CMS', 1, 0)) as has_cms
    from RAW.FCT_ALARM_NORMALISED
    group by 1, 2, 3;

    create or replace temporary table ENGINE.ENG_TMP_ANOM_DAY as
    select s.component_id, dc.turbine_id, s.scored_date as day
    from ML.SCORE_COMPONENT_ANOMALY s
    join RAW.DIM_COMPONENT dc on dc.component_id = s.component_id
    where s.is_anomaly;

    create or replace temporary table ENGINE.ENG_TMP_CORR as
    select c.incident_id, count(sd.day) > 0 as is_corroborated
    from ENGINE.ENG_TMP_INC c
    left join ENGINE.ENG_TMP_SRC_DAY sd
      on sd.turbine_id = c.turbine_id
     and sd.alarm_source <> c.alarm_source
     and sd.day between dateadd(day, -1, c.incident_start::date) and dateadd(day, 1, c.incident_end::date)
    group by c.incident_id;

    create or replace temporary table ENGINE.ENG_TMP_CMS as
    select c.incident_id, count(sd.day) > 0 as has_cms_near
    from ENGINE.ENG_TMP_INC c
    left join ENGINE.ENG_TMP_SRC_DAY sd
      on sd.turbine_id = c.turbine_id
     and sd.has_cms = 1
     and sd.day between dateadd(day, -7, c.incident_start::date) and dateadd(day, 7, c.incident_start::date)
    group by c.incident_id;

    create or replace temporary table ENGINE.ENG_TMP_ANOMNEAR as
    select c.incident_id, count(ad.day) > 0 as has_anomaly_near
    from ENGINE.ENG_TMP_INC c
    left join ENGINE.ENG_TMP_ANOM_DAY ad
      on ad.turbine_id = c.turbine_id
     and (c.component_id is null or ad.component_id = c.component_id)
     and ad.day between dateadd(day, -3, c.incident_start::date) and dateadd(day, 3, c.incident_start::date)
    group by c.incident_id;

    create or replace temporary table ENGINE.ENG_TMP_RECUR as
    select incident_id,
           coalesce(datediff(day, incident_end,
                    lead(incident_start) over (partition by turbine_id, alarm_code order by incident_start)) <= 14,
                    false) as recurs_14d
    from ENGINE.ENG_TMP_INC;

    -- OPERATING_POINT: the matched-load reading on the incident date. The class
    -- p95 is a fixed reference over the whole feature history, the same
    -- calibration BL-TRIVIAL-THRESHOLD uses; it reads no label.
    create or replace temporary table ENGINE.ENG_TMP_OPPOINT as
    with ref as (
        select component_class_code,
               approx_percentile(primary_vs_own_baseline, 0.95) as p95
        from ML.FEAT_COMPONENT_DAILY
        group by 1
    )
    select c.incident_id,
           f.primary_vs_own_baseline as op_value,
           r.p95                     as op_reference,
           f.feature_date            as op_date
    from ENGINE.ENG_TMP_INC c
    join ML.FEAT_COMPONENT_DAILY f
      on f.component_id = c.component_id and f.feature_date = c.incident_start::date
    join ref r on r.component_class_code = f.component_class_code
    where f.primary_vs_own_baseline is not null;

    -- MODEL, point in time: the classifier's risk on the incident date, from
    -- that date's observable features. Scored once per (component, day).
    create or replace temporary table ENGINE.ENG_TMP_RISK_PIT as
    select f.component_id, f.feature_date,
           ML.RISK_CLASSIFIER!PREDICT(object_construct(
               'COMPONENT_CLASS_CODE', f.component_class_code,
               'PLATFORM_ID', f.platform_id,
               'PRIMARY_MEAN', coalesce(f.primary_mean, 0),
               'PRIMARY_P95', coalesce(f.primary_p95, 0),
               'PRIMARY_VS_OWN_BASELINE', coalesce(f.primary_vs_own_baseline, 0),
               'TREND_7D', coalesce(f.trend_7d, 0),
               'TREND_14D', coalesce(f.trend_14d, 0),
               'TREND_30D', coalesce(f.trend_30d, 0),
               'TREND_ACCEL', coalesce(f.trend_accel, 0),
               'THERMAL_RISE', coalesce(f.thermal_rise, 0),
               'VIB_TEMP_DIVERGENCE', coalesce(f.vib_temp_divergence, 0),
               'HOURS_HIGH_LOAD_7D', coalesce(f.hours_high_load_7d, 0),
               'STARTS_7D', coalesce(f.starts_7d, 0),
               'AGE_DAYS', f.age_days,
               'SITE_STRESSOR_FACTOR', coalesce(f.site_stressor_factor, 1),
               'DAYS_SINCE_INTERVENTION', coalesce(f.days_since_intervention, 0)
           )):probability:"True"::float as risk_pit
    from ML.FEAT_COMPONENT_DAILY f
    where (f.component_id, f.feature_date) in
          (select distinct component_id, incident_start::date from ENGINE.ENG_TMP_INC
           where component_id is not null);

    create or replace temporary table ENGINE.ENG_TMP_EVID as
    select
        c.*,
        cr.is_corroborated,
        op.op_value, op.op_reference, op.op_date,
        coalesce(op.op_value > op.op_reference, false) as op_unexplained,
        rp.risk_pit,
        coalesce(rp.risk_pit >= 0.30, false)           as risk_pit_elevated,
        -- I-19 / FR-32: MEDIUM or HIGH risk ANYWHERE on the turbine, from a
        -- score dated on or before the incident — the suppression guard is
        -- turbine-level, so the classification must be too. A later score is
        -- not evidence the system had, so it is not used.
        tr.turbine_risk_max,
        coalesce(tr.turbine_risk_max >= 0.30, false)   as turbine_risk_elevated,
        (an.has_anomaly_near or cm.has_cms_near) as is_elevated,
        -- Coverage, not merely date. The first cut checked only the date window,
        -- so a converter trip (CNV: no CMS, not in the model scope) counted as
        -- "assessed and fine" when nothing was assessing it. Seven of the nine
        -- T-60 hits were exactly that. Absence of evidence is not health: an
        -- incident is assessable only if its OWN component is scored by the
        -- detector. A component-less alarm is never assessable.
        (c.incident_start::date >= (select min(scored_date) from ML.SCORE_COMPONENT_ANOMALY)
         and c.component_id is not null
         and c.component_id in (select distinct component_id from ML.SCORE_COMPONENT_ANOMALY))
                                                                      as has_evidence,
        -- ADR-0017's nuisance signature is "auto-reset AND NEVER RECURRED". The
        -- first cut omitted the second half. A code that returns to the same
        -- turbine within 14 days is a pattern, and a pattern is not noise.
        rc.recurs_14d
    from ENGINE.ENG_TMP_INC c
    join ENGINE.ENG_TMP_RECUR    rc on rc.incident_id = c.incident_id
    join ENGINE.ENG_TMP_CORR     cr on cr.incident_id = c.incident_id
    join ENGINE.ENG_TMP_CMS      cm on cm.incident_id = c.incident_id
    join ENGINE.ENG_TMP_ANOMNEAR an on an.incident_id = c.incident_id
    left join ENGINE.ENG_TMP_OPPOINT op on op.incident_id = c.incident_id
    left join ENGINE.ENG_TMP_RISK_PIT rp
      on rp.component_id = c.component_id and rp.feature_date = c.incident_start::date
    left join (
        select c2.incident_id, max(s.risk_probability) as turbine_risk_max
        from ENGINE.ENG_TMP_INC c2
        join ML.SCORE_COMPONENT_RISK s
          on s.turbine_id = c2.turbine_id and s.scored_date <= c2.incident_start::date
        group by c2.incident_id
    ) tr on tr.incident_id = c.incident_id;

    delete from ENGINE.ENG_INCIDENT;

    insert into ENGINE.ENG_INCIDENT (
        incident_id, turbine_id, site_code, component_id, component_class_code,
        alarm_code, alarm_source, alarm_name, severity, is_safety_critical,
        incident_start, incident_end, n_alarms, all_auto_reset, is_corroborated,
        is_elevated, has_evidence, incident_class, class_reason, noise_condition, built_at)
    select
        e.incident_id, e.turbine_id, e.site_code, e.component_id, ac.component_class_code,
        e.alarm_code, e.alarm_source, ac.alarm_name, ac.severity,
        coalesce(ac.is_safety_critical, false),
        e.incident_start, e.incident_end, e.n_alarms, e.all_auto_reset,
        e.is_corroborated, e.is_elevated, e.has_evidence,
        case
            when coalesce(ac.is_safety_critical, false)                 then 'ACTIONABLE'
            when e.is_elevated                                          then 'ACTIONABLE'
            when e.is_corroborated and not e.all_auto_reset             then 'ACTIONABLE'
            when e.n_alarms >= 3 and e.all_auto_reset and not e.is_corroborated
                 and not coalesce(ac.is_safety_critical, false) and not e.is_elevated
                 and e.has_evidence and not e.recurs_14d
                 and e.op_value is not null
                 and not e.op_unexplained and not e.risk_pit_elevated
                 and not e.turbine_risk_elevated                        then 'NUISANCE'
            else 'UNDETERMINED'
        end,
        case
            when coalesce(ac.is_safety_critical, false) then 'Safety-critical code: always actionable, never suppressible'
            when e.is_elevated then 'Elevated evidence on this asset (anomaly flag within 3 days, or CMS alarm within 7)'
            when e.is_corroborated and not e.all_auto_reset then 'Corroborated by another source within 24h and did not self-clear'
            when e.n_alarms >= 3 and e.all_auto_reset and not e.is_corroborated and e.has_evidence
                 and not e.recurs_14d and e.op_value is not null and not e.op_unexplained and not e.risk_pit_elevated
                 and not e.turbine_risk_elevated
                 then e.n_alarms || ' trips, all auto-reset, never recurred within 14 days, no corroboration, no elevated evidence, reading normal at matched load'
            when e.recurs_14d and e.all_auto_reset then 'Self-clearing, but the code keeps returning to this turbine: a pattern, not noise'
            when e.op_unexplained then 'Reading above normal at matched load: load does not explain it, so not called nuisance'
            when e.risk_pit_elevated then 'Classifier risk was MEDIUM or higher on the incident date: not called nuisance'
            when e.turbine_risk_elevated then 'Another component on this turbine was scored MEDIUM or HIGH risk before this incident: not called nuisance (FR-32)'
            when not e.has_evidence then 'Nothing monitors this component (or the alarm names none): no evidence either way, so not called nuisance'
            else 'Evidence is mixed or insufficient: left for a human'
        end,
        case when e.n_alarms >= 3 and e.all_auto_reset then 'CHATTERING'
             when datediff(hour, e.incident_start, e.incident_end) >= 24 then 'STANDING'
             else null end,
        current_timestamp()::timestamp_ntz
    from ENGINE.ENG_TMP_EVID e
    left join RAW.DIM_ALARM_CODE ac on ac.alarm_code = e.alarm_code;

    n_incidents := sqlrowcount;

    -- The four channels, one row each (T-68). Written from the same ENG_TMP_EVID
    -- the classification read, so the stored evidence cannot drift from it.
    delete from ENGINE.ENG_INCIDENT_EVIDENCE;
    insert into ENGINE.ENG_INCIDENT_EVIDENCE
        (incident_id, channel, verdict, measured_value, reference_value, as_of_date, detail, built_at)
    select e.incident_id, 'CORROBORATION',
           iff(e.is_corroborated, 'SUPPORTS_ACTIONABLE', 'SUPPORTS_NUISANCE'),
           iff(e.is_corroborated, 1, 0), 1, e.incident_start::date,
           iff(e.is_corroborated,
               'Another alarm source on this turbine within +/-1 day',
               'No other alarm source on this turbine within +/-1 day'),
           current_timestamp()::timestamp_ntz
    from ENGINE.ENG_TMP_EVID e
    union all
    select e.incident_id, 'OPERATING_POINT',
           case when e.op_value is null then 'NO_EVIDENCE'
                when e.op_unexplained  then 'SUPPORTS_ACTIONABLE'
                else 'SUPPORTS_NUISANCE' end,
           e.op_value, e.op_reference, e.op_date,
           case when e.op_value is null
                    then 'No matched-load CMS reading for this component on this date'
                when e.op_unexplained
                    then 'Matched-load reading ' || round(e.op_value, 3) || ' above own baseline exceeds the class p95 '
                         || round(e.op_reference, 3) || ': load does not explain it'
                else 'Matched-load reading ' || round(e.op_value, 3) || ' vs own baseline is within the class p95 '
                     || round(e.op_reference, 3) end,
           current_timestamp()::timestamp_ntz
    from ENGINE.ENG_TMP_EVID e
    union all
    select e.incident_id, 'RESET_RECURRENCE',
           iff(e.all_auto_reset and not e.recurs_14d, 'SUPPORTS_NUISANCE', 'SUPPORTS_ACTIONABLE'),
           e.n_alarms, 3, e.incident_start::date,
           case when not e.all_auto_reset then e.n_alarms || ' trips, at least one needed a manual reset'
                when e.recurs_14d then e.n_alarms || ' trips, all auto-reset, but the code returned within 14 days'
                else e.n_alarms || ' trips, all auto-reset, did not return within 14 days' end,
           current_timestamp()::timestamp_ntz
    from ENGINE.ENG_TMP_EVID e
    union all
    select e.incident_id, 'MODEL',
           case when e.is_elevated or e.risk_pit_elevated or e.turbine_risk_elevated then 'SUPPORTS_ACTIONABLE'
                when not e.has_evidence and e.risk_pit is null                      then 'NO_EVIDENCE'
                else 'SUPPORTS_NUISANCE' end,
           coalesce(greatest(e.risk_pit, e.turbine_risk_max), e.risk_pit, e.turbine_risk_max), 0.30,
           e.incident_start::date,
           case when e.is_elevated then 'Anomaly flag within 3 days or CMS alarm within 7'
                    || coalesce('; classifier risk ' || round(e.risk_pit, 3) || ' on the day', '')
                when e.risk_pit_elevated then 'Classifier risk ' || round(e.risk_pit, 3) || ' on the incident date (MEDIUM or higher)'
                when e.turbine_risk_elevated then 'Turbine risk ' || round(e.turbine_risk_max, 3)
                    || ' (another component, scored before this incident) is MEDIUM or higher'
                when not e.has_evidence and e.risk_pit is null
                    then 'No model monitors this component (or the alarm names none)'
                else 'No anomaly or CMS elevation; classifier risk '
                     || coalesce(round(e.risk_pit, 3)::varchar, 'not scored') || ' on the day' end,
           current_timestamp()::timestamp_ntz
    from ENGINE.ENG_TMP_EVID e;

    select count(*) into :n_alarms from RAW.FCT_ALARM_NORMALISED;
    select count_if(incident_class = 'ACTIONABLE'), count_if(incident_class = 'UNDETERMINED'),
           count_if(incident_class = 'NUISANCE')
      into :n_act, :n_und, :n_nui from ENGINE.ENG_INCIDENT;

    return n_alarms || ' alarms -> ' || n_incidents || ' incidents: ' || n_act || ' actionable, '
        || n_und || ' undetermined, ' || n_nui || ' nuisance';
end;
$$;

-- ---------------------------------------------------------------------------
-- 2. T-60 — which nuisance calls preceded a real failure?
-- ---------------------------------------------------------------------------
-- The ONLY use of ground truth in this file. A nuisance incident on a
-- component (or, where the alarm carries no component, a turbine) that then
-- failed within 30 days is a real failure the system would have hidden.

create or replace view ENGINE.ENG_SUPPRESSED_FAILURE as
select
    i.incident_id, i.turbine_id, i.component_id, i.alarm_code, i.incident_start,
    f.failure_event_id, f.failure_ts, f.component_class_code as failed_class
from ENGINE.ENG_INCIDENT i
join GEN.GEN_FAILURE_EVENT f
  on f.turbine_id = i.turbine_id
 and (i.component_id is null or f.component_id = i.component_id)
 and f.failure_ts between i.incident_start and dateadd(day, 30, i.incident_start)
where i.incident_class = 'NUISANCE';

-- ---------------------------------------------------------------------------
-- 3. The funnel — compression and failures-suppressed in ONE row (T-70)
-- ---------------------------------------------------------------------------

create or replace view ENGINE.ENG_ALARM_FUNNEL as
select
    (select count(*) from RAW.FCT_ALARM_NORMALISED)                     as raw_alarms,
    count(*)                                                            as incidents,
    count_if(incident_class = 'ACTIONABLE')                             as actionable,
    count_if(incident_class = 'UNDETERMINED')                           as undetermined,
    count_if(incident_class = 'NUISANCE')                               as nuisance,
    round((select count(*) from RAW.FCT_ALARM_NORMALISED)
          / nullif(count_if(incident_class in ('ACTIONABLE', 'UNDETERMINED')), 0), 1)
                                                                        as compression_ratio,
    (select count(distinct failure_event_id) from ENGINE.ENG_SUPPRESSED_FAILURE)
                                                                        as real_failures_suppressed,
    round(count_if(incident_class = 'UNDETERMINED') / nullif(count(*), 0), 4)
                                                                        as undetermined_rate
from ENGINE.ENG_INCIDENT;

-- ---------------------------------------------------------------------------
-- 4. The operator's queue (FR-64, T-61)
-- ---------------------------------------------------------------------------
-- ONE queue: every ACTIONABLE, then every UNDETERMINED. Ordering is a priority
-- hint, not a filter (ADR-0017), so UNDETERMINED is ranked below actionable and
-- is never absent. NUISANCE is the only class outside it. queue_total lets any
-- surface that shows a page say how many it is not showing.
create or replace view ENGINE.ENG_OPERATOR_QUEUE as
select
    i.*,
    row_number() over (
        order by iff(i.incident_class = 'ACTIONABLE', 0, 1),
                 i.is_safety_critical desc, i.is_elevated desc,
                 i.incident_start desc, i.incident_id) as queue_rank,
    count(*) over ()                                    as queue_total
from ENGINE.ENG_INCIDENT i
where i.incident_class in ('ACTIONABLE', 'UNDETERMINED');

-- The demo's "a day of alarms": the same funnel, per day, same pairing.
create or replace view ENGINE.ENG_ALARM_FUNNEL_DAILY as
select
    d.day,
    d.raw_alarms,
    count(i.incident_id)                                         as incidents,
    count_if(i.incident_class = 'ACTIONABLE')                    as actionable,
    count_if(i.incident_class = 'UNDETERMINED')                  as undetermined,
    count_if(i.incident_class = 'NUISANCE')                      as nuisance,
    round(d.raw_alarms / nullif(count_if(i.incident_class in ('ACTIONABLE', 'UNDETERMINED')), 0), 1)
                                                                 as compression_ratio,
    (select count(distinct s.failure_event_id) from ENGINE.ENG_SUPPRESSED_FAILURE s
      where s.incident_start::date = d.day)                      as real_failures_suppressed
from (
    select alarm_start::date as day, count(*) as raw_alarms
    from RAW.FCT_ALARM_NORMALISED group by 1
) d
left join ENGINE.ENG_INCIDENT i on i.incident_start::date = d.day
group by d.day, d.raw_alarms;
