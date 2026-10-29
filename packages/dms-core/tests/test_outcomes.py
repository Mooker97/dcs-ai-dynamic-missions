"""dms_core.outcomes: dcs.log sessions -> MissionOutcome -> Qualities (synthetic logs only)."""

from __future__ import annotations

import os
import random
import shutil
from pathlib import Path

import pytest
import yaml
from dms_core import outcomes as oc
from dms_core.schemas import CampaignArc, MissionOutcome, Qualities

ROOT = Path(__file__).resolve().parents[3]
FIXTURE = ROOT / "tests" / "fixtures" / "dcs-logs" / "multi-session-dcs.log.txt"
ARC_PATH = ROOT / "campaigns" / "dustoff-valley" / "arc.yaml"

TS = "2026-10-28 10:00:00.000"


def line(level: str, msg: str, ts: str = TS) -> str:
    return f"{ts} {level:<7} SCRIPTING (Main): {msg}\n"


def banner(mission: str, ts: str = TS) -> str:
    return line("INFO", f"[DMS][Init] DMS 0.3.0 started: mission={mission} seed=1 debug=false", ts)


def out(payload: str, ts: str = TS) -> str:
    return line("INFO", f"[DMS.OUTCOME] {payload}", ts)


@pytest.fixture(scope="module")
def arc() -> CampaignArc:
    return CampaignArc.model_validate(yaml.safe_load(ARC_PATH.read_text(encoding="utf-8")))


def test_fixture_sessions() -> None:
    sessions = oc.parse_sessions(FIXTURE.read_text(encoding="utf-8"))
    assert [s.mission_id for s in sessions] == [
        "m01-first-light",
        "m01-first-light",
        "m02-cracking-kirikhan",
    ]
    first, second, _ = sessions
    assert first.records[-1].result == "failure"
    assert len(second.records) == 2
    assert [m.reason.split(":")[0] for m in second.malformed] == [
        "invalid JSON",
        "payload is not a JSON object",
    ]
    levels = [(i.level, i.module) for i in second.issues]
    assert levels == [("WARNING", "Spawner"), ("ERROR", "safeCall")]
    assert "stack traceback" in second.issues[1].message
    assert "in function 'spawn'" in second.issues[1].message


def test_latest_session_wins_and_prefix_match() -> None:
    for wanted in ("m01-first-light", "m01"):
        path, s = oc.find_mission_session([FIXTURE], wanted)
        assert path == FIXTURE and s.records[-1].result == "success"
    o = oc.build_outcome(s, "m01-first-light", FIXTURE)
    assert o.kind == "summary" and o.result == "success"
    assert o.outcomes == {
        "on_station": True,
        "hidden_aa_found": True,
        "kills": 3,
        "patrol_complete": True,
    }
    assert o.quality_deltas == {"civilian_harm": 0, "intel": 2, "trust": 1}
    assert o.extra["ended"] is True and o.extra["source"] == "dcs_log"
    assert o.extra["beats_fired"][-1] == "patrol_complete"
    assert o.extra["session_start"] == "2026-10-27 19:15:00.000"
    assert len(o.extra["log_errors"]) == 1 and len(o.extra["malformed_lines"]) == 2
    MissionOutcome.model_validate(o.model_dump(mode="json"))


def test_missing_mission_is_a_clear_error() -> None:
    with pytest.raises(oc.DebriefError, match=r"no \[DMS.OUTCOME\] lines for mission 'm04'") as e:
        oc.find_mission_session([FIXTURE], "m04")
    assert "m02-cracking-kirikhan" in str(e.value)
    with pytest.raises(oc.DebriefError, match=r"no dcs\.log found"):
        oc.find_mission_session([], "m01")


def test_banner_without_outcome_lines(tmp_path: Path) -> None:
    log = tmp_path / "dcs.log"
    log.write_text(
        banner("m05-x") + line("ERROR", "[DMS][Narrative] boom") + out("{bad"), encoding="utf-8"
    )
    with pytest.raises(oc.DebriefError, match="wrote no valid") as e:
        oc.find_mission_session([log], "m05")
    assert "boom" in str(e.value) and "1 malformed" in str(e.value)


