# ruff: noqa: E501
"""Schema tests, using a Dustoff Corridor-like AH-64 convoy escort in Syria as the running example."""

from __future__ import annotations

import datetime as dt
import json
from pathlib import Path
from typing import Any

import pytest
from dms_core.schemas import (
    DOCUMENT_MODELS,
    Beat,
    BeatSheet,
    BuildPlan,
    CampaignArc,
    MissionOutcome,
    MissionSpec,
    Qualities,
    RuntimeConfig,
    StoryBible,
    VoiceLineSet,
    export_json_schemas,
    parse_dcs_log,
    summarize_outcomes,
    validate_mission_bundle,
)
from dms_core.schemas.runtime import Budgets, _fallback_dumps, snake_to_camel
from pydantic import BaseModel, ValidationError

# ---------------------------------------------------------------------------
# Running example: "Dustoff Corridor"
# ---------------------------------------------------------------------------


def make_bible() -> StoryBible:
    return StoryBible.model_validate(
        {
            "title": "Dustoff Corridor",
            "mode": "fictional",
            "setting": {
                "era": 2016,
                "theater": "Syria",
                "region": "Idlib - Jisr al-Shughur road",
                "premise_summary": "An Apache section keeps a medical convoy corridor open "
                "through contested valley towns.",
            },
            "tone": {"style": "professional-terse", "themes": ["attrition", "trust"]},
            "player_role": "AH-64D crew, callsign Gunfighter",
            "factions": [
                {
                    "id": "blue_task_force",
                    "name": "Task Force Lion",
                    "dcs": {"country": "USA", "coalition": "blue", "units": ["M1126 Stryker ICV"]},
                },
                {
                    "id": "red_militia",
                    "name": "Free Valley Front",
                    "doctrine": "Road ambushes, technicals, ZU-23s, the odd SA-8.",
                    "dcs": {
                        "country": "Insurgents",
                        "coalition": "red",
                        "units": ["ZU-23 Emplacement", "BTR-80", "Osa 9A33 ln"],
                        "tech_veneer": "Ex-regime stocks.",
                    },
                },
            ],
            "characters": [
                {
                    "id": "ops_mustang",
                    "name": "Maj. Dana Reyes",
                    "callsign": "Mustang",
                    "role": "TOC battle captain",
                    "faction": "blue_task_force",
                    "voice": {
                        "design_prompt": "Calm American female, 40s, clipped radio delivery.",
                        "age": 42,
                        "cadence": "brisk",
                        "brevity": "terse",
                        "radio_fx": "uhf_clean",
                    },
                },
                {
                    "id": "convoy_lead",
                    "name": "SSG Ortiz",
                    "callsign": "Ripper 2-1",
                    "role": "Convoy commander",
                    "faction": "blue_task_force",
                    "voice": {
                        "design_prompt": "Hoarse male, 30s, shouting over engine noise.",
                        "radio_fx": "vhf_noisy",
                        "eleven_voice_id": "abc123",
                    },
                },
            ],
            "timeline": [{"date": "2016-04-02", "event": "Corridor opens.", "fictional": True}],
            "sources": [{"claim": "AH-64D used for convoy overwatch.", "confidence": "high"}],
            "canon_rules": ["Mustang never swears on the net."],
        }
    )


def make_arc() -> CampaignArc:
    return CampaignArc.model_validate(
        {
            "title": "Dustoff Corridor",
            "logline": "Keep the corridor open long enough to matter.",
            "qualities": [{"id": "trust", "description": "Convoy crews' faith in air cover."}],
            "acts": [
                {
                    "id": "act1",
                    "title": "Opening the Road",
                    "summary": "First convoys.",
                    "missions": [
                        {
                            "id": "m01-dustoff",
                            "title": "Dustoff",
                            "mission_type": "CONVOY_ESCORT",
                            "dramatic_question": "Can two Apaches keep a convoy alive?",
                            "synopsis": "Escort Ripper convoy from FOB Lion to the hospital.",
                            "player_aircraft": "AH-64D_BLK_II",
                            "characters": ["ops_mustang", "convoy_lead"],
                            "quality_effects": {"trust": "+1 if no vehicle lost"},
                            "branches": [
                                {
                                    "when": {
                                        "qualities": [{"quality": "trust", "op": "<", "value": 0}]
                                    },
                                    "goto": "m02b-recovery",
                                }
                            ],
                        },
                        {
                            "id": "m02b-recovery",
                            "title": "Recovery",
                            "mission_type": "CSAR",
                            "dramatic_question": "Can we bring them home?",
                            "synopsis": "Recover a downed crew.",
                            "optional": True,
                        },
                    ],
                }
            ],
        }
    )


