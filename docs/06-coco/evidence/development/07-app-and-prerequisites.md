# Development 07 — the app, and everything it needed first

> **Phase:** development · **Date:** 2026-09-26 · **Stories:** `US-13`, `US-15`, `US-24`…`US-26`,
> `US-38`…`US-43`, `US-90`…`US-92` (first cuts) · **Tests:** `T-60` (gating), `T-70`, `T-86`, `T-87`,
> `T-94`, `T-96`, `T-97` · **Fixes:** `I-13`

## 1. Verifiable identifiers

| Field | Value |
| --- | --- |
| CoCo `session_id` | `04d1ee7a-0e99-44de-afb6-40f838e591e6` |
| Workspace ID | `936de335e0f95bdb62958c348cc76e08` |
| Model | `claude-opus-5` |
| Account | **`BGTCHIX-UZ86048`** — now the team's working account, per NK |
| Connection | `woa_bgtchix` (new JWT key-pair on user `NIRAJ`, see §4) |
| Database | `WIND_OPS_AI_DEV_NK` |
| Streamlit object | `WIND_OPS_AI_DEV_NK.APP.WOA_COMMAND_CENTER`, container runtime, `SYSTEM_COMPUTE_POOL_CPU` |
| Classifier run / detector run | `MLRUN-20260925181646` / `MLRUN-20260925181749` |
| Gates | **`just verify` exits 0 — 16 data + 10 ML + 5 engine = 31 assertions, 0 failures** |

```sql
select * from WIND_OPS_AI_DEV_NK.ENGINE.ENG_ALARM_FUNNEL;
select min(scored_date), variance(risk_probability), count_if(risk_band = 'HIGH')
from WIND_OPS_AI_DEV_NK.ML.SCORE_COMPONENT_RISK;
show streamlits like 'WOA_COMMAND_CENTER' in database WIND_OPS_AI_DEV_NK;
```

## 2. Prompt

> "list the item which need to build before app building and lets not wait for other account deploy
> everything to BGTCHIX-UZ86048. once prerequisite are ready build the app too."

Prerequisites listed and then built in order: a non-interactive CLI connection → the full stack →
the `I-13` fix → serving views → the alarm engine → the app.

## 3. What CoCo produced

| Artefact | What it is |
| --- | --- |
| `sql/25_ml/04_score_and_drivers.sql` | **`I-13` fixed.** Scores published *as of* `window_end − horizon` via new `ML.V_SCORING_ASOF` |
| `sql/30_serve/01_metrics.sql` | `MET_AVAILABILITY_CONTRACTUAL`, `MET_LD_EXPOSURE` (run-rate, labelled as such) |
| `sql/40_engine/01_alarm_incidents.sql` | `ENG_INCIDENT`, `SP_BUILD_INCIDENTS`, `ENG_SUPPRESSED_FAILURE`, `ENG_ALARM_FUNNEL`(`_DAILY`) |
| `sql/40_engine/02_alert_ranked.sql` | `ENG_ALERT_RANKED` — triage by expected loss, not probability |
| `sql/15_quality/04_engine_assertions.sql`, `12_run_verify_engine.sql` | `T-60` (gating), `T-70`, `T-86`, and a regression guard for `I-13` |
| `app/streamlit_app.py`, `app/snowflake.yml` | The command center: alarms · risk triage + evidence panel · rule vs model · fleet & contracts |
| `justfile` | `deploy-engine` and `deploy-app` implemented; `verify` gains the engine gate |

**Measured on `BGTCHIX`:**

| | |
| --- | --- |
| Risk surface after `I-13` | variance **1e-12 → 0.0148**; **6 components HIGH**, as of 2026-08-26 |
| Alarm funnel | 340,431 alarms → 15,803 incidents → **6,024 actionable, 9,739 undetermined, 40 nuisance** |
| Compression · real failures suppressed | **21.6 : 1 · 0** — always shown together (`T-70`) |
| Undetermined rate | **61.6%** — published, not hidden (`I-15`) |
| `T-10` (in the app) | model precision 1.000 vs trivial rule 0.567 → **1.76×** |
| `T-18` | Spearman **0.243** |
| Fleet LD exposure (run-rate) | ₹14.25 L; 1 site below guarantee |

**The app was executed, not just deployed.** Streamlit's `AppTest` ran it headless against `BGTCHIX`
from a laptop: **0 exceptions, 4 tabs, 6 data frames, every metric populated** — which is also `T-97`
(runs outside Snowflake, connection from configuration). Clicking *Suppress* on the top incident
returned *"Refused. `SA-YW-002` is a safety-critical code"* — `T-96` through the UI.

## 4. What a human changed

The human redirected the whole round: *stop waiting for the other account, deploy everything to
`BGTCHIX`.* That removes `I-14`'s cross-account caveat for this work.

One action taken on the human's behalf that they should know about: **a JWT key-pair was generated and
registered on user `NIRAJ`** (`ALTER USER NIRAJ SET RSA_PUBLIC_KEY`), because the existing connection
was browser-OAuth only and the recipes need a non-interactive CLI. The private key is at
`~/.snowflake/keys/woa_bgtchix_key.p8` (mode 600), outside the repo. Reversible with
`ALTER USER NIRAJ UNSET RSA_PUBLIC_KEY`.

## 5. What CoCo got wrong

| Error | How it was caught |
| --- | --- |
| **My alarm classifier hid 9 real failures.** | **`T-60` — the gating test — failed the build.** Diagnosed rather than tuned: 7 of 9 were genuine precursors (converter over-temperature, pitch trips) on the very component that later failed, 0–18 days out. Two rules the ADR states outright were broken: I treated *"no evidence"* as *"healthy"* on components nothing monitors, and I omitted *"never recurred"* from ADR-0017's nuisance signature. Both fixed from the ADR's text. `T-60` then passed at 0 |
| 60-minute incident window gave 1.1:1 compression | Measured the stream: repeat trips run a median **5.7 h** apart. An episode is a day. 24 h window → 21.6:1 |
| Correlated `EXISTS` with a range predicate | Snowflake: *"Unsupported subquery type"*. Rewritten as joins over daily rollups |
| Wrote a warehouse-runtime Streamlit deployment | The SiS skill mandates container runtime via `snow streamlit deploy`. Replaced before first deploy |
| Stale `pyproject.toml` on the stage | Would force PyPI resolution and break the app without an EAI. `--prune` added to the recipe |
| `st.connection("snowflake", connection_name=…)` | *"multiple values for keyword argument"* — documented in the skill's troubleshooting table |
| Named bind parameters | Connector default is `qmark`; converted to positional lists — still bound, never interpolated |
| `DECIMAL` columns | Altair silently typed them as **categories**; a numeric chart would have rendered as labels. Coerced to float in the query helper |

**The `T-60` story is the one worth telling.** The first classifier looked plausible and produced a
funnel. It was also hiding nine failures, and the only reason that isn't in the demo is a gating test
written before the code, whose bound is zero.

## 6. Cost

| Source | Credits |
| --- | --- |
| CoCo token credits, cumulative on `BGTCHIX` (533 requests) | 69.75 |
| Warehouse, last 12 h (full stack + 108M-row seed + ML + engine + app; lagged) | ≈ 1.31 |
| **Cumulative on `BGTCHIX`** | **≈ 74** — **past the second $100 alert** at list rates |

`ACCOUNT_USAGE` lags up to three hours, so both figures under-count this session.

## 7. Traceability

Branch `feat/nk/app-and-serving`. No given document modified.
