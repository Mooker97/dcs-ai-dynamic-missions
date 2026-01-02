"""
Unit addition functions for .miz files.

Functions for adding units to existing groups in missions.
"""

import re
from typing import Dict, Optional

from ..utils import patterns, validation, id_manager
from ..groups.list import find_group_by_name, get_group_info


# ============================================================================
# HELPER FUNCTIONS
# ============================================================================

def _generate_unit_name(group_name: str, unit_index: int) -> str:
    """
    Generate unit name from group name and index.

    Convention: "GroupName-Index" (e.g., "Fighter-1-3")

    Args:
        group_name: Name of the parent group
        unit_index: Index of the unit within group

    Returns:
        Generated unit name

    Example:
        >>> _generate_unit_name("Fighter-1", 3)
        'Fighter-1-3'
    """
    return f"{group_name}-{unit_index}"


def _get_max_unit_index_in_group(units_content: str) -> int:
    """
    Find the highest unit index in a units section.

    Args:
        units_content: Content of ["units"] section

    Returns:
        Maximum unit index found, or 0 if no units

    Example:
        >>> units = '[1] = {...}, [2] = {...}, [5] = {...}'
        >>> _get_max_unit_index_in_group(units)
        5
    """
    indices = re.findall(r'\[(\d+)\]\s*=', units_content)
    if not indices:
        return 0
    return max(int(idx) for idx in indices)


def _get_unit_category_from_type(unit_type: str) -> str:
    """
    Determine unit category from unit type string.

    This is a simplified helper - in production, would need comprehensive
    mapping of all DCS unit types to categories.

    Args:
        unit_type: Unit type string (e.g., "F-16C_50", "M-1 Abrams")

    Returns:
        Category: "plane", "helicopter", "ship", "vehicle", or "static"

    Note:
        For now, returns "plane" as default. In production, would need
        full unit type database.
    """
    # Common helicopter patterns
    if any(heli in unit_type.upper() for heli in ['UH-', 'AH-', 'MI-', 'KA-', 'CH-', 'SH-']):
        return "helicopter"

    # Common ship patterns
    if any(ship in unit_type.upper() for ship in ['CVN', 'LHA', 'TICONDEROGA', 'PERRY', 'KRIVAK']):
        return "ship"

    # Common vehicle patterns
    if any(veh in unit_type.upper() for veh in ['M-1', 'T-', 'BMP', 'BTR', 'M113', 'AAV']):
        return "vehicle"

    # Default to plane for aircraft
    return "plane"


def _generate_unit_lua(unit_name: str, unit_type: str, unit_id: int,
                      unit_index: int, position: Dict[str, float],
                      category: str, **kwargs) -> str:
    """
    Generate Lua code for a unit definition.

    Args:
        unit_name: Name of the unit
        unit_type: DCS unit type (e.g., "F-16C_50")
        unit_id: Globally unique unit ID
        unit_index: Index within units array
        position: Dict with 'x' and 'y' coordinates
        category: Unit category (plane, helicopter, ship, vehicle, static)
        **kwargs: Optional fields (skill, speed, alt, heading, etc.)

    Returns:
        Lua code string for unit definition
    """
    x = position.get('x', 0.0)
    y = position.get('y', 0.0)
    skill = kwargs.get('skill', 'Average')
    heading = kwargs.get('heading', 0.0)

    # Base unit definition (all unit types)
    unit_lua = f'''			[{unit_index}] =
			{{
				["type"] = "{unit_type}",
				["unitId"] = {unit_id},
				["skill"] = "{skill}",
				["y"] = {y},
				["x"] = {x},
				["name"] = "{unit_name}",
				["heading"] = {heading},
'''

    # Category-specific fields
    if category == "plane":
        speed = kwargs.get('speed', 150.0)
        alt = kwargs.get('alt', 2000.0)
        alt_type = kwargs.get('alt_type', 'BARO')

        unit_lua += f'''				["speed"] = {speed},
				["alt"] = {alt},
				["alt_type"] = "{alt_type}",
				["payload"] =
				{{
					["pylons"] =
					{{
					}}, -- end of ["pylons"]
					["fuel"] = 3249,
					["flare"] = 60,
					["chaff"] = 60,
					["gun"] = 100,
				}}, -- end of ["payload"]
'''

    elif category == "helicopter":
        speed = kwargs.get('speed', 50.0)
        alt = kwargs.get('alt', 500.0)
        alt_type = kwargs.get('alt_type', 'RADIO')

        unit_lua += f'''				["speed"] = {speed},
				["alt"] = {alt},
				["alt_type"] = "{alt_type}",
				["payload"] =
				{{
					["pylons"] =
					{{
					}}, -- end of ["pylons"]
					["fuel"] = 1000,
					["flare"] = 30,
					["chaff"] = 30,
				}}, -- end of ["payload"]
'''

    elif category == "ship":
        frequency = kwargs.get('frequency', 127500000)
        modulation = kwargs.get('modulation', 0)

        unit_lua += f'''				["frequency"] = {frequency},
				["modulation"] = {modulation},
'''

    elif category == "vehicle":
        # Vehicles have minimal fields beyond base
        pass

    elif category == "static":
        # Static objects have minimal fields
        pass

    # Close the unit definition
    unit_lua += '''			}}, -- end of [{}]
'''.format(unit_index)

    return unit_lua


