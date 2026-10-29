"""CliRunner tests for every ``dms`` command. Planner/check are faked where needed."""

from __future__ import annotations

import dataclasses
import json
import shutil
import sys
import types
import zipfile
from pathlib import Path
from typing import Any

import pytest
from dms_cli import main as cli
from dms_cli.main import app
from dms_cli.util import find_root
from typer.testing import CliRunner

ROOT = find_root(Path(__file__).parent)
CAMPAIGN = ROOT / "campaigns" / "dustoff-valley"
MISSION = CAMPAIGN / "missions" / "m01-first-light"

runner = CliRunner()


def invoke(*args: str) -> Any:
    return runner.invoke(app, ["--root", str(ROOT), *args], catch_exceptions=False)


@pytest.fixture
def mission(tmp_path: Path) -> Path:
    """A copy of dustoff-valley/m01 under tmp/campaigns/... (bible found by walking up)."""
    camp = tmp_path / "campaigns" / "dustoff-valley"
    camp.mkdir(parents=True)
    shutil.copy(CAMPAIGN / "bible.yaml", camp / "bible.yaml")
    dest = camp / "missions" / MISSION.name
    shutil.copytree(MISSION, dest, ignore=shutil.ignore_patterns("out", "voice"))
    return dest


@pytest.fixture
def lua_file(tmp_path: Path) -> Path:
    p = tmp_path / "dms.lua"
    p.write_text('env.info("dms")\n', encoding="utf-8")
    return p


# ---- fakes -------------------------------------------------------------------------------------


@dataclasses.dataclass
class FakeReport:
    ok: bool
    findings: list[dict[str, str]]


def _fake_plan_mission(
    spec: Any, beats: Any = None, lines: Any = None, voice_manifest: Any = None, seed: Any = None
) -> Any:
    from dms_core.schemas import BuildPlan, PlanGroup, PlanUnit, RuntimeConfig

    _fake_plan_mission.calls.append({"voice_manifest": voice_manifest, "seed": seed})  # type: ignore[attr-defined]
    return BuildPlan(
        mission_id=spec.id,
        seed=seed if seed is not None else 42,
        theater=spec.theater,
        date=spec.date,
        start_time_sec=6 * 3600,
        blue_countries=["USA"],
        red_countries=["Insurgents"],
        groups=[
            PlanGroup(
                name="Red 1",
                category="vehicle",
                coalition="red",
                country="Insurgents",
                units=[PlanUnit(name="Red 1-1", type="BMP-2", x=147000, y=39000)],
            )
        ],
        runtime=RuntimeConfig(seed=seed or 42, mission_id=spec.id),
    )


@pytest.fixture
def fakes(monkeypatch: pytest.MonkeyPatch) -> types.SimpleNamespace:
    import dms_gen  # type: ignore[import-untyped,unused-ignore]

    _fake_plan_mission.calls = []  # type: ignore[attr-defined]
    planner = types.ModuleType("dms_gen.planner")
    planner.validate = lambda spec, beats=None, lines=None, bible=None: []  # type: ignore[attr-defined]
    planner.plan_mission = _fake_plan_mission  # type: ignore[attr-defined]
    check = types.ModuleType("dms_gen.check")
    state = types.SimpleNamespace(ok=True, checked=[], planner=planner)

    def check_miz(path: Path) -> FakeReport:
        state.checked.append(Path(path))
        assert zipfile.is_zipfile(path)
        msgs = [] if state.ok else [{"severity": "error", "path": "mission", "problem": "bad id"}]
        return FakeReport(ok=state.ok, findings=msgs)

    check.check_miz = check_miz  # type: ignore[attr-defined]
    for name, mod in (("planner", planner), ("check", check)):
        monkeypatch.setitem(sys.modules, f"dms_gen.{name}", mod)
        monkeypatch.setattr(dms_gen, name, mod, raising=False)
    return state


# ---- root / help -------------------------------------------------------------------------------


def test_help_lists_commands() -> None:
    res = runner.invoke(app, ["--help"])
    assert res.exit_code == 0
    for cmd in (
        "validate",
        "plan",
        "voice",
        "build",
        "check",
        "run",
        "schema",
        "bundle-lua",
        "catalog",
        "outcome",
        "new-campaign",
    ):
        assert cmd in res.output
    assert res.output.isascii()


