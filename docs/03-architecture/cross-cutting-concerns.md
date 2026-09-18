# Cross-Cutting Concerns

> **Status:** Draft v0.1 · **Owner:** NK · **Last updated:** 2026-09-17
>
> Concerns that belong to no single component and would otherwise be nobody's job.

---

## 1. Security

| Concern | Approach | Requirement |
| --- | --- | --- |
| Privilege | Least privilege per role ([04-code.md §6](04-code.md#6-roles)). No `ACCOUNTADMIN` in application code | `NFR-3` |
| Agent capability | `WOA_AGENT` holds no write grant anywhere and none at all on `ACTION`. Enforced by grant, not prompt | `FR-53`, `NFR-2` |
| Generated SQL | Validated against a read-only operation allowlist and permitted-object list **before** execution | `FR-54` |
| Injection | No SQL built by string interpolation of user or model input. Bind parameters everywhere | `FR-54` |
| Secrets | `~/.snowflake/connections.toml`, Snowflake secrets, or the OS keychain. Never in git | `NFR-11` |
| Model output rendering | Treated as untrusted text. **Never** rendered as raw HTML | `NFR-12` |
| Egress | No unrestricted network rules. If an external access integration is needed, it names specific hosts | — |
| Account state | No `ALTER ACCOUNT` anywhere | — |

The last three each exist because the reference solution did the opposite: `unsafe_allow_html=True`
on model output, an egress rule of `0.0.0.0:443`, and `ALTER ACCOUNT SET EVENT_TABLE`.

## 2. Governance and data honesty

| Concern | Approach | Requirement |
| --- | --- | --- |
| Synthetic labelling | Labelled at the schema level, in the UI, and in the pitch | `NFR-10`, `FR-15` |
| No real data | Fictional company, generated data, synthetic documents. No employer or customer data | Official Rules §5 |
| Illustrative figures | Marked *(illustrative)* wherever an invented number appears | `NFR-10` |
| Metric provenance | Every metric view states its definition and the KPI it implements in a header comment | `FR-27` |
| Model provenance | Every score carries its model version and drivers | `FR-21`, `NFR-15` |
| Claim discipline | Nothing in the UI or the deck claims a capability the code does not have | `D-12` |

**The rule that makes this checkable:** no number is displayed to a user unless it can be traced to
either a driver set, a citation, or a stated metric definition (`NFR-15`). If a number cannot be
explained, it does not get shown.

## 3. Audit

Every state change is attributable. `AUD_ACTION` is append-only and records:

| Field | Why |
| --- | --- |
| Action type, target object | What happened |
| Actor identity and role | Who — a person, or a named scheduled job |
| Timestamp | When |
| Idempotency key | So a retry is provably not a second action |
| Input snapshot | The risk score, drivers, chosen window and constraint results at decision time |
| Model version | So a later disagreement can be reconstructed |
| Reversal reference | For suppressions and cancellations |

Two structural rules: **the audit append precedes the state change**, so a failed audit blocks the
write (`FR-37`); and there is **no `UPDATE` or `DELETE` grant** on the audit table for any role
including `WOA_ADMIN` at runtime.

## 4. Failure handling

| Layer | Principle |
| --- | --- |
| Pipeline | Idempotent and re-runnable. A failed refresh leaves the previous state intact and visible |
| Model | If scoring fails, the last good score is shown **with its age**. Stale is acceptable; silent is not |
| Metrics | A metric that cannot be computed shows as unavailable, never as zero |
| Engines | An infeasible plan is excluded, not ranked down |
| Action | Audit failure blocks the write. No partial writes |
| Agent | Ungrounded means "I cannot answer that from the data", never a plausible guess (`FR-55`) |
| App | Every view has an empty state and an error state. No traceback, no debug output (`FR-51`) |

**Zero as a value is banned for unavailable data.** An availability of "0%" and an availability of
"not computed" look identical on a dashboard and mean opposite things.

## 5. Observability

| Signal | Where | Requirement |
| --- | --- | --- |
| Pipeline freshness and lag per layer | `OPS` | `NFR-14` |
| Row counts per layer, per run | `OPS` | `NFR-14` |
| Data-quality assertions with pass/fail history | `OPS` | `NFR-14` |
| Model training and evaluation runs with metrics | `OPS` | `FR-17` |
| Credit consumption, reported at each $100 band | `OPS` | `NFR-8` |
| Agent question, tool calls, grounding outcome | `OPS` | `FR-55` |

**Data-quality assertions that gate the demo:** data reaches the current date (`T-11`); every
threshold is reachable (`T-12`); every seeded failure has a corrective work order (`T-7`); no metric
component is constant or random (`T-25`). These four are exactly the reference solution's silent
failures, so they run as assertions rather than as hopes.

## 6. Cost

| Control | Detail |
| --- | --- |
| Ceiling | $400 trial credit, shared across the team |
| Consumed by planning | **≈16.75 credits** — 15.07 CoCo Desktop tokens, 1.68 warehouse |
| **Accounting** | Sum **both** `CORTEX_CODE_*_USAGE_HISTORY` and `WAREHOUSE_METERING_HISTORY`. Warehouse alone under-reports by ~10× |
| Reporting | To NK at each $100-equivalent band |
| **CoCo token spend** | The largest consumer so far. Long exploratory chat sessions are a budget item |
| Warehouse discipline | `XSMALL`, `AUTO_SUSPEND = 60`, `INITIALLY_SUSPENDED` |
| Generation | The largest *warehouse* cost. Recommended 6-month window plus a failure-rich period (`Q-27`) |
| Search service | Loose refresh lag; the corpus barely changes |
| Dynamic tables | Loosest lag that still demonstrates freshness |
| Development | Personal zero-copy clones, not re-generated data per developer |

The credits-to-dollars rate depends on the edition, which we cannot read. **Credits are the hard
number; dollars are an estimate** — stated so nobody treats a converted figure as exact.

## 7. Performance

| Target | Value | Requirement |
| --- | --- | --- |
| Command-center view render | ≤ 5 s at p95 on the demo dataset | `NFR-9` |
| Agent answer | ≤ 30 s, or streamed | `NFR-9` |
| Approval round-trip | ≤ 3 s | — |

Unvalidated on `XSMALL` (`Q-33`). Levers if missed: pre-aggregate at the serving layer, cache the
alert list, narrow the demo scope filter. **Not** a lever: computing metrics in the app to make a
page feel faster — that breaks `NFR-1` and `FR-27`.

## 8. Accessibility

`NFR-13`, and it feeds `E8` Design.

| Rule | Reason |
| --- | --- |
| Status is never conveyed by colour alone — always a label or icon too | The reference solution's twin used colour as the sole status carrier |
| Every control has a text label, not only an emoji glyph | |
| Tables are readable without hover | |
| Charts have axis labels and units on every axis | |

## 9. Concerns we are explicitly not addressing

| Concern | Why |
| --- | --- |
| Multi-tenancy | One fictional OEM (`W9`) |
| Data residency and sovereignty | Single region, synthetic data |
| Disaster recovery, replication | 15-day prototype |
| PII handling | No personal data exists. Technician names are *(illustrative)* labels |
| Penetration testing | Out of scope, but the security rules in §1 are testable and tested |
| Model fairness | No decisions about people. Decisions concern gearboxes |
