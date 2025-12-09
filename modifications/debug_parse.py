#!/usr/bin/env python3
"""Debug script to test Lua parsing patterns"""

import re
import sys
from miz_file_modification.parsing.miz_parser import MizParser

def debug_parse(miz_path):
    parser = MizParser(miz_path)
    try:
        parser.extract()
        content = parser.get_mission_content()
    finally:
        parser.cleanup()

    print("="*60)
    print("DEBUG: Looking for coalition section")
    print("="*60)

    # Test 1: Find coalition section
    coalition_pattern = r'\["coalition"\]\s*=\s*\{'
    if re.search(coalition_pattern, content):
        print("[OK] Found coalition section start")
    else:
        print("[FAIL] Coalition section not found")
        return

    # Test 2: Find blue coalition
    blue_pattern = r'\["blue"\]\s*=\s*\{'
    if re.search(blue_pattern, content):
        print("[OK] Found blue coalition")
        # Get a sample
        match = re.search(r'\["blue"\]\s*=\s*\{(.{200})', content, re.DOTALL)
        if match:
            print("Sample:")
            print(match.group(1))
    else:
        print("[FAIL] Blue coalition not found")

    # Test 3: Find country section in blue
    country_pattern = r'\["country"\]\s*=\s*\{'
    matches = list(re.finditer(country_pattern, content))
    print(f"[OK] Found {len(matches)} country sections")

    # Test 4: Find plane groups
    plane_pattern = r'\["plane"\]\s*=\s*\{'
    plane_matches = list(re.finditer(plane_pattern, content))
    print(f"[OK] Found {len(plane_matches)} plane sections")

    # Test 5: Find groups
    group_pattern = r'\["group"\]\s*=\s*\{'
    group_matches = list(re.finditer(group_pattern, content))
    print(f"[OK] Found {len(group_matches)} group sections")

    # Test 6: Find routes
    route_pattern = r'\["route"\]\s*=\s*\{'
    route_matches = list(re.finditer(route_pattern, content))
    print(f"[OK] Found {len(route_matches)} route sections")

    # Test 7: Find points
    points_pattern = r'\["points"\]\s*=\s*\{'
    points_matches = list(re.finditer(points_pattern, content))
    print(f"[OK] Found {len(points_matches)} points sections")

    # Test 8: Try to find a complete group with waypoints
    print("\n" + "="*60)
    print("Looking for group with route and points...")
    print("="*60)

    # Find group name
    name_in_group = re.search(r'\["name"\]\s*=\s*"([^"]+)".*?\["route"\]\s*=', content, re.DOTALL)
    if name_in_group:
        print(f"Found group with route: {name_in_group.group(1)}")

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: python debug_parse.py <mission.miz>")
        sys.exit(1)

    debug_parse(sys.argv[1])
