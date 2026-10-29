"""Named locations per BeamNG level, so authored YAML never carries raw coordinates.

Coordinates are BeamNG world metres ``(x, y, z)`` and a heading in degrees (0 = +Y, clockwise).
Only entries with ``verified=True`` come from a source we checked; the rest are placeholders
to be replaced with points read in-game (``core_camera`` / MCP ``get_position``) [?].
"""

from __future__ import annotations

from dataclasses import dataclass

__all__ = ["LOCATIONS", "Location", "known_levels", "lookup"]


@dataclass(frozen=True)
class Location:
    """A named spot on a level."""

    pos: tuple[float, float, float]
    heading_deg: float = 0.0
    verified: bool = False
    note: str = ""


#: level -> name -> Location.
LOCATIONS: dict[str, dict[str, Location]] = {
    "west_coast_usa": {
        # From the BeamNGpy README example (pos=(-717, 101, 118)).
        "docs_spawn": Location((-717.0, 101.0, 118.0), 45.0, True, "BeamNGpy README spawn"),
        # Placeholders [?]: rough areas, not yet read in-game.
        "downtown_bank": Location((-780.0, 40.0, 118.0), 90.0, False, "downtown block"),
        "harbour_warehouse": Location((-430.0, -520.0, 101.0), 0.0, False, "harbour"),
        "hillside_garage": Location((560.0, -360.0, 145.0), 180.0, False, "hills"),
        "industrial_yard": Location((-200.0, 660.0, 110.0), 270.0, False, "industrial"),
        "freeway_onramp": Location((120.0, -80.0, 118.0), 0.0, False, "freeway"),
        "suburb_cul_de_sac": Location((740.0, 260.0, 130.0), 90.0, False, "suburbs"),
    },
    "italy": {
        "town_square": Location((0.0, 0.0, 0.0), 0.0, False, "placeholder"),
        "coast_villa": Location((500.0, 500.0, 0.0), 0.0, False, "placeholder"),
    },
}


def known_levels() -> tuple[str, ...]:
    """Levels that have a location table."""
    return tuple(LOCATIONS)


def lookup(level: str, name: str) -> Location:
    """Resolve ``name`` on ``level``; raises ``KeyError`` with the valid names."""
    table = LOCATIONS.get(level)
    if table is None:
        raise KeyError(f"no location table for level {level!r} (known: {sorted(LOCATIONS)})")
    if name not in table:
        raise KeyError(f"unknown location {name!r} on {level} (known: {sorted(table)})")
    return table[name]