def make_spec() -> MissionSpec:
    return MissionSpec.model_validate(
        {
            "id": "m01-dustoff",
            "title": "Dustoff",
            "campaign": "dustoff-corridor",
            "theater": "Syria",
            "era": 2016,
            "date": "2016-04-03",
            "start_time": "05:40",
            "weather_preset": "scattered",
            "mission_type": "CONVOY_ESCORT",
            "blue_countries": ["USA"],
            "red_countries": ["Insurgents"],
            "cast": ["ops_mustang", "convoy_lead"],
            "areas": [
                {"id": "farp_lion", "where": {"kind": "near_airbase", "airbase": "Hatay"}},
                {
                    "id": "fob_lion",
                    "where": {"kind": "near_named_place", "place": "Jisr al-Shughur"},
                    "terrain": "road",
                },
                {
                    "id": "hospital",
                    "where": {"kind": "latlon", "lat": 35.93, "lon": 36.63, "radius_nm": 1},
                },
                {
                    "id": "ridge",
                    "where": {
                        "kind": "zone",
                        "points": [
                            {"lat": 35.85, "lon": 36.4},
                            {"lat": 35.9, "lon": 36.45},
                            {"lat": 35.86, "lon": 36.5},
                        ],
                    },
                    "terrain": "high_ground",
                },
            ],
            "player_flights": [
                {
                    "callsign": "Gunfighter",
                    "aircraft": "AH-64D_BLK_II",
                    "count": 2,
                    "start_area": "farp_lion",
                    "start_type": "parking_hot",
                    "loadout": "anti-armor: 8 Hellfire + 2 rocket pods",
                }
            ],
            "objectives": [
                {
                    "id": "convoy_arrives",
                    "kind": "escort",
                    "description": "Get Ripper convoy to the hospital.",
                    "area": "hospital",
                    "target": "convoy_main",
                    "success_flag": "convoy_arrived",
                    "failure_flag": "convoy_lost",
                }
            ],
            "threats": [
                {"id": "ridge_aaa", "role": "aaa", "area": "ridge", "faction": "red_militia"}
            ],
            "support": [
                {
                    "id": "convoy_main",
                    "role": "convoy",
                    "callsign": "Ripper 2-1",
                    "route": ["fob_lion", "hospital"],
                    "composition": "4x M1126 Stryker, 2x HEMTT",
                    "speaker": "convoy_lead",
                }
            ],
            "dynamic": {
                "pools": [
                    {
                        "id": "aaa",
                        "roles": ["aaa", "sam_short"],
                        "areas": ["ridge"],
                        "pick": [2, 4],
                    },
                    {"id": "btr", "roles": ["ifv"], "areas": ["fob_lion"]},
                ],
                "encounters": [
                    {
                        "id": "popup_sam",
                        "kind": "ambush_sam",
                        "pool": "aaa",
                        "trigger": {"type": "proximity", "area": "ridge", "radius_nm": 10},
                        "chance": 60,
                        "telegraph_beat": "sam_spike",
                    },
                    {
                        "id": "qrf",
                        "kind": "waves",
                        "pool": "btr",
                        "trigger": {"type": "beat", "beat": "convoy_hit"},
                        "waves": 3,
                        "gap_min": [2, 4],
                        "hunt": True,
                    },
                ],
                "director": {"intensity": "moderate"},
            },
        }
    )


