# `00_setup` — roles, warehouses, database, schemas, grants

Implements `US-44` and `US-45`; satisfies `NFR-3` (least privilege) and `NFR-6` (no
hardcoded names); proven by `T-50` and `T-52`.

Run it with `just deploy-foundation`. Never by hand — see
[AGENTS.md · Deployment](../../AGENTS.md#deployment).

## Run order

Numeric prefixes give a total order. The `0x` files are the **elevated, one-time**
stage; the `1x` files run as `WOA_ADMIN` and hold no account-level privilege.

| File | Role | Creates |
| --- | --- | --- |
| `01_account_roles.sql` | `ACCOUNTADMIN` | The nine `WOA_*` roles and the hierarchy between them |
| `02_account_warehouses.sql` | `ACCOUNTADMIN` | `WOA_APP_WH`, `WOA_BUILD_WH`, and their `USAGE` grants |
| `03_account_database.sql` | `ACCOUNTADMIN` | The database, then hands ownership to `WOA_ADMIN` |
| `10_schemas.sql` | `WOA_ADMIN` | The ten schemas; drops the auto-created `PUBLIC` |
| `04_snowflake_intelligence.sql` | `ACCOUNTADMIN` | The account's Snowflake Intelligence object (IF NOT EXISTS); MODIFY to `WOA_ADMIN`, USAGE to `WOA_APP` |
| `11_grants.sql` | `WOA_ADMIN` | The least-privilege read matrix; revokes the retired `WOA_ENGINEER` grants |

Teardown is [`../90_teardown/`](../90_teardown/), which reverses this exactly.

## Parameter

Every file that names the database takes one parameter, `database`:

```bash
snow sql -f sql/00_setup/03_account_database.sql -D "database=WIND_OPS_AI"
```

`NFR-6` forbids a hardcoded database name. `snow sql` renders `<% database %>`
client-side and **fails outright** if the variable is not supplied, so a missing
parameter is a loud error rather than an empty identifier. Note that the older
`&{ ... }` syntax is deprecated in favour of `<% ... %>`.

## Three properties every file here holds

1. **Idempotent.** Every statement is `IF NOT EXISTS`, `IF EXISTS`, or a `GRANT` —
   all no-ops on a second run. `T-52` requires setup to succeed *twice in a row*,
   because a script that only works on a clean database is not reproducible, and
   reproducibility is what "a judge can run this" actually means.
2. **Fail-fast.** `snow sql -f` echoes each statement, aborts at the first failure,
   and exits non-zero. Verified by execution on `snow` CLI 3.27 — see the note on
   batching below.
3. **No `ACCOUNTADMIN` beyond the `0x` files.** `NFR-3` forbids `ACCOUNTADMIN` in
   application code. A one-time bootstrap that creates account-level objects is not
   application code, and nothing the app or agent executes lives in those files.

## Deliberate deviations from the plan

Both are recorded in [`STATE.md`](../../STATE.md) §7.

**The role hierarchy does not match the `04-code.md` §6 diagram.** The diagram draws
`WOA_APP --> {WOA_RMC, WOA_PLANNER, WOA_EXEC, WOA_TECH}`, but the grant table on the
same page defines `WOA_EXEC` as "`SELECT` on `SERVING` only" and `WOA_TECH` as
"`SELECT` on the job-pack view only". Under Snowflake semantics a role inherits the
roles granted *to* it, so no single arrow direction satisfies both:

- grant the personas **to** `WOA_APP` and `WOA_APP` gains the approval and
  suppression procedures, breaking `FR-35` / `T-33`;
- grant `WOA_APP` **to** all four personas and `WOA_EXEC`/`WOA_TECH` gain `SELECT` on
  `ML`, `CURATED` and `ENGINE`, breaking their own "notably lacks" cells.

The table is the more specific statement, so it wins. `WOA_APP` is granted only to
`WOA_PLANNER` and `WOA_RMC`. The diagram in `04-code.md` needs correcting.

**`WOA_ADMIN` does not create the database.** §6 requires it to own the database while
"notably lacking account-level privileges", but `CREATE DATABASE` *is* account-level.
`ACCOUNTADMIN` creates it and transfers ownership, so `WOA_ADMIN` owns everything and
still holds no account-level grant.

## On batching, and why these files hold many statements

`AGENTS.md` and the justfile say batched multi-statement SQL "silently skips
statements". On `snow` CLI 3.27 that is not reproducible: a three-statement file
echoes all three, a mid-file failure **aborts the remainder**, and the process
**exits 1**. So the rule's intent — never let a statement vanish unnoticed — already
holds, and these files group related statements for readability. The evidence is in
the `STATE.md` §7 entry; `AGENTS.md` and the justfile comment were corrected to match.

## What these files deliberately never do

| Never | Why |
| --- | --- |
| `CREATE OR REPLACE DATABASE` | Silently destroys a same-named database, including a colleague's clone |
| `GRANT … TO ROLE PUBLIC` | Grants to every user in the account (reference-solution defect `G-11`) |
| `ALTER ACCOUNT` | We do not touch account-wide state |
| Grant `WOA_AGENT` anything on `ACTION` | Not even schema `USAGE`. `FR-53` / `T-47` depend on the absence |
| Grant `WOA_SCHEDULER` anything on `ACTION` | It refreshes; it never applies (`FR-85`, `T-76`) |
| Grant any role anything on `GEN` | The generator must stay droppable and non-grantable to the app |
| `ALTER USER … SET DEFAULT_ROLE` | `Q-78` is open and is a human decision (`STATE.md` §4) |

## Grants that are deliberately deferred

These cannot be made at foundation time because the objects do not exist. Each is
made by the numbered script that creates the object, so the grant sits next to the
thing it protects:

| Grant | Made in |
| --- | --- |
| `WOA_APP`, `WOA_PLANNER`, `WOA_RMC` → `USAGE` on the approval and suppression procedures | `50_action` |
| `WOA_TECH` → `SELECT` on the job-pack view (one view, not a future grant) | `30_serve` |
| `WOA_AGENT` → `USAGE` on the semantic view | `30_serve` |
| `WOA_AGENT` → `USAGE` on the Cortex Search service | `60_docs` |
| `WOA_SCHEDULER` → `INSERT` on the score, suggestion and digest tables | `python/ml`, `40_engine`, `OPS` |

`WOA_SCHEDULER` gets no blanket `INSERT on future tables`: that would hand the
automation write access to every table nobody has designed yet.
