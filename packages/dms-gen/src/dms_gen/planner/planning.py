"""plan_mission: MissionSpec (+ beats, lines, voice manifest) -> exact, seeded BuildPlan.

Python decides the space of possibilities (templates, zones, pools, weights, beats, voice map);
the Lua runtime picks the instance on each play (ADR 0007). Everything here is deterministic
for a given seed: the only randomness source is ``random.Random(seed)``.
"""

# mypy: disallow-untyped-calls=False

from __future__ import annotations

import json
import math
import os
import random
import re
import zlib
from collections.abc import Mapping, Sequence
from pathlib import Path
from typing import Any

import yaml
from dms_core.schemas.beats import Beat, BeatSheet
from dms_core.schemas.campaign import Qualities
from dms_core.schemas.mission import MissionSpec, PlayerFlight, Support, Threat
from dms_core.schemas.plan import (
    BuildPlan,
    PlanBriefing,
    PlanGroup,
    PlanOptions,
    PlanResource,
    PlanUnit,
    PlanWaypoint,
    PlanWeather,
    PlanZone,
)
from dms_core.schemas.plan import (
    Skill as PlanSkill,
)
from dms_core.schemas.runtime import (
    XY,
    Adapt,
    Budgets,
    CircleZone,
    Director,
    Encounter,
    EncounterTrigger,
    Intel,
    Players,
    PolygonZone,
    Pool,
    PoolMember,
    RuntimeConfig,
    Speaker,
    Template,
    TemplateUnit,
    VoiceEntry,
    VoiceTurn,
)
from dms_core.schemas.story import StoryBible
from dms_core.schemas.voice import VoiceLineSet
from pydantic import ValidationError

from ..builder.mission import aircraft_type
from . import forces
from .context import (
    NM,
    PlanError,
    ResolvedArea,
    canonical_country,
    country_key,
    era_for_year,
    faction_map,
    on_map,
    resolve_areas,
)
from .loadouts import payload_for

Manifest = Mapping[str, Mapping[str, Any]]

_START_ACTION = {
    "parking_cold": "From Parking Area",
    "parking_hot": "From Parking Area Hot",
    "runway": "From Runway",
}
_WEATHER: dict[str, dict[str, Any]] = {
    "clear": {},
    "night_clear": {},
    "scattered": {"cloud_preset": "Preset5"},
    "broken": {"cloud_preset": "Preset10"},
    "overcast": {"cloud_preset": "Preset21"},
    "rain": {"cloud_preset": "RainyPreset1", "visibility_m": 10000, "precipitation": "rain"},
    "storm": {
        "cloud_preset": "RainyPreset3",
        "visibility_m": 5000,
        "precipitation": "thunderstorm",
    },
    "dust": {"visibility_m": 5000, "dust_visibility_m": 1500},
    "fog": {"visibility_m": 3000, "fog_visibility_m": 800},
}
_INTENSITY = {
    "calm": (50.0, (60.0, 120.0), 2.0),
    "moderate": (70.0, (40.0, 90.0), 3.0),
    "intense": (85.0, (25.0, 60.0), 5.0),
}
_AUDIO_TAG = re.compile(r"\[[^\]]*\]\s*")
_SUPPORT_AIR = {
    "awacs": ("awacs_e3a", "AWACS"),
    "tanker": ("tanker_kc135", "TANKER"),
    "cap": ("f15c_cap_2ship", "CAP"),
    "escort": ("f15c_cap_2ship", "CAP"),
    "cas": ("a10c_cas_2ship", "CAS"),
}
#: Minimum metres between pre-placed groups, and SAM-to-SAM spacing.
GROUP_SPACING_M = 250.0
SAM_SPACING_M = 1500.0


def resolve_seed(spec: MissionSpec, seed: int | None) -> int:
    """Explicit seed > spec.seed > crc32(mission id) (stable, so plans are reproducible)."""
    if seed is not None:
        return int(seed)
    if spec.seed is not None:
        return int(spec.seed)
    return zlib.crc32(spec.id.encode("utf-8")) & 0x7FFFFFFF


def load_manifest(
    voice_manifest: Manifest | str | os.PathLike[str] | None,
) -> tuple[dict[str, dict[str, Any]], Path | None]:
    """Voice manifest (dict or manifest.json path) -> (entries, directory holding the files)."""
    if voice_manifest is None:
        return {}, None
    if isinstance(voice_manifest, str | os.PathLike):
        p = Path(voice_manifest)
        if p.is_dir():
            p = p / "manifest.json"
        data = json.loads(p.read_text(encoding="utf-8"))
        return {str(k): dict(v) for k, v in data.items()}, p.parent
    return {str(k): dict(v) for k, v in voice_manifest.items()}, None


