---
name: approval-gated-agent-tools
description: "Give an AI agent (Cortex Agent, CoCo, any LLM) the ability to PROPOSE writes in Snowflake while making it structurally impossible for it to APPLY them. Builds owner's-rights stored procedures that are the only write path, guards that refuse unsafe requests with a reason, idempotency keys, an append-only audit that records refusals too, and grants proving no role can write around them. Triggers: agent write access, human in the loop, approval workflow, safe agent actions, guardrails for agent tools, audit every write, idempotent procedure, agent must not write."
---

# Approval-gated agent tools

## Purpose

An agent that can call a write procedure will eventually call it wrongly. This skill builds the
pattern where **the agent has no write tool at all** — an absent tool, not a disabled one — and
every state change goes through a procedure a human role invokes, which checks guards, writes
the audit first, and refuses with a reason the human can read.

It is the pattern behind `ACTION` in wind-ops-ai (`sql/50_action/`), generalised.

## When to use

- You are giving a Cortex Agent or CoCo tools over operational data and something must be
  approved before it changes (a work order, a suppression, a refund, a config change).
- You need to prove to a reviewer that the agent *cannot* write, not that it *doesn't*.

## Inputs (ask for any that are missing)

| Input | Example |
| --- | --- |
| Action schema | `ACTION` |
| The thing being approved, and its draft table | work order / `ACT_WORK_ORDER_DRAFT` |
| The approver role, and the read-only agent role | `WOA_PLANNER` / `WOA_AGENT` |
| Guards: conditions under which approval must be refused | "risk score refreshed since the draft", "safety-critical" |
| Admin role that owns the procedures | `WOA_ADMIN` |

## Steps

1. **Tables.** Create `<SCHEMA>.<DRAFT>`, `<SCHEMA>.<APPLIED>` and an append-only
   `<SCHEMA>.AUD_ACTION(audit_id, event_at, actor_user, actor_role, on_behalf_of, action_type,
   object_type, object_id, idempotency_key, outcome, reason, inputs variant, evidence variant)`.
   Owned by the admin role. No other role gets any table privilege — and no FUTURE grants in the
   schema, or a later table silently becomes writable.
2. **One procedure per verb**, `EXECUTE AS OWNER`, signature
   `(subject_id, idempotency_key, on_behalf_of default null) returns variant`. In order:
   1. Idempotency: if `idempotency_key` was already APPLIED, return that result; write nothing.
   2. **Who may call is the `USAGE` grant on the procedure (step 4), not a check inside it.**
      Do not use `is_role_in_session('<APPROVER>')` here: in an `EXECUTE AS OWNER` procedure it
      tests the **owner's** role hierarchy, so it passes for every caller whenever the owner
      inherits the approver role, and fails for every caller otherwise (proved in T-19, TEST.md).
   3. Guards, each producing a human-readable `reason`. Re-read live state; never trust the draft.
   4. `begin transaction`; insert the audit row (APPLIED **or** REFUSED); if the insert count is
      not 1, raise — an unaudited write must be impossible; then apply; `commit`.
   5. Return `object_construct('outcome', ..., 'message', reason, '<id>', ...)`. Never raise for a
      refusal — the caller (often an agent) needs the reason as data.
3. **Read access through a procedure too** (`SP_GET_<THING>`, owner's rights, read-only) if
   anything outside the app must see applied rows — do not grant SELECT on the tables.
4. **Grants.** `USAGE` on each procedure to the approver role only. The agent role gets nothing
   on the schema, not even `USAGE`.
5. **Agent.** Give the agent only read tools (semantic view, search). It may *recommend* a call;
   the app or a human makes it.
6. **Prove it** with behavioural tests that call the real procedures (see `TEST.md`) and a
   direct `INSERT` attempted as the agent role in a session with `use secondary roles none`.
   Without that line, a human's secondary roles make the INSERT succeed and the test lies.

## Outputs

- DDL for the tables, procedures and grants, deployed by the project's normal path.
- Assertions: guards refuse, refusals are audited, idempotent repeat returns the same id, agent
  role holds zero privileges on the schema, every applied row has an audit row no later than it.

## Limits

- `EXECUTE AS OWNER` makes `current_role()` inside the procedure the **owner**, not the caller.
  `is_role_in_session` inside it also sees the owner, not the caller. Control callers with the
  procedure's `USAGE` grant, record the person with the `on_behalf_of` argument, and do not
  read `approved_role` as the approver's role. (wind-ops-ai audit rows show this — see EXAMPLE.)
- Owner's-rights procedures cannot run `SHOW` on objects the owner cannot see, and cannot change
  role, so the "direct INSERT is refused" test must run outside the procedure.
- This makes an agent safe to *connect*; it does not make its recommendations correct.
