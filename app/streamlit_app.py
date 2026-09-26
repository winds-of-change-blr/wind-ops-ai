"""Wind Ops AI — command center (Streamlit in Snowflake, ADR-0020).

SYNTHETIC DATA ONLY (AGENTS.md rule 5). Read-only: this app issues no writes.

Design rules this file keeps:
* Connection from configuration, never a Snowflake-hosted session token, so
  `streamlit run` works on a laptop as the demo-day fallback (NFR-21).
* No hardcoded database (NFR-6): WOA_DATABASE locally, CURRENT_DATABASE() in SiS.
* The engine decides, the model explains (ADR-0004). Nothing here classifies,
  ranks or suppresses — it displays what ENGINE and ML already computed.
* Compression is never shown without real-failures-suppressed beside it
  (ADR-0017, T-70). Every visual degrades to a table that keeps its number
  (NFR-22).
"""

from __future__ import annotations

import decimal
import os
import re

import altair as alt
import pandas as pd
import streamlit as st

st.set_page_config(page_title="Wind Ops AI — Command Center", layout="wide")

_IDENT = re.compile(r"^[A-Z][A-Z0-9_]{0,254}$")


@st.cache_resource
def _conn():
    # One name, no connection_name kwarg: passing both duplicates the argument.
    # In SiS this resolves to the embedded identity; locally the connector reads
    # SNOWFLAKE_DEFAULT_CONNECTION_NAME from ~/.snowflake/connections.toml, so
    # nothing here depends on a Snowflake-hosted session token (NFR-21).
    return st.connection("snowflake")


def _run(sql: str, params: list | None = None, ttl: int = 600) -> pd.DataFrame:
    # Positional qmark binding (the connector default). User-chosen values are
    # always bound, never interpolated into the SQL string.
    df = _conn().query(sql, params=params, ttl=ttl)
    df.columns = [c.lower() for c in df.columns]
    # Snowflake NUMBER arrives as Python Decimal, which Altair cannot type and
    # silently treats as a CATEGORY — a numeric bar chart would render as
    # labels. Convert any all-Decimal column to float so every chart is typed.
    for col in df.columns:
        if df[col].dtype == object:
            nonnull = df[col].dropna()
            if len(nonnull) and nonnull.map(lambda v: isinstance(v, decimal.Decimal)).all():
                df[col] = df[col].astype(float)
    return df


@st.cache_data(ttl=3600)
def _database() -> str:
    db = os.getenv("WOA_DATABASE") or _run("select current_database() as db").iloc[0]["db"]
    db = (db or "").upper()
    # The database name is interpolated as an identifier, so it is validated,
    # never trusted. User input never reaches this function.
    if not _IDENT.match(db):
        raise ValueError(f"Refusing an unexpected database identifier: {db!r}")
    return db


def q(obj: str) -> str:
    """Fully qualify SCHEMA.OBJECT against the resolved database."""
    schema, name = obj.split(".")
    assert _IDENT.match(schema) and _IDENT.match(name), obj
    return f"{_database()}.{schema}.{name}"


def inr(x) -> str:
    if x is None or pd.isna(x):
        return "—"
    x = float(x)
    if abs(x) >= 1e7:
        return f"₹{x / 1e7:,.2f} Cr"
    if abs(x) >= 1e5:
        return f"₹{x / 1e5:,.2f} L"
    return f"₹{x:,.0f}"


# --------------------------------------------------------------------------- header
asof = _run(f"select as_of_date, data_end_date, horizon_days from {q('ML.V_SCORING_ASOF')}")
as_of = asof.iloc[0]["as_of_date"] if not asof.empty else None

st.title("Wind Ops AI — Command Center")
st.caption(
    "Vayuveda Wind Systems · 100 turbines · 6 sites. "
    "**Synthetic data only** — the data is synthetic; the system is not."
)
if as_of is not None:
    st.info(
        f"Risk is scored **as of {as_of}** — {int(asof.iloc[0]['horizon_days'])} days before the "
        f"data ends ({asof.iloc[0]['data_end_date']}). A "
        f"{int(asof.iloc[0]['horizon_days'])}-day-ahead "
        "prediction can only be checked if that much future exists (I-13).",
        icon=":material/event:",
    )

t_alarms, t_triage, t_model, t_fleet = st.tabs(
    [
        ":material/notifications: Alarms",
        ":material/priority_high: Risk triage",
        ":material/science: Is the model real?",
        ":material/wind_power: Fleet & contracts",
    ]
)

