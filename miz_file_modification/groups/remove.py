"""
Group removal functions for .miz files.

Functions for removing groups from missions by name, type, or coalition.
"""

import re
from typing import List

from ..utils import patterns, validation
from .list import get_groups_by_type, get_groups_by_coalition


# ============================================================================
# CORE REMOVAL FUNCTIONS
# ============================================================================

def remove_group(mission_content: str, group_name: str) -> str:
    """
    Remove a specific group by name from mission.

    Args:
        mission_content: Raw mission file content as string
        group_name: Name of the group to remove

    Returns:
        Modified mission content with group removed

    Raises:
        ValueError: If group not found in mission

    Example:
        >>> content = parser.get_mission_content()
        >>> content = remove_group(content, "Fighter-1")
        >>> parser.write_mission_content(content)
    """
    # Validate group exists
    if not validation.validate_group_exists(mission_content, group_name):
        raise ValueError(f"Group '{group_name}' not found in mission")

    # Pattern to match entire group block including trailing comment
    # Matches: [index] = { ... ["name"] = "group_name" ... }, -- end of [index]
    pattern = rf'\[(\d+)\]\s*=\s*\{{.*?\["name"\]\s*=\s*"{re.escape(group_name)}".*?\}},\s*--\s*end\s*of\s*\[\d+\]\s*\n'

    # Remove the group
    modified_content = re.sub(pattern, '', mission_content, flags=re.DOTALL)

    return modified_content


def remove_groups_by_type(mission_content: str, unit_types: List[str]) -> str:
    """
    Remove all groups of specified unit types.

    Args:
        mission_content: Raw mission file content as string
        unit_types: List of unit type categories to remove
                   (e.g., ["ship", "helicopter"])

    Returns:
        Modified mission content with specified group types removed

    Raises:
        ValueError: If any unit_type is invalid

    Example:
        >>> # Remove all ships and helicopters
        >>> content = remove_groups_by_type(content, ["ship", "helicopter"])
    """
    # Validate all unit types
    for unit_type in unit_types:
        is_valid, error = validation.validate_unit_type_category(unit_type)
        if not is_valid:
            raise ValueError(error)

    modified_content = mission_content

    # Remove groups for each unit type
    for unit_type in unit_types:
        # Find all groups of this type
        groups_to_remove = get_groups_by_type(modified_content, unit_type)

        # Remove each group
        for group_name in groups_to_remove:
            try:
                modified_content = remove_group(modified_content, group_name)
            except ValueError:
                # Group might have been removed already, continue
                continue

    return modified_content


def remove_groups_by_coalition(mission_content: str, coalition: str) -> str:
    """
    Remove all groups from a specific coalition.

    Args:
        mission_content: Raw mission file content as string
        coalition: Coalition to remove groups from (blue, red, neutrals)

    Returns:
        Modified mission content with all groups from coalition removed

    Raises:
        ValueError: If coalition name is invalid

    Example:
        >>> # Remove all red forces
        >>> content = remove_groups_by_coalition(content, "red")
    """
    # Validate coalition
    is_valid, error = validation.validate_coalition(coalition)
    if not is_valid:
        raise ValueError(error)

    # Find all groups in this coalition
    groups_to_remove = get_groups_by_coalition(mission_content, coalition)

    modified_content = mission_content

    # Remove each group
    for group_name in groups_to_remove:
        try:
            modified_content = remove_group(modified_content, group_name)
        except ValueError:
            # Group might not exist or already removed, continue
            continue

    return modified_content


def remove_empty_groups(mission_content: str) -> str:
    """
    Remove groups that have no units.

    Args:
        mission_content: Raw mission file content as string

    Returns:
        Modified mission content with empty groups removed

    Example:
        >>> # Clean up any groups that have no units
        >>> content = remove_empty_groups(content)
    """
    # Find all groups with empty units sections
    # Pattern matches: ["units"] = { }, (empty units section)
    empty_units_pattern = r'\["units"\]\s*=\s*\{\s*\}'

    modified_content = mission_content

    # Find all group blocks
    group_blocks = re.finditer(
        r'\[(\d+)\]\s*=\s*\{(.*?)\}},\s*--\s*end\s*of\s*\[\d+\]',
        mission_content,
        re.DOTALL
    )

    for match in group_blocks:
        group_content = match.group(2)

        # Check if this group has empty units section
        if re.search(empty_units_pattern, group_content):
            # Extract group name
            name_match = patterns.GROUP_NAME_PATTERN_COMPILED.search(group_content)
            if name_match:
                group_name = name_match.group(1)
                try:
                    modified_content = remove_group(modified_content, group_name)
                except ValueError:
                    # Group might have been removed, continue
                    continue

    return modified_content


