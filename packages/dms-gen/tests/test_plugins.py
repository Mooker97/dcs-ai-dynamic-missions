"""Optional pinned plugins: resolution, planner resources, build embedding and ``dms check``."""

from __future__ import annotations

import datetime as dt
from pathlib import Path
from typing import Any

import pytest
import yaml
from dms_core.schemas.plan import BuildPlan, PlanGroup, PlanResource, PlanUnit, PlanWaypoint
from dms_core.schemas.runtime import RuntimeConfig
from dms_gen import plugins
from dms_gen.builder import build_from_plan, inspect
from dms_gen.check import CheckReport, check_miz
from dms_gen.planner import PlanError, plan_mission

REPO = Path(__file__).resolve().parents[3]
M01 = REPO / "campaigns" / "dustoff-valley" / "missions" / "m01-first-light"
MIST = plugins.PLUGINS["mist"]
SKYNET = plugins.PLUGINS["skynet"]
MOOSE = plugins.PLUGINS["moose"]
ADAPTER = plugins.PLUGINS["skynet_adapter"]


def _plan(resources: list[PlanResource]) -> BuildPlan:
    return BuildPlan(
        mission_id="p01",
        seed=1,
        theater="Syria",
        date=dt.date(2012, 4, 1),
        start_time_sec=3600 * 6,
        blue_countries=["USA"],
        red_countries=["Insurgents"],
        groups=[
            PlanGroup(
                name="Dusty 1",
                category="helicopter",
                coalition="blue",
                country="USA",
                client=True,
                units=[PlanUnit(name="Dusty 1-1", type="AH-64D_BLK_II", x=0, y=0, skill="Client")],
                route=[PlanWaypoint(x=0, y=0, action="From Parking Area", airbase="Hatay")],
            )
        ],
        resources=resources,
        runtime=RuntimeConfig(version=1, seed=1, mission_id="p01"),
    )


def _build(tmp: Path, sources: list[str]) -> Path:
    """Build with scripts in the given order; ``dms.lua`` is a stub, plugin paths repo-relative."""
    dms = tmp / "dms.lua"
    dms.write_text("DMS = DMS or {}\n", encoding="utf-8")
    res = [
        PlanResource(
            path=f"l10n/DEFAULT/{Path(s).name}",
            source=str(dms) if s == "dms.lua" else s,
            kind="script",
        )
        for s in sources
    ]
    return build_from_plan(_plan(res), tmp / "p.miz", base_dir=REPO)


def _script_order(miz: Path) -> list[str]:
    s = inspect(miz)
    start = next(t for t in s.triggers if t["comment"] == "DMS: load scripts")
    return [s.resources[a["file"]] for a in start["actions"]]


def _codes(rep: CheckReport, severity: str | None = None) -> set[str]:
    return {i.code for i in rep.issues if severity is None or i.severity == severity}


# ---------------------------------------------------------------- registry


def test_resolve_adds_dependencies_and_adapter_in_order() -> None:
    assert [p.name for p in plugins.resolve(["skynet"])] == ["mist", "skynet", "skynet_adapter"]
    assert [p.name for p in plugins.resolve(["skynet", "moose", "mist"])] == [
        "mist",
        "moose",
        "skynet",
        "skynet_adapter",
    ]
    assert plugins.resolve([]) == []
    before, after = plugins.split_files(["skynet"])
    assert before == [MIST.file, SKYNET.file]
    assert after == [ADAPTER.file]


def test_resolve_rejects_unknown_and_adapter_names() -> None:
    with pytest.raises(KeyError):
        plugins.resolve(["ctld"])
    with pytest.raises(KeyError):
        plugins.resolve(["skynet_adapter"])


def test_registry_matches_spec_literal() -> None:
    from typing import get_args

    from dms_core.schemas.mission import PluginName

    assert sorted(get_args(PluginName)) == sorted(plugins.user_names())


def test_registry_files_exist_and_basenames_unique() -> None:
    names = [p.basename for p in plugins.PLUGINS.values()]
    assert len(names) == len(set(names))
    assert not {"dms.lua", "dms_config.lua", "dms_test.lua"} & set(names)
    for p in plugins.PLUGINS.values():
        assert (REPO / p.file).is_file(), p.file


# ---------------------------------------------------------------- planner


def _m01() -> tuple[Any, Any, Any]:
    from dms_core.schemas import BeatSheet, MissionSpec, StoryBible

    if not (M01 / "mission-spec.yaml").is_file():
        pytest.skip("m01 not present")

    def load(p: Path) -> Any:
        return yaml.safe_load(p.read_text(encoding="utf-8"))

    spec = MissionSpec.model_validate(load(M01 / "mission-spec.yaml"))
    bible = StoryBible.model_validate(load(M01.parents[1] / "bible.yaml"))
    beats = BeatSheet.model_validate(load(M01 / "beats.yaml"))
    return spec, beats, bible


def test_plan_without_plugins_is_unchanged() -> None:
    spec, beats, bible = _m01()
    plan = plan_mission(spec, beats, seed=1, bible=bible)
    scripts = [Path(r.path).name for r in plan.resources if r.kind == "script"]
    assert scripts == ["dms_config.lua", "dms.lua"]


