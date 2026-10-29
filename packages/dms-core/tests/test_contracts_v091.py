"""CONTRACTS "Ground moves on cue and immortal support (v0.9.1)": schema side."""

from __future__ import annotations

import pytest
from dms_core.schemas.beats import Beat, BeatMoveGroup, BeatTrigger
from dms_core.schemas.mission import Support
from dms_core.schemas.runtime import RuntimeConfig
from pydantic import ValidationError


def test_ground_arrived_is_a_beat_event() -> None:
    t = BeatTrigger.model_validate({"event": "ground.arrived", "group": "kestrel"})
    assert t.event == "ground.arrived" and t.group == "kestrel"


def test_move_group_fields() -> None:
    mv = BeatMoveGroup.model_validate({"group": "kestrel", "to": "lz_bravo"})
    assert (mv.speed_kts, mv.off_road, mv.speed_mps, mv.action) == (None, None, None, None)
    with pytest.raises(ValidationError):
        BeatMoveGroup.model_validate({"group": "kestrel", "to": "lz_bravo", "speed_kts": 0})
    with pytest.raises(ValidationError):
        BeatMoveGroup.model_validate({"group": "k", "to": "lz", "action": "Cross Country"})


def test_runtime_move_group_round_trips_camel() -> None:
    beat = Beat.model_validate(
        {
            "id": "go",
            "when": {"event": "mission.start"},
            "effects": {
                "move_group": {
                    "group": "kestrel_1",
                    "to": "lz_bravo",
                    "speed_mps": 4,
                    "action": "Off Road",
                }
            },
        }
    )
    cfg = RuntimeConfig(mission_id="m01", beats=[beat])
    table = cfg.to_lua_table()
    mv = table["beats"][0]["effects"]["moveGroup"]
    assert mv == {"group": "kestrel_1", "to": "lz_bravo", "speedMps": 4, "action": "Off Road"}
    back = RuntimeConfig.from_lua_table(table)
    assert back.beats[0].effects.move_group == beat.effects.move_group


def test_support_immortal_default_false() -> None:
    s = Support.model_validate({"id": "kestrel", "role": "friendly_ground"})
    assert s.immortal is False
    assert Support.model_validate({"id": "k", "role": "jtac", "immortal": True}).immortal
