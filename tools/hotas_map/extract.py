"""Effective HOTAS Warthog bindings per DCS aircraft -> bindings.json for the diagram page.

DCS stores a user's bindings as a diff on top of the device's default profile, and that default
is itself the module's joystick default.lua with the module's per-device diff applied:

    effective = base combos (default.lua + common profile + DefaultAssignments.lua)
              + module diff  Mods/aircraft/MODULE/Input/PROFILE/joystick/DEVICE.diff.lua
              + user diff    Saved Games/DCS/Config/Input/PROFILE/joystick/DEVICE {GUID}.diff.lua

Diffs are keyed by a command hash ("d3002pnilu3002cd19vd1vpnilvu0" for keys, "a2001cdnil" for
axes) and carry the command name. The few base combos that come from default.lua (the POV1
slow-view keys from common_joystick_binding.lua and the DefaultAssignments.lua axes) are matched
to diff entries by name, which is unique enough within one profile.

Usage (WSL or Windows, needs lupa from the dev group):

    uv run python tools/hotas_map/extract.py --out bindings.json
    uv run python tools/hotas_map/extract.py --out bindings.json --html page.html
"""

from __future__ import annotations

import argparse
import json
import re
from dataclasses import dataclass, field
from datetime import UTC, datetime
from pathlib import Path
from typing import Any

DCS_INSTALL = Path("/mnt/e/SteamLibrary/steamapps/common/DCSWorld")
SAVED_INPUT = Path("/mnt/c/Users/mook/Saved Games/DCS/Config/Input")
TEMPLATE = Path(__file__).resolve().with_name("template.html")
ART_DIR = Path(__file__).resolve().with_name("art")

DEVICES = {"stick": "Joystick - HOTAS Warthog", "throttle": "Throttle - HOTAS Warthog"}

# Saved Games profile folder -> (label, module input profile dir relative to Mods/aircraft or None)
PROFILES: dict[str, tuple[str, str | None]] = {
    "AH-64D_BLK_II_PLT": ("AH-64D Apache (pilot)", "AH-64D/Input/AH-64D_PLT"),
    "AH-64D_BLK_II_CPG": ("AH-64D Apache (CPG)", "AH-64D/Input/AH-64D_CPG"),
    "AH-64D_BLK_II_AI_Menu": ("AH-64D George AI menu", "AH-64D/Input/AH-64D_AI_Menu"),
    "F-16C_50": ("F-16C Viper", "F-16C/Input/F-16C"),
    "FA-18C_hornet": ("F/A-18C Hornet", "FA-18C/Input/FA-18C"),
    "UiLayer": ("Global (UI layer)", None),
}

# Base combos that do not come from any diff (see module docstring).
POV_VIEWS = {
    "View Left slow": "JOY_BTN_POV1_L",
    "View Right slow": "JOY_BTN_POV1_R",
    "View Up slow": "JOY_BTN_POV1_U",
    "View Down slow": "JOY_BTN_POV1_D",
    "View Up Right slow": "JOY_BTN_POV1_UR",
    "View Down Right slow": "JOY_BTN_POV1_DR",
    "View Down Left slow": "JOY_BTN_POV1_DL",
    "View Up Left slow": "JOY_BTN_POV1_UL",
}
DEFAULT_ASSIGN = {  # Scripts/Input/DefaultAssignments.lua
    "stick": {"pitch": "JOY_Y", "roll": "JOY_X", "fire": "JOY_BTN1"},
    "throttle": {"thrust": "JOY_RZ", "thrust_left": "JOY_RZ", "thrust_right": "JOY_Z"},
}
ASSIGN_RE = re.compile(
    r"combos\s*=\s*defaultDeviceAssignmentFor\(\s*\"(\w+)\"\s*\)\s*,.*?name\s*=\s*_\('([^']*)'\)"
)


@dataclass
class Combo:
    key: str
    modifiers: list[str] = field(default_factory=list)
    filter: dict[str, Any] | None = None

    @property
    def ident(self) -> tuple[str, tuple[str, ...]]:
        return (self.key, tuple(sorted(self.modifiers)))


@dataclass
class Command:
    name: str
    category: str | None
    axis: bool
    combos: dict[tuple[str, tuple[str, ...]], tuple[Combo, str]] = field(default_factory=dict)


