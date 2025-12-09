#!/usr/bin/env python3
"""
Waypoint Extraction Tool

Extracts waypoints from DCS mission files using hybrid string-finding + regex approach.
Works with any mission file format, no DCS installation required.

Approach:
- String finding for section boundaries (fast, reliable)
- Simple regex only for leaf-level data extraction
- No complex nested pattern matching
"""

import re
import sys
import json
from pathlib import Path
from typing import Dict, List, Any, Optional

# Import from new location
from miz_file_modification.parsing.miz_parser import MizParser


def extract_field(content: str, field_name: str, field_type) -> Optional[Any]:
    """
    Extract a single field value from content.

    Args:
        content: String to search in
        field_name: Name of the field (e.g., 'x', 'y', 'alt')
        field_type: Type to convert to (str, float, int)

    Returns:
        Field value converted to specified type, or None if not found
    """
    if field_type == str:
        pattern = rf'\["{field_name}"\]\s*=\s*"([^"]+)"'
    else:
        pattern = rf'\["{field_name}"\]\s*=\s*([-\d.]+)'

    match = re.search(pattern, content)
    if match:
        try:
            return field_type(match.group(1))
        except (ValueError, TypeError):
            return None
    return None


def find_waypoints_in_route(route_section: str) -> List[Dict[str, Any]]:
    """
    Extract waypoints from a route section.

    Args:
        route_section: Content between ["route"] = { and }, -- end of ["route"]

    Returns:
        List of waypoint dictionaries
    """
    waypoints = []

    # Find points section
    points_start = route_section.find('["points"]')
    if points_start == -1:
        return waypoints

    points_end = route_section.find('}, -- end of ["points"]', points_start)
    if points_end == -1:
        return waypoints

    points_section = route_section[points_start:points_end]

    # Find waypoint boundaries using end markers
    # Format: }, -- end of [N]
    search_pos = 0
    while True:
        # Find next end marker
        end_marker_match = re.search(r'\},\s*--\s*end\s*of\s*\[(\d+)\]', points_section[search_pos:])
        if not end_marker_match:
            break

        wp_index = int(end_marker_match.group(1))
        end_pos = search_pos + end_marker_match.start()

        # Find the start of this waypoint by searching backwards for [N] = {
        start_marker = f'[{wp_index}] ='
        start_pos = points_section.rfind(start_marker, 0, end_pos)
        if start_pos == -1:
            search_pos += end_marker_match.end()
            continue

        # Find the opening brace after the start marker
        brace_pos = points_section.find('{', start_pos)
        if brace_pos == -1 or brace_pos > end_pos:
            search_pos += end_marker_match.end()
            continue

        # Extract waypoint content
        wp_content = points_section[brace_pos + 1:end_pos]

        # Extract waypoint fields
        waypoint = {
            'index': wp_index,
            'x': extract_field(wp_content, 'x', float),
            'y': extract_field(wp_content, 'y', float),
            'alt': extract_field(wp_content, 'alt', float),
            'alt_type': extract_field(wp_content, 'alt_type', str),
            'speed': extract_field(wp_content, 'speed', float),
            'action': extract_field(wp_content, 'action', str),
            'type': extract_field(wp_content, 'type', str),
        }

        # Only include waypoints with at least x and y coordinates
        if waypoint['x'] is not None and waypoint['y'] is not None:
            waypoints.append(waypoint)

        # Move search position past this waypoint
        search_pos += end_marker_match.end()

    return waypoints


def extract_groups_for_unit_type(content: str, unit_type: str, coalition: str) -> List[Dict[str, Any]]:
    """
    Extract all groups of a specific unit type from a coalition.

    Args:
        content: Full mission file content
        unit_type: plane, helicopter, ship, or vehicle
        coalition: blue or red

    Returns:
        List of group dictionaries with waypoints
    """
    groups = []

    # Find main coalition section first
    main_coalition_start = content.find('["coalition"] =')
    if main_coalition_start == -1:
        return groups

    main_coalition_end = content.find('}, -- end of ["coalition"]', main_coalition_start)
    if main_coalition_end == -1:
        return groups

    main_coalition_section = content[main_coalition_start:main_coalition_end]

    # Now find specific coalition within the coalition section
    coalition_marker = f'["{coalition}"]'
    coalition_start = main_coalition_section.find(coalition_marker)
    if coalition_start == -1:
        return groups

    coalition_end = main_coalition_section.find(f'-- end of ["{coalition}"]', coalition_start)
    if coalition_end == -1:
        return groups

    coalition_section = main_coalition_section[coalition_start:coalition_end]

    # Find unit type section within coalition
    unit_type_marker = f'["{unit_type}"]'
    unit_type_start = coalition_section.find(unit_type_marker)
    if unit_type_start == -1:
        return groups

    unit_type_end = coalition_section.find(f'-- end of ["{unit_type}"]', unit_type_start)
    if unit_type_end == -1:
        return groups

    unit_type_section = coalition_section[unit_type_start:unit_type_end]

    # Find all route sections in this unit type
    route_positions = []
    search_pos = 0
    while True:
        route_start = unit_type_section.find('["route"] =', search_pos)
        if route_start == -1:
            break

        route_end = unit_type_section.find('}, -- end of ["route"]', route_start)
        if route_end == -1:
            break

        route_positions.append((route_start, route_end + len('}, -- end of ["route"]')))
        search_pos = route_end + 1

    # Extract waypoints for each route
    for route_idx, (route_start, route_end) in enumerate(route_positions, start=1):
        route_section = unit_type_section[route_start:route_end]
        waypoints = find_waypoints_in_route(route_section)

        if waypoints:
            # Use route number as name since group name extraction is complex
            route_name = f"{coalition.capitalize()} {unit_type.capitalize()} Route {route_idx}"
            groups.append({
                'name': route_name,
                'waypoint_count': len(waypoints),
                'waypoints': waypoints
            })

    return groups