def test_find_root() -> None:
    assert (ROOT / "pyproject.toml").is_file()
    assert find_root(MISSION) == ROOT


# ---- validate ----------------------------------------------------------------------------------


def test_validate_ok(mission: Path) -> None:
    res = invoke("validate", str(mission))
    assert res.exit_code == 0, res.output
    assert "OK: 0 error(s)" in res.output
    assert "bible.yaml" in res.output


def test_validate_spec_file_json(mission: Path) -> None:
    res = invoke("validate", str(mission / "mission-spec.yaml"), "--json")
    assert res.exit_code == 0, res.output
    data = json.loads(res.output)
    assert data["ok"] is True and data["files"]["bible"].endswith("bible.yaml")


def test_validate_schema_errors(mission: Path) -> None:
    spec = mission / "mission-spec.yaml"
    text = spec.read_text(encoding="utf-8")
    text = text.replace("weather_preset: clear", "weather_preset: claer\nweathr: 1", 1)
    spec.write_text(text, encoding="utf-8")
    res = invoke("validate", str(mission), "--json")
    assert res.exit_code == 1
    issues = {i["path"]: i for i in json.loads(res.output)["issues"]}
    assert issues["mission-spec.yaml:weather_preset"]["suggestions"][0] == "clear"
    assert "weather_preset" in issues["mission-spec.yaml:weathr"]["suggestions"]


def test_validate_cross_file_error(mission: Path) -> None:
    beats = mission / "beats.yaml"
    beats.write_text(
        beats.read_text(encoding="utf-8").replace("speaker: ops_walsh", "speaker: ops_wlash", 1),
        encoding="utf-8",
    )
    res = invoke("validate", str(mission))
    assert res.exit_code == 1
    assert "ops_wlash" in res.output and "try: ops_walsh" in res.output


def test_validate_uses_planner(mission: Path, fakes: types.SimpleNamespace) -> None:
    from dms_core.schemas import Issue

    fakes.planner.validate = lambda spec, beats=None, lines=None, bible=None: [
        Issue(path="mission-spec.yaml:areas[0]", problem="not on land", suggestions=["move"])
    ]
    res = invoke("validate", str(mission))
    assert res.exit_code == 1
    assert "ERROR mission-spec.yaml:areas[0]: not on land | try: move" in res.output


def test_validate_missing_dir(tmp_path: Path) -> None:
    res = invoke("validate", str(tmp_path))
    assert res.exit_code == 2
    assert "mission-spec.yaml" in res.output


# ---- plan / build / check / run ----------------------------------------------------------------


def test_plan_default_output(mission: Path, fakes: types.SimpleNamespace) -> None:
    (mission / "voice").mkdir()
    (mission / "voice" / "manifest.json").write_text('{"a": {"file": "a.ogg"}}', encoding="utf-8")
    res = invoke("plan", str(mission / "mission-spec.yaml"), "--seed", "9")
    assert res.exit_code == 0, res.output
    plan = json.loads((mission / "out" / "plan.json").read_text(encoding="utf-8"))
    assert plan["seed"] == 9 and plan["mission_id"] == "m01-first-light"
    assert _fake_plan_mission.calls[-1]["voice_manifest"] == mission / "voice" / "manifest.json"  # type: ignore[attr-defined]
    assert "seed 9" in res.output


def test_plan_output_option(mission: Path, fakes: types.SimpleNamespace, tmp_path: Path) -> None:
    out = tmp_path / "x" / "p.json"
    res = invoke("plan", str(mission), "-o", str(out))
    assert res.exit_code == 0, res.output
    assert out.is_file()
    assert _fake_plan_mission.calls[-1]["voice_manifest"] is None  # type: ignore[attr-defined]


def test_build_and_check(mission: Path, fakes: types.SimpleNamespace, lua_file: Path) -> None:
    assert invoke("plan", str(mission)).exit_code == 0
    res = invoke("build", str(mission), "--lua", str(lua_file))
    assert res.exit_code == 0, res.output
    miz = mission / "out" / "m01-first-light.miz"
    assert miz.is_file() and fakes.checked == [miz]
    names = zipfile.ZipFile(miz).namelist()
    assert any(n.endswith("dms.lua") for n in names)
    assert any(n.endswith("dms_config.lua") for n in names)
    assert "check: OK" in res.output and "lua resource added" in res.output


