"""
Unit modification functions for .miz files.

Functions for modifying unit properties like loadout, skill, position, etc.
"""

import re
from typing import Dict, Optional

from ..utils import patterns, validation
from .remove import _find_unit_by_name


# ============================================================================
# CORE MODIFICATION FUNCTIONS
# ============================================================================

def modify_unit_skill(mission_content: str, unit_name: str, skill: str) -> str:
    """
    Modify a unit's skill level.

    Args:
        mission_content: Raw mission file content as string
        unit_name: Name of the unit to modify
        skill: New skill level (Rookie, Trained, Average, Good, High, Excellent, Random, Player)

    Returns:
        Modified mission content with updated skill

    Raises:
        ValueError: If unit not found or skill level is invalid

    Example:
        >>> content = modify_unit_skill(content, "Fighter-1-1", "Good")
    """
    # Validate skill level
    if skill not in patterns.SKILL_LEVELS:
        raise ValueError(f"Invalid skill level '{skill}'. Valid: {', '.join(patterns.SKILL_LEVELS)}")

    # Find the unit
    unit_result = _find_unit_by_name(mission_content, unit_name)
    if not unit_result:
        raise ValueError(f"Unit '{unit_name}' not found in mission")

    unit_content, unit_start, unit_end = unit_result

    # Find and replace skill field
    skill_match = patterns.SKILL_PATTERN_COMPILED.search(unit_content)
    if not skill_match:
        raise ValueError(f"Unit '{unit_name}' has no skill field")

    # Calculate absolute positions
    old_skill_start = unit_start + skill_match.start(1)
    old_skill_end = unit_start + skill_match.end(1)

    # Replace skill value
    modified_content = (
        mission_content[:old_skill_start] +
        skill +
        mission_content[old_skill_end:]
    )

    return modified_content


def modify_unit_position(mission_content: str, unit_name: str, new_position: Dict[str, float]) -> str:
    """
    Modify a unit's position.

    Args:
        mission_content: Raw mission file content as string
        unit_name: Name of the unit to modify
        new_position: Dict with 'x' and 'y' coordinates in meters

    Returns:
        Modified mission content with updated position

    Raises:
        ValueError: If unit not found or position is invalid

    Example:
        >>> new_pos = {"x": -50000, "y": 30000}
        >>> content = modify_unit_position(content, "Fighter-1-1", new_pos)
    """
    # Validate position
    if 'x' not in new_position or 'y' not in new_position:
        raise ValueError("new_position must contain 'x' and 'y' keys")

    # Find the unit
    unit_result = _find_unit_by_name(mission_content, unit_name)
    if not unit_result:
        raise ValueError(f"Unit '{unit_name}' not found in mission")

    unit_content, unit_start, unit_end = unit_result

    # Find and replace x and y coordinates
    # Note: DCS uses ["y"] then ["x"] order in files
    y_match = patterns.Y_COORD_PATTERN_COMPILED.search(unit_content)
    x_match = patterns.X_COORD_PATTERN_COMPILED.search(unit_content)

    if not y_match or not x_match:
        raise ValueError(f"Unit '{unit_name}' has incomplete position information")

    # Replace y coordinate (do this first since it appears first)
    modified_content = mission_content
    y_start = unit_start + y_match.start(1)
    y_end = unit_start + y_match.end(1)

    modified_content = (
        modified_content[:y_start] +
        str(new_position['y']) +
        modified_content[y_end:]
    )

    # Recalculate x position after y change
    len_diff = len(str(new_position['y'])) - len(y_match.group(1))
    x_start = unit_start + x_match.start(1) + len_diff
    x_end = unit_start + x_match.end(1) + len_diff

    modified_content = (
        modified_content[:x_start] +
        str(new_position['x']) +
        modified_content[x_end:]
    )

    return modified_content


def modify_unit_heading(mission_content: str, unit_name: str, heading: float) -> str:
    """
    Modify a unit's heading.

    Args:
        mission_content: Raw mission file content as string
        unit_name: Name of the unit to modify
        heading: New heading in radians (0 = North, π/2 = East, π = South, 3π/2 = West)

    Returns:
        Modified mission content with updated heading

    Raises:
        ValueError: If unit not found

    Example:
        >>> import math
        >>> content = modify_unit_heading(content, "Fighter-1-1", math.pi/2)  # Face East
    """
    # Find the unit
    unit_result = _find_unit_by_name(mission_content, unit_name)
    if not unit_result:
        raise ValueError(f"Unit '{unit_name}' not found in mission")

    unit_content, unit_start, unit_end = unit_result

    # Find and replace heading field
    heading_match = patterns.HEADING_PATTERN_COMPILED.search(unit_content)
    if not heading_match:
        raise ValueError(f"Unit '{unit_name}' has no heading field")

    # Calculate absolute positions
    old_heading_start = unit_start + heading_match.start(1)
    old_heading_end = unit_start + heading_match.end(1)

    # Replace heading value
    modified_content = (
        mission_content[:old_heading_start] +
        str(heading) +
        mission_content[old_heading_end:]
    )

    return modified_content


