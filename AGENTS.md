# Agent instructions for this repository

Read this before doing anything. Keep it short — it is loaded into every session.

**Human contributors:** [`CONTRIBUTING.md`](CONTRIBUTING.md) is the workflow on one page, with prompts
to paste. This file is the rules those prompts rely on.

## What this project is

A 15-day, 4-person hackathon entry: a predictive-maintenance and OEE command center built on
Snowflake, for a fictional Indian wind-turbine OEM that also maintains the fleet it sells.

The plan under `docs/` is the source of truth for scope, architecture and decisions. Start
with `docs/README.md`.

## Session protocol

**The first and last thing you do.** Work is picked up by whichever teammate is free, mostly through
CoCo. [`STATE.md`](STATE.md) at the repo root is how a session hands off to the next one.

**First action of every session, before anything else:** run `just state` — it prints `STATE.md`, the
current branch, recent commits and open PRs. Read `STATE.md` in full. Do not start work that is
already claimed in §2.

**Last action of every session, before the final commit:** rewrite the sections of `STATE.md` your work
changed. A session that ends without updating it has not finished.

Five rules keep it from rotting into a second plan:

1. **Status, never intent.** IDs and state only — `US-12 done, T-8 green`. Never restate what a story
   *is*; link to it. When `docs/` and `STATE.md` disagree, `docs/` wins on what we are building,
   `STATE.md` wins on how far we got.
2. **Overwrite, never append.** Every section is replaced in place. It stays short enough to read in a
   minute, and a merge conflict then means something real: two people claimed the same work.
3. **Claim before you start.** Add your row to §2 *In flight* and push it before writing code. Clear it
   when the work merges.
4. **Nothing is "done" without its test ID.** A story is done when the test named in
   [`testing-and-validation.md`](docs/07-quality/testing-and-validation.md) passes — not when the code
   looks right.
5. **§5 is the account, not the repo.** Update *What actually exists in Snowflake* whenever you create
   or drop an object. Git cannot tell the next person this, and a stale §5 costs more time than
   anything else in the file.

