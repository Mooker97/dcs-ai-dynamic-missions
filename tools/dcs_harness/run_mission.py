"""Run a .miz in a real DCS World instance unattended, then parse dcs.log into a JSON report.

Usage:
    uv run python tools/dcs_harness/run_mission.py path/to/test.miz --minutes 5 [--accel 16]
        [--mode sp|server] [--render] [--wall-timeout SEC] [--write-dir-name DCS.dms_test]
        [--report out.json] [--probe] [--copy-login] [--keep-open] [--dry-run]
        [--priority idle|belownormal|normal] [--min-free-gb 6] [--ram-wait-sec 900]

How it works (details: docs/testing/STRATEGY.md):
  * Isolated write dir (default %USERPROFILE%/Saved Games/DCS.dms_test); the normal profile
    (Saved Games/DCS) is only ever read. Nothing inside the DCS install dir is modified.
  * Writes Config/autoexec.cfg (lets the hook run code in the "mission" and "gui" Lua states),
    Config/options.lua (copied once from the main profile, forced windowed/small/no-VR/muted, and
    ["launcher"] = false so the 2.9 launcher window never appears), Config/serverSettings.lua and
    Scripts/Hooks/dms_harness_hook.lua (from hook_template.lua).
  * mode "sp" (default, no login needed): DCS.exe -w <dir> --norender. Once the main menu idles the
    hook does what the GUI's Fly button does (START_PARAMS.command = '--mission' + missionPath,
    then __EMBEDDED__.doAction()) via net.dostring_in('gui', ...). The sim is unpaused (no briefing
    stop) and --accel N ramps model time to xN with iCommand 53 (Ctrl+Z).
  * mode "server": DCS.exe -w <dir> --server --norender; the hook calls net.start_server() for a
    private local server. Needs a saved ED login (Config/network.vault) in the write dir; no accel.
  * --render shows a 1280x720 window instead of --norender (about 2x wall time, more CPU/GPU/VRAM).
  * The hook exits DCS after "[DMS.TEST] DONE", after --minutes of model time, or on wall
    timeout; this script also kills our DCS process (matched by write-dir name) on hard timeout.

Log checks (on by default, --no-log-checks turns them off): after the run the harness replays
dcs.log and puts its own results in the report's log_checks (status PASS|FAIL|SKIP|INFO; a FAIL
fails the run like a [DMS.TEST] FAIL):
  * log_marks: replays the debug "[DMS][Intel] MARK add|remove id=N ..." lines. FAIL on an add of
    an id that is still live, a remove of an id never added (Intel logs a remove only for a mark
    it tracks), a failed mark call, or counts that disagree with the Lua marks check's
    "[DMS.TEST] ... added=A removed=R live=L" detail when that line is present. Without a Lua
    marks line it is informational (PASS = log self-consistent). SKIP when the Lua check says
    marks were drawn but no MARK lines were logged (debug off); INFO when there is nothing at all.
  * log_comms_overlap: "[DMS][Comms] PLAY n= ... start=<model s> end=<model s>" lines (info) never
    overlap: each start is >= the previous end + Comms.GAP_SEC (0.75) - 0.05. SKIP when the PLAY
    lines carry no start=/end= (format in docs/CONTRACTS.md "Test mode").

Exit codes: 0 = ran, no script errors, no FAIL; 1 = ran with failures/errors;
2 = infra problem (DCS not found / already running / never reached simulation).
"""

from __future__ import annotations

import argparse
import contextlib
import ctypes
import itertools
import json
import os
import re
import secrets
import shutil
import subprocess
import sys
import time

if sys.platform == "win32":  # Windows-only at runtime; guarded so the parsers import on Linux CI
    import winreg
from dataclasses import asdict, dataclass, field
from pathlib import Path

HERE = Path(__file__).resolve().parent
HOOK_TEMPLATE = HERE / "hook_template.lua"
SAVED_GAMES = Path(os.environ.get("USERPROFILE", str(Path.home()))) / "Saved Games"

# iCommand 53 "Accelerate model time" (Ctrl+Z): +1 step per press, single-player only.
ICOMMAND_ACCELERATE = 53
STEAM_APP_ID = "223750"  # DCS World Steam Edition

# ----------------------------------------------------------------------------------------------
# DCS discovery
# ----------------------------------------------------------------------------------------------


@dataclass
class DcsInstall:
    root: Path
    exe: Path
    is_dedicated: bool
    version: str
    source: str


def _exe_version(exe: Path) -> str:
    try:
        out = subprocess.run(
            ["powershell", "-NoProfile", "-Command", f"(Get-Item '{exe}').VersionInfo.FileVersion"],
            capture_output=True,
            text=True,
            timeout=20,
        )
        return out.stdout.strip() or "?"
    except Exception:
        return "?"