def test_restart_without_banner_splits_on_time() -> None:
    text = (
        out('{"missionId":"m01","kind":"update","t":100,"outcome":{"a":true}}')
        + out('{"missionId":"m01","kind":"update","t":20,"outcome":{"b":true}}')
        + "garbage line with no timestamp\n"
    )
    sessions = oc.parse_sessions(text)
    assert len(sessions) == 2
    _, s = oc.find_mission_session([Path("x")], "m01", texts={Path("x"): text})
    assert s.records[0].outcomes == {"b": True}
    o = oc.build_outcome(s, "m01", None)
    assert o.result is None and o.extra["ended"] is False


def test_old_log_fallback_and_default_paths(tmp_path: Path) -> None:
    stable = tmp_path / "DCS" / "Logs"
    beta = tmp_path / "DCS.openbeta" / "Logs"
    stable.mkdir(parents=True)
    beta.mkdir(parents=True)
    (stable / "dcs.log").write_text(banner("m02-y") + out('{"missionId":"m02-y","t":1}'))
    (stable / "dcs.log.old").write_text(banner("m01-z") + out('{"missionId":"m01-z","t":1}'))
    (beta / "dcs.log").write_text("", encoding="utf-8")
    os.utime(beta / "dcs.log", (1_000_000, 1_000_000))
    paths = oc.default_log_paths(tmp_path)
    assert paths == [stable / "dcs.log", stable / "dcs.log.old", beta / "dcs.log"]
    path, s = oc.find_mission_session(paths, "m01")
    assert path == stable / "dcs.log.old" and s.mission_id == "m01-z"
    assert oc.explicit_log_paths(stable) == [stable / "dcs.log", stable / "dcs.log.old"]
    assert oc.default_log_paths(tmp_path / "nowhere") == []


def _outcome(**kw: object) -> MissionOutcome:
    return MissionOutcome.model_validate({"mission_id": "m01-first-light", **kw})


def test_apply_outcome(arc: CampaignArc) -> None:
    state = Qualities(values={"intel": 4, "trust": 3}, flags={"m00_x": True, "m01_failure": True})
    o = _outcome(
        result="success",
        outcomes={"patrol_complete": True, "kills": 2, "civilians_hit": 0, "note": "x"},
        quality_deltas={"intel": 2, "trust": 1, "civilian_harm": 0, "morale": 1},
    )
    up = oc.apply_outcome(state, o, "m01-first-light", arc)
    assert up.state.values["intel"] == 5  # clamped to max 5
    assert up.state.values["trust"] == 3  # clamped to max 3
    assert up.state.values["fob_supply"] == 1  # missing -> initial
    assert {c.quality for c in up.changes} == {"intel", "trust"}
    assert "clamped" in up.changes[0].reason
    assert any("morale" in w for w in up.warnings)
    f = up.state.flags
    assert f["m00_x"] and f["m01_patrol_complete"] and f["m01_kills"] and f["m01_note"]
    assert f["m01_civilians_hit"] is False
    assert f["m01_success"] is True and f["m01_failure"] is False
    assert up.state.outcomes["m01-first-light"]["kills"] == 2
    assert up.state.updated_after == "m01-first-light"
    assert up.next_mission == "m02-cracking-kirikhan" and "branch 3" in up.next_reason
    assert state.values == {"intel": 4, "trust": 3}  # input untouched


def test_branches(arc: CampaignArc) -> None:
    lost = oc.apply_outcome(
        Qualities(),
        _outcome(result="failure", outcomes={"player_lost": True}),
        "m01-first-light",
        arc,
    )
    assert lost.next_mission == "m01-first-light"
    both = _outcome(
        result="success",
        outcomes={"reyhanli_aaa_destroyed": True, "kirikhan_aaa_destroyed": True},
    )
    assert oc.apply_outcome(Qualities(), both, "m01-first-light", arc).next_mission == "m03-dustoff"
    # m02 has only a replay branch -> falls through to next non-optional (m03)
    nxt, why = oc.choose_next_mission(arc, "m02-cracking-kirikhan", {}, {})
    assert nxt == "m03-dustoff" and why == "next in order"
    no_result = oc.apply_outcome(Qualities(), _outcome(), "m01-first-light", None)
    assert no_result.next_mission is None and any("no result" in w for w in no_result.warnings)


