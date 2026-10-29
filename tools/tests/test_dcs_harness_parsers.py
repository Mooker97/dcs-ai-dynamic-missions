"""Unit tests for the DCS harness dcs.log parser (synthetic logs; no DCS launched)."""

from __future__ import annotations

import importlib.util
import re
import sys
from pathlib import Path
from types import ModuleType
from typing import Any

SCRIPT = Path(__file__).resolve().parents[1] / "dcs_harness" / "run_mission.py"
LUA_SRC = Path(__file__).resolve().parents[2] / "lua" / "src" / "dms"


def _lua_fmt(module: str, start: str) -> str:
    """The string.format pattern in lua/src/dms/<module>.lua that starts with ``start``.

    Fixtures are rendered from the real runtime format strings (Lua %d/%s/%.Nf behave like
    Python's %), so a format change in the runtime breaks these tests instead of passing them.
    """
    src = (LUA_SRC / f"{module}.lua").read_text(encoding="utf-8")
    found = re.findall(r'"(' + re.escape(start) + r'[^"]*)"', src)
    assert found, f"{module}.lua: no format string starting with {start!r}"
    return found[0]


PLAY_FMT = _lua_fmt("comms", "PLAY n=")
MARK_ADD_FMT = _lua_fmt("intel", "MARK add id=")
MARK_REMOVE_FMT = _lua_fmt("intel", "MARK remove id=")
MARK_FAILED_FMT = _lua_fmt("intel", "MARK add failed id=")
LUA_MARKS_FMT = _lua_fmt("test", "added=%d removed=")


def _load() -> ModuleType:
    name = "dcs_harness_run_mission"
    if name in sys.modules:
        return sys.modules[name]
    spec = importlib.util.spec_from_file_location(name, SCRIPT)
    assert spec and spec.loader
    mod = importlib.util.module_from_spec(spec)
    sys.modules[name] = mod
    spec.loader.exec_module(mod)
    return mod


rm = _load()

TS = "2026-10-28 08:30:00.000"

CLEAN_LOG = f"""\
{TS} INFO    EDCORE (Main): DCS/2.9.10 (x86_64; MT; Windows NT 10.0.26200)
{TS} INFO    Scripting (Main): [DMS.HARNESS] PHASE menu_idle
{TS} INFO    Scripting (Main): [DMS.HARNESS] PHASE sim_start model=0.0
{TS} INFO    SCRIPTING (Main): [DMS][Spawner] spawned group Red-1
{TS} INFO    SCRIPTING (Main): [DMS.TEST] PASS spawner_spawns 3 units alive
{TS} INFO    SCRIPTING (Main): [DMS.TEST] SKIP intel_reveal no intel in this mission
{TS} INFO    SCRIPTING (Main): [DMS.OUTCOME] {{"mission":"m01","result":"success"}}
{TS} INFO    SCRIPTING (Main): [DMS.OUTCOME] not-json
{TS} INFO    SCRIPTING (Main): [DMS.TEST] DONE
{TS} INFO    Scripting (Main): [DMS.HARNESS] EXIT reason=done model=301.5
"""


def _write(tmp_path: Path, text: str) -> Path:
    p = tmp_path / "dcs.log"
    p.write_text(text, encoding="utf-8")
    return p


def _report() -> Any:
    return rm.Report(miz="m.miz", mode="sp", exe="DCS.exe")


def test_parse_clean_log_passes(tmp_path: Path) -> None:
    rep = _report()
    rm.parse_log(_write(tmp_path, CLEAN_LOG), rep)
    assert rep.reached_simulation
    assert rep.done
    assert rep.exit_reason == "done"
    assert rep.model_seconds_last == 301.5
    assert [t["status"] for t in rep.tests] == ["PASS", "SKIP"]
    assert rep.tests[0]["name"] == "spawner_spawns"
    assert rep.tests[0]["detail"] == "3 units alive"
    assert rep.outcomes == [{"mission": "m01", "result": "success"}, "not-json"]
    assert rep.script_errors == [] and rep.dms_errors == [] and rep.other_errors == []
    assert len(rep.phases) == 3
    assert rm.verdict(rep) == 0
    assert rep.verdict == "pass"


