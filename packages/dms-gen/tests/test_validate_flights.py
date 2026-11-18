"""`dms validate` / `dms check` / lint rules for AI flights and watch missions (CONTRACTS v0.9)."""

from __future__ import annotations

from typing import Any

from dms_core.lint import _callsign_words
from dms_core.schemas import BeatSheet, MissionSpec
from dms_core.schemas.validation import Issue
from dms_gen.check import CheckReport, _check_flights
from dms_gen.planner import validate
from test_planner import convoy_beats, convoy_lines, convoy_spec


def _data(**over: Any) -> dict[str, Any]:
    data = convoy_spec().model_dump(mode="json", exclude_none=True)
    data.update(over)
    return data


def _dustoff(**over: Any) -> dict[str, Any]:
    f: dict[str, Any] = {
        "id": "dustoff",
        "callsign": "Dustoff 3-1",
        "aircraft": "UH-60A",
        "start_area": "base",
        "orders": [
            {"do": "fly", "to": "ambush_ridge"},
            {"do": "land", "at": "ambush_ridge", "pickup": "convoy_main"},
            {"do": "rtb"},
        ],
    }
    f.update(over)
    return f


def _at(issues: list[Issue], frag: str) -> list[Issue]:
    return [i for i in issues if frag in i.path]


def test_clean_flight_has_no_flight_issues() -> None:
    spec = MissionSpec.model_validate(_data(flights=[_dustoff()]))
    issues = validate(spec, convoy_beats(), convoy_lines())
    assert not [i for i in _at(issues, "flights[") if i.severity == "error"], issues


def test_unknown_flight_aircraft_and_country() -> None:
    spec = MissionSpec.model_validate(
        _data(flights=[_dustoff(aircraft="UH-60Z", country="Russia")])
    )
    issues = validate(spec)
    errs = {i.path.split(":", 1)[1] for i in issues if i.severity == "error"}
    assert "flights[0].aircraft" in errs
    assert "flights[0].country" in errs


def test_unknown_order_area_is_an_error() -> None:
    spec = MissionSpec.model_validate(
        _data(flights=[_dustoff(orders=[{"do": "fly", "to": "nowhere"}])])
    )
    issues = validate(spec)
    assert any(i.severity == "error" and i.path.endswith("flights[0].orders[0].to") for i in issues)


def test_strike_group_should_name_threat_or_pool() -> None:
    orders = [
        {"do": "strike", "at": "town", "group": "tech_town"},
        {"do": "strike", "at": "town", "group": "DMS_qrf"},
        {"do": "strike", "at": "town", "group": "bogus"},
    ]
    spec = MissionSpec.model_validate(_data(flights=[_dustoff(aircraft="F-16C_50", orders=orders)]))
    bad = [i for i in _at(validate(spec), ".group") if "strike group" in i.problem]
    assert [i.path.rsplit("orders", 1)[1] for i in bad] == ["[2].group"]
    assert bad[0].severity == "warning"


def test_pickup_must_be_ground_support_or_flight() -> None:
    support = [
        *_data()["support"],
        {"id": "magic", "role": "awacs", "callsign": "Magic 1-1"},
    ]
    orders = [{"do": "land", "at": "town", "pickup": "magic"}]
    spec = MissionSpec.model_validate(_data(support=support, flights=[_dustoff(orders=orders)]))
    bad = _at(validate(spec), "orders[0].pickup")
    assert bad and bad[0].severity == "warning" and "awacs" in bad[0].problem


def test_plane_landing_off_airfield_warns() -> None:
    orders = [{"do": "land", "at": "town"}]
    spec = MissionSpec.model_validate(_data(flights=[_dustoff(aircraft="F-16C_50", orders=orders)]))
    assert any("airfields" in i.problem for i in _at(validate(spec), "orders[0].at"))


def test_medevac_support_warns_unless_a_flight_represents_it() -> None:
    support = [*_data()["support"], {"id": "medevac", "role": "medevac", "speaker": "ops"}]
    spec = MissionSpec.model_validate(_data(support=support))
    warn = [i for i in validate(spec) if "medevac" in i.problem and i.path.endswith(".role")]
    assert warn and "flights[]" in warn[0].problem
    for flight in (_dustoff(id="medevac"), _dustoff(speaker="ops")):
        spec = MissionSpec.model_validate(_data(support=support, flights=[flight]))
        assert not [i for i in validate(spec) if "'medevac'" in i.problem], flight