def test_requires_chance_is_seeded() -> None:
    from dms_core.schemas import Requires

    req = Requires(chance=50)
    a = [oc.requires_hold(req, {}, {}, rng=random.Random(7))[1] for _ in range(2)]
    assert a[0] == a[1] and "rolled" in a[0]
    q = Requires.model_validate({"qualities": {"trust": ">=2"}, "beats_fired": ["x"]})
    assert oc.requires_hold(q, {}, {"trust": 1}) == (False, "trust=1 fails >= 2")
    assert oc.requires_hold(q, {}, {"trust": 2}, beats=["x"])[0] is True


def test_write_and_guard(tmp_path: Path, arc: CampaignArc) -> None:
    camp = tmp_path / "camp"
    camp.mkdir()
    shutil.copy(ARC_PATH, camp / "arc.yaml")
    loaded_arc, state = oc.load_debrief_inputs(camp)
    assert loaded_arc is not None and state.values["enemy_aa"] == 2  # seeded from arc
    path, s = oc.find_mission_session([FIXTURE], "m01")
    o = oc.build_outcome(s, "m01-first-light", path)
    assert not oc.already_debriefed(camp, "m01-first-light", o)
    up = oc.apply_outcome(state, o, "m01-first-light", loaded_arc)
    written = oc.write_debrief(camp, "m01-first-light", o, up)
    assert [p.name for p in written] == ["m01.yaml", "qualities.yaml"]
    q = Qualities.model_validate(yaml.safe_load(written[1].read_text(encoding="utf-8")))
    assert q.values["intel"] == 2 and q.next_mission == "m02-cracking-kirikhan"
    MissionOutcome.model_validate(yaml.safe_load(written[0].read_text(encoding="utf-8")))
    assert oc.already_debriefed(camp, "m01-first-light", o)


def test_parse_quality_effect() -> None:
    cl, un = oc.parse_quality_effect(
        "-1 if sa6_radar_destroyed; -1 more if sa8_destroyed and sa6_launchers_destroyed >= 2 "
        "(min 0); set to 0 if a and b; -1 if only one of them"
    )
    assert [(c.op, c.amount) for c in cl] == [("add", -1), ("add", -1), ("set", 0)]
    assert un == ["-1 if only one of them"]
    facts = {"sa8_destroyed": True, "sa6_launchers_destroyed": 2}
    assert not cl[0].holds(facts) and cl[1].holds(facts)
    assert not cl[1].holds({"sa8_destroyed": True, "sa6_launchers_destroyed": 1})
    (neg,), _ = oc.parse_quality_effect("+1 if patrol_complete and not civilians_hit")
    assert neg.holds({"patrol_complete": True, "civilians_hit": 0})
    assert not neg.holds({"patrol_complete": True, "civilians_hit": 2})
    (alt,), _ = oc.parse_quality_effect("+1 if hidden_aa_found or staging_spotted (max +2)")
    assert alt.holds({"staging_spotted": "yes"}) and not alt.holds({})
    assert oc.parse_quality_effect("+1 per civilian hit, max +2") == (
        [],
        ["+1 per civilian hit, max +2"],
    )


def test_arc_effects_applied_clamped_and_not_doubled(arc: CampaignArc) -> None:
    o = _outcome(
        result="success",
        outcomes={"patrol_complete": True, "civilians_hit": False},
        quality_deltas={"intel": 1},
    )
    state = Qualities(values={"trust": 3, "intel": 1})
    up = oc.apply_outcome(state, o, "m01-first-light", arc)
    # intel moved by the beats -> its arc effect is skipped; trust +1 clamps at max 3 (no change)
    assert up.state.values["intel"] == 2
    assert up.state.values["trust"] == 3
    assert any("'intel' not applied" in w for w in up.warnings)
    assert not any(c.reason.startswith("arc") and c.quality == "trust" for c in up.changes)
    low = oc.apply_outcome(Qualities(values={"trust": 0}), o, "m01-first-light", arc)
    trust = [c for c in low.changes if c.quality == "trust"]
    assert trust and trust[0].after == 1 and trust[0].reason.startswith("arc quality_effects")
    off = oc.apply_outcome(
        Qualities(values={"trust": 0}), o, "m01-first-light", arc, arc_effects=False
    )
    assert off.state.values["trust"] == 0


