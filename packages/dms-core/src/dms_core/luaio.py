"""Exact Lua table I/O for DCS mission files.

``loads`` executes Lua source in a sandboxed lupa runtime (Lua 5.1 when available, which is
what DCS uses) and converts the resulting globals to Python. ``dumps`` serializes Python data
back to deterministic DCS Mission-Editor-style Lua.

Value mapping (exact mode, the default):

* Lua table   -> ``dict`` (integer keys stay ``int``; array parts are *not* turned into lists)
* Lua string  -> ``str`` (decoded UTF-8; invalid bytes survive via ``surrogateescape``)
* Lua number  -> ``int`` when integral, else ``float``
* Lua boolean -> ``bool``

With ``arrays=True`` tables whose keys are exactly ``1..n`` (n >= 1) become ``list``.
``dumps`` accepts ``dict``, ``list``/``tuple`` (written as 1-based arrays), ``str``, ``int``,
``float`` and ``bool``. ``loads(dumps(x, "n"), "n") == x`` holds for exact-mode data.
"""

from __future__ import annotations

import math
from collections.abc import Mapping, Sequence
from typing import Any, TypeAlias

import lupa  # type: ignore[import-untyped]

try:  # Lua 5.1 matches DCS; fall back to whatever lupa ships by default.
    from lupa import lua51 as _lua
except ImportError:  # pragma: no cover - depends on the lupa build
    _lua = lupa

__all__ = ["LuaError", "LuaKey", "LuaValue", "dumps", "dumps_globals", "loads"]

LuaKey: TypeAlias = "str | int | float | bool"
LuaValue: TypeAlias = "str | int | float | bool | dict[Any, Any] | list[Any]"

_ENCODING = "utf-8"
_ERRORS = "surrogateescape"


class LuaError(ValueError):
    """Raised when Lua source fails to compile or run, or data cannot be serialized."""


# Runs a text chunk with an empty environment. Works on Lua 5.1 (setfenv) and 5.2+ (load env).
_RUNNER = """
function(src, chunkname)
    if string.byte(src, 1) == 27 then return false, "binary chunks are not allowed" end
    local env = {}
    local fn, err
    if setfenv then
        fn, err = loadstring(src, chunkname)
        if fn then setfenv(fn, env) end
    else
        fn, err = load(src, chunkname, "t", env)
    end
    if not fn then return false, err end
    local ok, rerr = pcall(fn)
    if not ok then return false, rerr end
    return true, env
end
"""


def _decode(b: bytes | str) -> str:
    return b if isinstance(b, str) else b.decode(_ENCODING, _ERRORS)


def _convert(value: Any, arrays: bool, seen: set[str]) -> Any:
    if isinstance(value, bytes):
        return _decode(value)
    if isinstance(value, bool):
        return value
    if isinstance(value, int):
        return value
    if isinstance(value, float):
        if value.is_integer():
            return int(value)
        return value
    if isinstance(value, str):
        return value
    if _lua.lua_type(value) == "table":
        out: dict[Any, Any] = {}
        key_id = _table_id(value)
        if key_id in seen:
            raise LuaError("recursive Lua table cannot be converted")
        seen.add(key_id)
        for k, v in value.items():
            out[_convert(k, arrays, seen)] = _convert(v, arrays, seen)
        seen.discard(key_id)
        if arrays and out and all(isinstance(k, int) and not isinstance(k, bool) for k in out):
            n = len(out)
            if min(out) == 1 and max(out) == n:
                return [out[i] for i in range(1, n + 1)]
        return out
    raise LuaError(f"unsupported Lua value of type {_lua.lua_type(value)!r}")


def _table_id(table: Any) -> str:
    # lupa's repr embeds the Lua table address, stable for the table's lifetime.
    return repr(table)


def loads(src: str | bytes, name: str | None = None, *, arrays: bool = False) -> Any:
    """Execute Lua *src* in a sandbox and return its globals as Python data.

    If *name* is given, return only that global (``KeyError`` if it was not assigned);
    otherwise return a dict of every global the chunk assigned.
    """
    data = src.encode(_ENCODING, _ERRORS) if isinstance(src, str) else src
    if data.startswith(b"\xef\xbb\xbf"):
        data = data[3:]
    runtime = _lua.LuaRuntime(
        encoding=None,
        register_eval=False,
        register_builtins=False,
        unpack_returned_tuples=True,
    )
    runner = runtime.eval(_RUNNER)
    chunkname = ("=" + (name or "lua")).encode(_ENCODING)
    ok, result = runner(data, chunkname)
    if not ok:
        raise LuaError(_decode(result) if isinstance(result, (bytes, str)) else str(result))
    globals_: dict[str, Any] = _convert(result, arrays, set())
    if name is None:
        return globals_
    if name not in globals_:
        raise KeyError(f"Lua source does not assign global {name!r}")
    return globals_[name]


