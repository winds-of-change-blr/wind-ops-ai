# Requirements

> **Status:** Draft v0.4 · **Owner:** JP · **Last updated:** 2026-09-18
>
> **v0.4 adds** `FR-97`…`FR-99`: the baseline comparison shown rather than only tested, a generated
> aggregate outcome statement, and demonstrable suppression guards. Gating tests go from 17 to **18**.
> None of these add build surface — each surfaces work the plan already does.
>
> **v0.3 added** `FR-89`…`FR-96` and `NFR-20` for demonstrable freshness (`M12`), visual proof, and
> submission artefacts (`M13`).
>
> **v0.2 added** `FR-57`…`FR-88` and `NFR-18`…`NFR-19` for alarm intelligence (`M9`), planned work
> (`M10`) and committed ingenuity (`M11`), plus components `CMP-17`…`CMP-20`.
>
> **Readiness rule.** Every requirement carries five things: an **ID**, a **priority** (its
> [scope](scope.md) item), a **persona**, at least one **test**, and a **component** that
> implements it. If any of the five is missing, the requirement is marked `NOT READY` and must not
> be built.
>
> Tests are named here and specified in
> [testing-and-validation.md](../07-quality/testing-and-validation.md). Components are named here
> and elaborated in [the architecture](../03-architecture/README.md).

---

## 1. Components

Introduced here so requirements can name one. `CMP-` is a new prefix; Stage 4 owns the detail.

| ID | Component | Responsibility |
| --- | --- | --- |
| `CMP-1` | **Synthetic data generator** | Produces plausible SCADA, CMS, work-order, stock, contract and document data with seeded failures |
| `CMP-2` | **Landing & ingest** | Stages and raw tables; simulated arrival of new SCADA/CMS batches |
| `CMP-3` | **Curation pipeline** | Raw → curated → serving, incrementally |
| `CMP-4` | **Signal feature engine** | Per-component features from SCADA and CMS at matched operating conditions |
| `CMP-5` | **Metric layer** | Availability, lost energy, LD exposure, Turbine OEE — one definition each |
| `CMP-6` | **Risk model** | Trained classification and anomaly detection, plus driver attribution |
| `CMP-7` | **Alarm engine** | Normalises four alarm sources into one stream; correlates into incidents; labels chattering, standing and flood; classifies actionable / nuisance / `UNDETERMINED` with stored evidence |
| `CMP-8` | **Ranking service** | Orders alerts by money at stake |
| `CMP-9` | **Constraint engine** | Feasible maintenance windows against wind, crew, parts, crane. **Load-bearing for `CMP-18`** |
| `CMP-10` | **Action service** | Work-order draft, approval gate, idempotent write, audit append |
| `CMP-11` | **Document pipeline** | Parse documents; build and refresh the search service |
| `CMP-12` | **Semantic view** | Governed business model for natural-language querying |
| `CMP-13` | **Agent & tools** | Ranks and explains; read tools plus the approval-gated action tool |
| `CMP-14` | **Command center app** | The user surface |
| `CMP-15` | **Governance & RBAC** | Roles, grants, secrets, least privilege |
| `CMP-16` | **Observability** | Freshness, lag, data quality, model evaluation, cost |
| `CMP-17` | **Alarm feedback & noise metrics** | Confirm / dismiss / reinstate, per-source precision, noise numbers with the anti-gaming pairing |
| `CMP-18` | **Schedule suggestion & decision loop** | Typed proposals over engine windows, with reasoning, evidence, pre-commit impact, accept / edit / reject |
| `CMP-19` | **Notification & digest delivery** | Digest server-side; approval notification over MCP, interactive only |
| `CMP-20` | **Scheduled run** | One daily run refreshing scores, suggestions and digest. Refreshes only, never applies |
| `CMP-17` | **Alarm feedback & noise metrics** | Confirm / dismiss / reinstate capture, per-source precision, the noise numbers and the anti-gaming pairing |
| `CMP-18` | **Schedule suggestion & decision loop** | Typed change proposals over engine-produced windows, with reasoning, evidence, pre-commit impact, and accept / edit / reject |
| `CMP-19` | **Notification & digest delivery** | Server-side digest via notification integration; interactive approval notification via MCP |
| `CMP-20` | **Scheduled run** | One daily run refreshing scores, suggestions and the digest. Refreshes only, never applies |

## 2. Functional requirements

Priority column is the [scope](scope.md) item, which carries the MoSCoW level.

### 2.1 Data foundation

