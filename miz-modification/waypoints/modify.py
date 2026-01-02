"""
Waypoint modification functions for .miz files.

Functions for modifying waypoint properties like position, speed, altitude, action.
"""

import re
from typing import Dict, Optional

from ..utils import patterns
from ..groups.list import find_group_by_name
from .remove import _find_waypoint_in_content


# ============================================================================
# CORE MODIFICATION FUNCTIONS
# ============================================================================

def modify_waypoint(mission_content: str, group_name: str, waypoint_index: int,
                   position: Optional[Dict[str, float]] = None,
                   speed: Optional[float] = None,
                   alt: Optional[float] = None,
                   action: Optional[str] = None,
                   alt_type: Optional[str] = None) -> str:
    """
    Modify properties of a waypoint.

    Args:
        mission_content: Raw mission file content as string
        group_name: Name of the group
        waypoint_index: Index of the waypoint to modify (1-based)
        position: Optional new position {"x": float, "y": float}
        speed: Optional new speed in m/s
        alt: Optional new altitude in meters
        action: Optional new action string
        alt_type: Optional new altitude type ("BARO" or "RADIO")

    Returns:
        Modified mission content with waypoint updated

    Raises:
        ValueError: If group not found, has no route, waypoint doesn't exist,
                   or invalid values provided

    Note:
        Only provided parameters are modified. Unprovided parameters remain unchanged.

    Example:
        >>> # Change waypoint 2 position and speed
        >>> content = modify_waypoint(
        ...     content, "Fighter-1", 2,
        ...     position={"x": -50000, "y": 30000},
        ...     speed=250
        ... )
        >>>
        >>> # Change only altitude
        >>> content = modify_waypoint(content, "Fighter-1", 3, alt=5000)
    """
    # Validate action if provided
    if action and action not in patterns.WAYPOINT_ACTIONS:
        raise ValueError(f"Invalid waypoint action '{action}'. Valid: {', '.join(patterns.WAYPOINT_ACTIONS)}")

    # Validate altitude type if provided
    if alt_type and alt_type not in patterns.ALT_TYPES:
        raise ValueError(f"Invalid altitude type '{alt_type}'. Valid: {', '.join(patterns.ALT_TYPES)}")

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
    route_start = group_start + route_match.start(1)
    route_end = group_start + route_match.end(1)

    # Find points section in route
    points_match = patterns.POINTS_SECTION_PATTERN_COMPILED.search(route_content)
    if not points_match:
        raise ValueError(f"Group '{group_name}' has no waypoints")

    points_content = points_match.group(1)
    points_start = route_start + points_match.start(1)
    points_end = route_start + points_match.end(1)

    # Find the waypoint to modify
    wp_result = _find_waypoint_in_content(points_content, waypoint_index)
    if not wp_result:
        raise ValueError(f"Waypoint {waypoint_index} not found in group '{group_name}'")

    wp_content, wp_start_in_points, wp_end_in_points = wp_result

    # Calculate absolute positions
    wp_start = points_start + wp_start_in_points
    wp_end = points_start + wp_end_in_points

    # Start with current content
    modified_content = mission_content

    # Modify position if provided
    if position:
        if 'x' not in position or 'y' not in position:
            raise ValueError("Position must contain 'x' and 'y' keys")

        # Find y coordinate (appears first in DCS files)
        y_match = patterns.Y_COORD_PATTERN_COMPILED.search(wp_content)
        if y_match:
            y_start = wp_start + y_match.start(1)
            y_end = wp_start + y_match.end(1)
            modified_content = (
                modified_content[:y_start] +
                str(position['y']) +
                modified_content[y_end:]
            )

            # Recalculate positions after y change
            len_diff = len(str(position['y'])) - len(y_match.group(1))
            wp_start += len_diff
            wp_end += len_diff

            # Update wp_content for x search
            wp_content = modified_content[wp_start:wp_end]

        # Find x coordinate
        x_match = patterns.X_COORD_PATTERN_COMPILED.search(wp_content)
        if x_match:
            x_start = wp_start + x_match.start(1)
            x_end = wp_start + x_match.end(1)
            modified_content = (
                modified_content[:x_start] +
                str(position['x']) +
                modified_content[x_end:]
            )

            # Recalculate positions after x change
            len_diff = len(str(position['x'])) - len(x_match.group(1))
            wp_start += len_diff
            wp_end += len_diff

            # Update wp_content for subsequent searches
            wp_content = modified_content[wp_start:wp_end]

    # Modify speed if provided
    if speed is not None:
        speed_match = patterns.SPEED_PATTERN_COMPILED.search(wp_content)
        if speed_match:
            speed_start = wp_start + speed_match.start(1)
            speed_end = wp_start + speed_match.end(1)
            modified_content = (
                modified_content[:speed_start] +
                str(speed) +
                modified_content[speed_end:]
            )

            # Recalculate positions after speed change
            len_diff = len(str(speed)) - len(speed_match.group(1))
            wp_start += len_diff
            wp_end += len_diff

            # Update wp_content for subsequent searches
            wp_content = modified_content[wp_start:wp_end]

    # Modify altitude if provided
    if alt is not None:
        alt_match = patterns.ALT_PATTERN_COMPILED.search(wp_content)
        if alt_match:
            alt_start = wp_start + alt_match.start(1)
            alt_end = wp_start + alt_match.end(1)
            modified_content = (
                modified_content[:alt_start] +
                str(alt) +
                modified_content[alt_end:]
            )

            # Recalculate positions after alt change
            len_diff = len(str(alt)) - len(alt_match.group(1))
            wp_start += len_diff
            wp_end += len_diff

            # Update wp_content for subsequent searches
            wp_content = modified_content[wp_start:wp_end]

    # Modify action if provided
    if action:
        action_match = patterns.WAYPOINT_ACTION_PATTERN_COMPILED.search(wp_content)
        if action_match:
            action_start = wp_start + action_match.start(1)
            action_end = wp_start + action_match.end(1)
            modified_content = (
                modified_content[:action_start] +
                action +
                modified_content[action_end:]
            )

            # Recalculate positions after action change
            len_diff = len(action) - len(action_match.group(1))
            wp_start += len_diff
            wp_end += len_diff

            # Update wp_content for subsequent searches
            wp_content = modified_content[wp_start:wp_end]

        # Also update type field (usually matches action)
        type_match = re.search(r'\["type"\]\s*=\s*"([^"]+)"', wp_content)
        if type_match:
            type_start = wp_start + type_match.start(1)
            type_end = wp_start + type_match.end(1)
            modified_content = (
                modified_content[:type_start] +
                action +
                modified_content[type_end:]
            )

            # Recalculate positions after type change
            len_diff = len(action) - len(type_match.group(1))
            wp_start += len_diff
            wp_end += len_diff

            # Update wp_content for subsequent searches
            wp_content = modified_content[wp_start:wp_end]

    # Modify altitude type if provided
    if alt_type:
        alt_type_match = re.search(r'\["alt_type"\]\s*=\s*"([^"]+)"', wp_content)
        if alt_type_match:
            alt_type_start = wp_start + alt_type_match.start(1)
            alt_type_end = wp_start + alt_type_match.end(1)
            modified_content = (
                modified_content[:alt_type_start] +
                alt_type +
                modified_content[alt_type_end:]
            )

    return modified_content


