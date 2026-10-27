"""Tests for dms_core.luaio: sandboxed loads + exact DCS-style dumps."""

from __future__ import annotations

import math
import zipfile
from pathlib import Path
from typing import Any

import pytest
from dms_core.luaio import LuaError, dumps, dumps_globals, loads
from dms_core.miz import TABLES

EDGE_STRINGS = [
    "",
    "plain",
    'quote " inside',
    "single ' quote",
    r"back\slash" + "\\",
    "trailing backslash \\",
    "line1\nline2\r\nline3\rend",
    "tab\tbell\a back\b ff\f vt\v",
    "nul\0byte",
    "ctrl \x01\x1f\x7f",
    "\x001 digit after escaped nul",
    "\n literal backslash-n",
    "]] ]=] [[ long brackets",
    "-- not a comment",
    "unicode: é ü 漢字 🚁 Ωμέγα",
    "a" * 5000,
]


@pytest.mark.parametrize("s", EDGE_STRINGS)
def test_string_round_trip(s: str) -> None:
    data = {"s": s, s: 1} if s else {"s": s}
    assert loads(dumps(data, "t"), "t") == data


def test_undecodable_bytes_survive() -> None:
    raw = b't = { ["k"] = "\xff\xfe ok \xc3\xa9" }'
    value = loads(raw, "t")
    assert loads(dumps(value, "t"), "t") == value
    assert dumps(value, "t").encode("utf-8", "surrogateescape").count(b"\xc3\xa9") == 1


@pytest.mark.parametrize(
    "num",
    [
        0,
        1,
        -1,
        2**31,
        2**53,
        0.1,
        -0.5,
        1e-300,
        1.7976931348623157e308,
        1.1285208237082,
        -610532.42815746,
        5e-324,
        123456789.123456789,
    ],
)
def test_number_round_trip(num: float) -> None:
    out = loads(dumps({1: num}, "t"), "t")[1]
    assert out == num
    assert type(out) is (int if float(num).is_integer() else float)


def test_integral_float_becomes_int() -> None:
    assert loads("t = { 5.0, 2.5 }", "t") == {1: 5, 2: 2.5}
    assert isinstance(loads("t = { 5.0 }", "t")[1], int)


def test_special_floats() -> None:
    out = loads(dumps({"a": math.inf, "b": -math.inf, "c": math.nan}, "t"), "t")
    assert out["a"] == math.inf and out["b"] == -math.inf and math.isnan(out["c"])


def test_nested_mixed_keys_and_bools() -> None:
    data: dict[Any, Any] = {
        1: "a",
        2: {"x": True, "y": False},
        "name": "n",
        10: {},
        1.5: "frac",
        "deep": {1: {1: {1: {"z": -3}}}},
    }
    assert loads(dumps(data, "t"), "t") == data
    assert loads(dumps({True: "t", "x": 1}, "t"), "t") == {True: "t", "x": 1}


def test_exact_mode_keeps_int_keys_and_arrays_option() -> None:
    src = 't = { [1] = "a", [2] = "b", ["m"] = { 1, 2, 3 }, ["e"] = {}, '
    src += '["gap"] = { [1]=1, [3]=3 } }'
    exact = loads(src, "t")
    assert exact["m"] == {1: 1, 2: 2, 3: 3}
    arr = loads(src, "t", arrays=True)
    assert arr["m"] == [1, 2, 3]
    assert arr["e"] == {}
    assert arr["gap"] == {1: 1, 3: 3}
    assert loads(dumps(arr, "t"), "t") == exact


def test_lists_serialize_one_based() -> None:
    text = dumps({"l": ["a", "b"], "t": ("c",)}, "t")
    assert '[1] = "a"' in text and '[2] = "b"' in text
    assert loads(text, "t") == {"l": {1: "a", 2: "b"}, "t": {1: "c"}}


def test_dcs_style_format() -> None:
    text = dumps({"a": {"b": 1}, "e": {}}, "mission")
    assert text == (
        'mission = \n{\n\t["a"] = \n\t{\n\t\t["b"] = 1,\n\t}, -- end of ["a"]\n'
        '\t["e"] = {},\n} -- end of mission\n'
    )
    assert "-- end of" not in dumps({"a": {"b": 1}}, "m", end_comments=False)
    assert dumps(5) == "5"
    assert dumps({"a": 1}, indent="  ").startswith("{\n  [")


def test_deterministic_output() -> None:
    a = {"b": 1, "a": 2, 3: "x", 1: "y"}
    b = dict(reversed(list(a.items())))
    assert dumps(a, "t") == dumps(b, "t")


def test_loads_all_globals_and_missing_name() -> None:
    src = "a = 1\nb = { 2 }\n"
    assert loads(src) == {"a": 1, "b": {1: 2}}
    assert loads(dumps_globals(loads(src))) == loads(src)
    with pytest.raises(KeyError):
        loads(src, "c")


def test_sandbox_has_no_stdlib() -> None:
    with pytest.raises(LuaError):
        loads("x = os.time()")
    with pytest.raises(LuaError):
        loads("x = io.open('f')")
    assert loads("x = python") == {}  # lupa's python bridge is not reachable
    assert loads("x = string") == {}
    assert loads("x = print") == {}  # nil global: nothing assigned


def test_syntax_error_and_bytecode_rejected() -> None:
    with pytest.raises(LuaError):
        loads("t = {")
    with pytest.raises(LuaError):
        loads(b"\x1bLua binary")


def test_unserializable_values() -> None:
    with pytest.raises(LuaError):
        dumps({"a": object()})
    with pytest.raises(LuaError):
        dumps({(1, 2): 1})
    rec: dict[str, Any] = {}
    rec["self"] = rec
    with pytest.raises(LuaError):
        dumps(rec)
    with pytest.raises(LuaError):
        dumps({}, "not a name")


def test_bom_is_ignored() -> None:
    assert loads("﻿t = 1", "t") == 1


def test_fixture_tables_round_trip_exactly(miz_source: Path) -> None:
    with zipfile.ZipFile(miz_source) as zf:
        names = set(zf.namelist())
        checked = 0
        for path, global_name in TABLES.items():
            if path not in names:
                continue
            original = loads(zf.read(path), global_name)
            text = dumps(original, global_name)
            again = loads(text, global_name)
            assert again == original, f"{miz_source.name}:{path} changed on round trip"
            assert dumps(again, global_name) == text, "serializer is not a fixed point"
            checked += 1
        assert checked >= 1