def _candidate_roots() -> list[tuple[Path, str]]:
    roots: list[tuple[Path, str]] = []
    env = os.environ.get("DCS_INSTALL")
    if env:
        roots.append((Path(env), "env:DCS_INSTALL"))
    for hive in (winreg.HKEY_CURRENT_USER, winreg.HKEY_LOCAL_MACHINE):
        try:
            with winreg.OpenKey(hive, r"Software\Eagle Dynamics") as ed:
                i = 0
                while True:
                    try:
                        sub = winreg.EnumKey(ed, i)
                    except OSError:
                        break
                    i += 1
                    try:
                        with winreg.OpenKey(ed, sub) as k:
                            p, _ = winreg.QueryValueEx(k, "Path")
                            roots.append((Path(p), f"registry:{sub}"))
                    except OSError:
                        pass
        except OSError:
            pass
    for drive in ("C:", "D:", "E:", "F:", "G:"):
        for rel in (
            r"\Program Files\Eagle Dynamics\DCS World Server",
            r"\Program Files\Eagle Dynamics\DCS World Server OpenBeta",
            r"\Program Files\Eagle Dynamics\DCS World",
            r"\Program Files\Eagle Dynamics\DCS World OpenBeta",
            r"\SteamLibrary\steamapps\common\DCSWorld",
            r"\Steam\steamapps\common\DCSWorld",
            r"\Program Files (x86)\Steam\steamapps\common\DCSWorld",
        ):
            roots.append((Path(drive + rel), "path-scan"))
    return roots


def discover_installs() -> list[DcsInstall]:
    seen: set[str] = set()
    found: list[DcsInstall] = []
    for root, source in _candidate_roots():
        key = str(root).lower()
        if key in seen or not root.is_dir():
            continue
        seen.add(key)
        for name, dedicated in (("DCS_server.exe", True), ("DCS.exe", False)):
            exe = root / "bin" / name
            if exe.is_file():
                found.append(DcsInstall(root, exe, dedicated, _exe_version(exe), source))
                break

    # newest version first, dedicated preferred on ties
    def vkey(i: DcsInstall) -> tuple[list[int], bool]:
        nums = [int(x) for x in re.findall(r"\d+", i.version)] or [0]
        return nums, i.is_dedicated

    found.sort(key=vkey, reverse=True)
    return found


# ----------------------------------------------------------------------------------------------
# process helpers (Windows)
# ----------------------------------------------------------------------------------------------


def list_dcs_processes() -> list[dict[str, str]]:
    ps = (
        "Get-CimInstance Win32_Process | "
        "Where-Object { $_.Name -in @('DCS.exe','DCS_server.exe') } | "
        "Select-Object ProcessId,Name,CommandLine | ConvertTo-Json -Compress"
    )
    out = subprocess.run(
        ["powershell", "-NoProfile", "-Command", ps], capture_output=True, text=True, timeout=30
    ).stdout.strip()
    if not out:
        return []
    data = json.loads(out)
    if isinstance(data, dict):
        data = [data]
    return [{k: str(v or "") for k, v in d.items()} for d in data]


PRIORITY_CLASSES = {
    "idle": 0x00000040,  # IDLE_PRIORITY_CLASS
    "belownormal": 0x00004000,  # BELOW_NORMAL_PRIORITY_CLASS
    "normal": 0x00000020,  # NORMAL_PRIORITY_CLASS
}
PS_PRIORITY = {"idle": "Idle", "belownormal": "BelowNormal", "normal": "Normal"}


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
    """Available physical memory in GB (Windows GlobalMemoryStatusEx)."""
    st = _MemStatus()
    st.dwLength = ctypes.sizeof(_MemStatus)
    if not ctypes.windll.kernel32.GlobalMemoryStatusEx(ctypes.byref(st)):  # type: ignore[attr-defined]
        return float("inf")
    return st.ullAvailPhys / 1024**3


def wait_for_ram(min_gb: float, max_wait_sec: int) -> tuple[bool, float]:
    """Poll free RAM until >= min_gb (every 30 s, up to max_wait_sec). Returns (ok, last_gb)."""
    t0 = time.monotonic()
    while True:
        gb = free_ram_gb()
        if gb >= min_gb:
            return True, gb
        if time.monotonic() - t0 >= max_wait_sec:
            return False, gb
        print(f"[harness] only {gb:.1f} GB RAM free (< {min_gb} GB); waiting 30 s", flush=True)
        time.sleep(30)


def set_priority(pids: list[str], priority: str) -> None:
    if not pids:
        return
    ps = "; ".join(
        f"try {{ (Get-Process -Id {pid}).PriorityClass = '{PS_PRIORITY[priority]}' }} catch {{}}"
        for pid in pids
    )
    subprocess.run(["powershell", "-NoProfile", "-Command", ps], capture_output=True, timeout=30)


def ours(proc: dict[str, str], write_dir_name: str) -> bool:
    return write_dir_name.lower() in proc.get("CommandLine", "").lower()