| ID | Requirement | Pri | Persona | Component | Test |
| --- | --- | --- | --- | --- | --- |
| `FR-1` | Ingest SCADA 10-minute statistics (wind, power, rotor and generator RPM, pitch, yaw, component temperatures) and SCADA events/alarms with start and end times, per turbine | `M1` | `P-6` | `CMP-2`, `CMP-3` | `T-1` |
| `FR-2` | **Correlate SCADA signals with CMS vibration features at matched operating conditions** (same RPM band and load band), so a vibration change is not confused with a load change | `M1` | `P-2` | `CMP-4` | `T-2`, `T-3` |
| `FR-3` | Ingest the CMMS asset register (site → turbine → component → signal), preventive-maintenance plans, and work orders with failure code, cause, remedy, labour hours and downtime | `M1` | `P-3` | `CMP-2`, `CMP-3` | `T-1` |
| `FR-4` | Ingest ERP materials (stock by warehouse and site, reservations, lead times) and O&M contract terms (guarantee %, LD rate, exclusions) | `M1` | `P-9`, `P-5` | `CMP-2` | `T-1` |
| `FR-5` | Maintain **component genealogy** — the installed serial per position over time — so failure history can be read by position *or* by serial | `S4` | `P-8` | `CMP-3` | `T-4` |
| `FR-6` | Curate raw → serving with a **declared target lag**, incrementally, without re-running a setup script | `S1` | `P-6` | `CMP-3` | `T-5` |
| `FR-7` | Every fact table carries the operating state, so downtime can be classified as turbine-caused, grid, or excluded | `M1` | `P-10` | `CMP-3` | `T-6` |

### 2.2 Synthetic data

