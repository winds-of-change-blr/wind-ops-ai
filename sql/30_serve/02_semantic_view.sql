-- =============================================================================
-- 30_serve / 02 — the semantic view SV_WIND_OPS                    STAGE: WOA_ADMIN
-- =============================================================================
-- Implements : the Cortex Analyst semantic layer (ADR-0009) — G3
-- Proves     : T-42 (descriptions domain-correct, unit-bearing), feeds T-43..T-49
-- Authority  : docs/04-data/semantic-model-and-ontology.md, ADR-0009
-- Parameter  : <% database %>
--
-- Written as DDL, not generated: the agent-studio skill's generator needs the
-- Cortex CLI, which is not installed here (NK chose DDL, 2026-09-26). Every
-- description below was written against the data it describes.
--
-- ===================== ONE JOIN PATH PER METRIC ==============================
--
-- Several logical tables carry SITE_CODE directly (risk, availability,
-- incidents). Declaring every one of them as a relationship to SITE would give
-- Cortex Analyst two routes from a risk row to a site, and it may pick either.
-- So facts reach SITE only THROUGH TURBINE; SITE_CODE on those tables is not
-- declared as a join. The one exception is LD exposure, which is site-grain by
-- construction and has no turbine.
--
-- ===================== WHAT THE NUMBERS MEAN ==================================
--
-- The semantic layer is where a wrong definition becomes a confident wrong
-- answer, so the definitions are stated where Analyst will read them:
--   * risk is a 30-day-ahead probability, scored AS OF window_end - horizon (I-13)
--   * expected loss (INR) = risk x (part cost + LD cost of downtime); the repair
--     allowance inside downtime is illustrative (NFR-10)
--   * availability = available / (period - excluded hours); corrective repair
--     counts against the operator, the five exclusion classes do not
--   * LD exposure is a RUN-RATE over the six-month window, never an invoice
-- All data is synthetic (AGENTS.md rule 5).
-- =============================================================================

use role WOA_ADMIN;
use database <% database %>;
use warehouse WOA_BUILD_WH;

