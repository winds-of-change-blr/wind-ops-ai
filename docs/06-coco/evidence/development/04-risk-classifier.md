# Development 04 — the risk classifier, and the baseline that judges it

> ### ⚠️ PARTLY SUPERSEDED — read [`05-t10-margin-and-operating-point.md`](05-t10-margin-and-operating-point.md)
>
> The tight-budget figures in §3 of this entry (*"model 0.353–0.706 vs rule 0.000"*) are **wrong**.
> They came from ranking component-DAYS and from restricting the rule to its own shortlist. The
> corrected comparison at component level is **model precision 1.000 vs rule 0.586 at identical
> recall 1.000** — a 1.71× advantage, stable to zero spread over five retrainings. `T-10` still
> passes, but on *fewer wasted visits at equal detection*, not on *finding failures the rule
> misses*. Entry 05 has the corrected numbers, the mechanism, and the closure of `Q-60`/`Q-53`.
> Nothing else in this entry is affected.

> **Phase:** Development · **Date:** 2026-09-25 · **Author:** SB
> **Story IDs:** `US-18`…`US-21`
> **Tests:** `T-10` (gating), `T-14`, `T-15`, `T-16` (gating), `T-17`, `T-19`, `T-9` extension
> **Gate:** `G2` — the model is real. Also closes the last item `G1` was waiting on.

The ML layer, and the thing that makes it worth anything: a trivial baseline that was
**committed to git before the model was trained**, so the comparison cannot have been tuned
after the fact.

---

## 1. Verifiable identifiers

| Field | Value |
| --- | --- |
| CoCo session ID | `1a36e460-4f53-47db-bfc8-052cc16e89c0` (continuation of the generator session) |
| Workspace hash | `e287939e39ffda63e106c6e52956a6f0` |
| Thread ID | `264562180` · host `hhwoueb-wq04283.snowflakecomputing.com` |
| **CoCo account** | `HHWOUEB-WQ04283`, user `SAPNABHARTI` |
| **Deploy account** | `JKDRJBB-MW27072`, locator `EB28292`, user `JVPAN0816` |
| Model | `claude-opus-5` |
| Subagent session | `ML-layer spec extraction` — read-only quote gathering across 7 plan documents |
| Skill loaded | `machine-learning` → `guides/cli-environment.md` (required entry point) |
| Training run IDs | `MLRUN-20260925051650` (first), `MLRUN-20260925053325`, and successors in `OPS.ML_RUN` |
| Baseline registration | `ML.ML_BASELINE_SPEC`, rows `BL-RANDOM-STRATIFIED` and `BL-TRIVIAL-THRESHOLD` |

### SQL to reproduce

```sql
-- CoCo token credits, in HHWOUEB-WQ04283
select to_varchar(sum(token_credits), '99999.000000') as token_credits,
       sum(tokens) as tokens, count(distinct request_id) as requests,
       min(usage_time)::varchar, max(usage_time)::varchar
from SNOWFLAKE.ACCOUNT_USAGE.CORTEX_CODE_DESKTOP_USAGE_HISTORY
where usage_time >= dateadd(day, -2, current_timestamp()) and user_name = current_user();

-- warehouse credits, in JKDRJBB-MW27072
select warehouse_name, round(sum(credits_used), 4)
from SNOWFLAKE.ACCOUNT_USAGE.WAREHOUSE_METERING_HISTORY
where start_time >= dateadd(day, -2, current_timestamp()) group by 1 order by 2 desc;

-- the evaluation behind every number in §3
select metric_scope, metric_name, metric_value from OPS.ML_METRIC
where run_id = (select max(run_id) from OPS.ML_RUN) order by metric_name, metric_scope;
```

Measured, 2026-09-25 (two-day window, covering this session and the generator session):

| Source | Account | Figure |
| --- | --- | --- |
| `CORTEX_CODE_DESKTOP_USAGE_HISTORY.TOKEN_CREDITS` | `HHWOUEB-WQ04283` | **41.653360** over 299 requests, 88,984,742 tokens |
| `WAREHOUSE_METERING_HISTORY` — `WOA_BUILD_WH` | `JKDRJBB-MW27072` | **1.9385** |

`ACCOUNT_USAGE` lags up to three hours, so the tail of the session is not included.

## 2. Prompt

One human turn: *"work on deploy mL phase in separate branch and collect evidence when done"*,
following *"go to main branch"* and *"git pull"* in the same session.

No mid-session human correction. The `machine-learning` skill was loaded first as its
`[REQUIRED]` tag demands, and its CLI environment guide was read — though see §4: its default
of running Python locally was **not** followed, deliberately.

