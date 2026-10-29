"""``dms install`` (copy built .miz files into DCS Saved Games) and ``dms doctor`` (environment
checks). Plain-text output, no colours; the CLI wrappers live in ``main.py``."""

from __future__ import annotations

import dataclasses
import importlib
import os
import re
import shutil
import subprocess
import sys
from collections.abc import Callable, Iterable
from pathlib import Path
from typing import Any, Literal

from .util import SPEC_FILE, CliError, latest_mtime, load_yaml

SAVED_GAMES_ENV = "DMS_DCS_SAVED_GAMES"
DcsChoice = Literal["stable", "openbeta", "auto"]
DCS_CHOICES: tuple[str, ...] = ("stable", "openbeta", "auto")
_VARIANT_DIRS = {"stable": "DCS", "openbeta": "DCS.openbeta"}
_FOLDERID_SAVED_GAMES = "{4C5C32FF-BB9D-43b0-B5B4-2D72E54EAAA4}"


# ---- Saved Games detection ---------------------------------------------------------------------


def _known_folder_saved_games() -> Path | None:
    """Windows FOLDERID_SavedGames via SHGetKnownFolderPath; None off Windows or on failure."""
    if sys.platform != "win32":
        return None
    try:
        import ctypes
        import uuid
        from ctypes import wintypes

        class _GUID(ctypes.Structure):
            _fields_ = [
                ("Data1", wintypes.DWORD),
                ("Data2", wintypes.WORD),
                ("Data3", wintypes.WORD),
                ("Data4", ctypes.c_ubyte * 8),
            ]

        u = uuid.UUID(_FOLDERID_SAVED_GAMES)
        guid = _GUID(u.fields[0], u.fields[1], u.fields[2])
        for i, b in enumerate(u.bytes[8:]):
            guid.Data4[i] = b
        windll: Any = getattr(ctypes, "windll")  # noqa: B009 - absent off Windows
        out = ctypes.c_wchar_p()
        hr = windll.shell32.SHGetKnownFolderPath(ctypes.byref(guid), 0, None, ctypes.byref(out))
        if hr != 0 or not out.value:
            return None
        path = Path(out.value)
        windll.ole32.CoTaskMemFree(out)
        return path
    except Exception:  # pragma: no cover - platform specific
        return None


def saved_games_dir() -> Path:
    """``$DMS_DCS_SAVED_GAMES`` (the Saved Games dir itself), else the Windows known folder,
    else ``~/Saved Games``."""
    env = os.environ.get(SAVED_GAMES_ENV, "").strip()
    if env:
        return Path(env)
    return _known_folder_saved_games() or Path.home() / "Saved Games"


def _log_mtime(dcs_dir: Path) -> float:
    log = dcs_dir / "Logs" / "dcs.log"
    try:
        return log.stat().st_mtime
    except OSError:
        return 0.0


def pick_dcs_dir(saved: Path, choice: str) -> tuple[Path, str, list[str]]:
    """``(<Saved Games>/DCS[.openbeta], variant, warnings)`` for stable | openbeta | auto."""
    if choice not in DCS_CHOICES:
        raise CliError(f"--dcs must be one of {', '.join(DCS_CHOICES)} (got {choice!r})")
    if choice != "auto":
        return saved / _VARIANT_DIRS[choice], choice, []
    found = [(v, saved / d) for v, d in _VARIANT_DIRS.items() if (saved / d).is_dir()]
    if not found:
        return (
            saved / "DCS",
            "stable",
            [f"DCS Saved Games folder not found under {saved}; using {saved / 'DCS'}"],
        )
    if len(found) == 1:
        return found[0][1], found[0][0], []
    # both exist: the one DCS ran most recently (newest Logs/dcs.log); ties -> stable
    v, d = max(found, key=lambda vd: (_log_mtime(vd[1]), vd[0] == "stable"))
    return d, v, []


# ---- install -----------------------------------------------------------------------------------


@dataclasses.dataclass
class InstallPlan:
    campaign: str
    dcs: str
    saved_games: Path
    dcs_dir: Path
    dest: Path
    files: list[tuple[Path, Path]]
    warnings: list[str]

    def to_dict(self, dry_run: bool) -> dict[str, Any]:
        return {
            "campaign": self.campaign,
            "dcs": self.dcs,
            "saved_games": str(self.saved_games),
            "dcs_dir": str(self.dcs_dir),
            "dest": str(self.dest),
            "dry_run": dry_run,
            "files": [{"src": str(s), "dst": str(d)} for s, d in self.files],
            "warnings": self.warnings,
            "open_in_dcs": [self.dcs_path(d) for _, d in self.files],
        }

    def dcs_path(self, dst: Path) -> str:
        return f"Missions\\DMS\\{self.campaign}\\{dst.name}"


