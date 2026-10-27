"""Thin adapter: ``dms_core.schemas.plan.BuildPlan`` -> MissionBuilder -> .miz.

Covers what the builder supports today. Unsupported plan features raise
``NotImplementedError`` instead of being silently dropped:

* static groups
* AI air groups whose task is not CAP / CAS / AWACS / tanker *and* that have no route
  (with turning points they become a generic route flight: optional airfield start,
  the turning points in order, optional ``Landing`` waypoint -> land at that airbase)
* polygon zones with a vertex count other than 4 (DCS ME quads have exactly 4; arbitrary
  polygons belong in ``DMS_CONFIG.zones`` for the Lua runtime)

Script order: ``script`` resources in plan order, then ``dms_config.lua`` generated from
``plan.runtime`` (unless the plan already lists a resource with that name).
"""

# mypy: disallow-untyped-calls=False

from __future__ import annotations

import datetime as _dt
import os
import tempfile
from pathlib import Path
from typing import TYPE_CHECKING, Any

from dcs import action as dcs_action
from dcs import condition as dcs_condition
from dcs import triggers as dcs_triggers
from dcs.forcedoptions import ForcedOptions

from .mission import MissionBuilder
from .specs import AirWaypoint, Coalition, GroundWaypoint, StartKind, UnitSpec

if TYPE_CHECKING:
    from dms_core.schemas.plan import (  # type: ignore[import-untyped,unused-ignore]
        BuildPlan,
        PlanGroup,
    )

_START_BY_ACTION: dict[str, StartKind] = {
    "From Parking Area": "cold",
    "From Parking Area Hot": "hot",
    "From Runway": "runway",
}
_AI_TASKS = {
    "CAP": "cap",
    "CAS": "cas",
    "AWACS": "awacs",
    "TANKER": "tanker",
    "Refueling": "tanker",
}
_LABELS = {
    "none": ForcedOptions.Labels.None_,
    "full": ForcedOptions.Labels.Full,
    "abbreviated": ForcedOptions.Labels.Abbreviate,
    "dot": ForcedOptions.Labels.DotOnly,
}
_CIV = {
    "off": ForcedOptions.CivilTraffic.Off,
    "low": ForcedOptions.CivilTraffic.Low,
    "medium": ForcedOptions.CivilTraffic.Medium,
    "high": ForcedOptions.CivilTraffic.High,
}


def _coal(c: str) -> Coalition:
    return "neutrals" if c == "neutral" else c  # type: ignore[return-value]


