"""Schema additions from the Lua/Python integration pass (docs/CONTRACTS.md).

Covers new optional fields, Lua-alias normalisers and validators; everything must stay
backward compatible with the original canonical shapes.
"""

from __future__ import annotations

from typing import Any

import pytest
from dms_core.schemas import (
    Beat,
    BeatEffects,
    BeatMark,
    BeatTrigger,
    Encounter,
    MissionOutcome,
    PoolIntent,
    Qualities,
    Requires,
    RuntimeConfig,
    VoiceLine,
    parse_dcs_log,
)
from pydantic import ValidationError

# ---------------------------------------------------------------------------
# Requires aliases
# ---------------------------------------------------------------------------


def test_requires_canonical_unchanged() -> None:
    r = Requires.model_validate(
        {"flags": ["a"], "flags_not": ["b"], "qualities": [{"quality": "trust", "value": 2}]}
    )
    assert r.flags == ["a"] and r.flags_not == ["b"]
    assert r.qualities[0].op == ">="


def test_requires_flag_map_and_aliases() -> None:
    r = Requires.model_validate(
        {
            "flags": {"a": True, "b": False},
            "flags_set": ["c"],
            "notFlags": "d",
            "flags_not_set": ["e"],
        }
    )
    assert r.flags == ["a", "c"]
    assert r.flags_not == ["b", "d", "e"]


def test_requires_flag_map_rejects_numbers() -> None:
    with pytest.raises(ValidationError):
        Requires.model_validate({"flags": {"a": 2}})


@pytest.mark.parametrize(
    ("spec", "expected"),
    [
        (2, [(">=", 2)]),
        (">=2", [(">=", 2)]),
        ("<0", [("<", 0)]),
        ("=1", [("==", 1)]),
        ("~=3", [("!=", 3)]),
        ({"min": 1, "max": 3}, [(">=", 1), ("<=", 3)]),
        ({"op": "<", "value": 0}, [("<", 0)]),
    ],
)
def test_requires_quality_map(spec: Any, expected: list[tuple[str, float]]) -> None:
    r = Requires.model_validate({"qualities": {"trust": spec}})
    assert [(q.quality, q.op, q.value) for q in r.qualities] == [
        ("trust", op, v) for op, v in expected
    ]


def test_requires_quality_map_bad() -> None:
    with pytest.raises(ValidationError):
        Requires.model_validate({"qualities": {"trust": "lots"}})


# ---------------------------------------------------------------------------
# BeatTrigger
# ---------------------------------------------------------------------------


@pytest.mark.parametrize(
    ("raw", "event", "attr", "value"),
    [
        ({"afterSec": 30}, "timer", "after_sec", 30),
        ({"timer": 5}, "timer", "after_sec", 5),
        ({"flag": "x", "value": ">=2"}, "flag", "value", ">=2"),
        ({"zone": "box"}, "zone.entered", "zone", "box"),
        ({"director": "RELAX", "flight": "Dusty"}, "director.state", "state", "RELAX"),
        ({"directorState": "PEAK"}, "director.state", "state", "PEAK"),
        ({"beat": "b1", "delaySec": 4}, "beat.fired", "delay_sec", 4),
    ],
)
def test_trigger_shorthand(raw: dict[str, Any], event: str, attr: str, value: Any) -> None:
    t = BeatTrigger.model_validate(raw)
    assert t.event == event
    assert getattr(t, attr) == value


def test_trigger_camel_filters_and_neutral_coalition() -> None:
    t = BeatTrigger.model_validate(
        {"event": "unit.dead", "groupPrefix": "civilians", "playersOnly": False, "coalition": 0}
    )
    assert t.group_prefix == "civilians" and t.players_only is False and t.coalition == 0


@pytest.mark.parametrize(
    "event",
    [
        "mission.end",
        "encounter.telegraph",
        "encounter.sam_hot",
        "encounter.wave",
        "encounter.proximity",
        "convoy.halted",
        "convoy.resumed",
        "ground.stuck",
        "intel.revealed",
        "spawner.spawned",
    ],
)
def test_trigger_new_events(event: str) -> None:
    assert BeatTrigger(event=event).event == event  # type: ignore[arg-type]