def _mission_dir_for(target: Path) -> tuple[Path, Path | None]:
    """``(mission dir, explicit .miz or None)`` for a mission folder, spec, out dir or .miz."""
    t = target.resolve()
    if not t.exists():
        raise CliError(f"not found: {target}")
    if t.is_file() and t.suffix.lower() == ".miz":
        parent = t.parent
        while parent.name in ("out", "test") and parent.parent != parent:
            parent = parent.parent
        return parent, t
    if t.is_file():
        return t.parent, None
    if t.name == "out" and not (t / SPEC_FILE).is_file():
        return t.parent, None
    return t, None


def _spec_fields(mdir: Path) -> dict[str, Any]:
    spec = mdir / SPEC_FILE
    if not spec.is_file():
        return {}
    try:
        data = load_yaml(spec)
    except CliError:
        return {}
    return data if isinstance(data, dict) else {}


def campaign_name(mdir: Path, spec: dict[str, Any] | None = None) -> str:
    """campaigns/<slug>/missions/<id> -> slug; else the spec's ``campaign``; else ``misc``."""
    if mdir.parent.name == "missions" and mdir.parent.parent.name:
        return mdir.parent.parent.name
    camp = (spec if spec is not None else _spec_fields(mdir)).get("campaign")
    return str(camp) if camp else "misc"


def collect_miz(mdir: Path, mission_id: str | None, include_test: bool) -> list[Path]:
    """``<mdir>/out/<id>.miz`` and ``<id>-<variant>.miz`` (``-test.miz`` only if asked)."""
    out = mdir / "out"
    if not out.is_dir():
        return []
    pat = re.compile(rf"^{re.escape(mission_id)}(-[^.]+)?\.miz$" if mission_id else r"^.+\.miz$")
    files = []
    for p in sorted(out.glob("*.miz")):
        if not pat.match(p.name):
            continue
        if p.name.endswith("-test.miz") and not include_test:
            continue
        files.append(p)
    return files


def plan_install(target: Path, dcs: str = "auto", include_test: bool = False) -> InstallPlan:
    mdir, miz = _mission_dir_for(target)
    spec = _spec_fields(mdir)
    if miz is not None:
        files = [miz]
    else:
        mid = spec.get("id")
        files = collect_miz(mdir, str(mid) if mid else None, include_test)
        if not files:
            raise CliError(f"no built .miz in {mdir / 'out'}; run `dms run {target}` first", 1)
    saved = saved_games_dir()
    dcs_dir, variant, warnings = pick_dcs_dir(saved, dcs)
    camp = campaign_name(mdir, spec)
    dest = dcs_dir / "Missions" / "DMS" / camp
    return InstallPlan(
        campaign=camp,
        dcs=variant,
        saved_games=saved,
        dcs_dir=dcs_dir,
        dest=dest,
        files=[(f, dest / f.name) for f in files],
        warnings=warnings,
    )


def execute_install(plan: InstallPlan, dry_run: bool, echo: Callable[[str], None] | None) -> None:
    """Copy (copy2, overwriting) each file; with ``echo`` print the progress lines."""
    say = echo or (lambda _m: None)
    for w in plan.warnings:
        say(f"WARNING: {w}")
    say(f"install: {len(plan.files)} file(s) -> {plan.dest} (DCS {plan.dcs})")
    if not dry_run:
        plan.dest.mkdir(parents=True, exist_ok=True)
    for src, dst in plan.files:
        say(f"  {src} -> {dst}")
        if not dry_run:
            shutil.copy2(src, dst)
    if dry_run:
        say("dry run: nothing written")
    first = plan.files[0][1] if plan.files else None
    if first is not None:
        say(f"in DCS: Mission > Open > {plan.dcs_path(first)}")


# ---- doctor ------------------------------------------------------------------------------------

Status = Literal["OK", "WARN", "FAIL"]


@dataclasses.dataclass
class Check:
    name: str
    status: Status
    detail: str
    fix: str = ""

    def to_dict(self) -> dict[str, str]:
        return dataclasses.asdict(self)


DoctorCheck = Callable[[Path], list[Check]]


def _importable(mod: str) -> str | None:
    """None when ``mod`` imports, else the error text."""
    try:
        importlib.import_module(mod)
    except Exception as exc:
        return f"{type(exc).__name__}: {exc}"
    return None


def check_python(_root: Path) -> list[Check]:
    v = sys.version_info
    ver = f"{v.major}.{v.minor}.{v.micro}"
    rows = [
        Check("python", "OK", ver)
        if v >= (3, 11)
        else Check("python", "FAIL", f"{ver} < 3.11", "install Python 3.11+ (uv python install)")
    ]
    for mod, label in (
        ("dms_core", "dms_core"),
        ("dms_gen", "dms_gen"),
        ("dms_voice", "dms_voice"),
        ("dcs", "pydcs"),
    ):
        err = _importable(mod)
        rows.append(
            Check(label, "OK", "importable")
            if err is None
            else Check(label, "FAIL", err, "uv sync --all-packages")
        )
    return rows


