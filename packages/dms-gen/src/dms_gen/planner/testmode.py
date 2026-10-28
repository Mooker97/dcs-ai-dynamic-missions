"""Test build: turn a normal BuildPlan into a headless-DCS test variant.

The player flight is replaced by an AI "proxy" flight that flies through the zones of the
guaranteed ``zone.entered`` beats and lands back at its start airbase. The runtime is told to
treat that AI group as the player (``DMS_CONFIG.test.playerProxy``) through an extra script,
``dms_test.lua``, embedded between ``dms_config.lua`` and ``dms.lua``. Encounter chances are
forced to 100 and long time triggers are shortened so one run covers as much as possible.

The normal plan is never modified (everything works on a deep copy).
"""

from __future__ import annotations

import math
import os
import re
from dataclasses import dataclass
from pathlib import Path
from typing import Any

from dms_core.schemas import BeatSheet, BuildPlan, MissionSpec
from dms_core.schemas.beats import Beat
from dms_core.schemas.plan import PlanGroup, PlanResource, PlanUnit, PlanWaypoint
from dms_core.schemas.runtime import CircleZone, PolygonZone, TestSettings, from_lua

from .variants import pick_test_proxy, variant_plan

TEST_SCRIPT = "dms_test.lua"
TEST_SCRIPT_PATH = f"l10n/DEFAULT/{TEST_SCRIPT}"
MAX_TIME_TRIGGER_SEC = 240.0
CORNER_INSET = 0.15
MARGIN_MIN = 10.0  # approach, landing and slack
# Cold start + taxi before takeoff; measured 8.3 min for the AH-64 proxy in DCS 2.9.30 (2026-10-28).
GROUND_MIN = 10.0

_IDENT = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*$")
_LUA_KEYWORDS = {
    "and", "break", "do", "else", "elseif", "end", "false", "for", "function", "if", "in",
    "local", "nil", "not", "or", "repeat", "return", "then", "true", "until", "while",
}  # fmt: skip


@dataclass
class TestBuild:
    """Result of :func:`make_test_plan`."""

    __test__ = False

    plan: BuildPlan
    lua: str
    proxy: str
    minutes: float
    route_km: float


# ---- Lua serializer ------------------------------------------------------------------------


def _lua_str(s: str) -> str:
    out = ['"']
    for ch in s:
        if ch == "\\":
            out.append("\\\\")
        elif ch == '"':
            out.append('\\"')
        elif ch == "\n":
            out.append("\\n")
        elif ch == "\r":
            out.append("\\r")
        elif ord(ch) < 32 or ord(ch) == 127:
            out.append(f"\\{ord(ch):03d}")
        else:
            out.append(ch)
    out.append('"')
    return "".join(out)


def to_lua(v: Any) -> str:
    """Deterministic Python -> Lua literal (dict keys in insertion order)."""
    if v is None:
        return "nil"
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, int):
        return str(v)
    if isinstance(v, float):
        if v.is_integer() and abs(v) < 1e15:
            return str(int(v))
        return repr(v)
    if isinstance(v, str):
        return _lua_str(v)
    if isinstance(v, list | tuple):
        return "{ " + ", ".join(to_lua(x) for x in v) + " }" if v else "{}"
    if isinstance(v, dict):
        if not v:
            return "{}"
        parts = []
        for k, x in v.items():
            key = str(k)
            ks = key if _IDENT.match(key) and key not in _LUA_KEYWORDS else f"[{_lua_str(key)}]"
            parts.append(f"{ks} = {to_lua(x)}")
        return "{ " + ", ".join(parts) + " }"
    raise TypeError(f"cannot serialise {type(v).__name__} to Lua")


# ---- geometry ------------------------------------------------------------------------------

XY = tuple[float, float]


def _dist(a: XY, b: XY) -> float:
    return math.hypot(a[0] - b[0], a[1] - b[1])


def _contains(zone: CircleZone | PolygonZone, p: XY) -> bool:
    if isinstance(zone, CircleZone):
        return _dist((zone.x, zone.y), p) <= zone.radius
    pts = [(q.x, q.y) for q in zone.points]
    inside = False
    j = len(pts) - 1
    for i in range(len(pts)):
        xi, yi = pts[i]
        xj, yj = pts[j]
        if (yi > p[1]) != (yj > p[1]) and p[0] < (xj - xi) * (p[1] - yi) / ((yj - yi) or 1e-9) + xi:
            inside = not inside
        j = i
    return inside


def _zone_points(zone: CircleZone | PolygonZone, prev: XY) -> list[XY]:
    if isinstance(zone, CircleZone):
        return [(zone.x, zone.y)]
    pts = [(q.x, q.y) for q in zone.points]
    cx = sum(p[0] for p in pts) / len(pts)
    cy = sum(p[1] for p in pts) / len(pts)
    inset = [(x + (cx - x) * CORNER_INSET, y + (cy - y) * CORNER_INSET) for x, y in pts]
    start = min(range(len(inset)), key=lambda i: _dist(inset[i], prev))
    ordered = inset[start:] + inset[:start]
    return [*ordered, ordered[0]]


