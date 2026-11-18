"""Unit tests for the Arma harness .rpt parser (synthetic .rpt; no Arma launched)."""

from __future__ import annotations

import importlib.util
import sys
from pathlib import Path
from types import ModuleType
from typing import Any

SCRIPT = Path(__file__).resolve().parents[1] / "arma_harness" / "run_mission.py"


def _load() -> ModuleType:
    name = "arma_harness_run_mission"
    if name in sys.modules:
        return sys.modules[name]
    spec = importlib.util.spec_from_file_location(name, SCRIPT)
    assert spec and spec.loader
    mod = importlib.util.module_from_spec(spec)
    sys.modules[name] = mod
    spec.loader.exec_module(mod)
    return mod


rm = _load()

CLEAN_RPT = """\
=====================================================================
== arma3server_x64.exe
=====================================================================
 8:30:00 Mission id: 0123456789abcdef
 8:30:01 "[DMS] INFO: initServer done seed=42 site=Kavala"
 8:30:02 "[DMS] WARN: no QRF spawn point found, using fallback"
 8:30:05 "[DMS.TEST] PASS site_built objects=14"
 8:30:06 "[DMS.DIAG] fps=48 units=63"
 8:30:09 "[DMS.OUTCOME] result=success hill=held casualties=1"
 8:30:10 "[DMS.TEST] SUMMARY pass=1 fail=0"
 8:30:10 "[DMS.TEST] DONE"
"""


def _parse(text: str) -> Any:
    rep = rm.Report()
    rm.parse_rpt(text, rep)
    return rep


def test_clean_rpt_passes() -> None:
    rep = _parse(CLEAN_RPT)
    assert rep.started
    assert rep.done
    assert [(t["status"], t["name"]) for t in rep.tests] == [("PASS", "site_built")]
    assert rep.tests[0]["detail"].startswith("objects=14")
    assert rep.summary.startswith("pass=1 fail=0")
    assert rep.outcomes[0]["result"] == "success"
    assert rep.outcomes[0]["hill"] == "held"
    assert "raw" in rep.outcomes[0]
    assert len(rep.diag) == 1 and rep.diag[0].startswith("fps=48 units=63")
    assert len(rep.dms_lines) == 2
    assert len(rep.dms_warnings) == 1
    assert rep.script_errors == [] and rep.infra == []
    assert rm.verdict(rep, diag=False) == 0
    assert rep.verdict == "PASS"


def test_script_error_block_grouped_and_deduped() -> None:
    err = (
        " 8:30:07 Error in expression <_grp addWaypoint [_pos, 0]>\n"
        " 8:30:07   Error position: <addWaypoint [_pos, 0]>\n"
        " 8:30:07   Error Undefined variable in expression: _pos\n"
        " 8:30:07 File mpmissions\\__cur_mp.Altis\\functions\\fn_qrf.sqf..., line 12\n"
    )
    rep = _parse(CLEAN_RPT + err + err)
    assert len(rep.script_errors) == 1
    block = rep.script_errors[0]
    assert block.startswith("Error in expression")
    assert "Undefined variable" in block and "line 12" in block
    assert rm.verdict(rep, diag=False) == 1
    assert "1 script error(s)" in rep.verdict


def test_test_fail_and_missing_summary() -> None:
    rpt = ' 8:30:01 "[DMS] INFO: initServer done"\n 8:30:05 "[DMS.TEST] FAIL qrf_wave1 none"\n'
    rep = _parse(rpt)
    assert rm.verdict(rep, diag=False) == 1
    assert "FAIL: qrf_wave1" in rep.verdict
    assert "no summary" in rep.verdict


def test_never_started_is_infra() -> None:
    rep = _parse(" 8:30:00 Mission file(s) not found\n 8:30:00 Cannot load mission\n")
    assert not rep.started
    assert len(rep.infra) == 2
    assert rm.verdict(rep, diag=False) == 2
    assert rep.verdict.startswith("INFRA")


def test_diag_mode() -> None:
    rep = _parse(' 8:30:00 "[DMS.DIAG.BEGIN]"\n 8:30:01 "[DMS.DIAG] classes=12"\n')
    assert rep.started
    assert rm.verdict(rep, diag=True) == 1
    assert rep.verdict == "DIAG incomplete"
    rep = _parse(' 8:30:00 "[DMS.DIAG.BEGIN]"\n 8:30:02 "[DMS.TEST] DONE"\n')
    assert rm.verdict(rep, diag=True) == 0
    assert rep.verdict == "DIAG done"


def test_kv_helper() -> None:
    assert rm._kv("a=1 b=two c") == {"a": "1", "b": "two"}
