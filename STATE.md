# Current state — read this first, update it last

> **Last updated:** 2026-09-25 · **by:** SB · **CoCo session:** `1a36e460-4f53-47db-bfc8-052cc16e89c0`
> **Plan day:** D8 (generator + model built; `T-10` passed) · **Branch:** `feat/sb/deploy-ml`

**This file holds status, never intent.** Intent lives in `docs/`. If the two disagree: `docs/` wins on
*what we are building*, this file wins on *how far we got*. Overwrite sections in place — never append.
Full protocol in [`AGENTS.md`](AGENTS.md#session-protocol).

---

## 1. Gates

| Gate | State | Blocking |
| --- | --- | --- |
| **G1** — data is honest (D4) | **PASSED** — 16/16 data assertions green **and `T-10` passes** | — |
| **G2** — the model is real (D9) | **Nearly passed** — 8 ML assertions green incl. `T-10` at **1.71×** the trivial rule and a stability bound. Missing the anomaly detector (`US-22`, `T-18`) and `T-94`'s surface | `US-22`; `T-94` needs the app |
| **G3** — answers are trustworthy (D9) | Not started | G2 |
| **G4** — actions are safe (D12) | Not started | — |
| **G5** — demo-ready and submittable (D15) | Not started | all |

Gate definitions: [`testing-and-validation.md`](docs/07-quality/testing-and-validation.md).
**18 gating tests** — 4 run and passing: `T-8`, `T-10`, `T-11`, `T-16`. **`T-10` was the D4 decision
point and it passed**, so the generator stands and work continues rather than stopping to fix it.
Non-gating and green: `T-1`, `T-7`, `T-9`, `T-12`…`T-15`, `T-17`, `T-19`, `T-62`, `T-64`…`T-67`.
`just verify` runs both suites — 16 data + 7 ML assertions — and exits non-zero on any failure.

## 2. In flight — claim before you start

Claim a row *before* you begin, push it, and clear it when the work merges. An empty table means
nobody is mid-flight. A merge conflict here means two people claimed the same work — talk, do not
merge both.

| Owner | Story / test IDs | Branch | Claimed | Notes |
| --- | --- | --- | --- | --- |
| — | — | — | — | Nobody mid-flight. `feat/sb/deploy-ml` is in review |

## 3. Next actions, in order

Taken from [`project-plan.md`](docs/08-delivery/project-plan.md) D1. Do not re-derive the plan here —
just the next three things, each with the ID that proves it done.

1. **The anomaly detector** (`US-22`, `T-18`) — the second, independent signal `ml-models.md` §2
   requires. Without it `G2` is not passed and the classifier is the only signal we have.
2. **Curated layer** (`US-9`, `US-11`, `US-12`, `US-93`) — matched-band join, operating state,
   one dynamic table with `TARGET_LAG`. Features currently read `RAW` directly (§7).
3. **Metric layer + hand-worked fixtures** (`US-13`…`US-17`, `T-20`…`T-22`) — availability, lost
   energy, LD exposure, OEE. `G3` depends on it.

`Q-39` (Streamlit) is **closed** — verified working on 2026-09-18, ahead of D1.

## 4. Blocked / needs a human decision

| ID | Question | Owner | Blocks |
| --- | --- | --- | --- |
| `Q-78` | `WOA_SCHEDULER` — which role do automations run as? | NK | D1, `NFR-3` |
| `Q-90` | Which practitioner takes the D2 sanity-check call? | NK | D2, scenario credibility |
| `Q-6` | Fourth team member — confirmed or not? | NK | capacity (`R-1`) |
| `Q-84` | The model scores **precision 1.000 / PR-AUC 0.988** on held-out data. No leakage found (observable-only features, component-disjoint split, `DQ-NO-ID-FEATURE` green), so the honest reading is that the **generator's damage→feature mapping is too clean** — `ADR-0006`'s honesty constraint prescribes more noise. Whose call, and before or after the metric layer? | SA | the strength of the `T-10` claim |

Full register: [`raid-log.md`](docs/08-delivery/raid-log.md). Only list here what blocks *the next
action*; the RAID log holds the rest.

## 5. What actually exists in Snowflake right now

**The section git cannot tell you, and the one that wastes the most time when stale.** Update it
whenever you create or drop an object.

> **The account was found EMPTY on 2026-09-24.** We are still on `JKDRJBB-MW27072`
> (locator `EB28292`), but the `WIND_OPS_AI_DEV_KR` database, the nine `WOA_*` roles and both
> warehouses recorded here on 2026-09-22 **did not exist**. Everything below was re-deployed from
> the recipes. Recorded in §7.
>
> **CoCo and the CLI are on different accounts.** The CoCo conversation is bound to
> `HHWOUEB-WQ04283`; `snow` uses `SNOWFLAKE_DEFAULT_CONNECTION_NAME=jkdrjbb-mw27072`. Deploys go
> to `JKDRJBB-MW27072`. Token credits bill to one account and warehouse credits to the other, so
> **cost must be summed across both** (§6).

| Thing | State |
| --- | --- |
| Databases | `WIND_OPS_AI_DEV_SB` — SB's dev clone, deployed 2026-09-24, **holds the full generated dataset**. `WIND_OPS_AI_DEV_JP` — foundation + dimensions only, no facts. `WIND_OPS_AI` (shared) not created |
| Schemas | 10 per database: GEN, RAW, CURATED, SERVING, ML, ENGINE, ACTION, DOCS, OPS, APP — all owned by WOA_ADMIN |
| Roles | 9 `WOA_*` roles: ADMIN, APP, AGENT, SCHEDULER, ENGINEER, RMC, PLANNER, EXEC, TECH. Hierarchy and grants applied |
| Warehouses | `WOA_APP_WH`, `WOA_BUILD_WH` — both XSMALL, auto-suspend 60s |
| RAW dimensions | 14, all seeded: `DIM_COMPONENT_CLASS` (10), `DIM_PLATFORM` (2), `DIM_SITE` (6), `DIM_CONTRACT` (6), `DIM_EXCLUSION_CLASS` (5), `DIM_TURBINE` (100), `DIM_COMPONENT` (1,000), `DIM_COMPONENT_GENEALOGY` (1,057 — 1,000 installs + 57 replacements), `DIM_SIGNAL` (4,100), `DIM_ALARM_CODE` (31), `DIM_FAILURE_CODE` (26), `DIM_CREW` (8), `DIM_PART` (19), `DIM_STOCK` (76) |
| RAW facts (in `_SB`) | `FCT_SIGNAL_10MIN` **108,339,384** · `FCT_CMS_FEATURE` **3,524,000** · `FCT_ALARM_NORMALISED` **~340,040** · `FCT_TURBINE_STATE` **18,958** · `FCT_WORK_ORDER` **452** · `FCT_PART_MOVEMENT` **58** |
| GEN objects | `GEN_DAMAGE_STATE` (184,000) · `GEN_TURBINE_DAY` (18,400) · `GEN_FAILURE_EVENT` (**58 seeded failures**) · `GEN_CMS_THRESHOLD` (8) · `GEN_SEEDED_PATTERN` (5) · `GEN_RUN_CONFIG` (run log) |
| GEN functions | `FN_RAND`, `FN_WIND_SPEED`, `FN_EXPECTED_POWER`, `FN_RPM_BAND`, `FN_LOAD_BAND`, `FN_DAMAGE_RATE`; view `GEN_SITE_STRESSOR` |
| GEN procedures | `SP_GENERATE_OPERATING_CONTEXT`, `SP_GENERATE_DAMAGE`, `SP_GENERATE_SIGNALS`, `SP_GENERATE_CMS_FEATURES`, `SP_GENERATE_TURBINE_STATE`, `SP_GENERATE_ALARMS`, `SP_GENERATE_CONSEQUENCES`, `SP_GENERATE_ALL` |
| OPS objects | `DQ_ASSERTION` (16 catalogued) · `DQ_RESULT` (run history) · `SP_RUN_DATA_QUALITY` · `SP_ASSERT_QUALITY_GATE` |
| ML objects | `RISK_CLASSIFIER` (`SNOWFLAKE.ML.CLASSIFICATION`) · `FEAT_COMPONENT_DAILY` (61,009 component-days, 1,259 positive) · `SCORE_COMPONENT_RISK` (400 scored) · `DRIVER_COMPONENT_RISK` (2,000 rows) · `ML_BASELINE_SPEC` (2 pre-registered baselines) · views `V_ML_SPLIT`/`V_ML_TRAIN`/`V_ML_TEST` · procedures `SP_BUILD_FEATURES`, `SP_TRAIN_RISK_CLASSIFIER`, `SP_EVALUATE_RISK_CLASSIFIER`, `SP_SCORE_COMPONENTS` |
| OPS additions | `ML_RUN` (training runs) · `ML_METRIC` (held-out metrics for `T-87`) · `SP_RUN_ML_QUALITY` |
| Semantic views, search services, agents, dynamic tables, anomaly detector | **None** |
| Re-verified as *possible* on `JKDRJBB-MW27072` | `AI_COMPLETE('claude-sonnet-4-5')`, `AI_COMPLETE('llama3.1-8b')`, `SNOWFLAKE.CORTEX.COMPLETE`, `AI_EXTRACT`, `SNOWFLAKE.ML.CLASSIFICATION`, `ANOMALY_DETECTION`, `DOCUMENT_INTELLIGENCE`, `FORECAST`, `TOP_INSIGHTS`, `CREATE COMPUTE POOL`. Account params: `CORTEX_ENABLED_CROSS_REGION = ANY_REGION`, `ENABLE_CORTEX_ANALYST = true` |
| **Still not proven** | `CREATE SEMANTIC VIEW`, `CREATE CORTEX SEARCH SERVICE`, `CREATE DYNAMIC TABLE`, `CREATE AGENT`, `CREATE STREAMLIT`, `AI_PARSE_DOCUMENT`, `CREATE SERVICE`. Now that a database exists, these can be probed |
| Verified as **not** working | `claude-4-sonnet`, `mistral-large2`, `openai-gpt-4.1` (legacy names). `CREATE APPLICATION SERVICE` unavailable on trial accounts ([`ADR-0020`](docs/03-architecture/decisions/adr-0020-app-platform.md)) |
| Untested | Notification integrations; MCP connector; `st.components` HTML inside SiS |
| Other | `SNOWFLAKE_INTELLIGENCE` database does **not** exist — the agent needs `SNOWFLAKE_INTELLIGENCE.AGENTS` ([`04-code.md`](docs/03-architecture/04-code.md) §2) |

Account `JKDRJBB-MW27072` (locator `EB28292`) · region `AZURE_CENTRALINDIA` · trial, **$400 budget**.
Naming authority: [`04-code.md`](docs/03-architecture/04-code.md).

**Every object here was created by a `just` recipe** — see
[AGENTS.md · Deployment](AGENTS.md#deployment). If something exists in the account that no recipe
creates, that is a defect: record it in §7 and fold it into a recipe.

## 6. Budget

**Two accounts, and both must be summed.** CoCo token credits are billed in
`HHWOUEB-WQ04283` (where the conversation runs); warehouse credits in `JKDRJBB-MW27072` (where
SQL runs). Neither account alone shows what a session cost.

| Source | Account | Credits |
| --- | --- | --- |
| CoCo token credits (`CORTEX_CODE_DESKTOP_USAGE_HISTORY.TOKEN_CREDITS`, 2-day window, 299 requests) | `HHWOUEB-WQ04283` | 41.65 |
| Warehouse (`WAREHOUSE_METERING_HISTORY`, 2-day window) | `JKDRJBB-MW27072` | 2.28 |
| **Total observed** | — | **≈ 43.9** |

Generating 108M rows cost ~1.5 credits; training, evaluating and scoring the model cost under
half a credit. The conversations that produced the code cost ~41.7. The ratio is now near
**18:1** overall and **50:1** for the ML session — **warehouse metering alone under-reports by
an order of magnitude, and the gap widens as the SQL gets cheaper and the reasoning harder.**
Alert NK at each $100.

`ACCOUNT_USAGE` lags up to three hours, so the current session is never fully reflected. The
column is `TOKEN_CREDITS`, not `CREDITS`, and there are no `INPUT_TOKENS`/`OUTPUT_TOKENS`
columns — see [`evidence/development/03`](docs/06-coco/evidence/development/03-synthetic-data-generator.md) §1
for the real column list.

## 7. Deviations from the plan

Anything built differently from `docs/`, with where it was recorded. If this table has an entry with no
ADR or RAID reference, that is a defect.

| What changed | Recorded in |
| --- | --- |
| **Account moved** from `BGTCHIX-UZ86048` to `JKDRJBB-MW27072` (same region). Invalidates the planning-phase capability evidence and resets the credit budget | §5 and §6 above; [`deployment.md`](docs/03-architecture/deployment.md) §1. **Needs a RAID entry — `Q-41` (who holds the elevated credential) is now open against a different account** |
| **The account was found empty on 2026-09-24.** Every object recorded in §5 on 2026-09-22 was gone; all of it was re-deployed from the recipes into `WIND_OPS_AI_DEV_SB` | §5 above; [`evidence/development/03`](docs/06-coco/evidence/development/03-synthetic-data-generator.md) §5. **Needs a RAID entry — trial-account object lifetime is now a delivery risk** |
| **`03_seed_dimensions.sql` had never run successfully.** A broken `INSERT` sat above a rewrite of itself, so the script aborted at compilation; the dimension counts in evidence 02 were intent, not observation | [`evidence/development/03`](docs/06-coco/evidence/development/03-synthetic-data-generator.md) §5 |
| **Every `snow sql` call pinned to `--enable-templating STANDARD`.** LEGACY templating reads a bare `&IDENT` in *data* as a variable; `'C&I'` in `DIM_CONTRACT` aborted the seed | `justfile` `snow_sql` variable, with the reasoning inline |
| **The generator is set-based SQL, not Snowpark.** [`04-code.md`](docs/03-architecture/04-code.md) §7 anticipates `python/generator/`; the work is bulk set manipulation that never needs to leave the warehouse, and §9's rule ("engine logic stays in SQL") points the same way. `python/` still does not exist | This row; [`04-code.md`](docs/03-architecture/04-code.md) §7 **needs updating or an ADR** |
| **`FCT_SIGNAL_10MIN` holds ~108M rows, not the documented ≈2.6M.** [`data-sources`](docs/04-data/data-sources-and-synthetic-data.md) §3's figure assumes one row per turbine-interval (a WIDE table); `Q-46` chose a LONG table, so 4,100 tags at 10-minute grain over 183 days is ~108M. Same information, ~40× the rows. Measured cost: ~4.5 min and ~1.5 credits on an XSMALL | This row; `interval_min` is a `just seed` parameter so the grain can be coarsened |
| **Alarms ~340k against a documented ≈400k, and work orders 452 against ≈1,500.** Not padded to hit the targets: inventing rows that correspond to no event would defeat the purpose of the fixtures | This row; [`evidence/development/03`](docs/06-coco/evidence/development/03-synthetic-data-generator.md) §7 |
| **A 60-day burn-in on initial damage.** No component may cross its failure threshold in the first 60 days of the window, because a failure with no lead-in history cannot honestly be predicted — and `T-8` asserts *every* failure trends | `sql/10_generate/06_damage_and_failures.sql` header |
| **`sql/15_quality/` added** as a deployment stage, and `DQ_<subject>` / `GEN_<subject>` naming registered | [`04-code.md`](docs/03-architecture/04-code.md) §3 and §7; [`deployment.md`](docs/03-architecture/deployment.md) §3 |
| **Determinism is exact except for the alarm count.** Signals, CMS features, failures and work orders are bit-identical across runs with the same seed; the alarm total moves by a few rows because the nuisance stream is clamped to `NOW` and the window end tracks wall-clock time, which `T-11` requires | [`evidence/development/03`](docs/06-coco/evidence/development/03-synthetic-data-generator.md) §5 |
| **`sql/25_ml/` added** as a deployment stage, and the ML layer is **set-based SQL, not the Snowpark `python/ml/`** the code layout anticipates. `ADR-0007` already chose `SNOWFLAKE.ML.CLASSIFICATION`, `04-code.md` §9 says engine logic stays in SQL, and the features are aggregates over 108M rows that need not leave the warehouse | [`04-code.md`](docs/03-architecture/04-code.md) §7 **needs updating or an ADR**, same as the generator row above |
| **Drivers are NOT model feature importances.** `RISK_CLASSIFIER!SHOW_FEATURE_IMPORTANCE()` and `!SHOW_EVALUATION_METRICS()` both error in this account (reproduced on a clean probe model). Importance is a **train-split standardised mean difference**, and every row records `IMPORTANCE_METHOD` so nothing can present it as a per-prediction attribution. Weaker than [`ml-models.md`](docs/05-ai-ml/ml-models.md) §6 specifies | [`evidence/development/04`](docs/06-coco/evidence/development/04-risk-classifier.md) §5 |
| **`T-10` is judged at TWO operating points, not one.** At the trivial rule's own budget both methods reach 100% component recall, so that comparison discriminates nothing; a tight operational budget (2 alerts per failing component) was added and carries the verdict | `sql/15_quality/03_ml_assertions.sql` header; `Q-60` in §4 |
| ~~`SNOWFLAKE.ML.CLASSIFICATION` is not bit-deterministic~~ — **withdrawn.** The 0.353–0.706 swing was **measurement noise from ranking component-DAYS**, not model noise. With the component-level metric the spread is **zero across five retrainings**, and `DQ-STABILITY` now fails the build if it exceeds 0.05 | [`evidence/development/05`](docs/06-coco/evidence/development/05-t10-margin-and-operating-point.md) §5 |
| **`Q-60` and `Q-53` are CLOSED**, in the docs rather than only in code. `T-10` margin: model component precision ≥1.25× the rule's at no-lower recall and ≥3× random (measured **1.71×**). Operating point: `p >= 0.50` at component level | [`ml-models.md`](docs/05-ai-ml/ml-models.md) §10, [`testing-and-validation.md`](docs/07-quality/testing-and-validation.md), [`raid-log.md`](docs/08-delivery/raid-log.md) |
| **The model may be too good for the data to be credible.** Precision 1.000 / PR-AUC 0.988 with no leakage found. The remedy is more generator noise (`ADR-0006` honesty constraint), not model changes | `Q-84` in §4; [`evidence/development/05`](docs/06-coco/evidence/development/05-t10-margin-and-operating-point.md) §5 |
| **ML features read `RAW` directly**, not `CURATED`, because the curated layer does not exist yet. The matched-band control `US-9` calls for is satisfied by the generator writing `rpm_band`/`load_band` onto CMS rows | This row; revisit when `20_curate` lands |
| **`T-11` freshness is grain-aware.** Daily-grain generator state cannot meet a 24h bar after midday, so it gets 48h while the fact surfaces an operator reads keep 24h | `sql/15_quality/02_assertions.sql` |

## 8. Latest evidence entry

[`docs/06-coco/evidence/development/05-t10-margin-and-operating-point.md`](docs/06-coco/evidence/development/05-t10-margin-and-operating-point.md)
— closes `Q-60` and `Q-53`, and **corrects entry 04's headline**. Three successive metric defects
were found, each flattering a different side; the real result is **model component precision 1.000
vs the trivial rule's 0.586 at identical recall 1.000** — 1.71× against a 1.25× bar, stable to zero
spread over five retrainings. New `DQ-STABILITY` fails the build if the headline moves more than
0.05, so a lucky run cannot be quoted.

Previous: [`development/04-risk-classifier.md`](docs/06-coco/evidence/development/04-risk-classifier.md)
(partly superseded).

Next entry goes in `docs/06-coco/evidence/development/06-<slug>.md`, after the anomaly detector.
