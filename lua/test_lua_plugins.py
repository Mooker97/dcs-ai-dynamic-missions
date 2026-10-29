"""Optional plugins: vendored pins and the Skynet adapter under the DCS mock (lupa, Lua 5.1).

The adapter must no-op cleanly when Skynet/MIST/DMS are absent, and build an IADS from
prefix-matching SAM groups (existing and DMS-spawned) when a Skynet-shaped API is present.
"""

from __future__ import annotations

import hashlib
from pathlib import Path
from typing import Any

import pytest
from dms_gen import plugins

LUA_DIR = Path(__file__).resolve().parent
REPO_ROOT = LUA_DIR.parent
ADAPTER = REPO_ROOT / plugins.PLUGINS["skynet_adapter"].file

# A minimal Skynet-shaped stub: records what the adapter asks of it.
SKYNET_STUB = """
rawset(_G, "mist", {})
rawset(_G, "samTypesDB", {
  ["SA-6"] = { type = "single", searchRadar = { ["Kub 1S91 str"] = {} },
               launchers = { ["Kub 2P25 ln"] = {} } },
})
local S = { created = {}, sams = {}, ewrs = {}, activated = 0 }
S.__index = S
function S:create(name)
  local o = setmetatable({ name = name }, S)
  S.created[#S.created + 1] = name
  return o
end
function S:addSAMSite(n) S.sams[#S.sams + 1] = n return { n = n } end
function S:addEarlyWarningRadar(n) S.ewrs[#S.ewrs + 1] = n return { n = n } end
function S:activate() S.activated = S.activated + 1 end
function S:addRadioMenu() end
rawset(_G, "SkynetIADS", S)
"""


def _boot(env: Any) -> None:
    env.run_string(
        'rawset(_G, "DMS_CONFIG", { version = 1, seed = 1, debug = true, missionId = "t" })'
    )
    env.run_string("DMS.boot()")


def test_vendored_plugins_match_pins() -> None:
    pins = (REPO_ROOT / "lua" / "plugins" / "PINS.md").read_text(encoding="utf-8")
    for p in plugins.PLUGINS.values():
        path = REPO_ROOT / p.file
        assert path.is_file(), p.file
        if p.adapter:
            continue
        data = path.read_bytes()
        assert b"\r\n" not in data, f"{p.file}: vendored with CRLF (git stores LF)"
        assert hashlib.sha256(data).hexdigest() == p.sha256, p.file
        assert p.sha256 in pins and p.version in pins and p.url in pins, p.name


def test_adapter_noops_without_skynet(lua_env: Any) -> None:
    env = lua_env()
    _boot(env)
    env.run_file(ADAPTER)
    env.run_string("MOCK.advance(10)")
    assert env.eval("DMS.SkynetAdapter.iads") is None
    assert env.eval("(MOCK.logContains('Skynet%-IADS not loaded'))") is True
    assert not env.raw_errors()


def test_adapter_noops_without_dms(lua_env: Any) -> None:
    env = lua_env([])
    env.run_file(ADAPTER)  # no DMS at all: must not raise under strict globals
    assert env.eval("rawget(_G, 'DMS')") is None
    assert env.eval("(MOCK.logContains('adapter disabled'))") is True
    assert not env.raw_errors()


def test_adapter_skips_skynet_without_mist(lua_env: Any) -> None:
    env = lua_env()
    _boot(env)
    env.run_string(SKYNET_STUB)
    env.run_string('rawset(_G, "mist", nil)')
    env.run_file(ADAPTER)
    assert env.eval("#SkynetIADS.created") == 0
    assert env.eval("(MOCK.logContains('without MIST'))") is True


def test_adapter_builds_iads_from_prefixed_sams(lua_env: Any) -> None:
    env = lua_env()
    _boot(env)
    env.run_string(SKYNET_STUB)
    env.run_string(
        """
        MOCK.addGroup{ name = "DMS_sa6_1", coalition = 1, type = "Kub 2P25 ln", count = 2 }
        MOCK.addGroup{ name = "DMS_trucks_1", coalition = 1, type = "Ural-375", count = 2 }
        MOCK.addGroup{ name = "sa6_site_1", coalition = 1, type = "Kub 2P25 ln" }
        MOCK.addGroup{ name = "DMS_blue_sa6", coalition = 2, type = "Kub 2P25 ln" }
        """
    )
    env.run_file(ADAPTER)
    assert list(env.g.SkynetIADS.sams.values()) == ["DMS_sa6_1"]
    assert env.eval("SkynetIADS.activated") == 0
    env.run_string("MOCK.advance(3)")
    assert env.eval("SkynetIADS.activated") == 1
    assert env.eval("DMS.SkynetAdapter.active") is True
    # a DMS runtime spawn joins the running IADS
    env.run_string(
        """
        MOCK.addGroup{ name = "DMS_sa6_2", coalition = 1, type = "Kub 1S91 str" }
        DMS.Bus.emit("spawner.spawned", { group = "DMS_sa6_2" })
        DMS.Bus.emit("spawner.spawned", { group = "DMS_sa6_2" })
        """
    )
    # deferred: the controller of a fresh group is not touched before SPAWN_DELAY_SEC (1.5 s)
    assert list(env.g.SkynetIADS.sams.values()) == ["DMS_sa6_1"]
    env.run_string("MOCK.advance(1)")
    assert list(env.g.SkynetIADS.sams.values()) == ["DMS_sa6_1"]
    env.run_string("MOCK.advance(1)")
    assert list(env.g.SkynetIADS.sams.values()) == ["DMS_sa6_1", "DMS_sa6_2"]
    assert env.eval("(MOCK.logContains('%[DMS%]%[SkynetAdapter%] SAM site DMS_sa6_2 added'))")
    assert not env.raw_errors()


