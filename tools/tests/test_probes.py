"""Tests for the DCS-unknowns probes (tools/dcs_harness/probes). No DCS is launched.

* structural: every generated probe .miz has its script embedded and a MISSION START trigger
  that runs it, plus the groups the script expects;
* Lua: every probe script compiles under Lua 5.1 and runs against a small DCS stub, and the
  lines it logs parse into a non-empty answer;
* parser: hand-written dcs.log snippets for the interesting outcomes (negative ones included).
"""

from __future__ import annotations

import importlib.util
import re
import sys
import zipfile
from pathlib import Path
from types import ModuleType
from typing import Any

import pytest

PROBES_DIR = Path(__file__).resolve().parents[1] / "dcs_harness" / "probes"
TS = "2026-10-29 10:00:00.000"


def _load(name: str, file: str) -> ModuleType:
    if name in sys.modules:
        return sys.modules[name]
    spec = importlib.util.spec_from_file_location(name, PROBES_DIR / file)
    assert spec and spec.loader
    mod = importlib.util.module_from_spec(spec)
    sys.modules[name] = mod
    spec.loader.exec_module(mod)
    return mod


pp = _load("dms_probe_parse_probes", "parse_probes.py")
ALL = list(pp.PROBES)


def log_text(msgs: list[str], sub: str = "SCRIPTING") -> str:
    return "".join(f"{TS} INFO    {sub} (Main): {m}\n" for m in msgs)


def answer(pid: str, msgs: list[str], **kw: Any) -> dict[str, Any]:
    run = pp.parse_run(log_text(msgs))
    res: dict[str, Any] = pp.answer_all([run], [pid], **kw)[0]
    return res


# ------------------------------------------------------------------------------------------
# structural: generated miz files
# ------------------------------------------------------------------------------------------


@pytest.fixture(scope="module")
def built(tmp_path_factory: pytest.TempPathFactory) -> dict[str, Path]:
    pytest.importorskip("dms_gen")
    bp = _load("dms_probe_build_probes", "build_probes.py")
    out = tmp_path_factory.mktemp("probes")
    return {pid: bp.build_probe(pid, out) for pid in ALL}


def _mission(miz: Path) -> tuple[Any, Any, zipfile.ZipFile]:
    from dms_core.miz import MizFile

    m = MizFile.open(miz)
    return m.table("mission"), m.table("l10n/DEFAULT/mapResource"), zipfile.ZipFile(miz)


def _arr(t: Any) -> list[Any]:
    if isinstance(t, dict):
        return [t[k] for k in sorted(t)]
    return list(t or [])


def _group_names(mission: Any) -> set[str]:
    names: set[str] = set()
    for coal in mission["coalition"].values():
        for c in _arr(coal.get("country")):
            for g in _arr(c.get("vehicle", {}).get("group")):
                names.add(g["name"])
    return names


@pytest.mark.parametrize("pid", ALL)
def test_probe_miz_runs_its_script_at_mission_start(built: dict[str, Path], pid: str) -> None:
    miz = built[pid]
    assert miz.name == pp.PROBES[pid].miz_name
    mission, res, z = _mission(miz)
    script = f"dms_probe_{pid}.lua"
    assert f"l10n/DEFAULT/{script}" in z.namelist()
    rules = _arr(mission["trigrules"])
    start = [r for r in rules if r["predicate"] == "triggerStart"]
    assert len(start) == 1
    acts = _arr(start[0]["actions"])
    assert [a["predicate"] for a in acts] == ["a_do_script_file"]
    assert res[acts[0]["file"]] == script
    # the compiled trig table carries the same action
    assert any(acts[0]["file"] in a for a in _arr(mission["trig"]["actions"]))
    body = z.read(f"l10n/DEFAULT/{script}").decode("utf-8")
    assert "-- ==== tools/dcs_harness/probes/lua/common.lua ====" in body
    assert f"-- ==== tools/dcs_harness/probes/lua/{pp.PROBES[pid].script} ====" in body
    assert f'local PROBE = "{pid}"' in body
    assert "Probe Anchor" in _group_names(mission)


