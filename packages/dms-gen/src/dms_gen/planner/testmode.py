"""Test build: turn a normal BuildPlan into a headless-DCS test variant.

The player flight is replaced by an AI "proxy" flight that flies through the zones of the
guaranteed ``zone.entered`` beats and lands back at its start airbase. The runtime is told to
treat that AI group as the player (``DMS_CONFIG.test.playerProxy``) through an extra script,
``dms_test.lua``, embedded between ``dms_config.lua`` and ``dms.lua``. Encounter chances are
forced to 100 and long time triggers are shortened so one run covers as much as possible.

Verdicts stay honest for an AI proxy that cannot attack: encounter checks are required only when
their trigger is unconditional for the proxy (the rest are optional, never FAIL), ``outcome_end``
accepts any mission end unless the spec asks for a result, and when the spine's RTB call is not
position-driven the proxy loiters over the objective until it fires (``DMS_CONFIG.test.loiter``).

The normal plan is never modified (everything works on a deep copy).
"""

from __future__ import annotations

import itertools
import math
import os
import re
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Literal

from dms_core.schemas import BeatSheet, BuildPlan, MissionSpec
from dms_core.schemas.beats import Beat
from dms_core.schemas.plan import PlanGroup, PlanResource, PlanUnit, PlanWaypoint
from dms_core.schemas.runtime import (
    CircleZone,
    Encounter,
    PolygonZone,
    TestSettings,
    from_lua,
)

from .variants import pick_test_proxy, variant_plan

TEST_SCRIPT = "dms_test.lua"
TEST_SCRIPT_PATH = f"l10n/DEFAULT/{TEST_SCRIPT}"
MAX_TIME_TRIGGER_SEC = 240.0
CORNER_INSET = 0.15
MARGIN_MIN = 10.0  # approach, landing and slack
# Cold start + taxi before takeoff; measured 8.3 min for the AH-64 proxy in DCS 2.9.30 (2026-10-28).
GROUND_MIN = 10.0
HELO_SPEED_KMH = 220.0
HELO_ALT_M = 120.0  # AGL
PLANE_SPEED_KMH = 780.0  # ~420 kt
PLANE_ALT_M = 4500.0  # MSL, ~15,000 ft
# Loiter (orbit over the objective until the RTB beat): orbit speeds, trigger radius floors, cap.
PLANE_LOITER_KMH = 600.0
HELO_LOITER_KMH = 150.0
PLANE_LOITER_TRIGGER_M = 3000.0
HELO_LOITER_TRIGGER_M = 800.0
LOITER_CAP_MIN = 45.0
# Beat events driven by where the proxy flies (no loiter needed before them).
_POSITION_EVENTS = {"zone.entered", "unit.landed", "unit.takeoff"}

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


def _as_list(v: str | list[str] | None) -> list[str]:
    if v is None:
        return []
    return [v] if isinstance(v, str) else list(v)


def _trigger_key(b: Beat) -> tuple[Any, ...]:
    w = b.when
    return (w.event, w.beat, w.flag, w.zone, w.encounter, w.group, w.group_prefix, w.after_sec)


def exclusive_groups(beats: list[Beat]) -> dict[str, str]:
    """Beat id -> group name (the shared blocking flag) for mutually exclusive sibling beats.

    Siblings share a trigger and each one's ``set_flag`` blocks the others through a shared
    ``flags_not`` entry (e.g. m04's route_n / route_c / route_s rolls: exactly one fires).
    """
    out: dict[str, str] = {}
    by_key: dict[tuple[Any, ...], list[Beat]] = {}
    for b in beats:
        if not b.guaranteed:
            by_key.setdefault(_trigger_key(b), []).append(b)
    for sibs in by_key.values():
        if len(sibs) < 2:
            continue
        flags: dict[str, list[Beat]] = {}
        for b in sibs:
            sets = set(_as_list(b.effects.set_flag))
            for f in b.requires.flags_not:
                if f in sets:
                    flags.setdefault(f, []).append(b)
        for flag, members in flags.items():
            if len(members) < 2:
                continue
            for m in members:
                out.setdefault(m.id, flag)
    return out


