# ADR-0003 — Turbine OEE definition

> **Status:** **Proposed** — awaiting team confirmation · **Owner:** NK · **Last updated:** 2026-09-17
>
> Required by [company-profile.md §8](../../01-business/company-profile.md#8-kpis-the-company-runs-on),
> which proposes this definition and explicitly says *"This is **our proposal, not an industry
> standard**. Confirm it in round 2 and record it as an ADR."* This is that ADR.

---

## Context

The brief asks us to "lift Overall Equipment Effectiveness". OEE is a **factory** metric:
`Availability × Performance × Quality`, where Performance compares actual output to ideal cycle time
and Quality is good units over total units. It assumes discrete units of production and a definable
ideal rate.

A wind turbine has neither. Its output depends on a resource nobody controls. A turbine producing
0 MW in still air is working perfectly; the same turbine producing 0 MW in a 12 m/s wind is broken.
So "ideal rate" is only meaningful relative to the wind actually available, and "units" and "scrap"
do not exist at all.

The wind industry's own standards address availability, not OEE: IEC 61400-26 parts 1 and 2 cover
time-based and production-based availability, and the industry `Ready / Unavailable / Neglected`
framework gives `Availability = R ÷ (R + U)`. There is no standard wind OEE to adopt.

So we either decline the brief's word, or adapt it and say clearly that we adapted it.

## Decision

Adopt the profile's definition **unchanged**:

> **Turbine OEE = Availability × Performance × Quality**
>
> | Factor | Definition | Catches |
> | --- | --- | --- |
> | **Availability** | Time-based availability, **wind-in-limits** — counting only time when wind and temperature are within specification and the grid and balance of plant are available | Downtime the turbine is responsible for |
> | **Performance** | Actual energy ÷ energy expected from the power curve at the measured wind, while available | Underperformance while running: yaw misalignment, pitch faults, blade degradation |
> | **Quality** | Energy delivered within the forecast-schedule tolerance ÷ energy generated | Schedule deviation, which is what Indian DSM rules penalise |

And attach two engineering commitments that follow from the reference-solution analysis:

1. **The composed value must equal the product of its three stored components**, exactly (`FR-26`,
   `T-23`).
2. **No factor may be a constant or a random value** (`FR-28`, `T-25`).

Those two lines exist because the reference solution violated both: its `Performance` was
`UNIFORM(80,98)` in SQL and hardcoded `0.95` in Python — two different fake definitions of one
factor — and its stored `OEE_PERCENT` drew a *second, independent* random value, so `OEE ≠ A × P × Q`
while its semantic view told the language model that it was
([`G-7`](../../00-hackathon/reference-solution-analysis.md#33-the-rest-of-the-gap-list)). Any user who
checked the arithmetic would have caught it.

## Alternatives considered

| Option | Why not |
| --- | --- |
| **Don't report OEE; report availability and lost production only** | Most defensible technically — these are the metrics the industry actually uses, and IEC 61400-26 covers them. But the brief explicitly asks to "lift OEE", and silently substituting different metrics reads as dodging the requirement |
| **Availability × Performance only, dropping Quality** | Honest, since Quality has no natural wind analogue. But it abandons the grid-obligation dimension, which is a real Indian concern and a genuine differentiator |
| **Quality = energy meeting power-quality standards** (voltage, frequency, reactive) | Arguably a truer reading of "quality". Rejected: we have no plausible synthetic basis for power-quality data, and it would be invented detail |
| **Quality = 1 always** | Turns a three-factor metric into two factors wearing a disguise. This is how the reference solution's constant `Performance` happened |
| **Capacity Utilisation Factor instead** | Already a profile KPI in its own right. It measures resource availability as much as asset health, so it cannot substitute |

## Consequences

**Good.** We answer the brief's fourth ask directly, decomposed into three factors a maintenance
audience can act on differently: downtime, underperformance, and schedule deviation. The Performance
factor is what makes `GS-5` — yaw misalignment losing energy with no alarm and full availability —
expressible at all. And it is honest: an adaptation, declared as one.

**Costs.** Every artefact must label this as our proposal rather than a standard, including the
pitch. Performance needs a power curve per platform, which is additional synthetic-data work and is
`Q-23`'s open question. Quality needs a forecast-versus-actual schedule model, which is the weakest
of the three and the first factor to drop if capacity bites — and if it drops, we report
`Availability × Performance` and say so, rather than setting Quality to 1.

**Risk.** A judge with wind-industry background may challenge the term. The answer is the honest one:
*"OEE is a factory metric; there is no standard wind OEE. This is our adaptation, these are the three
factors, here is what each one catches, and here is the availability standard we do follow."*
Declared adaptation is defensible; undeclared substitution is not.

## Compliance

| Requirement | Test |
| --- | --- |
| `FR-26` OEE computed; product identity holds | `T-23` |
| `FR-28` no constant or random factor | `T-25` |
| `FR-27` single definition across app, semantic view, agent | `T-24` |
| `FR-24` lost energy from the power curve | `T-21` |
| `NFR-10` labelled as our proposal, not a standard | `T-13` |
