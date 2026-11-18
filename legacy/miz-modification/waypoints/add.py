"""
Waypoint addition functions for .miz files.

Functions for adding waypoints to group routes.
"""

import re
from typing import Dict, Optional

from ..utils import patterns
from ..groups.list import find_group_by_name
from .list import list_waypoints


# ============================================================================
# HELPER FUNCTIONS
# ============================================================================

def _generate_waypoint_lua(waypoint_index: int, position: Dict[str, float],
                           speed: float = 150.0, alt: float = 2000.0,
                           action: str = "Turning Point",
                           alt_type: str = "BARO", **kwargs) -> str:
    """
    Generate Lua code for a waypoint definition.

    Args:
        waypoint_index: Index of the waypoint in the route
        position: Dict with 'x' and 'y' coordinates
        speed: Speed in m/s (default: 150)
        alt: Altitude in meters (default: 2000)
        action: Waypoint action (default: "Turning Point")
        alt_type: Altitude type "BARO" or "RADIO" (default: "BARO")
        **kwargs: Additional waypoint properties

    Returns:
        Lua code string for waypoint definition
    """
    x = position.get('x', 0.0)
    y = position.get('y', 0.0)

    # Determine waypoint type (usually same as action)
    wp_type = kwargs.get('type', action)

    waypoint_lua = f'''				[{waypoint_index}] =
				{{
					["alt"] = {alt},
					["action"] = "{action}",
					["alt_type"] = "{alt_type}",
					["speed"] = {speed},
					["type"] = "{wp_type}",
					["y"] = {y},
					["x"] = {x},
					["speed_locked"] = true,
'''

    # Add task section if provided
    if 'task' in kwargs and kwargs['task']:
        task_data = kwargs['task']
        waypoint_lua += f'''					["task"] =
					{{
						["id"] = "ComboTask",
						["params"] =
						{{
							["tasks"] =
							{{
							}}, -- end of ["tasks"]
						}}, -- end of ["params"]
					}}, -- end of ["task"]
'''

    # Add ETA/ETA_locked if provided
    if 'ETA' in kwargs:
        waypoint_lua += f'''					["ETA"] = {kwargs['ETA']},
					["ETA_locked"] = {str(kwargs.get('ETA_locked', 'true')).lower()},
'''

    # Close waypoint definition
    waypoint_lua += f'''				}}, -- end of [{waypoint_index}]
'''

    return waypoint_lua


# ============================================================================
# CORE ADD FUNCTIONS
# ============================================================================

def add_waypoint(mission_content: str, group_name: str, position: Dict[str, float],
                speed: float = 150.0, alt: float = 2000.0,
                action: str = "Turning Point", alt_type: str = "BARO",
                index: Optional[int] = None, **kwargs) -> str:
    """
    Add a waypoint to a group's route.

    Args:
        mission_content: Raw mission file content as string
        group_name: Name of the group to add waypoint to
        position: Dict with 'x' and 'y' coordinates
        speed: Speed in m/s (default: 150)
        alt: Altitude in meters (default: 2000)
        action: Waypoint action (default: "Turning Point")
        alt_type: Altitude type "BARO" or "RADIO" (default: "BARO")
        index: Optional position to insert waypoint. If None, appends to end.
               Use 1 to insert before first waypoint, 2 for second, etc.
        **kwargs: Additional waypoint properties

    Returns:
        Modified mission content with waypoint added

    Raises:
        ValueError: If group not found, has no route, or index is invalid

    Example:
        >>> # Add waypoint at end of route
        >>> position = {"x": -50000, "y": 30000}
        >>> content = add_waypoint(content, "Fighter-1", position, speed=200, alt=3000)
        >>>
        >>> # Insert waypoint at position 2
        >>> content = add_waypoint(content, "Fighter-1", position, index=2)
    """
    # Validate action
    if action not in patterns.WAYPOINT_ACTIONS:
        raise ValueError(f"Invalid waypoint action '{action}'. Valid: {', '.join(patterns.WAYPOINT_ACTIONS)}")

    # Validate altitude type
    if alt_type not in patterns.ALT_TYPES:
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
        raise ValueError(f"Group '{group_name}' has no waypoints section")

    points_content = points_match.group(1)
    points_start = route_start + points_match.start(1)
    points_end = route_start + points_match.end(1)

    # Get existing waypoints to determine new index
    existing_waypoints = list_waypoints(mission_content, group_name)

    if not existing_waypoints:
        # No existing waypoints, create first one
        new_index = 1
    elif index is None:
        # Append to end
        new_index = max(wp['index'] for wp in existing_waypoints) + 1
    else:
        # Insert at specified position
        if index < 1:
            raise ValueError(f"Waypoint index must be >= 1 (got {index})")

        new_index = index

        # Need to renumber existing waypoints at or after this index
        # For now, we'll just append with the requested index
        # In production, would implement full renumbering
        if index <= len(existing_waypoints):
            # This would require renumbering - for MVP, we'll raise an error
            raise ValueError(f"Inserting waypoints at specific positions requires renumbering. "
                           f"Currently only appending (index=None) is supported. "
                           f"Group has {len(existing_waypoints)} waypoints.")

        new_index = index

    # Generate waypoint Lua code
    wp_lua = _generate_waypoint_lua(
        waypoint_index=new_index,
        position=position,
        speed=speed,
        alt=alt,
        action=action,
        alt_type=alt_type,
        **kwargs
    )

    # Insert waypoint into points section
    # For appending, add after last waypoint
    new_points_content = points_content + '\n' + wp_lua

    # Replace points section in mission content
    modified_content = (
        mission_content[:points_start] +
        new_points_content +
        mission_content[points_end:]
    )

    return modified_content