# --------------------------------------------------------------------------- alarms
with t_alarms:
    f = _run(f"select * from {q('ENGINE.ENG_ALARM_FUNNEL')}")
    if f.empty:
        st.warning("The alarm engine has not been built. Run `just deploy-engine`.")
    else:
        r = f.iloc[0]
        st.subheader("A flood of alarms becomes a short, honest list")
        c1, c2, c3, c4, c5 = st.columns(5)
        c1.metric("Raw alarms", f"{int(r.raw_alarms):,}")
        c2.metric("Incidents", f"{int(r.incidents):,}")
        c3.metric("Actionable", f"{int(r.actionable):,}")
        c4.metric(
            "Undetermined",
            f"{int(r.undetermined):,}",
            help="Unresolved, not resolved-as-noise. Never hidden, never suppressible (ADR-0017).",
        )
        # The anti-gaming rule: compression and failures-suppressed, together.
        c5.metric(
            "Compression · real failures suppressed",
            f"{r.compression_ratio}:1 · {int(r.real_failures_suppressed)}",
            help="Compression is trivially achieved by suppressing everything, "
            "so it is never shown alone (T-70).",
        )

        stages = pd.DataFrame(
            {
                "stage": [
                    "1 · Raw alarms",
                    "2 · Incidents",
                    "3 · Actionable + undetermined",
                    "4 · Actionable",
                ],
                "count": [
                    int(r.raw_alarms),
                    int(r.incidents),
                    int(r.actionable) + int(r.undetermined),
                    int(r.actionable),
                ],
            }
        )
        st.altair_chart(
            alt.Chart(stages)
            .mark_bar()
            .encode(
                x=alt.X("count:Q", scale=alt.Scale(type="log"), title="count (log scale)"),
                y=alt.Y("stage:N", sort=None, title=None),
                tooltip=["stage", "count"],
            )
            .properties(height=190),
            width="stretch",
        )
        st.caption(
            f"Undetermined rate **{float(r.undetermined_rate):.1%}** — published, not buried. "
            "A rising rate means the evidence base is degrading."
        )

        st.subheader("The queue")
        klass = st.segmented_control(
            "Class",
            ["ACTIONABLE", "UNDETERMINED", "NUISANCE"],
            default="ACTIONABLE",
        )
        queue = _run(
            f"""select incident_id, turbine_id, site_code, component_id, alarm_code, alarm_name,
                       severity, is_safety_critical, incident_start, n_alarms, all_auto_reset,
                       is_corroborated, is_elevated, noise_condition, class_reason
                from {q("ENGINE.ENG_INCIDENT")}
                where incident_class = ?
                order by is_safety_critical desc, is_elevated desc, incident_start desc
                limit 200""",
            params=[klass or "ACTIONABLE"],
        )
        st.dataframe(queue, hide_index=True, width="stretch")

        st.subheader("Try to suppress one")
        st.caption(
            "Suppression is guarded (AGENTS.md rule 3): never on a safety-critical "
            "code, never on an "
            "asset with elevated evidence. This checks the guards read-only; no write is made."
        )
        pick = st.selectbox("Incident", queue["incident_id"].tolist() if not queue.empty else [])
        if pick and st.button("Suppress this incident", icon=":material/notifications_off:"):
            row = queue[queue["incident_id"] == pick].iloc[0]
            if bool(row.is_safety_critical):
                st.error(
                    f"**Refused.** `{row.alarm_code}` is a safety-critical code. "
                    "Safety-critical alarms are never suppressible.",
                    icon=":material/block:",
                )
            elif bool(row.is_elevated):
                st.error(
                    "**Refused.** This asset carries elevated evidence — an "
                    "anomaly flag within 3 days "
                    "or a CMS alarm within 7. Nothing is suppressed on an elevated-risk asset.",
                    icon=":material/block:",
                )
            elif klass == "UNDETERMINED":
                st.error(
                    "**Refused.** Undetermined incidents are never auto-suppressible: "
                    "suppressing what you don't understand is how real failures get lost.",
                    icon=":material/block:",
                )
            else:
                st.warning(
                    "The guards would allow this. Suppression still needs human approval, "
                    "and the approval workflow (G4) is not built yet — so nothing was written.",
                    icon=":material/pending:",
                )

