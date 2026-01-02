#!/usr/bin/env python3
"""
Integration test: Find position of specific group (F-16).

This test demonstrates practical usage of patterns to:
1. Find a group by name or type
2. Extract its position coordinates
3. Display human-readable results

Uses the f16 A-G.miz test file.
"""

import sys
import re
from pathlib import Path

# Add parent directories to path
sys.path.insert(0, str(Path(__file__).parent.parent.parent))

from parsing.miz_parser import MizParser
from utils.patterns import (
    GROUP_PATTERN_COMPILED,
    POSITION_PATTERN_COMPILED,
    UNIT_TYPE_PATTERN_COMPILED,
    extract_field
)


def find_context(content: str, position: int, search_back: int = 250000) -> dict:
    """
    Find coalition and unit type context for a position in content.

    Args:
        content: Mission content
        position: Position to check context for
        search_back: How far back to search

    Returns:
        Dict with 'coalition' and 'unit_type'
    """
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


def find_group_position(mission_content: str, search_term: str = None, group_name: str = None) -> list:
    """
    Find position of groups matching search criteria.

    Args:
        mission_content: Raw mission file content
        search_term: Search for unit type (e.g., "F-16", "Su-27")
        group_name: Search for exact group name (e.g., "Aerial-1")

    Returns:
        List of dicts with group info and positions
    """
    results = []

    # Find all groups
    matches = list(GROUP_PATTERN_COMPILED.finditer(mission_content))

    for match in matches:
        units_content = match.group(1)
        found_group_name = match.group(2)
        group_start = match.start()

        # Get context
        context = find_context(mission_content, group_start)

        # Get unit type from first unit
        unit_type_match = UNIT_TYPE_PATTERN_COMPILED.search(units_content)
        unit_type = unit_type_match.group(1) if unit_type_match else "Unknown"

        # Filter by search criteria
        if group_name and found_group_name != group_name:
            continue

        if search_term and search_term.lower() not in unit_type.lower():
            continue

        # Find position in the group section
        # Look ahead from group start for position coordinates
        group_section = mission_content[group_start:group_start + 5000]
        position_match = POSITION_PATTERN_COMPILED.search(group_section)

        if position_match:
            y, x = position_match.groups()
            results.append({
                'group_name': found_group_name,
                'unit_type': unit_type,
                'coalition': context['coalition'],
                'category': context['unit_type'],
                'position': {
                    'x': float(x),
                    'y': float(y)
                }
            })

    return results


def test_find_f16_position(miz_path: str):
    """Find and display F-16 group position."""

    print("=" * 70)
    print("Integration Test: Find F-16 Group Position")
    print("=" * 70)
    print()

    # Extract mission
    print(f"Loading: {miz_path}")
    parser = MizParser(miz_path)
    try:
        parser.extract()
        content = parser.get_mission_content()
    finally:
        parser.cleanup()

    print("Extraction complete")
    print()

    # Find F-16 groups
    print("Searching for F-16 groups...")
    f16_groups = find_group_position(content, search_term="F-16")

    if not f16_groups:
        print("[FAIL] No F-16 groups found!")
        return False

    print(f"[OK] Found {len(f16_groups)} F-16 group(s)")
    print()

    # Display results
    print("-" * 70)
    print("F-16 GROUP DETAILS")
    print("-" * 70)

    for i, group in enumerate(f16_groups, 1):
        print(f"\n[{i}] {group['group_name']}")
        print(f"    Unit Type:  {group['unit_type']}")
        print(f"    Coalition:  {group['coalition'].upper()}")
        print(f"    Category:   {group['category']}")
        print(f"    Position:")
        print(f"      X: {group['position']['x']:>15,.2f}")
        print(f"      Y: {group['position']['y']:>15,.2f}")

        # Calculate distance from origin
        x, y = group['position']['x'], group['position']['y']
        distance = (x**2 + y**2) ** 0.5
        print(f"      Distance from origin: {distance:,.2f} meters")

    print()
    print("=" * 70)
    print("[SUCCESS] Test completed - F-16 position found and validated")
    print("=" * 70)

    return True