def test_continuity_entry_appends(tmp_path: Path, arc: CampaignArc) -> None:
    o = _outcome(result="failure", outcomes={"player_lost": True})
    up = oc.apply_outcome(Qualities(), o, "m01-first-light", arc)
    entry = oc.continuity_entry("m01-first-light", o, up, "2026-10-29")
    assert entry.startswith("### 2026-10-29 — dms debrief — m01-first-light flown (failure)")
    assert "m01_player_lost" in entry and "Next: m01-first-light" in entry
    (tmp_path / "continuity.md").write_text("# C\n\nold entry", encoding="utf-8")
    p = oc.append_continuity(tmp_path, entry)
    text = p.read_text(encoding="utf-8")
    assert text.startswith("# C\n\nold entry\n\n### 2026-10-29")
    fresh = tmp_path / "fresh"
    fresh.mkdir()
    assert oc.append_continuity(fresh, entry).read_text(encoding="utf-8") == entry


# ---- review fixes: guard hash, rollback, missing keys, unended, parentheticals, continuity ------


def _flight_log(tmp_path: Path, name: str = "dcs.log") -> Path:
    p = tmp_path / name
    p.write_text(
        banner("m01-first-light")
        + out(
            '{"mission_id":"m01-first-light","t":10,"kind":"update","outcomes":'
            '{"patrol_complete":true}}'
        )
        + out(
            '{"mission_id":"m01-first-light","t":20,"kind":"end","result":"success",'
            '"outcomes":{"patrol_complete":true,"civilians_hit":false}}'
        ),
        encoding="utf-8",
    )
    return p


def test_guard_survives_log_rotation_and_force_rolls_back(tmp_path: Path, arc: CampaignArc) -> None:
    camp = tmp_path / "camp"
    camp.mkdir()
    shutil.copy(ARC_PATH, camp / "arc.yaml")
    log = _flight_log(tmp_path)
    _, state = oc.load_debrief_inputs(camp)
    path, s = oc.find_mission_session([log], "m01")
    o = oc.build_outcome(s, "m01-first-light", path)
    assert len(o.extra["session_hash"]) == 16
    up = oc.apply_outcome(state, o, "m01-first-light", arc)
    o = o.model_copy(
        update={
            "extra": {
                **o.extra,
                "quality_changes": [c.to_dict() for c in up.changes],
                "flags_set": up.flags_set,
            }
        }
    )
    entry = oc.continuity_entry("m01-first-light", o, up, "2026-10-29")
    oc.commit_debrief(camp, "m01-first-light", o, up, entry)

    # the same flight read from the rotated dcs.log.old (different log_file) is still caught
    rotated = log.rename(tmp_path / "dcs.log.old")
    path2, s2 = oc.find_mission_session([rotated], "m01")
    o2 = oc.build_outcome(s2, "m01-first-light", path2)
    assert o2.extra["log_file"] != o.extra["log_file"]
    assert oc.already_debriefed(camp, "m01-first-light", o2)
    # a different flight (other records) at the same timestamp is not
    other = o2.model_copy(update={"extra": {**o2.extra, "session_hash": "0" * 16}})
    assert not oc.already_debriefed(camp, "m01-first-light", other)

    # --force: roll back the previous changes, then re-apply -> same values as the first time
    _, saved = oc.load_debrief_inputs(camp)
    rolled, notes = oc.rollback_previous(camp, "m01-first-light", saved, arc)
    assert notes and rolled.values == state.values
    assert not any(k.startswith("m01_") for k in rolled.flags)
    again = oc.apply_outcome(rolled, o2, "m01-first-light", arc)
    assert again.state.values == up.state.values
    entry2 = oc.continuity_entry("m01-first-light", o2, again, "2026-10-30")
    oc.commit_debrief(camp, "m01-first-light", o2, again, entry2)
    text = (camp / "continuity.md").read_text(encoding="utf-8")
    assert text.count("dms debrief — m01-first-light flown") == 1  # replaced, not duplicated
    assert "### 2026-10-30" in text and "### 2026-10-29" not in text


