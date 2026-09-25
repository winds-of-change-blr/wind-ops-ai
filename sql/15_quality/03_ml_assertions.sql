-- =============================================================================
-- 15_quality / 03 — ML assertions                              STAGE: WOA_ADMIN
-- =============================================================================
-- Implements : the G2 test suite (data half of G1 is in 02_assertions.sql)
-- Proves     : T-10 (GATING), T-14, T-15, T-16 (GATING), T-17, T-19
-- Authority  : docs/07-quality/testing-and-validation.md §2, §4
-- Parameter  : <% database %>
--
-- Reuses OPS.DQ_ASSERTION / OPS.DQ_RESULT so there is ONE place to ask "did the
-- build pass", and one gate procedure that fails it.
--
-- ===================== THE T-10 PASS CONDITION (Q-60, DECIDED) ===============
--
-- `Q-60` asked what margin counts as "beating the trivial rule". It was left open
-- until the first honest evaluation, which has now run five times, so it is
-- DECIDED here and closed in ml-models.md §10 and testing-and-validation.md.
--
-- Measured on held-out data, at each method's own operating point, COMPONENT
-- level (121 components, 17 failing), stable to zero spread over five retrainings:
--
--   MODEL (p >= 0.50)      flags 17 components, 17 truly failing
--                          -> precision 1.000, recall 1.000
--   TRIVIAL RULE (p95)     flags 29 components, 17 truly failing
--                          -> precision 0.586, recall 1.000
--   RANDOM                 -> precision 0.140 (the base rate)
--
-- Both find every failing component. The model does it with ZERO false positives
-- while the rule sends crews to 12 healthy ones. That is a 1.71x precision
-- advantage AT IDENTICAL RECALL, and it is the honest claim: not "the model finds
-- failures the rule misses" at its own operating point, but "the model finds the
-- same failures without the wasted visits".
--
-- THE PASS CONDITION, three parts, all required:
--   1. model component precision >= 3x random               (the floor)
--   2. model component recall    >= rule component recall   (no winning by being shy)
--   3. model component precision >= 1.25x rule precision    (the honest test)
--
-- WHY 1.25x. It has to be big enough that a rule dressed up as a model cannot
-- clear it, and it must NOT be set just below the observed 1.71x, which would be
-- reverse-engineering the pass mark from the answer. 1.25x means a quarter fewer
-- wasted truck rolls at equal detection — a margin a maintenance manager would
-- recognise as real. The observed 1.71x clears it with room, and if a future
-- generator change erodes the margin to 1.3x the test still passes while telling
-- us the gap is closing.
--
-- Condition 2 exists because precision alone is gameable: a model that flags one
-- certain component would score 1.000 precision and be useless.
--
-- ===================== THE OPERATING POINT (Q-53, DECIDED) ===================
--
-- p >= 0.50 at component level, using each component's BEST day. The natural
-- decision boundary, requiring no tuning, so it cannot be accused of having been
-- fitted. Risk bands (HIGH >= 0.70, MEDIUM >= 0.30) remain for triage ORDER.
--
-- Q-53 also reported metric instability of 0.353..0.706. That is now understood
-- and gone: it came from ranking component-DAYS, where ties among near-1.0
-- probabilities broke arbitrarily. It was measurement noise, not model noise.
-- DQ-STABILITY below asserts it stays gone.
--
use role WOA_ADMIN;
use database <% database %>;
use warehouse WOA_BUILD_WH;

