-- =============================================================================
-- 40_engine / 02 — triage ranked by money, not by severity       STAGE: WOA_ADMIN
-- =============================================================================
-- Implements : US-24 (ranked triage), FR-24 (rank by consequence) — first cut
-- Proves     : feeds the demo beat "triage ranked by money" and T-94's surface
-- Authority  : ADR-0004, docs/08-delivery/demo-and-submission.md beat 5
-- Parameter  : <% database %>
--
-- The reference solution ranked by severity. A severity-5 alarm on a yaw drive
-- and a severity-3 trend on a gearbox are not the same decision: one is a
-- ₹-thousands part and an hour, the other a crane campaign, a lead-time wait and
-- days of lost availability against a guarantee. So the rank is EXPECTED LOSS:
--
--   expected_loss = risk_probability x (part cost + LD cost of the downtime)
--
-- Downtime days = the part's lead time plus a repair allowance (5 days if the
-- part needs a crane, 2 if not). THE REPAIR ALLOWANCE IS ILLUSTRATIVE (NFR-10):
-- the profile gives lead times and crane flags but not repair durations, and
-- the column carrying it says so. Everything else is read from the data.
--
-- Deterministic, testable SQL (ADR-0004). No model ranks anything here; the
-- model contributes risk_probability as an input and nothing more.
-- =============================================================================

use role WOA_ADMIN;
use database <% database %>;
use warehouse WOA_BUILD_WH;

create or replace view ENGINE.ENG_ALERT_RANKED as
with part as (
    select component_class_code,
           max(unit_cost_inr)   as part_cost_inr,
           max(lead_time_days)  as lead_time_days,
           boolor_agg(coalesce(requires_crane, false)) as requires_crane
    from RAW.DIM_PART
    group by component_class_code
),
drivers as (
    select component_id, scored_date,
           listagg(feature_name || ' ' || direction, ', ') within group (order by driver_rank) as top_drivers
    from ML.DRIVER_COMPONENT_RISK
    where driver_rank <= 3
    group by component_id, scored_date
),
anom as (
    select component_id, scored_date, is_anomaly, anomaly_distance
    from ML.SCORE_COMPONENT_ANOMALY
)
select
    r.component_id,
    r.turbine_id,
    t.site_code,
    r.component_class_code,
    cc.component_class_name,
    r.scored_date                                            as as_of_date,
    r.risk_probability,
    r.risk_band,
    coalesce(a.is_anomaly, false)                            as anomaly_flag,
    a.anomaly_distance,
    d.top_drivers,
    p.part_cost_inr,
    p.lead_time_days,
    coalesce(p.requires_crane, false)                        as requires_crane,
    coalesce(p.lead_time_days, 0) + iff(coalesce(p.requires_crane, false), 5, 2)
                                                             as downtime_days_illustrative,
    -- LD cost of the downtime: hours lost as a share of eligible hours, in
    -- percentage points, times the contract's per-turbine-per-point rate.
    round(100 * (coalesce(p.lead_time_days, 0) + iff(coalesce(p.requires_crane, false), 5, 2)) * 24
          / nullif(av.eligible_hours, 0) * c.ld_rate_per_turbine_per_pct, 0)
                                                             as downtime_ld_cost_inr,
    round(r.risk_probability * (
            coalesce(p.part_cost_inr, 0)
          + 100 * (coalesce(p.lead_time_days, 0) + iff(coalesce(p.requires_crane, false), 5, 2)) * 24
            / nullif(av.eligible_hours, 0) * c.ld_rate_per_turbine_per_pct), 0)
                                                             as expected_loss_inr,
    row_number() over (order by r.risk_probability * (
            coalesce(p.part_cost_inr, 0)
          + 100 * (coalesce(p.lead_time_days, 0) + iff(coalesce(p.requires_crane, false), 5, 2)) * 24
            / nullif(av.eligible_hours, 0) * c.ld_rate_per_turbine_per_pct) desc,
          r.component_id)                                    as money_rank,
    row_number() over (order by r.risk_probability desc, r.component_id)
                                                             as probability_rank,
    r.model_version,
    true                                                     as is_synthetic
from ML.SCORE_COMPONENT_RISK r
join RAW.DIM_TURBINE t              on t.turbine_id = r.turbine_id
join RAW.DIM_COMPONENT_CLASS cc     on cc.component_class_code = r.component_class_code
join RAW.DIM_CONTRACT c             on c.site_code = t.site_code
join SERVING.MET_AVAILABILITY_CONTRACTUAL av on av.turbine_id = r.turbine_id
left join part p                    on p.component_class_code = r.component_class_code
left join drivers d                 on d.component_id = r.component_id and d.scored_date = r.scored_date
left join anom a                    on a.component_id = r.component_id and a.scored_date = r.scored_date;
