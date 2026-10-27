"""
Test script for core.py

Tests core utilities including find_context and validation functions.
"""

import sys
from pathlib import Path

# Add parent directory to path for imports
sys.path.insert(0, str(Path(__file__).parent.parent))

from parsing.miz_parser import MizParser
from core import (
    UNIT_TYPES,
    COALITIONS,
    COALITION_NAMES,
    find_context,
    validate_coalition,
    validate_unit_type,
    get_coalition_display_name
)


def test_constants():
    """Test that constants are defined correctly."""
    print("=" * 60)
    print("Core Constants Test")
    print("=" * 60)

    # Test UNIT_TYPES
    print("\nTest 1: UNIT_TYPES constant")
    print(f"  UNIT_TYPES: {UNIT_TYPES}")
    assert len(UNIT_TYPES) == 5, "Expected 5 unit types"
    assert 'plane' in UNIT_TYPES
    assert 'helicopter' in UNIT_TYPES
    assert 'ship' in UNIT_TYPES
    assert 'vehicle' in UNIT_TYPES
    assert 'static' in UNIT_TYPES
    print("  OK All unit types present")

    # Test COALITIONS
    print("\nTest 2: COALITIONS constant")
    print(f"  COALITIONS: {COALITIONS}")
    assert len(COALITIONS) == 3, "Expected 3 coalitions"
    assert 'blue' in COALITIONS
    assert 'red' in COALITIONS
    assert 'neutrals' in COALITIONS
    print("  OK All coalitions present")

    # Test COALITION_NAMES
    print("\nTest 3: COALITION_NAMES constant")
    for coalition in COALITIONS:
        display_name = COALITION_NAMES[coalition]
        print(f"  {coalition}: {display_name}")
    assert len(COALITION_NAMES) == 3
    print("  OK All coalition names defined")


def test_validation_functions():
    """Test validation functions."""
    print("\n" + "=" * 60)
    print("Validation Functions Test")
    print("=" * 60)

    # Test validate_coalition
    print("\nTest 4: validate_coalition()")
    assert validate_coalition('blue') == True
    assert validate_coalition('red') == True
    assert validate_coalition('neutrals') == True
    assert validate_coalition('green') == False
    assert validate_coalition('invalid') == False
    print("  OK Coalition validation working")

    # Test validate_unit_type
    print("\nTest 5: validate_unit_type()")
    assert validate_unit_type('plane') == True
    assert validate_unit_type('helicopter') == True
    assert validate_unit_type('ship') == True
    assert validate_unit_type('vehicle') == True
    assert validate_unit_type('static') == True
    assert validate_unit_type('tank') == False
    assert validate_unit_type('invalid') == False
    print("  OK Unit type validation working")

    # Test get_coalition_display_name
    print("\nTest 6: get_coalition_display_name()")
    assert get_coalition_display_name('blue') == 'Blue (Coalition)'
    assert get_coalition_display_name('red') == 'Red (Coalition)'
    assert get_coalition_display_name('neutrals') == 'Neutrals'
    assert get_coalition_display_name('invalid') == 'invalid'
    print("  OK Coalition display names working")


def test_find_context():
    """Test find_context with a real mission file."""
    print("\n" + "=" * 60)
    print("find_context() Test")
    print("=" * 60)

    # Path to test mission file
    test_mission = Path(__file__).parent.parent.parent / "miz-files" / "input" / "f16 A-G.miz"

    if not test_mission.exists():
        print(f"Warning: Test mission not found at {test_mission}")
        print("Skipping find_context test")
        return True

    print(f"Test mission: {test_mission.name}\n")

    # Parse mission
    parser = MizParser(str(test_mission))
    parser.extract()
    content = parser.get_mission_content()

    # Test 7: Find a group and determine its context
    print("Test 7: Find context for groups in mission")

    # Search for a group name pattern
    import re
    group_pattern = r'\["name"\]\s*=\s*"([^"]+)"'
    matches = list(re.finditer(group_pattern, content))

    if matches:
        # Test first few groups
        for i, match in enumerate(matches[:3]):
            group_name = match.group(1)
            position = match.start()
            context = find_context(content, position)

            print(f"  Group: '{group_name}'")
            print(f"    Coalition: {context['coalition']}")
            print(f"    Unit Type: {context['unit_type']}")

            # Context should have valid values
            if context['coalition']:
                assert context['coalition'] in COALITIONS
            if context['unit_type']:
                assert context['unit_type'] in UNIT_TYPES

        print("  OK Context detection working")
    else:
        print("  Warning: No groups found in mission file")

    # Cleanup
    parser.cleanup()

    return True


if __name__ == "__main__":
    try:
        test_constants()
        test_validation_functions()
        test_find_context()

        print("\n" + "=" * 60)
        print("All core tests passed!")
        print("=" * 60)
        sys.exit(0)
    except Exception as e:
        print(f"\nTest failed with error: {e}")
        import traceback
        traceback.print_exc()
        sys.exit(1)
