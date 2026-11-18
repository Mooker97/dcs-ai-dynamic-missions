# /// script
# requires-python = ">=3.11"
# dependencies = ["pygame-ce>=2.5"]
# ///
"""Pedal rudder bridge: two racing pedals -> one DCS rudder axis, with no virtual device.

Runs on Windows Python (USB devices are not visible from WSL). It reads the pedals with SDL
(pygame-ce, background input allowed, so DCS can keep focus) and mixes them as right minus left.
It sends the result (-1..1) over localhost UDP to PedalRudder.lua, which feeds DCS via
LoSetCommand(2003). Nothing is installed in Windows, so other games (Forza) never see a device.

Run it with ``uv run --script`` so uv builds an isolated env and never touches the repo's .venv:

    uv run --script tools/pedal_rudder/pedal_rudder.py install     # Lua + Export.lua line
    uv run --script tools/pedal_rudder/pedal_rudder.py calibrate   # pick + range the pedals
    uv run --script tools/pedal_rudder/pedal_rudder.py monitor     # live axis readout
    uv run --script tools/pedal_rudder/pedal_rudder.py             # run the bridge (leave open)
    uv run --script tools/pedal_rudder/pedal_rudder.py uninstall

Or double-click tools/pedal_rudder/pedal-rudder.cmd (runs the bridge).
"""

from __future__ import annotations

import argparse
import json
import os
import shutil
import socket
import sys
import time
from dataclasses import asdict, dataclass
from pathlib import Path
from typing import Any

PORT = 47801
EXPORT_TAG = "-- DMS PedalRudder"
EXPORT_LINE = r"pcall(dofile, lfs.writedir() .. [[Scripts\DMS\PedalRudder.lua]]) " + EXPORT_TAG
LUA_SOURCE = Path(__file__).resolve().with_name("PedalRudder.lua")
LUA_INSTALL_REL = Path("Scripts") / "DMS" / "PedalRudder.lua"
EXPORT_BACKUP_NAME = "Export.lua.dms-backup"
CONFIG_PATH = Path.home() / ".dms" / "pedal-rudder.json"
MIN_TRAVEL = 0.3  # calibration: an axis must move at least this far (of -1..1) to count
DISPLAY_HZ = 20
ACK_TIMEOUT_SEC = 1.5


# ---------------------------------------------------------------- config


@dataclass
class PedalAxis:
    """One pedal: which device and axis, and the raw axis value at rest and fully pressed."""

    device: str
    axis: int
    rest: float
    full: float


@dataclass
class Config:
    """Saved to ~/.dms/pedal-rudder.json by ``calibrate``; hand-editable."""

    left: PedalAxis | None = None
    right: PedalAxis | None = None
    deadzone: float = 0.03  # fraction of pedal travel ignored at the rest end
    curve: float = 1.0  # >1 softens the centre, 1 is linear
    invert: bool = False  # swap rudder direction
    port: int = PORT
    hz: int = 100

    def to_json(self) -> str:
        return json.dumps(asdict(self), indent=2) + "\n"

    @classmethod
    def from_dict(cls, data: dict[str, Any]) -> Config:
        known = set(cls.__dataclass_fields__)
        unknown = set(data) - known
        if unknown:
            raise ValueError(f"unknown config keys: {sorted(unknown)}")
        kwargs = dict(data)
        for side in ("left", "right"):
            if kwargs.get(side) is not None:
                kwargs[side] = PedalAxis(**kwargs[side])
        cfg = cls(**kwargs)
        if not 0 <= cfg.deadzone < 0.5:
            raise ValueError("deadzone must be in [0, 0.5)")
        if cfg.curve <= 0:
            raise ValueError("curve must be > 0")
        if not 10 <= cfg.hz <= 1000:
            raise ValueError("hz must be in [10, 1000]")
        return cfg


def load_config(path: Path = CONFIG_PATH) -> Config:
    if not path.exists():
        return Config()
    return Config.from_dict(json.loads(path.read_text(encoding="utf-8")))


def save_config(cfg: Config, path: Path = CONFIG_PATH) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(cfg.to_json(), encoding="utf-8")


# ---------------------------------------------------------------- mixing (pure)


def clamp(v: float, lo: float, hi: float) -> float:
    return lo if v < lo else hi if v > hi else v


def normalize(raw: float, pedal: PedalAxis, deadzone: float) -> float:
    """Raw axis value -> pedal travel 0..1 (0 at rest), with a deadzone at the rest end."""
    span = pedal.full - pedal.rest
    if abs(span) < 1e-6:
        return 0.0
    t = clamp((raw - pedal.rest) / span, 0.0, 1.0)
    if t <= deadzone:
        return 0.0
    return (t - deadzone) / (1.0 - deadzone)