# ---------------------------------------------------------------- lua loading


def _lua() -> Any:
    from lupa import lua51

    return lua51.LuaRuntime(unpack_returned_tuples=True)


def _to_py(obj: Any) -> Any:
    if hasattr(obj, "items") and not isinstance(obj, dict):
        d = {k: _to_py(v) for k, v in obj.items()}
        if d and all(isinstance(k, int) for k in d):
            return [d[k] for k in sorted(d)]
        return d
    return obj


def load_diff(path: Path) -> dict[str, Any]:
    if not path.exists():
        return {}
    rt = _lua()
    src = path.read_text(encoding="utf-8", errors="replace")
    fn = rt.execute("return function(src) return loadstring(src)() end")
    result = _to_py(fn(src))
    return result if isinstance(result, dict) else {}


def find_user_diff(profile: str, device: str) -> Path | None:
    d = SAVED_INPUT / profile / "joystick"
    if not d.is_dir():
        return None
    for p in sorted(d.iterdir()):
        if p.name.startswith(device + " {") and p.name.endswith(".diff.lua"):
            return p
    return None


# ---------------------------------------------------------------- merge


def _combo(raw: dict[str, Any]) -> Combo:
    filt = raw.get("filter")
    return Combo(
        key=str(raw["key"]),
        modifiers=[str(m) for m in raw.get("reformers", []) or []],
        filter=filt if isinstance(filt, dict) else None,
    )


def base_commands(module_dir: Path | None, device_kind: str) -> dict[str, Command]:
    """Base combos keyed by "name:<command name>" (matched to diff entries by name)."""
    out: dict[str, Command] = {}
    if module_dir is None:
        return out
    default = module_dir / "joystick" / "default.lua"
    text = default.read_text(encoding="utf-8", errors="replace") if default.exists() else ""
    if "common_joystick_binding.lua" in text:
        for name, key in POV_VIEWS.items():
            c = Combo(key)
            out["name:" + name] = Command(name, "View", False, {c.ident: (c, "default")})
    for assign, name in ASSIGN_RE.findall(text):
        assigned = DEFAULT_ASSIGN[device_kind].get(assign)
        if assigned:
            c = Combo(assigned)
            out["name:" + name] = Command(name, None, True, {c.ident: (c, "default")})
    return out


def apply_diff(cmds: dict[str, Command], diff: dict[str, Any], source: str) -> None:
    """Mirror Scripts/Input/Data.lua applyDiffToCommands_ (keys and axes separately)."""
    for section in ("keyDiffs", "axisDiffs"):
        sdiff: dict[str, Any] = diff.get(section) or {}
        if not sdiff:
            continue
        # Base entries are keyed by name until a diff tells us their hash.
        for h, entry in sdiff.items():
            name_key = "name:" + str(entry.get("name", h))
            if h not in cmds and name_key in cmds:
                cmds[h] = cmds.pop(name_key)
        # getDiffComboInfos: which command each combo was added to / removed from.
        added_by: dict[tuple[str, tuple[str, ...]], str] = {}
        removed_by: dict[tuple[str, tuple[str, ...]], str] = {}
        mentioned: set[tuple[str, tuple[str, ...]]] = set()
        for h, entry in sdiff.items():
            for raw in entry.get("added") or []:
                added_by[_combo(raw).ident] = h
            for raw in entry.get("removed") or []:
                removed_by[_combo(raw).ident] = h
            for part in ("added", "removed", "changed"):
                mentioned.update(_combo(raw).ident for raw in entry.get(part) or [])
        is_axis = section == "axisDiffs"
        for h, cmd in list(cmds.items()):
            if cmd.axis != is_axis:
                continue  # key commands are only touched by keyDiffs, axes by axisDiffs
            # A default combo that the diff assigned elsewhere marks the command "updated":
            # DCS then keeps its defaults (a visible conflict). Otherwise defaults that the
            # diff mentions anywhere are dropped.
            updated = any(
                (ident in added_by or ident in removed_by)
                and h != added_by.get(ident)
                and h != removed_by.get(ident)
                for ident in cmd.combos
            )
            if not updated:
                for ident in mentioned:
                    cmd.combos.pop(ident, None)
        for h, entry in sdiff.items():
            target = cmds.get(h)
            if target is None:
                target = cmds[h] = Command(str(entry.get("name", h)), None, is_axis)
            for raw in entry.get("removed") or []:
                target.combos.pop(_combo(raw).ident, None)
            for part in ("added", "changed"):
                for raw in entry.get(part) or []:
                    c = _combo(raw)
                    if c.ident not in target.combos:
                        target.combos[c.ident] = (c, source)