def placeholder_duration(text: str) -> float:
    """Rough spoken duration: ~2.6 words/s radio cadence plus squelch, min 1.5 s."""
    words = len(_AUDIO_TAG.sub("", text).split())
    return round(max(1.5, words / 2.6 + 0.6), 1)


class _Names:
    def __init__(self) -> None:
        self.used: set[str] = set()

    def alloc(self, base: str) -> str:
        name = base
        n = 2
        while name in self.used:
            name = f"{base}_{n}"
            n += 1
        self.used.add(name)
        return name


class _Placer:
    """Seeded point picker with spacing, map-bounds and SAM-off-town-centre rules."""

    def __init__(self, theater: str, rng: random.Random, keep_out: list[tuple[float, float]]):
        self.theater = theater
        self.rng = rng
        self.placed: list[tuple[float, float, bool]] = []  # x, y, is_sam
        self.keep_out = keep_out  # friendly airbases: no enemy within 3 km

    def place(self, area: ResolvedArea, role: str, enemy: bool = True) -> tuple[float, float]:
        is_sam = role in forces.SAM_ROLES
        ad = role in forces.AIR_DEFENSE_ROLES
        min_town = 0.0
        if area.place_center is not None and (ad or area.terrain_hint != "urban"):
            min_town = min(600.0, 0.4 * area.radius_m) if ad else 0.0
        best: tuple[float, float] | None = None
        for attempt in range(400):
            relax = attempt >= 200
            pt = area.sample(self.rng, outer=0.85)
            if not on_map(self.theater, *pt):
                continue
            if best is None:
                best = pt
            if area.place_center is not None and math.dist(pt, area.place_center) < min_town:
                continue
            if (
                enemy
                and area.airbase is None
                and any(math.dist(pt, k) < 3000 for k in self.keep_out)
            ):
                continue
            if not relax:
                ok = True
                for x, y, s in self.placed:
                    gap = SAM_SPACING_M if (is_sam and s) else GROUP_SPACING_M
                    if math.dist(pt, (x, y)) < gap:
                        ok = False
                        break
                if not ok:
                    continue
            best = pt
            break
        if best is None:
            raise PlanError(f"area '{area.id}' has no on-map point to place {role}")
        self.placed.append((best[0], best[1], is_sam))
        return best


def _skill(skill: str, default: PlanSkill) -> PlanSkill:
    if skill in ("Average", "Good", "High", "Excellent", "Random"):
        return skill  # type: ignore[return-value]
    return default


def _units_at(
    group: str,
    tpl: forces.TemplateChoice,
    at: tuple[float, float],
    heading_deg: float,
    skill: str,
) -> list[PlanUnit]:
    h = math.radians(heading_deg)
    ch, sh = math.cos(h), math.sin(h)
    units = []
    for i, (typ, dx, dy, hd) in enumerate(tpl.units, start=1):
        rx = dx * ch - dy * sh
        ry = dx * sh + dy * ch
        units.append(
            PlanUnit(
                name=f"{group}-{i}",
                type=typ,
                x=round(at[0] + rx, 1),
                y=round(at[1] + ry, 1),
                heading_deg=round((math.degrees(hd) + heading_deg) % 360, 1) % 360,
                skill=_skill(skill, "Random"),
            )
        )
    return units


def _orbit_route(
    center: tuple[float, float], heading_deg: float, alt: float, speed: float
) -> list[PlanWaypoint]:
    h = math.radians(heading_deg)
    p2 = (center[0] + 30000 * math.cos(h), center[1] + 30000 * math.sin(h))
    return [
        PlanWaypoint(x=round(center[0], 1), y=round(center[1], 1), alt_m=alt, speed_kmh=speed),
        PlanWaypoint(x=round(p2[0], 1), y=round(p2[1], 1), alt_m=alt, speed_kmh=speed),
    ]


def _air_group(
    name: str,
    tpl: forces.TemplateChoice,
    coalition: str,
    country: str,
    task: str,
    center: tuple[float, float],
    rng: random.Random,
    hidden: bool,
    skill: str,
    source: str,
) -> PlanGroup:
    helo = tpl.category == "helicopter"
    alt = 300.0 if helo else (9000.0 if task in ("AWACS", "TANKER") else 6000.0)
    speed = 200.0 if helo else 600.0
    hdg = rng.uniform(0, 360)
    units = [
        PlanUnit(
            name=f"{name}-{i}",
            type=typ,
            x=round(center[0] - 100 * (i - 1), 1),
            y=round(center[1] + 100 * (i - 1), 1),
            alt_m=alt,
            heading_deg=round(hdg, 1) % 360,
            skill=_skill(skill, "High"),
        )
        for i, (typ, _dx, _dy, _h) in enumerate(tpl.units, start=1)
    ]
    return PlanGroup(
        name=name,
        category="helicopter" if helo else "plane",
        coalition=coalition,  # type: ignore[arg-type]
        country=country,
        task=task,
        units=units,
        route=_orbit_route(center, hdg, alt, speed),
        hidden=hidden,
        source=source,
    )