def test_missing_condition_keys_warn_and_result_facts(arc: CampaignArc) -> None:
    o = _outcome(result="success", outcomes={"patrol_complete": True}, extra={"ended": True})
    up = oc.apply_outcome(Qualities(), o, "m01-first-light", arc)
    missing = [w for w in up.warnings if "not in this flight's outcome facts" in w]
    assert any("civilians_hit" in w for w in missing)
    assert any("hidden_aa_found, staging_spotted" in w for w in missing)
    facts = oc.effect_facts(o)
    assert facts["success"] is True and facts["failure"] is False and facts["result"] == "success"
    (c,), _ = oc.parse_quality_effect("+1 if success and not failure")
    assert c.holds(facts)
    assert "result" not in oc.effect_facts(_outcome())


def test_unended_flight_skips_arc_effects(arc: CampaignArc) -> None:
    facts = {"patrol_complete": True, "civilians_hit": False}
    unended = _outcome(outcomes=facts, quality_deltas={"morale": 1}, extra={"ended": False})
    up = oc.apply_outcome(Qualities(), unended, "m01-first-light", arc)
    assert any("flight did not end" in w for w in up.warnings)
    assert not any(c.reason.startswith("arc") for c in up.changes)
    forced = oc.apply_outcome(Qualities(), unended, "m01-first-light", arc, force_arc_effects=True)
    assert any(c.reason.startswith("arc") for c in forced.changes)
    no_end_line = _outcome(result="success", outcomes=facts, extra={"ended": False})
    assert any(
        "did not end" in w
        for w in oc.apply_outcome(Qualities(), no_end_line, "m01-first-light", arc).warnings
    )


def test_dropped_parentheticals_and_reserved_words() -> None:
    notes: list[str] = []
    cl, _ = oc.parse_quality_effect(
        "+1 if a (max +2); -1 if b (only if c); +1 if d (the bridge)", notes
    )
    assert len(cl) == 3
    assert len(notes) == 2 and "(max +2)" in notes[0] and "(only if c)" in notes[1]
    for bad in ("+1 if not", "+1 if or", "+1 if a and or", "+1 if and >= 2", "+1 if not or"):
        cl, un = oc.parse_quality_effect(bad)
        assert cl == [] and un == [bad], bad
    assert oc.parse_condition("not") is None and oc.parse_condition("or") is None


def test_continuity_keeps_crlf(tmp_path: Path, arc: CampaignArc) -> None:
    (tmp_path / "continuity.md").write_bytes(b"# C\r\n\r\nold entry\r\n")
    o = _outcome(result="failure", outcomes={"player_lost": True}, extra={"session_hash": "ab"})
    up = oc.apply_outcome(Qualities(), o, "m01-first-light", arc)
    entry = oc.continuity_entry("m01-first-light", o, up, "2026-10-29")
    oc.upsert_continuity(tmp_path, entry, "m01-first-light", o)
    oc.upsert_continuity(tmp_path, entry, "m01-first-light", o)  # idempotent
    raw = (tmp_path / "continuity.md").read_bytes()
    assert b"\n" not in raw.replace(b"\r\n", b"")  # every newline is CRLF
    assert raw.startswith(b"# C\r\n\r\nold entry\r\n\r\n### 2026-10-29")
    assert raw.count(b"dms debrief") == 1


def test_commit_order_guard_last(
    tmp_path: Path, arc: CampaignArc, monkeypatch: pytest.MonkeyPatch
) -> None:
    o = _outcome(result="success", outcomes={"patrol_complete": True}, extra={"ended": True})
    up = oc.apply_outcome(Qualities(), o, "m01-first-light", arc)
    entry = oc.continuity_entry("m01-first-light", o, up, "2026-10-29")
    real = oc._atomic_write
    order: list[str] = []

    def spy(p: Path, text: str, newline: str = "\n") -> None:
        order.append(p.name)
        real(p, text, newline)

    monkeypatch.setattr(oc, "_atomic_write", spy)
    oc.commit_debrief(tmp_path, "m01-first-light", o, up, entry)
    assert order == ["continuity.md", "qualities.yaml", "m01.yaml"]