# ---------------------------------------------------------------- serializer

_ESCAPES = {
    "\\": "\\\\",
    '"': '\\"',
    "\n": "\\n",
    "\r": "\\r",
    "\t": "\\t",
    "\a": "\\a",
    "\b": "\\b",
    "\f": "\\f",
    "\v": "\\v",
    "\0": "\\000",
}


def _quote(s: str) -> str:
    parts: list[str] = ['"']
    for ch in s:
        esc = _ESCAPES.get(ch)
        if esc is not None:
            parts.append(esc)
            continue
        o = ord(ch)
        if o < 0x20 or o == 0x7F:
            parts.append(f"\\{o:03d}")
        elif 0xDC80 <= o <= 0xDCFF:  # undecodable byte preserved by surrogateescape
            parts.append(f"\\{o - 0xDC00:03d}")
        elif 0xD800 <= o <= 0xDFFF:
            raise LuaError(f"lone surrogate U+{o:04X} cannot be encoded")
        else:
            parts.append(ch)
    parts.append('"')
    return "".join(parts)


def _number(v: int | float) -> str:
    if isinstance(v, int):
        return str(v)
    if math.isnan(v):
        return "(0/0)"
    if math.isinf(v):
        return "(1/0)" if v > 0 else "(-1/0)"
    if v.is_integer() and abs(v) < 1e16:  # note: -0.0 is written (and read back) as 0
        return str(int(v))
    return repr(v)


def _key(k: Any) -> str:
    if isinstance(k, bool):
        return "[true]" if k else "[false]"
    if isinstance(k, (int, float)):
        if isinstance(k, float) and math.isnan(k):
            raise LuaError("NaN cannot be a table key")
        return f"[{_number(k)}]"
    if isinstance(k, str):
        return f"[{_quote(k)}]"
    raise LuaError(f"unsupported table key type {type(k).__name__}")


def _sort_key(k: Any) -> tuple[int, Any]:
    if isinstance(k, bool):
        return (0, int(k))
    if isinstance(k, (int, float)):
        return (1, k)
    return (2, k)


def _items(obj: Mapping[Any, Any] | Sequence[Any]) -> list[tuple[Any, Any]]:
    if isinstance(obj, Mapping):
        return sorted(obj.items(), key=lambda kv: _sort_key(kv[0]))
    return [(i + 1, v) for i, v in enumerate(obj)]


def _dump(v: Any, depth: int, indent: str, comments: bool, out: list[str], seen: set[int]) -> None:
    if isinstance(v, bool):
        out.append("true" if v else "false")
    elif isinstance(v, (int, float)):
        out.append(_number(v))
    elif isinstance(v, str):
        out.append(_quote(v))
    elif isinstance(v, (Mapping, list, tuple)):
        items = _items(v)
        if not items:
            out.append("{}")
            return
        if id(v) in seen:
            raise LuaError("recursive structure cannot be serialized")
        seen.add(id(v))
        pad = indent * depth
        inner = indent * (depth + 1)
        out.append("\n" + pad + "{\n")
        for k, val in items:
            ks = _key(k)
            out.append(f"{inner}{ks} = ")
            _dump(val, depth + 1, indent, comments, out, seen)
            nested = isinstance(val, (Mapping, list, tuple)) and len(val) > 0
            if comments and nested:
                out.append(f", -- end of {ks}\n")
            else:
                out.append(",\n")
        out.append(pad + "}")
        seen.discard(id(v))
    else:
        raise LuaError(f"cannot serialize value of type {type(v).__name__}")


def dumps(
    obj: Any,
    name: str | None = None,
    indent: str = "\t",
    *,
    end_comments: bool = True,
) -> str:
    """Serialize *obj* as DCS-style Lua.

    With *name*, emit an assignment ``name = {...} -- end of name`` plus newline (the format of
    the files inside a .miz); without, emit just the value expression.
    """
    out: list[str] = []
    _dump(obj, 0, indent, end_comments, out, set())
    body = "".join(out)
    if name is None:
        return body.lstrip("\n")
    if not name.isidentifier():
        raise LuaError(f"invalid Lua global name {name!r}")
    tail = f" -- end of {name}" if end_comments and body.endswith("}") and body != "{}" else ""
    return f"{name} = {body}{tail}\n"


def dumps_globals(
    globals_: Mapping[str, Any], indent: str = "\t", *, end_comments: bool = True
) -> str:
    """Serialize several globals (sorted by name), the inverse of ``loads(src)``."""
    return "".join(
        dumps(globals_[n], n, indent, end_comments=end_comments) for n in sorted(globals_)
    )
