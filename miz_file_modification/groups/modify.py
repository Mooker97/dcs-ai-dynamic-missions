"""
Group modification functions for .miz files.

Functions for modifying existing groups: rename, move, change coalition/skill.
"""

import re
from typing import Dict, Optional

from ..utils import patterns, validation
from .list import find_group_by_name, get_group_info


# ============================================================================
# CORE MODIFICATION FUNCTIONS
# ============================================================================

def rename_group(mission_content: str, old_name: str, new_name: str) -> str:
    """
    Rename a group in the mission.

    Updates both the group name and all unit names that reference the group.
    Unit names typically follow the pattern "GroupName-1", "GroupName-2", etc.

    Args:
        mission_content: Raw mission file content as string
        old_name: Current name of the group
        new_name: New name for the group

    Returns:
        Modified mission content with group renamed

    Raises:
        ValueError: If group not found or new name is invalid/already exists

    Example:
        >>> content = parser.get_mission_content()
        >>> content = rename_group(content, "Fighter-1", "Alpha Flight")
        >>> parser.write_mission_content(content)
    """
    # Validate old group exists
    if not validation.validate_group_exists(mission_content, old_name):
        raise ValueError(f"Group '{old_name}' not found in mission")

    # Validate new name
    is_valid, error = validation.validate_group_name(new_name)
    if not is_valid:
        raise ValueError(error)

    # Check new name doesn't already exist
    if validation.validate_group_exists(mission_content, new_name):
        raise ValueError(f"Group '{new_name}' already exists in mission")

    # Find the group block
    result = find_group_by_name(mission_content, old_name)
    if not result:
        raise ValueError(f"Could not locate group '{old_name}' in mission")

    group_content, start_pos, end_pos = result

    # Replace the group name in the group definition
    modified_group = re.sub(
        rf'(\["name"\]\s*=\s*"){re.escape(old_name)}"',
        rf'\1{new_name}"',
        group_content,
        count=1  # Only replace first occurrence (the group name itself)
    )

    # Also update unit names that reference the old group name
    # Pattern: ["name"] = "OldGroupName-1" -> ["name"] = "NewGroupName-1"
    modified_group = re.sub(
        rf'(\["name"\]\s*=\s*"){re.escape(old_name)}(-\d+)"',
        rf'\1{new_name}\2"',
        modified_group
    )

    # Replace in mission content
    modified_content = (
        mission_content[:start_pos] +
        modified_group +
        mission_content[end_pos:]
    )

    return modified_content


