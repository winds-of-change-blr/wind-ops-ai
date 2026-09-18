# CoCo CLI setup

> **Status:** Draft v0.1 · **Owner:** _TBD (CoCo champion)_ · **Last updated:** 2026-09-18
>
> Everyone on the team runs this once. It takes about 20 minutes. Flags and paths change
> between versions — if a command below disagrees with `cortex --help`, trust the CLI and fix
> this page.

## What you need

| Step | Why |
| --- | --- |
| Snowflake CLI | CoCo reuses its connection profiles |
| CoCo CLI | Runs the prompts and builds |
| Account grants | Without `CORTEX_USER` nothing works; without `EXECUTE AGENT TASK` automations don't |
| Sensible user defaults | **Automations run as your *default* role**, not the role you had active |
| Repo config (already committed) | Same agent behaviour for all four of us |

## 1. Install the CLIs

Snowflake CLI (you have `uv`, so use it):

```bash
uv tool install snowflake-cli
```

CoCo CLI (macOS/Linux/WSL; installs to `~/.local/bin`, already on your PATH):

```bash
curl -LsS https://ai.snowflake.com/static/cc-scripts/install.sh | sh
```

Verify both:

```bash
snow --version && cortex --version
```

## 2. Point at the right Snowflake connection

You already have connections configured in `~/.snowflake/connections.toml`
(`exkfafl-nw77746`, `cms`, `Hackathon`), but **no default is set**, so tools have to guess.

```bash
snow connection list
```

```bash
snow connection set-default Hackathon
```

```bash
snow connection test
```

Use the hackathon account here, not a work account. Everything an agent does runs as this
connection.

## 3. Account grants and user defaults

Run in Snowsight as ACCOUNTADMIN, once per user. Replace the placeholders.

```sql
GRANT DATABASE ROLE SNOWFLAKE.CORTEX_USER TO ROLE <WOA_ENGINEER>;
GRANT EXECUTE AGENT TASK ON ACCOUNT TO ROLE <WOA_ENGINEER>;
ALTER USER <YOU> SET DEFAULT_ROLE = <WOA_ENGINEER>, DEFAULT_WAREHOUSE = <WOA_APP_WH>;
```

The `ALTER USER` line matters more than it looks: a CoCo automation runs with your **default**
role and default secondary roles. If your default is `PUBLIC`, scheduled runs will fail with
confusing permission errors while your interactive session works fine.

Some accounts use `SNOWFLAKE.CORTEX_AGENT_USER` instead — check which exists before granting.

## 4. First run

```bash
cortex
```

A setup wizard appears on first launch. Pick the `Hackathon` connection. Then, inside the
session, confirm the basics:

- `/model` — see and switch models. `auto` is the default and is usually right; switch to a
  stronger model for architecture and planning work, and back for routine edits.
- `/skill` — list bundled skills and invoke one by name.
- `/mcp` — MCP server status.

## 5. Repo-side configuration (already committed — nothing to do)

| File | Purpose |
| --- | --- |
| [`AGENTS.md`](../../AGENTS.md) | Project rules every agent session loads: branch and commit conventions, the read-only documents, the engineering rules, definition of done |
| [`prompt/generate-plan.md`](../../prompt/generate-plan.md) | The staged prompt that produces the plan |
| [`skills/`](../../skills/README.md) | Where our own skills live |

Always start CoCo **from the repository root** so it picks these up:

```bash
cd ~/niraj/git/winds-of-change/wind-ops-ai && cortex
```

## 6. Project skills

Write skills in [`skills/`](../../skills/README.md), one folder per skill with a `SKILL.md`.
CoCo discovers project skills from a workspace folder and scans for `SKILL.md` files.

**Confirm the discovery path on your version** before assuming it works:

```bash
cortex --help | grep -i skill
```

If CoCo does not find skills in `skills/`, place (or symlink) them where it does scan, and
update this section with what actually worked.

## 7. MCP connectors (optional, Preview)

Config lives at `~/.snowflake/cortex/mcp.json`. Use the CLI rather than editing by hand, so
secrets land in the OS keychain:

```bash
cortex mcp add <name> <command> [args...]
```

```bash
cortex mcp list
```

Notes that will save you time:

- `node` and `npx` are available on this machine; Docker is not, so prefer npx-based servers.
- Never hardcode a token in `mcp.json` — use environment variables or OAuth.
- Tool output is capped (about 50 KB) and tools time out around 60 s by default.
- **Automations cannot use your local MCP servers.** A scheduled run only sees Snowflake-side
  servers attached with `--mcp <database.schema.name>`. Our Slack-delivery automations depend
  on this — see [the CoCo usage plan](coco-usage-plan.md).

## 8. Automations (Preview)

```bash
cortex automation create --name shift-briefing --prompt "<the prompt>" --schedule "daily at 7am" --timezone Asia/Kolkata --dry-run
```

`--dry-run` prints the task SQL without creating anything. Drop it when the output looks right.
Then:

```bash
cortex automation list
```

```bash
cortex automation doctor shift-briefing
```

Limits: minimum frequency is one hour, schedules are time-based only, and run history is kept
for about two months.

## 9. Getting good results (the part that actually matters)

- **Point at files, don't paste them.** "Read `prompt/generate-plan.md` and follow it" beats
  pasting 200 lines; the file stays the single source of truth.
- **One task per session.** Long sessions accumulate context and drift. Start fresh for a new
  workstream.
- **Let it use skills.** Describe the goal ("build a dynamic table pipeline") and CoCo loads
  the right bundled skill; name one with `/skill` when you want a specific one.
- **Work in a personal clone** (`WIND_OPS_AI_DEV_<INITIALS>`), never the shared database.
- **Keep `AGENTS.md` short.** It loads every session; bloat costs you context and speed.
- **Review before you commit.** The pre-commit hooks are the backstop, not the reviewer.
- **Capture evidence as you go** — transcripts are much harder to reconstruct later:

```bash
cortex conversations transcript <thread_id>
```

## 10. Verification checklist

- [ ] `snow --version` and `cortex --version` both work
- [ ] `snow connection test` passes against the hackathon account
- [ ] Default connection set; default role and warehouse set on your user
- [ ] `cortex` launches from the repo root and acknowledges `AGENTS.md`
- [ ] `/skill` lists bundled skills
- [ ] A trivial automation created with `--dry-run` shows sensible SQL
- [ ] One evidence entry written to `docs/06-coco/evidence/`
