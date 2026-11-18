from __future__ import annotations

import datetime as dt
from pathlib import Path

from dms_core.miz import MizFile
from dms_core.schemas.plan import (
    BuildPlan,
    PlanGroup,
    PlanResource,
    PlanUnit,
    PlanWaypoint,
)
from dms_core.schemas.runtime import RuntimeConfig, VoiceEntry
from dms_gen.builder import build_from_plan
from dms_gen.check import check_miz, lua51_syntax_error


def _plan(resources: list[PlanResource], runtime: RuntimeConfig | None, **kw: object) -> BuildPlan:
    groups = [
        PlanGroup(
            name="Dusty 1",
            category="helicopter",
            coalition="blue",
            country="USA",
            client=True,
            units=[PlanUnit(name="Dusty 1-1", type="AH-64D_BLK_II", x=0, y=0, skill="Client")],
            route=[PlanWaypoint(x=0, y=0, action="From Parking Area", airbase="Hatay")],
        ),
        PlanGroup(
            name="red_1",
            category="vehicle",
            coalition="red",
            country="Insurgents",
            hidden=bool(kw.get("hidden", True)),
            units=[PlanUnit(name="red_1-1", type="BMP-2", x=140000, y=60000)],
        ),
    ]
    return BuildPlan(
        mission_id="c01",
        seed=1,
        theater="Syria",
        date=dt.date(2012, 4, 1),
        start_time_sec=3600 * 6,
        blue_countries=["USA"],
        red_countries=["Insurgents"],
        groups=groups,
        resources=resources,
        runtime=runtime,
    )


def _lua(tmp: Path, name: str, body: str) -> PlanResource:
    (tmp / name).write_text(body, encoding="utf-8")
    return PlanResource(path=f"l10n/DEFAULT/{name}", source=name, kind="script")


def test_lua51_syntax_helper() -> None:
    assert lua51_syntax_error(b"local x = 1") is None
    assert lua51_syntax_error(b"goto done ::done::") is not None  # 5.2+ only
    assert lua51_syntax_error(b"local x = = 1") is not None


def test_check_flags_problems(tmp_path: Path) -> None:
    rt = RuntimeConfig(
        mission_id="c01",
        voice={"v1": VoiceEntry(file="v1.ogg", text="hi", dur_sec=1, speaker="ops")},
    )
    res = [
        _lua(tmp_path, "plugin.lua", "local = broken"),
        _lua(tmp_path, "dms_config.lua", rt.to_lua_source()),
        _lua(tmp_path, "dms.lua", "x = 1"),
    ]
    out = build_from_plan(_plan(res, rt, hidden=False), tmp_path / "bad.miz", base_dir=tmp_path)
    rep = check_miz(out)
    codes = {i.code for i in rep.issues}
    assert not rep.ok
    assert "lua_syntax" in codes  # plugin.lua
    assert "voice_file_missing" in codes  # v1.ogg never embedded
    assert "enemy_not_hidden" in codes  # fog of war default on


def test_check_order_and_missing_config(tmp_path: Path) -> None:
    out = build_from_plan(
        _plan([_lua(tmp_path, "dms.lua", "x = 1")], None), tmp_path / "nocfg.miz", base_dir=tmp_path
    )
    codes = {i.code for i in check_miz(out).issues}
    assert "no_dms_config" in codes

    res = [
        _lua(tmp_path, "dms.lua", "x = 1"),
        _lua(tmp_path, "dms_config.lua", "DMS_CONFIG = {version = 1}"),
    ]
    out2 = build_from_plan(_plan(res, None), tmp_path / "order.miz", base_dir=tmp_path)
    rep = check_miz(out2)
    codes = {i.code for i in rep.issues}
    assert {"script_order", "config_key_missing"} <= codes


def test_check_duplicates_and_slots(tmp_path: Path) -> None:
    rt = RuntimeConfig(mission_id="c01")
    res = [_lua(tmp_path, "dms_config.lua", rt.to_lua_source()), _lua(tmp_path, "dms.lua", "x=1")]
    out = build_from_plan(_plan(res, rt), tmp_path / "ok.miz", base_dir=tmp_path)
    assert check_miz(out).ok
    miz = MizFile.open(out)
    mission = miz.table("mission")
    for side in mission["coalition"].values():
        for country in side["country"].values():
            for cat in ("helicopter", "vehicle"):
                for g in (country.get(cat) or {}).get("group", {}).values():
                    for u in g["units"].values():
                        u["unitId"] = 1
                        u["skill"] = "High"
                        u["x"] = 9e6
    miz.mark_dirty("mission")
    miz.save(tmp_path / "dup.miz")
    codes = {i.code for i in check_miz(tmp_path / "dup.miz").issues}
    assert {"duplicate_unit_id", "no_player_slot", "unit_off_map"} <= codes


def test_check_fog_defaults_on_unless_false() -> None:
    from dms_gen.check import CheckReport, _check_fog

    mission = {
        "coalition": {
            "red": {
                "country": [{"vehicle": {"group": [{"name": "red_1", "hidden": False}]}}],
            }
        }
    }
    for cfg, expect in (
        ({}, True),  # no intel table: fog of war is on
        ({"intel": {}}, True),  # fogOfWar nil: on
        ({"intel": {"fogOfWar": True}}, True),
        ({"intel": {"fogOfWar": False}}, False),
    ):
        rep = CheckReport(path="x.miz")
        _check_fog(rep, mission, cfg)
        assert ("enemy_not_hidden" in {i.code for i in rep.issues}) is expect, cfg
