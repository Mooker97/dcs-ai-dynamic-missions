"""AI flights and watch missions (CONTRACTS "AI flights and watch missions (v0.9)").

``MissionSpec.flights`` become plain AI route groups in the .miz (start point plus a first leg
toward the first order's area; never late-activated or uncontrolled) and ``DMS_CONFIG.flights``
entries whose orders the Lua ``DMS.Flights`` module drives at runtime. ``MissionSpec.watch``
becomes ``DMS_CONFIG.watch`` with the focus flight's DCS group name.

Group naming: ``<CallsignWord>_<flight id>`` (e.g. 'Dustoff 3-1' + 'dustoff' -> 'Dustoff_dustoff'),
made unique by the planner's name allocator.
"""

# mypy: disallow-untyped-calls=False

from __future__ import annotations

import math
import re
from collections.abc import Callable, Mapping, Sequence
from typing import TYPE_CHECKING, Literal

from dms_core.schemas.mission import FlightOrder, FlightSpec, MissionSpec, SpecRange, Support
from dms_core.schemas.plan import PlanGroup, PlanUnit, PlanWaypoint
from dms_core.schemas.runtime import FlightConfig, FlightOrderConfig, Range, WatchConfig

from ..builder.mission import aircraft_type, callsign_names, closest_callsign
from .context import NM, ResolvedArea, canonical_country
from .loadouts import payload_for

if TYPE_CHECKING:
    from dms_core.schemas.plan import Skill as PlanSkill

FT = 0.3048
KTS_MPS = 1852.0 / 3600.0
KTS_KMH = 1.852
#: Air-start defaults: helicopters AGL (RADIO), planes MSL (BARO).
HELO_START_ALT_FT = 500.0
HELO_START_KTS = 100.0
PLANE_START_ALT_FT = 15000.0
PLANE_START_KTS = 350.0
#: Default engagement radius (escort / engage), NM.
DEFAULT_RADIUS_NM = 1.5
#: Default order timeouts (minutes) and ground time (minutes).
DEFAULT_MAX_MIN = {"hold": 15.0, "escort": 15.0, "engage": 15.0, "strike": 6.0}
DEFAULT_GROUND_MIN = 1.0
#: Formation spacing behind/right of the lead for air starts, metres.
HELO_SPACING_M = 80.0
PLANE_SPACING_M = 300.0
#: `targets` keyword -> DCS attribute name (CONTRACTS). `weapon` stays a keyword; Lua maps it.
TARGET_ATTRS: dict[str, str] = {
    "ground": "Ground Units",
    "armor": "Armored vehicles",
    "aaa": "Air Defence",
    "infantry": "Infantry",
    "air": "Air",
}
#: Order kind -> preferred DCS main tasks (first one the aircraft supports wins).
_TASK_PREFS: dict[str, tuple[str, ...]] = {
    "strike": ("Ground Attack", "CAS"),
    "engage": ("CAS", "Ground Attack"),
    "escort": ("Escort", "CAS"),
}
_ALT_KINDS = frozenset({"fly", "hold", "escort", "engage", "strike"})
_START_ACTION = {"parking_hot": "From Parking Area Hot", "runway": "From Runway"}
_WORD = re.compile(r"[A-Za-z0-9]+")


def is_helicopter(aircraft: str) -> bool:
    return bool(getattr(aircraft_type(aircraft), "helicopter", False))


def group_base_name(f: FlightSpec) -> str:
    """'Dustoff 3-1' + 'dustoff' -> 'Dustoff_dustoff' (before uniqueness suffixes)."""
    m = _WORD.search(f.callsign)
    word = m.group(0) if m else "Flight"
    return f"{word[:1].upper()}{word[1:]}_{f.id}"


def main_task(f: FlightSpec) -> str | None:
    """DCS main task for the group: from its orders, among the tasks the aircraft supports."""
    ac = aircraft_type(f.aircraft)
    supported = [t.name for t in getattr(ac, "tasks", [])]
    for kind in ("strike", "engage", "escort"):
        if any(o.do == kind for o in f.orders):
            for name in _TASK_PREFS[kind]:
                if name in supported:
                    return name
    default = getattr(ac, "task_default", None)
    return str(default.name) if default is not None else (supported[0] if supported else None)


def first_target(f: FlightSpec) -> str | None:
    """Area the flight heads to first: heading_toward, else the first order's to/at."""
    if f.heading_toward:
        return f.heading_toward
    for o in f.orders:
        a = o.to or o.at
        if a and a != f.start_area:
            return a
    return None


def _loadout_mission_type(f: FlightSpec, fallback: str) -> str:
    kinds = {o.do for o in f.orders}
    if "strike" in kinds:
        return "STRIKE"
    if kinds & {"engage", "escort"}:
        return "CAS"
    return fallback


