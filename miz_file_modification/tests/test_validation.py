#!/usr/bin/env python3
"""
Test suite for utils/validation.py functions.

Tests all validation functions to ensure they correctly validate
and reject invalid inputs.
"""

import sys
from pathlib import Path

# Add parent directory to path for imports
sys.path.insert(0, str(Path(__file__).parent.parent))

from utils.validation import (
    validate_position,
    validate_coordinates,
    validate_group_name,
    validate_group_exists,
    validate_unit_type_category,
    validate_coalition,
    validate_skill_level,
    validate_waypoint_action,
    validate_altitude_type,
    validate_id,
    validate_add_group_params,
    validate_modify_group_params,
    get_validation_errors,
    raise_if_invalid
)
from parsing.miz_parser import MizParser


# ==============================================================================
# Test Configuration
# ==============================================================================

TEST_MIZ = Path(__file__).parent / "test.miz"


# ==============================================================================
# Position Validation Tests
# ==============================================================================

def test_validate_position():
    """Test position validation."""
    print("Testing position validation...")

    # Valid positions
    valid, error = validate_position({'x': 1000.0, 'y': 2000.0})
    assert valid and error is None, f"Valid position failed: {error}"

    valid, error = validate_position({'x': -50000, 'y': 30000, 'alt': 5000})
    assert valid and error is None, f"Valid position with altitude failed: {error}"

    valid, error = validate_position({'x': 0, 'y': 0, 'heading': 1.57})
    assert valid and error is None, f"Valid position with heading failed: {error}"

    # Invalid positions
    valid, error = validate_position({'x': 1000})  # Missing y
    assert not valid, "Should reject missing y"

    valid, error = validate_position({'y': 1000})  # Missing x
    assert not valid, "Should reject missing x"

    valid, error = validate_position({'x': 'invalid', 'y': 1000})  # Invalid x type
    assert not valid, "Should reject invalid x type"

    valid, error = validate_position({'x': 1000000, 'y': 1000})  # Out of bounds
    assert not valid, "Should reject out of bounds x"

    valid, error = validate_position({'x': 1000, 'y': 1000, 'alt': -100})  # Negative altitude
    assert not valid, "Should reject negative altitude"

    # Require altitude
    valid, error = validate_position({'x': 1000, 'y': 2000}, require_altitude=True)
    assert not valid, "Should reject missing altitude when required"

    valid, error = validate_position({'x': 1000, 'y': 2000, 'alt': 5000}, require_altitude=True)
    assert valid, "Should accept altitude when required and provided"

    print("[OK] Position validation tests passed")


def test_validate_coordinates():
    """Test coordinate validation."""
    print("Testing coordinate validation...")

    valid, error = validate_coordinates(1000, 2000)
    assert valid and error is None, "Valid coordinates failed"

    valid, error = validate_coordinates(1000000, 2000)
    assert not valid, "Should reject out of bounds coordinates"

    print("[OK] Coordinate validation tests passed")


# ==============================================================================
# Group Validation Tests
# ==============================================================================

def test_validate_group_name():
    """Test group name validation."""
    print("Testing group name validation...")

    # Valid names
    valid, error = validate_group_name("Fighter-1")
    assert valid and error is None, "Valid group name failed"

    valid, error = validate_group_name("A-10_Squadron_North")
    assert valid and error is None, "Valid group name with underscores failed"

    # Invalid names
    valid, error = validate_group_name("")
    assert not valid, "Should reject empty name"

    valid, error = validate_group_name('Group "1"')  # Contains quotes
    assert not valid, "Should reject name with quotes"

    valid, error = validate_group_name("Group\n1")  # Contains newline
    assert not valid, "Should reject name with newline"

    valid, error = validate_group_name("and")  # Lua keyword
    assert not valid, "Should reject Lua keyword"

    valid, error = validate_group_name("x" * 256)  # Too long
    assert not valid, "Should reject name too long"

    print("[OK] Group name validation tests passed")


def test_validate_group_exists():
    """Test group existence validation."""
    print("Testing group existence validation...")

    if not TEST_MIZ.exists():
        print("[SKIP] test.miz not found")
        return

    # Load test mission
    parser = MizParser(str(TEST_MIZ))
    parser.extract()
    content = parser.get_mission_content()
    parser.cleanup()

    # Should find existing group
    exists = validate_group_exists(content, "Aerial-1")
    assert exists, "Should find existing group 'Aerial-1'"

    # Should not find non-existent group
    exists = validate_group_exists(content, "NonExistentGroup-999")
    assert not exists, "Should not find non-existent group"

    print("[OK] Group existence validation tests passed")


# ==============================================================================
# Unit Type Validation Tests
# ==============================================================================

