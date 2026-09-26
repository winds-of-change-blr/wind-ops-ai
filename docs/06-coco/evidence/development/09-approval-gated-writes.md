# Development 09 — approval-gated writes, and the test that passed the wrong way

> **Gate:** `G4` — actions are safe · **Milestone:** `M10` · **Date:** 2026-09-26 · **By:** NK with CoCo
> **Account:** `BGTCHIX-UZ86048` · **Database:** `WIND_OPS_AI_DEV_NK` · **Branch:** `feat/nk/approval-gated-writes`

## 1. Verifiable identifiers

| What | Identifier |
| --- | --- |
| CoCo session | `04d1ee7a-0e99-44de-afb6-40f838e591e6` |
| Procedures | `ACTION.SP_APPROVE_SUPPRESSION`, `SP_REVOKE_SUPPRESSION` (→ `WOA_RMC`) · `SP_DRAFT_WORK_ORDER`, `SP_APPROVE_WORK_ORDER`, `SP_REJECT_WORK_ORDER_DRAFT` (→ `WOA_PLANNER`) |
| Audit | `ACTION.AUD_ACTION` — one row per request, refusals included |
| First action-gate run | `OPS.DQ_RESULT` run `DQ-20260925200927`: 10 of 12 pass (two assertions were wrong, §5) |
| Clean `just verify` | runs `DQ-20260925202839` (16/16), `…202903` (10/10), `…202924` (5/5), `…202933` (5/5), `…202941` (12/12) — **48 of 48**, plus `T-33` behavioural: `WOA_APP` and `WOA_AGENT` both refused (`002003`) |
| `T-34` in that run | draft for `GJ-KCH-T04-GEN`: approvals `APPLIED` / `DUPLICATE` (same key) / `DUPLICATE` (new key); **1** work order |
| `T-35` in that run | approval with the audit forced to fail: raised, **0** work orders, **0** audit rows left behind |
| The invalid first `T-33` | two `ACT_WORK_ORDER` rows with `approved_role` `WOA_APP` / `WOA_AGENT` at 2026-09-25 20:16:03 / 20:16:10 (since removed, §5) |

### SQL to reproduce

```sql
call WIND_OPS_AI_DEV_NK.OPS.SP_RUN_ACTION_QUALITY();

-- The audit, as the app's Audit tab shows it
select event_at, action_type, outcome, object_id, reason, actor_user, on_behalf_of
from WIND_OPS_AI_DEV_NK.ACTION.AUD_ACTION order by event_at desc;
```

## 2. Prompt

> "nice .. i have merged the PR and pulled it main branch. lets go ahead for next step"

`STATE.md` §3 named `M10` as the critical path: `G4` was the one gate with its core unbuilt. The design was
fully specified by `ADR-0005`, the `04-code.md` role table and `data-model.md` §6, so CoCo built it
without a planning round.

## 3. What CoCo produced

| Layer | File | What it does |
| --- | --- | --- |
| Tables | `sql/50_action/01_action_tables.sql` | `AUD_ACTION`, `ACT_SUPPRESSION`, `ACT_WORK_ORDER_DRAFT`, `ACT_WORK_ORDER`, `ACT_DECISION`, the active-suppression view, and the `T-35` fault hook |
| Procedures | `sql/50_action/02_action_procedures.sql` | `ADR-0005`'s flowchart in order: **idempotency → re-validate against the engine → audit first → write**, audit and write in one transaction. Owner's rights, so callers need no table privilege |
| Grants | `sql/50_action/03_action_grants.sql` | Suppression to `WOA_RMC`, work orders to `WOA_PLANNER`, nothing to `WOA_APP`, `WOA_AGENT` or `WOA_SCHEDULER` |
| Procedure map | `sql/60_docs/03_part_procedure.sql` + two new PDFs | Every part the risk ranking costs maps to a parsed procedure a draft can cite |
| Gate | `sql/15_quality/06_action_assertions.sql`, `14_run_verify_action.sql`, `justfile` `_t33-direct-writes-refused` | 12 assertions that **call the real procedures** and read what happened, plus a real `INSERT` as each role |
| App | `app/streamlit_app.py` | Suppress / revoke, draft / approve / reject, and an *Audit* tab — all through the procedures, with one idempotency key per action per session, so a double-click is `DUPLICATE` |
| Recipe | `justfile` `deploy-action`, `verify` | `verify` now runs five suites |

### Properties, and how each was shown

