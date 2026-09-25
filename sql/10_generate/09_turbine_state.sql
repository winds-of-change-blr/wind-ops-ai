-- =============================================================================
-- 10_generate / 09 — turbine state intervals                   STAGE: WOA_ADMIN
-- =============================================================================
-- Implements : US-12 (operating state on every fact row)
-- Proves     : supports T-6, and the availability denominator every metric needs
-- Authority  : docs/04-data/data-model.md §2 (interval grain), profile §8
-- Parameter  : <% database %>
--
-- INTERVAL-BASED, NOT SNAPSHOT-BASED. Availability is
-- available_time / (period - exclusions), which is a SUM over intervals rather
-- than a COUNT of snapshots. Snapshots would force an assumption about what
-- happened between them, and that assumption is where contractual availability
-- numbers quietly go wrong.
--
-- Four things take a turbine out of READY, and they are not equivalent:
--   * corrective repair      — counts against us, no exclusion
--   * scheduled maintenance  — excluded, within the contract's annual allowance
--   * grid outage            — excluded, not our fault
--   * curtailment            — excluded, the offtaker asked for it
-- Getting the exclusion class right is the difference between owing liquidated
-- damages and not owing them, which is why it is a column and not a comment.
-- =============================================================================

use role WOA_ADMIN;
use database <% database %>;
use warehouse WOA_BUILD_WH;

create or replace procedure GEN.SP_GENERATE_TURBINE_STATE(
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
    delete from RAW.FCT_TURBINE_STATE
    where state_start between :window_start and :window_end;

    insert into RAW.FCT_TURBINE_STATE (
        turbine_id, state_start, state_end, operating_state, state_reason,
        exclusion_class_code
    )
    -- Scheduled visits computed in a CTE, not a LATERAL: a LATERAL with no FROM
    -- clause is an unsupported subquery type in Snowflake.
    with pm_visit as (
        select
            t.turbine_id,
            n.visit_no,
            dateadd(
                hour,
                floor(
                    (datediff(hour, :window_start, :window_end) / 2.0) * (n.visit_no - 1)
                    + 80 * GEN.FN_RAND(t.turbine_id || n.visit_no::varchar, :seed || 'pm')
                ),
                :window_start
            ) as visit_start
        from RAW.DIM_TURBINE t
        cross join (
            select row_number() over (order by seq4()) as visit_no
            from table(generator(rowcount => 2))
        ) n
    ),
    grid_outage as (
        select
            s.site_code,
            dateadd(
                hour,
                floor(datediff(hour, :window_start, :window_end) * GEN.FN_RAND(s.site_code || g.n::varchar, 'grid-outage')),
                :window_start
            ) as outage_start,
            30 + floor(210 * GEN.FN_RAND(s.site_code || g.n::varchar, 'grid-dur')) as outage_min
        from RAW.DIM_SITE s
        cross join (
            select row_number() over (order by seq4()) as n
            from table(generator(rowcount => 3))
        ) g
    )
    -- ---- corrective downtime: failure to repair --------------------------
    select
        f.turbine_id,
        f.failure_ts,
        least(coalesce(f.repair_ts, :window_end), :window_end),
        'UNAVAILABLE',
        'Corrective repair: ' || fc.failure_name,
        null                                    -- counts against availability
    from GEN.GEN_FAILURE_EVENT f
    join RAW.DIM_FAILURE_CODE fc on fc.failure_code = f.failure_code
    where f.failure_ts between :window_start and :window_end

    union all

    -- ---- scheduled maintenance: two visits a year, per turbine -----------
    select
        v.turbine_id,
        v.visit_start,
        dateadd(hour, 8 + floor(4 * GEN.FN_RAND(v.turbine_id || v.visit_no::varchar, :seed || 'pmdur')), v.visit_start),
        'UNAVAILABLE',
        'Scheduled maintenance visit ' || v.visit_no,
        'SCHED_MAINT'
    from pm_visit v
    where v.visit_start < :window_end

    union all

    -- ---- grid outages: site-wide, and the seeded dip in 10_alarms --------
    select
        t.turbine_id,
        o.outage_start,
        dateadd(minute, o.outage_min, o.outage_start),
        'UNAVAILABLE',
        'Grid outage at site ' || t.site_code,
        'GRID'
    from RAW.DIM_TURBINE t
    join grid_outage o on o.site_code = t.site_code
    where o.outage_start < :window_end

    union all

    -- ---- READY: the remainder of each turbine-day ------------------------
    -- One row per turbine-day marked READY. Overlapping UNAVAILABLE intervals
    -- above are subtracted by the metric layer rather than pre-cut here: cutting
    -- them here would mean recomputing every interval whenever a failure moves,
    -- and the metric layer has to handle overlap correctly anyway.
    select
        d.turbine_id,
        d.day::timestamp_ntz,
        least(dateadd(day, 1, d.day::timestamp_ntz), :window_end),
        'READY',
        'Available',
        null
    from GEN.GEN_TURBINE_DAY d
    where d.day between :window_start::date and :window_end::date;

    rows_written := sqlrowcount;
    return 'FCT_TURBINE_STATE: ' || rows_written || ' intervals';
end;
$$;
