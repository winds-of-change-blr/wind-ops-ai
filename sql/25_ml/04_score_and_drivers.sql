-- =============================================================================
-- 25_ml / 04 — scores and drivers                              STAGE: WOA_ADMIN
-- =============================================================================
-- Implements : US-19 (risk score), US-20 (top drivers with magnitude+direction)
-- Proves     : T-14, T-16 (GATING), T-19
-- Authority  : docs/05-ai-ml/ml-models.md §6, §7 · FR-18 · NFR-15
-- Parameter  : <% database %>
--
-- ===================== NO SCORE WITHOUT DRIVERS ==============================
--
-- ml-models.md §6: "A score without drivers is a defect, not a degraded mode."
-- T-16 anti-joins SCORE_ to DRIVER_ and must return zero rows, so the two are
-- written in ONE procedure, in one transaction-shaped step. Writing them
-- separately is how you end up with a scoring run that half-succeeded and a UI
-- showing a number nobody can explain (NFR-15).
--
-- ===================== AN HONEST LIMITATION ==================================
--
-- These drivers are FEATURE IMPORTANCES from the trained model, combined with
-- each component's deviation from its OWN baseline. They are NOT per-prediction
-- attributions like SHAP. ml-models.md §6 states this explicitly and ADR-0007
-- keeps SHAP as a stretch goal. The distinction matters and must not be blurred
-- in the UI: "vibration is the top driver for this component" is supportable,
-- "vibration contributed 0.23 to this specific probability" is not.
--
-- The direction is real, though: it comes from the sign of the component's own
-- deviation, so "rising" and "falling" are honest even when the magnitude is a
-- model-level importance rather than a row-level attribution.
-- =============================================================================

use role WOA_ADMIN;
use database <% database %>;
use warehouse WOA_BUILD_WH;

-- The date scores are published "as of" (I-13). Derived, never hardcoded:
-- the last feature date minus the horizon, i.e. the last date whose outcome
-- is knowable. The app reads this to label every risk figure honestly.
create or replace view ML.V_SCORING_ASOF as
select
    dateadd(day, -max(horizon_days), max(feature_date))::date as as_of_date,
    max(feature_date)::date                                   as data_end_date,
    max(horizon_days)                                         as horizon_days
from ML.FEAT_COMPONENT_DAILY;

create table if not exists ML.SCORE_COMPONENT_RISK (
    component_id       varchar(30)   not null,
    turbine_id         varchar(20)   not null,
    component_class_code varchar(3)  not null,
    scored_date        date          not null,
    risk_probability   number(10,6)  not null,
    risk_band          varchar(20)   not null,
    horizon_days       integer       not null,
    model_name         varchar(100)  not null,
    model_version      varchar(40)   not null,
    run_id             varchar(40)   not null,
    scored_at          timestamp_ntz not null,
    is_synthetic       boolean       not null default true,
    constraint pk_score_component_risk primary key (component_id, scored_date)
);

create table if not exists ML.DRIVER_COMPONENT_RISK (
    component_id     varchar(30)   not null,
    scored_date      date          not null,
    driver_rank      integer       not null,
    feature_name     varchar(100)  not null,
    importance       number(10,6)  not null,
    direction        varchar(10)   not null,   -- RISING | FALLING | FLAT
    component_value  number(16,6),
    own_baseline_delta number(16,6),
    -- How IMPORTANCE was derived. Recorded per row so no surface can present a
    -- model-agnostic score as if it were a model attribution.
    importance_method varchar(60)  not null,
    run_id           varchar(40)   not null,
    is_synthetic     boolean       not null default true,
    constraint pk_driver_component_risk primary key (component_id, scored_date, driver_rank)
);

create or replace procedure ML.SP_SCORE_COMPONENTS()
returns varchar
language sql
execute as caller
as
$$
declare
    run_id     varchar;
    horizon    integer;
    n_scored   integer;
    n_drivers  integer;
    n_orphan   integer;
