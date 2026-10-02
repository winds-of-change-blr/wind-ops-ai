# Development 13 — three reusable skills, lifted from what already ran

> **Phase:** development · **Date:** 2026-10-02 · **Surface:** Cortex Code Desktop ·
> **Participants:** NK (human), CoCo (agent) · **Branch:** `feat/nk/coco-ingenuity`

---

## Verifiable identifiers

| Item | Value |
| --- | --- |
| **CoCo session ID** | `42a370d2-a657-4283-8984-94dac6f03a8a` (shared by entries 13, 14, execution 02 and testing 02) |
| Account (CoCo session) | `BGTCHIX-UZ86048`, user `NIRAJ`, role `ACCOUNTADMIN` |
| Account (the work) | `JKDRJBB-MW27072`, database `WIND_OPS_AI`, user `JVPAN0816` |
| Orchestration model | `claude-opus-5-5` |
| Mode | plan, then agent once the plan was approved |

### Server-side telemetry (build window 08:22–08:49 UTC, for the whole session)

| Measure | Value |
| --- | --- |
| CoCo requests in `CORTEX_CODE_DESKTOP_USAGE_HISTORY` (BGTCHIX, since 08:22 UTC) | 87 |
| First / last request | 2026-10-02 08:22:08 UTC / 08:49:19 UTC (at time of writing) |
| Tokens | 15,325,823 |
| CoCo token credits | 2.960 |

Sample `REQUEST_ID`s: `0faaa13f-9a33-4957-a1e7-f0159305a602`, `ff5fbb05-17f1-4bf4-bd1b-98ab52feca6b`,
`fcdc9406-4bec-4fa2-bb25-53d095818778`.

## Prompt

"do all 4 and collect the evidences … make the our repo submission ready" (item 1: publish two or
three real skills, lifted from `sql/50_action` and `sql/40_engine`).

## What CoCo produced

1. **[`approval-gated-agent-tools`](../../../../skills/approval-gated-agent-tools/SKILL.md)** is the
   `ACTION` pattern, generalised: owner's-rights procedures as the only write path, guards that
   refuse with a reason, idempotency, audit-first, and grant proofs. Its
   [EXAMPLE](../../../../skills/approval-gated-agent-tools/EXAMPLE.md) is today's real calls: a stale
   approval refused, a duplicate draft refused, then reject, re-draft and approve to
   `dd77c8bc-e4a0-474e-aaba-bb4fac9ca012`.
2. **[`alarm-noise-triage`](../../../../skills/alarm-noise-triage/SKILL.md)** is ADR-0017's
   three-class classifier made source-agnostic. Its
   [EXAMPLE](../../../../skills/alarm-noise-triage/EXAMPLE.md) is the live funnel: 342,305 alarms
   become 15,934 incidents (21.5×), with 38 nuisance, 9,655 undetermined and **0 real failures
   hidden** (`DQ-NO-SUPPRESSED-FAILURE`).
3. **[`semantic-view-audit`](../../../../skills/semantic-view-audit/SKILL.md)** was run for real
   against `SV_WIND_OPS`. It found four gaps that the existing T-42 checks pass over:
   - no verified queries;
   - 0 of 32 dimensions have sample values;
   - synonyms on 5 of 32 dimensions and 1 of 15 metrics;
   - three thin descriptions.
4. [`skills/README.md`](../../../../skills/README.md) now lists the published table, closes `Q-8`
   (the repo is public), and moves the unshipped candidates to the backlog.

## What a human changed

| Change | Effect |
| --- | --- |
| Approved the plan, including "two or three" skills rather than the seven candidates | Three skills, each with real output, instead of seven thin ones (`Q-68`) |

## What CoCo got wrong

| Error | How it was caught | Fix |
| --- | --- | --- |
| The alarm EXAMPLE said "70+ turbines" and cited `DQ-T60-*` | Re-queried: 100 distinct turbines; the T-60 assertion is `DQ-NO-SUPPRESSED-FAILURE` | Corrected before commit |
| The semantic-view EXAMPLE attributed the description check to T-37 | `OPS.DQ_ASSERTION`: T-37 is about documents; descriptions are `DQ-SV-DESCRIBED` (T-42) | Corrected before commit |

## Not done

The teammate test **`T-19` is pending** for all three skills. Each `TEST.md` has the prompt, the
expected result and an empty record row for JP. We do not mark a skill as teammate-tested until
that row is filled in.

## Cost

| Source | Credits |
| --- | --- |
| CoCo tokens | Included in the session total above (2.960 since 08:22 UTC, BGTCHIX) |
| Warehouse | The audit queries ran on JKDRJBB `COMPUTE_WH`: 0.265 since 08:00 UTC, all work |

## Traceability

| Item | Value |
| --- | --- |
| Implements | NFR-13 (published skills), coco-usage-plan §4 row 1 and §5, `Q-8` closed |
| Files added | 9 under `skills/`, plus `skills/README.md` changed |
