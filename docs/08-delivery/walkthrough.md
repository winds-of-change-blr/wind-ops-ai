# Walkthrough — two minutes through the Command Center

> **Status:** v1.0 · **Owner:** JP · **Last updated:** 2026-09-29 · Implements the script for `T-90`
>
> The script for the 2-minute recorded walkthrough and for a judge clicking through alone. It follows
> [demo-and-submission.md §2](demo-and-submission.md#2-the-demo--5-minutes), compressed to the beats
> that stand without narration. **Every number is read off the screen at recording time**, never from
> this file — figures here are the shape to expect, and [`results.md`](results.md) holds the current ones.

Open Snowsight › *Projects* › *Streamlit* › `WOA_COMMAND_CENTER`. Leave every sidebar filter on.

| Time | Tab › section | Do | Say |
| --- | --- | --- | --- |
| 0:00–0:20 | **Alarms** › *A flood of alarms becomes a short, honest list* | Point at the four funnel cards, then the three tiles | "Six months, a hundred turbines: about 340 thousand alarms become about 16 thousand incidents, and 6 thousand actionable. Compression is 21 to 1 — and **real failures suppressed: zero**, always shown beside it. The data is synthetic; the system is not." |
| 0:20–0:40 | **Alarms** › *Incident queue* → *Why was it classed this way?* | Select row 1 (a safety-critical code). Scroll the evidence table | "Every class carries its rule and four stored evidence channels — corroboration, operating point, reset recurrence, model risk. And 60% of incidents are **undetermined**: ranked below actionable, never hidden, never suppressible. A triage system that never says *I don't know* is lying." |
| 0:40–0:50 | **Alarms** › *Suppress this incident* | Read the ✓/✗ checklist aloud; **do not submit** | "Suppression is the one action that can hide a real failure, so it needs every gate — and the procedure re-checks them itself, time-boxed and audited. On this one, three gates fail: it will be refused." |
| 0:50–1:10 | **Risk triage** › *Triage ranked by money, not by probability* | Compare the two tables' top five | "Expected loss is risk times part cost plus the LD cost of downtime. Ranked by money, the generator moves to the top: its part costs three times a bearing, so the same risk is worth more money." |
| 1:10–1:25 | **Risk triage** › *Evidence panel* | Pick the top component; show the drivers table | "A 30-day score with the signals that drove it, each against the component's own baseline." |
| 1:25–1:45 | **Is the model real?** › *Rule versus model — on held-out data* | Point at precision for model, rule and random | "The build fails unless the trained model beats a trivial single-signal rule, not just random. Here it does, on held-out data, from the same run the app displays." |
| 1:45–1:55 | **Risk triage** › *Planning — windows the engine can vouch for* | Show one feasible window, then one infeasible with its binding constraint | "Windows come from weather, crews, cranes and parts. When none is feasible it says why — here, the part lands after the horizon." |
| 1:55–2:00 | **Audit** | Show the latest rows | "Every decision, including every refusal, is a row. The agent can read all of this and write none of it." |

## If there is more time

- **Fleet & contracts** › *Turbine OEE*: the turbines that availability calls healthy but OEE
  catches underperforming (`GS-5`).
- **Sidebar assistant**: ask *"Why is the top expected-loss component at risk, and what is the
  procedure?"* — the answer cites the fleet data and the procedure document.

## Before recording

1. `just verify` exits 0 on the day — a stale dataset fails `T-11` freshness, and the fix is `just deploy`.
2. `just results`, and check the funnel and precision on screen match [`results.md`](results.md).
3. Record at 100% zoom with the sidebar open, so the synthetic-data badge is in frame.
