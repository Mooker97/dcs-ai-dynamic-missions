"""Run a .miz in a real DCS World instance unattended, then parse dcs.log into a JSON report.

Usage:
    uv run python tools/dcs_harness/run_mission.py path/to/test.miz --minutes 5 [--accel N]
        [--mode auto|server|client] [--wall-timeout SEC] [--write-dir-name DCS.dms_test]
        [--report out.json] [--copy-login] [--keep-open] [--dry-run]

How it works (details: docs/testing/STRATEGY.md):
  * Isolated write dir (default %USERPROFILE%/Saved Games/DCS.dms_test); the normal profile
    (Saved Games/DCS) is only ever read. Nothing inside the DCS install dir is modified.
  * Writes Config/serverSettings.lua (mission list = test mission), Config/autoexec.cfg (lets the
    hook run code in the mission env), Config/options.lua (copied from the main profile, forced
    windowed/small/no-VR/muted) and Scripts/Hooks/dms_harness_hook.lua (from hook_template.lua).
  * mode "server" (default): DCS.exe -w <dir> --server --norender. Skips the 2.9 launcher window;
    the hook calls net.start_server() with a private local server running the test mission.
    Needs a saved ED login (Config/network.vault) in the write dir: see --copy-login.
  * mode "client": DCS.exe -w <dir> (normal client). Currently blocks on the launcher window.
  * The hook exits DCS after "[DMS.TEST] DONE", after --minutes of model time, or on wall
    timeout; this script also kills our DCS process (matched by write-dir name) on hard timeout.

Exit codes: 0 = ran, no script errors, no FAIL; 1 = ran with failures/errors;
2 = infra problem (DCS not found / already running / never reached simulation).
"""

from __future__ import annotations

import argparse
import contextlib
import json
import os
import re
import secrets
import shutil
import subprocess
import sys
import time
import winreg
from dataclasses import asdict, dataclass, field
from pathlib import Path

HERE = Path(__file__).resolve().parent
HOOK_TEMPLATE = HERE / "hook_template.lua"
SAVED_GAMES = Path(os.environ.get("USERPROFILE", str(Path.home()))) / "Saved Games"

# Export command ids for time acceleration (Ctrl+Z steps). Experimental: ignored in MP sessions.
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


def patch_options(src: Path | None, dst: Path, width: int, height: int) -> None:
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
        text = re.sub(r'(\["volume"\]\s*=\s*)\d+', r"\g<1>0", text)
        text = re.sub(r'(\["music"\]\s*=\s*)\d+', r"\g<1>0", text)
        dst.write_text(text, encoding="utf-8")


def prepare_write_dir(
    write_dir: Path,
    miz: Path,
    mode: str,
    minutes: float,
    accel: int,
    wall_timeout: int,
    inject: str,
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
    if not opts.exists():
        patch_options(SAVED_GAMES / "DCS" / "Config" / "options.lua", opts, 1280, 720)
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
        'net.allow_dostring_in = { "mission" }\n',
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
        "menuDelaySec": 20 if mode == "server" else 5,
        "accelSteps": max(0, accel.bit_length() - 1) if accel > 1 else 0,
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
    done: bool = False
    outcomes: list[object] = field(default_factory=list)
    script_errors: list[str] = field(default_factory=list)
    dms_errors: list[str] = field(default_factory=list)
    other_errors: list[str] = field(default_factory=list)
    log_path: str = ""
    notes: list[str] = field(default_factory=list)
    verdict: str = "infra_error"


def parse_log(log_path: Path, rep: Report) -> None:
    rep.log_path = str(log_path)
    if not log_path.is_file():
        rep.notes.append("dcs.log not found in write dir")
        return
    lines = log_path.read_text(encoding="utf-8", errors="replace").splitlines()
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


def verdict(rep: Report) -> int:
    if not rep.reached_simulation:
        rep.verdict = "infra_error"
        return 2
    fails = [t for t in rep.tests if t["status"] == "FAIL"]
    if rep.script_errors or rep.dms_errors or fails:
        rep.verdict = "fail"
        return 1
    rep.verdict = "pass" if (rep.done or rep.tests) else "ran_no_assertions"
    return 0


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
        "--accel", type=int, default=1, help="time acceleration (power of 2; experimental, SP only)"
    )
    ap.add_argument("--mode", choices=["auto", "server", "client"], default="auto")
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
        "--copy-login",
        action="store_true",
        help="opt-in: copy your saved ED login (Saved Games/DCS/Config/network.vault) "
        "into the test write dir",
    )
    a = ap.parse_args(argv)

    miz = a.miz.resolve()
    if not miz.is_file():
        print(f"miz not found: {miz}", file=sys.stderr)
        return 2

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
        inst = installs[0]

    mode = a.mode
    if mode == "auto":
        mode = "server"
    wall = a.wall_timeout or int(a.minutes * 60 / max(1, a.accel) + 420)

    write_dir = SAVED_GAMES / a.write_dir_name
    rep = Report(miz=str(miz), mode=mode, exe=str(inst.exe))
    cfg = prepare_write_dir(write_dir, miz, mode, a.minutes, a.accel, wall, a.inject)
    vault = write_dir / "Config" / "network.vault"
    if a.copy_login:
        src = SAVED_GAMES / "DCS" / "Config" / "network.vault"
        if src.is_file():
            shutil.copy2(src, vault)
            rep.notes.append("copied network.vault from main profile (--copy-login)")
        else:
            rep.notes.append("--copy-login: no network.vault in main profile")
    if not vault.is_file():
        rep.notes.append(
            "no Config/network.vault in write dir: server start will fail with 'login is required' "
            "(see docs/testing/STRATEGY.md, one-time login)"
        )

    args = [str(inst.exe), "-w", a.write_dir_name]
    if mode == "server":
        args += ["--server", "--norender"]
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

    t0 = time.monotonic()
    env = dict(os.environ)
    if "steamapps" in str(inst.exe).lower():
        # Steam edition: without these, DCS asks Steam to relaunch it and our args are lost.
        env.setdefault("SteamAppId", STEAM_APP_ID)
        env.setdefault("SteamGameId", STEAM_APP_ID)
    subprocess.Popen(args, cwd=str(inst.exe.parent), close_fds=True, env=env)
    rep.launched = True
    seen_ours = False
    log_path = write_dir / "Logs" / "dcs.log"
    print(f"[harness] launched {' '.join(args)}; wall timeout {wall}s; log {log_path}", flush=True)
    while True:
        time.sleep(5)
        elapsed = time.monotonic() - t0
        procs = [p for p in list_dcs_processes() if ours(p, a.write_dir_name)]
        if procs:
            seen_ours = True
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
    parse_log(log_path, rep)
    code = verdict(rep)
    out = json.dumps(asdict(rep), indent=2, default=str)
    if a.report:
        a.report.write_text(out, encoding="utf-8")
    print(out)
    return code


if __name__ == "__main__":
    sys.exit(main())
