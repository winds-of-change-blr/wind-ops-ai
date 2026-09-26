# Development 11 — the maintenance-window engine

> **Gates:** `G4` — action is safe ("no plan is invented") · **Date:** 2026-09-26 · **By:** NK with CoCo
> **Account:** `BGTCHIX-UZ86048` · **Database:** `WIND_OPS_AI_DEV_NK` · **Branch:** `feat/nk/window-engine`

## 1. Verifiable identifiers

| What | Identifier |
| --- | --- |
| CoCo session | `04d1ee7a-0e99-44de-afb6-40f838e591e6` |
| Planning context | `GEN.SP_GENERATE_PLANNING_CONTEXT`: 504 forecast site-days from 2026-09-26, 8 crews certified, 2 crane bookings, 1 open order |
| Engine run (via `just deploy-engine`) | `1008 candidate windows from 2026-09-26, 174 feasible` · `1 bundle(s), 3 single job(s), 1 infeasible` — identical on a second build |
| Cortex Analyst, `VQ-8` | request `a1c1ac1e-2796-4e4f-9347-d8c7541d5b13` — filters engine rows to `suggestion_type = 'BUNDLE'` |
| Planning assertions | 7/7, two consecutive runs (the self-test is repeatable); run IDs in `OPS.DQ_RESULT` under `DQ-T71-FROM-ENGINE` |
| Full `just verify` | exit 0 at 06:52 UTC: **65/65** assertions in seven suites + 8/8 behavioural role checks; `deploy-engine` and `deploy-action` re-ran cleanly before it |

### SQL to reproduce

```sql
call WIND_OPS_AI_DEV_NK.OPS.SP_RUN_PLANNING_QUALITY();

-- the plan, and why each date is what it is
select s.suggestion_type, i.component_id, i.crew_id, i.start_day, i.end_day,
       i.earliest_limited_by, s.binding_constraint
from WIND_OPS_AI_DEV_NK.ENGINE.ENG_SUGGESTION s
join WIND_OPS_AI_DEV_NK.ENGINE.ENG_SUGGESTION_ITEM i using (suggestion_id)
order by s.suggestion_type, i.start_day;
```

## 2. Prompt

> "lets build Maintenance-window engine next"

CoCo proposed it as the largest remaining item and recommended skipping it on budget. NK chose to build it.
Before planning, CoCo put two questions to NK (§4). The approved plan is in
`.snowflake/cortex/plans/maintenance-window-engine.plan.md`.

## 3. What CoCo produced

| Piece | File | What it does |
| --- | --- | --- |
| Planning inputs | `sql/10_generate/14_planning_context.sql` | 12-week seasonal wind forecast per site; crew certifications (a `VARIANT` array) and site coverage; two crane-team commitments; one open bearing order; a repair plan per component class (the same part `SP_DRAFT_WORK_ORDER` picks, job days, mobilisation, gust limit). Runs in `SP_GENERATE_ALL` |
| Constraint engine (`CMP-9`) | `sql/40_engine/03_window_candidates.sql` | `ENG_WINDOW_CANDIDATE`: one row per (elevated component × covering crew × start day). **Six constraint columns** plus their detail; `is_feasible` is their AND. Infeasible rows are kept for the binding constraint. Parts are allocated in expected-loss order: stock, then open orders, then a fresh order's lead time |
| Suggestions (`CMP-18`) | `sql/40_engine/04_suggestions.sql` | `ENG_SUGGESTION` + `_ITEM`: BUNDLE (a crane campaign back to back), SCHEDULE (earliest feasible, no crew double-booked), INFEASIBLE (binding constraint). Each item records **what set its date**. `ENG_PLAN_IMPACT`: covered vs uncovered expected loss, energy the work costs |
| Accept / reject (`FR-79`) | `sql/50_action/04_planning_procedures.sql` | `SP_ACCEPT_SUGGESTION` re-validates every window against the engine, requires existing drafts, audits first, then schedules the drafts. `SP_REJECT_SUGGESTION` has its own reason vocabulary (ADR-0018). Idempotent |
| Assertions | `sql/15_quality/08_planning_assertions.sql`, `16_run_verify_planning.sql` | 7 assertions, 3 gating (§ below) |
| Semantic view | `sql/30_serve/02_semantic_view.sql` | + `suggestion` and `plan` tables, so Analyst answers `VQ-8` from engine rows |
| App | `app/streamlit_app.py` | *Risk triage* → **Planning**: impact tiles, the plan table, accept / reject-with-reason, and a "why not sooner?" per-constraint view |

### The plan the engine produced

