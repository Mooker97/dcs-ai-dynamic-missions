"""
Waypoint inspection functions for .miz files.

Functions for listing and inspecting waypoints in group routes.
"""

import re
from typing import Dict, List, Optional

from ..utils import patterns
from ..groups.list import find_group_by_name


# ============================================================================
# CORE INSPECTION FUNCTIONS
# ============================================================================

def list_waypoints(mission_content: str, group_name: str) -> List[Dict]:
    """
    List all waypoints for a group's route.

    Args:
        mission_content: Raw mission file content as string
        group_name: Name of the group to get waypoints for

    Returns:
        List of waypoint dicts with structure:
        [
            {
                "index": 1,
                "x": -50000.0,
                "y": 30000.0,
                "alt": 2000.0,
                "speed": 150.0,
                "action": "Turning Point",
                "type": "Turning Point",
                "alt_type": "BARO"
            },
            ...
        ]

    Raises:
        ValueError: If group not found or has no route

    Example:
        >>> waypoints = list_waypoints(content, "Fighter-1")
        >>> print(f"Group has {len(waypoints)} waypoints")
        >>> for wp in waypoints:
        >>>     print(f"WP{wp['index']}: ({wp['x']}, {wp['y']}) @ {wp['alt']}m")
    """
    # Find the group
    group_result = find_group_by_name(mission_content, group_name)
    if not group_result:
        raise ValueError(f"Group '{group_name}' not found in mission")

    group_content, group_start, group_end = group_result

    # Find route section in group
    route_match = patterns.ROUTE_SECTION_PATTERN_COMPILED.search(group_content)
    if not route_match:
        raise ValueError(f"Group '{group_name}' has no route section")

    route_content = route_match.group(1)

    # Find points section in route
    points_match = patterns.POINTS_SECTION_PATTERN_COMPILED.search(route_content)
    if not points_match:
        raise ValueError(f"Group '{group_name}' has no waypoints (empty route)")

    points_content = points_match.group(1)

    # Extract all waypoints
    waypoints = []
    for wp_match in patterns.WAYPOINT_BLOCK_PATTERN_COMPILED.finditer(points_content):
        wp_index = int(wp_match.group(1))
        wp_content = wp_match.group(2)

        # Extract waypoint fields
        waypoint = {
            "index": wp_index,
            "x": None,
            "y": None,
            "alt": None,
            "speed": None,
            "action": None,
            "type": None,
            "alt_type": None
        }

        # Extract position
        pos_match = patterns.POSITION_PATTERN_COMPILED.search(wp_content)
        if pos_match:
            waypoint["y"] = float(pos_match.group(1))
            waypoint["x"] = float(pos_match.group(2))

        # Extract altitude
        alt_match = patterns.ALT_PATTERN_COMPILED.search(wp_content)
        if alt_match:
            waypoint["alt"] = float(alt_match.group(1))

        # Extract speed
        speed_match = patterns.SPEED_PATTERN_COMPILED.search(wp_content)
        if speed_match:
            waypoint["speed"] = float(speed_match.group(1))

        # Extract action
        action_match = patterns.WAYPOINT_ACTION_PATTERN_COMPILED.search(wp_content)
        if action_match:
            waypoint["action"] = action_match.group(1)

        # Extract type (often same as action)
        type_match = re.search(r'\["type"\]\s*=\s*"([^"]+)"', wp_content)
        if type_match:
            waypoint["type"] = type_match.group(1)

        # Extract altitude type
        alt_type_match = re.search(r'\["alt_type"\]\s*=\s*"([^"]+)"', wp_content)
        if alt_type_match:
            waypoint["alt_type"] = alt_type_match.group(1)

        waypoints.append(waypoint)

    return waypoints


def get_waypoint_count(mission_content: str, group_name: str) -> int:
    """
    Get the number of waypoints in a group's route.

    Args:
        mission_content: Raw mission file content as string
        group_name: Name of the group

    Returns:
        Number of waypoints in the group's route

    Raises:
        ValueError: If group not found or has no route

    Example:
        >>> count = get_waypoint_count(content, "Fighter-1")
        >>> print(f"Group has {count} waypoints")
    """
    waypoints = list_waypoints(mission_content, group_name)
    return len(waypoints)


def get_waypoint_info(mission_content: str, group_name: str, waypoint_index: int) -> Dict:
    """
    Get detailed information about a specific waypoint.

    Args:
        mission_content: Raw mission file content as string
        group_name: Name of the group
        waypoint_index: Index of the waypoint (1-based)

    Returns:
        Dict containing waypoint information (same structure as list_waypoints items)

    Raises:
        ValueError: If group not found, has no route, or waypoint index doesn't exist

    Example:
        >>> wp = get_waypoint_info(content, "Fighter-1", 2)
        >>> print(f"WP2: {wp['action']} at ({wp['x']}, {wp['y']})")
    """
    waypoints = list_waypoints(mission_content, group_name)

    # Find the waypoint with matching index
    for wp in waypoints:
        if wp["index"] == waypoint_index:
            return wp

    raise ValueError(f"Waypoint {waypoint_index} not found in group '{group_name}'")


# ============================================================================
# CONVENIENCE WRAPPER FUNCTIONS
# ============================================================================

def list_waypoints_file(input_miz: str, group_name: str) -> List[Dict]:
    """
    List waypoints from a .miz file (convenience wrapper).

    Args:
        input_miz: Path to input .miz file
        group_name: Name of the group

    Returns:
        List of waypoint dicts

    Raises:
        FileNotFoundError: If input_miz doesn't exist
        ValueError: If group not found or has no route

    Example:
        >>> waypoints = list_waypoints_file("../miz-files/input/mission.miz", "Fighter-1")
        >>> for wp in waypoints:
        >>>     print(f"WP{wp['index']}: {wp['action']}")
    """
    from ..parsing.miz_parser import MizParser

    parser = MizParser(input_miz)
    parser.extract()
    content = parser.get_mission_content()

    return list_waypoints(content, group_name)


def get_waypoint_count_file(input_miz: str, group_name: str) -> int:
    """
    Get waypoint count from a .miz file (convenience wrapper).

    Args:
        input_miz: Path to input .miz file
        group_name: Name of the group

    Returns:
        Number of waypoints

    Raises:
        FileNotFoundError: If input_miz doesn't exist
        ValueError: If group not found or has no route

    Example:
        >>> count = get_waypoint_count_file("../miz-files/input/mission.miz", "Fighter-1")
        >>> print(f"{count} waypoints")
    """
    waypoints = list_waypoints_file(input_miz, group_name)
    return len(waypoints)


def get_waypoint_info_file(input_miz: str, group_name: str, waypoint_index: int) -> Dict:
    """
    Get waypoint info from a .miz file (convenience wrapper).

    Args:
        input_miz: Path to input .miz file
        group_name: Name of the group
        waypoint_index: Index of the waypoint

    Returns:
        Dict containing waypoint information

    Raises:
        FileNotFoundError: If input_miz doesn't exist
        ValueError: If group not found, has no route, or waypoint doesn't exist

    Example:
        >>> wp = get_waypoint_info_file("../miz-files/input/mission.miz", "Fighter-1", 2)
        >>> print(f"Waypoint 2: {wp['action']}")
    """
    waypoints = list_waypoints_file(input_miz, group_name)

    for wp in waypoints:
        if wp["index"] == waypoint_index:
            return wp

    raise ValueError(f"Waypoint {waypoint_index} not found in group '{group_name}'")