def effective(profile: str, device_kind: str) -> dict[str, Command]:
    label_dir = PROFILES.get(profile, (profile, None))[1]
    module_dir = DCS_INSTALL / "Mods" / "aircraft" / label_dir if label_dir else None
    device = DEVICES[device_kind]
    cmds = base_commands(module_dir, device_kind)
    if module_dir is not None:
        apply_diff(cmds, load_diff(module_dir / "joystick" / f"{device}.diff.lua"), "default")
    user = find_user_diff(profile, device)
    if user is not None:
        apply_diff(cmds, load_diff(user), "yours")
    return cmds


def device_json(cmds: dict[str, Command]) -> dict[str, Any]:
    buttons: dict[str, list[dict[str, Any]]] = {}
    axes: dict[str, list[dict[str, Any]]] = {}
    for cmd in cmds.values():
        for combo, source in cmd.combos.values():
            if combo.key.startswith("JOY_BTN"):
                buttons.setdefault(combo.key, []).append(
                    {
                        "name": cmd.name,
                        "category": cmd.category,
                        "modifiers": combo.modifiers,
                        "source": source,
                    }
                )
            else:
                f = combo.filter or {}
                curv = f.get("curvature")
                axes.setdefault(combo.key, []).append(
                    {
                        "name": cmd.name,
                        "source": source,
                        "invert": f.get("invert"),
                        "deadzone": f.get("deadzone"),
                        "curvature": curv[0] if isinstance(curv, list) and curv else None,
                    }
                )
    for lst in (*buttons.values(), *axes.values()):
        lst.sort(key=lambda b: (bool(b.get("modifiers")), b["name"]))
    return {"buttons": dict(sorted(buttons.items())), "axes": dict(sorted(axes.items()))}


def build() -> dict[str, Any]:
    aircraft = []
    profiles = sorted(p.name for p in SAVED_INPUT.iterdir() if p.is_dir())
    for profile in profiles:
        if not any(find_user_diff(profile, d) for d in DEVICES.values()):
            continue
        devices = {kind: device_json(effective(profile, kind)) for kind in DEVICES}
        label = PROFILES.get(profile, (profile, None))[0]
        aircraft.append({"id": profile, "label": label, "devices": devices})
    order = list(PROFILES)
    aircraft.sort(key=lambda a: order.index(a["id"]) if a["id"] in order else 99)
    return {
        "generated": datetime.now(UTC).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "source": f"{DCS_INSTALL} + {SAVED_INPUT}",
        "aircraft": aircraft,
    }


def lua_serialize(obj: Any, depth: int = 0) -> str:
    """Python data -> Lua table text in the layout DCS writes (tabs, sorted ["key"] = ...)."""
    tab = "\t"
    if isinstance(obj, bool):
        return "true" if obj else "false"
    if isinstance(obj, int):
        return str(obj)
    if isinstance(obj, float):
        return str(int(obj)) if obj.is_integer() else repr(obj)
    if isinstance(obj, str):
        return '"' + obj.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n") + '"'
    items: list[tuple[str, Any]]
    if isinstance(obj, list):
        items = [(f"[{i}]", v) for i, v in enumerate(obj, 1)]
    elif isinstance(obj, dict):
        items = [(f"[{lua_serialize(k)}]", obj[k]) for k in sorted(obj)]
    else:
        raise TypeError(f"cannot serialize {type(obj).__name__}")
    inner = "".join(f"{tab * (depth + 1)}{k} = {lua_serialize(v, depth + 1)},\n" for k, v in items)
    return "{\n" + inner + tab * depth + "}"


