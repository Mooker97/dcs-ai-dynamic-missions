"""Tests for tools/pedal_rudder: Python mixer and installer (no pygame), Lua bridge (lupa)."""

from __future__ import annotations

import importlib.util
import sys
from pathlib import Path
from types import ModuleType
from typing import Any

import pytest

DIR = Path(__file__).resolve().parents[1] / "pedal_rudder"


def _load() -> ModuleType:
    spec = importlib.util.spec_from_file_location("dms_pedal_rudder", DIR / "pedal_rudder.py")
    assert spec and spec.loader
    mod = importlib.util.module_from_spec(spec)
    sys.modules["dms_pedal_rudder"] = mod
    spec.loader.exec_module(mod)
    return mod


pr = _load()


# ---------------------------------------------------------------- mixing


def test_normalize_rest_low_and_inverted_axes() -> None:
    up = pr.PedalAxis("MOZA", 2, rest=-1.0, full=1.0)
    down = pr.PedalAxis("MOZA", 3, rest=1.0, full=-1.0)
    assert pr.normalize(-1.0, up, 0.0) == 0.0
    assert pr.normalize(1.0, up, 0.0) == 1.0
    assert pr.normalize(0.0, up, 0.0) == pytest.approx(0.5)
    assert pr.normalize(1.0, down, 0.0) == 0.0
    assert pr.normalize(-1.0, down, 0.0) == 1.0


def test_normalize_deadzone_and_clamp() -> None:
    p = pr.PedalAxis("MOZA", 0, rest=-1.0, full=1.0)
    assert pr.normalize(-0.95, p, 0.05) == 0.0  # 2.5% travel, inside deadzone
    assert pr.normalize(1.5, p, 0.05) == 1.0
    assert pr.normalize(-2.0, p, 0.05) == 0.0
    assert pr.normalize(0.3, pr.PedalAxis("MOZA", 0, 0.3, 0.3), 0.0) == 0.0  # zero span


def test_mix_direction_curve_invert() -> None:
    assert pr.mix(0.0, 0.0) == 0.0
    assert pr.mix(1.0, 0.0) == -1.0  # left pedal -> left rudder
    assert pr.mix(0.0, 1.0) == 1.0
    assert pr.mix(0.5, 0.5) == 0.0
    assert pr.mix(0.0, 0.5, curve=2.0) == pytest.approx(0.25)
    assert pr.mix(0.5, 0.0, curve=2.0) == pytest.approx(-0.25)
    assert pr.mix(0.0, 1.0, invert=True) == -1.0


def test_pick_moved_axis() -> None:
    rest = {("MOZA", 0): 0.0, ("MOZA", 1): -1.0, ("MOZA", 2): -1.0}
    pressed = {("MOZA", 0): 0.1, ("MOZA", 1): -1.0, ("MOZA", 2): 0.9}
    assert pr.pick_moved_axis(rest, pressed) == (("MOZA", 2), pytest.approx(1.9))
    assert pr.pick_moved_axis(rest, pressed, {("MOZA", 2)}) is None
    assert pr.pick_moved_axis(rest, rest) is None


def test_bars() -> None:
    assert pr.bar(0.5, 4) == "[##..]"
    assert pr.signed_bar(0.0, 3) == "[---|---]"
    assert pr.signed_bar(-1.0, 3) == "[===|---]"
    assert pr.signed_bar(0.34, 3) == "[---|=--]"
    assert "DCS linked" in pr.status_line(0, 1, 1, True, 100)


# ---------------------------------------------------------------- config


def test_config_round_trip(tmp_path: Path) -> None:
    cfg = pr.Config(left=pr.PedalAxis("MOZA R9", 4, -1.0, 1.0), curve=1.5)
    path = tmp_path / "c.json"
    pr.save_config(cfg, path)
    assert pr.load_config(path) == cfg
    assert pr.load_config(tmp_path / "missing.json") == pr.Config()


def test_config_rejects_unknown_and_bad_values() -> None:
    with pytest.raises(ValueError, match="unknown"):
        pr.Config.from_dict({"lefft": None})
    with pytest.raises(ValueError, match="curve"):
        pr.Config.from_dict({"curve": 0})


# ---------------------------------------------------------------- install


BIOS = "dofile(lfs.writedir()..[[Scripts\\DCS-BIOS\\BIOS.lua]])"