def make_beats() -> BeatSheet:
    return BeatSheet.model_validate(
        [
            {
                "id": "sam_spike",
                "when": {"event": "encounter.spawned", "encounter": "popup_sam"},
                "priority": 90,
                "speaker": "ops_mustang",
                "lines": ["sam_spike_v1", "sam_spike_v2"],
                "text": "Gunfighter, Mustang: SA-8 emitter near the ridge.",
                "mark": {"type": "circle", "at": "zone:ridge", "radius_m": 3000},
            },
            {
                "id": "convoy_hit",
                "when": {"event": "unit.hit", "group_prefix": "CONVOY"},
                "requires": {"flags_not": ["convoy_arrived"]},
                "priority": 80,
                "speaker": "convoy_lead",
                "lines": ["convoy_hit_v1"],
                "effects": {"set_flag": "convoy_contact", "start_encounter": "qrf"},
            },
            {
                "id": "convoy_home",
                "when": {"event": "zone.entered", "zone": "hospital"},
                "speaker": "ops_mustang",
                "lines": ["convoy_home_v1"],
                "effects": {
                    "set_flag": "convoy_arrived",
                    "outcome": {"convoy_arrived": True},
                    "quality_deltas": {"trust": 1},
                    "end_mission": "success",
                },
            },
        ]
    )


def make_lines() -> VoiceLineSet:
    return VoiceLineSet.model_validate(
        {
            "mission_id": "m01-dustoff",
            "lines": [
                {"id": "sam_spike_v1", "speaker": "ops_mustang", "text": "Gunfighter, SA-8 up."},
                {"id": "sam_spike_v2", "speaker": "ops_mustang", "text": "Spike, ridge, SA-8."},
                {
                    "id": "convoy_hit_v1",
                    "speaker": "convoy_lead",
                    "text": "[shouts] Contact left!",
                    "radio_fx": "vhf_noisy",
                },
                {"id": "convoy_home_v1", "speaker": "ops_mustang", "text": "Ripper is in."},
            ],
        }
    )


def make_runtime() -> RuntimeConfig:
    return RuntimeConfig.model_validate(
        {
            "seed": 12345,
            "mission_id": "m01-dustoff",
            "templates": {
                "sa8": {
                    "country": "RUSSIA",
                    "category": "ground",
                    "skill": "High",
                    "units": [{"type": "Osa 9A33 ln"}],
                },
                "zsu": {
                    "country": "Insurgents",
                    "category": "ground",
                    "units": [{"type": "ZSU-23-4 Shilka"}],
                },
            },
            "zones": {
                "ridge": {
                    "kind": "polygon",
                    "points": [{"x": 0, "y": 0}, {"x": 100, "y": 0}, {"x": 0, "y": 100}],
                },
                "town": {"kind": "circle", "x": 10.5, "y": -20, "radius": 1500},
            },
            "pools": {
                "aaa": {
                    "members": [{"tpl": "zsu", "w": 3}, {"tpl": "sa8", "w": 1}],
                    "pick": [2, 4],
                    "zones": ["ridge"],
                }
            },
            "encounters": [
                {
                    "id": "popup_sam",
                    "kind": "ambush_sam",
                    "pool": "aaa",
                    "trigger": {"type": "proximity", "zone": "ridge", "radius_m": 20000},
                    "chance": 60,
                    "telegraph": "beat:sam_spike",
                }
            ],
            "beats": [
                {
                    "id": "tgt_down",
                    "when": {"event": "group.dead", "group": "HVT"},
                    "priority": 80,
                    "speaker": "ops_mustang",
                    "lines": ["tgt_down_v1"],
                    "text": "Splash HVT.",
                    "effects": {
                        "set_flag": "tgt_down",
                        "outcome": {"hvt_killed": True},
                        "start_encounter": "egress_cap",
                    },
                }
            ],
            "voice": {
                "tgt_down_v1": {
                    "file": "tgt_down_v1.ogg",
                    "text": "Splash HVT",
                    "dur_sec": 3,
                    "speaker": "ops_mustang",
                }
            },
        }
    )


