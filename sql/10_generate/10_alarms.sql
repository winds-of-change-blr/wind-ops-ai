-- =============================================================================
-- 10_generate / 10 — alarm streams, all four sources           STAGE: WOA_ADMIN
-- =============================================================================
-- Implements : US-52 (four alarm sources, with seeded noise patterns)
-- Proves     : T-62 (one normalised schema), T-64 (grid dip and code cascade each
--              become ONE incident), T-65 (chattering), T-66 (standing),
--              T-67 (flood), and contributes to T-12
-- Authority  : docs/04-data/data-sources-and-synthetic-data.md §1, §4
-- Parameter  : <% database %>
--
-- FOUR SOURCES, ONE SCHEMA. Everything lands in FCT_ALARM_NORMALISED with
-- ALARM_SOURCE as a column, which is the whole point of T-62: a fifth source
-- must be addable without a schema change. The fourth source is not in the
-- company profile and is worth noting — data-quality check failures become
-- alarms on the same stream as SCADA and CMS, so the platform tells the operator
-- when it does not trust its own input, in the same queue as everything else.
--
-- THRESHOLDS COME FROM THE DATA, NOT FROM GUESSES. CMS warning and alarm levels
-- are percentiles of the fleet's own generated distribution per monitored point.
-- That is how condition-monitoring baselines are actually set, and it makes T-12
-- ("every downstream threshold is crossed by real rows") true by construction
-- rather than by luck. The reference solution asserted vibration > 1.5 against a
-- column whose maximum was 0.70; a percentile cannot do that.
--
-- SEEDED PATTERNS. Five, each existing so a specific detector can be proven to
-- work AND proven not to over-fire:
--   * chattering    — one signature trips and auto-resets repeatedly (T-65),
--                     alongside ordinary single trips that must NOT be labelled
--   * grid dip      — every turbine at one site trips within seconds, which must
--                     correlate to ONE incident, not 28 (T-64)
--   * code cascade  — one turbine emits many distinct codes in minutes, from a
--                     single sensor fault: also ONE incident (T-64)
--   * standing      — opened, never acknowledged, still open (T-66)
--   * flood         — one site's rate far exceeds its normal, which must not
--                     trigger a fleet-wide label (T-67)
-- =============================================================================

use role WOA_ADMIN;
use database <% database %>;
use warehouse WOA_BUILD_WH;

-- ---------------------------------------------------------------------------
-- GEN_CMS_THRESHOLD — warning and alarm levels per monitored point.
--
-- Derived, not declared. Rebuilt whenever CMS features are regenerated.
-- ---------------------------------------------------------------------------
create table if not exists GEN.GEN_CMS_THRESHOLD (
    monitored_point   varchar(60)  not null,
    feature_name      varchar(60)  not null,
    warning_level     number(14,6) not null,
    alarm_level       number(14,6) not null,
    fleet_median      number(14,6) not null,
    derived_at        timestamp_ntz not null,
    is_synthetic      boolean      not null default true,
    constraint pk_gen_cms_threshold primary key (monitored_point, feature_name)
);

-- ---------------------------------------------------------------------------
-- GEN_SEEDED_PATTERN — the register of deliberately planted noise patterns.
--
-- This table is what makes T-64..T-67 honest. A detector test that looks for
-- "some chattering somewhere" proves nothing; these tests assert that the
-- EXACT planted turbine, code and window were found, and that unplanted ones
-- were not. Without a register the tests would drift into tautology.
-- ---------------------------------------------------------------------------
create table if not exists GEN.GEN_SEEDED_PATTERN (
    pattern_id     varchar(40)   not null,
    pattern_type   varchar(30)   not null,
    site_code      varchar(10),
    turbine_id     varchar(20),
    alarm_code     varchar(20),
    window_start   timestamp_ntz not null,
    window_end     timestamp_ntz not null,
    alarm_count    integer       not null,
    notes          varchar(500),
    is_synthetic   boolean       not null default true,
    constraint pk_gen_seeded_pattern primary key (pattern_id)
);

create or replace procedure GEN.SP_GENERATE_ALARMS(
    window_start timestamp_ntz,
    window_end   timestamp_ntz,
    seed         varchar
)
returns varchar
language sql
execute as caller
as
$$
declare
    n_cms      integer;
    n_scada    integer;
    n_grid     integer;
    n_dq       integer;
    n_nuisance integer;
    n_seeded   integer;
