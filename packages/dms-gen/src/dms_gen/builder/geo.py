"""Position helpers on top of pydcs terrain projections.

DCS map coordinates: ``x`` is north (metres), ``y`` is east (metres), relative to the
terrain's projection origin. pydcs carries the per-theater Transverse Mercator parameters, so
lat/lon conversion is exact enough for mission placement.

Land check limits: pydcs has no surface/elevation data. ``is_on_map`` only tests the theater's
playable bounds. Use DCS's ``land.getSurfaceType`` at runtime (the Lua side) for a real
LAND/WATER/ROAD test, or pass explicit water polygons to ``is_probably_land``.
"""

# mypy: disallow-untyped-calls=False

from __future__ import annotations

import random
from collections.abc import Sequence

from dcs import mapping
from dcs.terrain.terrain import Terrain

XY = tuple[float, float]


def latlon_to_xy(terrain: Terrain, lat: float, lon: float) -> XY:
    p = mapping.Point.from_latlng(mapping.LatLng(lat, lon), terrain)
    return (float(p.x), float(p.y))


def xy_to_latlon(terrain: Terrain, x: float, y: float) -> tuple[float, float]:
    ll = mapping.Point(x, y, terrain).latlng()
    return (float(ll.lat), float(ll.lng))


def point_in_polygon(pt: XY, poly: Sequence[XY]) -> bool:
    """Ray-casting point-in-polygon test (works for concave polygons)."""
    x, y = pt
    inside = False
    n = len(poly)
    j = n - 1
    for i in range(n):
        xi, yi = poly[i]
        xj, yj = poly[j]
        if (yi > y) != (yj > y) and x < (xj - xi) * (y - yi) / ((yj - yi) or 1e-12) + xi:
            inside = not inside
        j = i
    return inside


def random_point_in_polygon(poly: Sequence[XY], rng: random.Random, max_tries: int = 10_000) -> XY:
    """Uniform random point inside ``poly`` by rejection sampling its bounding box."""
    if len(poly) < 3:
        raise ValueError("polygon needs at least 3 points")
    xs = [p[0] for p in poly]
    ys = [p[1] for p in poly]
    for _ in range(max_tries):
        cand = (rng.uniform(min(xs), max(xs)), rng.uniform(min(ys), max(ys)))
        if point_in_polygon(cand, poly):
            return cand
    raise RuntimeError("could not sample a point in polygon (degenerate?)")


def is_on_map(terrain: Terrain, x: float, y: float) -> bool:
    """True if (x, y) is inside the theater's bounds rectangle.

    pydcs terrains are inconsistent about which of top/bottom is larger, so normalise.
    """
    b = terrain.bounds
    x0, x1 = sorted((float(b.top), float(b.bottom)))
    y0, y1 = sorted((float(b.left), float(b.right)))
    return x0 <= x <= x1 and y0 <= y <= y1


def is_probably_land(
    terrain: Terrain, x: float, y: float, water: Sequence[Sequence[XY]] = ()
) -> bool:
    """On the map and not inside any of the given water polygons. See module docs for limits."""
    if not is_on_map(terrain, x, y):
        return False
    return not any(point_in_polygon((x, y), poly) for poly in water)
