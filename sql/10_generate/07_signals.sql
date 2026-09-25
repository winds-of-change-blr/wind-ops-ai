-- =============================================================================
-- 10_generate / 07 — SCADA signal response                     STAGE: WOA_ADMIN
-- =============================================================================
-- Implements : US-2 (SCADA signals), US-6 (every threshold reachable)
-- Proves     : T-11 (data reaches the generation date), T-12 (thresholds crossed),
--              and the row-count half of T-1
-- Authority  : docs/04-data/data-sources-and-synthetic-data.md §2 stage 4, §4
-- Parameter  : <% database %>
--
-- Stage 4: signal = f(damage) + g(operating point) + noise.
--
-- EVERY SIGNAL IN DIM_SIGNAL GETS DATA. This procedure is driven BY the catalogue
-- rather than by a hand-written list, and that is deliberate. The first cut
-- modelled nine named signals, which left 27 of each turbine's 41 tags empty —
-- the reference solution's "51 of 54 sensors with no data" defect exactly
-- (reference-solution-analysis G-1), and the thing T-1's row-count assertion is
-- there to catch. A hand-written list also silently rots: adding a tag to
-- DIM_SIGNAL would create an orphan sensor with no error anywhere.
--
-- So signals are modelled GENERICALLY, from three columns the catalogue already
-- carries — SIGNAL_TYPE, NORMAL_RANGE_LOW and NORMAL_RANGE_HIGH. A signal's
-- value is positioned within its own declared envelope according to what the
-- turbine is doing. This is less bespoke than nine hand-tuned formulas, and it is
-- the reason T-12 ("every downstream threshold is crossed by real rows") can hold
-- for all 4,100 tags rather than for the handful somebody remembered.
--
-- g(operating point) is DELIBERATELY LARGE relative to f(damage). That is true of
-- real SCADA practice and is why the feature engine bands by RPM and load
-- (CMP-4): a raw temperature rise is swamped by the turbine simply working
-- harder. A generator that made degradation trivially visible in raw signals
-- would let a single-signal threshold beat the model, which T-10 forbids.
--
-- WHICH SIGNALS CARRY DAMAGE. Every TEMPERATURE and CMS tag, plus current-measured
-- OPERATIONAL tags (a worn drive draws more current — physically true, and it is
-- the only observable PIT and YAW have). That guarantees every component class
-- has at least one degradation channel, so T-8 is assertable for every seeded
-- failure and not only for the CMS-monitored classes.
--
-- VOLUME. FCT_SIGNAL_10MIN is LONG (one row per signal, Q-46), while profile §11's
-- ~5.26M rows/year assumes one row per turbine-interval — a WIDE table. The two
-- are not comparable: 4,100 tags at 10-minute grain over 183 days is ~108M rows.
-- INTERVAL_MIN therefore exists as a parameter, and the deviation from the
-- documented figure is recorded in STATE.md §7 with its measured cost.
-- =============================================================================

use role WOA_ADMIN;
use database <% database %>;
use warehouse WOA_BUILD_WH;

create or replace procedure GEN.SP_GENERATE_SIGNALS(
    window_start timestamp_ntz,
    window_end   timestamp_ntz,
    seed         varchar,
    interval_min integer
)
returns varchar
language sql
execute as caller
as
$$
declare
    rows_written integer;