def make_plan() -> BuildPlan:
    return BuildPlan.model_validate(
        {
            "mission_id": "m01-dustoff",
            "seed": 12345,
            "theater": "Syria",
            "date": "2016-04-03",
            "start_time_sec": 5 * 3600 + 40 * 60,
            "blue_countries": ["USA"],
            "red_countries": ["Insurgents"],
            "groups": [
                {
                    "name": "Gunfighter",
                    "category": "helicopter",
                    "coalition": "blue",
                    "country": "USA",
                    "task": "CAS",
                    "client": True,
                    "frequency_mhz": 251.0,
                    "units": [
                        {
                            "name": "Gunfighter-1",
                            "type": "AH-64D_BLK_II",
                            "x": 35000.0,
                            "y": 120000.0,
                            "skill": "Client",
                            "payload": {
                                "pylons": [
                                    {"num": 1, "clsid": "{88D18A5E-99C8-4B04-B40B-1C02F2018B6E}"}
                                ],
                                "fuel_kg": 1100,
                            },
                        }
                    ],
                    "route": [
                        {"x": 35000.0, "y": 120000.0, "action": "From Parking Area Hot"},
                        {"x": 36000.0, "y": 125000.0, "alt_m": 60, "alt_type": "RADIO"},
                    ],
                    "source": "Gunfighter",
                },
                {
                    "name": "CONVOY_Ripper",
                    "category": "vehicle",
                    "coalition": "blue",
                    "country": "USA",
                    "units": [
                        {"name": "CONVOY_Ripper-1", "type": "M1126 Stryker ICV", "x": 1, "y": 2}
                    ],
                    "route": [
                        {"x": 1, "y": 2, "action": "On Road", "speed_kmh": 40},
                        {"x": 900, "y": 2000, "action": "On Road", "speed_kmh": 40},
                    ],
                },
            ],
            "zones": [
                {"name": "hospital", "kind": "circle", "x": 900, "y": 2000, "radius_m": 1852},
                {"name": "ridge", "kind": "polygon", "points": [[0, 0], [100, 0], [0, 100]]},
            ],
            "triggers": [
                {
                    "name": "load dms",
                    "kind": "mission_start",
                    "actions": [{"type": "DoScriptFile", "params": {"file": "dms.lua"}}],
                }
            ],
            "resources": [
                {"path": "l10n/DEFAULT/dms.lua", "source": "dist/dms.lua", "kind": "script"}
            ],
            "briefing": {"title": "Dustoff"},
            "runtime": make_runtime().model_dump(),
        }
    )


EXAMPLES: dict[str, Any] = {
    "bible": make_bible,
    "arc": make_arc,
    "qualities": lambda: Qualities(values={"trust": 1}, flags={"corridor_open": True}),
    "spec": make_spec,
    "beats": make_beats,
    "lines": make_lines,
    "runtime": make_runtime,
    "plan": make_plan,
    "outcome": lambda: MissionOutcome(mission_id="m01-dustoff", time=1800, kills={"ground": 6}),
}

# ---------------------------------------------------------------------------
# Round trips
# ---------------------------------------------------------------------------


@pytest.mark.parametrize("name", list(EXAMPLES))
def test_round_trip(name: str) -> None:
    model: BaseModel = EXAMPLES[name]()
    cls = type(model)
    assert cls.model_validate(model.model_dump()) == model
    assert cls.model_validate_json(model.model_dump_json()) == model
    # JSON-mode dump must be YAML/JSON friendly and still validate
    assert cls.model_validate(json.loads(json.dumps(model.model_dump(mode="json")))) == model


def test_extra_keys_forbidden() -> None:
    data = make_spec().model_dump()
    data["theatre"] = "Syria"
    with pytest.raises(ValidationError, match="theatre"):
        MissionSpec.model_validate(data)


def test_closed_vocabularies() -> None:
    data = make_spec().model_dump()
    data["theater"] = "Iraq"
    with pytest.raises(ValidationError):
        MissionSpec.model_validate(data)
    data = make_spec().model_dump()
    data["mission_type"] = "BOMBING"
    with pytest.raises(ValidationError):
        MissionSpec.model_validate(data)


def test_spec_details() -> None:
    spec = make_spec()
    assert spec.date == dt.date(2016, 4, 3)
    assert spec.areas[3].where.kind == "zone"
    assert ("support[0].route[1]", "hospital") in spec.referenced_areas()
    with pytest.raises(ValidationError, match="requires 'beat'"):
        MissionSpec.model_validate(
            {
                **make_spec().model_dump(),
                "dynamic": {
                    "encounters": [
                        {"id": "x", "kind": "waves", "pool": "btr", "trigger": {"type": "beat"}}
                    ]
                },
            }
        )


