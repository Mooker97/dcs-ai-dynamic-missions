# -*- coding: utf-8 -*-
"""
Get Coordinates for Group
Extracts all coordinates (starting position + waypoints) for a specified group in a DCS mission
"""

import sys
import os
import re
import json
from pathlib import Path
from typing import Optional, Dict, Any, List

# Import from new location
from miz_file_modification.parsing.miz_parser import MizParser


def find_group_in_content(content: str, group_name: str) -> Optional[Dict[str, Any]]:
    """
    Find a specific group by name in the mission content.

    Args:
        content: Mission file content
        group_name: Name of the group to find

    Returns:
        Dictionary with group data or None if not found
    """
    # Escape special regex characters in group name
    escaped_name = re.escape(group_name)

    # Pattern to find the group by name
    # Groups have: ["name"] = "GroupName", followed by various properties including ["route"]
    group_pattern = rf'\["name"\]\s*=\s*"{escaped_name}".*?\["route"\]\s*=\s*\{{(.*?)\}}\s*,\s*--\s*end\s*of\s*\["route"\]'

    match = re.search(group_pattern, content, re.DOTALL)

    if not match:
        return None

    # Extract the full group section (search backward and forward from match)
    group_start = content.rfind('[', 0, match.start() - 100)
    group_end = content.find('} -- end of', match.end()) + 20
    group_section = content[group_start:group_end]

    # Extract route section
    route_section = match.group(1)

    # Find context (coalition and unit type)
    context = find_context(content, match.start())

    # Extract waypoints from route
    waypoints = extract_waypoints(route_section)

    # Extract starting position (first unit in the group)
    starting_position = extract_starting_position(group_section)

    # Count units
    units_match = re.search(r'\["units"\]\s*=\s*\{(.*?)\},\s*--\s*end\s*of\s*\["units"\]', group_section, re.DOTALL)
    unit_count = 0
    if units_match:
        unit_entries = re.findall(r'\[(\d+)\]\s*=\s*\{', units_match.group(1))
        unit_count = len(unit_entries)

    return {
        "group_name": group_name,
        "group_type": context.get('unit_type', 'unknown'),
        "coalition": context.get('coalition', 'unknown'),
        "unit_count": unit_count,
        "starting_position": starting_position,
        "waypoints": waypoints,
        "total_waypoints": len(waypoints)
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

    # Find last coalition marker
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

    # Find last unit type marker
    unit_type = None
    last_type_pos = -1
    for ut in ['plane', 'helicopter', 'ship', 'vehicle', 'static']:
        pattern = rf'\["{ut}"\]\s*='
        matches = list(re.finditer(pattern, context_section))
        if matches:
            last_match_pos = matches[-1].start()
            if last_match_pos > last_type_pos:
                last_type_pos = last_match_pos
                unit_type = ut

    return {'coalition': coalition, 'unit_type': unit_type}


def extract_waypoints(route_section: str) -> List[Dict[str, Any]]:
    """
    Extract waypoints from the route section.

    Args:
        route_section: The route section of the group

    Returns:
        List of waypoint dictionaries
    """
    waypoints = []

    # Find all waypoint entries
    # Waypoints are in ["points"] = { [1] = {...}, [2] = {...}, ... }
    points_match = re.search(r'\["points"\]\s*=\s*\{(.*)\}', route_section, re.DOTALL)

    if not points_match:
        return waypoints

    points_section = points_match.group(1)

    # Find each waypoint
    waypoint_pattern = r'\[(\d+)\]\s*=\s*\{(.*?)\}\s*,?\s*(?=\[\d+\]|$)'

    for match in re.finditer(waypoint_pattern, points_section, re.DOTALL):
        wp_index = int(match.group(1))
        wp_content = match.group(2)

        waypoint = {
            "index": wp_index - 1  # Convert to 0-based indexing
        }

        # Extract coordinates
        x_match = re.search(r'\["x"\]\s*=\s*([-\d.]+)', wp_content)
        y_match = re.search(r'\["y"\]\s*=\s*([-\d.]+)', wp_content)
        alt_match = re.search(r'\["alt"\]\s*=\s*([-\d.]+)', wp_content)
        speed_match = re.search(r'\["speed"\]\s*=\s*([-\d.]+)', wp_content)
        type_match = re.search(r'\["type"\]\s*=\s*"([^"]+)"', wp_content)
        action_match = re.search(r'\["action"\]\s*=\s*"([^"]+)"', wp_content)

        if x_match:
            waypoint["x"] = float(x_match.group(1))
        if y_match:
            waypoint["y"] = float(y_match.group(1))
        if alt_match:
            waypoint["alt"] = float(alt_match.group(1))
        if speed_match:
            waypoint["speed"] = float(speed_match.group(1))
        if type_match:
            waypoint["type"] = type_match.group(1)
        if action_match:
            waypoint["action"] = action_match.group(1)

        waypoints.append(waypoint)

    return waypoints


def extract_starting_position(group_section: str) -> Optional[Dict[str, float]]:
    """
    Extract starting position from the first unit in the group.

    Args:
        group_section: The full group section

    Returns:
        Dictionary with starting position or None
    """
    # Find the first unit
    units_match = re.search(r'\["units"\]\s*=\s*\{(.*?)\},\s*--\s*end\s*of\s*\["units"\]', group_section, re.DOTALL)

    if not units_match:
        return None

    units_section = units_match.group(1)

    # Find first unit [1] = {...}
    first_unit_match = re.search(r'\[1\]\s*=\s*\{(.*?)\}', units_section, re.DOTALL)

    if not first_unit_match:
        return None

    unit_content = first_unit_match.group(1)

    # Extract position coordinates
    x_match = re.search(r'\["x"\]\s*=\s*([-\d.]+)', unit_content)
    y_match = re.search(r'\["y"\]\s*=\s*([-\d.]+)', unit_content)
    alt_match = re.search(r'\["alt"\]\s*=\s*([-\d.]+)', unit_content)
    heading_match = re.search(r'\["heading"\]\s*=\s*([-\d.]+)', unit_content)

    position = {}

    if x_match:
        position["x"] = float(x_match.group(1))
    if y_match:
        position["y"] = float(y_match.group(1))
    if alt_match:
        position["alt"] = float(alt_match.group(1))
    if heading_match:
        position["heading"] = float(heading_match.group(1))

    return position if position else None


def list_all_groups(content: str) -> List[str]:
    """
    List all group names in the mission.

    Args:
        content: Mission file content

    Returns:
        List of group names with their type and coalition
    """
    groups = []

    # Find all group names
    group_pattern = r'\["name"\]\s*=\s*"([^"]+)"'

    for match in re.finditer(group_pattern, content):
        group_name = match.group(1)
        position = match.start()

        # Skip country/coalition names
        if group_name in ['USA', 'Russia', 'UK', 'neutrals', 'blue', 'red']:
            continue

        # Find context
        context = find_context(content, position)

        if context['coalition'] and context['unit_type']:
            groups.append(f"{group_name} ({context['unit_type']}, {context['coalition']})")

    # Remove duplicates while preserving order
    seen = set()
    unique_groups = []
    for g in groups:
        if g not in seen:
            seen.add(g)
            unique_groups.append(g)

    return unique_groups


def print_coordinates(data: Dict[str, Any], format_type: str = "text") -> None:
    """
    Print coordinates in specified format.

    Args:
        data: Group coordinate data
        format_type: Output format (text, json, compact)
    """
    if format_type == "json":
        print(json.dumps(data, indent=2))
        return

    if format_type == "compact":
        print(f"\n{data['group_name']} ({data['group_type']})")
        if data['starting_position']:
            sp = data['starting_position']
            print(f"Start: ({sp.get('x', 0):.2f}, {sp.get('y', 0):.2f}, {sp.get('alt', 0):.2f}m)")
        for wp in data['waypoints']:
            print(f"WP{wp['index']}: ({wp.get('x', 0):.2f}, {wp.get('y', 0):.2f}, {wp.get('alt', 0):.2f}m) @ {wp.get('speed', 0):.0f} m/s")
        return

    # Default: detailed text format
    print("\n" + "="*60)
    print(f"GROUP: {data['group_name']}")
    print("="*60)
    print(f"Type:       {data['group_type'].upper()}")
    print(f"Coalition:  {data['coalition'].upper()}")
    print(f"Units:      {data['unit_count']}")
    print(f"Waypoints:  {data['total_waypoints']}")

    if data['starting_position']:
        print("\n--- STARTING POSITION ---")
        sp = data['starting_position']
        print(f"X:        {sp.get('x', 0):.2f}")
        print(f"Y:        {sp.get('y', 0):.2f}")
        print(f"Altitude: {sp.get('alt', 0):.2f} meters")
        if 'heading' in sp:
            print(f"Heading:  {sp['heading']:.2f}°")

    if data['waypoints']:
        print("\n--- WAYPOINTS ---")
        for wp in data['waypoints']:
            print(f"\nWaypoint {wp['index']}:")
            print(f"  X:        {wp.get('x', 0):.2f}")
            print(f"  Y:        {wp.get('y', 0):.2f}")
            print(f"  Altitude: {wp.get('alt', 0):.2f} meters")
            if 'speed' in wp:
                print(f"  Speed:    {wp['speed']:.0f} m/s ({wp['speed'] * 1.94384:.0f} knots)")
            if 'type' in wp:
                print(f"  Type:     {wp['type']}")
            if 'action' in wp:
                print(f"  Action:   {wp['action']}")

    print("="*60 + "\n")


def main():
    """Main entry point"""
    if len(sys.argv) < 2:
        print("Usage: python get_for_group.py <miz_file> [group_name] [--format=text|json|compact] [--list]")
        print("\nExamples:")
        print("  python get_for_group.py mission.miz --list")
        print("  python get_for_group.py mission.miz \"Flight Alpha-1\"")
        print("  python get_for_group.py mission.miz \"Flight Alpha-1\" --format=json")
        print("  python get_for_group.py mission.miz \"Flight Alpha-1\" --format=compact")
        sys.exit(1)

    miz_path = sys.argv[1]

    # Parse arguments
    list_mode = "--list" in sys.argv
    format_type = "text"
    group_name = None

    for arg in sys.argv[2:]:
        if arg.startswith("--format="):
            format_type = arg.split("=")[1]
        elif not arg.startswith("--"):
            group_name = arg

    # Check if file exists
    if not os.path.exists(miz_path):
        print(f"Error: File not found: {miz_path}")
        sys.exit(1)

    # Create parser and extract mission
    parser = MizParser(miz_path)

    try:
        # Extract mission
        parser.extract()

        # Read mission content
        content = parser.get_mission_content()

        # List mode - show all groups
        if list_mode:
            groups = list_all_groups(content)
            print(f"\n=== ALL GROUPS IN MISSION ({len(groups)} total) ===\n")
            for group in groups:
                print(f"  {group}")
            print()
            return

        # Get coordinates mode
        if not group_name:
            print("Error: Group name required (or use --list to see all groups)")
            sys.exit(1)

        # Find and display group coordinates
        data = find_group_in_content(content, group_name)

        if not data:
            print(f"Error: Group not found: {group_name}")
            print("\nTip: Use --list to see all available groups")
            sys.exit(1)

        print_coordinates(data, format_type)

        # Optionally save to JSON file
        if format_type == "json":
            output_file = f"{group_name.replace(' ', '_').replace('/', '_')}_coords.json"
            with open(output_file, 'w', encoding='utf-8') as f:
                json.dump(data, f, indent=2)
            print(f"\nSaved to: {output_file}")

    finally:
        # Cleanup
        parser.cleanup()


if __name__ == "__main__":
    main()