def build_from_plan(
    plan: BuildPlan,
    out: str | os.PathLike[str],
    base_dir: str | os.PathLike[str] | None = None,
) -> Path:
    """Build ``plan`` into ``out``. Resource ``source`` paths resolve against ``base_dir``."""
    base = Path(base_dir) if base_dir else Path.cwd()
    b = MissionBuilder(plan.theater, plan.seed)
    t = _dt.time(
        plan.start_time_sec // 3600, (plan.start_time_sec // 60) % 60, plan.start_time_sec % 60
    )
    b.set_datetime(_dt.datetime.combine(plan.date, t))
    w = plan.weather
    b.set_weather_exact(
        cloud_preset=w.cloud_preset,
        cloud_base_m=w.cloud_base_m,
        wind_dir=w.wind_dir_deg,
        wind_speed_ms=w.wind_speed_mps,
        temperature_c=w.temperature_c,
        qnh_mmhg=w.qnh_mmhg,
        visibility_m=w.visibility_m,
        fog_visibility_m=w.fog_visibility_m,
        dust_visibility_m=w.dust_visibility_m,
    )
    for name in plan.blue_countries:
        b.country("blue", name)
    for name in plan.red_countries:
        b.country("red", name)
    if plan.briefing:
        br = plan.briefing
        b.set_briefing(br.title, br.description, br.blue_task, br.red_task)
    opts = plan.options
    b.set_map_view("fog_of_war" if opts.fog_of_war_map else "all")
    fo = b.mission.forced_options
    fo.labels = _LABELS[opts.labels]
    fo.civil_traffic = _CIV[opts.civil_traffic]
    fo.external_views = opts.external_views

    for g in plan.groups:
        _add_group(b, g)

    for z in plan.zones:
        if z.kind == "circle":
            assert z.x is not None and z.y is not None and z.radius_m is not None
            b.add_circle_zone(z.name, (z.x, z.y), z.radius_m)
        elif len(z.points) == 4:
            b.add_quad_zone(z.name, z.points)
        else:
            raise NotImplementedError(f"zone {z.name!r}: ME quads need exactly 4 points")

    with tempfile.TemporaryDirectory(prefix="dms-build-") as tmp:
        scripts: list[Path] = []
        for r in plan.resources:
            src = (base / r.source) if not Path(r.source).is_absolute() else Path(r.source)
            if r.kind == "script":
                scripts.append(src)
            elif r.kind == "sound":
                b.embed_sound(src)
            elif r.kind == "kneeboard":
                parts = r.path.split("/")
                aircraft = parts[1] if len(parts) == 4 and parts[2] == "IMAGES" else None
                b.embed_kneeboard(src, aircraft)
            elif r.kind == "briefing_image":
                b.mission.add_picture_blue(str(src))
            else:
                b._add_resource(src)
        if plan.runtime is not None and not any(p.name == "dms_config.lua" for p in scripts):
            cfg = Path(tmp) / "dms_config.lua"
            cfg.write_text(plan.runtime.to_lua_source(), encoding="utf-8")
            scripts.append(cfg)
        if scripts:
            b.embed_lua_files(scripts)
        for trig in plan.triggers:
            _add_trigger(b, trig)
        return b.save(out)


def _add_group(b: MissionBuilder, g: PlanGroup) -> None:
    coal = _coal(g.coalition)
    u0 = g.units[0]
    if g.category in ("vehicle", "ship"):
        units = [UnitSpec(u.type, u.x - u0.x, u.y - u0.y, u.heading_deg, u.name) for u in g.units]
        route = list(g.route)
        if route and abs(route[0].x - u0.x) < 1 and abs(route[0].y - u0.y) < 1:
            route = route[1:]
        if g.category == "vehicle":
            skill = u0.skill if u0.skill not in ("Client", "Player") else "Average"
            b.add_ground_group(
                coal,
                g.country,
                g.name,
                units,
                (u0.x, u0.y),
                late_activation=g.late_activation,
                hidden=g.hidden,
                waypoints=[
                    GroundWaypoint(p.x, p.y, p.speed_kmh or 30, p.action == "On Road")
                    for p in route
                ],
                skill=skill,  # type: ignore[arg-type]
            )
        else:
            b.add_ship_group(
                coal,
                g.country,
                g.name,
                units,
                (u0.x, u0.y),
                late_activation=g.late_activation,
                hidden=g.hidden,
                waypoints=[(p.x, p.y) for p in route],
            )
        return
    if g.category == "static":
        raise NotImplementedError(f"static group {g.name!r}: not supported by the builder yet")

    payload = {p.num: p.clsid for p in u0.payload.pylons} if u0.payload else None
    first = g.route[0] if g.route else None
    group: Any
    if g.client:
        start: StartKind = _START_BY_ACTION.get(first.action, "air") if first else "air"
        group = b.add_player_flight(
            coal,
            g.country,
            u0.type,
            first.airbase if first else None,
            g.name,
            start=start,
            count=len(g.units),
            payload=payload,
            position=(u0.x, u0.y),
            altitude_m=u0.alt_m,
            frequency_mhz=g.frequency_mhz,
            client=not any(u.skill == "Player" for u in g.units),
        )
    else:
        kind = _AI_TASKS.get(str(g.task or ""))
        if kind is None:
            if not any(p.action in ("Turning Point", "Fly Over Point") for p in g.route):
                raise NotImplementedError(
                    f"AI air group {g.name!r}: task {g.task!r} not supported without a route"
                )
            _add_route_flight(b, g, coal, payload)
            return
        legs = [p for p in g.route if p.action in ("Turning Point", "Fly Over Point")]
        p1 = (legs[0].x, legs[0].y) if legs else (u0.x, u0.y)
        p2 = (legs[1].x, legs[1].y) if len(legs) > 1 else (p1[0] + 20000, p1[1])
        group = b.add_ai_flight(
            coal,
            g.country,
            u0.type,
            g.name,
            kind,  # type: ignore[arg-type]
            (p1, p2),
            airbase=first.airbase if first else None,
            start=_START_BY_ACTION.get(first.action, "air") if first else "air",
            count=len(g.units),
            altitude_m=u0.alt_m or 6000,
            payload=payload,
            frequency_mhz=g.frequency_mhz,
        )
    b.rename_units(group, [u.name for u in g.units])
    group.late_activation = g.late_activation
    group.hidden = g.hidden
    group.uncontrolled = g.uncontrolled


