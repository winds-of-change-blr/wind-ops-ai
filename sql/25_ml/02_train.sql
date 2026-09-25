-- =============================================================================
-- 25_ml / 02 — split, train, and record the run                STAGE: WOA_ADMIN
-- =============================================================================
-- Implements : US-19 (trained risk classifier with an explicit horizon)
-- Proves     : T-14, T-15, T-19 · prerequisite for T-10
-- Authority  : docs/05-ai-ml/ml-models.md §5, ADR-0007, ADR-0014
-- Parameter  : <% database %>
--
-- ===================== THE SPLIT IS THE WHOLE BALLGAME ========================
--
-- SPLIT BY COMPONENT INSTANCE, NEVER BY ROW.
--
-- ml-models.md §5: "Random row splits leak: adjacent days from one degradation
-- ramp land in both train and test, and the model appears excellent while having
-- learned nothing generalisable."
--
-- A component's 30 positive days are 30 adjacent points on ONE ramp. Split them
-- randomly and the model memorises that ramp, then is tested on it. The reported
-- number would be excellent and worthless. Here a component lands ENTIRELY in
-- train or ENTIRELY in test, so no ramp is ever seen from both sides.
--
-- The split is a deterministic hash of the component id, so it is stable across
-- re-runs — the same component is always on the same side, which is what makes
-- T-19 (same inputs, same score) achievable at all.
--
-- ml-models.md §8 also tells us how to read a surprise: "Treat a suspiciously
-- good result as a bug." With ~42 in-scope failures, a near-perfect score is far
-- more likely to be leakage than skill.
--
-- ===================== WHAT WE DO NOT MEASURE ================================
--
-- ACCURACY IS NOT REPORTED. At a ~2% positive rate, predicting "no failure" for
-- everything scores ~98%. ml-models.md §4 and §9 both rule it out, and quoting it
-- would be the single most misleading number available to us.
-- =============================================================================

use role WOA_ADMIN;
use database <% database %>;
use warehouse WOA_BUILD_WH;

-- ---------------------------------------------------------------------------
-- The split, as views so training and evaluation cannot disagree about it.
-- ---------------------------------------------------------------------------
create or replace view ML.V_ML_SPLIT as
select
    f.*,
    case
        when GEN.FN_RAND(f.component_id, 'VWS-2026split') < 0.70 then 'TRAIN'
        else 'TEST'
    end as split_group
from ML.FEAT_COMPONENT_DAILY f
-- days between failure and repair are not in service, so a prediction about them
-- is meaningless (ml-models.md §4)
where not f.label_excluded;

-- ============================ NO IDENTIFIERS ================================
--
-- COMPONENT_ID IS NOT A FEATURE, and neither is PRIMARY_CHANNEL (which is a
-- deterministic function of the class).
--
-- The first cut of this view passed COMPONENT_ID through, which handed the model
-- a 400-value categorical key it could memorise — "health as a function of
-- primary key", the reference solution's defect and the exact thing T-9 exists to
-- forbid. With a component-disjoint split the memorised ids would be useless at
-- test time, so it would have shown up as weak generalisation rather than a
-- flattering score; but it also broke SHOW_FEATURE_IMPORTANCE outright, which is
-- how it was caught. Identifiers stay out.
create or replace view ML.V_ML_TRAIN as
select
    component_class_code, platform_id,
    coalesce(primary_mean, 0)            as primary_mean,
    coalesce(primary_p95, 0)             as primary_p95,
    coalesce(primary_vs_own_baseline, 0) as primary_vs_own_baseline,
    coalesce(trend_7d, 0)                as trend_7d,
    coalesce(trend_14d, 0)               as trend_14d,
    coalesce(trend_30d, 0)               as trend_30d,
    coalesce(trend_accel, 0)             as trend_accel,
    coalesce(thermal_rise, 0)            as thermal_rise,
    coalesce(vib_temp_divergence, 0)     as vib_temp_divergence,
    coalesce(hours_high_load_7d, 0)      as hours_high_load_7d,
    coalesce(starts_7d, 0)               as starts_7d,
    age_days,
    coalesce(site_stressor_factor, 1)    as site_stressor_factor,
    coalesce(days_since_intervention, 0) as days_since_intervention,
    failed_within_horizon
from ML.V_ML_SPLIT
where split_group = 'TRAIN';

-- COMPONENT_ID and FEATURE_DATE are carried here as JOIN KEYS ONLY. Every
-- PREDICT call constructs its input object from the feature columns explicitly,
-- never with object_construct(*), so the keys cannot leak into the model.
create or replace view ML.V_ML_TEST as
select
    component_id, feature_date, component_class_code, platform_id,
    coalesce(primary_mean, 0)            as primary_mean,
    coalesce(primary_p95, 0)             as primary_p95,
    coalesce(primary_vs_own_baseline, 0) as primary_vs_own_baseline,
    coalesce(trend_7d, 0)                as trend_7d,
    coalesce(trend_14d, 0)               as trend_14d,
    coalesce(trend_30d, 0)               as trend_30d,
    coalesce(trend_accel, 0)             as trend_accel,
    coalesce(thermal_rise, 0)            as thermal_rise,
    coalesce(vib_temp_divergence, 0)     as vib_temp_divergence,
    coalesce(hours_high_load_7d, 0)      as hours_high_load_7d,
    coalesce(starts_7d, 0)               as starts_7d,
    age_days,
    coalesce(site_stressor_factor, 1)    as site_stressor_factor,
    coalesce(days_since_intervention, 0) as days_since_intervention,
    failed_within_horizon