## 3. What CoCo produced

Eight new SQL files, 1,549 lines, across three commits kept deliberately in this order:

| Commit | Contents |
| --- | --- |
| `c9a8674` | `STATE.md` §2 claim |
| **`5b94f24`** | **the two baselines, pre-registered — before any training code existed** |
| `222c546` | features, training, evaluation, scores, drivers, assertions, `just deploy-ml` |

| File | Lines | Contents |
| --- | --- | --- |
| `sql/25_ml/00_baseline_spec.sql` | 113 | `ML.ML_BASELINE_SPEC` — the two rules as data |
| `sql/25_ml/01_features.sql` | 308 | `FEAT_COMPONENT_DAILY`, `SP_BUILD_FEATURES` |
| `sql/25_ml/02_train.sql` | 227 | split views, `OPS.ML_RUN`, `OPS.ML_METRIC`, `SP_TRAIN_RISK_CLASSIFIER` |
| `sql/25_ml/03_evaluate.sql` | 322 | `SP_EVALUATE_RISK_CLASSIFIER` — both baselines, two budgets, lead time |
| `sql/25_ml/04_score_and_drivers.sql` | 306 | `SCORE_COMPONENT_RISK`, `DRIVER_COMPONENT_RISK`, `SP_SCORE_COMPONENTS` |
| `sql/25_ml/10_run_ml.sql` | 21 | the ordered pipeline driver |
| `sql/15_quality/03_ml_assertions.sql` | 227 | `SP_RUN_ML_QUALITY` — 7 assertions |
| `sql/15_quality/11_run_verify_ml.sql` | 25 | the ML gate driver |

`just deploy-ml` implemented (was a placeholder); `just verify` extended to run both suites.

### The T-10 result

| Metric | Model | Trivial threshold | Stratified random |
| --- | --- | --- | --- |
| Alert budget (matched) | 1,070 | 1,070 | 1,070 |
| Precision at budget | **0.4766** | 0.3411 | 0.0278 |
| Component recall at budget | 1.000 | 1.000 | 0.8354 |
| **Component recall, tight budget (34)** | **0.353–0.706** | **0.000** | — |
| **Precision, tight budget** | **1.000** | **0.000** | — |
| PR-AUC | **0.988** | — | — |
| Lead time (days) | median **58**, min 39, max 123 | — | — |

Held out: 121 components, 18,333 rows, 510 positives, **17 failing components**. Split is
component-disjoint on a deterministic hash, so no degradation ramp is seen from both sides.

**`T-10` passes**, on three pre-registered conditions: ≥3× random precision (17×), ≥1.2× rule
precision (1.40×), and strictly better component recall at the tight budget (0.35–0.71 vs 0.00).

### Why a second operating point was necessary

At the rule's own budget **both methods reach 100% component recall**, so the headline metric
discriminates nothing — an alert budget 63× the number of failures is a list of everything. The
tight budget (2 alerts per failing component) asks the operational question instead, and there
the gap is categorical: the model finds failing components at 100% precision, the rule finds
none, because **an absolute threshold ranks the loudest machines rather than the degrading
ones.** That is the real difference between a model and a rule, and it is the honest basis for
the verdict rather than the flattering one.

## 4. What a human changed

Nothing was rewritten by the human this session — the single instruction was to build the layer
and collect evidence.

**One skill default was deliberately overridden by CoCo, not by the human.** The
`machine-learning` skill's CLI guide directs all execution to local Python scripts. This layer
is entirely SQL instead, because `ADR-0007` already chose `SNOWFLAKE.ML.CLASSIFICATION`,
`04-code.md` §9 says engine logic stays in SQL, and the features are aggregates over 108M rows
that have no business leaving the warehouse. Recorded as a deviation in `STATE.md` §7 rather
than silently diverging.

## 5. What CoCo got wrong

Seven items. Four were caught by the assertion suite, which is the argument for writing it.

1. **`COMPONENT_ID` was passed to the model as a feature.** A 400-value categorical key the
   model could memorise — *health as a function of primary key*, the reference solution's
   defect and precisely what `T-9` forbids. With a component-disjoint split it would have
   surfaced as weak generalisation rather than a flattering score, but it was live for the
   first two training runs. Caught only because it also broke `SHOW_FEATURE_IMPORTANCE`. A new
   assertion, `DQ-NO-ID-FEATURE`, now fails the build if any identifier appears in the training
   view — the class of error is closed, not just this instance.
2. **Lead time was measured only over rows labelled positive**, which caps it at the horizon by
   construction. The first run reported min = median = max = **exactly 30 days** and CoCo
   initially read that as a result rather than an artifact. Measured over every day of a failing
   component, the median is 58 days.
