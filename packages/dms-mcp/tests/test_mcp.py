"""dms-mcp: library ops on a tmp copy of dustoff-valley, plus the FastMCP tool surface."""

from __future__ import annotations

import asyncio
import json
import shutil
from pathlib import Path
from types import SimpleNamespace
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


def test_plan_passes_campaign_flags(repo: Path, mission: Path) -> None:
    """Like `dms plan`: state/qualities.yaml flags reach DMS_CONFIG.flags."""
    q = repo / "campaigns" / "dustoff-valley" / "state" / "qualities.yaml"
    q.write_text(
        q.read_text(encoding="utf-8").replace("flags: {}", "flags:\n  m00_success: true"),
        encoding="utf-8",
    )
    assert ops.plan(mission, seed=7, root=repo)["ok"] is True
    data = json.loads((mission / "out" / "plan.json").read_text(encoding="utf-8"))
    assert data["runtime"]["flags"] == {"m00_success": True}


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


def test_build_per_variant(repo: Path, mission: Path, lua_bundle: Path) -> None:
    import copy
    import json

    ops.plan(mission, root=repo)
    plan_path = mission / "out" / "plan.json"
    data = json.loads(plan_path.read_text(encoding="utf-8"))
    client = next(g for g in data["groups"] if g["client"])
    client["variant"] = "ramp"
    air = copy.deepcopy(client)
    air["name"], air["variant"] = "Air Flight", "air"
    for i, u in enumerate(air["units"], start=1):
        u["name"] = f"Air Flight-{i}"
    data["groups"].append(air)
    plan_path.write_text(json.dumps(data), encoding="utf-8")

    res = ops.build(mission, root=repo, lua=lua_bundle)
    assert res["ok"] is True, res
    assert [v["variant"] for v in res["variants"]] == ["ramp", "air"]
    assert [Path(v["miz"]).name for v in res["variants"]] == [
        f"{MISSION_NAME}-ramp.miz",
        f"{MISSION_NAME}-air.miz",
    ]
    assert res["miz"].endswith(f"{MISSION_NAME}.miz")
    only = ops.build(mission, root=repo, lua=lua_bundle, variant="air")
    assert [v["variant"] for v in only["variants"]] == ["air"]


def test_check_missing_file(repo: Path) -> None:
    res = ops.guarded(ops.check)("missing.miz", root=repo)
    assert res == {"ok": False, "error": f"not found: {(repo / 'missing.miz').resolve()}"}


def test_campaign_status_unknown(repo: Path) -> None:
    res = ops.guarded(ops.campaign_status)("nope", root=repo)
    assert res["ok"] is False
    assert "dustoff-valley" in res["error"]


def test_check_records_check_json_like_cli(repo: Path, mission: Path, lua_bundle: Path) -> None:
    """MCP and CLI share dms_cli.util.record_check: same file, merged per .miz."""
    from dms_cli.util import CHECK_FILE, record_check

    built = ops.build(mission, root=repo, lua=lua_bundle)
    miz = repo / built["miz"]
    record = miz.parent / CHECK_FILE
    other = miz.parent / "other.miz"
    record_check(other, {"ok": False, "issues": [], "stats": {}})
    data = json.loads(record.read_text(encoding="utf-8"))
    assert set(data) >= {miz.name, "other.miz"}
    assert data[miz.name]["ok"] is True and data[miz.name]["checked_at"]


# ---- read-only helpers -------------------------------------------------------------------------


def test_catalog_units_by_year() -> None:
    res = ops.catalog("units", era="1985", coalition="red", category="ground", root=ROOT)
    assert res["ok"] is True
    assert res["kind"] == "units"
    assert res["count"] == len(res["rows"]) > 0
    assert all("red" in r["coalitions"] for r in res["rows"])


def test_catalog_templates_and_mission_types() -> None:
    tpls = ops.catalog("templates", root=ROOT)
    assert tpls["count"] > 0 and "n_units" in tpls["rows"][0]
    mts = ops.catalog("mission-types", root=ROOT)
    assert mts["count"] > 0 and "id" in mts["rows"][0]


