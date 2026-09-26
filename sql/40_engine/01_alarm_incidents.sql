-- =============================================================================
-- 40_engine / 01 — alarm incidents, classification, and the funnel  STAGE: WOA_ADMIN
-- =============================================================================
-- Implements : US-24..US-26, US-53..US-60 (alarm intelligence, M9) — first cut
-- Proves     : T-60 (GATING), T-70, T-86 (the funnel's numbers)
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
--                 safety-critical, NOT elevated, and the component is actually
--                 MONITORED — all seven
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

    create or replace temporary table ENGINE.ENG_TMP_EVID as
    select
        c.*,
        cr.is_corroborated,
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
    join ENGINE.ENG_TMP_ANOMNEAR an on an.incident_id = c.incident_id;

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
                 and e.has_evidence and not e.recurs_14d                then 'NUISANCE'
            else 'UNDETERMINED'
        end,
        case
            when coalesce(ac.is_safety_critical, false) then 'Safety-critical code: always actionable, never suppressible'
            when e.is_elevated then 'Elevated evidence on this asset (anomaly flag within 3 days, or CMS alarm within 7)'
            when e.is_corroborated and not e.all_auto_reset then 'Corroborated by another source within 24h and did not self-clear'
            when e.n_alarms >= 3 and e.all_auto_reset and not e.is_corroborated and e.has_evidence
                 and not e.recurs_14d
                 then e.n_alarms || ' trips, all auto-reset, never recurred within 14 days, no corroboration, no elevated evidence'
            when e.recurs_14d and e.all_auto_reset then 'Self-clearing, but the code keeps returning to this turbine: a pattern, not noise'
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