# ---- beats ---------------------------------------------------------------------------------


def _beat_list(beats: list[Beat] | BeatSheet | None, plan: BuildPlan) -> list[Beat]:
    if isinstance(beats, BeatSheet):
        return list(beats.beats)
    if beats:
        return list(beats)
    return list(plan.runtime.beats) if plan.runtime is not None else []


def _zone_of(b: Beat) -> str | None:
    w = b.when
    event = getattr(w, "event", None)
    zone = getattr(w, "zone", None)
    if zone and (event in (None, "zone.entered")):
        return str(zone)
    return None


def _has_speech(b: Beat) -> bool:
    return bool(b.lines or b.text or b.speaker)


def _end_result(beats: list[Beat]) -> str | None:
    for b in beats:
        if b.guaranteed and b.effects is not None and b.effects.end_mission:
            return str(b.effects.end_mission)
    return None


# ---- main ----------------------------------------------------------------------------------


def make_test_plan(
    plan: BuildPlan,
    spec: MissionSpec,
    beats: list[Beat] | BeatSheet | None,
    *,
    minutes: float | None = None,
    proxy_speed_kmh: float = 220,
    proxy_alt_m: float = 120,
    variant: str | None = None,
) -> TestBuild:
    """Return a test variant of ``plan`` (deep copy) with an AI player proxy + dms_test.lua.

    The proxy replaces one client group: from ``variant`` when given, preferring a ramp/runway
    start (so on-deck and landing beats are reachable). All other client groups are dropped.
    """
    tp = variant_plan(plan, variant) if variant else plan.model_copy(deep=True)
    if tp.runtime is None:
        raise ValueError("plan has no runtime config")
    orig = pick_test_proxy(tp, variant)
    beat_list = _beat_list(beats, tp)
    zones = tp.runtime.zones

    first = orig.route[0] if orig.route else None
    u0 = orig.units[0]
    start_xy: XY = (first.x, first.y) if first else (u0.x, u0.y)
    airbase = first.airbase if first is not None else None
    at_airbase = bool(airbase) and first is not None and first.action != "Turning Point"

    # turning points through guaranteed zone beats
    zone_ids: list[str] = []
    for b in beat_list:
        if not b.guaranteed:
            continue
        z = _zone_of(b)
        if z is None or z not in zones:
            continue
        if zone_ids and zone_ids[-1] == z:
            continue
        if _contains(zones[z], start_xy):
            continue
        zone_ids.append(z)
    legs: list[XY] = []
    prev = start_xy
    for z in zone_ids:
        for p in _zone_points(zones[z], prev):
            legs.append(p)
            prev = p

    route: list[PlanWaypoint] = []
    if at_airbase:
        route.append(
            PlanWaypoint(
                x=round(start_xy[0], 1),
                y=round(start_xy[1], 1),
                action="From Parking Area Hot",
                airbase=airbase,
            )
        )
    else:
        route.append(
            PlanWaypoint(
                x=round(start_xy[0], 1),
                y=round(start_xy[1], 1),
                alt_m=proxy_alt_m,
                alt_type="RADIO",
                speed_kmh=proxy_speed_kmh,
            )
        )
    for x, y in legs:
        route.append(
            PlanWaypoint(
                x=round(x, 1),
                y=round(y, 1),
                alt_m=proxy_alt_m,
                alt_type="RADIO",
                speed_kmh=proxy_speed_kmh,
            )
        )
    if airbase:
        route.append(
            PlanWaypoint(
                x=round(start_xy[0], 1),
                y=round(start_xy[1], 1),
                action="Landing",
                airbase=airbase,
                speed_kmh=proxy_speed_kmh,
            )
        )
    path = [start_xy, *legs, start_xy]
    route_m = sum(_dist(path[i], path[i + 1]) for i in range(len(path) - 1))
    route_km = round(route_m / 1000, 1)

    proxy_name = f"Proxy {orig.name}"
    proxy = PlanGroup(
        name=proxy_name,
        category=orig.category,
        coalition=orig.coalition,
        country=orig.country,
        task=str(spec.mission_type or orig.task or "CAS"),
        units=[
            PlanUnit(
                name=f"{proxy_name}-1",
                type=u0.type,
                x=u0.x,
                y=u0.y,
                alt_m=None if at_airbase else proxy_alt_m,
                heading_deg=u0.heading_deg,
                skill="High",
                payload=u0.payload,
                livery=u0.livery,
            )
        ],
        route=route,
        frequency_mhz=orig.frequency_mhz,
        modulation=orig.modulation,
        client=False,
        source=None,
    )
    tp.groups = [proxy if g is orig else g for g in tp.groups if not g.client or g is orig]

    # runtime tweaks
    rt = tp.runtime
    rt.debug = True
    for e in rt.encounters:
        e.chance = 100
        a = e.trigger.after_sec
        if e.trigger.type == "time" and a is not None:
            if isinstance(a, int | float):
                e.trigger.after_sec = min(float(a), MAX_TIME_TRIGGER_SEC)
            else:
                lo, hi = a
                e.trigger.after_sec = (
                    min(float(lo), MAX_TIME_TRIGGER_SEC),
                    min(float(hi), MAX_TIME_TRIGGER_SEC),
                )

    # script resource after dms_config.lua
    res = [r for r in tp.resources if Path(r.path).name != TEST_SCRIPT]
    idx = next((i for i, r in enumerate(res) if Path(r.path).name == "dms_config.lua"), None)
    test_res = PlanResource(path=TEST_SCRIPT_PATH, source=TEST_SCRIPT, kind="script")
    if idx is None:
        idx = next((i - 1 for i, r in enumerate(res) if Path(r.path).name == "dms.lua"), -1)
    res.insert(idx + 1, test_res)
    tp.resources = res

    mins = (
        float(minutes)
        if minutes is not None
        else float(math.ceil(route_m / (proxy_speed_kmh / 3.6) / 60 + GROUND_MIN + MARGIN_MIN))
    )
    # ambient_cycle needs a site the proxy starts near and later leaves (beyond despawn radius)
    ambient = (
        rt.ambient is not None
        and rt.ambient.enabled
        and any(
            s.point is None
            or max(_dist((s.point.x, s.point.y), p) for p in path) > s.despawn_radius_m
            for s in rt.ambient.sites
        )
    )
    lua = build_test_lua(
        proxy_name, mins, beat_list, [e.id for e in rt.encounters], ambient=ambient
    )
    return TestBuild(plan=tp, lua=lua, proxy=proxy_name, minutes=mins, route_km=route_km)


