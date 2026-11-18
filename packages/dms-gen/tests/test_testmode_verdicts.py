"""Test-mode verdicts for an AI proxy: optional encounters, any-end outcome, loiter until RTB.

Minimal m03 / m04-like fixtures (viper-detachment shapes) are inlined so these tests never depend
on campaigns/ files.
"""

from __future__ import annotations

from pathlib import Path
from typing import Any

import pytest
import yaml
from dms_core.schemas import BeatSheet, MissionSpec, StoryBible, VoiceLineSet
from dms_core.schemas.beats import Beat, BeatMark
from dms_core.schemas.mission import MissionTestHints
from dms_core.schemas.runtime import CircleZone, Encounter, PolygonZone, TestSettings, from_lua
from dms_gen.planner import make_test_plan, plan_mission
from dms_gen.planner.testmode import (
    build_test_lua,
    default_checks,
    encounter_requirements,
    exclusive_groups,
    loiter_target,
)

Zones = dict[str, CircleZone | PolygonZone]

# m04-like: route roll by silent sibling chance beats, RTB on a flag (radar dead or escape timer).
M04_BEATS = """
beats:
  - {id: mission_start, when: {event: player.spawned, players_only: true}, guaranteed: true,
     speaker: ops, text: start}
  - {id: checkin, when: {event: zone.entered, zone: push, players_only: true}, guaranteed: true,
     speaker: awacs, text: checkin, effects: {set_flag: checked_in}}
  - {id: retask, when: {event: flag, flag: checked_in}, guaranteed: true, speaker: ops,
     text: retask}
  - {id: on_station, when: {event: zone.entered, zone: search_box, players_only: true},
     guaranteed: true, speaker: awacs, text: on station}
  - {id: rtb_call, when: {event: flag, flag: convoy_resolved}, delay_sec: 10, guaranteed: true,
     speaker: ops, text: rtb}
  - {id: on_deck, when: {event: unit.landed, players_only: true}, requires: {flags: [rtb_called]},
     guaranteed: true, speaker: ops, text: on deck}
  - id: route_n
    when: {event: beat.fired, beat: retask}
    requires: {flags_not: [route_set], chance: 33}
    effects: {set_flag: [route_set, route_n_set]}
  - id: route_c
    when: {event: beat.fired, beat: retask}
    requires: {flags_not: [route_set], chance: 50}
    effects: {set_flag: [route_set, route_c_set]}
  - id: route_s
    when: {event: beat.fired, beat: retask}
    requires: {flags_not: [route_set]}
    effects: {set_flag: [route_set, route_s_set]}
  - id: convoy_escaped
    when: {event: beat.fired, beat: retask}
    requires: {flags_not: [convoy_resolved]}
    delay_sec: 2400
    speaker: ops
    text: escaped
    effects: {set_flag: [convoy_escaped, convoy_resolved]}
  - id: result_failure
    when: {event: beat.fired, beat: on_deck}
    delay_sec: 30
    effects: {end_mission: failure}
"""

M04_ENCOUNTERS: list[dict[str, Any]] = [
    {
        "id": "convoy_n",
        "kind": "convoy",
        "pool": "p",
        "trigger": {"type": "beat", "beat": "route_n"},
    },
    {
        "id": "convoy_c",
        "kind": "convoy",
        "pool": "p",
        "trigger": {"type": "beat", "beat": "route_c"},
    },
    {
        "id": "convoy_s",
        "kind": "convoy",
        "pool": "p",
        "trigger": {"type": "beat", "beat": "route_s"},
    },
    {
        "id": "morning_traffic",
        "kind": "convoy",
        "pool": "p",
        "trigger": {"type": "time", "after_sec": 120},
        "chance": 80,
    },
    {
        "id": "crossing_manpads",
        "kind": "ambush_sam",
        "pool": "p",
        "trigger": {"type": "beat", "beat": "retask"},
        "chance": 60,
    },
]