begin
    delete from RAW.FCT_ALARM_NORMALISED
    where alarm_start between :window_start and :window_end;
    delete from GEN.GEN_SEEDED_PATTERN
    where window_start between :window_start and :window_end;

    -- =======================================================================
    -- Thresholds from the fleet's own distribution
    -- =======================================================================
    delete from GEN.GEN_CMS_THRESHOLD;
    insert into GEN.GEN_CMS_THRESHOLD (
        monitored_point, feature_name, warning_level, alarm_level, fleet_median, derived_at
    )
    select
        monitored_point,
        feature_name,
        round(approx_percentile(feature_value, 0.970), 6),
        round(approx_percentile(feature_value, 0.995), 6),
        round(approx_percentile(feature_value, 0.500), 6),
        current_timestamp()::timestamp_ntz
    from RAW.FCT_CMS_FEATURE
    where ts between :window_start and :window_end
    group by monitored_point, feature_name;

    -- =======================================================================
    -- SOURCE 2 — CMS threshold crossings
    -- One alarm per component / code / day: a band energy that sits above a
    -- threshold for a week is one condition, not 168 alarms.
    -- =======================================================================
    insert into RAW.FCT_ALARM_NORMALISED (
        alarm_id, turbine_id, component_id, alarm_code, alarm_source,
        alarm_start, alarm_end, is_auto_reset, acknowledged_at, site_code
    )
    with crossing as (
        select
            c.component_id,
            cp.turbine_id,
            t.site_code,
            c.monitored_point,
            c.ts::date as day,
            max(c.feature_value) as peak,
            min(th.warning_level) as warning_level,
            min(th.alarm_level)   as alarm_level,
            min(c.ts)             as first_ts
        from RAW.FCT_CMS_FEATURE c
        join GEN.GEN_CMS_THRESHOLD th
            on th.monitored_point = c.monitored_point and th.feature_name = c.feature_name
        join RAW.DIM_COMPONENT cp on cp.component_id = c.component_id
        join RAW.DIM_TURBINE t    on t.turbine_id    = cp.turbine_id
        where c.feature_name = 'BAND_ENERGY'
          and c.ts between :window_start and :window_end
        group by 1, 2, 3, 4, 5
        having max(c.feature_value) > min(th.warning_level)
    )
    select
        'AL-CMS-' || replace(x.component_id, '-', '') || '-' || to_varchar(x.day, 'YYYYMMDD') || '-' || x.code,
        x.turbine_id,
        x.component_id,
        x.code,
        'CMS',
        x.first_ts,
        -- CMS conditions persist; they close when the next day's assessment runs
        dateadd(hour, 20, x.first_ts),
        false,
        -- roughly four in five get looked at
        case when GEN.FN_RAND(x.component_id || to_varchar(x.day, 'YYYYMMDD'), :seed || 'ack') < 0.80
             then dateadd(hour, 2 + floor(30 * GEN.FN_RAND(x.component_id || to_varchar(x.day, 'YYYYMMDD'), :seed || 'ackh')), x.first_ts)
        end,
        x.site_code
    from (
        select
            c.*,
            case
                when c.monitored_point = 'GBX-HSS' and c.peak > c.alarm_level   then 'CM-VB-002'
                when c.monitored_point = 'GBX-HSS'                              then 'CM-VB-001'
                when c.monitored_point = 'GBX-IMS'                              then 'CM-VB-003'
                when c.monitored_point = 'GEN-DE'                               then 'CM-VB-004'
                when c.monitored_point = 'GEN-NDE'                              then 'CM-VB-004'
                when c.monitored_point = 'MSB-RAD' and c.peak > c.alarm_level    then 'CM-VB-006'
                when c.monitored_point = 'MSB-RAD'                              then 'CM-VB-005'
            end as code
        from crossing c
    ) x
    where x.code is not null;

    n_cms := sqlrowcount;

    -- =======================================================================
    -- SOURCE 1 — SCADA events and alarms
    -- Over-temperature alarms from signals that actually exceeded their declared
    -- normal range, one per turbine / code / day.
    -- =======================================================================
    insert into RAW.FCT_ALARM_NORMALISED (
        alarm_id, turbine_id, component_id, alarm_code, alarm_source,
        alarm_start, alarm_end, is_auto_reset, acknowledged_at, site_code
    )
    with over_temp as (
        select
            f.turbine_id,
            ds.component_id,
            t.site_code,
            f.ts::date as day,
            min(f.ts)  as first_ts,
            count(*)   as n_over,
            case ds.signal_name
                when 'TEMP_GBX_OIL'   then 'SA-OT-001'
                when 'TEMP_GBX_HSS'   then 'SA-OT-001'
                when 'TEMP_GEN_WIND'  then 'SA-OT-002'
                when 'TEMP_GEN_BEAR'  then 'SA-OT-003'
                when 'TEMP_CNV_IGBT'  then 'SA-OT-004'
                when 'TEMP_TRF_OIL'   then 'SA-OT-005'
                when 'TEMP_TRF_WIND'  then 'SA-OT-005'
            end as code
        from RAW.FCT_SIGNAL_10MIN f
        join RAW.DIM_SIGNAL ds on ds.signal_id = f.signal_id
        join RAW.DIM_TURBINE t on t.turbine_id = f.turbine_id
        where f.ts between :window_start and :window_end
          and ds.signal_type = 'TEMPERATURE'
          and f.value_avg > ds.normal_range_high
        group by 1, 2, 3, 4, ds.signal_name
    )
    select
        'AL-SCA-' || replace(o.turbine_id, '-', '') || '-' || to_varchar(o.day, 'YYYYMMDD') || '-' || o.code,
        o.turbine_id,
        o.component_id,
        o.code,
        'SCADA',
        o.first_ts,
        dateadd(minute, 20 + 10 * o.n_over, o.first_ts),
        true,                       -- over-temperature clears itself on cooling
        case when GEN.FN_RAND(o.turbine_id || to_varchar(o.day, 'YYYYMMDD') || o.code, :seed || 'ack2') < 0.6
             then dateadd(hour, 1 + floor(12 * GEN.FN_RAND(o.turbine_id || o.code, :seed || 'ackh2')), o.first_ts)
        end,
        o.site_code
    from over_temp o
    where o.code is not null
    qualify row_number() over (partition by o.turbine_id, o.day, o.code order by o.first_ts) = 1;

    n_scada := sqlrowcount;

    -- =======================================================================
    -- SOURCE 3 — GRID and balance-of-plant events
    -- Derived from the grid outages already written to FCT_TURBINE_STATE, so the
    -- two agree. A grid outage that appears as downtime but not as an alarm is
    -- exactly the sensor-record-versus-history disagreement T-7 guards against.
    -- =======================================================================
    insert into RAW.FCT_ALARM_NORMALISED (
        alarm_id, turbine_id, component_id, alarm_code, alarm_source,
        alarm_start, alarm_end, is_auto_reset, acknowledged_at, site_code
    )
    select
        'AL-GRD-' || replace(s.turbine_id, '-', '') || '-' || to_varchar(s.state_start, 'YYYYMMDDHH24MI'),
        s.turbine_id,
        null,
        case when s.exclusion_class_code = 'CURTAIL' then 'GR-CT-001' else 'GR-FT-001' end,
        'GRID',
        s.state_start,
        s.state_end,
        false,
        dateadd(minute, 5, s.state_start),   -- the control room sees these at once
        t.site_code
    from RAW.FCT_TURBINE_STATE s
    join RAW.DIM_TURBINE t on t.turbine_id = s.turbine_id
    where s.exclusion_class_code in ('GRID', 'CURTAIL')
      and s.state_start between :window_start and :window_end;

    n_grid := sqlrowcount;

    -- =======================================================================
    -- SOURCE 4 — platform data-quality checks
    --
    -- Fires on the seeded historian gaps written by SP_GENERATE_SIGNALS, found
    -- by comparing each turbine-day against the fleet MEDIAN for that day. The
    -- median matters: an earlier version compared against the fleet MAXIMUM and
    -- flagged 3,069 of 3,100 turbine-days, because a single turbine with one
    -- extra row makes every other turbine look short.
    -- =======================================================================
    insert into RAW.FCT_ALARM_NORMALISED (
        alarm_id, turbine_id, component_id, alarm_code, alarm_source,
        alarm_start, alarm_end, is_auto_reset, acknowledged_at, site_code
    )
    with per_day as (
        select
            f.turbine_id,
            f.ts::date as day,
            count(*)   as rows_seen
        from RAW.FCT_SIGNAL_10MIN f
        where f.ts between :window_start and :window_end
        group by 1, 2
    ),
    fleet as (
        select
            p.turbine_id,
            p.day,
            p.rows_seen,
            median(p.rows_seen) over (partition by p.day) as fleet_median
        from per_day p
    )
    select
        'AL-DQ-' || replace(e.turbine_id, '-', '') || '-' || to_varchar(e.day, 'YYYYMMDD'),
        e.turbine_id,
        null,
        'DQ-ST-001',
        'DQ',
        dateadd(hour, 21, e.day::timestamp_ntz),
        dateadd(hour, 23, e.day::timestamp_ntz),
        false,
        null,                              -- nobody acknowledges these yet
        t.site_code
    from fleet e
    join RAW.DIM_TURBINE t on t.turbine_id = e.turbine_id
    where e.rows_seen < e.fleet_median * 0.90;

    n_dq := sqlrowcount;

    -- =======================================================================
    -- SOURCE 1b — NUISANCE alarms, the ordinary background
    --
    -- A real turbine emits tens of short, self-clearing events a day: a pitch
    -- wobble, a brief over-temp, a yaw correction. Without them the stream had
    -- 10,600 alarms over six months against the ~400k data-sources §3 budgets,
    -- and — worse — the noise detectors had nothing to discriminate AGAINST.
    -- T-65 must not label a single trip as chattering and T-67 must not call the
    -- whole fleet flooded because one site is busy; neither claim means anything
    -- without a realistic background rate.
    --
    -- Only non-safety-critical, auto-reset-eligible codes appear here, because
    -- nothing safety-critical is ever nuisance (ADR-0017, and the suppression
    -- rule in AGENTS.md).
    -- =======================================================================
    insert into RAW.FCT_ALARM_NORMALISED (
        alarm_id, turbine_id, component_id, alarm_code, alarm_source,
        alarm_start, alarm_end, is_auto_reset, acknowledged_at, site_code
    )
    with nuisance_code as (
        select
            alarm_code,
            component_class_code,
            row_number() over (order by alarm_code) - 1 as idx,
            count(*)       over ()                      as n
        from RAW.DIM_ALARM_CODE
        where alarm_source = 'SCADA'
          and auto_reset_eligible
          and not is_safety_critical
          -- A TRIP is never a nuisance. Leaving SA-GR-001 (grid fault trip) in
          -- this pool put grid trips on six turbines at other sites inside the
          -- seeded grid-dip window, so the dip no longer looked site-scoped and
          -- T-64 failed. Severity is the right filter, not a hand-kept exclusion
          -- list that the next added code would silently escape.
          and severity <> 'TRIP'
    ),
    slot as (
        select row_number() over (order by seq4()) as n
        from table(generator(rowcount => 18))       -- ~18 events per turbine-day
    ),
    emitted as (
        select
            'AL-NUI-' || replace(d.turbine_id, '-', '') || '-' || to_varchar(d.day, 'YYYYMMDD') || '-' || lpad(s.n::varchar, 2, '0') as alarm_id,
            d.turbine_id,
            case when nc.component_class_code is not null
                 then d.turbine_id || '-' || nc.component_class_code end as component_id,
            nc.alarm_code,
            dateadd(minute, floor(1440 * GEN.FN_RAND(d.turbine_id || to_varchar(d.day, 'YYYYMMDD') || s.n::varchar, :seed || 'nuis')), d.day::timestamp_ntz) as alarm_start,
            GEN.FN_RAND(d.turbine_id || to_varchar(d.day, 'YYYYMMDD') || s.n::varchar, :seed || 'nack') as ack_draw,
            t.site_code
        from GEN.GEN_TURBINE_DAY d
        join RAW.DIM_TURBINE t on t.turbine_id = d.turbine_id
        cross join slot s
        join nuisance_code nc
            on nc.idx = floor(nc.n * GEN.FN_RAND(d.turbine_id || to_varchar(d.day, 'YYYYMMDD') || s.n::varchar, :seed || 'ncode'))
        where d.day between :window_start::date and :window_end::date
    )
    select
        e.alarm_id,
        e.turbine_id,
        e.component_id,
        e.alarm_code,
        'SCADA',
        e.alarm_start,
        dateadd(minute, 2, e.alarm_start),
        true,
        -- most nuisance alarms are never looked at, which is the point
        case when e.ack_draw < 0.12 then dateadd(hour, 3, e.alarm_start) end,
        e.site_code
    from emitted e
    -- Nuisance events are spread across the whole calendar day, so on the
    -- generation day itself the later slots land in the future. A turbine has not
    -- emitted tomorrow's alarms yet, and an alarm dated ahead of NOW would make
    -- every "open alarms" panel lie.
    where e.alarm_start <= :window_end;

    n_nuisance := sqlrowcount;

    -- =======================================================================
    -- SEEDED PATTERN 1 — CHATTERING (T-65)
    -- One turbine, one auto-reset-eligible code, 40 trips in 12 hours. The
    -- negative half of T-65 is covered by the ordinary single SCADA trips above.
    -- =======================================================================
    insert into RAW.FCT_ALARM_NORMALISED (
        alarm_id, turbine_id, component_id, alarm_code, alarm_source,
        alarm_start, alarm_end, is_auto_reset, acknowledged_at, site_code
    )
    select
        'AL-CHT-' || replace(t.turbine_id, '-', '') || '-' || lpad(g.n::varchar, 3, '0'),
        t.turbine_id,
        t.turbine_id || '-PIT',
        'SA-PT-001',
        'SCADA',
        dateadd(minute, 18 * g.n, dateadd(day, -21, :window_end)),
        dateadd(minute, 18 * g.n + 3, dateadd(day, -21, :window_end)),
        true,                              -- trips and self-clears: chattering
        null,
        t.site_code
    from RAW.DIM_TURBINE t
    cross join (select row_number() over (order by seq4()) as n from table(generator(rowcount => 40))) g
    where t.turbine_id = 'KA-CTD-T07';

    -- =======================================================================
    -- SEEDED PATTERN 2 — SITE-WIDE GRID DIP (T-64)
    -- Every turbine at GJ-KCH trips inside 90 seconds. Must correlate to ONE
    -- incident, not 28.
    -- =======================================================================
    insert into RAW.FCT_ALARM_NORMALISED (
        alarm_id, turbine_id, component_id, alarm_code, alarm_source,
        alarm_start, alarm_end, is_auto_reset, acknowledged_at, site_code
    )
    select
        'AL-DIP-' || replace(t.turbine_id, '-', ''),
        t.turbine_id,
        null,
        'SA-GR-001',
        'SCADA',
        dateadd(second, floor(90 * GEN.FN_RAND(t.turbine_id, 'dip')), dateadd(day, -14, :window_end)),
        dateadd(minute, 25, dateadd(day, -14, :window_end)),
        false,
        dateadd(minute, 4, dateadd(day, -14, :window_end)),
        t.site_code
    from RAW.DIM_TURBINE t
    where t.site_code = 'GJ-KCH';

    -- =======================================================================
    -- SEEDED PATTERN 3 — SENSOR-FAULT CODE CASCADE (T-64)
    -- One turbine, many distinct codes in eight minutes, from one root cause.
    -- =======================================================================
    insert into RAW.FCT_ALARM_NORMALISED (
        alarm_id, turbine_id, component_id, alarm_code, alarm_source,
        alarm_start, alarm_end, is_auto_reset, acknowledged_at, site_code
    )
    select
        'AL-CAS-' || replace(t.turbine_id, '-', '') || '-' || c.alarm_code,
        t.turbine_id,
        null,
        c.alarm_code,
        'SCADA',
        dateadd(second, 45 * c.idx, dateadd(day, -9, :window_end)),
        dateadd(minute, 40, dateadd(day, -9, :window_end)),
        false,
        dateadd(minute, 6, dateadd(day, -9, :window_end)),
        t.site_code
    from RAW.DIM_TURBINE t
    cross join (
        select alarm_code, row_number() over (order by alarm_code) as idx
        from RAW.DIM_ALARM_CODE
        where alarm_source = 'SCADA'
    ) c
    where t.turbine_id = 'TN-TVL-T11';

    -- =======================================================================
    -- SEEDED PATTERN 4 — STANDING ALARM (T-66)
    -- Opened 30 days ago, never acknowledged, never closed.
    -- =======================================================================
    insert into RAW.FCT_ALARM_NORMALISED (
        alarm_id, turbine_id, component_id, alarm_code, alarm_source,
        alarm_start, alarm_end, is_auto_reset, acknowledged_at, site_code
    )
    select
        'AL-STD-' || replace(t.turbine_id, '-', ''),
        t.turbine_id,
        t.turbine_id || '-YAW',
        'SA-YW-001',
        'SCADA',
        dateadd(day, -30, :window_end),
        null,                              -- still open
        false,
        null,                              -- and never acknowledged
        t.site_code
    from RAW.DIM_TURBINE t
    where t.turbine_id = 'MH-STR-T03';

    -- =======================================================================
    -- SEEDED PATTERN 5 — ALARM FLOOD AT ONE SITE (T-67)
    -- RJ-JSM emits 600 alarms in four hours. T-67's negative half matters more
    -- than its positive half: a flood detector that fires fleet-wide whenever one
    -- site is busy makes the label useless, and that is the obvious mistake.
    -- =======================================================================
    insert into RAW.FCT_ALARM_NORMALISED (
        alarm_id, turbine_id, component_id, alarm_code, alarm_source,
        alarm_start, alarm_end, is_auto_reset, acknowledged_at, site_code
    )
    select
        'AL-FLD-' || replace(t.turbine_id, '-', '') || '-' || lpad(g.n::varchar, 3, '0'),
        t.turbine_id,
        null,
        'SA-VB-001',
        'SCADA',
        dateadd(second, floor(14400 * GEN.FN_RAND(t.turbine_id || g.n::varchar, 'flood')), dateadd(day, -5, :window_end)),
        dateadd(second, 120 + floor(14400 * GEN.FN_RAND(t.turbine_id || g.n::varchar, 'flood')), dateadd(day, -5, :window_end)),
        true,
        null,
        t.site_code
    from RAW.DIM_TURBINE t
    cross join (select row_number() over (order by seq4()) as n from table(generator(rowcount => 50))) g
    where t.site_code = 'RJ-JSM';

    -- =======================================================================
    -- Nothing may be dated after the generation instant.
    --
    -- One guard for all of the inserts above rather than a clamp inside each: the
    -- DQ block stamps 21:00 and 23:00 on its day and the nuisance block spreads
    -- across the calendar day, so on the generation day itself both ran ahead of
    -- NOW. An alarm dated in the future makes every open-alarm panel and every
    -- "last 24 hours" count wrong, and T-11 rightly fails the build for it.
    --
    -- An alarm still open at the generation instant has no end yet, so a future
    -- ALARM_END becomes NULL rather than being truncated to now.
    -- =======================================================================
    delete from RAW.FCT_ALARM_NORMALISED where alarm_start > :window_end;
    update RAW.FCT_ALARM_NORMALISED set alarm_end = null where alarm_end > :window_end;
    update RAW.FCT_ALARM_NORMALISED set acknowledged_at = null where acknowledged_at > :window_end;

    -- ---- register what we planted, so the detectors can be held to it -----
    insert into GEN.GEN_SEEDED_PATTERN (
        pattern_id, pattern_type, site_code, turbine_id, alarm_code,
        window_start, window_end, alarm_count, notes
    )
    select 'SP-CHATTER-01', 'CHATTERING', 'KA-CTD', 'KA-CTD-T07', 'SA-PT-001',
           dateadd(day, -21, :window_end), dateadd(day, -20, :window_end), 40,
           'Repeated trip and auto-reset on one signature. T-65 must find this and must NOT label ordinary single trips.'
    union all
    select 'SP-GRIDDIP-01', 'GRID_DIP', 'GJ-KCH', null, 'SA-GR-001',
           dateadd(day, -14, :window_end), dateadd(day, -14, dateadd(minute, 30, :window_end)),
           (select count(*) from RAW.DIM_TURBINE where site_code = 'GJ-KCH'),
           'Every turbine at the site trips within 90 seconds. T-64 must correlate this to ONE incident.'
    union all
    select 'SP-CASCADE-01', 'CODE_CASCADE', 'TN-TVL', 'TN-TVL-T11', null,
           dateadd(day, -9, :window_end), dateadd(day, -9, dateadd(minute, 45, :window_end)),
           (select count(*) from RAW.DIM_ALARM_CODE where alarm_source = 'SCADA'),
           'One turbine, every SCADA code in eight minutes, one root cause. T-64 must correlate to ONE incident.'
    union all
    select 'SP-STANDING-01', 'STANDING', 'MH-STR', 'MH-STR-T03', 'SA-YW-001',
           dateadd(day, -30, :window_end), :window_end, 1,
           'Open 30 days, never acknowledged. T-66 must find it, and must clear it once acknowledged.'
    union all
    select 'SP-FLOOD-01', 'FLOOD', 'RJ-JSM', null, 'SA-VB-001',
           dateadd(day, -5, :window_end), dateadd(day, -5, dateadd(hour, 4, :window_end)),
           50 * (select count(*) from RAW.DIM_TURBINE where site_code = 'RJ-JSM'),
           'One site far above its normal rate in four hours. T-67 must flag the site and NOT the fleet.';

    n_seeded := sqlrowcount;

    return 'FCT_ALARM_NORMALISED: CMS=' || n_cms || ' SCADA=' || n_scada
        || ' GRID=' || n_grid || ' DQ=' || n_dq || ' NUISANCE=' || n_nuisance
        || '; seeded patterns registered=' || n_seeded;
end;
$$;