def test_plan_with_skynet_orders_plugin_resources() -> None:
    spec, beats, bible = _m01()
    spec = spec.model_copy(update={"plugins": ["skynet"]})
    plan = plan_mission(spec, beats, seed=1, bible=bible, plugins=["extra/custom.lua"])
    scripts = [(Path(r.path).name, r.source) for r in plan.resources if r.kind == "script"]
    assert scripts == [
        ("mist_4_5_126.lua", MIST.file),
        ("skynet-iads-compiled.lua", SKYNET.file),
        ("custom.lua", "extra/custom.lua"),
        ("dms_config.lua", "dms_config.lua"),
        ("dms.lua", "dist/dms.lua"),
        ("skynet_adapter.lua", ADAPTER.file),
    ]


def test_plan_rejects_unknown_plugin() -> None:
    spec, beats, bible = _m01()
    spec = spec.model_construct(**{**dict(spec), "plugins": ["nope"]})
    with pytest.raises(PlanError, match="unknown plugin"):
        plan_mission(spec, beats, seed=1, bible=bible)


# ---------------------------------------------------------------- build + check


def test_build_embeds_skynet_in_order_and_check_passes(tmp_path: Path) -> None:
    out = _build(tmp_path, [MIST.file, SKYNET.file, "dms.lua", ADAPTER.file])
    order = _script_order(out)
    # build_from_plan inserts the generated dms_config.lua before dms.lua
    assert order == [
        "mist_4_5_126.lua",
        "skynet-iads-compiled.lua",
        "dms_config.lua",
        "dms.lua",
        "skynet_adapter.lua",
    ]
    rep = check_miz(out)
    assert not _codes(rep) & {"plugin_order", "plugin_dependency", "plugin_unpinned"}
    assert "lua_syntax" not in _codes(rep)
    assert "plugins" in _codes(rep, "info")
    assert rep.stats["plugins"] == 3
    # the embedded bytes are the pinned ones
    from dms_core.miz import MizFile

    miz = MizFile.open(out)
    data = miz.read_bytes("l10n/DEFAULT/skynet-iads-compiled.lua")
    assert plugins.file_sha256(data) == SKYNET.sha256


def test_build_embeds_moose(tmp_path: Path) -> None:
    out = _build(tmp_path, [MIST.file, MOOSE.file, "dms.lua"])
    assert _script_order(out)[:2] == ["mist_4_5_126.lua", "Moose_.lua"]
    rep = check_miz(out)
    assert not _codes(rep) & {"plugin_order", "plugin_dependency", "plugin_unpinned", "lua_syntax"}


def test_check_flags_plugin_after_dms(tmp_path: Path) -> None:
    out = _build(tmp_path, ["dms.lua", MIST.file])
    assert "plugin_order" in _codes(check_miz(out), "error")


def test_check_flags_skynet_without_mist(tmp_path: Path) -> None:
    out = _build(tmp_path, [SKYNET.file, "dms.lua", ADAPTER.file])
    rep = check_miz(out)
    errors = [i for i in rep.issues if i.code == "plugin_dependency" and i.severity == "error"]
    assert errors and "mist" in errors[0].message


def test_check_flags_adapter_before_dms(tmp_path: Path) -> None:
    out = _build(tmp_path, [MIST.file, SKYNET.file, ADAPTER.file, "dms.lua"])
    assert "plugin_order" in _codes(check_miz(out), "error")


def test_check_adapter_without_skynet_is_a_warning(tmp_path: Path) -> None:
    out = _build(tmp_path, ["dms.lua", ADAPTER.file])
    rep = check_miz(out)
    assert "plugin_dependency" in _codes(rep, "warning")
    assert "plugin_dependency" not in _codes(rep, "error")


def test_check_warns_on_unpinned_plugin(tmp_path: Path) -> None:
    fake = tmp_path / "plug" / "mist_4_5_126.lua"
    fake.parent.mkdir()
    fake.write_text("mist = {}\n", encoding="utf-8")
    out = _build(tmp_path, [str(fake), "dms.lua"])
    assert "plugin_unpinned" in _codes(check_miz(out), "warning")


def test_plan_dedups_explicit_plugins_by_name() -> None:
    spec, beats, bible = _m01()
    spec = spec.model_copy(update={"plugins": ["skynet"]})
    plan = plan_mission(
        spec,
        beats,
        seed=1,
        bible=bible,
        plugins=["C:/elsewhere/mist_4_5_126.lua", "a/custom.lua", "b/custom.lua"],
    )
    names = [Path(r.path).name for r in plan.resources if r.kind == "script"]
    assert names.count("mist_4_5_126.lua") == 1 and names.count("custom.lua") == 1
    assert len(names) == len(set(names))


def test_dms_lua_insert_index_keeps_plugins_first_adapters_last() -> None:
    from dms_gen.plugins import dms_lua_insert_index

    paths = [f"l10n/DEFAULT/{Path(p).name}" for p in (MIST.file, SKYNET.file, ADAPTER.file)]
    assert dms_lua_insert_index(paths) == 2  # after skynet, before the adapter
    assert dms_lua_insert_index([f"l10n/DEFAULT/{Path(ADAPTER.file).name}"]) == 0
    assert dms_lua_insert_index([]) == 0
    assert dms_lua_insert_index(["l10n/DEFAULT/dms_config.lua", "x/briefing.lua"]) == 1