def modify_unit_loadout(mission_content: str, unit_name: str, loadout: Dict) -> str:
    """
    Modify a unit's weapon loadout (for aircraft/helicopters).

    Args:
        mission_content: Raw mission file content as string
        unit_name: Name of the unit to modify
        loadout: Loadout configuration dict with structure:
                {
                    "pylons": {1: "CLSID_...", 7: "CLSID_...", ...},  # pylon_num: weapon_CLSID
                    "fuel": 3249,  # Optional: fuel quantity
                    "chaff": 60,   # Optional: chaff count
                    "flare": 60,   # Optional: flare count
                    "gun": 100     # Optional: gun ammo percentage
                }

    Returns:
        Modified mission content with updated loadout

    Raises:
        ValueError: If unit not found or doesn't have payload section

    Note:
        For valid CLSID values, see: https://www.airgoons.com/w/DCS_Reference/Stores_List

    Example:
        >>> loadout = {
        ...     "pylons": {
        ...         1: "{LAU-115 - AIM-7MH}",
        ...         7: "{LAU-115 - AIM-7MH}",
        ...         2: "{LAU-115 - AIM-9M}",
        ...         8: "{LAU-115 - AIM-9M}"
        ...     },
        ...     "fuel": 3000,
        ...     "chaff": 120,
        ...     "flare": 120
        ... }
        >>> content = modify_unit_loadout(content, "Fighter-1-1", loadout)
    """
    # Find the unit
    unit_result = _find_unit_by_name(mission_content, unit_name)
    if not unit_result:
        raise ValueError(f"Unit '{unit_name}' not found in mission")

    unit_content, unit_start, unit_end = unit_result

    # Find payload section
    payload_match = patterns.PAYLOAD_SECTION_PATTERN_COMPILED.search(unit_content)
    if not payload_match:
        raise ValueError(f"Unit '{unit_name}' has no payload section (not an aircraft/helicopter)")

    payload_content = payload_match.group(1)
    payload_start = unit_start + payload_match.start(1)
    payload_end = unit_start + payload_match.end(1)

    # Build new payload section
    new_payload_parts = []

    # Handle pylons
    if "pylons" in loadout and loadout["pylons"]:
        new_payload_parts.append('\t\t\t\t\t["pylons"] =\n\t\t\t\t\t{')

        for pylon_num, clsid in sorted(loadout["pylons"].items()):
            pylon_block = f'''
\t\t\t\t\t\t[{pylon_num}] =
\t\t\t\t\t\t{{
\t\t\t\t\t\t\t["CLSID"] = "{clsid}",
\t\t\t\t\t\t}}, -- end of [{pylon_num}]'''
            new_payload_parts.append(pylon_block)

        new_payload_parts.append('\n\t\t\t\t\t}, -- end of ["pylons"]')
    else:
        # Empty pylons
        new_payload_parts.append('\t\t\t\t\t["pylons"] =\n\t\t\t\t\t{\n\t\t\t\t\t}, -- end of ["pylons"]')

    # Handle fuel
    fuel = loadout.get("fuel")
    if fuel is not None:
        new_payload_parts.append(f',\n\t\t\t\t\t["fuel"] = {fuel}')
    else:
        # Try to preserve existing fuel
        fuel_match = patterns.FUEL_PATTERN_COMPILED.search(payload_content)
        if fuel_match:
            new_payload_parts.append(f',\n\t\t\t\t\t["fuel"] = {fuel_match.group(1)}')

    # Handle flare
    flare = loadout.get("flare")
    if flare is not None:
        new_payload_parts.append(f',\n\t\t\t\t\t["flare"] = {flare}')
    else:
        # Try to preserve existing flare
        flare_match = patterns.FLARE_PATTERN_COMPILED.search(payload_content)
        if flare_match:
            new_payload_parts.append(f',\n\t\t\t\t\t["flare"] = {flare_match.group(1)}')

    # Handle chaff
    chaff = loadout.get("chaff")
    if chaff is not None:
        new_payload_parts.append(f',\n\t\t\t\t\t["chaff"] = {chaff}')
    else:
        # Try to preserve existing chaff
        chaff_match = patterns.CHAFF_PATTERN_COMPILED.search(payload_content)
        if chaff_match:
            new_payload_parts.append(f',\n\t\t\t\t\t["chaff"] = {chaff_match.group(1)}')

    # Handle gun
    gun = loadout.get("gun")
    if gun is not None:
        new_payload_parts.append(f',\n\t\t\t\t\t["gun"] = {gun}')
    else:
        # Try to preserve existing gun
        gun_match = patterns.GUN_AMMO_PATTERN_COMPILED.search(payload_content)
        if gun_match:
            new_payload_parts.append(f',\n\t\t\t\t\t["gun"] = {gun_match.group(1)}')

    # Construct new payload content
    new_payload_content = ''.join(new_payload_parts) + ',\n\t\t\t\t'

    # Replace payload in mission content
    modified_content = (
        mission_content[:payload_start] +
        new_payload_content +
        mission_content[payload_end:]
    )

    return modified_content


