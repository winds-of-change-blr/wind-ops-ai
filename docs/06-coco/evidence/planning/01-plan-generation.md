# Planning — 01 · Plan generation

> **Phase:** Planning · **Date:** 2026-09-17 → 2026-09-18 IST · **Surface:** Cortex Code Desktop ·
> **Participants:** NK (human), CoCo (agent) · **Branch:** `docs/nk/plan-generation`

---

## Verifiable identifiers

Snowflake can independently confirm this session from its own telemetry. These are not self-reported
claims — every value below is either a local session identifier or queryable from
`SNOWFLAKE.ACCOUNT_USAGE`.

| Item | Value |
| --- | --- |
| **CoCo session ID** | `04d1ee7a-0e99-44de-afb6-40f838e591e6` |
| Session title | "Hackathon Plan Generation" (AI-generated) |
| Workspace ID | `936de335e0f95bdb62958c348cc76e08` |
| Thread ID | `263509512` |
| Account | `BGTCHIX-UZ86048` · host `bgtchix-uz86048.snowflakecomputing.com` |
| User | `NIRAJ` (`USER_ID` 1), role `ACCOUNTADMIN` |
| Orchestration model | `claude-opus-5`, `inference_region: global` |
| Mode | `agent`, model selection `auto-intelligent` |
| Working directory | `/Users/nirajkumar/niraj/git/winds-of-change/wind-ops-ai` |
| Local transcript | `~/.snowflake/cortex/conversations/936de335e0f95bdb62958c348cc76e08/04d1ee7a-0e99-44de-afb6-40f838e591e6.history.jsonl` |

**Subagent sessions** — the two reference-solution forensics agents ran as separate, separately
logged sessions:

| Subagent session ID | Task |
| --- | --- |
| `5abce7f4-2281-43cc-b804-b1d1088d0209` | Forensic analysis of `setup.sql` (3,265 lines) |
| `8e017bb9-6cbf-44f4-8507-50d1300d65bf` | Forensic analysis of the Streamlit app (~4,700 lines) |

### Server-side telemetry

Cortex Code Desktop usage is recorded per request in
`SNOWFLAKE.ACCOUNT_USAGE.CORTEX_CODE_DESKTOP_USAGE_HISTORY`, with a `REQUEST_ID` per turn, token
counts by model, and credits. For this planning window:

| Measure | Value |
| --- | --- |
| Requests logged | **126** |
| First request | 2026-09-17 21:31:43 UTC |
| Last request | 2026-09-18 00:17:56 UTC |
| Tokens consumed | **24,064,327** |
| CoCo token credits | **15.0720** |

Reproduce with:

```sql
select request_id, usage_time, token_credits, tokens,
       tokens_granular::string as model_breakdown,
       metadata::string as meta
from snowflake.account_usage.cortex_code_desktop_usage_history
where user_name = 'NIRAJ' and usage_time >= '2026-09-17'
order by usage_time;
```

Sample `REQUEST_ID`s from this session, for spot-checking:
`f7880f9a-abad-409c-8a91-d1d835681e63`, `359b918a-df51-47d0-ab9e-acb693b602ba`,
`981d3cae-6b77-41dd-9178-9b60f4377323`, `67c266ca-d8ee-44d4-9c9e-bce73cca11b9`.

The capability probes in §Research are separately verifiable in
`SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY` for 2026-09-17, including the `CREATE`/`DROP` statements for
`NK_CAP_PROBE` and `SNOWFLAKE_INTELLIGENCE.AGENTS.PROBE_AGENT`.

## Prompt

Driven by [`prompt/generate-plan.md`](../../../../prompt/generate-plan.md), invoked as:

> Read AGENTS.md, then prompt/generate-plan.md, and follow the prompt. Before you begin, confirm you
> have read the three given documents it names: `docs/00-hackathon/problem-statement.md`,
> `docs/00-hackathon/terms-and-conditions.md`, and `docs/01-business/company-profile.md`. Work on a
> branch named `docs/nk/plan-generation`. Do not commit to main. Start with Stage 0: summarise the
> scenario back to me in five lines, ask your blocking questions, then stop and wait.

