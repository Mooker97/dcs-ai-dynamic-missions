"""MissionBuilder: a thin, typed facade over ``dcs.Mission`` for generating new missions.

Only use this to *generate* missions from scratch. Never load and re-save user missions with
pydcs: the round-trip is lossy (see docs/rebuild/RESEARCH-NOTES.md).
"""

# mypy: disallow-untyped-calls=False

from __future__ import annotations

import datetime as _dt
import os
import random
import zipfile
from collections.abc import Callable, Iterable, Mapping, Sequence
from pathlib import Path
from typing import Any, cast

import dcs
from dcs import action, condition, mapping, task, triggers, unitgroup
from dcs.country import Country
from dcs.forcedoptions import ForcedOptions
from dcs.mission import Mission, StartType
from dcs.point import PointAction
from dcs.terrain.terrain import Airport, Terrain
from dcs.translation import ResourceKey
from dcs.unit import Skill as DcsSkill
from dcs.unittype import FlyingType, ShipType, VehicleType
from dcs.weather import CloudPreset

from . import geo
from .env import ensure_configured
from .payloads import resolve_payload
from .specs import (
    XY,
    AiTask,
    Coalition,
    MapView,
    Skill,
    StartKind,
    UnitLike,
    WaypointLike,
    WeatherPreset,
    as_unit,
    as_waypoint,
)

_START: dict[str, StartType] = {
    "cold": StartType.Cold,
    "hot": StartType.Warm,
    "runway": StartType.Runway,
}

# DCS ME "F10 view options" labels -> optionsView values.
_VIEWS: dict[str, ForcedOptions.Views] = {
    "map_only": ForcedOptions.Views.OnlyMap,  # "Map Only"
    "my_aircraft": ForcedOptions.Views.MyAircraft,  # "My Aircraft"
    "fog_of_war": ForcedOptions.Views.Allies,  # "Fog of War" (own coalition's units only)
    "allies_only": ForcedOptions.Views.OnlyAllies,  # "Allies Only"
    "all": ForcedOptions.Views.All,  # "All"
}

_COALITION_NAMES: dict[str, str] = {"blue": "blue", "red": "red", "neutrals": "neutrals"}

LUA_TRIGGER_COMMENT = "DMS: load scripts"
SOUND_KEEPER_COMMENT = "DMS: keep sound resources (never fires)"
SOUND_KEEPER_FLAG = "DMS_SOUND_KEEPER_NEVER"


def terrain_by_name(name: str) -> Terrain:
    """Instantiate a pydcs terrain by name (case/space-insensitive: 'Syria', 'persian gulf')."""
    key = name.replace(" ", "").replace("_", "").lower()
    aliases = {"pg": "persiangulf", "channel": "thechannel", "marianas": "marianaislands"}
    key = aliases.get(key, key)
    for attr in dir(dcs.terrain):
        obj = getattr(dcs.terrain, attr)
        is_terrain = isinstance(obj, type) and issubclass(obj, Terrain) and obj is not Terrain
        if is_terrain and attr.lower() == key:
            return cast("Callable[[], Terrain]", obj)()
    raise ValueError(f"Unknown theater {name!r}")


def _lookup_type(type_id: str | type, *maps: Mapping[str, Any]) -> Any:
    if isinstance(type_id, type):
        return type_id
    for m in maps:
        if type_id in m:
            return m[type_id]
    raise ValueError(f"Unknown unit type {type_id!r}")


def vehicle_type(type_id: str | type[VehicleType]) -> type[VehicleType]:
    from dcs import vehicles

    return _lookup_type(type_id, vehicles.vehicle_map)  # type: ignore[no-any-return]


def ship_type(type_id: str | type[ShipType]) -> type[ShipType]:
    from dcs import ships

    return _lookup_type(type_id, ships.ship_map)  # type: ignore[no-any-return]


def aircraft_type(type_id: str | type[FlyingType]) -> type[FlyingType]:
    from dcs import helicopters, planes

    return _lookup_type(  # type: ignore[no-any-return]
        type_id, planes.plane_map, helicopters.helicopter_map
    )