def mix(left: float, right: float, curve: float = 1.0, invert: bool = False) -> float:
    """Two pedal travels (0..1) -> rudder -1..1. Right pedal is positive (right rudder)."""
    r = clamp(right - left, -1.0, 1.0)
    shaped = float(abs(r) ** curve)
    r = shaped if r >= 0 else -shaped
    return -r if invert else r


def pick_moved_axis(
    rest: dict[tuple[str, int], float],
    pressed: dict[tuple[str, int], float],
    exclude: set[tuple[str, int]] | None = None,
) -> tuple[tuple[str, int], float] | None:
    """The axis that moved most between two snapshots, if it moved at least MIN_TRAVEL."""
    best: tuple[tuple[str, int], float] | None = None
    for key, before in rest.items():
        if (exclude and key in exclude) or key not in pressed:
            continue
        delta = abs(pressed[key] - before)
        if delta >= MIN_TRAVEL and (best is None or delta > best[1]):
            best = (key, delta)
    return best


# ---------------------------------------------------------------- display (pure)


def bar(fraction: float, width: int = 20) -> str:
    """Unsigned bar for 0..1."""
    n = round(clamp(fraction, 0.0, 1.0) * width)
    return "[" + "#" * n + "." * (width - n) + "]"


def signed_bar(value: float, half: int = 15) -> str:
    """Centred bar for -1..1: fills left or right of the middle mark."""
    n = round(clamp(abs(value), 0.0, 1.0) * half)
    if value < 0:
        left = "-" * (half - n) + "=" * n
        right = "-" * half
    else:
        left = "-" * half
        right = "=" * n + "-" * (half - n)
    return "[" + left + "|" + right + "]"


def status_line(left: float, right: float, rudder: float, linked: bool, hz: float) -> str:
    link = "DCS linked " if linked else "DCS waiting"
    return (
        f"{link}  L {bar(left, 10)} {left * 100:3.0f}%  "
        f"RUDDER {signed_bar(rudder)} {rudder:+.2f}  "
        f"R {bar(right, 10)} {right * 100:3.0f}%  {hz:4.0f} Hz"
    )


# ---------------------------------------------------------------- Export.lua install (pure)


def add_export_line(text: str) -> str:
    if EXPORT_TAG in text:
        return text
    if text and not text.endswith("\n"):
        text += "\n"
    return text + EXPORT_LINE + "\n"


def remove_export_line(text: str) -> str:
    return "".join(ln for ln in text.splitlines(keepends=True) if EXPORT_TAG not in ln)


def default_dcs_dirs() -> list[Path]:
    saved = Path.home() / "Saved Games"
    return [d for d in (saved / "DCS", saved / "DCS.openbeta") if d.is_dir()]


def install(dcs_dir: Path) -> None:
    scripts = dcs_dir / "Scripts"
    target = dcs_dir / LUA_INSTALL_REL
    target.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(LUA_SOURCE, target)
    export = scripts / "Export.lua"
    old = export.read_text(encoding="utf-8") if export.exists() else ""
    backup = scripts / EXPORT_BACKUP_NAME
    if export.exists() and not backup.exists():
        shutil.copyfile(export, backup)
    new = add_export_line(old)
    if new != old:
        export.write_text(new, encoding="utf-8")
    print(f"installed {target}")
    print(f"Export.lua: {'line added' if new != old else 'line already present'} ({export})")


def uninstall(dcs_dir: Path) -> None:
    export = dcs_dir / "Scripts" / "Export.lua"
    if export.exists():
        old = export.read_text(encoding="utf-8")
        new = remove_export_line(old)
        if new != old:
            export.write_text(new, encoding="utf-8")
            print(f"Export.lua: line removed ({export})")
    target = dcs_dir / LUA_INSTALL_REL
    if target.exists():
        target.unlink()
        print(f"removed {target}")
    if target.parent.is_dir() and not any(target.parent.iterdir()):
        target.parent.rmdir()


# ---------------------------------------------------------------- input (pygame / SDL)