def kill_ours(write_dir_name: str) -> list[str]:
    killed = []
    for p in list_dcs_processes():
        if ours(p, write_dir_name):
            subprocess.run(["taskkill", "/F", "/T", "/PID", p["ProcessId"]], capture_output=True)
            killed.append(p["ProcessId"])
    return killed


# ----------------------------------------------------------------------------------------------
# write-dir preparation
# ----------------------------------------------------------------------------------------------


def lua_value(v: object, indent: str = "") -> str:
    if v is None:
        return "nil"
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, int | float):
        return repr(v)
    if isinstance(v, str):
        return '"' + v.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n") + '"'
    if isinstance(v, list):
        return "{ " + ", ".join(lua_value(x, indent) for x in v) + " }"
    if isinstance(v, dict):
        inner = indent + "    "
        items = ",\n".join(f'{inner}["{k}"] = {lua_value(x, inner)}' for k, x in v.items())
        return "{\n" + items + "\n" + indent + "}"
    raise TypeError(type(v))


def patch_options(
    src: Path | None, dst: Path, width: int, height: int, *, mute: bool = True
) -> None:
    if src and src.is_file():
        text = src.read_text(encoding="utf-8", errors="replace")
        text = re.sub(r'(\["fullScreen"\]\s*=\s*)true', r"\1false", text)
        text = re.sub(r'(\["width"\]\s*=\s*)\d+', rf"\g<1>{width}", text, count=1)
        text = re.sub(r'(\["height"\]\s*=\s*)\d+', rf"\g<1>{height}", text, count=1)
        text = re.sub(r'(\["aspect"\]\s*=\s*)[\d.]+', rf"\g<1>{width / height:.6f}", text, count=1)
        text = re.sub(
            r'(\["VR"\]\s*=\s*\{[^}]*?\["enable"\]\s*=\s*)true',
            r"\1false",
            text,
            count=1,
            flags=re.S,
        )
        if mute:
            text = re.sub(r'(\["volume"\]\s*=\s*)\d+', r"\g<1>0", text)
        text = re.sub(r'(\["music"\]\s*=\s*)\d+', r"\g<1>0", text)
        dst.write_text(text, encoding="utf-8")


def force_unattended_options(opts: Path) -> None:
    """Options that must hold on every run (test profile only): no 2.9 launcher window."""
    if not opts.is_file():
        return
    text = opts.read_text(encoding="utf-8", errors="replace")
    new = re.sub(r'(\["launcher"\]\s*=\s*)true', r"\1false", text)
    if new != text:
        opts.write_text(new, encoding="utf-8")


def prepare_write_dir(
    write_dir: Path,
    miz: Path,
    mode: str,
    minutes: float,
    accel: int,
    wall_timeout: int,
    inject: str,
    probe: bool = False,
    watch_size: tuple[int, int] | None = None,
) -> dict[str, object]:
    (write_dir / "Config").mkdir(parents=True, exist_ok=True)
    (write_dir / "Scripts" / "Hooks").mkdir(parents=True, exist_ok=True)
    (write_dir / "Missions" / "dms_harness").mkdir(parents=True, exist_ok=True)
    (write_dir / "Tracks").mkdir(parents=True, exist_ok=True)
    logs = write_dir / "Logs"
    if logs.is_dir():
        for f in ("dcs.log", "dcs.log.old"):
            with contextlib.suppress(PermissionError):
                (logs / f).unlink(missing_ok=True)

    run_miz = write_dir / "Missions" / "dms_harness" / miz.name
    shutil.copy2(miz, run_miz)
    miz_lua_path = str(run_miz).replace("\\", "/")

    # Seed options.lua once from the user's main profile (read-only copy), then force small window.
    opts = write_dir / "Config" / "options.lua"
    if watch_size:  # --watch: re-seed every run, larger window, sound on
        patch_options(SAVED_GAMES / "DCS" / "Config" / "options.lua", opts, *watch_size, mute=False)
    elif not opts.exists():
        patch_options(SAVED_GAMES / "DCS" / "Config" / "options.lua", opts, 1280, 720)
    force_unattended_options(opts)
    # nicknames: give the server a name so no first-run prompt appears
    nick = write_dir / "Config" / "nicknames.lua"
    if not nick.exists():
        nick.write_text('nicknames = { [1] = "DMS-Harness" }\n', encoding="utf-8")

    password = secrets.token_hex(6)
    port = 10411
    server_cfg = {
        "description": "DMS harness",
        "require_pure_textures": False,
        "listStartIndex": 1,
        "advanced": {
            "resume_mode": 1,
            "allow_change_tailno": True,
            "pause_on_load": False,
            "pause_without_clients": False,
            "voice_chat_server": False,
        },
        "port": port,
        "mode": 0,
        "bind_address": "127.0.0.1",
        "isPublic": False,
        "listShuffle": False,
        "password": password,
        "listLoop": False,
        "name": "DMS harness (private)",
        "require_pure_scripts": False,
        "missionList": [miz_lua_path],
        "require_pure_clients": False,
        "maxPlayers": 2,
    }
    (write_dir / "Config" / "serverSettings.lua").write_text(
        "cfg = " + lua_value(server_cfg) + "\n", encoding="utf-8"
    )
    (write_dir / "Config" / "autoexec.cfg").write_text(
        "-- written by DMS harness: allow the harness hook to run code in the mission env\n"
        "if not net then net = {} end\n"
        'net.allow_unsafe_api = { "userhooks" }\n'
        'net.allow_dostring_in = { "mission", "gui" }\n',
        encoding="utf-8",
    )

    hook_cfg = {
        "mode": mode,
        "miz": miz_lua_path,
        "password": password,
        "port": port,
        "maxModelSec": int(minutes * 60),
        "maxRealSec": wall_timeout - 30,
        "graceSec": 3,
        "menuFrames": 30,
        "menuDelaySec": 20 if mode == "server" else 15,
        "accel": accel,
        "accelSteps": max(0, accel.bit_length() - 1) if accel > 1 else 0,
        "probe": probe,
        "accelCommand": ICOMMAND_ACCELERATE,
        "injectLua": inject,
    }
    hook = HOOK_TEMPLATE.read_text(encoding="utf-8").replace("__CFG__", lua_value(hook_cfg))
    (write_dir / "Scripts" / "Hooks" / "dms_harness_hook.lua").write_text(hook, encoding="utf-8")
    return {"run_miz": str(run_miz), **hook_cfg}


