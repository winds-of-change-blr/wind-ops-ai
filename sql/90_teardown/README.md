# `90_teardown` — the exact reverse of `00_setup`

Implements `US-44`; proven by `T-52` ("setup succeeds twice in a row in a clean
database, **and teardown removes everything**").

Run it with `just teardown`. **Destructive.** It drops the team database the
demo runs from, so the recipe requires you to type the database name **and** the account name.

## Run order

The reverse of setup. Order matters: objects before their owners.

| File | Drops | Why here |
| --- | --- | --- |
| `01_database.sql` | The database, and everything inside it | `DROP DATABASE` removes schemas, tables, views, procedures and dynamic tables for us |
| `02_warehouses.sql` | `WOA_APP_WH`, `WOA_BUILD_WH` | A role that owns a warehouse cannot be dropped cleanly |
| `03_roles.sql` | The nine `WOA_*` roles, leaves first | Last, because everything else was owned by or granted to them |

## These files drop account-level objects

Warehouses and roles are account-level. Running teardown removes `WOA_APP_WH`, `WOA_BUILD_WH`
and the nine roles for everyone in the account, and the team database with them.

That is deliberate. `T-52` requires teardown to remove *everything* setup created,
and a judge running this in their own account must be left with no residue. The
protection is in the recipe, not in the SQL:

- `_resolve-db` refuses any account other than `JKDRJBB-MW27072`; there is no override flag
- it requires the database name and the account name to be **typed by hand** before proceeding

Running these `.sql` files directly bypasses both. Don't.

## What `DROP DATABASE` does not reach

`deployment.md` §5 gives the order as app → agent → search service → ML instances →
dynamic tables → views → procedures → tables → schemas → database → warehouses →
roles. Everything from *app* through *schemas* lives inside the database, so
`DROP DATABASE` handles it in dependency order. Enumerating those objects here would
be a list that goes stale the moment a later script adds one.

Objects that live **outside** the database must be added to `01_database.sql` as they
are built:

| Object | Lives in | Added by |
| --- | --- | --- |
| The Snowflake Intelligence object | Account level. Our agent is removed from it; the object is dropped only if no other agent is listed | `00_setup/04`, `70_agent/02` |
| Compute pools, image repositories | Account level | Only if SPCS is ever used (`ADR-0020` says not) |
| Notification integrations | Account level | `M11`, if it survives the cut order |

None of these exist at foundation, which is why teardown is currently three short
files. **If you add an object outside the database, add its drop here in the same
PR** — otherwise `T-52` passes while leaving residue behind, which is worse than a
failing test.

## Recoverability

`DROP DATABASE` moves the database into Time Travel rather than deleting it, so a
mistaken teardown is recoverable with `UNDROP DATABASE <name>` inside the retention
window. Dropped roles and warehouses are **not** recoverable — re-run
`just deploy-foundation` to recreate them.

## Idempotent

Every statement is `DROP … IF EXISTS`, so teardown can run twice without error.
`T-52` needs a clean database afterwards, and "already gone" is clean.
