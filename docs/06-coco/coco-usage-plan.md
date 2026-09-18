# CoCo Usage Plan

> **Status:** Draft v0.2 · **Owner:** NK · **Last updated:** 2026-09-18
>
> [problem-statement.md §2](../00-hackathon/problem-statement.md#2-snowflake-coco-usage-guidelines)
> makes CoCo use across the full lifecycle **mandatory**, and says judges will look for evidence at
> every stage. §3 lists the ingenuity bonuses. This is `E4` and `E5`.
>
> Evidence lives in [evidence/](evidence/README.md) — this document is the plan, that is the proof.

---

## 1. The rule we work by

**CoCo does the work; a human owns the result.** Every evidence entry records the prompt, what CoCo
produced, and **what a human changed afterwards**. That last field is the honest one and the one worth
showing: an entry claiming a human changed nothing is either a trivial task or an unreviewed output.

## 2. Coverage by phase

| Phase | Required | What we use CoCo for | Evidence |
| --- | --- | --- | --- |
| **Planning** | Explore data, frame the problem, draft the design, outline the data model, ontology and workflow | Reference-solution forensics; capability probing against the live account; the whole of `docs/` | [planning/](evidence/planning/) — **complete** |
| **Development** | Build pipelines, semantic views, models, agents and app code, iterating in the CLI or Desktop | Generator, dynamic tables, metric views, semantic view, ML training, agent and tools, Streamlit app | development/ |
| **Execution** | Run and orchestrate the end-to-end solution, including scheduled runs | Run the numbered setup scripts, generation, refresh, scoring; scheduled scoring if `C7` lands | execution/ |
| **Testing** | Validate outputs, test accuracy, handle errors and edge cases | Author the `pytest` suite and SQL assertions; the adversarial agent suite; degraded-mode drills | testing/ |

## 3. Recommended tasks — and where each lands

The brief names six. Being explicit about which we will genuinely demonstrate, rather than claiming
all six.

| Recommended task | Our use | Confidence |
| --- | --- | --- |
| **Synthetic data generation** | `CMP-1` — the whole dataset including four alarm streams, referentially consistent, no production data ever touched | **Core.** Our largest CoCo-built artefact |
| **Data pipeline creation** | Curation, alarm normalisation and correlation, scoring runs, and one scheduled run | **Core** |
| **Semantic model & ontology authoring** | `SV_WIND_OPS` plus verified queries, validated against natural-language questions | **Core** |
| **Streamlit report/app generation** | `CMP-14` command center — triage, evidence panel, schedule surface | **Core** |
| **Document & unstructured processing** | `AI_PARSE_DOCUMENT` + Cortex Search over real synthetic documents | **Core** |
| **Connecting additional sources via MCP** | Approval notification, interactive only | **Claimed, scoped** — see §4 |

## 4. Ingenuity — `E5`

**All seven capabilities, each CLAIMED or DECLINED with a reason.** A judge should see deliberate
choices, not gaps — and the declines are part of the story when the reasons are good.

| # | Capability | Verdict | Reason |
| --- | --- | --- | --- |
| 1 | **Reusable, shareable skills** (headline bonus) | **CLAIMED** | Three skills in `skills/`, each a generalisable capability we needed anyway — see §5 |
| 2 | **Custom tools / function calling** | **CLAIMED** | Five read-only agent tools plus the approval-gated action procedure. The agent has no write tool — an absent one, not a disabled one |
| 3 | **Guardrails & graceful fallback** | **CLAIMED** | Nine guardrails, each tested; a documented degraded mode per container; three of the fifteen gating tests exist solely to prove the guards hold |
| 4 | **Automations / scheduled runs** | **CLAIMED** | One daily run refreshing scores, suggestions and a **digest a human reads before their shift** — not a cron job that exists to claim a bonus. Runs as `WOA_SCHEDULER`; refreshes only, never applies |
| 5 | **MCP connectors** | **CLAIMED, scoped** | One connector doing one real thing: an approval notification where technicians actually work. **Interactive only** — a scheduled run cannot reach a locally configured MCP server, so the digest goes via a notification integration instead. We will not claim Slack delivery from the automation |
| 6 | **Working across surfaces** | **CLAIMED** | Four surfaces, each with a named evidence artefact — see §6 |
| 7 | **Multi-agent orchestration** | **DECLINED** | One agent is enough for this problem. Multi-agent would add handoff complexity and new failure modes without adding capability, and a fragile demonstration is worse than a stated refusal. If time appeared, the honest version is a second narrow agent for document-only Q&A — not a swarm |

Two further deliberate refusals sit outside this table but belong in the same conversation, because
both are things we could have built and chose not to:
[`W13`](../02-functional/scope.md#6-wont-this-hackathon) suppression patterns proposed automatically
from dismissal history, and [`W15`](../02-functional/scope.md#6-wont-this-hackathon) oil-debris and
overdue-PM as alarm sources.

## 6. Surfaces

| Surface | What is demonstrated | Evidence artefact |
| --- | --- | --- |
| **Cortex Code Desktop** | The whole build — planning, pipelines, model, agent, app | Session and request IDs in `CORTEX_CODE_DESKTOP_USAGE_HISTORY`, plus the local transcript |
| **Cortex Code CLI** | Setup run end to end, and a scoring run — named explicitly in Official Rules §9 | Rows in `CORTEX_CODE_CLI_USAGE_HISTORY` |
| **Snowflake Intelligence** | The same agent, same tools, same guardrails, reached without our app | The agent object plus a screenshot of an answer with its citation |
| **Streamlit app** | The command center — triage, evidence, schedule, approval | The `STREAMLIT` object, and `QUERY_HISTORY` for the session |

The point of the third row is that the agent is **not** an app feature: it is a governed object in the
account, usable from anywhere, with its guardrails enforced by grants rather than by our UI.

## 5. The skills we will publish

Each is a generalisable capability we needed anyway — not a wrapper written to claim the bonus.

| Skill | Does | Reusable because |
| --- | --- | --- |
| `synthetic-degradation-data` | Generates time-series with damage-driven degradation and **learnable** failure labels, then verifies learnability against two baselines | Any predictive-maintenance demo needs this, and most get it wrong the way the reference solution did |
| `semantic-view-audit` | Checks every description for domain correctness, unit and grain, and verifies `sample_values` exist in the underlying data | Catches exactly the defect that shipped in the official reference solution |
| `metric-parity-check` | Asserts a metric returns the same value through the app, the semantic view and the agent | Generic guard against the most common silent defect in a semantic layer |
| `alarm-noise-audit` | Computes compression, chattering, standing and flood counts over any alarm stream, and **refuses to report compression without the count of real failures suppressed beside it** | Alarm-flood triage is a universal industrial problem, and publishing compression alone is the universal way it gets gamed |

Kept in `skills/` for now; publishing later (`Q-8`, `Q-58`).

## 6. Evidence discipline

| Rule | Reason |
| --- | --- |
| One entry per meaningful session, in the right phase folder | Judges look per phase |
| Record the prompt verbatim, or a faithful summary | The prompt is the artefact |
| Record **what a human changed** | The honest field |
| Note anything CoCo got wrong, and why | More credible than a highlight reel, and useful to us |
| Link to the resulting commit or PR | Traceable |
| Write it at the end of the session, not later | It will not happen later |

Filed at end-of-session in the daily rhythm
([project plan §6](../08-delivery/project-plan.md#6-fixed-daily-rhythm)),
and `US-48` owns it as a story so it cannot be quietly skipped.

## 7. Honesty about this criterion

`E4` is mandatory and easy to fake with a folder of screenshots. What we will show instead:

- Real forensics — CoCo read 3,265 lines of the reference solution's SQL and 4,700 lines of Python
  and found two arithmetic bugs the guide's own authors did not document.
- Real capability probes — trained a classifier and an anomaly-detection model, created a semantic
  view, a search service, a dynamic table and an agent in our own account, then cleaned up, so that
  no document here describes an unverified feature.
- Real corrections — where CoCo was wrong and a human fixed it, the entry says so.

## 8. Open questions

| ID | Question | Owner |
| --- | --- | --- |
| `Q-67` | Do we record evidence per session or per story? Recommendation: per session — cheaper, and matches how judges read it | NK |
| `Q-68` | Are three skills enough for the headline bonus, or is one excellent skill stronger? Recommendation: three, but `synthetic-degradation-data` gets the documentation effort | NK |
| `Q-69` | Does any part of the pipeline need to be **demonstrably** CLI-run for Official Rules §9? Recommendation: yes — make setup and scoring CLI-invokable | NK |
