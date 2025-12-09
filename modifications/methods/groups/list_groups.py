#!/usr/bin/env python3
"""
List all unit groups present in a DCS mission file.

Shows groups organized by type (plane, helicopter, ship, vehicle, static)
with details like group names, unit counts, and coalition.
"""

import re
import sys
import os
from collections import defaultdict

# Import from new location
from miz_file_modification.parsing.miz_parser import MizParser


# Valid unit types in DCS missions
UNIT_TYPES = ['plane', 'helicopter', 'ship', 'vehicle', 'static']
COALITION_NAMES = {
    'blue': 'Blue (Coalition)',
    'red': 'Red (Coalition)',
    'neutrals': 'Neutrals'
}


def find_context(content: str, position: int, search_back: int = 2500000) -> dict:
    """
    Find the context (coalition and unit type) for a position in the content.

    Args:
        content: Mission content
        position: Position to check context for
        search_back: How far back to search for context markers

    Returns:
        Dict with 'coalition' and 'unit_type'
    """
    # Search backwards from position
    start = max(0, position - search_back)
    context_section = content[start:position]

    # Find last coalition marker (closest to the group)
    coalition = None
    last_coalition_pos = -1
    for c in ['blue', 'red', 'neutrals']:
        pattern = rf'\["{c}"\]\s*='
        matches = list(re.finditer(pattern, context_section))
        if matches:
            last_match_pos = matches[-1].start()
            if last_match_pos > last_coalition_pos:
                last_coalition_pos = last_match_pos
                coalition = c

    # Find last unit type marker (closest to the group)
    unit_type = None
    last_type_pos = -1
    for ut in UNIT_TYPES:
        pattern = rf'\["{ut}"\]\s*='
        matches = list(re.finditer(pattern, context_section))
        if matches:
            last_match_pos = matches[-1].start()
            if last_match_pos > last_type_pos:
                last_type_pos = last_match_pos
                unit_type = ut

    return {'coalition': coalition, 'unit_type': unit_type}


def list_all_groups(mission_content: str) -> dict:
    """
    Extract all groups from mission content.

    Args:
        mission_content: The mission file content as string

    Returns:
        Dictionary organized by coalition -> unit_type -> groups
    """
    result = defaultdict(lambda: defaultdict(list))

    # Find all group entries by looking for group names
    # Groups have: ["units"] = {...}, THEN ["name"] = "GroupName"
    group_pattern = r'\["units"\]\s*=\s*\{(.*?)\},\s*--\s*end\s*of\s*\["units"\]\s*\n(?:.*?\n){0,5}?\s*\["name"\]\s*=\s*"([^"]+)"'

    matches = list(re.finditer(group_pattern, mission_content, re.DOTALL))

    for match in matches:
        units_content = match.group(1)
        group_name = match.group(2)
        position = match.start()

        # Skip if this looks like a country name or other non-group name
        if group_name in ['USA', 'Russia', 'UK', 'neutrals', 'blue', 'red']:
            continue

        # Find context (coalition and unit type)
        context = find_context(mission_content, position)

        if not context['coalition'] or not context['unit_type']:
            continue

        # Count units
        unit_entries = re.findall(r'\[(\d+)\]\s*=\s*\{', units_content)
        unit_count = len(unit_entries)

        # Get first unit's type
        unit_type_name = "Unknown"
        type_match = re.search(r'\["type"\]\s*=\s*"([^"]+)"', units_content)
        if type_match:
            unit_type_name = type_match.group(1)

        result[context['coalition']][context['unit_type']].append({
            'name': group_name,
            'unit_count': unit_count,
            'unit_type': unit_type_name
        })

    return result


def print_groups_summary(groups_data: dict, verbose: bool = False) -> None:
    """
    Print a formatted summary of all groups.

    Args:
        groups_data: Dictionary of groups organized by coalition and type
        verbose: If True, show detailed information for each group
    """
    total_groups = 0
    total_units = 0

    print("\n" + "="*70)
    print("MISSION GROUPS SUMMARY")
    print("="*70)

    for coalition_name in ['blue', 'red', 'neutrals']:
        if coalition_name not in groups_data or not groups_data[coalition_name]:
            continue

        coalition_display = COALITION_NAMES.get(coalition_name, coalition_name.title())
        print(f"\n[{coalition_display}]")
        print("-" * 70)

        coalition_total_groups = 0
        coalition_total_units = 0

        for unit_type in UNIT_TYPES:
            if unit_type not in groups_data[coalition_name]:
                continue

            groups = groups_data[coalition_name][unit_type]
            if not groups:
                continue

            type_total_units = sum(g['unit_count'] for g in groups)
            coalition_total_groups += len(groups)
            coalition_total_units += type_total_units

            print(f"\n  {unit_type.upper()}S: {len(groups)} group(s), {type_total_units} unit(s)")

            if verbose:
                for group in groups:
                    unit_type_str = f" ({group['unit_type']})" if group['unit_type'] != "Unknown" else ""
                    print(f"    - {group['name']}: {group['unit_count']} unit(s){unit_type_str}")

        total_groups += coalition_total_groups
        total_units += coalition_total_units

        print(f"\n  Coalition Total: {coalition_total_groups} group(s), {coalition_total_units} unit(s)")

    print("\n" + "="*70)
    print(f"MISSION TOTAL: {total_groups} group(s), {total_units} unit(s)")
    print("="*70 + "\n")


def list_groups(miz_path: str, verbose: bool = False, json_output: bool = False) -> dict:
    """
    List all groups in a mission file.

    Args:
        miz_path: Path to .miz file
        verbose: Show detailed information
        json_output: Output as JSON

    Returns:
        Dictionary of groups data
    """
    parser = MizParser(miz_path)

    try:
        # Extract mission
        parser.extract()

        # Read mission content
        content = parser.get_mission_content()

        # Extract all groups
        groups_data = list_all_groups(content)

        # Output results
        if json_output:
            import json
            print(json.dumps(groups_data, indent=2))
        else:
            print_groups_summary(groups_data, verbose)

        return groups_data

    finally:
        # Cleanup
        parser.cleanup()


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("List Mission Groups - DCS Mission Analyzer")
        print("\nUsage: python list_groups.py <input.miz> [options]")
        print("\nOptions:")
        print("  -v, --verbose    Show detailed information for each group")
        print("  -j, --json       Output as JSON format")
        print("\nExamples:")
        print('  python list_groups.py "../../../miz-files/input/mission.miz"')
        print('  python list_groups.py "mission.miz" -v')
        print('  python list_groups.py "mission.miz" --json')
        sys.exit(1)

    input_file = sys.argv[1]

    if not os.path.exists(input_file):
        print(f"Error: Input file not found: {input_file}")
        sys.exit(1)

    # Parse options
    verbose = '-v' in sys.argv or '--verbose' in sys.argv
    json_output = '-j' in sys.argv or '--json' in sys.argv

    list_groups(input_file, verbose=verbose, json_output=json_output)
