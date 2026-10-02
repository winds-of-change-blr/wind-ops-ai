"""Drive the woa-github MCP server over stdio exactly as Cortex Code does, and record it.

    uv run --with 'mcp>=1.2,<2' python scripts/mcp_smoke.py <approved_wo> <selftest_wo> [out]

Three calls, three expected outcomes: FILED (or ALREADY_FILED), ALREADY_FILED on
the repeat (idempotency), REFUSED for a self-test row (the guard).
"""

from __future__ import annotations

import asyncio
import json
import sys
from pathlib import Path

from mcp import ClientSession, StdioServerParameters
from mcp.client.stdio import stdio_client


async def main(approved: str, selftest: str, out: Path) -> int:
    params = StdioServerParameters(command=sys.executable, args=["mcp/woa_github/server.py"])
    log: dict = {"tools": [], "calls": []}
    async with stdio_client(params) as (r, w), ClientSession(r, w) as s:
        await s.initialize()
        log["tools"] = [t.name for t in (await s.list_tools()).tools]
        for name, wo in [
            ("get_approved_work_order", approved),
            ("file_work_order_issue", approved),
            ("file_work_order_issue", approved),
            ("file_work_order_issue", selftest),
        ]:
            res = await s.call_tool(name, {"work_order_id": wo})
            text = res.content[0].text if res.content else ""
            try:
                body = json.loads(text)
            except json.JSONDecodeError:
                body = {"outcome": "ERROR", "is_error": res.isError, "text": text}
            log["calls"].append({"tool": name, "work_order_id": wo, "result": body})
            print(name, wo[:8], "->", body.get("outcome", body.get("status")), body.get("url", ""))
    out.write_text(json.dumps(log, indent=2, default=str) + "\n")
    outcomes = [c["result"].get("outcome") for c in log["calls"][1:]]
    ok = outcomes[0] in ("FILED", "ALREADY_FILED") and outcomes[1:] == ["ALREADY_FILED", "REFUSED"]
    print("PASS" if ok else f"FAIL {outcomes}")
    return 0 if ok else 1


if __name__ == "__main__":
    out = Path(sys.argv[3] if len(sys.argv) > 3 else "mcp_smoke.json")
    sys.exit(asyncio.run(main(sys.argv[1], sys.argv[2], out)))