class Pedals:
    """All attached game controllers via SDL, re-scanned on hot-plug."""

    def __init__(self) -> None:
        os.environ.setdefault("SDL_JOYSTICK_ALLOW_BACKGROUND_EVENTS", "1")
        os.environ.setdefault("SDL_VIDEODRIVER", "dummy")
        os.environ.setdefault("PYGAME_HIDE_SUPPORT_PROMPT", "1")
        import pygame  # type: ignore[import-not-found,unused-ignore]

        self.pg: Any = pygame
        pygame.display.init()
        pygame.joystick.init()
        self.joys: list[Any] = []
        self.rescan()

    def rescan(self) -> None:
        pg = self.pg
        self.joys = [pg.joystick.Joystick(i) for i in range(pg.joystick.get_count())]

    def pump(self) -> None:
        pg = self.pg
        changed = False
        for ev in pg.event.get():
            if ev.type in (pg.JOYDEVICEADDED, pg.JOYDEVICEREMOVED):
                changed = True
        if changed:
            self.rescan()

    def devices(self) -> list[tuple[str, int]]:
        return [(j.get_name(), j.get_numaxes()) for j in self.joys]

    def snapshot(self) -> dict[tuple[str, int], float]:
        out: dict[tuple[str, int], float] = {}
        for j in self.joys:
            name = j.get_name()
            for a in range(j.get_numaxes()):
                out.setdefault((name, a), float(j.get_axis(a)))
        return out

    def settle(self, seconds: float = 0.25) -> dict[tuple[str, int], float]:
        end = time.perf_counter() + seconds
        while time.perf_counter() < end:
            self.pump()
            time.sleep(0.01)
        return self.snapshot()

    def read(self, pedal: PedalAxis) -> float | None:
        for j in self.joys:
            if j.get_name() == pedal.device and pedal.axis < j.get_numaxes():
                try:
                    return float(j.get_axis(pedal.axis))
                except self.pg.error:
                    return None
        return None


def enable_ansi() -> None:
    if os.name == "nt":
        os.system("")  # switches the Windows console into VT mode


# ---------------------------------------------------------------- commands


def cmd_calibrate(args: argparse.Namespace) -> int:
    pedals = Pedals()
    pedals.settle(0.5)
    devs = pedals.devices()
    if not devs:
        print("No game controllers found. Is the MOZA base switched on and plugged in?")
        return 1
    print("Controllers:")
    for name, n in devs:
        print(f"  {name} ({n} axes)")
    cfg = load_config(args.config)
    input("\n1/3  Take your feet off all pedals, then press Enter.")
    rest = pedals.settle()

    def capture(label: str, exclude: set[tuple[str, int]]) -> PedalAxis:
        while True:
            input(f"{label} all the way down and hold it, then press Enter.")
            pressed = pedals.settle()
            hit = pick_moved_axis(rest, pressed, exclude)
            if hit is None:
                print(f"  No axis moved more than {MIN_TRAVEL}. Try again.")
                continue
            (dev, axis), _ = hit
            print(f"  -> {dev}, axis {axis}: rest {rest[(dev, axis)]:+.3f}, ", end="")
            print(f"full {pressed[(dev, axis)]:+.3f}")
            return PedalAxis(dev, axis, rest[(dev, axis)], pressed[(dev, axis)])

    cfg.left = capture("2/3  Press the LEFT rudder pedal (clutch)", set())
    input("     Release it, then press Enter.")
    cfg.right = capture(
        "3/3  Press the RIGHT rudder pedal (throttle)", {(cfg.left.device, cfg.left.axis)}
    )
    save_config(cfg, args.config)
    print(f"\nSaved {args.config}. Check it with: monitor")
    return 0


def cmd_monitor(args: argparse.Namespace) -> int:
    enable_ansi()
    pedals = Pedals()
    cfg = load_config(args.config)
    print("Live axes (Ctrl+C to stop). Press a pedal to see which axis moves.\n")
    drawn = 0
    try:
        while True:
            pedals.pump()
            lines: list[str] = []
            if not pedals.joys:
                lines.append("No game controllers found. Waiting for the MOZA base...")
            for j in pedals.joys:
                lines.append(f"{j.get_name()}")
                for a in range(j.get_numaxes()):
                    v = float(j.get_axis(a))
                    tag = ""
                    for side, p in (("LEFT", cfg.left), ("RIGHT", cfg.right)):
                        if p and p.device == j.get_name() and p.axis == a:
                            tag = f"  <- {side} rudder"
                    lines.append(f"  axis {a:2d} {bar((v + 1) / 2, 30)} {v:+.3f}{tag}")
            if cfg.left and cfg.right:
                rl, rr = pedals.read(cfg.left), pedals.read(cfg.right)
                if rl is not None and rr is not None:
                    lv = normalize(rl, cfg.left, cfg.deadzone)
                    rv = normalize(rr, cfg.right, cfg.deadzone)
                    out = mix(lv, rv, cfg.curve, cfg.invert)
                    lines.append("")
                    lines.append(f"RUDDER {signed_bar(out, 20)} {out:+.3f}")
            else:
                lines.append("")
                lines.append("Not calibrated yet: run calibrate to pick the pedals.")
            if drawn:
                sys.stdout.write(f"\x1b[{drawn}F")
            sys.stdout.write("".join(ln + "\x1b[K\n" for ln in lines))
            sys.stdout.flush()
            drawn = len(lines)
            time.sleep(1 / DISPLAY_HZ)
    except KeyboardInterrupt:
        return 0


