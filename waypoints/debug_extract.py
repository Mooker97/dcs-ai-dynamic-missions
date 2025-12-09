#!/usr/bin/env python3
"""Debug script to test waypoint extraction step by step."""

import sys
from pathlib import Path

# Import from new location
from miz_file_modification.parsing.miz_parser import MizParser

miz_path = "../miz-files/input/f16 A-G.miz"

parser = MizParser(miz_path)
parser.extract()
content = parser.get_mission_content()

print("="*60)
print("DEBUG: Waypoint Extraction")
print("="*60)

# Step 1: Find main coalition section
main_coalition_start = content.find('["coalition"] =')
print(f"\n1. Main coalition section:")
print(f"   Found at position: {main_coalition_start}")

if main_coalition_start != -1:
    main_coalition_end = content.find('}, -- end of ["coalition"]', main_coalition_start)
    print(f"   End at position: {main_coalition_end}")
    main_coalition_section = content[main_coalition_start:main_coalition_end]
    print(f"   Section length: {len(main_coalition_section)} chars")

    # Step 2: Find blue coalition
    blue_start = main_coalition_section.find('["blue"]')
    print(f"\n2. Blue coalition:")
    print(f"   Found at position: {blue_start} (relative to coalition section)")

    if blue_start != -1:
        blue_end = main_coalition_section.find('-- end of ["blue"]', blue_start)
        print(f"   End at position: {blue_end}")
        blue_section = main_coalition_section[blue_start:blue_end]
        print(f"   Section length: {len(blue_section)} chars")

        # Step 3: Find plane section
        plane_start = blue_section.find('["plane"]')
        print(f"\n3. Plane section:")
        print(f"   Found at position: {plane_start} (relative to blue section)")

        if plane_start != -1:
            plane_end = blue_section.find('-- end of ["plane"]', plane_start)
            print(f"   End at position: {plane_end}")
            plane_section = blue_section[plane_start:plane_end]
            print(f"   Section length: {len(plane_section)} chars")

            # Step 4: Find route sections
            route_count = plane_section.count('["route"] =')
            print(f"\n4. Route sections found: {route_count}")

            # Step 5: Find first route and waypoints
            first_route_start = plane_section.find('["route"] =')
            if first_route_start != -1:
                first_route_end = plane_section.find('}, -- end of ["route"]', first_route_start)
                print(f"\n5. First route:")
                print(f"   Start: {first_route_start}, End: {first_route_end}")

                route_section = plane_section[first_route_start:first_route_end]

                # Find points
                points_start = route_section.find('["points"]')
                print(f"   Points section found at: {points_start}")

                if points_start != -1:
                    points_end = route_section.find('}, -- end of ["points"]', points_start)
                    print(f"   Points end at: {points_end}")

                    points_section = route_section[points_start:points_end]

                    # Find waypoint markers
                    import re
                    waypoint_starts = []
                    for match in re.finditer(r'\[(\d+)\]\s*=\s*\{', points_section):
                        waypoint_starts.append((int(match.group(1)), match.start(), match.end()))

                    print(f"\n   Waypoint markers found: {len(waypoint_starts)}")
                    for idx, start, end in waypoint_starts[:3]:  # Show first 3
                        print(f"      [{idx}] at position {start}")

                    # Try extracting first waypoint
                    if waypoint_starts:
                        wp_idx, wp_start, wp_end = waypoint_starts[0]
                        if len(waypoint_starts) > 1:
                            next_start = waypoint_starts[1][1]
                        else:
                            next_start = len(points_section)

                        wp_content = points_section[wp_end:next_start]
                        print(f"\n   First waypoint content ({len(wp_content)} chars):")
                        print(f"   {wp_content[:300]}...")

                        # Try to extract x and y
                        x_match = re.search(r'\["x"\]\s*=\s*([-\d.]+)', wp_content)
                        y_match = re.search(r'\["y"\]\s*=\s*([-\d.]+)', wp_content)
                        print(f"\n   X coordinate found: {x_match.group(1) if x_match else 'NOT FOUND'}")
                        print(f"   Y coordinate found: {y_match.group(1) if y_match else 'NOT FOUND'}")

                        # Try the regex approach
                        print(f"\n6. Testing regex approach:")
                        wp_matches = list(re.finditer(r'\[(\d+)\]\s*=\s*\{(.*?)\},\s*--\s*end\s*of\s*\[\d+\]', points_section, re.DOTALL))
                        print(f"   Waypoint regex matches: {len(wp_matches)}")

                        if wp_matches:
                            first_wp = wp_matches[0]
                            print(f"   First match index: {first_wp.group(1)}")
                            wp_full_content = first_wp.group(2)
                            print(f"   Content length: {len(wp_full_content)}")
                            x_match2 = re.search(r'\["x"\]\s*=\s*([-\d.]+)', wp_full_content)
                            y_match2 = re.search(r'\["y"\]\s*=\s*([-\d.]+)', wp_full_content)
                            print(f"   X in full content: {x_match2.group(1) if x_match2 else 'NOT FOUND'}")
                            print(f"   Y in full content: {y_match2.group(1) if y_match2 else 'NOT FOUND'}")

parser.cleanup()