def test_script_error_with_traceback_continuation(tmp_path: Path) -> None:
    log = CLEAN_LOG + (
        f'{TS} ERROR   SCRIPTING (Main): Mission script error: [string "dms.lua"]:42: '
        "attempt to index a nil value\n"
        "stack traceback:\n"
        "\t[C]: ?\n"
    )
    rep = _report()
    rm.parse_log(_write(tmp_path, log), rep)
    assert len(rep.script_errors) == 1
    assert "stack traceback" in rep.script_errors[0]
    assert rm.verdict(rep) == 1
    assert rep.verdict == "fail"


def test_dms_error_and_test_fail(tmp_path: Path) -> None:
    log = CLEAN_LOG + (
        f"{TS} INFO    SCRIPTING (Main): [DMS][Bus] ERROR handler blew up\n"
        f"{TS} INFO    SCRIPTING (Main): [DMS.TEST] FAIL clock_ticks expected 5 got 4\n"
    )
    rep = _report()
    rm.parse_log(_write(tmp_path, log), rep)
    assert len(rep.dms_errors) == 1
    assert any(t["status"] == "FAIL" and t["name"] == "clock_ticks" for t in rep.tests)
    assert rm.verdict(rep) == 1


def test_login_required_and_gui_errors(tmp_path: Path) -> None:
    log = (
        f"{TS} ERROR   NET (Main): login is required to start a server\n"
        f"{TS} ERROR   LuaGUI (Main): something broke in the menu\n"
    )
    rep = _report()
    rm.parse_log(_write(tmp_path, log), rep)
    assert len(rep.other_errors) == 2
    assert any("BLOCKER" in n for n in rep.notes)
    assert not rep.reached_simulation
    assert rm.verdict(rep) == 2
    assert rep.verdict == "infra_error"


def test_ran_without_assertions(tmp_path: Path) -> None:
    log = f"{TS} INFO    Scripting (Main): [DMS.HARNESS] PHASE sim_start\n"
    rep = _report()
    rm.parse_log(_write(tmp_path, log), rep)
    assert rm.verdict(rep) == 0
    assert rep.verdict == "ran_no_assertions"


def test_missing_log(tmp_path: Path) -> None:
    rep = _report()
    rm.parse_log(tmp_path / "nope.log", rep)
    assert any("not found" in n for n in rep.notes)
    assert rm.verdict(rep) == 2


# Real crash pattern observed in a harness run (DCS ran out of memory and wrote a minidump).
CRASH_LINES = (
    "2026-10-28 08:36:41.904 ALERT   EDCORE (Main): "
    "Out of memory in ed_malloc for 239275128 bytes.\n"
    "2026-10-28 08:36:42.100 INFO    EDCORE (Main): Minidump created.\n"
)


def test_scan_for_crash_detects_oom(tmp_path: Path) -> None:
    p = _write(tmp_path, CLEAN_LOG)
    line, pos = rm.scan_for_crash(p, 0)
    assert line is None
    assert pos == p.stat().st_size
    with p.open("a", encoding="utf-8", newline="\n") as f:
        f.write(CRASH_LINES)
    line, pos2 = rm.scan_for_crash(p, pos)
    assert line is not None
    assert "Out of memory in ed_malloc for 239275128 bytes." in line
    assert pos2 == p.stat().st_size


def test_scan_for_crash_minidump_only(tmp_path: Path) -> None:
    p = _write(tmp_path, CRASH_LINES.splitlines(keepends=True)[1])
    line, _ = rm.scan_for_crash(p, 0)
    assert line is not None and "Minidump created" in line


def test_scan_for_crash_only_reads_new_bytes(tmp_path: Path) -> None:
    p = _write(tmp_path, CRASH_LINES)
    size = p.stat().st_size
    line, pos = rm.scan_for_crash(p, size)
    assert line is None and pos == size


def test_scan_for_crash_log_reset_and_missing(tmp_path: Path) -> None:
    p = _write(tmp_path, CRASH_LINES)
    # DCS truncates dcs.log on restart: a stale pos larger than the file restarts from 0.
    line, _ = rm.scan_for_crash(p, 10_000_000)
    assert line is not None
    line, pos = rm.scan_for_crash(tmp_path / "missing.log", 123)
    assert line is None and pos == 123