def modify_waypoint_position(mission_content: str, group_name: str,
                            waypoint_index: int, position: Dict[str, float]) -> str:
    """
    Modify only the position of a waypoint (convenience function).

    Args:
        mission_content: Raw mission file content as string
        group_name: Name of the group
        waypoint_index: Index of the waypoint to modify
        position: New position {"x": float, "y": float}

    Returns:
        Modified mission content

    Raises:
        ValueError: If group/waypoint not found or position invalid

    Example:
        >>> content = modify_waypoint_position(
        ...     content, "Fighter-1", 2,
        ...     {"x": -50000, "y": 30000}
        ... )
    """
    return modify_waypoint(mission_content, group_name, waypoint_index, position=position)


def modify_waypoint_speed(mission_content: str, group_name: str,
                         waypoint_index: int, speed: float) -> str:
    """
    Modify only the speed of a waypoint (convenience function).

    Args:
        mission_content: Raw mission file content as string
        group_name: Name of the group
        waypoint_index: Index of the waypoint to modify
        speed: New speed in m/s

    Returns:
        Modified mission content

    Raises:
        ValueError: If group/waypoint not found

    Example:
        >>> content = modify_waypoint_speed(content, "Fighter-1", 2, 250.0)
    """
    return modify_waypoint(mission_content, group_name, waypoint_index, speed=speed)


