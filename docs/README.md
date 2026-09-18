# Wind Ops AI — the plan

> **Status:** Draft v0.3 · **Owner:** NK · **Last updated:** 2026-09-18
>
> A 15-day hackathon entry: a **predictive-maintenance and OEE command center** on Snowflake for a
> fictional Indian wind-turbine OEM that also maintains the fleet it sells.
>
> **All data is synthetic.** Vayuveda Wind Systems is fictional. No real company, customer or
> personal data.

---

## Read this in ten minutes

| Order | Read | Why |
| --- | --- | --- |
| 1 | [00-hackathon/problem-statement.md](00-hackathon/problem-statement.md) | The brief, and the `E1…E9` criteria we are judged on |
| 2 | [01-business/company-profile.md](01-business/company-profile.md) | The scenario: the company, its fleet, contracts, roles, systems and KPIs |
| 3 | [00-hackathon/reference-solution-analysis.md](00-hackathon/reference-solution-analysis.md) | What the official reference solution really does, and where we differ. **The document that decides the entry** |
| 4 | [02-functional/scope.md](02-functional/scope.md) | What we will and will not build, the cut order, and the **minimum viable submission** |
| 5 | [08-delivery/evaluation-traceability.md](08-delivery/evaluation-traceability.md) | **Every criterion mapped to the artefact and demo moment that proves it.** Read this before the project plan |
| 6 | [08-delivery/project-plan.md](08-delivery/project-plan.md) | The 15 days, the gates and the cut triggers |

If you read only one thing after the brief, read #3.

