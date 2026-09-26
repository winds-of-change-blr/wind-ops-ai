-- =============================================================================
-- 15_quality / 07 — the numbers are trustworthy                    STAGE: WOA_ADMIN
-- =============================================================================
-- Implements : G3 as testing-and-validation.md defines it, plus T-86, T-87, T-94
-- Proves     : T-20, T-21, T-22 (hand-worked fixtures), T-23 (GATING: OEE identity),
--              T-24 (app = semantic view), T-25 (no constant factor), GS-5,
--              T-86 (funnel reconciles), T-87, T-94 (displayed model = recorded run)
-- Authority  : ADR-0003, docs/07-quality/testing-and-validation.md
-- Parameter  : <% database %>
--
-- ===================== HOW THE FIXTURES AVOID TESTING THEMSELVES ==============
--
-- Each fixture's EXPECTED value is worked by hand in the comment beside it,
-- and the ACTUAL value comes from the SERVING.FN_* function the live metric
-- views call. A fixture that re-implemented the formula inside the test would
-- only prove the test agrees with itself.
--
-- T-24's third path, the agent, needs a model call per run, so it is shown in
-- the evidence entry rather than gated here. The app reads the same views this
-- file reads, so app = view is by construction; the gated check is view =
-- semantic view, which is the path Cortex Analyst and the agent actually use.
-- =============================================================================

use role WOA_ADMIN;
use database <% database %>;
use warehouse WOA_BUILD_WH;

merge into OPS.DQ_ASSERTION tgt
using (
    select * from values
        ('DQ-T20-AVAILABILITY',      'T-20', 'G3', 'Contractual and technical availability match hand-worked fixtures, across a 95%->97% guarantee step',
            'An availability formula that is subtly wrong and decides whether LDs are owed', true),
        ('DQ-T21-LOST-ENERGY',       'T-21', 'G3', 'Lost energy and performance match a hand-worked wind/power fixture',
            'A power-curve calculation nobody checked', true),
        ('DQ-T22-LD',                'T-22', 'G3', 'LD exposure matches the business-case arithmetic (about Rs 2.6 lakh)',
            'An LD figure that disagrees with the pitch', true),
        ('DQ-T23-OEE-IDENTITY',      'T-23', 'G3', 'OEE equals Availability x Performance on every row, and Quality is NULL, not 1',
            'The reference solution defect: OEE drawn independently of its factors', true),
        ('DQ-T24-PATHS-AGREE',       'T-24', 'G3', 'The semantic view and the metric views give the same value for every headline metric',
            'An agent answer that disagrees with the screen', true),
        ('DQ-T25-NOT-CONSTANT',      'T-25', 'G3', 'No OEE factor is constant, and recomputation is identical',
            'A factor that is a constant, or a random value, in disguise', true),
        ('DQ-GS5-CAUGHT',            'T-25', 'G3', 'The seeded underperformers are flagged by Performance, and nothing else is',
            'A performance factor with nothing real to catch, or one that cries wolf', false),
        ('DQ-T86-NOISE-RECONCILES',  'T-86', 'G5', 'MET_NOISE reconciles to the funnel at every stage, every raw alarm is in exactly one incident, and failures-suppressed is present',
            'A funnel whose stages do not add up, or that renders without its safety number', true),
        ('DQ-T87-DISPLAYED-RUN',     'T-87', 'G2', 'The model run the app displays is the run that produced the scores on screen',
            'Held-out metrics from one model beside scores from another', false),
        ('DQ-T94-COMPARISON',        'T-94', 'G2', 'The displayed rule-vs-model comparison reconciles to the recorded evaluation run',
            'A baseline comparison that is typed, not measured', false)
    as s(id, test_id, gate, title, prevents, gating)
) src
on tgt.assertion_id = src.id
when matched then update set
    test_id = src.test_id, gate = src.gate, title = src.title,
    prevents = src.prevents, is_gating = src.gating
when not matched then insert (assertion_id, test_id, gate, title, prevents, is_gating)
    values (src.id, src.test_id, src.gate, src.title, src.prevents, src.gating);

