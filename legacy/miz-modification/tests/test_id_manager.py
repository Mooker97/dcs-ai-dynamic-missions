"""
Test script for id_manager.py

Tests ID finding and generation functions against real mission files.
"""

import sys
from pathlib import Path

# Add parent directory to path for imports
sys.path.insert(0, str(Path(__file__).parent.parent))

from parsing.miz_parser import MizParser
from utils.id_manager import (
    find_max_group_id,
    find_max_unit_id,
    find_max_ids,
    generate_new_group_id,
    generate_new_unit_ids,
    generate_new_unit_id
)


def test_id_manager():
    """Test ID manager functions with a real mission file."""
    print("=" * 60)
    print("ID Manager Test")
    print("=" * 60)

    # Path to test mission file
    test_mission = Path(__file__).parent.parent.parent / "miz-files" / "input" / "f16 A-G.miz"

    if not test_mission.exists():
        print(f"Error: Test mission not found at {test_mission}")
        print("Please place a .miz file in miz-files/input/ directory")
        return False

    print(f"Test mission: {test_mission.name}\n")

    # Parse mission
    parser = MizParser(str(test_mission))
    parser.extract()
    content = parser.get_mission_content()

    # Test 1: Find max group ID
    print("Test 1: Find max group ID")
    max_group_id = find_max_group_id(content)
    print(f"  Result: {max_group_id}")

    # Test 2: Find max unit ID
    print("\nTest 2: Find max unit ID")
    max_unit_id = find_max_unit_id(content)
    print(f"  Result: {max_unit_id}")

    # Test 3: Find both max IDs
    print("\nTest 3: Find both max IDs")
    max_ids = find_max_ids(content)
    print(f"  Max group ID: {max_ids['max_group_id']}")
    print(f"  Max unit ID: {max_ids['max_unit_id']}")

    # Test 4: Generate new group ID
    print("\nTest 4: Generate new group ID")
    new_group_id = generate_new_group_id(content)
    print(f"  New group ID: {new_group_id}")
    print(f"  (Should be {max_group_id + 1})")
    assert new_group_id == max_group_id + 1, "Group ID generation failed"

    # Test 5: Generate new unit ID
    print("\nTest 5: Generate new unit ID")
    new_unit_id = generate_new_unit_id(content)
    print(f"  New unit ID: {new_unit_id}")
    print(f"  (Should be {max_unit_id + 1})")
    assert new_unit_id == max_unit_id + 1, "Unit ID generation failed"

    # Test 6: Generate multiple unit IDs
    print("\nTest 6: Generate multiple unit IDs")
    count = 5
    new_unit_ids = generate_new_unit_ids(content, count)
    print(f"  Generated {count} IDs: {new_unit_ids}")
    expected = list(range(max_unit_id + 1, max_unit_id + 1 + count))
    print(f"  Expected: {expected}")
    assert new_unit_ids == expected, "Multiple unit ID generation failed"

    # Test 7: Error handling
    print("\nTest 7: Error handling")
    try:
        generate_new_unit_ids(content, 0)
        print("  ERROR: Should have raised ValueError for count=0")
        return False
    except ValueError as e:
        print(f"  Correctly raised ValueError: {e}")

    print("\n" + "=" * 60)
    print("All tests passed!")
    print("=" * 60)

    # Cleanup
    parser.cleanup()

    return True


if __name__ == "__main__":
    success = test_id_manager()
    sys.exit(0 if success else 1)