def test_bible_and_arc_cross_refs() -> None:
    data = make_bible().model_dump()
    data["characters"][0]["faction"] = "nope"
    with pytest.raises(ValidationError, match="unknown faction"):
        StoryBible.model_validate(data)
    arc = make_arc().model_dump()
    arc["acts"][0]["missions"][0]["branches"][0]["goto"] = "m99"
    with pytest.raises(ValidationError, match="unknown mission"):
        CampaignArc.model_validate(arc)
    assert make_bible().character("ops_mustang") is not None


def test_beat_rules() -> None:
    with pytest.raises(ValidationError, match="requires one of"):
        Beat.model_validate({"id": "b", "when": {"event": "group.dead"}})
    with pytest.raises(ValidationError, match="no speaker"):
        Beat.model_validate({"id": "b", "when": {"event": "mission.start"}, "lines": ["x"]})
    with pytest.raises(ValidationError, match="duplicate beat"):
        BeatSheet.model_validate([make_beats().beats[0].model_dump()] * 2)
    assert BeatSheet.model_validate({"beats": []}).beats == []


def test_beat_landed_zone_and_place_filters() -> None:
    b = Beat.model_validate(
        {"id": "b", "when": {"event": "unit.landed", "zone": "fob_pad", "airbase": "FARP London"}}
    )
    assert b.when.zone == "fob_pad" and b.when.place == "FARP London"
    assert (
        Beat.model_validate(
            {"id": "t", "when": {"event": "unit.takeoff", "place": "Kutaisi"}}
        ).when.place
        == "Kutaisi"
    )
    with pytest.raises(ValidationError, match="'place' filters only"):
        Beat.model_validate({"id": "b", "when": {"event": "unit.hit", "place": "Kutaisi"}})
    rt = RuntimeConfig.model_validate(
        {**make_runtime().model_dump(), "beats": [b.model_dump()]}
    ).to_lua_table()
    assert rt["beats"][0]["when"]["place"] == "FARP London"
    assert rt["beats"][0]["when"]["zone"] == "fob_pad"


def test_plan_unique_names() -> None:
    data = make_plan().model_dump()
    data["groups"][1]["name"] = "Gunfighter"
    with pytest.raises(ValidationError, match="duplicate group"):
        BuildPlan.model_validate(data)


# ---------------------------------------------------------------------------
# RuntimeConfig -> Lua
# ---------------------------------------------------------------------------


def test_snake_to_camel() -> None:
    assert snake_to_camel("max_active_ground") == "maxActiveGround"
    assert snake_to_camel("seed") == "seed"


def test_runtime_lua_table_camel_case() -> None:
    t = make_runtime().to_lua_table()
    assert t["missionId"] == "m01-dustoff"
    assert t["budgets"] == {"maxActiveGround": 150, "maxActiveAir": 16, "spawnsPerMin": 3}
    assert t["director"]["relaxSec"] == [40, 90]
    assert t["director"]["decayPerSec"] == 1.5
    assert t["director"]["adapt"] == {"min": -1, "max": 1}
    assert t["intel"] == {
        "fogOfWar": True,
        "revealRadiusM": 5000,
        "markRefreshSec": 15,
        "staleSec": 120,
    }
    assert t["players"] == {"coalition": 2}
    # user map keys preserved, not camelCased
    assert "tgt_down_v1" in t["voice"]
    assert t["voice"]["tgt_down_v1"]["durSec"] == 3
    assert t["pools"]["aaa"]["members"][0] == {"tpl": "zsu", "w": 3}
    enc = t["encounters"][0]
    assert enc["trigger"] == {"type": "proximity", "zone": "ridge", "radiusM": 20000}
    assert "waves" not in enc and "gapSec" not in enc  # None dropped
    beat = t["beats"][0]
    assert beat["cooldownSec"] == 0
    assert "mark" not in beat
    assert beat["effects"]["setFlag"] == "tgt_down"
    assert beat["effects"]["startEncounter"] == "egress_cap"
    assert beat["effects"]["outcome"] == {"hvt_killed": True}
    assert beat["when"] == {"event": "group.dead", "group": "HVT"}