from ML.V_ML_SPLIT
where split_group = 'TEST';

-- ---------------------------------------------------------------------------
-- OPS.ML_RUN / OPS.ML_METRIC — every run recorded, with its metrics (T-15).
--
-- The UI must display the held-out metric for the model version that produced
-- the score on screen (T-87), so the run id is the join key between a score and
-- the evaluation that justifies it. A metric that lives only in a log cannot
-- satisfy that.
-- ---------------------------------------------------------------------------
create table if not exists OPS.ML_RUN (
    run_id            varchar(40)   not null,
    model_name        varchar(100)  not null,
    model_version     varchar(40)   not null,
    trained_at        timestamp_ntz not null,
    horizon_days      integer       not null,
    scope_classes     varchar(200)  not null,
    split_rule        varchar(500)  not null,
    train_rows        integer,
    test_rows         integer,
    train_positives   integer,
    test_positives    integer,
    test_failed_components integer,
    notes             varchar(1000),
    is_synthetic      boolean       not null default true,
    constraint pk_ml_run primary key (run_id)
);

create table if not exists OPS.ML_METRIC (
    run_id        varchar(40)   not null,
    metric_scope  varchar(40)   not null,   -- MODEL | BL-RANDOM-STRATIFIED | BL-TRIVIAL-THRESHOLD
    metric_name   varchar(60)   not null,
    metric_value  number(20,6),
    detail        varchar(1000),
    recorded_at   timestamp_ntz not null,
    is_synthetic  boolean       not null default true
);

-- ---------------------------------------------------------------------------
-- SP_TRAIN_RISK_CLASSIFIER — train, and record what was trained on.
--
-- ADR-0007 chose SNOWFLAKE.ML.CLASSIFICATION: natively explainable through
-- feature importance, no extra infrastructure, and it never moves the data out of
-- the account. ADR-0014 chose ONE model with component class as a feature rather
-- than four per-class models.
-- ---------------------------------------------------------------------------
create or replace procedure ML.SP_TRAIN_RISK_CLASSIFIER(
    horizon_days integer
)
returns varchar
language sql
execute as caller
as
$$
declare
    run_id      varchar;
    n_train     integer;
    n_test      integer;
    n_train_pos integer;
    n_test_pos  integer;
    n_test_comp integer;
begin
    run_id := 'MLRUN-' || to_varchar(current_timestamp(), 'YYYYMMDDHH24MISS');

    select count(*), count_if(failed_within_horizon)
      into :n_train, :n_train_pos from ML.V_ML_TRAIN;
    select count(*), count_if(failed_within_horizon),
           count(distinct case when failed_within_horizon then component_id end)
      into :n_test, :n_test_pos, :n_test_comp from ML.V_ML_TEST;

    -- Fail loudly rather than train on nothing. A model trained on zero positives
    -- would still "succeed" and produce a scoring table full of zeros.
    if (n_train_pos < 20 or n_test_pos < 20) then
        return 'REFUSING TO TRAIN: too few positives (train=' || n_train_pos
            || ', test=' || n_test_pos || '). Raise the failure rate in the generator '
            || '(data-sources §3: raise the rate, not the window).';
    end if;

    create or replace snowflake.ml.classification ML.RISK_CLASSIFIER(
        input_data      => system$reference('view', 'ML.V_ML_TRAIN'),
        target_colname  => 'FAILED_WITHIN_HORIZON',
        config_object   => { 'evaluate': true, 'on_error': 'skip' }
    );

    merge into OPS.ML_RUN tgt
    using (
        select
            :run_id        as run_id,
            'RISK_CLASSIFIER' as model_name,
            :run_id        as model_version,
            current_timestamp()::timestamp_ntz as trained_at,
            :horizon_days  as horizon_days,
            'GBX, GEN, MSB, PIT (ADR-0014)' as scope_classes,
            'Component-instance disjoint, deterministic hash FN_RAND(component_id, VWS-2026split) < 0.70 -> TRAIN. No component appears on both sides, so no degradation ramp is seen from both.' as split_rule,
            :n_train as train_rows, :n_test as test_rows,
            :n_train_pos as train_positives, :n_test_pos as test_positives,
            :n_test_comp as test_failed_components,
            'SNOWFLAKE.ML.CLASSIFICATION. Accuracy deliberately not recorded: at a ~2% positive rate it is ~98% for predicting nothing.' as notes
    ) src
    on tgt.run_id = src.run_id
    when not matched then insert (
        run_id, model_name, model_version, trained_at, horizon_days, scope_classes,
        split_rule, train_rows, test_rows, train_positives, test_positives,
        test_failed_components, notes
    ) values (
        src.run_id, src.model_name, src.model_version, src.trained_at,
        src.horizon_days, src.scope_classes, src.split_rule, src.train_rows,
        src.test_rows, src.train_positives, src.test_positives,
        src.test_failed_components, src.notes
    );

    return 'RISK_CLASSIFIER trained as run ' || run_id
        || ' — train ' || n_train || ' rows / ' || n_train_pos || ' positive; '
        || 'held-out ' || n_test || ' rows / ' || n_test_pos || ' positive across '
        || n_test_comp || ' failed components';
end;
$$;
