# Example — wind-ops-ai, 2026-10-02, account JKDRJBB-MW27072

Real calls against `WIND_OPS_AI.ACTION`, run as `WOA_PLANNER` with `use secondary roles none`.

## 1. A guard refuses a stale approval

```sql
call ACTION.SP_APPROVE_WORK_ORDER('6ae4612e-91dd-419f-bf02-2796d3e7d8c5',
                                  'mcp-demo-approve-6ae4612e', 'Niraj Kumar (NK)');
```
```json
{ "outcome": "REFUSED",
  "message": "The risk score has been refreshed since this draft was made (2026-08-28 vs 2026-08-30). Re-draft from the current score." }
```

The draft was two days older than the model's latest score. The procedure re-read the live score
rather than trusting the draft, and refused. The refusal is in `AUD_ACTION` too.

## 2. One open draft per component

```sql
call ACTION.SP_DRAFT_WORK_ORDER('TN-TVL-T06-MSB', 'mcp-demo-draft-TN-TVL-T06-MSB', 'Niraj Kumar (NK)');
```
```json
{ "outcome": "REFUSED", "draft_id": "a72e5014-df9f-410c-841f-e55b9983dd28",
  "message": "An open draft already exists for this component: a72e5014-df9f-410c-841f-e55b9983dd28." }
```

## 3. Reject with a coded reason, re-draft, approve

```sql
call ACTION.SP_REJECT_WORK_ORDER_DRAFT('a72e5014-…', 'OTHER',
     'Stale: risk score refreshed after this draft; re-drafting from current score',
     'mcp-demo-reject-a72e5014', 'Niraj Kumar (NK)');
-- {"outcome":"APPLIED","decision_id":"6a1341e6-07db-4cd8-99b4-58c0befa014a","message":"Draft rejected (OTHER). Recorded in the audit."}

call ACTION.SP_DRAFT_WORK_ORDER('TN-TVL-T06-MSB', 'mcp-demo-draft2-TN-TVL-T06-MSB', 'Niraj Kumar (NK)');
-- {"outcome":"APPLIED","draft_id":"d90a5887-d8c2-439a-80c5-07b376bc11ec","message":"Draft created. It needs a planner's approval before anything is written as a work order."}

call ACTION.SP_APPROVE_WORK_ORDER('d90a5887-d8c2-439a-80c5-07b376bc11ec', 'mcp-demo-approve-d90a5887', 'Niraj Kumar (NK)');
-- {"outcome":"APPLIED","work_order_id":"dd77c8bc-e4a0-474e-aaba-bb4fac9ca012",
--  "message":"Work order approved and recorded. It is not yet scheduled: no window, crew or crane has been booked."}
```

## 4. Reading it back without SELECT on the table

`WOA_PLANNER` holds no table privilege in `ACTION` (an earlier `select` from it failed with
*"Your primary role WOA_PLANNER must have at least one privilege granted on TABLE ..."*). The
read path is `ACTION.SP_GET_WORK_ORDER`:

```json
{ "work_order_id": "dd77c8bc-e4a0-474e-aaba-bb4fac9ca012", "status": "APPROVED_NOT_SCHEDULED",
  "is_selftest": false, "approved_by": "JVPAN0816", "approved_role": "WOA_ADMIN",
  "on_behalf_of": "Niraj Kumar (NK)", "audit_id": "c1ae54bf-5ead-477c-8530-d1c5015d663f",
  "component_id": "TN-TVL-T06-MSB", "risk_band": "HIGH", "risk_probability": 0.999855,
  "procedure_doc_id": "VWS-MP-MSB-003" }
```

Note `approved_role: WOA_ADMIN` — the procedure owner, per the Limits section of `SKILL.md`.

## 5. The agent cannot write at all

From `just verify` (G4), 2026-10-02: `DQ-ACTION-NO-DIRECT-GRANT` PASS, `DQ-T76-NO-ACTION-PRIV`
PASS, and the recipe's two sessions — `INSERT` into `ACTION` as `WOA_APP` and as `WOA_AGENT` —
both refused for lack of privilege. The 10-probe adversarial suite (`just agent-suite`,
`docs/06-coco/evidence/testing/01-adversarial-and-degraded.md`) asked the agent to approve,
suppress and delete; it had no tool to do any of them.
