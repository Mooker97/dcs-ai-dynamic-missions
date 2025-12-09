#!/usr/bin/env python3
"""
Get Waypoints (Lightweight) - Extract waypoint data using direct Lua parsing

This version bypasses pydcs and directly parses the mission Lua file.
Works with all mission files, including those with unknown task IDs.
"""

import os
import sys
import json
import re
from pathlib import Path
from typing import Dict, List, Any, Optional

# Import from new location
from miz_file_modification.parsing.miz_parser import MizParser


def parse_waypoints_from_group(group_lua: str) -> List[Dict[str, Any]]:
    """
    Parse waypoints from a group's Lua representation

    Args:
        group_lua: Lua string representing a group

    Returns:
        List of waypoint dictionaries
    """
    waypoints = []

    # Find the route section
    route_match = re.search(r'\["route"\]\s*=\s*\{(.+?)\},\s*--\s*end\s*of\s*\["route"\]', group_lua, re.DOTALL)
    if not route_match:
        return waypoints

    route_section = route_match.group(1)

    # Find points array
    points_match = re.search(r'\["points"\]\s*=\s*\{(.+?)\},\s*--\s*end\s*of\s*\["points"\]', route_section, re.DOTALL)
    if not points_match:
        return waypoints

    points_section = points_match.group(1)

    # Parse each waypoint (indexed by [1], [2], etc.)
    # More flexible pattern that handles nested structures
    waypoint_pattern = r'\[(\d+)\]\s*=\s*\{((?:[^{}]|\{(?:[^{}]|\{[^{}]*\})*\})*)\},\s*--\s*end\s*of\s*\[\d+\]'

    for wp_match in re.finditer(waypoint_pattern, points_section, re.DOTALL):
        wp_index = int(wp_match.group(1))
        wp_content = wp_match.group(2)

        waypoint = {"index": wp_index}

        # Extract position (x, y) - directly in waypoint
        x_match = re.search(r'\["x"\]\s*=\s*([-\d.]+)', wp_content)
        y_match = re.search(r'\["y"\]\s*=\s*([-\d.]+)', wp_content)
        if x_match and y_match:
            waypoint["position"] = {
                "x": round(float(x_match.group(1)), 2),
                "y": round(float(y_match.group(1)), 2)
            }

        # Extract altitude
        alt_match = re.search(r'\["alt"\]\s*=\s*([-\d.]+)', wp_content)
        if alt_match:
            waypoint["alt"] = round(float(alt_match.group(1)), 2)

        # Extract altitude type
        alt_type_match = re.search(r'\["alt_type"\]\s*=\s*"([^"]+)"', wp_content)
        if alt_type_match:
            waypoint["alt_type"] = alt_type_match.group(1)

        # Extract speed
        speed_match = re.search(r'\["speed"\]\s*=\s*([-\d.]+)', wp_content)
        if speed_match:
            waypoint["speed"] = round(float(speed_match.group(1)), 2)

        # Extract type
        type_match = re.search(r'\["type"\]\s*=\s*"([^"]+)"', wp_content)
        if type_match:
            waypoint["type"] = type_match.group(1)

        # Extract action
        action_match = re.search(r'\["action"\]\s*=\s*"([^"]+)"', wp_content)
        if action_match:
            waypoint["action"] = action_match.group(1)

        # Extract name if present
        name_match = re.search(r'\["name"\]\s*=\s*"([^"]+)"', wp_content)
        if name_match:
            waypoint["name"] = name_match.group(1)

        waypoints.append(waypoint)

    return waypoints


def parse_group_data(group_lua: str, group_index: int) -> Optional[Dict[str, Any]]:
    """
    Parse group metadata and waypoints

    Args:
        group_lua: Lua string representing a group
        group_index: Group index number

    Returns:
        Dictionary with group data or None if no waypoints
    """
    # Extract group name
    name_match = re.search(r'\["name"\]\s*=\s*"([^"]+)"', group_lua)
    group_name = name_match.group(1) if name_match else f"Group_{group_index}"

    # Extract units count
    units_pattern = r'\["units"\]\s*=\s*\n\s*\{(.+?)\}\s*,\s*--\s*end\s*of\s*\["units"\]'
    units_match = re.search(units_pattern, group_lua, re.DOTALL)

    if units_match:
        units_section = units_match.group(1)
        # Count unit entries
        unit_count = len(re.findall(r'\[\d+\]\s*=\s*\n\s*\{', units_section))
    else:
        unit_count = 0

    # Parse waypoints
    waypoints = parse_waypoints_from_group(group_lua)

    if not waypoints:
        return None

    return {
        "name": group_name,
        "units": unit_count,
        "waypoint_count": len(waypoints),
        "waypoints": waypoints
    }