def _heading(a: tuple[float, float], b: tuple[float, float]) -> float:
    dx, dy = b[0] - a[0], b[1] - a[1]
    if math.hypot(dx, dy) < 1.0:
        return 0.0
    return round(math.degrees(math.atan2(dy, dx)) % 360.0, 2) % 360.0


def radio_callsign(f: FlightSpec, counter: dict[str, int]) -> str | None:
    """'Dustoff 3-1' -> the closest DCS callsign for the type/country, e.g. 'Dodge 3-1'."""
    from .planning import split_callsign

    names = callsign_names(f.aircraft, canonical_country(f.country) or f.country)
    wanted, num = split_callsign(f.callsign)
    name = closest_callsign(wanted, names)
    if name is None:
        return None
    if num is None:
        counter[name] = counter.get(name, 0) + 1
        num = counter[name]
    return f"{name} {num}-1"


def plan_flight_group(
    f: FlightSpec,
    name: str,
    area: Callable[[str], ResolvedArea],
    mission_type: str,
    callsigns: dict[str, int],
) -> PlanGroup:
    """The .miz group for one AI flight (route = start point + first leg)."""
    from .planning import radio_modulation

    helo = is_helicopter(f.aircraft)
    start = area(f.start_area)
    alt_ft = f.start_alt_ft or (HELO_START_ALT_FT if helo else PLANE_START_ALT_FT)
    kts = f.start_speed_kts or (HELO_START_KTS if helo else PLANE_START_KTS)
    alt_m = round(alt_ft * FT, 1)
    kmh = round(kts * KTS_KMH, 1)
    alt_type: Literal["BARO", "RADIO"] = "RADIO" if helo else "BARO"
    target_id = first_target(f)
    target = area(target_id).center if target_id else None
    payload, _choice = payload_for(
        f.aircraft, f.loadout or "auto", _loadout_mission_type(f, mission_type)
    )
    skill: PlanSkill = f.skill
    route: list[PlanWaypoint] = []
    ground = f.start_type != "air" and start.airbase is not None
    hdg = _heading(start.center, target) if target is not None else 0.0
    if ground:
        route.append(
            PlanWaypoint(
                x=round(start.x, 1),
                y=round(start.y, 1),
                action=_START_ACTION[f.start_type],  # type: ignore[arg-type]
                airbase=start.airbase,
            )
        )
        positions = [(start.x, start.y)] * f.count
        unit_alt: float | None = None
        if target is None:  # the builder needs one turning point; DMS.Flights takes over
            target = (start.x + 5000.0, start.y)
    else:
        rad = math.radians(hdg)
        fx, fy = math.cos(rad), math.sin(rad)
        rx, ry = -fy, fx
        sp = HELO_SPACING_M if helo else PLANE_SPACING_M
        positions = [
            (start.x - fx * sp * k + rx * sp * k, start.y - fy * sp * k + ry * sp * k)
            for k in range(f.count)
        ]  # echelon right
        unit_alt = alt_m
        route.append(
            PlanWaypoint(
                x=round(start.x, 1),
                y=round(start.y, 1),
                alt_m=alt_m,
                alt_type=alt_type,
                speed_kmh=kmh,
                name="START",
            )
        )
    if target is not None:
        route.append(
            PlanWaypoint(
                x=round(target[0], 1),
                y=round(target[1], 1),
                alt_m=alt_m,
                alt_type=alt_type,
                speed_kmh=kmh,
                name=target_id or "DEPART",
            )
        )
    units = [
        PlanUnit(
            name=f"{name}-{j}",
            type=f.aircraft,
            x=round(x, 1),
            y=round(y, 1),
            alt_m=unit_alt,
            heading_deg=hdg,
            skill=skill,
            payload=payload,
        )
        for j, (x, y) in enumerate(positions, start=1)
    ]
    return PlanGroup(
        name=name,
        category="helicopter" if helo else "plane",
        coalition=f.coalition,
        country=canonical_country(f.country) or f.country,
        task=main_task(f),
        units=units,
        route=route,
        frequency_mhz=f.frequency_mhz,
        modulation=radio_modulation(f.frequency_mhz, f.modulation),  # type: ignore[arg-type]
        source=f.id,
        radio_callsign=radio_callsign(f, callsigns),
        ai_flight=True,
        immortal=f.immortal,
        invisible=f.invisible,
    )


def flight_group_names(groups: Sequence[PlanGroup]) -> dict[str, str]:
    """Flight id -> DCS group name."""
    return {g.source: g.name for g in groups if g.ai_flight and g.source}


def pickup_group(pickup: str, spec: MissionSpec, groups: Sequence[PlanGroup]) -> str | None:
    """DCS group name of a pickup id: a support asset's ground group, else an AI flight."""
    if any(s.id == pickup for s in spec.support):
        g = next((g for g in groups if g.source == pickup and not g.ai_flight), None)
        if g is not None:
            return g.name
    return flight_group_names(groups).get(pickup)


