"""woa-github — a local MCP server that turns an APPROVED work order into a GitHub issue.

Why it exists (coco-usage-plan §4 row 5, ADR-0019): the approval happens in
Snowflake, but the crew coordinates in the issue tracker. This connector carries
one approved, audited decision across that boundary — and nothing else.

What it can and cannot do, by construction:
  * It READS Snowflake as WOA_PLANNER (read-only on ACTION; writes there only via
    the approval procedures, which this server never calls).
  * It FILES an issue only for a work order that exists, is APPROVED_*, is not a
    self-test row, and has an APPLIED audit row. Anything else is refused with
    the reason, so a draft or a rejected order can never reach the crew.
  * It is idempotent: the work-order id is in the title, and an existing open
    issue with that id is returned instead of a second one being filed.
  * It runs locally in Cortex Code Desktop only. The trial account has no
    external access integration, so nothing in Snowflake can reach GitHub.

Credentials: none in config. It shells out to `snow` (the named connection) and
`gh` (the user's keyring login). Inputs are validated before reaching either CLI.
"""

from __future__ import annotations

import json
import os
import re
import subprocess

from mcp.server.fastmcp import FastMCP

CONNECTION = os.environ.get("WOA_SNOW_CONNECTION", "jkdrjbb-mw27072")
DATABASE = os.environ.get("WOA_DATABASE", "WIND_OPS_AI")
REPO = os.environ.get("WOA_GITHUB_REPO", "winds-of-change-blr/wind-ops-ai")

_UUID = re.compile(r"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$")
_IDENT = re.compile(r"^[A-Z][A-Z0-9_]*$")

mcp = FastMCP("woa-github")


def _sql(query: str) -> list[dict]:
    """Run one read-only query as WOA_PLANNER and return rows."""
    if not _IDENT.match(DATABASE):
        raise ValueError(f"bad database name {DATABASE!r}")
    full = (
        f"use role WOA_PLANNER; use secondary roles none; use database {DATABASE}; "
        f"use warehouse WOA_APP_WH; {query}"
    )
    out = subprocess.run(
        ["snow", "sql", "-c", CONNECTION, "--format", "json", "-q", full],
        capture_output=True,
        text=True,
        timeout=120,
        check=True,
    ).stdout
    # Multi-statement output is a list of result sets; the query's is the last.
    return json.loads(out)[-1]


def _work_order(work_order_id: str) -> dict:
    if not _UUID.match(work_order_id):
        raise ValueError("work_order_id must be a work-order UUID")
    # No role can SELECT from ACTION (T-33); the read-only procedure is the
    # interface. The id is validated as a UUID above, so it is safe to inline.
    rows = _sql(f"call ACTION.SP_GET_WORK_ORDER('{work_order_id}')")
    raw = next(iter(rows[0].values())) if rows else None
    if not raw:
        raise LookupError(f"no work order {work_order_id}")
    return json.loads(raw)


def _refusal(wo: dict) -> str | None:
    if not str(wo["status"]).startswith("APPROVED"):
        return f"status is {wo['status']}, not approved"
    if str(wo["is_selftest"]).lower() in ("true", "1"):
        return "this is a verify self-test row, not a real approval"
    if not wo.get("audit_id"):
        return "no APPLIED audit row — an unaudited approval is not forwarded"
    return None


@mcp.tool()
def get_approved_work_order(work_order_id: str) -> dict:
    """Read one work order with its draft evidence and audit id. Read-only."""
    wo = _work_order(work_order_id)
    wo["fileable"] = _refusal(wo) is None
    wo["refusal"] = _refusal(wo)
    return wo


@mcp.tool()
def file_work_order_issue(work_order_id: str) -> dict:
    """File a GitHub issue for an APPROVED, audited work order. Idempotent; refuses otherwise."""
    wo = _work_order(work_order_id)
    # OBJECT_CONSTRUCT drops NULL keys, so unscheduled fields are simply absent.
    reason = _refusal(wo)
    if reason:
        return {"outcome": "REFUSED", "work_order_id": work_order_id, "reason": reason}

    title = f"[WO {work_order_id[:8]}] {wo['turbine_id']} {wo['component_class_name']} — approved"
    # Not `gh issue list --search`: the search index lags new issues by minutes,
    # so a quick retry would file twice (it did — evidence 14 §5). Match locally.
    issues = json.loads(
        subprocess.run(
            [
                "gh",
                "issue",
                "list",
                "-R",
                REPO,
                "--state",
                "all",
                "--limit",
                "500",
                "--json",
                "number,url,body",
            ],
            capture_output=True,
            text=True,
            timeout=60,
            check=True,
        ).stdout
    )
    existing = [
        {"number": i["number"], "url": i["url"]}
        for i in issues
        if work_order_id in (i.get("body") or "")
    ]
    existing.sort(key=lambda i: i["number"])
    if existing:
        return {"outcome": "ALREADY_FILED", "work_order_id": work_order_id, **existing[0]}

    def g(key: str) -> str:
        return str(wo.get(key) or "—")

    rows = [
        (
            "Turbine / component",
            f"{g('turbine_id')} / {g('component_id')} ({g('component_class_name')})",
        ),
        ("Site / crew", f"{g('site_code')} / {g('crew_id')}"),
        (
            "Risk",
            f"{g('risk_band')} (p={g('risk_probability')}), "
            f"expected loss INR {g('expected_loss_inr')}",
        ),
        ("Drivers", g("top_drivers")),
        ("Part / procedure", f"{g('part_number')} / {g('procedure_doc_id')}"),
        ("Window start", g("window_start")),
        ("Approved by", f"{g('approved_by')} as {g('approved_role')} at {g('approved_at')}"),
        ("Audit row", f"`ACTION.AUD_ACTION.AUDIT_ID = {g('audit_id')}`"),
    ]
    body = "\n".join(
        [
            f"Work order `{work_order_id}` was approved in Snowflake and is forwarded"
            " here for the crew.",
            "",
            "| Field | Value |",
            "| --- | --- |",
            *[f"| {k} | {v} |" for k, v in rows],
            "",
            "Synthetic data (hackathon). Filed by the `woa-github` MCP server from Cortex Code; "
            "it can read approvals and file this issue, nothing more.",
        ]
    )
    url = subprocess.run(
        ["gh", "issue", "create", "-R", REPO, "--title", title, "--body", body],
        capture_output=True,
        text=True,
        timeout=60,
        check=True,
    ).stdout.strip()
    return {
        "outcome": "FILED",
        "work_order_id": work_order_id,
        "url": url,
        "audit_id": wo["audit_id"],
    }


if __name__ == "__main__":
    mcp.run()