def test_validate_unit_type_category():
    """Test unit type category validation."""
    print("Testing unit type category validation...")

    # Valid categories
    for category in ['plane', 'helicopter', 'ship', 'vehicle', 'static']:
        valid, error = validate_unit_type_category(category)
        assert valid and error is None, f"Valid category '{category}' failed"

    # Invalid category
    valid, error = validate_unit_type_category('invalid')
    assert not valid, "Should reject invalid category"

    print("[OK] Unit type category validation tests passed")


def test_validate_coalition():
    """Test coalition validation."""
    print("Testing coalition validation...")

    # Valid coalitions
    for coalition in ['blue', 'red', 'neutrals']:
        valid, error = validate_coalition(coalition)
        assert valid and error is None, f"Valid coalition '{coalition}' failed"

    # Invalid coalition
    valid, error = validate_coalition('invalid')
    assert not valid, "Should reject invalid coalition"

    valid, error = validate_coalition('Blue')  # Case sensitive
    assert not valid, "Should reject incorrect case"

    print("[OK] Coalition validation tests passed")


# ==============================================================================
# Property Validation Tests
# ==============================================================================

def test_validate_skill_level():
    """Test skill level validation."""
    print("Testing skill level validation...")

    # Valid skills
    for skill in ['Rookie', 'Trained', 'Average', 'Good', 'High', 'Excellent', 'Random', 'Player']:
        valid, error = validate_skill_level(skill)
        assert valid and error is None, f"Valid skill '{skill}' failed"

    # Invalid skill
    valid, error = validate_skill_level('Invalid')
    assert not valid, "Should reject invalid skill"

    valid, error = validate_skill_level('average')  # Case sensitive
    assert not valid, "Should reject incorrect case"

    print("[OK] Skill level validation tests passed")


def test_validate_waypoint_action():
    """Test waypoint action validation."""
    print("Testing waypoint action validation...")

    # Valid actions
    for action in ['Turning Point', 'Takeoff', 'Land']:
        valid, error = validate_waypoint_action(action)
        assert valid and error is None, f"Valid action '{action}' failed"

    # Invalid action
    valid, error = validate_waypoint_action('Invalid Action')
    assert not valid, "Should reject invalid action"

    print("[OK] Waypoint action validation tests passed")


def test_validate_altitude_type():
    """Test altitude type validation."""
    print("Testing altitude type validation...")

    # Valid types
    for alt_type in ['BARO', 'RADIO']:
        valid, error = validate_altitude_type(alt_type)
        assert valid and error is None, f"Valid alt_type '{alt_type}' failed"

    # Invalid type
    valid, error = validate_altitude_type('INVALID')
    assert not valid, "Should reject invalid altitude type"

    print("[OK] Altitude type validation tests passed")


# ==============================================================================
# ID Validation Tests
# ==============================================================================

def test_validate_id():
    """Test ID validation."""
    print("Testing ID validation...")

    # Valid IDs
    valid, error = validate_id(1)
    assert valid and error is None, "Valid ID failed"

    valid, error = validate_id("123", "group")
    assert valid and error is None, "Valid ID string failed"

    # Invalid IDs
    valid, error = validate_id(0)
    assert not valid, "Should reject zero ID"

    valid, error = validate_id(-5)
    assert not valid, "Should reject negative ID"

    valid, error = validate_id("invalid")
    assert not valid, "Should reject non-numeric ID"

    print("[OK] ID validation tests passed")


# ==============================================================================
# Batch Validation Tests
# ==============================================================================

def test_validate_add_group_params():
    """Test add group parameter validation."""
    print("Testing add group parameter validation...")

    # Valid parameters
    valid, error = validate_add_group_params(
        "Fighter-1",
        "plane",
        "blue",
        {"x": 1000, "y": 2000, "alt": 5000},
        "Average"
    )
    assert valid and error is None, f"Valid add group params failed: {error}"

    # Invalid group name
    valid, error = validate_add_group_params(
        "",  # Empty name
        "plane",
        "blue",
        {"x": 1000, "y": 2000, "alt": 5000}
    )
    assert not valid, "Should reject invalid group name"

    # Invalid unit type category
    valid, error = validate_add_group_params(
        "Fighter-1",
        "invalid",  # Invalid category
        "blue",
        {"x": 1000, "y": 2000}
    )
    assert not valid, "Should reject invalid unit type category"

    # Invalid coalition
    valid, error = validate_add_group_params(
        "Fighter-1",
        "plane",
        "invalid",  # Invalid coalition
        {"x": 1000, "y": 2000, "alt": 5000}
    )
    assert not valid, "Should reject invalid coalition"

    # Missing altitude for aircraft
    valid, error = validate_add_group_params(
        "Fighter-1",
        "plane",
        "blue",
        {"x": 1000, "y": 2000}  # Missing altitude
    )
    assert not valid, "Should reject missing altitude for aircraft"

    # Invalid skill
    valid, error = validate_add_group_params(
        "Fighter-1",
        "plane",
        "blue",
        {"x": 1000, "y": 2000, "alt": 5000},
        "InvalidSkill"
    )
    assert not valid, "Should reject invalid skill"

    print("[OK] Add group parameter validation tests passed")