def test_catalog_airbases() -> None:
    res = ops.catalog("airbases", theater="Caucasus")
    assert res["count"] > 0
    assert any("Batumi" in r["name"] for r in res["rows"])


@pytest.mark.parametrize(
    ("args", "needle"),
    [
        ({"kind": "nope"}, "available"),
        ({"kind": "airbases"}, "theater"),
        ({"kind": "units", "era": "1066"}, "no era covers"),
        ({"kind": "airbases", "theater": "Atlantis"}, "Atlantis"),
    ],
)
def test_catalog_errors_are_structured(args: dict[str, Any], needle: str) -> None:
    res = ops.guarded(ops.catalog)(**args, root=ROOT)
    assert res["ok"] is False
    assert needle in res["error"]


OUTCOME_LOG = """\
2026-10-27 18:00:00.000 INFO    SCRIPTING (Main): [DMS][Init] DMS v0.3 starting
2026-10-27 18:20:11.500 INFO    SCRIPTING (Main): [DMS.OUTCOME] {"missionId":"m01-first-light","t":1150.5,"kind":"beat","beat":"convoy_hit","outcome":{"convoy_contact":true},"flags":[]}
2026-10-27 18:22:00.000 INFO    SCRIPTING (Main): [DMS.OUTCOME] {not json}
2026-10-27 18:30:00.000 INFO    SCRIPTING (Main): [DMS.OUTCOME] {"missionId":"m02-other","t":10,"kind":"beat","beat":"x"}
"""  # noqa: E501


def test_outcome_reads_log_file_and_folder(tmp_path: Path) -> None:
    log = tmp_path / "Logs" / "dcs.log"
    log.parent.mkdir()
    log.write_text(OUTCOME_LOG, encoding="utf-8")
    res = ops.outcome(log)
    assert res["ok"] is True
    assert res["count"] == 2
    assert set(res["summary"]) == {"m01-first-light", "m02-other"}
    only = ops.outcome(log.parent, mission_id="m01-first-light")
    assert only["count"] == 1
    assert only["records"][0]["beat"] == "convoy_hit"
    assert only["log"] == str(log)


