"""Test build (dms build --test): AI player proxy + dms_test.lua."""

from __future__ import annotations

from pathlib import Path
from typing import Any

import pytest
import yaml
from dms_core.miz import MizFile
from dms_core.schemas import BeatSheet, MissionSpec, StoryBible, VoiceLineSet
from dms_core.schemas.runtime import CircleZone, PolygonZone
from dms_gen.builder import build_from_plan
from dms_gen.check import check_miz
from dms_gen.planner import make_test_plan, plan_mission, write_runtime_config, write_test_lua
from dms_gen.planner.testmode import to_lua

REPO = Path(__file__).resolve().parents[3]
M01 = REPO / "campaigns" / "dustoff-valley" / "missions" / "m01-first-light"
BIBLE = REPO / "campaigns" / "dustoff-valley" / "bible.yaml"


def _yaml(p: Path) -> Any:
    return yaml.safe_load(p.read_text(encoding="utf-8"))


@pytest.fixture(scope="module")
def m01() -> tuple[Any, MissionSpec, BeatSheet]:
    spec = MissionSpec.model_validate(_yaml(M01 / "mission-spec.yaml"))
    beats = BeatSheet.model_validate(_yaml(M01 / "beats.yaml"))
    bible = StoryBible.model_validate(_yaml(BIBLE))
    lines = VoiceLineSet.model_validate(_yaml(M01 / "lines.yaml"))
    return plan_mission(spec, beats, lines, seed=7, bible=bible), spec, beats


def _items(t: Any) -> list[Any]:
    if isinstance(t, dict):
        return [t[k] for k in sorted(t)]
    return list(t or [])


def test_proxy_replaces_client_and_flies_spine_zones(m01: Any) -> None:
    plan, spec, beats = m01
    tb = make_test_plan(plan, spec, beats)
    assert not any(g.client for g in tb.plan.groups)
    assert any(g.client for g in plan.groups), "original plan must be untouched"
    proxy = next(g for g in tb.plan.groups if g.name == tb.proxy)
    assert tb.proxy == "Proxy Dusty 1"
    assert proxy.units[0].skill == "High"
    assert proxy.units[0].type == "AH-64D_BLK_II"
    route = proxy.route
    assert route[0].action == "From Parking Area Hot" and route[0].airbase == "Hatay"
    assert route[-1].action == "Landing" and route[-1].airbase == "Hatay"
    legs = route[1:-1]
    assert all(p.action == "Turning Point" and p.alt_type == "RADIO" for p in legs)
    # gate_west, 4 patrol_box corners + back to the first corner, gate_west
    assert len(legs) == 7
    assert (legs[0].x, legs[0].y) == (legs[-1].x, legs[-1].y)
    assert (legs[1].x, legs[1].y) == (legs[5].x, legs[5].y)
    assert tb.plan.runtime is not None
    zones = tb.plan.runtime.zones
    gw = zones["gate_west"]
    pb = zones["patrol_box"]
    assert isinstance(gw, CircleZone) and isinstance(pb, PolygonZone)
    assert abs(legs[0].x - gw.x) < 1 and abs(legs[0].y - gw.y) < 1
    from dms_gen.builder.geo import point_in_polygon

    box = [(p.x, p.y) for p in pb.points]
    assert all(point_in_polygon((p.x, p.y), box) for p in legs[1:6])
    assert tb.route_km > 50
    assert tb.minutes >= 8


def test_runtime_tweaks_and_script_order(m01: Any) -> None:
    plan, spec, beats = m01
    tb = make_test_plan(plan, spec, beats, minutes=30)
    rt = tb.plan.runtime
    assert rt is not None and plan.runtime is not None
    assert rt.debug is True
    assert all(e.chance == 100 for e in rt.encounters)
    for e in rt.encounters:
        if e.trigger.type == "time":
            a = e.trigger.after_sec
            assert isinstance(a, int | float) and a <= 240
    assert plan.runtime.encounters[0].chance == 70, "original plan must be untouched"
    names = [Path(r.path).name for r in tb.plan.resources if r.kind == "script"]
    assert names.index("dms_config.lua") + 1 == names.index("dms_test.lua")
    assert names.index("dms_test.lua") < names.index("dms.lua")
    assert tb.minutes == 30