| ID | Requirement | Pri | Persona | Component | Test |
| --- | --- | --- | --- | --- | --- |
| `FR-8` | Generate a fleet matching [profile §4](../01-business/company-profile.md#4-fleet--geography): 100 turbines, 6 sites, 2 platforms, with commissioning dates and site environment stressors | `M2` | `P-6` | `CMP-1` | `T-7` |
| `FR-9` | **Degradation must trend before failure.** For each seeded failure, the driving signals show a monotonic-in-expectation trend over a defined lead-in window before the failure timestamp | `M2` | `P-2` | `CMP-1` | `T-8` |
| `FR-10` | **Failures must be caused by the degradation path**, not drawn independently. Failure timing is a function of accumulated damage | `M2` | `P-2` | `CMP-1` | `T-9` |
| `FR-11` | The prediction label must be **learnable**: a model trained on generated features beats a stratified-random baseline by a stated margin on held-out data | `M2` | `SA` | `CMP-1`, `CMP-6` | `T-10` |
| `FR-12` | Data must extend to the **current date** at generation time, with no fixed row-count cap that truncates it | `M2` | `P-6` | `CMP-1` | `T-11` |
| `FR-13` | Every alarm and anomaly threshold must be **reachable** by the generated data ranges | `M2` | `P-7` | `CMP-1` | `T-12` |
| `FR-14` | The failure mix is drivetrain-weighted, consistent with [profile §3](../01-business/company-profile.md#3-the-problem-in-company-terms) | `M2` | `P-8` | `CMP-1` | `T-7` |
| `FR-15` | All generated data is labelled synthetic at the schema level | `M2` | `P-6` | `CMP-1` | `T-13` |

### 2.3 Prediction

| ID | Requirement | Pri | Persona | Component | Test |
| --- | --- | --- | --- | --- | --- |
| `FR-16` | Produce a **component-level failure risk** with an explicit prediction horizon, for the component classes in [profile §5](../01-business/company-profile.md#5-anatomy-of-an-asset-turbine--components--sensors) | `M3` | `P-2` | `CMP-6` | `T-14` |
| `FR-17` | The model is **trained and evaluated on held-out data**, and its metrics are recorded and displayable | `M3` | `SA` | `CMP-6` | `T-10`, `T-15` |
| `FR-18` | Every risk score carries its **top contributing features with magnitudes and direction**. No score is displayed anywhere without them | `M3` | `P-2`, `P-7` | `CMP-6` | `T-16` |
| `FR-19` | Report the **lead time distribution** — how far ahead of the seeded failure the model raised risk | `M3` | `P-3` | `CMP-6` | `T-17` |
| `FR-20` | Detect anomalies against expected behaviour at matched operating conditions, as a signal distinct from the trained classifier | `M3` | `P-2` | `CMP-6` | `T-18` |
| `FR-21` | Risk scores are **reproducible**: the same inputs produce the same score, and the model version is recorded with each score | `M3` | `P-6` | `CMP-6` | `T-19` |

### 2.4 Metrics

| ID | Requirement | Pri | Persona | Component | Test |
| --- | --- | --- | --- | --- | --- |
| `FR-22` | Compute **contractual availability** per [profile §8](../01-business/company-profile.md#8-kpis-the-company-runs-on), applying contract exclusions (grid, force majeure, scheduled-maintenance allowance) | `M4` | `P-10` | `CMP-5` | `T-20` |
| `FR-23` | Compute **technical availability**, counting only turbine-caused downtime | `M4` | `P-8` | `CMP-5` | `T-20` |
| `FR-24` | Compute **lost energy** from the power curve at measured wind speed, and energy-based availability | `M4` | `P-1` | `CMP-5` | `T-21` |
| `FR-25` | Compute **LD exposure**: forecast shortfall against the applicable guarantee × LD rate, per turbine and aggregated | `M4` | `P-5` | `CMP-5` | `T-22` |
| `FR-26` | Compute **Turbine OEE** using the profile's definition, and the composed value **must equal** the product of its three stored components | `M4` | `P-1` | `CMP-5` | `T-23` |
| `FR-27` | **No metric is defined twice.** App, semantic view and agent read the same definition; none re-derives it | `M4` | `P-10` | `CMP-5`, `CMP-12` | `T-24` |
| `FR-28` | **No component of any metric is a constant or a random value** | `M4` | `P-10` | `CMP-5` | `T-25` |

### 2.5 Triage and action

| ID | Requirement | Pri | Persona | Component | Test |
| --- | --- | --- | --- | --- | --- |
| `FR-29` | Rank alerts by **money at stake** — LD exposure plus lost energy — and show that ranking differs from severity ranking | `M5` | `P-7` | `CMP-8` | `T-26` |
| `FR-30` | Group related alarms into **incidents**, so repeated auto-resets on one asset are one item | `M9` | `P-7` | `CMP-7` | `T-27`, `T-63` |
| `FR-31` | Surface nuisance-alarm **suppression candidates with their evidence**. Suppression is always an explicit human act | `M9` | `P-7` | `CMP-7` | `T-28` |
| `FR-32` | **Suppression guards:** nothing may be suppressed on an asset with elevated risk, nor for a safety-critical alarm code. Every suppression is time-boxed, visible, reversible and audited | `M9` | `P-7` | `CMP-7` | `T-29`, `T-30`, `T-60` |
| `FR-33` | Produce **candidate maintenance windows** satisfying every constraint: wind and weather limits, crew certification and availability, parts on hand or lead time, crane need and mobilisation lead time | `M10` | `P-3` | `CMP-9` | `T-31` |
| `FR-34` | Draft a work order carrying scope, procedure reference, parts, assigned crew, window and the risk evidence that justified it | `M7` | `P-3` | `CMP-10` | `T-32` |
| `FR-35` | **No write occurs without explicit human approval.** The approver's identity, the timestamp and the inputs are recorded | `M7` | `P-3` | `CMP-10` | `T-33` |
| `FR-36` | Writes are **idempotent**: re-submitting the same approved action does not create a second work order | `M7` | `P-3` | `CMP-10` | `T-34` |
| `FR-37` | Every write appends to an **append-only audit trail**. If the audit append fails, the write fails | `M7` | `P-6` | `CMP-10` | `T-35` |
| `FR-38` | Request a parts reservation against the work order, showing stock location and lead time | `M10` | `P-9` | `CMP-9` | `T-36` |

### 2.6 Documents and natural language

| ID | Requirement | Pri | Persona | Component | Test |
| --- | --- | --- | --- | --- | --- |
| `FR-39` | Parse **real synthetic document files** (OEM procedures, service bulletins, CMS condition reports) into text with retained structure | `M6` | `P-8` | `CMP-11` | `T-37` |
| `FR-40` | Index parsed documents in a **search service** refreshed on a declared lag | `M6` | `P-8` | `CMP-11` | `T-38` |
| `FR-41` | Answer natural-language questions spanning structured data and documents, with **a citation for every factual claim** — table and row, or document and section | `M6` | `P-8` | `CMP-13` | `T-39`, `T-40` |
| `FR-42` | Find **similar past failures** across the fleet, by component position and by serial | `S4` | `P-8` | `CMP-13` | `T-4` |
| `FR-43` | A governed **semantic view** exposes the metric layer and asset model for natural-language querying, with verified queries for the golden scenarios | `M4` | `P-1` | `CMP-12` | `T-41` |
| `FR-44` | Every semantic-view description is **correct for this domain**; no placeholder or borrowed text | `M4` | `JP` | `CMP-12` | `T-42` |

### 2.7 Command center

| ID | Requirement | Pri | Persona | Component | Test |
| --- | --- | --- | --- | --- | --- |
| `FR-45` | Navigate fleet → region → site → turbine → component | `M8` | `P-1`, `P-3` | `CMP-14` | `T-43` |
| `FR-46` | Show the ranked alert list with, per item, the risk, the horizon, the drivers and the money at stake | `M8` | `P-7` | `CMP-14` | `T-26` |
| `FR-87` | Show, above the alert list, the **noise header**: alarms in, incidents out, actionable, undetermined, compression ratio and real failures suppressed | `M9` | `P-7` | `CMP-14`, `CMP-17` | `T-70` |
| `FR-88` | A single **reusable evidence panel** serves prediction drivers, alarm classification evidence and schedule suggestion reasoning. Built once, used in all three places | `M8` | `P-7`, `P-2`, `P-3` | `CMP-14` | `T-85` |
| `FR-47` | Show availability against guarantee, lost energy, LD exposure and Turbine OEE at the selected scope | `M8` | `P-1`, `P-5` | `CMP-14` | `T-23` |
| `FR-48` | Provide an **ask box** in context, whose answers carry drivers or citations | `M8` | `P-2`, `P-8` | `CMP-14`, `CMP-13` | `T-39` |
| `FR-49` | Provide the **approval action** on a drafted work order, and show the resulting audit entry | `M8` | `P-3` | `CMP-14`, `CMP-10` | `T-33` |
| `FR-50` | Provide a technician **job pack** view: scope, procedure, parts, history, safety notes | `C2` | `P-4` | `CMP-14` | `T-44` |
| `FR-51` | Every view has a defined **empty state and error state**. No stack trace, no debug output, ever reaches a user | `M8` | all | `CMP-14` | `T-45` |

### 2.8 Agent behaviour

| ID | Requirement | Pri | Persona | Component | Test |
| --- | --- | --- | --- | --- | --- |
| `FR-52` | The agent may **only** choose among candidates the engines produced. It never invents a window, a crew, a part, an incident or a number | `M5` | `P-2` | `CMP-13` | `T-46`, `T-71` |
| `FR-53` | The agent has **no destructive tools**. No DDL, no DELETE, no UPDATE outside the approval-gated action tool | `M7` | `P-6` | `CMP-13` | `T-47` |
| `FR-54` | Generated SQL is **validated before execution** against an allowlist of read-only operations and permitted objects | `M6` | `P-6` | `CMP-13` | `T-48` |
| `FR-55` | When the agent cannot ground an answer, it **says so** rather than producing an unsupported one | `M6` | `P-8` | `CMP-13` | `T-49` |
| `FR-56` | Agent answers about a metric match the metric layer's value exactly | `M4` | `P-10` | `CMP-13`, `CMP-5` | `T-24` |

### 2.9 Alarm intelligence — `M9`

| ID | Requirement | Pri | Persona | Component | Test |
| --- | --- | --- | --- | --- | --- |
| `FR-57` | Normalise **four alarm sources** into one stream with a conformed schema — source, turbine, component, code, severity, start, end, auto-reset flag. Sources: SCADA status and alarm codes, CMS threshold alarms, grid and balance-of-plant events, data-quality check failures. The schema must accept further sources without change | `M9` | `P-7` | `CMP-7` | `T-62` |
| `FR-58` | Correlate alarms into **incidents** by turbine and component within a window, so repeated occurrences are one item | `M9` | `P-7` | `CMP-7` | `T-63` |
| `FR-59` | Correlate by **known causal pattern**: a site-wide grid dip becomes one incident rather than one per turbine, and a sensor fault producing a code cascade becomes one incident | `M9` | `P-7` | `CMP-7` | `T-64` |
| `FR-60` | Label **chattering** — repeated trip and auto-reset on one signature within a window | `M9` | `P-7` | `CMP-7` | `T-65` |
| `FR-61` | Label **standing / stale** — open beyond a threshold with no acknowledgement | `M9` | `P-7` | `CMP-7` | `T-66` |
| `FR-62` | Label **flood periods** — alarm rate above a threshold, scoped per site | `M9` | `P-7` | `CMP-7` | `T-67` |
| `FR-63` | Classify every incident **actionable, nuisance or `UNDETERMINED`**, storing the evidence weighed: whether another channel agrees at matched operating conditions, whether load or RPM already explains the reading, whether it auto-reset and never recurred, and the component's current risk score | `M9` | `P-7`, `P-2` | `CMP-7` | `T-68` |
| `FR-64` | **`UNDETERMINED` policy.** An undetermined incident stays in the operator's queue, ranked below actionable, **never hidden and never auto-suppressible**. The undetermined **rate** is published as a headline figure | `M9` | `P-7` | `CMP-7` | `T-61` |
| `FR-65` | Capture **confirm**, **dismiss-with-reason** and **reinstate** on an incident, through the approval-gated action service. Reasons are stored | `M9` | `P-7` | `CMP-17`, `CMP-10` | `T-74` |
| `FR-66` | Track **classification precision per source** against seeded ground truth | `M9` | `P-7` | `CMP-17` | `T-69` |
| `FR-67` | Report the noise numbers: alarms in, incidents out, actionable count, **compression ratio**, alarms per operator-hour, standing count, chattering count | `M9` | `P-7`, `P-1` | `CMP-17` | `T-70` |
| `FR-68` | **Anti-gaming rule.** The compression ratio is never displayed or exported without, beside it, the count of real failures suppressed or dismissed. Compression alone is trivially achieved by suppressing everything | `M9` | `P-1` | `CMP-17` | `T-70` |

### 2.10 Planned work — `M10`

| ID | Requirement | Pri | Persona | Component | Test |
| --- | --- | --- | --- | --- | --- |
| `FR-69` | A **schedule view** showing completed and planned work per site and region, with the wind season shaded and access constraints marked, over a rolling 12-week horizon | `M10` | `P-3` | `CMP-18` | `T-80` |
| `FR-70` | Compute suggestions over a **rolling 12-week window by default** | `M10` | `P-3` | `CMP-18` | `T-81` |
| `FR-71` | A **"plan the season" mode** extending to 12 months for crane-dependent and long-lead work, returning a **ranked list of campaign proposals** rather than a full-year grid. Absorbs pre-season bundling | `M10` | `P-3` | `CMP-18` | `T-82` |
| `FR-72` | **One control** — "Suggest schedule" — scoped by site or region | `M10` | `P-3` | `CMP-18` | `T-81` |
| `FR-73` | An optional **free-text constraint** (e.g. "no crane before November") is **parsed into a filter over engine-produced windows**, the parsed interpretation is echoed back for confirmation, and an unparseable constraint is **refused**. The model translates; it never reasons about feasibility | `M10` | `P-3` | `CMP-18` | `T-73` |
| `FR-74` | Each suggestion is a **typed proposed change**: add, move, bundle or cancel | `M10` | `P-3` | `CMP-18` | `T-83` |
| `FR-75` | Each suggestion carries its **reasoning and evidence**: risk and lead time, last maintenance and interval due, parts stock and lead time, crew and crane availability, the weather window, and the seasonal value of the energy at stake | `M10` | `P-3` | `CMP-18` | `T-83` |
| `FR-76` | Each suggestion carries its **expected impact** in avoided LD and avoided lost energy | `M10` | `P-5` | `CMP-18`, `CMP-5` | `T-75` |
| `FR-77` | Suggestions are drawn **only** from windows the constraint engine already produced. No suggestion may reference an invented window, crew or part | `M10` | `P-3` | `CMP-18`, `CMP-9` | `T-71` |
| `FR-78` | When nothing is feasible, report the **binding constraint** — "no certified crew until week 44" is a valid and useful answer | `M10` | `P-3` | `CMP-9`, `CMP-18` | `T-72` |
| `FR-79` | **Accept, edit or reject-with-reason** on a suggestion. Acceptance goes through the existing approval-gated action service; rejection reasons are stored | `M10` | `P-3` | `CMP-18`, `CMP-10` | `T-74` |
| `FR-80` | Show the plan's effect **before committing**: risk left uncovered, and expected lost energy before versus after | `M10` | `P-3`, `P-5` | `CMP-18`, `CMP-5` | `T-75` |

### 2.11 Committed ingenuity — `M11`

| ID | Requirement | Pri | Persona | Component | Test |
| --- | --- | --- | --- | --- | --- |
| `FR-81` | **One daily scheduled run** refreshing risk scores, schedule suggestions and the digest together | `M11` | `P-6` | `CMP-20` | `T-76` |
| `FR-82` | The digest reports **what changed since the previous run** — new elevated-risk components, new actionable incidents, suggestions that moved, and anything that became stale | `M11` | `P-7`, `P-3` | `CMP-20` | `T-77` |
| `FR-83` | The digest is delivered **server-side via a notification integration**, because a scheduled run cannot reach a locally configured MCP server | `M11` | `P-7` | `CMP-19` | `T-77` |
| `FR-84` | An **approval notification over MCP**, sent interactively from the app session when a work order or schedule change is approved. Optional: its absence must never block an approval | `M11` | `P-4` | `CMP-19` | `T-79` |
| `FR-85` | **Automated runs refresh only, never apply.** No scheduled path may write state or approve anything | `M11` | `P-6` | `CMP-20` | `T-76` |
| `FR-86` | The solution is demonstrated across **four surfaces**, each with a named evidence artefact: Cortex Code Desktop, Cortex Code CLI, Snowflake Intelligence, and the Streamlit app | `M11` | `P-6` | `CMP-15` | `T-84` |

### 2.12 Freshness, visual proof and submission artefacts — `M12`, `M13`

| ID | Requirement | Pri | Persona | Component | Test |
| --- | --- | --- | --- | --- | --- |
| `FR-89` | **One incremental path** — alarms or CMS features — implemented as a dynamic table with an explicit `TARGET_LAG`. Landing new data must appear in the serving layer within that lag without a manual rebuild | `M12` | `P-6` | `CMP-3` | `T-88` |
| `FR-90` | **The alarm funnel.** The triage view renders the collapse — alarms in → incidents → actionable / nuisance / undetermined — as a single visual, reconciling exactly to `MET_NOISE`, with the real-failures-suppressed count shown | `M8`, `M9` | `P-7`, `P-1` | `CMP-14`, `CMP-17` | `T-86` |
| `FR-91` | **The model's held-out metric is displayed in the UI**, beside the risk score it produced, with the model version. Not only recorded in `OPS` | `M8`, `M3` | `P-2`, `P-7` | `CMP-14`, `CMP-6` | `T-87` |
| `FR-92` | **At least one point in the UI where a human overrides the system**, and the override is recorded with its reason and visible afterwards — a dismissed incident or a rejected suggestion | `M8` | `P-7`, `P-3` | `CMP-14`, `CMP-17` | `T-91` |
| `FR-93` | A **judge-facing root `README`** that states the problem, shows the key screens, gives runnable setup steps, and says the data is synthetic — readable in 60 seconds | `M13` | NK | `CMP-15` | `T-89` |
| `FR-94` | A **2-minute recorded walkthrough** of the golden scenarios, included in the prototype submission. Not a substitute for the live Finals demo | `M13` | NK | — | `T-90` |
| `FR-95` | A **generated results summary** — model metrics, compression with failures-suppressed, gating tests passing, credits consumed — produced **from `OPS`**, not hand-written | `M13` | NK | `CMP-16` | `T-92` |
| `FR-96` | Every evaluation criterion `E1`–`E9` maps to a named artefact and a demo moment, with no placeholders | `M13` | NK | — | `T-93` |
| `FR-97` | **The baseline comparison is displayed**, not merely tested: for the same window, how many components a trivial single-signal threshold rule flags versus how many the model flags, and how many of each actually failed. Reconciles to the recorded evaluation run | `M3`, `M13` | `P-2`, `P-7` | `CMP-6`, `CMP-14` | **`T-94`** |
| `FR-98` | **A generated aggregate outcome statement**: failures flagged out of failures seeded, median lead time, and LD exposure identified before it crystallised — one sentence, computed from `OPS` and `MET_LD_EXPOSURE`, never hand-written | `M13` | `P-1`, `P-5` | `CMP-16`, `CMP-5` | `T-95` |
| `FR-99` | **The suppression guards are demonstrable, not only asserted.** Attempting to suppress an alarm on an elevated-risk asset, or a safety-critical code, produces a **visible refusal with its reason** in the UI | `M9` | `P-7` | `CMP-7`, `CMP-14` | `T-96` |

## 3. Non-functional requirements

| ID | Requirement | Pri | Persona | Component | Test |
| --- | --- | --- | --- | --- | --- |
| `NFR-1` | **Determinism boundary.** State, feasibility, constraints, grouping and arithmetic are computed in SQL or Snowpark that is unit-testable. The model ranks and explains only | `M3` | `P-6` | `CMP-5`…`CMP-9` | `T-46` |
| `NFR-2` | **No destructive capability** is exposed to any agent or LLM-driven path | `M7` | `P-6` | `CMP-13`, `CMP-15` | `T-47` |
| `NFR-3` | **Least privilege.** No `ACCOUNTADMIN` in application code. Each component runs as a role with only the grants it needs | `S5` | `P-6` | `CMP-15` | `T-50` |
| `NFR-4` | **Auditability.** Every state change is attributable to a person or a scheduled job, append-only, and queryable | `M7` | `P-6` | `CMP-10` | `T-35` |
| `NFR-5` | **Idempotency.** Every pipeline step and every write can be re-run without duplicating data or actions | `M7` | `P-6` | `CMP-3`, `CMP-10` | `T-34`, `T-51` |
| `NFR-6` | **Reproducible from a clean account.** Database name parameterised; setup idempotent; teardown scripted; no hardcoded account, region or role | `M1` | `P-6` | `CMP-15` | `T-52` |
| `NFR-7` | **Every core-demo dependency has a written degraded mode**, and the degraded mode is itself tested | `M8` | NK | all | `T-53` |
| `NFR-8` | **Cost ceiling.** Total consumption stays within the $400 trial credit, with consumption reported at each $100 band. Consumption is the **sum** of `CORTEX_CODE_*_USAGE_HISTORY` token credits and `WAREHOUSE_METERING_HISTORY` credits — warehouse alone under-reports by ~10× | `M1` | NK | `CMP-16` | `T-54` |
| `NFR-9` | **Responsiveness.** Command-center views render within 5 s at p95 on the demo dataset; agent answers return within 30 s or stream | `M8` | `P-7` | `CMP-14` | `T-55` |
| `NFR-10` | **Data honesty.** Synthetic data is labelled as such in the schema, the UI and the pitch. Illustrative figures are marked | `M2` | all | `CMP-1`, `CMP-14` | `T-13` |
| `NFR-11` | **No secrets in git.** Credentials come from `~/.snowflake/connections.toml`, Snowflake secrets or the OS keychain | `M1` | `P-6` | `CMP-15` | `T-56` |
| `NFR-12` | **Crash-proof front end.** No unhandled exception reaches the user; every query failure degrades to a stated message | `M8` | all | `CMP-14` | `T-45` |
| `NFR-13` | **Accessibility floor.** Status is never conveyed by colour alone; every control has a text label | `M8` | all | `CMP-14` | `T-57` |
| `NFR-14` | **Observability.** Pipeline freshness and lag, row counts, data-quality results, model evaluation runs and credit consumption are queryable | `S6` | `P-6` | `CMP-16` | `T-58` |
| `NFR-15` | **No unexplained number.** Any figure shown to a user can be traced to its inputs — a driver set, a citation, or a metric definition | `M3` | all | `CMP-5`, `CMP-6` | `T-16` |
| `NFR-16` | **Preview-feature fallback.** Any feature not confirmed GA is marked, and has a working fallback path | `M1` | `P-6` | all | `T-53` |
| `NFR-17` | **Licence hygiene.** Every third-party dependency and dataset is recorded with its licence, per the Official Rules | `M1` | NK | `CMP-15` | `T-59` |
| `NFR-18` | **Freshness is visible.** Any surface showing derived output — scores, suggestions, the digest, noise metrics — displays when it was last refreshed. A silently stale suggestion is the same class of defect as a toast that lies | `M11` | `P-3` | `CMP-18`, `CMP-20` | `T-77` |
| `NFR-19` | **Automation runs least-privilege.** The scheduled run executes as `WOA_SCHEDULER`, never as `ACCOUNTADMIN` and never as a human's default role. Automations inherit their creator's default role, so the object must be created from a session whose default is `WOA_SCHEDULER` | `M11` | `P-6` | `CMP-20`, `CMP-15` | `T-78` |
| `NFR-20` | **The submission stands alone.** A stranger can clone the repo, follow the `README`, and reach a working system without asking us anything. No step depends on knowledge only we hold | `M13` | NK | `CMP-15` | `T-89`, `T-52` |

## 4. Requirement coverage

| Dimension | Check | Result |
| --- | --- | --- |
| Functional requirements | 99 | — |
| Non-functional requirements | 20 | — |
| Every FR/NFR has an ID, priority, persona, component and ≥1 test | 119 of 119 | **Pass** |
| Every persona `P-1`…`P-10` is named by ≥1 requirement | all 10 | **Pass** |
| Every component `CMP-1`…`CMP-20` is named by ≥1 requirement | all 20 | **Pass** |
| Every Must scope item has ≥1 requirement | `M1`…`M13` | **Pass** |

Requirements per Must: `M1` 8, `M2` 8, `M3` 10, `M4` 9, `M5` 3, `M6` 6, `M7` 7, `M8` 13, `M9` 18,
`M10` 14, `M11` 8, `M12` 1, `M13` 7.

**`FR-93`…`FR-99` are unusual requirements** — several are about *presenting* work rather than doing it.
They are here rather than in a delivery checklist because the prototype submission *is* a deck plus a
repo, a judge gives an entry 5–15 minutes, and an internal test nobody sees scores the same as a test
that was never written. `FR-97` and `FR-99` in particular add **no new build surface** — they surface
work the plan already does (`T-10`'s baseline, `FR-32`'s guards) where a judge can see it.

## 5. The requirements that gate the milestone

These must be **automated**, not checked by eye. If any fails, the build is not demo-ready.

| Test | Gates | Why this one |
| --- | --- | --- |
| `T-10` | `FR-11` | The label is learnable. If this fails, nothing downstream means anything |
| `T-8` | `FR-9` | Degradation actually trends before failure |
| `T-23` | `FR-26` | Turbine OEE equals the product of its parts |
| `T-24` | `FR-27`, `FR-56` | App, semantic view and agent agree on every metric |
| `T-25` | `FR-28` | No metric component is a constant or random |
| `T-16` | `FR-18` | No risk score is displayed without drivers |
| `T-33` | `FR-35` | No write without approval |
| `T-34` | `FR-36` | Writes are idempotent |
| `T-35` | `FR-37` | Audit append precedes the write, and failure blocks it |
| `T-29` | `FR-32` | Nothing suppressed on elevated risk or a safety-critical code |
| `T-47` | `FR-53` | No destructive tool reachable from any agent path |
| `T-11` | `FR-12` | Data reaches the current date |
| **`T-60`** | **`FR-32`, `FR-63`** | **No seeded real failure is ever suppressed or dismissed by the classifier.** Zero tolerance — one hit fails the build. This test is the licence to make any noise-reduction claim at all |
| **`T-71`** | **`FR-77`** | **No suggestion references a window, crew or part the engine did not produce.** `ADR-0004` enforced at the scheduling surface |
| **`T-76`** | **`FR-81`, `FR-85`** | **The scheduled run refreshes only and never applies.** An automation that can write state is a different and much more dangerous system |

| **`T-86`** | **`FR-90`** | **The alarm funnel reconciles exactly to `MET_NOISE`**, and cannot render without the real-failures-suppressed count. Our single most visible number must be provably correct |
| **`T-87`** | **`FR-91`** | **The held-out metric shown in the UI matches the recorded evaluation run.** Our highest-credibility claim must not drift from its source |

| **`T-94`** | **`FR-97`** | **The displayed baseline comparison reconciles to the recorded evaluation run.** This is the most persuasive number we own — "a rule flags 47, the model flags 6, five of them failed" — and a number that persuades must be provably correct |

Eighteen gating tests. Twelve encode a specific defect found in the reference solution; three encode
the ways `M9`, `M10` and `M11` could become dishonest — hiding a real failure, inventing a plan, or
acting without a human; and three protect the numbers a judge will actually look at.

## 6. Open questions

| ID | Question | Owner |
| --- | --- | --- |
| `Q-29` | `FR-11`: what margin over baseline counts as "learnable"? Recommendation: state a precision/recall target once the generator exists, rather than guessing now | SA |
| `Q-30` | `FR-16`: which component classes get a model? Recommendation: `GBX`, `MSB`, `GEN`, `PIT` — the four with real CMS coverage. Ties to `Q-15` | SA |
| `Q-31` | `FR-33`: is weather a forecast or a synthetic constraint? Ties to `C9`/`Q-25` | JP |
| `Q-32` | `FR-54`: allowlist by object, by operation, or both? Recommendation: both, plus a hard read-only role for the query path | NK |
| `Q-33` | `NFR-9`: is 5 s p95 achievable on `XSMALL`? Needs measurement, not assumption | JP |
| `Q-34` | `FR-50` is priority `C2` but `P-4` has no other requirement. Accept that `P-4` may go unserved, or promote `FR-50`? | JP |
