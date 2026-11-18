"""AI flights with orders and watch missions (CONTRACTS "AI flights and watch missions (v0.9)")."""

from __future__ import annotations

from pathlib import Path
from typing import Any

import pytest
from dms_core.miz import MizFile
from dms_core.schemas import BeatSheet, MissionSpec
from dms_core.schemas.runtime import RuntimeConfig
from dms_gen.builder import build_from_plan
from dms_gen.planner import plan_mission, write_runtime_config
from dms_gen.planner.testmode import make_test_plan
from pydantic import ValidationError


def watch_data(**over: Any) -> dict[str, Any]:
    data: dict[str, Any] = {
        "id": "w01-dustoff",
        "title": "Dustoff",
        "theater": "Syria",
        "era": 2012,
        "date": "2012-05-02",
        "mission_type": "CSAR",
        "duration_min": 40,
        "areas": [
            {"id": "hatay", "where": {"kind": "near_airbase", "airbase": "Hatay", "radius_nm": 1}},
            {
                "id": "gate_west",
                "where": {
                    "kind": "near_airbase",
                    "airbase": "Hatay",
                    "radius_nm": 0.5,
                    "bearing_deg": 120,
                    "distance_nm": 8,
                },
            },
            {
                "id": "lz_ridge",
                "where": {"kind": "near_named_place", "place": "Reyhanli", "radius_nm": 0.5},
            },
            {
                "id": "canal_east",
                "where": {
                    "kind": "near_named_place",
                    "place": "Reyhanli",
                    "radius_nm": 1,
                    "bearing_deg": 90,
                    "distance_nm": 3,
                },
            },
        ],
        "objectives": [
            {
                "id": "rescue",
                "kind": "rescue",
                "description": "Get Kestrel out.",
                "area": "lz_ridge",
            }
        ],
        "threats": [{"id": "technicals", "role": "technicals", "area": "canal_east"}],
        "support": [
            {
                "id": "kestrel",
                "role": "friendly_ground",
                "area": "lz_ridge",
                "callsign": "Kestrel",
                "frequency_mhz": 41.5,
            }
        ],
        "watch": {"focus": "dustoff"},
        "flights": [
            {
                "id": "dustoff",
                "callsign": "Dustoff 3-1",
                "aircraft": "UH-60A",
                "start_area": "hatay",
                "start_alt_ft": 500,
                "start_speed_kts": 100,
                "heading_toward": "gate_west",
                "frequency_mhz": 40.5,
                "modulation": "FM",
                "orders": [
                    {"do": "fly", "to": "gate_west", "alt_ft": 300, "speed_kts": 110},
                    {"do": "hold", "at": "gate_west", "until": {"beat": "lz_cold"}, "max_min": 6},
                    {"do": "land", "at": "lz_ridge", "ground_min": [1, 2], "pickup": "kestrel"},
                    {"do": "fly", "to": "hatay"},
                    {"do": "land", "at": "hatay"},
                ],
            },
            {
                "id": "gunfighter",
                "callsign": "Gunfighter 1-1",
                "aircraft": "AH-64D_BLK_II",
                "count": 2,
                "start_area": "hatay",
                "immortal": True,
                "orders": [
                    {
                        "do": "escort",
                        "flight": "dustoff",
                        "radius_nm": 1.5,
                        "targets": ["ground", "aaa"],
                        "until": {"event": "flight.lifted", "flight": "dustoff"},
                    },
                    {"do": "rtb"},
                ],
            },
            {
                "id": "viper",
                "callsign": "Viper 2-1",
                "aircraft": "F-16C_50",
                "count": 2,
                "start_area": "hatay",
                "start_type": "air",
                "start_alt_ft": 15000,
                "orders": [
                    {"do": "strike", "at": "canal_east", "group": "technicals"},
                    {"do": "rtb"},
                ],
            },
        ],
    }
    data.update(over)
    return data


BEATS = BeatSheet.model_validate(
    {
        "beats": [
            {
                "id": "start",
                "when": {"event": "mission.start"},
                "guaranteed": True,
                "cue": "F2 on Dustoff",
            },
            {"id": "lz_cold", "when": {"after_sec": 120}, "guaranteed": True},
            {
                "id": "lifted",
                "when": {"event": "flight.lifted", "flight": "dustoff", "zone": "lz_ridge"},
                "guaranteed": True,
                "effects": {"end_mission": "success"},
            },
        ]
    }
)