| Property | Shown by | Result |
| --- | --- | --- |
| A protection trip cannot be suppressed (`T-29`) | `DQ-T29-SAFETY` | `SA-EM-001` → REFUSED |
| Nor on an asset with elevated evidence (`T-29`) | `DQ-T29-ELEVATED` | REFUSED |
| Nor on a MEDIUM/HIGH-risk turbine (`T-29`, `FR-32`) | `DQ-T29-RISK` | `MH-STR-T08` → REFUSED, **the case the engine missed (`I-19`)** |
| Nor an `UNDETERMINED` incident | `DQ-T29-UNDETERMINED` | REFUSED |
| Reversible, time-boxed, never deleted (`T-30`) | `DQ-T30-REVERSIBLE` | suppress → revoke; row kept as `REVOKED`; 2 audit rows |
| One work order however many clicks (`T-34`) | `DQ-T34-IDEMPOTENT` | 3 approvals → 1 work order |
| Audit failure blocks the write (`T-35`) | `DQ-T35-AUDIT-BLOCKS` | 0 work orders, 0 orphan audit rows |
| Every row audited no later than itself | `DQ-EVERY-WRITE-AUDITED` | 0 exceptions |
| No role can write directly (`T-33`) | grant scan **and** real `INSERT` as `WOA_APP` / `WOA_AGENT` | both refused, `002003` |
| The scheduler and agent hold nothing on `ACTION` (`T-76`) | `DQ-T76-NO-ACTION-PRIV` | 0 grants |
| Bound, not interpolated | a reason of `demo'); delete from ACTION.AUD_ACTION; --` through the app's `_call` path | stored verbatim as data; audit intact |
| Identity is the caller | probe of an owner's-rights procedure | `CURRENT_USER()` = `NIRAJ` (caller), not the owner |

## 4. What a human changed

Nothing. NK asked for the next step; the build, the tests and the fixes in §5 were CoCo's.

## 5. What CoCo got wrong

1. **The first `T-33` test passed the wrong way — the most important finding here.** It ran
   `USE ROLE WOA_APP` and tried an `INSERT` into `ACTION`, expecting refusal. The `INSERT` **succeeded**, as
   did the one "as `WOA_AGENT`": user `NIRAJ` has `DEFAULT_SECONDARY_ROLES = ALL`, so the session kept
   `ACCOUNTADMIN`'s privileges. The grants were correct (the grant scan found nothing); the test was not
   testing the role. With `USE SECONDARY ROLES NONE` both are refused. CoCo nearly read the test output as
   a false alarm, and checked the table first: two rows were really there. Logged as `I-18`.
2. **Three unaudited rows were deleted from `ACTION`**: the two above, and one from a manual probe. That
   is the one deliberate exception to append-only. Leaving them would have meant keeping rows no audit
   explains, which `DQ-EVERY-WRITE-AUDITED` correctly rejects. Deleted by exact key, recorded here and in
   `STATE.md` §7.
3. **Then `T-33` reported a correct refusal as a failure.** The CLI draws errors in a box and wrapped
   "not authorized" across two lines, so a text match missed it. It now matches Snowflake's error
   **code** (`002003`, `003001`).
4. **Two assertions were too broad on the first gate run** (`DQ-20260925200927`). `DQ-ACTION-NO-DIRECT-GRANT`
   counted `WOA_ENGINEER`'s dev-only `SELECT` as a write path; narrowed to write-capable privileges.
   `DQ-DRAFT-PROCEDURE-RESOLVES` required a procedure for blade and yaw parts no model scores, so no draft
   can cite them; scoped to scored classes. Both changes narrow what "failure" means for a reason stated in
   the code. Neither hides a write.
5. **The corpus had no procedure for the parts drafts cite.** The risk ranking costs each class at its
   costliest part (stator, pitch bearing, full gearbox, main bearing). Two had no document, so two procedures
   were added and the map is asserted.
6. **`I-19`, found while choosing test data:** 3 `NUISANCE` incidents sit on MEDIUM/HIGH-risk turbines,
   because the engine's `is_elevated` ignores the risk score. The procedure guards it (`DQ-T29-RISK`); the
   classification still disagrees and is logged for the engine owner.
7. **The app click-through could not run under `AppTest`.** The harness crashes on re-run on the
   segmented-control value (`"A" is not in list`), a harness limitation. The render passed with 0
   exceptions, and the exact call path the buttons use was exercised directly (§3, last three rows).

## 6. Cost

| Item | Credits |
| --- | --- |
| Warehouse: two `deploy-action`, two full `verify`, smoke and probe calls (~5 min per self-test run) | ≈ 0.6 |
| Running total on `BGTCHIX` | ≈ 92.7 (`STATE.md` §6) — **roughly $250; the $300 alert is next** |

## 7. Traceability

| Plan item | Where it is now |
| --- | --- |
| `FR-32` suppression guards, `T-29` | `SP_APPROVE_SUPPRESSION`; four `DQ-T29-*` (three gating) |
| `FR-32` reversible, `T-30` | `SP_REVOKE_SUPPRESSION`; `DQ-T30-REVERSIBLE` |
| `FR-34` draft with evidence, `T-32` | `SP_DRAFT_WORK_ORDER` snapshot + `DQ-DRAFT-PROCEDURE-RESOLVES`; **window and crew not yet drafted** |
| `FR-35` no write without approval, `T-33` | grants + `DQ-ACTION-NO-DIRECT-GRANT` + `_t33-direct-writes-refused` (both gating) |
| `FR-36` idempotent, `T-34` | idempotency key + one-per-draft; `DQ-T34-IDEMPOTENT` |
| `FR-37` audit first, `T-35` | audit row + verification before the write, one transaction; `DQ-T35-AUDIT-BLOCKS` (gating) |
| `NFR-19` / `T-76` scheduler never applies | grant half `DQ-T76-NO-ACTION-PRIV`; **behavioural half needs the scheduled task** |
| `T-71`, `T-74` | **Not yet** — need the window engine and the confirm/dismiss/reinstate paths |
