"""Shared planning context: terrain, eras, area resolution (spec areas -> DCS x/y shapes)."""

# mypy: disallow-untyped-calls=False

from __future__ import annotations

import math
import random
from dataclasses import dataclass, field
from functools import lru_cache

from dcs.terrain.terrain import Terrain
from dms_core import catalog as cat
from dms_core.schemas.mission import (
    Area,
    LatLonArea,
    MissionSpec,
    NearAirbase,
    NearNamedPlace,
    PolygonArea,
)
from dms_core.schemas.story import StoryBible

from ..builder import geo
from ..builder.mission import terrain_by_name
from . import places

NM = 1852.0
XY = tuple[float, float]


class PlanError(ValueError):
    """The spec cannot be planned (run ``validate`` for details and suggestions)."""


@lru_cache(maxsize=16)
def terrain_for(theater: str) -> Terrain:
    """Cached pydcs terrain instance."""
    return terrain_by_name("Germany" if theater == "GermanyCW" else theater)


def era_for_year(year: int) -> str | None:
    """Catalog era id covering ``year`` (None if no era matches)."""
    for era in cat.load_catalog().eras.values():
        lo, hi = era.years
        if lo <= year <= hi:
            return era.id
    return None


def airbase_names(theater: str) -> list[str]:
    return [a.name for a in cat.find_airbases(theater)]


def find_airbase(theater: str, name: str) -> cat.Airbase | None:
    """Exact (case-insensitive) airbase match; no fuzzy fallback."""
    low = name.strip().lower()
    for a in cat.find_airbases(theater):
        if a.name.lower() == low:
            return a
    return None


@dataclass
class ResolvedArea:
    """A spec area in DCS map metres."""

    id: str
    kind: str  # near_airbase | near_named_place | latlon | zone
    x: float
    y: float
    radius_m: float
    polygon: list[XY] = field(default_factory=list)
    terrain_hint: str = "any"
    airbase: str | None = None
    place_center: XY | None = None  # town centre (near_named_place) for SAM offsets

    @property
    def center(self) -> XY:
        return (self.x, self.y)

    def contains(self, pt: XY) -> bool:
        if self.polygon:
            return geo.point_in_polygon(pt, self.polygon)
        return math.dist(pt, self.center) <= self.radius_m

    def sample(self, rng: random.Random, inner: float = 0.0, outer: float = 1.0) -> XY:
        """Random point inside the area (annulus fraction ``inner``..``outer`` for circles)."""
        if self.polygon:
            return geo.random_point_in_polygon(self.polygon, rng)
        r = self.radius_m * math.sqrt(rng.uniform(inner * inner, outer * outer))
        a = rng.uniform(0, 2 * math.pi)
        return (self.x + r * math.cos(a), self.y + r * math.sin(a))


def _offset(x: float, y: float, bearing: float | None, dist_nm: float | None) -> XY:
    if bearing is None or not dist_nm:
        return (x, y)
    b = math.radians(bearing)
    d = dist_nm * NM
    return (x + d * math.cos(b), y + d * math.sin(b))


