"""Nightly headless run: rebuild each test .miz, then run it through the DCS harness, one at a time.

Usage:
    uv run python tools/nightly.py [--config tools/nightly.yaml] [--min-free-gb 12]
        [--ram-wait-sec 900] [--lock-wait-sec 1800] [--out-dir ~/.dms/nightly] [--dry-run]

For each mission in the config (default tools/nightly.yaml: viper-detachment m01-m04):
  1. stop if a DCS or Arma 3 process is running (the user is playing; nothing is killed),
  2. skip if another run holds the DCS harness write-dir lock,
  3. rebuild the test variant (`dms build <mission> --test`, no voice, no cost),
  4. wait for --min-free-gb of free physical RAM (up to --ram-wait-sec), else skip,
  5. run tools/dcs_harness/run_mission.py on the built miz as a subprocess (it is never imported
     or edited here) and keep its JSON report.
The whole run holds the shared headless-sim lock (~/.dms/locks/sim.lock), so a nightly never
overlaps another nightly or (once they adopt it) a manual DCS/Arma harness run.

Output: <out-dir>/<YYYYMMDD-HHMMSS>/nightly.json (+ per-mission build/harness logs and harness
reports) and a copy at <out-dir>/latest.json. Schema, lock convention and Task Scheduler setup:
tools/README.md.

Exit codes: 0 = every mission passed (or --dry-run); 1 = at least one mission did not pass;
2 = refused (foreign DCS/Arma process, sim lock held, bad config).
"""

from __future__ import annotations

import argparse
import contextlib
import ctypes
import json
import os
import re
import socket
import subprocess
import sys
import time
from dataclasses import asdict, dataclass, field
from datetime import datetime
from pathlib import Path
from typing import Any

import yaml

REPO = Path(__file__).resolve().parents[1]
HARNESS = REPO / "tools" / "dcs_harness" / "run_mission.py"
DEFAULT_CONFIG = REPO / "tools" / "nightly.yaml"
DMS_HOME = Path(os.environ.get("DMS_HOME", str(Path.home() / ".dms")))
SAVED_GAMES = Path(os.environ.get("USERPROFILE", str(Path.home()))) / "Saved Games"

REPORT_SCHEMA = "dms.nightly/1"
SIM_LOCK_NAME = "sim.lock"  # shared convention, see tools/README.md "Shared sim lock"
HARNESS_LOCK_NAME = "dms_harness.lock"  # tools/dcs_harness/run_mission.py LOCK_NAME
DEFAULT_WRITE_DIR = "DCS.dms_test"  # run_mission.py --write-dir-name default

# A running game means the user is (or was just) playing: never start a sim run next to it.
FOREIGN_PROCESSES = frozenset(
    {
        "dcs.exe",
        "dcs_server.exe",
        "arma3.exe",
        "arma3_x64.exe",
        "arma3server.exe",
        "arma3server_x64.exe",
        "arma3battleye.exe",
    }
)

DEFAULT_MISSIONS: list[dict[str, Any]] = [
    {"mission": "campaigns/viper-detachment/missions/m01-broken-umbrella"},
    {"mission": "campaigns/viper-detachment/missions/m02-the-quarry"},
    {"mission": "campaigns/viper-detachment/missions/m03-troops-in-contact"},
    {"mission": "campaigns/viper-detachment/missions/m04-last-launcher"},
]

HARNESS_HINT_RE = re.compile(
    r"^harness: .*?run_mission\.py (?P<miz>.+?) --minutes (?P<minutes>[0-9.]+)"
    r"(?: --accel (?P<accel>\d+))?\s*$",
    re.MULTILINE,
)

BUILD_TIMEOUT_SEC = 900
HARNESS_EXIT_STATUS = {0: "pass", 1: "fail", 2: "infra_error"}


# ----------------------------------------------------------------------------------------------
# config
# ----------------------------------------------------------------------------------------------


@dataclass
class MissionEntry:
    mission: str
    variant: str | None = None
    minutes: float | None = None
    accel: int | None = None
    harness_args: list[str] = field(default_factory=list)

    @property
    def name(self) -> str:
        base = Path(self.mission).name
        return f"{base}-{self.variant}" if self.variant else base


class ConfigError(ValueError):
    pass


_ENTRY_KEYS = {"mission", "variant", "minutes", "accel", "harness_args"}


