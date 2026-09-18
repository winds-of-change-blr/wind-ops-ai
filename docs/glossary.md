# Glossary

> **Status:** Draft v0.2 · **Owner:** JP · **Last updated:** 2026-09-18
>
> One term, one meaning. Where a term is defined in
> [company-profile.md](01-business/company-profile.md), that definition governs and this entry
> points at it rather than restating it.

---

## Wind and O&M

| Term | Meaning |
| --- | --- |
| **WTG** | Wind turbine generator. Used interchangeably with "turbine" |
| **O&M** | Operations and maintenance. VWS's service business |
| **Availability guarantee** | The contractual availability VWS warrants — 95% in years 1–2, 97% from year 3 ([profile §2](01-business/company-profile.md#2-business-model--contracts)) |
| **Liquidated damages (LD)** | What VWS pays when contractual availability falls below the guarantee. ₹50,000 per turbine per 1% shortfall per contract year *(illustrative)* |
| **LD exposure** | *Forecast* liability from a predicted shortfall. Distinct from LDs paid |
| **Contractual availability** | The negotiated metric, excluding contract exclusions ([profile §8](01-business/company-profile.md#8-kpis-the-company-runs-on)) |
| **Technical availability** | Availability counting only turbine-caused downtime as unavailable |
| **Wind-in-limits** | Availability counted only while wind and temperature are in specification and the grid and balance of plant are available |
| **Exclusion** | A downtime cause that does not count against the provider — grid, force majeure, balance-of-plant, curtailment, scheduled allowance |
| **Contract year** | The year of the contract in force, **not** the calendar year. Determines which guarantee applies |
| **Lost energy** | Energy not produced versus power-curve expectation. **The customer's** revenue, not VWS's |
| **CUF** | Capacity Utilisation Factor — energy generated ÷ (rated capacity × hours) |
| **Wind season** | Roughly May–September in India, when most annual generation happens. Heavy work belongs before it |
| **Up-tower** | A repair done inside the nacelle without a crane. Fast and cheap by comparison |
| **Crane campaign** | A repair needing a mobile crane. Expensive, long lead time, and worth bundling |
| **DSM** | Deviation Settlement Mechanism — Indian rules penalising generation that deviates from schedule |
| **BoP** | Balance of plant — site infrastructure outside the turbine |
| **IPP / C&I** | Independent power producer / commercial and industrial buyer. VWS's customer types |

## Assets

| Term | Meaning |
| --- | --- |
| **Component position** | A slot on a turbine, e.g. `KA-CTD-T07-GBX`. Persists across part replacement |
| **Installed serial** | The physical part currently in a position, e.g. `GBX-24-00318`. Has its own history |
| **Component genealogy** | Which serial occupied which position, when. Makes "has *this part* failed before?" answerable |
| **Component class** | `GBX` gearbox, `MSB` main shaft & bearing, `GEN` generator, `PIT` pitch, `BLD` blades, `CNV` converter, `TRF` transformer, `YAW` yaw, `NAC` nacelle auxiliaries, `TWR` tower ([profile §5](01-business/company-profile.md#5-anatomy-of-an-asset-turbine--components--sensors)) |
| **HSS** | High-speed shaft — the gearbox output stage. Its bearing is the `GS-1` failure |
| **Platform** | Turbine model — VW-2.1 (legacy) or VW-3.0 (current) |
| **Power curve** | Expected power output at a given wind speed. The basis for lost energy and OEE Performance |

## Monitoring

| Term | Meaning |
| --- | --- |
| **SCADA** | The turbine control and monitoring system. Source of 10-minute statistics and alarms |
| **CMS** | Condition monitoring system — vibration analysis on the drivetrain |
| **CMS feature** | A derived vibration measure: band energy, kurtosis, trend. **We use features, never raw waveforms** (`W1`) |
| **Band energy** | Vibration energy in a frequency band associated with a specific fault |
| **Oil debris** | Particle count in gearbox oil. A confirming wear signal |
| **Operating state** | What the turbine was doing over an interval. The basis of all availability arithmetic |
| **Alarm** | A coded event with a start and end. A present fact |
| **Incident** | A group of related alarms. Forty auto-resets are one incident |
| **Nuisance alarm** | An alarm that recurs without indicating real degradation |
| **Matched conditions** | Comparing signals only within the same RPM and load band, so degradation is not confused with load change |

## System

| Term | Meaning |
| --- | --- |
| **Risk score** | Predicted probability of component failure within the horizon. A prediction, not an alarm |
| **Horizon** | The prediction window — 30 days |
| **Driver** | A feature contributing to a risk score, with magnitude and direction. Every score has them |
| **Lead time** | Days between risk first crossing the threshold and the actual failure. What makes a prediction *actionable* |
| **Candidate window** | A maintenance slot satisfying **every** constraint. Infeasible slots are excluded, not ranked down |
| **Money at stake** | LD exposure plus lost energy for an alert. The ranking signal |
| **Draft** | A proposed work order awaiting human approval. Never written until approved |
| **Approval gate** | The human act that permits a write |
| **Idempotency key** | A caller-supplied key ensuring a retry does not create a second action |
| **Audit** | The append-only record of every state change. Written *before* the change |
| **Suppression** | An explicit, time-boxed, reversible, audited decision to mute an alarm pattern. Never automatic |
| Compression ratio | Alarms in ÷ incidents out, **never shown without the count of real failures suppressed beside it**. Published alone it rewards over-suppression |
| Undetermined | An incident whose evidence does not support calling it actionable or nuisance. Stays in the queue, never hidden, never auto-suppressed |
| Chattering | Repeated trip and auto-reset on one signature within a window |
| Standing / stale | An alarm open beyond a threshold with nobody acting |
| Flood period | Alarm rate above a per-site threshold |
| Incident | A group of related alarms. Forty auto-resets are one incident; a site-wide grid dip is one, not forty |
| Binding constraint | The specific reason nothing is feasible — "no certified crew until week 44". An answer, not a failure |
| Suggestion | A typed proposed change to the schedule: add, move, bundle or cancel. Always drawn from engine-produced windows |
| Season mode | "Plan the season" — a 12-month horizon for crane-dependent and long-lead work, returning a ranked list of campaign proposals |
| Refresh only | An automated run may recompute derived output. It may never write state or approve anything |
| Compression funnel | The visual rendering of alarms in → incidents → actionable / nuisance / undetermined. Our one striking visual, and it cannot render without the failures-suppressed count |
| Minimum viable submission | The floor that still goes in on D15 if the build collapses, and still addresses all four brief asks ([scope §7](02-functional/scope.md#minimum-viable-submission)) |
| Scoring surface | The deck, the root `README`, the 2-minute walkthrough and the results summary — what a judge actually sees. **Not** `docs/` |
| **Turbine OEE** | `Availability × Performance × Quality` — **our proposal, not an industry standard** ([ADR-0003](03-architecture/decisions/adr-0003-turbine-oee.md)) |
| **Determinism boundary** | The rule that engines decide state and the model explains it ([ADR-0004](03-architecture/decisions/adr-0004-determinism-boundary.md)) |
| **Engine** | Deterministic, unit-tested SQL or Snowpark that computes state, feasibility or ranking |
| **Degraded mode** | The documented fallback for a core-demo dependency (`NFR-7`) |
| **Learnable label** | A prediction target genuinely inferable from the features. Tested, not assumed |
| **Damage** | The generator's hidden state variable driving both signals and failure ([ADR-0006](03-architecture/decisions/adr-0006-synthetic-data.md)) |
| **(illustrative)** | Marks an invented figure. Real-world facts are cited instead |

## Terms we avoid

| Avoid | Use instead | Why |
| --- | --- | --- |
| "Real-time" | "Incremental, with a declared target lag" for the **one** path that is; "refreshed daily" for the rest | `M12` restores one incremental path, so the accurate phrasing is also the honest one. Never say "real-time" unqualified |
| "Health score" | "Risk score with drivers" | The reference solution's health score was a function of primary key |
| "AI-powered" | Name the actual capability | Says nothing, and invites the question we want to answer specifically |
| "Autonomous" | "Approval-gated" | Autonomy is prohibited by design (`W3`) |
| "Digital twin" | "Fleet view" / "site view" | We are not building a twin |
| "Predicts failure mode" | "Predicts failure risk for a component class" | We predict risk per class, not a named mode |
| "Self-learning" / "it learns from your feedback" | "Repeated dismissals **propose** a pattern for human approval" | And in this prototype that proposal is designed, not built (`W13`) |
| "Noise reduced by N×" | The compression ratio **and** the real-failures-suppressed count | Compression alone is the metric that rewards hiding failures |
| Plant / line / process / asset | Site / turbine / component / signal | Factory vocabulary from the old scenario |