def _norm(v: Any) -> Any:
    """Normalise for comparing a Lua round trip: dicts with 1..n int keys -> lists, floats->ints."""
    if isinstance(v, dict):
        if v and all(isinstance(k, int) for k in v) and sorted(v) == list(range(1, len(v) + 1)):
            return [_norm(v[i]) for i in range(1, len(v) + 1)]
        return {k: _norm(x) for k, x in v.items() if not (isinstance(x, (dict, list)) and not x)}
    if isinstance(v, list):
        return [_norm(x) for x in v]
    if isinstance(v, float) and v.is_integer():
        return int(v)
    return v


def test_runtime_lua_source_round_trip() -> None:
    cfg = make_runtime()
    src = cfg.to_lua_source()
    assert src.startswith("DMS_CONFIG = ")
    luaio = pytest.importorskip("dms_core.luaio")
    back = luaio.loads(src, "DMS_CONFIG")
    assert _norm(back) == _norm(cfg.to_lua_table())


def test_fallback_dumps_is_valid_lua() -> None:
    lupa = pytest.importorskip("lupa")
    table = make_runtime().to_lua_table()
    src = "DMS_CONFIG = " + _fallback_dumps(table)
    rt = lupa.LuaRuntime()
    rt.execute(src)
    g = rt.globals()
    assert g.DMS_CONFIG.missionId == "m01-dustoff"
    assert g.DMS_CONFIG.budgets.maxActiveGround == 150
    assert g.DMS_CONFIG.pools.aaa.members[1].tpl == "zsu"
    assert _fallback_dumps({"end": 1, "a b": 'x\n"y"'}) == '{["end"] = 1, ["a b"] = "x\\n\\"y\\""}'


# ---------------------------------------------------------------------------
# Cross validation
# ---------------------------------------------------------------------------


def test_bundle_clean() -> None:
    issues = validate_mission_bundle(make_spec(), make_beats(), make_lines(), make_bible())
    assert [i for i in issues if i.severity == "error"] == []


def test_bundle_suggestions() -> None:
    beats = make_beats().model_dump()
    beats["beats"][0]["lines"][1] = "sam_spike_v3"
    beats["beats"][0]["speaker"] = "ops_mustnag"
    beats["beats"][1]["effects"]["start_encounter"] = "qfr"
    beats["beats"][2]["when"]["zone"] = "hospitl"
    spec = make_spec().model_dump()
    spec["dynamic"]["encounters"][0]["pool"] = "aa"
    spec["threats"][0]["area"] = "rigde"
    lines = make_lines().model_dump()
    lines["lines"][2]["speaker"] = "convoy_led"

    issues = validate_mission_bundle(
        MissionSpec.model_validate(spec),
        BeatSheet.model_validate(beats).beats,
        VoiceLineSet.model_validate(lines),
    )
    by_path = {i.path: i for i in issues if i.severity == "error"}

    def sugg(path: str) -> list[str]:
        assert path in by_path, f"{path} not in {sorted(by_path)}"
        return by_path[path].suggestions

    assert set(sugg("beats.yaml:beats[0].lines[1]")[:2]) == {"sam_spike_v1", "sam_spike_v2"}
    assert sugg("beats.yaml:beats[0].speaker")[0] == "ops_mustang"
    assert sugg("beats.yaml:beats[1].effects.start_encounter") == ["qrf"]
    assert sugg("beats.yaml:beats[2].when.zone") == ["hospital"]
    assert sugg("mission-spec.yaml:dynamic.encounters[0].pool")[0] == "aaa"
    assert sugg("mission-spec.yaml:threats[0].area") == ["ridge"]
    assert sugg("lines.yaml:lines[2].speaker") == ["convoy_lead"]
    # unused line warning
    assert any(i.severity == "warning" and "sam_spike_v2" in i.problem for i in issues)