class MissionBuilder:
    """Build a new DCS mission. All positions are DCS map metres (x north, y east)."""

    def __init__(self, theater: str, seed: int) -> None:
        ensure_configured()
        self.seed = seed
        self.rng = random.Random(seed)
        self.mission = Mission(terrain_by_name(theater))
        self.terrain: Terrain = self.mission.terrain
        self._group_names: set[str] = set()
        self._unit_names: set[str] = set()
        self._resource_names: set[str] = set()
        self._lua_trigger: triggers.TriggerStart | None = None
        self._sounds: list[ResourceKey] = []
        self._kneeboards: list[tuple[str, Path]] = []  # (zip dir, file)
        self.set_map_view("fog_of_war")

    # ------------------------------------------------------------------ mission-level
    def set_datetime(self, when: _dt.datetime) -> None:
        self.mission.start_time = when

    def set_weather(
        self,
        preset: WeatherPreset,
        wind_dir: float = 270.0,
        wind_speed_ms: float = 3.0,
        temperature_c: float = 20.0,
        cloud_base_m: int | None = None,
    ) -> None:
        """Apply a named weather preset (clear, scattered, overcast, rain, dust)."""
        clouds = {
            "clear": None,
            "scattered": "Preset5",  # Scattered 1
            "overcast": "Preset21",  # Overcast 1
            "rain": "RainyPreset1",  # Overcast And Rain 1
            "dust": None,
        }[preset]
        self.set_weather_exact(
            cloud_preset=clouds,
            cloud_base_m=cloud_base_m,
            wind_dir=wind_dir,
            wind_speed_ms=wind_speed_ms,
            temperature_c=temperature_c,
            visibility_m={"rain": 10000, "dust": 5000}.get(preset, 80000),
            dust_visibility_m=1500 if preset == "dust" else None,
            name=f"DMS {preset}",
        )

    def set_weather_exact(
        self,
        cloud_preset: str | None = None,
        cloud_base_m: float | None = None,
        wind_dir: float = 0.0,
        wind_speed_ms: float = 0.0,
        temperature_c: float = 20.0,
        qnh_mmhg: float = 760.0,
        visibility_m: float = 80000,
        fog_visibility_m: float | None = None,
        dust_visibility_m: float | None = None,
        name: str = "DMS custom",
    ) -> None:
        """Exact weather. Fog and dust keys are always written so DCS never sees them missing.

        ``cloud_preset`` is a DCS preset name ('Preset1'..'Preset27', 'RainyPreset1'..3); the
        base is clamped into the preset's legal range.
        """
        w = self.mission.weather
        w.wind_at_ground = dcs.weather.Wind(wind_dir, wind_speed_ms)
        w.wind_at_2000 = dcs.weather.Wind(wind_dir, wind_speed_ms * 2)
        w.wind_at_8000 = dcs.weather.Wind(wind_dir, wind_speed_ms * 3)
        w.season_temperature = temperature_c
        w.qnh = qnh_mmhg
        w.visibility_distance = int(visibility_m)
        w.enable_fog = fog_visibility_m is not None
        w.fog_thickness = 300 if fog_visibility_m is not None else 0
        w.fog_visibility = int(fog_visibility_m) if fog_visibility_m is not None else 0
        w.enable_dust = dust_visibility_m is not None
        w.dust_density = int(dust_visibility_m) if dust_visibility_m is not None else 0
        w.clouds_preset = None
        w.clouds_thickness = 200
        w.clouds_density = 0
        w.clouds_base = 300
        w.clouds_iprecptns = dcs.weather.Weather.Preceptions.None_
        if cloud_preset is not None:
            cp = CloudPreset.by_name(cloud_preset)
            w.clouds_preset = cp
            base = int(cloud_base_m) if cloud_base_m is not None else max(cp.min_base, 1500)
            w.clouds_base = min(max(base, cp.min_base), cp.max_base)
        w.name = name

    def set_briefing(
        self,
        sortie: str,
        description: str,
        blue_task: str = "",
        red_task: str = "",
    ) -> None:
        self.mission.set_sortie_text(sortie)
        self.mission.set_description_text(description)
        self.mission.set_description_bluetask_text(blue_task)
        self.mission.set_description_redtask_text(red_task)

    def set_map_view(self, view: MapView) -> None:
        """Set the forced F10 map view option (default: fog of war)."""
        self.mission.forced_options.options_view = _VIEWS[view]

    # ------------------------------------------------------------------ lookups
    def airbase(self, name: str) -> Airport:
        try:
            return self.terrain.airports[name]
        except KeyError:
            lowered = {k.lower(): v for k, v in self.terrain.airports.items()}
            if name.lower() in lowered:
                return lowered[name.lower()]
            raise ValueError(f"No airbase {name!r} on {self.terrain.name}") from None

    def point(self, x: float, y: float) -> mapping.Point:
        return mapping.Point(x, y, self.terrain)

    def latlon_to_xy(self, lat: float, lon: float) -> XY:
        return geo.latlon_to_xy(self.terrain, lat, lon)

    def xy_to_latlon(self, x: float, y: float) -> tuple[float, float]:
        return geo.xy_to_latlon(self.terrain, x, y)

    def random_point_in_polygon(self, poly: Sequence[XY]) -> XY:
        return geo.random_point_in_polygon(poly, self.rng)

    def is_on_map(self, x: float, y: float) -> bool:
        return geo.is_on_map(self.terrain, x, y)

    def country(self, coalition: Coalition, name: str) -> Country:
        """Return the country, moving it into ``coalition`` if pydcs defaults put it elsewhere."""
        target = self.mission.coalition[_COALITION_NAMES[coalition]]
        c = target.country(name)
        if c is not None:
            return c  # type: ignore[no-any-return]
        for cname, coal in self.mission.coalition.items():
            if cname != coalition and coal.country(name) is not None:
                coal.swap_country(target, name)
                return target.country(name)  # type: ignore[no-any-return]
        from dcs import countries

        for cls in countries.country_dict.values():
            if getattr(cls, "name", None) == name:
                newc = cls()
                target.add_country(newc)
                return newc
        raise ValueError(f"Unknown country {name!r}")

    # ------------------------------------------------------------------ names
    def _claim_group(self, name: str) -> None:
        if name in self._group_names:
            raise ValueError(f"Duplicate group name {name!r} (DCS would replace the group)")
        self._group_names.add(name)

    def _claim_unit(self, name: str) -> None:
        if name in self._unit_names:
            raise ValueError(f"Duplicate unit name {name!r}")
        self._unit_names.add(name)

    def rename_units(self, group: unitgroup.Group[Any, Any], names: Sequence[str]) -> None:
        """Rename a group's units (pydcs auto-names flight members '<group> Pilot #n')."""
        if len(names) != len(group.units):
            raise ValueError(f"{group.name}: {len(names)} names for {len(group.units)} units")
        for u, new in zip(group.units, names, strict=True):
            if new == u.name:
                continue
            self._claim_unit(new)
            self._unit_names.discard(u.name)
            u.name = new

    # ------------------------------------------------------------------ flights
    def add_player_flight(
        self,
        coalition: Coalition,
        country: str,
        aircraft: str | type[FlyingType],
        airbase: str | None,
        name: str,
        start: StartKind = "cold",
        count: int = 1,
        callsign: tuple[str, int] | None = None,
        payload: Mapping[int, str] | str | None = None,
        position: XY | None = None,
        altitude_m: float | None = None,
        frequency_mhz: float | None = None,
        client: bool = True,
    ) -> unitgroup.FlyingGroup[Any]:
        """Player/client flight. ``client=False`` makes the lead a single-player 'Player'."""
        group = self._flight(
            coalition,
            country,
            aircraft,
            airbase,
            name,
            start,
            count,
            task_=None,
            position=position,
            altitude_m=altitude_m,
        )
        for i, u in enumerate(group.units):
            if client:
                u.set_client()
            elif i == 0:
                u.set_player()
        self._apply_payload(group, payload)
        if callsign is not None:
            self._apply_callsign(group, country, callsign)
        if frequency_mhz is not None:
            group.set_frequency(frequency_mhz)
        return group

    def add_ai_flight(
        self,
        coalition: Coalition,
        country: str,
        aircraft: str | type[FlyingType],
        name: str,
        task_kind: AiTask,
        orbit: tuple[XY, XY],
        airbase: str | None = None,
        start: StartKind = "air",
        count: int = 1,
        altitude_m: float = 6000,
        speed_kmh: float = 600,
        payload: Mapping[int, str] | str | None = None,
        skill: Skill = "High",
        frequency_mhz: float | None = None,
        tacan: str = "10X",
    ) -> unitgroup.FlyingGroup[Any]:
        """Basic AI flight. ``orbit`` = (p1, p2): race-track legs (CAS: p1 = target area)."""
        m = self.mission
        c = self.country(coalition, country)
        t: Any = aircraft_type(aircraft)
        p1, p2 = self.point(*orbit[0]), self.point(*orbit[1])
        ab = self.airbase(airbase) if (airbase and start != "air") else None
        st = _START.get(start, StartType.Cold)
        if task_kind != "cas":
            self._claim_group(name)
        group: unitgroup.FlyingGroup[Any]
        heading = p1.heading_between_point(p2)
        dist = p1.distance_to_point(p2)
        freq = frequency_mhz or 251.0
        if task_kind == "cap":
            group = m.patrol_flight(
                c,
                name,
                t,
                ab,
                p1,
                p2,
                start_type=st,
                speed=speed_kmh,
                altitude=int(altitude_m),
                group_size=count,
            )
        elif task_kind == "awacs":
            group = m.awacs_flight(
                c,
                name,
                t,
                ab,
                p1,
                race_distance=dist,
                heading=heading,
                altitude=int(altitude_m),
                speed=speed_kmh,
                start_type=st,
                frequency=freq,
            )
        elif task_kind == "tanker":
            group = m.refuel_flight(
                c,
                name,
                t,
                ab,
                p1,
                race_distance=dist,
                heading=heading,
                altitude=int(altitude_m),
                speed=speed_kmh,
                start_type=st,
                frequency=freq,
                tacanchannel=tacan,
            )
        elif task_kind == "cas":
            group = self._flight(
                coalition,
                country,
                t,
                airbase,
                name,
                start,
                count,
                task_=task.CAS,
                position=(p1.x - 10000, p1.y),
                altitude_m=altitude_m,
            )
            group.add_waypoint(p1, altitude_m, speed_kmh)
            wp = group.add_waypoint(p2, altitude_m, speed_kmh)
            wp.tasks.append(
                task.OrbitAction(
                    int(altitude_m), int(speed_kmh), task.OrbitAction.OrbitPattern.Circle
                )
            )
        else:  # pragma: no cover - Literal guards this
            raise ValueError(task_kind)
        for u in group.units:
            if task_kind != "cas":
                self._claim_unit(u.name)
            u.skill = DcsSkill(skill)
        self._apply_payload(group, payload)
        if frequency_mhz is not None and task_kind in ("cap", "cas"):
            group.set_frequency(frequency_mhz)
        return group

    def _flight(
        self,
        coalition: Coalition,
        country: str,
        aircraft: str | type[FlyingType],
        airbase: str | None,
        name: str,
        start: StartKind,
        count: int,
        task_: type[task.MainTask] | None,
        position: XY | None,
        altitude_m: float | None,
    ) -> unitgroup.FlyingGroup[Any]:
        m = self.mission
        c = self.country(coalition, country)
        t = aircraft_type(aircraft)
        self._claim_group(name)
        maintask = task_ or t.task_default or task.CAS
        if start == "air":
            if position is None:
                if airbase is None:
                    raise ValueError("air start needs position or airbase")
                ab_pos = self.airbase(airbase).position
                position = (ab_pos.x, ab_pos.y)
            alt = altitude_m if altitude_m is not None else (150 if t.helicopter else 3000)
            group = m.flight_group_inflight(
                c, name, t, self.point(*position), int(alt), maintask=maintask, group_size=count
            )
        else:
            if airbase is None:
                raise ValueError(f"start={start!r} needs an airbase")
            group = m.flight_group_from_airport(
                c,
                name,
                t,
                self.airbase(airbase),
                maintask=maintask,
                start_type=_START[start],
                group_size=count,
            )
        for u in group.units:
            self._claim_unit(u.name)
        return group

    def _apply_payload(
        self, group: unitgroup.FlyingGroup[Any], payload: Mapping[int, str] | str | None
    ) -> None:
        t = group.units[0].unit_type
        loadout = resolve_payload(t, payload)
        if loadout is None:
            return
        for u in group.units:
            u.reset_loadout()
            for pylon, clsid in sorted(loadout.items()):
                u.load_pylon((pylon, {"clsid": clsid}))

    def _apply_callsign(
        self, group: unitgroup.FlyingGroup[Any], country: str, callsign: tuple[str, int]
    ) -> None:
        cs_name, flight_no = callsign
        t = group.units[0].unit_type
        names: list[str] = list(getattr(t, "callnames", {}).get(country, []))
        c = self.mission.country(country)
        for cat_names in getattr(c, "callsign", {}).values():
            names.extend(n for n in cat_names if n not in names)
        idx = names.index(cs_name) + 1 if cs_name in names else 1
        for i, u in enumerate(group.units, start=1):
            u.callsign = None
            u.callsign_dict = {1: idx, 2: flight_no, 3: i, "name": f"{cs_name}{flight_no}{i}"}

    # ------------------------------------------------------------------ ground / ships
    def add_ground_group(
        self,
        coalition: Coalition,
        country: str,
        name: str,
        units: Sequence[UnitLike],
        position: XY,
        late_activation: bool = False,
        hidden: bool = False,
        waypoints: Sequence[WaypointLike] = (),
        skill: Skill = "Average",
    ) -> unitgroup.VehicleGroup:
        """Ground group at ``position``; unit offsets are relative to it. Waypoints speed km/h."""
        m = self.mission
        c = self.country(coalition, country)
        specs = [as_unit(u) for u in units]
        if not specs:
            raise ValueError("ground group needs at least one unit")
        self._claim_group(name)
        vg = unitgroup.VehicleGroup(m.next_group_id(), name)
        for i, s in enumerate(specs, start=1):
            uname = s.name or f"{name}-{i}"
            self._claim_unit(uname)
            v = m.vehicle(uname, vehicle_type(s.type))
            v.position = self.point(position[0] + s.dx, position[1] + s.dy)
            v.heading = s.heading
            v.skill = DcsSkill(skill)
            vg.add_unit(v)
        wps = [as_waypoint(w) for w in waypoints]
        first_action = (
            (PointAction.OnRoad if wps[0].on_road else PointAction.OffRoad)
            if wps
            else PointAction.OffRoad
        )
        first_speed = wps[0].speed if wps else 0
        wp0 = vg.add_waypoint(vg.units[0].position, first_action, first_speed)
        wp0.ETA_locked = True
        for w in wps:
            vg.add_waypoint(
                self.point(w.x, w.y),
                PointAction.OnRoad if w.on_road else PointAction.OffRoad,
                w.speed,
            )
        vg.late_activation = late_activation
        vg.hidden = hidden
        vg.hidden_on_planner = hidden
        vg.hidden_on_mfd = hidden
        c.add_vehicle_group(vg)
        return vg

    def add_ship_group(
        self,
        coalition: Coalition,
        country: str,
        name: str,
        units: Sequence[UnitLike],
        position: XY,
        late_activation: bool = False,
        hidden: bool = False,
        waypoints: Sequence[XY] = (),
        speed_kmh: float = 20,
    ) -> unitgroup.ShipGroup:
        m = self.mission
        c = self.country(coalition, country)
        specs = [as_unit(u) for u in units]
        self._claim_group(name)
        sg = unitgroup.ShipGroup(m.next_group_id(), name)
        for i, s in enumerate(specs, start=1):
            uname = s.name or f"{name}-{i}"
            self._claim_unit(uname)
            sh = m.ship(uname, ship_type(s.type))
            sh.position = self.point(position[0] + s.dx, position[1] + s.dy)
            sh.heading = s.heading
            sg.add_unit(sh)
        sg.add_waypoint(sg.units[0].position, 0)
        for x, y in waypoints:
            sg.add_waypoint(self.point(x, y), speed_kmh)
        sg.late_activation = late_activation
        sg.hidden = hidden
        c.add_ship_group(sg)
        return sg

    # ------------------------------------------------------------------ zones
    def add_circle_zone(self, name: str, center: XY, radius: float) -> triggers.TriggerZone:
        return self.mission.triggers.add_triggerzone(self.point(*center), radius, name=name)

    def add_quad_zone(self, name: str, points: Sequence[XY]) -> triggers.TriggerZone:
        """Quad-point zone (DCS supports exactly 4 vertices, stored as ``verticies``)."""
        if len(points) != 4:
            raise ValueError("DCS quad zones need exactly 4 points")
        cx = sum(p[0] for p in points) / 4
        cy = sum(p[1] for p in points) / 4
        return self.mission.triggers.add_triggerzone_quad(
            self.point(cx, cy), [self.point(*p) for p in points], name=name
        )

    # ------------------------------------------------------------------ resources
    def _add_resource(self, path: str | os.PathLike[str]) -> ResourceKey:
        p = Path(path)
        if not p.is_file():
            raise FileNotFoundError(p)
        if p.name in self._resource_names:
            raise ValueError(f"Resource name clash in l10n/DEFAULT: {p.name}")
        self._resource_names.add(p.name)
        return self.mission.map_resource.add_resource_file(str(p))

    def embed_lua_files(self, files_in_order: Iterable[str | os.PathLike[str]]) -> list[str]:
        """Add scripts as ordered DO SCRIPT FILE actions in one MISSION START trigger.

        Order is the caller's: framework plugins first, then dms.lua, then dms_config.lua.
        Repeated calls append to the same trigger. Returns the resource keys.
        """
        if self._lua_trigger is None:
            self._lua_trigger = triggers.TriggerStart(comment=LUA_TRIGGER_COMMENT)
            self.mission.triggerrules.triggers.append(self._lua_trigger)
        keys = []
        for f in files_in_order:
            key = self._add_resource(f)
            self._lua_trigger.add_action(action.DoScriptFile(key))
            keys.append(key.key)
        return keys

    def embed_sound(self, path: str | os.PathLike[str]) -> str:
        """Embed a sound; returns the path Lua should use (``l10n/DEFAULT/<file>``)."""
        key = self._add_resource(path)
        self._sounds.append(key)
        return f"l10n/DEFAULT/{Path(path).name}"

    def embed_kneeboard(
        self, path: str | os.PathLike[str], aircraft: str | type[FlyingType] | None = None
    ) -> str:
        """Kneeboard image for all aircraft (``KNEEBOARD/IMAGES``) or one type."""
        p = Path(path)
        if not p.is_file():
            raise FileNotFoundError(p)
        folder = (
            "KNEEBOARD/IMAGES"
            if aircraft is None
            else f"KNEEBOARD/{aircraft_type(aircraft).id}/IMAGES"
        )
        self._kneeboards.append((folder, p))
        return f"{folder}/{p.name}"

    def _finalize_sounds(self) -> None:
        # Remove any previous keeper (save may be called twice).
        rules = self.mission.triggerrules.triggers
        rules[:] = [t for t in rules if t.comment != SOUND_KEEPER_COMMENT]
        if not self._sounds:
            return
        keeper = triggers.TriggerOnce(comment=SOUND_KEEPER_COMMENT)
        keeper.add_condition(condition.FlagEquals(SOUND_KEEPER_FLAG, 424242))
        for key in self._sounds:
            keeper.add_action(action.SoundToAll(key))
        rules.append(keeper)

    # ------------------------------------------------------------------ output
    def save(self, path: str | os.PathLike[str]) -> Path:
        out = Path(path)
        out.parent.mkdir(parents=True, exist_ok=True)
        self._finalize_sounds()
        self.mission.save(str(out))
        if self._kneeboards:
            with zipfile.ZipFile(out, "a", compression=zipfile.ZIP_DEFLATED) as z:
                existing = set(z.namelist())
                for folder, f in self._kneeboards:
                    arc = f"{folder}/{f.name}"
                    if arc not in existing:
                        z.write(f, arcname=arc)
                        existing.add(arc)
        return out
