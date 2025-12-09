#!/usr/bin/env python3
"""
Remove unit groups from DCS mission files.

Supports removing: planes, helicopters, ships, vehicles, and static objects.
Use with the parsing workflow: extract → modify → repackage
"""

import re
import sys
import os

# Import from new location
from miz_file_modification.parsing.miz_parser import quick_modify


# Valid unit types in DCS missions
VALID_UNIT_TYPES = ['plane', 'helicopter', 'ship', 'vehicle', 'static']


def remove_groups_from_content(mission_content: str, unit_types: list) -> str:
    """
    Remove specified unit group types from mission content.

    Args:
        mission_content: The mission file content as string
        unit_types: List of unit types to remove (e.g., ['ship', 'plane'])

    Returns:
        Modified mission content with specified groups removed
    """
    modified_content = mission_content
    removed_count = 0

    for unit_type in unit_types:
        if unit_type not in VALID_UNIT_TYPES:
            print(f"Warning: Unknown unit type '{unit_type}', skipping...")
            continue

        # Look for unit type section start and end markers
        unit_start_pattern = rf'(\["{unit_type}"\]\s*=\s*\n)'
        unit_end_pattern = rf'(\}},\s*--\s*end\s*of\s*\["{unit_type}"\])'

        # Check if this unit type exists
        if re.search(unit_start_pattern, modified_content) and re.search(unit_end_pattern, modified_content):
            print(f"Found {unit_type} section, removing...")

            # Find the section and replace everything between start and end
            pattern = rf'(\["{unit_type}"\]\s*=\s*\n)(\s*\{{.*?\}}),(\s*--\s*end\s*of\s*\["{unit_type}"\])'

            def replace_unit(match):
                # Keep the opening, replace middle with empty group, keep closing
                indent = '\t\t\t\t\t'
                return f'{match.group(1)}{indent}{{\n{indent}}},{match.group(3)}'

            modified_content = re.sub(
                pattern,
                replace_unit,
                modified_content,
                flags=re.DOTALL
            )
            removed_count += 1
            print(f"[OK] {unit_type.capitalize()} groups removed successfully!")
        else:
            print(f"No {unit_type} section found, skipping...")

    if removed_count > 0:
        print(f"\nTotal: Removed {removed_count} unit type(s)")
    else:
        print("\nNo matching unit types found in mission file.")

    return modified_content


def remove_groups(input_miz: str, output_miz: str, unit_types: list) -> None:
    """
    Remove specified unit groups from a mission file.

    Args:
        input_miz: Path to input .miz file
        output_miz: Path to output .miz file
        unit_types: List of unit types to remove
    """
    print(f"Removing {', '.join(unit_types)} from: {input_miz}")

    # Create a closure to pass unit_types to the modification function
    def modify_func(content):
        return remove_groups_from_content(content, unit_types)

    quick_modify(input_miz, output_miz, modify_func)
    print(f"\nGroup removal complete!")


def parse_unit_types(type_arg: str) -> list:
    """
    Parse unit type argument into a list.

    Args:
        type_arg: Comma-separated string of unit types or 'all'

    Returns:
        List of unit types to remove
    """
    if type_arg.lower() == 'all':
        return VALID_UNIT_TYPES.copy()

    # Split by comma and clean up whitespace
    types = [t.strip().lower() for t in type_arg.split(',')]

    # Validate types
    invalid_types = [t for t in types if t not in VALID_UNIT_TYPES]
    if invalid_types:
        print(f"Warning: Invalid unit types will be skipped: {', '.join(invalid_types)}")

    return [t for t in types if t in VALID_UNIT_TYPES]


if __name__ == "__main__":
    if len(sys.argv) < 3:
        print("Remove Unit Groups - DCS Mission Modifier")
        print("\nUsage: python remove_groups.py <unit_types> <input.miz> [output.miz]")
        print("\nUnit Types:")
        print("  plane       - Remove all aircraft groups")
        print("  helicopter  - Remove all helicopter groups")
        print("  ship        - Remove all naval groups")
        print("  vehicle     - Remove all ground vehicle groups")
        print("  static      - Remove all static objects")
        print("  all         - Remove all unit types")
        print("\nExamples:")
        print('  python remove_groups.py ship "../../miz-files/input/mission.miz" "../../miz-files/output/no_ships.miz"')
        print('  python remove_groups.py "ship,vehicle" "input.miz" "output.miz"')
        print('  python remove_groups.py all "input.miz" "output.miz"')
        sys.exit(1)

    unit_type_arg = sys.argv[1]
    input_file = sys.argv[2]
    output_file = sys.argv[3] if len(sys.argv) > 3 else input_file.replace('.miz', '_modified.miz')

    if not os.path.exists(input_file):
        print(f"Error: Input file not found: {input_file}")
        sys.exit(1)

    unit_types = parse_unit_types(unit_type_arg)

    if not unit_types:
        print("Error: No valid unit types specified")
        sys.exit(1)

    remove_groups(input_file, output_file, unit_types)