def move_group(mission_content: str, group_name: str, new_position: Dict[str, float]) -> str:
    """
    Move a group to a new position.

    Updates the group's base position and all unit positions by calculating
    the offset from the original position.

    Args:
        mission_content: Raw mission file content as string
        group_name: Name of the group to move
        new_position: Dict with 'x', 'y', and optionally 'alt' keys

    Returns:
        Modified mission content with group moved

    Raises:
        ValueError: If group not found or position is invalid

    Example:
        >>> content = parser.get_mission_content()
        >>> content = move_group(content, "Fighter-1", {"x": -60000, "y": 40000})
        >>> parser.write_mission_content(content)
    """
    # Validate group exists
    if not validation.validate_group_exists(mission_content, group_name):
        raise ValueError(f"Group '{group_name}' not found in mission")

    # Validate position
    is_valid, error = validation.validate_position(new_position)
    if not is_valid:
        raise ValueError(error)

    # Find the group block
    result = find_group_by_name(mission_content, group_name)
    if not result:
        raise ValueError(f"Could not locate group '{group_name}' in mission")

    group_content, start_pos, end_pos = result

    # Get current group position
    current_info = get_group_info(mission_content, group_name)
    if 'position' not in current_info:
        raise ValueError(f"Could not determine current position of group '{group_name}'")

    current_x = current_info['position']['x']
    current_y = current_info['position']['y']

    # Calculate offset
    new_x = float(new_position['x'])
    new_y = float(new_position['y'])
    offset_x = new_x - current_x
    offset_y = new_y - current_y

    # Apply offset to all positions in the group
    def offset_position(match):
        """Regex replacement function to offset a position."""
        y_value = float(match.group(1))
        x_value = float(match.group(2))

        new_y_val = y_value + offset_y
        new_x_val = x_value + offset_x

        return f'["y"] = {new_y_val},\n                        ["x"] = {new_x_val}'

    # Apply offset to all y,x position pairs
    modified_group = patterns.POSITION_PATTERN_COMPILED.sub(
        offset_position,
        group_content
    )

    # Also update any standalone x and y coordinates that might exist
    # Update the group-level x and y (these are outside the position pattern)
    modified_group = re.sub(
        rf'(\["y"\]\s*=\s*){re.escape(str(current_y))}(\s*,)',
        rf'\g<1>{new_y}\2',
        modified_group
    )
    modified_group = re.sub(
        rf'(\["x"\]\s*=\s*){re.escape(str(current_x))}(\s*,)',
        rf'\g<1>{new_x}\2',
        modified_group
    )

    # Update altitude if provided
    if 'alt' in new_position:
        new_alt = float(new_position['alt'])
        # Replace all altitude values in the group
        modified_group = re.sub(
            r'(\["alt"\]\s*=\s*)[+-]?\d+\.?\d*',
            rf'\g<1>{new_alt}',
            modified_group
        )

    # Replace in mission content
    modified_content = (
        mission_content[:start_pos] +
        modified_group +
        mission_content[end_pos:]
    )

    return modified_content


def change_group_coalition(
    mission_content: str,
    group_name: str,
    new_coalition: str,
    new_country: str
) -> str:
    """
    Move a group to a different coalition.

    This is a complex operation that involves:
    1. Removing the group from its current location
    2. Adding it to the new coalition/country section

    Note: This changes only the coalition assignment, not the group's behavior
    or allegiances in mission logic.

    Args:
        mission_content: Raw mission file content as string
        group_name: Name of the group to move
        new_coalition: Target coalition (blue, red, neutrals)
        new_country: Target country within the coalition

    Returns:
        Modified mission content with group moved to new coalition

    Raises:
        ValueError: If group not found, coalition/country invalid

    Example:
        >>> # Move a captured unit to the other side
        >>> content = change_group_coalition(content, "Tank-1", "blue", "USA")
    """
    # Validate group exists
    if not validation.validate_group_exists(mission_content, group_name):
        raise ValueError(f"Group '{group_name}' not found in mission")

    # Validate new coalition
    is_valid, error = validation.validate_coalition(new_coalition)
    if not is_valid:
        raise ValueError(error)

    # Import here to avoid circular imports
    from .add import COUNTRY_IDS

    # Validate country
    if new_country not in COUNTRY_IDS.get(new_coalition, {}):
        valid_countries = list(COUNTRY_IDS.get(new_coalition, {}).keys())
        raise ValueError(
            f"Invalid country '{new_country}' for coalition '{new_coalition}'. "
            f"Valid: {valid_countries}"
        )

    # Find the group
    result = find_group_by_name(mission_content, group_name)
    if not result:
        raise ValueError(f"Could not locate group '{group_name}' in mission")

    group_content, start_pos, end_pos = result

    # Determine current unit type category by searching context
    unit_type_category = _find_group_unit_type(mission_content, start_pos)
    if not unit_type_category:
        raise ValueError(f"Could not determine unit type for group '{group_name}'")

    # Remove from current location
    from .remove import remove_group
    modified_content = remove_group(mission_content, group_name)

    # Extract group index from the content
    index_match = re.match(r'\[(\d+)\]', group_content)
    group_index = index_match.group(1) if index_match else "1"

    # Clean the group content (remove the index prefix)
    # The group content starts with [index] = { ... }
    # We need to re-add it with a new index when inserting
    clean_group = re.sub(r'^\[\d+\]\s*=\s*', '', group_content.strip())

    # Find target section and insert
    modified_content = _insert_existing_group(
        mission_content=modified_content,
        group_content=clean_group,
        coalition=new_coalition,
        country=new_country,
        unit_type_category=unit_type_category
    )

    return modified_content