def default_checks(
    minutes: float, beats: list[Beat], encounter_ids: list[str], *, ambient: bool = False
) -> list[dict[str, Any]]:
    """The default in-mission check list (see lua/src/dms/test.lua for the kinds).

    ``ambient``: the runtime has ``DMS_CONFIG.ambient`` enabled with at least one site, so an
    ``ambient_cycle`` check (a site activates, then deactivates once the proxy leaves) is added.
    """
    d = int(minutes * 60 - 30)
    spine = [b for b in beats if b.guaranteed]
    checks: list[dict[str, Any]] = [
        {"kind": "booted", "name": "runtime_booted"},
        {"kind": "spawns", "name": "spawns_on_land", "min": 1, "deadlineSec": d},
        {
            "kind": "beats_in_order",
            "name": "spine_in_order",
            "beats": [b.id for b in spine],
            "deadlineSec": d,
        },
        {
            "kind": "comms",
            "name": "comms_queued",
            "min": sum(1 for b in spine if _has_speech(b)),
            "deadlineSec": d,
        },
    ]
    for eid in encounter_ids:
        checks.append(
            {"kind": "encounter", "name": f"encounter_{eid}", "id": eid, "deadlineSec": d}
        )
    if ambient:
        checks.append({"kind": "ambient_cycle", "name": "ambient_cycle", "deadlineSec": d})
    checks.append({"kind": "convoy_halt", "name": "convoy_halt_on_hit"})
    outcome: dict[str, Any] = {"kind": "outcome", "name": "outcome_end"}
    result = _end_result(beats)
    if result:
        outcome["result"] = result
    outcome["deadlineSec"] = d
    checks.append(outcome)
    return checks


def build_test_lua(
    proxy: str,
    minutes: float,
    beats: list[Beat],
    encounter_ids: list[str],
    *,
    ambient: bool = False,
) -> str:
    cfg = {
        "enabled": True,
        "playerProxy": proxy,
        "minutes": minutes,
        "checks": default_checks(minutes, beats, encounter_ids, ambient=ambient),
    }
    TestSettings.model_validate(from_lua(TestSettings, cfg))  # DMS_CONFIG.test contract
    return (
        "-- DMS test-mode config (generated by dms build --test). Not for normal play.\n"
        "DMS_CONFIG = DMS_CONFIG or {}\n"
        "DMS_CONFIG.debug = true\n"
        f"DMS_CONFIG.test = {to_lua(cfg)}\n"
    )


def write_test_lua(build: TestBuild, out_dir: str | os.PathLike[str]) -> Path:
    """Write ``dms_test.lua`` to ``out_dir`` and point the plan's resource at it (absolute)."""
    d = Path(out_dir)
    d.mkdir(parents=True, exist_ok=True)
    p = (d / TEST_SCRIPT).resolve()
    p.write_text(build.lua, encoding="utf-8")
    for r in build.plan.resources:
        if Path(r.path).name == TEST_SCRIPT:
            r.source = str(p)
    return p