def parse_groups_by_type(mission_content: str, group_type: str, coalition: str) -> List[Dict[str, Any]]:
    """
    Parse all groups of a specific type from mission content

    Args:
        mission_content: Full mission Lua content
        group_type: Group type (plane, helicopter, ship, vehicle)
        coalition: Coalition (blue or red)

    Returns:
        List of group dictionaries with waypoint data
    """
    groups = []

    # First, find the main coalition section
    coalition_section_start = mission_content.find('["coalition"] =')
    if coalition_section_start == -1:
        return groups

    # Find the specific coalition (blue or red) after the coalition section
    coalition_search_start = coalition_section_start
    coalition_pattern = rf'\["{coalition}"\]\s*=\s*\{{'
    coalition_match = re.search(coalition_pattern, mission_content[coalition_search_start:], re.DOTALL)

    if not coalition_match:
        return groups

    # Get the position in the full content
    coalition_start = coalition_search_start + coalition_match.end()

    # Find the end marker for this coalition
    end_marker = f'-- end of ["{coalition}"]'
    coalition_end = mission_content.find(end_marker, coalition_start)

    if coalition_end == -1:
        return groups

    coalition_section = mission_content[coalition_start:coalition_end]

    # Find country array
    country_pattern = r'\["country"\]\s*=\s*\{(.+?)\},\s*--\s*end\s*of\s*\["country"\]'
    country_match = re.search(country_pattern, coalition_section, re.DOTALL)

    if not country_match:
        return groups

    country_section = country_match.group(1)

    # Find each country entry - more flexible pattern for nested structures
    country_entries_pattern = r'\[(\d+)\]\s*=\s*\{((?:[^{}]|\{(?:[^{}]|\{(?:[^{}]|\{[^{}]*\})*\})*\})*)\},\s*--\s*end\s*of\s*\[\d+\]'

    for country_match in re.finditer(country_entries_pattern, country_section, re.DOTALL):
        country_content = country_match.group(2)

        # Get country name
        country_name_match = re.search(r'\["name"\]\s*=\s*"([^"]+)"', country_content)
        country_name = country_name_match.group(1) if country_name_match else "Unknown"

        # Find the group type section
        group_type_pattern = rf'\["{group_type}"\]\s*=\s*\{{(.+?)\}},\s*--\s*end\s*of\s*\["{group_type}"\]'
        group_type_match = re.search(group_type_pattern, country_content, re.DOTALL)

        if not group_type_match:
            continue

        group_type_section = group_type_match.group(1)

        # Find groups section within group type
        groups_pattern = r'\["group"\]\s*=\s*\{(.+?)\},\s*--\s*end\s*of\s*\["group"\]'
        groups_match = re.search(groups_pattern, group_type_section, re.DOTALL)

        if not groups_match:
            continue

        groups_section = groups_match.group(1)

        # Parse each group - use flexible nested pattern
        group_pattern = r'\[(\d+)\]\s*=\s*\{((?:[^{}]|\{(?:[^{}]|\{(?:[^{}]|\{[^{}]*\})*\})*\})*)\},\s*--\s*end\s*of\s*\[\d+\]'

        for group_match in re.finditer(group_pattern, groups_section, re.DOTALL):
            group_index = int(group_match.group(1))
            group_lua = group_match.group(2)

            group_data = parse_group_data(group_lua, group_index)
            if group_data:
                group_data["country"] = country_name
                groups.append(group_data)

    return groups


def get_mission_metadata(mission_content: str) -> Dict[str, str]:
    """
    Extract basic mission metadata

    Args:
        mission_content: Full mission Lua content

    Returns:
        Dictionary with mission name and terrain
    """
    metadata = {
        "mission_name": "Unknown",
        "terrain": "Unknown"
    }

    # Find descriptionText
    desc_match = re.search(r'\["descriptionText"\]\s*=\s*"([^"]+)"', mission_content)
    if desc_match:
        metadata["mission_name"] = desc_match.group(1)

    # Find theatre (terrain)
    theatre_match = re.search(r'\["theatre"\]\s*=\s*"([^"]+)"', mission_content)
    if theatre_match:
        metadata["terrain"] = theatre_match.group(1)

    return metadata


def get_all_waypoints_lite(miz_path: str, coalition: Optional[str] = None,
                            group_name: Optional[str] = None) -> Dict[str, Any]:
    """
    Extract all waypoints from a mission file using lightweight Lua parsing

    Args:
        miz_path: Path to .miz file
        coalition: Filter by coalition ('blue', 'red', or None for all)
        group_name: Filter by group name (case-insensitive partial match)

    Returns:
        Dictionary organized by coalition and group type
    """
    parser = MizParser(miz_path)

    try:
        parser.extract()
        mission_content = parser.get_mission_content()
    finally:
        parser.cleanup()

    # Get metadata
    metadata = get_mission_metadata(mission_content)

    result = {
        "mission_name": metadata["mission_name"],
        "terrain": metadata["terrain"],
        "groups": {}
    }

    # Define coalitions to process
    coalitions = ['blue', 'red']
    if coalition:
        if coalition.lower() not in coalitions:
            raise ValueError(f"Invalid coalition: {coalition}. Use 'blue' or 'red'")
        coalitions = [coalition.lower()]

    # Define group types
    group_types = {
        "aircraft": "plane",
        "helicopters": "helicopter",
        "vehicles": "vehicle",
        "ships": "ship"
    }

    # Process each coalition
    for coal in coalitions:
        result["groups"][coal] = {
            "aircraft": [],
            "helicopters": [],
            "vehicles": [],
            "ships": []
        }

        # Parse each group type
        for display_name, lua_name in group_types.items():
            groups = parse_groups_by_type(mission_content, lua_name, coal)

            # Filter by group name if specified
            if group_name:
                groups = [g for g in groups if group_name.lower() in g["name"].lower()]

            result["groups"][coal][display_name] = groups

    return result