# ----------------------------------------------------------------------------------------------
# log parsing
# ----------------------------------------------------------------------------------------------

LINE_RE = re.compile(
    r"^(\S+ \S+)\s+(INFO|WARNING|ERROR|ALERT|DEBUG)\s+(\S+)\s+\(([^)]*)\):\s?(.*)$"
)
TEST_RE = re.compile(r"\[DMS\.TEST\]\s+(PASS|FAIL|SKIP|INFO|DONE)\b\s*(\S+)?\s*(.*)$")
OUTCOME_RE = re.compile(r"\[DMS\.OUTCOME\]\s*(.*)$")
HARNESS_RE = re.compile(r"\[DMS\.HARNESS\]\s+(\S+)\s*(.*)$")
MARK_RE = re.compile(r"\[DMS\]\[Intel\] MARK (add|remove)(?: failed)? id=(\d+)(.*)$")
MARK_FAILED_RE = re.compile(r"\[DMS\]\[Intel\] MARK add failed id=(\d+)")
LUA_MARKS_RE = re.compile(r"\badded=(\d+) removed=(\d+) live=(\d+) failed=(\d+)")
PLAY_RE = re.compile(r"\[DMS\]\[Comms\] PLAY\b(.*)$")
KV_RE = re.compile(r"(?:^|\s)(n|line|start|end)=(\S+)")
LOAD_MISSION_RE = re.compile(r"loadMission (?!Done)(.+?\.miz)\s*$")
COMMS_GAP_SEC = 0.75  # DMS.Comms.GAP_SEC: the queue waits end + GAP before the next PLAY


@dataclass
class Report:
    miz: str
    mode: str
    exe: str
    launched: bool = False
    reached_simulation: bool = False
    exit_reason: str = "unknown"
    wall_seconds: float = 0.0
    model_seconds_last: float | None = None
    phases: list[str] = field(default_factory=list)
    tests: list[dict[str, str]] = field(default_factory=list)
    log_checks: list[dict[str, str]] = field(default_factory=list)
    done: bool = False
    outcomes: list[object] = field(default_factory=list)
    script_errors: list[str] = field(default_factory=list)
    dms_errors: list[str] = field(default_factory=list)
    other_errors: list[str] = field(default_factory=list)
    log_path: str = ""
    loaded_miz: str = ""
    notes: list[str] = field(default_factory=list)
    verdict: str = "infra_error"


def _kv(rest: str) -> dict[str, str]:
    """key=value pairs before the quoted text of a log line (the text itself may contain t=)."""
    head = rest.split("'", 1)[0]
    return {m[1]: m[2] for m in KV_RE.finditer(head)}


