"""Lua spec harness: runs busted-style specs in lupa's Lua 5.1 runtime under the DCS mock.

How module authors add specs
----------------------------
1. Write ``lua/spec/<module>_spec.lua`` using ``describe`` / ``it`` / ``before_each`` /
   ``after_each`` and ``assert.*`` (see ``lua/mocks/busted_shim.lua``).
2. Before the spec runs, the harness loads, in order: ``mocks/busted_shim.lua``,
   ``mocks/dcs.lua`` (globals ``MOCK``, ``env``, ``timer``, ``trigger``, ...), applies
   ``MOCK.sanitize()`` (os/io/lfs/require removed like DCS) and ``MOCK.strictGlobals(true)``,
   then every module in ``lua/manifest.txt`` that exists in ``lua/src/dms/``.
   To load a subset, put a directive in the first lines of the spec::

       --# modules: core, clock, rng

   (``--# modules: none`` loads no modules.) ``DMS_CONFIG`` is nil at load time; set it in
   ``before_each`` and read it lazily in module code (``init.lua`` only boots when it is set,
   call ``DMS.boot()`` yourself in specs).
3. Every ``it`` becomes one pytest test, executed in a brand-new Lua VM (full isolation).
   A test fails if it raises, or if ``MOCK.rawErrors`` is non-empty at the end (an error
   escaped a timer callback or event handler unguarded) unless it sets
   ``MOCK.expectRawErrors = true``.
4. Run: ``uv run pytest lua -q`` (filter with ``-k bus``). Failures show the Lua traceback and
   the tail of the mocked ``env`` log.
"""

from __future__ import annotations

import re
from collections.abc import Callable
from dataclasses import dataclass
from pathlib import Path
from typing import Any

import pytest

LUA_DIR = Path(__file__).resolve().parent
REPO_ROOT = LUA_DIR.parent
SRC_DIR = LUA_DIR / "src" / "dms"
SPEC_DIR = LUA_DIR / "spec"
MOCK_DIR = LUA_DIR / "mocks"
MANIFEST = LUA_DIR / "manifest.txt"

_DIRECTIVE = re.compile(r"^--#\s*modules:\s*(.*)$")


class LuaLoadError(Exception):
    pass


def read_manifest() -> list[str]:
    names: list[str] = []
    for raw in MANIFEST.read_text(encoding="utf-8").splitlines():
        line = raw.split("#", 1)[0].strip()
        if line:
            names.append(line)
    return names


def present_modules() -> list[str]:
    return [m for m in read_manifest() if (SRC_DIR / f"{m}.lua").is_file()]


def _rel(path: Path) -> str:
    try:
        return path.resolve().relative_to(REPO_ROOT).as_posix()
    except ValueError:
        return path.as_posix()


def spec_modules(spec: Path) -> list[str]:
    for line in spec.read_text(encoding="utf-8").splitlines()[:10]:
        m = _DIRECTIVE.match(line.strip())
        if m:
            wanted = [w for w in re.split(r"[\s,]+", m.group(1).strip()) if w]
            if wanted == ["none"]:
                return []
            missing = [w for w in wanted if not (SRC_DIR / f"{w}.lua").is_file()]
            if missing:
                raise LuaLoadError(f"{spec.name}: modules not found: {missing}")
            order = read_manifest()
            return sorted(wanted, key=lambda w: order.index(w) if w in order else len(order))
    return present_modules()


class LuaEnv:
    """A fresh Lua 5.1 VM with shim + DCS mock (+ modules) loaded."""

    def __init__(self, modules: list[str] | None = None, strict: bool = True) -> None:
        from lupa import lua51

        self.lua = lua51.LuaRuntime(unpack_returned_tuples=True)
        self._loadstring = self.lua.eval("loadstring")
        self.run_file(MOCK_DIR / "busted_shim.lua")
        self.run_file(MOCK_DIR / "dcs.lua")
        self.g = self.lua.globals()
        self.g.MOCK.sanitize()
        if strict:
            self.g.MOCK.strictGlobals(True)
        for name in modules if modules is not None else present_modules():
            self.run_file(SRC_DIR / f"{name}.lua")

    def run_file(self, path: Path) -> Any:
        return self.run_string(path.read_text(encoding="utf-8"), "@" + _rel(path))

    def run_string(self, src: str, chunkname: str = "=snippet") -> Any:
        res = self._loadstring(src, chunkname)
        if isinstance(res, tuple):
            chunk, err = res[0], res[1] if len(res) > 1 else "?"
        else:
            chunk, err = res, None
        if chunk is None:
            raise LuaLoadError(str(err))
        try:
            return chunk()
        except Exception as exc:  # lupa.LuaError
            raise LuaLoadError(f"{chunkname.lstrip('@=')}: {exc}") from exc

    def eval(self, expr: str) -> Any:
        return self.run_string("return " + expr)

    def log_tail(self, n: int = 40) -> str:
        return str(
            self.run_string(
                "local t, L = {}, MOCK.log "
                f"for i = math.max(1, #L - {n}), #L do "
                "t[#t + 1] = L[i].level .. ': ' .. L[i].msg end "
                "return table.concat(t, '\\n')"
            )
        )

    def raw_errors(self) -> list[str]:
        n = int(self.eval("#MOCK.rawErrors"))
        return [
            str(self.eval(f"MOCK.rawErrors[{i}].where .. ': ' .. MOCK.rawErrors[{i}].err"))
            for i in range(1, n + 1)
        ]


@dataclass(frozen=True)
class SpecCase:
    path: Path
    index: int  # 1-based test index in SHIM.tests; 0 = load failure
    name: str
    modules: tuple[str, ...] = ()
    load_error: str = ""


def collect_spec_cases() -> list[SpecCase]:
    cases: list[SpecCase] = []
    for spec in sorted(SPEC_DIR.glob("*_spec.lua")):
        try:
            mods = spec_modules(spec)
            env = LuaEnv(mods)
            env.run_file(spec)
            names = list(env.g.SHIM.list().values())
        except Exception as exc:
            cases.append(SpecCase(spec, 0, "<load>", (), str(exc)))
            continue
        if not names:
            cases.append(SpecCase(spec, 0, "<empty>", tuple(mods), "spec registered no tests"))
        for i, name in enumerate(names, start=1):
            cases.append(SpecCase(spec, i, str(name), tuple(mods)))
    return cases


def _case_id(c: SpecCase) -> str:
    return f"{c.path.stem}::{c.name}"


def pytest_generate_tests(metafunc: pytest.Metafunc) -> None:
    if "lua_spec_case" in metafunc.fixturenames:
        cases = collect_spec_cases()
        metafunc.parametrize("lua_spec_case", cases, ids=[_case_id(c) for c in cases])
    if "lua_source_file" in metafunc.fixturenames:
        files = sorted(
            p
            for d in (SRC_DIR, MOCK_DIR, SPEC_DIR, LUA_DIR / "plugins")
            if d.is_dir()
            for p in d.rglob("*.lua")
        )
        metafunc.parametrize("lua_source_file", files, ids=[_rel(p) for p in files])


@pytest.fixture
def lua_env() -> Callable[..., LuaEnv]:
    """Factory: ``lua_env(modules=None, strict=True)`` -> fresh LuaEnv for Python-driven tests."""
    return LuaEnv
