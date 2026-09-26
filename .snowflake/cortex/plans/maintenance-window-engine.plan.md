# Plan: Maintenance-window engine (CMP-9 + suggestions, ADR-0018)

## Scope (NK, 2026-09-26)
Engine + suggestions + accept/reject + app. Inputs come from a new generator step. **Out of scope:** `T-73` free-text constraints ("no crane before November"). It is recorded as not built, not faked.

## Facts it is designed around
- 6 elevated components, all HIGH. Their costliest part needs a crane (GEN stator, MSB bearing, PIT bearing).
- Two sites have two crane jobs each: **MH-STR** (GEN + MSB) and **TN-TVL** (2× MSB). These are the `GS-3`/`VQ-8` bundle cases.
- Parts: lead times of 60–180 days; stock is 1–3 units for crane parts. MSB has **1 unit** on hand, so two TN-TVL jobs compete for it. That is a real binding constraint (`T-72`).
- 8 crews (6 site crews, 2 crane teams South/West). Certifications are empty. There is no forecast and no crane calendar.

## 1. Planning inputs — `sql/10_generate/14_planning_context.sql`
`GEN.SP_GENERATE_PLANNING_CONTEXT(as_of, seed)`: deterministic, idempotent, added to `SP_GENERATE_ALL` and `deploy-data`. It can also be applied to the current data without a regenerate.
- `RAW.DIM_CREW.certifications`: site crews get `UPTOWER,ELECTRICAL`, plus `DRIVETRAIN` for some. Crane teams get `CRANE,DRIVETRAIN`. At least one site lacks a drivetrain-certified crew, so crew is sometimes the binding constraint.
- `RAW.FCT_WIND_FORECAST(site_code, day, forecast_mean_wind_ms, forecast_max_gust_ms)`: 12 weeks ahead. Seasonal: the SW monsoon (Jun–Sep) is high wind, and Oct onward calms. Crane lifts are limited to gusts ≤ 10 m/s, up-tower work to ≤ 15 m/s.
- `RAW.FCT_CRANE_BOOKING(crew_id, start_day, end_day, note)`: existing commitments for the two crane teams, so some weeks are unavailable.
- `RAW.DIM_COMPONENT_CLASS`: add `crane_mobilisation_days` and `job_days` (e.g. MSB 4 days, GEN stator 3, PIT bearing 2).

## 2. Candidate windows — `sql/40_engine/03_window_candidates.sql`
`ENGINE.SP_BUILD_WINDOW_CANDIDATES()` → table `ENGINE.ENG_WINDOW_CANDIDATE`.
- One row per (elevated component × start week in a rolling 12-week horizon × crew able to do the job).
- It stores **each constraint's result** as its own column, plus the detail behind it: `weather_ok`, `crew_certified`, `crew_available`, `part_available`, `crane_available`, `mobilisation_ok`, `before_risk_horizon`.
- It also stores `is_feasible` (the AND of all of them) and `window_id` (a deterministic hash).
- Hard filters, never weights: infeasible rows are **kept with their failing constraint**, so the binding constraint can be reported. Suggestions select only `is_feasible` rows.
- The part is feasible if on-hand stock covers it at the window start; otherwise only if the lead time ends before the window starts. Stock is reserved in risk order, so the second MSB job at TN-TVL waits for lead time.

## 3. Suggestions — `sql/40_engine/04_suggestions.sql`
`ENGINE.ENG_SUGGESTION`, built by `SP_BUILD_SUGGESTIONS()`. It selects, groups, ranks and explains, and **never constructs** a window.
- `SCHEDULE`: the earliest feasible window per component, preferring a site crew over a crane mobilisation where the repair allows.
- `BUNDLE`: crane jobs at the same site whose feasible windows share a crane team and week. **One mobilisation** covers them all, with the saving stated (`VQ-8`).
- `INFEASIBLE`: a component with no feasible window gets a **binding constraint** message, e.g. "no drivetrain-certified crew at X until week N" (`T-72`).
- Impact per suggestion, read from the metric layer, not recomputed: risk covered (expected loss from `ENG_ALERT_RANKED`) and lost energy avoided (from `MET_LOST_ENERGY`, the job downtime at forecast wind) (`T-75`).
- Columns: `suggestion_id`, `suggestion_type`, `window_id`(s), `crew_id`, `part_number`, `component_ids`, `reasoning`, `binding_constraint`, `impact_*`, `status`.

## 4. Accept / reject — `sql/50_action/02_action_procedures.sql` (+ grants)
- `SP_ACCEPT_SUGGESTION(suggestion_id, idempotency_key)` (WOA_PLANNER): re-validates that the window is still feasible in the engine, writes the audit row first, then creates or updates the draft with `window_status = 'SCHEDULED'`, `window_id`, `crew_id` and dates. The `NOT_SCHEDULED` text becomes "not scheduled: no suggestion accepted yet". One transaction, idempotent. This is the same pattern as the existing procedures.
- `SP_REJECT_SUGGESTION(suggestion_id, reason_code, note, key)`: writes to `ACT_DECISION` with its own reason vocabulary (ADR-0018), audited.
- Confirm/dismiss/reinstate on incidents (the other half of `T-74`) stays out of scope.

## 5. Assertions — `sql/15_quality/08_planning_assertions.sql` + `16_run_verify_planning.sql`
| Test | Assertion |
| --- | --- |
| **`T-71` gating** | Anti-join every suggestion's window, crew and part against `ENG_WINDOW_CANDIDATE` (feasible rows only) → 0 rows |
| **`T-31` gating** | Every feasible candidate passes every constraint, re-checked from source (forecast, bookings, stock, certifications) |
| `T-72` | Every elevated component has either a feasible suggestion or a non-null binding constraint; no empty answers |
| `T-75` | Suggestion impact figures equal the metric-layer values exactly |
| `GS-3` | A BUNDLE exists at MH-STR and/or TN-TVL with one mobilisation |
| `T-74` (half) | Self-test: accept → draft SCHEDULED + audit; accept again → DUPLICATE; reject → ACT_DECISION + audit; accept of an infeasible/stale window → REFUSED |

Wired into `deploy-engine` / `deploy-action` and a 7th suite in `verify`.

## 6. Semantic view + agent + app
- `SV_WIND_OPS`: add a `suggestion` table (type, site, crew, bundle size, binding constraint, impact metrics), so Analyst and the agent answer `VQ-8` from engine rows only. The agent instructions already forbid inventing slots.
- App: a **Planning** section in *Risk triage*.
  - Suggestions table, with bundles highlighted.
  - Binding constraints for infeasible items.
  - Per-constraint detail for a chosen component, i.e. why other weeks fail.
  - Accept / reject-with-reason buttons through the procedures.
  - Degrades to tables.

## 7. Docs and delivery
- Evidence `development/11-window-engine.md`
- `STATE.md` (§1 G4 row, §3, §5, §7 deviations: synthetic forecast/certifications/bookings; `T-73` not built)
- RAID update for `R-21`
- `deployment.md` rows
- `just results` regenerated
- PR

## Verification
- `just verify` on `WIND_OPS_AI_DEV_NK`: all suites green (58 + ~7 new).
- Cortex Analyst: `VQ-8` returns the engine's bundle(s) only.
- App renders headless with 0 exceptions; the accept path is shown end to end in the audit.
- **No second `T-52` rebuild.** It costs ~3 credits; a single `just deploy-data`/`deploy-engine` re-run proves the new steps are idempotent.

## Budget
Estimate ~15–20 credits (~$40–55) of the ~$110 left. I'll report spend at the end.
