-- =============================================================================
-- 25_ml / 05 — the anomaly detector, and the bound that judges it  STAGE: WOA_ADMIN
-- =============================================================================
-- Implements : US-22 (anomaly detection as an independent second signal)
-- Proves     : T-18 · closes G2
-- Authority  : docs/05-ai-ml/ml-models.md §2 and §10, FR-20, ADR-0007
-- Parameter  : <% database %>
--
-- ===================== THE BOUND IS PRE-REGISTERED ===========================
--
-- T-18 says the two signals must be "not collinear — correlation below a stated
-- bound", and the plan never stated the bound. It is stated here, and this file
-- is committed BEFORE the correlation is ever computed, for the same reason
-- 00_baseline_spec.sql is committed before any evaluation: a threshold chosen
-- after seeing the number is not a test, it is a description.
--
--   |Spearman rho| <= 0.50  between risk probability and anomaly distance.
--
-- Why 0.50, argued from the requirement rather than from the data:
--   * rho = 0.50 implies rho^2 = 0.25 of shared rank variance, so at the bound
--     three quarters of each signal's variation is unexplained by the other.
--     Below it, the two genuinely carry different information.
--   * The named anti-pattern is the reference solution, whose two "signals" had
--     correlation -1.0 by construction because one was a linear rescale of the
--     other (ml-models.md §2). Any bound under 1.0 excludes that; 0.50 excludes
--     the much larger family of "technically two models, practically one".
--   * Spearman, not Pearson: risk probability is a bounded, heavily skewed
--     near-binary quantity and anomaly distance is unbounded and long-tailed.
--     Pearson on that pair measures the shape of the tails as much as the
--     association. Pearson is recorded too, as context, never as the verdict.
--
-- A second, less obvious failure is guarded: a CONSTANT anomaly score would
-- make the correlation NULL and sail through a naive "rho <= 0.5" check while
-- carrying no information at all. DQ-NON-COLLINEAR therefore requires both
-- signals to vary, and treats a NULL correlation as a FAILURE, not a pass.
--
-- ===================== WHAT "UNLIKE ITSELF" FORCES ============================
--
-- Q-55 asked whether the detector runs per component instance or per class. The
-- recorded recommendation was per class, for one stated reason: "fewer models to
-- train". That reason does not survive contact with the platform —
-- SNOWFLAKE.ML.ANOMALY_DETECTION takes SERIES_COLNAME and builds ONE model
-- object over all series, so per-component costs exactly one model either way.
-- With the only argument for per-class void, FR-20's wording decides it:
-- "unlike ITSELF at matched operating conditions". SERIES_COLNAME =
-- COMPONENT_ID. Q-55 is closed in ml-models.md §10 in this same change.
--
-- ===================== WHY THE REFERENCE WINDOW IS THE BURN-IN ================
--
-- DETECT_ANOMALIES requires every evaluation timestamp to fall AFTER the last
-- training timestamp (verified: "All evaluation timestamps must be after the
-- last timestamp in fitting data"). That platform constraint turns out to match
-- the domain exactly. The generator guarantees a 60-day burn-in during which no
-- component may cross its failure threshold
-- (sql/10_generate/06_damage_and_failures.sql), so the first 60 days of the
-- window are the closest thing we have to certified-healthy behaviour. We fit
-- there and detect afterwards. The cutoff is DERIVED from the generator's own
-- window start, never hardcoded, so it stays correct if the window moves.
--
-- ===================== WHAT WE DO NOT CLAIM ==================================
--
-- This is not failure prediction and is never labelled as such (ml-models.md
-- §9). It answers "is this behaving unlike itself?" and nothing more. It is not
-- blended with the risk score: §2 forbids merging them, because a planner needs
-- to know WHICH signal is firing. The two are written to separate tables and
-- displayed side by side.
-- =============================================================================

use role WOA_ADMIN;
use database <% database %>;
use warehouse WOA_BUILD_WH;

-- ---------------------------------------------------------------------------
-- 1. The pre-registered independence bound
-- ---------------------------------------------------------------------------
-- Mirrors ML.ML_BASELINE_SPEC: the claim is recorded as a row, with a flag
-- asserting it predates the measurement, so the honesty of T-18 is auditable
-- rather than a matter of trusting the commit history.

create table if not exists ML.ML_INDEPENDENCE_SPEC (
    spec_id                      varchar(40)   not null,
    spec_name                    varchar(200)  not null,
    signal_a                     varchar(200)  not null,
    signal_b                     varchar(200)  not null,
    statistic                    varchar(40)   not null,
    bound_abs                    number(10,4)  not null,
    rationale                    varchar(2000) not null,
    registered_at                timestamp_ntz not null,
    registered_before_evaluation boolean       not null default true,
    is_synthetic                 boolean       not null default true,
    constraint pk_ml_independence_spec primary key (spec_id)
);

merge into ML.ML_INDEPENDENCE_SPEC tgt
using (
    select
        'IND-RISK-VS-ANOMALY' as spec_id,
        'Risk classifier and anomaly detector carry different information' as spec_name,
        'ML.SCORE_COMPONENT_RISK.RISK_PROBABILITY' as signal_a,
        'ML.SCORE_COMPONENT_ANOMALY.ANOMALY_DISTANCE' as signal_b,
        'SPEARMAN' as statistic,
        0.50 as bound_abs,
        'rho=0.50 implies rho^2=0.25 shared rank variance, so at the bound three quarters of each signal is unexplained by the other. The anti-pattern is the reference solution at -1.0 by construction (one signal a linear rescale of the other). Spearman rather than Pearson because risk probability is bounded and near-binary while anomaly distance is unbounded and long-tailed. A NULL correlation counts as FAILURE, not a pass, so a constant score cannot sail through.' as rationale,
        current_timestamp()::timestamp_ntz as registered_at
) src
on tgt.spec_id = src.spec_id
when matched then update set
    spec_name = src.spec_name, signal_a = src.signal_a, signal_b = src.signal_b,
    statistic = src.statistic, bound_abs = src.bound_abs, rationale = src.rationale
when not matched then insert
    (spec_id, spec_name, signal_a, signal_b, statistic, bound_abs, rationale, registered_at)
    values
    (src.spec_id, src.spec_name, src.signal_a, src.signal_b, src.statistic, src.bound_abs,
     src.rationale, src.registered_at);

-- ---------------------------------------------------------------------------
-- 2. Reference and detection windows
-- ---------------------------------------------------------------------------
-- FEATURE_DATE is a DATE; ANOMALY_DETECTION wants a timestamp column, so both
-- views expose FEATURE_TS. The cutoff is the generator's window start + 60 days
-- (the documented burn-in), computed here rather than pasted as a literal.

create or replace view ML.V_ANOMALY_CUTOFF as
select dateadd(day, 60, min(day))::date as reference_end
from GEN.GEN_TURBINE_DAY;

create or replace view ML.V_ANOMALY_REFERENCE as
select
    f.component_id,
    f.feature_date::timestamp_ntz as feature_ts,
    f.primary_mean
from ML.FEAT_COMPONENT_DAILY f
cross join ML.V_ANOMALY_CUTOFF c
where f.primary_mean is not null
  and f.feature_date <= c.reference_end;

create or replace view ML.V_ANOMALY_DETECT as
select
    f.component_id,
    f.feature_date::timestamp_ntz as feature_ts,
    f.primary_mean
from ML.FEAT_COMPONENT_DAILY f
cross join ML.V_ANOMALY_CUTOFF c
where f.primary_mean is not null
  and f.feature_date > c.reference_end;

-- ---------------------------------------------------------------------------
-- 3. The output table
-- ---------------------------------------------------------------------------
-- SCORE_<subject> per 04-code.md §3, alongside SCORE_COMPONENT_RISK and
-- deliberately NOT joined into it (ml-models.md §2).

create table if not exists ML.SCORE_COMPONENT_ANOMALY (
    component_id       varchar(40)   not null,
    scored_date        date          not null,
    primary_mean       number(20,6),
    expected_mean      number(20,6),
    lower_bound        number(20,6),
    upper_bound        number(20,6),
    is_anomaly         boolean       not null,
    anomaly_percentile number(20,6),
    anomaly_distance   number(20,6),
    model_name         varchar(100)  not null,
    model_version      varchar(40)   not null,
    run_id             varchar(40)   not null,
    scored_at          timestamp_ntz not null,
    is_synthetic       boolean       not null default true,
    constraint pk_score_component_anomaly primary key (component_id, scored_date)
);

-- ---------------------------------------------------------------------------
-- 4. Train
-- ---------------------------------------------------------------------------

create or replace procedure ML.SP_TRAIN_ANOMALY_DETECTOR()
returns varchar
language sql
execute as caller
as
$$
declare
    run_id        varchar;
    ref_end       date;
    n_ref         integer;
    n_series      integer;
    n_detect      integer;
begin
    run_id := 'MLRUN-' || to_varchar(current_timestamp(), 'YYYYMMDDHH24MISS');

    select reference_end into :ref_end from ML.V_ANOMALY_CUTOFF;
    select count(*), count(distinct component_id) into :n_ref, :n_series
      from ML.V_ANOMALY_REFERENCE;
    select count(*) into :n_detect from ML.V_ANOMALY_DETECT;

    -- Refuse rather than train on a window that cannot support a model. The
    -- classifier does the same (02_train.sql) — a model fitted on nothing at
    -- all would still produce scores, which is the dangerous outcome.
    if (n_ref < 500 or n_series < 10 or n_detect = 0) then
        return 'REFUSING TO TRAIN: reference window has ' || n_ref || ' rows over '
            || n_series || ' series and the detection window has ' || n_detect
            || ' rows. Need >=500 reference rows, >=10 series, >0 detection rows. '
            || 'Remedy: run just seed with a longer history, then ML.SP_BUILD_FEATURES.';
    end if;

    create or replace snowflake.ml.anomaly_detection ML.ANOMALY_DETECTOR(
        input_data        => system$reference('view', 'ML.V_ANOMALY_REFERENCE'),
        series_colname    => 'COMPONENT_ID',
        timestamp_colname => 'FEATURE_TS',
        target_colname    => 'PRIMARY_MEAN',
        label_colname     => ''
    );

    merge into OPS.ML_RUN tgt
    using (
        select
            :run_id as run_id,
            'ANOMALY_DETECTOR' as model_name,
            :run_id as model_version,
            current_timestamp()::timestamp_ntz as trained_at,
            0 as horizon_days,
            'GBX, GEN, MSB, PIT (follows FEAT_COMPONENT_DAILY scope)' as scope_classes,
            'Unsupervised. Reference window = generator window start + 60 days (the documented burn-in, ending '
                || :ref_end || '); detection window = everything after. Split is temporal and forced by the platform: '
                || 'DETECT_ANOMALIES requires every evaluation timestamp to follow the last fitting timestamp.' as split_rule,
            :n_ref as train_rows,
            :n_detect as test_rows,
            null as train_positives,
            null as test_positives,
            null as test_failed_components,
            'SNOWFLAKE.ML.ANOMALY_DETECTION, SERIES_COLNAME=COMPONENT_ID (Q-55 closed: per instance, because '
                || 'multi-series is one model object either way and FR-20 says "unlike itself"). horizon_days=0 is '
                || 'not a 0-day horizon — this model has no horizon, it answers a different question from the '
                || 'classifier and is never presented as failure prediction (ml-models.md §9). '
                || 'train_positives/test_positives are null because the fit is unsupervised: there are no labels.' as notes
    ) src
    on tgt.run_id = src.run_id
    when not matched then insert
        (run_id, model_name, model_version, trained_at, horizon_days, scope_classes,
         split_rule, train_rows, test_rows, train_positives, test_positives,
         test_failed_components, notes)
        values
        (src.run_id, src.model_name, src.model_version, src.trained_at, src.horizon_days,
         src.scope_classes, src.split_rule, src.train_rows, src.test_rows,
         src.train_positives, src.test_positives, src.test_failed_components, src.notes);

    return 'ANOMALY_DETECTOR trained as run ' || run_id || ': ' || n_ref
        || ' reference rows over ' || n_series || ' component series up to ' || ref_end
        || '; ' || n_detect || ' rows queued for detection.';
end;
$$;

-- ---------------------------------------------------------------------------
-- 5. Score, then measure independence
-- ---------------------------------------------------------------------------
-- The correlation is computed on the population a planner actually sees: each
-- component at the date its risk score was written. Anomaly rows exist for the
-- whole detection window and are all persisted for the app; only the matched
-- dates enter the T-18 statistic.

create or replace procedure ML.SP_SCORE_ANOMALY()
returns varchar
language sql
execute as caller
as
$$
declare
    run_id       varchar;
    qid          varchar;
    n_written    integer;
    n_flagged    integer;
    n_pairs      integer;
    rho          float;
    pear         float;
    var_risk     float;
    var_anom     float;
begin
    select max(run_id) into :run_id from OPS.ML_RUN where model_name = 'ANOMALY_DETECTOR';
    if (run_id is null) then
        return 'ABORTED: no ANOMALY_DETECTOR run recorded. Run ML.SP_TRAIN_ANOMALY_DETECTOR() first.';
    end if;

    call ML.ANOMALY_DETECTOR!DETECT_ANOMALIES(
        input_data        => system$reference('view', 'ML.V_ANOMALY_DETECT'),
        series_colname    => 'COMPONENT_ID',
        timestamp_colname => 'FEATURE_TS',
        target_colname    => 'PRIMARY_MEAN'
    );
    qid := last_query_id();

    create or replace temporary table ML.ML_TMP_ANOMALY as
    select
        -- SERIES comes back as a VARIANT; trimming the JSON quotes is the
        -- reliable cast across both VARIANT and VARCHAR returns.
        trim(to_varchar(series), '"')          as component_id,
        ts::date                               as scored_date,
        y::number(20,6)                        as primary_mean,
        forecast::number(20,6)                 as expected_mean,
        lower_bound::number(20,6)              as lower_bound,
        upper_bound::number(20,6)              as upper_bound,
        coalesce(is_anomaly, false)            as is_anomaly,
        percentile::number(20,6)               as anomaly_percentile,
        distance::number(20,6)                 as anomaly_distance
    from table(result_scan(:qid));

    -- Scoped to the key pairs being rewritten, not to the run id: Snowflake
    -- does not enforce the primary key, so a re-run must replace its own rows
    -- (the lesson recorded in 04_score_and_drivers.sql).
    delete from ML.SCORE_COMPONENT_ANOMALY
    where (component_id, scored_date) in (select component_id, scored_date from ML.ML_TMP_ANOMALY);

    insert into ML.SCORE_COMPONENT_ANOMALY
        (component_id, scored_date, primary_mean, expected_mean, lower_bound, upper_bound,
         is_anomaly, anomaly_percentile, anomaly_distance, model_name, model_version,
         run_id, scored_at)
    select
        component_id, scored_date, primary_mean, expected_mean, lower_bound, upper_bound,
        is_anomaly, anomaly_percentile, anomaly_distance,
        'ANOMALY_DETECTOR', :run_id, :run_id, current_timestamp()::timestamp_ntz
    from ML.ML_TMP_ANOMALY;

    n_written := sqlrowcount;
    select count_if(is_anomaly) into :n_flagged from ML.ML_TMP_ANOMALY;

    -- ---- the T-18 statistic, on the planner's population ----
    create or replace temporary table ML.ML_TMP_INDEPENDENCE as
    select
        r.component_id,
        r.risk_probability,
        a.anomaly_distance
    from ML.SCORE_COMPONENT_RISK r
    join ML.SCORE_COMPONENT_ANOMALY a
      on a.component_id = r.component_id
     and a.scored_date  = r.scored_date;

    select count(*),
           variance(risk_probability),
           variance(anomaly_distance)
      into :n_pairs, :var_risk, :var_anom
      from ML.ML_TMP_INDEPENDENCE;

    if (n_pairs = 0) then
        return 'ABORTED: no component-dates where a risk score and an anomaly score coincide, '
            || 'so T-18 cannot be measured. Anomaly rows written: ' || n_written
            || '. Remedy: confirm ML.SP_SCORE_COMPONENTS() ran and that its scored_date falls '
            || 'inside the detection window.';
    end if;

    -- Spearman is Pearson on ranks. corr() over ranks is exact for the
    -- no-ties case and the standard tie-corrected value otherwise.
    select corr(rank_risk, rank_anom), corr(risk_probability, anomaly_distance)
      into :rho, :pear
      from (
        select
            risk_probability,
            anomaly_distance,
            rank() over (order by risk_probability) as rank_risk,
            rank() over (order by anomaly_distance) as rank_anom
        from ML.ML_TMP_INDEPENDENCE
      );

    delete from OPS.ML_METRIC where run_id = :run_id;

    insert into OPS.ML_METRIC (run_id, metric_scope, metric_name, metric_value, detail, recorded_at)
    select :run_id, 'ANOMALY', 'rows_scored', :n_written,
           'component-days written to SCORE_COMPONENT_ANOMALY across the detection window',
           current_timestamp()::timestamp_ntz
    union all
    select :run_id, 'ANOMALY', 'rows_flagged', :n_flagged,
           'component-days the detector marked IS_ANOMALY',
           current_timestamp()::timestamp_ntz
    union all
    select :run_id, 'ANOMALY', 'anomaly_rate',
           round(:n_flagged / nullif(:n_written, 0), 6),
           'flagged share of the detection window',
           current_timestamp()::timestamp_ntz
    union all
    select :run_id, 'ANOMALY', 'independence_pairs', :n_pairs,
           'components where a risk score and an anomaly score share a date',
           current_timestamp()::timestamp_ntz
    union all
    select :run_id, 'ANOMALY', 'spearman_vs_risk', round(:rho, 6),
           'THE HEADLINE for T-18: rank correlation against risk probability. Bound |rho| <= 0.50, pre-registered in ML.ML_INDEPENDENCE_SPEC',
           current_timestamp()::timestamp_ntz
    union all
    select :run_id, 'ANOMALY', 'pearson_vs_risk', round(:pear, 6),
           'context only, NOT the verdict: linear correlation on two differently-shaped distributions',
           current_timestamp()::timestamp_ntz
    union all
    select :run_id, 'ANOMALY', 'variance_risk', round(:var_risk, 6),
           'degeneracy guard: a constant signal cannot be called independent',
           current_timestamp()::timestamp_ntz
    union all
    select :run_id, 'ANOMALY', 'variance_anomaly', round(:var_anom, 6),
           'degeneracy guard: a constant signal cannot be called independent',
           current_timestamp()::timestamp_ntz;

    return 'ANOMALY scored for run ' || run_id || ': ' || n_written || ' component-days, '
        || n_flagged || ' flagged. Independence over ' || n_pairs || ' pairs: Spearman '
        || coalesce(round(rho, 4)::varchar, 'NULL') || ' (bound 0.50), Pearson '
        || coalesce(round(pear, 4)::varchar, 'NULL') || '.';
end;
$$;
