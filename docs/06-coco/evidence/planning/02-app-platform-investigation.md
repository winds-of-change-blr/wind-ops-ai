# Planning 02 — App platform investigation (Snowflake App Runtime vs Streamlit)

> **Phase:** planning · **Date:** 2026-09-18 · **Outcome:** [`ADR-0020`](../../../03-architecture/decisions/adr-0020-app-platform.md)

## Verifiable identifiers

| Field | Value |
| --- | --- |
| CoCo `session_id` | `04d1ee7a-0e99-44de-afb6-40f838e591e6` |
| Workspace ID | `936de335e0f95bdb62958c348cc76e08` |
| Thread ID | `263509512` |
| Account | `BGTCHIX-UZ86048` (org `BGTCHIX`, locator `LM21871`) |
| User / role | `NIRAJ` / `ACCOUNTADMIN` |
| Model | `claude-opus-5` |
| Region / version | `AZURE_CENTRALINDIA` / 10.33.101 |
| Requests (cumulative, account) | 336 |
| Tokens (cumulative, account) | 95,771,805 |
| Skills loaded | `snowflake-apps`, `sar-actions-desktop` |

Reproduce:

```sql
SELECT COUNT(*) AS requests, SUM(tokens) AS tokens, ROUND(SUM(token_credits), 2) AS coco_credits
FROM SNOWFLAKE.ACCOUNT_USAGE.CORTEX_CODE_DESKTOP_USAGE_HISTORY;

SELECT ROUND(SUM(credits_used), 2) AS wh_credits
FROM SNOWFLAKE.ACCOUNT_USAGE.WAREHOUSE_METERING_HISTORY;
```

## Prompt

> "right now we are assuming we would make a streamlit app .. but as streamlit app has many limitation
> .. look for way to build proper web apps on snowflake with similar integrations. and update the app
> plan accordingly. do not worry if this extend the scope."

Mid-session decision by the human, after being shown the findings: **stay on Streamlit in Snowflake.**

## What CoCo produced

Eight capability probes against the live account, each a single statement, all cleaned up afterwards:

| Probe | Result |
| --- | --- |
| `SHOW APPLICATION SERVICES` | Recognised — DDL exists |
| `CREATE COMPUTE POOL WOA_PROBE_POOL … CPU_X64_XS` | Succeeded, reached `STARTING` |
| `CREATE ARTIFACT REPOSITORY … TYPE = APPLICATION` | Succeeded |
| `CREATE IMAGE REPOSITORY` | Succeeded |
| **`CREATE APPLICATION SERVICE …`** | **`Snowpark Container Services feature APPLICATION SERVICE not available for trial accounts`** |
| `CREATE SERVICE …` (plain SPCS, `public: true` endpoint) | Spec accepted; failed only on a deliberately absent image |
| **`CREATE STREAMLIT …`** | **Succeeded — closes `Q-39`** |
| `snow --version` | `command not found` |

Documents written: `adr-0020-app-platform.md` (94 lines) plus propagation into `decisions/README.md`,
`02-container.md`, `deployment.md`, `requirements.md` (`NFR-21`, `NFR-22`),
`testing-and-validation.md` (`T-97`, `T-98`), `raid-log.md` (`R-7`/`DEP-2`/`Q-39` closed, `R-29`,
`Q-94`), `project-plan.md`, `evaluation-traceability.md`, `demo-and-submission.md`, `STATE.md`.

## What a human changed

**The decision itself.** CoCo presented four options and recommended a containerised SPCS app behind a
D2 spike gate with Streamlit as fallback. The human chose **Streamlit only**. That is the more
conservative call and, on reflection, the better-argued one — writing up the rationale surfaced a
governance argument that CoCo had under-weighted: under SiS the app runs as the *viewer's* role, so
`NFR-3` is a property of the deployment rather than of code we would have to write and then ask a judge
to trust. A container would have meant re-implementing role scoping in application code.

## What CoCo got wrong

| Error | How it was caught |
| --- | --- |
| Wrote `PACKAGE = 'name'` in `CREATE APPLICATION SERVICE` | Syntax error. The grammar is `PACKAGE <name>` with no `=`. Fixed by reading the SQL reference rather than guessing again |
| Attempted `CREATE ARTIFACT REPOSITORY TYPE = NPM_REGISTRY` | Rejected: `Property 'API_INTEGRATION' must be specified`. The correct type for app packages is `APPLICATION`; `NPM_REGISTRY` is not a valid type at all |
| Initially treated the documentation statement "not available on trial accounts" as sufficient | It was correct, but three DDL probes *succeeded* first (compute pool, artifact repository, image repository), which would have made a docs-only answer look wrong to a teammate. Empirical confirmation was worth the four extra statements |

One judgement call recorded for honesty: CoCo weighted scope risk first and governance second when
recommending. The governance argument is the stronger one and should have led.

## Cost

| Source | Credits |
| --- | --- |
| CoCo token credits (`CORTEX_CODE_DESKTOP_USAGE_HISTORY`) | 48.61 |
| Warehouse (`WAREHOUSE_METERING_HISTORY`) | 2.57 |
| **Cumulative total** | **≈ 51.18** |

Both sources summed per `AGENTS.md`. The compute pool created during probing was dropped the same
session; it never left `STARTING` and ran no service.

## Traceability

Branch `docs/nk/hackathon-planning`. Follows commits `286f700`, `33a3ff5`, `3b0dee4`, `2208b8a`.
