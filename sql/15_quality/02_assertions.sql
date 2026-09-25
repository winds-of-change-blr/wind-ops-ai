-- =============================================================================
-- 15_quality / 02 — the assertions                             STAGE: WOA_ADMIN
-- =============================================================================
-- Implements : the G1 test suite
-- Proves     : T-1, T-7, T-8, T-9, T-11, T-12, T-13, T-62, T-64..T-67
-- Authority  : docs/07-quality/testing-and-validation.md, data-sources §6
-- Parameter  : <% database %>
--
-- Each assertion computes a MEASURED VALUE and compares it to a THRESHOLD. Both
-- are stored, because "T-8 passed" is worth much less than "T-8 passed: worst
-- lead-in ratio 1.66 against a required 1.15". The first tells you nothing when
-- it later fails; the second tells you how much margin you had.
--
-- The negative halves matter as much as the positive ones. T-65 asserts that
-- single trips are NOT labelled chattering and T-67 that a busy site does NOT
-- make the fleet look flooded — those are the obvious implementation mistakes,
-- and an assertion suite that only checks the happy direction will not catch them.
--
-- THE SEEDED-PATTERN ASSERTIONS MATCH ON ALARM_ID PREFIX, not on (turbine, code,
-- time window). They were written the loose way first and it produced a FLAKY
-- TEST: DQ-SEEDED-CASCADE passed at "16 codes within 11 minutes" and later failed
-- at 40 minutes on identical generator code, because the ordinary nuisance stream
-- had put unrelated alarms on the same turbine inside the window. A test that
-- silently measures the background instead of the thing it planted is worse than
-- no test — it passes until it doesn't, for reasons unrelated to the change in
-- front of you. The generator owns these prefixes (AL-DIP-, AL-CAS-, AL-CHT-),
-- so they are a contract rather than a coincidence.
--
-- T-67 is deliberately the exception: it compares RATES and so must count every
-- alarm in the window, background included. That is the measurement.
-- =============================================================================

use role WOA_ADMIN;
use database <% database %>;
use warehouse WOA_BUILD_WH;

