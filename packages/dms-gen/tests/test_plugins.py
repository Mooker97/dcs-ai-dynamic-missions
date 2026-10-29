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


# ---------------------------------------------------------------- generated DMS_SKYNET

P01 = REPO / "campaigns" / "plugin-smoke" / "missions" / "p01-skynet"


def _load_mission(mdir: Path) -> tuple[Any, Any, Any]:
    from dms_core.schemas import BeatSheet, MissionSpec, StoryBible

    if not (mdir / "mission-spec.yaml").is_file():
        pytest.skip(f"{mdir.name} not present")

    def load(p: Path) -> Any:
        return yaml.safe_load(p.read_text(encoding="utf-8"))

    spec = MissionSpec.model_validate(load(mdir / "mission-spec.yaml"))
    bible = StoryBible.model_validate(load(mdir.parents[1] / "bible.yaml"))
    beats = BeatSheet.model_validate(load(mdir / "beats.yaml"))
    return spec, beats, bible


def _embedded_config(miz_path: Path) -> dict[str, Any]:
    from dms_core.luaio import loads
    from dms_core.miz import MizFile

    src = MizFile.open(miz_path).read_bytes("l10n/DEFAULT/dms_config.lua").decode("utf-8")
    out: dict[str, Any] = loads(src, arrays=True)
    return out


def test_skynet_options_cover_planned_sam_groups_only() -> None:
    from dms_core.luaio import loads
    from dms_core.schemas.mission import Threat

    threats = [
        Threat.model_construct(id="sa6_site", role="sam_medium"),
        Threat.model_construct(id="sa10", role="sam_long"),
        Threat.model_construct(id="aaa", role="aaa"),
    ]

    def grp(name: str, source: str | None, category: str = "vehicle") -> PlanGroup:
        return PlanGroup(
            name=name,
            category=category,  # type: ignore[arg-type]
            coalition="red",
            country="Insurgents",
            units=[PlanUnit(name=name + "-1", type="Kub 1S91 str", x=0, y=0)],
            source=source,
        )

    groups = [
        grp("sa6_site_1", "sa6_site"),
        grp("aaa_1", "aaa"),
        grp("sa10_1", "sa10"),
        grp("sa10_pd", "sa10"),
        grp("Python 1", None, "plane"),
    ]
    assert plugins.skynet_options([], threats, groups) is None
    assert plugins.skynet_options(["moose"], threats, groups) is None
    opts = plugins.skynet_options(["skynet"], threats, groups)
    assert opts is not None
    assert opts.prefixes == ["DMS_", "sa6_site_1", "sa10_1", "sa10_pd"]
    assert loads(plugins.skynet_lua(opts), arrays=True)["DMS_SKYNET"] == {"prefixes": opts.prefixes}


def test_plan_without_skynet_emits_no_dms_skynet(tmp_path: Path) -> None:
    from dms_gen.planner import write_runtime_config

    spec, beats, bible = _m01()
    plan = plan_mission(spec, beats, seed=1, bible=bible)
    assert plan.skynet is None
    text = write_runtime_config(plan, tmp_path).read_text(encoding="utf-8")
    assert "DMS_CONFIG" in text and "DMS_SKYNET" not in text


def test_built_config_has_dms_skynet_for_planned_sams(tmp_path: Path) -> None:
    """p01-skynet: DMS_SKYNET.prefixes = DMS_ + the planned SA-6 group; ambush SAMs left to DMS_."""
    from dms_gen.planner import write_runtime_config

    spec, beats, bible = _load_mission(P01)
    assert spec.plugins == ["skynet"]
    plan = plan_mission(spec, beats, seed=7, bible=bible)
    sam_ids = {t.id for t in spec.threats if t.role in plugins.SAM_ROLES}
    planned_sams = [g.name for g in plan.groups if g.source in sam_ids]
    assert planned_sams == ["sa6_site_1"]
    assert plan.skynet is not None
    assert plan.skynet.prefixes == ["DMS_", *planned_sams]
    # ambush_sam pools are never listed by name: the adapter skips their DMS_<pool>_<n> spawns
    ambush_pools = {e.pool for e in spec.dynamic.encounters if e.kind == "ambush_sam"}
    assert ambush_pools == {"sa6_ambush", "sa8_popup"}
    assert not any(p.startswith(tuple(ambush_pools)) for p in plan.skynet.prefixes)

    cfg = write_runtime_config(plan, tmp_path)
    dms = tmp_path / "dms.lua"
    dms.write_text("DMS = DMS or {}\n", encoding="utf-8")
    for r in plan.resources:
        name = Path(r.path).name
        if name == "dms_config.lua":
            r.source = str(cfg)
        elif name == "dms.lua":
            r.source = str(dms)
    out = build_from_plan(plan, tmp_path / "p01.miz", base_dir=REPO)
    assert _script_order(out)[-3:] == ["dms_config.lua", "dms.lua", "skynet_adapter.lua"]
    g = _embedded_config(out)
    assert g["DMS_SKYNET"] == {"prefixes": ["DMS_", "sa6_site_1"]}
    assert g["DMS_CONFIG"]["missionId"] == "p01-skynet"
    assert "lua_syntax" not in _codes(check_miz(out))
