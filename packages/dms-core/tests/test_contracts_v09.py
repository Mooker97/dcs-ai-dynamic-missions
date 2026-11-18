"""Contract v0.9 schema fields (MP, state/resume, variety): defaults and round-trips.

The runtime does not implement these yet; these tests pin the *shape* and backwards compatibility.
"""

from __future__ import annotations

from pathlib import Path
from typing import Any

import pytest
from dms_core.schemas import (
    ENCOUNTER_KINDS,
    Beat,
    CommsSettings,
    Encounter,
    EncounterIntent,
    MissionOutcome,
    Objective,
    PlayerOutcome,
    ResumeState,
    RuntimeConfig,
    StateSettings,
    parse_dcs_log,
    summarize_outcomes,
)
from dms_core.schemas._common import V09_ENCOUNTER_KINDS
from dms_core.schemas.runtime import TestSettings
from pydantic import ValidationError

REPO = Path(__file__).resolve().parents[3]


def _beat(**kw: Any) -> Beat:
    return Beat.model_validate({"id": "b1", "when": {"event": "mission.start"}, **kw})


def test_beat_scope_default_and_values() -> None:
    assert _beat().scope is None
    assert _beat(scope="flight").scope == "flight"
    assert _beat(scope="mission").scope == "mission"
    with pytest.raises(ValidationError):
        _beat(scope="server")


def test_beat_player_joined_late_event() -> None:
    b = Beat.model_validate({"id": "b2", "when": {"event": "player.joined_late"}})
    assert b.when.event == "player.joined_late"


def test_encounter_kinds_and_per_flight() -> None:
    assert set(V09_ENCOUNTER_KINDS) <= set(ENCOUNTER_KINDS)
    for kind in V09_ENCOUNTER_KINDS:
        e = Encounter.model_validate(
            {"id": "e", "kind": kind, "pool": "p", "trigger": {"type": "manual"}}
        )
        assert e.kind == kind and e.per_flight is None
    intent = EncounterIntent.model_validate(
        {
            "id": "arty",
            "kind": "artillery",
            "pool": "guns",
            "trigger": {"type": "time", "after_min": 5},
            "per_flight": True,
        }
    )
    assert intent.per_flight is True
    with pytest.raises(ValidationError):
        Encounter.model_validate(
            {"id": "e", "kind": "nuke", "pool": "p", "trigger": {"type": "manual"}}
        )


def test_objective_troops() -> None:
    o = Objective.model_validate(
        {"id": "drop", "kind": "troops", "description": "Insert the squad.", "area": "lz"}
    )
    assert o.kind == "troops"


def _runtime(**kw: Any) -> RuntimeConfig:
    return RuntimeConfig.model_validate({"mission_id": "m-test", **kw})


def test_runtime_defaults_emit_nothing_new() -> None:
    rt = _runtime()
    assert rt.comms is None and rt.state is None and rt.resume is None
    table = rt.to_lua_table()
    for key in ("comms", "state", "resume"):
        assert key not in table
    beat_table = _runtime(beats=[_beat().model_dump()]).to_lua_table()["beats"][0]
    assert "scope" not in beat_table


def test_runtime_v09_round_trip() -> None:
    rt = _runtime(
        beats=[_beat(scope="flight").model_dump()],
        encounters=[
            {
                "id": "csar1",
                "kind": "csar",
                "pool": "p",
                "trigger": {"type": "manual"},
                "per_flight": True,
            }
        ],
        comms={"max_age_sec": 45},
        state={"interval_sec": 120},
        resume={
            "seq": 7,
            "t": 1834.5,
            "seed": 12345,
            "modules": {"Narrative": {"fired": {"b1": 1}}, "Encounters": {}},
        },
        test={"player_proxy": "Proxy 1", "proxies": ["Proxy 1", "Proxy 2"]},
    )
    table = rt.to_lua_table()
    assert table["comms"] == {"maxAgeSec": 45}
    assert table["state"] == {"enabled": True, "intervalSec": 120, "chunkBytes": 2000}
    assert table["resume"]["modules"]["Narrative"] == {"fired": {"b1": 1}}
    assert table["test"]["proxies"] == ["Proxy 1", "Proxy 2"]
    assert table["beats"][0]["scope"] == "flight"
    assert table["encounters"][0]["perFlight"] is True
    back = RuntimeConfig.from_lua_table(table)
    assert back == rt


def test_runtime_settings_defaults_and_bounds() -> None:
    assert CommsSettings().max_age_sec is None
    s = StateSettings()
    assert (s.enabled, s.interval_sec, s.chunk_bytes) == (True, 300, 2000)
    with pytest.raises(ValidationError):
        StateSettings(chunk_bytes=10)
    with pytest.raises(ValidationError):
        CommsSettings(max_age_sec=0)
    r = ResumeState.model_validate({"seq": 1, "modules": []})  # empty Lua table
    assert r.modules == {} and r.seed is None
    assert TestSettings().proxies is None
    with pytest.raises(ValidationError):
        ResumeState.model_validate({"seq": 1, "bogus": 1})


def test_outcome_players_bare_names_still_parse() -> None:
    o = MissionOutcome.from_payload({"missionId": "m01", "players": ["Mook"]})
    assert o.players == [PlayerOutcome(name="Mook")]


def test_outcome_players_v09_objects() -> None:
    log = (
        "2026-10-29 10:00:00.000 INFO    SCRIPTING (Main): [DMS.OUTCOME] "
        '{"missionId":"m01","kind":"update","players":["Mook","Wing"]}\n'
        "2026-10-29 10:30:00.000 INFO    SCRIPTING (Main): [DMS.OUTCOME] "
        '{"missionId":"m01","kind":"end","players":[{"name":"Mook","flight":"Viper 1",'
        '"typeName":"F-16C_50","kills":{"ground":3},"dead":false,"ejected":true,'
        '"late":false,"joinedSec":12}]}\n'
    )
    outs = parse_dcs_log(log)
    assert len(outs) == 2
    mook = outs[1].players[0]
    assert (mook.flight, mook.type_name, mook.kills, mook.ejected, mook.joined_sec) == (
        "Viper 1",
        "F-16C_50",
        {"ground": 3},
        True,
        12,
    )
    merged = summarize_outcomes(outs)["m01"]
    by_name = {p.name: p for p in merged.players}
    assert set(by_name) == {"Mook", "Wing"}
    assert by_name["Mook"].ejected is True  # later report wins per name
    dumped = merged.model_dump(mode="json")
    assert MissionOutcome.model_validate(dumped) == merged


def test_player_outcome_rejects_unknown_keys() -> None:
    with pytest.raises(ValidationError):
        PlayerOutcome.model_validate({"name": "Mook", "bogus": 1})
    assert PlayerOutcome.model_validate({"name": "X", "kills": []}).kills == {}


def test_committed_json_schemas_carry_v09_fields() -> None:
    import json

    rt = REPO / "schemas" / "runtime-config.schema.json"
    if not rt.is_file():
        pytest.skip("JSON Schema export not committed")
    on_disk = json.loads(rt.read_text(encoding="utf-8"))
    assert on_disk == {
        **RuntimeConfig.model_json_schema(),
        "$schema": on_disk["$schema"],
        "$id": on_disk["$id"],
    }
    for name in ("comms", "state", "resume"):
        assert name in on_disk["properties"]
