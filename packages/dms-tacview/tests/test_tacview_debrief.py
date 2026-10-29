from __future__ import annotations

import os
import zipfile
from pathlib import Path

import pytest
from dms_core.schemas import MissionOutcome
from dms_tacview import (
    TacviewFacts,
    default_tacview_dirs,
    find_newest_acmi,
    merge_acmi,
)
from dms_tacview.cli import load_points

FIX = Path(__file__).parent / "fixtures"
HOG = FIX / "hog_cas.txt.acmi"
VIPER = FIX / "viper_strike.txt.acmi"


def _outcome(**kw: object) -> MissionOutcome:
    base: dict[str, object] = {
        "mission_id": "m02-hog",
        "kind": "summary",
        "result": "success",
        "players": ["Mooker"],
        "outcomes": {"column_destroyed": True, "tv_player_kills": 99},
        "extra": {"session_hash": "abc123", "session_start": "2026-10-29 20:00:00"},
    }
    base.update(kw)
    return MissionOutcome.model_validate(base)


def _tv(o: MissionOutcome) -> TacviewFacts:
    return TacviewFacts.model_validate(o.extra["tacview"])


def test_merge_player_from_outcome_players() -> None:
    o = _outcome()
    e = merge_acmi(o, HOG, points=load_points(FIX / "hog_points.yaml"))
    tv = _tv(e)
    assert tv.error is None and tv.recording_time == "2026-10-29T20:00:00Z"
    p = tv.player
    assert p is not None
    # the heuristic would pick the AI (Hawg 2-1, seen first); outcome.players picks Mooker
    assert (p.object_id, p.pilot, p.selected_by) == ("101", "Mooker", "explicit")
    assert p.takeoffs == [10] and p.landings == [400] and p.landed and not p.destroyed
    assert p.min_alt_m == 30 and p.max_alt_m == 900
    assert [(w.weapon, w.count, w.hits) for w in tv.weapons_released] == [("Mk-82", 2, 1)]
    hit = [s for s in tv.shots if s.hit]
    assert [(s.weapon_id, s.target_id) for s in hit] == [("401", "301")]
    kills = [k for k in tv.kills if k.by_player]
    assert [(k.victim_id, k.weapon_id, k.killer_id, k.confidence) for k in kills] == [
        ("301", "401", "101", "medium")
    ]
    (zone,) = tv.time_over_target
    assert zone.name == "Column" and zone.entered is True
    assert zone.time_inside_s is not None and zone.time_inside_s > 0
    f = tv.facts
    assert f["tv_player_shots"] == 2 and f["tv_player_hits"] == 1 and f["tv_player_kills"] == 1
    assert f["tv_player_landed"] is True and f["tv_min_alt_m"] == 30
    assert f["tv_time_over_target_s"] == f["tv_column_time_inside_s"]
    # default: facts stay in extra.tacview, outcomes and the re-debrief guard are untouched
    assert e.outcomes == o.outcomes and not tv.merged_into_outcomes
    assert e.extra["session_hash"] == "abc123" and o.extra.get("tacview") is None
    MissionOutcome.model_validate(e.model_dump(mode="json"))


def test_merge_into_outcomes_never_overwrites() -> None:
    e = merge_acmi(_outcome(), HOG, merge_into_outcomes=True)
    assert _tv(e).merged_into_outcomes
    assert e.outcomes["tv_player_kills"] == 99  # Lua-reported key wins
    assert e.outcomes["tv_player_landed"] is True and e.outcomes["column_destroyed"] is True


def test_explicit_player_and_heuristic() -> None:
    e = merge_acmi(_outcome(players=[]), HOG)
    p = _tv(e).player
    assert p is not None and p.pilot == "Hawg 2-1"  # labelled heuristic pick
    assert p.selected_by == "heuristic_first_piloted_aircraft"
    e = merge_acmi(_outcome(players=[]), HOG, player="Hawg 1")
    p = _tv(e).player
    assert p is not None and p.object_id == "101"


def test_missing_player_and_bad_file(tmp_path: Path) -> None:
    e = merge_acmi(_outcome(), HOG, player="Nobody", merge_into_outcomes=True)
    tv = _tv(e)
    assert tv.player is None and tv.facts["tv_player_found"] is False
    assert any("no player aircraft" in w for w in tv.warnings)
    assert e.outcomes == _outcome().outcomes  # nothing merged without a player
    bad = tmp_path / "bad.zip.acmi"
    bad.write_bytes(b"PK\x03\x04garbage")
    tv = _tv(merge_acmi(_outcome(), bad))
    assert tv.error and "cannot read ACMI" in tv.error and tv.facts == {}
    tv = _tv(merge_acmi(_outcome(), tmp_path / "missing.txt.acmi"))
    assert tv.error is not None


def test_zip_acmi_merges_like_text(tmp_path: Path) -> None:
    z = tmp_path / "Tacview-20261029-DCS-m02.zip.acmi"
    with zipfile.ZipFile(z, "w", zipfile.ZIP_DEFLATED) as zf:
        zf.writestr("Tacview-20261029-DCS-m02.txt.acmi", HOG.read_text(encoding="utf-8"))
    a, b = _tv(merge_acmi(_outcome(), z)), _tv(merge_acmi(_outcome(), HOG))
    assert a.facts == b.facts and a.kills == b.kills


def test_viper_fixture_kills_by_id() -> None:
    tv = _tv(merge_acmi(_outcome(players=["Viper11"]), VIPER))
    assert tv.player is not None and tv.player.object_id == "101"
    assert sorted(k.victim_id for k in tv.kills if k.by_player) == ["202", "203", "301"]
    assert {w.weapon for w in tv.weapons_released} == {"AIM-120C", "GBU-12"}


def test_find_newest_acmi(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> None:
    assert find_newest_acmi([tmp_path / "nope"]) is None
    d1, d2 = tmp_path / "a", tmp_path / "b"
    d1.mkdir()
    d2.mkdir()
    old = d1 / "old.txt.acmi"
    new = d2 / "new.zip.acmi"
    other = d2 / "notes.txt"
    for i, f in enumerate((old, new, other)):
        f.write_text("x", encoding="utf-8")
        os.utime(f, (1000 + i * 100, 1000 + i * 100))
    assert find_newest_acmi([d1, d2]) == new
    monkeypatch.setenv("DMS_TACVIEW_DIR", str(d1))
    dirs = default_tacview_dirs(home=tmp_path)
    assert dirs[0] == d1 and tmp_path / "Documents" / "Tacview" in dirs