def check_lua(_root: Path) -> list[Check]:
    rows: list[Check] = []
    try:
        from lupa import lua51

        rt = lua51.LuaRuntime(encoding=None)
        ver = rt.eval("_VERSION")
        ver_s = ver.decode() if isinstance(ver, bytes) else str(ver)
        if ver_s == "Lua 5.1":
            rows.append(Check("lupa/lua51", "OK", ver_s))
        else:
            rows.append(
                Check("lupa/lua51", "FAIL", f"runtime is {ver_s}", "uv sync --all-packages")
            )
    except Exception as exc:
        rows.append(
            Check(
                "lupa/lua51",
                "FAIL",
                f"{type(exc).__name__}: {exc}",
                "uv sync --all-packages (lupa with the lua51 module)",
            )
        )
    luac = shutil.which("luac5.1") or shutil.which("luac")
    rows.append(
        Check(
            "luac",
            "OK",
            luac or "not on PATH (not needed: dms check compiles with lupa lua51)",
        )
    )
    return rows


def _bundled_ffmpeg() -> str | None:
    """The imageio-ffmpeg binary dms_voice actually uses, if present."""
    try:
        from dms_voice.fx import ffmpeg_exe

        exe = ffmpeg_exe()
    except Exception:
        return None
    return exe if exe and Path(exe).is_file() else None


def check_ffmpeg(_root: Path) -> list[Check]:
    bundled = _bundled_ffmpeg()
    if bundled:
        return [Check("ffmpeg", "OK", f"{bundled} (imageio-ffmpeg, used by dms_voice)")]
    path = shutil.which("ffmpeg")
    if path:
        return [Check("ffmpeg", "OK", path)]
    return [
        Check(
            "ffmpeg",
            "WARN",
            "not on PATH (needed for real voice radio FX)",
            "install ffmpeg and add it to PATH (e.g. winget install Gyan.FFmpeg)",
        )
    ]


def _dotenv_has_key(path: Path, key: str) -> bool:
    try:
        text = path.read_text(encoding="utf-8", errors="replace")
    except OSError:
        return False
    for line in text.splitlines():
        s = line.strip()
        if s.startswith("export "):
            s = s[7:].lstrip()
        name, sep, value = s.partition("=")
        if sep and name.strip() == key and value.strip().strip("'\"").strip():
            return True
    return False


def _dotenv_candidates(root: Path) -> list[Path]:
    seen: list[Path] = []
    cwd = Path.cwd().resolve()
    for p in [root / ".env", *(d / ".env" for d in [cwd, *cwd.parents])]:
        if p not in seen:
            seen.append(p)
    return seen


def check_elevenlabs(root: Path) -> list[Check]:
    """Presence only: the key value is never printed."""
    key = "ELEVENLABS_API_KEY"
    if os.environ.get(key, "").strip():
        return [Check("elevenlabs key", "OK", "set (environment)")]
    for env in _dotenv_candidates(root):
        if env.is_file() and _dotenv_has_key(env, key):
            return [Check("elevenlabs key", "OK", f"set ({env})")]
    return [
        Check(
            "elevenlabs key",
            "WARN",
            "not set (voice: subtitles only, or `dms voice --offline`)",
            f"add {key}=... to {root / '.env'} or the environment",
        )
    ]


def _registry_dcs_paths() -> list[Path]:
    if sys.platform != "win32":
        return []
    try:
        import winreg
    except ImportError:  # pragma: no cover
        return []
    out: list[Path] = []
    for sub in ("DCS World", "DCS World OpenBeta"):
        try:
            with winreg.OpenKey(winreg.HKEY_CURRENT_USER, f"Software\\Eagle Dynamics\\{sub}") as k:
                val, _t = winreg.QueryValueEx(k, "Path")
        except OSError:
            continue
        if val:
            out.append(Path(str(val)))
    return out


def _common_dcs_paths() -> list[Path]:
    bases = [os.environ.get("PROGRAMFILES"), os.environ.get("PROGRAMFILES(X86)")]
    out: list[Path] = []
    for b in bases:
        if b:
            out += [Path(b) / "Eagle Dynamics" / n for n in ("DCS World", "DCS World OpenBeta")]
            out.append(Path(b) / "Steam" / "steamapps" / "common" / "DCSWorld")
    for drive in "CDEFG":
        out += [Path(f"{drive}:\\") / n for n in ("DCS World", "DCS World OpenBeta", "DCS")]
    return out


