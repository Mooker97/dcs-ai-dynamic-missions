"""
Test suite for utils/patterns.py regex patterns.

Tests verify that regex patterns correctly extract information from Lua mission data.
Uses standard test.miz file as test data source.
"""

import sys
from pathlib import Path

# Add parent directory to path for imports
sys.path.insert(0, str(Path(__file__).parent.parent))

from utils.patterns import (
    GROUP_PATTERN_COMPILED,
    POSITION_PATTERN_COMPILED,
    GROUP_ID_PATTERN_COMPILED,
    UNIT_ID_PATTERN_COMPILED,
    SKILL_PATTERN_COMPILED,
    extract_field
)
from parsing.miz_parser import MizParser


# ==============================================================================
# Test Configuration
# ==============================================================================

TEST_MIZ = Path(__file__).parent / "test.miz"


# ==============================================================================
# Test Data Setup
# ==============================================================================

def load_test_mission():
    """Load mission content from test.miz."""
    if not TEST_MIZ.exists():
        raise FileNotFoundError(f"test.miz not found at {TEST_MIZ}")

    parser = MizParser(str(TEST_MIZ))
    parser.extract()
    content = parser.get_mission_content()
    parser.cleanup()
    return content


# ==============================================================================
# Test Functions
# ==============================================================================

def test_group_pattern():
    """Test group pattern extraction from test.miz."""
    content = load_test_mission()

    matches = list(GROUP_PATTERN_COMPILED.finditer(content))
    assert len(matches) > 0, "Should find at least one group in test.miz"

    # Test first match
    units_content = matches[0].group(1)
    group_name = matches[0].group(2)

    assert group_name is not None and len(group_name) > 0, "Group should have a name"
    assert len(units_content) > 0, "Group should have units content"

    print(f"[OK] Group pattern test passed - Found {len(matches)} groups")
    print(f"     First group: '{group_name}'")


def test_position_pattern():
    """Test position extraction from test.miz."""
    content = load_test_mission()

    matches = list(POSITION_PATTERN_COMPILED.finditer(content))
    assert len(matches) > 0, "Should find at least one position in test.miz"

    # Test first position
    x, y = matches[0].groups()
    x_val = float(x)
    y_val = float(y)

    # Positions should be reasonable DCS map coordinates
    assert -500000 < x_val < 500000, f"X coordinate seems unreasonable: {x_val}"
    assert -500000 < y_val < 500000, f"Y coordinate seems unreasonable: {y_val}"

    print(f"[OK] Position pattern test passed - Found {len(matches)} positions")
    print(f"     First position: x={x_val}, y={y_val}")


def test_id_patterns():
    """Test ID extraction from test.miz."""
    content = load_test_mission()

    group_matches = list(GROUP_ID_PATTERN_COMPILED.finditer(content))
    assert len(group_matches) > 0, "Should find at least one group ID in test.miz"

    group_id = int(group_matches[0].group(1))
    assert group_id > 0, f"Group ID should be positive: {group_id}"

    unit_matches = list(UNIT_ID_PATTERN_COMPILED.finditer(content))
    assert len(unit_matches) > 0, "Should find at least one unit ID in test.miz"

    unit_id = int(unit_matches[0].group(1))
    assert unit_id > 0, f"Unit ID should be positive: {unit_id}"

    print(f"[OK] ID pattern tests passed")
    print(f"     Found {len(group_matches)} group IDs, {len(unit_matches)} unit IDs")


def test_skill_pattern():
    """Test skill extraction from test.miz."""
    content = load_test_mission()

    matches = list(SKILL_PATTERN_COMPILED.finditer(content))
    assert len(matches) > 0, "Should find at least one skill level in test.miz"

    skill = matches[0].group(1)
    valid_skills = ["Rookie", "Trained", "Average", "Good", "High", "Excellent", "Random", "Player"]
    assert skill in valid_skills, f"Skill '{skill}' not in valid skills list"

    print(f"[OK] Skill pattern test passed - Found {len(matches)} skill levels")
    print(f"     First skill: '{skill}'")


def test_extract_field():
    """Test extract_field utility function with test.miz."""
    content = load_test_mission()

    # Test extracting x coordinate (should exist)
    x = extract_field(content, 'x', float)
    assert x is not None, "Should extract x coordinate"
    assert isinstance(x, float), f"x should be float, got {type(x)}"

    # Test extracting a name (should exist)
    name = extract_field(content, 'name', str)
    assert name is not None, "Should extract a name"
    assert isinstance(name, str), f"name should be str, got {type(name)}"
    assert len(name) > 0, "name should not be empty"

    # Test extracting boolean field
    visible = extract_field(content, 'visible', bool)
    assert visible is not None, "Should extract visible field"
    assert isinstance(visible, bool), f"visible should be bool, got {type(visible)}"

    print(f"[OK] extract_field test passed")
    print(f"     Extracted: x={x}, name='{name}', visible={visible}")



# ==============================================================================
# Individual Test Runner (Optional - use run_tests.py for all tests)
# ==============================================================================

if __name__ == "__main__":
    """Run this test file individually for debugging."""
    print("=" * 70)
    print("Testing utils/patterns.py - Regex Pattern Validation")
    print("=" * 70)
    print()

    tests = [
        ("Group Pattern", test_group_pattern),
        ("Position Pattern", test_position_pattern),
        ("ID Patterns", test_id_patterns),
        ("Skill Pattern", test_skill_pattern),
        ("Extract Field", test_extract_field),
    ]

    passed = 0
    failed = 0

    for test_name, test_func in tests:
        try:
            print(f"Running: {test_name}...")
            test_func()
            passed += 1
        except AssertionError as e:
            print(f"[FAILED] {test_name}: {e}")
            failed += 1
        except Exception as e:
            print(f"[ERROR] {test_name}: {e}")
            failed += 1

    print()
    print("=" * 70)
    print(f"Results: {passed} passed, {failed} failed")
    print("=" * 70)
    print()
    print("Note: Use 'python run_tests.py' to run all tests in the test suite")
    print()

    sys.exit(0 if failed == 0 else 1)
