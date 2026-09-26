-- =============================================================================
-- 30_serve / 03 — energy, performance and Turbine OEE              STAGE: WOA_ADMIN
-- =============================================================================
-- Implements : FR-24 (lost energy), FR-26 (OEE), FR-28, ADR-0003, GS-5, VQ-6, VQ-7
-- Proves     : T-21, T-23, T-25 (15_quality/07), DQ-GS5-CAUGHT
-- Authority  : ADR-0003, docs/04-data/data-model.md §5
-- Parameter  : <% database %>
--
-- ===================== TURBINE OEE, AS DECLARED ==============================
--
--   Turbine OEE = Availability x Performance        (Quality NOT modelled)
--
-- ADR-0003 defines three factors. Quality needs a forecast schedule, and the
-- data has none. ADR-0003's own fallback applies: report A x P and say so,
-- never set Quality to 1. Every row carries OEE_DEFINITION, and QUALITY_FACTOR
-- is NULL — not 1 — so nothing downstream can multiply by a quality it never had.
--
-- Both factors are computed over the SAME intervals, which is what makes their
-- product mean something:
--
--   wind-in-limits  cut-in <= wind < cut-out, and not CURTAILED (a grid-side
--                   instruction, not the turbine's doing)
--   Availability    RUNNING intervals / (RUNNING + UNAVAILABLE) intervals
--   Performance     actual energy / power-curve energy at measured wind, over
--                   the RUNNING intervals
--
-- so A x P = actual energy / expected energy over every wind-in-limits interval
-- the turbine was responsible for: production-based availability, decomposed.
--
-- Performance is measured against the IDEAL curve (FN_EXPECTED_POWER, no
-- losses), so a healthy turbine reads ~96.5%, the generator's modelled
-- conversion loss. "Underperforming" is therefore judged against the FLEET
-- MEDIAN, not against 100%: IS_UNDERPERFORMING = more than 1.5 points below it.
--
-- ===================== WHY FUNCTIONS =========================================
--
-- The arithmetic lives in SERVING.FN_* so the hand-worked fixtures (T-20..T-22)
-- exercise the same code the views run. A fixture that re-implements the
-- formula in the test proves only that the test agrees with itself.
-- =============================================================================

use role WOA_ADMIN;
use database <% database %>;
use warehouse WOA_BUILD_WH;

-- The SERVING.FN_* arithmetic functions live in 01_metrics.sql, which runs first.

-- ------------------------------------------------------- the daily aggregate
-- 108M 10-minute rows reduce to ~18k turbine-days once, here, rather than on
-- every page load. Rebuilt by SP_BUILD_TURBINE_DAY; deterministic from RAW.
create table if not exists CURATED.AGG_TURBINE_DAY (
    turbine_id               varchar(20)  not null,
    day                      date         not null,
    site_code                varchar(10)  not null,
    platform_id              varchar(10)  not null,
    n_wind_in_limits         integer      not null,
    n_running                integer      not null,
    n_unavailable            integer      not null,
    n_curtailed              integer      not null,
    actual_kwh_running       float        not null,
    expected_kwh_running     float        not null,
    expected_kwh_unavailable float        not null,
    mean_yaw_error_deg       float,
    is_synthetic             boolean      not null default true,
    constraint pk_agg_turbine_day primary key (turbine_id, day)
) comment = 'Per turbine-day energy and interval counts from FCT_SIGNAL_10MIN, over wind-in-limits intervals. Source of MET_TURBINE_OEE and MET_LOST_ENERGY.';

create or replace procedure SERVING.SP_BUILD_TURBINE_DAY()
returns varchar
language sql
execute as caller
as
$$
declare
    n integer;
    interval_min float;
begin
    select signal_interval_min into :interval_min from GEN.GEN_RUN_CONFIG order by generated_at desc limit 1;

    delete from CURATED.AGG_TURBINE_DAY;
    insert into CURATED.AGG_TURBINE_DAY (
        turbine_id, day, site_code, platform_id, n_wind_in_limits, n_running, n_unavailable, n_curtailed,
        actual_kwh_running, expected_kwh_running, expected_kwh_unavailable, mean_yaw_error_deg)
    with tagged as (
        select f.turbine_id, f.ts, f.operating_state, ds.signal_name, f.value_avg
        from RAW.FCT_SIGNAL_10MIN f
        join RAW.DIM_SIGNAL ds on ds.signal_id = f.signal_id
        where ds.signal_name in ('ACTIVE_POWER', 'WIND_SPEED', 'YAW_ERROR')
    ),
    iv as (
        select turbine_id, ts, operating_state,
               max(iff(signal_name = 'ACTIVE_POWER', value_avg, null)) as power_kw,
               max(iff(signal_name = 'WIND_SPEED',   value_avg, null)) as wind_ms,
               max(iff(signal_name = 'YAW_ERROR',    value_avg, null)) as yaw_deg
        from tagged
        group by turbine_id, ts, operating_state
    ),
    curve as (
        select iv.*, t.site_code, t.platform_id,
               iv.wind_ms >= p.cut_in_speed_ms and iv.wind_ms < p.cut_out_speed_ms  as in_limits,
               GEN.FN_EXPECTED_POWER(iv.wind_ms, p.rated_power_mw * 1000,
                                     p.cut_in_speed_ms, p.rated_speed_ms, p.cut_out_speed_ms) as expected_kw
        from iv
        join RAW.DIM_TURBINE t  on t.turbine_id = iv.turbine_id
        join RAW.DIM_PLATFORM p on p.platform_id = t.platform_id
    )
    select turbine_id, ts::date, site_code, platform_id,
           count_if(in_limits and operating_state <> 'CURTAILED'),
           count_if(in_limits and operating_state = 'RUNNING'),
           count_if(in_limits and operating_state = 'UNAVAILABLE'),
           count_if(in_limits and operating_state = 'CURTAILED'),
           coalesce(sum(iff(in_limits and operating_state = 'RUNNING', SERVING.FN_INTERVAL_KWH(power_kw, :interval_min), 0)), 0),
           coalesce(sum(iff(in_limits and operating_state = 'RUNNING', SERVING.FN_INTERVAL_KWH(expected_kw, :interval_min), 0)), 0),
           coalesce(sum(iff(in_limits and operating_state = 'UNAVAILABLE', SERVING.FN_INTERVAL_KWH(expected_kw, :interval_min), 0)), 0),
           avg(iff(operating_state = 'RUNNING', yaw_deg, null))
    from curve
    group by turbine_id, ts::date, site_code, platform_id;
    n := sqlrowcount;
    return n || ' turbine-days built';
end;
$$;

-- ------------------------------------------------------------ metric views
-- Technical availability: turbine-caused downtime only. Scheduled maintenance
-- is turbine-caused, so unlike the CONTRACTUAL figure it counts as down here;
-- grid, curtailment, force majeure and balance of plant stay excluded.
create or replace view SERVING.MET_AVAILABILITY_TECHNICAL as
select
    t.turbine_id, t.site_code, t.platform_id, w.period_hours,
    coalesce(s.excluded_hours, 0)          as excluded_hours,
    coalesce(s.turbine_down_hours, 0)      as turbine_down_hours,
    round(SERVING.FN_AVAILABILITY_PCT(w.period_hours, s.excluded_hours, s.turbine_down_hours), 3) as availability_pct,
    true                                   as is_synthetic
from RAW.DIM_TURBINE t
cross join SERVING.V_WINDOW w
left join (
    select turbine_id,
           sum(iff(exclusion_class_code is not null and exclusion_class_code <> 'SCHED_MAINT',
                   datediff(minute, state_start, coalesce(state_end, state_start)), 0)) / 60.0 as excluded_hours,
           sum(iff(exclusion_class_code is null or exclusion_class_code = 'SCHED_MAINT',
                   datediff(minute, state_start, coalesce(state_end, state_start)), 0)) / 60.0 as turbine_down_hours
    from RAW.FCT_TURBINE_STATE
    where operating_state <> 'READY'
    group by turbine_id
) s on s.turbine_id = t.turbine_id;

create or replace view SERVING.MET_TURBINE_OEE as
with f as (
    select turbine_id, site_code, platform_id,
           sum(n_running) / nullif(sum(n_running) + sum(n_unavailable), 0)       as availability_factor,
           sum(actual_kwh_running) / nullif(sum(expected_kwh_running), 0)        as performance_factor,
           sum(actual_kwh_running) / 1000                                        as actual_mwh,
           (sum(expected_kwh_running) + sum(expected_kwh_unavailable)) / 1000    as expected_mwh,
           avg(mean_yaw_error_deg)                                               as mean_yaw_error_deg
    from CURATED.AGG_TURBINE_DAY
    group by turbine_id, site_code, platform_id
)
select
    turbine_id, site_code, platform_id,
    availability_factor,
    performance_factor,
    cast(null as float)                                                          as quality_factor,
    availability_factor * performance_factor                                     as oee,
    'Availability x Performance. Quality NOT modelled: no forecast schedule exists (ADR-0003 fallback). Our adaptation, not an industry standard.' as oee_definition,
    median(performance_factor) over ()                                           as fleet_median_performance,
    performance_factor < median(performance_factor) over () - 0.015              as is_underperforming,
    actual_mwh, expected_mwh, mean_yaw_error_deg,
    true                                                                         as is_synthetic
from f;

-- Lost energy, split by cause. Underperformance loss is measured against the
-- fleet-median performance, so the idealised curve's ~3.5% conversion loss is
-- not reported as "lost" on every healthy turbine.
create or replace view SERVING.MET_LOST_ENERGY as
select
    o.turbine_id, o.site_code, o.platform_id,
    round(sum(d.expected_kwh_unavailable) / 1000, 3)                                            as lost_mwh_downtime,
    round(greatest(0, o.fleet_median_performance - o.performance_factor)
          * sum(d.expected_kwh_running) / 1000, 3)                                              as lost_mwh_underperformance,
    round(sum(d.expected_kwh_unavailable) / 1000
          + greatest(0, o.fleet_median_performance - o.performance_factor) * sum(d.expected_kwh_running) / 1000, 3)
                                                                                                as lost_mwh_total,
    true                                                                                        as is_synthetic
from SERVING.MET_TURBINE_OEE o
join CURATED.AGG_TURBINE_DAY d on d.turbine_id = o.turbine_id
group by o.turbine_id, o.site_code, o.platform_id, o.fleet_median_performance, o.performance_factor;

-- The alarm-noise numbers, compression and real-failures-suppressed together.
-- Recounted from source rather than copied from ENG_ALARM_FUNNEL, so T-86 can
-- reconcile the two instead of comparing a view with itself.
create or replace view SERVING.MET_NOISE as
select
    (select count(*) from RAW.FCT_ALARM_NORMALISED)                          as raw_alarms,
    (select sum(n_alarms) from ENGINE.ENG_INCIDENT)                          as alarms_in_incidents,
    count(*)                                                                 as incidents,
    count_if(incident_class = 'ACTIONABLE')                                  as actionable,
    count_if(incident_class = 'UNDETERMINED')                                as undetermined,
    count_if(incident_class = 'NUISANCE')                                    as nuisance,
    (select count(distinct failure_event_id) from ENGINE.ENG_SUPPRESSED_FAILURE) as real_failures_suppressed,
    true                                                                     as is_synthetic
from ENGINE.ENG_INCIDENT;
