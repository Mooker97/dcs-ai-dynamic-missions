"""Mission-quality lint rules (dms_core.lint): one firing and one quiet case per rule."""

from __future__ import annotations

import copy
import json
from pathlib import Path
from typing import Any

import pytest
import yaml
from dms_core.lint import (
    RULES,
    MissionDocs,
    _effect_swing,
    lint_arc,
    lint_mission,
    lint_mission_dir,
    load_mission_docs,
)
from dms_core.schemas import BeatSheet, CampaignArc, MissionSpec, StoryBible, VoiceLineSet
from dms_core.schemas.validation import Issue

CAMPAIGNS = Path(__file__).resolve().parents[3] / "campaigns"

BASE_SPEC: dict[str, Any] = {
    "id": "m01-test",
    "title": "Test",
    "theater": "Syria",
    "era": 2016,
    "date": "2016-11-03",
    "mission_type": "SEAD",
    "blue_countries": ["USA"],
    "red_countries": ["Insurgents"],
    "cast": ["ops", "awacs", "pike"],
    "areas": [
        {"id": "base", "where": {"kind": "near_airbase", "airbase": "Incirlik"}},
        {"id": "push", "where": {"kind": "latlon", "lat": 36.6, "lon": 37.1}},
        {"id": "town", "where": {"kind": "latlon", "lat": 36.4, "lon": 37.5}},
    ],
    "player_flights": [
        {
            "callsign": "Python",
            "aircraft": "F-16C_50",
            "start_area": "base",
            "start_type": "parking_cold",
            "loadout": "sead",
            "variant": "ramp",
        }
    ],
    "objectives": [{"id": "obj", "kind": "destroy", "description": "Kill it.", "area": "town"}],
    "dynamic": {
        "pools": [
            {"id": "sam", "roles": ["sam_short"], "areas": ["town"]},
            {"id": "tanks", "roles": ["armor"], "areas": ["town"]},
            {"id": "jets", "roles": ["fighters"], "areas": ["town"]},
        ]
    },
}

GOOD_BRIEFING = """# TEST

Duration: air start ~30 min, ramp ~55 min. Stakes: if we fail, the drone stays grounded.

## 1. Situation
ZU-23 guns in town.
## 2. Mission
Kill it.
## 3. Execution
Abort on damage. Bingo 3000 lb. Laser code 1688.
## 4. Administration
Divert Gaziantep.
## 5. Command and signal
| Agency | Freq |
|---|---|
| AWACS | 251.0 AM |
"""

GOOD_KNEEBOARD = """# KNEEBOARD
Laser code 1688
| Agency | Freq |
|---|---|
| AWACS | 251.0 AM |
"""


def spec(**over: Any) -> MissionSpec:
    d = copy.deepcopy(BASE_SPEC)
    for k, v in over.items():
        if k in ("encounters",):
            d["dynamic"]["encounters"] = v
        else:
            d[k] = v
    return MissionSpec.model_validate(d)


def beat(bid: str, when: dict[str, Any], text: str | None = None, **kw: Any) -> dict[str, Any]:
    b: dict[str, Any] = {"id": bid, "when": when, **kw}
    if text is not None:
        b["text"] = text
        b.setdefault("speaker", "ops")
    return b


def run(
    beats: list[dict[str, Any]] | None = None,
    lines: list[dict[str, Any]] | None = None,
    sp: MissionSpec | None = None,
    bible: StoryBible | None = None,
    docs: MissionDocs | None = None,
) -> list[Issue]:
    return lint_mission(
        sp or spec(),
        BeatSheet.model_validate(beats or []),
        VoiceLineSet.model_validate(lines or []),
        bible,
        docs,
    )


def codes(issues: list[Issue], sev: str | None = None) -> set[str]:
    return {i.code for i in issues if i.code and (sev is None or i.severity == sev)}


def lines_for(bid: str, texts: list[str], speaker: str = "ops") -> list[dict[str, Any]]:
    return [{"id": f"{bid}_v{n}", "speaker": speaker, "text": t} for n, t in enumerate(texts, 1)]