def parse_config(data: Any) -> tuple[list[MissionEntry], dict[str, Any]]:
    """Validate a loaded config (a `missions` list plus optional defaults) -> (entries, opts)."""
    if not isinstance(data, dict) or not isinstance(data.get("missions"), list):
        raise ConfigError("config must be a mapping with a `missions` list")
    unknown = set(data) - {"missions", "min_free_gb", "ram_wait_sec", "write_dir_name"}
    if unknown:
        raise ConfigError(f"unknown config keys: {sorted(unknown)}")
    entries: list[MissionEntry] = []
    for i, raw in enumerate(data["missions"]):
        if isinstance(raw, str):
            raw = {"mission": raw}
        if not isinstance(raw, dict) or not isinstance(raw.get("mission"), str):
            raise ConfigError(f"missions[{i}]: needs a `mission` path")
        bad = set(raw) - _ENTRY_KEYS
        if bad:
            raise ConfigError(f"missions[{i}]: unknown keys {sorted(bad)}")
        args = raw.get("harness_args", [])
        if not isinstance(args, list) or not all(isinstance(a, str) for a in args):
            raise ConfigError(f"missions[{i}].harness_args: must be a list of strings")
        entries.append(
            MissionEntry(
                mission=raw["mission"],
                variant=raw.get("variant"),
                minutes=float(raw["minutes"]) if raw.get("minutes") is not None else None,
                accel=int(raw["accel"]) if raw.get("accel") is not None else None,
                harness_args=list(args),
            )
        )
    if not entries:
        raise ConfigError("config has no missions")
    opts = {k: data[k] for k in ("min_free_gb", "ram_wait_sec", "write_dir_name") if k in data}
    return entries, opts


def load_config(path: Path | None) -> tuple[list[MissionEntry], dict[str, Any], str]:
    """Load YAML/JSON config; no file at the default path -> built-in viper m01-m04."""
    if path is None:
        if not DEFAULT_CONFIG.is_file():
            entries, opts = parse_config({"missions": DEFAULT_MISSIONS})
            return entries, opts, "<built-in>"
        path = DEFAULT_CONFIG
    if not path.is_file():
        raise ConfigError(f"config not found: {path}")
    text = path.read_text(encoding="utf-8")
    data = json.loads(text) if path.suffix.lower() == ".json" else yaml.safe_load(text)
    entries, opts = parse_config(data)
    return entries, opts, str(path)


# ----------------------------------------------------------------------------------------------
# machine state: processes, RAM, pids
# ----------------------------------------------------------------------------------------------


def foreign_processes() -> list[str]:
    """Names of running DCS/Arma processes (tasklist; no PowerShell needed)."""
    try:
        out = subprocess.run(
            ["tasklist", "/FO", "CSV", "/NH"],
            capture_output=True,
            text=True,
            errors="replace",
            timeout=60,
        ).stdout
    except (OSError, subprocess.SubprocessError):
        return []
    hits = []
    for line in out.splitlines():
        cols = line.split('","')
        name = cols[0].strip().strip('"')
        if name.lower() in FOREIGN_PROCESSES:
            pid = cols[1].strip('"') if len(cols) > 1 else "?"
            hits.append(f"{name} pid {pid}")
    return hits


class _MemStatus(ctypes.Structure):
    _fields_ = [
        ("dwLength", ctypes.c_ulong),
        ("dwMemoryLoad", ctypes.c_ulong),
        ("ullTotalPhys", ctypes.c_ulonglong),
        ("ullAvailPhys", ctypes.c_ulonglong),
        ("ullTotalPageFile", ctypes.c_ulonglong),
        ("ullAvailPageFile", ctypes.c_ulonglong),
        ("ullTotalVirtual", ctypes.c_ulonglong),
        ("ullAvailVirtual", ctypes.c_ulonglong),
        ("ullAvailExtendedVirtual", ctypes.c_ulonglong),
    ]


def free_ram_gb() -> float:
    """Available physical memory in GB (GlobalMemoryStatusEx; inf when unknown/non-Windows)."""
    if sys.platform != "win32":
        return float("inf")
    st = _MemStatus()
    st.dwLength = ctypes.sizeof(_MemStatus)
    k32: Any = getattr(ctypes, "windll").kernel32  # noqa: B009 (Windows-only attribute)
    if not k32.GlobalMemoryStatusEx(ctypes.byref(st)):
        return float("inf")
    return float(st.ullAvailPhys) / 1024**3