class _Planner:
    def __init__(
        self,
        spec: MissionSpec,
        seed: int,
        bible: StoryBible | None,
        extra_places: dict[str, tuple[float, float]] | None,
    ) -> None:
        self.spec = spec
        self.seed = seed
        self.rng = random.Random(seed)
        self.era = era_for_year(spec.era)
        self.factions = {
            k: (canonical_country(c) or c, side, u)
            for k, (c, side, u) in faction_map(bible).items()
        }
        self.blue = [canonical_country(c) or c for c in spec.blue_countries]
        self.red = [canonical_country(c) or c for c in spec.red_countries]
        areas, errors = resolve_areas(spec, extra_places)
        if errors:
            raise PlanError("; ".join(errors.values()))
        self.areas = areas
        self.names = _Names()
        self.groups: list[PlanGroup] = []
        self.fog = spec.dynamic.fog_of_war.enabled
        bases = [a.center for a in areas.values() if a.airbase]
        self.placer = _Placer(spec.theater, self.rng, bases)
        self.players_side = spec.player_flights[0].coalition
        self.enemy_side = "red" if self.players_side == "blue" else "blue"

    # -- helpers -------------------------------------------------------------------------
    def area(self, area_id: str) -> ResolvedArea:
        try:
            return self.areas[area_id]
        except KeyError:
            raise PlanError(f"unknown area '{area_id}' (run validate)") from None

    def side_countries(self, side: str) -> list[str]:
        if side == "blue":
            return list(self.blue)
        if side == "red":
            return list(self.red)
        return []

    def country_for(self, faction: str | None, side: str) -> str:
        """Pydcs country name for a faction on ``side`` (falls back to the side's first)."""
        if faction and faction in self.factions:
            fc, fcoal, _ = self.factions[faction]
            if fcoal == side and (fc in self.side_countries(side) or not self.side_countries(side)):
                return fc
            if fcoal == "neutral":
                return fc
        countries = self.side_countries(side)
        if not countries:
            raise PlanError(f"no {side} countries in spec")
        return countries[0]

    def choices(self, role: str, faction: str | None, strength: str) -> list[forces.TemplateChoice]:
        fac = self.factions.get(faction) if faction else None
        return forces.candidates(role, self.era, fac, faction, strength)

    # -- players -------------------------------------------------------------------------
    def plan_players(self) -> None:
        for i, f in enumerate(self.spec.player_flights, start=1):
            self.groups.append(self._player_group(f, i))

    def _player_group(self, f: PlayerFlight, idx: int) -> PlanGroup:
        area = self.area(f.start_area)
        ac = aircraft_type(f.aircraft)
        helo = bool(getattr(ac, "helicopter", False))
        name = self.names.alloc(f"{f.callsign} {idx}")
        payload, _choice = payload_for(f.aircraft, f.loadout)
        freq = f.frequency_mhz or float(getattr(ac, "radio_frequency", 0) or 0) or None
        if f.start_type != "air" and area.airbase:
            wp = PlanWaypoint(
                x=round(area.x, 1),
                y=round(area.y, 1),
                action=_START_ACTION[f.start_type],  # type: ignore[arg-type]
                airbase=area.airbase,
            )
            alt: float | None = None
        else:
            alt = 150.0 if helo else 3000.0
            wp = PlanWaypoint(
                x=round(area.x, 1), y=round(area.y, 1), alt_m=alt, speed_kmh=200 if helo else 500
            )
        units = [
            PlanUnit(
                name=f"{name}-{j}",
                type=f.aircraft,
                x=round(area.x + 30 * (j - 1), 1),
                y=round(area.y, 1),
                alt_m=alt,
                skill="Client",
                payload=payload,
            )
            for j in range(1, f.count + 1)
        ]
        return PlanGroup(
            name=name,
            category="helicopter" if helo else "plane",
            coalition=f.coalition,
            country=canonical_country(f.country) or f.country,
            task=self.spec.mission_type,
            units=units,
            route=[wp],
            frequency_mhz=freq,
            client=True,
            source=f.callsign if re.match(r"^[A-Za-z0-9][A-Za-z0-9_.\-]*$", f.callsign) else None,
        )

    # -- threats -------------------------------------------------------------------------
    def plan_threats(self) -> None:
        for t in self.spec.threats:
            self._threat(t)

    def _threat(self, t: Threat) -> None:
        choices = self.choices(t.role, t.faction, t.strength)
        if not choices:
            return  # validate reports roles without templates
        area = self.area(t.area)
        country = self.country_for(t.faction, self.enemy_side)
        hidden = bool(t.hidden_on_map and self.fog)
        n = forces.group_count(t.role, t.strength)
        for _ in range(n):
            tpl = forces.pick_for_strength(choices, t.strength, self.rng)
            name = self.names.alloc(
                f"{t.id}_{len([g for g in self.groups if g.source == t.id]) + 1}"
            )
            if tpl.category in ("plane", "helicopter"):
                task = "CAP" if t.role == "fighters" else "CAS"
                self.groups.append(
                    _air_group(
                        name,
                        tpl,
                        self.enemy_side,
                        country,
                        task,
                        area.center,
                        self.rng,
                        hidden,
                        t.skill,
                        t.id,
                    )
                )
                continue
            at = self.placer.place(area, t.role)
            hdg = round(self.rng.uniform(0, 360), 1) % 360
            self.groups.append(
                PlanGroup(
                    name=name,
                    category="vehicle",
                    coalition=self.enemy_side,  # type: ignore[arg-type]
                    country=country,
                    units=_units_at(name, tpl, at, hdg, t.skill),
                    hidden=hidden,
                    source=t.id,
                )
            )
        if t.strength == "heavy" and t.role in ("sam_medium", "sam_long"):
            escort = self.choices("sam_short", t.faction, "medium")
            if escort:
                tpl = forces.pick_for_strength(escort, "medium", self.rng)
                name = self.names.alloc(f"{t.id}_pd")
                at = self.placer.place(area, "sam_short")
                self.groups.append(
                    PlanGroup(
                        name=name,
                        category="vehicle",
                        coalition=self.enemy_side,  # type: ignore[arg-type]
                        country=country,
                        units=_units_at(name, tpl, at, self.rng.uniform(0, 359), t.skill),
                        hidden=hidden,
                        source=t.id,
                    )
                )

    # -- objectives ----------------------------------------------------------------------
    def plan_objectives(self) -> None:
        threat_ids = {t.id for t in self.spec.threats}
        for o in self.spec.objectives:
            if o.kind != "destroy" or not o.area or (o.target and o.target in threat_ids):
                continue
            choices = self.choices("hvt", None, "medium")
            if not choices:
                continue
            tpl = forces.pick_for_strength(choices, "medium", self.rng)
            area = self.area(o.area)
            name = self.names.alloc(f"{o.target or o.id}_1")
            at = self.placer.place(area, "hvt")
            self.groups.append(
                PlanGroup(
                    name=name,
                    category="vehicle",
                    coalition=self.enemy_side,  # type: ignore[arg-type]
                    country=self.country_for(None, self.enemy_side),
                    units=_units_at(name, tpl, at, self.rng.uniform(0, 359), "Good"),
                    hidden=self.fog,
                    source=o.id,
                )
            )

    # -- support -------------------------------------------------------------------------
    def plan_support(self) -> None:
        for s in self.spec.support:
            g = self._support(s)
            if g is not None:
                self.groups.append(g)

    def _player_base(self) -> tuple[float, float]:
        return self.area(self.spec.player_flights[0].start_area).center

    def _support(self, s: Support) -> PlanGroup | None:
        side = self.players_side
        country = self.side_countries(side)[0] if self.side_countries(side) else "USA"
        if s.role in _SUPPORT_AIR:
            tpl_id, task = _SUPPORT_AIR[s.role]
            from dms_core import catalog as cat

            t = cat.load_catalog().templates.get(tpl_id)
            if t is None:
                return None
            tpl = forces.TemplateChoice(
                t.id, t.category, [(u.type, u.dx, u.dy, u.heading) for u in t.units]
            )
            if s.area:
                center = self.area(s.area).center
            else:
                bx, by = self._player_base()
                tx, ty = self._objective_centroid()
                d = math.dist((bx, by), (tx, ty)) or 1.0
                center = (bx - (tx - bx) / d * 60000, by - (ty - by) / d * 60000)
            name = self.names.alloc(f"{s.id}_1")
            return _air_group(name, tpl, side, country, task, center, self.rng, False, "High", s.id)
        if s.role not in ("convoy", "friendly_ground", "jtac"):
            return None  # medevac / farp: not supported by the builder yet (validate warns)
        types, _bad = forces.parse_composition(s.composition)
        if not types:
            types = {
                "convoy": ["M 818", "M 818", "Hummer"],
                "jtac": ["Hummer"],
                "friendly_ground": ["Soldier M4", "Soldier M4", "Soldier M249"],
            }[s.role]
        start_id = s.route[0] if s.route else s.area
        if start_id is None:
            return None
        start = self.area(start_id)
        at = start.sample(self.rng, outer=0.3) if s.role != "convoy" else start.center
        tpl = forces.TemplateChoice(
            f"{s.id}_tpl", "ground", [(t, -25.0 * i, 0.0, 0.0) for i, t in enumerate(types)]
        )
        name = self.names.alloc(f"{s.id}_1")
        route = [
            PlanWaypoint(
                x=round(self.area(a).x, 1),
                y=round(self.area(a).y, 1),
                speed_kmh=40,
                action="On Road",
                name=a,
            )
            for a in s.route[1:]
        ]
        return PlanGroup(
            name=name,
            category="vehicle",
            coalition=side,
            country=country,
            units=_units_at(name, tpl, at, 0.0, "Good"),
            route=route,
            frequency_mhz=s.frequency_mhz,
            source=s.id,
        )

    def _objective_centroid(self) -> tuple[float, float]:
        pts = [self.area(o.area).center for o in self.spec.objectives if o.area]
        if not pts:
            return self._player_base()
        return (sum(p[0] for p in pts) / len(pts), sum(p[1] for p in pts) / len(pts))

    # -- zones ---------------------------------------------------------------------------
    def zones(self) -> tuple[list[PlanZone], dict[str, CircleZone | PolygonZone]]:
        plan_zones: list[PlanZone] = []
        rt: dict[str, CircleZone | PolygonZone] = {}
        for a in self.spec.areas:
            r = self.areas[a.id]
            if r.polygon and len(r.polygon) == 4:
                plan_zones.append(
                    PlanZone(
                        name=a.id,
                        kind="polygon",
                        points=[(round(x, 1), round(y, 1)) for x, y in r.polygon],
                    )
                )
            else:  # ME quads need exactly 4 points: other polygons get a bounding circle there
                plan_zones.append(
                    PlanZone(
                        name=a.id,
                        kind="circle",
                        x=round(r.x, 1),
                        y=round(r.y, 1),
                        radius_m=round(r.radius_m, 1),
                    )
                )
            if r.polygon:
                rt[a.id] = PolygonZone(
                    points=[XY(x=round(x, 1), y=round(y, 1)) for x, y in r.polygon]
                )
            else:
                rt[a.id] = CircleZone(x=round(r.x, 1), y=round(r.y, 1), radius=round(r.radius_m, 1))
        return plan_zones, rt

    # -- weather -------------------------------------------------------------------------
    def weather(self) -> PlanWeather:
        preset = dict(_WEATHER.get(self.spec.weather_preset, {}))
        calm = self.spec.weather_preset in ("clear", "night_clear", "fog")
        month = self.spec.date.month
        base_temp = {
            12: 8,
            1: 6,
            2: 8,
            3: 12,
            4: 16,
            5: 21,
            6: 26,
            7: 29,
            8: 29,
            9: 25,
            10: 19,
            11: 13,
        }
        return PlanWeather(
            wind_dir_deg=round(self.rng.uniform(0, 359), 0),
            wind_speed_mps=round(self.rng.uniform(0, 2) if calm else self.rng.uniform(2, 8), 1),
            temperature_c=float(base_temp.get(month, 20)),
            **preset,
        )

    # -- runtime -------------------------------------------------------------------------
    def convoy_route(
        self,
        pool_zones: Sequence[str],
        trigger_area: str | None,
        rt_zones: Mapping[str, CircleZone | PolygonZone],
    ) -> tuple[str | None, str | None]:
        """(spawn zone, destination) for a spec-level convoy encounter (see CONTRACTS).

        Spawn in the pool's first area; drive to its last area (2+ areas), else to the
        trigger area when it differs, else to the nearest road area outside the spawn area,
        else the nearest other area outside it. Destination is None when nothing qualifies.
        """
        if not pool_zones:
            return None, None
        start = pool_zones[0]
        if len(pool_zones) > 1 and pool_zones[-1] != start:
            return start, pool_zones[-1]
        if trigger_area and trigger_area != start and trigger_area in rt_zones:
            return start, trigger_area
        here = self.areas[start]
        terrain = {a.id: a.terrain for a in self.spec.areas}
        others = [
            a
            for a in rt_zones
            if a != start
            and a in self.areas
            and not here.contains(self.areas[a].center)
            and not self.areas[a].contains(here.center)
            and on_map(self.spec.theater, *self.areas[a].center)
        ]
        if not others:
            return start, None

        def dist(a: str) -> float:
            return math.dist(here.center, self.areas[a].center)

        roads = [a for a in others if terrain.get(a) == "road"]
        return start, min(roads or others, key=lambda a: (dist(a), a))

    def runtime(
        self,
        rt_zones: dict[str, CircleZone | PolygonZone],
        beats: list[Beat],
        voice: dict[str, VoiceEntry],
        debug: bool,
    ) -> RuntimeConfig:
        spec = self.spec
        templates: dict[str, Template] = {}
        pools: dict[str, Pool] = {}
        for p in spec.dynamic.pools:
            members: dict[str, float] = {}
            side = self.enemy_side
            if (
                p.faction
                and p.faction in self.factions
                and self.factions[p.faction][1] == "neutral"
            ):
                side = "neutral"
            country = self.country_for(p.faction, side)
            for role in p.roles:
                for tpl in self.choices(role, p.faction, "medium"):
                    if tpl.category not in ("ground", "plane", "helicopter", "ship"):
                        continue
                    templates.setdefault(
                        tpl.id,
                        Template(
                            country=country_key(country),
                            category="ground"
                            if tpl.category == "ground"
                            else ("ship" if tpl.category == "ship" else "air"),
                            skill=tpl.skill
                            if tpl.skill in ("Average", "Good", "High", "Excellent", "Random")
                            else "Random",  # type: ignore[arg-type]
                            units=[
                                TemplateUnit(type=u[0], dx=u[1], dy=u[2], heading=u[3])
                                for u in tpl.units
                            ],
                        ),
                    )
                    members[tpl.id] = max(members.get(tpl.id, 0.0), tpl.weight)
            zones = [
                a for a in p.areas if a in rt_zones and on_map(spec.theater, *self.areas[a].center)
            ]
            if not members or not zones:
                raise PlanError(f"pool '{p.id}' has no templates or no valid zones (run validate)")
            lo, hi = p.pick
            pools[p.id] = Pool(
                members=[PoolMember(tpl=k, w=v) for k, v in members.items()],
                pick=(min(lo, hi), max(lo, hi)),
                zones=zones,
            )
        encounters = []
        for e in spec.dynamic.encounters:
            tr = e.trigger
            spawn_zone, destination = (
                self.convoy_route(pools[e.pool].zones, tr.area, rt_zones)
                if e.kind == "convoy" and e.pool in pools
                else (None, None)
            )
            radius = (
                tr.radius_nm * NM if tr.radius_nm else (5 * NM if tr.type == "proximity" else None)
            )
            encounters.append(
                Encounter(
                    id=e.id,
                    kind=e.kind,
                    pool=e.pool,
                    trigger=EncounterTrigger(
                        type=tr.type,
                        zone=tr.area,
                        radius_m=round(radius, 1) if radius else None,
                        beat=tr.beat,
                        after_sec=tr.after_min * 60 if tr.after_min is not None else None,
                    ),
                    chance=e.chance,
                    telegraph=f"beat:{e.telegraph_beat}" if e.telegraph_beat else None,
                    hunt=e.hunt,
                    waves=(e.waves or 3) if e.kind == "waves" else e.waves,
                    gap_sec=(e.gap_min[0] * 60, e.gap_min[1] * 60) if e.gap_min else None,
                    spawn_zone=spawn_zone,
                    destination=destination,
                )
            )
        d = spec.dynamic.director
        peak, relax, spm = _INTENSITY[d.intensity]
        fow = spec.dynamic.fog_of_war
        return RuntimeConfig(
            seed=self.seed,
            debug=debug,
            mission_id=spec.id,
            budgets=Budgets(spawns_per_min=spm),
            director=Director(
                enabled=d.enabled,
                peak=peak,
                relax_sec=relax,
                adapt=Adapt(min=-1, max=1) if d.adaptive else Adapt(min=0, max=0),
            ),
            templates=templates,
            zones=dict(rt_zones),
            pools=pools,
            encounters=encounters,
            beats=beats,
            voice=voice,
            intel=Intel(
                fog_of_war=fow.enabled,
                reveal_radius_m=fow.reveal_radius_km * 1000,
                mark_refresh_sec=fow.mark_refresh_sec,
                stale_sec=fow.mark_refresh_sec * 8,
                known_groups=[
                    g.name
                    for g in self.groups
                    if g.source in {t.id for t in self.spec.threats if not t.hidden_on_map}
                    and not g.hidden
                    and g.category != "static"
                ]
                or None
                if fow.enabled
                else None,
            ),
            players=Players(coalition=2 if self.players_side == "blue" else 1),
        )


