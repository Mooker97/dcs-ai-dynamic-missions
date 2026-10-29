"""dms-mcp over real stdio: spawn the console script and drive all six tools with the MCP client.

This is what Claude Code does with ``.mcp.json``. The server runs against a temp repo root
(``DMS_ROOT``) holding a copy of campaigns/viper-detachment and a pre-bundled ``dist/dms.lua``, so
plan/build outputs never land in the real campaign folder.
"""

from __future__ import annotations

import asyncio
import json
import os
import shutil
import sys
from pathlib import Path
from typing import Any

import pytest
from dms_cli.util import find_root
from dms_mcp import ops
from mcp import ClientSession, StdioServerParameters
from mcp.client.stdio import stdio_client

ROOT = find_root(Path(__file__).parent)
SLUG = "viper-detachment"
CAMPAIGN = ROOT / "campaigns" / SLUG
TOOLS = {"validate", "plan", "build", "check", "schema", "campaign_status"}

pytestmark = pytest.mark.skipif(not CAMPAIGN.is_dir(), reason=f"campaigns/{SLUG} missing")


def _server_command() -> list[str]:
    """The installed ``dms-mcp`` console script next to this interpreter (what ``uv run`` runs)."""
    bindir = Path(sys.executable).parent
    for name in ("dms-mcp.exe", "dms-mcp"):
        exe = bindir / name
        if exe.is_file():
            return [str(exe)]
    return [sys.executable, "-m", "dms_mcp.server"]


@pytest.fixture(scope="module")
def fake_root(tmp_path_factory: pytest.TempPathFactory) -> Path:
    root = tmp_path_factory.mktemp("mcp-stdio") / "repo"
    shutil.copytree(
        CAMPAIGN, root / "campaigns" / SLUG, ignore=shutil.ignore_patterns("out", "voice")
    )
    ops.bundle_lua(ROOT, root / "dist" / "dms.lua")
    # missions with `plugins:` resolve lua/plugins/... against the repo root
    shutil.copytree(ROOT / "lua" / "plugins", root / "lua" / "plugins")
    return root


def _payload(result: Any) -> dict[str, Any]:
    """Structured tool output (FastMCP wraps dict returns), else the JSON text block."""
    assert not result.isError, result.content
    data = result.structuredContent
    if isinstance(data, dict):
        inner = data.get("result", data)
        if isinstance(inner, dict):
            return inner
    text = "".join(getattr(c, "text", "") for c in result.content)
    parsed: dict[str, Any] = json.loads(text)
    return parsed


async def _session_run(root: Path) -> dict[str, Any]:
    cmd = _server_command()
    params = StdioServerParameters(
        command=cmd[0],
        args=cmd[1:],
        env={**os.environ, ops.ROOT_ENV: str(root)},
        cwd=str(ROOT),
    )
    out: dict[str, Any] = {}
    async with stdio_client(params) as (read, write), ClientSession(read, write) as session:
        init = await session.initialize()
        out["server"] = init.serverInfo.name
        out["instructions"] = init.instructions
        out["tools"] = {t.name for t in (await session.list_tools()).tools}

        async def call(tool: str, /, **args: Any) -> dict[str, Any]:
            return _payload(await session.call_tool(tool, args))

        out["schema"] = await call("schema", name="mission-spec")
        out["schema_bad"] = await call("schema", name="nope")
        out["bible"] = await call("validate", path=f"campaigns/{SLUG}/bible.yaml")
        out["arc"] = await call("validate", path=f"campaigns/{SLUG}/arc.yaml")
        missions = sorted(p.name for p in (root / "campaigns" / SLUG / "missions").iterdir())
        out["missions"] = {}
        for m in missions:
            rel = f"campaigns/{SLUG}/missions/{m}"
            res: dict[str, Any] = {"validate": await call("validate", path=rel)}
            res["plan"] = await call("plan", mission_dir=rel)
            res["build"] = await call("build", mission_dir=rel)
            res["check"] = await call("check", miz_path=res["build"]["miz"])
            out["missions"][m] = res
        out["status"] = await call("campaign_status", campaign_slug=SLUG)
        out["status_bad"] = await call("campaign_status", campaign_slug="nope")
    return out


@pytest.fixture(scope="module")
def session(fake_root: Path) -> dict[str, Any]:
    return asyncio.run(asyncio.wait_for(_session_run(fake_root), timeout=300))


def test_handshake_and_tools(session: dict[str, Any]) -> None:
    assert session["server"] == "dms"
    assert "validate" in (session["instructions"] or "")
    assert session["tools"] == TOOLS


def test_schema_tool(session: dict[str, Any]) -> None:
    assert session["schema"]["ok"] is True
    assert session["schema"]["model"] == "MissionSpec"
    assert session["schema_bad"]["ok"] is False
    assert "available" in session["schema_bad"]["error"]


def test_validate_documents(session: dict[str, Any]) -> None:
    assert session["bible"]["ok"] is True, session["bible"]["issues"]
    assert session["arc"]["ok"] is True, session["arc"]["issues"]


def test_every_mission_validates_plans_builds_and_checks(
    session: dict[str, Any], fake_root: Path
) -> None:
    assert len(session["missions"]) == 4
    for mid, res in session["missions"].items():
        assert res["validate"]["ok"] is True, (mid, res["validate"]["issues"])
        assert res["plan"]["ok"] is True, (mid, res["plan"])
        assert res["plan"]["players"], mid
        build = res["build"]
        assert build["ok"] is True, (mid, build)
        assert (fake_root / build["miz"]).is_file()
        assert build["miz"].startswith(f"campaigns/{SLUG}/missions/{mid}/out/")
        assert res["check"]["ok"] is True, (mid, res["check"]["issues"])
        assert res["check"]["stats"]["scripts"] >= 1


def test_campaign_status_tool(session: dict[str, Any]) -> None:
    status = session["status"]
    assert status["ok"] is True
    assert len(status["missions"]) == 4
    for m in status["missions"]:
        assert m["designed"] and m["planned"] and m["built"], m["id"]
        assert m["last_check"] and all(v["ok"] for v in m["last_check"].values()), m
    assert session["status_bad"]["ok"] is False
    assert SLUG in session["status_bad"]["error"]