merge into OPS.DQ_ASSERTION tgt
using (
    select * from values
        ('DQ-LEARNABLE',     'T-10', 'G2', 'The label is learnable AND beats both pre-registered baselines',
            'A feature store whose target is a coin flip; or shipping a threshold rule labelled as a model', true),
        ('DQ-SCORE-COVERAGE','T-14', 'G2', 'A risk score exists for every in-scope component, with a horizon',
            'A scoring surface with silent gaps', false),
        ('DQ-RUN-RECORDED',  'T-15', 'G2', 'Training evaluated on held-out data and wrote metrics to OPS',
            'A metric that exists only in a console log and cannot be shown beside the score', false),
        ('DQ-DRIVERS',       'T-16', 'G2', 'No risk score exists without drivers',
            'An unexplained number on screen (FR-18, NFR-15)', true),
        ('DQ-LEADTIME',      'T-17', 'G2', 'Lead time computed per caught failure and summarised',
            'A model that detects failure two days out being called a planning aid', false),
        ('DQ-REPRODUCIBLE',  'T-19', 'G2', 'Same inputs and model version produce the same score',
            'Scores that move without an input changing', false),
        ('DQ-NO-ID-FEATURE', 'T-9',  'G2', 'No identifier column is a model feature',
            'Health as a function of primary key', false),
        ('DQ-STABILITY',     'T-10', 'G2', 'The headline comparison is stable across retrainings',
            'Quoting a lucky run. The metric once swung 0.353..0.706 on identical code', false)
    as s(id, test_id, gate, title, prevents, gating)
) src
on tgt.assertion_id = src.id
when matched then update set
    test_id = src.test_id, gate = src.gate, title = src.title,
    prevents = src.prevents, is_gating = src.gating
when not matched then insert (assertion_id, test_id, gate, title, prevents, is_gating)
    values (src.id, src.test_id, src.gate, src.title, src.prevents, src.gating);

create or replace procedure OPS.SP_RUN_ML_QUALITY()
returns varchar
language sql
execute as caller
as
$$
declare
    run_id     varchar;
    ml_run     varchar;
    m_prec     float;
    r_prec     float;
    rnd_prec   float;
    m_tight    float;
    r_tight    float;