def make_bible() -> StoryBible:
    def char(cid: str, cs: str, role: str, brevity: str = "normal") -> dict[str, Any]:
        return {
            "id": cid,
            "name": cid,
            "callsign": cs,
            "role": role,
            "voice": {"design_prompt": "calm", "brevity": brevity},
        }

    return StoryBible.model_validate(
        {
            "title": "T",
            "mode": "fictional",
            "setting": {"era": 2016, "theater": "Syria", "premise_summary": "A test."},
            "factions": [
                {"id": "blue", "name": "Blue", "dcs": {"country": "USA", "coalition": "blue"}}
            ],
            "characters": [
                char("ops", "Rook", "squadron ops officer"),
                char("awacs", "Magic", "AWACS controller", "terse"),
                char("pike", "Pike", "wingman"),
            ],
        }
    )


# ---- meta -------------------------------------------------------------------------------------


def test_issue_shape_has_code_and_fix() -> None:
    issues = run([beat("late", {"event": "timer", "after_sec": 600}, "Python, Rook, go.")])
    hook = [i for i in issues if i.code == "hook_late"]
    assert hook
    assert hook[0].problem.startswith("[hook_late] ")
    assert "Fix:" in hook[0].problem
    assert hook[0].hint
    assert all(i.code in RULES for i in issues)


def test_clean_mission_has_no_findings() -> None:
    issues = run(
        [beat("start", {"event": "timer", "after_sec": 20}, "Python, Rook Ops, push.")],
        docs=MissionDocs(briefing=GOOD_BRIEFING, kneeboard=GOOD_KNEEBOARD),
    )
    assert issues == []


# ---- spine / takeoff / hook -------------------------------------------------------------------


def test_spine_no_fallback_fires_on_kill_gate() -> None:
    b = [
        beat(
            "radar_down",
            {"event": "group.dead", "group": "SAM"},
            "Python, Rook, radar down.",
            guaranteed=True,
            effects={"set_flag": "window_done"},
        )
    ]
    issues = run(b)
    assert "spine_no_fallback" in codes(issues, "warning")


def test_spine_no_fallback_quiet_with_timeout_sibling() -> None:
    b = [
        beat(
            "radar_down",
            {"event": "group.dead", "group": "SAM"},
            "Python, Rook, radar down.",
            guaranteed=True,
            effects={"set_flag": "window_done"},
        ),
        beat(
            "retask",
            {"event": "timer", "after_sec": 600},
            "Python, Rook, retask.",
            requires={"beats_not_fired": ["radar_down"]},
            effects={"set_flag": "window_done"},
        ),
        beat(
            "close",
            {"event": "flag", "flag": "window_done"},
            "Python, Rook, window closed.",
            guaranteed=True,
        ),
    ]
    assert "spine_no_fallback" not in codes(run(b))


def test_spine_flag_with_single_kill_setter_fires() -> None:
    b = [
        beat("kill", {"event": "unit.dead", "unit": "X"}, effects={"set_flag": "done"}),
        beat("next", {"event": "flag", "flag": "done"}, "Python, Rook, next.", guaranteed=True),
    ]
    assert "spine_no_fallback" in codes(run(b))


def _air_spec() -> MissionSpec:
    flights = copy.deepcopy(BASE_SPEC["player_flights"])
    flights.append({**flights[0], "start_type": "air", "start_area": "push", "variant": "air"})
    return spec(player_flights=flights)


def test_guaranteed_on_takeoff_is_error_with_air_variant() -> None:
    b = [beat("airborne", {"event": "unit.takeoff"}, "Python, Rook, airborne.", guaranteed=True)]
    issues = run(b, sp=_air_spec())
    assert "guaranteed_on_takeoff" in codes(issues, "error")


def test_guaranteed_on_ramp_zone_chain_is_error() -> None:
    b = [
        beat("ramp", {"event": "zone.entered", "zone": "base"}, "Python, Ground, taxi."),
        beat("after", {"event": "beat.fired", "beat": "ramp"}, "Python, Rook.", guaranteed=True),
    ]
    assert "guaranteed_on_takeoff" in codes(run(b, sp=_air_spec()), "error")


def test_guaranteed_on_takeoff_quiet_without_air_variant() -> None:
    b = [beat("airborne", {"event": "unit.takeoff"}, "Python, Rook, airborne.", guaranteed=True)]
    assert "guaranteed_on_takeoff" not in codes(run(b))
    b2 = [
        beat("push", {"event": "zone.entered", "zone": "push"}, "Python, Magic.", guaranteed=True)
    ]
    assert "guaranteed_on_takeoff" not in codes(run(b2, sp=_air_spec()))


