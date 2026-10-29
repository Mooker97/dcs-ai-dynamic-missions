from __future__ import annotations

import json
from pathlib import Path

import pytest
from dms_core.schemas import MissionOutcome
from dms_tacview import enrich_outcome, outcome_facts, parse_acmi_file, summarize
from dms_tacview.cli import load_points, main
from dms_tacview.summary import FlightSummary, Heuristics

FIX = Path(__file__).parent / "fixtures"
VIPER = FIX / "viper_strike.txt.acmi"


@pytest.fixture(scope="module")
def summary() -> FlightSummary:
    return summarize(parse_acmi_file(VIPER), points=load_points(FIX / "points.yaml"))


def test_player_heuristic_and_track(summary: FlightSummary) -> None:
    p = summary.player
    assert p is not None
    assert (p.object_id, p.pilot, p.selected_by) == (
        "101",
        "Mooker",
        "heuristic_first_piloted_aircraft",
    )
    assert p.takeoffs == [5] and p.landings == []
    assert p.fate == "present_at_end"
    assert p.max_alt_m == 4000 and p.min_alt_m == 50
    assert 15 < p.distance_km < 25
    assert p.samples[0][0] == 0 and p.samples[-1][0] == 150


def test_explicit_player() -> None:
    s = summarize(parse_acmi_file(VIPER), player="Viper 1-2")
    assert s.player is not None and s.player.object_id == "102"
    assert s.player.selected_by == "explicit" and s.player.landings == [125]
    assert summarize(parse_acmi_file(VIPER), player="nobody").player is None


def test_fates(summary: FlightSummary) -> None:
    fates = {o.id: (o.fate, o.fate_source) for o in summary.objects}
    assert fates["301"] == ("destroyed", "destroyed_event")
    assert fates["202"] == ("destroyed", "removal_inferred")
    assert fates["203"] == ("destroyed", "destroyed_event")
    assert fates["102"] == ("removed", "removal")  # landed, then despawned
    assert fates["401"] == ("removed", "removal")
    assert fates["501"] == ("present_at_end", "none")
    mig = next(o for o in summary.objects if o.id == "301")
    assert mig.lifespan_s == 41


def test_shots(summary: FlightSummary) -> None:
    shots = {s.weapon_id: s for s in summary.shots}
    assert shots["401"].launcher_method == "parent_property"
    assert shots["401"].hit and shots["401"].target_id == "301"
    assert shots["402"].launcher_id == "101"
    assert shots["402"].launcher_method == "launch_proximity"
    assert shots["402"].hit and shots["402"].target_id == "202"
    assert shots["403"].launcher_id == "201" and not shots["403"].hit
    assert (summary.player_shots, summary.player_hits) == (2, 2)


def test_kills(summary: FlightSummary) -> None:
    kills = {k.victim_id: k for k in summary.kills}
    assert set(kills) == {"301", "202", "203"}
    mig = kills["301"]
    assert (mig.killer_id, mig.weapon_name, mig.method, mig.confidence) == (
        "101",
        "AIM-120C",
        "nearest_weapon",
        "medium",
    )
    assert mig.distance_m is not None and mig.distance_m < 100
    truck = kills["202"]
    assert (truck.killer_id, truck.method, truck.confidence, truck.destroy_source) == (
        "101",
        "nearest_weapon",
        "low",
        "removal_inferred",
    )
    gun = kills["203"]
    assert (gun.killer_pilot, gun.method, gun.confidence, gun.weapon_name) == (
        "Mooker",
        "timeout_event",
        "high",
        "M61A1",
    )
    assert summary.player_kills == 3


def test_no_removal_inference() -> None:
    s = summarize(parse_acmi_file(VIPER), heuristics=Heuristics(infer_destroyed_from_removal=False))
    assert {k.victim_id for k in s.kills} == {"301", "203"}


def test_points_and_threats(summary: FlightSummary) -> None:
    pts = {p.name: p for p in summary.points}
    convoy = pts["Convoy route"]
    assert convoy.entered is True and convoy.min_distance_m < 6000
    assert convoy.first_entry_t is not None and 60 < convoy.first_entry_t < 120
    assert convoy.time_inside_s is not None and convoy.time_inside_s > 0
    assert pts["Kutaisi"].min_distance_m == 0 and pts["Kutaisi"].entered is None
    assert [t.id for t in summary.threats] == ["201"]
    assert 3000 < summary.threats[0].min_slant_m < 7000


def test_facts(summary: FlightSummary) -> None:
    f = outcome_facts(summary)
    assert f["tv_player_found"] is True
    assert f["tv_player_kills"] == 3
    assert f["tv_player_kills_confident"] == 2
    assert (f["tv_player_kills_air"], f["tv_player_kills_ground"]) == (1, 2)
    assert f["tv_enemy_losses"] == 3 and f["tv_friendly_losses"] == 0
    assert f["tv_player_destroyed"] is False
    assert f["tv_convoy_route_entered"] is True
    assert "tv_kutaisi_min_m" in f and "tv_kutaisi_entered" not in f
    import re

    assert all(re.fullmatch(r"[a-z][a-z0-9_]*", k) for k in f)


def test_enrich_outcome_is_additive(summary: FlightSummary) -> None:
    o = MissionOutcome(mission_id="m03-x", kind="summary", outcomes={"tv_player_kills": 99})
    e = enrich_outcome(o, summary, merge_into_outcomes=True)
    assert o.extra == {}  # input untouched
    assert e.extra["tacview"]["facts"]["tv_player_kills"] == 3
    assert e.outcomes["tv_player_kills"] == 99  # never overwrites a reported key
    assert e.outcomes["tv_player_landed"] is False
    plain = enrich_outcome(o, summary)
    assert plain.outcomes == o.outcomes
    MissionOutcome.model_validate(e.model_dump())


def test_cli(capsys: pytest.CaptureFixture[str]) -> None:
    assert main(["summarize", str(VIPER), "--json", "--facts"]) == 0
    facts = json.loads(capsys.readouterr().out)
    assert facts["tv_player_kills"] == 3
    assert main(["summarize", str(VIPER), "--points", str(FIX / "points.yaml")]) == 0
    out = capsys.readouterr().out
    assert "kills:" in out and "objects:" not in out
    assert main(["summarize", str(FIX / "missing.acmi")]) == 1