def check_marks_log(msgs: list[str]) -> dict[str, str]:
    """log_marks: replay Intel MARK add/remove lines; cross-check the Lua marks check counts.

    ``msgs`` are the DMS log messages in log order, including ``[DMS.TEST]`` lines: the replay
    counters are snapshotted at the (last) Lua marks line, so marks removed afterwards (e.g.
    Intel.stop at mission end) do not count as a disagreement.
    """
    live: set[int] = set()
    adds = removes = peak = failed = 0
    unknown: list[int] = []
    problems: list[str] = []
    lua: tuple[int, int, int, int] | None = None
    snap: tuple[int, int, int, int] = (0, 0, 0, 0)
    for msg in msgs:
        if TEST_RE.search(msg):
            if lm := LUA_MARKS_RE.search(msg):
                lua = (int(lm[1]), int(lm[2]), int(lm[3]), int(lm[4]))
                snap = (adds, removes, len(live), failed)
            continue
        if MARK_FAILED_RE.search(msg):
            failed += 1
            continue
        m = MARK_RE.search(msg)
        if not m:
            continue
        op, mid = m[1], int(m[2])
        if op == "add":
            if mid in live:
                problems.append(f"id {mid} added while live")
            live.add(mid)
            adds += 1
            peak = max(peak, len(live))
        elif mid in live:
            live.discard(mid)
            removes += 1
        else:
            unknown.append(mid)
    if unknown:
        problems.append(
            f"{len(unknown)} remove(s) of never-added id(s): " + ",".join(map(str, unknown[:5]))
        )
    if failed:
        problems.append(f"{failed} mark call(s) failed")
    detail = f"adds={adds} removes={removes} live_at_end={len(live)} peak={peak}"
    if adds == 0 and not unknown and not failed:
        if lua and lua[0] > 0:
            return {
                "status": "SKIP",
                "name": "log_marks",
                "detail": f"Lua marks check reports added={lua[0]} but no MARK lines (debug off?)",
            }
        return {
            "status": "INFO",
            "name": "log_marks",
            "detail": "no MARK lines (debug off, or Intel drew no marks)",
        }
    if lua is None:
        detail += " (informational: no Lua marks check line)"
    elif lua != snap:
        problems.append(
            "log replay (added={} removed={} live={} failed={}) disagrees with Lua marks check "
            "(added={} removed={} live={} failed={})".format(*snap, *lua)
        )
    else:
        detail += ", matches Lua marks check"
    if problems:
        bad = "; ".join(problems[:5])
        return {"status": "FAIL", "name": "log_marks", "detail": f"{bad} [{detail}]"}
    return {"status": "PASS", "name": "log_marks", "detail": detail}


def check_comms_overlap_log(
    msgs: list[str], tol: float = 0.05, gap: float = COMMS_GAP_SEC
) -> dict[str, str]:
    """log_comms_overlap: each Comms PLAY starts >= previous end + gap - tol (model time)."""
    tx: list[tuple[float, float, str]] = []
    untimed = 0
    for msg in msgs:
        m = PLAY_RE.search(msg)
        if not m:
            continue
        kv = _kv(m[1])
        try:
            tx.append((float(kv["start"]), float(kv["end"]), kv.get("line", "?")))
        except (KeyError, ValueError):
            untimed += 1
    if not tx:
        if untimed:
            return {
                "status": "SKIP",
                "name": "log_comms_overlap",
                "detail": f"{untimed} PLAY line(s) without start=/end= (see CONTRACTS Test mode)",
            }
        return {"status": "INFO", "name": "log_comms_overlap", "detail": "no Comms PLAY lines"}
    tx.sort(key=lambda e: e[0])
    overlaps = [
        f"{a[2]}@{a[0]:.1f}+{a[1] - a[0]:.1f} overlaps {b[2]}@{b[0]:.1f}"
        for a, b in itertools.pairwise(tx)
        if b[0] < a[1] + gap - tol
    ]
    detail = f"{len(tx)} timed PLAY line(s)" + (f", {untimed} untimed" if untimed else "")
    if overlaps:
        return {
            "status": "FAIL",
            "name": "log_comms_overlap",
            "detail": f"{len(overlaps)} overlap(s): " + "; ".join(overlaps[:4]) + f" [{detail}]",
        }
    return {"status": "PASS", "name": "log_comms_overlap", "detail": detail + ", no overlap"}


def run_log_checks(msgs: list[str]) -> list[dict[str, str]]:
    """Harness-side checks over the DMS log lines, in log order (see the module docstring)."""
    return [check_marks_log(msgs), check_comms_overlap_log(msgs)]