def test_trigger_still_requires_filter() -> None:
    with pytest.raises(ValidationError):
        BeatTrigger.model_validate({"event": "zone.entered"})


# ---------------------------------------------------------------------------
# BeatMark / BeatEffects / Beat
# ---------------------------------------------------------------------------


def test_mark_shorthands() -> None:
    assert BeatMark.model_validate("zone:box").at == "zone:box"
    m = BeatMark.model_validate({"x": 100.5, "y": -20, "radius": 300, "text": "HERE"})
    assert m.at == "point:100.5,-20" and m.radius_m == 300
    assert BeatMark.model_validate({"at": {"x": 1, "y": 2}}).at == "point:1,2"
    assert BeatMark.model_validate({"type": "circle", "at": "unit:Dusty-1"}).at == "unit:Dusty-1"
    with pytest.raises(ValidationError):
        BeatMark.model_validate({"at": "somewhere"})


def test_effects_lists_and_aliases() -> None:
    e = BeatEffects.model_validate(
        {
            "setFlag": ["a", "b"],
            "flag_value": 2,
            "clear_flag": ["c"],
            "start_encounter": ["e1", "e2"],
            "finish": "victory",
            "qualities": {"trust": 1},
        }
    )
    assert e.set_flag == ["a", "b"] and e.flag_value == 2 and e.clear_flag == ["c"]
    assert e.start_encounter == ["e1", "e2"]
    assert e.end_mission == "success"
    assert e.quality_deltas == {"trust": 1}
    assert BeatEffects.model_validate({"end": "defeat"}).end_mission == "failure"
    with pytest.raises(ValidationError):
        BeatEffects.model_validate({"finish": "maybe"})


def test_beat_guaranteed() -> None:
    b = Beat.model_validate({"id": "spine", "when": {"zone": "box"}, "guaranteed": True})
    assert b.guaranteed and b.when.event == "zone.entered"
    assert Beat.model_validate({"id": "x", "when": {"event": "mission.start"}}).guaranteed is False
    with pytest.raises(ValidationError):
        Beat.model_validate(
            {"id": "bad", "when": {"zone": "box"}, "guaranteed": True, "requires": {"chance": 50}}
        )


def test_beat_mark_string_and_camel() -> None:
    b = Beat.model_validate(
        {"id": "m", "when": {"afterSec": 1}, "mark": "group:hidden_aa", "delaySec": 3}
    )
    assert b.mark is not None and b.mark.at == "group:hidden_aa"
    assert b.delay_sec == 3


# ---------------------------------------------------------------------------
# Voice turns
# ---------------------------------------------------------------------------


def test_voice_line_turns_fill_text_and_speaker() -> None:
    ln = VoiceLine.model_validate(
        {
            "id": "net_v1",
            "turns": [
                {"speaker": "kestrel_ferris", "text": "Ops, Kestrel. Routine."},
                {"speaker": "ops_walsh", "text": "Kestrel, Ops. Copy."},
            ],
        }
    )
    assert ln.speaker == "kestrel_ferris"
    assert ln.text == "Ops, Kestrel. Routine. Kestrel, Ops. Copy."
    assert ln.turns is not None and ln.turns[1].speaker == "ops_walsh"


def test_voice_line_turns_need_two() -> None:
    with pytest.raises(ValidationError):
        VoiceLine.model_validate(
            {"id": "x", "speaker": "a", "text": "t", "turns": [{"speaker": "a", "text": "t"}]}
        )


# ---------------------------------------------------------------------------
# RuntimeConfig additions
# ---------------------------------------------------------------------------