create or replace procedure OPS.SP_RUN_NUMBERS_QUALITY()
returns varchar
language sql
execute as caller
as
$$
declare
    run_id varchar;
    bad    integer;
    n      integer;
    h1     integer;
    h2     integer;
    v      float;
    d      varchar;
    rid    varchar;
    c_model float;
    c_rule  float;
    c_failed float;
    r_model float;
    r_rule  float;
begin
    run_id := 'DQ-' || to_varchar(current_timestamp(), 'YYYYMMDDHH24MISS');

    -- T-20. Hand-worked:
    --   contractual: period 1000 h, excluded 100 h, down 45 h -> 855/900 = 95.000%
    --   technical:   same turbine, but scheduled maintenance (60 h) is turbine-caused,
    --                so excluded = 40 h (grid only), down = 45 + 60 = 105 h
    --                -> (1000-40-105)/(1000-40) = 855/960 = 89.0625%
    --   guarantee:   contract from 2024-10-01; 2026-09-30 is month 23 -> 95%;
    --                2026-10-01 is month 24 -> 97%
    select count_if(abs(actual - expected) > 1e-9),
           listagg(case when abs(actual - expected) > 1e-9 then k || '=' || actual end, ', ')
      into :bad, :d
      from (
        select 'contractual' k, SERVING.FN_AVAILABILITY_PCT(1000, 100, 45) actual, 95.0 expected
        union all select 'technical', SERVING.FN_AVAILABILITY_PCT(1000, 40, 105), 89.0625
        union all select 'guarantee_m23', SERVING.FN_GUARANTEE_PCT('2024-10-01', '2026-09-30', 95, 97), 95
        union all select 'guarantee_m24', SERVING.FN_GUARANTEE_PCT('2024-10-01', '2026-10-01', 95, 97), 97
        union all select 'no_eligible_time_is_null', coalesce(SERVING.FN_AVAILABILITY_PCT(100, 100, 0), -1), -1
      );
    insert into OPS.DQ_RESULT (run_id, assertion_id, test_id, run_at, passed, measured_value, threshold_value, detail)
    select :run_id, 'DQ-T20-AVAILABILITY', 'T-20', current_timestamp()::timestamp_ntz, :bad = 0, :bad, 0,
           '5 fixture cases (contractual 95.000, technical 89.0625, guarantee 95->97 at month 24, empty denominator); '
           || :bad || ' mismatched' || coalesce(': ' || :d, '');

    -- T-21. Hand-worked, VW-3.0 (3,000 kW; cut-in 3, rated 12, cut-out 25), 10-minute intervals:
    --   a) 7.5 m/s RUNNING, 300 kW actual: curve 3000 x (4.5/9)^3 = 375 kW
    --      -> expected 62.5 kWh, actual 50 kWh
    --   b) 12.0 m/s UNAVAILABLE: curve 3000 kW -> 500 kWh lost to downtime
    --   c) 2.0 m/s and d) 26 m/s: outside limits -> 0 kWh expected
    --   => downtime loss 500 kWh; running expected 62.5; performance 50/62.5 = 0.8
    select count_if(abs(actual - expected) > 1e-9),
           listagg(case when abs(actual - expected) > 1e-9 then k || '=' || actual end, ', ')
      into :bad, :d
      from (
        select 'curve_7.5' k, GEN.FN_EXPECTED_POWER(7.5, 3000, 3, 12, 25) actual, 375.0 expected
        union all select 'curve_2.0', GEN.FN_EXPECTED_POWER(2.0, 3000, 3, 12, 25), 0
        union all select 'curve_26',  GEN.FN_EXPECTED_POWER(26, 3000, 3, 12, 25), 0
        union all select 'running_expected_kwh', SERVING.FN_INTERVAL_KWH(GEN.FN_EXPECTED_POWER(7.5, 3000, 3, 12, 25), 10), 62.5
        union all select 'downtime_lost_kwh',    SERVING.FN_INTERVAL_KWH(GEN.FN_EXPECTED_POWER(12.0, 3000, 3, 12, 25), 10), 500
        union all select 'performance',          SERVING.FN_INTERVAL_KWH(300, 10)
                                                 / SERVING.FN_INTERVAL_KWH(GEN.FN_EXPECTED_POWER(7.5, 3000, 3, 12, 25), 10), 0.8
      );
    insert into OPS.DQ_RESULT (run_id, assertion_id, test_id, run_at, passed, measured_value, threshold_value, detail)
    select :run_id, 'DQ-T21-LOST-ENERGY', 'T-21', current_timestamp()::timestamp_ntz, :bad = 0, :bad, 0,
           '6 fixture cases (375 kW at 7.5 m/s, 0 outside limits, 62.5 kWh, 500 kWh downtime, performance 0.8); '
           || :bad || ' mismatched' || coalesce(': ' || :d, '');

    -- T-22. Business case §2.1: one VW-3.0, 720 h gearbox swap in a year, 97% guarantee,
    --   Rs 50,000 per turbine per point.
    --   availability = (8760 - 720)/8760 = 91.7808%; shortfall 5.2192 pts
    --   LD = 5.2192 x 50,000 = Rs 260,959 (the business case rounds to "about Rs 2.6 lakh")
    -- And the guarantee step on a site: 18 turbines at 96.0% owe nothing against 95%,
    --   and 1.0 x 50,000 x 18 = Rs 900,000 against 97%.
    select count_if(abs(actual - expected) > 0.5),
           listagg(case when abs(actual - expected) > 0.5 then k || '=' || actual end, ', ')
      into :bad, :d
      from (
        select 'business_case' k, SERVING.FN_LD_RUN_RATE_INR(SERVING.FN_AVAILABILITY_PCT(8760, 0, 720), 97, 50000, 1) actual,
               50000 * (97 - 100 * 8040 / 8760) expected
        union all select 'rounds_to_2.6_lakh',
               round(SERVING.FN_LD_RUN_RATE_INR(SERVING.FN_AVAILABILITY_PCT(8760, 0, 720), 97, 50000, 1) / 1e5, 1), 2.6
        union all select 'site_at_95', SERVING.FN_LD_RUN_RATE_INR(96.0, 95, 50000, 18), 0
        union all select 'site_at_97', SERVING.FN_LD_RUN_RATE_INR(96.0, 97, 50000, 18), 900000
      );
    select SERVING.FN_LD_RUN_RATE_INR(SERVING.FN_AVAILABILITY_PCT(8760, 0, 720), 97, 50000, 1) into :v;
    insert into OPS.DQ_RESULT (run_id, assertion_id, test_id, run_at, passed, measured_value, threshold_value, detail)
    select :run_id, 'DQ-T22-LD', 'T-22', current_timestamp()::timestamp_ntz, :bad = 0, :v, 260959,
           'business case Rs ' || round(:v) || ' (about 2.6 lakh); site step 0 at 95%, 900,000 at 97%; '
           || :bad || ' mismatched' || coalesce(': ' || :d, '');

    -- T-23. The identity, on every published row; and Quality is NULL, never a silent 1.
    select count_if(abs(oee - availability_factor * performance_factor) > 1e-12 or oee is null),
           count_if(quality_factor is not null), count(*)
      into :bad, :n, :h1
      from SERVING.MET_TURBINE_OEE;
    insert into OPS.DQ_RESULT (run_id, assertion_id, test_id, run_at, passed, measured_value, threshold_value, detail)
    select :run_id, 'DQ-T23-OEE-IDENTITY', 'T-23', current_timestamp()::timestamp_ntz,
           :bad = 0 and :n = 0 and :h1 > 0, :bad + :n, 0,
           :h1 || ' turbines; ' || :bad || ' where OEE <> A x P; ' || :n || ' with a Quality value (must be NULL)';

    -- T-24. Semantic view vs the metric views, for every headline metric.
    select count_if(abs(sv - direct) > 1e-6 * greatest(1, abs(direct))),
           listagg(k || ' sv=' || round(sv, 6) || ' view=' || round(direct, 6), '; ')
      into :bad, :d
      from (
        select 'mean_oee' k, sv.mean_oee sv, (select avg(oee) from SERVING.MET_TURBINE_OEE) direct
          from semantic_view(SERVING.SV_WIND_OPS metrics oee.mean_oee) sv
        union all select 'total_lost_mwh', sv.total_lost_mwh, (select sum(lost_mwh_total) from SERVING.MET_LOST_ENERGY)
          from semantic_view(SERVING.SV_WIND_OPS metrics lost.total_lost_mwh) sv
        union all select 'total_ld_inr', sv.total_ld_exposure_run_rate_inr, (select sum(ld_exposure_run_rate_inr) from SERVING.MET_LD_EXPOSURE)
          from semantic_view(SERVING.SV_WIND_OPS metrics ld.total_ld_exposure_run_rate_inr) sv
        union all select 'total_expected_loss_inr', sv.total_expected_loss_inr, (select sum(expected_loss_inr) from ENGINE.ENG_ALERT_RANKED)
          from semantic_view(SERVING.SV_WIND_OPS metrics risk.total_expected_loss_inr) sv
        union all select 'mean_availability_pct', sv.mean_turbine_availability_pct, (select avg(availability_pct) from SERVING.MET_AVAILABILITY_CONTRACTUAL)
          from semantic_view(SERVING.SV_WIND_OPS metrics availability.mean_turbine_availability_pct) sv
        union all select 'underperforming_turbines', sv.underperforming_turbines, (select count_if(is_underperforming) from SERVING.MET_TURBINE_OEE)
          from semantic_view(SERVING.SV_WIND_OPS metrics oee.underperforming_turbines) sv
      );
    insert into OPS.DQ_RESULT (run_id, assertion_id, test_id, run_at, passed, measured_value, threshold_value, detail)
    select :run_id, 'DQ-T24-PATHS-AGREE', 'T-24', current_timestamp()::timestamp_ntz, :bad = 0, :bad, 0,
           '6 metrics, semantic view vs view; ' || :bad || ' disagree. ' || :d;

    -- T-25. Each factor varies across turbines, and recomputing gives the same
    -- answer with the result cache off (so the second read is a real recompute).
    select count_if(s = 0), listagg(k || '=' || s, ', ') into :bad, :d from (
        select 'availability' k, variance(availability_factor) s from SERVING.MET_TURBINE_OEE
        union all select 'performance', variance(performance_factor) from SERVING.MET_TURBINE_OEE
        union all select 'oee', variance(oee) from SERVING.MET_TURBINE_OEE);
    alter session set use_cached_result = false;
    select hash_agg(turbine_id, availability_factor, performance_factor, oee) into :h1 from SERVING.MET_TURBINE_OEE;
    select hash_agg(turbine_id, availability_factor, performance_factor, oee) into :h2 from SERVING.MET_TURBINE_OEE;
    alter session set use_cached_result = true;
    insert into OPS.DQ_RESULT (run_id, assertion_id, test_id, run_at, passed, measured_value, threshold_value, detail)
    select :run_id, 'DQ-T25-NOT-CONSTANT', 'T-25', current_timestamp()::timestamp_ntz, :bad = 0 and :h1 = :h2,
           :bad + iff(:h1 = :h2, 0, 1), 0,
           'variances: ' || :d || '; recompute identical: ' || (:h1 = :h2)::varchar;

    -- GS-5: flagged set == seeded set, exactly.
    select count(*), count_if(o.turbine_id is null or s.turbine_id is null),
           listagg(coalesce(o.turbine_id, s.turbine_id) || iff(s.turbine_id is null, ' (flagged, not seeded)',
                   iff(o.turbine_id is null, ' (seeded, missed)', '')), ', ')
      into :n, :bad, :d
      from (select turbine_id from SERVING.MET_TURBINE_OEE where is_underperforming) o
      full outer join (select turbine_id from GEN.GEN_SEEDED_PATTERN where pattern_type = 'UNDERPERFORMANCE') s
        on s.turbine_id = o.turbine_id;
    insert into OPS.DQ_RESULT (run_id, assertion_id, test_id, run_at, passed, measured_value, threshold_value, detail)
    select :run_id, 'DQ-GS5-CAUGHT', 'T-25', current_timestamp()::timestamp_ntz, :bad = 0 and :n > 0, :bad, 0,
           :n || ' turbines flagged or seeded; ' || :bad || ' mismatched: ' || coalesce(:d, 'none');

    -- T-86: every stage, and the conservation check (each alarm in exactly one incident).
    select (n.raw_alarms <> f.raw_alarms)::int + (n.raw_alarms <> n.alarms_in_incidents)::int
           + (n.incidents <> f.incidents)::int + (n.actionable <> f.actionable)::int
           + (n.undetermined <> f.undetermined)::int + (n.nuisance <> f.nuisance)::int
           + (n.actionable + n.undetermined + n.nuisance <> n.incidents)::int
           + (n.real_failures_suppressed is null)::int + (n.real_failures_suppressed <> f.real_failures_suppressed)::int,
           n.raw_alarms || ' alarms = ' || n.alarms_in_incidents || ' in ' || n.incidents || ' incidents ('
           || n.actionable || ' actionable, ' || n.undetermined || ' undetermined, ' || n.nuisance
           || ' nuisance); real failures suppressed ' || n.real_failures_suppressed
      into :bad, :d
      from SERVING.MET_NOISE n, ENGINE.ENG_ALARM_FUNNEL f;
    insert into OPS.DQ_RESULT (run_id, assertion_id, test_id, run_at, passed, measured_value, threshold_value, detail)
    select :run_id, 'DQ-T86-NOISE-RECONCILES', 'T-86', current_timestamp()::timestamp_ntz, :bad = 0, :bad, 0,
           :bad || ' stage mismatches. ' || :d;

    -- T-87: the app shows the latest RISK_CLASSIFIER run; the scores must come from it.
    select count(distinct model_version), max(model_version)
      into :n, :d
      from ML.SCORE_COMPONENT_RISK;
    select max(run_id) into :rid from OPS.ML_RUN where model_name = 'RISK_CLASSIFIER';
    select count(*) into :bad from ML.SCORE_COMPONENT_RISK where model_version <> :rid;
    insert into OPS.DQ_RESULT (run_id, assertion_id, test_id, run_at, passed, measured_value, threshold_value, detail)
    select :run_id, 'DQ-T87-DISPLAYED-RUN', 'T-87', current_timestamp()::timestamp_ntz, :n = 1 and :bad = 0, :bad, 0,
           'scores from ' || :n || ' model version(s) (' || coalesce(:d, 'none') || '); app displays run '
           || coalesce(:rid, 'none') || '; ' || :bad || ' scores from another run';

    -- T-94: the comparison figures are consistent with the per-method metrics of
    -- the same run: caught = recall x failed-in-hold-out, for the model and the rule.
    -- (SELECT ... INTO cannot follow a WITH clause in Snowflake Scripting, so the
    -- run id is fetched first.)
    select max(run_id) into :rid from OPS.ML_RUN where model_name = 'RISK_CLASSIFIER';
    select max(iff(metric_scope = 'COMPARISON' and metric_name = 'components_caught_by_model', metric_value, null)),
           max(iff(metric_scope = 'COMPARISON' and metric_name = 'components_caught_by_rule', metric_value, null)),
           max(iff(metric_scope = 'COMPARISON' and metric_name = 'failed_components_in_holdout', metric_value, null)),
           max(iff(metric_scope = 'MODEL' and metric_name = 'recall_components', metric_value, null)),
           max(iff(metric_scope = 'BL-TRIVIAL-THRESHOLD' and metric_name = 'recall_components', metric_value, null))
      into :c_model, :c_rule, :c_failed, :r_model, :r_rule
      from OPS.ML_METRIC where run_id = :rid;
    bad := iff(c_model is null or c_model <> round(r_model * c_failed), 1, 0)
         + iff(c_rule  is null or c_rule  <> round(r_rule  * c_failed), 1, 0);
    d := 'run ' || coalesce(rid, 'none') || ': caught by model ' || coalesce(c_model::int::varchar, 'null')
         || ', by rule ' || coalesce(c_rule::int::varchar, 'null') || ', of '
         || coalesce(c_failed::int::varchar, 'null') || ' failed in hold-out';
    insert into OPS.DQ_RESULT (run_id, assertion_id, test_id, run_at, passed, measured_value, threshold_value, detail)
    select :run_id, 'DQ-T94-COMPARISON', 'T-94', current_timestamp()::timestamp_ntz, :bad = 0, :bad, 0,
           :bad || ' inconsistent figures. ' || coalesce(:d, 'no comparison recorded');

    return 'Numbers quality run ' || :run_id || ' complete';
end;
$$;