create or replace procedure OPS.SP_RUN_DATA_QUALITY()
returns table (
    test_id        varchar,
    assertion_id   varchar,
    passed         boolean,
    -- FLOAT, not bare NUMBER: snow CLI 3.27 fails to parse an unscaled NUMBER
    -- column out of a procedure result set ("invalid literal for int() with
    -- base 10: '0.000000'"), which makes the suite unreadable from the CLI.
    measured_value  float,
    threshold_value float,
    detail         varchar
)
language sql
execute as caller
as
$$
declare
    run_id  varchar;
    res     resultset;
begin
    run_id := 'DQ-' || to_varchar(current_timestamp(), 'YYYYMMDDHH24MISS');

    -- =======================================================================
    -- T-1a — referential integrity. Every fact FK resolves to a dimension.
    -- =======================================================================
    insert into OPS.DQ_RESULT (run_id, assertion_id, test_id, run_at, passed, measured_value, threshold_value, detail)
    with orphans as (
        select 'FCT_SIGNAL_10MIN.signal_id' as rel, count(*) as n
        from RAW.FCT_SIGNAL_10MIN f
        where not exists (select 1 from RAW.DIM_SIGNAL d where d.signal_id = f.signal_id)
        union all
        select 'FCT_SIGNAL_10MIN.turbine_id', count(*)
        from RAW.FCT_SIGNAL_10MIN f
        where not exists (select 1 from RAW.DIM_TURBINE d where d.turbine_id = f.turbine_id)
        union all
        select 'FCT_CMS_FEATURE.component_id', count(*)
        from RAW.FCT_CMS_FEATURE f
        where not exists (select 1 from RAW.DIM_COMPONENT d where d.component_id = f.component_id)
        union all
        select 'FCT_ALARM_NORMALISED.alarm_code', count(*)
        from RAW.FCT_ALARM_NORMALISED f
        where not exists (select 1 from RAW.DIM_ALARM_CODE d where d.alarm_code = f.alarm_code)
        union all
        select 'FCT_ALARM_NORMALISED.turbine_id', count(*)
        from RAW.FCT_ALARM_NORMALISED f
        where not exists (select 1 from RAW.DIM_TURBINE d where d.turbine_id = f.turbine_id)
        union all
        select 'FCT_WORK_ORDER.component_id', count(*)
        from RAW.FCT_WORK_ORDER f
        where not exists (select 1 from RAW.DIM_COMPONENT d where d.component_id = f.component_id)
        union all
        select 'FCT_WORK_ORDER.failure_code', count(*)
        from RAW.FCT_WORK_ORDER f
        where f.failure_code is not null
          and not exists (select 1 from RAW.DIM_FAILURE_CODE d where d.failure_code = f.failure_code)
        union all
        select 'FCT_PART_MOVEMENT.part_number', count(*)
        from RAW.FCT_PART_MOVEMENT f
        where not exists (select 1 from RAW.DIM_PART d where d.part_number = f.part_number)
        union all
        select 'FCT_PART_MOVEMENT.work_order_id', count(*)
        from RAW.FCT_PART_MOVEMENT f
        where f.work_order_id is not null
          and not exists (select 1 from RAW.FCT_WORK_ORDER w where w.work_order_id = f.work_order_id)
        union all
        select 'FCT_TURBINE_STATE.exclusion_class_code', count(*)
        from RAW.FCT_TURBINE_STATE f
        where f.exclusion_class_code is not null
          and not exists (select 1 from RAW.DIM_EXCLUSION_CLASS d where d.exclusion_class_code = f.exclusion_class_code)
    )
    select
        :run_id, 'DQ-RI-FACTS', 'T-1', current_timestamp()::timestamp_ntz,
        sum(n) = 0, sum(n), 0,
        case when sum(n) = 0 then 'all foreign keys resolve'
             else 'orphans: ' || listagg(rel || '=' || n, ', ') within group (order by rel) end
    from orphans
    where n > 0 or true;

    -- =======================================================================
    -- T-1b — every signal in the catalogue actually has data.
    -- The reference solution shipped 51 of 54 sensors empty.
    -- =======================================================================
    insert into OPS.DQ_RESULT (run_id, assertion_id, test_id, run_at, passed, measured_value, threshold_value, detail)
    select
        :run_id, 'DQ-ROWCOUNT', 'T-1', current_timestamp()::timestamp_ntz,
        count_if(n_rows = 0) = 0,
        count_if(n_rows = 0),
        0,
        'signals with no data: ' || count_if(n_rows = 0) || ' of ' || count(*)
    from (
        select d.signal_id, count(f.signal_id) as n_rows
        from RAW.DIM_SIGNAL d
        left join RAW.FCT_SIGNAL_10MIN f on f.signal_id = d.signal_id
        group by d.signal_id
    );

    -- =======================================================================
    -- T-7a — every seeded failure has a corrective work order.
    -- =======================================================================
    insert into OPS.DQ_RESULT (run_id, assertion_id, test_id, run_at, passed, measured_value, threshold_value, detail)
    select
        :run_id, 'DQ-WO-PER-FAIL', 'T-7', current_timestamp()::timestamp_ntz,
        count_if(w.work_order_id is null) = 0,
        count_if(w.work_order_id is null),
        0,
        count_if(w.work_order_id is null) || ' of ' || count(*) || ' seeded failures have no corrective work order'
    from GEN.GEN_FAILURE_EVENT f
    left join RAW.FCT_WORK_ORDER w
        on  w.component_id     = f.component_id
        and w.work_order_type  = 'CORRECTIVE'
        and w.failure_code     = f.failure_code;

    -- =======================================================================
    -- T-7b — the failure mix is drivetrain-weighted.
    -- =======================================================================
    insert into OPS.DQ_RESULT (run_id, assertion_id, test_id, run_at, passed, measured_value, threshold_value, detail)
    select
        :run_id, 'DQ-DRIVETRAIN', 'T-7', current_timestamp()::timestamp_ntz,
        ratio >= 0.50, ratio, 0.50,
        'drivetrain share of failures: ' || round(100 * ratio, 1) || '%'
    from (
        select coalesce(sum(case when cc.is_drivetrain then 1 else 0 end) / nullif(count(*), 0), 0) as ratio
        from GEN.GEN_FAILURE_EVENT f
        join RAW.DIM_COMPONENT_CLASS cc on cc.component_class_code = f.component_class_code
    );

    -- =======================================================================
    -- T-8 (GATING) — degradation trends before EVERY seeded failure.
    --
    -- Compares the driving feature's mean over the 14 days before failure with
    -- the same feature 45..105 days before, AT MATCHED LOAD BANDS. The band
    -- restriction is the whole point: without it a component that simply ran
    -- harder in the lead-in window would pass, which is the classic false
    -- positive in condition monitoring.
    --
    -- Classes without a CMS point use their SCADA degradation channel instead,
    -- because only GBX, GEN and MSB are IS_CMS_MONITORED and a failure with no
    -- observable at all could never be predicted honestly.
    -- =======================================================================
    insert into OPS.DQ_RESULT (run_id, assertion_id, test_id, run_at, passed, measured_value, threshold_value, detail)
    with cms_driver as (
        select
            f.failure_event_id,
            avg(case when c.ts >= dateadd(day, -14, f.failure_ts) and c.ts < f.failure_ts then c.feature_value end) as lead_in,
            avg(case when c.ts >= dateadd(day, -105, f.failure_ts) and c.ts < dateadd(day, -45, f.failure_ts) then c.feature_value end) as baseline
        from GEN.GEN_FAILURE_EVENT f
        join RAW.FCT_CMS_FEATURE c
            on  c.component_id    = f.component_id
            and c.feature_name    = 'BAND_ENERGY'
            and c.load_band in ('HIGH', 'FULL')
            and c.monitored_point = case f.component_class_code
                                        when 'GBX' then 'GBX-HSS'
                                        when 'GEN' then 'GEN-DE'
                                        when 'MSB' then 'MSB-RAD'
                                    end
        group by f.failure_event_id
    ),
    scada_driver as (
        select
            f.failure_event_id,
            avg(case when s.ts >= dateadd(day, -14, f.failure_ts) and s.ts < f.failure_ts then s.value_avg end) as lead_in,
            avg(case when s.ts >= dateadd(day, -105, f.failure_ts) and s.ts < dateadd(day, -45, f.failure_ts) then s.value_avg end) as baseline
        from GEN.GEN_FAILURE_EVENT f
        join RAW.DIM_SIGNAL ds
            on  ds.component_id = f.component_id
            and (ds.signal_type in ('TEMPERATURE', 'CMS') or (ds.signal_type = 'OPERATIONAL' and ds.unit = 'A'))
        join RAW.FCT_SIGNAL_10MIN s
            on  s.signal_id       = ds.signal_id
            and s.operating_state = 'RUNNING'
        where not exists (select 1 from cms_driver c where c.failure_event_id = f.failure_event_id)
        group by f.failure_event_id
    ),
    combined as (
        select failure_event_id, lead_in, baseline from cms_driver
        union all
        select failure_event_id, lead_in, baseline from scada_driver
    ),
    scored as (
        select
            failure_event_id,
            lead_in / nullif(baseline, 0) as ratio
        from combined
        where baseline is not null and lead_in is not null
    )
    select
        :run_id, 'DQ-DEGRADATION', 'T-8', current_timestamp()::timestamp_ntz,
        -- every failure must trend, and every failure must be measurable
        min(ratio) > 1.05
            and (select count(*) from scored) = (select count(*) from GEN.GEN_FAILURE_EVENT),
        round(min(ratio), 4), 1.05,
        'failures measured ' || (select count(*) from scored) || ' of '
            || (select count(*) from GEN.GEN_FAILURE_EVENT)
            || '; worst lead-in ratio ' || round(min(ratio), 3)
            || ', median ' || round(median(ratio), 3)
    from scored;

    -- =======================================================================
    -- T-9 — failure tracks accumulated damage, NOT identity.
    -- Asserts a positive AND a negative, because the reference solution's defect
    -- was health as a function of primary key.
    -- =======================================================================
    insert into OPS.DQ_RESULT (run_id, assertion_id, test_id, run_at, passed, measured_value, threshold_value, detail)
    with peak as (
        select
            d.component_id,
            max(d.damage_level / nullif(d.failure_threshold, 0)) as peak_ratio,
            max(case when f.failure_event_id is not null then 1 else 0 end) as failed,
            try_to_number(regexp_substr(d.component_id, 'T([0-9]+)', 1, 1, 'e', 1)) as turbine_no
        from GEN.GEN_DAMAGE_STATE d
        left join GEN.GEN_FAILURE_EVENT f on f.component_id = d.component_id
        group by d.component_id
    )
    select
        :run_id, 'DQ-DAMAGE-CORR', 'T-9', current_timestamp()::timestamp_ntz,
        corr(failed, peak_ratio) >= 0.30 and abs(corr(failed, turbine_no)) <= 0.15,
        round(corr(failed, peak_ratio), 4), 0.30,
        'corr(failed, peak damage)=' || round(corr(failed, peak_ratio), 4)
            || ' must be >= 0.30; corr(failed, turbine number)='
            || round(corr(failed, turbine_no), 4) || ' must be within +/-0.15'
    from peak;

    -- =======================================================================
    -- T-11 (GATING) — data reaches the generation date, across every fact.
    -- =======================================================================
    insert into OPS.DQ_RESULT (run_id, assertion_id, test_id, run_at, passed, measured_value, threshold_value, detail)
    -- Thresholds are GRAIN-AWARE, and that is a correction rather than a
    -- concession. GEN_DAMAGE_STATE is generator state at DAY grain, so its newest
    -- timestamp is midnight of the current day and it is structurally >24h stale
    -- from midday onward — a bar it can never meet no matter how fresh the run.
    -- Holding a daily table to a sub-daily bar measures the clock, not the
    -- pipeline. The FACT SURFACES an operator actually looks at keep the 24h bar
    -- T-11 is about: "a last-24-hours panel returning zero rows".
    with freshness as (
        select 'FCT_SIGNAL_10MIN' as t, max(ts) as max_ts, 24 as allowance_h from RAW.FCT_SIGNAL_10MIN
        union all select 'FCT_CMS_FEATURE',      max(ts),          24 from RAW.FCT_CMS_FEATURE
        union all select 'FCT_ALARM_NORMALISED', max(alarm_start), 24 from RAW.FCT_ALARM_NORMALISED
        union all select 'FCT_TURBINE_STATE',    max(state_start), 48 from RAW.FCT_TURBINE_STATE
        union all select 'GEN_DAMAGE_STATE',     max(ts),          48 from GEN.GEN_DAMAGE_STATE
    ),
    scored as (
        select
            t,
            datediff(hour, max_ts, current_timestamp()) as staleness_h,
            allowance_h,
            datediff(hour, max_ts, current_timestamp()) - allowance_h as overrun_h
        from freshness
    )
    select
        :run_id, 'DQ-FRESHNESS', 'T-11', current_timestamp()::timestamp_ntz,
        max(overrun_h) <= 0, round(max(staleness_h), 2), max(allowance_h),
        'worst overrun: ' || (select t from scored order by overrun_h desc limit 1)
            || ' at ' || (select round(staleness_h, 1) from scored order by overrun_h desc limit 1)
            || 'h against a ' || (select allowance_h from scored order by overrun_h desc limit 1)
            || 'h allowance'
    from scored;

    -- =======================================================================
    -- T-11b — and nothing is dated in the future.
    -- =======================================================================
    insert into OPS.DQ_RESULT (run_id, assertion_id, test_id, run_at, passed, measured_value, threshold_value, detail)
    select
        :run_id, 'DQ-NO-FUTURE', 'T-11', current_timestamp()::timestamp_ntz,
        n_future = 0, n_future, 0,
        n_future || ' fact rows are dated after the generation instant'
    from (
        select
            (select count(*) from RAW.FCT_SIGNAL_10MIN      where ts > current_timestamp())
          + (select count(*) from RAW.FCT_CMS_FEATURE        where ts > current_timestamp())
          + (select count(*) from RAW.FCT_ALARM_NORMALISED   where alarm_start > current_timestamp())
            as n_future
    );

    -- =======================================================================
    -- T-12 — every downstream threshold is crossed by real rows.
    -- Checks the CMS warning/alarm levels the alarm generator uses, and the
    -- declared normal range of every temperature tag.
    -- =======================================================================
    insert into OPS.DQ_RESULT (run_id, assertion_id, test_id, run_at, passed, measured_value, threshold_value, detail)
    with cms_cross as (
        select
            th.monitored_point,
            count_if(c.feature_value > th.warning_level) as n_warn,
            count_if(c.feature_value > th.alarm_level)   as n_alarm
        from GEN.GEN_CMS_THRESHOLD th
        join RAW.FCT_CMS_FEATURE c
            on c.monitored_point = th.monitored_point and c.feature_name = th.feature_name
        group by th.monitored_point
    ),
    temp_cross as (
        select
            ds.signal_name,
            count_if(f.value_avg > ds.normal_range_high) as n_over
        from RAW.DIM_SIGNAL ds
        join RAW.FCT_SIGNAL_10MIN f on f.signal_id = ds.signal_id
        where ds.signal_type = 'TEMPERATURE'
        group by ds.signal_name
    )
    select
        :run_id, 'DQ-THRESHOLDS', 'T-12', current_timestamp()::timestamp_ntz,
        n_uncrossed = 0, n_uncrossed, 0,
        n_uncrossed || ' thresholds are never crossed by any generated row'
    from (
        select
            (select count(*) from cms_cross  where n_warn = 0 or n_alarm = 0)
          + (select count(*) from temp_cross where n_over = 0)
            as n_uncrossed
    );

    -- =======================================================================
    -- T-13 — every row carries the synthetic marker.
    -- =======================================================================
    insert into OPS.DQ_RESULT (run_id, assertion_id, test_id, run_at, passed, measured_value, threshold_value, detail)
    with unmarked as (
        select 'FCT_SIGNAL_10MIN' as t, count(*) as n from RAW.FCT_SIGNAL_10MIN      where is_synthetic is distinct from true
        union all select 'FCT_CMS_FEATURE',      count(*) from RAW.FCT_CMS_FEATURE       where is_synthetic is distinct from true
        union all select 'FCT_ALARM_NORMALISED', count(*) from RAW.FCT_ALARM_NORMALISED  where is_synthetic is distinct from true
        union all select 'FCT_WORK_ORDER',       count(*) from RAW.FCT_WORK_ORDER        where is_synthetic is distinct from true
        union all select 'FCT_TURBINE_STATE',    count(*) from RAW.FCT_TURBINE_STATE     where is_synthetic is distinct from true
        union all select 'FCT_PART_MOVEMENT',    count(*) from RAW.FCT_PART_MOVEMENT     where is_synthetic is distinct from true
        union all select 'DIM_TURBINE',          count(*) from RAW.DIM_TURBINE           where is_synthetic is distinct from true
        union all select 'DIM_COMPONENT',        count(*) from RAW.DIM_COMPONENT         where is_synthetic is distinct from true
        union all select 'DIM_SIGNAL',           count(*) from RAW.DIM_SIGNAL            where is_synthetic is distinct from true
    )
    select
        :run_id, 'DQ-SYNTHETIC', 'T-13', current_timestamp()::timestamp_ntz,
        sum(n) = 0, sum(n), 0,
        case when sum(n) = 0 then 'every row is marked synthetic'
             else 'unmarked rows in ' || listagg(t, ', ') within group (order by t) end
    from unmarked;

    -- =======================================================================
    -- T-62 — all four sources conform to the one normalised schema.
    -- =======================================================================
    insert into OPS.DQ_RESULT (run_id, assertion_id, test_id, run_at, passed, measured_value, threshold_value, detail)
    select
        :run_id, 'DQ-ALARM-SCHEMA', 'T-62', current_timestamp()::timestamp_ntz,
        n_sources = 4 and n_bad = 0, n_sources, 4,
        'sources present: ' || src_list || '; rows violating the common contract: ' || n_bad
    from (
        select
            count(distinct alarm_source) as n_sources,
            listagg(distinct alarm_source, ',') as src_list,
            count_if(alarm_id is null or turbine_id is null or alarm_code is null
                     or alarm_start is null or site_code is null) as n_bad
        from RAW.FCT_ALARM_NORMALISED
    );

    -- =======================================================================
    -- T-64a — the seeded grid dip: present, site-scoped, tightly timed.
    -- One incident, not one per turbine.
    -- =======================================================================
    insert into OPS.DQ_RESULT (run_id, assertion_id, test_id, run_at, passed, measured_value, threshold_value, detail)
    select
        :run_id, 'DQ-SEEDED-DIP', 'T-64', current_timestamp()::timestamp_ntz,
        n_turbines = expected_turbines and span_seconds <= 120 and n_other_sites = 0,
        n_turbines, expected_turbines,
        n_turbines || ' of ' || expected_turbines || ' turbines at the site tripped within '
            || span_seconds || 's; turbines at other sites involved: ' || n_other_sites
    from (
        select
            count(distinct case when a.site_code = p.site_code then a.turbine_id end) as n_turbines,
            count(distinct case when a.site_code <> p.site_code then a.turbine_id end) as n_other_sites,
            datediff(second, min(a.alarm_start), max(a.alarm_start))                   as span_seconds,
            max(p.alarm_count)                                                        as expected_turbines
        from GEN.GEN_SEEDED_PATTERN p
        join RAW.FCT_ALARM_NORMALISED a
            on  a.alarm_id like 'AL-DIP-%'
            and a.alarm_start between p.window_start and p.window_end
        where p.pattern_type = 'GRID_DIP'
    );

    -- =======================================================================
    -- T-64b — the seeded code cascade: many distinct codes, one turbine, minutes.
    -- =======================================================================
    insert into OPS.DQ_RESULT (run_id, assertion_id, test_id, run_at, passed, measured_value, threshold_value, detail)
    select
        :run_id, 'DQ-SEEDED-CASCADE', 'T-64', current_timestamp()::timestamp_ntz,
        n_codes >= 10 and span_minutes <= 15 and n_turbines = 1,
        n_codes, 10,
        n_codes || ' distinct codes on ' || n_turbines || ' turbine within ' || span_minutes || ' minutes'
    from (
        select
            count(distinct a.alarm_code)                            as n_codes,
            count(distinct a.turbine_id)                            as n_turbines,
            datediff(minute, min(a.alarm_start), max(a.alarm_start)) as span_minutes
        from GEN.GEN_SEEDED_PATTERN p
        join RAW.FCT_ALARM_NORMALISED a
            on  a.alarm_id like 'AL-CAS-%'
            and a.alarm_start between p.window_start and p.window_end
        where p.pattern_type = 'CODE_CASCADE'
    );

    -- =======================================================================
    -- T-65 — chattering present, AND single trips exist to contrast against.
    -- The negative half is what stops a detector labelling everything.
    -- =======================================================================
    insert into OPS.DQ_RESULT (run_id, assertion_id, test_id, run_at, passed, measured_value, threshold_value, detail)
    select
        :run_id, 'DQ-SEEDED-CHATTER', 'T-65', current_timestamp()::timestamp_ntz,
        chatter_count >= 20 and all_auto_reset and single_trip_population > 0,
        chatter_count, 20,
        chatter_count || ' auto-reset trips on the seeded signature (all auto-reset: ' || all_auto_reset
            || '); contrast population of one-off trips: ' || single_trip_population
    from (
        select
            (select count(*) from GEN.GEN_SEEDED_PATTERN p
             join RAW.FCT_ALARM_NORMALISED a
               on a.alarm_id like 'AL-CHT-%'
              and a.alarm_start between p.window_start and p.window_end
             where p.pattern_type = 'CHATTERING') as chatter_count,
            (select count_if(not a.is_auto_reset) = 0 from GEN.GEN_SEEDED_PATTERN p
             join RAW.FCT_ALARM_NORMALISED a
               on a.alarm_id like 'AL-CHT-%'
              and a.alarm_start between p.window_start and p.window_end
             where p.pattern_type = 'CHATTERING') as all_auto_reset,
            -- turbine/code/day combinations with exactly one alarm: these must
            -- never be labelled chattering
            (select count(*) from (
                select turbine_id, alarm_code, alarm_start::date as d, count(*) as n
                from RAW.FCT_ALARM_NORMALISED
                group by 1, 2, 3
                having count(*) = 1
             )) as single_trip_population
    );

    -- =======================================================================
    -- T-66 — the standing alarm: open, unacknowledged, beyond threshold.
    -- =======================================================================
    insert into OPS.DQ_RESULT (run_id, assertion_id, test_id, run_at, passed, measured_value, threshold_value, detail)
    select
        :run_id, 'DQ-SEEDED-STAND', 'T-66', current_timestamp()::timestamp_ntz,
        n_standing >= 1, n_standing, 1,
        n_standing || ' alarm(s) open beyond 7 days with no acknowledgement, oldest '
            || coalesce(max_age_days::varchar, 'n/a') || ' days'
    from (
        select
            count(*)                                              as n_standing,
            max(datediff(day, a.alarm_start, current_timestamp())) as max_age_days
        from GEN.GEN_SEEDED_PATTERN p
        join RAW.FCT_ALARM_NORMALISED a
            on  a.turbine_id = p.turbine_id
            and a.alarm_code = p.alarm_code
        where p.pattern_type = 'STANDING'
          and a.alarm_end is null
          and a.acknowledged_at is null
          and datediff(day, a.alarm_start, current_timestamp()) >= 7
    );

    -- =======================================================================
    -- T-67 — the flood is concentrated at ONE site, not fleet-wide.
    -- The negative half is the important one: a rate threshold that fires
    -- fleet-wide whenever a single site is busy makes the label useless.
    -- =======================================================================
    insert into OPS.DQ_RESULT (run_id, assertion_id, test_id, run_at, passed, measured_value, threshold_value, detail)
    select
        :run_id, 'DQ-SEEDED-FLOOD', 'T-67', current_timestamp()::timestamp_ntz,
        flood_site_rate >= 4 * other_site_rate, round(flood_site_rate / nullif(other_site_rate, 0), 2), 4,
        'seeded site ran at ' || round(flood_site_rate, 1) || ' alarms/hour against '
            || round(other_site_rate, 1) || ' elsewhere in the same window'
    from (
        select
            count_if(a.site_code =  p.site_code) / 4.0 as flood_site_rate,
            count_if(a.site_code <> p.site_code) / 4.0 / 5.0 as other_site_rate
        from GEN.GEN_SEEDED_PATTERN p
        join RAW.FCT_ALARM_NORMALISED a
            on a.alarm_start between p.window_start and p.window_end
        where p.pattern_type = 'FLOOD'
    );

    -- ---- hand back this run's verdicts -----------------------------------
    res := (
        select
            r.test_id::varchar, r.assertion_id::varchar, r.passed,
            r.measured_value::float, r.threshold_value::float, r.detail::varchar
        from OPS.DQ_RESULT r
        where r.run_id = :run_id
        order by r.test_id, r.assertion_id
    );
    return table(res);
end;
$$;

-- ---------------------------------------------------------------------------
-- SP_ASSERT_QUALITY_GATE — raise if the latest run has any failure.
--
-- `just verify` needs a non-zero exit code, and a SELECT that merely reports
-- failures gives an exit code of zero. A deploy gate that reports a problem and
-- then succeeds is the same defect as a placeholder recipe that silently passes.
-- ---------------------------------------------------------------------------
create or replace procedure OPS.SP_ASSERT_QUALITY_GATE()
returns varchar
language sql
execute as caller
as
$$
declare
    n_failed  integer;
    n_total   integer;
    failed_ids varchar;
    gate_failed exception (-20001, 'Data quality gate failed');
begin
    select count(*), count_if(not passed),
           coalesce(listagg(case when not passed then test_id || '/' || assertion_id end, ', '), '')
      into :n_total, :n_failed, :failed_ids
    from OPS.DQ_RESULT
    where run_id = (select max(run_id) from OPS.DQ_RESULT);

    if (n_total = 0) then
        raise gate_failed;
    end if;

    if (n_failed > 0) then
        raise gate_failed;
    end if;

    return 'data quality gate passed: ' || n_total || ' assertions, 0 failures';
end;
$$;