def conflicts(cmds: dict[str, Command]) -> list[tuple[str, str, Combo, str]]:
    """Default combos that share key+modifiers with one of the user's own bindings.

    Returns (command hash, command name, combo, name of the user's binding it clashes with).
    """
    yours: dict[tuple[str, tuple[str, ...]], str] = {}
    for cmd in cmds.values():
        for ident, (_, source) in cmd.combos.items():
            if source == "yours":
                yours[ident] = cmd.name
    out = []
    for h, cmd in cmds.items():
        for ident, (combo, source) in cmd.combos.items():
            if source == "default" and ident in yours:
                out.append((h, cmd.name, combo, yours[ident]))
    return out


def clear_conflicts(dry_run: bool) -> int:
    """Unbind every default that clashes with a user binding, via "removed" in the user diff."""
    stamp = datetime.now(UTC).strftime("%Y%m%d-%H%M%S")
    total = 0
    for profile in sorted(p.name for p in SAVED_INPUT.iterdir() if p.is_dir()):
        for kind, device in DEVICES.items():
            user = find_user_diff(profile, device)
            if user is None:
                continue
            cmds = effective(profile, kind)
            found = [c for c in conflicts(cmds) if not c[0].startswith("name:")]
            if not found:
                continue
            diff = load_diff(user)
            for h, name, combo, theirs in found:
                section = "axisDiffs" if cmds[h].axis else "keyDiffs"
                entry = diff.setdefault(section, {}).setdefault(h, {"name": name})
                raw: dict[str, Any] = {"key": combo.key}
                if combo.modifiers:
                    raw["reformers"] = list(combo.modifiers)
                entry.setdefault("removed", []).append(raw)
                mod = "+".join([*combo.modifiers, combo.key])
                print(f"{profile:22} {kind:8} {mod:16} unbind '{name}' (keeps '{theirs}')")
                total += 1
            if dry_run:
                continue
            original = user.read_text(encoding="utf-8")
            backup = user.with_name(user.name + f".{stamp}.bak")
            backup.write_text(original, encoding="utf-8")
            lead = "\n" if original.startswith("\n") else ""
            text = lead + "local diff = " + lua_serialize(diff) + "\nreturn diff"
            user.write_text(text, encoding="utf-8", newline="\n")
            if load_diff(user) != diff:
                backup.replace(user)
                raise RuntimeError(f"round-trip mismatch, restored {user}")
            print(f"  wrote {user.name} (backup {backup.name})")
    print(f"{total} default binding(s) {'would be ' if dry_run else ''}cleared")
    return 0


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--out", type=Path, help="write bindings.json here")
    ap.add_argument("--html", type=Path, help="also write the diagram page with data injected")
    ap.add_argument(
        "--art-dir",
        type=Path,
        default=ART_DIR,
        help="folder with stick.svg/throttle.svg (default: the drawn art in tools/hotas_map/art)",
    )
    ap.add_argument(
        "--clear-conflicts",
        action="store_true",
        help="unbind defaults that clash with your bindings (edits Saved Games, makes .bak)",
    )
    ap.add_argument("--dry-run", action="store_true", help="with --clear-conflicts: only list")
    args = ap.parse_args()
    if args.clear_conflicts:
        return clear_conflicts(args.dry_run)
    if args.out is None:
        ap.error("--out is required")
    data = build()
    args.out.write_text(json.dumps(data, indent=1), encoding="utf-8")
    if args.html:
        page = TEMPLATE.read_text(encoding="utf-8")
        blob = json.dumps(data, separators=(",", ":")).replace("</", "<\\/")
        assert page.count("__BINDINGS_JSON__") == 1, "template must contain the token once"
        page = page.replace("__BINDINGS_JSON__", blob)
        for token, art in (("__STICK_SVG__", "stick.svg"), ("__THROTTLE_SVG__", "throttle.svg")):
            path = args.art_dir / art
            svg = path.read_text(encoding="utf-8") if path.exists() else ""
            assert "</script" not in svg.lower(), f"{art} must not contain a script end tag"
            page = page.replace(token, svg)
        args.html.write_text(page, encoding="utf-8")
    for a in data["aircraft"]:
        counts = {k: len(v["buttons"]) for k, v in a["devices"].items()}
        print(f"{a['id']:24} buttons bound: {counts}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