The prompt file sets the rules the run had to obey: research before writing, cite real-world facts,
verify tool behaviour against the platform, five-part requirement readiness, flag duplication,
deterministic code decides state, approval-gated writes, recommend one option per decision, respect
capacity, degraded mode for every core dependency, Mermaid diagrams, and the three given documents
read-only.

Subsequent human instructions during the run:

| Turn | Instruction |
| --- | --- |
| 2 | Answered Stage 0 questions: reference solution URL, event page, team, account |
| 3 | 4th member undecided; **2 h/day**; **$400** budget with an alert per $100; stop chasing the edition; keep skills in-repo |
| 4 | **Park the capacity analysis.** Record hours as an open question in the RAID log and move on |
| 5 | **No correction to `terms-and-conditions.md`; `problem-statement.md` takes priority.** Proceed |
| 6–7 | Approve Stage 2, then Stage 3 |
| 8 | "finish all entire planning" — run Stages 4, 5 and 6 to completion |

## What CoCo produced

### Research (Stage 1)

| Artefact | Detail |
| --- | --- |
| Reference-solution forensics | Read **all 23 files** of `Snowflake-Labs/sfguide-getting-started-with-predictive-maintenance` — `setup.sql` (3,265 lines), 15 Python files, `line_visualization.html` (477 lines) — and checked every marketing claim against the code |
| Contest ground truth | Located the event page and the contest's **own Official Rules**, which the repo's `terms-and-conditions.md` was not based on |
| Live capability verification | Executed probes in account `BGTCHIX-UZ86048` and cleaned up afterwards |

**Key findings.** The reference solution contains **no ML at all**: health score is a `CASE` on
`asset_id` plus `UNIFORM()`, RUL and failure probability are algebra on it, and failure mode is a
four-branch `CASE` in the Streamlit layer. Two arithmetic bugs compound it — a `ROWCOUNT` cap makes
telemetry end 2025-12-22, and `days_since_decay_start` evaluates to zero for all 180,000 rows, so no
signal precedes any failure. Failures are a 2% coin flip independent of all telemetry, making the
shipped `ML_FEATURE_STORE` label unlearnable from its own features. There is no document parsing, no
Cortex Search, no streams, tasks or dynamic tables, and the work-order buttons emit a toast and write
nothing.

**Capabilities verified working** (all probed, then dropped): `SNOWFLAKE.ML.CLASSIFICATION`,
`SNOWFLAKE.ML.ANOMALY_DETECTION`, `CREATE SEMANTIC VIEW`, `CREATE CORTEX SEARCH SERVICE`,
`AI_PARSE_DOCUMENT`, `AI_EXTRACT`, `CREATE AGENT`, `CREATE DYNAMIC TABLE`, `AI_COMPLETE` with
`claude-sonnet-4-5`. Also found: `claude-4-sonnet`, `mistral-large2` and `openai-gpt-4.1` are rejected
as legacy, and `claude-sonnet-4-5` resolves **only** because `CORTEX_ENABLED_CROSS_REGION = ANY_REGION`.

### Documents (Stages 2–5)

25 files under `docs/`. The heaviest are
[`reference-solution-analysis.md`](../../../00-hackathon/reference-solution-analysis.md) (the
weight-bearing gap analysis), the functional set (`FR-1`…`FR-56`, `NFR-1`…`NFR-17`, all five-part
ready), the architecture set (C4 levels 1–4, deployment, cross-cutting concerns, 16 ADRs), and the
[RAID log](../../../08-delivery/raid-log.md) carrying 18 risks, 12 assumptions, 5 issues, 7
dependencies and 72 open questions.

### Cost

| Source | Credits |
| --- | --- |
| Cortex Code Desktop tokens | **15.0720** |
| Warehouse (capability probes, audit queries) | **1.6809** |
| **Total** | **≈16.75** |