def test_hook_late_fires_and_quiet() -> None:
    late = [beat("first", {"event": "timer", "after_sec": 400}, "Python, Rook, go.")]
    assert "hook_late" in codes(run(late))
    early = [beat("first", {"event": "timer", "after_sec": 60}, "Python, Rook, go.")]
    assert "hook_late" not in codes(run(early))
    # a zone-triggered call can come any time: no verdict
    zone = [*late, beat("z", {"event": "zone.entered", "zone": "push"}, "Python, Magic.")]
    assert "hook_late" not in codes(run(zone))


# ---- encounters --------------------------------------------------------------------------------


def _enc(eid: str, kind: str, pool: str, **kw: Any) -> dict[str, Any]:
    return {
        "id": eid,
        "kind": kind,
        "pool": pool,
        "trigger": {"type": "time", "after_min": 1},
        **kw,
    }


def test_popup_no_telegraph_error_for_sam() -> None:
    issues = run(sp=spec(encounters=[_enc("popup", "ambush_sam", "sam")]))
    assert "popup_no_telegraph" in codes(issues, "error")


def test_popup_no_telegraph_ground_waves_only_warn() -> None:
    issues = run(sp=spec(encounters=[_enc("push", "waves", "tanks", waves=2)]))
    assert "popup_no_telegraph" in codes(issues, "warning")
    assert "popup_no_telegraph" not in codes(issues, "error")


def test_popup_no_telegraph_quiet_with_telegraph() -> None:
    b = [beat("warn", {"event": "timer", "after_sec": 30}, "Python, Magic, pop-up group.")]
    sp = spec(encounters=[_enc("bandits", "cap", "jets", telegraph_beat="warn")])
    assert "popup_no_telegraph" not in codes(run(b, sp=sp))
    # a beat on encounter.telegraph for the encounter also counts
    b2 = [
        beat(
            "tw",
            {"event": "encounter.telegraph", "encounter": "popup"},
            "Python, Rook, SAM up.",
        )
    ]
    sp2 = spec(encounters=[_enc("popup", "ambush_sam", "sam")])
    assert "popup_no_telegraph" not in codes(run(b2, sp=sp2))


def test_popup_no_cue_needs_briefing_mention() -> None:
    enc = [_enc("manpads_popup", "ambush_sam", "sam", notes="no-cue: IR, no RWR warning")]
    without = run(sp=spec(encounters=enc), docs=MissionDocs(briefing="# B\nNothing here."))
    assert "popup_no_telegraph" in codes(without, "error")
    briefed = run(
        sp=spec(encounters=enc),
        docs=MissionDocs(briefing="# B\nSA-8 and other short-range SAM pop-ups possible."),
    )
    assert "popup_no_telegraph" not in codes(briefed)


def test_telegraph_too_short_fires_on_delay_and_quiet() -> None:
    sp = spec(encounters=[_enc("popup", "ambush_sam", "sam", telegraph_beat="warn")])
    slow = [beat("warn", {"event": "timer", "after_sec": 30}, "Python, Rook, SAM.", delay_sec=20)]
    assert "telegraph_too_short" in codes(run(slow, sp=sp))
    gated = [
        beat(
            "warn",
            {"event": "timer", "after_sec": 30},
            "Python, Rook, SAM.",
            requires={"chance": 50},
        )
    ]
    assert "telegraph_too_short" in codes(run(gated, sp=sp))
    ok = [beat("warn", {"event": "timer", "after_sec": 30}, "Python, Rook, SAM.")]
    assert "telegraph_too_short" not in codes(run(ok, sp=sp))


def test_vul_overload() -> None:
    many = [_enc(f"e{n}", "pool", "tanks") for n in range(7)]
    assert "vul_overload" in codes(run(sp=spec(encounters=many)))
    assert "vul_overload" not in codes(run(sp=spec(encounters=many[:6])))


# ---- lines ------------------------------------------------------------------------------------


def _line_beat(
    bid: str, texts: list[str], when: dict[str, Any] | None = None, **kw: Any
) -> tuple[list[dict[str, Any]], list[dict[str, Any]]]:
    ln = lines_for(bid, texts, kw.pop("speaker", "ops"))
    b = {
        "id": bid,
        "when": when or {"event": "timer", "after_sec": 10},
        "speaker": ln[0]["speaker"],
        "lines": [x["id"] for x in ln],
        **kw,
    }
    return [b], ln


LONG = "Python, Rook Ops, " + " ".join(["word"] * 23)


