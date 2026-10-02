# Execution — 02 · The scheduled daily digest, run as `WOA_SCHEDULER`

> **Phase:** execution (scheduled run) · **Date:** 2026-10-02 · **Surface:** Snowflake task, built from Cortex Code Desktop ·
> **Participants:** NK (human), CoCo (agent) · **Branch:** `feat/nk/coco-ingenuity`

---

## Verifiable identifiers

| Item | Value |
| --- | --- |
| **CoCo session ID** | `42a370d2-a657-4283-8984-94dac6f03a8a` (telemetry in [development 13](../development/13-reusable-skills.md)) |
| Task | `WIND_OPS_AI.OPS.T_DAILY_DIGEST`: `USING CRON 30 5 * * * Asia/Kolkata`, owner `WOA_SCHEDULER`, state `started` |
| First run | `SUCCEEDED`, query `01c774fb-0002-24cf-000f-997200114ff2`, 2026-10-02 08:27:47–08:27:53 UTC |
| Next scheduled run | 2026-10-03 00:00 UTC (05:30 IST), visible in `INFORMATION_SCHEMA.TASK_HISTORY` as `SCHEDULED` |
| Digest row | `DIG-20261002012748`, `built_by_role = WOA_SCHEDULER` |
| Account grant | `EXECUTE TASK ON ACCOUNT` to `WOA_SCHEDULER`, granted by `ACCOUNTADMIN` 2026-10-02 01:27:45 PDT |

## Prompt

Item 2: "a Snowflake CREATE TASK producing a daily risk and alarm digest (T-76/T-77), plus a CoCo
scheduled automation … Q-78 needs resolving."

## What CoCo produced

1. **`Q-78` resolved by ownership.** The task is *owned* by `WOA_SCHEDULER`, a role with no
   human user, so it runs with exactly that role's grants:
   - SELECT on ENGINE;
   - INSERT on the one table `OPS.OPS_DIGEST`;
   - nothing at all on `ACTION`.

   No `ALTER USER … DEFAULT_ROLE` was needed, which is the thing `01_account_roles.sql` forbids.
2. **[`sql/85_ops/01_daily_digest.sql`](../../../../sql/85_ops/01_daily_digest.sql)** creates
   `OPS.OPS_DIGEST`, the procedure `OPS.SP_BUILD_DIGEST()` and the task. It is idempotent: it
   uses `create … if not exists`, so the table and the task's history survive a re-run. The
   first run wrote:

   > 5 HIGH-risk components; 3 safety-critical incidents; 3 maintenance windows proposed for
   > approval. Nothing has been applied.

   It also wrote the top 5 risks (#1 `MH-STR-T08` Generator, INR 4,367,892 expected loss),
   alarm-noise stats with the real-failure count beside compression, and the top 3 window
   suggestions.
3. **Gated by [`sql/15_quality/09_ops_assertions.sql`](../../../../sql/15_quality/09_ops_assertions.sql)**,
   run in `just verify` and `just deploy-ops`. All 4 assertions **PASS**:

   | Assertion | Gating | Result |
   | --- | --- | --- |
   | `DQ-T76-TASK-OWNED-BY-SCHEDULER` | yes | `WOA_SCHEDULER / started / USING CRON 30 5 * * * Asia/Kolkata` |
   | `DQ-T76-TASK-SUCCEEDED` | yes | 1 SUCCEEDED run in 7 days |
   | `DQ-T76-SCHEDULER-ONE-WRITE` | yes | 0 write privileges other than INSERT on `OPS.OPS_DIGEST` |
   | `DQ-T77-DIGEST-FRESH` | no | 1 populated digest by `WOA_SCHEDULER` in 26 h |

4. A new `just deploy-ops` recipe, wired into `just deploy`, which executes the task once so the
   gate checks a real run.

## The CoCo-side automation: not built, and why

The ask included a CoCo scheduled automation (a Snowflake AGENT TASK running Cortex Code). CoCo
loaded the `automation` skill. It creates these through the `cortex automation` CLI, and **that
CLI is not installed on this machine** (`cortex: command not found`; not in the app bundle
either). A fire would also run in a Snowflake sandbox with no local repo and no local MCP
servers, so it could not run `just verify` as asked. We claim the Snowflake task only.

## What a human changed

| Change | Effect |
| --- | --- |
| None beyond approving the plan | |

## What CoCo got wrong

| Error | How it was caught | Fix |
| --- | --- | --- |
| Put `COMMENT` after `EXECUTE AS` in the procedure | Compile error "unexpected 'comment'" | Moved it before `EXECUTE AS` |
| The grant-check detail printed blank on a pass (`listagg` of zero rows is `''`, not NULL) | Read the gate output | `coalesce(nullif(…, ''), …)` |

## Cost

| Source | Credits |
| --- | --- |
| One digest run | 6 s on `WOA_BUILD_WH` (XS); the daily cost is about one minute of XS |
| Warehouse, JKDRJBB, since 08:00 UTC (all activity) | `WOA_APP_WH` 0.840, `COMPUTE_WH` 0.265; `WOA_BUILD_WH` not yet in `WAREHOUSE_METERING_HISTORY` (lag) |

## Traceability

| Item | Value |
| --- | --- |
| Implements | T-76 (gating), T-77, FR-85, NFR-19, `Q-78` closed |
| Files | `sql/85_ops/01_daily_digest.sql`, `sql/15_quality/09_ops_assertions.sql`, `sql/15_quality/17_run_verify_ops.sql`, `justfile` |
| To stop it | `use role WOA_SCHEDULER; alter task WIND_OPS_AI.OPS.T_DAILY_DIGEST suspend;` |
