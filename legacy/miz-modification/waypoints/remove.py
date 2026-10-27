"""
Waypoint removal functions for .miz files.

Functions for removing waypoints from group routes.
"""

import re
from typing import Optional

from ..utils import patterns
from ..groups.list import find_group_by_name
from .list import list_waypoints


# ============================================================================
# HELPER FUNCTIONS
# ============================================================================

def _find_waypoint_in_content(points_content: str, waypoint_index: int) -> Optional[tuple]:
    """
    Find a waypoint by index in points content.

    Args:
        points_content: Content of ["points"] section
        waypoint_index: Index of the waypoint to find

    Returns:
        Tuple of (waypoint_content, start_pos, end_pos) if found, None if not found
    """
    # Pattern to match: [index] = { ... },
    # Use proper brace counting for nested structures
    for wp_match in patterns.WAYPOINT_BLOCK_PATTERN_COMPILED.finditer(points_content):
        wp_idx = int(wp_match.group(1))
        if wp_idx == waypoint_index:
            wp_start = wp_match.start()
            wp_end = wp_match.end()

            # Check for trailing comment
            remaining = points_content[wp_end:]
            comment_match = re.match(r'\s*--\s*end\s*of\s*\[\d+\]\s*\n?', remaining)
            if comment_match:
                wp_end += comment_match.end()

            return (points_content[wp_start:wp_end], wp_start, wp_end)

    return None


# ============================================================================
# CORE REMOVAL FUNCTIONS
# ============================================================================

def remove_waypoint(mission_content: str, group_name: str, waypoint_index: int) -> str:
    """
    Remove a waypoint from a group's route.

    Args:
        mission_content: Raw mission file content as string
        group_name: Name of the group
        waypoint_index: Index of the waypoint to remove (1-based)

    Returns:
        Modified mission content with waypoint removed

    Raises:
        ValueError: If group not found, has no route, waypoint doesn't exist,
                   or trying to remove the only waypoint

    Note:
        Cannot remove the only waypoint in a route. Use clear_route() to remove
        all waypoints (leaves empty route).

    Example:
        >>> # Remove the 2nd waypoint
        >>> content = remove_waypoint(content, "Fighter-1", 2)
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
    route_start = group_start + route_match.start(1)
    route_end = group_start + route_match.end(1)

    # Find points section in route
    points_match = patterns.POINTS_SECTION_PATTERN_COMPILED.search(route_content)
    if not points_match:
        raise ValueError(f"Group '{group_name}' has no waypoints")

    points_content = points_match.group(1)
    points_start = route_start + points_match.start(1)
    points_end = route_start + points_match.end(1)

    # Check if this is the only waypoint
    waypoints = list_waypoints(mission_content, group_name)
    if len(waypoints) == 1:
        raise ValueError(f"Cannot remove the only waypoint from group '{group_name}'. "
                       f"Use clear_route() to remove all waypoints.")

    # Find the waypoint to remove
    wp_result = _find_waypoint_in_content(points_content, waypoint_index)
    if not wp_result:
        raise ValueError(f"Waypoint {waypoint_index} not found in group '{group_name}'")

    wp_content, wp_start_in_points, wp_end_in_points = wp_result

    # Remove the waypoint
    modified_points_content = (
        points_content[:wp_start_in_points] +
        points_content[wp_end_in_points:]
    )

    # Replace points section in mission content
    modified_content = (
        mission_content[:points_start] +
        modified_points_content +
        mission_content[points_end:]
    )

    return modified_content


def clear_route(mission_content: str, group_name: str, keep_first: bool = True) -> str:
    """
    Clear all waypoints from a group's route.

    Args:
        mission_content: Raw mission file content as string
        group_name: Name of the group
        keep_first: If True, keeps the first waypoint (default: True).
                   If False, removes all waypoints leaving empty route.

    Returns:
        Modified mission content with waypoints cleared

    Raises:
        ValueError: If group not found or has no route

    Note:
        Keeping the first waypoint is recommended as it usually represents
        the starting position (takeoff point, spawn point, etc.).

    Example:
        >>> # Remove all waypoints except the first one
        >>> content = clear_route(content, "Fighter-1", keep_first=True)
        >>>
        >>> # Remove all waypoints including first (empty route)
        >>> content = clear_route(content, "Fighter-1", keep_first=False)
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
    route_start = group_start + route_match.start(1)
    route_end = group_start + route_match.end(1)

    # Find points section in route
    points_match = patterns.POINTS_SECTION_PATTERN_COMPILED.search(route_content)
    if not points_match:
        raise ValueError(f"Group '{group_name}' has no waypoints")

    points_content = points_match.group(1)
    points_start = route_start + points_match.start(1)
    points_end = route_start + points_match.end(1)

    if keep_first:
        # Keep only the first waypoint
        waypoints = list_waypoints(mission_content, group_name)
        if not waypoints:
            raise ValueError(f"Group '{group_name}' has no waypoints")

        # Find the first waypoint in content
        first_wp_result = _find_waypoint_in_content(points_content, waypoints[0]['index'])
        if not first_wp_result:
            raise ValueError(f"Could not find first waypoint in group '{group_name}'")

        first_wp_content, _, _ = first_wp_result

        # Replace points content with just the first waypoint
        modified_points_content = '\n' + first_wp_content + '\t\t\t\t'
    else:
        # Empty points section
        modified_points_content = '\n\t\t\t\t'

    # Replace points section in mission content
    modified_content = (
        mission_content[:points_start] +
        modified_points_content +
        mission_content[points_end:]
    )

    return modified_content