def cmd_run(args: argparse.Namespace) -> int:
    cfg = load_config(args.config)
    if cfg.left is None or cfg.right is None:
        print(f"Not calibrated ({args.config} missing). Run: calibrate")
        return 1
    pedals = Pedals()
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.setblocking(False)
    addr = ("127.0.0.1", cfg.port)
    period = 1.0 / cfg.hz
    last_ack = -1e9
    last_draw = 0.0
    sent = 0
    rate = 0.0
    rate_t0 = time.perf_counter()
    print(f"Pedal rudder -> DCS udp {addr[0]}:{addr[1]} at {cfg.hz} Hz. Ctrl+C to stop.")
    print(f"LEFT  = {cfg.left.device} axis {cfg.left.axis}")
    print(f"RIGHT = {cfg.right.device} axis {cfg.right.axis}\n")
    next_tick = time.perf_counter()
    try:
        while True:
            now = time.perf_counter()
            pedals.pump()
            rl, rr = pedals.read(cfg.left), pedals.read(cfg.right)
            if rl is None or rr is None:
                # Stop sending: DCS releases the rudder after its stale timeout.
                sys.stdout.write("\rPedals not found, waiting for the MOZA base...\x1b[K")
                sys.stdout.flush()
                time.sleep(0.5)
                next_tick = time.perf_counter()
                continue
            lv = normalize(rl, cfg.left, cfg.deadzone)
            rv = normalize(rr, cfg.right, cfg.deadzone)
            out = mix(lv, rv, cfg.curve, cfg.invert)
            sock.sendto(f"{out:.4f}".encode("ascii"), addr)
            sent += 1
            while True:
                try:
                    data, _ = sock.recvfrom(64)
                except (BlockingIOError, ConnectionResetError):
                    break  # nothing pending, or nothing listening yet (Windows ICMP reset)
                if data == b"DMS-ACK":
                    last_ack = now
            if now - rate_t0 >= 1.0:
                rate = sent / (now - rate_t0)
                sent = 0
                rate_t0 = now
            if now - last_draw >= 1 / DISPLAY_HZ:
                linked = now - last_ack < ACK_TIMEOUT_SEC
                sys.stdout.write("\r" + status_line(lv, rv, out, linked, rate) + "\x1b[K")
                sys.stdout.flush()
                last_draw = now
            next_tick += period
            delay = next_tick - time.perf_counter()
            if delay > 0:
                time.sleep(delay)
            else:
                next_tick = time.perf_counter()
    except KeyboardInterrupt:
        print("\nStopped. DCS releases the rudder within half a second.")
        return 0


def _dcs_dirs(args: argparse.Namespace) -> list[Path]:
    dirs = [args.dcs_dir] if args.dcs_dir else default_dcs_dirs()
    if not dirs:
        print("No Saved Games\\DCS folder found. Pass --dcs-dir.")
    return dirs


def cmd_install(args: argparse.Namespace) -> int:
    dirs = _dcs_dirs(args)
    for d in dirs:
        install(d)
    return 0 if dirs else 1


def cmd_uninstall(args: argparse.Namespace) -> int:
    dirs = _dcs_dirs(args)
    for d in dirs:
        uninstall(d)
    return 0 if dirs else 1


def main(argv: list[str] | None = None) -> int:
    p = argparse.ArgumentParser(prog="pedal_rudder", description=__doc__.split("\n\n")[0])
    p.add_argument("--config", type=Path, default=CONFIG_PATH, help="calibration file")
    sub = p.add_subparsers(dest="cmd")
    sub.add_parser("run", help="run the bridge (default)")
    sub.add_parser("monitor", help="live readout of every axis and the mixed rudder")
    sub.add_parser("calibrate", help="pick the left/right pedals and their range")
    for name in ("install", "uninstall"):
        sp = sub.add_parser(name, help=f"{name} PedalRudder.lua and the Export.lua line")
        sp.add_argument("--dcs-dir", type=Path, help="Saved Games DCS folder (default: found)")
    args = p.parse_args(argv)
    handlers = {
        None: cmd_run,
        "run": cmd_run,
        "monitor": cmd_monitor,
        "calibrate": cmd_calibrate,
        "install": cmd_install,
        "uninstall": cmd_uninstall,
    }
    return handlers[args.cmd](args)


if __name__ == "__main__":
    sys.exit(main())