def pid_alive(pid: int) -> bool:
    if pid <= 0:
        return False
    if sys.platform != "win32":
        try:
            os.kill(pid, 0)
        except OSError:
            return False
        return True
    k32: Any = getattr(ctypes, "windll").kernel32  # noqa: B009 (Windows-only attribute)
    h = k32.OpenProcess(0x1000, False, pid)  # PROCESS_QUERY_LIMITED_INFORMATION
    if not h:
        return False
    try:
        code = ctypes.c_ulong()
        ok = k32.GetExitCodeProcess(h, ctypes.byref(code))
        return bool(ok) and code.value == 259  # STILL_ACTIVE
    finally:
        k32.CloseHandle(h)


def sleep(sec: float) -> None:  # indirection so tests never really wait
    time.sleep(sec)


def wait_for_ram(min_gb: float, max_wait_sec: float, poll_sec: float = 30.0) -> tuple[bool, float]:
    t0 = time.monotonic()
    waited = 0.0
    while True:
        gb = free_ram_gb()
        if gb >= min_gb:
            return True, gb
        if waited >= max_wait_sec or time.monotonic() - t0 >= max_wait_sec:
            return False, gb
        log(f"only {gb:.1f} GB RAM free (< {min_gb:g} GB); waiting {poll_sec:g} s")
        sleep(poll_sec)
        waited += poll_sec


# ----------------------------------------------------------------------------------------------
# locks
# ----------------------------------------------------------------------------------------------


def lock_holder(lock: Path) -> int | None:
    """Live pid holding `lock` (first token of the file, or JSON {"pid": N}); None if free/stale."""
    try:
        text = lock.read_text(encoding="utf-8").strip()
    except OSError:
        return None
    pid = -1
    try:
        pid = int(json.loads(text)["pid"]) if text.startswith("{") else int(text.split()[0])
    except (ValueError, KeyError, IndexError, TypeError):
        pid = -1
    return pid if pid_alive(pid) else None


def acquire_sim_lock(lock: Path, owner: str, wait_sec: float, poll_sec: float = 30.0) -> bool:
    """Create the shared sim lock (O_EXCL); stale locks (dead pid) are taken over."""
    lock.parent.mkdir(parents=True, exist_ok=True)
    waited = 0.0
    while True:
        try:
            fd = os.open(lock, os.O_CREAT | os.O_EXCL | os.O_WRONLY)
        except FileExistsError:
            holder = lock_holder(lock)
            if holder is None:
                with contextlib.suppress(OSError):
                    lock.unlink()
                continue
            if waited >= wait_sec:
                return False
            log(f"{lock} held by live pid {holder}; waiting {poll_sec:g} s")
            sleep(poll_sec)
            waited += poll_sec
            continue
        body = {
            "pid": os.getpid(),
            "owner": owner,
            "started": now_iso(),
            "host": socket.gethostname(),
        }
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            f.write(json.dumps(body) + "\n")
        return True


def release_sim_lock(lock: Path) -> None:
    with contextlib.suppress(OSError, ValueError, KeyError):
        if int(json.loads(lock.read_text(encoding="utf-8"))["pid"]) == os.getpid():
            lock.unlink()


def wait_harness_lock(lock: Path, wait_sec: float, poll_sec: float = 30.0) -> int | None:
    """Wait while a live harness run holds its write-dir lock. Returns the holder pid or None."""
    waited = 0.0
    while True:
        holder = lock_holder(lock)
        if holder is None or waited >= wait_sec:
            return holder
        log(f"harness lock {lock} held by live pid {holder}; waiting {poll_sec:g} s")
        sleep(poll_sec)
        waited += poll_sec


# ----------------------------------------------------------------------------------------------
# report
# ----------------------------------------------------------------------------------------------


@dataclass
class Step:
    cmd: list[str]
    exit_code: int | None = None
    seconds: float | None = None
    log: str | None = None


