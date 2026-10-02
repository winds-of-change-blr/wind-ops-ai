# Testing — 02 · Re-verify after the ingenuity work, and what the gate caught

> **Phase:** testing · **Date:** 2026-10-02 · **Surface:** Cortex Code Desktop → `just verify` / `just check` ·
> **Participants:** NK (human), CoCo (agent) · **Branch:** `feat/nk/coco-ingenuity`

---

## Verifiable identifiers

| Item | Value |
| --- | --- |
| **CoCo session ID** | `42a370d2-a657-4283-8984-94dac6f03a8a` (telemetry in [development 13](../development/13-reusable-skills.md)) |
| Target | `JKDRJBB-MW27072` / `WIND_OPS_AI` |
| `just verify` gate failure | query `01c77512-0002-2358-000f-99720011c30e`, `GATE_FAILED` in G1 |

## Prompt

Plan step 7: "`just check` and `just verify` (73 plus the new assertions, all passing)".

## Results

| Suite | Result |
| --- | --- |
| `just check` (ruff and pytest) | **PASS**: lint clean, 3/3 tests |
| G1 data quality | **1 FAIL**: `T-11 DQ-FRESHNESS`, worst overrun `FCT_SIGNAL_10MIN` at 63 h against a 24 h allowance. All other G1 assertions pass |
| G2 model | PASS, 10 assertions |
| Engine | PASS, 11 |
| Answers (G3) | PASS, 6 |
| Numbers (G3) | PASS, 10 |
| G4 approval-gated writes | PASS, 13, plus `_role-writes-refused`: DELETE, UPDATE, ALTER and DROP as the app and agent roles, all refused (003001) |
| G4 planning | PASS, 7 |
| **Automation (new)** | **PASS, 4** (see [execution 02](../execution/02-scheduled-digest.md)) |
| MCP connector smoke (new) | **PASS**: `ALREADY_FILED` ×2, then `REFUSED` for a self-test row ([artifact](../development/artifacts/14-mcp-smoke.json)) |

`just verify` stops at the first failing suite, so after G1 CoCo ran each remaining suite's
`15_quality/*_run_verify_*.sql` directly to show the rest of the stack is green.

## Reading the one failure honestly

`T-11` is the freshness contract: the synthetic data must end within 24 h of now. The last full
`just deploy` was 2026-09-29 ([execution 01](../execution/01-full-deploy-and-submission-surface.md)),
so the data is now 63 h old. **This session did not cause it, and this session did not fix it.**
The fix is a full `just deploy`, which regenerates the data, retrains the classifier and rebuilds
everything downstream. STATE.md §3 already schedules that within 48 h of the demo, so a judge
sees fresh data. Running it now would have to be repeated anyway.

So `results.md` is **not** regenerated here. It would publish a failing freshness gate, and the
reason for that belongs in this entry, not in a generated summary.

## What a human changed

| Change | Effect |
| --- | --- |
| None | |

## What CoCo got wrong

| Error | How it was caught | Fix |
| --- | --- | --- |
| Six lines over 100 characters in the new Python | `just check` (ruff E501) | Refactored the issue-body builder; the smoke test re-run still PASSes |

## Cost

Within the session totals in development 13.
