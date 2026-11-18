"""Tests for tools/hotas_map/extract.py diff semantics (mirrors DCS Scripts/Input/Data.lua)."""

from __future__ import annotations

import importlib.util
import sys
from pathlib import Path
from types import ModuleType

SCRIPT = Path(__file__).resolve().parents[1] / "hotas_map" / "extract.py"


def _load() -> ModuleType:
    spec = importlib.util.spec_from_file_location("dms_hotas_map", SCRIPT)
    assert spec and spec.loader
    mod = importlib.util.module_from_spec(spec)
    sys.modules["dms_hotas_map"] = mod
    spec.loader.exec_module(mod)
    return mod


hm = _load()


def _cmd(name: str, key: str, axis: bool = False) -> object:
    c = hm.Combo(key)
    return hm.Command(name, None, axis, {c.ident: (c, "default")})


def _keys(cmds: dict[str, object], h: str) -> list[tuple[str, str]]:
    return sorted((c.key, src) for c, src in cmds[h].combos.values())  # type: ignore[attr-defined]


def test_rebinding_a_default_key_to_another_command_keeps_both_as_conflict() -> None:
    cmds = {"dY": _cmd("Y", "JOY_BTN4")}
    diff = {"keyDiffs": {"dX": {"name": "X", "added": [{"key": "JOY_BTN4"}]}}}
    hm.apply_diff(cmds, diff, "yours")
    assert _keys(cmds, "dY") == [("JOY_BTN4", "default")]  # DCS marks Y "updated"
    assert _keys(cmds, "dX") == [("JOY_BTN4", "yours")]


def test_removed_and_added_on_same_command() -> None:
    cmds = {"dX": _cmd("X", "JOY_BTN1")}
    diff = {
        "keyDiffs": {
            "dX": {"name": "X", "removed": [{"key": "JOY_BTN1"}], "added": [{"key": "JOY_BTN2"}]}
        }
    }
    hm.apply_diff(cmds, diff, "yours")
    assert _keys(cmds, "dX") == [("JOY_BTN2", "yours")]


def test_base_entry_matched_by_name_and_modifier_layer_is_distinct() -> None:
    cmds = {"name:View Left slow": _cmd("View Left slow", "JOY_BTN_POV1_L")}
    diff = {
        "keyDiffs": {
            "dV": {
                "name": "View Left slow",
                "added": [{"key": "JOY_BTN_POV1_L", "reformers": ["JOY_BTN5"]}],
            }
        }
    }
    hm.apply_diff(cmds, diff, "yours")
    assert "name:View Left slow" not in cmds
    combos = cmds["dV"].combos  # type: ignore[attr-defined]
    assert ("JOY_BTN_POV1_L", ()) in combos
    assert ("JOY_BTN_POV1_L", ("JOY_BTN5",)) in combos


def test_changed_axis_filter_replaces_default() -> None:
    cmds = {"a1": _cmd("Pitch", "JOY_Y", axis=True)}
    filt = {"invert": True, "deadzone": 0.05, "curvature": [0.2]}
    diff = {"axisDiffs": {"a1": {"name": "Pitch", "changed": [{"key": "JOY_Y", "filter": filt}]}}}
    hm.apply_diff(cmds, diff, "yours")
    out = hm.device_json(cmds)["axes"]["JOY_Y"]
    assert out == [
        {"name": "Pitch", "source": "yours", "invert": True, "deadzone": 0.05, "curvature": 0.2}
    ]


def test_key_diff_does_not_touch_axis_commands() -> None:
    cmds = {"a1": _cmd("Roll", "JOY_X", axis=True)}
    diff = {"keyDiffs": {"dX": {"name": "X", "added": [{"key": "JOY_X"}]}}}
    hm.apply_diff(cmds, diff, "yours")
    assert _keys(cmds, "a1") == [("JOY_X", "default")]
