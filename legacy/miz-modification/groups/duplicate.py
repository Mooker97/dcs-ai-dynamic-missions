"""
Group duplication functions for .miz files.

Functions for duplicating existing groups with optional position offsets.
"""

import re
from typing import Optional, Dict

from ..utils import patterns, validation, id_manager
from .list import find_group_by_name


# ============================================================================
# CORE DUPLICATION FUNCTIONS
# ============================================================================

def duplicate_group(
    mission_content: str,
    group_name: str,
    new_group_name: Optional[str] = None,
    position_offset: Optional[Dict[str, float]] = None
) -> str:
    """
    Duplicate an existing group with new name and optional position offset.

    Creates a copy of the specified group with:
    - New unique group name
    - New unique group ID
    - New unique unit IDs for all units
    - Optional position offset for spawning at different location

    Args:
        mission_content: Raw mission file content as string
        group_name: Name of the group to duplicate
        new_group_name: New name for duplicated group. If None, generates
                       name as "{group_name}-Copy" or "{group_name}-Copy-2" etc.
        position_offset: Optional dict with "x" and/or "y" offset values.
                        Example: {"x": 1000, "y": 2000} moves group 1km east, 2km north

    Returns:
        Modified mission content with duplicated group added

    Raises:
        ValueError: If source group not found or new name already exists

    Example:
        >>> # Simple duplication
        >>> content = duplicate_group(content, "Fighter-1", "Fighter-2")
        >>>
        >>> # Duplicate with position offset (1km east, 2km north)
        >>> content = duplicate_group(
        ...     content,
        ...     "Tank-1",
        ...     "Tank-2",
        ...     position_offset={"x": 1000, "y": 2000}
        ... )
        >>>
        >>> # Auto-generate name
        >>> content = duplicate_group(content, "Bomber-1")  # Creates "Bomber-1-Copy"
    """
    # Validate source group exists
    if not validation.validate_group_exists(mission_content, group_name):
        raise ValueError(f"Group '{group_name}' not found in mission")

    # Find the source group
    result = find_group_by_name(mission_content, group_name)
    if not result:
        raise ValueError(f"Group '{group_name}' not found in mission")

    source_group_content, start_pos, end_pos = result

    # Generate new group name if not provided
    if new_group_name is None:
        new_group_name = _generate_copy_name(mission_content, group_name)
    else:
        # Validate new name
        is_valid, error = validation.validate_group_name(new_group_name)
        if not is_valid:
            raise ValueError(error)

        # Check new name doesn't already exist
        if validation.validate_group_exists(mission_content, new_group_name):
            raise ValueError(f"Group '{new_group_name}' already exists in mission")

    # Validate position offset if provided
    if position_offset is not None:
        if not isinstance(position_offset, dict):
            raise ValueError("position_offset must be a dictionary")

        if "x" not in position_offset and "y" not in position_offset:
            raise ValueError("position_offset must contain at least 'x' or 'y' key")

        # Validate offset values
        for key, value in position_offset.items():
            if key not in ["x", "y"]:
                raise ValueError(f"Invalid position_offset key: {key}. Must be 'x' or 'y'")
            try:
                float(value)
            except (ValueError, TypeError):
                raise ValueError(f"Invalid position_offset value for {key}: {value}")

    # Generate new IDs
    new_group_id = id_manager.generate_new_group_id(mission_content)

    # Count units in source group
    units_section_match = patterns.UNITS_SECTION_PATTERN_COMPILED.search(source_group_content)
    if not units_section_match:
        raise ValueError(f"Group '{group_name}' has no units section")

    units_content = units_section_match.group(1)
    unit_blocks = patterns.UNIT_BLOCK_PATTERN_COMPILED.findall(units_content)
    unit_count = len(unit_blocks)

    new_unit_ids = id_manager.generate_new_unit_ids(mission_content, unit_count)

    # Create duplicated group content
    duplicated_group = source_group_content

    # Replace group name
    duplicated_group = re.sub(
        r'\["name"\]\s*=\s*"[^"]+"',
        f'["name"] = "{new_group_name}"',
        duplicated_group,
        count=1  # Only replace first occurrence (the group name, not unit names)
    )

    # Replace group ID
    duplicated_group = re.sub(
        r'\["groupId"\]\s*=\s*\d+',
        f'["groupId"] = {new_group_id}',
        duplicated_group
    )

    # Replace unit IDs
    unit_id_matches = list(patterns.UNIT_ID_PATTERN_COMPILED.finditer(duplicated_group))

    # Replace in reverse order to maintain positions
    for i, match in enumerate(reversed(unit_id_matches)):
        old_unit_id = match.group(1)
        new_unit_id = new_unit_ids[-(i+1)]  # Get corresponding new ID

        # Replace this specific unit ID
        duplicated_group = (
            duplicated_group[:match.start()] +
            f'["unitId"] = {new_unit_id}' +
            duplicated_group[match.end():]
        )

    # Update unit names to include new group name
    duplicated_group = _update_unit_names(duplicated_group, group_name, new_group_name)

    # Apply position offset if provided
    if position_offset:
        duplicated_group = _apply_position_offset(duplicated_group, position_offset)

    # Find insertion point (after the source group)
    insertion_point = end_pos

    # Insert duplicated group
    modified_content = (
        mission_content[:insertion_point] +
        "\n" +  # Add newline before new group
        duplicated_group +
        mission_content[insertion_point:]
    )

    return modified_content