begin
    select max(run_id) into :run_id from OPS.ML_RUN where model_name = 'RISK_CLASSIFIER';
    select horizon_days into :horizon from OPS.ML_RUN where run_id = :run_id;

    -- score the most recent day available per component (daily batch, §7)
    -- AS-OF DATE (I-13). Scoring used to take each component's LATEST feature
    -- date, and every one of the 400 published scores came out between
    -- 0.000001 and 0.000007: variance 1e-12, all MINIMAL, an empty triage
    -- surface. Not a model fault — across the detection window the same model
    -- has variance 0.026. The last day carrying ANY positive label is
    -- window_end - horizon, because a label needs a full horizon of future to be
    -- known. Scoring after that date scores a period in which, by construction,
    -- nothing can be seen to fail.
    --
    -- So scoring is AS OF window_end - horizon. That is not stale data dressed
    -- up: a 30-day-ahead prediction is only a claim you can check if 30 days of
    -- future exist to check it against. ML.V_SCORING_ASOF exposes the date so
    -- the app states it rather than implying the scores are "today".
    create or replace temporary table ML.ML_TMP_LATEST as
    select f.*
    from ML.FEAT_COMPONENT_DAILY f
    join (
        select component_id, max(feature_date) as feature_date
        from ML.FEAT_COMPONENT_DAILY
        where not label_excluded
          and feature_date <= (select as_of_date from ML.V_SCORING_ASOF)
        group by component_id
    ) l on l.component_id = f.component_id and l.feature_date = f.feature_date;

    create or replace temporary table ML.ML_TMP_SCORED as
    select
        l.component_id,
        l.turbine_id,
        l.component_class_code,
        l.feature_date,
        p.pred:probability:"True"::float as risk_probability
    from ML.ML_TMP_LATEST l
    join (
        select
            component_id,
            feature_date,
            ML.RISK_CLASSIFIER!PREDICT(object_construct(
                'COMPONENT_CLASS_CODE', component_class_code,
                'PLATFORM_ID', platform_id,
                'PRIMARY_MEAN', coalesce(primary_mean, 0),
                'PRIMARY_P95', coalesce(primary_p95, 0),
                'PRIMARY_VS_OWN_BASELINE', coalesce(primary_vs_own_baseline, 0),
                'TREND_7D', coalesce(trend_7d, 0),
                'TREND_14D', coalesce(trend_14d, 0),
                'TREND_30D', coalesce(trend_30d, 0),
                'TREND_ACCEL', coalesce(trend_accel, 0),
                'THERMAL_RISE', coalesce(thermal_rise, 0),
                'VIB_TEMP_DIVERGENCE', coalesce(vib_temp_divergence, 0),
                'HOURS_HIGH_LOAD_7D', coalesce(hours_high_load_7d, 0),
                'STARTS_7D', coalesce(starts_7d, 0),
                'AGE_DAYS', age_days,
                'SITE_STRESSOR_FACTOR', coalesce(site_stressor_factor, 1),
                'DAYS_SINCE_INTERVENTION', coalesce(days_since_intervention, 0)
            )) as pred
        from ML.ML_TMP_LATEST
    ) p on p.component_id = l.component_id and p.feature_date = l.feature_date;

    -- SNOWFLAKE DOES NOT ENFORCE PRIMARY KEYS. The declared PK on
    -- (component_id, scored_date) is documentation, not a constraint, so deleting
    -- only the CURRENT run id left every previous run's rows in place and the table
    -- accumulated one row per component per run. T-19 caught it: re-prediction was
    -- compared against stale rows from an earlier model version and "the same
    -- inputs produced a different score" — which was true, but not for the reason
    -- the test is looking for.
    --
    -- The table is a SNAPSHOT — one row per component at the as-of date, every row
    -- from the current model version (05_anomaly.sql and DQ in 07_numbers rely on
    -- both). So the whole snapshot is replaced. Scoping the delete to the
    -- (component, date) pairs being rewritten was not enough: when the as-of date
    -- moved (I-13), a redeploy onto existing data left the previous snapshot beside
    -- the new one, and T-19 re-predicted 400 stale rows with the new model.
    delete from ML.SCORE_COMPONENT_RISK;
    delete from ML.DRIVER_COMPONENT_RISK;

    insert into ML.SCORE_COMPONENT_RISK (
        component_id, turbine_id, component_class_code, scored_date,
        risk_probability, risk_band, horizon_days, model_name, model_version,
        run_id, scored_at
    )
    select
        component_id, turbine_id, component_class_code, feature_date,
        round(risk_probability, 6),
        case
            when risk_probability >= 0.70 then 'HIGH'
            when risk_probability >= 0.30 then 'MEDIUM'
            when risk_probability >= 0.05 then 'LOW'
            else 'MINIMAL'
        end,
        :horizon, 'RISK_CLASSIFIER', :run_id, :run_id,
        current_timestamp()::timestamp_ntz
    from ML.ML_TMP_SCORED;

    n_scored := sqlrowcount;

    -- ---- drivers: model importance x this component's own deviation -------
    insert into ML.DRIVER_COMPONENT_RISK (
        component_id, scored_date, driver_rank, feature_name, importance,
        direction, component_value, own_baseline_delta, importance_method, run_id
    )
    -- ---- IMPORTANCE: A DOCUMENTED FALLBACK, NOT MODEL ATTRIBUTION --------
    --
    -- ml-models.md §6 specifies "feature importances from the trained model".
    -- SNOWFLAKE.ML.CLASSIFICATION exposes those through
    -- !SHOW_FEATURE_IMPORTANCE(), and in this account that function FAILS with
    -- "Computation Error in function __SHOW_FEATURE_IMPORTANCE" — reproduced on a
    -- freshly trained probe model with default config, so it is not our
    -- configuration. !SHOW_EVALUATION_METRICS() fails the same way. PREDICT works
    -- fine, which is why the held-out evaluation is unaffected: it computes its
    -- metrics from predictions rather than asking the model to describe itself.
    --
    -- Rather than ship scores with no drivers (forbidden by FR-18 and T-16), or
    -- claim model attributions we cannot obtain, importance is computed as the
    -- ABSOLUTE STANDARDISED MEAN DIFFERENCE (Cohen's d) of each feature between
    -- positive and negative component-days, ON THE TRAINING SPLIT ONLY.
    --
    -- Two properties make this honest rather than convenient:
    --   * it is computed on TRAIN only, so it cannot launder held-out information
    --     into a surface that also displays held-out metrics
    --   * every row records IMPORTANCE_METHOD, so a UI cannot present this as a
    --     per-prediction attribution. It is a feature-level discriminability
    --     score, which is weaker than SHAP and weaker than model importance, and
    --     ml-models.md §6 already requires us to describe drivers accurately
    --     rather than overclaim.
    --
    -- Recorded as a deviation in STATE.md §7.
    with stats as (
        select
            avg(case when failed_within_horizon then primary_vs_own_baseline end) as p_vob,
            avg(case when not failed_within_horizon then primary_vs_own_baseline end) as n_vob,
            stddev(primary_vs_own_baseline) as s_vob,
            avg(case when failed_within_horizon then trend_30d end) as p_t30,
            avg(case when not failed_within_horizon then trend_30d end) as n_t30,
            stddev(trend_30d) as s_t30,
            avg(case when failed_within_horizon then trend_7d end) as p_t7,
            avg(case when not failed_within_horizon then trend_7d end) as n_t7,
            stddev(trend_7d) as s_t7,
            avg(case when failed_within_horizon then trend_accel end) as p_ac,
            avg(case when not failed_within_horizon then trend_accel end) as n_ac,
            stddev(trend_accel) as s_ac,
            avg(case when failed_within_horizon then thermal_rise end) as p_th,
            avg(case when not failed_within_horizon then thermal_rise end) as n_th,
            stddev(thermal_rise) as s_th,
            avg(case when failed_within_horizon then vib_temp_divergence end) as p_dv,
            avg(case when not failed_within_horizon then vib_temp_divergence end) as n_dv,
            stddev(vib_temp_divergence) as s_dv,
            avg(case when failed_within_horizon then primary_mean end) as p_pm,
            avg(case when not failed_within_horizon then primary_mean end) as n_pm,
            stddev(primary_mean) as s_pm,
            avg(case when failed_within_horizon then hours_high_load_7d end) as p_hl,
            avg(case when not failed_within_horizon then hours_high_load_7d end) as n_hl,
            stddev(hours_high_load_7d) as s_hl,
            avg(case when failed_within_horizon then age_days end) as p_ag,
            avg(case when not failed_within_horizon then age_days end) as n_ag,
            stddev(age_days) as s_ag,
            avg(case when failed_within_horizon then days_since_intervention end) as p_di,
            avg(case when not failed_within_horizon then days_since_intervention end) as n_di,
            stddev(days_since_intervention) as s_di
        from ML.V_ML_TRAIN
    ),
    importance as (
        select 'PRIMARY_VS_OWN_BASELINE' as feature_name, abs(p_vob - n_vob) / nullif(s_vob, 0) as importance from stats
        union all select 'TREND_30D',               abs(p_t30 - n_t30) / nullif(s_t30, 0) from stats
        union all select 'TREND_7D',                abs(p_t7  - n_t7)  / nullif(s_t7, 0)  from stats
        union all select 'TREND_ACCEL',             abs(p_ac  - n_ac)  / nullif(s_ac, 0)  from stats
        union all select 'THERMAL_RISE',            abs(p_th  - n_th)  / nullif(s_th, 0)  from stats
        union all select 'VIB_TEMP_DIVERGENCE',     abs(p_dv  - n_dv)  / nullif(s_dv, 0)  from stats
        union all select 'PRIMARY_MEAN',            abs(p_pm  - n_pm)  / nullif(s_pm, 0)  from stats
        union all select 'HOURS_HIGH_LOAD_7D',      abs(p_hl  - n_hl)  / nullif(s_hl, 0)  from stats
        union all select 'AGE_DAYS',                abs(p_ag  - n_ag)  / nullif(s_ag, 0)  from stats
        union all select 'DAYS_SINCE_INTERVENTION', abs(p_di  - n_di)  / nullif(s_di, 0)  from stats
    ),
    unpivoted as (
        select l.component_id, l.feature_date, 'PRIMARY_VS_OWN_BASELINE' as fname,
               l.primary_mean as val, l.primary_vs_own_baseline as delta from ML.ML_TMP_LATEST l
        union all
        select component_id, feature_date, 'TREND_30D', trend_30d, trend_30d from ML.ML_TMP_LATEST
        union all
        select component_id, feature_date, 'TREND_7D', trend_7d, trend_7d from ML.ML_TMP_LATEST
        union all
        select component_id, feature_date, 'TREND_ACCEL', trend_accel, trend_accel from ML.ML_TMP_LATEST
        union all
        select component_id, feature_date, 'THERMAL_RISE', thermal_rise, thermal_rise from ML.ML_TMP_LATEST
        union all
        select component_id, feature_date, 'VIB_TEMP_DIVERGENCE', vib_temp_divergence, vib_temp_divergence from ML.ML_TMP_LATEST
        union all
        select component_id, feature_date, 'PRIMARY_MEAN', primary_mean, primary_vs_own_baseline from ML.ML_TMP_LATEST
        union all
        select component_id, feature_date, 'HOURS_HIGH_LOAD_7D', hours_high_load_7d, 0 from ML.ML_TMP_LATEST
        union all
        select component_id, feature_date, 'AGE_DAYS', age_days, 0 from ML.ML_TMP_LATEST
        union all
        select component_id, feature_date, 'DAYS_SINCE_INTERVENTION', days_since_intervention, 0 from ML.ML_TMP_LATEST
    )
    select
        u.component_id,
        u.feature_date,
        row_number() over (partition by u.component_id order by i.importance desc, u.fname),
        u.fname,
        round(i.importance, 6),
        case
            when u.delta is null or abs(u.delta) < 0.0001 then 'FLAT'
            when u.delta > 0 then 'RISING'
            else 'FALLING'
        end,
        round(u.val, 6),
        round(u.delta, 6),
        'TRAIN_SPLIT_STANDARDISED_MEAN_DIFF',
        :run_id
    from unpivoted u
    join importance i on i.feature_name = u.fname
    where i.importance is not null
    qualify row_number() over (partition by u.component_id order by i.importance desc, u.fname) <= 5;

    n_drivers := sqlrowcount;

    -- ---- T-16 enforced here, not just asserted later ---------------------
    select count(*) into :n_orphan
    from ML.SCORE_COMPONENT_RISK s
    where s.run_id = :run_id
      and not exists (
          select 1 from ML.DRIVER_COMPONENT_RISK d
          where d.component_id = s.component_id and d.scored_date = s.scored_date
      );

    if (n_orphan > 0) then
        -- Roll the scores back rather than publish unexplained numbers. A score
        -- with no drivers is a defect (FR-18), so it must not survive the run
        -- that produced it.
        delete from ML.SCORE_COMPONENT_RISK
        where (component_id, scored_date) in (select component_id, feature_date from ML.ML_TMP_SCORED);
        return 'ABORTED: ' || n_orphan || ' scores had no drivers; all scores for run '
            || run_id || ' were removed rather than published without explanation (FR-18, T-16).';
    end if;

    return 'SCORE_COMPONENT_RISK: ' || n_scored || ' components scored; '
        || 'DRIVER_COMPONENT_RISK: ' || n_drivers || ' driver rows; 0 scores without drivers';
end;
$$;