def test_test_lua_compiles_and_sets_config(m01: Any) -> None:
    lupa = pytest.importorskip("lupa")
    plan, spec, beats = m01
    tb = make_test_plan(plan, spec, beats, minutes=40)
    lua = lupa.lua51.LuaRuntime(unpack_returned_tuples=True)
    lua.execute(tb.lua)
    t = lua.eval("DMS_CONFIG.test")
    assert t.enabled is True
    assert t.playerProxy == "Proxy Dusty 1"
    assert t.minutes == 40
    kinds = [t.checks[i].kind for i in range(1, len(t.checks) + 1)]
    assert kinds[:4] == ["booted", "spawns", "beats_in_order", "comms"]
    assert tb.plan.runtime is not None
    assert kinds.count("encounter") == len(tb.plan.runtime.encounters)
    # end-of-run checks (CONTRACTS test section), then convoy_halt and the outcome
    assert kinds[-6:] == [
        "marks",
        "fog_hidden",
        "comms_no_overlap",
        "comms_beats",
        "convoy_halt",
        "outcome",
    ]
    names = [t.checks[i].name for i in range(1, len(t.checks) + 1)]
    assert names[-6:-2] == ["f10_marks", "fog_hidden", "radio_no_overlap", "spine_lines_played"]
    spine = t.checks[3].beats
    assert [spine[i] for i in range(1, len(spine) + 1)] == [
        "mission_start",
        "kestrel_checkin",
        "on_station",
        "patrol_complete",
        "tower_welcome",
        "on_deck",
    ]
    # any mission end passes unless the spec asks for a result (mission-spec test.require_result);
    # no loiter: the spine's tower_welcome zone beat precedes on_deck
    assert t.checks[len(t.checks)].requireResult is None
    assert t.checks[len(t.checks)].result is None
    assert t.loiter is None
    assert t.checks[2].deadlineSec == 40 * 60 - 30
    assert lua.eval("DMS_CONFIG.debug") is True


def test_to_lua_escapes() -> None:
    assert to_lua({"a": 'x"y\\z\n', "and": [1, 2.5, True, None]}) == (
        '{ a = "x\\"y\\\\z\\n", ["and"] = { 1, 2.5, true, nil } }'
    )


def test_build_test_miz_has_ai_proxy_with_landing(m01: Any, tmp_path: Path) -> None:
    plan, spec, beats = m01
    tb = make_test_plan(plan, spec, beats)
    tp = tb.plan
    write_test_lua(tb, tmp_path)
    for r in tp.resources:
        if r.path.endswith("dms_config.lua"):
            r.source = str(tmp_path / "dms_config.lua")
        elif r.path.endswith("dms.lua"):
            (tmp_path / "dms.lua").write_text('env.info("dms")\n', encoding="utf-8")
            r.source = str(tmp_path / "dms.lua")
    write_runtime_config(tp, tmp_path)
    tp.resources = [r for r in tp.resources if r.kind == "script"]
    out = build_from_plan(tp, tmp_path / "t.miz", base_dir=tmp_path)
    mis = MizFile.open(out).table("mission")
    found = None
    for c in _items(mis["coalition"]["blue"]["country"]):
        for g in _items((c.get("helicopter") or {}).get("group")):
            if g["name"] == tb.proxy:
                found = g
    assert found is not None
    assert all(u["skill"] not in ("Client", "Player") for u in _items(found["units"]))
    pts = _items(found["route"]["points"])
    assert pts[0]["type"] == "TakeOffParkingHot"
    assert pts[-1]["type"] == "Land" and pts[-1]["action"] == "Landing"
    assert [p["alt_type"] for p in pts[1:-1]] == ["RADIO"] * (len(pts) - 2)
    rep = check_miz(out)
    assert rep.ok, rep.errors
    assert any(i.code == "no_player_slot" and i.severity == "warning" for i in rep.issues)
