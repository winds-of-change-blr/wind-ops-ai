# Evidence entry template

> Copy this file to `docs/06-coco/evidence/<phase>/<NN>-<short-slug>.md` and fill it in. Delete these
> two quote lines and every `<…>` placeholder. Then add the entry to the index in
> [README.md](README.md).
>
> Rules in [AGENTS.md](../../../AGENTS.md#evidence). One file per session — never append to an
> existing entry.

---

# `<Phase>` — `<NN>` · `<Short title>`

> **Phase:** `<planning | development | execution | testing>` · **Date:** `<YYYY-MM-DD>` ·
> **Surface:** `<Cortex Code Desktop | CLI | Snowsight>` ·
> **Participants:** `<initials>` (human), CoCo (agent) · **Branch:** `<branch>`

---

## Verifiable identifiers

Read these from the session file:
`~/.snowflake/cortex/conversations/<workspaceId>/<session_id>.json`

| Item | Value |
| --- | --- |
| **CoCo session ID** | `<session_id>` |
| Session title | `<title>` |
| Workspace ID | `<workspaceId>` |
| Thread ID | `<thread.threadId>` |
| Account | `<account>` · host `<thread.accountHost>` |
| User | `<USER_NAME>`, role `<role_name>` |
| Orchestration model | `<model_name>`, `inference_region: <region>` |
| Mode | `<agent | plan>` |
| Working directory | `<path>` |
| Local transcript | `~/.snowflake/cortex/conversations/<workspaceId>/<session_id>.history.jsonl` |

**Subagent sessions** — delete this table if none were used.

| Subagent session ID | Task |
| --- | --- |
| `<subagentSessionId>` | `<what it did>` |

### Server-side telemetry

| Measure | Value |
| --- | --- |
| Requests logged | `<n>` |
| First request | `<timestamp>` UTC |
| Last request | `<timestamp>` UTC |
| Tokens consumed | `<n>` |
| CoCo token credits | `<n>` |

```sql
-- swap _DESKTOP_ for _CLI_ if the session ran in the CLI
select request_id, usage_time, token_credits, tokens,
       tokens_granular::string as model_breakdown,
       metadata::string as meta
from snowflake.account_usage.cortex_code_desktop_usage_history
where user_name = '<USER>'
  and usage_time between '<start>' and '<end>'
order by usage_time;
```

Sample `REQUEST_ID`s for spot-checking: `<id>`, `<id>`, `<id>`.

`<If SQL was executed, note that it is verifiable in ACCOUNT_USAGE.QUERY_HISTORY for the date, and
name the objects created or dropped.>`

## Prompt

`<Verbatim prompt, or a faithful summary if long.>`

Mid-session human instructions — delete if none.

| Turn | Instruction |
| --- | --- |
| `<n>` | `<what the human asked for or redirected>` |

## What CoCo produced

`<Files with paths and line counts. Snowflake objects created. Findings, with evidence.>`

## What a human changed

**The honest field.** An entry claiming nothing was changed is either a trivial task or an unreviewed
output, and a judge can tell the difference.

| Change | Effect |
| --- | --- |
| `<what the human corrected, rejected or rewrote>` | `<consequence, with the ID it became if any>` |

## What CoCo got wrong

Errors, dead ends and wrong turns. This section is more credible than a highlight reel, and it is
useful to us.

| Error | How it was caught | Fix |
| --- | --- | --- |
| `<what went wrong>` | `<who or what noticed>` | `<what changed>` |

## Cost

| Source | Credits |
| --- | --- |
| CoCo tokens | `<n>` |
| Warehouse | `<n>` |
| **Total** | `<n>` |

Both sources must be summed — CoCo token credits are **not** in `WAREHOUSE_METERING_HISTORY`.

```sql
select 'coco_tokens' as source, sum(token_credits) as credits
  from snowflake.account_usage.cortex_code_desktop_usage_history
  where usage_time between '<start>' and '<end>'
union all
select 'warehouse', sum(credits_used)
  from snowflake.account_usage.warehouse_metering_history
  where start_time between '<start>' and '<end>';
```

## Traceability

| Item | Value |
| --- | --- |
| Branch | `<branch>` |
| Commit / PR | `<sha or PR link>` |
| Files added or changed | `<n>` |
| Given files modified | `<None — or say which, and why the team approved it>` |