# --------------------------------------------------------------------------- triage
with t_triage:
    ranked = _run(
        f"""select money_rank, probability_rank, component_id, turbine_id, site_code,
                   component_class_name, risk_probability, risk_band, anomaly_flag,
                   anomaly_distance, top_drivers, part_cost_inr, lead_time_days,
                   requires_crane, downtime_days_illustrative, downtime_ld_cost_inr,
                   expected_loss_inr
            from {q("ENGINE.ENG_ALERT_RANKED")}
            order by money_rank"""
    )
    if ranked.empty:
        st.warning("No risk scores. Run `just deploy-ml`, then `just deploy-engine`.")
    else:
        st.subheader("Triage ranked by money, not by probability")
        st.caption(
            "Expected loss = risk × (part cost + LD cost of the downtime). "
            "The repair allowance inside downtime is **illustrative** (NFR-10)."
        )
        top = ranked.head(15)
        left, right = st.columns(2)
        with left:
            st.markdown("**By expected loss**")
            st.dataframe(
                top[
                    [
                        "money_rank",
                        "component_id",
                        "component_class_name",
                        "risk_probability",
                        "expected_loss_inr",
                        "anomaly_flag",
                    ]
                ],
                hide_index=True,
                width="stretch",
            )
        with right:
            st.markdown("**By probability alone**")
            st.dataframe(
                ranked.sort_values("probability_rank").head(15)[
                    [
                        "probability_rank",
                        "component_id",
                        "component_class_name",
                        "risk_probability",
                        "expected_loss_inr",
                        "anomaly_flag",
                    ]
                ],
                hide_index=True,
                width="stretch",
            )

        st.subheader("Evidence panel")
        cid = st.selectbox("Component", ranked["component_id"].tolist())
        row = ranked[ranked["component_id"] == cid].iloc[0]
        e1, e2, e3, e4 = st.columns(4)
        e1.metric("Risk (30-day)", f"{float(row.risk_probability):.1%}", row.risk_band)
        e2.metric(
            "Anomaly",
            "flagged" if bool(row.anomaly_flag) else "normal",
            f"distance {float(row.anomaly_distance):.2f}"
            if pd.notna(row.anomaly_distance)
            else None,
            help="A separate question: is this behaving unlike itself? Not failure prediction.",
        )
        e3.metric("Expected loss", inr(row.expected_loss_inr))
        e4.metric(
            "Part · lead time",
            inr(row.part_cost_inr),
            f"{int(row.lead_time_days or 0)} days{' · crane' if bool(row.requires_crane) else ''}",
        )

        drivers = _run(
            f"""select driver_rank, feature_name, direction, importance, component_value,
                       own_baseline_delta, importance_method
                from {q("ML.DRIVER_COMPONENT_RISK")} d
                join {q("ML.SCORE_COMPONENT_RISK")} s
                  on s.component_id = d.component_id and s.scored_date = d.scored_date
                where d.component_id = ?
                order by driver_rank""",
            params=[cid],
        )
        st.markdown("**Why — the drivers behind this score**")
        st.dataframe(drivers, hide_index=True, width="stretch")
        if not drivers.empty:
            st.caption(
                f"Importance method: `{drivers.iloc[0]['importance_method']}` — a train-split "
                "standardised difference, not a per-prediction attribution (I-8)."
            )

        series = _run(
            f"""select scored_date, primary_mean, expected_mean,
                   lower_bound, upper_bound, is_anomaly
                from {q("ML.SCORE_COMPONENT_ANOMALY")}
                where component_id = ? order by scored_date""",
            params=[cid],
        )
        if not series.empty:
            st.markdown("**Behaving unlike itself? — the anomaly detector's view**")
            base = alt.Chart(series).encode(x=alt.X("scored_date:T", title=None))
            band = base.mark_area(opacity=0.2).encode(
                y=alt.Y("lower_bound:Q", title="primary channel"), y2="upper_bound:Q"
            )
            line = base.mark_line().encode(y="primary_mean:Q")
            pts = (
                base.transform_filter("datum.is_anomaly")
                .mark_point(filled=True, size=60)
                .encode(
                    y="primary_mean:Q",
                    tooltip=["scored_date:T", "primary_mean:Q", "expected_mean:Q"],
                )
            )
            st.altair_chart((band + line + pts).properties(height=240), width="stretch")