def parse_log(log_path: Path, rep: Report, *, log_checks: bool = True) -> None:
    rep.log_path = str(log_path)
    if not log_path.is_file():
        rep.notes.append("dcs.log not found in write dir")
        return
    lines = log_path.read_text(encoding="utf-8", errors="replace").splitlines()
    for raw in lines:
        lm = LOAD_MISSION_RE.search(raw)
        if lm:
            rep.loaded_miz = lm[1]
    cur: dict[str, str] | None = None
    entries: list[dict[str, str]] = []
    for raw in lines:
        m = LINE_RE.match(raw)
        if m:
            cur = {"ts": m[1], "level": m[2], "sub": m[3], "thread": m[4], "msg": m[5]}
            entries.append(cur)
        elif cur is not None:  # continuation (tracebacks)
            cur["msg"] += "\n" + raw
    for e in entries:
        msg, lvl, sub = e["msg"], e["level"], e["sub"]
        if h := HARNESS_RE.search(msg):
            kind, rest = h[1], h[2]
            if kind in ("PHASE", "EXIT"):
                rep.phases.append(f"{e['ts']} {kind} {rest}")
            if kind == "PHASE" and rest.startswith("sim_start"):
                rep.reached_simulation = True
            if kind == "EXIT":
                rep.exit_reason = rest.split()[0].removeprefix("reason=")
            if mm := re.search(r"model=([\d.]+)", rest):
                rep.model_seconds_last = float(mm[1])
            if kind == "ERROR":
                rep.other_errors.append(f"{e['ts']} harness: {rest}")
            continue
        if t := TEST_RE.search(msg):
            status = t[1]
            if status == "DONE":
                rep.done = True
            else:
                rep.tests.append(
                    {"status": status, "name": t[2] or "", "detail": t[3].strip(), "ts": e["ts"]}
                )
            continue
        if o := OUTCOME_RE.search(msg):
            try:
                rep.outcomes.append(json.loads(o[1]))
            except json.JSONDecodeError:
                rep.outcomes.append(o[1])
            continue
        if "[DMS]" in msg and ("ERROR" in msg or lvl == "ERROR"):
            rep.dms_errors.append(f"{e['ts']} {msg[:2000]}")
            continue
        if "login is required" in msg or "Login failed" in msg:
            rep.other_errors.append(f"{e['ts']} {sub}: {msg[:300]}")
            if "login is required" in msg:
                rep.notes.append(
                    "BLOCKER: ED login required to start a server (one-time setup, see docs)"
                )
            continue
        if lvl == "ERROR" and (
            sub == "SCRIPTING" or "Mission script error" in msg or "SCRIPTING ERROR" in msg
        ):
            rep.script_errors.append(f"{e['ts']} {sub}: {msg[:2000]}")
        elif lvl == "ERROR" and sub in ("LuaGUI", "Lua::Config", "DCS", "LuaNET", "NET"):
            rep.other_errors.append(f"{e['ts']} {sub}: {msg[:500]}")
    if log_checks:
        dms_msgs = [e["msg"] for e in entries if "[DMS][" in e["msg"] or "[DMS.TEST]" in e["msg"]]
        rep.log_checks = run_log_checks(dms_msgs)


CRASH_MARKERS = ("Out of memory in ed_malloc", "fatal_out_of_memory", "Minidump created")


def scan_for_crash(log_path: Path, pos: int) -> tuple[str | None, int]:
    """Return (first crash line since byte pos, new pos). The log is reset on each DCS start."""
    try:
        size = log_path.stat().st_size
        if size < pos:
            pos = 0
        with log_path.open("rb") as f:
            f.seek(pos)
            chunk = f.read()
    except OSError:
        return None, pos
    for line in chunk.decode("utf-8", errors="replace").splitlines():
        if any(m in line for m in CRASH_MARKERS):
            return line.strip()[:300], pos + len(chunk)
    return None, pos + len(chunk)


def verdict(rep: Report) -> int:
    if rep.loaded_miz and Path(rep.loaded_miz).name.lower() != Path(rep.miz).name.lower():
        # another harness run shared the write dir and swapped the hook (2026-10-29)
        rep.notes.append(f"DCS loaded {rep.loaded_miz}, not {Path(rep.miz).name}")
        rep.verdict = "wrong_mission"
        return 2
    if not rep.reached_simulation:
        rep.verdict = "infra_error"
        return 2
    fails = [t for t in rep.tests + rep.log_checks if t["status"] == "FAIL"]
    if rep.script_errors or rep.dms_errors or fails:
        rep.verdict = "fail"
        return 1
    rep.verdict = "pass" if (rep.done or rep.tests) else "ran_no_assertions"
    return 0


# ----------------------------------------------------------------------------------------------
# write-dir lock: one harness run per write dir (two runs overwrite each other's hook and
# kill_ours() would kill the other run's DCS)
# ----------------------------------------------------------------------------------------------

LOCK_NAME = "dms_harness.lock"


def pid_alive(pid: int) -> bool:
    if pid <= 0:
        return False
    if sys.platform != "win32":
        try:
            os.kill(pid, 0)
        except OSError:
            return False
        return True
    k32 = ctypes.windll.kernel32
    h = k32.OpenProcess(0x1000, False, pid)  # PROCESS_QUERY_LIMITED_INFORMATION
    if not h:
        return False
    try:
        code = ctypes.c_ulong()
        ok = k32.GetExitCodeProcess(h, ctypes.byref(code))
        return bool(ok) and code.value == 259  # STILL_ACTIVE
    finally:
        k32.CloseHandle(h)


def acquire_lock(write_dir: Path, wait_sec: int, poll_sec: float = 30.0) -> Path | None:
    """Create <write_dir>/dms_harness.lock holding our pid; wait while a live run holds it."""
    write_dir.mkdir(parents=True, exist_ok=True)
    lock = write_dir / LOCK_NAME
    deadline = time.monotonic() + wait_sec
    while True:
        try:
            fd = os.open(lock, os.O_CREAT | os.O_EXCL | os.O_WRONLY)
        except FileExistsError:
            try:
                holder = int(lock.read_text(encoding="utf-8").split()[0])
            except (OSError, ValueError, IndexError):
                holder = -1
            if not pid_alive(holder):
                with contextlib.suppress(OSError):
                    lock.unlink()
                continue
            if time.monotonic() >= deadline:
                return None
            print(f"[harness] {lock} held by live pid {holder}; waiting", flush=True)
            time.sleep(poll_sec)
            continue
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            f.write(f"{os.getpid()}\n")
        return lock


