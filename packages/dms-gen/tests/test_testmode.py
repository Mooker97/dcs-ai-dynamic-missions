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
from dms_gen.planner.testmode import default_checks, runtime_plugins, to_lua

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
    assert kinds[-7:] == [
        "marks",
        "fog_hidden",
        "comms_no_overlap",
        "comms_beats",
        "convoy_halt",
        "voice_files",
        "outcome",
    ]
    names = [t.checks[i].name for i in range(1, len(t.checks) + 1)]
    assert names[-7:-3] == ["f10_marks", "fog_hidden", "radio_no_overlap", "spine_lines_played"]
    # no flights / watch / plugins in m01: none of the A3 conditional kinds
    for k in ("flight_orders", "flight_strike", "camera_cues", "watch_mode", "plugins"):
        assert k not in kinds
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


@pytest.mark.parametrize("task", [None, "CAS", "CAP"])
def test_build_test_miz_has_ai_proxy_with_landing(
    m01: Any, tmp_path: Path, task: str | None
) -> None:
    plan, spec, beats = m01
    tb = make_test_plan(plan, spec, beats)
    tp = tb.plan
    if task is not None:
        # CAS/CAP map to canned AI flights; a proxy with a planned Landing must keep its route
        next(g for g in tp.groups if g.name == tb.proxy).task = task
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


# ---- A3 check kinds: flight_strike, camera_cues, voice_files, watch_mode, plugins -----------

W01 = REPO / "campaigns" / "dustoff-valley" / "missions" / "w01-dustoff-under-fire"


@pytest.fixture(scope="module")
def w01() -> tuple[Any, MissionSpec, BeatSheet, VoiceLineSet]:
    spec = MissionSpec.model_validate(_yaml(W01 / "mission-spec.yaml"))
    beats = BeatSheet.model_validate(_yaml(W01 / "beats.yaml"))
    bible = StoryBible.model_validate(_yaml(BIBLE))
    lines = VoiceLineSet.model_validate(_yaml(W01 / "lines.yaml"))
    return plan_mission(spec, beats, lines, seed=7, bible=bible), spec, beats, lines


def _checks(lua_src: str) -> list[dict[str, Any]]:
    lupa = pytest.importorskip("lupa")
    lua = lupa.lua51.LuaRuntime(unpack_returned_tuples=True)
    lua.execute(lua_src)
    t = lua.eval("DMS_CONFIG.test")
    out: list[dict[str, Any]] = []
    for i in range(1, len(t.checks) + 1):
        c = t.checks[i]
        d: dict[str, Any] = {k: c[k] for k in c}
        for k in ("plugins", "subtitleOnly"):
            if d.get(k) is not None:
                d[k] = [d[k][j] for j in range(1, len(d[k]) + 1)]
        out.append(d)
    return out


def test_default_checks_a3_kinds_are_conditional() -> None:
    base = [c["kind"] for c in default_checks(10, [], [])]
    assert "voice_files" in base  # always
    for k in ("flight_strike", "camera_cues", "watch_mode", "plugins"):
        assert k not in base
    full = default_checks(
        10,
        [],
        [],
        flights=True,
        strike=True,
        cues=True,
        watch=True,
        plugins=["mist", "skynet"],
        subtitle_only=["b", "a", "a"],
    )
    kinds = [c["kind"] for c in full]
    assert kinds[-7:] == [
        "voice_files",
        "flight_orders",
        "flight_strike",
        "camera_cues",
        "watch_mode",
        "plugins",
        "outcome",
    ]
    by = {c["kind"]: c for c in full}
    assert by["voice_files"]["subtitleOnly"] == ["a", "b"]
    assert by["plugins"] == {
        "kind": "plugins",
        "name": "plugins",
        "plugins": ["mist", "skynet"],
        "deadlineSec": 570,
    }
    # end-of-run checks carry no deadline (they resolve with DONE)
    for k in ("flight_strike", "camera_cues", "watch_mode", "voice_files"):
        assert "deadlineSec" not in by[k]


def test_runtime_plugins_expands_dependencies() -> None:
    assert runtime_plugins([]) == []
    assert runtime_plugins(["skynet"]) == ["mist", "skynet"]
    assert runtime_plugins(["moose"]) == ["moose"]
    assert runtime_plugins(["moose", "mist"]) == ["mist", "moose"]


def test_watch_test_build_adds_a3_checks(w01: Any) -> None:
    plan, spec, beats, lines = w01
    sub = [ln.id for ln in lines.lines if not ln.voiced]
    assert sub, "w01 has voiced:false lines"
    tb = make_test_plan(plan, spec, beats, subtitle_only=sub)
    checks = _checks(tb.lua)
    kinds = [c["kind"] for c in checks]
    for k in ("flight_orders", "flight_strike", "camera_cues", "watch_mode", "voice_files"):
        assert kinds.count(k) == 1, k
    assert "plugins" not in kinds
    assert kinds[-1] == "outcome"
    voice = next(c for c in checks if c["kind"] == "voice_files")
    assert voice["subtitleOnly"] == sorted(set(sub))
    # without the line set the check still runs, just without the voiced:false list
    plain = _checks(make_test_plan(plan, spec, beats).lua)
    assert next(c for c in plain if c["kind"] == "voice_files").get("subtitleOnly") is None


def test_watch_cues_off_drops_camera_cues(w01: Any) -> None:
    plan, spec, beats, _ = w01
    assert spec.watch is not None
    spec_off = spec.model_copy(update={"watch": spec.watch.model_copy(update={"cues": False})})
    p2 = plan.model_copy(deep=True)
    assert p2.runtime is not None and p2.runtime.watch is not None
    p2.runtime.watch.cues = False
    kinds = [c["kind"] for c in _checks(make_test_plan(p2, spec_off, beats).lua)]
    assert "camera_cues" not in kinds
    assert "watch_mode" in kinds


def test_plugins_check_from_spec(m01: Any) -> None:
    plan, spec, beats = m01
    sp = spec.model_copy(update={"plugins": ["skynet"]})
    checks = _checks(make_test_plan(plan, sp, beats, minutes=30).lua)
    plug = [c for c in checks if c["kind"] == "plugins"]
    assert len(plug) == 1
    assert plug[0]["plugins"] == ["mist", "skynet"]
    assert plug[0]["deadlineSec"] == 30 * 60 - 30
    kinds = [c["kind"] for c in checks]
    assert "watch_mode" not in kinds and "camera_cues" not in kinds
    assert "flight_strike" not in kinds
