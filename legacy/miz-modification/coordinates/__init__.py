"""
Coordinates Module

Operations for extracting and transforming coordinates:
- extract.py - Get coordinates from groups/units (read-only)
- transform.py - Coordinate transformations (lat/lon ↔ x/y)
"""

from .extract import (
    get_group_coordinates,
    get_unit_coordinates,
    get_all_positions,
    get_waypoint_coordinates,
    get_group_coordinates_file,
    get_unit_coordinates_file,
    get_all_positions_file,
    get_waypoint_coordinates_file,
)

__all__ = [
    "get_group_coordinates",
    "get_unit_coordinates",
    "get_all_positions",
    "get_waypoint_coordinates",
    "get_group_coordinates_file",
    "get_unit_coordinates_file",
    "get_all_positions_file",
    "get_waypoint_coordinates_file",
]
