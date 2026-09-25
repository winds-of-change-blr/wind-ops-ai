-- =============================================================================
-- 10_generate / 06 — damage accumulation and failures          STAGE: WOA_ADMIN
-- =============================================================================
-- Implements : US-4 (failure timing driven by accumulated damage)
-- Proves     : T-8 (degradation trends before failure), T-9 (failure correlates
--              with damage, not with asset ID), T-7 (drivetrain-weighted mix)
-- Authority  : docs/04-data/data-sources-and-synthetic-data.md §2 stages 3 and 5
-- Parameter  : <% database %>
--
-- Stage 3 is the one that makes the dataset worth modelling. The causal chain is
-- conditions -> damage -> signals, and damage -> failure. Nothing here looks at
-- a component's identity to decide whether it fails: identity only seeds the
-- per-instance variation, through HASH, which is uncorrelated with ID ordering.
-- That is the whole content of T-9, and it is the reference solution's headline
-- defect (health as a function of primary key).
--
-- DAMAGE IS NORMALISED so that 1.0 means "at this instance's failure
-- threshold". The threshold itself varies per instance (0.88..1.16), because
-- identical components do not fail at identical wear.
--
-- Starting damage is the component's position in its CURRENT wear cycle, taken
-- as MOD(lifetime accumulation, 1.0). A 2016 turbine's gearbox is therefore not
-- absurdly at damage 15.0; it is somewhere in its third cycle. This models
-- periodic replacement without needing to generate a decade of history we would
-- then throw away.
--
-- WHY A BAD-BATCH POPULATION. The first cut gave every instance a similar wear
-- rate and T-8 failed on half the seeded failures. The reason is arithmetic, not
-- tuning: at a uniform rate a component accrues only ~0.2 of its threshold over
-- 183 days, so which components fail is decided almost entirely by where they
-- started, and any smooth feature of damage moves a few percent across the
-- comparison span. Making the curve accelerate did not help — it made damage run
-- away once started, and the failure count went to 171..289.
--
-- So the variance lives in the POPULATION instead. ACCEL_SHARE of instances are
-- a bad batch degrading 5-11x faster; they traverse a wide damage range inside
-- the window and produce most of the failures, with a trend a CMS feature can
-- genuinely show. The rest wear slowly and fail only if they entered the window
-- already near threshold. Both paths are real: infant mortality from a supplier
-- batch, and end-of-life wear-out. This is also why DIM_COMPONENT_GENEALOGY
-- matters — a bad batch is a serial-number story, not a position story.
--
-- ONE FAILURE PER COMPONENT PER WINDOW. Over 183 days with ~5% of components
-- failing, a second failure on the same position is vanishingly unlikely, and
-- allowing it would force a recursive CTE for damage reset. After repair the
-- instance restarts near zero (refurbished), which the damage curve reflects.
-- =============================================================================

use role WOA_ADMIN;
use database <% database %>;
use warehouse WOA_BUILD_WH;

-- ---------------------------------------------------------------------------
-- SP_GENERATE_DAMAGE — daily damage per component, and the failures it causes.
--
-- Writes GEN_DAMAGE_STATE (one row per component per day) and
-- GEN_FAILURE_EVENT (one row per crossing). DAMAGE_MULTIPLIER is the tuning
-- knob for failure count: data-sources §3 is explicit that when the count is
-- too low the lever is a HIGHER RATE over the same window, not a longer window,
-- because failures are what cost us statistically and rows are what cost us
-- credits.
-- ---------------------------------------------------------------------------
create or replace procedure GEN.SP_GENERATE_DAMAGE(
    window_start      timestamp_ntz,
    window_end        timestamp_ntz,
    seed              varchar,
    damage_multiplier float,
    accel_share       float
)
returns varchar
language sql
execute as caller
as
$$
declare
    damage_rows  integer;
    failure_rows integer;
