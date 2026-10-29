"""MissionSpec.plugins: opt-in optional pinned Lua plugins (CONTRACTS "Optional plugins")."""

from __future__ import annotations

import json
from pathlib import Path
from typing import Any

import pytest
from dms_core.schemas import MissionSpec
from pydantic import ValidationError

REPO = Path(__file__).resolve().parents[3]

BASE: dict[str, Any] = {
    "id": "m01-test",
    "title": "Test",
    "theater": "Syria",
    "era": 2016,
    "date": "2016-04-03",
    "mission_type": "CAS",
    "areas": [{"id": "home", "where": {"kind": "near_airbase", "airbase": "Hatay"}}],
    "player_flights": [
        {"callsign": "Gunfighter", "aircraft": "AH-64D_BLK_II", "start_area": "home"}
    ],
    "objectives": [{"id": "o1", "kind": "destroy", "description": "Kill it", "area": "home"}],
}


def _spec(**kw: Any) -> MissionSpec:
    return MissionSpec.model_validate({**BASE, **kw})


def test_plugins_default_empty() -> None:
    assert _spec().plugins == []


@pytest.mark.parametrize("plugins", [["skynet"], ["mist"], ["moose"], ["skynet", "moose"]])
def test_plugins_accepts_known(plugins: list[str]) -> None:
    assert _spec(plugins=plugins).plugins == plugins


@pytest.mark.parametrize("plugins", [["ctld"], ["skynet_adapter"], ["Skynet"], "skynet"])
def test_plugins_rejects_unknown(plugins: Any) -> None:
    with pytest.raises(ValidationError):
        _spec(plugins=plugins)


def test_plugins_rejects_duplicates() -> None:
    with pytest.raises(ValidationError, match="duplicate plugins"):
        _spec(plugins=["mist", "mist"])


def test_plugins_in_json_schema() -> None:
    prop = MissionSpec.model_json_schema()["properties"]["plugins"]
    assert prop["description"]
    assert sorted(prop["items"]["enum"]) == ["mist", "moose", "skynet"]
    committed = REPO / "schemas" / "mission-spec.schema.json"
    if committed.is_file():
        on_disk = json.loads(committed.read_text(encoding="utf-8"))
        assert on_disk["properties"]["plugins"] == prop
