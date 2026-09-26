# ADR-0020 — App platform: Streamlit in Snowflake, not a container

> **Status:** Accepted · **Owner:** NK · **Last updated:** 2026-09-18 ·
> **Related:** [ADR-0012](README.md#adr-0012--front-end) (now resolved),
> [ADR-0001](README.md#adr-0001--snowflake-native-single-account),
> [ADR-0004](adr-0004-determinism-boundary.md)

---

## Context

`M8` needs an operations UI. Streamlit has real limitations — layout control, interactivity, the
rerun model — so before committing we asked whether a **proper web app** could be built on Snowflake
with the same in-account integrations.

The canonical answer is **Snowflake App Runtime (SAR)**: a Next.js app deployed with `snow app deploy`
as an `APPLICATION SERVICE`, served at a `*.snowflakecomputing.app` HTTPS endpoint. It is the path
Snowflake documents and tools for exactly this.

**We tested it in our own account rather than reading the documentation.** Findings, all reproducible:

| Probe | Result |
| --- | --- |
| `SHOW APPLICATION SERVICES` | Recognised — the DDL exists |
| `CREATE COMPUTE POOL … CPU_X64_XS` | **Succeeded**, reached `STARTING` |
| `CREATE ARTIFACT REPOSITORY … TYPE = APPLICATION` | **Succeeded** |
| `CREATE IMAGE REPOSITORY` | **Succeeded** |
| `CREATE APPLICATION SERVICE …` | ❌ **`Snowpark Container Services feature APPLICATION SERVICE not available for trial accounts`** |
| `CREATE SERVICE …` (plain SPCS, public endpoint) | Spec **accepted** — failed only on a deliberately absent image |
| `CREATE STREAMLIT …` | **Succeeded** — this resolves `Q-39` |
| `snow --version` | Not installed locally |

Two things follow. **SAR is unavailable to us**: we are on a trial account (Official Rules §4.3, $400
credit), and the block is explicit and feature-level, not a privilege we can grant ourselves. But
**plain SPCS is available**, so a real containerised web app — Next.js or React plus FastAPI, public
endpoint, in-container OAuth via `/snowflake/session/token` — was genuinely on the table.

## Decision

**Streamlit in Snowflake.** A containerised SPCS web app was available and was deliberately declined.

The scope argument is real but secondary: a container adds Docker, an image registry, a service spec,
compute-pool lifecycle and in-container auth to a 15-day plan whose 40%-weighted criterion already
rests on one unproven assumption (`T-10`). Debugging a crash-looping container on D13 is how demos die.

**The stronger argument is governance, and it points the same way.** Our least-privilege story —
`WOA_RMC`, `WOA_PLANNER`, `WOA_EXEC`, `WOA_TECH` — is enforced by the platform under SiS: the app runs
as the *viewer's* role, so `NFR-3` is a property of the deployment rather than of our code. A custom
SPCS service authenticates as the service, and we would have to re-implement role scoping inside the
app and prove it. That is more code in the exact place where a mistake is least visible and most
damaging to `E2` and `E8`. **SiS gives us the audit story for free; a container would make us build it
and then ask a judge to trust it.**

## Consequences

**Accepted costs.** Streamlit's layout and interactivity ceiling is now ours. The funnel (`FR-89`) and
the dense triage surface are the two places it will bite.

**Mitigations, which are design constraints rather than hopes:**

| Limit | How `M8` works within it |
| --- | --- |
| Layout control | The **one reusable evidence panel** (`US-85` sequencing) is already the plan's answer — three contexts, one component. Fewer bespoke layouts, not more |
| The funnel visual | `st.components` HTML, or a Vega-Lite spec. Falls back to a plain stacked bar, which still carries the number |
| Rerun model | Deterministic engine tables (`ADR-0004`) mean the UI reads precomputed state. Nothing expensive recomputes on a widget change |
| No custom auth | **A feature, not a limit.** Snowflake login and RBAC are the auth |
| No arbitrary egress | Only the MCP connector needed it, and `ADR-0019` already made that interactive-only |

**What stays true regardless.** The app must take its connection from configuration and must not depend
on a Snowflake-hosted session token — the constraint `ADR-0012` identified and the exact mistake that
made the reference solution SiS-only. That keeps `streamlit run` locally as a demo-day fallback
(`T-53`).

**Revisit trigger.** If the account becomes paid, SAR is unlocked and this decision should be
re-examined — but not during the hackathon, and not after D2. Recorded as `Q-94`.

## Alternatives rejected

| Option | Why not |
| --- | --- |
| **SAR / Next.js via `snow app`** | Not available on a trial account. Verified, not assumed |
| **Custom SPCS container, no fallback** | Available, but the largest new build surface in the plan, competing with `T-10`, with no escape hatch late |
| **Custom SPCS container with a D2 spike gate and SiS fallback** | The safe version of the above. Still pays for two UI paths, and the governance argument above says the fallback was the better target all along |
| **Convert to a paid account** | Costs real money and may affect the hackathon credit arrangement under Official Rules §4.3. Not a decision to take mid-build for a UI nicety |

## Honesty note

This is worth saying out loud on the honesty slide and in Q&A, because "why not a real web app?" is a
fair question and the weak answer is "Streamlit was easier". The true answer has three parts: the
documented path is closed to us on a trial account, we verified that rather than assuming it, and the
open path would have required us to rebuild role-based access control that the platform otherwise
gives us. Declining a capability for a stated reason reads as judgement; being unable to name why reads
as a gap.

## Amendment — 2026-09-26: warehouse runtime, not container runtime (`I-17`)

Within Streamlit in Snowflake there are two runtimes, and the one this ADR implicitly assumed does not
work here. The **container runtime** installs every Python package from `pypi.org` when the app boots,
which requires an external access integration — and **"External access is not supported for trial
accounts."** Tried three ways; all failed at boot. The **warehouse runtime** installs `environment.yml`
from Snowflake's own Anaconda channel, needs no egress, and ships Streamlit 1.52.2.

The runtime is set **explicitly** (`RUNTIME_NAME = 'SYSTEM$WAREHOUSE_RUNTIME'`), because Snowflake is
moving new apps to default to the container runtime and `snow streamlit deploy` already did so on a clean
recreate. `just deploy-app` asserts the runtime after every deploy.

**What this costs:** each viewer gets their own app instance on the warehouse, rather than one shared
container; and packages are limited to the Anaconda channel. Neither matters for a read-only demo app.
The governance argument above is unchanged — the app still runs as the viewer's role.