# ---- schema ------------------------------------------------------------------------------


def test_watch_spec_valid_without_player_flights() -> None:
    spec = MissionSpec.model_validate(watch_data())
    assert spec.player_flights == []
    assert spec.watch is not None and spec.watch.focus == "dustoff" and spec.watch.cues
    o = spec.flights[0].orders[2]
    assert o.do == "land" and o.ground_min == (1, 2) and o.pickup == "kestrel"
    assert spec.flights[0].orders[1].until is not None
    assert spec.flights[0].orders[1].until.event == "beat.fired"
    refs = dict(spec.referenced_areas())
    assert refs["flights[0].orders[0].to"] == "gate_west"


def test_player_flights_required_without_watch() -> None:
    with pytest.raises(ValidationError, match="player_flights"):
        MissionSpec.model_validate(watch_data(watch=None))


def test_watch_focus_must_be_a_flight() -> None:
    with pytest.raises(ValidationError, match=r"watch.focus"):
        MissionSpec.model_validate(watch_data(watch={"focus": "nobody"}))


@pytest.mark.parametrize(
    ("order", "msg"),
    [
        ({"do": "fly"}, "requires 'to'"),
        ({"do": "hold", "at": "hatay", "pickup": "kestrel"}, "only valid for land"),
        ({"do": "escort", "flight": "ghost"}, "unknown flight"),
        ({"do": "land", "at": "lz_ridge", "pickup": "ghost"}, "unknown support/flight"),
        ({"do": "land", "at": "lz_ridge", "ground_min": [3, 1]}, "range"),
        ({"do": "strike", "at": "canal_east", "weapon": "nuke"}, "weapon"),
    ],
)
def test_bad_orders_rejected(order: dict[str, Any], msg: str) -> None:
    data = watch_data()
    data["flights"][0]["orders"] = [order]
    with pytest.raises(ValidationError, match=msg):
        MissionSpec.model_validate(data)


def test_order_accepts_lua_kind_spelling() -> None:
    data = watch_data()
    data["flights"][0]["orders"] = [{"kind": "fly", "to": "hatay"}]
    assert MissionSpec.model_validate(data).flights[0].orders[0].do == "fly"


def test_beat_cue_and_voiced_flag() -> None:
    from dms_core.schemas import VoiceLineSet

    assert BEATS.beats[0].cue == "F2 on Dustoff"
    lines = VoiceLineSet.model_validate(
        {"lines": [{"id": "a", "speaker": "x", "text": "hi", "voiced": False}]}
    )
    assert lines.lines[0].voiced is False


# ---- planner -----------------------------------------------------------------------------


@pytest.fixture(scope="module")
def plan() -> Any:
    return plan_mission(MissionSpec.model_validate(watch_data()), BEATS, seed=7)


def test_planner_flight_groups(plan: Any) -> None:
    groups = {g.source: g for g in plan.groups if g.ai_flight}
    assert set(groups) == {"dustoff", "gunfighter", "viper"}
    assert not any(g.client for g in plan.groups)
    d, a, v = groups["dustoff"], groups["gunfighter"], groups["viper"]
    assert d.name == "Dustoff_dustoff" and d.category == "helicopter"
    assert v.category == "plane" and len(v.units) == 2
    for g in (d, a, v):
        assert not g.late_activation and not g.uncontrolled
        assert g.route[0].action == "Turning Point"  # air start
    assert d.route[0].alt_type == "RADIO" and d.route[0].alt_m == pytest.approx(152.4)
    assert v.route[0].alt_type == "BARO" and v.route[0].alt_m == pytest.approx(4572.0)
    assert v.task == "Ground Attack" and a.task == "Escort" and d.task == "Transport"
    assert v.units[0].payload is not None  # loadout machinery (F-16 strike preset)
    assert a.immortal and not d.immortal
    assert d.frequency_mhz == 40.5 and d.modulation == "FM"