@dataclass
class MissionResult:
    name: str
    mission: str
    variant: str | None
    status: str = "pending"  # pass|fail|infra_error|build_failed|skipped|planned
    reason: str | None = None
    miz: str | None = None
    minutes: float | None = None
    accel: int | None = None
    free_ram_gb: float | None = None
    build: Step | None = None
    harness: Step | None = None
    harness_report: str | None = None
    verdict: str | None = None
    tests: dict[str, int] | None = None
    script_errors: int | None = None
    dms_errors: int | None = None


@dataclass
class NightlyReport:
    started: str
    host: str
    config: str
    dry_run: bool
    min_free_gb: float
    run_dir: str
    schema: str = REPORT_SCHEMA
    finished: str | None = None
    status: str = "running"  # pass|fail|refused|planned
    refused_reason: str | None = None
    preflight: dict[str, Any] = field(default_factory=dict)
    missions: list[MissionResult] = field(default_factory=list)
    summary: dict[str, int] = field(default_factory=dict)


def now_iso() -> str:
    return datetime.now().astimezone().isoformat(timespec="seconds")


def log(msg: str) -> None:
    print(f"[nightly] {msg}", flush=True)


def summarise(rep: NightlyReport) -> None:
    counts: dict[str, int] = {"total": len(rep.missions)}
    for m in rep.missions:
        counts[m.status] = counts.get(m.status, 0) + 1
    rep.summary = counts
    if rep.status == "refused":
        return
    if rep.dry_run:
        rep.status = "planned"
    else:
        ok = rep.missions and all(m.status == "pass" for m in rep.missions)
        rep.status = "pass" if ok else "fail"


def write_report(rep: NightlyReport, run_dir: Path, out_dir: Path) -> Path:
    rep.finished = now_iso()
    summarise(rep)
    text = json.dumps(asdict(rep), indent=2, default=str)
    run_dir.mkdir(parents=True, exist_ok=True)
    path = run_dir / "nightly.json"
    path.write_text(text, encoding="utf-8")
    (out_dir / "latest.json").write_text(text, encoding="utf-8")
    return path


# ----------------------------------------------------------------------------------------------
# per-mission steps
# ----------------------------------------------------------------------------------------------


def dms_cmd(*args: str) -> list[str]:
    """`dms ...` through this interpreter (works from Task Scheduler without uv on PATH)."""
    return [sys.executable, "-c", "from dms_cli.main import app; app(prog_name='dms')", *args]


def build_cmd(e: MissionEntry) -> list[str]:
    cmd = dms_cmd("build", str(REPO / e.mission), "--test")
    if e.variant:
        cmd += ["--variant", e.variant]
    if e.minutes is not None:
        cmd += ["--test-minutes", f"{e.minutes:g}"]
    return cmd


def harness_cmd(
    e: MissionEntry,
    miz: str,
    minutes: float,
    accel: int,
    report: Path,
    a: argparse.Namespace,
) -> list[str]:
    return [
        sys.executable,
        str(HARNESS),
        miz,
        "--minutes",
        f"{minutes:g}",
        "--accel",
        str(accel),
        "--report",
        str(report),
        "--min-free-gb",
        f"{a.min_free_gb:g}",
        "--ram-wait-sec",
        str(int(a.ram_wait_sec)),
        "--write-dir-name",
        a.write_dir_name,
        *e.harness_args,
    ]


def run_step(cmd: list[str], log_path: Path, timeout: float) -> tuple[Step, str]:
    step = Step(cmd=cmd, log=str(log_path))
    t0 = time.monotonic()
    try:
        proc = subprocess.run(
            cmd,
            cwd=str(REPO),
            capture_output=True,
            text=True,
            errors="replace",
            timeout=timeout,
        )
        out = (proc.stdout or "") + (proc.stderr or "")
        step.exit_code = proc.returncode
    except subprocess.TimeoutExpired as exc:
        out = f"{exc}\n"
        step.exit_code = None
    step.seconds = round(time.monotonic() - t0, 1)
    log_path.parent.mkdir(parents=True, exist_ok=True)
    log_path.write_text(out, encoding="utf-8")
    return step, out


def default_miz(e: MissionEntry) -> str:
    return str(REPO / e.mission / "out" / f"{Path(e.mission).name}-test.miz")


def harness_timeout(minutes: float, accel: int, ram_wait_sec: float) -> float:
    # the harness's own wall timeout is minutes*60/accel + 420; allow RAM/lock waits and parsing
    return minutes * 60 / max(1, accel) + 420 + ram_wait_sec + 600


