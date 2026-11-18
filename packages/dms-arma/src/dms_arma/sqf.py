"""SQF literal values: a deterministic emitter and a parser for the config-file subset.

The subset is what `fn_config.sqf` uses: numbers, strings, booleans, nested arrays, `//` and
`/* */` comments, optionally wrapped in `createHashMapFromArray [...]`. It is not a general SQF
parser; anything else (variables, commands, code blocks) is rejected with `SqfParseError`.
"""

from __future__ import annotations

import math
import re
from collections.abc import Sequence

SqfValue = bool | int | float | str | Sequence["SqfValue"]
"""A literal SQF value. Python lists/tuples map to SQF arrays."""

WRAPPER = "createHashMapFromArray"


class SqfParseError(ValueError):
    """The text is not in the supported SQF literal subset."""


# ------------------------------------------------------------------------------------- emitter


def sqf_string(text: str) -> str:
    """Quote `text` as an SQF string literal (double quotes, inner quotes doubled)."""
    return '"' + text.replace('"', '""') + '"'


def sqf_number(value: float) -> str:
    """Format a number for SQF: integral values without a decimal point, never exponent form."""
    if isinstance(value, bool):
        raise TypeError("bool is not a number")
    if isinstance(value, float):
        if not math.isfinite(value):
            raise ValueError(f"SQF has no literal for {value!r}")
        if value.is_integer():
            return str(int(value))
        text = repr(value)
        if "e" in text or "E" in text:
            text = f"{value:.15f}".rstrip("0").rstrip(".")
        return text
    return str(value)


def sqf_inline(value: SqfValue) -> str:
    """Render a value on one line."""
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, int | float):
        return sqf_number(value)
    if isinstance(value, str):
        return sqf_string(value)
    return "[" + ", ".join(sqf_inline(v) for v in value) + "]"


def sqf_format(
    value: SqfValue, indent: int = 0, width: int = 100, tab: str = "\t", prefix: int = 0
) -> str:
    """Render a value, breaking an array one element per line when it does not fit in `width`.

    `indent` is the nesting level of the line the value starts on (a tab counts 4 columns) and
    `prefix` the number of characters already on that line before the value. Deterministic.
    """
    inline = sqf_inline(value)
    if isinstance(value, str | int | float | bool) or indent * 4 + prefix + len(inline) <= width:
        return inline
    if not value:
        return "[]"
    inner = tab * (indent + 1)
    parts = [inner + sqf_format(v, indent + 1, width, tab) for v in value]
    return "[\n" + ",\n".join(parts) + "\n" + tab * indent + "]"


# -------------------------------------------------------------------------------------- parser

_TOKEN = re.compile(
    r"""
    (?P<ws>\s+)
  | (?P<line_comment>//[^\n]*)
  | (?P<block_comment>/\*.*?\*/)
  | (?P<dstring>"(?:[^"]|"")*")
  | (?P<sstring>'(?:[^']|'')*')
  | (?P<hex>-?(?:0x|\$)[0-9A-Fa-f]+)
  | (?P<number>-?(?:\d+\.?\d*|\.\d+)(?:[eE][+-]?\d+)?)
  | (?P<ident>[A-Za-z_][A-Za-z0-9_]*)
  | (?P<punct>[\[\],;])
    """,
    re.VERBOSE | re.DOTALL,
)


def _tokens(text: str) -> list[tuple[str, str, int]]:
    out: list[tuple[str, str, int]] = []
    pos = 0
    while pos < len(text):
        m = _TOKEN.match(text, pos)
        if m is None:
            line = text.count("\n", 0, pos) + 1
            raise SqfParseError(f"line {line}: unexpected {text[pos : pos + 20]!r}")
        kind = m.lastgroup or ""
        if kind not in {"ws", "line_comment", "block_comment"}:
            out.append((kind, m.group(), text.count("\n", 0, pos) + 1))
        pos = m.end()
    return out


