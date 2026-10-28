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