def modify_group_skill(mission_content: str, group_name: str, skill: str) -> str:
    """
    Change the skill level for all units in a group.

    Args:
        mission_content: Raw mission file content as string
        group_name: Name of the group to modify
        skill: New skill level (Rookie, Trained, Average, Good, High, Excellent, Random, Player)

    Returns:
        Modified mission content with updated skill level

    Raises:
        ValueError: If group not found or skill is invalid

    Example:
        >>> content = parser.get_mission_content()
        >>> content = modify_group_skill(content, "Fighter-1", "Excellent")
        >>> parser.write_mission_content(content)
    """
    # Validate group exists
    if not validation.validate_group_exists(mission_content, group_name):
        raise ValueError(f"Group '{group_name}' not found in mission")

    # Validate skill level
    is_valid, error = validation.validate_skill_level(skill)
    if not is_valid:
        raise ValueError(error)

    # Find the group block
    result = find_group_by_name(mission_content, group_name)
    if not result:
        raise ValueError(f"Could not locate group '{group_name}' in mission")

    group_content, start_pos, end_pos = result

    # Replace all skill values in the group
    modified_group = re.sub(
        r'(\["skill"\]\s*=\s*)"[^"]+"',
        rf'\1"{skill}"',
        group_content
    )

    # Replace in mission content
    modified_content = (
        mission_content[:start_pos] +
        modified_group +
        mission_content[end_pos:]
    )

    return modified_content


def modify_group_heading(mission_content: str, group_name: str, heading: float) -> str:
    """
    Change the heading for all units in a group.

    Args:
        mission_content: Raw mission file content as string
        group_name: Name of the group to modify
        heading: New heading in radians (0 = North, pi/2 = East)

    Returns:
        Modified mission content with updated heading

    Raises:
        ValueError: If group not found or heading is invalid

    Example:
        >>> import math
        >>> content = modify_group_heading(content, "Fighter-1", math.radians(90))  # Face East
    """
    # Validate group exists
    if not validation.validate_group_exists(mission_content, group_name):
        raise ValueError(f"Group '{group_name}' not found in mission")

    # Validate heading (should be in radians, 0 to 2*pi)
    try:
        heading = float(heading)
    except (ValueError, TypeError):
        raise ValueError(f"Invalid heading: {heading}")

    if not (-6.29 <= heading <= 6.29):  # Allow some tolerance around 2*pi
        raise ValueError(f"Heading should be in radians (0 to 2*pi), got: {heading}")

    # Find the group block
    result = find_group_by_name(mission_content, group_name)
    if not result:
        raise ValueError(f"Could not locate group '{group_name}' in mission")

    group_content, start_pos, end_pos = result

    # Replace all heading values in the group
    modified_group = re.sub(
        r'(\["heading"\]\s*=\s*)[+-]?\d+\.?\d*',
        rf'\g<1>{heading}',
        group_content
    )

    # Replace in mission content
    modified_content = (
        mission_content[:start_pos] +
        modified_group +
        mission_content[end_pos:]
    )

    return modified_content


# ============================================================================
# HELPER FUNCTIONS
# ============================================================================

def _find_group_unit_type(mission_content: str, group_position: int) -> Optional[str]:
    """
    Determine the unit type category for a group based on its position.

    Searches backwards from the group position to find the nearest
    unit type section marker.

    Args:
        mission_content: Full mission content
        group_position: Character position where group starts

    Returns:
        Unit type category (plane, helicopter, ship, vehicle, static) or None
    """
    search_back = 50000  # Characters to search back
    start = max(0, group_position - search_back)
    context_section = mission_content[start:group_position]

    # Find last unit type marker
    unit_type = None
    last_type_pos = -1

    for ut in patterns.UNIT_TYPE_CATEGORIES:
        pattern = rf'\["{ut}"\]\s*='
        matches = list(re.finditer(pattern, context_section))
        if matches:
            last_match_pos = matches[-1].start()
            if last_match_pos > last_type_pos:
                last_type_pos = last_match_pos
                unit_type = ut

    return unit_type


