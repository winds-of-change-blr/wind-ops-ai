"""Wind Ops AI — command center (Streamlit in Snowflake, ADR-0020).

SYNTHETIC DATA ONLY (AGENTS.md rule 5). Writes ONLY through the ACTION approval
procedures (ADR-0005): the app holds no DML, and every button that changes
something calls a procedure that re-validates, audits first, then writes.

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
import json
import os
import re
import uuid
from contextlib import contextmanager

import altair as alt
import pandas as pd
import streamlit as st

st.set_page_config(
    page_title="Wind Ops AI — Command Center", layout="wide", initial_sidebar_state="expanded"
)

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


def _fresh(sql: str, params: list | None = None) -> pd.DataFrame:
    """Uncached read, for ACTION state that must reflect the click just made."""
    df = _conn().session().sql(sql, params=params or []).to_pandas()
    df.columns = [c.lower() for c in df.columns]
    return df


def _viewer() -> str | None:
    # The app runs as its owner, so CURRENT_USER() inside a procedure cannot see
    # the person clicking. Their name is passed as ON_BEHALF_OF and recorded
    # BESIDE the authenticated caller, never instead of it (ADR-0020).
    try:
        return getattr(st.user, "user_name", None) or getattr(st.user, "email", None)
    except Exception:
        return None


def _key(action: str, subject: str) -> str:
    """One idempotency key per (action, subject) per browser session.

    A double-click or a rerun re-sends the SAME key, so the procedure returns
    DUPLICATE instead of writing twice (T-34). A new key is issued only after
    the user deliberately starts over.
    """
    slot = f"idem::{action}::{subject}"
    if slot not in st.session_state:
        st.session_state[slot] = f"APP-{uuid.uuid4()}"
    return st.session_state[slot]


def _call(proc: str, args: list) -> dict:
    """Call an ACTION procedure with bound arguments and return its result."""
    marks = ", ".join("?" for _ in args)
    row = _conn().session().sql(f"call {q(proc)}({marks})", params=args).collect()[0]
    return json.loads(row[0]) if isinstance(row[0], str) else dict(row[0])


def _show(result: dict) -> None:
    """Render a procedure outcome. Never claims a write that did not happen."""
    outcome, msg = result.get("outcome"), result.get("message") or ""
    if outcome == "APPLIED":
        st.success(f"**Done.** {msg}", icon=":material/check_circle:")
    elif outcome == "DUPLICATE":
        st.info(f"**Already done — nothing new written.** {msg}", icon=":material/content_copy:")
    else:
        st.error(f"**Refused.** {msg}", icon=":material/block:")


def _short(exc: BaseException) -> str:
    """One line of an error for a human: no traceback, no SQL, no HTML."""
    first = (str(exc).strip().splitlines() or [type(exc).__name__])[-1]
    return first[:200]


@contextmanager
def _degrade(what: str):
    """Contain a failure to the section it happened in (T-45).

    A failed read becomes one readable message and the rest of the page keeps
    working. Streamlit's own rerun/stop signals are BaseException, not
    Exception, so st.rerun() still passes straight through.
    """
    try:
        yield
    except Exception as exc:  # shown, never swallowed
        st.error(f"**{what} is unavailable right now.** {_short(exc)}", icon=":material/cloud_off:")
        st.caption("Other tabs keep working. The failed query is in Snowflake's query history.")


def _ask_agent(messages: list[dict]) -> dict:
    """One non-streaming run of the Cortex Agent over a whole conversation (FR-48).

    `messages` is the chat so far, oldest first, ending with the user's turn, so
    follow-ups ("and what part does it need?") keep their meaning. The agent has
    only read tools (T-48), so this cannot change anything. The agent name and
    the whole request body are bound, never interpolated.
    """
    body = json.dumps(
        {
            "messages": [
                {"role": m["role"], "content": [{"type": "text", "text": m["text"]}]}
                for m in messages
            ],
            "stream": False,
        }
    )
    row = (
        _conn()
        .session()
        .sql(
            "select snowflake.cortex.data_agent_run(?, ?) as r",
            params=[q("GEN.WOA_OPS_AGENT"), body],
        )
        .collect()[0]
    )
    answer = json.loads(row[0]) if isinstance(row[0], str) else dict(row[0])
    # DATA_AGENT_RUN does not raise for a missing agent or a denied role: it
    # returns {"code", "message"} with no content. Surface it as the failure it is,
    # rather than letting it render as an empty, "unsupported" answer.
    if "content" not in answer and answer.get("code"):
        raise RuntimeError(f"{answer.get('message', 'agent error')} (code {answer['code']})")
    return answer


def _parse_answer(answer: dict) -> dict:
    """Reduce an agent response to what the chat shows: text, tables, citations."""
    parts = answer.get("content") or []
    text = "\n\n".join(
        p["text"].strip() for p in parts if p.get("type") == "text" and p.get("text")
    )
    tables = []
    for p in parts:
        if p.get("type") != "table":
            continue
        rs = p["table"].get("result_set") or {}
        cols = [c["name"].lower() for c in (rs.get("resultSetMetaData") or {}).get("rowType", [])]
        if cols:
            tables.append(
                (
                    p["table"].get("title") or "From the fleet data",
                    pd.DataFrame(rs.get("data") or [], columns=cols),
                )
            )
    cites: dict[str, dict] = {}
    for p in parts:
        for a in p.get("annotations") or []:
            if a.get("type") == "cortex_search_citation":
                cites.setdefault(a.get("doc_id") or a.get("doc_title"), a)
    follow = [
        s["query"]
        for p in parts
        if p.get("type") == "suggested_queries"
        for s in p.get("suggested_queries") or []
        if s.get("query")
    ][:3]
    return {"text": text, "tables": tables, "cites": list(cites.values()), "follow": follow}


# What the user is looking at, registered by the tabs as they render and read by
# the sidebar assistant at the end of the script. label -> context sentence.
_ASK_CONTEXT: dict[str, str] = {"Fleet": "An operator is asking about the whole fleet."}


def _ask_context(kind: str, label: str, context: str) -> None:
    """Offer `label` to the assistant. A newly selected row becomes the default."""
    _ASK_CONTEXT[label] = context
    prev = st.session_state.get(f"ask_prev::{kind}")
    if prev is not None and prev != label:
        st.session_state["ask_about"] = label
    st.session_state[f"ask_prev::{kind}"] = label


def _render_turn(turn: dict) -> None:
    """One chat bubble. Tables and sources fold away: the sidebar is narrow."""
    with st.chat_message(turn["role"], avatar=None if turn["role"] == "user" else ":material/air:"):
        if turn["role"] == "user":
            st.markdown(turn["text"].replace("$", r"\$"))
            if turn.get("about") and turn["about"] != "Fleet":
                st.caption(f"about {turn['about']}")
            return
        if turn.get("error"):
            st.error(f"The agent could not answer: {turn['error'][:300]}", icon=":material/error:")
            return
        # Streamlit reads `$…$` as LaTeX; escape it so figures render as written.
        st.markdown(turn["text"].replace("$", r"\$") or "_The agent returned no text._")
        for title, df in turn["tables"]:
            with st.expander(f"{title} · {len(df)} row(s)", icon=":material/table:"):
                st.dataframe(
                    df, hide_index=True, width="stretch", height=min(38 + 35 * len(df), 260)
                )
        if turn["cites"]:
            with st.expander(f"Sources · {len(turn['cites'])}", icon=":material/menu_book:"):
                for c in turn["cites"]:
                    st.markdown(f"**{c.get('doc_title')}**  \n`{c.get('relative_path')}`")
                    st.caption((c.get("text") or "")[:300])
        elif not turn["tables"]:
            # FR-55: never pass an ungrounded answer off as grounded.
            st.warning(
                "No data table and no citation came back — treat as unsupported.",
                icon=":material/help:",
            )


def _assistant() -> None:
    """The Wind Ops Assistant, in the sidebar, for every tab (FR-48, FR-86).

    Context is the user's "Asking about" choice, defaulting to the row they most
    recently selected: Streamlit does not expose the active tab. The context is
    sent with each question, not stored in the history, so switching subject
    mid-conversation is honest about what each question was about.
    """
    h1, h2 = st.columns([3, 1], vertical_alignment="center")
    h1.markdown("**:material/forum: Assistant**")
    chat: list[dict] = st.session_state.setdefault("chat", [])
    if chat and h2.button("Clear", type="tertiary", key="chat_clear"):
        chat.clear()
        st.rerun()

    options = list(_ASK_CONTEXT)
    if st.session_state.get("ask_about") not in options:
        st.session_state["ask_about"] = "Fleet"
    about = st.selectbox("Asking about", options, key="ask_about")

    for turn in chat:
        _render_turn(turn)
    if not chat:
        st.caption(
            "Ask about risk, availability, LD exposure, alarms or a maintenance procedure. "
            "Answers cite the fleet data or the procedure they came from. Read-only."
        )

    pending = st.session_state.pop("chat_pending", None)
    last = chat[-1] if chat else None
    if last and last["role"] == "assistant" and last.get("follow") and not pending:
        for i, fq in enumerate(last["follow"]):
            if st.button(
                fq,
                key=f"chat_follow::{len(chat)}::{i}",
                icon=":material/subdirectory_arrow_right:",
                type="tertiary",
            ):
                st.session_state["chat_pending"] = fq
                st.rerun()

    typed = st.chat_input("Ask the Wind Ops Assistant", key="chat_input")
    question = (typed or pending or "").strip()
    if not question:
        return

    chat.append({"role": "user", "text": question, "about": about})
    _render_turn(chat[-1])
    # Only complete, answered pairs go back to the agent; a failed turn is dropped.
    history = []
    for u, a in zip(chat[:-1:2], chat[1:-1:2], strict=False):
        if u["role"] == "user" and a["role"] == "assistant" and a.get("text"):
            history += [
                {"role": "user", "text": u["text"]},
                {"role": "assistant", "text": a["text"]},
            ]
    history.append({"role": "user", "text": f"{_ASK_CONTEXT[about]}\n\nQuestion: {question}"})
    with st.spinner("Reading the fleet data and the maintenance documents…"):
        try:
            turn = {"role": "assistant", **_parse_answer(_ask_agent(history))}
        except Exception as exc:  # shown, never swallowed
            turn = {"role": "assistant", "text": "", "error": str(exc)}
    chat.append(turn)
    st.rerun()


def inr(x) -> str:
    if x is None or pd.isna(x):
        return "—"
    x = float(x)
    if abs(x) >= 1e7:
        return f"₹{x / 1e7:,.2f} Cr"
    if abs(x) >= 1e5:
        return f"₹{x / 1e5:,.2f} L"
    return f"₹{x:,.0f}"


# --------------------------------------------------------------------------- frame
# Every tab needs these. If they fail there is no page to degrade to, so say so
# once, plainly, and stop (T-45).
try:
    asof = _run(f"select as_of_date, data_end_date, horizon_days from {q('ML.V_SCORING_ASOF')}")
    as_of = asof.iloc[0]["as_of_date"] if not asof.empty else None
    funnel = _run(f"select * from {q('ENGINE.ENG_ALARM_FUNNEL')}")
    fleet = _run(
        f"""select count(*) as turbines, count(distinct site_code) as sites
            from {q("SERVING.MET_AVAILABILITY_CONTRACTUAL")}"""
    )
    site_list = _run(
        f"select distinct site_code from {q('ENGINE.ENG_INCIDENT')} order by site_code"
    )["site_code"].tolist()
except Exception as exc:
    st.error(
        f"**The command center cannot reach its data right now.** {_short(exc)}",
        icon=":material/cloud_off:",
    )
    st.caption("Check the connection and that the stack is deployed (`just verify`).")
    st.stop()
SEVERITIES = ["TRIP", "ALARM", "WARNING"]


def _reset_filters() -> None:
    st.session_state["f_sites"] = site_list
    st.session_state["f_sev"] = SEVERITIES
    st.session_state["q_search"] = ""


with st.sidebar:
    st.markdown("**:material/air: Wind Ops AI**  \nVayuveda Wind Systems")
    # One line, so the assistant below gets the height.
    if as_of is not None:
        st.caption(
            f"Risk scored as of **{as_of}** · data ends **{asof.iloc[0]['data_end_date']}** · "
            f"{int(asof.iloc[0]['horizon_days'])} days ahead",
            help="A prediction can only be checked if that much future exists (I-13).",
        )
    else:
        st.caption("No scoring run yet.")
    fh1, fh2 = st.columns([3, 1], vertical_alignment="bottom")
    fh1.caption("Filters")
    fh2.button("Reset", on_click=_reset_filters, type="tertiary")
    sel_sites = st.pills(
        "Sites", site_list, selection_mode="multi", default=site_list, key="f_sites"
    )
    sel_sev = st.pills(
        "Severity", SEVERITIES, selection_mode="multi", default=SEVERITIES, key="f_sev"
    )
    fleet_note = (
        f"**Fleet** · {int(fleet.iloc[0]['turbines'])} turbines · "
        f"{int(fleet.iloc[0]['sites'])} sites · "
        if not fleet.empty
        else ""
    )
    st.caption(fleet_note + "**Data** · synthetic — the system is not")
    st.divider()
    # Filled at the end of the script, once the tabs have registered what is
    # selected on them (_ask_context).
    assistant_slot = st.container()

sel_sites = sel_sites or []
sel_sev = sel_sev or []
sites_json = json.dumps(sel_sites)
sev_json = json.dumps(sel_sev)
filtered_note = (
    ""
    if set(sel_sites) == set(site_list)
    else f"Filtered to {len(sel_sites)} of {len(site_list)} sites."
)

st.title("Command Center")
h1, h2 = st.columns([3, 2], vertical_alignment="center")
h1.caption("Alarm triage, failure risk and model evidence for the Vayuveda fleet")
with h2.container(horizontal=True, horizontal_alignment="right"):
    st.badge("Synthetic data", icon=":material/science:", color="violet")
    if as_of is not None:
        st.badge(
            f"Scored as of {as_of} · data ends {asof.iloc[0]['data_end_date']}",
            icon=":material/event:",
            color="gray",
        )

actionable_badge = f" · {int(funnel.iloc[0]['actionable']):,}" if not funnel.empty else ""
t_alarms, t_triage, t_model, t_fleet, t_audit = st.tabs(
    [
        f":material/notifications: Alarms{actionable_badge}",
        ":material/warning: Risk triage",
        ":material/science: Is the model real?",
        ":material/wind_power: Fleet & contracts",
        ":material/history: Audit",
    ]
)

VERDICT = {
    "SUPPORTS_ACTIONABLE": "Actionable",
    "SUPPORTS_NUISANCE": "Nuisance",
    "NO_EVIDENCE": "No evidence",
}
FILTER_SQL = """site_code in (select value::varchar from table(flatten(parse_json(?))))
               and severity in (select value::varchar from table(flatten(parse_json(?))))
               and (? = '' or turbine_id ilike ? or alarm_code ilike ? or alarm_name ilike ?
                    or coalesce(component_id, '') ilike ?)"""

# --------------------------------------------------------------------------- alarms
with t_alarms, _degrade("The alarm queue"):
    if funnel.empty:
        st.warning("The alarm engine has not been built. Run `just deploy-engine`.")
    else:
        r = funnel.iloc[0]
        queued = int(r.actionable) + int(r.undetermined)
        st.subheader("A flood of alarms becomes a short, honest list")
        st.caption("Whole scoring window · all sites (the funnel is not filtered)")
        f1, f2, f3, f4 = st.columns(4)
        with f1.container(border=True):
            st.metric("1 · Raw alarms", f"{int(r.raw_alarms):,}")
            st.caption("every code, every turbine")
            st.progress(1.0)
        with f2.container(border=True):
            st.metric(
                "2 · Incidents",
                f"{int(r.incidents):,}",
                f"{int(r.raw_alarms) / max(int(r.incidents), 1):.1f} : 1",
                delta_color="off",
            )
            st.caption("grouped by asset + code")
            st.progress(min(1.0, int(r.incidents) / max(int(r.raw_alarms), 1) * 10))
        with f3.container(border=True):
            st.metric(
                "3 · In queue",
                f"{queued:,}",
                f"−{int(r.nuisance):,}",
                delta_color="off",
            )
            st.caption("engine-classed nuisance removed")
            st.progress(min(1.0, queued / max(int(r.raw_alarms), 1) * 10))
        with f4.container(border=True):
            st.metric("4 · Actionable", f"{int(r.actionable):,}")
            st.caption(f"+ {int(r.undetermined):,} undetermined, ranked below")
            st.progress(min(1.0, int(r.actionable) / max(int(r.raw_alarms), 1) * 10))
        # The anti-gaming rule: compression and failures-suppressed, together (T-70).
        g1, g2, g3 = st.columns(3)
        g1.metric(
            "Compression",
            f"{r.compression_ratio} : 1",
            help="Raw alarms per queued incident. Trivially achieved by suppressing "
            "everything, so it is never shown without the next number.",
            border=True,
        )
        g2.metric(
            "Real failures suppressed",
            int(r.real_failures_suppressed),
            help="The number that must stay zero.",
            border=True,
        )
        g3.metric(
            "Undetermined rate",
            f"{float(r.undetermined_rate):.1%}",
            help="Published, not buried — a rising rate means the evidence base is degrading.",
            border=True,
        )

        st.subheader("Incident queue")
        st.caption("Select a row to see why it was classed and whether it can be suppressed.")
        c_view, c_search = st.columns([1, 2], vertical_alignment="bottom")
        view = c_view.segmented_control(
            "Show",
            ["Queue", "Nuisance"],
            default="Queue",
            key="q_view",
            label_visibility="collapsed",
        )
        search = c_search.text_input(
            "Search",
            key="q_search",
            placeholder="Turbine, alarm code, name or component",
            label_visibility="collapsed",
        )
        like = f"%{(search or '').strip()}%"
        fparams = [sites_json, sev_json, (search or "").strip(), like, like, like, like]
        cols = """incident_id, incident_class, severity, alarm_name, alarm_code, turbine_id,
                  site_code, component_id, incident_start, n_alarms, is_safety_critical,
                  is_corroborated, is_elevated, all_auto_reset, class_reason"""
        if (view or "Queue") == "Queue":
            queue = _run(
                f"""select queue_rank, {cols}, count(*) over () as n_match
                    from {q("ENGINE.ENG_OPERATOR_QUEUE")}
                    where {FILTER_SQL}
                    order by queue_rank limit 200""",
                params=fparams,
            )
            scope = f"of {queued:,} in the queue"
            tail = "Undetermined ranks below actionable — never hidden, never suppressible."
        else:
            queue = _run(
                f"""select row_number() over (order by incident_start desc) as queue_rank,
                           {cols}, count(*) over () as n_match
                    from {q("ENGINE.ENG_INCIDENT")}
                    where incident_class = 'NUISANCE' and {FILTER_SQL}
                    order by incident_start desc limit 200""",
                params=fparams,
            )
            scope = f"of {int(r.nuisance):,} engine-classed nuisance"
            tail = "The only suppression candidates."
        n_match = int(queue["n_match"].iloc[0]) if not queue.empty else 0
        st.caption(
            f"Showing **{len(queue):,}** of {n_match:,} matching ({scope}). {tail} {filtered_note}"
        )
        shown = queue.drop(columns=["n_match", "incident_id"], errors="ignore")
        event = st.dataframe(
            shown,
            hide_index=True,
            width="stretch",
            height=360,
            on_select="rerun",
            selection_mode="single-row",
            key="q_table",
            column_config={
                "queue_rank": st.column_config.NumberColumn("#", width="small"),
                "incident_class": st.column_config.TextColumn("Class"),
                "severity": st.column_config.TextColumn("Severity"),
                "alarm_name": st.column_config.TextColumn("Alarm"),
                "alarm_code": st.column_config.TextColumn("Code"),
                "turbine_id": st.column_config.TextColumn("Turbine"),
                "site_code": None,
                "component_id": st.column_config.TextColumn("Component"),
                "incident_start": st.column_config.DatetimeColumn("Started", format="MM-DD HH:mm"),
                "n_alarms": st.column_config.NumberColumn("Alarms"),
                "is_safety_critical": st.column_config.CheckboxColumn("Safety"),
                "is_corroborated": st.column_config.CheckboxColumn("Corrob."),
                "is_elevated": st.column_config.CheckboxColumn("Elevated"),
                "all_auto_reset": None,
                "class_reason": st.column_config.TextColumn("Why this class", width="large"),
            },
        )
        if queue.empty:
            st.info("No incidents match these filters.", icon=":material/filter_alt_off:")
        else:
            rows = event.selection.rows if event and event.selection else []
            d = queue.iloc[rows[0] if rows else 0]
            iid = d["incident_id"]
            risk = _run(
                f"""select count_if(risk_band in ('HIGH', 'MEDIUM')) as n_risky,
                           coalesce(max(iff(risk_band = 'HIGH', 'HIGH', null)),
                                    max(iff(risk_band = 'MEDIUM', 'MEDIUM', null)), 'LOW') as band
                    from {q("ENGINE.ENG_ALERT_RANKED")} where turbine_id = ?""",
                params=[d["turbine_id"]],
            ).iloc[0]

            left, right = st.columns([3, 2])
            with left.container(border=True):
                st.markdown(f"**Why was it classed this way?** — {d['alarm_name']}")
                with st.container(horizontal=True):
                    st.badge(
                        d["incident_class"],
                        color="violet" if d["incident_class"] == "ACTIONABLE" else "gray",
                    )
                    st.badge(d["severity"], color="gray")
                    if bool(d["is_safety_critical"]):
                        st.badge("Safety-critical", icon=":material/shield:", color="red")
                    st.badge(
                        f"Turbine risk {risk['band']}",
                        color="orange" if risk["band"] != "LOW" else "gray",
                    )
                st.caption(
                    f"{d['turbine_id']} · {d['component_id'] or 'no component'} · "
                    f"{d['incident_start']} · {int(d['n_alarms'])} alarm(s) · `{iid}`"
                )
                st.markdown(f"**Rule applied** — {d['class_reason']}")
                ev = _run(
                    f"""select channel, verdict, measured_value, reference_value, detail
                        from {q("ENGINE.ENG_INCIDENT_EVIDENCE")}
                        where incident_id = ?
                        order by decode(channel, 'CORROBORATION', 1, 'OPERATING_POINT', 2,
                                        'RESET_RECURRENCE', 3, 4)""",
                    params=[iid],
                )
                if ev.empty:
                    st.caption("No stored evidence rows for this incident.")
                else:
                    ev["verdict"] = ev["verdict"].map(VERDICT).fillna(ev["verdict"])
                    tally = ev["verdict"].value_counts()
                    st.markdown(
                        "**Evidence channels** — "
                        + " · ".join(
                            f"{int(tally.get(k, 0))} {k.lower()}"
                            for k in ("Actionable", "Nuisance", "No evidence")
                        )
                    )
                    st.dataframe(
                        ev,
                        hide_index=True,
                        width="stretch",
                        column_config={
                            "channel": "Channel",
                            "verdict": "Verdict",
                            "measured_value": st.column_config.NumberColumn("Measured"),
                            "reference_value": st.column_config.NumberColumn("Reference"),
                            "detail": st.column_config.TextColumn("Detail", width="large"),
                        },
                    )
                    st.caption(
                        "Measured against reference. The four channels ADR-0017 weighs, "
                        "stored so a human can disagree (T-68)."
                    )
                _ask_context(
                    "incident",
                    f"Incident · {d['turbine_id']} · {d['alarm_code']}",
                    f"An RMC engineer is looking at alarm incident {iid}: {d['alarm_code']} "
                    f"({d['alarm_name']}) on turbine {d['turbine_id']}, component "
                    f"{d['component_id'] or 'unknown'}, severity {d['severity']}, started "
                    f"{d['incident_start']}, engine class {d['incident_class']}. "
                    "Answer about this incident and this turbine.",
                )

            with right.container(border=True):
                st.markdown("**Suppress this incident**")
                st.caption(
                    "Suppression is the one action that can hide a real failure. The procedure "
                    "re-checks every gate itself — time-boxed, audited, reversible. Refusals are "
                    "recorded too."
                )
                # Display only: mirrors SP_APPROVE_SUPPRESSION's guards in its order.
                # The procedure stays the authority and re-checks every one.
                gates = [
                    ("Not a safety-critical code", not bool(d["is_safety_critical"])),
                    ("No elevated evidence on asset", not bool(d["is_elevated"])),
                    ("No MEDIUM/HIGH risk on the turbine", int(risk["n_risky"]) == 0),
                    ("Engine-classed NUISANCE", d["incident_class"] == "NUISANCE"),
                ]
                for label, ok in gates:
                    st.markdown(
                        f":material/{'check_circle' if ok else 'cancel'}: {label}"
                        if ok
                        else f":gray[:material/cancel: {label}]"
                    )
                failing = sum(1 for _, ok in gates if not ok)
                if failing == 0:
                    st.success(
                        "Eligible — a request will be granted, time-boxed and audited.",
                        icon=":material/lock_open:",
                    )
                else:
                    st.warning(
                        f"Not eligible — a request will be refused and recorded "
                        f"({failing} gate{'s' if failing > 1 else ''} failing).",
                        icon=":material/lock:",
                    )
                with st.form("suppress", border=False):
                    reason = st.text_input(
                        "Reason (required)", placeholder="Why is this noise? At least 10 characters"
                    )
                    hours = st.number_input("Hours", min_value=1, max_value=168, value=24)
                    sent = st.form_submit_button(
                        f"Request suppression for {d['turbine_id']} · {d['alarm_code']}",
                        icon=":material/notifications_off:",
                    )
                if sent:
                    st.session_state["n_requests"] = st.session_state.get("n_requests", 0) + 1
                    _show(
                        _call(
                            "ACTION.SP_APPROVE_SUPPRESSION",
                            [iid, int(hours), reason, _key("suppress", iid), _viewer()],
                        )
                    )

        active = _fresh(
            f"""select suppression_id, incident_id, turbine_id, alarm_code, reason,
                       approved_by, on_behalf_of, approved_at, expires_at
                from {q("ACTION.ACT_V_SUPPRESSION_ACTIVE")} order by approved_at desc"""
        )
        with st.container(border=True):
            st.markdown(
                f"**Active suppressions · {len(active)}** — "
                f"{st.session_state.get('n_requests', 0)} request(s) this session"
            )
            if active.empty:
                st.caption(
                    "None. Engine-classed nuisance incidents are the only eligible candidates — "
                    "switch the queue to Nuisance to find one."
                )
            else:
                for srow in active.itertuples():
                    a1, a2 = st.columns([4, 1], vertical_alignment="center")
                    a1.markdown(
                        f"**{srow.turbine_id} · {srow.alarm_code}** — until {srow.expires_at} · "
                        f"“{srow.reason}” · by {srow.on_behalf_of or srow.approved_by}"
                    )
                    if a2.button("Lift", key=f"lift_{srow.suppression_id}", icon=":material/undo:"):
                        _show(
                            _call(
                                "ACTION.SP_REVOKE_SUPPRESSION",
                                [
                                    srow.suppression_id,
                                    "Lifted from the command center by the operator",
                                    _key("revoke", srow.suppression_id),
                                    _viewer(),
                                ],
                            )
                        )

# --------------------------------------------------------------------------- triage
with t_triage, _degrade("Risk triage"):
    ranked = _run(
        f"""select money_rank, probability_rank, component_id, turbine_id, site_code,
                   component_class_name, risk_probability, risk_band, anomaly_flag,
                   anomaly_distance, top_drivers, part_cost_inr, lead_time_days,
                   requires_crane, downtime_days_illustrative, downtime_ld_cost_inr,
                   expected_loss_inr
            from {q("ENGINE.ENG_ALERT_RANKED")}
            order by money_rank"""
    )
    ranked = ranked[ranked["site_code"].isin(sel_sites)] if not ranked.empty else ranked
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
        _ask_context(
            "component",
            f"Component · {cid}",
            f"A reliability engineer is looking at component {cid}: 30-day failure risk "
            f"{float(row.risk_probability):.1%} ({row.risk_band}), expected loss "
            f"{inr(row.expected_loss_inr)}. Answer about this component.",
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

        st.subheader("Work order")
        st.caption(
            "A draft is made only for MEDIUM or HIGH risk, and carries the evidence as it "
            "stands now. Approval re-checks that evidence against the engine and writes one "
            "work order, however many times it is clicked. A draft gets a window, crew and "
            "crane only when a planner accepts a schedule suggestion below."
        )
        if st.button("Draft a work order", icon=":material/edit_note:"):
            _show(_call("ACTION.SP_DRAFT_WORK_ORDER", [cid, _key("draft", cid), _viewer()]))
        drafts = _fresh(
            f"""select d.draft_id, d.status, d.scope, d.part_number, d.part_name,
                       d.part_lead_time_days, d.requires_crane, d.stock_on_hand,
                       d.procedure_doc_id, d.procedure_section, d.risk_band, d.risk_probability,
                       d.expected_loss_inr, d.risk_as_of_date, d.window_status, d.window_note,
                       d.drafted_by, d.drafted_at, w.work_order_id, w.approved_by, w.approved_at
                from {q("ACTION.ACT_WORK_ORDER_DRAFT")} d
                left join {q("ACTION.ACT_WORK_ORDER")} w on w.draft_id = d.draft_id
                where d.component_id = ? and not d.is_selftest
                order by d.drafted_at desc limit 5""",
            params=[cid],
        )
        if not drafts.empty:
            d = drafts.iloc[0]
            st.markdown(f"**Latest draft — {d.status}**")
            st.write(d.scope)
            w1, w2, w3, w4 = st.columns(4)
            w1.metric("Part", d.part_number, d.part_name)
            w2.metric(
                "Lead time · stock",
                f"{int(d.part_lead_time_days or 0)} days",
                f"{int(d.stock_on_hand or 0)} on hand"
                + (" · crane" if bool(d.requires_crane) else ""),
            )
            w3.metric("Procedure", d.procedure_doc_id, d.procedure_section)
            w4.metric("Window", d.window_status)
            st.caption(d.window_note)
            if d.status == "DRAFT":
                a1, a2, a3 = st.columns([1, 1, 2])
                if a1.button("Approve", type="primary", icon=":material/task_alt:"):
                    _show(
                        _call(
                            "ACTION.SP_APPROVE_WORK_ORDER",
                            [d.draft_id, _key("approve", d.draft_id), _viewer()],
                        )
                    )
                code = a3.selectbox(
                    "Reject reason",
                    [
                        "NOT_NEEDED",
                        "ALREADY_PLANNED",
                        "EVIDENCE_DISPUTED",
                        "DUPLICATE_DRAFT",
                        "OTHER",
                    ],
                )
                note = a3.text_input("Note (required for OTHER)", key="reject_note")
                if a2.button("Reject", icon=":material/close:"):
                    _show(
                        _call(
                            "ACTION.SP_REJECT_WORK_ORDER_DRAFT",
                            [d.draft_id, code, note, _key("reject", d.draft_id), _viewer()],
                        )
                    )
            elif pd.notna(d.work_order_id):
                st.success(
                    f"Work order `{d.work_order_id}` approved by {d.approved_by} at "
                    f"{d.approved_at}. Window: {d.window_status}.",
                    icon=":material/assignment_turned_in:",
                )

    # ------------------------------------------------------------- planning
    plan = _fresh(
        f"""select s.suggestion_id, s.suggestion_type, s.site_code, s.crew_id, s.start_day,
                   s.end_day, s.component_count, s.mobilisations_saved,
                   s.expected_loss_covered_inr, s.planned_downtime_mwh, s.binding_constraint,
                   s.reasoning, s.plan_start,
                   listagg(i.component_id, ', ') within group (order by i.start_day) as components,
                   listagg(i.earliest_limited_by, ' | ') within group (order by i.start_day)
                       as limited_by,
                   max(dc.decision) as decision
            from {q("ENGINE.ENG_SUGGESTION")} s
            join {q("ENGINE.ENG_SUGGESTION_ITEM")} i on i.suggestion_id = s.suggestion_id
            left join {q("ACTION.ACT_DECISION")} dc
                   on dc.subject_id = s.suggestion_id and not dc.is_selftest
            group by all
            order by decode(s.suggestion_type, 'BUNDLE', 0, 'SCHEDULE', 1, 2), s.start_day"""
    )
    if not plan.empty:
        st.subheader("Planning — windows the engine can vouch for")
        st.caption(
            f"Rolling 12 weeks from {plan.iloc[0]['plan_start']}. Every window passed all six "
            "constraints (forecast wind, crew certification and commitments, part in hand, "
            "crane mobilisation, horizon); nothing here was proposed by a model. Forecast, "
            "crews and crane bookings are synthetic."
        )
        impact = _fresh(f"select * from {q('ENGINE.ENG_PLAN_IMPACT')}")
        if not impact.empty:
            im = impact.iloc[0]
            p1, p2, p3, p4 = st.columns(4)
            p1.metric("Expected loss covered", f"₹{im.covered_expected_loss_inr / 1e5:,.1f} L")
            p2.metric("Left uncovered", f"₹{im.uncovered_expected_loss_inr / 1e5:,.1f} L")
            p3.metric("Crane mobilisations saved", int(im.crane_mobilisations_saved))
            p4.metric("Energy the work costs", f"{im.planned_downtime_mwh:,.1f} MWh")
        st.dataframe(
            plan[
                [
                    "suggestion_type",
                    "site_code",
                    "components",
                    "crew_id",
                    "start_day",
                    "end_day",
                    "expected_loss_covered_inr",
                    "binding_constraint",
                    "limited_by",
                    "decision",
                ]
            ],
            hide_index=True,
            width="stretch",
        )
        open_plan = plan[(plan.suggestion_type != "INFEASIBLE") & plan.decision.isna()]
        if not open_plan.empty:
            label = {
                r.suggestion_id: f"{r.suggestion_type} · {r.site_code} · {r.components}"
                for r in open_plan.itertuples()
            }
            sid = st.selectbox("Suggestion", list(label), format_func=label.get)
            st.caption(open_plan.set_index("suggestion_id").loc[sid, "reasoning"])
            b1, b2, b3 = st.columns([1, 1, 2])
            if b1.button("Accept schedule", type="primary", icon=":material/event_available:"):
                _show(_call("ACTION.SP_ACCEPT_SUGGESTION", [sid, _key("accept", sid), _viewer()]))
            reason = b3.selectbox(
                "Reject reason",
                [
                    "CREW_PREFERENCE",
                    "CUSTOMER_OUTAGE",
                    "BUNDLE_DIFFERENTLY",
                    "RISK_DISPUTED",
                    "OTHER",
                ],
                key="plan_reason",
            )
            pnote = b3.text_input("Note (required for OTHER)", key="plan_note")
            if b2.button("Reject", icon=":material/event_busy:", key="plan_reject"):
                _show(
                    _call(
                        "ACTION.SP_REJECT_SUGGESTION",
                        [sid, reason, pnote, _key("reject_plan", sid), _viewer()],
                    )
                )
            st.caption(
                "Accepting schedules drafts that already exist — draft each component's work "
                "order first. It is refused if the engine no longer vouches for the window."
            )

        with st.expander("Why not sooner? Per-constraint results for one component"):
            comps = sorted(
                {c.strip() for cs in plan.components for c in str(cs).split(",") if c.strip()}
            )
            pick = st.selectbox("Component", comps, key="plan_comp")
            cand = _run(
                f"""select start_day, crew_id, is_feasible, weather_ok, crew_certified,
                           crew_available, part_available, mobilisation_ok, within_horizon,
                           max_forecast_gust_ms, gust_limit_ms, part_source, crew_conflict
                    from {q("ENGINE.ENG_WINDOW_CANDIDATE")}
                    where component_id = ? and crew_certified
                    order by start_day, crew_id""",
                params=[pick],
            )
            st.dataframe(cand, hide_index=True, width="stretch", height=300)

# --------------------------------------------------------------------------- model
with t_model, _degrade("The model evaluation"):
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
with t_fleet, _degrade("Fleet & contracts"):
    ld = _run(
        f"select * from {q('SERVING.MET_LD_EXPOSURE')} order by ld_exposure_run_rate_inr desc"
    )
    ld = ld[ld["site_code"].isin(sel_sites)] if not ld.empty else ld
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

    oee = _run(
        f"""select o.turbine_id, o.site_code, o.availability_factor, o.performance_factor,
                   o.oee, o.is_underperforming, o.mean_yaw_error_deg, o.fleet_median_performance,
                   o.oee_definition, l.lost_mwh_downtime, l.lost_mwh_underperformance,
                   l.lost_mwh_total
            from {q("SERVING.MET_TURBINE_OEE")} o
            join {q("SERVING.MET_LOST_ENERGY")} l on l.turbine_id = o.turbine_id
            order by o.performance_factor"""
    )
    if not oee.empty:
        st.subheader("Turbine OEE — and what it catches that availability cannot")
        # The definition is shown, not footnoted: this is our adaptation (ADR-0003).
        st.caption(oee.iloc[0]["oee_definition"])
        o1, o2, o3, o4 = st.columns(4)
        o1.metric("Mean OEE (A × P)", f"{oee['oee'].mean():.1%}")
        o2.metric("Mean availability factor", f"{oee['availability_factor'].mean():.1%}")
        o3.metric(
            "Fleet-median performance",
            f"{float(oee.iloc[0]['fleet_median_performance']):.1%}",
            help="Against the ideal power curve, so a healthy turbine reads about 96.5%.",
        )
        o4.metric("Energy lost", f"{oee['lost_mwh_total'].sum():,.0f} MWh")

        under = oee[oee["is_underperforming"]]
        st.markdown(
            f"**{len(under)} turbine(s) underperforming while available** — losing energy "
            "while running, with no alarm raised. Availability alone would call them healthy."
        )
        st.dataframe(
            under[
                [
                    "turbine_id",
                    "site_code",
                    "availability_factor",
                    "performance_factor",
                    "oee",
                    "mean_yaw_error_deg",
                    "lost_mwh_underperformance",
                ]
            ],
            hide_index=True,
            width="stretch",
        )
        # Degrades to a table that keeps the number (NFR-22): the scatter is extra.
        st.altair_chart(
            alt.Chart(oee)
            .mark_circle(size=70)
            .encode(
                x=alt.X(
                    "availability_factor:Q",
                    scale=alt.Scale(zero=False),
                    title="availability factor",
                ),
                y=alt.Y(
                    "performance_factor:Q",
                    scale=alt.Scale(zero=False),
                    title="performance factor",
                ),
                color=alt.Color("is_underperforming:N", title="underperforming"),
                tooltip=["turbine_id", "availability_factor", "performance_factor", "oee"],
            )
            .properties(height=260),
            width="stretch",
        )

# --------------------------------------------------------------------------- audit
with t_audit, _degrade("The audit trail"):
    st.subheader("Who decided what, when, and on what evidence")
    st.caption(
        "Every request to the ACTION procedures is appended here **before** anything "
        "changes \u2014 refusals included. If this append fails, the write fails (ADR-0005). "
        "Self-test rows from `just verify` are hidden."
    )
    aud = _fresh(
        f"""select event_at, action_type, outcome, object_id, reason, actor_user, actor_role,
                   on_behalf_of, idempotency_key, evidence
            from {q("ACTION.AUD_ACTION")}
            where not is_selftest
            order by event_at desc limit 200"""
    )
    if aud.empty:
        st.info(
            "Nothing has been requested yet. Try suppressing an alarm or drafting a work order."
        )
    else:
        k1, k2, k3 = st.columns(3)
        k1.metric("Requests", len(aud))
        k2.metric("Applied", int((aud["outcome"] == "APPLIED").sum()))
        k3.metric("Refused", int((aud["outcome"] == "REFUSED").sum()))
        st.dataframe(aud, hide_index=True, width="stretch")

# --------------------------------------------------------------------------- assistant
# Last, so every tab has registered its selection. Draws into the sidebar slot.
with assistant_slot, _degrade("The assistant"):
    _assistant()
