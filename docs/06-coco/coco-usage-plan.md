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
| **Development** | Build pipelines, semantic views, models, agents and app code, iterating in Desktop | Generator, metric views (no dynamic tables: designed, not built), semantic view, ML training, agent and tools, Streamlit app | development/ |
| **Execution** | Run and orchestrate the end-to-end solution, including scheduled runs | Run the numbered setup scripts, generation, refresh, scoring; scheduled scoring if `C7` lands | execution/ |
| **Testing** | Validate outputs, test accuracy, handle errors and edge cases | Author the `pytest` suite and SQL assertions; the adversarial agent suite; degraded-mode drills | testing/ |

## 3. Recommended tasks — and where each lands

The brief names six. Being explicit about which we will genuinely demonstrate, rather than claiming
all six.

| Recommended task | Our use | Confidence |
| --- | --- | --- |
| **Synthetic data generation** | `CMP-1` — the whole dataset including four alarm streams, referentially consistent, no production data ever touched | **Core.** Our largest CoCo-built artefact |
| **Data pipeline creation** | Generation, curation, alarm correlation and scoring via `just deploy`, plus **one scheduled task** (`OPS.T_DAILY_DIGEST`). No streams, and no dynamic table re-proven on this account | **Core** |
| **Semantic model & ontology authoring** | `SV_WIND_OPS`: 10 tables, 32 dimensions, 22 facts, 15 metrics, 10 relationships, all described. **No verified queries yet**, found by our own `semantic-view-audit` skill | **Core, with a stated gap** |
| **Streamlit report/app generation** | `CMP-14` command center — triage, evidence panel, schedule surface | **Core** |
| **Document & unstructured processing** | `AI_PARSE_DOCUMENT` + Cortex Search over real synthetic documents | **Core** |
| **Connecting additional sources via MCP** | `woa-github`, a local stdio connector that files a GitHub issue from an approved work order. Not Jira, Slack or Drive: none is configured on this account, and the trial cannot egress | **Claimed, scoped**, see §4 |

## 4. Ingenuity — `E5`

**All seven capabilities, each CLAIMED or DECLINED with a reason.** A judge should see deliberate
choices, not gaps — and the declines are part of the story when the reasons are good.

| # | Capability | Verdict | Reason |
| --- | --- | --- | --- |
| 1 | **Reusable, shareable skills** (headline bonus) | **CLAIMED** | Three skills in [`skills/`](../../skills): `approval-gated-agent-tools`, `alarm-noise-triage`, `semantic-view-audit`, each with SKILL/EXAMPLE/TEST and real output. Teammate test `T-19` is recorded per skill and pending where not yet run. See §5 |
| 2 | **Custom tools / function calling** | **CLAIMED** | Two read-only agent tools (`fleet_data` over the semantic view, `maintenance_docs` over Cortex Search) plus the approval-gated `ACTION` procedures. The agent has no write tool: an absent one, not a disabled one |
| 3 | **Guardrails & graceful fallback** | **CLAIMED** | Nine guardrails, each tested; a documented degraded mode per container; three of the fifteen gating tests exist solely to prove the guards hold |
| 4 | **Automations / scheduled runs** | **CLAIMED, Snowflake side** | `OPS.T_DAILY_DIGEST`, 05:30 IST daily, **owned by and run as `WOA_SCHEDULER`** (`Q-78` resolved). It reads ENGINE and writes only `OPS.OPS_DIGEST`. Gated by four assertions (T-76, T-77). A CoCo agent-task automation was **not built**: the `cortex automation` CLI is not installed here, and such a run could not reach the repo anyway |
| 5 | **MCP connectors** | **CLAIMED, scoped** | `woa-github` ([`mcp/woa_github`](../../mcp/woa_github/server.py)): reads one approved work order through a read-only owner's-rights procedure and files an idempotent GitHub issue, refusing drafts, self-tests and unaudited rows. Interactive only. The trial account has no external access integration, so a scheduled run cannot use it |
| 6 | **Working across surfaces** | **CLAIMED** | Three Snowflake surfaces plus GitHub through MCP. The CoCo CLI is not one of them. See §6 |
| 7 | **Multi-agent orchestration** | **DECLINED** | One agent is enough for this problem. Multi-agent would add handoff complexity and new failure modes without adding capability, and a fragile demonstration is worse than a stated refusal. If time appeared, the honest version is a second narrow agent for document-only Q&A — not a swarm |

Two further deliberate refusals sit outside this table but belong in the same conversation, because
both are things we could have built and chose not to:
[`W13`](../02-functional/scope.md#6-wont-this-hackathon) suppression patterns proposed automatically
from dismissal history, and [`W15`](../02-functional/scope.md#6-wont-this-hackathon) oil-debris and
overdue-PM as alarm sources.

## 6. Surfaces

| Surface | What is demonstrated | Evidence artefact |
| --- | --- | --- |
| **Cortex Code Desktop** | The whole build: planning, pipelines, model, agent, app, skills, MCP | Session and request IDs in `CORTEX_CODE_DESKTOP_USAGE_HISTORY`, plus the local transcript. `CORTEX_CODE_CLI_USAGE_HISTORY` has no rows; we did not use the CLI |
| **GitHub (via MCP)** | An approved work order arrives where the crew coordinates | Issue [#27](https://github.com/winds-of-change-blr/wind-ops-ai/issues/27) and `artifacts/14-mcp-smoke.json` |
| **Snowflake Intelligence** | The same agent, same tools, same guardrails, reached without our app | The agent object plus a screenshot of an answer with its citation |
| **Streamlit app** | The command center — triage, evidence, schedule, approval | The `STREAMLIT` object, and `QUERY_HISTORY` for the session |

The point of the third row is that the agent is **not** an app feature: it is a governed object in the
account, usable from anywhere, with its guardrails enforced by grants rather than by our UI.

## 5. The skills we will publish

Each is a generalisable capability we needed anyway — not a wrapper written to claim the bonus.

| Skill | Does | Reusable because |
| --- | --- | --- |
| [`approval-gated-agent-tools`](../../skills/approval-gated-agent-tools/SKILL.md) | Builds the pattern where an agent proposes and only a human role applies: owner's-rights procedures, guards that refuse with a reason, idempotency, audit-first, and grant proofs | Any team giving an agent tools over operational data |
| [`alarm-noise-triage`](../../skills/alarm-noise-triage/SKILL.md) | Collapses any alarm stream into incidents, classifies ACTIONABLE, NUISANCE or UNDETERMINED with stored evidence, and **refuses to report compression without the count of real failures hidden** | Any SCADA, IoT or monitoring alert stream |
| [`semantic-view-audit`](../../skills/semantic-view-audit/SKILL.md) | Measures descriptions, synonyms, sample values, relationships and verified queries from `DESCRIBE SEMANTIC VIEW`, then lists fixes by accuracy impact | Any semantic view before Analyst or an agent relies on it |

Published: the repository is public (`Q-8` closed). Backlog, not shipped: `synthetic-degradation-data`
and `metric-parity-check`. The pattern exists in `sql/10_generate` and `DQ-T24-PATHS-AGREE` but is not yet
written up as a skill.

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
| `Q-69` | Does any part of the pipeline need to be **demonstrably** CLI-run for Official Rules §9? **Closed 2026-10-02:** no. Everything was run from Desktop, and the CLI surface is not claimed | NK |