`STATE.md` holds only the present. **History lives in the evidence entries** (see
[Evidence](#evidence)) — one immutable file per session, which is also why `STATE.md` never needs a log.

## Authoritative documents — do not rewrite

| File | Status |
| --- | --- |
| `docs/00-hackathon/problem-statement.md` | The brief as given |
| `docs/00-hackathon/terms-and-conditions.md` | Organiser rules |
| `docs/01-business/company-profile.md` | The scenario: company, fleet, roles, systems, KPIs |

If one of these looks wrong, say so and propose the change. Never edit them silently.

`STATE.md` is the opposite — the one file **everybody** rewrites, every session.

## How we work

- **Branches:** `<type>/<initials>/<short-desc>`, e.g. `feat/nk/alarm-correlator`.
  Types: `feat`, `fix`, `chore`, `docs`, `spike`. **A pre-commit hook rejects anything else** — it is
  a mechanical rule, not a convention. Never work directly on `main`.
- **Commits:** Conventional Commits (`feat: …`, `fix: …`).
- **Never commit to `main`.** A pre-commit hook blocks it. Open a PR with `just pr`; it needs
  2 approvals.
- **Before a PR:** `just check` (lint, format, tests) must pass. Do not skip hooks.
- **Python:** `uv` for dependencies, `just` for commands. Add dependencies with `uv add`, and
  ask before introducing a new one.
- **Docs change in the same PR as the code** they describe.

## Engineering rules from the plan

These are decisions, not preferences. See the ADRs in `docs/03-architecture/decisions/`.

1. **Deterministic code decides state; the model explains it.** Feasibility, constraints,
   grouping and arithmetic belong in SQL or Snowpark that can be unit-tested. An agent may
   rank and explain what the engine produced — it never invents a window, a crew, a part or
   an incident.
2. **Every write action is approval-gated, idempotent and audited.** Agents get no destructive
   tools at all.
3. **Nothing is auto-suppressed** on an asset with elevated risk, or for a safety-critical
   alarm code. Suppression is always reversible and visible.
4. **Explain everything:** predictions carry their drivers, answers carry their citations.
5. **Synthetic data only.** Label it as synthetic. No real company, customer or personal data.
6. **Least privilege.** No ACCOUNTADMIN in application code. No secrets in git — credentials
   come from `~/.snowflake/connections.toml`, Snowflake secrets or the OS keychain.

## Snowflake conventions

Naming for databases, schemas, tables, procedures, warehouses and roles is defined in
`docs/03-architecture/04-code.md` once the plan exists. Follow it. If it does not exist yet,
propose a scheme and record it there rather than inventing names per file.

Developer work happens in a personal clone (`WIND_OPS_AI_DEV_<INITIALS>`), never directly in
the shared database.

## Evidence

The hackathon requires CoCo in every phase, and judges look for proof. **After every meaningful CoCo
session, write one new file** — never append to an existing one:

```
docs/06-coco/evidence/<phase>/<NN>-<short-slug>.md
```

`<phase>` is exactly one of `planning`, `development`, `execution`, `testing`. `<NN>` is a
zero-padded sequence within that phase (`01`, `02`, …). Create the folder if it is missing.

Every entry carries these seven sections, in this order. The format and a worked example are in
[`docs/06-coco/evidence/README.md`](docs/06-coco/evidence/README.md) and
[`planning/01-plan-generation.md`](docs/06-coco/evidence/planning/01-plan-generation.md) — follow the
example rather than inventing a new shape.

| Section | Content |
| --- | --- |
| **Verifiable identifiers** | Mandatory. CoCo `session_id`, workspace and thread ID, account, user, model, any subagent session IDs, plus request count, tokens and credits from `ACCOUNT_USAGE`. Include the SQL to reproduce them |
| **Prompt** | Verbatim, or a faithful summary, plus any mid-session human instructions |
| **What CoCo produced** | Files, objects and findings, with paths and line counts |
| **What a human changed** | The honest field. What was corrected, rejected or rewritten, and why |
| **What CoCo got wrong** | Errors and dead ends, and how they were caught |
| **Cost** | CoCo token credits **and** warehouse credits, summed |
| **Traceability** | Branch, commit or PR |

Then add the entry to the index table in `docs/06-coco/evidence/README.md`.

**Self-reported prose is not evidence.** Identifiers come from the session file at
`~/.snowflake/cortex/conversations/<workspace>/<session>.json` and from
`SNOWFLAKE.ACCOUNT_USAGE.CORTEX_CODE_DESKTOP_USAGE_HISTORY` (or `..._CLI_...` for CLI sessions), so a
judge can confirm any entry against Snowflake's own telemetry.

**Credit accounting.** Always sum both sources. CoCo token credits are not in
`WAREHOUSE_METERING_HISTORY`, and warehouse metering alone under-reported the planning phase by about
ten times.

## Deployment

**Every change to Snowflake goes through a `just` recipe.** `just --list` shows them grouped; the
`snowflake` group is the whole deployment surface. No exceptions, including for "just one quick
`ALTER`" — a one-off statement typed into a worksheet is invisible to the next person, unreviewable,
and unreproducible by a judge.

- **`just target` before anything.** It prints the database and connection a run will hit. If that is
  not what you expected, stop.
- **Deploy to the team account `JKDRJBB-MW27072` — every developer, every time.** That is the account
  the demo and the judges use; a stack that exists only in someone's trial account is not deployed.
  Before any recipe, `snow connection test` must report account `JKDRJBB-MW27072`: set
  `SNOWFLAKE_DEFAULT_CONNECTION_NAME` to your connection for it, and let `just target` confirm it.
  Personal or trial accounts (for example `BGTCHIX-UZ86048`) are for experiments only. Nothing built
  there counts as done until it has been redeployed to `JKDRJBB-MW27072` through the same recipes and
  `just verify` passes there. Evidence and `STATE.md` §5 record the account a result came from.
- **`env=dev` is the default** and resolves to your personal clone `WIND_OPS_AI_DEV_<INITIALS>`
  (set `git config user.initials nk` once). `env=shared` targets the team database and must be typed
  deliberately, every time.
- **Ad-hoc SQL still goes through `just sql <file>`** — a file in git, parameterised, never a
  literal database name. **No statement may fail unnoticed.** This rule was originally "one statement
  per call", on the belief that batched multi-statement SQL silently skips statements. That is not
  reproducible on `snow` CLI 3.27: `snow sql -f` echoes every statement, aborts at the first failure,
  and exits non-zero — verified by execution, recorded in [`STATE.md`](STATE.md) §7. Grouped `.sql`
  files are therefore fine. Do not batch through a path that has *not* been checked for this.
- **Recipes are idempotent.** Safe to run twice. `CREATE OR ALTER` / `IF NOT EXISTS`, never
  "drop then create" on anything holding data. `just update` is the everyday command and must never
  drop or recreate a table with rows in it.
- **A placeholder recipe exits non-zero.** If you implement one, remove its `_todo` — and if you need
  a new deployment step, add a recipe rather than a script somebody has to know about. A deploy command
  that silently succeeds without deploying is worse than one that is missing.
- **After deploying, update [`STATE.md`](STATE.md) §5** — what exists in the account is the one thing
  git cannot tell the next person.

## Definition of done

- Acceptance criteria met, with **the test named in the plan** passing — not just a test
- `just check` green
- Docs and ADRs updated
- **Evidence entry written for the session, with its identifiers, and indexed**
- **[`STATE.md`](STATE.md) updated: your §2 claim cleared, gates and §5 Snowflake state current**
- No secrets; least-privilege roles
- Reviewed by 2 teammates
