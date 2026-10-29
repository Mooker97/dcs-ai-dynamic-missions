from __future__ import annotations

import pytest
from dms_arma.sqf import (
    SqfParseError,
    SqfValue,
    parse_config,
    parse_sqf_value,
    sqf_equal,
    sqf_format,
    sqf_inline,
    sqf_number,
    sqf_string,
)


def test_string_escaping_round_trips() -> None:
    for text in ["plain", 'say "hi"', '""', "it's", "a\nb", "// not a comment", "/* nor */"]:
        lit = sqf_string(text)
        assert lit.startswith('"') and lit.endswith('"')
        assert parse_sqf_value(lit) == text
    assert sqf_string('a"b') == '"a""b"'


def test_single_quoted_strings_parse() -> None:
    assert parse_sqf_value("'it''s'") == "it's"


def test_numbers() -> None:
    assert sqf_number(5.0) == "5"
    assert sqf_number(5.5) == "5.5"
    assert sqf_number(-7.5) == "-7.5"
    assert sqf_number(1e-7) == "0.0000001"
    assert sqf_number(1e20) == "100000000000000000000"
    with pytest.raises(ValueError):
        sqf_number(float("nan"))
    assert parse_sqf_value("-12") == -12
    assert parse_sqf_value("0.18") == 0.18
    assert parse_sqf_value("1e3") == 1000.0
    assert parse_sqf_value("0x1F") == 31


def test_arrays_and_bools() -> None:
    value: SqfValue = [1, "a", [True, False], [], [[0.5]]]
    assert sqf_inline(value) == '[1, "a", [true, false], [], [[0.5]]]'
    assert sqf_equal(parse_sqf_value(sqf_inline(value)), value)


def test_format_breaks_long_arrays_deterministically() -> None:
    value: SqfValue = [["x" * 40, [1, 2]], ["y" * 40, [3, 4]], ["z" * 40, [5, 6]]]
    out = sqf_format(value, indent=1)
    assert out == sqf_format(value, indent=1)
    assert out.count("\n") == 4
    assert sqf_equal(parse_sqf_value(out), value)


def test_comments_ignored() -> None:
    text = 'createHashMapFromArray [\n// c\n["a", 1], /* b */ ["b", [2, "x"]] // t\n]'
    assert parse_config(text) == {"a": 1, "b": [2, "x"]}


def test_rejects_non_literals_and_trailing_comma() -> None:
    with pytest.raises(SqfParseError):
        parse_sqf_value("[player]")
    with pytest.raises(SqfParseError):
        parse_sqf_value("[1, 2,]")
    with pytest.raises(SqfParseError):
        parse_config('[["a", 1], ["a", 2]]')


def test_equality_is_semantic() -> None:
    assert sqf_equal(8, 8.0)
    assert not sqf_equal(True, 1)
    assert not sqf_equal("1", 1)
    assert not sqf_equal([1], [1, 2])