def test_outcome_missing_log_is_structured(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> None:
    res = ops.guarded(ops.outcome)(tmp_path / "nope.log")
    assert res["ok"] is False and "not found" in res["error"]
    from dms_core import outcomes as oc

    monkeypatch.setattr(oc, "default_log_paths", lambda: [])
    res = ops.guarded(ops.outcome)()
    assert res["ok"] is False and "log_path" in res["error"]


def test_doctor_uses_cli_checks(monkeypatch: pytest.MonkeyPatch) -> None:
    from dms_cli import install

    rows = [install.Check("python", "OK", "3.12"), install.Check("lua", "FAIL", "no", "fix it")]
    monkeypatch.setattr(install, "run_doctor", lambda root: rows)
    res = ops.doctor(root=ROOT)
    assert res["ok"] is False
    assert res["checks"][1] == {"name": "lua", "status": "FAIL", "detail": "no", "fix": "fix it"}


def _boom(*_a: Any, **_k: Any) -> Any:
    raise AssertionError("voice_estimate must never touch ElevenLabs or the network")


@pytest.fixture
def no_voice_client(monkeypatch: pytest.MonkeyPatch, tmp_path: Path) -> None:
    """Fail loudly if anything builds an ElevenLabs client; empty key, private TTS cache."""
    from dms_voice import client

    boom = _boom
    monkeypatch.setattr(client.VoiceClient, "__init__", boom)
    try:
        import elevenlabs.client as el_client
    except ImportError:  # pragma: no cover
        pass
    else:
        monkeypatch.setattr(el_client, "ElevenLabs", boom)
    monkeypatch.setenv("ELEVENLABS_API_KEY", "")
    monkeypatch.setenv("DMS_TTS_CACHE", str(tmp_path / "tts-cache"))


@pytest.mark.usefixtures("no_voice_client")
def test_voice_estimate_is_dry_run_only(
    repo: Path, mission: Path, monkeypatch: pytest.MonkeyPatch, tmp_path: Path
) -> None:
    import socket

    monkeypatch.setattr(socket.socket, "connect", _boom)  # no network at all
    monkeypatch.setattr(socket, "create_connection", _boom)
    # quickstart-demo: every speaker has a voice id (read-only use of the real campaign)
    demo = ROOT / "campaigns" / "quickstart-demo" / "missions" / "m01-hog-down-low"
    if not demo.is_dir():  # pragma: no cover
        pytest.skip("campaigns/quickstart-demo missing")
    res = ops.voice_estimate(demo, root=ROOT)
    assert res["ok"] is True, res
    assert res["lines"].endswith("lines.yaml")
    assert res["total_lines"] == len(res["per_line"]) > 0
    assert res["to_render"] == res["total_lines"]  # empty private cache: everything to render
    assert res["characters"] > 0 and res["credits"] > 0
    assert "ElevenLabs credits" in res["summary"]
    assert not (tmp_path / "tts-cache").exists()  # the estimate wrote nothing to the cache

    # dustoff m01 lacks voice ids for some speakers: a structured error, like `dms voice --dry-run`
    bad = ops.guarded(ops.voice_estimate)(mission, root=repo)
    assert bad["ok"] is False and "no ElevenLabs voice id" in bad["error"]
    off = ops.voice_estimate(mission / "lines.yaml", offline=True, root=repo)
    assert off["ok"] is True and off["offline"] is True and off["credits"] == 0
    assert not (mission / "voice").exists()  # nothing rendered or written


@pytest.mark.usefixtures("no_voice_client")
def test_voice_estimate_through_server(repo: Path, monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setenv(ops.ROOT_ENV, str(repo))
    rel = f"campaigns/dustoff-valley/missions/{MISSION_NAME}"
    result: Any = asyncio.run(
        server.mcp.call_tool("voice_estimate", {"mission": rel, "offline": True})
    )
    assert "0 ElevenLabs credits" in json.dumps(result, default=str)


def test_voice_estimate_missing(repo: Path) -> None:
    res = ops.guarded(ops.voice_estimate)("campaigns/nope", root=repo)
    assert res["ok"] is False and "not found" in res["error"]


# ---- FastMCP surface ---------------------------------------------------------------------------


def test_server_lists_ten_tools() -> None:
    tools = asyncio.run(server.mcp.list_tools())
    names = {t.name for t in tools}
    assert names == {
        "validate",
        "plan",
        "build",
        "check",
        "schema",
        "campaign_status",
        "catalog",
        "outcome",
        "doctor",
        "voice_estimate",
    }
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


@pytest.mark.parametrize("existing", [["mist", "skynet", "adapter"], ["adapter"], []])
def test_attach_lua_fallback_keeps_plugin_order(tmp_path: Path, existing: list[str]) -> None:
    """A plan without dms.lua: dms.lua goes after the plugins, before the DMS adapters."""
    from dms_core.schemas import PlanResource
    from dms_gen.plugins import PLUGINS

    files = {"mist": PLUGINS["mist"].file, "skynet": PLUGINS["skynet"].file}
    files["adapter"] = PLUGINS["skynet_adapter"].file
    res = [
        PlanResource(path=f"l10n/DEFAULT/{Path(files[k]).name}", source=files[k], kind="script")
        for k in existing
    ]
    plan = SimpleNamespace(resources=res, runtime=None)
    assert ops._attach_lua(plan, tmp_path / "dms.lua", tmp_path) == "added"
    names = [Path(r.path).name for r in plan.resources]
    want = [Path(files[k]).name for k in existing if k != "adapter"] + ["dms.lua"]
    want += [Path(files["adapter"]).name] if "adapter" in existing else []
    assert names == want