def find_dcs_installs(candidates: Iterable[Path] | None = None) -> list[Path]:
    """DCS install dirs (registry first, then common locations) that contain ``bin``."""
    paths = list(candidates) if candidates is not None else _registry_dcs_paths()
    if candidates is None:
        paths += _common_dcs_paths()
    found: list[Path] = []
    for p in paths:
        try:
            ok = (p / "bin").is_dir()
        except OSError:
            ok = False
        if ok and p not in found:
            found.append(p)
    return found


def check_dcs(_root: Path) -> list[Check]:
    installs = find_dcs_installs()
    rows = [
        Check("dcs install", "OK", "; ".join(str(p) for p in installs))
        if installs
        else Check(
            "dcs install",
            "WARN",
            "not found (registry or common folders)",
            "install DCS World (only needed to fly; building works without it)",
        )
    ]
    saved = saved_games_dir()
    present = [d for d in _VARIANT_DIRS.values() if (saved / d).is_dir()]
    if present:
        _dir, variant, _w = pick_dcs_dir(saved, "auto")
        rows.append(
            Check(
                "dcs saved games",
                "OK",
                f"{', '.join(str(saved / d) for d in present)} (install auto -> {variant})",
            )
        )
    else:
        rows.append(
            Check(
                "dcs saved games",
                "WARN",
                f"no DCS or DCS.openbeta under {saved}",
                f"run DCS once, or set {SAVED_GAMES_ENV} to your Saved Games folder",
            )
        )
    return rows


def lua_sources(root: Path) -> list[Path]:
    return [*sorted((root / "lua" / "src").rglob("*.lua")), root / "lua" / "manifest.txt"]


def check_bundle(root: Path) -> list[Check]:
    out = root / "dist" / "dms.lua"
    fix = "uv run dms bundle-lua"
    if not out.is_file():
        return [Check("dist/dms.lua", "WARN", "missing (build rebuilds it automatically)", fix)]
    if out.stat().st_mtime < latest_mtime(lua_sources(root)):
        return [Check("dist/dms.lua", "WARN", "stale (older than lua/src)", fix)]
    return [Check("dist/dms.lua", "OK", "up to date")]


def check_git_lfs(_root: Path) -> list[Check]:
    err = ""
    res: subprocess.CompletedProcess[str] | None = None
    try:
        res = subprocess.run(
            ["git", "lfs", "version"], capture_output=True, text=True, timeout=15, check=False
        )
    except (OSError, subprocess.SubprocessError) as exc:
        err = str(exc)
    if res is not None and res.returncode == 0:
        return [Check("git-lfs", "OK", res.stdout.strip().splitlines()[0] if res.stdout else "ok")]
    detail = err if res is None else (res.stderr.strip() or f"exit {res.returncode}")
    return [Check("git-lfs", "WARN", detail[:120], "install Git LFS, then `git lfs install`")]


def check_uv(_root: Path) -> list[Check]:
    path = shutil.which("uv")
    if path:
        return [Check("uv", "OK", path)]
    return [Check("uv", "WARN", "not on PATH", "install uv: https://docs.astral.sh/uv/")]


DOCTOR_CHECKS: list[DoctorCheck] = [
    check_python,
    check_lua,
    check_ffmpeg,
    check_elevenlabs,
    check_dcs,
    check_bundle,
    check_git_lfs,
    check_uv,
]


def run_doctor(root: Path, checks: Iterable[DoctorCheck] | None = None) -> list[Check]:
    rows: list[Check] = []
    for fn in checks if checks is not None else DOCTOR_CHECKS:
        try:
            rows.extend(fn(root))
        except Exception as exc:  # a broken check is a FAIL row, never a crash
            name = getattr(fn, "__name__", "check").removeprefix("check_")
            rows.append(Check(name, "FAIL", f"check crashed: {type(exc).__name__}: {exc}"))
    return rows


def render_doctor(rows: list[Check]) -> list[str]:
    cols = ("CHECK", "STATUS", "DETAIL")
    w0 = max(len(cols[0]), *(len(r.name) for r in rows)) if rows else len(cols[0])
    w1 = max(len(cols[1]), *(len(r.status) for r in rows)) if rows else len(cols[1])
    out = [f"{cols[0].ljust(w0)}  {cols[1].ljust(w1)}  {cols[2]}"]
    out += [f"{r.name.ljust(w0)}  {r.status.ljust(w1)}  {r.detail}".rstrip() for r in rows]
    fixes = [r for r in rows if r.status != "OK" and r.fix]
    if fixes:
        out.append("fix:")
        out += [f"  {r.name}: {r.fix}" for r in fixes]
    n_fail = sum(r.status == "FAIL" for r in rows)
    n_warn = sum(r.status == "WARN" for r in rows)
    out.append(f"{'FAILED' if n_fail else 'OK'}: {n_fail} fail, {n_warn} warn, {len(rows)} checks")
    return out
