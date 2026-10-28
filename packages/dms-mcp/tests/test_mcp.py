"""dms-mcp: library ops on a tmp copy of dustoff-valley, plus the FastMCP tool surface."""

from __future__ import annotations

import asyncio
import json
import shutil
from pathlib import Path
from typing import Any

import pytest
from dms_cli.util import find_root
from dms_mcp import ops, server

ROOT = find_root(Path(__file__).parent)
CAMPAIGN = ROOT / "campaigns" / "dustoff-valley"
MISSION_NAME = "m01-first-light"


@pytest.fixture
def repo(tmp_path: Path) -> Path:
    """A fake repo root: campaigns/dustoff-valley (no out/ or voice/) + lua sources + tools."""
    root = tmp_path / "repo"
    shutil.copytree(
        CAMPAIGN,
        root / "campaigns" / "dustoff-valley",
        ignore=shutil.ignore_patterns("out", "voice"),
    )
    return root


@pytest.fixture
def mission(repo: Path) -> Path:
    return repo / "campaigns" / "dustoff-valley" / "missions" / MISSION_NAME


@pytest.fixture(scope="session")
def lua_bundle(tmp_path_factory: pytest.TempPathFactory) -> Path:
    """The real runtime bundle, written to tmp (never into the repo's dist/)."""
    out = tmp_path_factory.mktemp("lua") / "dms.lua"
    return ops.bundle_lua(ROOT, out)


# ---- validate / schema -------------------------------------------------------------------------


def test_validate_mission_ok(repo: Path, mission: Path) -> None:
    res = ops.validate(mission, root=repo)
    assert res["kind"] == "mission"
    assert res["ok"] is True, res["issues"]
    assert res["errors"] == 0
    assert res["files"]["spec"].endswith("mission-spec.yaml")
    assert res["files"]["bible"] == "campaigns/dustoff-valley/bible.yaml"


def test_validate_relative_path(repo: Path) -> None:
    res = ops.validate(f"campaigns/dustoff-valley/missions/{MISSION_NAME}", root=repo)
    assert res["ok"] is True


def test_validate_reports_schema_issue(repo: Path, mission: Path) -> None:
    spec = mission / "mission-spec.yaml"
    spec.write_text(spec.read_text(encoding="utf-8") + "\nbogus_field: 1\n", encoding="utf-8")
    res = ops.validate(mission, root=repo)
    assert res["ok"] is False
    assert any("bogus_field" in i["problem"] for i in res["issues"])


@pytest.mark.parametrize("name", ["bible.yaml", "arc.yaml", "state/qualities.yaml"])
def test_validate_documents(repo: Path, name: str) -> None:
    res = ops.validate(repo / "campaigns" / "dustoff-valley" / name, root=repo)
    assert res["ok"] is True, res["issues"]
    assert res["kind"] in ("story-bible", "campaign-arc", "qualities")


def test_validate_missing_is_structured_error(repo: Path) -> None:
    res = ops.guarded(ops.validate)("nope", root=repo)
    assert res["ok"] is False
    assert "not found" in res["error"]


@pytest.mark.parametrize(
    ("name", "stem"),
    [("mission-spec", "mission-spec"), ("MissionSpec", "mission-spec"), ("bible", "story-bible")],
)
def test_schema_lookup(name: str, stem: str) -> None:
    res = ops.schema(name)
    assert res["name"] == stem
    assert "properties" in res["schema"]


def test_schema_unknown() -> None:
    res = ops.guarded(ops.schema)("nope")
    assert res["ok"] is False
    assert "mission-spec" in res["error"]


# ---- plan / build / check / status -------------------------------------------------------------


def test_plan_writes_plan_json(repo: Path, mission: Path) -> None:
    res = ops.plan(mission, seed=7, root=repo)
    assert res["ok"] is True
    assert res["seed"] == 7
    assert res["plan"].endswith("out/plan.json")
    assert res["stats"]["groups"] > 0
    assert res["players"]
    data = json.loads((mission / "out" / "plan.json").read_text(encoding="utf-8"))
    assert data["seed"] == 7


def test_build_check_and_status(repo: Path, mission: Path, lua_bundle: Path) -> None:
    built = ops.build(mission, root=repo, lua=lua_bundle)
    assert built["miz"].endswith(".miz")
    miz = repo / built["miz"]
    assert miz.is_file()
    assert any("planned seed" in n for n in built["notes"])
    assert built["check"]["ok"] is True, built["check"]["issues"]
    assert built["ok"] is True

    checked = ops.check(built["miz"], root=repo)
    assert checked["ok"] is True
    assert checked["stats"]["scripts"] >= 1

    status = ops.campaign_status("dustoff-valley", root=repo)
    assert status["ok"] is True
    m01 = next(m for m in status["missions"] if m["id"] == MISSION_NAME)
    assert m01["designed"] and m01["planned"]
    assert m01["built"] == [miz.name]
    assert m01["last_check"][miz.name]["ok"] is True
    assert any(p.endswith("check.json") for p in m01["out"])
    assert status["qualities"]["intel"] == 0
    assert {m["id"] for m in status["arc_missions_not_designed"]}  # m02.. not designed yet


def test_build_test_variant(repo: Path, mission: Path, lua_bundle: Path) -> None:
    res = ops.build(mission, test=True, root=repo, lua=lua_bundle)
    assert res["test"] is True
    assert res["miz"].endswith("-test.miz")
    assert "run_mission.py" in res["harness"]
    assert (mission / "out" / "test" / "dms_test.lua").is_file()


def test_check_missing_file(repo: Path) -> None:
    res = ops.guarded(ops.check)("missing.miz", root=repo)
    assert res == {"ok": False, "error": f"not found: {(repo / 'missing.miz').resolve()}"}


def test_campaign_status_unknown(repo: Path) -> None:
    res = ops.guarded(ops.campaign_status)("nope", root=repo)
    assert res["ok"] is False
    assert "dustoff-valley" in res["error"]


# ---- FastMCP surface ---------------------------------------------------------------------------


def test_server_lists_six_tools() -> None:
    tools = asyncio.run(server.mcp.list_tools())
    names = {t.name for t in tools}
    assert names == {"validate", "plan", "build", "check", "schema", "campaign_status"}
    by_name = {t.name: t for t in tools}
    assert by_name["plan"].inputSchema["required"] == ["mission_dir"]
    assert "test" in by_name["build"].inputSchema["properties"]


def test_server_call_tool(repo: Path, monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setenv(ops.ROOT_ENV, str(repo))
    result: Any = asyncio.run(server.mcp.call_tool("campaign_status", {"campaign_slug": "x"}))
    text = json.dumps(result, default=str)
    assert "no campaign" in text
    result = asyncio.run(server.mcp.call_tool("schema", {"name": "beats"}))
    assert "BeatSheet" in json.dumps(result, default=str)
