"""
Unit removal functions for .miz files.

Functions for removing units from groups in missions.
"""

import re
from typing import Optional, Tuple

from ..utils import patterns, validation
from ..groups.list import find_group_by_name


# ============================================================================
# HELPER FUNCTIONS
# ============================================================================

def _find_unit_by_name(mission_content: str, unit_name: str) -> Optional[Tuple[str, int, int]]:
    """
    Find a unit by name and return its content and position.

    Args:
        mission_content: Raw mission file content as string
        unit_name: Name of the unit to find

    Returns:
        Tuple of (unit_content, start_pos, end_pos) if found, None if not found
        - unit_content: Full unit definition including [index] = { ... },
        - start_pos: Character position where unit starts
        - end_pos: Character position where unit ends

    Example:
        >>> result = _find_unit_by_name(content, "Fighter-1-2")
        >>> if result:
        >>>     unit_content, start, end = result
        >>>     print(f"Found unit at position {start}")
    """
    # Pattern to match: [index] = { ... ["name"] = "unit_name" ... },
    # Uses proper brace counting for nested structures
    name_pattern = rf'\["name"\]\s*=\s*"{re.escape(unit_name)}"'
    name_match = re.search(name_pattern, mission_content)

    if not name_match:
        return None

    name_pos = name_match.start()

    # Search backwards to find the unit block start [index] = {
    # Look for [number] = { before the name
    search_start = max(0, name_pos - 5000)  # Search back up to 5000 chars
    section = mission_content[search_start:name_pos]

    # Find all [index] = { patterns in this section
    unit_starts = list(re.finditer(r'\[(\d+)\]\s*=\s*\{', section))

    if not unit_starts:
        return None

    # The last one before name_pos is our unit
    last_start = unit_starts[-1]
    unit_index = last_start.group(1)
    unit_start = search_start + last_start.start()

    # Find the opening brace
    open_brace = mission_content.index('{', unit_start)

    # Count braces to find matching close
    depth = 0
    for i in range(open_brace, len(mission_content)):
        if mission_content[i] == '{':
            depth += 1
        elif mission_content[i] == '}':
            depth -= 1
            if depth == 0:
                # Found the closing brace
                # Check for trailing comma and comment
                unit_end = i + 1

                # Include trailing comma if present
                if unit_end < len(mission_content) and mission_content[unit_end] == ',':
                    unit_end += 1

                # Include end-of-unit comment if present
                end_marker = re.match(r'\s*--\s*end\s*of\s*\[\d+\]\s*\n?', mission_content[unit_end:])
                if end_marker:
                    unit_end += end_marker.end()

                return (mission_content[unit_start:unit_end], unit_start, unit_end)

    return None


# ============================================================================
# CORE REMOVAL FUNCTIONS
# ============================================================================

def remove_unit_from_group(mission_content: str, group_name: str, unit_index: int) -> str:
    """
    Remove a unit from a group by its index.

    Args:
        mission_content: Raw mission file content as string
        group_name: Name of the group containing the unit
        unit_index: Index of the unit to remove (e.g., 1, 2, 3)

    Returns:
        Modified mission content with unit removed

    Raises:
        ValueError: If group not found or unit index doesn't exist

    Example:
        >>> # Remove the 2nd unit from Fighter-1 group
        >>> content = remove_unit_from_group(content, "Fighter-1", 2)
    """
    # Find the group
    group_result = find_group_by_name(mission_content, group_name)
    if not group_result:
        raise ValueError(f"Group '{group_name}' not found in mission")

    group_content, group_start, group_end = group_result

    # Find units section in group
    units_match = patterns.UNITS_SECTION_PATTERN_COMPILED.search(group_content)
    if not units_match:
        raise ValueError(f"Group '{group_name}' has no units section")

    units_content = units_match.group(1)

    # Find the specific unit by index
    # Pattern: [index] = { ... },
    unit_pattern = rf'\[{unit_index}\]\s*=\s*\{{(.*?)\}},'
    unit_match = re.search(unit_pattern, units_content, re.DOTALL)

    if not unit_match:
        raise ValueError(f"Unit index {unit_index} not found in group '{group_name}'")

    # Remove the unit block
    # Get the full match including opening [index] = {
    unit_start_in_units = unit_match.start()
    unit_end_in_units = unit_match.end()

    # Check for trailing comment
    remaining = units_content[unit_end_in_units:]
    comment_match = re.match(r'\s*--\s*end\s*of\s*\[\d+\]\s*\n?', remaining)
    if comment_match:
        unit_end_in_units += comment_match.end()

    # Remove the unit
    modified_units_content = (
        units_content[:unit_start_in_units] +
        units_content[unit_end_in_units:]
    )

    # Replace units section in group content
    modified_group_content = group_content[:units_match.start(1)] + modified_units_content + group_content[units_match.end(1):]

    # Replace group in mission content
    modified_content = mission_content[:group_start] + modified_group_content + mission_content[group_end:]

    return modified_content


