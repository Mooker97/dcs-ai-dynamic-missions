"""
Coordinate extraction functions for .miz files.

Read-only functions for extracting positions and coordinates from groups and units.
"""

import re
from typing import Dict, List, Optional, Any
from pathlib import Path

from ..utils import patterns, validation
from ..core import UNIT_TYPES


# ============================================================================
# CORE EXTRACTION FUNCTIONS
# ============================================================================

def get_group_coordinates(mission_content: str, group_name: str) -> Dict[str, float]:
    """
    Get coordinates of a group (first unit's position).

    Args:
        mission_content: Raw mission file content as string
        group_name: Name of the group to find

    Returns:
        Dictionary with coordinates:
        {"x": float, "y": float, "alt": float (if available)}

    Raises:
        ValueError: If group not found in mission

    Example:
        >>> coords = get_group_coordinates(content, "Fighter-1")
        >>> print(f"Position: x={coords['x']}, y={coords['y']}")
    """
    # Find the group name in the content
    name_pattern = rf'\["name"\]\s*=\s*"{re.escape(group_name)}"'
    name_match = re.search(name_pattern, mission_content)

    if not name_match:
        raise ValueError(f"Group '{group_name}' not found in mission")

    # Search backwards from the name match to find the group start
    # Then search forward to find coordinates in the units section
    group_start_pos = name_match.start()

    # Look backwards to find the beginning of this group block (find nearest "[n] = {")
    search_start = max(0, group_start_pos - 5000)
    preceding_content = mission_content[search_start:group_start_pos]

    # Find the last group index pattern before the name
    group_starts = list(re.finditer(r'\[(\d+)\]\s*=\s*\{', preceding_content))
    if not group_starts:
        raise ValueError(f"Could not find group block for '{group_name}'")

    # Get position of last group start relative to full content
    last_start = group_starts[-1]
    actual_group_start = search_start + last_start.start()

    # Extract a reasonable chunk containing the group (up to next group or 10KB)
    group_content = mission_content[actual_group_start:actual_group_start + 10000]

    # Find units section within this group
    units_match = patterns.UNITS_SECTION_PATTERN_COMPILED.search(group_content)
    if units_match:
        # Get coordinates from units section
        units_content = units_match.group(1)
        x_match = patterns.X_COORD_PATTERN_COMPILED.search(units_content)
        y_match = patterns.Y_COORD_PATTERN_COMPILED.search(units_content)
        alt_match = patterns.ALT_PATTERN_COMPILED.search(units_content)
    else:
        # Fall back to searching the whole group content
        x_match = patterns.X_COORD_PATTERN_COMPILED.search(group_content)
        y_match = patterns.Y_COORD_PATTERN_COMPILED.search(group_content)
        alt_match = patterns.ALT_PATTERN_COMPILED.search(group_content)

    coords = {}
    if x_match:
        coords["x"] = float(x_match.group(1))
    if y_match:
        coords["y"] = float(y_match.group(1))
    if alt_match:
        coords["alt"] = float(alt_match.group(1))

    if "x" not in coords or "y" not in coords:
        raise ValueError(f"Could not extract coordinates from group '{group_name}'")

    return coords


def get_unit_coordinates(mission_content: str, unit_name: str) -> Dict[str, float]:
    """
    Get coordinates of a specific unit.

    Args:
        mission_content: Raw mission file content as string
        unit_name: Name of the unit to find

    Returns:
        Dictionary with coordinates:
        {"x": float, "y": float, "alt": float (if available)}

    Raises:
        ValueError: If unit not found in mission

    Example:
        >>> coords = get_unit_coordinates(content, "Pilot #001")
        >>> print(f"Unit at: x={coords['x']}, y={coords['y']}, alt={coords.get('alt', 'N/A')}")
    """
    # Find unit by name
    name_pattern = rf'\["name"\]\s*=\s*"{re.escape(unit_name)}"'
    name_match = re.search(name_pattern, mission_content)

    if not name_match:
        raise ValueError(f"Unit '{unit_name}' not found in mission")

    # Get surrounding content - coordinates are typically nearby
    # Search 1000 chars before and 500 chars after the name
    search_start = max(0, name_match.start() - 1000)
    search_end = min(len(mission_content), name_match.end() + 500)
    unit_content = mission_content[search_start:search_end]

    # Extract coordinates - find the ones closest to the name
    coords = {}

    # Get x coordinate (find the last one before name position in unit_content)
    x_matches = list(patterns.X_COORD_PATTERN_COMPILED.finditer(unit_content))
    if x_matches:
        # Use the one closest to the name match position
        name_pos_in_content = name_match.start() - search_start
        closest_x = min(x_matches, key=lambda m: abs(m.start() - name_pos_in_content))
        coords["x"] = float(closest_x.group(1))

    # Get y coordinate
    y_matches = list(patterns.Y_COORD_PATTERN_COMPILED.finditer(unit_content))
    if y_matches:
        name_pos_in_content = name_match.start() - search_start
        closest_y = min(y_matches, key=lambda m: abs(m.start() - name_pos_in_content))
        coords["y"] = float(closest_y.group(1))

    # Get altitude (optional)
    alt_matches = list(patterns.ALT_PATTERN_COMPILED.finditer(unit_content))
    if alt_matches:
        name_pos_in_content = name_match.start() - search_start
        closest_alt = min(alt_matches, key=lambda m: abs(m.start() - name_pos_in_content))
        coords["alt"] = float(closest_alt.group(1))

    if "x" not in coords or "y" not in coords:
        raise ValueError(f"Could not extract coordinates from unit '{unit_name}'")

    return coords