def test_k1_has_one_group_per_route_variant(built: dict[str, Path]) -> None:
    bp = _load("dms_probe_build_probes", "build_probes.py")
    mission, _, z = _mission(built["k1"])
    assert set(bp.K1_GROUPS) <= _group_names(mission)
    body = z.read("l10n/DEFAULT/dms_probe_k1.lua").decode("utf-8")
    for name in bp.K1_GROUPS:
        assert f'"{name}"' in body


def test_k5_embeds_the_runtime_rng(built: dict[str, Path]) -> None:
    _, _, z = _mission(built["k5"])
    body = z.read("l10n/DEFAULT/dms_probe_k5.lua").decode("utf-8")
    assert "-- ==== lua/src/dms/rng.lua ====" in body
    assert body.index("function Rng.seed") < body.index('local PROBE = "k5"')


def test_harness_command_carries_k7_inject() -> None:
    bp = _load("dms_probe_build_probes", "build_probes.py")
    cmd = bp.harness_command("k7", "x.miz")
    assert cmd[cmd.index("--inject") + 1] == pp.K7_INJECT
    k1 = bp.harness_command("k1", "x.miz")
    assert k1[k1.index("--accel") + 1] == "8"
    assert "--inject" not in k1


# ------------------------------------------------------------------------------------------
# Lua: compile and run every probe against a DCS stub
# ------------------------------------------------------------------------------------------

STUB = r"""
LOG = {}
NOW = 0
QUEUE = {}
HANDLERS = {}
PANELS = {}
GROUPS = {}
env = { info = function(s) LOG[#LOG + 1] = s end }
timer = {
  getTime = function() return NOW end,
  getAbsTime = function() return 36000 + NOW end,
  scheduleFunction = function(f, arg, t)
    QUEUE[#QUEUE + 1] = { f = f, arg = arg, t = t }
    return #QUEUE
  end,
}
function RUN(maxT)
  while true do
    local best, bi = nil, nil
    for i, q in ipairs(QUEUE) do
      if not best or q.t < best.t then best, bi = q, i end
    end
    if not best or best.t > maxT then return end
    table.remove(QUEUE, bi)
    if best.t > NOW then NOW = best.t end
    best.f(best.arg, NOW)
  end
end
world = {
  event = { S_EVENT_BIRTH = 15 },
  addEventHandler = function(h) HANDLERS[#HANDLERS + 1] = h end,
  getMarkPanels = function()
    local out = {}
    for _, p in ipairs(PANELS) do out[#out + 1] = p end
    return out
  end,
}
local function mkGroup(name)
  local ctrl = {}
  function ctrl:setTask(t) self.task = t end
  function ctrl:hasTask() return self.task ~= nil end
  local unit = {}
  function unit:isExist() return true end
  function unit:getPoint() return { x = 0, y = 100, z = 0 } end
  local g = {}
  function g:getUnit() return unit end
  function g:getController() return ctrl end
  GROUPS[name] = g
end
for _, n in ipairs({ "Probe Anchor", "K1 one_point", "K1 two_no_current", "K1 two_current_first",
                     "K1 two_current_first_road", "K1 control" }) do mkGroup(n) end
Group = { getByName = function(n) return GROUPS[n] end, Category = { GROUND = 2 } }
local function panel(id, text, p, coal)
  PANELS[#PANELS + 1] = {
    idx = id, text = text, pos = p, coalition = coal, groupID = 4294967295, time = NOW,
  }
end
trigger = { action = {
  markToAll = function(id, text, p) panel(id, text, p, 255) end,
  markToCoalition = function(id, text, p, c) panel(id, text, p, c) end,
  circleToAll = function(c, id, p) panel(id, "", p, 255) end,
  textToAll = function(c, id, p) panel(id, "", p, 255) end,
  lineToAll = function(c, id, p) panel(id, "", p, 255) end,
  quadToAll = function(c, id, p) panel(id, "", p, 255) end,
  removeMark = function(id)
    for i, p in ipairs(PANELS) do if p.idx == id then table.remove(PANELS, i) return end end
  end,
  radioTransmission = function(file, p, mod, loop, freq, power, name)
    if type(p) ~= "table" or type(freq) ~= "number" then error("bad argument") end
  end,
  stopRadioTransmission = function() end,
} }
land = { getHeight = function() return 100 end, isVisible = function() return true end }
country = { id = { USA = 2 } }
coalition = { addGroup = function()
  for _, h in ipairs(HANDLERS) do h:onEvent({ id = 15 }) end
end }
net = {
  get_player_list = function() return { 1 } end,
  get_my_player_id = function() return 1 end,
  get_player_info = function(id, attr)
    local info = { id = id, name = "Player", side = 0, slot = "", ucid = "secret" }
    if attr then return info[attr] end
    return info
  end,
}
"""