def _runtime() -> RuntimeConfig:
    return RuntimeConfig.model_validate(
        {
            "mission_id": "m01",
            "qualities": {"enemy_aa": 2, "trust": 0},
            "speakers": {"kestrel_ferris": {"callsign": "Kestrel Two-Two", "frequency": 251.0}},
            "narrative": {"min_gap_sec": 5},
            "intel": {"scan_sec": 3, "remove_sec": 400, "mark_radius_m": 500, "sensors": False},
            "budgets": {"max_active_ship": 4},
            "director": {"peak_hold_sec": 20, "gain": {"near_shot": 3}},
            "templates": {
                "zu23": {
                    "country": "INSURGENTS",
                    "category": "helicopter",
                    "task": "CAS",
                    "alt_m": 300,
                    "units": [{"type": "Mi-8MT", "heading": 90, "skill": "High", "livery": "x"}],
                }
            },
            "zones": {"box": {"kind": "circle", "x": 0, "y": 0, "radius": 1000}},
            "pools": {"p": {"members": [{"tpl": "zu23"}], "pick": 2, "zones": ["box"]}},
            "encounters": [
                {
                    "id": "popup",
                    "kind": "ambush_sam",
                    "pool": "p",
                    "trigger": {"type": "proximity", "zone": "box", "radius_m": 8000},
                    "telegraph": "beat:warn",
                    "engage_radius_m": 5000,
                    "hot_chance": 80,
                    "telegraph_sec": [30, 60],
                    "react_sec": 5,
                },
                {
                    "id": "cv",
                    "kind": "convoy",
                    "group": "Convoy1",
                    "trigger": {"type": "time", "after_sec": [60, 120]},
                    "destination": {"x": 10, "y": 20},
                    "resume_after_sec": [30, 60],
                },
                {
                    "id": "ev",
                    "kind": "waves",
                    "template": "zu23",
                    "zone": "box",
                    "waves": [2, 4],
                    "hunt": "Dusty",
                    "trigger": {"type": "event", "event": "convoy.halted", "coalition": 2},
                },
                {
                    "id": "dir",
                    "kind": "pool",
                    "pool": "p",
                    "trigger": {"type": "director", "state": "RELAX"},
                },
                {"id": "man", "kind": "pool", "pool": "p", "trigger": {"type": "manual"}},
            ],
            "voice": {
                "net_v1": {
                    "file": "net_v1.ogg",
                    "text": "Ops, Kestrel. Ops: copy.",
                    "dur_sec": 4,
                    "speaker": "kestrel_ferris",
                    "turns": [
                        {"speaker": "kestrel_ferris", "text": "Ops, Kestrel."},
                        {"speaker": "ops_walsh", "text": "Copy."},
                    ],
                }
            },
        }
    )


def test_runtime_new_fields_to_lua_camel_case() -> None:
    t = _runtime().to_lua_table()
    assert t["qualities"] == {"enemy_aa": 2, "trust": 0}  # user keys preserved
    assert t["speakers"]["kestrel_ferris"] == {"callsign": "Kestrel Two-Two", "frequency": 251.0}
    assert t["narrative"] == {"minGapSec": 5, "pendingTtlSec": 45, "zonePollSec": 3}
    assert t["intel"]["scanSec"] == 3 and t["intel"]["removeSec"] == 400
    assert t["intel"]["markRadiusM"] == 500 and t["intel"]["sensors"] is False
    assert t["budgets"]["maxActiveShip"] == 4
    assert t["director"]["peakHoldSec"] == 20 and t["director"]["gain"] == {"nearShot": 3}
    tpl = t["templates"]["zu23"]
    assert tpl["altM"] == 300 and tpl["units"][0]["heading"] == 90
    enc = {e["id"]: e for e in t["encounters"]}
    assert enc["popup"]["engageRadiusM"] == 5000 and enc["popup"]["hotChance"] == 80
    assert enc["popup"]["telegraphSec"] == [30, 60] and enc["popup"]["reactSec"] == 5
    assert enc["popup"]["trigger"]["radiusM"] == 8000
    assert enc["cv"]["trigger"]["afterSec"] == [60, 120]
    assert enc["cv"]["destination"] == {"x": 10, "y": 20} and enc["cv"]["resumeAfterSec"] == [
        30,
        60,
    ]
    assert "pool" not in enc["cv"]
    assert enc["ev"]["waves"] == [2, 4] and enc["ev"]["hunt"] == "Dusty"
    assert enc["dir"]["trigger"] == {"type": "director", "state": "RELAX"}
    assert t["voice"]["net_v1"]["turns"][1] == {"speaker": "ops_walsh", "text": "Copy."}


