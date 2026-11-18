"""Tests for tools/nightly.py with a fake subprocess (no DCS, no harness, no builds)."""

from __future__ import annotations

import importlib.util
import json
import subprocess
import sys
from pathlib import Path
from types import ModuleType
from typing import Any

import pytest

SCRIPT = Path(__file__).resolve().parents[1] / "nightly.py"


def _load() -> ModuleType:
    spec = importlib.util.spec_from_file_location("dms_nightly", SCRIPT)
    assert spec and spec.loader
    mod = importlib.util.module_from_spec(spec)
    sys.modules["dms_nightly"] = mod
    spec.loader.exec_module(mod)
    return mod


nightly = _load()


class FakeWorld:
    """Stands in for tasklist, `dms build --test` and run_mission.py."""

    def __init__(self, tmp: Path) -> None:
        self.tmp = tmp
        self.processes: list[str] = []  # image names tasklist reports
        self.processes_after_harness: list[str] | None = None
        self.harness_exit = 0
        self.build_exit = 0
        self.calls: list[str] = []
        self.harness_cmds: list[list[str]] = []
        self.ram = [20.0]  # successive free_ram_gb() values (last one repeats)
        self.live_pids: set[int] = set()
        self.sleeps = 0

    def run(self, cmd: list[str], **kw: Any) -> subprocess.CompletedProcess[str]:
        if cmd[0] == "tasklist":
            self.calls.append("tasklist")
            rows = [
                f'"{n}","{4000 + i}","Console","1","1,000 K"' for i, n in enumerate(self.processes)
            ]
            rows.append('"explorer.exe","123","Console","1","90,000 K"')
            return subprocess.CompletedProcess(cmd, 0, "\n".join(rows), "")
        if "build" in cmd and "--test" in cmd:
            self.calls.append("build")
            name = Path(cmd[cmd.index("build") + 1]).name
            miz = self.tmp / "out" / f"{name}-test.miz"
            miz.parent.mkdir(parents=True, exist_ok=True)
            miz.write_bytes(b"PK")
            out = (
                f"built {miz}\ncheck: OK\n"
                "harness: uv run python tools/dcs_harness/run_mission.py "
                f"{miz} --minutes 42 --accel 16\n"
            )
            return subprocess.CompletedProcess(cmd, self.build_exit, out, "")
        if str(nightly.HARNESS) in cmd:
            self.calls.append("harness")
            self.harness_cmds.append(cmd)
            report = Path(cmd[cmd.index("--report") + 1])
            verdict = {0: "pass", 1: "fail", 2: "infra_error"}[self.harness_exit]
            report.write_text(
                json.dumps(
                    {
                        "verdict": verdict,
                        "tests": [{"status": "PASS"}, {"status": "PASS"}],
                        "log_checks": [{"status": "SKIP"}],
                        "script_errors": [],
                        "dms_errors": ["x"] if self.harness_exit else [],
                    }
                ),
                encoding="utf-8",
            )
            if self.processes_after_harness is not None:
                self.processes = self.processes_after_harness
            return subprocess.CompletedProcess(cmd, self.harness_exit, "{}", "")
        raise AssertionError(f"unexpected command {cmd}")

    def free_ram(self) -> float:
        return self.ram.pop(0) if len(self.ram) > 1 else self.ram[0]

    def sleep(self, _sec: float) -> None:
        self.sleeps += 1


