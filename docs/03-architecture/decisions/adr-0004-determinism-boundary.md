# ADR-0004 — Determinism boundary: the engine decides, the model explains

> **Status:** Accepted · **Owner:** NK · **Last updated:** 2026-09-17 ·
> **Supersedes:** nothing · **Related:** [ADR-0005](adr-0005-approval-gated-writes.md), [ADR-0009](README.md#adr-0009--native-semantic-view-as-the-nl-interface)

---

## Context

The brief asks for prediction, natural-language root cause, and automated work orders. The obvious
route is to give a language model tools and let it reason its way to an answer. That route produces
a compelling demo and an untrustworthy system, and it is where the reference solution ends up: its
agent generates SQL that is executed with no validation, its "recommended action" is a hardcoded
string, and its work-order tool carries the comment *"For now, we'll simulate"*
([analysis §3.3](../../00-hackathon/reference-solution-analysis.md#33-the-rest-of-the-gap-list)).

The failure mode is specific. A language model asked "when can we do this repair?" will produce a
plausible date. It will not know whether a crane is available, whether the crew is certified, or
whether the bearing is in stock — and it will answer anyway. In maintenance planning, a plausible
wrong answer costs a crew a day and a customer an outage.

## Decision

**Deterministic code decides state. The model explains it.**

| Belongs to the engines — SQL or Snowpark, unit-tested | Belongs to the model |
| --- | --- |
| Whether a component is at risk, and by how much | Which of the at-risk components to talk about first |
| What availability, lost energy, LD exposure and OEE are | What those numbers mean for this customer |
| Which maintenance windows are feasible | Why one feasible window reads better than another |
| Which alarms group into an incident | How to summarise the incident |
| Whether a suppression is permitted | Nothing — this is a guard, not a judgement |
| All arithmetic | No arithmetic at all |

Three enforcement mechanisms, in order of strength:

1. **Grants.** `WOA_AGENT` has no write privilege anywhere and no privilege on `ACTION`. A prompt can
   be argued with; a missing grant cannot.
2. **Validation.** Generated SQL is checked against a read-only operation allowlist and a
   permitted-object list before execution (`FR-54`).
3. **Candidate-only selection.** The agent may choose among rows the engines produced. It cannot
   construct a window, a crew, a part, an incident or a number (`FR-52`).

## Alternatives considered

| Option | Why not |
| --- | --- |
| **Agent-first**: give the model tools and let it reason freely | Produces the reference solution's failure mode. Unverifiable, untestable, and one adversarial question away from inventing a crane |
| **Model computes, engine validates afterwards** | Validation after the fact still shows the user a wrong number first. And the validator would need to contain the logic anyway, so the model adds nothing but risk |
| **No model at all** | Loses the brief's second bullet, and loses the genuine value: explanation and synthesis are things a language model is actually good at |
| **Model computes, with a confidence threshold** | Confidence in a language model is not calibrated against arithmetic correctness. A confident wrong date is still a wrong date |

## Consequences

**Good.** Every state-bearing calculation is unit-testable, and `T-46` can assert adversarially that
the agent cannot produce an invented window or number. Metrics have one definition, so the app,
semantic view and agent cannot disagree (`T-24`). The security story is structural rather than
aspirational. And it maps directly onto the largest-weighted judging criterion.

**Costs.** More SQL to write, and up front — the engines must exist before the agent is interesting.
The agent looks less magical in a demo: it cannot be asked to "just schedule it", because scheduling
is a human approval over engine-produced candidates. We accept that trade; a system that can be
talked into a wrong action is not a better demo, it is a worse product.

**What this rules out permanently.** Autonomous action (`W3`). Not deferred — prohibited.

## Compliance

| Requirement | Test |
| --- | --- |
| `NFR-1` determinism boundary | `T-46` |
| `FR-52` candidate-only selection | `T-46` |
| `FR-53` no destructive tools | `T-47` |
| `FR-54` SQL validation | `T-48` |
| `FR-27` one metric definition | `T-24` |
| `FR-55` admits when ungrounded | `T-49` |