# m03-like: time-placed positions, waves on a guaranteed beat, a SAM on proximity, RTB on a chain.
M03_BEATS = """
beats:
  - {id: mission_start, when: {event: timer, after_sec: 20}, guaranteed: true, speaker: ops,
     text: start}
  - {id: handoff, when: {event: zone.entered, zone: ip, players_only: true}, guaranteed: true,
     speaker: awacs, text: handoff, effects: {set_flag: checked_in}}
  - {id: talk_on, when: {event: flag, flag: checked_in}, delay_sec: 12, guaranteed: true,
     speaker: jtac, text: talk on}
  - {id: checkout, when: {event: flag, flag: fight_over}, delay_sec: 30, guaranteed: true,
     speaker: jtac, text: checkout}
  - {id: rook_rtb, when: {event: beat.fired, beat: checkout}, delay_sec: 15, guaranteed: true,
     speaker: ops, text: rtb}
  - {id: hold_limit, when: {event: beat.fired, beat: talk_on}, delay_sec: 1200,
     effects: {set_flag: fight_over}}
  - {id: bonus_target, when: {event: flag, flag: next_target}, speaker: jtac, text: bonus}
"""

M03_ENCOUNTERS: list[dict[str, Any]] = [
    {
        "id": "fort_positions",
        "kind": "pool",
        "pool": "p",
        "trigger": {"type": "time", "after_sec": 0},
    },
    {
        "id": "assault_push",
        "kind": "waves",
        "pool": "p",
        "trigger": {"type": "beat", "beat": "talk_on"},
    },
    {
        "id": "sa13_ambush",
        "kind": "ambush_sam",
        "pool": "p",
        "trigger": {"type": "proximity", "zone": "fight_box", "radius_m": 25000},
    },
    {
        "id": "far_sam",
        "kind": "ambush_sam",
        "pool": "p",
        "trigger": {"type": "proximity", "zone": "far_box", "radius_m": 5000},
    },
    {
        "id": "bonus_armor",
        "kind": "pool",
        "pool": "p",
        "trigger": {"type": "beat", "beat": "bonus_target"},
    },
    {"id": "scripted", "kind": "pool", "pool": "p", "trigger": {"type": "manual"}},
]

ZONES: Zones = {
    "push": CircleZone(x=50_000, y=0, radius=10_000),
    "search_box": PolygonZone.model_validate(
        {
            "kind": "polygon",
            "points": [
                {"x": 90_000, "y": -10_000},
                {"x": 110_000, "y": -10_000},
                {"x": 110_000, "y": 10_000},
                {"x": 90_000, "y": 10_000},
            ],
        }
    ),
    "ip": CircleZone(x=60_000, y=0, radius=5_000),
    "fight_box": CircleZone(x=70_000, y=5_000, radius=3_000),
    "far_box": CircleZone(x=0, y=200_000, radius=3_000),
}
START = (0.0, 0.0)


def _beats(src: str) -> list[Beat]:
    return list(BeatSheet.model_validate(yaml.safe_load(src)).beats)


def _encs(rows: list[dict[str, Any]]) -> list[Encounter]:
    return [Encounter.model_validate(r) for r in rows]


def test_m04_route_roll_is_an_optional_exclusive_group() -> None:
    beats = _beats(M04_BEATS)
    assert exclusive_groups(beats) == {
        "route_n": "route_set",
        "route_c": "route_set",
        "route_s": "route_set",
    }
    path = [START, (50_000, 0), (100_000, 0), START]
    optional = encounter_requirements(_encs(M04_ENCOUNTERS), beats, path, ZONES)
    assert optional == {
        "convoy_n": "route_set",
        "convoy_c": "route_set",
        "convoy_s": "route_set",
        "morning_traffic": None,  # chance 80
        "crossing_manpads": None,  # chance 60 (its beat is guaranteed)
    }
    checks = default_checks(60, beats, [e["id"] for e in M04_ENCOUNTERS], optional=optional)
    enc = {c["id"]: c for c in checks if c["kind"] == "encounter"}
    assert enc["convoy_c"]["optional"] is True and enc["convoy_c"]["group"] == "route_set"
    assert enc["morning_traffic"]["optional"] is True and "group" not in enc["morning_traffic"]
    TestSettings.model_validate(from_lua(TestSettings, {"checks": checks}))


def test_m03_unconditional_triggers_stay_required() -> None:
    beats = _beats(M03_BEATS)
    path = [START, (60_000, 0), START]
    optional = encounter_requirements(_encs(M03_ENCOUNTERS), beats, path, ZONES)
    # time / guaranteed beat / proximity on the route are required
    assert "fort_positions" not in optional
    assert "assault_push" not in optional
    assert "sa13_ambush" not in optional
    # off-route proximity, non-guaranteed beat, manual: optional
    assert optional == {"far_sam": None, "bonus_armor": None, "scripted": None}


def test_start_encounter_from_guaranteed_beat_is_required() -> None:
    beats = _beats(M03_BEATS)
    beats[2].effects.start_encounter = "scripted"
    optional = encounter_requirements(_encs(M03_ENCOUNTERS), beats, [START, START], ZONES)
    assert "scripted" not in optional