def modify_waypoint_altitude(mission_content: str, group_name: str,
                            waypoint_index: int, alt: float, alt_type: Optional[str] = None) -> str:
    """
    Modify the altitude (and optionally altitude type) of a waypoint (convenience function).

    Args:
        mission_content: Raw mission file content as string
        group_name: Name of the group
        waypoint_index: Index of the waypoint to modify
        alt: New altitude in meters
        alt_type: Optional new altitude type ("BARO" or "RADIO")

    Returns:
        Modified mission content

    Raises:
        ValueError: If group/waypoint not found or alt_type invalid

    Example:
        >>> # Change to 5000m BARO altitude
        >>> content = modify_waypoint_altitude(content, "Fighter-1", 2, 5000, "BARO")
        >>>
        >>> # Change altitude only, keep existing type
        >>> content = modify_waypoint_altitude(content, "Fighter-1", 2, 5000)
    """
    return modify_waypoint(mission_content, group_name, waypoint_index, alt=alt, alt_type=alt_type)


def modify_waypoint_action(mission_content: str, group_name: str,
                          waypoint_index: int, action: str) -> str:
    """
    Modify only the action of a waypoint (convenience function).

    Args:
        mission_content: Raw mission file content as string
        group_name: Name of the group
        waypoint_index: Index of the waypoint to modify
        action: New action string

    Returns:
        Modified mission content

    Raises:
        ValueError: If group/waypoint not found or action invalid

    Example:
        >>> content = modify_waypoint_action(content, "Fighter-1", 2, "Fly Over Point")
    """
    return modify_waypoint(mission_content, group_name, waypoint_index, action=action)


# ============================================================================
# CONVENIENCE WRAPPER FUNCTIONS
# ============================================================================

def modify_waypoint_file(input_miz: str, output_miz: str, group_name: str,
                        waypoint_index: int, position: Optional[Dict] = None,
                        speed: Optional[float] = None, alt: Optional[float] = None,
                        action: Optional[str] = None, alt_type: Optional[str] = None) -> None:
    """
    Modify waypoint in a .miz file (convenience wrapper).

    Args:
        input_miz: Path to input .miz file
        output_miz: Path to output .miz file
        group_name: Name of the group
        waypoint_index: Index of the waypoint to modify
        position: Optional new position
        speed: Optional new speed
        alt: Optional new altitude
        action: Optional new action
        alt_type: Optional new altitude type

    Raises:
        FileNotFoundError: If input_miz doesn't exist
        ValueError: If group/waypoint not found or invalid values

    Example:
        >>> modify_waypoint_file(
        ...     "../miz-files/input/mission.miz",
        ...     "../miz-files/output/mission_modified.miz",
        ...     "Fighter-1",
        ...     2,
        ...     position={"x": -50000, "y": 30000},
        ...     speed=250
        ... )
    """
    from ..parsing.miz_parser import quick_modify

    def modify_func(content):
        return modify_waypoint(content, group_name, waypoint_index, position, speed, alt, action, alt_type)

    quick_modify(input_miz, output_miz, modify_func)