def remove_unit_by_name(mission_content: str, unit_name: str) -> str:
    """
    Remove a unit by name from mission.

    Args:
        mission_content: Raw mission file content as string
        unit_name: Name of the unit to remove

    Returns:
        Modified mission content with unit removed

    Raises:
        ValueError: If unit not found in mission

    Example:
        >>> # Remove a specific unit
        >>> content = remove_unit_by_name(content, "Fighter-1-2")
    """
    # Find the unit
    unit_result = _find_unit_by_name(mission_content, unit_name)

    if not unit_result:
        raise ValueError(f"Unit '{unit_name}' not found in mission")

    unit_content, unit_start, unit_end = unit_result

    # Remove the unit
    modified_content = mission_content[:unit_start] + mission_content[unit_end:]

    return modified_content


def remove_units_by_type(mission_content: str, unit_type: str) -> str:
    """
    Remove all units of a specific type from mission.

    Args:
        mission_content: Raw mission file content as string
        unit_type: Unit type to remove (e.g., "F-16C_50", "M-1 Abrams")

    Returns:
        Modified mission content with all units of that type removed

    Example:
        >>> # Remove all F-16s
        >>> content = remove_units_by_type(content, "F-16C_50")
    """
    modified_content = mission_content

    # Find all units sections
    for units_match in patterns.UNITS_SECTION_PATTERN_COMPILED.finditer(mission_content):
        units_content = units_match.group(1)

        # Find all units of this type
        for unit_match in patterns.UNIT_BLOCK_PATTERN_COMPILED.finditer(units_content):
            unit_content = unit_match.group(2)

            # Check if this unit is of the target type
            type_match = patterns.UNIT_TYPE_PATTERN_COMPILED.search(unit_content)
            if type_match and type_match.group(1) == unit_type:
                # Extract unit name
                name_match = patterns.UNIT_NAME_PATTERN_COMPILED.search(unit_content)
                if name_match:
                    unit_name = name_match.group(1)
                    try:
                        modified_content = remove_unit_by_name(modified_content, unit_name)
                    except ValueError:
                        # Unit might have been removed already, continue
                        continue

    return modified_content


def remove_all_units_from_group(mission_content: str, group_name: str) -> str:
    """
    Remove all units from a group (leaves group with empty units section).

    Args:
        mission_content: Raw mission file content as string
        group_name: Name of the group to clear

    Returns:
        Modified mission content with all units removed from group

    Raises:
        ValueError: If group not found

    Note:
        This leaves the group with an empty units section. To remove the
        entire group, use groups.remove.remove_group() instead.

    Example:
        >>> # Clear all units from a group
        >>> content = remove_all_units_from_group(content, "Fighter-1")
    """
    # Find the group
    group_result = find_group_by_name(mission_content, group_name)
    if not group_result:
        raise ValueError(f"Group '{group_name}' not found in mission")

    group_content, group_start, group_end = group_result

    # Find units section in group
    units_match = patterns.UNITS_SECTION_PATTERN_COMPILED.search(group_content)
    if not units_match:
        raise ValueError(f"Group '{group_name}' has no units section")

    # Replace units content with empty section
    empty_units = '\n\t\t\t'  # Proper indentation for empty units
    modified_group_content = (
        group_content[:units_match.start(1)] +
        empty_units +
        group_content[units_match.end(1):]
    )

    # Replace group in mission content
    modified_content = (
        mission_content[:group_start] +
        modified_group_content +
        mission_content[group_end:]
    )

    return modified_content


