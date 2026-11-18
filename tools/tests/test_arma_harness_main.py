"""Tests for the Arma harness CLI: argparse -> mission params / jobs, and the batch-JSON verdict.

No Arma is launched: `run_one`, `running_servers` and `free_ram_gb` are monkeypatched, and the
server executable is an empty placeholder file in a temp dir.
"""

from __future__ import annotations

import argparse
import importlib.util
import json
import sys
from pathlib import Path
from types import ModuleType
from typing import Any

import pytest

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

PASS_RPT = """\
 8:30:01 "[DMS] INFO: initServer done seed=1"
 8:30:05 "[DMS.TEST] PASS spawn_squad 7 units"
 8:30:09 "[DMS.OUTCOME] result=WIN end=DMS_Win reason=extracted seed=1"
 8:30:10 "[DMS.TEST] SUMMARY pass=1 fail=0 seed=1"
 8:30:10 "[DMS.TEST] DONE"
"""
FAIL_RPT = """\
 8:30:01 "[DMS] INFO: initServer done seed=2"
 8:30:05 "[DMS.TEST] PASS spawn_squad 7 units"
 8:30:06 "[DMS.TEST] FAIL exfil_boarded not reached"
 8:30:09 "[DMS.OUTCOME] result=LOSS end=DMS_Fail reason=heli_lost seed=2"
 8:30:10 "[DMS.TEST] SUMMARY pass=1 fail=1 seed=2"
 8:30:10 "[DMS.TEST] DONE"
"""
INFRA_RPT = " 8:30:00 Mission file(s) not found\n"


