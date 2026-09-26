-- =============================================================================
-- 30_serve / 01 — contractual availability and LD exposure       STAGE: WOA_ADMIN
-- =============================================================================
-- Implements : US-13 (contractual availability), US-15 (LD exposure) — first cut
-- Proves     : feeds T-20..T-22 (hand-worked fixtures still to be written)
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
    round(100 * (w.period_hours - coalesce(s.excluded_hours, 0) - coalesce(s.counted_down_hours, 0))
          / nullif(w.period_hours - coalesce(s.excluded_hours, 0), 0), 3) as availability_pct,
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
    iff(datediff(month, c.start_date, w.window_end) < 24,
        c.guarantee_yr1_2_pct, c.guarantee_yr3_plus_pct)          as guarantee_pct,
    greatest(0, iff(datediff(month, c.start_date, w.window_end) < 24,
                    c.guarantee_yr1_2_pct, c.guarantee_yr3_plus_pct)
                - avg(a.availability_pct))                        as shortfall_pct,
    c.ld_rate_per_turbine_per_pct,
    round(greatest(0, iff(datediff(month, c.start_date, w.window_end) < 24,
                          c.guarantee_yr1_2_pct, c.guarantee_yr3_plus_pct)
                      - avg(a.availability_pct))
          * c.ld_rate_per_turbine_per_pct * count(*), 0)         as ld_exposure_run_rate_inr,
    true                                                          as is_synthetic
from SERVING.MET_AVAILABILITY_CONTRACTUAL a
join RAW.DIM_SITE si     on si.site_code = a.site_code
join RAW.DIM_CONTRACT c  on c.site_code  = a.site_code
cross join SERVING.V_WINDOW w
group by a.site_code, si.site_name, si.state, c.start_date, c.guarantee_yr1_2_pct,
         c.guarantee_yr3_plus_pct, c.ld_rate_per_turbine_per_pct, w.window_end;