def test_runtime_defaults_omit_optional_sections() -> None:
    t = RuntimeConfig(mission_id="m").to_lua_table()
    assert "narrative" not in t
    assert t["qualities"] == {} and t["speakers"] == {}
    assert t["intel"] == {
        "fogOfWar": True,
        "revealRadiusM": 5000,
        "markRefreshSec": 15,
        "staleSec": 120,
    }


def test_encounter_needs_a_source() -> None:
    with pytest.raises(ValidationError):
        Encounter.model_validate({"id": "x", "kind": "pool", "trigger": {"type": "manual"}})


def test_runtime_beats_with_lua_shapes_round_trip() -> None:
    cfg = RuntimeConfig.model_validate(
        {
            "mission_id": "m",
            "beats": [
                {
                    "id": "b1",
                    "when": {"flag": "x", "value": 1},
                    "requires": {"qualities": {"trust": ">=2"}, "notFlags": ["y"]},
                    "effects": {"finish": "victory", "qualities": {"trust": -1}},
                    "guaranteed": True,
                }
            ],
        }
    )
    b = cfg.to_lua_table()["beats"][0]
    assert b["when"] == {"event": "flag", "flag": "x", "value": 1}
    assert b["requires"]["flagsNot"] == ["y"]
    assert b["requires"]["qualities"] == [{"quality": "trust", "op": ">=", "value": 2.0}]
    assert b["effects"]["endMission"] == "success"
    assert b["effects"]["qualityDeltas"] == {"trust": -1}
    assert b["guaranteed"] is True


# ---------------------------------------------------------------------------
# Campaign / mission / outcome
# ---------------------------------------------------------------------------


def test_qualities_next_mission() -> None:
    q = Qualities.model_validate({"values": {"trust": 1}, "next_mission": "m02-cracking-kirikhan"})
    assert q.next_mission == "m02-cracking-kirikhan"
    assert Qualities().next_mission is None


def test_civilian_threat_role() -> None:
    p = PoolIntent.model_validate({"id": "civ", "roles": ["civilian"], "areas": ["road"]})
    assert p.roles == ["civilian"]


def test_outcome_new_fields_and_event_alias() -> None:
    log = (
        '2026-01-01 10:00:00.000 INFO SCRIPTING: [DMS.OUTCOME] {"beats":["a"],"kind":"update",'
        '"missionId":"m01","outcome":{"x":true},"qualities":{"trust":1},"qualityDeltas":{"trust":1},'
        '"t":12.5}\n'
        '2026-01-01 10:10:00.000 INFO SCRIPTING: [DMS.OUTCOME] {"beats":["a","b"],"event":"end",'
        '"flags":{"landed":true},"missionId":"m01","outcome":[],"qualities":[],"qualityDeltas":[],'
        '"result":"success","t":600}\n'
    )
    recs = parse_dcs_log(log)
    assert len(recs) == 2
    assert recs[0].quality_deltas == {"trust": 1} and recs[0].beats == ["a"]
    assert recs[1].kind == "end" and recs[1].quality_deltas == {} and recs[1].extra == {}
    merged = recs[0].merge(recs[1])
    assert merged.beats == ["a", "b"] and merged.quality_deltas == {"trust": 1}
    assert merged.result == "success" and merged.flags == {"landed": True}
    assert isinstance(merged, MissionOutcome)


def test_voice_entry_subtitle_only() -> None:
    cfg = RuntimeConfig.model_validate(
        {"mission_id": "m", "voice": {"l1": {"text": "Copy.", "dur_sec": 2, "speaker": "ops"}}}
    )
    assert cfg.voice["l1"].file is None
    assert "file" not in cfg.to_lua_table()["voice"]["l1"]


def test_build_plan_neutral_countries() -> None:
    from dms_core.schemas import BuildPlan

    assert "neutral_countries" in BuildPlan.model_fields
    field = BuildPlan.model_fields["neutral_countries"]
    assert field.default_factory is list