def remove_groups_by_names(mission_content: str, group_names: List[str]) -> str:
    """
    Remove multiple groups by name.

    Args:
        mission_content: Raw mission file content as string
        group_names: List of group names to remove

    Returns:
        Modified mission content with specified groups removed

    Note:
        Does not raise error if a group is not found - silently skips it.
        This allows removing groups that may or may not exist.

    Example:
        >>> groups_to_remove = ["Fighter-1", "Bomber-1", "Tank-1"]
        >>> content = remove_groups_by_names(content, groups_to_remove)
    """
    modified_content = mission_content

    for group_name in group_names:
        try:
            modified_content = remove_group(modified_content, group_name)
        except ValueError:
            # Group not found, continue with next
            continue

    return modified_content


# ============================================================================
# CONVENIENCE WRAPPER FUNCTIONS
# ============================================================================

def remove_group_file(input_miz: str, output_miz: str, group_name: str) -> None:
    """
    Remove a specific group from a .miz file (convenience wrapper).

    Args:
        input_miz: Path to input .miz file
        output_miz: Path to output .miz file
        group_name: Name of the group to remove

    Raises:
        FileNotFoundError: If input_miz doesn't exist
        ValueError: If group not found in mission

    Example:
        >>> remove_group_file(
        ...     "../miz-files/input/mission.miz",
        ...     "../miz-files/output/mission_modified.miz",
        ...     "Fighter-1"
        ... )
    """
    from ..parsing.miz_parser import quick_modify

    def modify_func(content):
        return remove_group(content, group_name)

    quick_modify(input_miz, output_miz, modify_func)


def remove_groups_by_type_file(input_miz: str, output_miz: str, unit_types: List[str]) -> None:
    """
    Remove groups by type from a .miz file (convenience wrapper).

    Args:
        input_miz: Path to input .miz file
        output_miz: Path to output .miz file
        unit_types: List of unit type categories to remove

    Raises:
        FileNotFoundError: If input_miz doesn't exist
        ValueError: If any unit_type is invalid

    Example:
        >>> remove_groups_by_type_file(
        ...     "../miz-files/input/mission.miz",
        ...     "../miz-files/output/mission_no_ships.miz",
        ...     ["ship"]
        ... )
    """
    from ..parsing.miz_parser import quick_modify

    def modify_func(content):
        return remove_groups_by_type(content, unit_types)

    quick_modify(input_miz, output_miz, modify_func)


def remove_groups_by_coalition_file(input_miz: str, output_miz: str, coalition: str) -> None:
    """
    Remove groups by coalition from a .miz file (convenience wrapper).

    Args:
        input_miz: Path to input .miz file
        output_miz: Path to output .miz file
        coalition: Coalition to remove groups from

    Raises:
        FileNotFoundError: If input_miz doesn't exist
        ValueError: If coalition name is invalid

    Example:
        >>> remove_groups_by_coalition_file(
        ...     "../miz-files/input/mission.miz",
        ...     "../miz-files/output/mission_blue_only.miz",
        ...     "red"
        ... )
    """
    from ..parsing.miz_parser import quick_modify

    def modify_func(content):
        return remove_groups_by_coalition(content, coalition)

    quick_modify(input_miz, output_miz, modify_func)


def remove_empty_groups_file(input_miz: str, output_miz: str) -> None:
    """
    Remove empty groups from a .miz file (convenience wrapper).

    Args:
        input_miz: Path to input .miz file
        output_miz: Path to output .miz file

    Raises:
        FileNotFoundError: If input_miz doesn't exist

    Example:
        >>> remove_empty_groups_file(
        ...     "../miz-files/input/mission.miz",
        ...     "../miz-files/output/mission_cleaned.miz"
        ... )
    """
    from ..parsing.miz_parser import quick_modify

    def modify_func(content):
        return remove_empty_groups(content)

    quick_modify(input_miz, output_miz, modify_func)


def remove_groups_by_names_file(input_miz: str, output_miz: str, group_names: List[str]) -> None:
    """
    Remove multiple groups by name from a .miz file (convenience wrapper).

    Args:
        input_miz: Path to input .miz file
        output_miz: Path to output .miz file
        group_names: List of group names to remove

    Raises:
        FileNotFoundError: If input_miz doesn't exist

    Example:
        >>> groups = ["Fighter-1", "Bomber-1", "Tank-1"]
        >>> remove_groups_by_names_file(
        ...     "../miz-files/input/mission.miz",
        ...     "../miz-files/output/mission_modified.miz",
        ...     groups
        ... )
    """
    from ..parsing.miz_parser import quick_modify

    def modify_func(content):
        return remove_groups_by_names(content, group_names)

    quick_modify(input_miz, output_miz, modify_func)