create or replace semantic view SERVING.SV_WIND_OPS
  tables (
    site as RAW.DIM_SITE
      primary key (site_code)
      with synonyms = ('wind farm', 'plant')
      comment = 'The six wind farms Vayuveda Wind Systems operates and maintains in India. One row per site.',
    turbine as RAW.DIM_TURBINE
      primary key (turbine_id)
      with synonyms = ('WTG', 'wind turbine generator', 'unit')
      comment = 'The 100 turbines in the fleet. One row per turbine; each belongs to exactly one site.',
    risk as ENGINE.ENG_ALERT_RANKED
      primary key (component_id)
      with synonyms = ('component risk', 'failure risk', 'triage list', 'alert ranking')
      comment = 'One row per monitored component (gearbox, generator, main shaft & bearing, pitch system): its 30-day failure risk, anomaly flag, top drivers and expected loss in INR. Scored as of window end minus the 30-day horizon.',
    availability as SERVING.MET_AVAILABILITY_CONTRACTUAL
      primary key (turbine_id)
      with synonyms = ('contractual availability', 'uptime')
      comment = 'Contractual availability per turbine over the six-month window: available hours divided by (period hours minus excluded hours). Grid, curtailment, force majeure, balance of plant and scheduled maintenance are excluded; corrective repair counts against the operator.',
    ld as SERVING.MET_LD_EXPOSURE
      primary key (site_code)
      with synonyms = ('liquidated damages', 'penalty exposure', 'guarantee shortfall')
      comment = 'Liquidated-damages exposure per site: shortfall of availability against the contractual guarantee (95% in contract years 1-2, 97% after) times the per-turbine-per-percentage-point rate. A RUN-RATE over the window, not an invoice.',
    incident as ENGINE.ENG_INCIDENT
      primary key (incident_id)
      with synonyms = ('alarm incident', 'alarm', 'event', 'trip')
      comment = 'Alarm incidents: repeats of one alarm code on one turbine within 24 hours grouped into one incident, then classified ACTIONABLE, UNDETERMINED or NUISANCE by deterministic rules. Nothing safety-critical and nothing on an elevated-risk asset is ever NUISANCE.',
    oee as SERVING.MET_TURBINE_OEE
      primary key (turbine_id)
      with synonyms = ('turbine OEE', 'overall equipment effectiveness', 'performance')
      comment = 'Turbine OEE per turbine over the window: Availability x Performance, both over wind-in-limits intervals. Quality is NOT modelled (no forecast schedule), so OEE here is A x P, declared. Our adaptation of a factory metric, not an industry standard (ADR-0003).',
    lost as SERVING.MET_LOST_ENERGY
      primary key (turbine_id)
      with synonyms = ('lost energy', 'lost production', 'energy loss')
      comment = 'Energy lost per turbine in MWh, split into downtime (power-curve energy while unavailable) and underperformance (shortfall against the fleet-median performance while running).'
  )
  relationships (
    turbine_site     as turbine(site_code)      references site,
    risk_turbine     as risk(turbine_id)        references turbine,
    avail_turbine    as availability(turbine_id) references turbine,
    ld_site          as ld(site_code)           references site,
    incident_turbine as incident(turbine_id)    references turbine,
    oee_turbine      as oee(turbine_id)         references turbine,
    lost_turbine     as lost(turbine_id)        references turbine
  )
  facts (
    risk.risk_probability as risk_probability
      comment = '30-day-ahead probability that the component fails, between 0 and 1.',
    risk.expected_loss_inr as expected_loss_inr
      comment = 'Expected loss in Indian rupees (INR): risk probability x (part cost + LD cost of the downtime).',
    risk.part_cost_inr as part_cost_inr
      comment = 'Replacement part cost in INR.',
    risk.downtime_ld_cost_inr as downtime_ld_cost_inr
      comment = 'LD cost in INR of the downtime a failure would cause, from the part lead time plus an illustrative repair allowance.',
    risk.lead_time_days as lead_time_days
      comment = 'Replacement part lead time in days.',
    risk.anomaly_distance as anomaly_distance
      comment = 'How far the component''s primary sensor channel sits from its own expected level; larger is more unusual. Not a failure probability.',
    availability.turbine_availability_pct as availability_pct
      comment = 'Contractual availability of one turbine, in percent (0-100).',
    availability.counted_down_hours as counted_down_hours
      comment = 'Hours the turbine was unavailable for reasons that count against the operator (corrective repair).',
    availability.excluded_hours as excluded_hours
      comment = 'Hours removed from the availability denominator: grid, curtailment, force majeure, balance of plant, scheduled maintenance.',
    ld.ld_exposure_run_rate_inr as ld_exposure_run_rate_inr
      comment = 'LD exposure in INR at the current availability run-rate. Not an invoice.',
    ld.shortfall_pct as shortfall_pct
      comment = 'Percentage points by which site availability falls below its guarantee; 0 when at or above it.',
    ld.site_availability_pct as availability_pct
      comment = 'Mean contractual availability across the site''s turbines, in percent.',
    ld.guarantee_pct as guarantee_pct
      comment = 'Availability guarantee in force for the site''s contract year, in percent (95 or 97).',
    incident.n_alarms as n_alarms
      comment = 'Number of raw alarm trips grouped into this incident.',
    oee.availability_factor as availability_factor
      comment = 'OEE availability factor, 0 to 1: running intervals / (running + unavailable) intervals while the wind is within limits.',
    oee.performance_factor as performance_factor
      comment = 'OEE performance factor, 0 to 1: actual energy / power-curve energy at the measured wind, while running. A healthy turbine reads about 0.965 against the ideal curve.',
    oee.oee_value as oee
      comment = 'Turbine OEE, 0 to 1: availability_factor x performance_factor exactly. Quality not modelled.',
    lost.lost_mwh_downtime as lost_mwh_downtime
      comment = 'Energy lost in MWh while the turbine was unavailable and the wind was within limits.',
    lost.lost_mwh_underperformance as lost_mwh_underperformance
      comment = 'Energy lost in MWh by running below the fleet-median performance.',
    lost.lost_mwh_total as lost_mwh_total
      comment = 'Total energy lost in MWh: downtime plus underperformance.'
  )
  dimensions (
    site.site_code as site_code comment = 'Site code, e.g. KA-CTD, GJ-KCH, TN-TVL.',
    site.site_name as site_name comment = 'Wind farm name.',
    site.state as state comment = 'Indian state the site is in.',
    site.region as region comment = 'Region of India.',
    turbine.turbine_id as turbine_id comment = 'Turbine identifier, e.g. KA-CTD-T07 (site code, then T and a number).',
    turbine.platform_id as platform_id comment = 'Turbine platform / model.',
    risk.component_id as component_id comment = 'Monitored component identifier.',
    risk.component_class as component_class_name
      with synonyms = ('component type', 'component')
      comment = 'Component type: Gearbox, Generator, Main Shaft & Bearing, or Pitch System.',
    risk.risk_band as risk_band comment = 'Risk band: HIGH (>= 0.70), MEDIUM (>= 0.30), LOW, or MINIMAL.',
    risk.anomaly_flag as anomaly_flag comment = 'True when the anomaly detector flags the component as behaving unlike itself.',
    risk.requires_crane as requires_crane comment = 'True when the repair needs a crane rather than an up-tower fix.',
    risk.top_drivers as top_drivers comment = 'The three features driving the risk score, with their direction.',
    risk.risk_as_of_date as as_of_date comment = 'Date the risk score is as of (window end minus the 30-day horizon).',
    incident.incident_class as incident_class
      with synonyms = ('alarm class', 'classification')
      comment = 'ACTIONABLE, UNDETERMINED (left for a human, never hidden) or NUISANCE.',
    incident.alarm_code as alarm_code comment = 'Alarm code, e.g. SA-OT-004.',
    incident.alarm_name as alarm_name comment = 'Human-readable alarm name.',
    incident.alarm_source as alarm_source comment = 'Source system: SCADA, CMS, GRID or DQ.',
    incident.severity as severity comment = 'Alarm severity.',
    incident.is_safety_critical as is_safety_critical comment = 'True for protection trips; these are never suppressible.',
    incident.noise_condition as noise_condition comment = 'CHATTERING or STANDING when the incident shows that noise pattern.',
    incident.class_reason as class_reason comment = 'Plain-English reason the incident got its class.',
    incident.incident_start as incident_start comment = 'Timestamp of the first trip in the incident.',
    oee.is_underperforming as is_underperforming
      with synonyms = ('underperforming', 'underperforming while available')
      comment = 'True when performance is more than 1.5 points below the fleet median: losing energy while running, whatever the availability.',
    oee.oee_definition as oee_definition comment = 'How OEE is defined here, including that Quality is not modelled.'
  )
  metrics (
    risk.total_expected_loss_inr as sum(risk.expected_loss_inr)
      comment = 'Total expected loss in INR across the selected components.',
    risk.high_risk_components as count_if(risk.risk_band = 'HIGH')
      comment = 'Number of components in the HIGH risk band.',
    risk.max_risk_probability as max(risk.risk_probability)
      comment = 'Highest 30-day failure probability among the selected components.',
    availability.mean_turbine_availability_pct as avg(availability.turbine_availability_pct)
      comment = 'Mean contractual availability across the selected turbines, in percent.',
    ld.total_ld_exposure_run_rate_inr as sum(ld.ld_exposure_run_rate_inr)
      comment = 'Total LD exposure in INR at the current run-rate. Not an invoice.',
    ld.sites_below_guarantee as count_if(ld.shortfall_pct > 0)
      with synonyms = ('sites in shortfall', 'sites missing guarantee')
      comment = 'Number of sites whose availability is below their contractual guarantee. For WHICH sites, show site_name with shortfall_pct and guarantee_pct.',
    incident.incident_count as count(incident.incident_id)
      comment = 'Number of alarm incidents.',
    incident.actionable_incidents as count_if(incident.incident_class = 'ACTIONABLE')
      comment = 'Number of incidents classified ACTIONABLE.',
    incident.undetermined_incidents as count_if(incident.incident_class = 'UNDETERMINED')
      comment = 'Number of incidents left UNDETERMINED for a human.',
    oee.mean_oee as avg(oee.oee_value)
      comment = 'Mean Turbine OEE (A x P) across the selected turbines, 0 to 1.',
    oee.underperforming_turbines as count_if(oee.is_underperforming)
      comment = 'Number of turbines running more than 1.5 points below fleet-median performance.',
    lost.total_lost_mwh as sum(lost.lost_mwh_total)
      comment = 'Total energy lost in MWh across the selected turbines.'
  )
  comment = 'Wind Ops AI command center: component failure risk and expected loss, contractual availability, LD exposure, and classified alarm incidents for a fictional Indian wind OEM (100 turbines, 6 sites). SYNTHETIC DATA ONLY.';
