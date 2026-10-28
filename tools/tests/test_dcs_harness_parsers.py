"""Unit tests for the DCS harness dcs.log parser (synthetic logs; no DCS launched)."""

from __future__ import annotations

import importlib.util
import sys
from pathlib import Path
from types import ModuleType
from typing import Any

SCRIPT = Path(__file__).resolve().parents[1] / "dcs_harness" / "run_mission.py"


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
