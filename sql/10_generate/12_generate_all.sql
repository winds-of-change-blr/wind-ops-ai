-- =============================================================================
-- 10_generate / 12 — the orchestrator                          STAGE: WOA_ADMIN
-- =============================================================================
-- Implements : US-8..US-12 (the generator as one callable unit), backs `just seed`
-- Proves     : T-8's determinism requirement — same seed, same data
-- Authority  : docs/04-data/data-sources-and-synthetic-data.md §2 (six stages)
-- Parameter  : <% database %>
--
-- One entry point, in dependency order, because the stages are not independent:
-- damage needs the operating context, signals and CMS features need damage, state
-- needs failures, alarms need signals and CMS features, and consequences need
-- alarms. Running them by hand in the wrong order produces a dataset that looks
-- fine and is quietly inconsistent — for instance alarms with no matching
-- downtime, which is the disagreement T-7 exists to catch.
--
-- Every run records its parameters in GEN_RUN_CONFIG, so a dataset can always be
-- traced back to the window, seed and volume knobs that produced it.
-- =============================================================================

use role WOA_ADMIN;
use database <% database %>;
use warehouse WOA_BUILD_WH;

create or replace procedure GEN.SP_GENERATE_ALL(
    history_days      integer,
    seed              varchar,
    damage_multiplier float,
    accel_share       float,
    interval_min      integer
)
returns varchar
language sql
execute as caller
as
$$
declare
    window_start timestamp_ntz;
    window_end   timestamp_ntz;
    run_id       varchar;
    log          varchar default '';
    step         varchar;
begin
    -- WINDOW_END is NOW, not a fixed date. T-11 asserts max(timestamp) is within
    -- a day of the generation date, and a hardcoded end date is precisely how the
    -- reference solution ended up with telemetry stopping nine months in the past
    -- and a "last 24 hours" panel returning nothing.
    window_end   := current_timestamp()::timestamp_ntz;
    window_start := dateadd(day, -:history_days, current_date())::timestamp_ntz;
    run_id       := 'RUN-' || to_varchar(window_end, 'YYYYMMDDHH24MISS');

    call GEN.SP_GENERATE_OPERATING_CONTEXT(:window_start, :window_end, :seed);
    log := log || (select * from table(result_scan(last_query_id()))) || '\n';

    call GEN.SP_GENERATE_DAMAGE(:window_start, :window_end, :seed, :damage_multiplier, :accel_share);
    log := log || (select * from table(result_scan(last_query_id()))) || '\n';

    call GEN.SP_GENERATE_SIGNALS(:window_start, :window_end, :seed, :interval_min);
    log := log || (select * from table(result_scan(last_query_id()))) || '\n';

    call GEN.SP_GENERATE_CMS_FEATURES(:window_start, :window_end, :seed);
    log := log || (select * from table(result_scan(last_query_id()))) || '\n';

    call GEN.SP_GENERATE_TURBINE_STATE(:window_start, :window_end, :seed);
    log := log || (select * from table(result_scan(last_query_id()))) || '\n';

    call GEN.SP_GENERATE_ALARMS(:window_start, :window_end, :seed);
    log := log || (select * from table(result_scan(last_query_id()))) || '\n';

    call GEN.SP_GENERATE_CONSEQUENCES(:window_start, :window_end, :seed);
    log := log || (select * from table(result_scan(last_query_id()))) || '\n';

    merge into GEN.GEN_RUN_CONFIG tgt
    using (
        select
            :run_id             as run_id,
            :window_end         as generated_at,
            :window_start       as window_start,
            :window_end         as window_end,
            :seed               as seed,
            :damage_multiplier  as damage_multiplier,
            :interval_min       as signal_interval_min,
            'accel_share=' || :accel_share || '; history_days=' || :history_days as notes
    ) src
    on tgt.run_id = src.run_id
    when not matched then insert (
        run_id, generated_at, window_start, window_end, seed, damage_multiplier,
        signal_interval_min, notes
    ) values (
        src.run_id, src.generated_at, src.window_start, src.window_end, src.seed,
        src.damage_multiplier, src.signal_interval_min, src.notes
    );

    return 'run ' || run_id || ' (' || to_varchar(:window_start, 'YYYY-MM-DD')
        || ' .. ' || to_varchar(:window_end, 'YYYY-MM-DD HH24:MI') || ')\n' || log;
end;
$$;