**A correction worth recording.** Throughout the run, CoCo reported consumption using
`WAREHOUSE_METERING_HISTORY` only, and told the human "0.64 credits used" at the end of Stage 6. That
figure was real but incomplete: it omitted CoCo Desktop's own token credits, which are **roughly ten
times larger**. Planning alone consumed ≈16.75 credits of the $400 trial allowance. The human caught
this by asking what evidence Snowflake could actually track. `NFR-8`'s reporting must therefore sum
**both** sources, and the cost documents were corrected accordingly.

## What a human changed

| Change | Effect |
| --- | --- |
| **Parked the capacity analysis** after CoCo flagged 164 h estimated against ~90 h available | CoCo had raised it twice. The human's call: record it as a risk and stop debating. `R-1`, `Q-6` |
| **Refused to correct `terms-and-conditions.md`** despite CoCo finding six material contradictions with the Official Rules | `problem-statement.md` became the operative source. CoCo recorded the discrepancy as `I-1` rather than editing a read-only file |
| **Stopped the edition investigation** | CoCo had failed to read it two ways. Human parked it; design assumes the lowest capability set. `I-3` |
| Set budget policy: $400, alert per $100 | Became `NFR-8` and a cost section in every relevant document |
| Confirmed 2 h/day and three named members | Drove the whole project plan and the cut order |
| Decided skills stay in-repo for now | `Q-8` answered |

## What CoCo got wrong

| Error | How it was caught | Fix |
| --- | --- | --- |
| **Anchor-checking script was wrong.** First link check reported 13 broken anchors in the given files. The slug function collapsed whitespace runs, but GitHub maps *each* space to a hyphen — so `## 4. Fleet & geography` yields `4-fleet--geography` with a double hyphen | The given `company-profile.md` linked to its own headings with double hyphens, which contradicted the checker | Fixed the slug rule. Re-ran: **0 broken anchors**. The original report was a false positive |
| **Raised the capacity concern three times** across turns | The human said "park it" and then had to repeat it | Recorded once as `R-1` and dropped |
| Multi-statement SQL silently did not execute — a `CREATE TABLE` in a batch never ran, and a later probe failed with "object does not exist" | The dependent probe failed | Ran probes one statement at a time |
| Guessed the wrong companion repo initially (`sfguide-intelligent-jidoka-system-for-ev-manufacturing`) from a keyword search | Its description was EV manufacturing, not the guide's factory scenario | Searched again; confirmed the correct repo by matching README structure to the guide's screenshots |
| Two `AI_COMPLETE` probes failed because three model names are legacy | Error messages named the legacy models | Recorded the finding — it is now [ADR-0013](../../../03-architecture/decisions/README.md#adr-0013--orchestration-model-and-fallback) |
| **Under-reported cost by ~10x** for the entire run, by counting warehouse credits only and omitting CoCo Desktop token credits | The human asked what evidence Snowflake could track, which surfaced `CORTEX_CODE_DESKTOP_USAGE_HISTORY` | Corrected to ≈16.75 credits. `NFR-8` now requires summing both sources |
| **Collected no verifiable identifiers.** The first version of this entry was self-reported prose with no session ID, request IDs or server-side references — the weakest possible form of evidence for a criterion judged on proof | The human asked directly whether we were capturing anything Snowflake could track | Added the [Verifiable identifiers](#verifiable-identifiers) section. Made mandatory for all future entries |

The first row is worth keeping: CoCo's own verification tool was wrong, and it took the *given*
documents disagreeing with it to notice. Verification tooling needs verifying.

## Traceability

| Item | Value |
| --- | --- |
| Branch | `docs/nk/plan-generation` |
| Files added | 25 under `docs/` |
| Given files modified | **None.** `problem-statement.md`, `terms-and-conditions.md` and `company-profile.md` are byte-identical to their state at the start of the run |
| Verification | Stage 6 self-audit in [testing-and-validation.md](../../../07-quality/testing-and-validation.md) and the audit report in the Stage 6 summary |