def read_harness_report(res: MissionResult, path: Path) -> None:
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return
    res.verdict = data.get("verdict")
    counts: dict[str, int] = {}
    for t in data.get("tests", []) + data.get("log_checks", []):
        st = str(t.get("status", "?"))
        counts[st] = counts.get(st, 0) + 1
    res.tests = counts
    res.script_errors = len(data.get("script_errors", []))
    res.dms_errors = len(data.get("dms_errors", []))


def run_mission(e: MissionEntry, res: MissionResult, run_dir: Path, a: argparse.Namespace) -> None:
    # 1. the user started a game since the last mission: stop politely
    foreign = foreign_processes()
    if foreign:
        res.status, res.reason = "skipped", "foreign_process: " + ", ".join(foreign)
        return
    # 2. a manual harness run owns the write dir
    hlock = SAVED_GAMES / a.write_dir_name / HARNESS_LOCK_NAME
    holder = wait_harness_lock(hlock, a.lock_wait_sec)
    if holder is not None:
        res.status, res.reason = "skipped", f"harness_lock_held: pid {holder} ({hlock})"
        return
    # 3. rebuild the test miz
    step, out = run_step(build_cmd(e), run_dir / f"{e.name}.build.log", BUILD_TIMEOUT_SEC)
    res.build = step
    hint = HARNESS_HINT_RE.search(out)
    res.miz = hint.group("miz").strip() if hint else default_miz(e)
    minutes = float(hint.group("minutes")) if hint else (e.minutes or 30.0)
    accel = e.accel or (int(hint.group("accel")) if hint and hint.group("accel") else 16)
    res.minutes, res.accel = minutes, accel
    if step.exit_code != 0:
        res.status = "build_failed"
        res.reason = f"dms build --test exit {step.exit_code} (see {step.log})"
        return
    if not Path(res.miz).is_file():
        res.status, res.reason = "build_failed", f"built miz not found: {res.miz}"
        return
    # 4. RAM gate
    ok, gb = wait_for_ram(a.min_free_gb, a.ram_wait_sec)
    res.free_ram_gb = round(gb, 1) if gb != float("inf") else None
    if not ok:
        res.status = "skipped"
        res.reason = f"low_ram: {gb:.1f} GB free < {a.min_free_gb:g} GB after {a.ram_wait_sec:g}s"
        return
    # 5. harness
    report = run_dir / f"{e.name}.harness.json"
    cmd = harness_cmd(e, res.miz, minutes, accel, report, a)
    step, _ = run_step(
        cmd, run_dir / f"{e.name}.harness.log", harness_timeout(minutes, accel, a.ram_wait_sec)
    )
    res.harness = step
    if report.is_file():
        res.harness_report = str(report)
        read_harness_report(res, report)
    if step.exit_code is None:
        res.status, res.reason = "infra_error", "nightly timeout waiting for the harness"
    else:
        res.status = HARNESS_EXIT_STATUS.get(step.exit_code, "infra_error")
        if res.status != "pass":
            res.reason = f"harness exit {step.exit_code} verdict {res.verdict}"


def plan_mission(e: MissionEntry, res: MissionResult, run_dir: Path, a: argparse.Namespace) -> None:
    """--dry-run: record the commands that would run; nothing is built or launched."""
    res.status = "planned"
    res.miz = default_miz(e)
    res.minutes, res.accel = e.minutes, e.accel or 16
    res.build = Step(cmd=build_cmd(e))
    cmd = harness_cmd(
        e, res.miz, e.minutes or 0.0, res.accel, run_dir / f"{e.name}.harness.json", a
    )
    if e.minutes is None:  # the real run takes minutes from the build's `harness:` hint
        cmd[cmd.index("--minutes") + 1] = "<from build>"
    res.harness = Step(cmd=cmd)


# ----------------------------------------------------------------------------------------------
# main
# ----------------------------------------------------------------------------------------------