begin
    delete from RAW.FCT_SIGNAL_10MIN
    where ts between :window_start and :window_end;

    insert into RAW.FCT_SIGNAL_10MIN (
        turbine_id, signal_id, ts, value_avg, value_min, value_max, value_std,
        operating_state
    )
    with ticks as (
        select dateadd(minute, :interval_min * (row_number() over (order by seq4()) - 1), :window_start) as ts
        from table(generator(rowcount => 120000))
        qualify ts < :window_end
    ),
    -- ---- the operating point, once per turbine-interval ------------------
    op as (
        select
            t.turbine_id,
            k.ts,
            s.region,
            p.rated_power_mw * 1000 as rated_kw,
            p.cut_in_speed_ms,
            p.rated_speed_ms,
            p.cut_out_speed_ms,
            case when t.platform_id = 'VW-2.1' then 17.0 else 13.5 end as rated_rotor_rpm,
            GEN.FN_WIND_SPEED(t.turbine_id, k.ts, s.mean_wind_speed, :seed) as wind_ms,
            22.0
              + 7.0 * sin(2 * pi() * (dayofyear(k.ts) - 120) / 365.0)
              + 5.5 * sin(2 * pi() * (hour(k.ts) - 9) / 24.0)
              + case when s.region in ('West', 'North') then 3.5 else 0.0 end
              + 2.0 * (GEN.FN_RAND(t.turbine_id || to_varchar(k.ts, 'YYYYMMDDHH24MI'), :seed || 'amb') - 0.5)
                as ambient_c
        from RAW.DIM_TURBINE t
        join RAW.DIM_SITE s     on s.site_code   = t.site_code
        join RAW.DIM_PLATFORM p on p.platform_id = t.platform_id
        cross join ticks k
    ),
    stated as (
        select
            o.*,
            GEN.FN_EXPECTED_POWER(o.wind_ms, o.rated_kw, o.cut_in_speed_ms, o.rated_speed_ms, o.cut_out_speed_ms) as ideal_kw,
            case
                when o.wind_ms <  o.cut_in_speed_ms  then 0.0
                when o.wind_ms >= o.cut_out_speed_ms then 0.0
                when o.wind_ms >= o.rated_speed_ms   then o.rated_rotor_rpm
                else o.rated_rotor_rpm * (o.wind_ms - o.cut_in_speed_ms) / (o.rated_speed_ms - o.cut_in_speed_ms)
            end as rotor_rpm,
            dt.failure_ts is not null as is_down
        from op o
        -- A correlated EXISTS against GEN_FAILURE_EVENT with a BETWEEN on the
        -- outer timestamp is an unsupported subquery type in Snowflake, so
        -- downtime is a range JOIN. QUALIFY dedupes it, because a turbine can
        -- have two components down at the same time.
        left join (
            select turbine_id, failure_ts, coalesce(repair_ts, :window_end) as repair_ts
            from GEN.GEN_FAILURE_EVENT
        ) dt
            on  dt.turbine_id = o.turbine_id
            and o.ts >= dt.failure_ts
            and o.ts <  dt.repair_ts
        qualify row_number() over (partition by o.turbine_id, o.ts order by dt.failure_ts nulls last) = 1
    ),
    live as (
        select
            s.*,
            case
                when s.is_down                       then 'UNAVAILABLE'
                when s.wind_ms <  s.cut_in_speed_ms  then 'IDLE_LOW_WIND'
                when s.wind_ms >= s.cut_out_speed_ms then 'IDLE_HIGH_WIND'
                when GEN.FN_RAND(s.turbine_id || to_varchar(s.ts, 'YYYYMMDDHH24MI'), :seed || 'curt') < 0.015
                                                     then 'CURTAILED'
                else 'RUNNING'
            end as operating_state,
            -- load fraction actually delivered, which is what most tags follow
            case
                when s.is_down                       then 0.0
                when s.wind_ms <  s.cut_in_speed_ms  then 0.0
                when s.wind_ms >= s.cut_out_speed_ms then 0.0
                else s.ideal_kw / nullif(s.rated_kw, 0)
            end as load_frac
        from stated s
    ),
    -- ---- damage per component per day, for the tags that carry it --------
    dmg as (
        select
            component_id,
            ts::date                                   as day,
            damage_level / nullif(failure_threshold, 0) as damage_ratio
        from GEN.GEN_DAMAGE_STATE
    ),
    -- the generic signal model, one row per (tag, interval).
    -- This was written as JOIN LATERAL (SELECT ...) with no FROM clause, which
    -- Snowflake rejects as an unsupported subquery type. A CTE does the same job.
    emitted as (
        select
            l.turbine_id,
            ds.signal_id,
            l.ts,
            l.operating_state,
            (
            case
                -- ---- named tags whose physics we model explicitly ---------
                when ds.signal_name = 'WIND_SPEED'     then l.wind_ms
                when ds.signal_name = 'AMBIENT_TEMP'   then l.ambient_c
                when ds.signal_name = 'ACTIVE_POWER'   then l.ideal_kw * case when l.operating_state = 'CURTAILED' then 0.45 when l.operating_state = 'RUNNING' then 0.965 else 0.0 end
                when ds.signal_name = 'REACTIVE_POWER' then l.ideal_kw * 0.12 * (GEN.FN_RAND(ds.signal_id || to_varchar(l.ts, 'YYYYMMDDHH24MI'), :seed || 'q') - 0.4)
                when ds.signal_name = 'ROTOR_RPM'      then case when l.operating_state in ('RUNNING', 'CURTAILED') then l.rotor_rpm else 0.0 end
                when ds.signal_name = 'GEN_RPM'        then case when l.operating_state in ('RUNNING', 'CURTAILED') then l.rotor_rpm * 105.0 else 0.0 end
                when ds.signal_name = 'WIND_DIR'       then 360.0 * GEN.FN_RAND(l.turbine_id || to_varchar(l.ts, 'YYYYMMDDHH'), :seed || 'dir')
                when ds.signal_name = 'NACELLE_TEMP'   then l.ambient_c + 6.0 + 14.0 * l.load_frac

                -- ---- TEMPERATURE: ambient, plus a load rise, plus damage ---
                when ds.signal_type = 'TEMPERATURE' then
                    l.ambient_c
                    + (ds.normal_range_high - ds.normal_range_low) * 0.18
                    + (ds.normal_range_high - l.ambient_c) * 0.55 * l.load_frac
                    + (ds.normal_range_high - ds.normal_range_low) * 0.30 * pow(coalesce(d.damage_ratio, 0), 2.4)

                -- ---- CMS vibration: baseline, load, and damage -------------
                when ds.signal_type = 'CMS' then
                    ds.normal_range_low
                    + (ds.normal_range_high - ds.normal_range_low)
                      * (0.18 + 0.30 * l.load_frac + 0.55 * pow(coalesce(d.damage_ratio, 0), 2.6))

                -- ---- current-measured OPERATIONAL: wear shows as draw ------
                when ds.signal_type = 'OPERATIONAL' and ds.unit = 'A' then
                    ds.normal_range_low
                    + (ds.normal_range_high - ds.normal_range_low)
                      * (0.15 + 0.35 * l.load_frac + 0.45 * pow(coalesce(d.damage_ratio, 0), 2.6))

                -- ---- everything else: inside its envelope, load-following --
                when ds.signal_type = 'OPERATIONAL' then
                    ds.normal_range_low
                    + (ds.normal_range_high - ds.normal_range_low) * (0.35 + 0.45 * l.load_frac)
                when ds.signal_type = 'STRUCTURAL' then
                    ds.normal_range_low
                    + (ds.normal_range_high - ds.normal_range_low)
                      * (0.45 + 0.20 * l.load_frac + 0.10 * pow(coalesce(d.damage_ratio, 0), 2.0))
                when ds.signal_type = 'EVENT' then
                    ds.normal_range_low
                when ds.signal_type = 'ENVIRONMENTAL' then
                    ds.normal_range_low + (ds.normal_range_high - ds.normal_range_low) * 0.5
                else
                    ds.normal_range_low + (ds.normal_range_high - ds.normal_range_low) * 0.5
            end
            )
            -- measurement noise, deterministic per (tag, interval)
            * (1 + 0.035 * (GEN.FN_RAND(ds.signal_id || to_varchar(l.ts, 'YYYYMMDDHH24MI'), :seed || 'noise') - 0.5))
            as value_avg
        from live l
        join RAW.DIM_SIGNAL ds on ds.turbine_id = l.turbine_id
        left join dmg d on d.component_id = ds.component_id and d.day = l.ts::date
    )
    select
        e.turbine_id,
        e.signal_id,
        e.ts,
        round(e.value_avg, 4),
        round(e.value_avg - abs(e.value_avg) * 0.05 * GEN.FN_RAND(e.signal_id || to_varchar(e.ts, 'YYYYMMDDHH24MI'), :seed || 'lo'), 4),
        round(e.value_avg + abs(e.value_avg) * 0.05 * GEN.FN_RAND(e.signal_id || to_varchar(e.ts, 'YYYYMMDDHH24MI'), :seed || 'hi'), 4),
        round(abs(e.value_avg) * 0.02 * (0.5 + GEN.FN_RAND(e.signal_id || to_varchar(e.ts, 'YYYYMMDDHH24MI'), :seed || 'sd')), 4),
        e.operating_state
    from emitted e
    where e.value_avg is not null;

    rows_written := sqlrowcount;

    -- ---- seeded historian gaps -------------------------------------------
    -- Source 4 of the alarm stream is the platform's own data-quality checks,
    -- and those have to have something real to find. Twelve turbine-days lose
    -- their afternoon: a historian that stopped writing, which is the most
    -- common real gap and exactly what DQ-ST-001 describes.
    --
    -- Without this the DQ source had to infer "missing data" from row-count
    -- comparisons across the fleet, which fired on 3,069 of 3,100 turbine-days
    -- in testing because it compared each turbine against the fleet MAXIMUM. An
    -- alarm source that fires on everything is worse than no alarm source: it
    -- teaches the operator to ignore the queue.
    delete from RAW.FCT_SIGNAL_10MIN f
    using (
        select
            t.turbine_id,
            dateadd(
                day,
                floor(datediff(day, :window_start, :window_end) * GEN.FN_RAND(t.turbine_id, 'gapday')),
                :window_start::date
            )::date as gap_day
        from RAW.DIM_TURBINE t
        where GEN.FN_RAND(t.turbine_id, 'gap') < 0.12
    ) g
    where f.turbine_id = g.turbine_id
      and f.ts::date   = g.gap_day
      and hour(f.ts) between 13 and 20;

    return 'FCT_SIGNAL_10MIN: ' || rows_written || ' rows at ' || :interval_min
        || '-minute grain, less ' || sqlrowcount || ' rows removed as seeded historian gaps';
end;
$$;