# ============================================================================
# CONVENIENCE WRAPPER FUNCTIONS
# ============================================================================

def remove_unit_from_group_file(input_miz: str, output_miz: str,
                                group_name: str, unit_index: int) -> None:
    """
    Remove unit from group by index in a .miz file (convenience wrapper).

    Args:
        input_miz: Path to input .miz file
        output_miz: Path to output .miz file
        group_name: Name of the group containing the unit
        unit_index: Index of the unit to remove

    Raises:
        FileNotFoundError: If input_miz doesn't exist
        ValueError: If group not found or unit index doesn't exist

    Example:
        >>> remove_unit_from_group_file(
        ...     "../miz-files/input/mission.miz",
        ...     "../miz-files/output/mission_modified.miz",
        ...     "Fighter-1",
        ...     2
        ... )
    """
    from ..parsing.miz_parser import quick_modify

    def modify_func(content):
        return remove_unit_from_group(content, group_name, unit_index)

    quick_modify(input_miz, output_miz, modify_func)


def remove_unit_by_name_file(input_miz: str, output_miz: str, unit_name: str) -> None:
    """
    Remove unit by name from a .miz file (convenience wrapper).

    Args:
        input_miz: Path to input .miz file
        output_miz: Path to output .miz file
        unit_name: Name of the unit to remove

    Raises:
        FileNotFoundError: If input_miz doesn't exist
        ValueError: If unit not found

    Example:
        >>> remove_unit_by_name_file(
        ...     "../miz-files/input/mission.miz",
        ...     "../miz-files/output/mission_modified.miz",
        ...     "Fighter-1-2"
        ... )
    """
    from ..parsing.miz_parser import quick_modify

    def modify_func(content):
        return remove_unit_by_name(content, unit_name)

    quick_modify(input_miz, output_miz, modify_func)


def remove_units_by_type_file(input_miz: str, output_miz: str, unit_type: str) -> None:
    """
    Remove all units of a type from a .miz file (convenience wrapper).

    Args:
        input_miz: Path to input .miz file
        output_miz: Path to output .miz file
        unit_type: Unit type to remove

    Raises:
        FileNotFoundError: If input_miz doesn't exist

    Example:
        >>> remove_units_by_type_file(
        ...     "../miz-files/input/mission.miz",
        ...     "../miz-files/output/mission_no_f16.miz",
        ...     "F-16C_50"
        ... )
    """
    from ..parsing.miz_parser import quick_modify

    def modify_func(content):
        return remove_units_by_type(content, unit_type)

    quick_modify(input_miz, output_miz, modify_func)


def remove_all_units_from_group_file(input_miz: str, output_miz: str, group_name: str) -> None:
    """
    Remove all units from a group in a .miz file (convenience wrapper).

    Args:
        input_miz: Path to input .miz file
        output_miz: Path to output .miz file
        group_name: Name of the group to clear

    Raises:
        FileNotFoundError: If input_miz doesn't exist
        ValueError: If group not found

    Example:
        >>> remove_all_units_from_group_file(
        ...     "../miz-files/input/mission.miz",
        ...     "../miz-files/output/mission_cleared.miz",
        ...     "Fighter-1"
        ... )
    """
    from ..parsing.miz_parser import quick_modify

    def modify_func(content):
        return remove_all_units_from_group(content, group_name)

    quick_modify(input_miz, output_miz, modify_func)