class _Parser:
    def __init__(self, tokens: list[tuple[str, str, int]]) -> None:
        self.toks = tokens
        self.i = 0

    def peek(self) -> tuple[str, str, int] | None:
        return self.toks[self.i] if self.i < len(self.toks) else None

    def take(self) -> tuple[str, str, int]:
        tok = self.peek()
        if tok is None:
            raise SqfParseError("unexpected end of input")
        self.i += 1
        return tok

    def value(self) -> SqfValue:
        kind, text, line = self.take()
        if kind == "dstring":
            return text[1:-1].replace('""', '"')
        if kind == "sstring":
            return text[1:-1].replace("''", "'")
        if kind == "hex":
            neg = text.startswith("-")
            digits = text.lstrip("-").removeprefix("0x").removeprefix("$")
            return -int(digits, 16) if neg else int(digits, 16)
        if kind == "number":
            if re.fullmatch(r"-?\d+", text):
                return int(text)
            return float(text)
        if kind == "ident" and text.lower() in {"true", "false"}:
            return text.lower() == "true"
        if text == "[":
            items: list[SqfValue] = []
            nxt = self.peek()
            if nxt is not None and nxt[1] == "]":
                self.take()
                return items
            while True:
                items.append(self.value())
                _, sep, sep_line = self.take()
                if sep == "]":
                    return items
                if sep != ",":
                    raise SqfParseError(f"line {sep_line}: expected ',' or ']', got {sep!r}")
                nxt = self.peek()
                if nxt is not None and nxt[1] == "]":
                    raise SqfParseError(f"line {nxt[2]}: trailing comma (SQF rejects it)")
        raise SqfParseError(f"line {line}: unsupported token {text!r}")


def parse_sqf_value(text: str) -> SqfValue:
    """Parse one SQF literal value (comments allowed), returning Python lists for arrays."""
    parser = _Parser(_tokens(text))
    value = parser.value()
    if parser.peek() is not None:
        tok = parser.take()
        raise SqfParseError(f"line {tok[2]}: trailing input {tok[1]!r}")
    return value


def parse_config(text: str) -> dict[str, SqfValue]:
    """Parse a `fn_config.sqf` body (`createHashMapFromArray [[key, value], ...]`) to a dict.

    Key order is preserved. Duplicate keys raise, because SQF would silently keep the last one.
    """
    toks = _tokens(text)
    if toks and toks[0][0] == "ident" and toks[0][1] == WRAPPER:
        toks = toks[1:]
    if toks and toks[-1][1] == ";":
        toks = toks[:-1]
    parser = _Parser(toks)
    raw = parser.value()
    if parser.peek() is not None:
        tok = parser.take()
        raise SqfParseError(f"line {tok[2]}: trailing input {tok[1]!r}")
    if not isinstance(raw, list):
        raise SqfParseError("config is not an array of [key, value] pairs")
    out: dict[str, SqfValue] = {}
    for pair in raw:
        if not (isinstance(pair, list) and len(pair) == 2 and isinstance(pair[0], str)):
            raise SqfParseError(f"not a [key, value] pair: {sqf_inline(pair)[:60]}")
        key = pair[0]
        if key in out:
            raise SqfParseError(f"duplicate key {key!r}")
        out[key] = pair[1]
    return out


def sqf_equal(a: SqfValue, b: SqfValue) -> bool:
    """Semantic equality of SQF values: all numbers are one scalar type, bools are not numbers."""
    if isinstance(a, bool) or isinstance(b, bool):
        return isinstance(a, bool) and isinstance(b, bool) and a == b
    if isinstance(a, int | float) and isinstance(b, int | float):
        return float(a) == float(b)
    if isinstance(a, str) or isinstance(b, str):
        return isinstance(a, str) and isinstance(b, str) and a == b
    if isinstance(a, int | float) or isinstance(b, int | float):
        return False
    return len(a) == len(b) and all(sqf_equal(x, y) for x, y in zip(a, b, strict=True))


def config_diff(a: dict[str, SqfValue], b: dict[str, SqfValue]) -> list[str]:
    """Human-readable semantic differences between two parsed configs (empty = equivalent)."""
    diffs = [f"only in first: {k}" for k in a if k not in b]
    diffs += [f"only in second: {k}" for k in b if k not in a]
    for k in a:
        if k in b and not sqf_equal(a[k], b[k]):
            diffs.append(f"{k}: {sqf_inline(a[k])[:80]} != {sqf_inline(b[k])[:80]}")
    return diffs