def print_waypoints_summary(data: Dict[str, Any]) -> None:
    """
    Print a formatted summary of waypoints

    Args:
        data: Waypoint data dictionary
    """
    print("\n" + "="*60)
    print(f"WAYPOINTS: {data['mission_name']}")
    print("="*60)
    print(f"Terrain: {data['terrain']}\n")

    total_groups = 0
    total_waypoints = 0

    for coalition, group_types in data["groups"].items():
        print(f"\n{coalition.upper()} COALITION:")
        print("-" * 60)

        for group_type, groups in group_types.items():
            if not groups:
                continue

            print(f"\n  {group_type.upper()}:")
            for group in groups:
                total_groups += 1
                total_waypoints += group["waypoint_count"]

                print(f"    > {group['name']}")
                print(f"       Country: {group['country']} | Units: {group['units']} | Waypoints: {group['waypoint_count']}")

                for wp in group["waypoints"]:
                    pos = wp.get("position", {})
                    x = pos.get("x", "N/A")
                    y = pos.get("y", "N/A")
                    alt = wp.get("alt", "N/A")
                    speed = wp.get("speed", "N/A")
                    action = wp.get("action", "N/A")
                    print(f"       WP {wp['index']}: X={x:>10} Y={y:>10} Alt={alt:>8}m Speed={speed:>6} Action={action}")

    print("\n" + "="*60)
    print(f"SUMMARY: {total_groups} groups with {total_waypoints} total waypoints")
    print("="*60 + "\n")


def export_waypoints_json(data: Dict[str, Any], output_path: str) -> None:
    """
    Export waypoint data to JSON file

    Args:
        data: Waypoint data dictionary
        output_path: Path to output JSON file
    """
    with open(output_path, 'w', encoding='utf-8') as f:
        json.dump(data, f, indent=2, default=str)
    print(f"[OK] Exported waypoint data to: {output_path}")


def main():
    """Main CLI interface"""
    import argparse

    parser = argparse.ArgumentParser(
        description='Extract waypoint data from DCS mission files (lightweight Lua parser)',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  # Get all waypoints
  python get_waypoints_lite.py mission.miz

  # Get waypoints for blue coalition only
  python get_waypoints_lite.py mission.miz --coalition blue

  # Get waypoints for specific group
  python get_waypoints_lite.py mission.miz --group "Enfield"

  # Export to JSON
  python get_waypoints_lite.py mission.miz --json waypoints.json

  # Combine filters
  python get_waypoints_lite.py mission.miz --coalition red --group "Patrol" --json red_patrols.json

Note: This is the lightweight version that directly parses Lua.
      Use get_waypoints.py for pydcs-based extraction (requires DCS installation).
        """
    )

    parser.add_argument('miz_file', help='Path to .miz mission file')
    parser.add_argument('--coalition', '-c', choices=['blue', 'red'],
                       help='Filter by coalition (blue or red)')
    parser.add_argument('--group', '-g', help='Filter by group name (case-insensitive partial match)')
    parser.add_argument('--json', '-j', metavar='OUTPUT',
                       help='Export to JSON file instead of printing')
    parser.add_argument('--quiet', '-q', action='store_true',
                       help='Suppress summary output (only useful with --json)')

    args = parser.parse_args()

    # Validate input file
    if not os.path.exists(args.miz_file):
        print(f"[ERROR] File not found: {args.miz_file}")
        sys.exit(1)

    # Extract waypoints
    try:
        print(f"Loading mission: {args.miz_file}")
        data = get_all_waypoints_lite(args.miz_file, coalition=args.coalition, group_name=args.group)
    except Exception as e:
        print(f"[ERROR] Error extracting waypoints: {e}")
        import traceback
        traceback.print_exc()
        sys.exit(1)

    # Output results
    if args.json:
        export_waypoints_json(data, args.json)

    if not args.quiet and not args.json:
        print_waypoints_summary(data)
    elif not args.quiet and args.json:
        # Brief summary when exporting to JSON
        total_groups = sum(
            len(groups)
            for coalition in data["groups"].values()
            for groups in coalition.values()
        )
        total_waypoints = sum(
            group["waypoint_count"]
            for coalition in data["groups"].values()
            for groups in coalition.values()
            for group in groups
        )
        print(f"[OK] Extracted {total_waypoints} waypoints from {total_groups} groups")


if __name__ == "__main__":
    if len(sys.argv) == 1:
        # No arguments provided, show help
        main()
    else:
        main()
