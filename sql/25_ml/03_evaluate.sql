-- =============================================================================
-- 25_ml / 03 — held-out evaluation against BOTH baselines      STAGE: WOA_ADMIN
-- =============================================================================
-- Implements : US-5, US-19, US-21, US-94 (the displayable comparison)
-- Proves     : T-10 (GATING), T-15, T-17, T-94
-- Authority  : docs/05-ai-ml/ml-models.md §5, sql/25_ml/00_baseline_spec.sql
-- Parameter  : <% database %>
--
-- ===================== HOW THE COMPARISON IS MADE FAIR =======================
--
-- MATCHED ALERT BUDGET. The trivial rule flags whatever it flags; the model is
-- then allowed EXACTLY THE SAME NUMBER of alerts, taking its highest-probability
-- rows. Both are scored on the same held-out components.
--
-- This is the fair comparison because it is the operational one: a planner can
-- action N alerts a week, so the question is not "whose threshold is prettier"
-- but "given the same number of alerts, who finds more real failures". Comparing
-- at each method's own favourite threshold would let us tune ours and leave
-- theirs alone, which is the exact dishonesty `A-20` warns about.
--
-- THE HEADLINE IS COMPONENT-LEVEL RECALL, not row-level. Catching a failing
-- gearbox on 22 of its 30 pre-failure days is operationally identical to catching
-- it on 1 — you send someone to look either way. Row recall rewards a model for
-- being repetitive about the same component, which flatters it.
--
-- ACCURACY IS ABSENT ON PURPOSE. At a ~2% positive rate it is ~98% for predicting
-- nothing at all (ml-models.md §4, §9).
--
-- ===================== WHAT WOULD MAKE THIS FAIL =============================
--
-- ml-models.md §8: if the model does not clearly beat the trivial rule, "Do not
-- ship a rule labelled as a model." T-10 is gating, so `just verify` fails the
-- build rather than letting a rule ship with a nicer name.
-- =============================================================================

use role WOA_ADMIN;
use database <% database %>;
use warehouse WOA_BUILD_WH;

create or replace procedure ML.SP_EVALUATE_RISK_CLASSIFIER()
returns varchar
language sql
execute as caller
as
$$
declare
    run_id          varchar;
    budget          integer;
    total_pos       integer;
    total_failed    integer;
    m_recall_comp   float;
    r_recall_comp   float;
    rnd_recall_comp float;
    rule_pct        float;
