# Results — generated, do not edit

> **Generated** 2026-09-26 06:53 UTC by `just results` from `WIND_OPS_AI_DEV_NK` on `UZ86048` (AZURE_CENTRALINDIA).
> Every figure is read from Snowflake at generation time; the right-hand column names its source.
> **All data is synthetic** — the data is synthetic; the system is not.

## Outcome (T-95)

On held-out data the risk model flagged **17 of 17** seeded component failures, a median **59 days** before failure. It ranks today's risk as of **2026-08-26**: **6** components HIGH, **₹209.21 L** expected loss. Contractual LD exposure at the current run-rate is **₹14.25 L** across **1** site(s) below guarantee. Turbine OEE (A × P) averages **94.2%**, and **3** turbines were found underperforming while available — invisible to availability and to every alarm. **340,431** alarms compress **21.6:1** into a queue, with **0** real failures suppressed.

## Gates (latest result of every registered assertion)

| Gate | Assertions passing | Gating passing | Last run |
| --- | --- | --- | --- |
| G1 | 16 / 16 | 2 / 2 | 2026-09-25 23:49 |
| G2 | 13 / 13 | 2 / 2 | 2026-09-25 23:50 |
| G3 | 7 / 7 | 6 / 6 | 2026-09-25 23:50 |
| G4 | 23 / 23 | 12 / 12 | 2026-09-25 23:52 |
| G5 | 6 / 6 | 1 / 1 | 2026-09-25 23:50 |
| **All** | **65 / 65** | | |

Gating tests passing: `T-10`, `T-11`, `T-16`, `T-20`, `T-21`, `T-22`, `T-23`, `T-24`, `T-25`, `T-29`, `T-31`, `T-33`, `T-35`, `T-48`, `T-60`, `T-71`, `T-76`, `T-8`, `T-86`.
Failing: **none**.

Plus the behavioural role checks `just verify` runs outside SQL: direct writes to `ACTION` as
`WOA_APP`, `WOA_AGENT`, `WOA_SCHEDULER` (`T-33`) and DDL/DELETE/UPDATE as `WOA_AGENT` (`T-47`).

## The model is real (T-10, T-87, T-94)

| Figure | Value | Source |
| --- | --- | --- |
| Model component precision | 1.000 | `OPS.ML_METRIC` run `MLRUN-20260925181646` |
| Trivial-rule component precision | 0.567 | same run, `BL-TRIVIAL-THRESHOLD` |
| Random component precision | 0.140 | same run, `BL-RANDOM-STRATIFIED` |
| Margin over the rule (T-10, bound ≥ 1.25×) | **1.76×** | ratio of the two above |
| PR-AUC | 0.989 | same run |
| Caught by model / by rule / failed in hold-out | 17 / 17 / 17 | same run, `COMPARISON` |
| Anomaly vs risk, Spearman ρ (bound ≤ 0.50) | 0.243 | `OPS.ML_METRIC` `ANOMALY` |

## Alarms (T-70, T-86)

| Stage | Count | Source |
| --- | --- | --- |
| Raw alarms | 340,431 | `SERVING.MET_NOISE` |
| Incidents | 15,803 | same |
| Actionable · undetermined · nuisance | 6,024 · 9,739 · 40 | same |
| Compression · **real failures suppressed** | 21.6:1 · **0** | `ENGINE.ENG_ALARM_FUNNEL` — never shown apart |
| Undetermined rate | 61.6% | same (published, not buried) |

## Money and energy

| Figure | Value | Source |
| --- | --- | --- |
| Expected loss, all components | ₹209.21 L | `ENGINE.ENG_ALERT_RANKED` |
| LD exposure, run-rate (not an invoice) | ₹14.25 L | `SERVING.MET_LD_EXPOSURE` |
| Mean Turbine OEE (A × P; Quality not modelled) | 94.2% | `SERVING.MET_TURBINE_OEE` |
| Energy lost (downtime + underperformance) | 10,940 MWh | `SERVING.MET_LOST_ENERGY` |

## Actions (G4)

0 requests to the approval procedures outside self-tests: 0 applied, 0 refused. Source: `ACTION.AUD_ACTION`.

## Credits (both sources, R-31)

| Source | Credits |
| --- | --- |
| CoCo token credits | 102.50 |
| Warehouse credits | 12.78 |
| **Total on this account** | **115.28** |

`ACCOUNT_USAGE` data through 2026-09-26 06:46:01.214000+00:00; it lags up to three hours.