def test_validate_modify_group_params():
    """Test modify group parameter validation."""
    print("Testing modify group parameter validation...")

    if not TEST_MIZ.exists():
        print("[SKIP] test.miz not found")
        return

    # Load test mission
    parser = MizParser(str(TEST_MIZ))
    parser.extract()
    content = parser.get_mission_content()
    parser.cleanup()

    # Valid modification
    valid, error = validate_modify_group_params(
        content,
        "Aerial-1",
        new_position={"x": 5000, "y": 6000}
    )
    assert valid and error is None, f"Valid modify params failed: {error}"

    # Non-existent group
    valid, error = validate_modify_group_params(
        content,
        "NonExistentGroup",
        new_position={"x": 5000, "y": 6000}
    )
    assert not valid, "Should reject non-existent group"

    # Invalid new position
    valid, error = validate_modify_group_params(
        content,
        "Aerial-1",
        new_position={"x": 5000}  # Missing y
    )
    assert not valid, "Should reject invalid new position"

    # Invalid new name
    valid, error = validate_modify_group_params(
        content,
        "Aerial-1",
        new_name=""  # Empty name
    )
    assert not valid, "Should reject invalid new name"

    print("[OK] Modify group parameter validation tests passed")


# ==============================================================================
# Utility Function Tests
# ==============================================================================

def test_get_validation_errors():
    """Test error collection utility."""
    print("Testing validation error collection...")

    # All valid
    validations = [
        (True, None),
        (True, None),
        (True, None)
    ]
    errors = get_validation_errors(validations)
    assert len(errors) == 0, "Should have no errors"

    # Some invalid
    validations = [
        (True, None),
        (False, "Error 1"),
        (False, "Error 2")
    ]
    errors = get_validation_errors(validations)
    assert len(errors) == 2, "Should have 2 errors"
    assert "Error 1" in errors, "Should contain Error 1"
    assert "Error 2" in errors, "Should contain Error 2"

    print("[OK] Validation error collection tests passed")


def test_raise_if_invalid():
    """Test raise utility."""
    print("Testing raise_if_invalid utility...")

    # Should not raise
    try:
        raise_if_invalid(True, None)
    except ValueError:
        assert False, "Should not raise for valid"

    # Should raise
    try:
        raise_if_invalid(False, "Test error")
        assert False, "Should raise for invalid"
    except ValueError as e:
        assert "Test error" in str(e), "Should contain error message"

    print("[OK] raise_if_invalid tests passed")


# ==============================================================================
# Test Runner
# ==============================================================================

if __name__ == "__main__":
    print("=" * 70)
    print("Testing utils/validation.py - Validation Functions")
    print("=" * 70)
    print()

    tests = [
        ("Position Validation", test_validate_position),
        ("Coordinate Validation", test_validate_coordinates),
        ("Group Name Validation", test_validate_group_name),
        ("Group Existence Validation", test_validate_group_exists),
        ("Unit Type Category Validation", test_validate_unit_type_category),
        ("Coalition Validation", test_validate_coalition),
        ("Skill Level Validation", test_validate_skill_level),
        ("Waypoint Action Validation", test_validate_waypoint_action),
        ("Altitude Type Validation", test_validate_altitude_type),
        ("ID Validation", test_validate_id),
        ("Add Group Params Validation", test_validate_add_group_params),
        ("Modify Group Params Validation", test_validate_modify_group_params),
        ("Validation Error Collection", test_get_validation_errors),
        ("Raise If Invalid", test_raise_if_invalid),
    ]

    passed = 0
    failed = 0
    skipped = 0

    for test_name, test_func in tests:
        try:
            print(f"Running: {test_name}...")
            test_func()
            passed += 1
        except AssertionError as e:
            print(f"[FAILED] {test_name}: {e}")
            failed += 1
        except Exception as e:
            if "[SKIP]" in str(e):
                print(f"[SKIP] {test_name}")
                skipped += 1
            else:
                print(f"[ERROR] {test_name}: {e}")
                import traceback
                traceback.print_exc()
                failed += 1

    print()
    print("=" * 70)
    print(f"Results: {passed} passed, {failed} failed, {skipped} skipped")
    print("=" * 70)

    sys.exit(0 if failed == 0 else 1)
