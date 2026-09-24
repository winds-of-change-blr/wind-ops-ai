# Current state — read this first, update it last

> **Last updated:** 2026-09-22 · **by:** KR · **CoCo session:** current
> **Plan day:** D5 (foundation deployed, data layer built) · **Branch:** `feat/kr/deploy-data-foundation`

**This file holds status, never intent.** Intent lives in `docs/`. If the two disagree: `docs/` wins on
*what we are building*, this file wins on *how far we got*. Overwrite sections in place — never append.
Full protocol in [`AGENTS.md`](AGENTS.md#session-protocol).

---

## 1. Gates

| Gate | State | Blocking |
| --- | --- | --- |
| **G1** — data is honest (D4) | In progress — dimensions seeded, fact tables empty | generator needed |
| **G2** — the model is real (D9) | Not started | `T-10` at D4 |
| **G3** — answers are trustworthy (D9) | Not started | G2 |
| **G4** — actions are safe (D12) | Not started | — |
| **G5** — demo-ready and submittable (D15) | Not started | all |

Gate definitions: [`testing-and-validation.md`](docs/07-quality/testing-and-validation.md).
**18 gating tests** — none run yet.

## 2. In flight — claim before you start

Claim a row *before* you begin, push it, and clear it when the work merges. An empty table means
nobody is mid-flight. A merge conflict here means two people claimed the same work — talk, do not
merge both.

| Owner | Story / test IDs | Branch | Claimed | Notes |
| --- | --- | --- | --- | --- |
| SB | `US-2`…`US-7`, `US-52` · `T-8`, `T-11`, `T-12`, `T-13`, `T-7`, `T-9`, `T-62`, `T-64`…`T-67` | `feat/sb/synthetic-data-generator` | 2026-09-24 | Synthetic data generator + `OPS` quality assertions, for `G1`. **Account `EB28292` was found empty** — KR's foundation and data layer no longer exist and are being re-deployed as part of this work |

## 3. Next actions, in order

Taken from [`project-plan.md`](docs/08-delivery/project-plan.md) D1. Do not re-derive the plan here —
just the next three things, each with the ID that proves it done.

1. **Build the synthetic data generator** (`US-2`…`US-7`, `US-52`) — SCADA signals, CMS features,
   damage accumulation, failure events, alarm streams. Without this, `G1` cannot pass.
2. **Curated layer** (`US-9`, `US-11`, `US-12`, `US-93`) — matched-band CMS join, operating state,
   one dynamic table with `TARGET_LAG`.
3. **Decide `WOA_SCHEDULER`** (`Q-78`, `DEP-8`) — still open.

`Q-39` (Streamlit) is **closed** — verified working on 2026-09-18, ahead of D1.

## 4. Blocked / needs a human decision

| ID | Question | Owner | Blocks |
| --- | --- | --- | --- |
| `Q-78` | `WOA_SCHEDULER` — which role do automations run as? | NK | D1, `NFR-3` |
| `Q-90` | Which practitioner takes the D2 sanity-check call? | NK | D2, scenario credibility |
| `Q-6` | Fourth team member — confirmed or not? | NK | capacity (`R-1`) |

Full register: [`raid-log.md`](docs/08-delivery/raid-log.md). Only list here what blocks *the next
action*; the RAID log holds the rest.

## 5. What actually exists in Snowflake right now

**The section git cannot tell you, and the one that wastes the most time when stale.** Update it
whenever you create or drop an object.

> **The account changed on 2026-09-21.** We are now on `JKDRJBB-MW27072`; the planning-phase
> account `BGTCHIX-UZ86048` is gone. Everything previously "verified as possible" was proven
> against that account and had to be re-proven. Recorded in §7.

| Thing | State |
| --- | --- |
| Databases | `WIND_OPS_AI_DEV_KR` — KR's personal dev clone, deployed 2026-09-22. `WIND_OPS_AI` (shared) not created |
| Schemas | 10: GEN, RAW, CURATED, SERVING, ML, ENGINE, ACTION, DOCS, OPS, APP — all owned by WOA_ADMIN |
| Roles | 9 `WOA_*` roles created: ADMIN, APP, AGENT, SCHEDULER, ENGINEER, RMC, PLANNER, EXEC, TECH. Hierarchy and grants applied |
| Warehouses | `WOA_APP_WH` and `WOA_BUILD_WH` — both XSMALL, auto-suspend 60s, initially suspended |
| RAW dimension tables | `DIM_COMPONENT_CLASS` (10), `DIM_PLATFORM` (2), `DIM_SITE` (6), `DIM_CONTRACT` (6), `DIM_EXCLUSION_CLASS` (5), `DIM_TURBINE` (100), `DIM_COMPONENT` (1000), `DIM_COMPONENT_GENEALOGY` (1000), `DIM_SIGNAL` (4100), `DIM_ALARM_CODE` (31), `DIM_FAILURE_CODE` (26), `DIM_CREW` (8), `DIM_PART` (19), `DIM_STOCK` (76) — all seeded |
| RAW fact tables | `FCT_SIGNAL_10MIN`, `FCT_CMS_FEATURE`, `FCT_TURBINE_STATE`, `FCT_ALARM_NORMALISED`, `FCT_WORK_ORDER`, `FCT_PART_MOVEMENT` — created, **empty** (awaiting generator) |
| GEN tables | `GEN_DAMAGE_STATE` — created, empty |
| Models, semantic views, search services, agents | **None** |
| Re-verified as *possible* on `JKDRJBB-MW27072` (2026-09-21) | `AI_COMPLETE('claude-sonnet-4-5')`, `AI_COMPLETE('llama3.1-8b')`, `SNOWFLAKE.CORTEX.COMPLETE` for both, `AI_EXTRACT`, `SNOWFLAKE.ML.CLASSIFICATION`, `ANOMALY_DETECTION`, `DOCUMENT_INTELLIGENCE`, `FORECAST`, `TOP_INSIGHTS`, `CREATE COMPUTE POOL` (`CPU_X64_XS`, compiles). Account params confirmed: `CORTEX_ENABLED_CROSS_REGION = ANY_REGION`, `ENABLE_CORTEX_ANALYST = true` |
| **Carried over from the old account — NOT yet re-proven** | `CREATE SEMANTIC VIEW`, `CREATE CORTEX SEARCH SERVICE`, `CREATE DYNAMIC TABLE`, `CREATE AGENT`, `CREATE STREAMLIT`, `AI_PARSE_DOCUMENT`, `CREATE SERVICE`, `CREATE ARTIFACT REPOSITORY`, `CREATE IMAGE REPOSITORY`. Each needs a database to exist first — they get proven by `just verify` once `deploy-foundation` lands |
| Verified as **not** working (old account; assumed to still hold) | `claude-4-sonnet`, `mistral-large2`, `openai-gpt-4.1` (legacy names, rejected). **`CREATE APPLICATION SERVICE` — not available for trial accounts, so Snowflake App Runtime is unavailable to us** ([`ADR-0020`](docs/03-architecture/decisions/adr-0020-app-platform.md)). The re-probe on the new account failed on *syntax*, not on the feature gate, so this is **inconclusive here** — but `ADR-0020` chose SiS deliberately, so nothing is blocked |
| Untested | Notification integrations; MCP connector; `st.components` HTML inside SiS |
| Other | `SNOWFLAKE_INTELLIGENCE` database does **not** exist — the agent needs `SNOWFLAKE_INTELLIGENCE.AGENTS` (platform-mandated, [`04-code.md`](docs/03-architecture/04-code.md) §2) |

Account `JKDRJBB-MW27072` (locator `EB28292`) · region `AZURE_CENTRALINDIA` · version 10.33.101 ·
trial, **$400 budget**. Naming authority: [`04-code.md`](docs/03-architecture/04-code.md).

**Every object here was created by a `just` recipe** — see
[AGENTS.md · Deployment](AGENTS.md#deployment). If something exists in the account that no recipe
creates, that is a defect: record it in §7 and fold it into a recipe.

## 6. Budget

Figures below are for **`JKDRJBB-MW27072`** and reset with the account move; the 51.18 credits spent
planning were charged to `BGTCHIX-UZ86048` and are not recoverable here.

| Source | Credits |
| --- | --- |
| CoCo token credits (`CORTEX_CODE_DESKTOP_USAGE_HISTORY.TOKEN_CREDITS`) | 3.28 |
| Warehouse (`WAREHOUSE_METERING_HISTORY.CREDITS_USED`) | 1.10 |
| **Total spent** | **≈ 4.38** |

**Always sum both** — warehouse metering alone under-reported planning by ~10×. Alert NK at each $100.
`ACCOUNT_USAGE` lags by up to three hours, so the current session is not yet reflected. Note the
column is `TOKEN_CREDITS`, not `CREDITS`.

## 7. Deviations from the plan

Anything built differently from `docs/`, with where it was recorded. If this table has an entry with no
ADR or RAID reference, that is a defect.

| What changed | Recorded in |
| --- | --- |
| **Account moved** from `BGTCHIX-UZ86048` to `JKDRJBB-MW27072` (same region). Invalidates the planning-phase capability evidence and resets the credit budget | §5 and §6 above; [`deployment.md`](docs/03-architecture/deployment.md) §1. **Needs a RAID entry — `Q-41` (who holds the elevated credential) is now open against a different account** |

## 8. Latest evidence entry

[`docs/06-coco/evidence/development/02-data-layer-foundation.md`](docs/06-coco/evidence/development/02-data-layer-foundation.md)
— deployed foundation (roles, warehouses, database, schemas, grants) to `WIND_OPS_AI_DEV_KR`.
Created 14 dimension tables and 7 fact tables in RAW and GEN schemas. Seeded all dimension tables
with data from the company profile: 100 turbines, 1,000 components, 4,100 signals, 31 alarm codes.
Implemented `just deploy-data` recipe.
Previous: [`development/01-foundation-setup.md`](docs/06-coco/evidence/development/01-foundation-setup.md).

Next entry goes in `docs/06-coco/evidence/development/03-<slug>.md`, after the generator.
