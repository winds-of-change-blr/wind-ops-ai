-- =============================================================================
-- 30_serve / 01 — contractual availability and LD exposure       STAGE: WOA_ADMIN
-- =============================================================================
-- Implements : US-13 (contractual availability), US-15 (LD exposure) — first cut
-- Proves     : T-20, T-22 through the SERVING.FN_* functions (15_quality/07 fixtures)
-- Authority  : sql/10_generate/09_turbine_state.sql header (the availability
--              definition), profile §8 (the contract), docs/04-data/data-model.md
-- Parameter  : <% database %>
--
-- ===================== THE DEFINITION IS THE GENERATOR'S =====================
--
--   availability = available_time / (period - excluded_time)
--
-- Four things take a turbine out of READY and they are not equivalent. Grid
-- outage, curtailment, force majeure, balance of plant and scheduled
-- maintenance carry an exclusion class and come OFF the denominator. Corrective
-- repair carries none and counts AGAINST us. That distinction is the difference
-- between owing liquidated damages and not, so it is taken from the
-- exclusion_class_code column and never inferred.
--
-- Only non-READY intervals are summed, so the formula is correct whether or not
-- the state table also records READY intervals.
--
-- ===================== WHAT LD EXPOSURE MEANS HERE ===========================
--
-- Contracts assess availability annually; the generated window is six months.
-- MET_LD_EXPOSURE is therefore a RUN-RATE: what the site would owe if the
-- contract year ended at the window's availability. It is labelled as such in
-- every column name and comment, and never presented as an invoice.
-- =============================================================================

use role WOA_ADMIN;
use database <% database %>;
use warehouse WOA_BUILD_WH;

-- ---------------------------------------------------------------- functions
create or replace function SERVING.FN_AVAILABILITY_PCT(
    period_hours float, excluded_hours float, counted_down_hours float
)
returns float language sql immutable
comment = 'Time-based availability in percent: (period - excluded - down) / (period - excluded). Used by MET_AVAILABILITY_* and T-20.'
as $$
    100 * (period_hours - coalesce(excluded_hours, 0) - coalesce(counted_down_hours, 0))
        / nullif(period_hours - coalesce(excluded_hours, 0), 0)
$$;

create or replace function SERVING.FN_GUARANTEE_PCT(
    contract_start date, as_of date, yr1_2_pct float, yr3_plus_pct float
)
returns float language sql immutable
comment = 'Availability guarantee in force: years 1-2 of the contract, then year 3 onward. Used by MET_LD_EXPOSURE and T-20.'
as $$
    iff(datediff(month, contract_start, as_of) < 24, yr1_2_pct, yr3_plus_pct)
$$;

create or replace function SERVING.FN_LD_RUN_RATE_INR(
    availability_pct float, guarantee_pct float, rate_per_turbine_per_pct float, turbines float
)
returns float language sql immutable
comment = 'LD exposure in INR: shortfall below guarantee (never negative) x rate x turbines. A run-rate, not an invoice. Used by MET_LD_EXPOSURE and T-22.'
as $$
    greatest(0, guarantee_pct - availability_pct) * rate_per_turbine_per_pct * turbines
$$;

create or replace function SERVING.FN_INTERVAL_KWH(power_kw float, interval_min float)
returns float language sql immutable
comment = 'Energy in kWh of one interval at a mean power. Used by AGG_TURBINE_DAY and T-21.'
as $$
    coalesce(power_kw, 0) * interval_min / 60.0
$$;

create or replace view SERVING.V_WINDOW as
select
    min(day)::date                                      as window_start,
    max(day)::date                                      as window_end,
    datediff(hour, min(day), dateadd(day, 1, max(day))) as period_hours
from GEN.GEN_TURBINE_DAY;

create or replace view SERVING.MET_AVAILABILITY_CONTRACTUAL as
select
    t.turbine_id,
    t.site_code,
    t.platform_id,
    w.period_hours,
    coalesce(s.excluded_hours, 0)                                        as excluded_hours,
    coalesce(s.counted_down_hours, 0)                                    as counted_down_hours,
    w.period_hours - coalesce(s.excluded_hours, 0)                       as eligible_hours,
    round(SERVING.FN_AVAILABILITY_PCT(w.period_hours, s.excluded_hours, s.counted_down_hours), 3) as availability_pct,
    true                                                                 as is_synthetic
from RAW.DIM_TURBINE t
cross join SERVING.V_WINDOW w
left join (
    select
        turbine_id,
        sum(iff(exclusion_class_code is not null,
                datediff(minute, state_start, coalesce(state_end, state_start)), 0)) / 60.0 as excluded_hours,
        sum(iff(exclusion_class_code is null,
                datediff(minute, state_start, coalesce(state_end, state_start)), 0)) / 60.0 as counted_down_hours
    from RAW.FCT_TURBINE_STATE
    where operating_state <> 'READY'
    group by turbine_id
) s on s.turbine_id = t.turbine_id;

-- Guarantee by contract year at the window end: 95% in years 1-2, 97% after.
create or replace view SERVING.MET_LD_EXPOSURE as
select
    a.site_code,
    si.site_name,
    si.state,
    count(*)                                                      as turbines,
    round(avg(a.availability_pct), 3)                             as availability_pct,
    SERVING.FN_GUARANTEE_PCT(c.start_date, w.window_end, c.guarantee_yr1_2_pct, c.guarantee_yr3_plus_pct) as guarantee_pct,
    greatest(0, SERVING.FN_GUARANTEE_PCT(c.start_date, w.window_end, c.guarantee_yr1_2_pct, c.guarantee_yr3_plus_pct)
                - avg(a.availability_pct))                        as shortfall_pct,
    c.ld_rate_per_turbine_per_pct,
    round(SERVING.FN_LD_RUN_RATE_INR(avg(a.availability_pct),
              SERVING.FN_GUARANTEE_PCT(c.start_date, w.window_end, c.guarantee_yr1_2_pct, c.guarantee_yr3_plus_pct),
              c.ld_rate_per_turbine_per_pct, count(*)), 0)       as ld_exposure_run_rate_inr,
    true                                                          as is_synthetic
from SERVING.MET_AVAILABILITY_CONTRACTUAL a
join RAW.DIM_SITE si     on si.site_code = a.site_code
join RAW.DIM_CONTRACT c  on c.site_code  = a.site_code
cross join SERVING.V_WINDOW w
group by a.site_code, si.site_name, si.state, c.start_date, c.guarantee_yr1_2_pct,
         c.guarantee_yr3_plus_pct, c.ld_rate_per_turbine_per_pct, w.window_end;