@pytest.fixture
def world(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> FakeWorld:
    w = FakeWorld(tmp_path)
    monkeypatch.setattr(nightly.subprocess, "run", w.run)
    monkeypatch.setattr(nightly, "free_ram_gb", w.free_ram)
    monkeypatch.setattr(nightly, "pid_alive", lambda pid: pid in w.live_pids)
    monkeypatch.setattr(nightly, "sleep", w.sleep)
    monkeypatch.setattr(nightly, "SAVED_GAMES", tmp_path / "Saved Games")
    return w


def _config(tmp: Path, n: int = 2, **extra: Any) -> Path:
    data = {"missions": [f"campaigns/c/missions/m0{i + 1}-x" for i in range(n)], **extra}
    p = tmp / "nightly.json"
    p.write_text(json.dumps(data), encoding="utf-8")
    return p


def _run(tmp: Path, *args: str, n: int = 2) -> tuple[int, dict[str, Any]]:
    code = nightly.main(
        [
            "--config",
            str(_config(tmp, n)),
            "--out-dir",
            str(tmp / "nightly"),
            "--lock-dir",
            str(tmp / "locks"),
            "--ram-wait-sec",
            "0",
            "--lock-wait-sec",
            "0",
            *args,
        ]
    )
    latest = json.loads((tmp / "nightly" / "latest.json").read_text(encoding="utf-8"))
    return code, latest


# ---- report shape -------------------------------------------------------------------------------


def test_all_pass_report_shape(world: FakeWorld, tmp_path: Path) -> None:
    code, rep = _run(tmp_path)
    assert code == 0
    assert world.calls.count("build") == 2 and world.calls.count("harness") == 2
    assert world.calls.index("build") < world.calls.index("harness")  # rebuild before each run
    assert rep["schema"] == "dms.nightly/1"
    assert rep["status"] == "pass" and rep["refused_reason"] is None and rep["dry_run"] is False
    assert rep["summary"] == {"total": 2, "pass": 2}
    assert set(rep["preflight"]) == {
        "foreign_processes",
        "free_ram_gb",
        "sim_lock",
        "sim_lock_holder",
        "harness_lock_holder",
    }
    m = rep["missions"][0]
    assert m["name"] == "m01-x" and m["status"] == "pass" and m["verdict"] == "pass"
    assert m["minutes"] == 42 and m["accel"] == 16 and m["free_ram_gb"] == 20.0
    assert m["tests"] == {"PASS": 2, "SKIP": 1} and m["script_errors"] == 0
    assert m["build"]["exit_code"] == 0 and m["harness"]["exit_code"] == 0
    assert Path(m["harness_report"]).is_file()
    assert Path(rep["run_dir"], "nightly.json").is_file()
    cmd = world.harness_cmds[0]
    assert cmd[cmd.index("--min-free-gb") + 1] == "12"
    assert cmd[cmd.index("--minutes") + 1] == "42"
    assert not (tmp_path / "locks" / "sim.lock").exists()  # released


def test_harness_failure_and_build_failure(world: FakeWorld, tmp_path: Path) -> None:
    world.harness_exit = 1
    code, rep = _run(tmp_path, n=1)
    assert code == 1 and rep["status"] == "fail"
    assert rep["missions"][0]["status"] == "fail" and rep["missions"][0]["dms_errors"] == 1

    world.harness_exit, world.build_exit = 0, 1
    world.calls.clear()
    code, rep = _run(tmp_path, n=1)
    assert code == 1 and rep["missions"][0]["status"] == "build_failed"
    assert "harness" not in world.calls


def test_dry_run_builds_and_launches_nothing(world: FakeWorld, tmp_path: Path) -> None:
    code, rep = _run(tmp_path, "--dry-run")
    assert code == 0
    assert "build" not in world.calls and "harness" not in world.calls
    assert rep["status"] == "planned" and rep["dry_run"] is True
    assert [m["status"] for m in rep["missions"]] == ["planned", "planned"]
    hcmd = rep["missions"][0]["harness"]["cmd"]
    assert hcmd[hcmd.index("--minutes") + 1] == "<from build>"
    assert not (tmp_path / "locks" / "sim.lock").exists()


# ---- RAM gate -----------------------------------------------------------------------------------


def test_low_ram_skips_mission_without_launching(world: FakeWorld, tmp_path: Path) -> None:
    world.ram = [8.0]
    code, rep = _run(tmp_path, n=1)
    assert code == 1
    m = rep["missions"][0]
    assert m["status"] == "skipped" and m["reason"].startswith("low_ram")
    assert "harness" not in world.calls


def test_ram_gate_waits_then_runs(world: FakeWorld, tmp_path: Path) -> None:
    world.ram = [30.0, 6.0, 7.0, 13.0]  # preflight, then two low polls, then enough
    code, rep = _run(tmp_path, "--ram-wait-sec", "120", n=1)
    assert code == 0 and rep["missions"][0]["status"] == "pass"
    assert world.sleeps == 2


def test_min_free_gb_flag_overrides(world: FakeWorld, tmp_path: Path) -> None:
    world.ram = [16.0]
    code, rep = _run(tmp_path, "--min-free-gb", "20", n=1)
    assert code == 1 and rep["min_free_gb"] == 20
    assert rep["missions"][0]["reason"].startswith("low_ram")


# ---- foreign processes -------------------------------------------------------------------------


@pytest.mark.parametrize(
    "exe", ["DCS.exe", "DCS_server.exe", "arma3_x64.exe", "arma3server_x64.exe"]
)
def test_refuses_when_game_running(world: FakeWorld, tmp_path: Path, exe: str) -> None:
    world.processes = [exe]
    code, rep = _run(tmp_path)
    assert code == 2
    assert rep["status"] == "refused" and rep["refused_reason"].startswith("foreign_process")
    assert exe in rep["refused_reason"]
    assert all(m["status"] == "skipped" for m in rep["missions"])
    assert "build" not in world.calls and "harness" not in world.calls


def test_game_started_mid_run_stops_remaining(world: FakeWorld, tmp_path: Path) -> None:
    world.processes_after_harness = ["DCS.exe"]
    code, rep = _run(tmp_path, n=3)
    assert code == 1
    assert [m["status"] for m in rep["missions"]] == ["pass", "skipped", "skipped"]
    assert world.calls.count("harness") == 1


# ---- locks --------------------------------------------------------------------------------------


def test_refuses_when_sim_lock_held_by_live_pid(world: FakeWorld, tmp_path: Path) -> None:
    lock = tmp_path / "locks" / "sim.lock"
    lock.parent.mkdir(parents=True)
    lock.write_text(json.dumps({"pid": 777, "owner": "arma_harness"}), encoding="utf-8")
    world.live_pids.add(777)
    code, rep = _run(tmp_path)
    assert code == 2 and rep["refused_reason"].startswith("sim_lock_held: pid 777")
    assert rep["preflight"]["sim_lock_holder"] == 777
    assert lock.exists()  # someone else's lock is left alone


def test_stale_sim_lock_is_taken_over(world: FakeWorld, tmp_path: Path) -> None:
    lock = tmp_path / "locks" / "sim.lock"
    lock.parent.mkdir(parents=True)
    lock.write_text("999\n", encoding="utf-8")  # plain-pid form, dead pid
    code, rep = _run(tmp_path, n=1)
    assert code == 0 and rep["status"] == "pass"
    assert not lock.exists()


def test_sim_lock_is_held_during_run(
    world: FakeWorld, tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    seen: list[dict[str, Any]] = []
    real = world.run

    def spy(cmd: list[str], **kw: Any) -> subprocess.CompletedProcess[str]:
        if str(nightly.HARNESS) in cmd:
            seen.append(json.loads((tmp_path / "locks" / "sim.lock").read_text(encoding="utf-8")))
        return real(cmd, **kw)

    monkeypatch.setattr(nightly.subprocess, "run", spy)
    code, _ = _run(tmp_path, n=1)
    assert code == 0
    assert seen and seen[0]["owner"] == "nightly" and seen[0]["pid"] > 0
    assert {"started", "host"} <= set(seen[0])


def test_harness_write_dir_lock_skips_mission(world: FakeWorld, tmp_path: Path) -> None:
    hlock = tmp_path / "Saved Games" / "DCS.dms_test" / "dms_harness.lock"
    hlock.parent.mkdir(parents=True)
    hlock.write_text("4242\n", encoding="utf-8")  # run_mission.py's format
    world.live_pids.add(4242)
    code, rep = _run(tmp_path, n=1)
    assert code == 1
    m = rep["missions"][0]
    assert m["status"] == "skipped" and m["reason"].startswith("harness_lock_held: pid 4242")
    assert "build" not in world.calls
    assert rep["preflight"]["harness_lock_holder"] == 4242


def test_dead_harness_lock_is_ignored(world: FakeWorld, tmp_path: Path) -> None:
    hlock = tmp_path / "Saved Games" / "DCS.dms_test" / "dms_harness.lock"
    hlock.parent.mkdir(parents=True)
    hlock.write_text("4242\n", encoding="utf-8")
    code, _ = _run(tmp_path, n=1)
    assert code == 0
    assert hlock.exists()  # the harness cleans its own stale lock; nightly never deletes it


# ---- config ------------------------------------------------------------------------------------


def test_config_parsing() -> None:
    entries, opts = nightly.parse_config(
        {
            "min_free_gb": 14,
            "missions": [
                "a/m01",
                {
                    "mission": "a/m02",
                    "variant": "air",
                    "minutes": 20,
                    "accel": 8,
                    "harness_args": ["--no-log-checks"],
                },
            ],
        }
    )
    assert opts == {"min_free_gb": 14}
    assert entries[0].name == "m01" and entries[1].name == "m02-air"
    cmd = nightly.build_cmd(entries[1])
    assert cmd[-4:] == ["--variant", "air", "--test-minutes", "20"]
    bads: list[dict[str, Any]] = [
        {},
        {"missions": []},
        {"missions": [{"path": "x"}]},
        {"missions": ["x"], "foo": 1},
    ]
    for bad in bads:
        with pytest.raises(nightly.ConfigError):
            nightly.parse_config(bad)


def test_default_config_file_lists_viper_m01_to_m04() -> None:
    entries, opts, _ = nightly.load_config(None)
    assert [e.name for e in entries] == [
        "m01-broken-umbrella",
        "m02-the-quarry",
        "m03-troops-in-contact",
        "m04-last-launcher",
    ]
    assert opts["min_free_gb"] == 12
    for e in entries:
        assert (nightly.REPO / e.mission / "mission-spec.yaml").is_file()


def test_bad_config_exits_2(tmp_path: Path) -> None:
    p = tmp_path / "bad.yaml"
    p.write_text("missions: nope\n", encoding="utf-8")
    assert nightly.main(["--config", str(p), "--out-dir", str(tmp_path / "o")]) == 2
