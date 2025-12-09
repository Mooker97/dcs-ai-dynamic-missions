#!/usr/bin/env python3
"""
Duplicate an aircraft group in a DCS mission file.

Duplicates a group with all its properties: waypoints, tasks, loadout, settings.
Automatically assigns new unique IDs to the group and all units.
"""

import re
import sys
import os

# Import from new location
from miz_file_modification.parsing.miz_parser import quick_modify


def find_max_ids(mission_content: str) -> dict:
    """
    Find maximum groupId and unitId in mission.

    Args:
        mission_content: The mission file content

    Returns:
        Dict with max_group_id and max_unit_id
    """
    group_ids = re.findall(r'\["groupId"\]\s*=\s*(\d+)', mission_content)
    unit_ids = re.findall(r'\["unitId"\]\s*=\s*(\d+)', mission_content)

    max_group_id = max([int(gid) for gid in group_ids]) if group_ids else 0
    max_unit_id = max([int(uid) for uid in unit_ids]) if unit_ids else 0

    return {'max_group_id': max_group_id, 'max_unit_id': max_unit_id}


def find_group_by_name(mission_content: str, group_name: str) -> tuple:
    """
    Find a group by name and extract its full definition.

    Args:
        mission_content: The mission file content
        group_name: Name of the group to find

    Returns:
        Tuple of (group_content, insert_position) or (None, None) if not found
    """
    # Pattern to match entire group definition
    # Groups are structured as: [n] = { ... }, -- end of [n]
    group_pattern = rf'(\[\d+\]\s*=\s*\{{.*?\["name"\]\s*=\s*"{re.escape(group_name)}".*?\}}),\s*--\s*end\s*of\s*\[\d+\]'

    match = re.search(group_pattern, mission_content, re.DOTALL)

    if match:
        group_content = match.group(1)
        insert_position = match.end()
        return group_content, insert_position

    return None, None


def update_group_ids(group_content: str, new_group_id: int, new_unit_ids: list) -> str:
    """
    Update groupId and unitIds in a group definition.

    Args:
        group_content: The group definition string
        new_group_id: New group ID to assign
        new_unit_ids: List of new unit IDs (one per unit in group)

    Returns:
        Modified group content with new IDs
    """
    # Replace groupId
    modified = re.sub(
        r'\["groupId"\]\s*=\s*\d+',
        f'["groupId"] = {new_group_id}',
        group_content
    )

    # Replace unitIds one by one using a counter
    unit_id_counter = [0]  # Use list for mutable closure variable

    def replace_unit_id(match):
        """Replace function that uses incrementing counter."""
        if unit_id_counter[0] < len(new_unit_ids):
            replacement = f'["unitId"] = {new_unit_ids[unit_id_counter[0]]}'
            unit_id_counter[0] += 1
            return replacement
        return match.group(0)

    modified = re.sub(
        r'\["unitId"\]\s*=\s*\d+',
        replace_unit_id,
        modified
    )

    if unit_id_counter[0] != len(new_unit_ids):
        print(f"Warning: Found {unit_id_counter[0]} units but provided {len(new_unit_ids)} new IDs")

    return modified


def update_group_name(group_content: str, new_name: str) -> str:
    """
    Update the group name in the group definition.

    Args:
        group_content: The group definition string
        new_name: New name for the group

    Returns:
        Modified group content with new name
    """
    # Replace group name (only the main group name, not pilot names)
    modified = re.sub(
        r'(\["name"\]\s*=\s*)"([^"]+)"',
        rf'\1"{new_name}"',
        group_content,
        count=1  # Only replace first occurrence (group name)
    )

    return modified


def count_units_in_group(group_content: str) -> int:
    """
    Count the number of units in a group.

    Args:
        group_content: The group definition string

    Returns:
        Number of units in the group
    """
    unit_ids = re.findall(r'\["unitId"\]\s*=\s*\d+', group_content)
    return len(unit_ids)