def _scale(v: SpecRange | None, k: float) -> Range | None:
    if v is None:
        return None
    if isinstance(v, tuple):
        return (round(v[0] * k, 1), round(v[1] * k, 1))
    return round(float(v) * k, 1)


def compile_order(
    o: FlightOrder,
    f: FlightSpec,
    helo: bool,
    areas: Mapping[str, ResolvedArea],
    spec: MissionSpec,
    groups: Sequence[PlanGroup],
) -> FlightOrderConfig:
    """One spec order -> DMS_CONFIG order (meters, seconds, m/s; DCS names resolved)."""
    alt_m: float | None = None
    alt_type: Literal["BARO", "RADIO"] | None = None
    speed: float | None = None
    if o.do in _ALT_KINDS:
        alt_ft = o.alt_ft or f.start_alt_ft or (HELO_START_ALT_FT if helo else PLANE_START_ALT_FT)
        alt_m = round(alt_ft * FT, 1)
        alt_type = "RADIO" if helo else "BARO"
        kts = o.speed_kts or f.start_speed_kts or (HELO_START_KTS if helo else PLANE_START_KTS)
        speed = round(kts * KTS_MPS, 1)
    elif o.speed_kts is not None:
        speed = round(o.speed_kts * KTS_MPS, 1)
    at = o.at
    if o.do == "land" and at is not None and not helo:
        ab = areas[at].airbase if at in areas else None
        at = ab or at  # planes land on the airfield (an airbase area means that airfield)
    targets: list[str] | None = None
    radius: float | None = None
    if o.do in ("escort", "engage"):
        targets = [TARGET_ATTRS[t] for t in (o.targets or ["ground"])]
        radius = round((o.radius_nm or DEFAULT_RADIUS_NM) * NM, 1)
    elif o.targets:
        targets = [TARGET_ATTRS[t] for t in o.targets]
    max_min = o.max_min if o.max_min is not None else DEFAULT_MAX_MIN.get(o.do)
    ground = (
        o.ground_min
        if o.ground_min is not None
        else (DEFAULT_GROUND_MIN if o.do == "land" else None)
    )
    return FlightOrderConfig(
        kind=o.do,
        to=o.to,
        at=at,
        flight=o.flight,
        group=o.group,
        weapon=(o.weapon or "guided_bomb") if o.do == "strike" else None,
        targets=targets,
        alt_m=alt_m,
        alt_type=alt_type,
        speed_mps=speed,
        radius_m=radius,
        ground_sec=_scale(ground, 60.0),
        max_sec=_scale(max_min, 60.0),
        pickup=pickup_group(o.pickup, spec, groups) if o.pickup else None,
        until=o.until.model_copy(deep=True) if o.until is not None else None,
        when=o.when.model_copy(deep=True) if o.when is not None else None,
    )


def compile_flights(
    spec: MissionSpec, groups: Sequence[PlanGroup], areas: Mapping[str, ResolvedArea]
) -> list[FlightConfig] | None:
    """DMS_CONFIG.flights (None when the spec has no flights)."""
    if not spec.flights:
        return None
    names = flight_group_names(groups)
    out: list[FlightConfig] = []
    for f in spec.flights:
        helo = is_helicopter(f.aircraft)
        start = areas.get(f.start_area)
        out.append(
            FlightConfig(
                id=f.id,
                group=names[f.id],
                category="helicopter" if helo else "plane",
                coalition=2 if f.coalition == "blue" else 1,
                speaker=f.speaker,
                start_airbase=start.airbase
                if (start is not None and f.start_type != "air")
                else None,
                orders=[compile_order(o, f, helo, areas, spec, groups) for o in f.orders],
            )
        )
    return out


def watch_config(spec: MissionSpec, groups: Sequence[PlanGroup]) -> WatchConfig | None:
    """DMS_CONFIG.watch (None for a normal mission)."""
    if spec.watch is None:
        return None
    return WatchConfig(
        enabled=True,
        focus=flight_group_names(groups).get(spec.watch.focus),
        cues=spec.watch.cues,
    )


def flight_support(spec: MissionSpec) -> list[Support]:
    """Radio agencies for AI flights (as Support-like assets) so comms assign their frequency."""
    support_ids = {s.id for s in spec.support}
    out: list[Support] = []
    for f in spec.flights:
        if f.id in support_ids or not (f.speaker or f.frequency_mhz):
            continue
        out.append(
            Support(
                id=f.id,
                role="cas",
                callsign=f.callsign,
                speaker=f.speaker,
                frequency_mhz=f.frequency_mhz,
                modulation=f.modulation,
            )
        )
    return out