def test_planner_runtime_flights_and_watch(plan: Any) -> None:
    rt = plan.runtime
    assert rt.watch is not None and rt.watch.focus == "Dustoff_dustoff" and rt.watch.cues
    flights = {f.id: f for f in rt.flights}
    d = flights["dustoff"]
    assert d.group == "Dustoff_dustoff" and d.category == "helicopter" and d.coalition == 2
    assert d.start_airbase is None
    fly, hold, land = d.orders[0], d.orders[1], d.orders[2]
    assert (fly.kind, fly.to, fly.alt_type) == ("fly", "gate_west", "RADIO")
    assert fly.alt_m == pytest.approx(91.4) and fly.speed_mps == pytest.approx(56.6)
    assert hold.max_sec == 360 and hold.until is not None and hold.until.beat == "lz_cold"
    kestrel = next(g.name for g in plan.groups if g.source == "kestrel")
    assert land.pickup == kestrel and land.ground_sec == (60, 120)
    esc = flights["gunfighter"].orders[0]
    assert esc.targets == ["Ground Units", "Air Defence"] and esc.radius_m == pytest.approx(2778)
    assert esc.until is not None and esc.until.event == "flight.lifted"
    assert esc.max_sec == 900
    strike = flights["viper"].orders[0]
    assert (strike.kind, strike.group, strike.weapon) == ("strike", "technicals", "guided_bomb")
    assert strike.alt_type == "BARO" and strike.max_sec == 360
    assert flights["viper"].orders[1].kind == "rtb"
    # Lua side: camelCase and round trip
    table = rt.to_lua_table()
    assert table["watch"]["focus"] == "Dustoff_dustoff"
    lua_land = table["flights"][0]["orders"][2]
    assert lua_land["groundSec"] == [60, 120] and lua_land["pickup"] == kestrel
    assert table["flights"][0]["orders"][1]["until"] == {"event": "beat.fired", "beat": "lz_cold"}
    assert RuntimeConfig.from_lua_table(table) == rt


def test_plane_land_at_airbase_area_uses_airfield() -> None:
    data = watch_data()
    data["flights"][2]["orders"] = [{"do": "land", "at": "hatay"}]
    p = plan_mission(MissionSpec.model_validate(data), BEATS, seed=1)
    assert p.runtime is not None and p.runtime.flights is not None
    assert p.runtime.flights[2].orders[0].at == "Hatay"


def test_parking_start_sets_start_airbase() -> None:
    data = watch_data()
    data["flights"][1]["start_type"] = "parking_hot"
    p = plan_mission(MissionSpec.model_validate(data), BEATS, seed=1)
    g = next(g for g in p.groups if g.source == "gunfighter")
    assert g.route[0].action == "From Parking Area Hot" and g.route[0].airbase == "Hatay"
    assert p.runtime is not None and p.runtime.flights is not None
    assert p.runtime.flights[1].start_airbase == "Hatay"


def test_build_watch_miz(plan: Any, tmp_path: Path) -> None:
    write_runtime_config(plan, tmp_path)
    (tmp_path / "dist").mkdir()
    (tmp_path / "dist" / "dms.lua").write_text("-- stub\n", encoding="utf-8")
    out = build_from_plan(plan, tmp_path / "w01.miz", base_dir=tmp_path)
    mission = MizFile.open(out).table("mission")
    found: dict[str, Any] = {}
    for coal in mission["coalition"].values():
        for country in coal.get("country", {}).values():
            for cat in ("helicopter", "plane"):
                for g in country.get(cat, {}).get("group", {}).values():
                    found[g["name"]] = g
    assert {"Dustoff_dustoff", "Gunfighter_gunfighter", "Viper_viper"} <= set(found)
    apache = found["Gunfighter_gunfighter"]
    assert not apache.get("lateActivation") and not apache.get("uncontrolled")
    assert apache["task"] == "Escort"
    tasks = apache["route"]["points"][1]["task"]["params"]["tasks"]
    ids = [t.get("params", {}).get("action", {}).get("id") for t in tasks.values()]
    assert "SetImmortal" in ids
    for u in mission_units(found):
        assert u["skill"] not in ("Client", "Player")


def mission_units(groups: dict[str, Any]) -> list[dict[str, Any]]:
    return [u for g in groups.values() for u in g["units"].values()]


# ---- test mode ---------------------------------------------------------------------------


def test_testmode_watch_uses_focus(plan: Any) -> None:
    spec = MissionSpec.model_validate(watch_data())
    tb = make_test_plan(plan, spec, BEATS)
    assert tb.proxy == "Dustoff_dustoff"
    assert not any(g.name.startswith("Proxy ") for g in tb.plan.groups)
    assert {g.name for g in tb.plan.groups} == {g.name for g in plan.groups}
    assert tb.minutes == 40
    assert 'playerProxy = "Dustoff_dustoff"' in tb.lua
    assert "loiter" not in tb.lua
    assert 'kind = "flight_orders"' in tb.lua