def duplicate_group_content(mission_content: str, group_name: str, new_group_name: str = None) -> str:
    """
    Duplicate a group in the mission content.

    Args:
        mission_content: The mission file content
        group_name: Name of group to duplicate
        new_group_name: Optional new name (defaults to "group_name Copy")

    Returns:
        Modified mission content with duplicated group
    """
    # Find the group
    group_content, insert_position = find_group_by_name(mission_content, group_name)

    if not group_content:
        print(f"Error: Group '{group_name}' not found in mission")
        return mission_content

    print(f"Found group: {group_name}")

    # Count units
    num_units = count_units_in_group(group_content)
    print(f"Group has {num_units} unit(s)")

    # Find max IDs
    max_ids = find_max_ids(mission_content)
    new_group_id = max_ids['max_group_id'] + 1
    new_unit_ids = [max_ids['max_unit_id'] + i + 1 for i in range(num_units)]

    print(f"Assigning new group ID: {new_group_id}")
    print(f"Assigning new unit IDs: {new_unit_ids}")

    # Create duplicate with new IDs
    duplicated = update_group_ids(group_content, new_group_id, new_unit_ids)

    # Update group name
    if not new_group_name:
        new_group_name = f"{group_name} Copy"
    duplicated = update_group_name(duplicated, new_group_name)

    print(f"New group name: {new_group_name}")

    # Determine next array index
    # Find the array index pattern before our group
    context_before = mission_content[:insert_position]
    array_indices = re.findall(r'\[(\d+)\]\s*=\s*\{', context_before)
    if array_indices:
        next_index = max([int(idx) for idx in array_indices]) + 1
    else:
        next_index = 1

    # Format the duplicate entry
    indent = '\t\t\t\t\t\t'
    duplicate_entry = f"\n{indent}[{next_index}] = {duplicated}, -- end of [{next_index}]"

    # Insert after original group
    modified_content = (
        mission_content[:insert_position] +
        duplicate_entry +
        mission_content[insert_position:]
    )

    print(f"Group duplicated successfully!")

    return modified_content


def duplicate_group(input_miz: str, output_miz: str, group_name: str, new_group_name: str = None) -> None:
    """
    Duplicate a group in a mission file.

    Args:
        input_miz: Path to input .miz file
        output_miz: Path to output .miz file
        group_name: Name of group to duplicate
        new_group_name: Optional new name for duplicated group
    """
    print(f"Duplicating group '{group_name}' in: {input_miz}")
    print(f"Output: {output_miz}\n")

    # Create closure to pass parameters
    def modify_func(content):
        return duplicate_group_content(content, group_name, new_group_name)

    quick_modify(input_miz, output_miz, modify_func)
    print(f"\nDuplication complete!")


if __name__ == "__main__":
    if len(sys.argv) < 3:
        print("Duplicate Group - DCS Mission Modifier")
        print("\nUsage: python duplicate_group.py <group_name> <input.miz> [output.miz] [new_group_name]")
        print("\nArguments:")
        print("  group_name      - Name of the group to duplicate (use quotes if it contains spaces)")
        print("  input.miz       - Path to input .miz file")
        print("  output.miz      - (Optional) Path to output .miz file")
        print("  new_group_name  - (Optional) Name for the duplicated group (defaults to 'Original Name Copy')")
        print("\nExamples:")
        print('  python duplicate_group.py "Viper 1-1" "../miz-files/input/mission.miz"')
        print('  python duplicate_group.py "Viper 1-1" "input.miz" "output.miz" "Viper 1-2"')
        sys.exit(1)

    group_name = sys.argv[1]
    input_file = sys.argv[2]
    output_file = sys.argv[3] if len(sys.argv) > 3 else input_file.replace('.miz', '_duplicated.miz')
    new_group_name = sys.argv[4] if len(sys.argv) > 4 else None

    if not os.path.exists(input_file):
        print(f"Error: Input file not found: {input_file}")
        sys.exit(1)

    duplicate_group(input_file, output_file, group_name, new_group_name)