def _watch_data(**over: Any) -> dict[str, Any]:
    d = _data(
        player_flights=[],
        watch={"focus": "dustoff"},
        flights=[_dustoff(coalition="blue")],
    )
    d.update(over)
    return d


def test_watch_mission_validates_without_player_flights() -> None:
    support = [
        *_data()["support"],
        {"id": "magic", "role": "awacs", "callsign": "Overlord 1-1", "faction": "usa"},
    ]
    spec = MissionSpec.model_validate(_watch_data(support=support))
    issues = validate(spec, convoy_beats(), convoy_lines())  # must not IndexError
    assert not [i for i in issues if "player" in i.problem.lower() and i.severity == "error"]


def test_beat_flight_filter_cue_and_order_triggers() -> None:
    beats = convoy_beats().model_dump(mode="json", exclude_none=True)
    beats["beats"].append(
        {
            "id": "dust_up",
            "when": {"event": "flight.lifted", "flight": "dustof"},
            "cue": "F2 on Dustoff",
        }
    )
    orders = [{"do": "hold", "at": "town", "until": {"beat": "nope"}}]
    bs = BeatSheet.model_validate(beats)
    spec = MissionSpec.model_validate(_data(flights=[_dustoff(orders=orders)]))
    issues = validate(spec, bs, convoy_lines())
    assert any(i.path.endswith(".when.flight") and i.severity == "warning" for i in issues)
    assert any(i.path.endswith(".cue") and i.severity == "info" for i in issues)
    assert any(i.path.endswith("orders[0].until.beat") for i in issues)
    spec_w = MissionSpec.model_validate(_watch_data())
    issues_w = validate(spec_w, bs, convoy_lines())
    assert not any(i.path.endswith(".cue") for i in issues_w)


def test_lint_callsigns_include_flights() -> None:
    spec = MissionSpec.model_validate(_watch_data())
    assert "dustoff" in _callsign_words(spec, None)


def _mission(*names: str) -> dict[str, Any]:
    return {
        "coalition": {
            "blue": {
                "country": [
                    {"helicopter": {"group": [{"name": n, "units": []} for n in names]}},
                ]
            }
        }
    }


def test_check_watch_relaxes_slot_and_checks_flights() -> None:
    rep = CheckReport(path="x.miz")
    rep.add("error", "no_player_slot", "mission has no Client/Player slot")
    cfg: dict[str, Any] = {
        "zones": {"town": {}},
        "watch": {"enabled": True, "focus": "Dustoff_dustoff"},
        "flights": [
            {
                "id": "dustoff",
                "group": "Dustoff_dustoff",
                "orders": [
                    {"kind": "fly", "to": "town"},
                    {"kind": "fly", "to": "gone"},
                    {"kind": "land", "at": "Hatay", "pickup": "Kestrel_kestrel"},
                    {"kind": "escort", "flight": "ghost"},
                ],
            },
            {"id": "lost", "group": "Missing_lost", "orders": []},
        ],
    }
    _check_flights(rep, _mission("Dustoff_dustoff"), cfg)
    by = {i.code: i for i in rep.issues}
    assert by["no_player_slot"].severity == "info"
    assert {"flight_bad_zone", "flight_bad_escort", "flight_group_missing"} <= set(by)
    assert by["flight_bad_pickup"].severity == "warning"
    assert "watch_focus_missing" not in by
    assert len([i for i in rep.issues if i.code == "flight_bad_zone"]) == 1  # land: airbase ok

    rep2 = CheckReport(path="x.miz")
    rep2.add("error", "no_player_slot", "mission has no Client/Player slot")
    _check_flights(rep2, _mission("Other"), {"watch": {"focus": "Dustoff_dustoff"}})
    codes = {i.code: i.severity for i in rep2.issues}
    assert codes == {"no_player_slot": "info", "watch_focus_missing": "error"}
    assert not rep2.ok


def test_check_normal_mission_keeps_slot_error() -> None:
    rep = CheckReport(path="x.miz")
    rep.add("error", "no_player_slot", "mission has no Client/Player slot")
    _check_flights(rep, _mission("A"), {})
    assert rep.issues[0].severity == "error"
