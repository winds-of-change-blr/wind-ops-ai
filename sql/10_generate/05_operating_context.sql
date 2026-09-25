-- =============================================================================
-- 10_generate / 05 — operating context, per turbine-day        STAGE: WOA_ADMIN
-- =============================================================================
-- Implements : US-2 (diurnal and seasonal wind behaviour) · stage 2 of §2
-- Authority  : docs/04-data/data-sources-and-synthetic-data.md §2, §4
-- Parameter  : <% database %>
--
-- Stage 2 of the six-stage strategy: wind by site and season, through the power
-- curve, to an operating point. Materialised at DAY grain because three later
-- stages need the same summary and recomputing it in each would let them drift:
--   * damage accumulation scales the daily increment by wind loading (stage 3)
--   * the signal response needs the day's operating point (stage 4)
--   * turbine state and availability need daily energy (stage 6)
--
-- 100 turbines x ~183 days is ~18k rows, so this is cheap to hold and cheap to
-- rebuild. The hourly detail behind it is derived on the fly from
-- GEN.FN_WIND_SPEED rather than stored — it is a pure function of
-- (turbine, timestamp), so storing it would buy nothing.
-- =============================================================================

use role WOA_ADMIN;
use database <% database %>;
use warehouse WOA_BUILD_WH;

create table if not exists GEN.GEN_TURBINE_DAY (
    turbine_id        varchar(20)   not null,
    day               date          not null,
    mean_wind_ms      number(6,3)   not null,
    max_wind_ms       number(6,3)   not null,
    mean_power_kw     number(10,2)  not null,
    energy_mwh        number(10,3)  not null,
    capacity_factor   number(6,4)   not null,
    wind_load_factor  number(6,4)   not null,
    hours_below_cutin number(5,2)   not null,
    hours_above_cutout number(5,2)  not null,
    is_synthetic      boolean       not null default true,
    constraint pk_gen_turbine_day primary key (turbine_id, day)
);

-- ---------------------------------------------------------------------------
-- SP_GENERATE_OPERATING_CONTEXT — fill GEN_TURBINE_DAY for a window.
--
-- WIND_LOAD_FACTOR is the term that carries into damage: the ratio of the day's
-- mean wind to the site's long-run mean, squared, because load on a drivetrain
-- rises faster than linearly with wind. A windy month therefore accumulates
-- more damage than a calm one, which is what makes degradation correlate with
-- operating history rather than with the calendar.
--
-- Idempotent: deletes the window it is about to write, then writes it. It never
-- truncates the table, so regenerating one month leaves other months intact.
-- ---------------------------------------------------------------------------
create or replace procedure GEN.SP_GENERATE_OPERATING_CONTEXT(
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
    rows_written integer;
begin
    delete from GEN.GEN_TURBINE_DAY
    where day between :window_start::date and :window_end::date;

    insert into GEN.GEN_TURBINE_DAY (
        turbine_id, day, mean_wind_ms, max_wind_ms, mean_power_kw, energy_mwh,
        capacity_factor, wind_load_factor, hours_below_cutin, hours_above_cutout
    )
    with hours as (
        select
            t.turbine_id,
            s.mean_wind_speed                     as site_mean,
            p.rated_power_mw * 1000               as rated_kw,
            p.cut_in_speed_ms,
            p.rated_speed_ms,
            p.cut_out_speed_ms,
            dateadd(hour, g.seq, :window_start)   as ts
        from RAW.DIM_TURBINE t
        join RAW.DIM_SITE s     on s.site_code   = t.site_code
        join RAW.DIM_PLATFORM p on p.platform_id = t.platform_id
        cross join (
            select row_number() over (order by seq4()) - 1 as seq
            from table(generator(rowcount => 4416))          -- 184 days of hours
        ) g
        where dateadd(hour, g.seq, :window_start) < :window_end
    ),
    resolved as (
        select
            turbine_id,
            ts::date as day,
            site_mean,
            rated_kw,
            cut_in_speed_ms,
            rated_speed_ms,
            cut_out_speed_ms,
            GEN.FN_WIND_SPEED(turbine_id, ts, site_mean, :seed) as wind_ms
        from hours
    )
    select
        turbine_id,
        day,
        round(avg(wind_ms), 3),
        round(max(wind_ms), 3),
        round(avg(GEN.FN_EXPECTED_POWER(wind_ms, rated_kw, cut_in_speed_ms, rated_speed_ms, cut_out_speed_ms)), 2),
        round(sum(GEN.FN_EXPECTED_POWER(wind_ms, rated_kw, cut_in_speed_ms, rated_speed_ms, cut_out_speed_ms)) / 1000.0, 3),
        round(avg(GEN.FN_EXPECTED_POWER(wind_ms, rated_kw, cut_in_speed_ms, rated_speed_ms, cut_out_speed_ms)) / max(rated_kw), 4),
        round(pow(avg(wind_ms) / max(site_mean), 2), 4),
        round(sum(case when wind_ms < cut_in_speed_ms  then 1 else 0 end), 2),
        round(sum(case when wind_ms >= cut_out_speed_ms then 1 else 0 end), 2)
    from resolved
    group by turbine_id, day;

    rows_written := sqlrowcount;
    return 'GEN_TURBINE_DAY: ' || rows_written || ' turbine-days written for '
        || to_varchar(:window_start, 'YYYY-MM-DD') || ' .. ' || to_varchar(:window_end, 'YYYY-MM-DD');
end;
$$;