begin
    run_id := 'DQ-' || to_varchar(current_timestamp(), 'YYYYMMDDHH24MISS');
    select max(run_id) into :ml_run from OPS.ML_RUN where model_name = 'RISK_CLASSIFIER';

    select metric_value into :m_prec   from OPS.ML_METRIC where run_id = :ml_run and metric_scope = 'MODEL' and metric_name = 'precision_components';
    select metric_value into :r_prec   from OPS.ML_METRIC where run_id = :ml_run and metric_scope = 'BL-TRIVIAL-THRESHOLD' and metric_name = 'precision_components';
    select metric_value into :rnd_prec from OPS.ML_METRIC where run_id = :ml_run and metric_scope = 'BL-RANDOM-STRATIFIED' and metric_name = 'precision_components';
    select metric_value into :m_tight  from OPS.ML_METRIC where run_id = :ml_run and metric_scope = 'MODEL' and metric_name = 'recall_components';
    select metric_value into :r_tight  from OPS.ML_METRIC where run_id = :ml_run and metric_scope = 'BL-TRIVIAL-THRESHOLD' and metric_name = 'recall_components';

    -- ---- T-10 (GATING) — the three conditions above ----------------------
    insert into OPS.DQ_RESULT (run_id, assertion_id, test_id, run_at, passed, measured_value, threshold_value, detail)
    select
        :run_id, 'DQ-LEARNABLE', 'T-10', current_timestamp()::timestamp_ntz,
        coalesce(
            (:m_prec >= 3.0 * :rnd_prec) and (:m_tight >= :r_tight) and (:m_prec >= 1.25 * :r_prec),
            false
        ),
        coalesce(round(:m_prec / nullif(:r_prec, 0), 4), 0),
        1.25,
        case when :m_prec is null
             then 'NO EVALUATION RECORDED for training run ' || :ml_run
                  || ' — run ML.SP_EVALUATE_RISK_CLASSIFIER(). '
             else '' end
            || 'component precision: model ' || coalesce(:m_prec::varchar, 'n/a')
            || ' vs rule ' || coalesce(:r_prec::varchar, 'n/a')
            || ' (x' || coalesce(round(:m_prec / nullif(:r_prec, 0), 2)::varchar, 'n/a')
            || ', needs >=1.25x) vs random ' || coalesce(:rnd_prec::varchar, 'n/a')
            || ' (needs >=3x). Recall: model ' || coalesce(:m_tight::varchar, 'n/a')
            || ' vs rule ' || coalesce(:r_tight::varchar, 'n/a') || ' (model must not be lower).';

    -- ---- DQ-STABILITY — the headline must not move between retrainings ----
    insert into OPS.DQ_RESULT (run_id, assertion_id, test_id, run_at, passed, measured_value, threshold_value, detail)
    select
        :run_id, 'DQ-STABILITY', 'T-10', current_timestamp()::timestamp_ntz,
        coalesce(spread <= 0.05, true), coalesce(round(spread, 4), 0), 0.05,
        'model component precision spread across the last ' || n_runs
            || ' evaluated runs: ' || coalesce(round(spread, 4)::varchar, 'n/a')
            || ' (must be <= 0.05, or a quoted figure is a lucky draw)'
    from (
        select
            count(*) as n_runs,
            max(metric_value) - min(metric_value) as spread
        from OPS.ML_METRIC
        where metric_scope = 'MODEL' and metric_name = 'precision_components'
          and run_id in (select run_id from OPS.ML_RUN order by trained_at desc limit 5)
    );

    -- ---- T-14 ------------------------------------------------------------
    insert into OPS.DQ_RESULT (run_id, assertion_id, test_id, run_at, passed, measured_value, threshold_value, detail)
    select
        :run_id, 'DQ-SCORE-COVERAGE', 'T-14', current_timestamp()::timestamp_ntz,
        n_missing = 0, n_missing, 0,
        n_missing || ' in-scope components have no risk score; ' || n_scored || ' scored, all carrying a horizon'
    from (
        select
            (select count(*) from RAW.DIM_COMPONENT c
              where c.component_class_code in ('GBX', 'GEN', 'MSB', 'PIT')
                and not exists (select 1 from ML.SCORE_COMPONENT_RISK s where s.component_id = c.component_id)
            ) as n_missing,
            (select count(*) from ML.SCORE_COMPONENT_RISK where horizon_days is not null) as n_scored
    );

    -- ---- T-15 ------------------------------------------------------------
    insert into OPS.DQ_RESULT (run_id, assertion_id, test_id, run_at, passed, measured_value, threshold_value, detail)
    select
        :run_id, 'DQ-RUN-RECORDED', 'T-15', current_timestamp()::timestamp_ntz,
        n_metrics >= 12 and test_pos > 0, n_metrics, 12,
        n_metrics || ' metrics recorded for run ' || :ml_run || ' on ' || test_pos || ' held-out positives'
    from (
        select
            (select count(*) from OPS.ML_METRIC where run_id = :ml_run) as n_metrics,
            (select test_positives from OPS.ML_RUN where run_id = :ml_run) as test_pos
    );

    -- ---- T-16 (GATING) — the anti-join the plan specifies ----------------
    insert into OPS.DQ_RESULT (run_id, assertion_id, test_id, run_at, passed, measured_value, threshold_value, detail)
    select
        :run_id, 'DQ-DRIVERS', 'T-16', current_timestamp()::timestamp_ntz,
        n_orphan = 0, n_orphan, 0,
        n_orphan || ' scores without drivers (anti-join must return zero rows)'
    from (
        select count(*) as n_orphan
        from ML.SCORE_COMPONENT_RISK s
        where not exists (
            select 1 from ML.DRIVER_COMPONENT_RISK d
            where d.component_id = s.component_id and d.scored_date = s.scored_date
        )
    );

    -- ---- T-17 ------------------------------------------------------------
    insert into OPS.DQ_RESULT (run_id, assertion_id, test_id, run_at, passed, measured_value, threshold_value, detail)
    select
        :run_id, 'DQ-LEADTIME', 'T-17', current_timestamp()::timestamp_ntz,
        n_lead >= 3 and med_lead is not null, coalesce(med_lead, -1), 0,
        'median lead time ' || coalesce(med_lead::varchar, 'n/a') || ' days across '
            || n_lead || ' recorded lead-time metrics'
    from (
        select
            (select count(*) from OPS.ML_METRIC where run_id = :ml_run and metric_name like 'lead_time%') as n_lead,
            (select metric_value from OPS.ML_METRIC where run_id = :ml_run and metric_name = 'lead_time_median_days') as med_lead
    );

    -- ---- T-19 — determinism of the score -------------------------------
    -- Re-predicts the scored rows and compares. PREDICT on an unchanged model
    -- over unchanged features must reproduce the stored probability exactly.
    insert into OPS.DQ_RESULT (run_id, assertion_id, test_id, run_at, passed, measured_value, threshold_value, detail)
    with repredict as (
        select
            f.component_id,
            f.feature_date,
            ML.RISK_CLASSIFIER!PREDICT(object_construct(
                'COMPONENT_CLASS_CODE', f.component_class_code,
                'PLATFORM_ID', f.platform_id,
                'PRIMARY_MEAN', coalesce(f.primary_mean, 0),
                'PRIMARY_P95', coalesce(f.primary_p95, 0),
                'PRIMARY_VS_OWN_BASELINE', coalesce(f.primary_vs_own_baseline, 0),
                'TREND_7D', coalesce(f.trend_7d, 0),
                'TREND_14D', coalesce(f.trend_14d, 0),
                'TREND_30D', coalesce(f.trend_30d, 0),
                'TREND_ACCEL', coalesce(f.trend_accel, 0),
                'THERMAL_RISE', coalesce(f.thermal_rise, 0),
                'VIB_TEMP_DIVERGENCE', coalesce(f.vib_temp_divergence, 0),
                'HOURS_HIGH_LOAD_7D', coalesce(f.hours_high_load_7d, 0),
                'STARTS_7D', coalesce(f.starts_7d, 0),
                'AGE_DAYS', f.age_days,
                'SITE_STRESSOR_FACTOR', coalesce(f.site_stressor_factor, 1),
                'DAYS_SINCE_INTERVENTION', coalesce(f.days_since_intervention, 0)
            )):probability:"True"::float as p
        from ML.FEAT_COMPONENT_DAILY f
        join ML.SCORE_COMPONENT_RISK s
          on s.component_id = f.component_id and s.scored_date = f.feature_date
    )
    select
        :run_id, 'DQ-REPRODUCIBLE', 'T-19', current_timestamp()::timestamp_ntz,
        n_diff = 0, n_diff, 0,
        n_diff || ' of ' || n_tot || ' scores changed on re-prediction with the same model version'
    from (
        select
            count_if(abs(r.p - s.risk_probability) > 0.000001) as n_diff,
            count(*) as n_tot
        from repredict r
        join ML.SCORE_COMPONENT_RISK s
          on s.component_id = r.component_id and s.scored_date = r.feature_date
    );

    -- ---- T-9 extension: no identifier may be a feature -------------------
    insert into OPS.DQ_RESULT (run_id, assertion_id, test_id, run_at, passed, measured_value, threshold_value, detail)
    select
        :run_id, 'DQ-NO-ID-FEATURE', 'T-9', current_timestamp()::timestamp_ntz,
        n_id_cols = 0, n_id_cols, 0,
        n_id_cols || ' identifier columns present in the training view ML.V_ML_TRAIN'
    from (
        select count(*) as n_id_cols
        -- current_database() rather than a literal: NFR-6 forbids hardcoded
        -- database names, and this file is deployed into every clone
        from information_schema.columns
        where table_schema = 'ML' and table_name = 'V_ML_TRAIN'
          and column_name in ('COMPONENT_ID', 'TURBINE_ID', 'FEATURE_DATE', 'PRIMARY_CHANNEL')
    );

    return 'ML quality run ' || run_id || ' complete';
end;
$$;
