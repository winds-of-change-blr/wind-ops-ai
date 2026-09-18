# Current state — read this first, update it last

> **Last updated:** 2026-09-18 · **by:** NK · **CoCo session:** `04d1ee7a-0e99-44de-afb6-40f838e591e6`
> **Plan day:** D0 (planning complete, build not started) · **Branch:** `docs/nk/hackathon-planning`

**This file holds status, never intent.** Intent lives in `docs/`. If the two disagree: `docs/` wins on
*what we are building*, this file wins on *how far we got*. Overwrite sections in place — never append.
Full protocol in [`AGENTS.md`](AGENTS.md#session-protocol).

---

## 1. Gates

| Gate | State | Blocking |
| --- | --- | --- |
| **G1** — data is honest (D4) | Not started | — |
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
| — | — | — | — | Nothing in flight |

## 3. Next actions, in order

Taken from [`project-plan.md`](docs/08-delivery/project-plan.md) D1. Do not re-derive the plan here —
just the next three things, each with the ID that proves it done.

1. **Decide `WOA_SCHEDULER`** (`Q-39` sibling, D1 blocking) — automations inherit the creator's default
   role, which breaks `NFR-3` if left as `ACCOUNTADMIN`. Record in `04-code.md`.
2. **Probe Streamlit object creation** in the account (`Q-39`) — untested, and `M8` depends on it. If it
   fails, the cut order in [`scope.md`](docs/02-functional/scope.md) changes on day one.
3. **Write the deck skeleton** (`US-85`) — D1 deliberately, not D14. It is the specification and the
   cut-decision tool.

## 4. Blocked / needs a human decision

| ID | Question | Owner | Blocks |
| --- | --- | --- | --- |
| `Q-39` | Can we create Streamlit objects in this account? | NK | `M8`, D13 |
| `Q-90` | Which practitioner takes the D2 sanity-check call? | NK | D2, scenario credibility |
| `Q-6` | Fourth team member — confirmed or not? | NK | capacity (`R-1`) |

Full register: [`raid-log.md`](docs/08-delivery/raid-log.md). Only list here what blocks *the next
action*; the RAID log holds the rest.

## 5. What actually exists in Snowflake right now

**The section git cannot tell you, and the one that wastes the most time when stale.** Update it
whenever you create or drop an object.

| Thing | State |
| --- | --- |
| Databases | **None.** `WIND_OPS_AI` not created |
| Schemas | — |
| Roles / warehouses | **None** of the `WOA_*` roles or warehouses exist |
| Models, semantic views, search services, agents | **None** |
| Verified as *possible* in this account | `SNOWFLAKE.ML.CLASSIFICATION`, `ANOMALY_DETECTION`, `CREATE SEMANTIC VIEW`, `CREATE CORTEX SEARCH SERVICE`, `AI_PARSE_DOCUMENT`, `AI_EXTRACT`, `CREATE AGENT`, `CREATE DYNAMIC TABLE`, `AI_COMPLETE('claude-sonnet-4-5')`, `AI_COMPLETE('llama3.1-8b')` |
| Verified as **not** working | `claude-4-sonnet`, `mistral-large2`, `openai-gpt-4.1` (legacy names, rejected) |
| Untested | Streamlit object creation, custom compute pools, notification integrations |

Account `BGTCHIX-UZ86048` · region `AZURE_CENTRALINDIA` · trial, **$400 budget**.
Naming authority: [`04-code.md`](docs/03-architecture/04-code.md).

**Every object here was created by a `just` recipe** — see
[AGENTS.md · Deployment](AGENTS.md#deployment). If something exists in the account that no recipe
creates, that is a defect: record it in §7 and fold it into a recipe.

## 6. Budget

| Source | Credits |
| --- | --- |
| CoCo token credits (`CORTEX_CODE_DESKTOP_USAGE_HISTORY`) | 15.07 |
| Warehouse (`WAREHOUSE_METERING_HISTORY`) | 1.68 |
| **Total spent** | **≈ 16.75** |

**Always sum both** — warehouse metering alone under-reported planning by ~10×. Alert NK at each $100.

## 7. Deviations from the plan

Anything built differently from `docs/`, with where it was recorded. If this table has an entry with no
ADR or RAID reference, that is a defect.

| What changed | Recorded in |
| --- | --- |
| — | — |

## 8. Latest evidence entry

[`docs/06-coco/evidence/planning/01-plan-generation.md`](docs/06-coco/evidence/planning/01-plan-generation.md)
— planning phase, 126 requests, 24,064,327 tokens.

Next entry goes in `docs/06-coco/evidence/development/01-<slug>.md`.
