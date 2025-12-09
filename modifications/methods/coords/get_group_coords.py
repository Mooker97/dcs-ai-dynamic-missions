#!/usr/bin/env python3
"""
Get coordinates of unit groups from a DCS mission file.

Extracts x, y coordinates of the first unit in each group.
"""

import re
import sys
import os
import json

# Import from new location
from miz_file_modification.parsing.miz_parser import MizParser


def extract_group_coords(mission_content: str, coalition: str = None) -> dict:
    """
    Extract coordinates for all groups in the mission.

    Args:
        mission_content: Full mission Lua content
        coalition: Filter by coalition ('blue', 'red', or None for all)

    Returns:
        Dictionary with group coordinates organized by coalition
    """
    result = {}

    # Define coalitions to process
    coalitions = ['blue', 'red', 'neutrals']
    if coalition:
        if coalition.lower() not in coalitions:
            raise ValueError(f"Invalid coalition: {coalition}")
        coalitions = [coalition.lower()]

    # Define group types
    group_types = ['plane', 'helicopter', 'ship', 'vehicle']

    for coal in coalitions:
        result[coal] = {}

        # Find the coalition section
        coalition_pattern = rf'\["{coal}"\]\s*=\s*\{{'
        coalition_match = re.search(coalition_pattern, mission_content, re.DOTALL)
        if not coalition_match:
            continue

        coalition_start = coalition_match.end()
        end_marker = f'-- end of ["{coal}"]'
        coalition_end = mission_content.find(end_marker, coalition_start)

        if coalition_end == -1:
            continue

        coalition_section = mission_content[coalition_start:coalition_end]

        # Find country array
        country_pattern = r'\["country"\]\s*=\s*\{(.+?)\},\s*--\s*end\s*of\s*\["country"\]'
        country_match = re.search(country_pattern, coalition_section, re.DOTALL)

        if not country_match:
            continue

        country_section = country_match.group(1)

        # Process each group type
        for group_type in group_types:
            # Find the group type section
            group_type_pattern = rf'\["{group_type}"\]\s*=\s*\{{(.+?)\}},\s*--\s*end\s*of\s*\["{group_type}"\]'
            group_type_match = re.search(group_type_pattern, country_section, re.DOTALL)

            if not group_type_match:
                continue

            group_type_section = group_type_match.group(1)

            # Find groups section
            groups_pattern = r'\["group"\]\s*=\s*\{(.+?)\},\s*--\s*end\s*of\s*\["group"\]'
            groups_match = re.search(groups_pattern, group_type_section, re.DOTALL)

            if not groups_match:
                continue

            groups_section = groups_match.group(1)

            # Parse each group
            group_pattern = r'\[(\d+)\]\s*=\s*\{((?:[^{}]|\{(?:[^{}]|\{(?:[^{}]|\{[^{}]*\})*\})*\})*)\},\s*--\s*end\s*of\s*\[\d+\]'

            for group_match in re.finditer(group_pattern, groups_section, re.DOTALL):
                group_lua = group_match.group(2)

                # Extract group name
                name_match = re.search(r'\["name"\]\s*=\s*"([^"]+)"', group_lua)
                group_name = name_match.group(1) if name_match else f"Unknown_{group_match.group(1)}"

                # Find units section
                units_pattern = r'\["units"\]\s*=\s*\{(.+?)\},\s*--\s*end\s*of\s*\["units"\]'
                units_match = re.search(units_pattern, group_lua, re.DOTALL)

                if not units_match:
                    continue

                units_section = units_match.group(1)

                # Extract first unit's coordinates
                unit_pattern = r'\[1\]\s*=\s*\{(.+?)\},\s*--\s*end\s*of\s*\[1\]'
                unit_match = re.search(unit_pattern, units_section, re.DOTALL)

                if unit_match:
                    unit_content = unit_match.group(1)

                    # Extract x and y coordinates
                    x_match = re.search(r'\["x"\]\s*=\s*([-\d.]+)', unit_content)
                    y_match = re.search(r'\["y"\]\s*=\s*([-\d.]+)', unit_content)

                    if x_match and y_match:
                        if group_type not in result[coal]:
                            result[coal][group_type] = []

                        result[coal][group_type].append({
                            'name': group_name,
                            'x': float(x_match.group(1)),
                            'y': float(y_match.group(1))
                        })

    return result


def print_coords_summary(data: dict) -> None:
    """
    Print formatted summary of group coordinates.

    Args:
        data: Coordinate data dictionary
    """
    print("\n" + "="*70)
    print("GROUP COORDINATES")
    print("="*70)

    for coalition, group_types in data.items():
        if not group_types:
            continue

        print(f"\n{coalition.upper()} COALITION:")
        print("-" * 70)

        for group_type, groups in group_types.items():
            if not groups:
                continue

            print(f"\n  {group_type.upper()}:")
            for group in groups:
                print(f"    {group['name']:<30} X: {group['x']:>12.2f}  Y: {group['y']:>12.2f}")

    print("\n" + "="*70 + "\n")


def main():
    """Main CLI interface"""
    import argparse

    parser = argparse.ArgumentParser(
        description='Extract coordinates of unit groups from DCS mission files',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  # Get all group coordinates
  python get_group_coords.py mission.miz

  # Get blue coalition only
  python get_group_coords.py mission.miz --coalition blue

  # Export to JSON
  python get_group_coords.py mission.miz --json coords.json
        """
    )

    parser.add_argument('miz_file', help='Path to .miz mission file')
    parser.add_argument('--coalition', '-c', choices=['blue', 'red', 'neutrals'],
                       help='Filter by coalition')
    parser.add_argument('--json', '-j', metavar='OUTPUT',
                       help='Export to JSON file')

    args = parser.parse_args()

    # Validate input file
    if not os.path.exists(args.miz_file):
        print(f"Error: File not found: {args.miz_file}")
        sys.exit(1)

    # Extract coordinates
    try:
        print(f"Loading mission: {args.miz_file}")
        parser_obj = MizParser(args.miz_file)
        parser_obj.extract()
        mission_content = parser_obj.get_mission_content()
        parser_obj.cleanup()

        data = extract_group_coords(mission_content, coalition=args.coalition)
    except Exception as e:
        print(f"Error extracting coordinates: {e}")
        import traceback
        traceback.print_exc()
        sys.exit(1)

    # Output results
    if args.json:
        with open(args.json, 'w', encoding='utf-8') as f:
            json.dump(data, f, indent=2)
        print(f"Exported coordinates to: {args.json}")
    else:
        print_coords_summary(data)


if __name__ == "__main__":
    main()