def extract_waypoints(miz_path: str, coalition: Optional[str] = None,
                      group_filter: Optional[str] = None) -> Dict[str, Any]:
    """
    Extract waypoints from a DCS mission file.

    Args:
        miz_path: Path to .miz file
        coalition: Filter by coalition ('blue' or 'red'), or None for all
        group_filter: Filter by group name (case-insensitive partial match)

    Returns:
        Dictionary with mission info and groups organized by coalition and type
    """
    # Extract mission
    parser = MizParser(miz_path)
    try:
        parser.extract()
        content = parser.get_mission_content()
    finally:
        parser.cleanup()

    # Extract mission metadata
    mission_name = extract_field(content, 'descriptionText', str) or "Unknown"
    terrain = extract_field(content, 'theatre', str) or "Unknown"

    result = {
        'mission_name': mission_name,
        'terrain': terrain,
        'groups': {}
    }

    # Define coalitions to process
    coalitions = ['blue', 'red']
    if coalition and coalition.lower() in coalitions:
        coalitions = [coalition.lower()]

    # Define unit types
    unit_types = {
        'aircraft': 'plane',
        'helicopters': 'helicopter',
        'ships': 'ship',
        'vehicles': 'vehicle'
    }

    # Extract groups for each coalition and unit type
    for coal in coalitions:
        result['groups'][coal] = {}

        for display_name, lua_name in unit_types.items():
            groups = extract_groups_for_unit_type(content, lua_name, coal)

            # Apply group name filter if specified
            if group_filter:
                groups = [g for g in groups if group_filter.lower() in g['name'].lower()]

            result['groups'][coal][display_name] = groups

    return result


def print_waypoints_summary(data: Dict[str, Any]) -> None:
    """Print formatted summary of waypoints to console."""
    print("\n" + "="*60)
    print(f"WAYPOINTS: {data['mission_name']}")
    print("="*60)
    print(f"Terrain: {data['terrain']}\n")

    total_groups = 0
    total_waypoints = 0

    for coalition, group_types in data["groups"].items():
        has_groups = any(groups for groups in group_types.values())
        if not has_groups:
            continue

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
                print(f"       Waypoints: {group['waypoint_count']}")

                for wp in group["waypoints"]:
                    x = wp.get('x', 'N/A')
                    y = wp.get('y', 'N/A')
                    alt = wp.get('alt', 'N/A')
                    speed = wp.get('speed', 'N/A')
                    action = wp.get('action', 'N/A')

                    # Format numbers
                    if isinstance(x, float):
                        x = f"{x:>10.2f}"
                    if isinstance(y, float):
                        y = f"{y:>10.2f}"
                    if isinstance(alt, float):
                        alt = f"{alt:>8.2f}"
                    if isinstance(speed, float):
                        speed = f"{speed:>6.2f}"

                    print(f"       WP {wp['index']}: X={x} Y={y} Alt={alt}m Speed={speed} Action={action}")

    print("\n" + "="*60)
    print(f"SUMMARY: {total_groups} groups with {total_waypoints} total waypoints")
    print("="*60 + "\n")


def export_json(data: Dict[str, Any], output_path: str) -> None:
    """Export waypoint data to JSON file."""
    with open(output_path, 'w', encoding='utf-8') as f:
        json.dump(data, f, indent=2)
    print(f"[OK] Exported to: {output_path}")


def main():
    """Command-line interface."""
    import argparse

    parser = argparse.ArgumentParser(
        description='Extract waypoints from DCS mission files',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  # Extract all waypoints
  python extract_waypoints.py mission.miz

  # Filter by coalition
  python extract_waypoints.py mission.miz --coalition blue

  # Filter by group name
  python extract_waypoints.py mission.miz --group "Enfield"

  # Export to JSON
  python extract_waypoints.py mission.miz --json waypoints.json

  # Combine filters
  python extract_waypoints.py mission.miz --coalition red --group "Patrol" --json output.json
        """
    )

    parser.add_argument('miz_file', help='Path to .miz mission file')
    parser.add_argument('--coalition', '-c', choices=['blue', 'red'],
                       help='Filter by coalition')
    parser.add_argument('--group', '-g',
                       help='Filter by group name (case-insensitive partial match)')
    parser.add_argument('--json', '-j', metavar='FILE',
                       help='Export to JSON file')
    parser.add_argument('--quiet', '-q', action='store_true',
                       help='Suppress console output (use with --json)')

    args = parser.parse_args()

    # Validate input
    miz_file = Path(args.miz_file)
    if not miz_file.exists():
        print(f"[ERROR] File not found: {args.miz_file}")
        sys.exit(1)

    # Extract waypoints
    try:
        print(f"Loading mission: {args.miz_file}")
        data = extract_waypoints(str(miz_file), coalition=args.coalition, group_filter=args.group)
    except Exception as e:
        print(f"[ERROR] Extraction failed: {e}")
        import traceback
        traceback.print_exc()
        sys.exit(1)

    # Output results
    if args.json:
        export_json(data, args.json)

    if not args.quiet:
        if args.json:
            # Brief summary when exporting
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
        else:
            # Full console output
            print_waypoints_summary(data)


if __name__ == "__main__":
    main()