def add_multiple_waypoints(mission_content: str, group_name: str,
                           waypoints: list) -> str:
    """
    Add multiple waypoints to a group's route.

    Args:
        mission_content: Raw mission file content as string
        group_name: Name of the group to add waypoints to
        waypoints: List of waypoint dicts, each containing:
                  - position: {"x": float, "y": float}
                  - speed: float (optional, default: 150)
                  - alt: float (optional, default: 2000)
                  - action: str (optional, default: "Turning Point")
                  - alt_type: str (optional, default: "BARO")

    Returns:
        Modified mission content with all waypoints added

    Raises:
        ValueError: If group not found or has no route

    Example:
        >>> waypoints = [
        ...     {"position": {"x": -50000, "y": 30000}, "speed": 200, "alt": 3000},
        ...     {"position": {"x": -45000, "y": 35000}, "speed": 250, "alt": 3500},
        ...     {"position": {"x": -40000, "y": 40000}, "speed": 300, "alt": 4000}
        ... ]
        >>> content = add_multiple_waypoints(content, "Fighter-1", waypoints)
    """
    modified_content = mission_content

    for wp_data in waypoints:
        position = wp_data.get('position')
        if not position:
            raise ValueError("Each waypoint must have a 'position' field")

        speed = wp_data.get('speed', 150.0)
        alt = wp_data.get('alt', 2000.0)
        action = wp_data.get('action', 'Turning Point')
        alt_type = wp_data.get('alt_type', 'BARO')

        # Extract any additional kwargs
        extra_kwargs = {k: v for k, v in wp_data.items()
                       if k not in ['position', 'speed', 'alt', 'action', 'alt_type']}

        modified_content = add_waypoint(
            modified_content,
            group_name,
            position,
            speed=speed,
            alt=alt,
            action=action,
            alt_type=alt_type,
            **extra_kwargs
        )

    return modified_content


# ============================================================================
# CONVENIENCE WRAPPER FUNCTIONS
# ============================================================================

def add_waypoint_file(input_miz: str, output_miz: str, group_name: str,
                     position: Dict[str, float], speed: float = 150.0,
                     alt: float = 2000.0, action: str = "Turning Point",
                     alt_type: str = "BARO", index: Optional[int] = None,
                     **kwargs) -> None:
    """
    Add waypoint to a .miz file (convenience wrapper).

    Args:
        input_miz: Path to input .miz file
        output_miz: Path to output .miz file
        group_name: Name of the group
        position: Dict with 'x' and 'y' coordinates
        speed: Speed in m/s
        alt: Altitude in meters
        action: Waypoint action
        alt_type: Altitude type
        index: Optional position to insert waypoint
        **kwargs: Additional waypoint properties

    Raises:
        FileNotFoundError: If input_miz doesn't exist
        ValueError: If group not found or has no route

    Example:
        >>> add_waypoint_file(
        ...     "../miz-files/input/mission.miz",
        ...     "../miz-files/output/mission_with_waypoint.miz",
        ...     "Fighter-1",
        ...     {"x": -50000, "y": 30000},
        ...     speed=200,
        ...     alt=3000
        ... )
    """
    from ..parsing.miz_parser import quick_modify

    def modify_func(content):
        return add_waypoint(content, group_name, position, speed, alt, action, alt_type, index, **kwargs)

    quick_modify(input_miz, output_miz, modify_func)


def add_multiple_waypoints_file(input_miz: str, output_miz: str,
                                group_name: str, waypoints: list) -> None:
    """
    Add multiple waypoints to a .miz file (convenience wrapper).

    Args:
        input_miz: Path to input .miz file
        output_miz: Path to output .miz file
        group_name: Name of the group
        waypoints: List of waypoint dicts

    Raises:
        FileNotFoundError: If input_miz doesn't exist
        ValueError: If group not found or has no route

    Example:
        >>> waypoints = [
        ...     {"position": {"x": -50000, "y": 30000}, "speed": 200, "alt": 3000},
        ...     {"position": {"x": -45000, "y": 35000}, "speed": 250, "alt": 3500}
        ... ]
        >>> add_multiple_waypoints_file(
        ...     "../miz-files/input/mission.miz",
        ...     "../miz-files/output/mission_with_waypoints.miz",
        ...     "Fighter-1",
        ...     waypoints
        ... )
    """
    from ..parsing.miz_parser import quick_modify

    def modify_func(content):
        return add_multiple_waypoints(content, group_name, waypoints)

    quick_modify(input_miz, output_miz, modify_func)