def _voice_file_optional() -> bool:
    return not VoiceEntry.model_fields["file"].is_required()


def _turns(raw: Any) -> list[VoiceTurn] | None:
    if not raw:
        return None
    out = []
    for t in raw:
        d = t if isinstance(t, Mapping) else getattr(t, "__dict__", {})
        if d.get("speaker") and d.get("text"):
            text = _AUDIO_TAG.sub("", str(d["text"])).strip()
            out.append(VoiceTurn(speaker=str(d["speaker"]), text=text))
    return out or None


def _voice_entry(
    file: str | None, text: str, dur: float, speaker: str, turns: list[VoiceTurn] | None
) -> VoiceEntry:
    if file is None and not _voice_file_optional():  # pragma: no cover - older dms-core schema
        file = ""  # subtitle-only marker until VoiceEntry.file is optional
    kw: dict[str, Any] = {"text": text, "dur_sec": dur, "speaker": speaker}
    if file is not None:
        kw["file"] = file
    if turns:
        kw["turns"] = turns
    return VoiceEntry(**kw)


def build_voice_map(
    lines: VoiceLineSet | None, manifest: dict[str, dict[str, Any]]
) -> dict[str, VoiceEntry]:
    """Line id -> VoiceEntry.

    Rendered lines (manifest entry with ``dur_sec``) get their file and real duration. Lines
    without rendered audio are subtitle-only: no ``file``, duration estimated from the text.
    """
    out: dict[str, VoiceEntry] = {}
    if lines is not None:
        for ln in lines.lines:
            m = manifest.get(ln.id, {})
            rendered = bool(m.get("dur_sec"))
            text = ln.subtitle or _AUDIO_TAG.sub("", ln.text).strip()
            dur = m.get("dur_sec") if rendered else (ln.dur_sec or placeholder_duration(ln.text))
            out[ln.id] = _voice_entry(
                str(m.get("file") or f"{ln.id}.ogg") if rendered else None,
                text,
                float(dur or placeholder_duration(ln.text)),
                ln.speaker,
                _turns(getattr(ln, "turns", None)),
            )
        return out
    for lid, m in sorted(manifest.items()):
        if not m.get("speaker"):
            continue
        rendered = bool(m.get("dur_sec"))
        out[lid] = _voice_entry(
            str(m.get("file") or f"{lid}.ogg") if rendered else None,
            _AUDIO_TAG.sub("", str(m.get("text", ""))).strip() or lid,
            float(m.get("dur_sec") or placeholder_duration(str(m.get("text", "")))),
            str(m["speaker"]),
            _turns(m.get("turns")),
        )
    return out