# ---------------------------------------------------------------- harness log checks


def _dms(msg: str) -> str:
    return f"{TS} INFO    SCRIPTING (Main): {msg}\n"


def _mark_add(mid: int, kind: str = "text") -> str:
    msg = MARK_ADD_FMT % (
        mid,
        kind,
        "2",
        1000.0,
        -2000.0,
        "-",
        12.5,
        "contact:SAM1",
        "Enemy: Osa x2",
    )
    return _dms("[DMS][Intel] " + msg)


def _mark_remove(mid: int) -> str:
    return _dms("[DMS][Intel] " + MARK_REMOVE_FMT % (mid, "text", 40.0, "destroyed"))


def _mark_failed(mid: int) -> str:
    msg = "[DMS][Intel] " + MARK_FAILED_FMT % (mid, "text", "boom")
    return f"{TS} ERROR   SCRIPTING (Main): {msg}\n"


def _lua_marks(added: int, removed: int, live: int, failed: int = 0) -> str:
    detail = LUA_MARKS_FMT % (added, removed, live, failed)
    return _dms(f"[DMS.TEST] PASS f10_marks {detail} getMarkPanels text 1/1")


_play_n = 0


def _tx(t: float, dur: float, line: str = "ops_v1") -> str:
    global _play_n
    _play_n += 1
    msg = PLAY_FMT % (_play_n, line, "ops", "radio", "x.ogg", t, t + dur, 1)
    return _dms("[DMS][Comms] " + msg)


def _checks(tmp_path: Path, body: str) -> dict[str, dict[str, str]]:
    rep = _report()
    rm.parse_log(_write(tmp_path, CLEAN_LOG + body), rep)
    return {c["name"]: c for c in rep.log_checks}


def test_fixture_formats_match_harness_regexes() -> None:
    assert rm.PLAY_RE.search(_tx(1, 2))
    assert rm.MARK_RE.search(_mark_add(1)) and rm.MARK_RE.search(_mark_remove(1))
    assert rm.MARK_FAILED_RE.search(_mark_failed(1))
    assert rm.LUA_MARKS_RE.search(_lua_marks(1, 0, 1))
    kv = rm._kv(rm.PLAY_RE.search(_tx(3, 4.5, "l1"))[1])
    assert (kv["start"], kv["end"], kv["line"]) == ("3.00", "7.50", "l1")


def test_log_marks_consistent(tmp_path: Path) -> None:
    body = _mark_add(50000, "circle") + _mark_add(50001) + _mark_remove(50000) + _mark_add(50002)
    c = _checks(tmp_path, body)["log_marks"]
    assert c["status"] == "PASS"
    assert c["detail"] == (
        "adds=3 removes=1 live_at_end=2 peak=2 (informational: no Lua marks check line)"
    )


def test_log_marks_fails_on_readded_live_id_and_failed_call(tmp_path: Path) -> None:
    body = _mark_add(50000) + _mark_add(50000) + _mark_failed(50001)
    rep = _report()
    rm.parse_log(_write(tmp_path, CLEAN_LOG + body), rep)
    c = {x["name"]: x for x in rep.log_checks}["log_marks"]
    assert c["status"] == "FAIL"
    assert "id 50000 added while live" in c["detail"]
    assert "1 mark call(s) failed" in c["detail"]
    assert rm.verdict(rep) == 1


def test_log_marks_fails_on_remove_of_unknown_id(tmp_path: Path) -> None:
    c = _checks(tmp_path, _mark_add(50000) + _mark_remove(50007))["log_marks"]
    assert c["status"] == "FAIL", c
    assert "1 remove(s) of never-added id(s): 50007" in c["detail"]


def test_log_marks_matches_lua_marks_check(tmp_path: Path) -> None:
    body = _mark_add(50000) + _mark_add(50001) + _mark_remove(50000) + _lua_marks(2, 1, 1)
    body += _mark_remove(50001)  # Intel.stop after DONE: not part of the comparison
    c = _checks(tmp_path, body)["log_marks"]
    assert c["status"] == "PASS", c
    assert c["detail"].endswith("matches Lua marks check")
    bad = _checks(tmp_path, _mark_add(50000) + _lua_marks(3, 0, 3))["log_marks"]
    assert bad["status"] == "FAIL", bad
    assert "disagrees with Lua marks check (added=3 removed=0 live=3 failed=0)" in bad["detail"]