def test_build_warns_on_placeholder_voice(
    mission: Path, fakes: types.SimpleNamespace, lua_file: Path
) -> None:
    assert invoke("plan", str(mission)).exit_code == 0
    (mission / "voice").mkdir()
    manifest = {
        "a": {"file": "a.ogg", "model": "placeholder", "placeholder": True},
        "b": {"file": "b.ogg", "model": "eleven_v3"},
    }
    (mission / "voice" / "manifest.json").write_text(json.dumps(manifest), encoding="utf-8")
    res = invoke("build", str(mission), "--lua", str(lua_file))
    assert res.exit_code == 0, res.output
    assert (
        "WARNING: 1/2 voice clips are offline placeholders" in res.output and ": a;" in res.output
    )
    manifest["a"] = {"file": "a.ogg", "model": "eleven_v3"}
    (mission / "voice" / "manifest.json").write_text(json.dumps(manifest), encoding="utf-8")
    assert "placeholders" not in invoke("build", str(mission), "--lua", str(lua_file)).output


def test_build_check_failure(
    mission: Path, fakes: types.SimpleNamespace, lua_file: Path, tmp_path: Path
) -> None:
    assert invoke("plan", str(mission)).exit_code == 0
    fakes.ok = False
    out = tmp_path / "o.miz"
    res = invoke(
        "build", str(mission / "out" / "plan.json"), "-o", str(out), "--lua", str(lua_file)
    )
    assert res.exit_code == 1
    assert out.is_file() and "check: FAILED" in res.output and "bad id" in res.output


def test_build_links_existing_lua_resource(
    mission: Path, fakes: types.SimpleNamespace, lua_file: Path
) -> None:
    assert invoke("plan", str(mission)).exit_code == 0
    plan_path = mission / "out" / "plan.json"
    data = json.loads(plan_path.read_text(encoding="utf-8"))
    data["resources"] = [
        {"path": "l10n/DEFAULT/dms.lua", "source": "dist/dms.lua", "kind": "script"}
    ]
    plan_path.write_text(json.dumps(data), encoding="utf-8")
    res = invoke("build", str(plan_path), "--lua", str(lua_file))
    assert res.exit_code == 0, res.output
    assert "lua resource linked" in res.output


def _add_variant_groups(plan_path: Path) -> None:
    data = json.loads(plan_path.read_text(encoding="utf-8"))
    for i, v in enumerate(("ramp", "air"), start=1):
        data["groups"].append(
            {
                "name": f"Python {i}",
                "category": "plane",
                "coalition": "blue",
                "country": "USA",
                "client": True,
                "variant": v,
                "units": [
                    {
                        "name": f"Python {i}-1",
                        "type": "F-16C_50",
                        "x": 140000 + i * 1000,
                        "y": 30000,
                        "alt_m": 6096,
                        "skill": "Player",
                    }
                ],
                "route": [{"x": 140000 + i * 1000, "y": 30000, "alt_m": 6096, "speed_kmh": 777}],
            }
        )
    plan_path.write_text(json.dumps(data), encoding="utf-8")


def test_build_variants(mission: Path, fakes: types.SimpleNamespace, lua_file: Path) -> None:
    assert invoke("plan", str(mission)).exit_code == 0
    _add_variant_groups(mission / "out" / "plan.json")
    res = invoke("build", str(mission), "--lua", str(lua_file))
    assert res.exit_code == 0, res.output
    out = mission / "out"
    ramp, air = out / "m01-first-light-ramp.miz", out / "m01-first-light-air.miz"
    assert fakes.checked == [ramp, air]
    assert (out / "m01-first-light.miz").read_bytes() == ramp.read_bytes()
    assert "variant air" in res.output
    for miz, keep, drop in ((ramp, "Python 1", "Python 2"), (air, "Python 2", "Python 1")):
        src = zipfile.ZipFile(miz).read("mission").decode("utf-8")
        assert f'"{keep}"' in src and f'"{drop}"' not in src
    fakes.checked.clear()
    res = invoke("build", str(mission), "--lua", str(lua_file), "--variant", "air")
    assert res.exit_code == 0, res.output
    assert fakes.checked == [air]
    res = invoke("build", str(mission), "--lua", str(lua_file), "--variant", "hot")
    assert res.exit_code == 1 and "unknown variant" in res.output


