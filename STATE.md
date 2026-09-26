# Current state — read this first, update it last

> **Last updated:** 2026-09-26 · **by:** NK · **CoCo session:** `04d1ee7a-0e99-44de-afb6-40f838e591e6`
> **Plan day:** D9 · **Working account: `BGTCHIX-UZ86048`** (moved here 2026-09-26, per NK) · **Branch:** `feat/nk/numbers-and-gates`
> **The app exists:** `WIND_OPS_AI_DEV_NK.APP.WOA_COMMAND_CENTER` — https://app.snowflake.com/BGTCHIX/uz86048/#/streamlit-apps/WIND_OPS_AI_DEV_NK.APP.WOA_COMMAND_CENTER
> **The agent exists:** `WIND_OPS_AI_DEV_NK.GEN.WOA_OPS_AGENT` — Snowsight › AI & ML › Agents

**This file holds status, never intent.** Intent lives in `docs/`. If the two disagree: `docs/` wins on
*what we are building*, this file wins on *how far we got*. Overwrite sections in place — never append.
Full protocol in [`AGENTS.md`](AGENTS.md#session-protocol).

---

## 1. Gates

Gate names follow [`testing-and-validation.md`](docs/07-quality/testing-and-validation.md) § gates. Until 2026-09-26 this file
called the agent work "`G3`"; the plan's `G3` is **the numbers**, and that was not built until evidence 10.

| Gate | State | Blocking |
| --- | --- | --- |
| **G1** — data is worth modelling (D4) | **PASSED** — 16 assertions | — |
| **G2** — the model is real (D9) | **PASSED** — 13 assertions: `T-10` **1.76×**, `T-18` ρ **0.243**, **`T-87`** (scores come from the run the app displays), **`T-94`** (the rule-vs-model comparison reconciles to that run) | — |
| **G3** — the numbers are trustworthy (D9) | **PASSED** — 10 assertions, 7 gating: hand-worked fixtures **`T-20`** (availability, 95→97% step), **`T-21`** (lost energy), **`T-22`** (LD = ₹260,959, the business case's ≈ ₹2.6 L); **`T-23`** OEE = A × P on all 100 turbines; **`T-24`** semantic view = metric views on 6 metrics; **`T-25`** no constant factor; `GS-5` caught | the agent leg of `T-24` is shown in evidence, not gated (needs a model call) |
| **G4** — action is safe (D12) | **PASSED (except `T-71`, `T-74`)** — approval core (evidence 09), **`T-47`** (DDL/DELETE/UPDATE as `WOA_AGENT` refused), **`T-48`** (agent read-only), **`T-33`** now also covers `WOA_SCHEDULER` | `T-71` (no window engine), `T-74` (confirm/dismiss/reinstate), `T-76` behavioural half (no scheduled task) |
| **G5** — demo-ready (D15) | **Built, not yet submittable** — app with OEE, writes and *Audit*; **`T-86`** funnel reconciles (every one of 340,431 alarms in exactly one incident); **`T-92`/`T-95`** `just results` generates `docs/08-delivery/results.md`; `T-52` see §7; `T-37`/`T-42` answer-quality checks | README (`T-89`), walkthrough (`T-90`), deck, `T-93` |

`just verify` runs **six** suites — **16 data + 10 ML + 5 engine + 5 answers + 10 numbers + 12 action = 58
assertions**, plus the behavioural role checks (`T-33` × 3 roles, `T-47` × 5 statements) — and exits non-zero on
any failure. `just results` prints the same tally from `OPS`.

## 2. In flight — claim before you start

Claim a row *before* you begin, push it, and clear it when the work merges. An empty table means
nobody is mid-flight. A merge conflict here means two people claimed the same work — talk, do not
merge both.

| Owner | Story / test IDs | Branch | Claimed | Notes |
| --- | --- | --- | --- | --- |
| NK | `G3` numbers (`T-20`…`T-25`), `GS-5` seed, `T-47`, `T-86`, `T-87`, `T-94`, `just results`, `just deploy` + `T-52` — **done, in review** | `feat/nk/numbers-and-gates` | 2026-09-26 | Clear this row when the PR merges |

## 3. Next actions, in order

Do not re-derive the plan here — just the next things, each with the ID that proves it done. **These three
are independent and should run in parallel across the team.**

1. **Submission surface** — judge-facing README (`T-89`: a stranger reaches a working system from it), 2-minute
   walkthrough (`T-90`), deck, `T-93` criteria map. **Build `results.md` first** with `just results` and quote
   it, never retype. Demo beats: a protection trip refused; one work order however many clicks; the three
   yaw-misaligned turbines that availability calls healthy (OEE tab); the *Audit* tab.
2. **Put the agent in the app** — an *Ask* tab calling `GEN.WOA_OPS_AGENT`, showing citations.
3. **The window engine** (`FR-33`, `ENG_WINDOW_CANDIDATE`) — drafts say `NOT_SCHEDULED` until it exists,
   and `T-71` cannot run without it.

Then: fold risk into `ENG_INCIDENT.is_elevated` (`I-19`); verified queries for `VQ-1`, `VQ-4`, `VQ-5`, `VQ-7`;
`T-74` decision paths; curated layer + one dynamic table (`M12`); widen detector coverage (`I-15`);
`just cost` and `just update` are still placeholders.

## 4. Blocked / needs a human decision

| ID | Question | Owner | Blocks |
| --- | --- | --- | --- |
| `Q-78` | `WOA_SCHEDULER` — which role do automations run as? | NK | D1, `NFR-3` |
| `Q-90` | Which practitioner takes the D2 sanity-check call? | NK | D2, scenario credibility |
| `Q-6` | Fourth team member — confirmed or not? | NK | capacity (`R-1`) |
| `Q-84` | The model scores **precision 1.000 / PR-AUC 0.988** on held-out data with no leakage found, so the **generator's damage→feature mapping is too clean** (`ADR-0006` honesty constraint). Raise generator noise, and re-run `T-8` and `T-10` together — they pull in opposite directions | SA | the credibility of the `T-10` claim |

**Deferred, tracked, not blocking the next action.** Six issues and two risks were logged from the
generator and ML work: `I-7` (model too good for the data), `I-8` (drivers are not model feature
importances — the platform accessors error), `I-9` (`04-code.md` §7 expects `python/`, we built
SQL), `I-10` (ML features read `RAW`, not `CURATED`), `I-11` (`just pr --fill` mis-titles
multi-commit PRs), `I-12` (`T-94`/`T-86`/`T-87` have numbers but no surface, so `G5` is blocked
behind `deploy-app`), plus `R-30` (trial-account objects do not survive — rehearse the ~15 min
recovery before the demo) and `R-31` (CoCo and the CLI are on different accounts, so cost must
always be summed across both). Full detail in [`raid-log.md`](docs/08-delivery/raid-log.md).

Full register: [`raid-log.md`](docs/08-delivery/raid-log.md). Only list here what blocks *the next
action*; the RAID log holds the rest.

## 5. What actually exists in Snowflake right now

**The section git cannot tell you.** Update it whenever you create or drop an object.

> **Working account is now `BGTCHIX-UZ86048`** (locator `LM21871`, `AZURE_CENTRALINDIA`, trial, $400).
> Moved on 2026-09-26 at NK's direction, so the team stops waiting on a credential for `JKDRJBB-MW27072`.
> Everything below was deployed **from the recipes** — `just deploy-foundation → deploy-data → seed →
> deploy-ml → deploy-engine → deploy-app`, about 20 minutes end to end. The objects previously recorded on
> `JKDRJBB-MW27072` and `EXKFAFL-NW77746` still exist there but are **no longer the project's state**.
>
> **To deploy here you need a non-interactive connection.** NK's is `woa_bgtchix` (JWT key-pair, `I-16`).
> Teammates: create your own key-pair, or ask NK. `SNOWFLAKE_DEFAULT_CONNECTION_NAME=<yours> just target`.

| Thing | State on `BGTCHIX-UZ86048` |
| --- | --- |
| Database | **`WIND_OPS_AI_DEV_NK`** — full stack. `WIND_OPS_AI` (shared) **not created** |
| Roles / warehouses | 9 `WOA_*` roles with hierarchy and grants · `WOA_APP_WH`, `WOA_BUILD_WH` (XSMALL, 60 s suspend) |
| RAW | 14 dimensions seeded · `FCT_SIGNAL_10MIN` ~108.3M (**3 turbines' power and yaw edited in place by the `GS-5` seed**) · `FCT_CMS_FEATURE` ~3.5M · `FCT_ALARM_NORMALISED` **340,431** · `FCT_TURBINE_STATE` · `FCT_WORK_ORDER` · 58 seeded failures |
| ML | `RISK_CLASSIFIER` · `ANOMALY_DETECTOR` · `FEAT_COMPONENT_DAILY` · `SCORE_COMPONENT_RISK` (**400, as of 2026-08-26, 6 HIGH**) · `DRIVER_COMPONENT_RISK` · `SCORE_COMPONENT_ANOMALY` (48,813) · `ML_BASELINE_SPEC` · `ML_INDEPENDENCE_SPEC` · **`V_SCORING_ASOF`** |
| SERVING | `V_WINDOW` · `MET_AVAILABILITY_CONTRACTUAL` · **`MET_AVAILABILITY_TECHNICAL`** · `MET_LD_EXPOSURE` (run-rate) · **`MET_TURBINE_OEE`** (A × P, Quality NULL) · **`MET_LOST_ENERGY`** · **`MET_NOISE`** · `FN_AVAILABILITY_PCT`, `FN_GUARANTEE_PCT`, `FN_LD_RUN_RATE_INR`, `FN_INTERVAL_KWH` (the arithmetic the fixtures test) · `SP_BUILD_TURBINE_DAY` · **`SV_WIND_OPS`** (8 tables, 7 relationships) |
| CURATED | **`AGG_TURBINE_DAY`** (18,400 turbine-days from the 10-minute signals). First object in `CURATED` |
| DOCS | `MAINTENANCE_DOCS` stage (SSE, **11 PDFs**) · `DOC_PARSED` (11) · `DOC_CHUNK` (**53 section chunks**) · `DOC_PART_PROCEDURE` (13 parts → procedure) · `SP_PARSE_DOCUMENTS` · **`CSS_MAINTENANCE_DOCS`** (Cortex Search) |
| GEN | **`WOA_OPS_AGENT`** — Cortex Agent, `claude-sonnet-4-5`, two read-only tools (`fleet_data` → `SV_WIND_OPS`, `maintenance_docs` → `CSS_MAINTENANCE_DOCS`) |
| ENGINE | `ENG_INCIDENT` (**15,803**) · `SP_BUILD_INCIDENTS` · `ENG_SUPPRESSED_FAILURE` (**0 rows**) · `ENG_ALARM_FUNNEL` · `ENG_ALARM_FUNNEL_DAILY` · `ENG_ALERT_RANKED` |
| ACTION | `AUD_ACTION` (append-only audit, refusals included) · `ACT_SUPPRESSION` · `ACT_WORK_ORDER_DRAFT` · `ACT_WORK_ORDER` · `ACT_DECISION` · `ACT_V_SUPPRESSION_ACTIVE` · five owner's-rights procedures (`SP_APPROVE_SUPPRESSION`, `SP_REVOKE_SUPPRESSION` → `WOA_RMC`; `SP_DRAFT_WORK_ORDER`, `SP_APPROVE_WORK_ORDER`, `SP_REJECT_WORK_ORDER_DRAFT` → `WOA_PLANNER`). Self-test rows are marked `IS_SELFTEST` and hidden by the app |
| OPS | `DQ_ASSERTION` (**58**) · `DQ_RESULT` · `ML_RUN` · `ML_METRIC` · six `SP_RUN_*_QUALITY` · `SP_ASSERT_QUALITY_GATE` · `OPS_TEST_HOOK` (`FAIL_AUDIT`, **off**; asserted) |
| APP | **`WOA_COMMAND_CENTER`** — Streamlit, **warehouse runtime** `SYSTEM$WAREHOUSE_RUNTIME`, Streamlit 1.52.2 from the Anaconda channel, warehouse `WOA_APP_WH`, source on `APP.WOA_APP_STAGE`. 5 tabs; writes via the ACTION procedures only |
| **Not yet built** | window engine (`ENG_WINDOW_CANDIDATE`) · verified queries · dynamic tables · notification integration · scheduled task · the app's *Ask* tab |
| Proven possible here | `CREATE SEMANTIC VIEW` · `CREATE CORTEX SEARCH SERVICE` · `CREATE AGENT` + `DATA_AGENT_RUN` · `AI_PARSE_DOCUMENT` (LAYOUT, SSE stage) · `CREATE STREAMLIT` (warehouse runtime; container runtime creates but **cannot boot** without egress) · `ANOMALY_DETECTION` multi-series + `DETECT_ANOMALIES` · `ML.CLASSIFICATION` `PREDICT` · compute pools · `CREATE SERVICE` · models `claude-sonnet-4-5`, `llama3.1-8b` |
| Proven NOT possible | `CREATE APPLICATION SERVICE` (trial account, `ADR-0020`) · **`CREATE EXTERNAL ACCESS INTEGRATION`** (trial account) — so no PyPI, no MCP egress, no outbound calls from the app · `!SHOW_FEATURE_IMPORTANCE()` on the classifier (`I-8`) · legacy model names `claude-4-sonnet`, `mistral-large2`, `openai-gpt-4.1` |
| Still unproven | `CREATE DYNAMIC TABLE` — verified during planning on this same account, not re-probed since |

Naming authority: [`04-code.md`](docs/03-architecture/04-code.md). **Every object here was created by a `just`
recipe** — see [AGENTS.md · Deployment](AGENTS.md#deployment).

## 6. Budget

| Source | Credits |
| --- | --- |
| CoCo token credits on `BGTCHIX` (`CORTEX_CODE_DESKTOP_USAGE_HISTORY`, cumulative, data through 05:40 UTC 2026-09-26) | **94.90** |
| Warehouse on `BGTCHIX` (`WAREHOUSE_METERING_HISTORY`, cumulative) | **11.65** |
| **Total on `BGTCHIX`** | **≈ 106.6** |
| *Also spent elsewhere, not on the $400:* `JKDRJBB-MW27072` ≈ 43.9 (SB, KR, JP sessions) · `EXKFAFL-NW77746` ≈ 0.6 (NK, personal) | |

**≈ 106.6 credits — roughly $288** at the conversion used for earlier alerts (≈ 74 credits ≈ $200). With the
three-hour `ACCOUNT_USAGE` lag, **treat the $300 alert as reached (NK told 2026-09-26)**; ≈ $110 remains.
`just results` prints this table from source. The two `T-52` builds cost ≈ 3 warehouse credits together;
reasoning still dominates. Always sum both sources. Alert NK at each $100.

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

| **The anomaly detector was verified on a DIFFERENT ACCOUNT.** `snow` was not installed locally and `connections.toml` has no `JKDRJBB-MW27072` entry, so the whole stack was re-deployed from the recipes into `WIND_OPS_AI_DEV_NK` on `EXKFAFL-NW77746` and verified there. Reproduction matched closely (108,317,900 signal rows vs 108,339,384; 58 failures; `T-10` 1.7647× vs 1.71×). **The team must re-run `just deploy-ml` on the deploy account before quoting these figures** | `I-14`; [`evidence/development/06`](docs/06-coco/evidence/development/06-anomaly-detector.md) §1 |
| **`T-18`'s population is the detection window, not `SCORE_COMPONENT_RISK`.** The planner snapshot gave ρ = 0.216, which **passed**, but its risk variance is 1e-12 so the number described nothing. The population changed; the pre-registered bound did not. Both figures are in `OPS.ML_METRIC` so the claim is checkable | `I-13`; [`ml-models.md` §2.1](docs/05-ai-ml/ml-models.md#21-the-t-18-bound-and-what-it-is-measured-on) |
| **`sql/25_ml/05_anomaly.sql` added**, and `ML.ML_INDEPENDENCE_SPEC` / `SCORE_COMPONENT_ANOMALY` registered as naming-convention instances of `04-code.md` §3 (`SCORE_<subject>`). No new deployment stage was needed | This row; `04-code.md` §3 |

| **Working account moved to `BGTCHIX-UZ86048`**, at NK's direction, so the team stops waiting on a `JKDRJBB-MW27072` credential. Full stack rebuilt from the recipes in ~20 min | §5; `I-16` |
| **Risk is scored as of `window_end − horizon`**, not the last feature date (`I-13`). The app states the as-of date on every risk figure | `ML.V_SCORING_ASOF`; `raid-log.md` `I-13` |
| **`30_serve/` and `40_engine/` exist but hold first cuts.** Availability and LD exposure have no hand-worked fixtures yet (`T-20`…`T-22`); the alarm engine has no approval path | This row |
| **The *Suppress* button is read-only.** It runs every guard and shows the refusal, but writes nothing — approval-gated writes (`M10`) are not built, and the UI says so | `app/streamlit_app.py` |
| **Incident window is 24 h, and nuisance requires the component to be monitored and the code not to recur within 14 days** — two conditions ADR-0017 states and the first cut omitted. The first cut hid 9 real failures | `sql/40_engine/01_alarm_incidents.sql` header; evidence 07 §5 |

| **The app runs on the WAREHOUSE runtime, set explicitly — not the container runtime.** The container runtime installs every package from `pypi.org` at boot, and this trial account **cannot have external access**. Proven three ways: no `pyproject.toml` (runtime refuses to start), an empty one (*Streamlit library not found*), a real one (*DNS failure reaching pypi.org*). The warehouse runtime installs `environment.yml` from Snowflake's own Anaconda channel (Streamlit 1.52.2). `snow streamlit deploy` kept choosing the container runtime even on a clean recreate — Snowflake is moving new apps to default to it — so `deploy-app` now creates the app in SQL with `RUNTIME_NAME = 'SYSTEM$WAREHOUSE_RUNTIME'` and **asserts the runtime** after every deploy | `sql/80_app/`; `I-17` |

| **The semantic view and the agent are hand-written DDL**, not generated by the `agent-studio` skill. Its generator and its agent tooling need the Cortex CLI, which is not installed here; NK chose DDL through `just`. Every description was checked against the data (`DQ-SV-DESCRIBED`, `DQ-SV-SAMPLES-REAL`) | `sql/30_serve/02_semantic_view.sql`, `sql/70_agent/01_agent.sql` headers; evidence 08 §3 |
| **Documents are chunked by SECTION, not by the `search-optimization` skill's fixed 500-character pipeline**, which would cut sections in half and lose the headings a citation needs (`T-37`) | `sql/60_docs/02_search_service.sql` header |
| **Parser headings are normalised.** `AI_PARSE_DOCUMENT` LAYOUT marked headings with `##` in 6 of 9 identically styled PDFs and as plain text in 3. `SP_PARSE_DOCUMENTS` promotes the known heading shape; a no-op where the parser was right. Found by `DQ-DOC-SECTIONS` | `sql/60_docs/01_documents.sql`; evidence 08 §5 |
| **No verified queries yet.** The plan has ten `VQ-*` questions but no checked SQL for any; writing SQL for them unchecked would teach Analyst an unverified answer. Two were checked by hand against the engine in evidence 08 and are the first candidates | §3 above |
| **The documents are regenerated, not committed.** `data/maintenance_docs/` is git-ignored; `just deploy-agent` rebuilds the PDFs from `scripts/generate_maintenance_docs.py` | `.gitignore` |
| **Approval procedures are granted to the persona roles, not to `WOA_APP`.** `04-code.md`'s role table lists `USAGE on SP_APPROVE_*` under `WOA_APP`, but `WOA_RMC` inherits `WOA_APP` and must not approve work orders. Suppression → `WOA_RMC`; work orders → `WOA_PLANNER`; `WOA_APP` holds nothing on `ACTION` | `sql/50_action/03_action_grants.sql` header |
| **The app's writes are attributed to its owner, with the viewer as a label.** The app runs as `WOA_ADMIN` (owner's rights), which inherits both persona roles, so any viewer who can open the app can approve. `CURRENT_USER()` is recorded as the actor; the viewer's name goes in `ON_BEHALF_OF` beside it, not instead of it. Real per-person approval needs caller's rights or per-persona apps | `sql/50_action/02_action_procedures.sql` header; `ADR-0020` |
| **Work-order drafts are not scheduled.** No window engine exists, so every draft says `NOT_SCHEDULED`, and so does the app, rather than inventing a window. Approval writes `APPROVED_NOT_SCHEDULED` | `SP_DRAFT_WORK_ORDER` header |
| **`T-35`'s audit failure is injected**, through `OPS.OPS_TEST_HOOK.FAIL_AUDIT`, because it cannot be produced on demand otherwise. On for one call inside the self-test, and `DQ-FAULT-HOOK-OFF` (gating) fails the build if it is left on | `sql/15_quality/06_action_assertions.sql` header |
| **Three rows were deleted from `ACTION`**, the one exception to append-only: unaudited rows written by the first, invalid `T-33` test (`I-18`) | evidence 09 §5 |
| **Two procedures added to the corpus** (`VWS-MP-GEN-012` stator, `VWS-MP-PIT-015` pitch bearing), so that every part the risk ranking costs has a procedure a draft can cite | `scripts/generate_maintenance_docs.py`; `DQ-DRAFT-PROCEDURE-RESOLVES` |
| **Turbine OEE is Availability × Performance; Quality is NOT modelled.** No forecast schedule exists, so `ADR-0003`'s own fallback applies (NK's choice). `QUALITY_FACTOR` is NULL, never 1, and every row carries `OEE_DEFINITION` | `sql/30_serve/03_energy_and_oee.sql` header; `DQ-T23-OEE-IDENTITY` asserts the NULL |
| **`GS-5` underperformance was seeded after the fact** (NK's choice). The generator wrote power as `ideal × 0.965` for every running turbine, so Performance was a disguised constant. `SP_GENERATE_UNDERPERFORMANCE` gives 3 turbines a 9–14° yaw offset from day 75 (power × cos³, no alarm); it runs last in `SP_GENERATE_ALL`, so a fresh `just seed` reproduces it | `sql/10_generate/13_underperformance.sql`; `I-20` |
| **Performance is judged against the fleet median, not 100%.** The power curve is ideal (no conversion loss), so a healthy turbine reads ~96.5%; underperforming = more than 1.5 points below the median, and underperformance loss is measured from the median | `MET_TURBINE_OEE`, `MET_LOST_ENERGY` |
| **`T-52` ran on a scratch database, not with account teardown.** `just teardown` drops the shared `WOA_*` roles and warehouses as well as the database, which would destroy the live demo on this one account. `just deploy` ran twice into `WIND_OPS_AI_DEV_T52`, then the new `just teardown-db` dropped only that database. Account-level teardown remains **unexercised** | evidence 10 §3; `teardown-db` recipe |
| **Gate labels corrected.** The answer-quality assertions had been filed under `G3`; `T-48` is now `G4` and `T-37`/`T-42` are `G5`, so `G3` counts only the numbers | `sql/15_quality/05_g3_assertions.sql` |

## 8. Latest evidence entry

[`docs/06-coco/evidence/development/10-numbers-and-clean-builds.md`](docs/06-coco/evidence/development/10-numbers-and-clean-builds.md)
— the plan's real `G3`: hand-worked fixtures, Turbine OEE (A × P, declared), lost energy, and a seeded `GS-5`
that Performance alone catches. Plus `T-47`, `T-86`, `T-87`, `T-94`, `just results`, and **`T-52`: `just deploy`
twice into an empty database, then a database-only teardown.** Found on the way: the gate had been mislabelled,
and the generator's power had no performance signal (`I-20`).

Previous: [`development/09-approval-gated-writes.md`](docs/06-coco/evidence/development/09-approval-gated-writes.md).
Next entry goes in `docs/06-coco/evidence/development/11-<slug>.md`.
