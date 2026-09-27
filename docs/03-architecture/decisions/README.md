# Architecture Decision Records

> **Status:** Draft v0.4 · **Owner:** NK · **Last updated:** 2026-09-18
>
> **v0.4** adds [`ADR-0020`](adr-0020-app-platform.md) (app platform, after testing Snowflake App
> Runtime in-account) and closes `ADR-0012`.
>
> **Every decision, made or pending, is in the table below.** Nothing is buried in prose elsewhere.
> The most consequential eight have their own file; the rest are recorded here in full and promoted
> to a file if they become contested.
>
> Status values: **Accepted** (decided), **Proposed** (recommended, awaiting team confirmation),
> **Open** (genuinely undecided, blocks work).

---

## Index

| ID | Decision | Status | Owner | Own file |
| --- | --- | --- | --- | --- |
| `ADR-0001` | [Snowflake-native, single account](#adr-0001--snowflake-native-single-account) | Accepted | NK | — |
| `ADR-0002` | [Scenario: Indian wind O&M OEM](adr-0002-scenario.md) | Accepted | NK | ✓ |
| `ADR-0003` | [Turbine OEE definition](adr-0003-turbine-oee.md) | **Proposed** | NK | ✓ |
| `ADR-0004` | [Determinism boundary: engine decides, model explains](adr-0004-determinism-boundary.md) | Accepted | NK | ✓ |
| `ADR-0005` | [Approval-gated, idempotent, audited writes](adr-0005-approval-gated-writes.md) | Accepted | NK | ✓ |
| `ADR-0006` | [Damage-driven synthetic data generation](adr-0006-synthetic-data.md) | Accepted | SA | ✓ |
| `ADR-0007` | [ML approach: Snowflake ML classification + anomaly detection](#adr-0007--ml-approach) | **Proposed** | SA | — |
| `ADR-0008` | [Naming and environment convention](#adr-0008--naming-and-environment-convention) | Accepted | JP | — |
| `ADR-0009` | [Native semantic view as the NL interface](#adr-0009--native-semantic-view-as-the-nl-interface) | Accepted | JP | — |
| `ADR-0010` | [Document pipeline: parse then search service](#adr-0010--document-pipeline) | Accepted | JP | — |
| `ADR-0011` | [Incremental pipeline via dynamic tables](#adr-0011--incremental-pipeline-via-dynamic-tables) | **Accepted, narrowed** — one path | JP | — |
| `ADR-0012` | [Front end: Streamlit in Snowflake, local fallback](#adr-0012--front-end) | **Resolved** — see `ADR-0020` | NK | — |
| `ADR-0013` | [Orchestration model choice and fallback](#adr-0013--orchestration-model-and-fallback) | Accepted | SA | — |
| `ADR-0014` | [One classifier with component class as a feature](#adr-0014--model-granularity) | **Proposed** — `Q-15`, `Q-30` | SA | — |
| `ADR-0015` | [Reuse from the reference solution](#adr-0015--what-we-reuse-from-the-reference-solution) | Accepted | NK | — |
| `ADR-0016` | [History window and data volume](#adr-0016--history-window) | **Proposed** — `Q-27` | SA | — |
| `ADR-0017` | [Alarm classification policy](adr-0017-alarm-classification.md) | Accepted | NK | ✓ |
| `ADR-0018` | [The scheduling suggestion boundary](adr-0018-scheduling-suggestion-boundary.md) | Accepted | NK | ✓ |
| `ADR-0019` | [Automation and notification split](adr-0019-automation-and-notification.md) | Accepted | NK | ✓ |
| `ADR-0020` | [App platform: Streamlit in Snowflake, not a container](adr-0020-app-platform.md) | Accepted | NK | ✓ |

Three decisions are not yet settled and one of those blocks work: `ADR-0014` blocks feature
engineering (`Q-30`). `ADR-0012` is resolved — Streamlit object creation was verified on this account
and the wider platform question is settled in [`ADR-0020`](adr-0020-app-platform.md).

---

## ADR-0001 — Snowflake-native, single account

**Status:** Accepted · **Context:** The Official Rules require use of the Snowflake platform and
give special consideration to Snowpark and Streamlit. We have one trial account and $400.

**Decision.** Everything runs inside Snowflake: generation in Snowpark, transformation in SQL and
dynamic tables, ML in Snowflake ML, retrieval in Cortex Search, the agent as a Cortex Agent, and the
UI in Streamlit. No external compute, no external vector store, no external orchestrator.

**Alternatives.** External Python service plus a warehouse — rejected: more moving parts, more
credentials, nothing to gain in 15 days. External vector database — rejected: Cortex Search is
verified working in-account.

**Consequences.** Simple deployment and a clean security story. We are exposed to any in-region
feature gap, which [02-container.md §5](../02-container.md#5-degraded-modes-per-container) covers
per container. **Trial-account limits are a real and now-measured constraint:** `APPLICATION SERVICE`
(Snowflake App Runtime) is blocked outright, which closed off the containerised-web-app option
([`ADR-0020`](adr-0020-app-platform.md)).

## ADR-0007 — ML approach

**Status:** Proposed · **Context:** `FR-16`…`FR-21` need a real, trained, evaluated model with
drivers. Both `SNOWFLAKE.ML.CLASSIFICATION` and `SNOWFLAKE.ML.ANOMALY_DETECTION` were verified
working in our account on 2026-09-17.

**Decision.** Two independent signals, not one blended score:

1. A **classifier** for "will this component fail within the horizon", trained on engineered
   features, evaluated on held-out data, exposing feature importances as drivers.
2. An **anomaly detector** on residuals at matched operating conditions, catching behaviour the
   classifier was never trained on.

**Alternatives.** Custom model in Snowpark ML with SHAP — richer explanations, more time, and
`Q-6`'s capacity makes it hard to justify; kept as a stretch. Cortex `FORECAST` — forecasts a series,
does not classify an event. A rules engine — rejected outright: that is what the reference solution
did while calling it AI.

**Consequences.** Fast to build, natively explainable, no extra infrastructure. Drivers are feature
importances rather than per-prediction attributions, which is weaker than SHAP and must be
described accurately — not overclaimed. Keeping the two signals separate is deliberate, and `T-18`
asserts they are not collinear.

## ADR-0008 — Naming and environment convention

**Status:** Accepted · **Context:** `AGENTS.md` requires a single naming authority so names are not
invented per file.

**Decision.** As specified in [04-code.md](../04-code.md): `WIND_OPS_AI` shared,
`WIND_OPS_AI_DEV_<INITIALS>` personal clones (retired 2026-09-27: one team database only), ten schemas, prefixed object names, two `XSMALL`
warehouses, a role hierarchy under `SYSADMIN`, and the database name always a script parameter.

**Alternatives.** One schema — rejected: makes least-privilege grants impossible. Per-developer
databases built from scratch — rejected: wastes credits; zero-copy clone is free.

**Consequences.** Grants can be narrow and legible. Setup must be parameterised and idempotent,
which is more work up front and is what makes `T-52` pass.

## ADR-0009 — Native semantic view as the NL interface

**Status:** Accepted · **Context:** `FR-43` needs a governed model for natural-language querying.
`CREATE SEMANTIC VIEW` and Cortex Analyst were both verified available.

**Decision.** A native semantic view over the metric layer and asset model, deliberately **narrower
than the reference solution's**: fewer entities, every description correct for wind O&M, sample
values matching the loaded data, and a verified query per golden scenario.

**Alternatives.** YAML semantic model on a stage — the reference solution's route; rejected because
a stage file is one more manual upload step and drifts from the schema. A hand-written text-to-SQL
prompt — rejected: no governance, no verified queries.

**Consequences.** Text-to-SQL quality depends on description quality, so `T-42` checks every
description is domain-correct. Narrow scope means some questions fall outside it — and `FR-55`
requires the agent to say so rather than guess.

## ADR-0010 — Document pipeline

**Status:** Accepted · **Context:** `M6` requires real documents, genuinely parsed and cited. This
is the reference solution's largest unsupported claim.

**Decision.** Synthetic documents as **real files** on an internal stage →
`AI_PARSE_DOCUMENT` → chunks carrying section identifiers → Cortex Search service on a declared lag.
Citations name document **and section**.

**Alternatives.** Document text in a table column — rejected: that is precisely what the reference
solution did and called dark-data processing. External embedding and vector store — rejected:
unnecessary, and adds credentials.

**Consequences.** Real parsing work and real retrieval, at the cost of writing 8–12 documents well
enough to be worth retrieving (`Q-26`). Section identifiers are what make a citation checkable.

## ADR-0011 — Incremental pipeline via dynamic tables

**Status:** **Accepted, narrowed to one path** · **Context:** `FR-89` and `M12` require a demonstrable
incremental path. `CREATE DYNAMIC TABLE` was verified working in our account.

**Decision.** **One** dynamic table on the alarm path (`Q-88`), with an explicit `TARGET_LAG` and the
refresh time visible on the surface (`NFR-18`). The remaining layers stay batch and we say so.

**Why narrowed rather than dropped.** The brief's first bullet says *"Correlate **real time** sensor
streams"*. With no incremental path at all, we would have had to strip the word from every artefact —
and would have scored worse on a checklist read than teams who batch-load and claim real time anyway.
One dynamic table lets us say **"incremental, with a declared target lag"** truthfully. This reverses
an earlier decision to displace the incremental pipeline entirely; the reversal is deliberate and the
reason is scoring, not architecture.

**Alternatives.** Full incremental across all layers — more credits and more failure modes for no extra
scoring value. Streams and tasks — more objects to explain. Scheduled full rebuild — what we do for
every *other* layer.

**Consequences.** Real incremental behaviour, demonstrable in the opening beat where a judge is already
looking. "Real-time" is still never claimed; "incremental, declared lag" is. If the single dynamic
table proves unreliable, the fallback is a procedure-driven rebuild **and the word comes out of every
artefact** — `R-27` tracks this.

## ADR-0012 — Front end

**Status:** **Resolved** · superseded in scope by [`ADR-0020`](adr-0020-app-platform.md) ·
**Context:** `M8` needs a UI. Streamlit-in-Snowflake object creation is now **verified working** on this
trial account (`Q-39` closed).

**Decision.** Streamlit in Snowflake. The wider question this ADR did not ask — *could we build a
proper web app instead?* — is answered in `ADR-0020`: Snowflake App Runtime is blocked on trial
accounts, plain SPCS containers are available, and we declined them for governance reasons as much as
scope.

**Consequence that still binds.** The app must not depend on a Snowflake-hosted session token for
authentication, or the local fallback breaks. This is exactly how the reference solution became
SiS-only: it read an OAuth token from `/snowflake/session/token`, so it cannot run anywhere else.
Our app must take its connection from configuration.

## ADR-0013 — Orchestration model and fallback

**Status:** Accepted · **Context:** The agent needs an orchestration model. In
`AZURE_CENTRALINDIA`, `claude-sonnet-4-5` responds **only** because
`CORTEX_ENABLED_CROSS_REGION = ANY_REGION`. Verified on 2026-09-17: `claude-4-sonnet`,
`mistral-large2` and `openai-gpt-4.1` are rejected as legacy.

**Decision.** `claude-sonnet-4-5` as primary. `llama3.1-8b`, verified responding, as the in-region
fallback. The model name is configuration, never a literal in application code.

**Consequences.** One account parameter is a single point of failure for the primary model, so the
fallback is rehearsed in the [demo runbook](../deployment.md#7-demo-day-runbook), not just
documented. Answer quality drops on fallback; grounding rules do not change, because they are
enforced by grants and validation rather than by the model.

## ADR-0014 — Model granularity

**Status:** Proposed · **Context:** `Q-15`, `Q-30`. Ten component classes, four with real CMS
coverage.

**Decision.** **One** classifier, with component class as a feature, scoped to the four
CMS-covered classes: `GBX`, `MSB`, `GEN`, `PIT`.

**Alternatives.** One model per class — better per-class fit, four times the training, evaluation
and maintenance. One model over all ten classes — six of them have no meaningful signal, which
would dilute the model and invite a fair question about why.

**Consequences.** Cheaper and simpler, and honest about scope: we say the model covers four
drivetrain-and-pitch classes rather than implying whole-turbine coverage. If per-class fit turns out
poor, splitting `GBX` out first is the obvious next step.

## ADR-0015 — What we reuse from the reference solution

**Status:** Accepted · **Context:** The
[analysis](../../00-hackathon/reference-solution-analysis.md) found genuine strengths alongside the
gaps. Reinventing them wastes capacity; copying wholesale forfeits differentiation.

**Decision.** Reuse the *approach*, never the code, and only these: conformed star schema with
surrogate keys and clustering on the time-series fact; a Unified-Namespace-style path as an
attribute; availability derived from downtime propagating into runtime; the craft in the agent's
prompt design; and the two-fragment Streamlit layout that keeps the chat beside the content.

**Explicitly not reused:** their database and object names, their `ACCOUNTADMIN`-everywhere setup
pattern, their Python-side business logic, their unvalidated SQL execution, and the semantic model's
breadth.

**Consequences.** We inherit sound dimensional modelling and a good UX pattern without inheriting
the defects. The reference solution is **never mentioned in the pitch** (`R-REF-5`) — the
differentiation has to stand on its own.

## ADR-0016 — History window

**Status:** Proposed · **Context:** [Profile §11](../../01-business/company-profile.md#11-data-scale-for-the-synthetic-dataset)
suggests 12–24 months, ≈5.26 M SCADA rows and ≈7.0 M CMS rows per year, and flags that this needs
confirming against credits. We have $400 and ~90 person-hours.

**Decision.** **6 months** of full-fidelity history, plus a failure-rich window sized to give the
model enough positive examples. Volume is a parameter, so it can be raised if credits allow.

**Alternatives.** 24 months — best for the model, worst for credits and generation time. 3 months —
too few seeded failures for a credible held-out evaluation.

**Consequences.** Fewer positive examples, so the evaluation must report confidence honestly rather
than quoting a single flattering number. The profile's volume figures are *(illustrative)* by its own
statement, so reducing them contradicts nothing.

---

## Pending decisions, gathered

Per the requirement that every open decision is visible in one list.

| ADR | Blocks | Question |
| --- | --- | --- |
| `ADR-0003` | Metric layer | Does the team accept the profile's Turbine OEE proposal as-is? |
| `ADR-0007` | Model build | Confirm two-signal approach; confirm drivers-as-importances is acceptable |
| `ADR-0011` | Pipeline | **Resolved** — narrowed to one path (`M12`), accepted |
| `ADR-0012` | **The app** | **Resolved** — `Q-39` closed, Streamlit verified; platform settled in `ADR-0020` |
| `ADR-0014` | Features | `Q-30` — four component classes, one model? |
| `ADR-0016` | Generation | `Q-27` — 6 months, plus a failure-rich window? |