def test_export_line_add_remove_idempotent() -> None:
    added = pr.add_export_line(BIOS)
    assert added == BIOS + "\n" + pr.EXPORT_LINE + "\n"
    assert pr.add_export_line(added) == added
    assert pr.remove_export_line(added) == BIOS + "\n"
    assert pr.add_export_line("") == pr.EXPORT_LINE + "\n"


def test_install_uninstall(tmp_path: Path) -> None:
    scripts = tmp_path / "Scripts"
    scripts.mkdir()
    (scripts / "Export.lua").write_text(BIOS + "\n", encoding="utf-8")
    pr.install(tmp_path)
    pr.install(tmp_path)  # twice is harmless
    export = (scripts / "Export.lua").read_text(encoding="utf-8")
    assert export.count(pr.EXPORT_TAG) == 1
    assert export.startswith(BIOS)
    assert (scripts / "DMS" / "PedalRudder.lua").read_text() == pr.LUA_SOURCE.read_text()
    assert (scripts / pr.EXPORT_BACKUP_NAME).read_text(encoding="utf-8") == BIOS + "\n"
    pr.uninstall(tmp_path)
    assert (scripts / "Export.lua").read_text(encoding="utf-8") == BIOS + "\n"
    assert not (scripts / "DMS").exists()


# ---------------------------------------------------------------- Lua bridge (lupa, Lua 5.1)

LUA_HARNESS = r"""
H = { t = 0, inbox = {}, sent = {}, cmds = {}, logs = {}, bound = nil, biosFrames = 0 }
log = { INFO = 1, WARNING = 2, write = function(_, _, m) table.insert(H.logs, m) end }
lfs = { currentdir = function() return "C:/DCS" end }
function LoSetCommand(c, v) table.insert(H.cmds, { c, v }) end
local fakeSocket = {
  gettime = function() return H.t end,
  udp = function()
    return {
      setsockname = function(_, ip, port) H.bound = ip .. ":" .. port; return 1 end,
      settimeout = function() end,
      close = function() H.closed = true end,
      receivefrom = function()
        local m = table.remove(H.inbox, 1)
        if m then return m, "127.0.0.1", 50000 end
        return nil, "timeout"
      end,
      sendto = function(_, d, ip, port) table.insert(H.sent, d) end,
    }
  end,
}
package.loaded["socket"] = fakeSocket
-- what DCS-BIOS would have defined before us
function LuaExportBeforeNextFrame() H.biosFrames = H.biosFrames + 1 end
"""


@pytest.fixture
def lua() -> Any:
    from lupa import lua51

    rt = lua51.LuaRuntime(unpack_returned_tuples=True)
    rt.execute(LUA_HARNESS)
    rt.execute((DIR / "PedalRudder.lua").read_text(encoding="utf-8"))
    rt.execute("LuaExportStart()")
    return rt


def _cmds(rt: Any) -> list[tuple[int, float]]:
    return [(int(c[1]), float(c[2])) for c in rt.eval("H.cmds").values()]


def test_lua_feeds_latest_value_and_chains(lua: Any) -> None:
    assert lua.eval("H.bound") == "127.0.0.1:47801"
    lua.execute('H.inbox = { "0.2", "junk", "-0.5" }; LuaExportBeforeNextFrame()')
    assert _cmds(lua) == [(2003, -0.5)]
    assert lua.eval("H.biosFrames") == 1  # previous export still called
    assert list(lua.eval("H.sent").values()) == ["DMS-ACK"]


def test_lua_clamps_and_releases_when_stale(lua: Any) -> None:
    lua.execute('H.inbox = { "3" }; LuaExportBeforeNextFrame()')
    lua.execute("H.t = 0.3; LuaExportBeforeNextFrame()")  # no packet, still fresh: hold value
    lua.execute("H.t = 1.0; LuaExportBeforeNextFrame()")  # stale: release once
    lua.execute("H.t = 2.0; LuaExportBeforeNextFrame()")  # then leave the rudder alone
    assert _cmds(lua) == [(2003, 1.0), (2003, 1.0), (2003, 0.0)]


def test_lua_idle_never_touches_rudder(lua: Any) -> None:
    lua.execute("LuaExportBeforeNextFrame(); LuaExportStop()")
    assert _cmds(lua) == []
    assert lua.eval("H.closed") is True


def test_lua_error_does_not_break_other_exports(lua: Any) -> None:
    lua.execute("LoSetCommand = nil; H.inbox = { '0.1' }; LuaExportBeforeNextFrame()")
    assert lua.eval("H.biosFrames") == 1
    assert any("frame failed" in m for m in lua.eval("H.logs").values())
