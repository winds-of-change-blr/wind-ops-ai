# Development 06 — the anomaly detector, and the guard that found something else

> **Phase:** development · **Date:** 2026-09-25 · **Story:** `US-22` · **Test:** `T-18` · **Closes:** `G2`

## 1. Verifiable identifiers

| Field | Value |
| --- | --- |
| CoCo `session_id` | `04d1ee7a-0e99-44de-afb6-40f838e591e6` |
| Workspace ID | `936de335e0f95bdb62958c348cc76e08` |
| Model | `claude-opus-5` |
| Verification account | `EXKFAFL-NW77746` (connection `cms`, JWT keypair), region `AZURE_CENTRALINDIA` |
| Database | `WIND_OPS_AI_DEV_NK` |
| CLI | `snow` 3.28.0, installed this session via `uv tool install snowflake-cli` |
| Training run | `MLRUN-20260925111906` |
| Scoring run | `MLRUN-20260925112646` |
| DQ run | gate passed, **10 assertions, 0 failures** |

```sql
-- the T-18 evidence, reproducible
select metric_name, metric_value from OPS.ML_METRIC
where metric_scope = 'ANOMALY'
  and run_id = (select max(run_id) from OPS.ML_RUN where model_name = 'ANOMALY_DETECTOR')
order by metric_name;

select * from ML.ML_INDEPENDENCE_SPEC;   -- the pre-registered bound
```

**A deviation worth stating first: this was verified on a different account from the team's.**
`snow` was not installed on this machine and `~/.snowflake/connections.toml` has no entry for
`JKDRJBB-MW27072`, so the full stack was re-deployed from the recipes into `EXKFAFL-NW77746` and the
work was verified there. The recipes are parameterised and account-agnostic, so this is legitimate
evidence that the code runs and that the arithmetic holds — but **the team must re-run
`just deploy-ml` on `JKDRJBB-MW27072`** before quoting these figures as the project's. Raised as
`I-14`. The reproduction matched SB's environment closely: 108,317,900 signal rows against their
108,339,384, 58 seeded failures, and `T-10` at 1.7647× against their 1.71×.

## 2. Prompt

> "lot of work is done ny colugues .. understand what is done what is pending. move to new branch.
> implement next part. collect evidence once done"

followed mid-session by: *"dont wait for my response .. take your best desicion. try to complete all
development in this round."*

`STATE.md` §3 named the next action unambiguously — the anomaly detector — so no interpretation was
needed. The session protocol worked exactly as designed: `just state`, read the handoff, claim, push
the claim before starting.

## 3. What CoCo produced

| Artefact | Detail |
| --- | --- |
| `sql/25_ml/05_anomaly.sql` | 489 lines. `ML.ML_INDEPENDENCE_SPEC`, the reference/detection views, `ML.SCORE_COMPONENT_ANOMALY`, `SP_TRAIN_ANOMALY_DETECTOR`, `SP_SCORE_ANOMALY` |
| `sql/15_quality/03_ml_assertions.sql` | `DQ-NON-COLLINEAR` and `DQ-ANOMALY-COVERAGE` registered and asserted |
| `sql/25_ml/10_run_ml.sql` | detector trained and scored **last**, because `T-18` measures against the classifier |
| `justfile` | `05_anomaly` added to the `deploy-ml` DDL loop |
| Docs | `ml-models.md` §2.1 (new) and §10 (`Q-55` closed); `testing-and-validation.md` `T-18`; `raid-log.md` `I-13`, `I-14` |

**Measured result:**