def modify_unit_type(mission_content: str, unit_name: str, new_unit_type: str) -> str:
    """
    Change a unit's type (e.g., change F-16 to F-15).

    Args:
        mission_content: Raw mission file content as string
        unit_name: Name of the unit to modify
        new_unit_type: New DCS unit type string

    Returns:
        Modified mission content with updated unit type

    Raises:
        ValueError: If unit not found

    Warning:
        Changing unit type may create invalid loadout configurations.
        Consider clearing or updating loadout after type change.

    Example:
        >>> content = modify_unit_type(content, "Fighter-1-1", "F-15C")
    """
    # Find the unit
    unit_result = _find_unit_by_name(mission_content, unit_name)
    if not unit_result:
        raise ValueError(f"Unit '{unit_name}' not found in mission")

    unit_content, unit_start, unit_end = unit_result

    # Find and replace type field
    type_match = patterns.UNIT_TYPE_PATTERN_COMPILED.search(unit_content)
    if not type_match:
        raise ValueError(f"Unit '{unit_name}' has no type field")

    # Calculate absolute positions
    old_type_start = unit_start + type_match.start(1)
    old_type_end = unit_start + type_match.end(1)

    # Replace type value
    modified_content = (
        mission_content[:old_type_start] +
        new_unit_type +
        mission_content[old_type_end:]
    )

    return modified_content


def modify_unit_name(mission_content: str, old_name: str, new_name: str) -> str:
    """
    Rename a unit.

    Args:
        mission_content: Raw mission file content as string
        old_name: Current unit name
        new_name: New unit name

    Returns:
        Modified mission content with renamed unit

    Raises:
        ValueError: If unit not found

    Example:
        >>> content = modify_unit_name(content, "Fighter-1-1", "Viper-1")
    """
    # Find the unit
    unit_result = _find_unit_by_name(mission_content, old_name)
    if not unit_result:
        raise ValueError(f"Unit '{old_name}' not found in mission")

    unit_content, unit_start, unit_end = unit_result

    # Find and replace name field
    name_match = patterns.UNIT_NAME_PATTERN_COMPILED.search(unit_content)
    if not name_match:
        raise ValueError(f"Unit '{old_name}' has no name field")

    # Calculate absolute positions
    old_name_start = unit_start + name_match.start(1)
    old_name_end = unit_start + name_match.end(1)

    # Replace name value
    modified_content = (
        mission_content[:old_name_start] +
        new_name +
        mission_content[old_name_end:]
    )

    return modified_content


# ============================================================================
# CONVENIENCE WRAPPER FUNCTIONS
# ============================================================================

def modify_unit_skill_file(input_miz: str, output_miz: str, unit_name: str, skill: str) -> None:
    """
    Modify unit skill in a .miz file (convenience wrapper).

    Args:
        input_miz: Path to input .miz file
        output_miz: Path to output .miz file
        unit_name: Name of the unit to modify
        skill: New skill level

    Raises:
        FileNotFoundError: If input_miz doesn't exist
        ValueError: If unit not found or skill invalid

    Example:
        >>> modify_unit_skill_file(
        ...     "../miz-files/input/mission.miz",
        ...     "../miz-files/output/mission_modified.miz",
        ...     "Fighter-1-1",
        ...     "Excellent"
        ... )
    """
    from ..parsing.miz_parser import quick_modify

    def modify_func(content):
        return modify_unit_skill(content, unit_name, skill)

    quick_modify(input_miz, output_miz, modify_func)