def resolve_area(
    theater: str, area: Area, extra_places: dict[str, tuple[float, float]] | None = None
) -> ResolvedArea:
    """Resolve ``area`` to DCS x/y. Raises PlanError (with suggestions) if it cannot."""
    terrain = terrain_for(theater)
    w = area.where
    if isinstance(w, NearAirbase):
        ab = find_airbase(theater, w.airbase)
        if ab is None:
            sugg = cat.suggest(w.airbase, "airbase", theater=theater, n=3)
            raise PlanError(
                f"area '{area.id}': unknown airbase '{w.airbase}'; did you mean {sugg}?"
            )
        x, y = _offset(ab.x, ab.y, w.bearing_deg, w.distance_nm)
        return ResolvedArea(area.id, w.kind, x, y, w.radius_nm * NM, [], area.terrain, ab.name)
    if isinstance(w, NearNamedPlace):
        ll = places.find_place(theater, w.place, extra_places)
        if ll is not None:
            cx, cy = geo.latlon_to_xy(terrain, *ll)
        else:
            ab = find_airbase(theater, w.place)
            if ab is None:
                sugg = places.suggest_place(theater, w.place, airbase_names(theater))
                raise PlanError(
                    f"area '{area.id}': unknown place '{w.place}' on {theater}; "
                    f"did you mean {sugg}?"
                )
            cx, cy = ab.x, ab.y
        x, y = _offset(cx, cy, w.bearing_deg, w.distance_nm)
        return ResolvedArea(
            area.id, w.kind, x, y, w.radius_nm * NM, [], area.terrain, place_center=(cx, cy)
        )
    if isinstance(w, LatLonArea):
        x, y = geo.latlon_to_xy(terrain, w.lat, w.lon)
        return ResolvedArea(area.id, w.kind, x, y, w.radius_nm * NM, [], area.terrain)
    assert isinstance(w, PolygonArea)
    poly = [geo.latlon_to_xy(terrain, p.lat, p.lon) for p in w.points]
    cx = sum(p[0] for p in poly) / len(poly)
    cy = sum(p[1] for p in poly) / len(poly)
    radius = max(math.dist((cx, cy), p) for p in poly)
    return ResolvedArea(area.id, w.kind, cx, cy, radius, poly, area.terrain)


def resolve_areas(
    spec: MissionSpec, extra_places: dict[str, tuple[float, float]] | None = None
) -> tuple[dict[str, ResolvedArea], dict[str, str]]:
    """All spec areas -> (resolved by id, error message by id)."""
    out: dict[str, ResolvedArea] = {}
    errors: dict[str, str] = {}
    for a in spec.areas:
        try:
            out[a.id] = resolve_area(spec.theater, a, extra_places)
        except PlanError as exc:
            errors[a.id] = str(exc)
    return out, errors


def on_map(theater: str, x: float, y: float) -> bool:
    return geo.is_on_map(terrain_for(theater), x, y)


def faction_map(bible: StoryBible | None) -> dict[str, tuple[str, str, list[str]]]:
    """Bible faction id -> (country, coalition, unit types)."""
    if bible is None:
        return {}
    return {f.id: (f.dcs.country, f.dcs.coalition, list(f.dcs.units)) for f in bible.factions}


_LUA_KEY_OVERRIDES = {
    "Combined Joint Task Forces Blue": "CJTF_BLUE",
    "Combined Joint Task Forces Red": "CJTF_RED",
    "United Nations Peacekeepers": "UN_PEACEKEEPERS",
    "Third Reich": "THIRDREICH",
}


def _norm_country(s: str) -> str:
    return "".join(ch for ch in s.lower() if ch.isalnum())


@lru_cache(maxsize=1)
def _country_aliases() -> dict[str, str]:
    from dcs import countries

    out: dict[str, str] = {}
    for cls in countries.country_dict.values():
        name = str(cls.name)  # type: ignore[misc]
        for alias in (
            name,
            cls.__name__,
            str(getattr(cls, "shortname", "") or ""),
            _LUA_KEY_OVERRIDES.get(name, name.upper().replace(" ", "_")),
        ):
            if alias:
                out.setdefault(_norm_country(alias), name)
    for key, lua in _LUA_KEY_OVERRIDES.items():
        out[_norm_country(lua.replace("_", " "))] = key
    return out


def canonical_country(name: str) -> str | None:
    """pydcs country name for ``name`` or an alias ('CJTF Red', 'CJTF_RED', 'RED'), else None."""
    return _country_aliases().get(_norm_country(name))


def country_names() -> list[str]:
    return sorted(set(_country_aliases().values()))


def country_key(name: str) -> str:
    """Country name/alias -> Lua ``country.id`` key ('CJTF Red' -> 'CJTF_RED')."""
    canon = canonical_country(name) or name.strip()
    return _LUA_KEY_OVERRIDES.get(canon, canon.upper().replace(" ", "_").replace("-", "_"))