# ============================================================================
# CORE ADD FUNCTIONS
# ============================================================================

def add_unit_to_group(mission_content: str, group_name: str, unit_type: str,
                     position_offset: Optional[Dict[str, float]] = None,
                     **kwargs) -> str:
    """
    Add a new unit to an existing group.

    Args:
        mission_content: Raw mission file content as string
        group_name: Name of the group to add unit to
        unit_type: DCS unit type (e.g., "F-16C_50", "UH-1H", "M-1 Abrams")
        position_offset: Optional position offset from group position
                        Dict with 'x' and 'y' (meters). If None, uses group position.
        **kwargs: Optional unit properties:
                 - skill: Skill level (default: "Average")
                 - speed: Speed in m/s (default varies by category)
                 - alt: Altitude in meters (default varies by category)
                 - heading: Heading in radians (default: 0.0)
                 - Other category-specific fields

    Returns:
        Modified mission content with new unit added

    Raises:
        ValueError: If group not found or unit_type is invalid

    Example:
        >>> # Add F-16 to Fighter-1 group at same position
        >>> content = add_unit_to_group(content, "Fighter-1", "F-16C_50")
        >>>
        >>> # Add F-16 offset 100m east and 50m north
        >>> content = add_unit_to_group(
        ...     content, "Fighter-1", "F-16C_50",
        ...     position_offset={"x": 100, "y": 50},
        ...     skill="Good", alt=3000
        ... )
    """
    # Find the group
    group_result = find_group_by_name(mission_content, group_name)
    if not group_result:
        raise ValueError(f"Group '{group_name}' not found in mission")

    group_content, group_start, group_end = group_result

    # Get group info for position
    group_info = get_group_info(mission_content, group_name)
    if 'position' not in group_info:
        raise ValueError(f"Group '{group_name}' has no position information")

    group_pos = group_info['position']

    # Calculate unit position
    if position_offset:
        unit_position = {
            'x': group_pos['x'] + position_offset.get('x', 0),
            'y': group_pos['y'] + position_offset.get('y', 0)
        }
    else:
        unit_position = group_pos.copy()

    # Find units section in group
    units_match = patterns.UNITS_SECTION_PATTERN_COMPILED.search(group_content)
    if not units_match:
        raise ValueError(f"Group '{group_name}' has no units section")

    units_content = units_match.group(1)
    units_start = group_start + units_match.start(1)
    units_end = group_start + units_match.end(1)

    # Get max unit index in this group
    max_index = _get_max_unit_index_in_group(units_content)
    new_index = max_index + 1

    # Get globally unique unit ID
    max_unit_id = id_manager.find_max_unit_id(mission_content)
    new_unit_id = max_unit_id + 1

    # Generate unit name
    unit_name = _generate_unit_name(group_name, new_index)

    # Determine category
    category = _get_unit_category_from_type(unit_type)

    # Generate unit Lua code
    unit_lua = _generate_unit_lua(
        unit_name=unit_name,
        unit_type=unit_type,
        unit_id=new_unit_id,
        unit_index=new_index,
        position=unit_position,
        category=category,
        **kwargs
    )

    # Insert new unit into units section
    # Find the last unit in the section to insert after it
    if max_index > 0:
        # There are existing units, insert after the last one
        new_units_content = units_content + '\n' + unit_lua
    else:
        # No existing units, create first unit
        new_units_content = '\n' + unit_lua + '\t\t\t'

    # Replace units content in mission
    modified_content = (
        mission_content[:units_start] +
        new_units_content +
        mission_content[units_end:]
    )

    return modified_content


