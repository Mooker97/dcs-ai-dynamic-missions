"""Read a saved .miz back and summarise it (no pydcs round-trip).

Uses ``dms_core.luaio`` if importable, otherwise ``zipfile`` + ``dcs.lua.loads`` (pure Python).
"""

# mypy: disallow-untyped-calls=False

from __future__ import annotations

import importlib
import os
import zipfile
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

_GROUP_CATEGORIES = ("plane", "helicopter", "vehicle", "ship", "static")


@dataclass
class GroupInfo:
    name: str
    category: str
    country: str
    group_id: int
    units: list[dict[str, Any]]
    hidden: bool
    late_activation: bool


@dataclass
class MizSummary:
    theater: str
    groups: dict[str, list[GroupInfo]] = field(default_factory=dict)
    player_slots: list[dict[str, Any]] = field(default_factory=list)
    triggers: list[dict[str, Any]] = field(default_factory=list)
    zones: list[dict[str, Any]] = field(default_factory=list)
    resources: dict[str, str] = field(default_factory=dict)
    files: list[str] = field(default_factory=list)
    mission: dict[str, Any] = field(default_factory=dict, repr=False)

    def text(self) -> str:
        lines = [f"theater: {self.theater}"]
        for coal, gs in self.groups.items():
            lines.append(f"{coal}: {len(gs)} groups, {sum(len(g.units) for g in gs)} units")
        lines.append(f"player slots: {len(self.player_slots)}")
        for t in self.triggers:
            lines.append(f"trigger {t['comment']!r}: {[a.get('predicate') for a in t['actions']]}")
        lines.append(f"zones: {[z['name'] for z in self.zones]}")
        lines.append(f"resources: {sorted(self.resources.values())}")
        return "\n".join(lines)


def lua_list(t: Any) -> list[Any]:
    """Lua array (dict with 1..n int keys, or list) -> Python list in index order."""
    if t is None:
        return []
    if isinstance(t, list):
        return t
    if isinstance(t, dict):
        return [t[k] for k in sorted(k for k in t if isinstance(k, int))]
    return []


def _load_lua(text: str, name: str) -> dict[str, Any]:
    """Prefer dms_core.luaio (exact, lupa); fall back to pydcs's pure-Python parser."""
    try:
        luaio = importlib.import_module("dms_core.luaio")
        return luaio.loads(text, name)  # type: ignore[no-any-return]
    except ImportError:
        pass
    from dcs.lua.parse import loads

    return loads(text)[name]  # type: ignore[no-any-return]


def inspect(path: str | os.PathLike[str]) -> MizSummary:
    with zipfile.ZipFile(Path(path)) as z:
        files = z.namelist()
        mission = _load_lua(z.read("mission").decode("utf-8"), "mission")
        resources: dict[str, str] = {}
        if "l10n/DEFAULT/mapResource" in files:
            res = _load_lua(z.read("l10n/DEFAULT/mapResource").decode("utf-8"), "mapResource")
            resources = {str(k): str(v) for k, v in res.items()}

    summary = MizSummary(theater=str(mission.get("theatre", "")), files=files, mission=mission)
    summary.resources = resources
    for coal_name, coal in (mission.get("coalition") or {}).items():
        gs: list[GroupInfo] = []
        for country in lua_list(coal.get("country")):
            for cat in _GROUP_CATEGORIES:
                for g in lua_list((country.get(cat) or {}).get("group")):
                    units = lua_list(g.get("units"))
                    gs.append(
                        GroupInfo(
                            name=str(g.get("name")),
                            category=cat,
                            country=str(country.get("name")),
                            group_id=int(g.get("groupId", 0)),
                            units=units,
                            hidden=bool(g.get("hidden", False)),
                            late_activation=bool(g.get("lateActivation", False)),
                        )
                    )
                    for u in units:
                        if u.get("skill") in ("Client", "Player"):
                            summary.player_slots.append(
                                {
                                    "group": g.get("name"),
                                    "unit": u.get("name"),
                                    "type": u.get("type"),
                                    "skill": u.get("skill"),
                                    "coalition": coal_name,
                                }
                            )
        summary.groups[str(coal_name)] = gs
    for rule in lua_list(mission.get("trigrules")):
        summary.triggers.append(
            {
                "comment": rule.get("comment", ""),
                "predicate": rule.get("predicate"),
                "actions": lua_list(rule.get("actions")),
                "conditions": lua_list(rule.get("rules")),
            }
        )
    for zone in lua_list((mission.get("triggers") or {}).get("zones")):
        summary.zones.append(zone)
    return summary
