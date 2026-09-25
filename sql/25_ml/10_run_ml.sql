-- =============================================================================
-- 25_ml / 10 — run the ML pipeline in order                    STAGE: WOA_ADMIN
-- =============================================================================
-- Implements : the body of `just deploy-ml`
-- Parameters : <% database %>, <% horizon_days %>
--
-- THE ORDER IS THE POINT. Features -> train -> evaluate -> score. Retraining
-- without re-evaluating leaves the newest model with no recorded metrics, which
-- makes T-87 (the UI metric must match the recorded run) unsatisfiable and makes
-- T-10 unevaluable. That state was reached by hand during development, so the
-- sequence lives in a file rather than in somebody's memory.
--
-- The detector is trained and scored LAST, and that is load-bearing rather than
-- tidy: ML.SP_SCORE_ANOMALY measures T-18 against SCORE_COMPONENT_RISK, so the
-- risk scores must already exist at their final dates. Scoring the detector
-- before the classifier would leave the independence statistic measured against
-- a previous run's scores, or against none at all.
-- =============================================================================

use role WOA_ADMIN;
use database <% database %>;
use warehouse WOA_BUILD_WH;

call ML.SP_BUILD_FEATURES(<% horizon_days %>);
call ML.SP_TRAIN_RISK_CLASSIFIER(<% horizon_days %>);
call ML.SP_EVALUATE_RISK_CLASSIFIER();
call ML.SP_SCORE_COMPONENTS();
call ML.SP_TRAIN_ANOMALY_DETECTOR();
call ML.SP_SCORE_ANOMALY();