def test_line_too_long_fires_on_words_and_manifest_duration() -> None:
    b, ln = _line_beat("brief", [LONG])
    assert "line_too_long" in codes(run(b, ln))
    b2, ln2 = _line_beat("brief", ["Python, Rook, push."])
    long_audio = MissionDocs(durations={"brief_v1": 9.5})
    assert "line_too_long" in codes(run(b2, ln2, docs=long_audio))


def test_line_too_long_quiet_and_terse_limit() -> None:
    b, ln = _line_beat("brief", ["Python, Rook Ops, push now, window open."])
    assert "line_too_long" not in codes(run(b, ln))
    # 15 words is fine for 'normal' but over 'terse' (Magic)
    fifteen = "Python, Magic, " + " ".join(["word"] * 13)
    b2, ln2 = _line_beat("pic", [fifteen], speaker="awacs")
    assert "line_too_long" in codes(run(b2, ln2, bible=make_bible()))
    b3, ln3 = _line_beat("pic", [fifteen], speaker="ops")
    assert "line_too_long" not in codes(run(b3, ln3, bible=make_bible()))


def test_peak_chatter_fires_mid_fight_only() -> None:
    chatty = "Python, Rook, " + " ".join(["word"] * 13)
    b, ln = _line_beat("hit", [chatty], {"event": "unit.hit", "players_only": True})
    assert "peak_chatter" in codes(run(b, ln))
    b2, ln2 = _line_beat("calm", [chatty], {"event": "timer", "after_sec": 30})
    assert "peak_chatter" not in codes(run(b2, ln2))
    b3, ln3 = _line_beat("hit", ["Python, Two, you're hit."], {"event": "unit.hit"})
    assert "peak_chatter" not in codes(run(b3, ln3))


def test_callsign_first() -> None:
    b, ln = _line_beat("odd", ["Something strange is happening out there."])
    assert "callsign_first" in codes(run(b, ln))
    for ok in ("Python, Magic, picture clean.", "Two's fenced in.", "Check fire, check fire."):
        b2, ln2 = _line_beat("ok", [ok])
        assert "callsign_first" not in codes(run(b2, ln2)), ok


def test_callsign_first_exempts_same_speaker_chain() -> None:
    b = [
        beat("a", {"event": "timer", "after_sec": 10}, "Python, Rook, nine-line follows."),
        beat("b", {"event": "beat.fired", "beat": "a"}, "From the village, go south."),
    ]
    assert "callsign_first" not in codes(run(b))


def test_banned_phrases() -> None:
    b, ln = _line_beat("x", ["Python, Rook, copy that."])
    assert "banned_phrases" in codes(run(b, ln))
    b2, ln2 = _line_beat("x", ["Python, Rook, hit! hit!"])
    assert "banned_phrases" in codes(run(b2, ln2))
    b3, ln3 = _line_beat("x", ["Python, Rook, copy, push."])
    assert "banned_phrases" not in codes(run(b3, ln3))


@pytest.mark.parametrize(
    "text",
    [
        "Python, Magic, group bulls one-four-zero, twelve.",
        "Python, Magic, BRAA one-eight-three for ten, hot.",
        "Python, Two, tally the friendlies north.",
        "Python, Two, visual bandits, two o'clock.",
    ],
)
def test_brevity_misuse_fires(text: str) -> None:
    b, ln = _line_beat("x", [text])
    assert "brevity_misuse" in codes(run(b, ln))


def test_brevity_misuse_quiet_and_aircrew_rule() -> None:
    b, ln = _line_beat("x", ["Python, Magic, group bullseye one-four-zero, twelve, hot."])
    assert "brevity_misuse" not in codes(run(b, ln))
    bible = make_bible()
    b2, ln2 = _line_beat("x", ["Python, Magic, say bingo."], speaker="awacs")
    assert "brevity_misuse" in codes(run(b2, ln2, bible=bible))
    b3, ln3 = _line_beat("x", ["Python, Two, bingo."], speaker="pike")
    assert "brevity_misuse" not in codes(run(b3, ln3, bible=bible))


def test_variants_too_similar() -> None:
    same = ["Python, Rook, window open, push now.", "Python, Rook, window open, push now."]
    b, ln = _line_beat("x", same)
    assert "variants_too_similar" in codes(run(b, ln))
    diff = ["Python, Rook, window open, push now.", "Python, Rook. Cyclops is inbound, go."]
    b2, ln2 = _line_beat("x", diff)
    assert "variants_too_similar" not in codes(run(b2, ln2))