def test_outcome_any_end_unless_required() -> None:
    beats = _beats(M04_BEATS)
    out = default_checks(60, beats, [])[-1]
    assert out["kind"] == "outcome" and "requireResult" not in out and "result" not in out
    out = default_checks(60, beats, [], require_result="success")[-1]
    assert out["requireResult"] == "success"


def test_loiter_targets_rtb_beat_and_last_zone() -> None:
    m04 = loiter_target(_beats(M04_BEATS), ZONES, START)
    assert m04 is not None
    rtb, zone_beat, zone = m04
    assert (rtb.id, zone_beat.id, zone) == ("rtb_call", "on_station", "search_box")
    # no landing beat in the spine: the last spine beat is the RTB beat
    m03 = loiter_target(_beats(M03_BEATS), ZONES, START)
    assert m03 is not None
    assert (m03[0].id, m03[1].id, m03[2]) == ("rook_rtb", "handoff", "ip")


def test_no_loiter_when_rtb_is_position_driven() -> None:
    beats = _beats(M04_BEATS)
    # m01 shape: a home-approach zone beat right before the landing beat
    beats[4] = Beat.model_validate(
        {
            "id": "tower_welcome",
            "when": {"event": "zone.entered", "zone": "push"},
            "guaranteed": True,
            "speaker": "tower",
            "text": "welcome",
        }
    )
    assert loiter_target(beats, ZONES, START) is None


def test_build_test_lua_carries_loiter_and_validates() -> None:
    lupa = pytest.importorskip("lupa")
    loiter = {
        "zone": "search_box",
        "x": 100_000.0,
        "y": 0.0,
        "radiusM": 3000.0,
        "altM": 4500.0,
        "altType": "BARO",
        "speedMps": 166.7,
        "startBeat": "on_station",
        "untilBeat": "rtb_call",
        "returnSec": 1200,
    }
    src = build_test_lua("Proxy 1", 90, _beats(M04_BEATS), ["convoy_n"], loiter=loiter)
    lua = lupa.lua51.LuaRuntime(unpack_returned_tuples=True)
    lua.execute(src)
    t = lua.eval("DMS_CONFIG.test")
    assert t.loiter.untilBeat == "rtb_call"
    assert t.loiter.startBeat == "on_station"


# ---- end to end on the dustoff m01 fixture (helicopter, no loiter) -------------------------

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


def test_m01_helicopter_has_no_loiter_and_spec_hint_sets_require_result(m01: Any) -> None:
    lupa = pytest.importorskip("lupa")
    plan, spec, beats = m01
    hinted = spec.model_copy(update={"test": MissionTestHints(require_result="success")})
    tb = make_test_plan(plan, hinted, beats, minutes=40)
    lua = lupa.lua51.LuaRuntime(unpack_returned_tuples=True)
    lua.execute(tb.lua)
    t = lua.eval("DMS_CONFIG.test")
    assert t.loiter is None
    assert t.checks[len(t.checks)].requireResult == "success"


def test_end_of_run_checks_for_marks_fog_and_comms() -> None:
    beats = _beats(M04_BEATS)
    checks = default_checks(60, beats, [])
    by_kind = {c["kind"]: c for c in checks}
    assert by_kind["marks"] == {"kind": "marks", "name": "f10_marks", "min": 0}
    assert by_kind["fog_hidden"]["name"] == "fog_hidden"
    assert by_kind["comms_no_overlap"]["name"] == "radio_no_overlap"
    assert by_kind["comms_beats"]["name"] == "spine_lines_played"
    assert checks[-1]["kind"] == "outcome"
    beats[1].mark = BeatMark.model_validate("zone:push")
    assert {c["kind"]: c for c in default_checks(60, beats, [])}["marks"]["min"] == 1
    # the generated DMS_CONFIG.test validates against the contract model
    lua = build_test_lua("Proxy", 60, beats, [])
    assert 'kind = "comms_beats"' in lua and 'kind = "fog_hidden"' in lua
    cfg = TestSettings.model_validate(
        from_lua(TestSettings, {"enabled": True, "checks": default_checks(60, beats, [])})
    )
    kinds = [c.kind for c in cfg.checks]
    assert kinds[-7:-3] == ["marks", "fog_hidden", "comms_no_overlap", "comms_beats"]
    assert kinds[-2] == "voice_files"  # always added (A3)