def release_lock(lock: Path) -> None:
    with contextlib.suppress(OSError):
        if lock.read_text(encoding="utf-8").split()[0] == str(os.getpid()):
            lock.unlink()


# ----------------------------------------------------------------------------------------------
# main
# ----------------------------------------------------------------------------------------------


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    ap.add_argument("miz", type=Path)
    ap.add_argument("--minutes", type=float, default=5.0, help="model minutes before forced exit")
    ap.add_argument(
        "--accel", type=int, default=1, help="model-time acceleration factor (sp mode only)"
    )
    ap.add_argument(
        "--mode",
        choices=["sp", "server"],
        default="sp",
        help="sp: single-player mission, no login, accel works (default); "
        "server: private local MP server (needs ED login, no accel)",
    )
    ap.add_argument(
        "--render",
        action="store_true",
        help="render a 1280x720 window instead of --norender (more GPU load; for watching a run)",
    )
    ap.add_argument(
        "--watch",
        action="store_true",
        help="for a person to watch: rendered 1920x1080 window with sound, real time (implies "
        "--render --accel 1 --priority normal; options.lua re-seeded from the main profile)",
    )
    ap.add_argument("--probe", action="store_true", help="log the hook-visible DCS API inventory")
    ap.add_argument(
        "--wall-timeout",
        type=int,
        default=0,
        help="hard kill after N real seconds (default derived)",
    )
    ap.add_argument("--write-dir-name", default="DCS.dms_test")
    ap.add_argument("--exe", type=Path, help="explicit DCS.exe / DCS_server.exe")
    ap.add_argument("--inject", default="", help="Lua run in mission env at load (via a_do_script)")
    ap.add_argument("--report", type=Path, help="write JSON report here")
    ap.add_argument("--keep-open", action="store_true", help="do not kill DCS on wall timeout")
    ap.add_argument(
        "--dry-run", action="store_true", help="prepare write dir, print command, do not launch"
    )
    ap.add_argument(
        "--allow-running", action="store_true", help="launch even if another DCS is running"
    )
    ap.add_argument(
        "--priority",
        choices=sorted(PRIORITY_CLASSES),
        default="belownormal",
        help="CPU priority class of the DCS process (default belownormal: be nice to other apps)",
    )
    ap.add_argument(
        "--min-free-gb",
        type=float,
        default=12.0,
        help="wait (up to --ram-wait-sec) until this much physical RAM is free before launching "
        "(Syria ran out of memory at 9 GB free)",
    )
    ap.add_argument("--ram-wait-sec", type=int, default=900, help="max wait for free RAM")
    ap.add_argument(
        "--no-log-checks",
        action="store_true",
        help="skip the harness-side dcs.log checks (log_marks, log_comms_overlap)",
    )
    ap.add_argument(
        "--copy-login",
        action="store_true",
        help="opt-in: copy your saved ED login (Saved Games/DCS/Config/network.vault) "
        "into the test write dir",
    )
    a = ap.parse_args(argv)
    if a.watch:
        a.render, a.accel, a.priority = True, 1, "normal"

    miz = a.miz.resolve()
    if not miz.is_file():
        print(f"miz not found: {miz}", file=sys.stderr)
        return 2

    lock = acquire_lock(SAVED_GAMES / a.write_dir_name, a.ram_wait_sec)
    if lock is None:
        print(f"write dir {a.write_dir_name} is in use by another harness run", file=sys.stderr)
        return 2
    try:
        return _run(a, miz)
    finally:
        release_lock(lock)