@pytest.fixture
def env(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> dict[str, Any]:
    mission = tmp_path / "missions" / "dms_x.Altis"
    mission.mkdir(parents=True)
    (mission / "mission.sqm").write_text("version = 54;\n", "utf-8")
    arma = tmp_path / "arma"
    arma.mkdir()
    (arma / "arma3server_x64.exe").write_bytes(b"")
    profile = tmp_path / "profile"
    calls: list[tuple[argparse.Namespace, Any]] = []
    rpts: dict[str, str] = {}

    def fake_run_one(a: argparse.Namespace, m: Path, exe: Path, job: Any) -> tuple[int, Any]:
        calls.append((a, job))
        rep = rm.Report(mission=str(m), template=job.template, params=job.params)
        rm.parse_rpt(rpts.get(job.tag, PASS_RPT), rep)
        code = rm.verdict(rep, a.diag)
        job.report.parent.mkdir(parents=True, exist_ok=True)
        job.report.write_text(json.dumps({"verdict": rep.verdict}), "utf-8")
        return code, rep

    monkeypatch.setattr(rm, "run_one", fake_run_one)
    monkeypatch.setattr(rm, "running_servers", lambda: [])
    monkeypatch.setattr(rm, "free_ram_gb", lambda: 64.0)
    base = [str(mission), "--arma", str(arma), "--profile", str(profile), "--quiet"]
    return {"base": base, "calls": calls, "rpts": rpts, "profile": profile}


def _jobs(env: dict[str, Any]) -> list[Any]:
    return sorted((job for _, job in env["calls"]), key=lambda j: j.tag)


def test_default_test_params(env: dict[str, Any]) -> None:
    assert rm.main([*env["base"], "--seed", "7", "--minutes", "25.5"]) == 0
    (job,) = _jobs(env)
    assert job.params == {
        "DMS_testMode": 1,
        "DMS_testMinutes": 25,
        "DMS_testTimeScale": 15,
        "DMS_testStartDist": 300,
        "DMS_testAssist": 180,
        "DMS_debug": 0,
        "DMS_seed": 7,
    }
    assert job.tag == "s7"
    assert job.template == "dms_x.Altis"
    assert job.profile == env["profile"].resolve()
    assert job.port == 2402


def test_flags_and_param_overrides(env: dict[str, Any]) -> None:
    argv = [
        *env["base"],
        "--time-scale",
        "100",
        "--assist",
        "0",
        "--start-dist",
        "0",
        "--param",
        "DMS_site=2",
        "--param",
        " DMS_testForce = 1 ",
        "--param",
        "DMS_debug=1",
    ]
    assert rm.main(argv) == 0
    (job,) = _jobs(env)
    p = job.params
    assert (p["DMS_testTimeScale"], p["DMS_testAssist"], p["DMS_testStartDist"]) == (100, 0, 0)
    # --param values arrive as stripped strings and override the defaults.
    assert p["DMS_site"] == "2" and p["DMS_testForce"] == "1" and p["DMS_debug"] == "1"
    assert "DMS_seed" not in p and job.tag == "run"
    cfg = rm.server_cfg(job.template, p, "Regular")
    assert "DMS_site = 2;" in cfg and "DMS_testForce = 1;" in cfg
    assert 'template = "dms_x.Altis";' in cfg


def test_no_test_mode_and_diag(env: dict[str, Any]) -> None:
    assert rm.main([*env["base"], "--no-test-mode", "--seed", "3"]) == 0
    assert _jobs(env)[0].params == {"DMS_debug": 0, "DMS_seed": 3}
    env["calls"].clear()
    rm.main([*env["base"], "--diag", "--seed", "3"])
    assert _jobs(env)[0].params == {}


def test_seeds_make_one_job_each_and_parallel_is_capped(env: dict[str, Any]) -> None:
    assert rm.main([*env["base"], "--seeds", "1, 2,3", "--parallel", "9", "--port", "2500"]) == 0
    jobs = _jobs(env)
    assert [j.tag for j in jobs] == ["s1", "s2", "s3"]
    assert [j.params["DMS_seed"] for j in jobs] == [1, 2, 3]
    assert [j.template for j in jobs] == ["dms_x_s1.Altis", "dms_x_s2.Altis", "dms_x_s3.Altis"]
    assert [j.port for j in jobs] == [2500, 2520, 2540]
    root = env["profile"].resolve()
    assert [j.profile for j in jobs] == [root / "s1", root / "s2", root / "s3"]
    assert all(j.report.parent == root / "reports" for j in jobs)
    assert env["calls"][0][0].parallel == rm.MAX_PARALLEL


def test_bad_mission_folder_is_infra(env: dict[str, Any], tmp_path: Path) -> None:
    argv = list(env["base"])
    argv[0] = str(tmp_path)
    assert rm.main(argv) == 2
    assert env["calls"] == []


def test_dry_run_launches_nothing(env: dict[str, Any]) -> None:
    assert rm.main([*env["base"], "--seeds", "1,2", "--dry-run"]) == 0
    assert env["calls"] == []


def _batch(env: dict[str, Any]) -> dict[str, Any]:
    (path,) = (env["profile"].resolve() / "reports").glob("dms_x_batch_*.json")
    data: dict[str, Any] = json.loads(path.read_text("utf-8"))
    return data


def test_batch_json_verdict_is_worst_run(env: dict[str, Any]) -> None:
    env["rpts"].update({"s1": PASS_RPT, "s2": FAIL_RPT})
    assert rm.main([*env["base"], "--seeds", "2,1"]) == 1
    batch = _batch(env)
    assert set(batch) == {"wall_seconds", "runs"}
    runs = batch["runs"]
    assert [r["tag"] for r in runs] == ["s1", "s2"]
    assert [r["code"] for r in runs] == [0, 1]
    assert runs[0]["verdict"] == "PASS"
    assert runs[1]["verdict"] == "FAIL: FAIL: exfil_boarded"
    assert runs[0]["summary"].startswith("pass=1 fail=0")
    assert runs[0]["outcome"].startswith("result=WIN")
    assert runs[1]["outcome"].startswith("result=LOSS")
    assert all(Path(r["report"]).is_file() for r in runs)


def test_batch_infra_dominates(env: dict[str, Any]) -> None:
    env["rpts"].update({"s1": PASS_RPT, "s2": INFRA_RPT})
    assert rm.main([*env["base"], "--seeds", "1,2"]) == 2
    runs = _batch(env)["runs"]
    assert [(r["code"], r["verdict"]) for r in runs] == [
        (0, "PASS"),
        (2, "INFRA: mission never started"),
    ]
    assert runs[1]["outcome"] == "" and runs[1]["summary"] == ""


def test_single_run_writes_no_batch(env: dict[str, Any]) -> None:
    env["rpts"]["s1"] = FAIL_RPT
    assert rm.main([*env["base"], "--seed", "1"]) == 1
    assert list((env["profile"].resolve() / "reports").glob("*_batch_*.json")) == []