def build_speakers(
    spec: MissionSpec, bible: StoryBible | None, lines: VoiceLineSet | None
) -> dict[str, Speaker]:
    """Character id -> radio identity (callsign from the bible, frequency from support assets)."""
    chars = {c.id: c for c in bible.characters} if bible is not None else {}
    line_speakers = [ln.speaker for ln in lines.lines] if lines is not None else []
    ids = list(dict.fromkeys(list(spec.cast) + line_speakers))
    out: dict[str, Speaker] = {}
    for cid in ids:
        ch = chars.get(cid)
        sup = next((s for s in spec.support if s.speaker == cid), None)
        callsign = (ch.callsign or ch.name) if ch is not None else None
        callsign = callsign or (sup.callsign if sup is not None else None)
        if not callsign:
            continue
        freq = sup.frequency_mhz if sup is not None else None
        fm = sup is not None and sup.role in ("friendly_ground", "jtac", "convoy", "medevac")
        out[cid] = Speaker(
            callsign=callsign,
            frequency=freq,
            modulation=(1 if fm else 0) if freq else None,
        )
    return out


def plan_mission(
    spec: MissionSpec,
    beats: BeatSheet | list[Beat] | None = None,
    lines: VoiceLineSet | None = None,
    voice_manifest: Manifest | str | os.PathLike[str] | None = None,
    seed: int | None = None,
    *,
    bible: StoryBible | None = None,
    dms_lua: str = "dist/dms.lua",
    plugins: Sequence[str] = (),
    voice_dir: str | os.PathLike[str] | None = None,
    debug: bool = False,
    extra_places: dict[str, tuple[float, float]] | None = None,
    config_source: str = "dms_config.lua",
    qualities: Mapping[str, float] | None = None,
) -> BuildPlan:
    """Plan ``spec`` into an exact, seeded :class:`BuildPlan` with ``plan.runtime`` populated.

    Script order is plugins -> ``dms_config.lua`` -> ``dms.lua``. Resource ``source`` paths
    are relative to the ``base_dir`` later given to ``build_from_plan`` unless absolute. Call
    :func:`write_runtime_config` (writes ``plan.runtime`` to the ``dms_config.lua`` source)
    before building. Lines without rendered audio become subtitle-only voice entries.
    Raises :class:`PlanError` when the spec cannot be resolved (run ``validate`` first).
    """
    s = resolve_seed(spec, seed)
    p = _Planner(spec, s, bible, extra_places)
    p.plan_players()
    p.plan_support()
    p.plan_threats()
    p.plan_objectives()
    plan_zones, rt_zones = p.zones()

    beat_list = (beats.beats if isinstance(beats, BeatSheet) else list(beats)) if beats else []
    manifest, mdir = load_manifest(voice_manifest)
    sound_dir = Path(voice_dir) if voice_dir is not None else mdir
    voice = build_voice_map(lines, manifest)
    runtime = p.runtime(rt_zones, beat_list, voice, debug)
    runtime.speakers = build_speakers(spec, bible, lines)
    if qualities:
        runtime.qualities = {str(k): float(v) for k, v in qualities.items()}

    resources: list[PlanResource] = []
    for plug in plugins:
        resources.append(
            PlanResource(path=f"l10n/DEFAULT/{Path(plug).name}", source=str(plug), kind="script")
        )
    resources.append(
        PlanResource(path="l10n/DEFAULT/dms_config.lua", source=config_source, kind="script")
    )
    resources.append(PlanResource(path="l10n/DEFAULT/dms.lua", source=dms_lua, kind="script"))
    for v in voice.values():
        if not v.file:
            continue  # subtitle-only: nothing to embed
        src = (sound_dir / v.file) if sound_dir is not None else Path(v.file)
        resources.append(PlanResource(path=f"l10n/DEFAULT/{v.file}", source=str(src), kind="sound"))

    h, m = (int(x) for x in spec.start_time.split(":"))
    prim = [o for o in spec.objectives if o.primary]
    sec = [o for o in spec.objectives if not o.primary]
    task_lines = [f"- {o.description}" for o in prim]
    if sec:
        task_lines += ["", "Secondary:"] + [f"- {o.description}" for o in sec]
    return BuildPlan(
        mission_id=spec.id,
        seed=s,
        theater=spec.theater,
        date=spec.date,
        start_time_sec=h * 3600 + m * 60,
        weather=p.weather(),
        blue_countries=p.blue,
        red_countries=p.red,
        groups=p.groups,
        zones=plan_zones,
        triggers=[],
        resources=resources,
        briefing=PlanBriefing(
            title=spec.title,
            description=f"{spec.title} ({spec.mission_type}).",
            blue_task="\n".join(task_lines),
        ),
        options=PlanOptions(fog_of_war_map=spec.dynamic.fog_of_war.enabled),
        runtime=runtime,
    )