def test_too_few_variants() -> None:
    two = ["Python, Rook, one.", "Python, Rook, second thing here."]
    b, ln = _line_beat("x", two, once=False)
    assert "too_few_variants" in codes(run(b, ln))
    three = [*two, "Python, Rook, a third different call."]
    b2, ln2 = _line_beat("x", three, once=False)
    assert "too_few_variants" not in codes(run(b2, ln2))
    b3, ln3 = _line_beat("x", two)  # once: true
    assert "too_few_variants" not in codes(run(b3, ln3))


def test_reaction_no_cooldown() -> None:
    b = [beat("hit", {"event": "unit.hit"}, "Python, Two, hit.", once=False)]
    assert "reaction_no_cooldown" in codes(run(b))
    b2 = [beat("hit", {"event": "unit.hit"}, "Python, Two, hit.", once=False, cooldown_sec=60)]
    assert "reaction_no_cooldown" not in codes(run(b2))


def test_no_generic_fallback_is_info() -> None:
    gated = [
        beat("hit_a", {"event": "unit.hit"}, "Python, Two, hit.", requires={"flags": ["a"]}),
        beat("hit_b", {"event": "unit.hit"}, "Python, Two, hit.", requires={"flags": ["b"]}),
    ]
    issues = run(gated)
    assert "no_generic_fallback" in codes(issues, "info")
    generic = [*gated, beat("hit_any", {"event": "unit.hit"}, "Python, Two, you're hit.")]
    assert "no_generic_fallback" not in codes(run(generic))


# ---- density ----------------------------------------------------------------------------------


def test_radio_density_shared_trigger() -> None:
    four = [beat(f"b{n}", {"event": "flag", "flag": "go"}, "Python, Rook, go.") for n in range(4)]
    assert "radio_density" in codes(run(four))
    assert "radio_density" not in codes(run(four[:3]))


def test_radio_density_window_uses_manifest_durations() -> None:
    bs: list[dict[str, Any]] = []
    ln: list[dict[str, Any]] = []
    for n in range(3):
        b, lx = _line_beat(
            f"c{n}", ["Python, Rook, short."], {"event": "timer", "after_sec": 10 + n}
        )
        bs += b
        ln += lx
    long_audio = MissionDocs(durations={f"c{n}_v1": 10.0 for n in range(3)})
    assert "radio_density" in codes(run(bs, ln, docs=long_audio))
    short_audio = MissionDocs(durations={f"c{n}_v1": 3.0 for n in range(3)})
    assert "radio_density" not in codes(run(bs, ln, docs=short_audio))


# ---- qualities --------------------------------------------------------------------------------


def test_quality_swing_beats() -> None:
    b = [
        beat("a", {"event": "timer", "after_sec": 10}, effects={"quality_deltas": {"trust": 2}}),
        beat("b", {"event": "timer", "after_sec": 20}, effects={"quality_deltas": {"trust": 1}}),
    ]
    assert "quality_swing" in codes(run(b))
    b2 = [
        beat("a", {"event": "timer", "after_sec": 10}, effects={"quality_deltas": {"trust": 1}}),
        beat("b", {"event": "timer", "after_sec": 20}, effects={"quality_deltas": {"trust": -2}}),
    ]
    assert "quality_swing" not in codes(run(b2))
    rep = [beat("r", {"event": "unit.hit"}, once=False, effects={"quality_deltas": {"trust": 1}})]
    assert "quality_swing" in codes(run(rep))


@pytest.mark.parametrize(
    ("text", "swing"),
    [
        ("+1 if a; +1 more if b; +1 more if c", 3),
        ("+2 if >= 6 vehicles arrive; +1 if 3-5; 0 otherwise", 2),
        ("+1 per civilian hit, max +2", 2),
        ("+1 per civilian hit", 5),
        ("set to 0 if both destroyed", 3),
        ("-2 if fratricide; -1 if not held; +1 if held", 2),
    ],
)
def test_effect_swing(text: str, swing: int) -> None:
    assert _effect_swing(text, 0, 3 if text.startswith("set") else 5) == swing


# ---- briefing / kneeboard / transit -----------------------------------------------------------