def test_build_missing_plan(mission: Path) -> None:
    res = invoke("build", str(mission))
    assert res.exit_code == 2 and "dms plan" in res.output


def test_check_command(fakes: types.SimpleNamespace, tmp_path: Path) -> None:
    miz = tmp_path / "a.miz"
    with zipfile.ZipFile(miz, "w") as z:
        z.writestr("mission", "mission = {}")
    res = invoke("check", str(miz), "--json")
    assert res.exit_code == 0 and json.loads(res.output)["ok"] is True
    fakes.ok = False
    res = invoke("check", str(miz))
    assert res.exit_code == 1 and "ERROR mission bad id" in res.output


def test_check_mission_folder_checks_every_variant(
    mission: Path, fakes: types.SimpleNamespace, lua_file: Path
) -> None:
    res = invoke("check", str(mission))
    assert res.exit_code == 2 and "no built .miz" in res.output
    assert invoke("plan", str(mission)).exit_code == 0
    _add_variant_groups(mission / "out" / "plan.json")
    assert invoke("build", str(mission), "--lua", str(lua_file)).exit_code == 0
    out = mission / "out"
    ramp, air = out / "m01-first-light-ramp.miz", out / "m01-first-light-air.miz"
    fakes.checked.clear()
    res = invoke("check", str(mission))
    assert res.exit_code == 0, res.output
    assert fakes.checked == [ramp, air]
    assert "m01-first-light-air.miz:" in res.output
    fakes.checked.clear()
    res = invoke("check", str(out), "--json")
    assert res.exit_code == 0 and fakes.checked == [ramp, air]
    assert set(json.loads(res.output)) == {str(ramp), str(air)}


def test_run_pipeline(
    mission: Path, fakes: types.SimpleNamespace, monkeypatch: pytest.MonkeyPatch, lua_file: Path
) -> None:
    import dms_voice.cli

    calls: list[list[str]] = []

    def fake_voice(argv: list[str]) -> int:
        calls.append(argv)
        return 2

    monkeypatch.setattr(dms_voice.cli, "main", fake_voice)
    monkeypatch.setattr(cli, "_ensure_lua", lambda root, lua: (lua_file, "given"))
    res = invoke("run", str(mission), "--seed", "5")
    assert res.exit_code == 0, res.output
    assert calls == [[str(mission / "lines.yaml")]]
    assert "voice render failed" in res.output
    for step in ("[1/5] validate", "[2/5] voice", "[3/5] plan", "[4/5] build", "[5/5] check"):
        assert step in res.output
    assert (mission / "out" / "m01-first-light.miz").is_file()

    calls.clear()
    res = invoke("run", str(mission), "--skip-voice")
    assert res.exit_code == 0 and calls == [] and "--skip-voice" in res.output


def test_run_stops_on_validation(mission: Path, fakes: types.SimpleNamespace) -> None:
    (mission / "lines.yaml").write_text("lines: [{id: x}]\n", encoding="utf-8")
    res = invoke("run", str(mission))
    assert res.exit_code == 1 and "[2/5]" not in res.output


# ---- voice -------------------------------------------------------------------------------------


def test_voice_delegates(mission: Path, monkeypatch: pytest.MonkeyPatch, tmp_path: Path) -> None:
    import dms_voice.cli

    seen: list[list[str]] = []

    def fake_voice(argv: list[str]) -> int:
        seen.append(argv)
        return 0

    monkeypatch.setattr(dms_voice.cli, "main", fake_voice)
    res = invoke("voice", str(mission), "--dry-run", "--fx", "uhf", "--out", str(tmp_path))
    assert res.exit_code == 0, res.output
    assert seen == [
        [str(mission / "lines.yaml"), "--out", str(tmp_path), "--fx", "uhf", "--dry-run"]
    ]
    seen.clear()
    res = invoke(
        "voice",
        str(mission),
        "--offline",
        "--rerender",
        "l1",
        "--rerender",
        "l2",
        "--no-raw-cache",
    )
    assert res.exit_code == 0, res.output
    assert seen == [
        [
            str(mission / "lines.yaml"),
            "--rerender",
            "l1",
            "--rerender",
            "l2",
            "--offline",
            "--no-raw-cache",
        ]
    ]
    monkeypatch.setattr(dms_voice.cli, "main", lambda argv: 2)
    assert invoke("voice", str(mission / "lines.yaml")).exit_code == 2