def _insert_existing_group(
    mission_content: str,
    group_content: str,
    coalition: str,
    country: str,
    unit_type_category: str
) -> str:
    """
    Insert an existing group definition into a new coalition/country.

    Args:
        mission_content: Mission content to modify
        group_content: Group definition (without index)
        coalition: Target coalition
        country: Target country
        unit_type_category: Unit type category for the group

    Returns:
        Modified mission content
    """
    from .add import COUNTRY_IDS

    country_id = COUNTRY_IDS[coalition][country]

    # Find the coalition section
    coalition_pattern = patterns.get_coalition_section_pattern(coalition)
    coalition_match = coalition_pattern.search(mission_content)

    if not coalition_match:
        raise ValueError(f"Coalition '{coalition}' section not found")

    coalition_content = coalition_match.group(1)
    coalition_start = coalition_match.start(1)

    # Find the country section
    country_pattern = rf'\[(\d+)\]\s*=\s*\{{[^{{}}]*\["id"\]\s*=\s*{country_id}.*?\["name"\]\s*=\s*"{country}".*?\}},\s*--\s*end\s*of\s*\[\d+\]'
    country_match = re.search(country_pattern, coalition_content, re.DOTALL)

    if not country_match:
        raise ValueError(f"Country '{country}' not found in coalition '{coalition}'")

    country_content = country_match.group(0)
    country_start_in_coalition = country_match.start()

    # Find the unit type section
    unit_type_pattern = patterns.get_unit_type_section_pattern(unit_type_category)
    unit_type_match = unit_type_pattern.search(country_content)

    if not unit_type_match:
        raise ValueError(f"Unit type '{unit_type_category}' section not found")

    unit_type_content = unit_type_match.group(1)
    unit_type_start_in_country = unit_type_match.start(1)

    # Find the group section
    group_section_pattern = r'\["group"\]\s*=\s*\{(.*?)\},\s*--\s*end\s*of\s*\["group"\]'
    group_match = re.search(group_section_pattern, unit_type_content, re.DOTALL)

    if not group_match:
        raise ValueError(f"Group section not found in unit type '{unit_type_category}'")

    groups_content = group_match.group(1)
    group_section_start = group_match.start(1)

    # Find the highest group index
    group_indices = re.findall(r'\[(\d+)\]\s*=', groups_content)
    new_index = max([int(idx) for idx in group_indices]) + 1 if group_indices else 1

    # Format the group with new index
    new_group_lua = f"[{new_index}] = {group_content}"

    # Calculate absolute position
    abs_position = (
        coalition_start +
        country_start_in_coalition +
        unit_type_start_in_country +
        group_section_start +
        len(groups_content)
    )

    # Add newline if needed
    if groups_content.strip():
        new_group_lua = "\n\t\t\t\t\t\t\t" + new_group_lua

    # Build modified content
    modified_content = (
        mission_content[:abs_position] +
        new_group_lua +
        mission_content[abs_position:]
    )

    return modified_content


# ============================================================================
# CONVENIENCE WRAPPER FUNCTIONS
# ============================================================================

def rename_group_file(input_miz: str, output_miz: str, old_name: str, new_name: str) -> None:
    """
    Rename a group in a .miz file (convenience wrapper).

    Args:
        input_miz: Path to input .miz file
        output_miz: Path to output .miz file
        old_name: Current name of the group
        new_name: New name for the group

    Raises:
        FileNotFoundError: If input_miz doesn't exist
        ValueError: If group not found or new name invalid

    Example:
        >>> rename_group_file(
        ...     "../miz-files/input/mission.miz",
        ...     "../miz-files/output/mission_renamed.miz",
        ...     "Fighter-1",
        ...     "Alpha Flight"
        ... )
    """
    from ..parsing.miz_parser import quick_modify

    def modify_func(content):
        return rename_group(content, old_name, new_name)

    quick_modify(input_miz, output_miz, modify_func)


