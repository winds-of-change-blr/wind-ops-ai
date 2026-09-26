"""Generate the results summary from OPS and the metric views (T-92, T-95).

Every figure on the page is read from Snowflake at generation time and printed
beside the object it came from, so the summary can be re-checked against its
source and can never drift into hand-typed claims. Run through `just results`.

    uv run --with snowflake-connector-python python scripts/generate_results.py WIND_OPS_AI_DEV_NK
"""

from __future__ import annotations

import datetime as dt
import os
import sys
import tomllib
from pathlib import Path

import snowflake.connector

OUT = Path(__file__).resolve().parent.parent / "docs" / "08-delivery" / "results.md"


def _connection_name() -> str | None:
    name = os.environ.get("SNOWFLAKE_DEFAULT_CONNECTION_NAME")
    if name:
        return name
    cfg = Path.home() / ".snowflake" / "config.toml"
    if cfg.exists():
        return tomllib.loads(cfg.read_text()).get("default_connection_name")
    return None


def main(db: str) -> None:
    if not db.replace("_", "").isalnum():
        raise SystemExit(f"refusing an unexpected database identifier: {db!r}")
    con = snowflake.connector.connect(connection_name=_connection_name())
    cur = con.cursor()

    def one(sql: str, params: tuple = ()):
        cur.execute(sql, params)
        return cur.fetchone()

    def rows(sql: str, params: tuple = ()):
        cur.execute(sql, params)
        return cur.fetchall()

    cur.execute("use role WOA_ADMIN")
    cur.execute(f"use database {db}")
    cur.execute("use warehouse WOA_BUILD_WH")

    # ---- gates: the latest result of every registered assertion
    gates = rows(
        """
        with latest as (
            select r.*, row_number() over (partition by r.assertion_id order by r.run_at desc) rn
            from OPS.DQ_RESULT r
        )
        select a.gate, count(*), count_if(l.passed), count_if(a.is_gating),
               count_if(a.is_gating and l.passed), max(l.run_at)
        from OPS.DQ_ASSERTION a
        join latest l on l.assertion_id = a.assertion_id and l.rn = 1
        group by a.gate order by a.gate
        """
    )
    gating_ids = [
        r[0]
        for r in rows(
            """
            select distinct a.test_id from OPS.DQ_ASSERTION a
            join (select assertion_id, passed,
                         row_number() over (partition by assertion_id order by run_at desc) rn
                  from OPS.DQ_RESULT) l on l.assertion_id = a.assertion_id and l.rn = 1
            where a.is_gating and l.passed order by 1
            """
        )
    ]
    failing = rows(
        """
        select a.assertion_id, a.test_id from OPS.DQ_ASSERTION a
        join (select assertion_id, passed,
                     row_number() over (partition by assertion_id order by run_at desc) rn
              from OPS.DQ_RESULT) l on l.assertion_id = a.assertion_id and l.rn = 1
        where not l.passed
        """
    )

    # ---- the model, from the run that produced the scores on screen
    run_id = one("select max(run_id) from OPS.ML_RUN where model_name = 'RISK_CLASSIFIER'")[0]
    m = {
        (s, n): float(v)
        for s, n, v in rows(
            "select metric_scope, metric_name, metric_value from OPS.ML_METRIC where run_id = %s",
            (run_id,),
        )
    }
    rho = one(
        """select metric_value from OPS.ML_METRIC where metric_scope = 'ANOMALY'
           and metric_name = 'spearman_vs_risk'
           and run_id = (select max(run_id) from OPS.ML_RUN where model_name = 'ANOMALY_DETECTOR')"""
    )

    noise = one(
        """select n.raw_alarms, n.incidents, n.actionable, n.undetermined, n.nuisance,
                  n.real_failures_suppressed, f.compression_ratio, f.undetermined_rate
           from SERVING.MET_NOISE n, ENGINE.ENG_ALARM_FUNNEL f"""
    )
    money = one(
        """select (select sum(expected_loss_inr) from ENGINE.ENG_ALERT_RANKED),
                  (select count_if(risk_band = 'HIGH') from ENGINE.ENG_ALERT_RANKED),
                  (select sum(ld_exposure_run_rate_inr) from SERVING.MET_LD_EXPOSURE),
                  (select count_if(shortfall_pct > 0) from SERVING.MET_LD_EXPOSURE),
                  (select avg(oee) from SERVING.MET_TURBINE_OEE),
                  (select count_if(is_underperforming) from SERVING.MET_TURBINE_OEE),
                  (select sum(lost_mwh_total) from SERVING.MET_LOST_ENERGY),
                  (select max(as_of_date) from ENGINE.ENG_ALERT_RANKED)"""
    )
    audit = one(
        """select count(*), coalesce(count_if(outcome = 'APPLIED'), 0), coalesce(count_if(outcome = 'REFUSED'), 0)
           from ACTION.AUD_ACTION where not is_selftest"""
    )

    # ---- credits: both sources, always summed (R-31). ACCOUNT_USAGE needs an
    # elevated role and lags ~3 h; if it is unreadable, say so instead of 0.
    try:
        cur.execute("use role ACCOUNTADMIN")
        spend = one(
            """select (select sum(token_credits) from SNOWFLAKE.ACCOUNT_USAGE.CORTEX_CODE_DESKTOP_USAGE_HISTORY),
                      (select sum(credits_used) from SNOWFLAKE.ACCOUNT_USAGE.WAREHOUSE_METERING_HISTORY),
                      (select max(usage_time) from SNOWFLAKE.ACCOUNT_USAGE.CORTEX_CODE_DESKTOP_USAGE_HISTORY)"""
        )
    except snowflake.connector.errors.Error as e:
        spend = None
        credit_err = str(e).splitlines()[0]
    account = one("select current_account_name(), current_region()")
    con.close()

    # ---- render
    failed = m.get(("COMPARISON", "failed_components_in_holdout"), 0)
    caught = m.get(("COMPARISON", "components_caught_by_model"), 0)
    lead = m.get(("MODEL", "lead_time_median_days"))
    p_model = m.get(("MODEL", "precision_components"))
    p_rule = m.get(("BL-TRIVIAL-THRESHOLD", "precision_components"))
    p_rand = m.get(("BL-RANDOM-STRATIFIED", "precision_components"))
    lakh = lambda x: f"₹{float(x) / 1e5:,.2f} L"  # noqa: E731
    now = dt.datetime.now(dt.UTC).strftime("%Y-%m-%d %H:%M UTC")

    total_asserts = sum(g[1] for g in gates)
    total_pass = sum(g[2] for g in gates)
    lines = [
        "# Results — generated, do not edit",
        "",
        f"> **Generated** {now} by `just results` from `{db}` on `{account[0]}` ({account[1]}).",
        "> Every figure is read from Snowflake at generation time; the right-hand column names its source.",
        "> **All data is synthetic** — the data is synthetic; the system is not.",
        "",
        "## Outcome (T-95)",
        "",
        (
            f"On held-out data the risk model flagged **{int(caught)} of {int(failed)}** seeded component "
            f"failures, a median **{lead:.0f} days** before failure. It ranks today's risk as of "
            f"**{money[7]}**: **{int(money[1])}** components HIGH, **{lakh(money[0])}** expected loss. "
            f"Contractual LD exposure at the current run-rate is **{lakh(money[2])}** across "
            f"**{int(money[3])}** site(s) below guarantee. Turbine OEE (A × P) averages "
            f"**{float(money[4]):.1%}**, and **{int(money[5])}** turbines were found underperforming "
            f"while available — invisible to availability and to every alarm. "
            f"**{int(noise[0]):,}** alarms compress **{noise[6]}:1** into a queue, with "
            f"**{int(noise[5])}** real failures suppressed."
        ),
        "",
        "## Gates (latest result of every registered assertion)",
        "",
        "| Gate | Assertions passing | Gating passing | Last run |",
        "| --- | --- | --- | --- |",
    ]
    lines += [
        f"| {g[0]} | {g[2]} / {g[1]} | {g[4]} / {g[3]} | {g[5]:%Y-%m-%d %H:%M} |" for g in gates
    ]
    lines += [
        f"| **All** | **{total_pass} / {total_asserts}** | | |",
        "",
        f"Gating tests passing: {', '.join(f'`{t}`' for t in gating_ids)}.",
        "Failing: " + (", ".join(f"`{a}` ({t})" for a, t in failing) if failing else "**none**."),
        "",
        "Plus the behavioural role checks `just verify` runs outside SQL: direct writes to `ACTION` as",
        "`WOA_APP`, `WOA_AGENT`, `WOA_SCHEDULER` (`T-33`) and DDL/DELETE/UPDATE as `WOA_AGENT` (`T-47`).",
        "",
        "## The model is real (T-10, T-87, T-94)",
        "",
        "| Figure | Value | Source |",
        "| --- | --- | --- |",
        f"| Model component precision | {p_model:.3f} | `OPS.ML_METRIC` run `{run_id}` |",
        f"| Trivial-rule component precision | {p_rule:.3f} | same run, `BL-TRIVIAL-THRESHOLD` |",
        f"| Random component precision | {p_rand:.3f} | same run, `BL-RANDOM-STRATIFIED` |",
        f"| Margin over the rule (T-10, bound ≥ 1.25×) | **{p_model / p_rule:.2f}×** | ratio of the two above |",
        f"| PR-AUC | {m.get(('MODEL', 'pr_auc'), 0):.3f} | same run |",
        f"| Caught by model / by rule / failed in hold-out | {int(caught)} / "
        f"{int(m.get(('COMPARISON', 'components_caught_by_rule'), 0))} / {int(failed)} | same run, `COMPARISON` |",
        f"| Anomaly vs risk, Spearman ρ (bound ≤ 0.50) | {float(rho[0]):.3f} | `OPS.ML_METRIC` `ANOMALY` |"
        if rho
        else "| Anomaly vs risk | not recorded | |",
        "",
        "## Alarms (T-70, T-86)",
        "",
        "| Stage | Count | Source |",
        "| --- | --- | --- |",
        f"| Raw alarms | {int(noise[0]):,} | `SERVING.MET_NOISE` |",
        f"| Incidents | {int(noise[1]):,} | same |",
        f"| Actionable · undetermined · nuisance | {int(noise[2]):,} · {int(noise[3]):,} · "
        f"{int(noise[4]):,} | same |",
        f"| Compression · **real failures suppressed** | {noise[6]}:1 · **{int(noise[5])}** | "
        "`ENGINE.ENG_ALARM_FUNNEL` — never shown apart |",
        f"| Undetermined rate | {float(noise[7]):.1%} | same (published, not buried) |",
        "",
        "## Money and energy",
        "",
        "| Figure | Value | Source |",
        "| --- | --- | --- |",
        f"| Expected loss, all components | {lakh(money[0])} | `ENGINE.ENG_ALERT_RANKED` |",
        f"| LD exposure, run-rate (not an invoice) | {lakh(money[2])} | `SERVING.MET_LD_EXPOSURE` |",
        f"| Mean Turbine OEE (A × P; Quality not modelled) | {float(money[4]):.1%} | `SERVING.MET_TURBINE_OEE` |",
        f"| Energy lost (downtime + underperformance) | {float(money[6]):,.0f} MWh | `SERVING.MET_LOST_ENERGY` |",
        "",
        "## Actions (G4)",
        "",
        f"{int(audit[0])} requests to the approval procedures outside self-tests: {int(audit[1])} applied, "
        f"{int(audit[2])} refused. Source: `ACTION.AUD_ACTION`.",
        "",
        "## Credits (both sources, R-31)",
        "",
    ]
    if spend:
        lines += [
            "| Source | Credits |",
            "| --- | --- |",
            f"| CoCo token credits | {float(spend[0] or 0):,.2f} |",
            f"| Warehouse credits | {float(spend[1] or 0):,.2f} |",
            f"| **Total on this account** | **{float(spend[0] or 0) + float(spend[1] or 0):,.2f}** |",
            "",
            f"`ACCOUNT_USAGE` data through {spend[2]}; it lags up to three hours.",
        ]
    else:
        lines += [f"Credits unavailable to this connection's role: {credit_err}"]
    OUT.write_text("\n".join(lines) + "\n")
    print(f"wrote {OUT.relative_to(Path.cwd()) if OUT.is_relative_to(Path.cwd()) else OUT}")
    print(f"assertions {total_pass}/{total_asserts}; failing: {len(failing)}")


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else "WIND_OPS_AI_DEV_NK")