def _lua() -> Any:
    lupa = pytest.importorskip("lupa")
    return lupa.lua51.LuaRuntime(unpack_returned_tuples=True)


def _script(pid: str) -> str:
    bp = _load("dms_probe_build_probes", "build_probes.py")
    return str(bp.probe_script(pid))


def run_probe(pid: str, inject: str = "") -> list[str]:
    """Run one probe script against the stub and return everything it passed to env.info."""
    lua = _lua()
    lua.execute(STUB)
    if inject:
        lua.execute(inject)
    lua.execute(_script(pid))
    lua.execute("RUN(1000)")
    log = lua.eval("LOG")
    return [str(log[i]) for i in range(1, len(log) + 1)]


FORBIDDEN = [r"\bgoto\b", r"::\w+::", r"//", r"table\.unpack", r"\brequire\b", r"\bos\.", r"\bio\."]


@pytest.mark.parametrize("pid", ALL)
def test_probe_script_is_lua51_and_sandbox_safe(pid: str) -> None:
    src = _script(pid)
    code = "\n".join(re.sub(r"--.*$", "", ln) for ln in src.splitlines())
    for pat in FORBIDDEN:
        assert not re.search(pat, code), f"{pid}: forbidden {pat}"
    lua = _lua()
    fn = lua.eval("function(s) local f, err = loadstring(s) return f ~= nil, err end")
    ok, err = fn(src)
    assert ok, err


@pytest.mark.parametrize("pid", ALL)
def test_probe_runs_against_stub_and_parses(pid: str) -> None:
    msgs = run_probe(pid, inject=pp.K7_INJECT if pid == "k7" else "")
    assert msgs[-1] == "[DMS.TEST] DONE"
    assert any(f"probe={pid} done=1" in m for m in msgs)
    res = answer(pid, msgs)
    assert res["status"] not in ("no_data", "error"), res
    assert not any("never logged done" in n for n in res["notes"])


def test_stub_k1_answers_every_variant() -> None:
    a = answer("k1", run_probe("k1"))["answer"]
    assert set(a["variants"]) == {
        "one_point",
        "two_points_no_current",
        "two_points_current_first",
        "two_points_current_first_on_road",
        "control_no_task",
    }
    assert a["variants"]["one_point"]["points"] == 1
    assert a["variants"]["two_points_current_first"]["points"] == 2
    assert a["one_point_moves"] is False  # the stub never moves anything


def test_stub_k2_shapes_and_initiator() -> None:
    a = answer("k2", run_probe("k2"))["answer"]
    assert a["shapes_listed"] is True
    assert a["lines_quads_listed"] is True
    assert a["script_initiator_nil"] is True
    assert a["removed_mark_still_listed"] is False
    assert len(a["our_panels"]) == 6


def test_stub_k3_arity() -> None:
    a = answer("k3", run_probe("k3"))["answer"]
    assert a["arity7_ok"] is True and a["arity9_ok"] is True
    assert a["validates_arguments"] is True


