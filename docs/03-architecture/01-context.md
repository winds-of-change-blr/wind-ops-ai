# C4 Level 1 — System Context

> **Status:** Draft v0.1 · **Owner:** NK · **Last updated:** 2026-09-17
>
> Actors are the personas from
> [personas-and-journeys.md](../01-business/personas-and-journeys.md). External systems are VWS's
> real source systems from
> [profile §7](../01-business/company-profile.md#7-systems-landscape-where-predictive-maintenance-data-comes-from).

---

```mermaid
C4Context
    title Wind Ops AI — system context
    Person(p7, "RMC / SCADA Engineer", "P-7 · 24x7 alarm triage")
    Person(p2, "CMS Analyst", "P-2 · vibration review")
    Person(p3, "Maintenance Planner", "P-3 · plans and approves work")
    Person(p8, "Reliability Engineer", "P-8 · root cause")
    Person(p1, "COO Services / O&M Controller", "P-1, P-5 · availability and LD exposure")
    Person(p4, "Field Technician", "P-4 · executes the work")
    Person(p6, "Data Platform Engineer", "P-6 · runs the platform")

    System(woa, "Wind Ops AI", "Predictive maintenance and OEE command center on Snowflake. Predicts component failure with explained drivers, answers why with citations, and turns decisions into approval-gated work orders.")

    System_Ext(s1, "SCADA historian", "S1, S2 · 10-min signals, events and alarms")
    System_Ext(s3, "CMS", "S3 · vibration features, condition reports")
    System_Ext(s8, "CMMS / EAM", "S8 · asset register, work orders, PM plans")
    System_Ext(s10, "ERP materials", "S10 · stock, reservations, lead times")
    System_Ext(s11, "ERP finance & contracts", "S11 · guarantees, LD rates, exclusions")
    System_Ext(s13, "Document management", "S13 · OEM manuals, service bulletins")
    System_Ext(s5, "Met & weather forecast", "S5 · wind limits for work windows")
    System_Ext(cust, "Customer", "IPP / C&I · receives availability reports")

    Rel(p7, woa, "Triages ranked alerts, escalates, suppresses nuisance patterns")
    Rel(p2, woa, "Reviews CMS findings, confirms diagnosis")
    Rel(p3, woa, "Reviews backlog, approves work orders")
    Rel(p8, woa, "Asks why, in natural language")
    Rel(p1, woa, "Monitors availability vs guarantee and LD exposure")
    Rel(p4, woa, "Reads the job pack")
    Rel(p6, woa, "Operates pipelines, models and access")

    Rel(s1, woa, "Signals, events, operating states")
    Rel(s3, woa, "Vibration features, analyst reports")
    Rel(s8, woa, "Asset register, work-order history")
    Rel(woa, s8, "Approved work-order drafts")
    Rel(s10, woa, "Stock and lead times")
    Rel(woa, s10, "Reservation requests")
    Rel(s11, woa, "Contract terms")
    Rel(s13, woa, "Documents for parsing")
    Rel(s5, woa, "Wind and weather limits")
    Rel(woa, cust, "Availability and generation reporting")
```

## Boundaries

| Question | Answer |
| --- | --- |
| Does Wind Ops AI replace SCADA, CMS or the CMMS? | **No.** It converges their data. Scope item [`W10`](../02-functional/scope.md#6-wont-this-hackathon) |
| Which integrations are real in the prototype? | **None.** All seven external systems are simulated by `CMP-1`, because VWS is fictional. The *data shapes* are real; the connections are not. Stated in every artefact per `NFR-10` |
| Which arrows point *out* of the system? | Three: approved work orders to the CMMS, reservation requests to ERP materials, and reporting to the customer. All three are approval-gated ([ADR-0005](decisions/adr-0005-approval-gated-writes.md)) |
| What does the prototype write to? | Its own `ACTION` schema, which stands in for the CMMS. The write is real; the destination is modelled |

## Simulated versus real

Being explicit, because the honesty rule requires it and because a judge will ask.

| Element | In the prototype |
| --- | --- |
| Turbines, components, signals | Synthetic, generated (`CMP-1`) |
| SCADA 10-minute data and alarms | Synthetic, with plausible diurnal and seasonal behaviour |
| CMS vibration features | Synthetic, with **real pre-failure trends** (`FR-9`) |
| Work orders, stock, contracts | Synthetic, referentially consistent with the above |
| OEM manuals, bulletins, condition reports | Synthetic **files**, genuinely parsed (`FR-39`) |
| Weather | Synthetic, unless `C9` brings in Marketplace data |
| The prediction | **Real** — trained and evaluated (`FR-17`) |
| The metrics | **Real** — computed from the state data (`FR-22`…`FR-26`) |
| The retrieval and citations | **Real** — a search service over parsed files (`FR-40`) |
| The write, approval and audit | **Real** — into `ACTION` (`FR-35`…`FR-37`) |

The line to hold in the pitch: **the data is synthetic; the system is not.**
