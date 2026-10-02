# Plan: CoCo ingenuity → submission ready

All work goes on branch `feat/nk/coco-ingenuity`, claimed in STATE.md §2 after running `just state`. All deploys target **JKDRJBB-MW27072 / WIND_OPS_AI**. I'll run `just target` first, and every SQL statement goes through `snow sql -c jkdrjbb-mw27072` or a `just` recipe.

## 1. Publish 3 real skills (`skills/<name>/SKILL.md, EXAMPLE.md, TEST.md`)
| Skill | Lifted from | Real output in EXAMPLE.md |
|---|---|---|
| `approval-gated-agent-tools` | `sql/50_action/*`, `sql/70_agent/01_agent.sql` | Approve and refuse rows from `ACTION.AUD_ACTION`, plus agent-suite probe results |
| `alarm-noise-triage` | `sql/40_engine/01_alarm_incidents.sql` and the related files | Compression, chattering, standing and flood counts, with the count of suppressed real failures shown beside them |
| `semantic-view-audit` | `sql/30_serve/02_semantic_view.sql`, the G3 assertions | Description and sample_values check output on `SV_WIND_OPS` |

- Each skill gets frontmatter (name, description, triggers), plus inputs, outputs, limits and failure modes.
- Each `TEST.md` has a prompt and the expected result. I'll run each one in a fresh CoCo session and record the session IDs.
- The `T-19` step needs a teammate who didn't write the skill to run the test. I'll mark it pending for JP to sign off, rather than claim it.
- I'll update `skills/README.md` to close the `Q-8` open question now that the repo is public.
- I'll replace coco-usage-plan §5 with the skills that actually ship, and mark the other candidates as backlog.

## 2. Automation (`T-76`/`T-77`, resolving `Q-78`)
- **Snowflake side:** new `sql/80_ops/` (or the next free number):
  - `01_scheduler_role.sql`: `WOA_SCHEDULER` gets EXECUTE TASK, usage on `WOA_BUILD_WH`, SELECT on SERVING/ENGINE, and INSERT only on `OPS.DIGEST`. It has no ACTION privileges, which resolves `Q-78`: automations run as `WOA_SCHEDULER` and only refresh, never apply.
  - `02_digest.sql`: `OPS.DIGEST` table plus a `OPS.SP_BUILD_DIGEST()` procedure that writes the top risks, alarm-noise stats and pending approvals.
  - `03_task.sql`: `CREATE TASK OPS.T_DAILY_DIGEST` with a 05:30 Asia/Kolkata cron, owned by `WOA_SCHEDULER`. Then `EXECUTE TASK` once to prove it.
- New recipe `deploy-ops`, wired into `deploy`, and assertions added to `just verify` (task exists and has started, at least one digest row today, scheduler has no ACTION grants).
- The app gets a small "Today's digest" panel reading `OPS.DIGEST`.
- **CoCo side:** create a `cortex automation` (load the automation skill) running `just verify` and `just agent-suite` daily.
  - Risk: the `cortex` CLI isn't on PATH. If I can't create the automation from Desktop, the README will say so plainly and point to the Snowflake task as the scheduled-run evidence.
- Evidence: `TASK_HISTORY` rows, digest rows, and the automation ID or its run log.

## 3. MCP: GitHub, local, interactive only
- Configure the GitHub MCP server in CoCo Desktop (the gh account `nirajkmr007` is authenticated).
- Demo: approve a work order in the app, then in CoCo read the approved row from `AUD_ACTION` and use MCP to file an issue in `winds-of-change-blr/wind-ops-ai` that links back to the audit row ID.
- Document the scope from ADR-0019: interactive only, because the account can't egress (no EAI on trial). Add a short note to ADR-0019.
- If the MCP server can't be configured, the fallback is to remove MCP from every claim and record it as DECLINED with that reason.

## 4. Fix over-claims
- `evaluation-traceability.md` lines 110, 121 and 173 and the related rows, plus coco-usage-plan §4 and §6, so they state what ships:
  - Skill count and names.
  - Automation: real.
  - MCP: real, or declined.
  - Surfaces: Desktop, Snowflake Intelligence and the Streamlit app. The CLI row is kept only if CLI usage rows exist; otherwise it's removed or marked not used.
  - Multi-agent: declined with its reason.
- I'll grep the README and docs for "four skills", "CLI", "Slack" and "MCP" to catch any other stale claims.

## 5. README evaluator map
New top section, "How this maps to the evaluation", containing:
- **Ingenuity table (7 rows):** criterion, verdict, what we built, a link to the code, and a link to the evidence file.
- **Phases table (Planning, Development, Execution and scheduled runs, Testing and validation):** CoCo's role in each and the evidence files.
- **Recommended tasks table:**
  - Synthetic data: `sql/10_generate`.
  - Pipelines: tasks, streams and dynamic tables. I'll state honestly what exists; dynamic tables only if verified.
  - Semantic model and verified queries: `SV_WIND_OPS`.
  - Streamlit app.
  - MCP: GitHub. Jira, Slack and Drive are not used, with the reason.
  - Unstructured documents: Cortex Search over maintenance docs.
- Credits summary from `just cost`, and a 3-command quickstart.

## 6. Evidence (7-section format, real IDs from the session JSON and ACCOUNT_USAGE)
- `development/13-reusable-skills.md`
- `development/14-github-mcp.md`
- `execution/02-scheduled-digest-and-automation.md`
- `testing/02-skill-tests-and-verify.md`
- Update the evidence README index, and summarise CoCo plus warehouse credits.

## 7. Close
- Run `just check` and `just verify` (expecting 73 plus the new assertions, all passing) and `just results`.
- Update STATE.md §1, §2, §5 and §8.
- Commit using Conventional Commits, then `just pr`. Nothing merges without 2 approvals.

## Assumptions and risks
- `CREATE TASK` works on the trial account (serverless or `WOA_BUILD_WH`). If it doesn't, I'll record the error as evidence.
- The scheduled digest costs only a few credits a day. I'll suspend the task after the demo if you want.
