"""Small typed inputs for the builder. Kept independent of dms_core.schemas on purpose."""

from __future__ import annotations

from dataclasses import dataclass
from typing import Literal

Coalition = Literal["blue", "red", "neutrals"]
StartKind = Literal["cold", "hot", "runway", "air"]
AiTask = Literal["cap", "cas", "awacs", "tanker"]
WeatherPreset = Literal["clear", "scattered", "overcast", "rain", "dust"]
MapView = Literal["map_only", "my_aircraft", "fog_of_war", "allies_only", "all"]
Skill = Literal["Average", "Good", "High", "Excellent", "Random"]

XY = tuple[float, float]


@dataclass(frozen=True)
class UnitSpec:
    """One unit in a ground/ship group.

    ``dx``/``dy`` are metre offsets from the group origin; ``heading`` is in degrees.
    """

    type: str
    dx: float = 0.0
    dy: float = 0.0
    heading: float = 0.0
    name: str | None = None


@dataclass(frozen=True)
class GroundWaypoint:
    """Ground route point. ``speed`` is km/h (pydcs convention)."""

    x: float
    y: float
    speed: float = 30.0
    on_road: bool = True


UnitLike = UnitSpec | tuple[str, float, float, float]
WaypointLike = GroundWaypoint | tuple[float, float, float, bool]


def as_unit(u: UnitLike) -> UnitSpec:
    if isinstance(u, UnitSpec):
        return u
    t, dx, dy, hdg = u
    return UnitSpec(type=t, dx=float(dx), dy=float(dy), heading=float(hdg))


def as_waypoint(w: WaypointLike) -> GroundWaypoint:
    if isinstance(w, GroundWaypoint):
        return w
    x, y, speed, on_road = w
    return GroundWaypoint(x=float(x), y=float(y), speed=float(speed), on_road=bool(on_road))