def add_multiple_units_to_group(mission_content: str, group_name: str,
                                units: list, spacing: float = 50.0) -> str:
    """
    Add multiple units to a group with automatic spacing.

    Args:
        mission_content: Raw mission file content as string
        group_name: Name of the group to add units to
        units: List of unit type strings to add
        spacing: Spacing between units in meters (default: 50m)

    Returns:
        Modified mission content with all units added

    Raises:
        ValueError: If group not found

    Example:
        >>> # Add 3 F-16s with 50m spacing
        >>> units_to_add = ["F-16C_50", "F-16C_50", "F-16C_50"]
        >>> content = add_multiple_units_to_group(content, "Fighter-1", units_to_add)
    """
    modified_content = mission_content

    for i, unit_type in enumerate(units):
        # Offset each unit by spacing
        offset = {
            'x': i * spacing,  # Space units along x-axis
            'y': 0
        }

        modified_content = add_unit_to_group(
            modified_content,
            group_name,
            unit_type,
            position_offset=offset
        )

    return modified_content


# ============================================================================
# CONVENIENCE WRAPPER FUNCTIONS
# ============================================================================

def add_unit_to_group_file(input_miz: str, output_miz: str, group_name: str,
                           unit_type: str, position_offset: Optional[Dict] = None,
                           **kwargs) -> None:
    """
    Add unit to group in a .miz file (convenience wrapper).

    Args:
        input_miz: Path to input .miz file
        output_miz: Path to output .miz file
        group_name: Name of the group to add unit to
        unit_type: DCS unit type
        position_offset: Optional position offset dict
        **kwargs: Optional unit properties

    Raises:
        FileNotFoundError: If input_miz doesn't exist
        ValueError: If group not found or unit_type is invalid

    Example:
        >>> add_unit_to_group_file(
        ...     "../miz-files/input/mission.miz",
        ...     "../miz-files/output/mission_with_unit.miz",
        ...     "Fighter-1",
        ...     "F-16C_50",
        ...     position_offset={"x": 100, "y": 0},
        ...     skill="Good"
        ... )
    """
    from ..parsing.miz_parser import quick_modify

    def modify_func(content):
        return add_unit_to_group(content, group_name, unit_type, position_offset, **kwargs)

    quick_modify(input_miz, output_miz, modify_func)


def add_multiple_units_to_group_file(input_miz: str, output_miz: str,
                                     group_name: str, units: list,
                                     spacing: float = 50.0) -> None:
    """
    Add multiple units to group in a .miz file (convenience wrapper).

    Args:
        input_miz: Path to input .miz file
        output_miz: Path to output .miz file
        group_name: Name of the group to add units to
        units: List of unit type strings
        spacing: Spacing between units in meters

    Raises:
        FileNotFoundError: If input_miz doesn't exist
        ValueError: If group not found

    Example:
        >>> units_to_add = ["F-16C_50", "F-16C_50", "F-16C_50"]
        >>> add_multiple_units_to_group_file(
        ...     "../miz-files/input/mission.miz",
        ...     "../miz-files/output/mission_modified.miz",
        ...     "Fighter-1",
        ...     units_to_add,
        ...     spacing=100.0
        ... )
    """
    from ..parsing.miz_parser import quick_modify

    def modify_func(content):
        return add_multiple_units_to_group(content, group_name, units, spacing)

    quick_modify(input_miz, output_miz, modify_func)