def modify_waypoint_position_file(input_miz: str, output_miz: str, group_name: str,
                                 waypoint_index: int, position: Dict[str, float]) -> None:
    """
    Modify waypoint position in a .miz file (convenience wrapper).

    Args:
        input_miz: Path to input .miz file
        output_miz: Path to output .miz file
        group_name: Name of the group
        waypoint_index: Index of the waypoint
        position: New position

    Raises:
        FileNotFoundError: If input_miz doesn't exist
        ValueError: If group/waypoint not found

    Example:
        >>> modify_waypoint_position_file(
        ...     "../miz-files/input/mission.miz",
        ...     "../miz-files/output/mission_modified.miz",
        ...     "Fighter-1",
        ...     2,
        ...     {"x": -50000, "y": 30000}
        ... )
    """
    from ..parsing.miz_parser import quick_modify

    def modify_func(content):
        return modify_waypoint_position(content, group_name, waypoint_index, position)

    quick_modify(input_miz, output_miz, modify_func)


def modify_waypoint_speed_file(input_miz: str, output_miz: str, group_name: str,
                               waypoint_index: int, speed: float) -> None:
    """
    Modify waypoint speed in a .miz file (convenience wrapper).

    Args:
        input_miz: Path to input .miz file
        output_miz: Path to output .miz file
        group_name: Name of the group
        waypoint_index: Index of the waypoint
        speed: New speed in m/s

    Raises:
        FileNotFoundError: If input_miz doesn't exist
        ValueError: If group/waypoint not found

    Example:
        >>> modify_waypoint_speed_file(
        ...     "../miz-files/input/mission.miz",
        ...     "../miz-files/output/mission_modified.miz",
        ...     "Fighter-1",
        ...     2,
        ...     250.0
        ... )
    """
    from ..parsing.miz_parser import quick_modify

    def modify_func(content):
        return modify_waypoint_speed(content, group_name, waypoint_index, speed)

    quick_modify(input_miz, output_miz, modify_func)


def modify_waypoint_altitude_file(input_miz: str, output_miz: str, group_name: str,
                                 waypoint_index: int, alt: float,
                                 alt_type: Optional[str] = None) -> None:
    """
    Modify waypoint altitude in a .miz file (convenience wrapper).

    Args:
        input_miz: Path to input .miz file
        output_miz: Path to output .miz file
        group_name: Name of the group
        waypoint_index: Index of the waypoint
        alt: New altitude in meters
        alt_type: Optional new altitude type

    Raises:
        FileNotFoundError: If input_miz doesn't exist
        ValueError: If group/waypoint not found or alt_type invalid

    Example:
        >>> modify_waypoint_altitude_file(
        ...     "../miz-files/input/mission.miz",
        ...     "../miz-files/output/mission_modified.miz",
        ...     "Fighter-1",
        ...     2,
        ...     5000,
        ...     "BARO"
        ... )
    """
    from ..parsing.miz_parser import quick_modify

    def modify_func(content):
        return modify_waypoint_altitude(content, group_name, waypoint_index, alt, alt_type)

    quick_modify(input_miz, output_miz, modify_func)


def modify_waypoint_action_file(input_miz: str, output_miz: str, group_name: str,
                               waypoint_index: int, action: str) -> None:
    """
    Modify waypoint action in a .miz file (convenience wrapper).

    Args:
        input_miz: Path to input .miz file
        output_miz: Path to output .miz file
        group_name: Name of the group
        waypoint_index: Index of the waypoint
        action: New action string

    Raises:
        FileNotFoundError: If input_miz doesn't exist
        ValueError: If group/waypoint not found or action invalid

    Example:
        >>> modify_waypoint_action_file(
        ...     "../miz-files/input/mission.miz",
        ...     "../miz-files/output/mission_modified.miz",
        ...     "Fighter-1",
        ...     2,
        ...     "Fly Over Point"
        ... )
    """
    from ..parsing.miz_parser import quick_modify

    def modify_func(content):
        return modify_waypoint_action(content, group_name, waypoint_index, action)

    quick_modify(input_miz, output_miz, modify_func)