def _add_route_flight(
    b: MissionBuilder, g: PlanGroup, coal: Coalition, payload: dict[int, str] | None
) -> None:
    """Generic AI air route: optional airfield start, turning points, optional landing."""
    u0 = g.units[0]
    first = g.route[0] if g.route else None
    start: StartKind = _START_BY_ACTION.get(first.action, "air") if first else "air"
    landing = next((p for p in g.route if p.action == "Landing"), None)
    legs = [
        AirWaypoint(p.x, p.y, p.alt_m or 150, p.speed_kmh or 220, p.alt_type)
        for p in g.route
        if p.action in ("Turning Point", "Fly Over Point")
    ]
    if start == "air" and first is not None and first.action in ("Turning Point", "Fly Over Point"):
        position: tuple[float, float] | None = (first.x, first.y)
        alt: float | None = first.alt_m or u0.alt_m or 150
        legs = legs[1:]
    else:
        position, alt = None, None
    skill = u0.skill if u0.skill in ("Average", "Good", "High", "Excellent", "Random") else "High"
    group = b.add_ai_route_flight(
        coal,
        g.country,
        u0.type,
        g.name,
        legs,
        airbase=first.airbase if first else None,
        start=start,
        count=len(g.units),
        payload=payload,
        skill=skill,
        frequency_mhz=g.frequency_mhz,
        land_at=(landing.airbase or (first.airbase if first else None)) if landing else None,
        position=position,
        altitude_m=alt,
    )
    b.rename_units(group, [u.name for u in g.units])
    group.late_activation = g.late_activation
    group.hidden = g.hidden
    group.uncontrolled = g.uncontrolled


def _resolve_params(b: MissionBuilder, params: dict[str, Any]) -> dict[str, Any]:
    out: dict[str, Any] = {}
    zones = {z.name: z.id for z in b.mission.triggers.zones()}
    for k, v in params.items():
        if k in ("zone", "zone_id") and isinstance(v, str):
            out[k] = zones[v]
        elif k in ("group", "group_id", "unit_group") and isinstance(v, str):
            grp = b.mission.find_group(v)
            if grp is None:
                raise ValueError(f"trigger references unknown group {v!r}")
            out[k] = grp.id
        elif k == "text" and isinstance(v, str):
            out[k] = b.mission.string(v)
        else:
            out[k] = v
    return out


def _add_trigger(b: MissionBuilder, trig: Any) -> None:
    rule_cls = {
        "once": dcs_triggers.TriggerOnce,
        "continuous": dcs_triggers.TriggerContinious,
        "mission_start": dcs_triggers.TriggerStart,
        "switched": dcs_triggers.TriggerCondition,
    }[trig.kind]
    rule = rule_cls(comment=trig.name)
    for c in trig.conditions:
        rule.add_condition(getattr(dcs_condition, c.type)(**_resolve_params(b, c.params)))
    for a in trig.actions:
        rule.add_action(getattr(dcs_action, a.type)(**_resolve_params(b, a.params)))
    b.mission.triggerrules.triggers.append(rule)