def move_group_file(
    input_miz: str,
    output_miz: str,
    group_name: str,
    new_position: Dict[str, float]
) -> None:
    """
    Move a group to a new position in a .miz file (convenience wrapper).

    Args:
        input_miz: Path to input .miz file
        output_miz: Path to output .miz file
        group_name: Name of the group to move
        new_position: Position dict with x, y, optionally alt

    Raises:
        FileNotFoundError: If input_miz doesn't exist
        ValueError: If group not found or position invalid

    Example:
        >>> move_group_file(
        ...     "../miz-files/input/mission.miz",
        ...     "../miz-files/output/mission_moved.miz",
        ...     "Fighter-1",
        ...     {"x": -60000, "y": 40000, "alt": 6000}
        ... )
    """
    from ..parsing.miz_parser import quick_modify

    def modify_func(content):
        return move_group(content, group_name, new_position)

    quick_modify(input_miz, output_miz, modify_func)


def change_group_coalition_file(
    input_miz: str,
    output_miz: str,
    group_name: str,
    new_coalition: str,
    new_country: str
) -> None:
    """
    Move a group to a different coalition in a .miz file (convenience wrapper).

    Args:
        input_miz: Path to input .miz file
        output_miz: Path to output .miz file
        group_name: Name of the group
        new_coalition: Target coalition
        new_country: Target country

    Raises:
        FileNotFoundError: If input_miz doesn't exist
        ValueError: If parameters invalid

    Example:
        >>> change_group_coalition_file(
        ...     "../miz-files/input/mission.miz",
        ...     "../miz-files/output/mission_defected.miz",
        ...     "Tank-1",
        ...     "blue",
        ...     "USA"
        ... )
    """
    from ..parsing.miz_parser import quick_modify

    def modify_func(content):
        return change_group_coalition(content, group_name, new_coalition, new_country)

    quick_modify(input_miz, output_miz, modify_func)


def modify_group_skill_file(
    input_miz: str,
    output_miz: str,
    group_name: str,
    skill: str
) -> None:
    """
    Change skill level for a group in a .miz file (convenience wrapper).

    Args:
        input_miz: Path to input .miz file
        output_miz: Path to output .miz file
        group_name: Name of the group
        skill: New skill level

    Raises:
        FileNotFoundError: If input_miz doesn't exist
        ValueError: If group not found or skill invalid

    Example:
        >>> modify_group_skill_file(
        ...     "../miz-files/input/mission.miz",
        ...     "../miz-files/output/mission_elite.miz",
        ...     "Fighter-1",
        ...     "Excellent"
        ... )
    """
    from ..parsing.miz_parser import quick_modify

    def modify_func(content):
        return modify_group_skill(content, group_name, skill)

    quick_modify(input_miz, output_miz, modify_func)


def modify_group_heading_file(
    input_miz: str,
    output_miz: str,
    group_name: str,
    heading: float
) -> None:
    """
    Change heading for a group in a .miz file (convenience wrapper).

    Args:
        input_miz: Path to input .miz file
        output_miz: Path to output .miz file
        group_name: Name of the group
        heading: New heading in radians

    Raises:
        FileNotFoundError: If input_miz doesn't exist
        ValueError: If group not found or heading invalid

    Example:
        >>> import math
        >>> modify_group_heading_file(
        ...     "../miz-files/input/mission.miz",
        ...     "../miz-files/output/mission_turned.miz",
        ...     "Fighter-1",
        ...     math.radians(180)  # Face South
        ... )
    """
    from ..parsing.miz_parser import quick_modify

    def modify_func(content):
        return modify_group_heading(content, group_name, heading)

    quick_modify(input_miz, output_miz, modify_func)