def test_stub_k5_two_runs() -> None:
    runs = [pp.parse_run(log_text(run_probe("k5")), f"run{i}") for i in range(2)]
    a = pp.answer_k5(runs)
    assert a["answer"]["runs"] == 2
    assert a["answer"]["per_run"][0]["phase"] == "first_birth"
    assert a["status"] == "answered"


def test_stub_k6_all_fire() -> None:
    a = answer("k6", run_probe("k6"))["answer"]
    assert len(a["labels"]) == 10
    assert a["start_now_fires"] is True and a["callback_now_fires"] is True


def test_stub_k7_inject_seen() -> None:
    a = answer("k7", run_probe("k7", inject=pp.K7_INJECT))["answer"]
    assert a["inject_ran_in_mission"] is True
    assert a["global_visible_to_mission_script"] is True
    assert a["works"] is True


def test_stub_k9_all_intact_and_lua_matches_python() -> None:
    msgs = run_probe("k9")
    a = answer("k9", msgs)["answer"]
    assert a["all_intact"] is True
    assert a["max_intact_len"] == 65536
    for row in a["lengths"]:
        assert row["logged_len"] == row["len"]


def test_stub_k10_player_api() -> None:
    msgs = run_probe("k10")
    assert not any("secret" in m for m in msgs)  # ucid never logged
    a = answer("k10", msgs)["answer"]
    assert a["get_player_list_ok"] is True
    assert a["player_count"] == 1
    assert a["get_player_info_ok"] is True
    assert "get_player_list" in a["net_keys"]
    assert a["player_info_keys"] == "id,name,side,slot,ucid"


def test_lua_quote_round_trips_through_parser() -> None:
    lua = _lua()
    lua.execute(STUB)
    lua.execute(_script("k8"))  # any probe: loads common.lua
    tricky = ["a b", 'x="y"', "back\\slash", "tab\there", "line\nbreak", "", "plain"]
    for s in tricky:
        lua.execute("LOG = {}")
        lua.globals().DMS_PROBE.log("kx", "v", s, "after", "ok")
        line = str(lua.eval("LOG[1]"))
        kv = pp.parse_kv(line.split("[DMS.PROBE] ", 1)[1])
        assert kv["v"] == s and kv["after"] == "ok", line


# ------------------------------------------------------------------------------------------
# parser: fixture log snippets
# ------------------------------------------------------------------------------------------


def test_no_data_when_probe_absent() -> None:
    res = answer("k6", ["[DMS][Init] boot"])
    assert res["status"] == "no_data"
    assert pp.answer_all([pp.parse_run(log_text(["[DMS][Init] boot"]))]) == []


def test_k1_fixture_one_point_stays_put() -> None:
    p = "[DMS.PROBE] probe=k1"
    msgs = [
        f"{p} phase=route_set variant=one_point points=1 ok=true err=nil t=2.000",
        f"{p} phase=route_set variant=two_points_current_first points=2 ok=true err=nil t=2.000",
        f"{p} phase=route_set variant=control_no_task points=0 ok=true err=nil t=2.000",
        f"{p} phase=final variant=one_point moved_m=0.0 has_task=false t=122.000",
        f"{p} phase=final variant=two_points_current_first moved_m=960.4 has_task=true t=122.0",
        f"{p} phase=final variant=control_no_task moved_m=0.0 has_task=false t=122.000",
        f"{p} done=1 t=122.000",
    ]
    res = answer("k1", msgs)
    assert res["status"] == "answered"
    assert res["answer"]["one_point_moves"] is False
    assert res["answer"]["two_points_current_first_moves"] is True
    assert res["answer"]["control_moves"] is False


def test_k1_fixture_cut_short_is_partial() -> None:
    msgs = ["[DMS.PROBE] probe=k1 phase=mid variant=one_point moved_m=3.0 has_task=true t=62"]
    res = answer("k1", msgs)
    assert res["status"] == "partial"
    assert any("never logged done" in n for n in res["notes"])