def remove_waypoints_after(mission_content: str, group_name: str, waypoint_index: int) -> str:
    """
    Remove all waypoints after a specified index (keep waypoints up to and including index).

    Args:
        mission_content: Raw mission file content as string
        group_name: Name of the group
        waypoint_index: Keep waypoints up to and including this index

    Returns:
        Modified mission content with waypoints after index removed

    Raises:
        ValueError: If group not found, has no route, or index is invalid

    Example:
        >>> # Keep waypoints 1-3, remove 4 onwards
        >>> content = remove_waypoints_after(content, "Fighter-1", 3)
    """
    waypoints = list_waypoints(mission_content, group_name)

    # Validate index
    if waypoint_index < 1:
        raise ValueError(f"Waypoint index must be >= 1 (got {waypoint_index})")

    if not any(wp['index'] == waypoint_index for wp in waypoints):
        raise ValueError(f"Waypoint {waypoint_index} not found in group '{group_name}'")

    # Remove waypoints with index > waypoint_index
    modified_content = mission_content
    for wp in reversed(waypoints):  # Remove in reverse order to avoid index issues
        if wp['index'] > waypoint_index:
            modified_content = remove_waypoint(modified_content, group_name, wp['index'])

    return modified_content


# ============================================================================
# CONVENIENCE WRAPPER FUNCTIONS
# ============================================================================

def remove_waypoint_file(input_miz: str, output_miz: str, group_name: str,
                        waypoint_index: int) -> None:
    """
    Remove waypoint from a .miz file (convenience wrapper).

    Args:
        input_miz: Path to input .miz file
        output_miz: Path to output .miz file
        group_name: Name of the group
        waypoint_index: Index of the waypoint to remove

    Raises:
        FileNotFoundError: If input_miz doesn't exist
        ValueError: If group not found, has no route, or waypoint doesn't exist

    Example:
        >>> remove_waypoint_file(
        ...     "../miz-files/input/mission.miz",
        ...     "../miz-files/output/mission_modified.miz",
        ...     "Fighter-1",
        ...     2
        ... )
    """
    from ..parsing.miz_parser import quick_modify

    def modify_func(content):
        return remove_waypoint(content, group_name, waypoint_index)

    quick_modify(input_miz, output_miz, modify_func)


def clear_route_file(input_miz: str, output_miz: str, group_name: str,
                    keep_first: bool = True) -> None:
    """
    Clear route from a .miz file (convenience wrapper).

    Args:
        input_miz: Path to input .miz file
        output_miz: Path to output .miz file
        group_name: Name of the group
        keep_first: If True, keeps first waypoint

    Raises:
        FileNotFoundError: If input_miz doesn't exist
        ValueError: If group not found or has no route

    Example:
        >>> clear_route_file(
        ...     "../miz-files/input/mission.miz",
        ...     "../miz-files/output/mission_cleared.miz",
        ...     "Fighter-1",
        ...     keep_first=True
        ... )
    """
    from ..parsing.miz_parser import quick_modify

    def modify_func(content):
        return clear_route(content, group_name, keep_first)

    quick_modify(input_miz, output_miz, modify_func)


def remove_waypoints_after_file(input_miz: str, output_miz: str, group_name: str,
                                waypoint_index: int) -> None:
    """
    Remove waypoints after index from a .miz file (convenience wrapper).

    Args:
        input_miz: Path to input .miz file
        output_miz: Path to output .miz file
        group_name: Name of the group
        waypoint_index: Keep waypoints up to and including this index

    Raises:
        FileNotFoundError: If input_miz doesn't exist
        ValueError: If group not found, has no route, or index is invalid

    Example:
        >>> remove_waypoints_after_file(
        ...     "../miz-files/input/mission.miz",
        ...     "../miz-files/output/mission_trimmed.miz",
        ...     "Fighter-1",
        ...     3
        ... )
    """
    from ..parsing.miz_parser import quick_modify

    def modify_func(content):
        return remove_waypoints_after(content, group_name, waypoint_index)

    quick_modify(input_miz, output_miz, modify_func)