def test_briefing_threat_mismatch() -> None:
    threats = [{"id": "town_guns", "role": "aaa", "area": "town", "hidden_on_map": False}]
    sp = spec(threats=threats)
    missing = run(sp=sp, docs=MissionDocs(briefing="# B\nNothing about guns... wait."))
    # "guns" is in the id tokens; use a briefing without any match
    missing = run(sp=sp, docs=MissionDocs(briefing="# B\nQuiet sector, no known defences."))
    assert "briefing_threat_mismatch" in codes(missing, "error")
    ok = run(sp=sp, docs=MissionDocs(briefing="# B\nZU-23 at the town edge."))
    assert "briefing_threat_mismatch" not in codes(ok)
    hidden = spec(threats=[{**threats[0], "hidden_on_map": True}])
    assert "briefing_threat_mismatch" not in codes(run(sp=hidden, docs=MissionDocs(briefing="#")))


def test_briefing_threat_mismatch_telegraphed_encounter() -> None:
    b = [beat("warn", {"event": "timer", "after_sec": 30}, "Python, Rook, SAM.")]
    sp = spec(encounters=[_enc("popup", "ambush_sam", "sam", telegraph_beat="warn")])
    assert "briefing_threat_mismatch" in codes(run(b, sp=sp, docs=MissionDocs(briefing="# x")))
    brief = MissionDocs(briefing="# x\nPossible SA-8 pop-up.")
    assert "briefing_threat_mismatch" not in codes(run(b, sp=sp, docs=brief))


def test_briefing_missing_sections() -> None:
    issues = run(docs=MissionDocs(briefing="# B\n## 1. Situation\nStuff."))
    found = [i for i in issues if i.code == "briefing_missing_sections"]
    assert found and "stakes" in found[0].problem and "## 2." in found[0].problem
    assert "briefing_missing_sections" not in codes(run(docs=MissionDocs(briefing=GOOD_BRIEFING)))


def test_kneeboard_contradiction_laser_is_error() -> None:
    kb = GOOD_KNEEBOARD.replace("1688", "1511")
    issues = run(docs=MissionDocs(briefing=GOOD_BRIEFING, kneeboard=kb))
    assert "kneeboard_contradiction" in codes(issues, "error")


def test_kneeboard_missing_frequency_is_warning() -> None:
    brief = GOOD_BRIEFING + "| Tanker | 276.1 AM |\n"
    issues = run(docs=MissionDocs(briefing=brief, kneeboard=GOOD_KNEEBOARD))
    assert "kneeboard_contradiction" in codes(issues, "warning")
    assert "kneeboard_contradiction" not in codes(issues, "error")
    ok = run(docs=MissionDocs(briefing=GOOD_BRIEFING, kneeboard=GOOD_KNEEBOARD))
    assert "kneeboard_contradiction" not in codes(ok)


def test_kneeboard_too_long() -> None:
    long_kb = GOOD_KNEEBOARD + "\n".join(f"line {n}" for n in range(30))
    assert "kneeboard_too_long" in codes(run(docs=MissionDocs(kneeboard=long_kb)))
    no_comms = "# K\nJust notes."
    assert "kneeboard_too_long" in codes(run(docs=MissionDocs(kneeboard=no_comms)))
    assert "kneeboard_too_long" not in codes(run(docs=MissionDocs(kneeboard=GOOD_KNEEBOARD)))


def _plan(ip_km: float, variant: str = "ramp") -> dict[str, Any]:
    start_action = "From Parking Area" if variant == "ramp" else "Turning Point"
    return {
        "groups": [
            {
                "name": "Python 1",
                "category": "plane",
                "client": True,
                "variant": variant,
                "route": [
                    {"x": 0.0, "y": 0.0, "speed_kmh": 0.0, "action": start_action},
                    {"x": ip_km * 1000, "y": 0.0, "speed_kmh": 800.0, "name": "IP"},
                    {"x": ip_km * 1000 + 50_000, "y": 0.0, "speed_kmh": 800.0, "name": "TGT1"},
                ],
            }
        ]
    }


def test_transit_too_long() -> None:
    assert "transit_too_long" in codes(run(docs=MissionDocs(plan=_plan(600))))  # 45 min
    assert "transit_too_long" not in codes(run(docs=MissionDocs(plan=_plan(200))))  # 15 min
    assert "transit_too_long" in codes(run(docs=MissionDocs(plan=_plan(200, "air"))))
    assert "transit_too_long" not in codes(run(docs=MissionDocs(plan=_plan(80, "air"))))


# ---- arc --------------------------------------------------------------------------------------


def _arc_mission(mid: str, **kw: Any) -> dict[str, Any]:
    return {
        "id": mid,
        "title": mid,
        "mission_type": "SEAD",
        "dramatic_question": "?",
        "synopsis": "Fly.",
        **kw,
    }


