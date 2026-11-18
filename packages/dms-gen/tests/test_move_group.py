"""move_group beat effect and Support.immortal (CONTRACTS "Ground moves on cue ... (v0.9.1)")."""

from __future__ import annotations

from pathlib import Path
from typing import Any

import pytest
from dms_core.miz import MizFile
from dms_core.schemas import BeatSheet, MissionSpec
from dms_core.schemas.beats import BeatEffects, BeatMoveGroup
from dms_core.schemas.validation import validate_mission_bundle
from dms_core.schemas.voice import VoiceLineSet
from dms_gen.builder import build_from_plan
from dms_gen.planner import plan_mission, write_runtime_config
from dms_gen.planner.moves import is_infantry_type


def spec_data(**over: Any) -> dict[str, Any]:
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
            {"id": "rescue", "kind": "rescue", "description": "Get out.", "area": "lz_ridge"}
        ],
        "threats": [{"id": "technicals", "role": "technicals", "area": "canal_east"}],
        "support": [
            {
                "id": "kestrel",
                "role": "friendly_ground",
                "area": "canal_east",
                "callsign": "Kestrel",
                "immortal": True,
            },
            {
                "id": "convoy",
                "role": "convoy",
                "area": "canal_east",
                "composition": "2x M 818",
            },
        ],
        "watch": {"focus": "dustoff"},
        "flights": [
            {
                "id": "dustoff",
                "callsign": "Dustoff 3-1",
                "aircraft": "UH-60A",
                "start_area": "hatay",
                "orders": [{"do": "land", "at": "lz_ridge", "pickup": "kestrel"}],
            }
        ],
    }
    data.update(over)
    return data


def beats(*moves: dict[str, Any]) -> BeatSheet:
    return BeatSheet.model_validate(
        {
            "beats": [
                {"id": "start", "when": {"event": "mission.start"}, "guaranteed": True},
                *(
                    {"id": f"move{i}", "when": {"after_sec": 30 + i}, "effects": {"move_group": m}}
                    for i, m in enumerate(moves)
                ),
                {
                    "id": "arrived",
                    "when": {"event": "ground.arrived", "group": "kestrel"},
                    "effects": {"end_mission": "success"},
                },
            ]
        }
    )


def runtime_moves(sheet: BeatSheet) -> list[dict[str, Any]]:
    plan = plan_mission(MissionSpec.model_validate(spec_data()), sheet, seed=1)
    assert plan.runtime is not None
    table = plan.runtime.to_lua_table()
    return [b["effects"]["moveGroup"] for b in table["beats"] if "moveGroup" in b["effects"]]


# ---- schema ------------------------------------------------------------------------------


def test_move_group_schema_and_camel() -> None:
    e = BeatEffects.model_validate(
        {"moveGroup": {"group": "kestrel", "to": "lz_ridge", "speedKts": 6, "offRoad": True}}
    )
    assert e.move_group == BeatMoveGroup(group="kestrel", to="lz_ridge", speed_kts=6, off_road=True)
    with pytest.raises(ValueError):
        BeatMoveGroup.model_validate({"group": "kestrel", "to": "lz", "speed": 3})


# ---- planner -----------------------------------------------------------------------------


def test_compile_infantry_support_defaults_off_road() -> None:
    (mv,) = runtime_moves(beats({"group": "kestrel", "to": "lz_ridge"}))
    assert mv == {"group": "kestrel_1", "to": "lz_ridge", "speedMps": 4.0, "action": "Off Road"}


def test_compile_vehicle_support_on_road_and_speed() -> None:
    (mv,) = runtime_moves(beats({"group": "convoy", "to": "lz_ridge", "speed_kts": 20}))
    assert mv == {"group": "convoy_1", "to": "lz_ridge", "speedMps": 10.3, "action": "On Road"}


def test_compile_explicit_off_road_and_prefix_passthrough() -> None:
    moves = runtime_moves(
        beats(
            {"group": "convoy", "to": "lz_ridge", "off_road": True},
            {"group": "kestrel", "to": "lz_ridge", "off_road": False},
            {"group": "technicals", "to": "lz_ridge"},
        )
    )
    assert [m["action"] for m in moves] == ["Off Road", "On Road", "On Road"]
    assert moves[2]["group"] == "technicals"  # threat id: runtime prefix


def test_infantry_types() -> None:
    assert is_infantry_type("Soldier M4") and is_infantry_type("Infantry AK ver3")
    assert not is_infantry_type("M 818") and not is_infantry_type("M1126 Stryker ICV")


# ---- validation --------------------------------------------------------------------------


def test_validate_move_group_refs() -> None:
    spec = MissionSpec.model_validate(spec_data())
    lines = VoiceLineSet(lines=[])
    ok = validate_mission_bundle(spec, beats({"group": "kestrel", "to": "lz_ridge"}), lines)
    assert not [i for i in ok if "move_group" in i.path]
    bad = validate_mission_bundle(spec, beats({"group": "kestrl", "to": "lz_nowhere"}), lines)
    found = {i.path.rsplit(".", 1)[-1]: i for i in bad if "move_group" in i.path}
    assert found["to"].severity == "error"
    assert found["group"].severity == "warning" and "kestrel" in found["group"].suggestions


# ---- immortal support --------------------------------------------------------------------


def test_immortal_support_builds_set_immortal(tmp_path: Path) -> None:
    plan = plan_mission(MissionSpec.model_validate(spec_data()), beats(), seed=1)
    groups = {g.source: g for g in plan.groups}
    assert groups["kestrel"].immortal and not groups["convoy"].immortal
    write_runtime_config(plan, tmp_path)
    (tmp_path / "dist").mkdir()
    (tmp_path / "dist" / "dms.lua").write_text("-- stub\n", encoding="utf-8")
    out = build_from_plan(plan, tmp_path / "w01.miz", base_dir=tmp_path)
    mission = MizFile.open(out).table("mission")
    found: dict[str, Any] = {}
    for coal in mission["coalition"].values():
        for country in coal.get("country", {}).values():
            for g in country.get("vehicle", {}).get("group", {}).values():
                found[g["name"]] = g

    def start_actions(name: str) -> list[Any]:
        tasks = found[name]["route"]["points"][1]["task"]["params"].get("tasks", {})
        return [t.get("params", {}).get("action", {}).get("id") for t in tasks.values()]

    assert "SetImmortal" in start_actions("kestrel_1")
    assert "SetImmortal" not in start_actions("convoy_1")