def modify_unit_position_file(input_miz: str, output_miz: str, unit_name: str,
                              new_position: Dict[str, float]) -> None:
    """
    Modify unit position in a .miz file (convenience wrapper).

    Args:
        input_miz: Path to input .miz file
        output_miz: Path to output .miz file
        unit_name: Name of the unit to modify
        new_position: Dict with 'x' and 'y' coordinates

    Raises:
        FileNotFoundError: If input_miz doesn't exist
        ValueError: If unit not found or position invalid

    Example:
        >>> modify_unit_position_file(
        ...     "../miz-files/input/mission.miz",
        ...     "../miz-files/output/mission_modified.miz",
        ...     "Fighter-1-1",
        ...     {"x": -50000, "y": 30000}
        ... )
    """
    from ..parsing.miz_parser import quick_modify

    def modify_func(content):
        return modify_unit_position(content, unit_name, new_position)

    quick_modify(input_miz, output_miz, modify_func)


def modify_unit_loadout_file(input_miz: str, output_miz: str, unit_name: str,
                             loadout: Dict) -> None:
    """
    Modify unit loadout in a .miz file (convenience wrapper).

    Args:
        input_miz: Path to input .miz file
        output_miz: Path to output .miz file
        unit_name: Name of the unit to modify
        loadout: Loadout configuration dict

    Raises:
        FileNotFoundError: If input_miz doesn't exist
        ValueError: If unit not found or doesn't have payload

    Example:
        >>> loadout = {
        ...     "pylons": {1: "{LAU-115 - AIM-7MH}", 7: "{LAU-115 - AIM-7MH}"},
        ...     "fuel": 3000
        ... }
        >>> modify_unit_loadout_file(
        ...     "../miz-files/input/mission.miz",
        ...     "../miz-files/output/mission_modified.miz",
        ...     "Fighter-1-1",
        ...     loadout
        ... )
    """
    from ..parsing.miz_parser import quick_modify

    def modify_func(content):
        return modify_unit_loadout(content, unit_name, loadout)

    quick_modify(input_miz, output_miz, modify_func)


def modify_unit_heading_file(input_miz: str, output_miz: str, unit_name: str, heading: float) -> None:
    """
    Modify unit heading in a .miz file (convenience wrapper).

    Args:
        input_miz: Path to input .miz file
        output_miz: Path to output .miz file
        unit_name: Name of the unit to modify
        heading: New heading in radians

    Raises:
        FileNotFoundError: If input_miz doesn't exist
        ValueError: If unit not found

    Example:
        >>> import math
        >>> modify_unit_heading_file(
        ...     "../miz-files/input/mission.miz",
        ...     "../miz-files/output/mission_modified.miz",
        ...     "Fighter-1-1",
        ...     math.pi/2  # East
        ... )
    """
    from ..parsing.miz_parser import quick_modify

    def modify_func(content):
        return modify_unit_heading(content, unit_name, heading)

    quick_modify(input_miz, output_miz, modify_func)


def modify_unit_type_file(input_miz: str, output_miz: str, unit_name: str, new_unit_type: str) -> None:
    """
    Modify unit type in a .miz file (convenience wrapper).

    Args:
        input_miz: Path to input .miz file
        output_miz: Path to output .miz file
        unit_name: Name of the unit to modify
        new_unit_type: New DCS unit type string

    Raises:
        FileNotFoundError: If input_miz doesn't exist
        ValueError: If unit not found

    Example:
        >>> modify_unit_type_file(
        ...     "../miz-files/input/mission.miz",
        ...     "../miz-files/output/mission_modified.miz",
        ...     "Fighter-1-1",
        ...     "F-15C"
        ... )
    """
    from ..parsing.miz_parser import quick_modify

    def modify_func(content):
        return modify_unit_type(content, unit_name, new_unit_type)

    quick_modify(input_miz, output_miz, modify_func)


def modify_unit_name_file(input_miz: str, output_miz: str, old_name: str, new_name: str) -> None:
    """
    Rename unit in a .miz file (convenience wrapper).

    Args:
        input_miz: Path to input .miz file
        output_miz: Path to output .miz file
        old_name: Current unit name
        new_name: New unit name

    Raises:
        FileNotFoundError: If input_miz doesn't exist
        ValueError: If unit not found

    Example:
        >>> modify_unit_name_file(
        ...     "../miz-files/input/mission.miz",
        ...     "../miz-files/output/mission_modified.miz",
        ...     "Fighter-1-1",
        ...     "Viper-1"
        ... )
    """
    from ..parsing.miz_parser import quick_modify

    def modify_func(content):
        return modify_unit_name(content, old_name, new_name)

    quick_modify(input_miz, output_miz, modify_func)
