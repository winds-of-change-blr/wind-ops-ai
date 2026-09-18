# Results Summary — specification

> **Status:** Draft v0.2 · **Owner:** NK · **Last updated:** 2026-09-18
>
> **v0.2 adds** the aggregate outcome sentence (§2.0) and the rule-versus-model comparison (§2.0b).
>
> **This file is the specification. The artefact itself is generated on D15 from `OPS`** and
> replaces the placeholders below. It must not be written by hand — `T-92` asserts it reconciles to
> its source.
>
> **Why it exists.** `E9` Execution asks for *"a clear timeline and effective results"*. The project
> plan covers the timeline. Nothing in the plan previously covered **results** — we could describe
> what we built but not what it does. This is that artefact, and it is deck slide 13.

---

## 1. Why generated, not written

A hand-written results section is a claim. A generated one is a measurement.

| Risk of hand-writing | How generation removes it |
| --- | --- |
| Numbers drift from reality as the build changes | Regenerated on demand from `OPS` |
| Flattering figures get selected | The query is fixed before the numbers are known |
| A judge cannot check it | Every figure has a source table and a query |
| It becomes marketing | `T-92` requires reconciliation |

The reference solution presented `$150,000 / $50,000` literals in Python as "Cost Avoidance (YTD)".
That is precisely the failure mode this artefact is designed to make impossible for us.

## 2. Structure

### 2.0 The one sentence

**Leads the summary, the deck's results slide and the README.** Generated, never typed.

> *"Over `<window>`, `<N>` of `<M>` seeded failures were flagged before they occurred, with a median
> lead time of `<D>` days, representing `<₹X>` of LD exposure identified before it crystallised."*

This is the number a judge repeats to another judge. Every term has a source: `N`/`M` from the
evaluation run, `D` from the lead-time distribution, `₹X` from `MET_LD_EXPOSURE`. `T-95` asserts it
reconciles.

### 2.0b Rule versus model

The most persuasive artefact we own, and until v0.4 it was tested in the dark.

| Figure | Source |
| --- | --- |
| Components flagged by a **trivial single-signal threshold rule** | evaluation run |
| Components flagged by **the model** | evaluation run |
| Of each, how many **actually failed** within the horizon | seeded ground truth |
| False positives avoided | derived |

**The rule must be defined before the comparison is run**, and it must be the obvious one an engineer
would reach for — not a strawman. `T-94` asserts the displayed figures reconcile to the evaluation run;
the integrity of the baseline choice is a review obligation, made on **D8**, before the numbers are
known.

### 2.1 What the model actually does

| Figure | Source | Notes |
| --- | --- | --- |
| Precision and recall at the operating point | `OPS` model evaluation run | Held-out split by **component and time**, never by row |
| PR-AUC | same | Accuracy deliberately **not** reported — meaningless under this imbalance |
| Lift over a stratified-random baseline | same | The floor |
| **Lift over a trivial single-signal threshold** | same | **The honest test.** If this is not clearly positive, we have a rule, not a model |
| Lead-time distribution | `OPS` | Median and spread of days between first elevated risk and the seeded failure. *Actionable* lead time, not just detection |
| Model version, feature count, training window | `OPS` | Provenance |

### 2.2 What the triage actually does

| Figure | Source |
| --- | --- |
| Alarms in, over the demo window | `MET_NOISE` |
| Incidents out | `MET_NOISE` |
| Actionable / nuisance / **undetermined** counts | `MET_NOISE` |
| **Compression ratio** | `MET_NOISE` |
| **Real failures suppressed or dismissed** | `MET_NOISE` — **inseparable from the line above** |
| Undetermined rate | `MET_NOISE` |
| Chattering and standing counts | `MET_NOISE` |
| Classification precision per source | `CMP-17` |

**The pairing rule applies here as it does everywhere:** compression is never printed without
failures-suppressed on the same line. If the second number is not zero, the first number is a
liability, not an achievement — and the summary must say so rather than bury it.

### 2.3 What the numbers are worth

| Figure | Source | Caveat carried in the artefact |
| --- | --- | --- |
| LD exposure identified ahead of failure | `MET_LD_EXPOSURE` | Against a **synthetic** fleet and *(illustrative)* LD rate |
| Lost energy avoidable on the planned path | `MET_LOST_ENERGY` | Customer revenue, not VWS's |
| Turbine OEE, decomposed | `MET_TURBINE_OEE` | Our declared adaptation, not a standard |
| Mean time to respond | `MET_MTTRESPOND` | From alarm acknowledgement timestamps |

### 2.4 What we proved about ourselves

| Figure | Source |
| --- | --- |
| Gating tests passing — **17 of 17** required | test run |
| Degraded modes exercised | `T-53` checklist |
| Setup runs twice from clean | `T-52` |
| `README` followed by a non-author | `T-89` |
| Credits consumed — **CoCo tokens + warehouse, summed** | `ACCOUNT_USAGE` |
| CoCo sessions, requests, tokens per phase | `CORTEX_CODE_*_USAGE_HISTORY` |

### 2.5 What did not work

**A required section, not an optional one.** Whatever we attempted and dropped, whatever a test
exposed, whatever the model does worse than hoped. Two reasons: it is the most credible part of any
results page, and a judge who finds an unstated weakness discounts everything else on the page.

Expected candidates: lead time shorter than the planning horizon needs for some component classes;
drivers being feature importances plus deviations rather than true per-prediction attributions; the
undetermined rate being higher than comfortable.

## 3. Rules

| Rule | Reason |
| --- | --- |
| Generated from `OPS`, never typed | `T-92` |
| Every figure names its source table | A judge can check it |
| Compression never appears without failures-suppressed | `FR-68` |
| **The baseline rule is defined on D8, before the comparison is run** | Otherwise the baseline is chosen to flatter the model, which is the same dishonesty as a fake score |
| No accuracy figure | Misleading under this imbalance |
| Every *(illustrative)* input marked | `NFR-10` |
| §2.5 is never empty | An empty weaknesses section is itself a warning sign |
| One page | It is a deck slide and a README section, not a report |

## 4. Where it appears

| Surface | Form |
| --- | --- |
| Deck slide 9 | **Rule versus model** (§2.0b) |
| Deck slide 14 | The headline figures, led by the one sentence (§2.0) |
| Demo, 2:10–2:30 | The baseline comparison on screen |
| Demo, 3:40–4:00 | The one sentence as the closing line |
| Root `README` | A "Results" section near the top, led by the one sentence |
| This file | The full generated artefact |
| `OPS` | The source of every number |

## 5. Open questions

| ID | Question | Owner |
| --- | --- | --- |
| `Q-86` | Which single figure leads the summary? Recommendation: **lift over the trivial rule** — it is the one that proves the model is a model | SA |
| `Q-87` | Do we publish the undetermined rate even if it is high? Recommendation: **yes.** A suppressed uncertainty figure would undo the credibility the class was built to earn | NK |
| `Q-91` | Which signal is the trivial baseline rule built on — CMS band energy, or bearing temperature? Recommendation: **band energy**, because it is the signal an engineer would actually threshold, which makes the comparison fair rather than a strawman | SA |
| `Q-92` | If the model does **not** clearly beat the rule, do we still show the comparison? Recommendation: **yes** — and say so on the honesty slide. A hidden unfavourable comparison is precisely the dishonesty we differentiate against | NK |
