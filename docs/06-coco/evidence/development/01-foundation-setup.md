# Development 01 — Foundation setup: roles, warehouses, database, schemas, grants

> **Phase:** development · **Date:** 2026-09-21 · **Stories:** `US-44`, `US-45` · **Tests:** `T-50`, `T-52`
> **Status:** phases 1–3 of 5 complete. **Nothing deployed to Snowflake yet** — see
> [What CoCo produced](#what-coco-produced) and the zero-DDL proof below.

## Verifiable identifiers

| Field | Value |
| --- | --- |
| CoCo `session_id` | `34ca9e37-5241-44c0-b632-53e21e2c8e96` |
| Workspace ID | `e287939e39ffda63e106c6e52956a6f0` |
| Thread ID | `262913552` — **detached**, `detachReason: accountSwitched` (see caveat below) |
| Account | `JKDRJBB-MW27072` (org `JKDRJBB`, account `MW27072`, locator `EB28292`) |
| User / role | `JVPAN0816` / `ACCOUNTADMIN` |
| Model | `claude-opus-5` (`selectedCortexModelId: auto-intelligent`, `model_role: orchestration`) |
| Region / version | `AZURE_CENTRALINDIA` / 10.33.101 |
| Session history length | 167 messages · `stats.diff`: 15 files, +1016 / −46 |
| Subagent `session_id` (1) | `26427780-e1c8-4c9d-9754-3d659ad79e26` — `toolu_bdrk_01NQwdcjPFFgrPNAUFJh2KtJ` |
| Subagent `session_id` (2) | `fae123ac-8c2d-471c-8133-b3e9850a3690` — `toolu_bdrk_015a1KVJsV4w5aAC8fDvbwGw` |
| Skills loaded | None. No skill matched a SQL-foundation task |

**Account-usage figures at time of writing** (cumulative for this account, all sessions):

| Day | Requests | Tokens | CoCo credits |
| --- | --- | --- | --- |
| 2026-09-16 | 8 | 365,671 | 0.2466 |
| 2026-09-19 | 38 | 4,552,429 | 3.0305 |
| 2026-09-21 *(this session)* | 53 | 11,167,494 | 5.9644 |
| **Total** | **99** | **16,085,594** | **9.2415** |

**Two honest caveats on these identifiers.**

1. **The thread is detached.** `thread.accountHost` is `konussk-jy51269.snowflakecomputing.com` with
   `detachReason: accountSwitched`, because this session began on `KONUSSK-JY51269`, moved to
   `WSFSDHO-BF64223`, and settled on `JKDRJBB-MW27072`. `lastSyncedHistoryLength` is `0`, so
   server-side thread sync holds nothing for this session. The local transcript at
   `~/.snowflake/cortex/conversations/e287939e39ffda63e106c6e52956a6f0/34ca9e37-….history.jsonl` and
   `CORTEX_CODE_DESKTOP_USAGE_HISTORY` on `JKDRJBB-MW27072` are the authoritative records.
2. **`requestCount` in the session file says `5`** and is wrong — it does not survive the account
   switches. The `ACCOUNT_USAGE` figure (53 requests on 2026-09-21) is the one to trust.

Reproduce:

```sql
-- Per-day CoCo usage. NOTE: the column is TOKEN_CREDITS, not CREDITS.
select to_date(usage_time) as usage_day, count(*) as requests,
       sum(tokens) as tokens, round(sum(token_credits), 4) as coco_credits
from snowflake.account_usage.cortex_code_desktop_usage_history
group by 1 order by 1;

-- Both credit sources, summed (NFR-8).
select 'cortex_code_desktop' as source, round(sum(token_credits), 4) as credits
  from snowflake.account_usage.cortex_code_desktop_usage_history
union all
select 'warehouse', round(sum(credits_used), 4)
  from snowflake.account_usage.warehouse_metering_history;

-- PROOF THAT NOTHING WAS DEPLOYED: every statement this user ran, by type.
select coalesce(query_type, 'n/a') as query_type, count(*) as n
from snowflake.account_usage.query_history
where start_time >= '2026-09-21' and user_name = 'JVPAN0816'
group by 1 order by n desc;

-- PROOF THE ACCOUNT IS CLEAN.
select (select count(*) from snowflake.account_usage.roles
          where name like 'WOA%' and deleted_on is null) as woa_roles,
       (select count(*) from snowflake.account_usage.databases
          where database_name like 'WIND_OPS_AI%' and deleted is null) as woa_databases,
       (select count(*) from snowflake.account_usage.warehouse_metering_history
          where warehouse_name like 'WOA%') as woa_wh_metering_rows;
```

**Zero-DDL proof, as returned:**

| `QUERY_TYPE` (user `JVPAN0816`, 2026-09-21) | n |
| --- | --- |
| `SELECT` | 15 |
| `UNKNOWN` | 2 |
| `SHOW` | 2 |
| `DESCRIBE` | 1 |
| `EXPLAIN` | 1 |

No `CREATE`, `GRANT`, `DROP`, `ALTER`, `INSERT`, `UPDATE`, `DELETE` or `MERGE`. And
`woa_roles = 0`, `woa_databases = 0`, `woa_wh_metering_rows = 0`.

This check was worth running: the unfiltered `QUERY_HISTORY` for 2026-09-21 shows **407 `GRANT`** and
**204 `CREATE`** statements, which looks damning until you group by user — all of them are
`SYSTEM` / `SNOWFLAKE`, Snowflake's own internal maintenance. An evidence entry that quoted the
unfiltered number would have been wrong in the alarming direction.

## Prompt

Session opened with `snow connection test` (repeated across three account switches), then:

> "scan this project in very detail. I want to start the implementation. create a branch for that and
> check the snowflake connections is ready. Dont implement anything yet. Ask for my confirmation."

Then, after the scan and a four-question gate:

> "take all actions to complete local development set up, just dont start the implementation"

Then:

> "go ahead and start implementation in phased manner, wait for my response after every phase. Dont
> assume anything if you are not clear then ask me"

Finally:

> "Collect the evidence of what we have done till now"

**Mid-session human decisions** — eight, all through the question gate, all recorded because each one
changed the output:

| Decision | Chosen |
| --- | --- |
| Toolchain | Install `just`, `uv`, `gh` via Homebrew |
| Initials | `jp` |
| First-branch scope | Foundation **plus** re-verify account capabilities |
| Blockers | "Take all actions to complete local development set up" |
| SQL parameterisation | `snow` CLI `-D` variables |
| Elevated stage role | `ACCOUNTADMIN` for the whole elevated stage |
| Dev database | Build dev directly; make cloning a later concern |
| `Q-78` | Create `WOA_SCHEDULER`, skip `ALTER USER`, keep it flagged |
| Role hierarchy contradiction | Trust the grant table; flat persona roles |
| `WOA_ADMIN` / `CREATE DATABASE` | `ACCOUNTADMIN` creates, then transfers ownership |
| SQL batching | Grouped files; record the finding and correct the rule |
| Teardown scope | Drop database **and** roles **and** warehouses, guard both |

## What CoCo produced

### Local environment (was entirely absent)

`just`, `uv`, `pre-commit` and `gh` were **all missing** — the whole documented workflow runs through
`just`, so nothing in `CONTRIBUTING.md` was executable. Installed `just 1.58.0`, `uv 0.12.17`,
`gh 2.101.0`; `snow 3.27.0` was already present. Set `user.name`, `user.email`, `user.initials=jp`;
ran `just bootstrap` (17 packages, both git hooks). Set the default `snow` connection — there was
**none**, so the justfile's `env_var_or_default(…, "default")` resolved to a connection that did not
exist. Exported `SNOWFLAKE_DEFAULT_CONNECTION_NAME` in `~/.zshrc`.

### Capability re-verification on the new account

| Verified working | Method |
| --- | --- |
| `AI_COMPLETE` / `SNOWFLAKE.CORTEX.COMPLETE`, `claude-sonnet-4-5` | Executed, returned `ok` |
| Same, `llama3.1-8b` | Executed, returned `ok` |
| `AI_EXTRACT` | Executed on inline turbine text |
| `SNOWFLAKE.ML` classes | `show classes in schema snowflake.ml` — all five present |
| `CREATE COMPUTE POOL` | Compiles |
| `CORTEX_ENABLED_CROSS_REGION = ANY_REGION`, `ENABLE_CORTEX_ANALYST = true` | `show parameters` |

Six capabilities carried over from the old account could **not** be re-proven — semantic view, Cortex
Search, dynamic table, agent, Streamlit, `AI_PARSE_DOCUMENT` — because each needs a database to exist.
Deferred to `just verify`. `SNOWFLAKE_INTELLIGENCE` does not exist in this account.

### `snow` CLI behaviour, established by execution

Four probes in `/tmp`, all cleaned up:

| Probe | Result |
| --- | --- |
| `&{ var }` templating | Works, but **deprecated** — warns, use `<% var %>` |
| `<% var %>` templating | Works |
| Undefined variable | **Hard rendering error**, not an empty substitution — this is what makes `NFR-6` safe |
| 3-statement file, failure in the middle | Each statement echoed; **aborts** the remainder; **exits 1** |

### Files written — 846 new lines across 11 files

| File | Lines |
| --- | --- |
| `sql/00_setup/01_account_roles.sql` | 95 |
| `sql/00_setup/02_account_warehouses.sql` | 66 |
| `sql/00_setup/03_account_database.sql` | 51 |
| `sql/00_setup/10_schemas.sql` | 70 |
| `sql/00_setup/11_grants.sql` | 207 |
| `sql/00_setup/12_grants_dev.sql` | 72 |
| `sql/00_setup/README.md` | 110 |
| `sql/90_teardown/01_database.sql` | 37 |
| `sql/90_teardown/02_warehouses.sql` | 30 |
| `sql/90_teardown/03_roles.sql` | 42 |
| `sql/90_teardown/README.md` | 66 |

Modified: `justfile` (+125/−12 — implemented `deploy-foundation`, `sql`, `teardown`; added the
`database` variable; removed three `_todo` placeholders), `STATE.md` (+34/−12), `deployment.md`
(+27/−10), `AGENTS.md` (+8/−2).

Statement counts: 22 roles/grants, 11 warehouse, 4 database, 12 schema, 70 grant, 18 dev-grant.

**Audits run against the scripts:** `<% database %>` used 24 times, zero hardcoded database names
(`NFR-6`); all four prohibited patterns (`CREATE OR REPLACE DATABASE`, `TO ROLE PUBLIC`,
`ALTER ACCOUNT`, `SET DEFAULT_ROLE`) present **only inside explanatory comments**, zero in executable
SQL; all five justfile guards tested and refusing correctly; `just check` green throughout.

## What a human changed

**The human blocked every design decision that the plan did not already settle, and was right to.**
Twelve decisions went through an explicit question gate rather than being assumed — the full list is
in [Prompt](#prompt). Three mattered more than the rest:

1. **Elevated-stage role.** CoCo's default recommendation was to split the elevated stage across
   `USERADMIN` / `SECURITYADMIN` / `SYSADMIN` to demonstrate least privilege inside the bootstrap
   itself. The human chose plain `ACCOUNTADMIN` for the whole elevated stage. That is the better call:
   `NFR-3` governs *application* code, a one-time bootstrap is not application code, and the split
   would have added `use role` churn that obscures what the script does without changing what it can
   do.
2. **Teardown scope.** CoCo flagged that roles and warehouses are account-level and shared between
   developers' clones, and offered a narrower teardown. The human chose the full drop with both
   guards, which is what `T-52` actually demands — a judge running teardown must be left with no
   residue.
3. **Dev database.** `ADR-0008` says personal databases are zero-copy clones of `WIND_OPS_AI`, which
   does not exist yet. The human chose to build the dev database directly and defer cloning, avoiding
   a chicken-and-egg problem without amending the ADR prematurely.

The human also set the phase discipline — "wait for my response after every phase" and "don't assume
anything" — which is why the two plan contradictions below were surfaced as questions instead of being
silently resolved.

## What CoCo got wrong

| Error | How it was caught |
| --- | --- |
| **Ownership-transfer bug.** Put `drop schema if exists PUBLIC` in `10_schemas.sql`, to run as `WOA_ADMIN`. `GRANT OWNERSHIP ON DATABASE` transfers only the database object, **not** the schemas inside it, so `PUBLIC` stays owned by `ACCOUNTADMIN` and `WOA_ADMIN` cannot drop it | Caught by CoCo while reasoning through ownership before deploying, not by a test. Moved into `03_account_database.sql` where the owner actually is. Would have failed the first deploy |
| **Conflated two cost snapshots.** Overwrote `deployment.md`'s 16.75-credit figure with `STATE.md`'s 51.18, treating a disagreement between two documents as a contradiction when they were two snapshots taken at different times | Caught by CoCo immediately after the edit; both figures are now recorded with their scope |
| **Quoted unfiltered `QUERY_HISTORY`.** First read of today's DDL showed 407 `GRANT` and 204 `CREATE`, which appeared to contradict the "nothing deployed" claim | Grouping by `user_name` showed all of it is `SYSTEM` / `SNOWFLAKE` internal maintenance. Caught while writing *this* entry |
| **Assumed `GRANT` could be compile-checked.** `only_compile` wraps the statement in `EXPLAIN`, which rejects `GRANT` | Three compile attempts failed with `syntax error … unexpected 'grant'`. Consequence stated rather than hidden: **all 99 grant statements are syntactically unverified** until phase 4 executes them |
| **Wrong `CREATE APPLICATION SERVICE` grammar** when re-probing `ADR-0020` | Compile error on `in compute pool` / `from specification`. The probe therefore failed on *syntax*, not on the trial-account feature gate, so `ADR-0020` is recorded as **inconclusive** on this account rather than re-confirmed |

**Two contradictions in the plan that CoCo found but did not resolve alone.** Both are recorded in
`STATE.md` §7 and both need a `04-code.md` correction:

1. **The role hierarchy in `04-code.md` §6 cannot be built as drawn.** The mermaid has
   `WOA_APP --> {WOA_RMC, WOA_PLANNER, WOA_EXEC, WOA_TECH}`, but the grant table on the same page
   defines `WOA_EXEC` as "`SELECT` on `SERVING` only" and `WOA_TECH` as "`SELECT` on the job-pack view
   only". Granting the personas *to* `WOA_APP` gives `WOA_APP` the approval and suppression
   procedures, breaking `FR-35`/`T-33`; granting `WOA_APP` *to* all four gives `WOA_EXEC` and
   `WOA_TECH` access to `ML`, `CURATED` and `ENGINE`, breaking their own "notably lacks" cells. Either
   reading breaks two of four roles.
2. **`WOA_ADMIN` needs `CREATE DATABASE`, which its own row forbids.** It must own the database while
   "notably lacking account-level privileges", but `CREATE DATABASE` is account-level.

**One documented team rule contradicted by evidence.** `AGENTS.md` and the justfile both said batched
multi-statement SQL "silently skips statements — this cost us a debugging cycle during planning". Not
reproducible on `snow` CLI 3.27: statements are echoed, the first failure aborts the rest, exit code is
1. CoCo raised this rather than quietly ignoring the rule; the human approved correcting it. Both
files now state the intent ("no statement may fail unnoticed") and cite the evidence.

## Cost

| Source | Credits |
| --- | --- |
| CoCo token credits (`CORTEX_CODE_DESKTOP_USAGE_HISTORY.TOKEN_CREDITS`) | 9.2415 |
| Warehouse (`WAREHOUSE_METERING_HISTORY.CREDITS_USED`) | 1.4447 |
| **Cumulative total, this account** | **≈ 10.69** |

Both sources summed per `AGENTS.md`. **This session contributed 5.9644 CoCo credits** (53 requests,
11,167,494 tokens) and close to zero warehouse credits — every Snowflake statement was a `SELECT`,
`SHOW`, `DESCRIBE` or `EXPLAIN` on `COMPUTE_WH`, and no object was created.

The ≈51.18 credits spent during planning were charged to the **old** account `BGTCHIX-UZ86048` and do
not count against this account's $400. `ACCOUNT_USAGE` lags by up to three hours, so the final
requests of this session are not yet reflected.

A note for future entries: `AGENTS.md` names the CoCo credit column as `CREDITS`, which **does not
exist** — it is `TOKEN_CREDITS`. The first query written from the documented name failed with
`invalid identifier 'CREDITS'`.

## Traceability

Branch `feat/jp/deploy-foundation`, forked from `main` at `2f55cf6`. **No commits yet** — the human
asked to review before committing, per `CONTRIBUTING.md` Path A ("stop before committing so I can
review"). `STATE.md` §2 claims `US-44`, `US-45` · `T-50`, `T-52` against this branch.

| File | New / modified |
| --- | --- |
| `sql/00_setup/` — 6 `.sql` + `README.md` | New |
| `sql/90_teardown/` — 3 `.sql` + `README.md` | New |
| `justfile` | Modified — 3 recipes implemented, 3 `_todo` removed |
| `STATE.md` | Modified — §2 claim, §5 account, §6 budget, §7 deviations |
| `docs/03-architecture/deployment.md` | Modified — v0.3, §1 account, §6 cost, `Q-41` re-opened |
| `AGENTS.md` | Modified — batching rule corrected |
| `~/.zshrc`, `~/.snowflake/config.toml` | Modified outside the repo — env var and default connection |

**Phases 4 and 5 remain**: deploy to `WIND_OPS_AI_DEV_JP`, run it twice for `T-52`, assert the
`WOA_AGENT` negatives for `T-50`, re-verify the six deferred capabilities, tear down — then implement
`just verify` and write the follow-up evidence entry. Eleven justfile placeholders still exit
non-zero, including `verify`.