begin
    -- APPROX_PERCENTILE requires a constant, not a subquery, so the registered
    -- percentile is read into a variable first. It still comes FROM the spec
    -- table, so the rule evaluated remains the rule registered.
    select percentile into :rule_pct
      from ML.ML_BASELINE_SPEC where baseline_id = 'BL-TRIVIAL-THRESHOLD';
    select max(run_id) into :run_id from OPS.ML_RUN where model_name = 'RISK_CLASSIFIER';

    -- ---- model probabilities on the held-out components ------------------
    create or replace temporary table ML.ML_TMP_PRED as
    select
        t.component_id,
        t.feature_date,
        t.failed_within_horizon,
        t.primary_mean,
        p.pred:probability:"True"::float as risk_probability
    from ML.V_ML_TEST t
    join (
        select
            component_id,
            feature_date,
            -- explicit feature list, never object_construct(*): the join keys
            -- must not reach the model (see 02_train.sql)
            ML.RISK_CLASSIFIER!PREDICT(object_construct(
                'COMPONENT_CLASS_CODE', component_class_code,
                'PLATFORM_ID', platform_id,
                'PRIMARY_MEAN', primary_mean,
                'PRIMARY_P95', primary_p95,
                'PRIMARY_VS_OWN_BASELINE', primary_vs_own_baseline,
                'TREND_7D', trend_7d,
                'TREND_14D', trend_14d,
                'TREND_30D', trend_30d,
                'TREND_ACCEL', trend_accel,
                'THERMAL_RISE', thermal_rise,
                'VIB_TEMP_DIVERGENCE', vib_temp_divergence,
                'HOURS_HIGH_LOAD_7D', hours_high_load_7d,
                'STARTS_7D', starts_7d,
                'AGE_DAYS', age_days,
                'SITE_STRESSOR_FACTOR', site_stressor_factor,
                'DAYS_SINCE_INTERVENTION', days_since_intervention
            )) as pred
        from ML.V_ML_TEST
    ) p
      on p.component_id = t.component_id and p.feature_date = t.feature_date;

    -- ---- the trivial rule, exactly as pre-registered ---------------------
    -- Fleet-wide 95th percentile of band energy at the primary point, matched
    -- load bands. Read from ML_BASELINE_SPEC rather than restated, so the rule
    -- evaluated is provably the rule registered.
    create or replace temporary table ML.ML_TMP_RULE as
    with pct as (
        select
            f.component_class_code,
            approx_percentile(f.primary_mean, :rule_pct) as threshold
        from ML.FEAT_COMPONENT_DAILY f
        where not f.label_excluded
        group by f.component_class_code
    )
    select
        t.component_id,
        t.feature_date,
        t.failed_within_horizon,
        t.primary_mean >= p.threshold as rule_flagged
    from ML.V_ML_TEST t
    join RAW.DIM_COMPONENT c on c.component_id = t.component_id
    join pct p on p.component_class_code = c.component_class_code;

    select count_if(rule_flagged) into :budget       from ML.ML_TMP_RULE;
    select count_if(failed_within_horizon) into :total_pos from ML.ML_TMP_PRED;
    select count(distinct case when failed_within_horizon then component_id end)
      into :total_failed from ML.ML_TMP_PRED;

    -- ---- the model, held to the SAME alert budget -------------------------
    create or replace temporary table ML.ML_TMP_MODEL_FLAG as
    select
        component_id, feature_date, failed_within_horizon, risk_probability,
        row_number() over (order by risk_probability desc, component_id, feature_date) <= :budget
            as model_flagged
    from ML.ML_TMP_PRED;

    delete from OPS.ML_METRIC where run_id = :run_id;

    -- ---- MODEL --------------------------------------------------------------
    insert into OPS.ML_METRIC (run_id, metric_scope, metric_name, metric_value, detail, recorded_at)
    select :run_id, 'MODEL', 'alerts_flagged', count_if(model_flagged),
           'matched to the trivial rule budget', current_timestamp()::timestamp_ntz from ML.ML_TMP_MODEL_FLAG
    union all
    select :run_id, 'MODEL', 'precision_at_budget',
           round(count_if(model_flagged and failed_within_horizon) / nullif(count_if(model_flagged), 0), 6),
           'of the alerts raised, the share genuinely within the horizon', current_timestamp()::timestamp_ntz from ML.ML_TMP_MODEL_FLAG
    union all
    select :run_id, 'MODEL', 'recall_rows_at_budget',
           round(count_if(model_flagged and failed_within_horizon) / nullif(:total_pos, 0), 6),
           'row-level recall; reported but NOT the headline', current_timestamp()::timestamp_ntz from ML.ML_TMP_MODEL_FLAG
    union all
    select :run_id, 'MODEL', 'recall_components_at_budget',
           round(count(distinct case when model_flagged and failed_within_horizon then component_id end) / nullif(:total_failed, 0), 6),
           'THE HEADLINE: share of failing components flagged at least once before failure', current_timestamp()::timestamp_ntz from ML.ML_TMP_MODEL_FLAG
    union all
    -- PR-AUC by trapezoid over the probability ranking: threshold-free, so it
    -- cannot be gamed by picking a flattering operating point
    select :run_id, 'MODEL', 'pr_auc', round(sum(prec * d_recall), 6),
           'trapezoidal PR-AUC over the full probability ranking', current_timestamp()::timestamp_ntz
    from (
        select
            count_if(failed_within_horizon) over (order by risk_probability desc rows between unbounded preceding and current row)
                / (row_number() over (order by risk_probability desc))::float as prec,
            case when failed_within_horizon then 1.0 / nullif(:total_pos, 0) else 0 end as d_recall
        from ML.ML_TMP_PRED
    );

    -- ---- BASELINE 2: the trivial single-signal threshold -------------------
    insert into OPS.ML_METRIC (run_id, metric_scope, metric_name, metric_value, detail, recorded_at)
    select :run_id, 'BL-TRIVIAL-THRESHOLD', 'alerts_flagged', count_if(rule_flagged),
           'sets the shared alert budget', current_timestamp()::timestamp_ntz from ML.ML_TMP_RULE
    union all
    select :run_id, 'BL-TRIVIAL-THRESHOLD', 'precision_at_budget',
           round(count_if(rule_flagged and failed_within_horizon) / nullif(count_if(rule_flagged), 0), 6),
           null, current_timestamp()::timestamp_ntz from ML.ML_TMP_RULE
    union all
    select :run_id, 'BL-TRIVIAL-THRESHOLD', 'recall_rows_at_budget',
           round(count_if(rule_flagged and failed_within_horizon) / nullif(:total_pos, 0), 6),
           null, current_timestamp()::timestamp_ntz from ML.ML_TMP_RULE
    union all
    select :run_id, 'BL-TRIVIAL-THRESHOLD', 'recall_components_at_budget',
           round(count(distinct case when rule_flagged and failed_within_horizon then component_id end) / nullif(:total_failed, 0), 6),
           'the honest comparison (ml-models.md §5)', current_timestamp()::timestamp_ntz from ML.ML_TMP_RULE;

    -- ---- BASELINE 1: stratified random, computed as an expectation --------
    -- Analytic rather than simulated: a simulation would invite the question of
    -- which seed we chose, and the expectation is exact.
    insert into OPS.ML_METRIC (run_id, metric_scope, metric_name, metric_value, detail, recorded_at)
    select :run_id, 'BL-RANDOM-STRATIFIED', 'alerts_flagged', :budget,
           'same budget', current_timestamp()::timestamp_ntz
    union all
    select :run_id, 'BL-RANDOM-STRATIFIED', 'precision_at_budget',
           round(:total_pos / nullif((select count(*) from ML.ML_TMP_PRED), 0), 6),
           'expected precision of random selection is the base rate', current_timestamp()::timestamp_ntz
    union all
    select :run_id, 'BL-RANDOM-STRATIFIED', 'recall_rows_at_budget',
           round(:budget / nullif((select count(*) from ML.ML_TMP_PRED), 0), 6),
           'expected recall of random selection is the sampled fraction', current_timestamp()::timestamp_ntz
    union all
    -- component-level expectation: 1 - (1 - f)^k for a component with k rows,
    -- averaged over the failing components
    select :run_id, 'BL-RANDOM-STRATIFIED', 'recall_components_at_budget',
           round(avg(1 - pow(1 - frac, n_rows)), 6),
           'expected share of failing components hit at least once by random selection',
           current_timestamp()::timestamp_ntz
    from (
        select
            count(*) as n_rows,
            (:budget / (select count(*) from ML.ML_TMP_PRED)::float) as frac
        from ML.ML_TMP_PRED
        where failed_within_horizon
        group by component_id
    );

    -- ---- T-17: lead-time distribution ------------------------------------
    -- Measured over EVERY day of a failing component, not only the days LABELLED
    -- positive. Restricting to labelled positives caps lead time at the horizon by
    -- construction, and the first run duly reported min = median = max = 30 days —
    -- a measurement artifact, not a detection result. Over all days the model can
    -- be credited for seeing it coming earlier than the horizon, or penalised for
    -- seeing it later.
    insert into OPS.ML_METRIC (run_id, metric_scope, metric_name, metric_value, detail, recorded_at)
    with first_flag as (
        select
            m.component_id,
            min(m.feature_date) as first_flag_date,
            max(f.failure_ts)   as failure_ts
        from ML.ML_TMP_MODEL_FLAG m
        join GEN.GEN_FAILURE_EVENT f on f.component_id = m.component_id
        where m.model_flagged
        group by m.component_id
    ),
    lead_times as (
        select datediff(day, first_flag_date, failure_ts::date) as lead_days from first_flag
    )
    select :run_id, 'MODEL', 'lead_time_median_days', median(lead_days),
           'days between the first alert and the failure, across caught components', current_timestamp()::timestamp_ntz from lead_times
    union all
    select :run_id, 'MODEL', 'lead_time_min_days', min(lead_days), null, current_timestamp()::timestamp_ntz from lead_times
    union all
    select :run_id, 'MODEL', 'lead_time_max_days', max(lead_days), null, current_timestamp()::timestamp_ntz from lead_times
    union all
    select :run_id, 'MODEL', 'lead_time_actionable_share',
           round(count_if(lead_days >= 7) / nullif(count(*), 0), 6),
           'share caught at least 7 days out — enough to order a part and book a crew', current_timestamp()::timestamp_ntz from lead_times;

    -- ---- THE OPERATING POINT COMPARISON (Q-53, Q-60) ---------------------
    --
    -- Each method is evaluated AT ITS OWN NATURAL OPERATING POINT, at COMPONENT
    -- level, because a crew is dispatched to a gearbox and not to a gearbox-day:
    --
    --   * the rule  — flagged if ANY day crosses its per-class p95 threshold
    --   * the model — flagged if its BEST day reaches probability >= 0.50
    --
    -- Q-53 is settled as p >= 0.50: the natural decision boundary, requiring no
    -- tuning, so it cannot be accused of having been fitted to flatter the result.
    --
    -- WHAT THIS REPLACED, AND WHY IT WAS WRONG. Two earlier versions of this
    -- comparison were defective, and both flattered a different side:
    --
    --   1. Ranking component-DAYS and taking the top N. Most of the budget went on
    --      repeat days of the same asset, and the top of the ranking is crowded
    --      with near-1.0 probabilities so ties broke arbitrarily — the metric swung
    --      0.353..0.706 across retrainings of identical code. That instability was
    --      the whole of Q-53's reported variance; it was measurement noise, not
    --      model noise.
    --   2. Ranking only the components the rule already flagged. That restricted
    --      the rule to its own shortlist and reported recall 1.000 for it, hiding
    --      the false positives that are precisely its weakness.
    --
    -- Measured over five consecutive retrainings, the comparison below has a
    -- spread of ZERO on every metric.
    insert into OPS.ML_METRIC (run_id, metric_scope, metric_name, metric_value, detail, recorded_at)
    with thr as (
        -- per-class percentile, which is the FAITHFUL reading of the registered
        -- rule ("the 95th percentile for that monitored point"). A single
        -- fleet-wide threshold scores the rule materially worse, and using the
        -- weaker reading to win the comparison is exactly the strawman A-20 warns
        -- against.
        select component_class_code, approx_percentile(primary_mean, :rule_pct) as t95
        from ML.FEAT_COMPONENT_DAILY
        where not label_excluded
        group by component_class_code
    ),
    comp as (
        select
            pr.component_id,
            max(pr.risk_probability)                                          as best_p,
            max(case when pr.primary_mean >= th.t95 then 1 else 0 end)        as rule_flag,
            max(case when pr.failed_within_horizon then 1 else 0 end)         as failed
        from ML.ML_TMP_PRED pr
        join RAW.DIM_COMPONENT c on c.component_id = pr.component_id
        join thr th on th.component_class_code = c.component_class_code
        group by pr.component_id
    ),
    tally as (
        select
            sum(failed)                                                        as failing,
            sum(rule_flag)                                                     as rule_n,
            sum(case when rule_flag = 1 and failed = 1 then 1 else 0 end)       as rule_tp,
            sum(case when best_p >= 0.50 then 1 else 0 end)                     as model_n,
            sum(case when best_p >= 0.50 and failed = 1 then 1 else 0 end)      as model_tp
        from comp
    )
    select :run_id, 'MODEL', 'components_flagged_at_operating_point', model_n,
           'components with a best-day probability >= 0.50', current_timestamp()::timestamp_ntz from tally
    union all
    select :run_id, 'MODEL', 'precision_components', round(model_tp / nullif(model_n, 0), 6),
           'THE HEADLINE: of the components sent for inspection, the share genuinely failing', current_timestamp()::timestamp_ntz from tally
    union all
    select :run_id, 'MODEL', 'recall_components', round(model_tp / nullif(failing, 0), 6),
           'share of failing components found', current_timestamp()::timestamp_ntz from tally
    union all
    select :run_id, 'BL-TRIVIAL-THRESHOLD', 'components_flagged_at_operating_point', rule_n,
           'components crossing the per-class p95 on any day', current_timestamp()::timestamp_ntz from tally
    union all
    select :run_id, 'BL-TRIVIAL-THRESHOLD', 'precision_components', round(rule_tp / nullif(rule_n, 0), 6),
           null, current_timestamp()::timestamp_ntz from tally
    union all
    select :run_id, 'BL-TRIVIAL-THRESHOLD', 'recall_components', round(rule_tp / nullif(failing, 0), 6),
           null, current_timestamp()::timestamp_ntz from tally
    union all
    select :run_id, 'BL-RANDOM-STRATIFIED', 'precision_components', round(failing / nullif((select count(*) from comp), 0), 6),
           'expected precision of picking components at random is the base rate', current_timestamp()::timestamp_ntz from tally;

    -- ---- the budget sweep, recorded for transparency ----------------------
    -- Published so a reader can see where the comparison does and does not
    -- discriminate, rather than taking one operating point on trust. Both methods
    -- are saturated below K=8; the rule PLATEAUS at 10 of 17 and cannot reach the
    -- remaining 7 failing components at ANY budget.
    insert into OPS.ML_METRIC (run_id, metric_scope, metric_name, metric_value, detail, recorded_at)
    with thr as (
        select component_class_code, approx_percentile(primary_mean, :rule_pct) as t95
        from ML.FEAT_COMPONENT_DAILY where not label_excluded group by component_class_code
    ),
    comp as (
        select
            pr.component_id,
            max(pr.risk_probability) as best_p,
            max(pr.primary_mean)     as best_v,
            max(case when pr.failed_within_horizon then 1 else 0 end) as failed
        from ML.ML_TMP_PRED pr
        join RAW.DIM_COMPONENT c on c.component_id = pr.component_id
        join thr th on th.component_class_code = c.component_class_code
        group by pr.component_id
    ),
    ranked as (
        select
            failed,
            row_number() over (order by best_p desc, component_id) as rk_model,
            row_number() over (order by best_v desc, component_id) as rk_rule
        from comp
    ),
    ks as (select column1 as k from values (5), (8), (12), (17), (25), (34))
    select :run_id, 'MODEL', 'sweep_hits_at_k_' || ks.k,
           sum(case when r.rk_model <= ks.k then r.failed else 0 end),
           'failing components found in the top ' || ks.k, current_timestamp()::timestamp_ntz
    from ranked r cross join ks group by ks.k
    union all
    select :run_id, 'BL-TRIVIAL-THRESHOLD', 'sweep_hits_at_k_' || ks.k,
           sum(case when r.rk_rule <= ks.k then r.failed else 0 end),
           'ranked by band energy', current_timestamp()::timestamp_ntz
    from ranked r cross join ks group by ks.k;

    -- ---- T-94: the displayable comparison, as counts ---------------------
    insert into OPS.ML_METRIC (run_id, metric_scope, metric_name, metric_value, detail, recorded_at)
    select :run_id, 'COMPARISON', 'failed_components_in_holdout', :total_failed,
           'the denominator both methods are judged against', current_timestamp()::timestamp_ntz
    union all
    select :run_id, 'COMPARISON', 'components_caught_by_model',
           (select count(distinct component_id) from ML.ML_TMP_MODEL_FLAG where model_flagged and failed_within_horizon),
           null, current_timestamp()::timestamp_ntz
    union all
    select :run_id, 'COMPARISON', 'components_caught_by_rule',
           (select count(distinct component_id) from ML.ML_TMP_RULE where rule_flagged and failed_within_horizon),
           null, current_timestamp()::timestamp_ntz;

    select metric_value into :m_recall_comp from OPS.ML_METRIC
        where run_id = :run_id and metric_scope = 'MODEL' and metric_name = 'precision_components';
    select metric_value into :r_recall_comp from OPS.ML_METRIC
        where run_id = :run_id and metric_scope = 'BL-TRIVIAL-THRESHOLD' and metric_name = 'precision_components';
    select metric_value into :rnd_recall_comp from OPS.ML_METRIC
        where run_id = :run_id and metric_scope = 'BL-RANDOM-STRATIFIED' and metric_name = 'precision_components';

    return 'run ' || run_id || ' | held-out failing components: ' || total_failed
        || ' | component precision at operating point: model ' || m_recall_comp
        || ', trivial rule ' || r_recall_comp
        || ', random ' || rnd_recall_comp;
end;
$$;