def _run(a: argparse.Namespace, miz: Path) -> int:
    if a.exe:
        inst = DcsInstall(
            a.exe.parent.parent,
            a.exe,
            a.exe.name.lower() == "dcs_server.exe",
            _exe_version(a.exe),
            "cli",
        )
    else:
        installs = discover_installs()
        if not installs:
            print("no DCS install found (set DCS_INSTALL or --exe)", file=sys.stderr)
            return 2
        # sp needs the client (DCS_server.exe has no single-player); server prefers dedicated
        clients = [i for i in installs if not i.is_dedicated]
        inst = clients[0] if a.mode == "sp" and clients else installs[0]

    mode = a.mode
    wall = a.wall_timeout or int(a.minutes * 60 / max(1, a.accel) + 420)

    write_dir = SAVED_GAMES / a.write_dir_name
    rep = Report(miz=str(miz), mode=mode, exe=str(inst.exe))
    cfg = prepare_write_dir(
        write_dir,
        miz,
        mode,
        a.minutes,
        a.accel,
        wall,
        a.inject,
        a.probe,
        watch_size=(1920, 1080) if a.watch else None,
    )
    vault = write_dir / "Config" / "network.vault"
    if a.copy_login:
        src = SAVED_GAMES / "DCS" / "Config" / "network.vault"
        if src.is_file():
            shutil.copy2(src, vault)
            rep.notes.append("copied network.vault from main profile (--copy-login)")
        else:
            rep.notes.append("--copy-login: no network.vault in main profile")
    if mode == "server" and not vault.is_file():
        rep.notes.append(
            "no Config/network.vault in write dir: server start will fail with 'login is required' "
            "(see docs/testing/STRATEGY.md, one-time login)"
        )

    args = [str(inst.exe), "-w", a.write_dir_name]
    if mode == "server":
        args += ["--server"]
    if not a.render:
        args += ["--norender"]
    rep.notes.append(f"install={inst.root} version={inst.version} dedicated={inst.is_dedicated}")
    rep.notes.append("cmd=" + " ".join(args))

    if a.dry_run:
        print(json.dumps({"cmd": args, "write_dir": str(write_dir), "hook_cfg": cfg}, indent=2))
        return 0

    running = list_dcs_processes()
    foreign = [p for p in running if not ours(p, a.write_dir_name)]
    if foreign and not a.allow_running:
        print(
            f"another DCS is running ({foreign[0]['Name']} pid {foreign[0]['ProcessId']}); "
            "close it or pass --allow-running",
            file=sys.stderr,
        )
        return 2
    kill_ours(a.write_dir_name)

    ok_ram, gb = wait_for_ram(a.min_free_gb, a.ram_wait_sec)
    if not ok_ram:
        print(
            f"only {gb:.1f} GB RAM free after waiting {a.ram_wait_sec}s "
            f"(need {a.min_free_gb}); not launching",
            file=sys.stderr,
        )
        return 2
    rep.notes.append(f"free_ram_gb_at_launch={gb:.1f} priority={a.priority}")

    old_log = write_dir / "Logs" / "dcs.log"
    if old_log.is_file():  # so the crash scan never reads the previous run's log
        old_log.replace(old_log.with_name("dcs.log.prev"))

    t0 = time.monotonic()
    env = dict(os.environ)
    if "steamapps" in str(inst.exe).lower():
        # Steam edition: without these, DCS asks Steam to relaunch it and our args are lost.
        env.setdefault("SteamAppId", STEAM_APP_ID)
        env.setdefault("SteamGameId", STEAM_APP_ID)
    subprocess.Popen(
        args,
        cwd=str(inst.exe.parent),
        close_fds=True,
        env=env,
        creationflags=PRIORITY_CLASSES[a.priority],
    )
    rep.launched = True
    seen_ours = False
    prioritised: set[str] = set()
    log_path = write_dir / "Logs" / "dcs.log"
    log_pos = 0
    print(f"[harness] launched {' '.join(args)}; wall timeout {wall}s; log {log_path}", flush=True)
    while True:
        time.sleep(5)
        elapsed = time.monotonic() - t0
        # A crashed DCS hangs on its crash reporter instead of exiting: stop as soon as we see it.
        crash, log_pos = scan_for_crash(log_path, log_pos)
        if crash:
            rep.exit_reason = "dcs_crashed"
            rep.notes.append(f"DCS crashed: {crash}")
            rep.notes.append(f"killed pids {kill_ours(a.write_dir_name)}")
            break
        procs = [p for p in list_dcs_processes() if ours(p, a.write_dir_name)]
        if procs:
            seen_ours = True
            fresh = [p["ProcessId"] for p in procs if p["ProcessId"] not in prioritised]
            if fresh:  # creationflags covers DCS.exe; re-apply in case it re-spawned itself
                set_priority(fresh, a.priority)
                prioritised.update(fresh)
        elif elapsed > 60 or seen_ours:
            # Steam may relaunch DCS without our args: detect a foreign DCS that appeared
            foreign_now = [p for p in list_dcs_processes() if not ours(p, a.write_dir_name)]
            if foreign_now and not foreign:
                rep.notes.append(
                    "a DCS process without our -w arg is running (Steam relaunch dropped args?): "
                    + foreign_now[0].get("CommandLine", "")
                )
            break
        if elapsed > wall:
            rep.exit_reason = "wall_timeout_killed"
            if not a.keep_open:
                rep.notes.append(f"killed pids {kill_ours(a.write_dir_name)}")
            break
    rep.wall_seconds = round(time.monotonic() - t0, 1)
    time.sleep(2)
    parse_log(log_path, rep, log_checks=not a.no_log_checks)
    code = verdict(rep)
    out = json.dumps(asdict(rep), indent=2, default=str)
    if a.report:
        a.report.write_text(out, encoding="utf-8")
    print(out)
    return code


if __name__ == "__main__":
    sys.exit(main())
