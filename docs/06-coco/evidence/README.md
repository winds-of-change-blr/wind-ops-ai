# CoCo Evidence Log

> **Status:** Draft v0.1 · **Owner:** NK · **Last updated:** 2026-09-17
>
> [problem-statement.md §2](../../00-hackathon/problem-statement.md#2-snowflake-coco-usage-guidelines)
> makes CoCo use mandatory across the lifecycle and says judges will look for evidence at every
> stage. This is that evidence — `E4`. The plan is in
> [coco-usage-plan.md](../coco-usage-plan.md).

---

## Phases

One folder per phase. **One file per session** — never append to an existing entry.

| Phase | Folder | Status |
| --- | --- | --- |
| Planning | [planning/](planning/) | **Complete** — 2 entries |
| Development | [development/](development/README.md) | **In progress** — 4 entries |
| Execution | [execution/](execution/README.md) | Not started |
| Testing | [testing/](testing/README.md) | Not started |

## Entry format

Copy **[TEMPLATE.md](TEMPLATE.md)** to `<phase>/<NN>-<short-slug>.md`, fill it in, then add a row to
the [index](#index) below. `<NN>` is a zero-padded sequence within the phase. Rules live in
[AGENTS.md](../../../AGENTS.md#evidence); the worked example is
[planning/01-plan-generation.md](planning/01-plan-generation.md).

## Index

| Entry | Phase | What it records |
| --- | --- | --- |
| [planning/01-plan-generation.md](planning/01-plan-generation.md) | Planning | Generating the full plan — 46 documents, the reference-solution forensics, the cost under-report CoCo made and the human caught |
| [planning/02-app-platform-investigation.md](planning/02-app-platform-investigation.md) | Planning | Testing Snowflake App Runtime in-account: blocked on trial accounts, plain SPCS available, Streamlit verified. Outcome [`ADR-0020`](../../03-architecture/decisions/adr-0020-app-platform.md) |
| [development/01-foundation-setup.md](development/01-foundation-setup.md) | Development | `00_setup` + `90_teardown` behind `just deploy-foundation` (`US-44`, `US-45`, `T-50`, `T-52`). Local toolchain built from nothing; account move to `JKDRJBB-MW27072` re-verified; two contradictions found in `04-code.md` §6; the "batched SQL silently skips statements" rule disproved by execution |

The seven required sections, in order:

| Section | Required content |
| --- | --- |
| **Verifiable identifiers** | **Mandatory.** CoCo session ID, workspace and thread ID, account, user, model, subagent session IDs, plus `REQUEST_ID`s and aggregate token/credit figures from `ACCOUNT_USAGE`. Include the SQL to reproduce them |
| **Prompt** | Verbatim, or a faithful summary, plus mid-session human instructions |
| **What CoCo produced** | Files, objects, findings — with paths and, where relevant, line counts |
| **What a human changed** | **The honest field.** What was corrected, rejected or rewritten, and why |
| **What CoCo got wrong** | Errors and dead ends, and how they were caught |
| **Cost** | CoCo token credits **and** warehouse credits, summed |
| **Traceability** | Branch, commit or PR; files changed; whether any given file was modified |

The "what a human changed" field is the one worth reading. An entry claiming nothing was changed is
either a trivial task or an unreviewed output, and judges can tell the difference.

## Why identifiers are mandatory

An evidence log a team wrote about itself proves nothing. Snowflake records **every** Cortex Code
request server-side, so an entry can be tied to telemetry the judges' own platform holds:

| Where | What it proves |
| --- | --- |
| `ACCOUNT_USAGE.CORTEX_CODE_DESKTOP_USAGE_HISTORY` | Per-request IDs, timestamps, model, tokens, credits, role — that CoCo was used, when, how much, by whom |
| `ACCOUNT_USAGE.CORTEX_CODE_CLI_USAGE_HISTORY` | The same for CLI sessions (Official Rules §9 names the CLI specifically) |
| `ACCOUNT_USAGE.QUERY_HISTORY` | The SQL CoCo actually executed |
| Local `~/.snowflake/cortex/conversations/<workspace>/<session>.history.jsonl` | The full transcript, including subagent sessions |

The first version of the planning entry had none of this. It was caught by the human asking, and the
requirement exists so it is not missed again.

## Credit accounting

CoCo's own token usage is **not** in `WAREHOUSE_METERING_HISTORY`. Reporting warehouse credits alone
under-reported total consumption by roughly ten times during planning. Every cost figure must sum
**both** sources (`NFR-8`):

```sql
select 'cortex_code_desktop' as source, sum(token_credits) as credits
  from snowflake.account_usage.cortex_code_desktop_usage_history
union all
select 'warehouse', sum(credits_used)
  from snowflake.account_usage.warehouse_metering_history;
```

## Index

| # | Phase | Entry | Date | Produced |
| --- | --- | --- | --- | --- |
| 01 | Planning | [01-plan-generation.md](planning/01-plan-generation.md) | 2026-09-17 | The whole of `docs/` — 25 documents. Reference-solution forensics; live capability verification |
| 02 | Planning | [02-app-platform-investigation.md](planning/02-app-platform-investigation.md) | 2026-09-18 | `ADR-0020`: App Runtime blocked on trial, Streamlit verified. Eight in-account capability probes |
| 03 | Development | [01-foundation-setup.md](development/01-foundation-setup.md) | 2026-09-21 | 846 lines of setup/teardown SQL, 3 justfile recipes implemented. **Nothing deployed yet** — zero-DDL proof included |
| 04 | Development | [02-data-layer-foundation.md](development/02-data-layer-foundation.md) | 2026-09-22 | Foundation deployed to `WIND_OPS_AI_DEV_KR`. 14 dimension + 7 fact tables created; all dimensions seeded (100 turbines, 1000 components, 4100 signals). `just deploy-data` recipe implemented |
| 05 | Development | [03-synthetic-data-generator.md](development/03-synthetic-data-generator.md) | 2026-09-25 | The six-stage generator (`US-2`…`US-7`, `US-52`) and the `OPS` assertion suite — 13 SQL files, 2,904 lines, 108M signal rows, 16/16 assertions passing. Found the deploy account **empty** and entry 04's seed script **unrunnable**; `T-8` failed twice before the bad-batch population fixed it; `just seed` and `just verify` implemented |
| 06 | Development | [04-risk-classifier.md](development/04-risk-classifier.md) | 2026-09-25 | The ML layer (`US-18`…`US-21`) — 8 SQL files, 1,549 lines. **`T-10` passes**: 1.40x the trivial rule's precision at a matched budget, and 0.35–0.71 vs 0.00 component recall at a tight one. Baselines **pre-registered in their own commit before training**. Found `COMPONENT_ID` being used as a feature, a lead-time measurement artifact, and that Snowflake does not enforce primary keys |