def test_find_specific_group(miz_path: str, group_name: str):
    """Find a specific group by exact name."""

    print("=" * 70)
    print(f"Integration Test: Find Group '{group_name}'")
    print("=" * 70)
    print()

    # Extract mission
    print(f"Loading: {miz_path}")
    parser = MizParser(miz_path)
    try:
        parser.extract()
        content = parser.get_mission_content()
    finally:
        parser.cleanup()

    print("Extraction complete")
    print()

    # Find specific group
    print(f"Searching for group: {group_name}")
    groups = find_group_position(content, group_name=group_name)

    if not groups:
        print(f"[FAIL] Group '{group_name}' not found!")
        return False

    group = groups[0]
    print(f"[OK] Group found")
    print()

    # Display results
    print("-" * 70)
    print("GROUP DETAILS")
    print("-" * 70)
    print(f"Name:       {group['group_name']}")
    print(f"Unit Type:  {group['unit_type']}")
    print(f"Coalition:  {group['coalition'].upper()}")
    print(f"Category:   {group['category']}")
    print(f"Position:")
    print(f"  X: {group['position']['x']:>15,.2f} meters")
    print(f"  Y: {group['position']['y']:>15,.2f} meters")

    print()
    print("=" * 70)
    print("[SUCCESS] Group found and position extracted")
    print("=" * 70)

    return True


def test_find_all_aircraft(miz_path: str):
    """Find all aircraft (planes and helicopters) in mission."""

    print("=" * 70)
    print("Integration Test: Find All Aircraft Positions")
    print("=" * 70)
    print()

    # Extract mission
    print(f"Loading: {miz_path}")
    parser = MizParser(miz_path)
    try:
        parser.extract()
        content = parser.get_mission_content()
    finally:
        parser.cleanup()

    print("Extraction complete")
    print()

    # Find all groups (no filter)
    print("Searching for all aircraft...")
    all_groups = find_group_position(content)

    # Filter to aircraft only
    aircraft = [g for g in all_groups if g['category'] in ['plane', 'helicopter']]

    if not aircraft:
        print("[FAIL] No aircraft found!")
        return False

    print(f"[OK] Found {len(aircraft)} aircraft group(s)")
    print()

    # Group by coalition
    blue_aircraft = [a for a in aircraft if a['coalition'] == 'blue']
    red_aircraft = [a for a in aircraft if a['coalition'] == 'red']

    # Display summary
    print("-" * 70)
    print("AIRCRAFT SUMMARY")
    print("-" * 70)

    if blue_aircraft:
        print(f"\n[BLUE COALITION] - {len(blue_aircraft)} group(s)")
        for group in blue_aircraft:
            print(f"  {group['group_name']:20s} ({group['unit_type']})")
            print(f"    Position: X={group['position']['x']:>10,.0f}, Y={group['position']['y']:>10,.0f}")

    if red_aircraft:
        print(f"\n[RED COALITION] - {len(red_aircraft)} group(s)")
        for group in red_aircraft:
            print(f"  {group['group_name']:20s} ({group['unit_type']})")
            print(f"    Position: X={group['position']['x']:>10,.0f}, Y={group['position']['y']:>10,.0f}")

    print()
    print("=" * 70)
    print(f"[SUCCESS] Found and extracted {len(aircraft)} aircraft positions")
    print("=" * 70)

    return True


if __name__ == "__main__":
    # Default test file
    default_miz = str(Path(__file__).parent.parent.parent.parent / "miz-files" / "input" / "f16 A-G.miz")

    if len(sys.argv) < 2:
        print("Integration Tests: Group Position Extraction")
        print()
        print("Usage:")
        print("  python position_of_group.py <test_name> [miz_file]")
        print()
        print("Available tests:")
        print("  f16              - Find F-16 groups and positions")
        print("  group <name>     - Find specific group by name")
        print("  all              - Find all aircraft positions")
        print()
        print("Examples:")
        print(f'  python position_of_group.py f16 "{default_miz}"')
        print(f'  python position_of_group.py group "Aerial-1" "{default_miz}"')
        print(f'  python position_of_group.py all "{default_miz}"')
        sys.exit(1)

    test_name = sys.argv[1].lower()

    # Get miz file path
    if test_name == "group" and len(sys.argv) >= 4:
        group_name = sys.argv[2]
        miz_path = sys.argv[3]
    elif len(sys.argv) >= 3:
        miz_path = sys.argv[2]
        group_name = None
    else:
        miz_path = default_miz
        group_name = None

    # Check file exists
    if not Path(miz_path).exists():
        print(f"Error: File not found: {miz_path}")
        sys.exit(1)

    # Run test
    success = False
    try:
        if test_name == "f16":
            success = test_find_f16_position(miz_path)
        elif test_name == "group":
            if not group_name:
                print("Error: group test requires group name")
                print('Usage: python position_of_group.py group "GroupName" <miz_file>')
                sys.exit(1)
            success = test_find_specific_group(miz_path, group_name)
        elif test_name == "all":
            success = test_find_all_aircraft(miz_path)
        else:
            print(f"Error: Unknown test '{test_name}'")
            print("Available tests: f16, group, all")
            sys.exit(1)
    except Exception as e:
        print()
        print(f"[ERROR] Test failed with exception: {e}")
        import traceback
        traceback.print_exc()
        sys.exit(1)

    sys.exit(0 if success else 1)
