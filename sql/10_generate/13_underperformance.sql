-- =============================================================================
-- 10_generate / 13 — seeded underperformance (GS-5)                STAGE: WOA_ADMIN
-- =============================================================================
-- Implements : GS-5 — a turbine losing energy with NO alarm and full availability
-- Proves     : the Performance factor of Turbine OEE is real (ADR-0003, T-25);
--              DQ-GS5-CAUGHT asserts it is found, and found alone
-- Authority  : ADR-0003 ("Performance ... is what makes GS-5 expressible at all")
-- Parameter  : <% database %>
--
-- ===================== WHY THIS STEP EXISTS ==================================
--
-- The signal generator writes ACTIVE_POWER = ideal x 0.965 for every running
-- turbine, plus +-1.75% measurement noise. Performance computed from that is
-- ~96.5% fleet-wide: technically not constant, practically a disguised
-- constant — the reference solution's exact defect (ADR-0003, G-7). Nothing in
-- the data gave the Performance factor anything to catch.
--
-- So three turbines get a yaw offset from day 75 of the window. Power follows
-- the standard cos^3 yaw-loss law and YAW_ERROR rises by the offset. NO alarm
-- is written, and availability is untouched: the turbine is running, reports
-- READY, and quietly loses 4-9% of its energy. That is GS-5, and only the
-- Performance factor can see it.
--
-- ===================== DETERMINISM AND IDEMPOTENCY ============================
--
-- Turbines are chosen by FN_RAND over the seed, one per site, among turbines
-- with no seeded failure (so no component failure can explain the loss). The
-- step records itself in GEN_SEEDED_PATTERN and does nothing if that row
-- already exists; SP_GENERATE_ALARMS clears the register on every full
-- regenerate, so a fresh dataset gets the pattern exactly once.
--
-- Nothing downstream of the generator reads ACTIVE_POWER or YAW_ERROR except
-- the energy metrics (checked 2026-09-26: ML features and the alarm engine use
-- CMS and temperature tags), so this moves only what it is meant to move.
-- =============================================================================

use role WOA_ADMIN;
use database <% database %>;
use warehouse WOA_BUILD_WH;

create or replace procedure GEN.SP_GENERATE_UNDERPERFORMANCE(
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
    n_existing integer;
    n_power    integer;
    n_yaw      integer;
begin
    select count(*) into :n_existing from GEN.GEN_SEEDED_PATTERN where pattern_type = 'UNDERPERFORMANCE';
    if (n_existing > 0) then
        return 'underperformance already seeded (' || n_existing || ' turbines); nothing changed';
    end if;

    create or replace temporary table GEN.GEN_TMP_YAW as
    with candidates as (
        select t.turbine_id, t.site_code,
               row_number() over (partition by t.site_code
                                  order by GEN.FN_RAND(t.turbine_id, :seed || 'gs5')) as rn_in_site
        from RAW.DIM_TURBINE t
        where not exists (select 1 from GEN.GEN_FAILURE_EVENT f where f.turbine_id = t.turbine_id)
    ),
    one_per_site as (
        select turbine_id, site_code,
               row_number() over (order by GEN.FN_RAND(site_code, :seed || 'gs5site')) as k
        from candidates where rn_in_site = 1
    )
    select turbine_id, site_code,
           decode(k, 1, 14.0, 2, 11.0, 9.0)                          as yaw_offset_deg,
           pow(cos(radians(decode(k, 1, 14.0, 2, 11.0, 9.0))), 3)    as power_factor,
           dateadd(day, 75, :window_start)                          as start_ts
    from one_per_site
    where k <= 3;

    update RAW.FCT_SIGNAL_10MIN f
       set value_avg = f.value_avg * y.power_factor,
           value_min = f.value_min * y.power_factor,
           value_max = f.value_max * y.power_factor,
           value_std = f.value_std * y.power_factor
      from GEN.GEN_TMP_YAW y
      join RAW.DIM_SIGNAL ds on ds.turbine_id = y.turbine_id and ds.signal_name = 'ACTIVE_POWER'
     where f.signal_id = ds.signal_id
       and f.ts >= y.start_ts
       and f.operating_state in ('RUNNING', 'CURTAILED');
    n_power := sqlrowcount;

    update RAW.FCT_SIGNAL_10MIN f
       set value_avg = f.value_avg + y.yaw_offset_deg,
           value_min = f.value_min + y.yaw_offset_deg,
           value_max = f.value_max + y.yaw_offset_deg
      from GEN.GEN_TMP_YAW y
      join RAW.DIM_SIGNAL ds on ds.turbine_id = y.turbine_id and ds.signal_name = 'YAW_ERROR'
     where f.signal_id = ds.signal_id
       and f.ts >= y.start_ts
       and f.operating_state in ('RUNNING', 'CURTAILED');
    n_yaw := sqlrowcount;

    insert into GEN.GEN_SEEDED_PATTERN (pattern_id, pattern_type, site_code, turbine_id, alarm_code,
                                        window_start, window_end, alarm_count, notes)
    select 'SP-UNDERPERF-0' || row_number() over (order by yaw_offset_deg desc),
           'UNDERPERFORMANCE', site_code, turbine_id, null, start_ts, :window_end, 0,
           'Yaw offset ' || yaw_offset_deg || ' deg from ' || to_varchar(start_ts, 'YYYY-MM-DD')
           || '; power x cos^3 = ' || to_varchar(round(power_factor, 4))
           || '. NO alarm, availability untouched. GS-5: must be caught by MET_TURBINE_OEE performance alone.'
    from GEN.GEN_TMP_YAW;

    return 'underperformance seeded on 3 turbines: ' || n_power || ' power rows, ' || n_yaw || ' yaw rows';
end;
$$;
