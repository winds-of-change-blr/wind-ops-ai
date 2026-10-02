# Results — generated, do not edit

> **Generated** 2026-09-29 17:26 UTC by `just results` from `WIND_OPS_AI` on `MW27072` (AZURE_CENTRALINDIA).
> Every figure is read from Snowflake at generation time; the right-hand column names its source.
> **All data is synthetic** — the data is synthetic; the system is not.

## Outcome (T-95)

On held-out data the risk model flagged **17 of 17** seeded component failures, a median **59 days** before failure. It ranks today's risk as of **2026-08-30**: **5** components HIGH, **₹163.95 L** expected loss. Contractual LD exposure at the current run-rate is **₹13.77 L** across **1** site(s) below guarantee. Turbine OEE (A × P) averages **94.2%**, and **3** turbines were found underperforming while available — invisible to availability and to every alarm. **342,305** alarms compress **21.5:1** into a queue, with **0** real failures suppressed.

## Gates (latest result of every registered assertion)

| Gate | Assertions passing | Gating passing | Last run |
| --- | --- | --- | --- |
| G1 | 16 / 16 | 2 / 2 | 2026-09-29 10:22 |
| G2 | 13 / 13 | 2 / 2 | 2026-09-29 10:23 |
| G3 | 7 / 7 | 6 / 6 | 2026-09-29 10:23 |
| G4 | 31 / 31 | 19 / 19 | 2026-09-29 10:25 |
| G5 | 6 / 6 | 1 / 1 | 2026-09-29 10:23 |
| **All** | **73 / 73** | | |

Gating tests passing: `T-10`, `T-11`, `T-16`, `T-20`, `T-21`, `T-22`, `T-23`, `T-24`, `T-25`, `T-29`, `T-31`, `T-33`, `T-35`, `T-48`, `T-60`, `T-61`, `T-68`, `T-71`, `T-76`, `T-8`, `T-84`, `T-86`.
Failing: **none**.

Plus the behavioural role checks `just verify` runs outside SQL: direct writes to `ACTION` as
`WOA_APP`, `WOA_AGENT`, `WOA_SCHEDULER` (`T-33`) and DDL/DELETE/UPDATE as `WOA_AGENT` (`T-47`).

## The model is real (T-10, T-87, T-94)

| Figure | Value | Source |
| --- | --- | --- |
| Model component precision | 1.000 | `OPS.ML_METRIC` run `MLRUN-20260929100549` |
| Trivial-rule component precision | 0.607 | same run, `BL-TRIVIAL-THRESHOLD` |
| Random component precision | 0.140 | same run, `BL-RANDOM-STRATIFIED` |
| Margin over the rule (T-10, bound ≥ 1.25×) | **1.65×** | ratio of the two above |
| PR-AUC | 0.986 | same run |
| Caught by model / by rule / failed in hold-out | 17 / 17 / 17 | same run, `COMPARISON` |
| Anomaly vs risk, Spearman ρ (bound ≤ 0.50) | 0.211 | `OPS.ML_METRIC` `ANOMALY` |

## Alarms (T-70, T-86)

| Stage | Count | Source |
| --- | --- | --- |
| Raw alarms | 342,305 | `SERVING.MET_NOISE` |
| Incidents | 15,934 | same |
| Actionable · undetermined · nuisance | 6,241 · 9,655 · 38 | same |
| Compression · **real failures suppressed** | 21.5:1 · **0** | `ENGINE.ENG_ALARM_FUNNEL` — never shown apart |
| Undetermined rate | 60.6% | same (published, not buried) |

## Money and energy

| Figure | Value | Source |
| --- | --- | --- |
| Expected loss, all components | ₹163.95 L | `ENGINE.ENG_ALERT_RANKED` |
| LD exposure, run-rate (not an invoice) | ₹13.77 L | `SERVING.MET_LD_EXPOSURE` |
| Mean Turbine OEE (A × P; Quality not modelled) | 94.2% | `SERVING.MET_TURBINE_OEE` |
| Energy lost (downtime + underperformance) | 10,943 MWh | `SERVING.MET_LOST_ENERGY` |

## Actions (G4)

10 requests to the approval procedures outside self-tests: 3 applied, 7 refused. Source: `ACTION.AUD_ACTION`.

## Credits (both sources, R-31)

| Source | Credits |
| --- | --- |
| CoCo token credits | 33.08 |
| Warehouse credits | 21.97 |
| **Total on this account** | **55.04** |

`ACCOUNT_USAGE` data through 2026-09-29 17:21:15.128000+00:00; it lags up to three hours.
