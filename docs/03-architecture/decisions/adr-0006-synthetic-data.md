# ADR-0006 — Damage-driven synthetic data generation

> **Status:** Accepted · **Owner:** SA · **Last updated:** 2026-09-17 ·
> **Related:** [ADR-0007](README.md#adr-0007--ml-approach), [ADR-0016](README.md#adr-0016--history-window)

---

## Context

Everything in this build rests on the synthetic dataset. If the sensor data does not carry
information about the failures, then no model can learn anything, and a "prediction" becomes a
relabelled rule — which is exactly what happened to the reference solution, in a way worth
understanding before we repeat it.

Its failures were drawn as `UNIFORM(0, 100, RANDOM()) < 2`, independent of every sensor value, and
its `ML_FEATURE_STORE.FAILED_IN_NEXT_7_DAYS` label derived from that draw. The label was therefore
**unlearnable from its own features**: anyone training on it gets AUC ≈ 0.5. Separately, its
degradation term evaluated to zero for all 180,000 rows, so even the intended trend was absent
([analysis §3.2](../../00-hackathon/reference-solution-analysis.md#32-two-arithmetic-bugs-make-it-worse-on-any-run-today)).

Generating "realistic-looking" data is easy and worthless. The dataset must be *learnable* and
*honestly difficult*.

## Decision

Generate data through an explicit **damage state variable** per component instance, so that causality
runs in one direction only:

```
operating conditions ──► damage accumulation ──► signal response
                                    │
                                    └──────────► failure event
```

| Rule | Consequence |
| --- | --- |
| Damage accumulates as a function of operating conditions, component age, platform and site stressor | Older VW-2.1 turbines and harsher sites degrade faster, matching the profile |
| Damage is monotonic within a component life, and **resets on replacement** | Genealogy becomes meaningful: the position continues, the part starts fresh |
| `signal = f(damage) + g(operating point) + noise` | Degradation is only visible **after** controlling for the operating point — which is why `CMP-4` bands by RPM and load, and why the feature engineering is real work |
| Failure occurs when damage crosses a per-instance threshold | Failure is *caused by* the degradation path. The label is learnable |
| The threshold varies per component instance | Prevents the model learning one constant and calling it physics |
| Noise amplitude is an explicit, recorded parameter | Difficulty is tuned deliberately and reported honestly |
| Failure mix is drivetrain-weighted | Matches published reliability patterns cited in the profile |
| No fixed row-count caps; generation runs to the current date | Avoids the reference solution's staleness bug |
| Every downstream threshold must be crossed by real generated rows | Avoids the reference solution's dead-threshold bug |

**The honesty constraint.** Noise must be high enough that a trivial baseline — a single-signal
threshold — does **not** match the trained model. If a threshold rule performs as well as the
classifier, we have not built a predictive system; we have built a rule and given it a nicer name.
`T-10` tests the model beats a random baseline; the harder check is that it also beats the trivial
one.

## Alternatives considered

| Option | Why not |
| --- | --- |
| **Random signals + independently drawn failures** | The reference solution's approach. Unlearnable by construction |
| **Failures first, then back-fill a trend before each one** | Tempting and simpler, but it teaches the model to detect the *shape we drew*, and produces no true negatives that look like near-misses. Leakage disguised as signal |
| **Real public SCADA data** (e.g. an open wind-farm dataset) | More credible, but licensing must be verified under Official Rules §4.4, failure labels are sparse and inconsistent, and it would not match our fleet, contracts or component model. Recorded as a possible enrichment, not the foundation |
| **Physics simulation of a drivetrain** | Correct and far beyond 90 person-hours |

The second row is the trap worth naming explicitly, because it is the shortcut a tired team reaches
for on day 9. Back-filling a trend behind known failures is a form of label leakage: the model
learns the artefact, the metrics look excellent, and the system fails on anything real.

## Consequences

**Good.** The label is learnable, so `M3` is real work rather than theatre. Degradation requires
matched-condition comparison to see, which makes the feature engineering genuinely valuable and
matches actual CMS practice. Component replacement resetting damage makes genealogy answerable
(`GS-2`). Difficulty is a parameter we can state.

**Costs.** This is the single largest and riskiest piece of work in the plan (`R-REF-2`), it must be
built first because everything depends on it, and its estimate is the least reliable. Tuning noise so
the problem is neither trivial nor impossible will take iteration.

**Reporting obligation.** Because we designed the data, every metric we quote describes *our
generator*, not the world. The business case says this explicitly and the pitch must too.

## Compliance

| Requirement | Test |
| --- | --- |
| `FR-9` degradation trends before failure | `T-8` |
| `FR-10` failure caused by the degradation path | `T-9` |
| `FR-11` label is learnable | `T-10` |
| `FR-12` data reaches the current date | `T-11` |
| `FR-13` every threshold reachable | `T-12` |
| `FR-14` drivetrain-weighted mix | `T-7` |
| `FR-15` labelled synthetic | `T-13` |