def test_k3_fixture_unvalidated_control_noted() -> None:
    p = "[DMS.PROBE] probe=k3 phase=call"
    msgs = [
        f"{p} variant=arity7 nargs=7 ok=true err=nil",
        f'{p} variant=arity9 nargs=9 ok=false err="[string \\"x\\"]:1: too many args"',
        f"{p} variant=bad_arg_control nargs=7 ok=true err=nil",
        '[DMS.PROBE] probe=k3 phase=events count=0 ids=""',
        "[DMS.PROBE] probe=k3 done=1 t=8.000",
    ]
    a = answer("k3", msgs)
    assert a["answer"]["arity9_ok"] is False
    assert a["answer"]["calls"]["arity9"]["err"] == '[string "x"]:1: too many args'
    assert a["answer"]["validates_arguments"] is False
    assert any("did not raise" in n for n in a["notes"])


def test_k5_fixture_identical_seeds() -> None:
    line = (
        "[DMS.PROBE] probe=k5 phase=first_birth t=0.000000 abs=36000.000000 gc_kb=100.000 "
        'table_addr="table: 0x1" math_random=0.1,0.2,0.3 launch_entropy=7 seed=12345 '
        "picks=1,2,3,4,5"
    )
    runs = [
        pp.parse_run(log_text([line, "[DMS.PROBE] probe=k5 done=1"]), f"r{i}") for i in range(3)
    ]
    a = pp.answer_k5(runs)["answer"]
    assert a["runs"] == 3
    assert a["seeds_all_distinct"] is False
    assert a["time_identical_across_runs"] is True
    assert a["per_run"][0]["table_addr"] == "table: 0x1"


def test_k5_fixture_single_run_is_partial() -> None:
    line = "[DMS.PROBE] probe=k5 phase=load t=0 seed=1 picks=1"
    res = pp.answer_k5([pp.parse_run(log_text([line]))])
    assert res["status"] == "partial"


def test_k6_fixture_now_never_fires() -> None:
    p = "[DMS.PROBE] probe=k6 phase="
    msgs = [
        f"{p}scheduled label=start_now_0 t0=0.000 for=0.000 ok=true err=nil",
        f"{p}scheduled label=start_plus_0_05 t0=0.000 for=0.050 ok=true err=nil",
        f"{p}fired label=start_plus_0_05 at=0.050 time_arg=0.050",
        "[DMS.PROBE] probe=k6 done=1 t=9.000",
    ]
    a = answer("k6", msgs)["answer"]
    assert a["start_now_fires"] is False
    assert a["start_plus_0_05_fires"] is True
    assert a["labels"]["start_plus_0_05"]["fired_at"] == pytest.approx(0.05)


def test_k7_fixture_from_hook_lines() -> None:
    msgs = [
        "[DMS.HARNESS] INFO errorbox_disable res=nil err=nil",
        "[DMS.HARNESS] INFO inject res=nil err=nil",
        "[DMS.PROBE] probe=k7 phase=inject inject_ran=1",
        "[DMS.PROBE] probe=k7 phase=check injected=true",
        "[DMS.PROBE] probe=k7 done=1",
    ]
    run = pp.parse_run(log_text(msgs[:2], "Scripting") + log_text(msgs[2:]))
    a = pp.answer_k7([run])
    assert a["status"] == "answered"
    assert a["answer"]["inject_dostring_ok"] is True
    assert a["answer"]["works"] is True


def test_k7_fixture_dostring_fails() -> None:
    msgs = ["[DMS.HARNESS] INFO errorbox_disable res=nil err=net.dostring_in unavailable"]
    a = answer("k7", msgs)
    assert a["status"] == "answered"
    assert a["answer"]["errorbox_dostring_ok"] is False
    assert a["answer"]["works"] is False
    assert any("--inject" in n for n in a["notes"])