**Picking up work?** Read [`STATE.md`](../STATE.md) at the repo root first — or run `just state`. This
folder tells you *what* we are building; `STATE.md` tells you *how far we got* and what is already
claimed. The protocol is in [AGENTS.md · Session protocol](../AGENTS.md#session-protocol).

## The idea in four sentences

VWS sells turbines and then sells the promise they will be **available when the wind blows** — a
contractual promise, with liquidated damages when it is missed. Today the monitoring centre drowns in
alarms and cannot tell which few matter, while the vibration evidence, the work orders, the spares and
the contract terms sit in systems nobody joins — so a bearing becomes a gearbox and a gearbox becomes
an LD payment. Wind Ops AI turns the alarm flood into a short, honest actionable list — including an
explicit **"we're not sure"** class — predicts component failure with explained drivers, answers "why"
with citations, and turns the decision into approval-gated, audited planned work. **Deterministic code
decides state; the model explains it** — and every write needs a human.

## Everything, by folder

| Folder | Documents |
| --- | --- |
| **00-hackathon** | [problem-statement.md](00-hackathon/problem-statement.md) `[given]` · [terms-and-conditions.md](00-hackathon/terms-and-conditions.md) `[given]` · [reference-solution-analysis.md](00-hackathon/reference-solution-analysis.md) |
| **01-business** | [company-profile.md](01-business/company-profile.md) `[given]` · [business-case.md](01-business/business-case.md) · [personas-and-journeys.md](01-business/personas-and-journeys.md) |
| **02-functional** | [scope.md](02-functional/scope.md) · [requirements.md](02-functional/requirements.md) · [epics-and-stories.md](02-functional/epics-and-stories.md) |
| **03-architecture** | [README.md](03-architecture/README.md) · [01-context.md](03-architecture/01-context.md) · [02-container.md](03-architecture/02-container.md) · [03-component.md](03-architecture/03-component.md) · [04-code.md](03-architecture/04-code.md) · [deployment.md](03-architecture/deployment.md) · [cross-cutting-concerns.md](03-architecture/cross-cutting-concerns.md) · [decisions/](03-architecture/decisions/README.md) |
| **04-data** | [data-sources-and-synthetic-data.md](04-data/data-sources-and-synthetic-data.md) · [data-model.md](04-data/data-model.md) · [semantic-model-and-ontology.md](04-data/semantic-model-and-ontology.md) |
| **05-ai-ml** | [ml-models.md](05-ai-ml/ml-models.md) · [agents-and-tools.md](05-ai-ml/agents-and-tools.md) |
| **06-coco** | [coco-usage-plan.md](06-coco/coco-usage-plan.md) · [coco-setup.md](06-coco/coco-setup.md) · [evidence/](06-coco/evidence/README.md) |
| **07-quality** | [testing-and-validation.md](07-quality/testing-and-validation.md) |
| **08-delivery** | [project-plan.md](08-delivery/project-plan.md) · [raid-log.md](08-delivery/raid-log.md) · [demo-and-submission.md](08-delivery/demo-and-submission.md) · [evaluation-traceability.md](08-delivery/evaluation-traceability.md) · [results-summary.md](08-delivery/results-summary.md) |
| — | [glossary.md](glossary.md) |

`[given]` marks the three read-only documents. They are the ground truth for the brief, the rules and
the scenario. **Never edit them** — propose changes to the team instead
([`I-1`](08-delivery/raid-log.md#3-issues), [`I-2`](08-delivery/raid-log.md#3-issues) are two such
proposals).

## ID conventions

Prefixes are kept visually distinct on purpose — no `G1` and `G-1` for different things.

| Prefix | Means | Defined in |
| --- | --- | --- |
| `E1…E9` | Evaluation criteria | [problem-statement.md](00-hackathon/problem-statement.md#4-evaluation-criteria--consolidated-scorecard) `[given]` |
| `S1…S17` | VWS source systems | [company-profile.md §7](01-business/company-profile.md#7-systems-landscape-where-predictive-maintenance-data-comes-from) `[given]` |
| `G-` | Gaps in the reference solution | [reference-solution-analysis.md](00-hackathon/reference-solution-analysis.md) |
| `D-` | Differentiators | [reference-solution-analysis.md](00-hackathon/reference-solution-analysis.md#5-differentiators) |
| `BG-` | Business goals | [business-case.md](01-business/business-case.md#3-business-goals) |
| `H-` | Value hypotheses | [business-case.md](01-business/business-case.md#4-value-hypotheses) |
| `P-` | Personas | [personas-and-journeys.md](01-business/personas-and-journeys.md#1-persona-set) |
| `J-` | Journeys | [personas-and-journeys.md](01-business/personas-and-journeys.md#2-journeys) |
| `GS-` | Golden demo scenarios | [personas-and-journeys.md](01-business/personas-and-journeys.md#3-golden-scenarios) |
| `M`/`S`/`C`/`W` | MoSCoW scope items | [scope.md](02-functional/scope.md) |
| `FR-` / `NFR-` | Requirements | [requirements.md](02-functional/requirements.md) |
| `CMP-` | Components | [requirements.md §1](02-functional/requirements.md#1-components) |
| `EP-` / `US-` | Epics and stories | [epics-and-stories.md](02-functional/epics-and-stories.md) |
| `ADR-` | Decisions | [decisions/](03-architecture/decisions/README.md) |
| `VQ-` | Verified queries | [semantic-model-and-ontology.md](04-data/semantic-model-and-ontology.md#5-verified-queries) |
| `T-` | Tests | [testing-and-validation.md](07-quality/testing-and-validation.md) |
| `G1…G5` | Milestone gates | [testing-and-validation.md §9](07-quality/testing-and-validation.md#9-milestone-gates) |
| `R-` `A-` `I-` `DEP-` `Q-` | Risks, assumptions, issues, dependencies, open questions | [raid-log.md](08-delivery/raid-log.md) |

**What gets judged.** The prototype submission is a **deck plus a repo**, and a judge spends 5–15
minutes. The scoring surface is therefore the deck, the root `README`, the 2-minute walkthrough and
the [results summary](08-delivery/results-summary.md) — not this folder. `docs/` exists to make the
build faster and the claims defensible under questioning. See
[evaluation-traceability.md](08-delivery/evaluation-traceability.md).

Two pairs that look similar and are not: `G-` (gaps in the reference solution) versus `G1…G5`
(milestone gates); and `S1…S17` (VWS source systems, from the profile) versus `S1…S6` (Should-have
scope items). Both distinctions come from the given documents, so they are kept rather than renamed —
context always disambiguates, and every reference is linked.

## The rules everything obeys

From [AGENTS.md](../AGENTS.md), restated because they are decisions rather than preferences.

1. **Deterministic code decides state; the model explains it.** [ADR-0004](03-architecture/decisions/adr-0004-determinism-boundary.md)
2. **Every write is approval-gated, idempotent and audited.** Agents get no destructive tools. [ADR-0005](03-architecture/decisions/adr-0005-approval-gated-writes.md)
3. **Nothing is auto-suppressed** on an at-risk asset or for a safety-critical alarm code. Suppression is always reversible and visible.
4. **Explain everything:** predictions carry drivers, answers carry citations.
5. **Synthetic data only**, labelled as such.
6. **Least privilege.** No `ACCOUNTADMIN` in application code, no secrets in git.

## Where things stand

| | |
| --- | --- |
| Planning | Complete — **v0.3**. Alarm intelligence, planned work, committed ingenuity, demonstrable freshness and the scoring surface all folded in |
| Build | Not started. `D1` is Fri 18 Sep 2026 |
| **Submission deadline** | **Sun 4 Oct 2026, 11:59 PM IST.** We aim for Fri 2 Oct |
| What constrains us | Not person-hours — the calendar and gates, **human review and decision load**, credits, and blast radius |
| Credits used | **≈16.75** of a $400 trial allowance (15.07 CoCo tokens + 1.68 warehouse) |
| Gating tests | **17**, of which `T-10` is the single point of failure |
| Blocking questions | Listed in the [RAID log](08-delivery/raid-log.md#blocking) |

## Revision process

| Rule | Detail |
| --- | --- |
| Where a decision lives | An ADR. Not in prose |
| Where an open question lives | The [RAID log](08-delivery/raid-log.md). One register, no exceptions |
| Changing a `[given]` document | Propose to the team; never edit silently |
| Changing scope | Update [scope.md](02-functional/scope.md), then requirements, then stories. Never the other way round |
| Adding a requirement | It needs an ID, a priority, a persona, a test and a component, or it is `NOT READY` |
| Docs and code | Change in the same PR |
| Vocabulary | [glossary.md](glossary.md) governs. One term, one meaning |