def test_bundle_speaker_mismatch_warning() -> None:
    lines = make_lines().model_dump()
    lines["lines"][3]["speaker"] = "convoy_lead"
    issues = validate_mission_bundle(make_spec(), make_beats(), VoiceLineSet.model_validate(lines))
    warn = [i for i in issues if i.severity == "warning"]
    assert any(i.path == "beats.yaml:beats[2].lines[0]" for i in warn)


# ---------------------------------------------------------------------------
# Outcome parsing
# ---------------------------------------------------------------------------

DCS_LOG = """\
2026-10-27 18:01:02.123 INFO    SCRIPTING (Main): [DMS][init] DMS v0.3 started
2026-10-27 18:20:11.500 INFO    SCRIPTING (Main): [DMS.OUTCOME] {"missionId":"m01-dustoff","t":1150.5,"kind":"beat","beat":"convoy_hit","outcome":{"convoy_contact":true},"flags":[]}
2026-10-27 18:22:00.000 INFO    SCRIPTING (Main): [DMS.OUTCOME] {not json}
2026-10-27 18:25:00.000 INFO    SCRIPTING (Main): [DMS.OUTCOME] [1,2,3]
2026-10-27 18:40:30.000 INFO    SCRIPTING (Main): [DMS.OUTCOME] {"missionId":"m01-dustoff","time":2400,"kind":"end","result":"success","outcomes":{"convoy_arrived":true},"kills":{"ground":7},"losses":{"vehicle":1},"players":["Mook"],"weirdKey":5}
"""


def test_parse_dcs_log() -> None:
    outs = parse_dcs_log(DCS_LOG)
    assert len(outs) == 2
    first, last = outs
    assert first.mission_id == "m01-dustoff"
    assert first.time == 1150.5
    assert first.outcomes == {"convoy_contact": True}
    assert first.flags == {}
    assert first.log_timestamp == "2026-10-27 18:20:11.500"
    assert last.result == "success"
    assert last.kills == {"ground": 7}
    assert last.losses == {"vehicle": 1}
    assert last.extra == {"weirdKey": 5}
    merged = summarize_outcomes(outs)["m01-dustoff"]
    assert merged.outcomes == {"convoy_contact": True, "convoy_arrived": True}
    assert merged.time == 2400
    assert merged.kind == "end"
    assert parse_dcs_log("nothing here") == []


# ---------------------------------------------------------------------------
# JSON Schema export
# ---------------------------------------------------------------------------


def test_export_json_schemas(tmp_path: Path) -> None:
    paths = export_json_schemas(tmp_path / "schemas")
    assert {p.name for p in paths} == {f"{s}.schema.json" for s in DOCUMENT_MODELS}
    spec_schema = json.loads((tmp_path / "schemas" / "mission-spec.schema.json").read_text("utf-8"))
    assert spec_schema["additionalProperties"] is False
    assert "Syria" in json.dumps(spec_schema)
    assert spec_schema["properties"]["theater"]["description"]


def test_every_field_has_description() -> None:
    missing: list[str] = []
    seen: set[type[BaseModel]] = set()

    def walk(cls: type[BaseModel]) -> None:
        if cls in seen:
            return
        seen.add(cls)
        for name, f in cls.model_fields.items():
            if not f.description:
                missing.append(f"{cls.__name__}.{name}")
        for sub in _submodels(cls):
            walk(sub)

    for m in DOCUMENT_MODELS.values():
        walk(m)
    assert missing == [], missing


def _submodels(cls: type[BaseModel]) -> list[type[BaseModel]]:
    import typing

    out: list[type[BaseModel]] = []

    def visit(tp: Any) -> None:
        if isinstance(tp, type) and issubclass(tp, BaseModel):
            out.append(tp)
        for a in typing.get_args(tp):
            visit(a)

    for f in cls.model_fields.values():
        visit(f.annotation)
    return out


@pytest.mark.parametrize("bad", [0, 0.5, -1])
def test_budgets_spawns_per_min_below_one_rejected(bad: float) -> None:
    # the Lua director floors the spawn budget at 1/min; the schema must not promise less
    with pytest.raises(ValidationError):
        Budgets(spawns_per_min=bad)
    assert Budgets(spawns_per_min=1).spawns_per_min == 1