3. **`T-10` was nearly declared passed on a metric that could not discriminate.** The first
   evaluation showed component recall 1.000 for the model *and* 1.000 for the trivial rule, plus
   PR-AUC 0.991. Reported as-is, that is a pass with no evidence of advantage. `ml-models.md` §8
   says to treat a suspiciously good result as a bug; the tight-budget comparison exists because
   of that instruction.
4. **Snowflake does not enforce declared primary keys.** `SCORE_COMPONENT_RISK` accumulated one
   row per component *per run*, so `T-19` compared re-predictions against stale rows from an
   earlier model version and failed. The delete was scoped to the current `run_id`; it is now
   scoped to the `(component_id, scored_date)` pairs being rewritten.
5. **Retraining without re-evaluating crashed the gate instead of failing it.** `max(run_id)`
   moved to a run with no metrics, every comparison variable came back `NULL`, and the insert
   died on a non-nullable column. `T-10` now returns **fail** in that state, and `just deploy-ml`
   enforces features → train → evaluate → score so it is hard to reach.
6. **A hardcoded database name** (`WIND_OPS_AI_DEV_SB.information_schema`) went into the `T-9`
   assertion, violating `NFR-6`. Caught on review before deploying.
7. **`T-11`'s freshness bar was structurally unmeetable** for `GEN_DAMAGE_STATE`, which is daily
   grain and therefore >24h stale from midday onward regardless of how fresh the run was. Now
   grain-aware, with the fact surfaces an operator actually reads keeping the 24h bar.

**A platform limitation, not an error of ours, but it forced a documented compromise.**
`RISK_CLASSIFIER!SHOW_FEATURE_IMPORTANCE()` and `!SHOW_EVALUATION_METRICS()` both fail with
`Computation Error in function __SHOW_FEATURE_IMPORTANCE` in this account — reproduced on a
freshly trained probe model with default config. `PREDICT` works, so the held-out evaluation is
unaffected (it computes metrics from predictions rather than asking the model to describe
itself). Drivers therefore use a **train-split standardised mean difference**, and every row
carries `IMPORTANCE_METHOD = 'TRAIN_SPLIT_STANDARDISED_MEAN_DIFF'` so no surface can present it
as a per-prediction attribution. This is weaker than the feature importances `ml-models.md` §6
specifies, and weaker still than SHAP.

**An instability worth reporting rather than hiding.** `SNOWFLAKE.ML.CLASSIFICATION` is not
bit-deterministic across training runs: tight-budget component recall measured **0.706** on one
run and **0.353** on the next, with PR-AUC moving 0.991 → 0.988. The direction of the `T-10`
verdict is unaffected (the rule scores 0.000 in both), but any single figure quoted from this
metric would be cherry-picked. It must be reported as a range until the variance is understood.

## 6. Cost

| Source | Account | Credits |
| --- | --- | --- |
| CoCo token credits (299 requests, 88.98M tokens, 2-day window) | `HHWOUEB-WQ04283` | **41.65** |
| Warehouse — `WOA_BUILD_WH` (2-day window, generator + ML) | `JKDRJBB-MW27072` | **1.94** |
| **Total observed, both sessions** | — | **≈ 43.6** |

Attributing the delta from the generator entry: this session added roughly **22.1 token credits
and 0.43 warehouse credits**. Training, evaluating and scoring the model cost under half a
credit of compute — the expensive part remains the conversation, at a ratio near **50:1**.

## 7. Traceability

| Field | Value |
| --- | --- |
| Branch | `feat/sb/deploy-ml` |
| Commits | `c9a8674` claim · **`5b94f24` baselines pre-registered** · `222c546` the layer |
| Files added | 8 SQL files, 1,549 lines |
| Files modified | `justfile`, `sql/15_quality/02_assertions.sql`, `STATE.md` |
| Gate | `just verify` green — **16 data + 7 ML assertions, 0 failures**; `just deploy-ml` idempotent across consecutive runs |
| Reproduce | `just deploy-ml` (deploys, runs the pipeline in order, then gates on `T-10`) |

**Deliberately not done.** The **anomaly detector** (`US-22`, `T-18` non-collinearity) is not
built, so `G2` is **not fully passed** — `ml-models.md` §2 requires two independent signals and
only one exists. `T-94`'s displayable comparison has its numbers recorded in `OPS.ML_METRIC` but
no surface to display them on, and `T-86`/`T-87` need the app. `Q-60` (the `T-10` margin) is
answered as a **recommendation in code**, not a decision — NK still owns it, and it is in
`STATE.md` §4.