def test_voice_real_dry_run_bad_file(tmp_path: Path) -> None:
    res = invoke("voice", str(tmp_path / "nope.yaml"))
    assert res.exit_code == 2 and "not found" in res.output


# ---- schema / bundle-lua -----------------------------------------------------------------------


def test_schema(tmp_path: Path) -> None:
    res = invoke("schema", "--out", str(tmp_path))
    assert res.exit_code == 0
    assert (tmp_path / "mission-spec.schema.json").is_file()


def test_bundle_lua(tmp_path: Path) -> None:
    pytest.importorskip("lupa")
    if not (ROOT / "tools" / "bundle_lua.py").is_file():
        pytest.skip("tools/bundle_lua.py missing")
    out = tmp_path / "dms.lua"
    res = invoke("bundle-lua", "--out", str(out))
    assert res.exit_code == 0, res.output
    assert "DMS.VERSION" in out.read_text(encoding="utf-8")


def test_ensure_lua_staleness(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> None:
    import os

    src = tmp_path / "lua" / "src" / "dms"
    src.mkdir(parents=True)
    (tmp_path / "lua" / "manifest.txt").write_text("core\n", encoding="utf-8")
    (src / "core.lua").write_text("x = 1\n", encoding="utf-8")
    built: list[Path] = []

    def fake_bundle(root: Path, out: Path) -> Path:
        built.append(out)
        out.parent.mkdir(parents=True, exist_ok=True)
        out.write_text("-- bundle\n", encoding="utf-8")
        return out

    monkeypatch.setattr(cli, "_bundle_lua", fake_bundle)
    path, state = cli._ensure_lua(tmp_path, None)
    assert state == "rebuilt (missing)" and built == [path]
    _, state = cli._ensure_lua(tmp_path, None)
    assert state == "up to date"
    old = path.stat().st_mtime - 100
    os.utime(path, (old, old))
    _, state = cli._ensure_lua(tmp_path, None)
    assert state == "rebuilt (stale)"


# ---- catalog -----------------------------------------------------------------------------------


def test_catalog_units() -> None:
    res = invoke("catalog", "units", "--era", "1985", "--coalition", "red", "--role", "sam_short")
    assert res.exit_code == 0 and "Osa 9A33 ln" in res.output
    res = invoke("catalog", "units", "--role", "sam_short", "--json")
    assert all("id" in u for u in json.loads(res.output))
    res = invoke("catalog", "units", "--era", "moden")
    assert res.exit_code == 2 and "modern" in res.output


def test_catalog_templates_and_mission_types() -> None:
    res = invoke("catalog", "templates", "--role", "air_defense", "--json")
    assert res.exit_code == 0 and json.loads(res.output)
    res = invoke("catalog", "mission-types")
    assert res.exit_code == 0 and "SEAD" in res.output


@pytest.mark.parametrize("role", ["aaa", "manpads", "technicals", "sam_short"])
def test_catalog_templates_accept_threat_roles(role: str) -> None:
    res = invoke("catalog", "templates", "--role", role, "--json")
    assert res.exit_code == 0, res.output
    assert json.loads(res.output), f"no templates for ThreatRole {role!r}"


def test_catalog_templates_no_results_lists_valid_roles() -> None:
    res = invoke("catalog", "templates", "--role", "flak")
    assert res.exit_code == 0 and "Valid roles:" in res.output and "aaa" in res.output
    res = invoke("catalog", "templates", "--role", "civilian")
    assert res.exit_code == 0 and "neutral bible faction" in res.output


def test_catalog_airbases() -> None:
    pytest.importorskip("dcs")
    res = invoke(
        "catalog", "airbases", "--theater", "Syria", "--near", "Hatay", "--limit", "2", "--json"
    )
    assert res.exit_code == 0, res.output
    rows = json.loads(res.output)
    assert rows[0]["name"] == "Hatay" and len(rows) == 2
    res = invoke("catalog", "airbases", "--theater", "Syira")
    assert res.exit_code == 2 and "Syria" in res.output


# ---- outcome / new-campaign --------------------------------------------------------------------


def test_outcome(tmp_path: Path) -> None:
    log = tmp_path / "dcs.log"
    log.write_text(
        "2026-10-27 10:00:00.000 INFO    SCRIPTING: [DMS.OUTCOME] "
        '{"missionId":"m01","kind":"beat","beat":"tgt_down","t":120,"outcome":{"hvtKilled":true}}\n'
        "junk line\n"
        "2026-10-27 10:05:00.000 INFO    SCRIPTING: [DMS.OUTCOME] "
        '{"missionId":"m02","kind":"end"}\n',
        encoding="utf-8",
    )
    res = invoke("outcome", str(log))
    assert res.exit_code == 0 and "2 record(s)" in res.output and "tgt_down" in res.output
    res = invoke("outcome", str(log), "--mission-id", "m01", "--json")
    data = json.loads(res.output)
    assert len(data["records"]) == 1 and data["summary"]["m01"]["outcomes"] == {"hvtKilled": True}


DCS_LOG = ROOT / "tests" / "fixtures" / "dcs-logs" / "multi-session-dcs.log.txt"


@pytest.fixture
def campaign(tmp_path: Path) -> Path:
    camp = tmp_path / "dustoff-valley"
    (camp / "state").mkdir(parents=True)
    shutil.copy(CAMPAIGN / "arc.yaml", camp / "arc.yaml")
    shutil.copy(CAMPAIGN / "state" / "qualities.yaml", camp / "state" / "qualities.yaml")
    return camp


def test_debrief(campaign: Path) -> None:
    import yaml

    args = ["debrief", str(campaign), "--mission", "m01", "--log", str(DCS_LOG)]
    res = invoke(*args, "--dry-run")
    assert res.exit_code == 0, res.output
    assert "result: success" in res.output and "dry run" in res.output
    assert "next mission: m02-cracking-kirikhan" in res.output
    assert "LOG ERROR" in res.output and "skipped malformed" in res.output
    assert not (campaign / "state" / "outcomes").exists()

    res = invoke(*args)
    assert res.exit_code == 0, res.output
    out = yaml.safe_load((campaign / "state" / "outcomes" / "m01.yaml").read_text("utf-8"))
    assert out["kind"] == "summary" and out["extra"]["source"] == "dcs_log"
    assert out["extra"]["next_mission"] == "m02-cracking-kirikhan"
    q = yaml.safe_load((campaign / "state" / "qualities.yaml").read_text("utf-8"))
    assert q["values"]["intel"] == 2 and q["values"]["trust"] == 1
    assert q["flags"]["m01_patrol_complete"] is True and q["updated_after"] == "m01-first-light"
    cont = (campaign / "continuity.md").read_text("utf-8")
    assert "— dms debrief — m01-first-light flown (success)" in cont

    again = invoke(*args)
    assert again.exit_code == 1 and "already" in again.output
    forced = invoke(*args, "--force", "--json")
    assert forced.exit_code == 0, forced.output
    data = json.loads(forced.output)
    # --force rolls the first application back before re-applying: same value, not doubled
    assert data["qualities"]["values"]["intel"] == 2
    cont = (campaign / "continuity.md").read_text(encoding="utf-8")
    assert cont.count("— dms debrief — m01-first-light flown") == 1


def test_debrief_errors(campaign: Path, tmp_path: Path) -> None:
    res = invoke("debrief", str(campaign), "--mission", "m04", "--log", str(DCS_LOG))
    assert res.exit_code == 1 and "no [DMS.OUTCOME] lines for mission" in res.output
    res = invoke("debrief", str(campaign), "--mission", "m99", "--log", str(DCS_LOG))
    assert res.exit_code == 2 and "not found in arc.yaml" in res.output
    res = invoke("debrief", str(campaign), "-m", "m01", "--log", str(tmp_path / "nope.log"))
    assert res.exit_code == 2 and "not found" in res.output


def test_new_campaign(tmp_path: Path) -> None:
    (tmp_path / "pyproject.toml").write_text(
        "[tool.uv.workspace]\nmembers = []\n", encoding="utf-8"
    )
    shutil.copytree(ROOT / "campaigns" / "_template", tmp_path / "campaigns" / "_template")
    args = ["--root", str(tmp_path), "new-campaign"]
    res = runner.invoke(app, [*args, "red-sky"])
    assert res.exit_code == 0, res.output
    camp = tmp_path / "campaigns" / "red-sky"
    assert (camp / "bible.yaml").is_file()
    assert (camp / "missions").is_dir() and not any((camp / "missions").iterdir())
    assert (camp / "state" / "outcomes").is_dir()
    assert not any((camp / "state" / "outcomes").iterdir())
    assert not [p for p in camp.rglob("*") if "example" in p.name]
    res = runner.invoke(app, [*args, "blue-sky", "--with-example"])
    assert res.exit_code == 0, res.output
    assert (tmp_path / "campaigns" / "blue-sky" / "missions" / "m01-example").is_dir()
    assert runner.invoke(app, [*args, "red-sky"]).exit_code == 2
    assert runner.invoke(app, [*args, "Bad Slug"]).exit_code == 2


# ---- real end to end (only when the planner and checker exist) ---------------------------------


def test_run_end_to_end_real(mission: Path) -> None:
    pytest.importorskip("dms_gen.planner")
    pytest.importorskip("dms_gen.check")
    res = invoke("run", str(mission), "--skip-voice", "--seed", "1")
    assert res.exit_code in (0, 1), res.output
    assert "[4/5] build" in res.output, res.output
    assert (mission / "out" / "m01-first-light.miz").is_file()


def test_plan_error_is_clean_exit_1(mission: Path, fakes: types.SimpleNamespace) -> None:
    class PlanError(Exception):
        pass

    def boom(spec: Any, **kw: Any) -> Any:
        raise PlanError("area 'x' is not on land")

    fakes.planner.plan_mission = boom
    res = invoke("plan", str(mission))
    assert res.exit_code == 1
    assert "planning failed: area 'x' is not on land" in res.output


def test_build_writes_runtime_config(
    mission: Path, fakes: types.SimpleNamespace, lua_file: Path
) -> None:
    assert invoke("plan", str(mission)).exit_code == 0
    plan_path = mission / "out" / "plan.json"
    data = json.loads(plan_path.read_text(encoding="utf-8"))
    data["resources"] = [
        {"path": "l10n/DEFAULT/dms_config.lua", "source": "dms_config.lua", "kind": "script"},
        {"path": "l10n/DEFAULT/dms.lua", "source": "dist/dms.lua", "kind": "script"},
    ]
    plan_path.write_text(json.dumps(data), encoding="utf-8")
    res = invoke("build", str(plan_path), "--lua", str(lua_file))
    assert res.exit_code == 0, res.output
    cfg = mission / "out" / "dms_config.lua"
    assert "DMS_CONFIG" in cfg.read_text(encoding="utf-8")
    assert "runtime config:" in res.output


def test_build_test_writes_out_test_only(mission: Path, lua_file: Path) -> None:
    pytest.importorskip("dms_gen.planner")
    pytest.importorskip("dms_gen.check")
    out = mission / "out"
    out.mkdir(exist_ok=True)
    sentinel = '{"seed": 5}'
    (out / "plan.json").write_text(sentinel, encoding="utf-8")
    res = invoke("build", "--test", str(mission), "--lua", str(lua_file))
    assert res.exit_code == 0, res.output
    assert (out / "plan.json").read_text(encoding="utf-8") == sentinel
    assert not (out / "m01-first-light.miz").exists()
    assert (out / "m01-first-light-test.miz").is_file()
    assert (out / "test" / "plan.test.json").is_file()
    assert (out / "test" / "dms_config.lua").is_file()
    assert "playerProxy" in (out / "test" / "dms_test.lua").read_text(encoding="utf-8")
    assert "test: planned seed 5" in res.output
    assert "Proxy Dusty 1" in res.output
    assert "run_mission.py" in res.output and "--accel 16" in res.output
    with zipfile.ZipFile(out / "m01-first-light-test.miz") as z:
        assert "l10n/DEFAULT/dms_test.lua" in z.namelist()


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
    plan = types.SimpleNamespace(resources=res, runtime=None)
    assert cli._attach_lua(plan, tmp_path / "dms.lua", tmp_path) == "added"
    names = [Path(r.path).name for r in plan.resources]
    want = [Path(files[k]).name for k in existing if k != "adapter"] + ["dms.lua"]
    want += [Path(files["adapter"]).name] if "adapter" in existing else []
    assert names == want
