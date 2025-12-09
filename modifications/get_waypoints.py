#!/usr/bin/env python3
"""
Get Waypoints - Extract waypoint data from DCS mission groups

Extracts waypoint information for aircraft, helicopter, vehicle, and ship groups.
Outputs waypoint coordinates, altitudes, speeds, actions, and other route data.
"""

import os
import sys
import json
from pathlib import Path
from typing import Dict, List, Any, Optional

# Add parent directory to path and suppress DCS_HOME warnings
sys.path.insert(0, os.path.dirname(__file__))
os.environ.setdefault('DCS_HOME', str(Path.home() / '.dcs'))

from miz_utils import MizHandler


def extract_waypoint_data(waypoint, index: int) -> Dict[str, Any]:
    """
    Extract waypoint data into a structured dictionary

    Args:
        waypoint: pydcs waypoint object
        index: Waypoint sequence number

    Returns:
        Dictionary with waypoint information
    """
    data = {
        "index": index,
        "position": {
            "x": round(waypoint.position.x, 2) if hasattr(waypoint, 'position') else None,
            "y": round(waypoint.position.y, 2) if hasattr(waypoint, 'position') else None,
        },
        "alt": round(waypoint.alt, 2) if hasattr(waypoint, 'alt') else None,
        "alt_type": waypoint.alt_type if hasattr(waypoint, 'alt_type') else None,
        "speed": round(waypoint.speed, 2) if hasattr(waypoint, 'speed') else None,
        "type": waypoint.type if hasattr(waypoint, 'type') else None,
        "action": waypoint.action if hasattr(waypoint, 'action') else None,
    }

    # Add optional properties if they exist
    if hasattr(waypoint, 'name') and waypoint.name:
        data["name"] = waypoint.name
    if hasattr(waypoint, 'properties') and waypoint.properties:
        data["properties"] = waypoint.properties

    return data


def get_group_waypoints(group) -> List[Dict[str, Any]]:
    """
    Extract waypoints from a group

    Args:
        group: pydcs group object (plane, helicopter, vehicle, or ship)

    Returns:
        List of waypoint dictionaries
    """
    waypoints = []

    if not hasattr(group, 'points') or not group.points:
        return waypoints

    for idx, waypoint in enumerate(group.points, start=1):
        waypoint_data = extract_waypoint_data(waypoint, idx)
        waypoints.append(waypoint_data)

    return waypoints


def get_all_waypoints(handler: MizHandler, coalition: Optional[str] = None,
                      group_name: Optional[str] = None) -> Dict[str, Any]:
    """
    Get waypoints from all groups in the mission

    Args:
        handler: MizHandler instance with loaded mission
        coalition: Filter by coalition ('blue', 'red', or None for all)
        group_name: Filter by specific group name (case-insensitive partial match)

    Returns:
        Dictionary organized by coalition and group type
    """
    if not handler.mission:
        raise ValueError("No mission loaded")

    result = {
        "mission_name": handler.mission.description_text or "Unnamed",
        "terrain": handler.mission.terrain.name if handler.mission.terrain else "Unknown",
        "groups": {}
    }

    # Define coalitions to process
    coalitions = ['blue', 'red']
    if coalition:
        if coalition.lower() not in coalitions:
            raise ValueError(f"Invalid coalition: {coalition}. Use 'blue' or 'red'")
        coalitions = [coalition.lower()]

    # Process each coalition
    for coal in coalitions:
        result["groups"][coal] = {
            "aircraft": [],
            "helicopters": [],
            "vehicles": [],
            "ships": []
        }

        # Iterate through countries in this coalition
        for country in handler.mission.coalition[coal].countries.values():

            # Process aircraft groups
            for group in country.plane_group:
                if group_name and group_name.lower() not in group.name.lower():
                    continue

                waypoints = get_group_waypoints(group)
                if waypoints:  # Only include groups with waypoints
                    result["groups"][coal]["aircraft"].append({
                        "name": group.name,
                        "country": country.name,
                        "units": len(group.units),
                        "waypoint_count": len(waypoints),
                        "waypoints": waypoints
                    })

            # Process helicopter groups
            for group in country.helicopter_group:
                if group_name and group_name.lower() not in group.name.lower():
                    continue

                waypoints = get_group_waypoints(group)
                if waypoints:
                    result["groups"][coal]["helicopters"].append({
                        "name": group.name,
                        "country": country.name,
                        "units": len(group.units),
                        "waypoint_count": len(waypoints),
                        "waypoints": waypoints
                    })

            # Process vehicle groups
            for group in country.vehicle_group:
                if group_name and group_name.lower() not in group.name.lower():
                    continue

                waypoints = get_group_waypoints(group)
                if waypoints:
                    result["groups"][coal]["vehicles"].append({
                        "name": group.name,
                        "country": country.name,
                        "units": len(group.units),
                        "waypoint_count": len(waypoints),
                        "waypoints": waypoints
                    })

            # Process ship groups
            for group in country.ship_group:
                if group_name and group_name.lower() not in group.name.lower():
                    continue

                waypoints = get_group_waypoints(group)
                if waypoints:
                    result["groups"][coal]["ships"].append({
                        "name": group.name,
                        "country": country.name,
                        "units": len(group.units),
                        "waypoint_count": len(waypoints),
                        "waypoints": waypoints
                    })

    return result


def print_waypoints_summary(data: Dict[str, Any]) -> None:
    """
    Print a formatted summary of waypoints

    Args:
        data: Waypoint data dictionary from get_all_waypoints()
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
                    pos = wp["position"]
                    print(f"       WP {wp['index']}: X={pos['x']:>10} Y={pos['y']:>10} Alt={wp['alt']:>8}m Speed={wp['speed']:>6} Action={wp['action']}")

    print("\n" + "="*60)
    print(f"SUMMARY: {total_groups} groups with {total_waypoints} total waypoints")
    print("="*60 + "\n")


def export_waypoints_json(data: Dict[str, Any], output_path: str) -> None:
    """
    Export waypoint data to JSON file

    Args:
        data: Waypoint data dictionary from get_all_waypoints()
        output_path: Path to output JSON file
    """
    with open(output_path, 'w', encoding='utf-8') as f:
        json.dump(data, f, indent=2, default=str)
    print(f"[OK] Exported waypoint data to: {output_path}")


def main():
    """Main CLI interface"""
    import argparse

    parser = argparse.ArgumentParser(
        description='Extract waypoint data from DCS mission files',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  # Get all waypoints
  python get_waypoints.py mission.miz

  # Get waypoints for blue coalition only
  python get_waypoints.py mission.miz --coalition blue

  # Get waypoints for specific group
  python get_waypoints.py mission.miz --group "Enfield"

  # Export to JSON
  python get_waypoints.py mission.miz --json waypoints.json

  # Combine filters
  python get_waypoints.py mission.miz --coalition red --group "Patrol" --json red_patrols.json
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

    # Load mission
    try:
        print(f"Loading mission: {args.miz_file}")
        handler = MizHandler(args.miz_file)
    except Exception as e:
        print(f"[ERROR] Error loading mission: {e}")
        import traceback
        traceback.print_exc()
        sys.exit(1)

    # Extract waypoints
    try:
        data = get_all_waypoints(handler, coalition=args.coalition, group_name=args.group)
    except Exception as e:
        print(f"[ERROR] Error extracting waypoints: {e}")
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