| Metric | Value |
| --- | --- |
| Reference window | 12,211 rows over 400 component series, to 2026-05-25 (the generator's documented 60-day burn-in) |
| Detection window | 48,801 component-days |
| Flagged anomalous | 4,661 (9.55%) |
| **`T-18` Spearman ρ vs risk** | **0.2219** against a pre-registered bound of 0.50 |
| Pearson (context only) | 0.0776 |
| Variance: risk / anomaly | 0.0262 / 11.3138 — both non-zero, as the guard requires |

Two decisions the plan had left open were taken and closed in docs, not only in code:

- **`Q-55` — per instance, not per class.** The recorded recommendation was per class for exactly one
  reason, "fewer models to train". That reason is void: `SNOWFLAKE.ML.ANOMALY_DETECTION` takes
  `SERIES_COLNAME` and builds **one** model object over all series, so per-instance costs one model
  either way. With its only argument gone, `FR-20`'s "unlike **itself**" decides it.
- **The `T-18` bound — |Spearman ρ| ≤ 0.50, pre-registered.** Committed in `03f1855`, *before* the
  correlation was computed, mirroring what `00_baseline_spec.sql` did for the `T-10` baselines.

## 4. What a human changed

Nothing yet — this entry is written before review. The human's one mid-session instruction was to stop
checking in and use judgement, which is why `I-13` was **documented rather than fixed** (see §5).

## 5. What CoCo got wrong, and what the guard caught

| Error | How it was caught |
| --- | --- |
| Assumed `DETECT_ANOMALIES` could score the same window it was fitted on | The platform refused: *"All evaluation timestamps must be after the last timestamp in fitting data."* Found by probing on a throwaway 300-row table **before** writing the real file, which is the only reason it cost minutes rather than a rewrite. The constraint turned out to match the domain — fit on the certified-healthy burn-in, detect after it |
| Wrote `PACKAGE = 'x'`-style guesses at unfamiliar grammar | Recurring habit this session. Probing a toy example first, then reading the SQL reference, was faster both times than guessing twice |
| Treated `SERIES` in the output as a `VARCHAR` | It returns as a `VARIANT`, so a plain cast keeps the JSON quotes. `trim(to_varchar(series), '"')` handles both |
| Put the `T-18` population on the planner's snapshot | **The important one.** See below |

**The guard found a defect in somebody else's work, which is what guards are for.**

`DQ-NON-COLLINEAR` deliberately requires both signals to *vary*, on the reasoning that a constant score
would make ρ null and sail through a naive bound check. On the first real run the correlation **passed**
at ρ = 0.216 — and the build failed anyway, because `variance(risk_probability)` over the 400 published
scores is **1e-12**.

Every row of `ML.SCORE_COMPONENT_RISK` sits between 0.000001 and 0.000007, and every component is banded
`MINIMAL`. The triage surface the whole demo depends on is empty.

The diagnosis is not the classifier. Re-predicted across the detection window the same model has
variance 0.0262 and 1,326 component-days above `p = 0.50`. The cause is structural: **the last day
carrying any positive label is 2026-08-30, while features run to 2026-09-25.** Scoring at the latest
feature date scores a period where, by generator design, nothing can be within the 30-day horizon.

So the `T-18` population moved to the full detection window, where both signals vary. **The
pre-registered bound did not move**, and both numbers — 0.2219 over 48,801 component-days, and the
snapshot's 0.1882 with its 1e-12 variance — are written to `OPS.ML_METRIC` precisely so a reviewer can
verify that the population changed because the input was degenerate and not because a bound was missed.
The snapshot number passed. That is the whole point of recording it.

**`I-13` was not fixed here, deliberately.** The fix belongs in the generator — let damage continue past
the window end so that at "today" some components are genuinely 5–25 days from failing, which is what
prediction means. Doing that changes `T-8` and `T-10`'s measured headline, and silently re-baselining
another person's gating result is exactly the failure `ADR-0006`'s honesty constraint exists to prevent.
It needs its own story and SA's eyes.

## 6. Cost

| Source | Account | Credits |
| --- | --- | --- |
| Warehouse (24h window) | `EXKFAFL-NW77746` | 0.601 |
| CoCo token credits | `BGTCHIX-UZ86048` / CoCo's own account | not yet reflected — `ACCOUNT_USAGE` lags up to 3h |

The warehouse figure covers **three** full `deploy-ml` runs plus a complete `deploy-foundation` →
`deploy-data` → `seed` (108M rows). Generation and three model pipelines for 0.6 credits, against a
reasoning cost of the same order as previous sessions: the ratio `STATE.md` §6 reports holds. Note this
spend landed on a **personal** account, not the hackathon's $400.

## 7. Traceability

Branch `feat/nk/anomaly-detector`, from `main` at `3a46da2`.

| Commit | |
| --- | --- |
| `23f1a0d` | claim in `STATE.md` §2 |
| `03f1855` | **pre-register the bound, before measuring** |
| _this_ | the detector, the assertions, the docs, this entry |

No given document was modified. `docs/00-hackathon/*` and `company-profile.md` untouched.