def get_all_positions(
    mission_content: str,
    coalition: Optional[str] = None,
    unit_type: Optional[str] = None
) -> Dict[str, Dict[str, Any]]:
    """
    Get positions of all groups, optionally filtered by coalition and/or unit type.

    Args:
        mission_content: Raw mission file content as string
        coalition: Optional coalition filter (blue, red, neutrals)
        unit_type: Optional unit type filter (plane, helicopter, ship, vehicle, static)

    Returns:
        Dictionary mapping group names to their coordinate info:
        {
            "GroupName": {
                "x": float,
                "y": float,
                "alt": float (if available),
                "coalition": str,
                "unit_type": str
            },
            ...
        }

    Raises:
        ValueError: If coalition or unit_type is invalid

    Example:
        >>> positions = get_all_positions(content, coalition="blue")
        >>> for name, pos in positions.items():
        >>>     print(f"{name}: x={pos['x']}, y={pos['y']}")
    """
    from ..core import find_context

    # Validate inputs
    if coalition is not None:
        is_valid, error = validation.validate_coalition(coalition)
        if not is_valid:
            raise ValueError(error)

    if unit_type is not None:
        is_valid, error = validation.validate_unit_type_category(unit_type)
        if not is_valid:
            raise ValueError(error)

    result = {}

    # Find all groups using GROUP_PATTERN which captures (units_content, group_name)
    group_matches = list(patterns.GROUP_PATTERN_COMPILED.finditer(mission_content))

    for match in group_matches:
        units_content = match.group(1)  # Units content is first capture group
        group_name = match.group(2)  # Group name is second capture group

        # Get context (coalition and unit_type) for this group
        context = find_context(mission_content, match.start())
        group_coalition = context.get('coalition')
        group_unit_type = context.get('unit_type')

        # Apply filters
        if coalition is not None and group_coalition != coalition:
            continue
        if unit_type is not None and group_unit_type != unit_type:
            continue

        # Get position from first unit
        x_match = patterns.X_COORD_PATTERN_COMPILED.search(units_content)
        y_match = patterns.Y_COORD_PATTERN_COMPILED.search(units_content)

        if x_match and y_match:
            group_info = {
                "x": float(x_match.group(1)),
                "y": float(y_match.group(1)),
                "coalition": group_coalition,
                "unit_type": group_unit_type
            }

            # Try to get altitude
            alt_match = patterns.ALT_PATTERN_COMPILED.search(units_content)
            if alt_match:
                group_info["alt"] = float(alt_match.group(1))

            result[group_name] = group_info

    return result


def get_waypoint_coordinates(
    mission_content: str,
    group_name: str,
    waypoint_index: int = 1
) -> Dict[str, float]:
    """
    Get coordinates of a specific waypoint for a group.

    Args:
        mission_content: Raw mission file content as string
        group_name: Name of the group
        waypoint_index: Index of the waypoint (1-based, default is first waypoint)

    Returns:
        Dictionary with waypoint coordinates:
        {"x": float, "y": float, "alt": float, "speed": float (if available)}

    Raises:
        ValueError: If group or waypoint not found

    Example:
        >>> wp = get_waypoint_coordinates(content, "Fighter-1", 2)
        >>> print(f"Waypoint 2: x={wp['x']}, y={wp['y']}, alt={wp['alt']}")
    """
    # Find the group
    group_pattern = rf'\[(\d+)\]\s*=\s*\{{[^}}]*?\["name"\]\s*=\s*"{re.escape(group_name)}".*?\}},\s*--'
    group_match = re.search(group_pattern, mission_content, re.DOTALL)

    if not group_match:
        raise ValueError(f"Group '{group_name}' not found in mission")

    group_content = group_match.group(0)

    # Find route section
    route_match = patterns.ROUTE_SECTION_PATTERN_COMPILED.search(group_content)
    if not route_match:
        raise ValueError(f"No route found for group '{group_name}'")

    route_content = route_match.group(1)

    # Find points section
    points_match = patterns.POINTS_SECTION_PATTERN_COMPILED.search(route_content)
    if not points_match:
        raise ValueError(f"No waypoints found for group '{group_name}'")

    points_content = points_match.group(1)

    # Find the specific waypoint
    waypoint_pattern = rf'\[{waypoint_index}\]\s*=\s*\{{(.*?)\}},'
    waypoint_match = re.search(waypoint_pattern, points_content, re.DOTALL)

    if not waypoint_match:
        raise ValueError(f"Waypoint {waypoint_index} not found for group '{group_name}'")

    waypoint_content = waypoint_match.group(1)

    # Extract coordinates
    coords = {}

    x_match = patterns.X_COORD_PATTERN_COMPILED.search(waypoint_content)
    if x_match:
        coords["x"] = float(x_match.group(1))

    y_match = patterns.Y_COORD_PATTERN_COMPILED.search(waypoint_content)
    if y_match:
        coords["y"] = float(y_match.group(1))

    alt_match = patterns.ALT_PATTERN_COMPILED.search(waypoint_content)
    if alt_match:
        coords["alt"] = float(alt_match.group(1))

    # Try to get speed
    speed_match = re.search(r'\["speed"\]\s*=\s*([+-]?\d+\.?\d*)', waypoint_content)
    if speed_match:
        coords["speed"] = float(speed_match.group(1))

    if "x" not in coords or "y" not in coords:
        raise ValueError(f"Could not extract coordinates from waypoint {waypoint_index}")

    return coords