def _near_route(path: list[XY], zones: dict[str, CircleZone | PolygonZone], e: Encounter) -> bool:
    """True if the proxy path enters a proximity trigger (zone or point + radius)."""
    t = e.trigger
    zone = zones.get(t.zone) if t.zone else None
    centre: XY
    if t.point is not None:
        centre = (t.point.x, t.point.y)
    elif zone is not None:
        centre = _zone_centre(zone)[0]
    else:
        return False
    samples: list[XY] = []
    for a, b in itertools.pairwise(path):
        n = max(1, int(_dist(a, b) // 500))
        samples.extend(
            (a[0] + (b[0] - a[0]) * i / n, a[1] + (b[1] - a[1]) * i / n) for i in range(n)
        )
    samples.extend(path[-1:])
    if t.radius_m is not None:
        return any(_dist(centre, p) <= t.radius_m for p in samples)
    if zone is None:
        return False
    return any(_contains(zone, p) for p in samples)


def encounter_requirements(
    encounters: list[Encounter],
    beats: list[Beat],
    path: list[XY],
    zones: dict[str, CircleZone | PolygonZone],
) -> dict[str, str | None]:
    """Encounter id -> group (or None) for every encounter whose check is OPTIONAL.

    Required (absent from the result) only when the trigger is unconditional for the proxy:
    spec chance 100 and a time / director trigger, a proximity trigger on the proxy route, a
    guaranteed beat, or ``start_encounter`` from a guaranteed beat. Beat-triggered encounters of
    mutually exclusive sibling beats carry the siblings' group name.
    """
    guaranteed = {b.id for b in beats if b.guaranteed}
    started = {eid for b in beats if b.guaranteed for eid in _as_list(b.effects.start_encounter)}
    groups = exclusive_groups(beats)
    starter_group: dict[str, str] = {}
    for b in beats:
        if b.id in groups:
            for eid in _as_list(b.effects.start_encounter):
                starter_group.setdefault(eid, groups[b.id])
    optional: dict[str, str | None] = {}
    for e in encounters:
        t = e.trigger
        if e.chance >= 100 and (
            e.id in started
            or t.type in ("time", "director")
            or (t.type == "beat" and t.beat in guaranteed)
            or (t.type == "proximity" and t.coalition is None and _near_route(path, zones, e))
        ):
            continue
        group = groups.get(t.beat or "") if t.type == "beat" else None
        optional[e.id] = group or starter_group.get(e.id)
    return optional


def loiter_target(
    beats: list[Beat], zones: dict[str, CircleZone | PolygonZone], start_xy: XY
) -> tuple[Beat, Beat, str] | None:
    """(RTB beat, loiter zone beat, zone id), or None when the route alone reaches the landing.

    The RTB beat is the guaranteed beat right before the first guaranteed landing beat (or the
    last spine beat when there is none); it needs a loiter only when it is not position-driven
    (a flag / timer / beat chain such as m04's rtb_call or m03's rook_rtb). The loiter zone is the
    last guaranteed zone beat's zone before it in the spine.
    """
    spine = [b for b in beats if b.guaranteed]
    if not spine:
        return None
    land = next((i for i, b in enumerate(spine) if b.when.event == "unit.landed"), len(spine))
    if land == 0:
        return None
    rtb = spine[land - 1]
    if rtb.when.event in _POSITION_EVENTS:
        return None
    for b in reversed(spine[: land - 1]):
        z = _zone_of(b)
        if z is not None and z in zones and not _contains(zones[z], start_xy):
            return rtb, b, z
    return None


def _loiter_minutes(beats: list[Beat], zone_beat: str) -> float:
    """Longest timed delay among beats after the loiter zone's beat (capped), in minutes."""
    idx = next((i for i, b in enumerate(beats) if b.id == zone_beat), 0)
    longest = 0.0
    for b in beats[idx + 1 :]:
        w = b.when
        timer = float(w.after_sec or 0) if w.event == "timer" else 0.0
        longest = max(longest, float(b.delay_sec or 0) + float(w.delay_sec or 0), timer)
    return min(longest / 60.0, LOITER_CAP_MIN)


def _zone_centre(zone: CircleZone | PolygonZone) -> tuple[XY, float]:
    """Centre and enclosing radius (circle radius, or farthest polygon vertex)."""
    if isinstance(zone, CircleZone):
        return (zone.x, zone.y), zone.radius
    pts = [(q.x, q.y) for q in zone.points]
    c = (sum(p[0] for p in pts) / len(pts), sum(p[1] for p in pts) / len(pts))
    return c, max(_dist(c, p) for p in pts)


# ---- main ----------------------------------------------------------------------------------


def make_test_plan(
    plan: BuildPlan,
    spec: MissionSpec,
    beats: list[Beat] | BeatSheet | None,
    *,
    minutes: float | None = None,
    proxy_speed_kmh: float | None = None,
    proxy_alt_m: float | None = None,
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
    # Helicopters fly the route low and slow; fixed-wing jets need a jet profile (an F-16 at the
    # helicopter's 120 m / 220 km/h fell out of the sky in the first Viper run).
    plane = orig.category == "plane"
    if proxy_speed_kmh is None:
        proxy_speed_kmh = PLANE_SPEED_KMH if plane else HELO_SPEED_KMH
    if proxy_alt_m is None:
        proxy_alt_m = PLANE_ALT_M if plane else HELO_ALT_M
    alt_type: Literal["BARO", "RADIO"] = "BARO" if plane else "RADIO"
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
                alt_type=alt_type,
                speed_kmh=proxy_speed_kmh,
            )
        )
    for x, y in legs:
        route.append(
            PlanWaypoint(
                x=round(x, 1),
                y=round(y, 1),
                alt_m=proxy_alt_m,
                alt_type=alt_type,
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
    # before the runtime tweaks below force chance = 100
    optional = encounter_requirements(tp.runtime.encounters, beat_list, path, zones)

    loiter: dict[str, Any] | None = None
    loiter_min = 0.0
    target = loiter_target(beat_list, zones, start_xy)
    if target is not None:
        rtb, zone_beat, lz = target
        centre, radius = _zone_centre(zones[lz])
        if not isinstance(zones[lz], CircleZone):
            radius = 0.0  # a polygon's enclosing circle reaches far outside it
        floor = PLANE_LOITER_TRIGGER_M if plane else HELO_LOITER_TRIGGER_M
        orbit_kmh = PLANE_LOITER_KMH if plane else HELO_LOITER_KMH
        return_sec = _dist(centre, start_xy) / (proxy_speed_kmh / 3.6) + MARGIN_MIN * 60
        loiter = {
            "zone": lz,
            "x": round(centre[0], 1),
            "y": round(centre[1], 1),
            "radiusM": round(max(radius, floor), 1),
            "altM": proxy_alt_m,
            "altType": alt_type,
            "speedMps": round(orbit_kmh / 3.6, 1),
            "startBeat": zone_beat.id,
            "untilBeat": rtb.id,
            "returnSec": round(return_sec),
        }
        loiter_min = _loiter_minutes(beat_list, zone_beat.id)

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
        else float(
            math.ceil(route_m / (proxy_speed_kmh / 3.6) / 60 + loiter_min + GROUND_MIN + MARGIN_MIN)
        )
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
    hints = spec.test
    lua = build_test_lua(
        proxy_name,
        mins,
        beat_list,
        [e.id for e in rt.encounters],
        ambient=ambient,
        optional=optional,
        require_result=hints.require_result if hints is not None else None,
        loiter=loiter,
    )
    return TestBuild(plan=tp, lua=lua, proxy=proxy_name, minutes=mins, route_km=route_km)


def default_checks(
    minutes: float,
    beats: list[Beat],
    encounter_ids: list[str],
    *,
    ambient: bool = False,
    optional: dict[str, str | None] | None = None,
    require_result: str | None = None,
) -> list[dict[str, Any]]:
    """The default in-mission check list (see lua/src/dms/test.lua for the kinds).

    ``ambient``: the runtime has ``DMS_CONFIG.ambient`` enabled with at least one site, so an
    ``ambient_cycle`` check (a site activates, then deactivates once the proxy leaves) is added.
    ``optional``: encounter id -> mutually exclusive group (or None) for optional encounter checks
    (see :func:`encounter_requirements`). ``require_result``: outcome_end demands this result
    (default: any mission end passes).
    """
    optional = optional or {}
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
        enc: dict[str, Any] = {"kind": "encounter", "name": f"encounter_{eid}", "id": eid}
        if eid in optional:
            enc["optional"] = True
            group = optional[eid]
            if group:
                enc["group"] = group
        enc["deadlineSec"] = d
        checks.append(enc)
    if ambient:
        checks.append({"kind": "ambient_cycle", "name": "ambient_cycle", "deadlineSec": d})
    checks.append({"kind": "convoy_halt", "name": "convoy_halt_on_hit"})
    outcome: dict[str, Any] = {"kind": "outcome", "name": "outcome_end"}
    if require_result:
        outcome["requireResult"] = require_result
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
    optional: dict[str, str | None] | None = None,
    require_result: str | None = None,
    loiter: dict[str, Any] | None = None,
) -> str:
    cfg: dict[str, Any] = {
        "enabled": True,
        "playerProxy": proxy,
        "minutes": minutes,
        "checks": default_checks(
            minutes,
            beats,
            encounter_ids,
            ambient=ambient,
            optional=optional,
            require_result=require_result,
        ),
    }
    if loiter is not None:
        cfg["loiter"] = loiter
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