def test_log_marks_skip_when_debug_off(tmp_path: Path) -> None:
    c = _checks(tmp_path, _lua_marks(4, 1, 3))["log_marks"]
    assert c["status"] == "SKIP", c


def test_log_marks_info_without_lines(tmp_path: Path) -> None:
    c = _checks(tmp_path, "")["log_marks"]
    assert c["status"] == "INFO"


def test_log_comms_overlap(tmp_path: Path) -> None:
    # gap 0.75 - tol 0.05: next start must be >= prev end + 0.70
    ok = _checks(tmp_path, _tx(10, 5) + _tx(15.75, 3) + _tx(30, 2))["log_comms_overlap"]
    assert ok["status"] == "PASS", ok
    assert ok["detail"] == "3 timed PLAY line(s), no overlap"
    bad = _checks(tmp_path, _tx(10, 5, "a") + _tx(12, 3, "b"))["log_comms_overlap"]
    assert bad["status"] == "FAIL"
    assert "a@10.0+5.0 overlaps b@12.0" in bad["detail"]
    # back-to-back without the radio gap is a FAIL too
    tight = _checks(tmp_path, _tx(10, 5, "a") + _tx(15.2, 3, "b"))["log_comms_overlap"]
    assert tight["status"] == "FAIL", tight
    # the debug TX text line alone is not timing
    info = _checks(tmp_path, _dms("[DMS][Comms] TX 'Dusty, Ops'"))["log_comms_overlap"]
    assert info["status"] == "INFO"


def test_log_comms_overlap_skips_untimed_play(tmp_path: Path) -> None:
    # format drift guard: a PLAY line that lost start=/end= SKIPs instead of passing
    body = _dms("[DMS][Comms] PLAY n=1 line=ops_v1 speaker=ops via=text file=-")
    c = _checks(tmp_path, body)["log_comms_overlap"]
    assert c["status"] == "SKIP"
    rep = _report()
    rm.parse_log(_write(tmp_path, CLEAN_LOG + body), rep)
    assert rm.verdict(rep) == 0


def test_log_checks_can_be_disabled(tmp_path: Path) -> None:
    rep = _report()
    rm.parse_log(_write(tmp_path, CLEAN_LOG + _mark_add(1) + _mark_add(1)), rep, log_checks=False)
    assert rep.log_checks == []
    assert rm.verdict(rep) == 0


def test_wrong_mission_loaded_is_infra(tmp_path: Path) -> None:
    other = f"{TS} INFO    Dispatcher (Main): loadMission C:/x/dms_harness/other-test.miz\n"
    done = f"{TS} INFO    Dispatcher (Main): loadMission Done: Control passed to the player\n"
    rep = _report()
    rm.parse_log(_write(tmp_path, other + done + CLEAN_LOG), rep)
    assert rep.loaded_miz.endswith("other-test.miz")
    assert rm.verdict(rep) == 2
    assert rep.verdict == "wrong_mission"


def test_right_mission_loaded_passes(tmp_path: Path) -> None:
    ok = f"{TS} INFO    Dispatcher (Main): loadMission C:/x/Missions/dms_harness/m.miz\n"
    rep = _report()
    rm.parse_log(_write(tmp_path, ok + CLEAN_LOG), rep)
    assert rm.verdict(rep) == 0


def test_lock_is_exclusive_and_stale_lock_is_taken(tmp_path: Path) -> None:
    lock = rm.acquire_lock(tmp_path, wait_sec=0)
    assert lock is not None
    assert rm.acquire_lock(tmp_path, wait_sec=0, poll_sec=0) is None  # held by us, alive
    rm.release_lock(lock)
    assert not lock.exists()
    lock.write_text("999999999\n", encoding="utf-8")  # dead pid
    again = rm.acquire_lock(tmp_path, wait_sec=0)
    assert again is not None
    rm.release_lock(again)