def parse_args(argv: list[str] | None) -> argparse.Namespace:
    ap = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    ap.add_argument(
        "--config", type=Path, help=f"YAML/JSON mission list (default {DEFAULT_CONFIG})"
    )
    ap.add_argument("--min-free-gb", type=float, help="free physical RAM needed (default 12)")
    ap.add_argument("--ram-wait-sec", type=float, help="max wait for free RAM (default 900)")
    ap.add_argument(
        "--lock-wait-sec",
        type=float,
        default=1800,
        help="max wait for the sim lock / harness write-dir lock (default 1800)",
    )
    ap.add_argument("--write-dir-name", help=f"harness write dir (default {DEFAULT_WRITE_DIR})")
    ap.add_argument(
        "--out-dir", type=Path, default=DMS_HOME / "nightly", help="reports (~/.dms/nightly)"
    )
    ap.add_argument(
        "--lock-dir", type=Path, default=DMS_HOME / "locks", help="shared lock dir (~/.dms/locks)"
    )
    ap.add_argument(
        "--dry-run",
        action="store_true",
        help="check the gates and print the plan; build and launch nothing",
    )
    return ap.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    a = parse_args(argv)
    try:
        entries, opts, cfg_name = load_config(a.config)
    except (ConfigError, ValueError, yaml.YAMLError) as exc:
        print(f"[nightly] bad config: {exc}", file=sys.stderr)
        return 2
    if a.min_free_gb is None:
        a.min_free_gb = float(opts.get("min_free_gb", 12.0))
    if a.ram_wait_sec is None:
        a.ram_wait_sec = float(opts.get("ram_wait_sec", 900.0))
    if a.write_dir_name is None:
        a.write_dir_name = str(opts.get("write_dir_name", DEFAULT_WRITE_DIR))

    out_dir: Path = a.out_dir
    run_dir = out_dir / datetime.now().strftime("%Y%m%d-%H%M%S")
    rep = NightlyReport(
        started=now_iso(),
        host=socket.gethostname(),
        config=cfg_name,
        dry_run=a.dry_run,
        min_free_gb=a.min_free_gb,
        run_dir=str(run_dir),
    )
    rep.missions = [
        MissionResult(name=e.name, mission=e.mission, variant=e.variant) for e in entries
    ]

    sim_lock = a.lock_dir / SIM_LOCK_NAME
    foreign = foreign_processes()
    gb = free_ram_gb()
    rep.preflight = {
        "foreign_processes": foreign,
        "free_ram_gb": round(gb, 1) if gb != float("inf") else None,
        "sim_lock": str(sim_lock),
        "sim_lock_holder": lock_holder(sim_lock),
        "harness_lock_holder": lock_holder(SAVED_GAMES / a.write_dir_name / HARNESS_LOCK_NAME),
    }

    def refuse(reason: str) -> int:
        rep.status, rep.refused_reason = "refused", reason
        for m in rep.missions:
            m.status, m.reason = "skipped", "refused"
        path = write_report(rep, run_dir, out_dir)
        print(f"[nightly] refused: {reason} (report {path})", file=sys.stderr)
        return 2

    out_dir.mkdir(parents=True, exist_ok=True)
    if a.dry_run:
        for e, res in zip(entries, rep.missions, strict=True):
            plan_mission(e, res, run_dir, a)
        path = write_report(rep, run_dir, out_dir)
        print(json.dumps(asdict(rep), indent=2, default=str))
        log(f"dry run: nothing built or launched (report {path})")
        return 0

    if foreign:
        return refuse("foreign_process: " + ", ".join(foreign))
    if not acquire_sim_lock(sim_lock, "nightly", a.lock_wait_sec):
        return refuse(f"sim_lock_held: pid {lock_holder(sim_lock)} ({sim_lock})")
    try:
        stop_reason: str | None = None
        for e, res in zip(entries, rep.missions, strict=True):
            if stop_reason:
                res.status, res.reason = "skipped", stop_reason
                continue
            log(f"{e.name}: start")
            run_mission(e, res, run_dir, a)
            log(f"{e.name}: {res.status}{' (' + res.reason + ')' if res.reason else ''}")
            if res.reason and res.reason.startswith("foreign_process"):
                stop_reason = res.reason  # the user is playing: leave the PC alone
            write_report(rep, run_dir, out_dir)  # partial report survives a crash
        path = write_report(rep, run_dir, out_dir)
    finally:
        release_sim_lock(sim_lock)
    log(f"done: {rep.status} {rep.summary} (report {path})")
    return 0 if rep.status == "pass" else 1


if __name__ == "__main__":
    sys.exit(main())