def make_arc(
    missions: list[dict[str, Any]], qualities: list[dict[str, Any]] | None = None, acts: int = 1
) -> CampaignArc:
    if acts == 1:
        act_list = [{"id": "act1", "title": "A", "summary": "s", "missions": missions}]
    else:
        act_list = [
            {"id": f"act{n}", "title": "A", "summary": "s", "missions": [m]}
            for n, m in enumerate(missions, 1)
        ]
    return CampaignArc.model_validate(
        {"title": "T", "logline": "L", "acts": act_list, "qualities": qualities or []}
    )


def test_failure_dead_end_is_error(tmp_path: Path) -> None:
    arc = make_arc([_arc_mission("m01-a"), _arc_mission("m02-b")])
    # next mission not designed yet: it may still read the flag, so only a warning
    dead = [i for i in lint_arc(arc) if i.code == "failure_dead_end"]
    assert dead and dead[0].severity == "warning" and "m01-a" in dead[0].problem
    # the last mission is not a dead end (the campaign ends)
    assert not any("m02-b" in i.path for i in dead)
    # designed next mission that never reads it: error
    m2 = tmp_path / "missions" / "m02-b"
    m2.mkdir(parents=True)
    (m2 / "briefing.md").write_text("# Next. Nothing about the last sortie.", encoding="utf-8")
    dead = [i for i in lint_arc(arc, tmp_path) if i.code == "failure_dead_end"]
    assert dead and dead[0].severity == "error"


def test_failure_dead_end_quiet_with_branch_or_next_mission_reading_it(tmp_path: Path) -> None:
    branch = {"when": {"flags": ["m01_player_lost"]}, "goto": "m01-a"}
    arc = make_arc([_arc_mission("m01-a", branches=[branch]), _arc_mission("m02-b")])
    assert "failure_dead_end" not in codes(lint_arc(arc))
    arc2 = make_arc([_arc_mission("m01-a"), _arc_mission("m02-b")])
    m2 = tmp_path / "missions" / "m02-b"
    m2.mkdir(parents=True)
    (m2 / "briefing.md").write_text("If m01_player_lost: a new jet.", encoding="utf-8")
    assert "failure_dead_end" not in codes(lint_arc(arc2, tmp_path))


def test_failure_dead_end_scoped_in_lint_mission(tmp_path: Path) -> None:
    arc = make_arc([_arc_mission("m01-test"), _arc_mission("m02-b")])
    assert "failure_dead_end" in codes(run(docs=MissionDocs(arc=arc)), "warning")
    m2 = tmp_path / "missions" / "m02-b"
    m2.mkdir(parents=True)
    (m2 / "briefing.md").write_text("# Next", encoding="utf-8")
    issues = run(docs=MissionDocs(arc=arc, campaign_dir=tmp_path))
    assert "failure_dead_end" in codes(issues, "error")


def test_branch_never_rejoins() -> None:
    arc = make_arc(
        [
            _arc_mission("m01-a", branches=[{"when": {"flags": ["x"]}, "goto": "m01b-side"}]),
            _arc_mission(
                "m02-b", branches=[{"when": {"flags": ["m02_player_lost"]}, "goto": "m02-b"}]
            ),
            _arc_mission("m01b-side", optional=True),
        ]
    )
    assert "branch_never_rejoins" in codes(lint_arc(arc))
    arc2 = make_arc(
        [
            _arc_mission("m01-a", branches=[{"when": {"flags": ["x"]}, "goto": "m01b-side"}]),
            _arc_mission("m01b-side", optional=True),
            _arc_mission("m02-b"),
        ]
    )
    assert "branch_never_rejoins" not in codes(lint_arc(arc2))


def _write_campaign(tmp: Path, intensities: list[str]) -> list[dict[str, Any]]:
    missions = []
    for n, inten in enumerate(intensities, 1):
        mid = f"m0{n}-x"
        d = copy.deepcopy(BASE_SPEC)
        d["id"] = mid
        d["dynamic"]["director"] = {"intensity": inten}
        md = tmp / "missions" / mid
        md.mkdir(parents=True)
        (md / "mission-spec.yaml").write_text(yaml.safe_dump(d), encoding="utf-8")
        missions.append(_arc_mission(mid))
    return missions