begin
    delete from GEN.GEN_DAMAGE_STATE
    where ts::date between :window_start::date and :window_end::date;
    -- Delete on the DATE range, not the timestamp range: a failure on the final
    -- day is stamped 6..18h into that day and can therefore fall after
    -- WINDOW_END, survive the delete, and accumulate across re-runs. That is
    -- exactly what happened while tuning the multiplier — three stale rows
    -- turned 49 failures into 52 and broke the component count.
    delete from GEN.GEN_FAILURE_EVENT
    where failure_ts::date between :window_start::date and :window_end::date;

    -- ---- per-instance constants ------------------------------------------
    create or replace temporary table GEN.GEN_TMP_INSTANCE as
    select
        c.component_id,
        c.turbine_id,
        c.component_class_code,
        c.installed_serial                                    as serial_number,
        t.site_code,
        t.platform_id,
        datediff(day, c.install_date, :window_start) / 365.25 as age_years,
        GEN.FN_DAMAGE_RATE(c.component_class_code)            as annual_rate,
        ss.stressor_factor,
        case when t.platform_id = 'VW-2.1' then 1.12 else 1.00 end as platform_factor,
        -- bimodal: a bad batch, and everybody else. See the file header.
        --
        -- Batch incidence is scaled by the class's own wear rate, so a bad batch
        -- bites hardest where the duty is hardest. Without that scaling the 5-11x
        -- factor swamps the per-class rates and the failure mix flattens out:
        -- measured 46% drivetrain, with yaw drives and blades failing as often as
        -- gearboxes, which T-7 rightly rejects. Profile §5 is clear that the
        -- drivetrain — and the gearbox above all — dominates corrective work.
        case
            when GEN.FN_RAND(c.installed_serial, :seed || 'batch')
                 < :accel_share * (GEN.FN_DAMAGE_RATE(c.component_class_code) / 0.155)
            then 5.0 + 6.0 * GEN.FN_RAND(c.component_id, :seed || 'batchmag')
            else 0.70 + 0.70 * GEN.FN_RAND(c.component_id, :seed || 'inst')
        end                                                   as instance_factor,
        case
            when GEN.FN_RAND(c.installed_serial, :seed || 'batch')
                 < :accel_share * (GEN.FN_DAMAGE_RATE(c.component_class_code) / 0.155)
            then true else false
        end                                                   as is_bad_batch,
        0.88 + 0.28 * GEN.FN_RAND(c.component_id, :seed || 'thresh') as failure_threshold,
        wl.mean_wind_load
    from RAW.DIM_COMPONENT c
    join RAW.DIM_TURBINE t        on t.turbine_id = c.turbine_id
    join GEN.GEN_SITE_STRESSOR ss on ss.site_code = t.site_code
    join (
        select turbine_id, avg(greatest(0.15, wind_load_factor)) as mean_wind_load
        from GEN.GEN_TURBINE_DAY
        where day between :window_start::date and :window_end::date
        group by turbine_id
    ) wl on wl.turbine_id = c.turbine_id;

    -- ---- daily increments, then a running total --------------------------
    create or replace temporary table GEN.GEN_TMP_DAMAGE as
    with daily as (
        select
            i.component_id,
            i.turbine_id,
            i.component_class_code,
            i.serial_number,
            i.failure_threshold,
            d.day,
            -- the day's wear: class rate, spread over a year, scaled by how
            -- hard this site and this day actually worked the component
            (i.annual_rate / 365.25)
                * i.stressor_factor
                * i.platform_factor
                * i.instance_factor
                * greatest(0.15, d.wind_load_factor)
                * :damage_multiplier            as damage_inc,
            -- where this instance already was when the window opened, CAPPED.
            --
            -- The cap is what makes T-8 assertable for EVERY seeded failure
            -- rather than most of them. Without it, a component can enter the
            -- window at damage 0.97 and fail three weeks later having barely
            -- moved: there is no trend to detect, and no feature engineering
            -- could find one. Capping the starting point at 0.55 means crossing
            -- the threshold requires accumulating at least ~0.33 INSIDE the
            -- window, so every failure has a real degradation history behind it.
            -- The fleet is therefore "healthy or mid-life" at window open, which
            -- is also the honest reading of a 6-month observation window.
            least(
                0.55,
                mod(
                    i.age_years * i.annual_rate * i.stressor_factor
                        * i.platform_factor * i.instance_factor,
                    1.0
                ),
                -- BURN-IN. Nothing may cross its threshold inside the first 60
                -- days of the window, because a component that fails on day 41
                -- has no observable history to have trended over, and T-8 could
                -- not be asserted for it: the run measured 57 of 58 failures and
                -- failed on the 58th. A predictive claim about a failure with no
                -- lead-in data would be dishonest anyway, so the first 60 days
                -- are baseline history for every component, by construction.
                i.failure_threshold - 60.0 * (
                    (i.annual_rate / 365.25) * i.stressor_factor * i.platform_factor
                    * i.instance_factor * i.mean_wind_load * :damage_multiplier
                )
            )                                    as initial_damage
        from GEN.GEN_TMP_INSTANCE i
        join GEN.GEN_TURBINE_DAY d on d.turbine_id = i.turbine_id
        where d.day between :window_start::date and :window_end::date
    )
    select
        component_id,
        turbine_id,
        component_class_code,
        serial_number,
        failure_threshold,
        day,
        damage_inc,
        initial_damage,
        initial_damage
            + sum(damage_inc) over (
                  partition by component_id order by day
                  rows between unbounded preceding and current row
              ) as damage_raw
    from daily;

    -- ---- first threshold crossing is the failure -------------------------
    create or replace temporary table GEN.GEN_TMP_FAILURE as
    select
        component_id,
        turbine_id,
        component_class_code,
        serial_number,
        failure_threshold,
        min(day) as failure_day
    from GEN.GEN_TMP_DAMAGE
    where damage_raw >= failure_threshold
    group by 1, 2, 3, 4, 5;

    -- ---- failure events, with a code and a repair date -------------------
    insert into GEN.GEN_FAILURE_EVENT (
        failure_event_id, component_id, turbine_id, component_class_code,
        serial_number, failure_ts, failure_code, damage_at_failure,
        failure_threshold, repair_ts
    )
    select
        'FE-' || replace(f.component_id, '-', '') || '-' || to_varchar(f.failure_day, 'YYYYMMDD'),
        f.component_id,
        f.turbine_id,
        f.component_class_code,
        f.serial_number,
        -- fail during operating hours, not always at midnight, but never after
        -- the window closes — T-11 asserts max(timestamp) is inside the window
        least(
            dateadd(hour, 6 + floor(12 * GEN.FN_RAND(f.component_id, :seed || 'hour')), f.failure_day::timestamp_ntz),
            :window_end
        ),
        fc.failure_code,
        d.damage_raw,
        f.failure_threshold,
        -- repair lands after the part's lead time, longer if a crane is needed
        dateadd(
            day,
            greatest(1, round(coalesce(pt.lead_time_days, 14) * (0.15 + 0.35 * GEN.FN_RAND(f.component_id, :seed || 'rep')))),
            f.failure_day::timestamp_ntz
        )
    from GEN.GEN_TMP_FAILURE f
    join GEN.GEN_TMP_DAMAGE d
        on d.component_id = f.component_id and d.day = f.failure_day
    -- deterministic pick among the failure codes valid for this class
    join (
        select
            failure_code,
            component_class_code,
            row_number() over (partition by component_class_code order by failure_code) - 1 as idx,
            count(*)       over (partition by component_class_code)                         as n
        from RAW.DIM_FAILURE_CODE
    ) fc
        on fc.component_class_code = f.component_class_code
       and fc.idx = floor(fc.n * GEN.FN_RAND(f.component_id, :seed || 'fcode'))
    -- cheapest matching part drives the lead time
    left join (
        select component_class_code, min(lead_time_days) as lead_time_days
        from RAW.DIM_PART group by component_class_code
    ) pt
        on pt.component_class_code = f.component_class_code;

    failure_rows := sqlrowcount;

    -- ---- damage state, with the post-repair reset applied ----------------
    insert into GEN.GEN_DAMAGE_STATE (
        component_id, serial_number, ts, damage_level, failure_threshold,
        has_failed, failure_ts
    )
    select
        d.component_id,
        -- after repair the position carries a NEW serial: genealogy (US-10)
        case
            when fe.repair_ts is not null and d.day >= fe.repair_ts::date
            then d.serial_number || 'R'
            else d.serial_number
        end,
        d.day::timestamp_ntz,
        round(
            case
                -- repaired: a refurbished instance restarts near zero
                when fe.repair_ts is not null and d.day >= fe.repair_ts::date
                    then 0.04 + sum(d.damage_inc) over (
                             partition by d.component_id
                             order by d.day rows between unbounded preceding and current row
                         ) - sum(case when d.day < fe.repair_ts::date then d.damage_inc else 0 end) over (
                             partition by d.component_id
                             order by d.day rows between unbounded preceding and current row
                         )
                -- failed but not yet repaired: held at the threshold, stopped
                when fe.failure_ts is not null and d.day > fe.failure_ts::date
                    then d.failure_threshold
                else least(d.damage_raw, d.failure_threshold)
            end,
            6
        ),
        round(d.failure_threshold, 6),
        case when fe.failure_ts is not null and d.day >= fe.failure_ts::date then true else false end,
        fe.failure_ts
    from GEN.GEN_TMP_DAMAGE d
    left join GEN.GEN_FAILURE_EVENT fe on fe.component_id = d.component_id;

    damage_rows := sqlrowcount;

    return 'GEN_DAMAGE_STATE: ' || damage_rows || ' component-days; '
        || 'GEN_FAILURE_EVENT: ' || failure_rows || ' seeded failures';
end;
$$;