def load_campaign_qualities(mission_dir: str | os.PathLike[str]) -> dict[str, float]:
    """Campaign quality values for ``plan_mission(qualities=...)``.

    Reads ``<mission_dir>/../../state/qualities.yaml`` (``campaigns/<slug>/missions/mNN-x`` ->
    ``campaigns/<slug>/state/qualities.yaml``), validated as :class:`Qualities`. Returns ``{}``
    when the file is absent (standalone missions). Raises ``ValueError`` if it is invalid.
    """
    path = Path(mission_dir) / ".." / ".." / "state" / "qualities.yaml"
    if not path.is_file():
        return {}
    raw = yaml.safe_load(path.read_text(encoding="utf-8")) or {}
    try:
        q = Qualities.model_validate(raw)
    except ValidationError as exc:
        raise ValueError(f"{path.resolve()}: invalid qualities file: {exc}") from exc
    return {str(k): float(v) for k, v in q.values.items()}


def write_runtime_config(plan: BuildPlan, base_dir: str | os.PathLike[str] | None = None) -> Path:
    """Write ``plan.runtime`` as Lua to the ``dms_config.lua`` resource's source path.

    Relative sources resolve against ``base_dir`` (default: cwd), the same directory later
    passed to ``build_from_plan``. Returns the written path.
    """
    if plan.runtime is None:
        raise PlanError("plan has no runtime config")
    res = next((r for r in plan.resources if Path(r.path).name == "dms_config.lua"), None)
    src = Path(res.source) if res is not None else Path("dms_config.lua")
    if not src.is_absolute():
        src = Path(base_dir or ".") / src
    src.parent.mkdir(parents=True, exist_ok=True)
    src.write_text(plan.runtime.to_lua_source() + "\n", encoding="utf-8")
    return src
