# ADR-0017 — Alarm classification policy

> **Status:** Accepted · **Owner:** NK · **Last updated:** 2026-09-18 ·
> **Related:** [ADR-0004](adr-0004-determinism-boundary.md), [ADR-0005](adr-0005-approval-gated-writes.md)

---

## Context

The monitoring centre drowns in alarms and cannot tell which few matter — the single biggest
day-to-day pain in the scenario ([profile §3](../../01-business/company-profile.md#3-the-problem-in-company-terms),
item 5). Hundreds a day, most nuisance trips or auto-resets, hiding the few that signal real
degradation.

Alarm handling was originally `S2` (Should), which put the biggest daily pain at **step 6 of the cut
order** — the sixth thing we would have thrown away. It is now `M9`.

The obvious design is a binary classifier: actionable or nuisance. That is what a dashboard does, and
it has a specific failure mode. When the evidence is genuinely ambiguous — one channel reports
something, no other channel corroborates, the operating point might explain it — a binary classifier
must guess. Guessing "nuisance" hides a possible failure. Guessing "actionable" rebuilds the flood it
was meant to reduce. Either way the operator is not told that the system is unsure, which is the one
fact they most need.

## Decision

**Three classes, not two.** Every incident is classified **actionable**, **nuisance**, or
**`UNDETERMINED`**.

### The evidence weighed, and stored

Four channels, recorded per incident so a human can disagree with the conclusion:

| Evidence | Source | Why |
| --- | --- | --- |
| Does another channel agree **at matched operating conditions**? | `CMP-4` | Corroboration is the strongest single signal, and matched-band comparison is already on the critical path |
| Does load or RPM already explain the reading? | `CMP-4` | A vibration rise at higher load is not degradation |
| Did it auto-reset and never recur? | normalised stream | The classic nuisance signature |
| What does the component's risk score say? | `CMP-6` | Ties present alarms to predicted failure |

### The `UNDETERMINED` policy — binding

| Rule | Reason |
| --- | --- |
| Stays in the operator's queue | It is unresolved, not resolved-as-noise |
| Ranked **below** actionable | Ordering is a priority hint, not a filter |
| **Never hidden** | The whole point is to disclose uncertainty, not bury it |
| **Never auto-suppressible** | Suppressing what you don't understand is how real failures get lost |
| The undetermined **rate** is published as a headline figure | A rising rate means the evidence base is degrading, which is itself actionable |

### Noise conditions labelled explicitly

Chattering, standing/stale and flood are labelled as **separate, independently testable conditions**
rather than folded into a severity score, because they call for different responses: chattering needs
a suppression decision, standing needs someone to act, flood needs a cause found.

### The anti-gaming rule

**The compression ratio may never be displayed or exported without the count of real failures
suppressed or dismissed beside it.** A 40:1 compression is trivially achieved by suppressing
everything. Published alone, it is a metric that rewards the worst possible behaviour. `T-70` asserts
the pairing at the view level, not only in the UI.

### Patterns never self-activate

Repeated dismissals of a signature may **propose** a suppression pattern for human approval. No
pattern activates itself, ever. And per [`W13`](../../02-functional/scope.md#6-wont-this-hackathon),
the automatic proposal is **designed and documented but not built** in this prototype.

## Alternatives considered

| Option | Why not |
| --- | --- |
| **Binary actionable/nuisance** | Forces a guess on exactly the cases where guessing is most costly, and tells the operator nothing about the system's confidence |
| **A single continuous noise score** | Collapses four different questions into one number. An operator cannot act differently on "chattering" versus "nobody has looked at this in six days" if both are just 0.7 |
| **Suppress automatically above a confidence threshold** | Model confidence is not calibrated to operational consequence. And it would violate `FR-32`'s guards |
| **Build the dismissal-learning loop now** | With no real operators we would seed the dismissals ourselves, then present the loop "learning" a pattern we planted. Manufactured evidence, and adjacent to the exact failure mode we differentiate against |
| **Publish compression alone** | Rewards over-suppression. The headline number would improve as the system got more dangerous |

## Consequences

**Good.** The system can say "I don't know", which no dashboard-shaped competitor will do and which is
the most defensible thing in the demo. Classification reuses `CMP-4`'s matched-band features, so the
hardest input is already paid for. The noise conditions are independently testable. And the
compression figure is honest by construction rather than by good intentions.

**Costs.** Three classes mean more UI states and a policy to enforce. The `UNDETERMINED` bucket will
look like a weakness to a judge who wants a confident number — the answer is that a triage system
which never abstains is lying, and that the rate is itself information. Standing-alarm detection
depends on acknowledgement timestamps, which creates a dependency on `CMP-17`.

**One genuine byproduct.** Acknowledgement timestamps give us **mean time to respond**
([profile §8](../../01-business/company-profile.md#8-kpis-the-company-runs-on)) for free, which
resolves `Q-18` in favour of committing to that KPI.

## Compliance

| Requirement | Test |
| --- | --- |
| `FR-57` four sources normalised | `T-62` |
| `FR-58`, `FR-59` temporal and causal correlation | `T-63`, `T-64` |
| `FR-60`…`FR-62` chattering, standing, flood | `T-65`, `T-66`, `T-67` |
| `FR-63` three-way classification with stored evidence | `T-68` |
| `FR-64` `UNDETERMINED` never hidden | `T-61` |
| `FR-32` suppression guards | `T-29`, `T-30`, **`T-60`** |
| `FR-67`, `FR-68` noise metrics and the anti-gaming pairing | `T-70` |
| **No seeded real failure suppressed or dismissed** | **`T-60` — gating, zero tolerance** |