# ============================================================================
# CONVENIENCE WRAPPER FUNCTIONS
# ============================================================================

def get_group_coordinates_file(input_miz: str, group_name: str) -> Dict[str, float]:
    """
    Get group coordinates from a .miz file (convenience wrapper).

    Args:
        input_miz: Path to input .miz file
        group_name: Name of the group to find

    Returns:
        Dictionary with coordinates

    Raises:
        FileNotFoundError: If input_miz doesn't exist
        ValueError: If group not found

    Example:
        >>> coords = get_group_coordinates_file("mission.miz", "Fighter-1")
        >>> print(f"Position: {coords}")
    """
    from ..parsing.miz_parser import MizParser

    if not Path(input_miz).exists():
        raise FileNotFoundError(f"Input .miz file not found: {input_miz}")

    parser = MizParser(input_miz)
    parser.extract()

    try:
        content = parser.get_mission_content()
        return get_group_coordinates(content, group_name)
    finally:
        parser.cleanup()


def get_unit_coordinates_file(input_miz: str, unit_name: str) -> Dict[str, float]:
    """
    Get unit coordinates from a .miz file (convenience wrapper).

    Args:
        input_miz: Path to input .miz file
        unit_name: Name of the unit to find

    Returns:
        Dictionary with coordinates

    Raises:
        FileNotFoundError: If input_miz doesn't exist
        ValueError: If unit not found

    Example:
        >>> coords = get_unit_coordinates_file("mission.miz", "Pilot #001")
        >>> print(f"Position: {coords}")
    """
    from ..parsing.miz_parser import MizParser

    if not Path(input_miz).exists():
        raise FileNotFoundError(f"Input .miz file not found: {input_miz}")

    parser = MizParser(input_miz)
    parser.extract()

    try:
        content = parser.get_mission_content()
        return get_unit_coordinates(content, unit_name)
    finally:
        parser.cleanup()


def get_all_positions_file(
    input_miz: str,
    coalition: Optional[str] = None,
    unit_type: Optional[str] = None
) -> Dict[str, Dict[str, Any]]:
    """
    Get all group positions from a .miz file (convenience wrapper).

    Args:
        input_miz: Path to input .miz file
        coalition: Optional coalition filter
        unit_type: Optional unit type filter

    Returns:
        Dictionary mapping group names to coordinate info

    Raises:
        FileNotFoundError: If input_miz doesn't exist

    Example:
        >>> positions = get_all_positions_file("mission.miz", coalition="blue")
        >>> for name, pos in positions.items():
        >>>     print(f"{name}: x={pos['x']}, y={pos['y']}")
    """
    from ..parsing.miz_parser import MizParser

    if not Path(input_miz).exists():
        raise FileNotFoundError(f"Input .miz file not found: {input_miz}")

    parser = MizParser(input_miz)
    parser.extract()

    try:
        content = parser.get_mission_content()
        return get_all_positions(content, coalition, unit_type)
    finally:
        parser.cleanup()


def get_waypoint_coordinates_file(
    input_miz: str,
    group_name: str,
    waypoint_index: int = 1
) -> Dict[str, float]:
    """
    Get waypoint coordinates from a .miz file (convenience wrapper).

    Args:
        input_miz: Path to input .miz file
        group_name: Name of the group
        waypoint_index: Index of the waypoint (1-based)

    Returns:
        Dictionary with waypoint coordinates

    Raises:
        FileNotFoundError: If input_miz doesn't exist
        ValueError: If group or waypoint not found

    Example:
        >>> wp = get_waypoint_coordinates_file("mission.miz", "Fighter-1", 2)
        >>> print(f"Waypoint: {wp}")
    """
    from ..parsing.miz_parser import MizParser

    if not Path(input_miz).exists():
        raise FileNotFoundError(f"Input .miz file not found: {input_miz}")

    parser = MizParser(input_miz)
    parser.extract()

    try:
        content = parser.get_mission_content()
        return get_waypoint_coordinates(content, group_name, waypoint_index)
    finally:
        parser.cleanup()
