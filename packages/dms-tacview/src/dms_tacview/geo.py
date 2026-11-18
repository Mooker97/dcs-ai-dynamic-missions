"""Small geodesy helpers (spherical Earth; good to a few metres over tactical distances)."""

from __future__ import annotations

import math

__all__ = ["EARTH_RADIUS_M", "ground_distance_m", "slant_distance_m"]

EARTH_RADIUS_M = 6_371_008.8


def ground_distance_m(lon1: float, lat1: float, lon2: float, lat2: float) -> float:
    """Great-circle (haversine) distance in metres."""
    p1, p2 = math.radians(lat1), math.radians(lat2)
    dp = p2 - p1
    dl = math.radians(lon2 - lon1)
    a = math.sin(dp / 2) ** 2 + math.cos(p1) * math.cos(p2) * math.sin(dl / 2) ** 2
    return 2 * EARTH_RADIUS_M * math.asin(min(1.0, math.sqrt(a)))


def slant_distance_m(
    lon1: float, lat1: float, alt1: float, lon2: float, lat2: float, alt2: float
) -> float:
    """3-D distance in metres (ground distance combined with the altitude difference)."""
    g = ground_distance_m(lon1, lat1, lon2, lat2)
    return math.hypot(g, alt2 - alt1)