| Suggestion | Components | Crew | Window | What set the date |
| --- | --- | --- | --- | --- |
| **BUNDLE** — TN-TVL crane campaign | `TN-TVL-T03-MSB`, `TN-TVL-T06-MSB` | `CRW-CR01` (South crane) | 9–16 Nov | forecast gust 10.5 m/s above the 10 m/s limit the day before; the second job follows the first |
| SCHEDULE | `KA-CTD-T18-PIT` | `CRW-CR01` | 8–9 Oct | forecast gust |
| SCHEDULE | `MH-STR-T08-GEN` | `CRW-CR02` (West crane) | 10–12 Oct | crane mobilisation lead time |
| SCHEDULE | `GJ-KCH-T04-GEN` | `CRW-CR02` | 8–10 Nov | forecast gust (Kutch: 6 crane-workable days in October) |
| **INFEASIBLE** | `MH-STR-T09-MSB` | — | — | **Binding:** part `PT-MSB-BEAR` not available until 25 Dec (1 in stock and 1 on order both allocated to the higher-loss TN-TVL jobs; a new order has a 90-day lead time), after the horizon ends 18 Dec |

Plan impact: ₹177.2 L of ₹209.2 L elevated expected loss covered, **₹32.0 L uncovered** (the infeasible bearing),
31.8 MWh of forecast energy spent on the work, **one crane mobilisation saved**.

### What the planning gate checks

| Test | Result |
| --- | --- |
| **`T-71`** (gating) | 6 suggestion items; 0 not matching a feasible engine row on window, crew, part, component and dates |
| **`T-31`** (gating) | 1,008 candidates, 174 feasible; 0 violate a constraint **re-derived from source** (forecast, bookings, certifications, coverage, mobilisation, horizon, part date and source), and `is_feasible` equals the AND of its columns on every row |
| No double-booking (gating) | 0 overlapping crew assignments |
| `T-72` | every elevated component is in exactly one suggestion; the infeasible one carries its binding constraint; every scheduled date says what set it |
| `T-75` | item losses = `ENG_ALERT_RANKED`; suggestion totals = sum of items; covered + uncovered = elevated total; planned downtime recomputed from forecast and power curve |
| `GS-3` | 1 valid campaign: TN-TVL, 2 jobs, one crew, back to back, no overlap |
| `T-74` (accept/reject half) | no draft → REFUSED; accept → APPLIED, both drafts SCHEDULED with engine window ids; same key → DUPLICATE; invented suggestion id → REFUSED; infeasible suggestion → REFUSED; bad reject reason → REFUSED; 6 audit rows |

## 4. What a human changed

NK made three decisions:

1. **Build the engine anyway,** against CoCo's recommendation to skip it on budget.
2. **Generate the missing inputs** in a generator step rather than as static reference rows.
3. **Scope:** engine, suggestions, accept/reject and app. `T-73` free-text constraints are not built.

The plan's credibility to a planner (`R-21`) still needs NK's review. The tests prove the plan is feasible, not
that it persuades.

## 5. What CoCo got wrong

1. **Assumed `DIM_CREW.certifications` was text.** It is a `VARIANT`; the first run failed on type and the
   generator now writes arrays.
2. **Inverted `name AS column` for four semantic-view dimensions.** It was the same mistake as evidence 08; the
   compiler caught it.
3. **Three Snowflake Scripting errors in the assertions:**
   - a scalar subquery in an `INTO` list, again;
   - `FOR … IN (query)`, which is not valid (now a `RESULTSET` with a cursor);
   - an `AND`/`OR` precedence bug in an audit count, caught on review before it could pass for the wrong reason.
4. **A self-test that would have blocked itself:** suggestion ids are deterministic, so the "already decided"
   guard would have refused the next `verify`'s acceptance. That guard is now scoped to one test run for
   `SELFTEST-` keys only; real decisions are unaffected.
5. **The first "why not sooner?" note read "the start of the horizon"** where the real reason was a crew
   commitment inside the bundle. The logic now distinguishes the cases.

## 6. Cost

| Item | Credits |
| --- | --- |
| Whole round (reasoning + warehouse), from `ACCOUNT_USAGE` | ≈ 8.7 (≈ $24); warehouse share ≈ 1.1 |
| CoCo reasoning | see `STATE.md` §6 |

## 7. Traceability

| Plan item | Where it is now |
| --- | --- |
| `FR-33` candidate windows | `ENG_WINDOW_CANDIDATE`; `DQ-T31-FEASIBLE` (gating) |
| `FR-38` part stock and lead time shown | `part_source`, `part_available_date` on every candidate |
| `FR-77` suggestions only from engine windows | `DQ-T71-FROM-ENGINE` (gating); the agent's adversarial half is for `testing/01` |
| `FR-78` binding constraint | `ENG_SUGGESTION.binding_constraint`, `ENG_SUGGESTION_ITEM.earliest_limited_by`; `DQ-T72-BINDING` |
| `FR-79` accept / reject | `SP_ACCEPT_SUGGESTION`, `SP_REJECT_SUGGESTION`; `DQ-T74-ACCEPT-REJECT` |
| `FR-76`, `FR-80` impact | `ENG_PLAN_IMPACT`; `DQ-T75-IMPACT` |
| `GS-3`, `VQ-8` | `DQ-GS3-BUNDLE`; Analyst request above |
| Not built | `T-73` free-text constraints; `T-74` incident half; `FR-70`/`FR-71` season mode as a separate view; event-driven re-planning (ruled out by ADR-0018) |