def test_adapter_respects_options(lua_env: Any) -> None:
    env = lua_env()
    _boot(env)
    env.run_string(SKYNET_STUB)
    env.run_string(
        """
        rawset(_G, "DMS_SKYNET", { prefixes = { "sa6_" }, coalition = "blue", name = "Blue" })
        MOCK.addGroup{ name = "sa6_b", coalition = 2, type = "Kub 2P25 ln" }
        MOCK.addGroup{ name = "DMS_sa6_1", coalition = 2, type = "Kub 2P25 ln" }
        """
    )
    env.run_file(ADAPTER)
    assert list(env.g.SkynetIADS.created.values()) == ["Blue"]
    assert list(env.g.SkynetIADS.sams.values()) == ["sa6_b"]


def test_adapter_defaults_to_enemy_of_players(lua_env: Any) -> None:
    env = lua_env()
    env.run_string(
        'rawset(_G, "DMS_CONFIG", { version = 1, seed = 1, debug = true, missionId = "t",'
        " players = { coalition = 1 } })"
    )
    env.run_string("DMS.boot()")
    env.run_string(SKYNET_STUB)
    env.run_string(
        """
        MOCK.addGroup{ name = "DMS_red_sa6", coalition = 1, type = "Kub 2P25 ln" }
        MOCK.addGroup{ name = "DMS_blue_sa6", coalition = 2, type = "Kub 2P25 ln" }
        """
    )
    env.run_file(ADAPTER)
    assert list(env.g.SkynetIADS.sams.values()) == ["DMS_blue_sa6"]
    assert env.eval("(MOCK.logContains('coalition blue'))") is True


def test_adapter_skips_ambush_sam_spawns(lua_env: Any) -> None:
    env = lua_env()
    _boot(env)
    env.run_string(SKYNET_STUB)
    env.run_file(ADAPTER)
    env.run_string(
        """
        DMS.Encounters.add({ id = "popup", kind = "ambush_sam", template = "sa6" })
        DMS.Encounters.add({ id = "site", kind = "pool", pool = "sams" })
        MOCK.addGroup{ name = "DMS_sa6_7", coalition = 1, type = "Kub 2P25 ln" }
        MOCK.addGroup{ name = "DMS_sa6_8", coalition = 1, type = "Kub 2P25 ln" }
        DMS.Bus.emit("spawner.spawned", { group = "DMS_sa6_7", encounter = "popup" })
        DMS.Bus.emit("spawner.spawned", { group = "DMS_sa6_8", encounter = "site" })
        MOCK.advance(3)
        """
    )
    assert list(env.g.SkynetIADS.sams.values()) == ["DMS_sa6_8"]
    assert env.eval("(MOCK.logContains('skip DMS_sa6_7: ambush_sam encounter popup'))") is True
    assert not env.raw_errors()


def test_adapter_disabled(lua_env: Any) -> None:
    env = lua_env()
    _boot(env)
    env.run_string(SKYNET_STUB)
    env.run_string('rawset(_G, "DMS_SKYNET", { enabled = false })')
    env.run_file(ADAPTER)
    assert env.eval("#SkynetIADS.created") == 0


@pytest.mark.parametrize("name", ["mist", "skynet"])
def test_vendored_plugin_loads_under_mock(name: str, lua_env: Any) -> None:
    """MIST and Skynet load in the DCS mock (non-strict) and define their globals."""
    env = lua_env([], strict=False)
    for dep in plugins.resolve([name]):
        if not dep.adapter:
            env.run_file(REPO_ROOT / dep.file)
    glob = {"mist": "mist", "skynet": "SkynetIADS"}[name]
    assert env.eval(f"type(rawget(_G, '{glob}'))") == "table"