# ============================================================================
# HELPER FUNCTIONS
# ============================================================================

def _generate_copy_name(mission_content: str, base_name: str) -> str:
    """
    Generate a unique copy name for a group.

    Args:
        mission_content: Mission content to check for existing names
        base_name: Base name to generate copy from

    Returns:
        Unique name like "GroupName-Copy" or "GroupName-Copy-2"
    """
    # Try simple "-Copy" suffix first
    candidate = f"{base_name}-Copy"

    if not validation.validate_group_exists(mission_content, candidate):
        return candidate

    # Try numbered suffixes
    counter = 2
    while True:
        candidate = f"{base_name}-Copy-{counter}"
        if not validation.validate_group_exists(mission_content, candidate):
            return candidate
        counter += 1

        # Safety limit
        if counter > 1000:
            raise ValueError(f"Could not generate unique copy name for '{base_name}'")


def _update_unit_names(group_content: str, old_group_name: str, new_group_name: str) -> str:
    """
    Update unit names within a group to reflect new group name.

    DCS typically names units as "GroupName-1", "GroupName-2", etc.
    This function updates these references.

    Args:
        group_content: Group content string
        old_group_name: Original group name
        new_group_name: New group name

    Returns:
        Group content with updated unit names
    """
    # Find units section
    units_section_match = patterns.UNITS_SECTION_PATTERN_COMPILED.search(group_content)

    if not units_section_match:
        return group_content

    units_content = units_section_match.group(1)

    # Replace unit names that contain the old group name
    # Pattern: ["name"] = "OldGroupName-1" or ["name"] = "OldGroupName Pilot #001"
    updated_units = re.sub(
        rf'\["name"\]\s*=\s*"({re.escape(old_group_name)}[^"]*)"',
        lambda m: f'["name"] = "{m.group(1).replace(old_group_name, new_group_name, 1)}"',
        units_content
    )

    # Replace the units section in group content
    modified_group = group_content.replace(units_content, updated_units)

    return modified_group


def _apply_position_offset(group_content: str, position_offset: Dict[str, float]) -> str:
    """
    Apply position offset to all positions in group content.

    Offsets both the group position and all unit positions.

    Args:
        group_content: Group content string
        position_offset: Dict with "x" and/or "y" offset values

    Returns:
        Group content with offset positions
    """
    x_offset = position_offset.get("x", 0)
    y_offset = position_offset.get("y", 0)

    def offset_position(match):
        """Regex replacement function to offset a position."""
        y_value = float(match.group(1))
        x_value = float(match.group(2))

        new_y = y_value + y_offset
        new_x = x_value + x_offset

        return f'["y"] = {new_y},\n                        ["x"] = {new_x}'

    # Apply offset to all position patterns
    modified_content = patterns.POSITION_PATTERN_COMPILED.sub(
        offset_position,
        group_content
    )

    return modified_content


# ============================================================================
# CONVENIENCE WRAPPER FUNCTIONS
# ============================================================================

def duplicate_group_file(
    input_miz: str,
    output_miz: str,
    group_name: str,
    new_group_name: Optional[str] = None,
    position_offset: Optional[Dict[str, float]] = None
) -> None:
    """
    Duplicate a group in a .miz file (convenience wrapper).

    Args:
        input_miz: Path to input .miz file
        output_miz: Path to output .miz file
        group_name: Name of the group to duplicate
        new_group_name: Optional new name for duplicated group
        position_offset: Optional position offset dict

    Raises:
        FileNotFoundError: If input_miz doesn't exist
        ValueError: If source group not found or parameters invalid

    Example:
        >>> duplicate_group_file(
        ...     "../miz-files/input/mission.miz",
        ...     "../miz-files/output/mission_with_copy.miz",
        ...     "Fighter-1",
        ...     "Fighter-2",
        ...     {"x": 5000, "y": 5000}
        ... )
    """
    from ..parsing.miz_parser import quick_modify

    def modify_func(content):
        return duplicate_group(content, group_name, new_group_name, position_offset)

    quick_modify(input_miz, output_miz, modify_func)
