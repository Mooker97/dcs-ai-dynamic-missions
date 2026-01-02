"""
Waypoints Module

Operations for managing group waypoints and routes:
- list.py - List waypoints (read-only)
- add.py - Add waypoints to routes
- remove.py - Remove waypoints
- modify.py - Modify waypoint properties (position, speed, altitude)
"""

# List operations
from .list import (
    list_waypoints,
    get_waypoint_count,
    get_waypoint_info,
    list_waypoints_file,
    get_waypoint_count_file,
    get_waypoint_info_file,
)

# Add operations
from .add import (
    add_waypoint,
    add_multiple_waypoints,
    add_waypoint_file,
    add_multiple_waypoints_file,
)

# Remove operations
from .remove import (
    remove_waypoint,
    clear_route,
    remove_waypoints_after,
    remove_waypoint_file,
    clear_route_file,
    remove_waypoints_after_file,
)

# Modify operations
from .modify import (
    modify_waypoint,
    modify_waypoint_position,
    modify_waypoint_speed,
    modify_waypoint_altitude,
    modify_waypoint_action,
    modify_waypoint_file,
    modify_waypoint_position_file,
    modify_waypoint_speed_file,
    modify_waypoint_altitude_file,
    modify_waypoint_action_file,
)

__all__ = [
    # List
    "list_waypoints",
    "get_waypoint_count",
    "get_waypoint_info",
    "list_waypoints_file",
    "get_waypoint_count_file",
    "get_waypoint_info_file",
    # Add
    "add_waypoint",
    "add_multiple_waypoints",
    "add_waypoint_file",
    "add_multiple_waypoints_file",
    # Remove
    "remove_waypoint",
    "clear_route",
    "remove_waypoints_after",
    "remove_waypoint_file",
    "clear_route_file",
    "remove_waypoints_after_file",
    # Modify
    "modify_waypoint",
    "modify_waypoint_position",
    "modify_waypoint_speed",
    "modify_waypoint_altitude",
    "modify_waypoint_action",
    "modify_waypoint_file",
    "modify_waypoint_position_file",
    "modify_waypoint_speed_file",
    "modify_waypoint_altitude_file",
    "modify_waypoint_action_file",
]
