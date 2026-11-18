"""Pytest entry point for the Lua runtime: one pytest test per busted ``it`` + syntax checks.

See the docstring of ``lua/conftest.py`` for how to add specs. Run with ``uv run pytest lua -q``.
"""

from __future__ import annotations

import importlib.util
from pathlib import Path
from typing import Any

import pytest

LUA_DIR = Path(__file__).resolve().parent
REPO_ROOT = LUA_DIR.parent


def test_spec(lua_spec_case: Any, lua_env: Any) -> None:
    case = lua_spec_case
    if case.index == 0:
        pytest.fail(f"{case.path.name}: {case.load_error}", pytrace=False)
    env = lua_env(list(case.modules))
    env.run_file(case.path)
    names = list(env.g.SHIM.list().values())
    assert names[case.index - 1] == case.name, "spec registration is not deterministic"
    status, msg = env.g.SHIM.run(case.index)
    if status == "pending":
        pytest.skip("pending")
    problems: list[str] = []
    if status == "fail":
        problems.append(str(msg))
    raw = env.raw_errors()
    if raw and not env.eval("MOCK.expectRawErrors"):
        problems.append("unguarded errors escaped to DCS (MOCK.rawErrors):\n  " + "\n  ".join(raw))
    if problems:
        pytest.fail(
            "\n\n".join(problems) + "\n\n--- env log tail ---\n" + env.log_tail(), pytrace=False
        )


def test_lua51_syntax(lua_source_file: Path) -> None:
    """luac -p equivalent: every Lua file must compile under Lua 5.1 (no goto, //, etc)."""
    from lupa import lua51

    lua = lua51.LuaRuntime(unpack_returned_tuples=True)
    res = lua.eval("loadstring")(
        lua_source_file.read_text(encoding="utf-8"), "@" + lua_source_file.name
    )
    if isinstance(res, tuple) and res[0] is None:
        pytest.fail(f"Lua 5.1 syntax error: {res[1]}", pytrace=False)


def _load_bundler() -> Any:
    spec = importlib.util.spec_from_file_location(
        "bundle_lua", REPO_ROOT / "tools" / "bundle_lua.py"
    )
    assert spec and spec.loader
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def test_bundle_loads_under_mock(tmp_path: Path, lua_env: Any) -> None:
    bundler = _load_bundler()
    out = tmp_path / "dms.lua"
    bundler.bundle(out, quiet=True)
    text = out.read_text(encoding="utf-8")
    assert text.startswith("-- DMS runtime bundle")
    env = lua_env([])
    env.run_file(out)
    assert env.eval("type(DMS.VERSION)") == "string"
    assert not env.raw_errors()


def test_bundle_boots_with_config(tmp_path: Path, lua_env: Any) -> None:
    bundler = _load_bundler()
    out = tmp_path / "dms.lua"
    bundler.bundle(out, quiet=True)
    env = lua_env([])
    env.run_string('DMS_CONFIG = { version = 1, seed = 42, debug = true, missionId = "t" }')
    env.run_file(out)
    assert env.eval("DMS._booted") is True
    assert env.eval("(MOCK.logContains('started'))") is True
    assert not env.raw_errors()