def test_k8_fixture_acmi_found(tmp_path: Path) -> None:
    (tmp_path / "Tacview-20261029-100500-DCS-probe.zip.acmi").write_bytes(b"x")
    msgs = ["[DMS.PROBE] probe=k8 phase=ran anchor_alive=true", "[DMS.PROBE] probe=k8 done=1"]
    text = log_text(msgs) + f"{TS} INFO    TACVIEW.DLL (Main): Tacview 1.9.4 recording\n"
    run = pp.parse_run(text)
    a = pp.answer_k8([run], tmp_path)
    assert a["status"] == "answered"
    assert a["answer"]["tacview_loaded"] is True
    assert a["answer"]["acmi_written"] is True


def test_k8_fixture_without_dir_is_partial() -> None:
    a = answer("k8", ["[DMS.PROBE] probe=k8 done=1"])
    assert a["status"] == "partial"
    assert a["answer"]["acmi_written"] is None
    assert a["answer"]["tacview_loaded"] is False


def test_k9_fixture_truncated_line() -> None:
    plan = "[DMS.PROBE] probe=k9 phase=plan lengths=100,4096,8192"
    msgs = [plan, pp.k9_message(100), pp.k9_message(4096), pp.k9_message(8192)[:4095]]
    msgs.append("[DMS.PROBE] probe=k9 done=1")
    a = answer("k9", msgs)["answer"]
    assert a["max_intact_len"] == 4096
    assert a["first_broken_len"] == 8192
    assert a["all_intact"] is False
    assert a["lengths"][2]["logged_len"] == 4095


def test_k9_fixture_split_line() -> None:
    m = pp.k9_message(2048)
    text = log_text(["[DMS.PROBE] probe=k9 phase=plan lengths=2048"]) + (
        f"{TS} INFO    SCRIPTING (Main): {m[:1000]}\n{m[1000:]}\n"
    )
    a = pp.answer_k9([pp.parse_run(text)])["answer"]
    assert a["lengths"][0]["split"] is True
    assert a["lengths"][0]["intact"] is False


def test_k9_message_lengths_exact() -> None:
    for n in (100, 1024, 65536):
        assert len(pp.k9_message(n)) == n
        assert pp.k9_message(n).endswith("|END")


def test_k10_fixture_net_missing() -> None:
    p = "[DMS.PROBE] probe=k10 phase=t2"
    msgs = [
        f"{p} net_type=nil keys_part=1 keys_parts=1 net_keys=nil",
        f'{p} call=get_player_list ok=false type=string count=-1 ids="" err=missing',
        "[DMS.PROBE] probe=k10 done=1",
    ]
    a = answer("k10", msgs)["answer"]
    assert a["net_type"] == "nil"
    assert a["get_player_list_ok"] is False
    assert a["errors"] == ["missing"]


def test_probes_seen_and_cli(tmp_path: Path, capsys: pytest.CaptureFixture[str]) -> None:
    log = tmp_path / "dcs.log"
    log.write_text(
        log_text(
            [
                "[DMS.PROBE] probe=k6 phase=scheduled label=start_now_0 for=0 ok=true",
                "[DMS.PROBE] probe=k6 phase=fired label=start_now_0 at=0",
                "[DMS.PROBE] probe=k6 done=1",
            ]
        ),
        encoding="utf-8",
    )
    out = tmp_path / "answers.json"
    assert pp.main([str(log), "--out", str(out)]) == 0
    import json

    data = json.loads(out.read_text(encoding="utf-8"))
    assert [x["probe"] for x in data["answers"]] == ["k6"]
    assert data["answers"][0]["answer"]["start_now_fires"] is True
    assert pp.main([str(log), "--probe", "k2"]) == 1  # k2 has no data in this log
    capsys.readouterr()


def test_catalog_scripts_exist() -> None:
    for info in pp.PROBES.values():
        assert (PROBES_DIR / "lua" / info.script).is_file(), info.script
    assert (PROBES_DIR / "README.md").is_file()