def test_intensity_streak(tmp_path: Path) -> None:
    arc = make_arc(_write_campaign(tmp_path, ["intense", "intense", "intense"]))
    found = [i for i in lint_arc(arc, tmp_path) if i.code == "intensity_streak"]
    assert any("third intense" in i.problem for i in found)
    assert any("no calm mission" in i.problem for i in found)


def test_intensity_streak_quiet(tmp_path: Path) -> None:
    arc = make_arc(_write_campaign(tmp_path, ["calm", "intense", "intense"]))
    assert "intensity_streak" not in codes(lint_arc(arc, tmp_path))


def test_quality_unmoved_and_unread() -> None:
    q = [{"id": "trust", "description": "d"}]
    arc = make_arc([_arc_mission("m01-a")], q)
    assert {"quality_unmoved", "quality_unread"} <= codes(lint_arc(arc))
    used = make_arc(
        [
            _arc_mission(
                "m01-a",
                quality_effects={"trust": "+1 if ok"},
                branches=[
                    {"when": {"qualities": [{"quality": "trust", "value": 2}]}, "goto": "m01-a"}
                ],
            )
        ],
        q,
    )
    assert not {"quality_unmoved", "quality_unread"} & codes(lint_arc(used))


def test_arc_quality_swing() -> None:
    q = [{"id": "trust", "description": "d", "min": 0, "max": 5}]
    big = make_arc([_arc_mission("m01-a", quality_effects={"trust": "+2 if a; +1 more if b"})], q)
    assert "quality_swing" in codes(lint_arc(big))
    small = make_arc([_arc_mission("m01-a", quality_effects={"trust": "+2 if a; +1 if b"})], q)
    assert "quality_swing" not in codes(lint_arc(small))


# ---- files ------------------------------------------------------------------------------------


def test_load_mission_docs(tmp_path: Path) -> None:
    camp = tmp_path / "camp"
    md = camp / "missions" / "m01-test"
    (md / "voice").mkdir(parents=True)
    (md / "out").mkdir()
    (md / "briefing.md").write_text(GOOD_BRIEFING, encoding="utf-8")
    (md / "kneeboard.md").write_text(GOOD_KNEEBOARD, encoding="utf-8")
    (md / "voice" / "manifest.json").write_text(
        json.dumps({"a_v1": {"dur_sec": 4.2}, "bad": {"dur_sec": None}}), encoding="utf-8"
    )
    (md / "out" / "plan.json").write_text(json.dumps(_plan(600)), encoding="utf-8")
    arc = {
        "title": "T",
        "logline": "L",
        "acts": [{"id": "a", "title": "A", "summary": "s", "missions": [_arc_mission("m01-test")]}],
    }
    (camp / "arc.yaml").write_text(yaml.safe_dump(arc), encoding="utf-8")
    docs = load_mission_docs(md)
    assert docs.briefing and docs.kneeboard
    assert docs.durations == {"a_v1": 4.2}
    assert docs.plan is not None and docs.arc is not None
    assert docs.campaign_dir == camp
    issues = lint_mission_dir(md, spec(), BeatSheet(), VoiceLineSet())
    assert "transit_too_long" in codes(issues)


def test_load_mission_docs_none_and_missing(tmp_path: Path) -> None:
    assert load_mission_docs(None) == MissionDocs()
    docs = load_mission_docs(tmp_path)
    assert docs.briefing is None and docs.plan is None and docs.durations == {}


# ---- real campaigns ---------------------------------------------------------------------------


def _load(path: Path) -> Any:
    return yaml.safe_load(path.read_text(encoding="utf-8"))


@pytest.mark.parametrize("slug", ["viper-detachment", "dustoff-valley"])
def test_real_campaigns_lint(slug: str) -> None:
    camp = CAMPAIGNS / slug
    if not camp.is_dir():
        pytest.skip(f"{camp} missing")
    bible = StoryBible.model_validate(_load(camp / "bible.yaml"))
    for md in sorted((camp / "missions").iterdir()):
        if not (md / "mission-spec.yaml").is_file():
            continue
        issues = lint_mission_dir(
            md,
            MissionSpec.model_validate(_load(md / "mission-spec.yaml")),
            BeatSheet.model_validate(_load(md / "beats.yaml") or []),
            VoiceLineSet.model_validate(_load(md / "lines.yaml") or []),
            bible,
        )
        assert all(i.code in RULES for i in issues)
        if md.name == "m01-broken-umbrella":
            assert [i for i in issues if i.severity == "error"] == []
    lint_arc(CampaignArc.model_validate(_load(camp / "arc.yaml")), camp)
