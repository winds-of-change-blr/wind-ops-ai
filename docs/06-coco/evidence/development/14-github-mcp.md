# Development 14 — `woa-github`: an MCP connector that can only forward an approval

> **Phase:** development · **Date:** 2026-10-02 · **Surface:** Cortex Code Desktop (local MCP) ·
> **Participants:** NK (human), CoCo (agent) · **Branch:** `feat/nk/coco-ingenuity`

---

## Verifiable identifiers

| Item | Value |
| --- | --- |
| **CoCo session ID** | `42a370d2-a657-4283-8984-94dac6f03a8a` (telemetry in [development 13](13-reusable-skills.md)) |
| Account | `JKDRJBB-MW27072`, database `WIND_OPS_AI`; reads run as `WOA_PLANNER` with `use secondary roles none` |
| Approved work order | `dd77c8bc-e4a0-474e-aaba-bb4fac9ca012` (draft `d90a5887-d8c2-439a-80c5-07b376bc11ec`, component `TN-TVL-T06-MSB`) |
| Its audit row | `ACTION.AUD_ACTION.AUDIT_ID = c1ae54bf-5ead-477c-8530-d1c5015d663f` |
| GitHub issue filed | [#27](https://github.com/winds-of-change-blr/wind-ops-ai/issues/27) (open) |
| Duplicate, closed | [#28](https://github.com/winds-of-change-blr/wind-ops-ai/issues/28), see "What CoCo got wrong" |
| Protocol transcript | [`artifacts/14-mcp-smoke.json`](artifacts/14-mcp-smoke.json) |

## Prompt

Item 3: "a local MCP connector on the CoCo side, e.g. GitHub, to file an issue from an approved
work order. Otherwise remove MCP from the claims."

## What CoCo produced

1. **[`mcp/woa_github/server.py`](../../../../mcp/woa_github/server.py)** is a stdio MCP server
   with two tools:
   - `get_approved_work_order` (read-only).
   - `file_work_order_issue`, which files only if the work order is `APPROVED_*`, is not a
     self-test, and has an APPLIED audit row. Otherwise it returns `REFUSED` with the reason.
     It is idempotent by work-order id.

   It holds no credentials: it shells out to `snow` (named connection) and `gh` (keyring
   login), and validates the id as a UUID before it reaches either.
2. **[`ACTION.SP_GET_WORK_ORDER`](../../../../sql/50_action/05_read_procedures.sql)** is a
   read-only owner's-rights procedure. No role holds SELECT on `ACTION` (T-33). The connector's
   first query, a plain `select`, failed with *"Your primary role WOA_PLANNER must have at least
   one privilege granted on TABLE …"*. CoCo added a procedure rather than a grant, so T-33
   still holds.
3. **A real approval to forward.** The first approval attempt was **refused by a guard**: "The
   risk score has been refreshed since this draft was made (2026-08-28 vs 2026-08-30)". A
   second draft was refused because one was already open. CoCo rejected the stale draft with a
   coded reason, re-drafted from the current score, and approved, all through the gated
   procedures as `WOA_PLANNER`.
4. **[`scripts/mcp_smoke.py`](../../../../scripts/mcp_smoke.py)** drives the server over the MCP
   stdio protocol, as CoCo does: approved order → `ALREADY_FILED` #27, repeat →
   `ALREADY_FILED` #27, self-test row `df589594-…` → `REFUSED` ("a verify self-test row, not a
   real approval"). **PASS**.
5. Registration: [`mcp/mcp.example.json`](../../../../mcp/mcp.example.json) is the template, and
   the local `~/.snowflake/cortex/mcp.json` registers `woa-github` for CoCo Desktop.

## What a human changed

| Change | Effect |
| --- | --- |
| Chose "build it" over "remove MCP from the claims" | One scoped connector instead of a decline |

## What CoCo got wrong

| Error | How it was caught | Fix |
| --- | --- | --- |
| Imported `mcp.server.fastmcp`; `uv` resolved `mcp` 2.x, where FastMCP is renamed | Server exited at start, so the smoke test saw "Connection closed" | Pinned `mcp>=1.2,<2` in the server config and the smoke test |
| Indexed `wo['crew_id']`; `OBJECT_CONSTRUCT` drops NULL keys, and an unscheduled order has no crew | Smoke test returned `'crew_id'` as a tool error | All optional fields read with a fallback |
| **Idempotency by `gh issue list --search`.** The search index lags new issues, so the repeat call filed **#28** | The smoke test's second call expected `ALREADY_FILED` and got `FILED` | Match the work-order id locally over `gh issue list --json body`; #28 closed as a duplicate with a comment |
| Audit read attempted with `SELECT` on `ACTION` | Insufficient-privilege error | Read-only procedure (item 2) |

## Found, not fixed

`approved_role` on every work order, including today's, records **`WOA_ADMIN`**, the owner of
the owner's-rights procedure, not the caller `WOA_PLANNER`. The guard itself uses
`is_role_in_session`, so access control is correct, but the audit column is misleading.
Recorded in the skill's Limits. A fix belongs in `50_action/02` and its assertions, not in this
session.

## Scope and limits

Interactive only. The trial account has no external access integration, so neither a Snowflake
task nor a CoCo agent-task automation can reach GitHub. The connector runs where the human is.

## Cost

Within the session totals in development 13. The `snow` calls ran on `WOA_APP_WH`: 0.840
credits since 08:00 UTC, for all activity.