# --------------------------------------------------------------------------- model
with t_model:
    m = _run(
        f"""select m.metric_scope, m.metric_name, m.metric_value, m.detail, r.run_id, r.trained_at
            from {q("OPS.ML_METRIC")} m
            join {q("OPS.ML_RUN")} r on r.run_id = m.run_id
            where r.run_id = (select max(run_id) from {q("OPS.ML_RUN")}
                              where model_name = 'RISK_CLASSIFIER')"""
    )
    if m.empty:
        st.warning("No evaluation recorded. Run `just deploy-ml`.")
    else:

        def mv(scope: str, name: str):
            s = m[(m.metric_scope == scope) & (m.metric_name == name)]["metric_value"]
            return None if s.empty else float(s.iloc[0])

        st.subheader("Rule versus model — on held-out data")
        st.caption(
            f"Training run `{m.iloc[0]['run_id']}`. Figures are read from OPS, never typed (T-87)."
        )
        cmp = pd.DataFrame(
            [
                {
                    "method": "Model (p ≥ 0.50)",
                    "precision": mv("MODEL", "precision_components"),
                    "recall": mv("MODEL", "recall_components"),
                },
                {
                    "method": "Trivial rule — CMS band energy ≥ p95",
                    "precision": mv("BL-TRIVIAL-THRESHOLD", "precision_components"),
                    "recall": mv("BL-TRIVIAL-THRESHOLD", "recall_components"),
                },
                {
                    "method": "Random, stratified",
                    "precision": mv("BL-RANDOM-STRATIFIED", "precision_components"),
                    "recall": mv("BL-RANDOM-STRATIFIED", "recall_components"),
                },
            ]
        )
        mp, rp = cmp.iloc[0]["precision"], cmp.iloc[1]["precision"]
        c1, c2, c3 = st.columns(3)
        c1.metric("Model precision", f"{mp:.3f}" if mp is not None else "—")
        c2.metric("Trivial rule precision", f"{rp:.3f}" if rp is not None else "—")
        c3.metric(
            "Advantage at equal recall",
            f"{mp / rp:.2f}×" if mp and rp else "—",
            help="Pass bar is 1.25× the rule and 3× random (T-10).",
        )
        st.altair_chart(
            alt.Chart(cmp.melt("method", var_name="measure"))
            .mark_bar()
            .encode(
                x=alt.X("value:Q", scale=alt.Scale(domain=[0, 1])),
                y=alt.Y("method:N", title=None),
                color="measure:N",
                yOffset="measure:N",
                tooltip=["method", "measure", "value"],
            )
            .properties(height=220),
            width="stretch",
        )
        st.dataframe(cmp, hide_index=True, width="stretch")

        ind = _run(
            f"""select metric_name, metric_value, detail from {q("OPS.ML_METRIC")}
                where metric_scope = 'ANOMALY' and run_id = (
                      select max(run_id) from {q("OPS.ML_RUN")}
                      where model_name = 'ANOMALY_DETECTOR')"""
        )
        if not ind.empty:
            rho = ind[ind.metric_name == "spearman_vs_risk"]["metric_value"]
            st.subheader("Two signals, not one")
            st.metric(
                "Spearman ρ, risk vs anomaly",
                f"{float(rho.iloc[0]):.3f}" if not rho.empty else "—",
                help="Pre-registered bound |ρ| ≤ 0.50 (T-18). The reference solution's two "
                "signals correlated at −1.0 by construction.",
            )

# --------------------------------------------------------------------------- fleet
with t_fleet:
    ld = _run(
        f"select * from {q('SERVING.MET_LD_EXPOSURE')} order by ld_exposure_run_rate_inr desc"
    )
    if ld.empty:
        st.warning("No serving views. Run `just deploy-engine`.")
    else:
        st.subheader("Contractual availability against the guarantee")
        st.caption(
            "Availability = available ÷ (period − exclusions). Grid, curtailment, force majeure, "
            "balance of plant and scheduled maintenance are excluded; corrective repair is not. "
            "LD exposure is a **run-rate** over the six-month window, not an invoice."
        )
        k1, k2 = st.columns(2)
        k1.metric("Fleet LD exposure (run-rate)", inr(ld["ld_exposure_run_rate_inr"].sum()))
        k2.metric("Sites below guarantee", int((ld["shortfall_pct"] > 0).sum()))
        st.altair_chart(
            alt.Chart(ld)
            .mark_bar()
            .encode(
                x=alt.X("availability_pct:Q", scale=alt.Scale(zero=False), title="availability %"),
                y=alt.Y("site_name:N", sort="-x", title=None),
                color=alt.condition(
                    "datum.shortfall_pct > 0", alt.value("#d9534f"), alt.value("#29B5E8")
                ),
                tooltip=[
                    "site_name",
                    "availability_pct",
                    "guarantee_pct",
                    "ld_exposure_run_rate_inr",
                ],
            )
            .properties(height=240),
            width="stretch",
        )
        st.dataframe(
            ld[
                [
                    "site_name",
                    "state",
                    "turbines",
                    "availability_pct",
                    "guarantee_pct",
                    "shortfall_pct",
                    "ld_exposure_run_rate_inr",
                ]
            ],
            hide_index=True,
            width="stretch",
        )
