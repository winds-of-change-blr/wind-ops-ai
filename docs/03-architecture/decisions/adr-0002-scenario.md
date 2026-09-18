# ADR-0002 — Scenario: an Indian wind-turbine OEM that maintains its own fleet

> **Status:** Accepted · **Owner:** NK · **Last updated:** 2026-09-17
>
> Recorded because [company-profile.md §12](../../01-business/company-profile.md#12-impact-on-other-planning-docs)
> requires it. The scenario itself is **already decided and given** — this ADR records *why*, and
> what follows from it.

---

## Context

The brief is written for manufacturing: *"Manufacturers lose value to unplanned downtime because OT
sensor data sits apart from ERP and maintenance context."* It asks us to correlate vibration,
temperature and RPM with ERP and maintenance records, predict failures, support natural-language root
cause, deliver a command center, and lift OEE.

A literal reading gives a factory: plants, lines, processes, machines. That is what the official
reference solution builds — 2 plants, 6 lines, 18 assets, robot arms and pumps.

The choice of scenario is not cosmetic. It determines whether "downtime costs money" is a modelled
fact or an invented constant, and it is scored directly under `E1` Real World Relevance.

## Decision

**A fictional Indian wind-turbine OEM that also operates and maintains the fleet it sells** —
Vayuveda Wind Systems, 100 turbines across 6 wind parks in 5 states, under multi-year comprehensive
O&M contracts with availability guarantees and liquidated damages. Fully specified in
[company-profile.md](../../01-business/company-profile.md).

## Why this, over a factory

| Dimension | Factory | Wind O&M |
| --- | --- | --- |
| **Consequence of downtime** | Has to be invented. The reference solution literally hardcodes `$150,000 / $50,000` and labels it "Cost Avoidance (YTD)" | **Contractual.** 95%/97% availability guarantee, LD at a stated rate per turbine per 1% shortfall. The money is in the contract, not in a constant |
| **Why timing matters** | Not modelled | **Wind season May–September.** The same failure costs far more in July than in March, so the output is a *scheduling* decision, not just a prediction |
| **Repair decision** | Replace the part | **Up-tower versus crane campaign** — a real, expensive, lead-time-driven choice with a bundling incentive |
| **Sensor realism** | Generic temperature and vibration | Documented CMS practice: band energies, kurtosis, oil-debris counts, minimum sensor placements per drivetrain |
| **Asset history** | Asset ID | **Component genealogy** — serials move between positions, so "this position failed twice" and "this part failed twice" are different questions |
| **OT/IT gap** | Asserted | **Structural and documented**: SCADA in the RMC, vibration in a separate CMS tool emailed as PDFs, planners in the CMMS, stores in the ERP |
| **Grid context** | None | Indian forecasting, scheduling and DSM deviation rules |

The decisive point is the first row. A predictive-maintenance system's whole value is deciding
*whether intervening is worth it*, and that requires a real cost of not intervening. A wind O&M
contract supplies one; a generic factory requires us to make one up. Since the reference solution
does make one up, and a judge can see it in the source, this is where the entry separates.

## Alternatives considered

| Option | Why not |
| --- | --- |
| **Discrete manufacturing plant** | The reference solution's territory. We would be compared directly, and on their strongest axis — a broad semantic model — while inheriting their weakest, an invented cost of downtime |
| **Process plant** (cement, steel, chemicals) | Good fit for OEE, which is genuinely a factory metric. But downtime cost is still internal and negotiable rather than contractual, and continuous-process modelling is heavier |
| **Rail or aviation fleet** | Excellent maintenance stories, but safety-critical framing invites questions we cannot answer responsibly in 15 days on synthetic data |
| **Solar farm** | Simpler assets, far less interesting failure physics, almost no drivetrain story |
| **A real, named company** | Prohibited: no third-party confidential content, and no real customer data (Official Rules §5, AGENTS.md rule 5) |

## Consequences

**Good.** Real-world relevance is structural rather than asserted. Risk can be ranked in rupees
(`M5`, `D-9`) because the LD rate and guarantee come from a contract. The seasonal constraint gives
the planning journey (`J-3`) genuine tension. Genealogy gives us a differentiator the reference
solution cannot retrofit. Indian context suits a GCC-edition hackathon judged in India.

**Costs.** OEE is a factory metric and does not transfer cleanly, which forces the Turbine OEE
adaptation in [ADR-0003](adr-0003-turbine-oee.md) — an adaptation we must present as *our proposal*,
not an industry standard. Wind domain knowledge has to be right or a knowledgeable judge will notice,
which is why the profile carries a cited source list. And the fleet's scale (100 turbines × 10
components) makes the synthetic data harder than 18 factory assets.

**Obligations this creates.** Everything must use the profile's vocabulary, roles, systems and KPI
definitions rather than inventing parallel ones. Every wind-industry fact is cited; everything
invented is marked *(illustrative)*. The company is labelled fictional and the data synthetic,
everywhere.

## Compliance

| Requirement | Where |
| --- | --- |
| Real-world relevance (`E1`) | [business-case.md](../../01-business/business-case.md) |
| Roles map to the company's actual org (`E1`) | [personas-and-journeys.md](../../01-business/personas-and-journeys.md) |
| Synthetic-only, no real company data | `NFR-10`, `FR-15`, `T-13` |
| KPI definitions not duplicated | `FR-27`, `T-24` |
