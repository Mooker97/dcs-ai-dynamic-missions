"""
Test suite for coordinates/extract.py functions.

Tests coordinate extraction from groups, units, and waypoints.
"""

import sys
from pathlib import Path

# Add parent directory to path for imports
sys.path.insert(0, str(Path(__file__).parent.parent))

from coordinates.extract import (
    get_group_coordinates,
    get_unit_coordinates,
    get_all_positions,
    get_waypoint_coordinates,
    get_group_coordinates_file,
    get_unit_coordinates_file,
    get_all_positions_file,
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

def test_get_group_coordinates():
    """Test extracting group coordinates."""
    content = load_test_mission()

    # Test with known group
    coords = get_group_coordinates(content, "Player F16")
    assert "x" in coords, "Should have x coordinate"
    assert "y" in coords, "Should have y coordinate"
    assert isinstance(coords["x"], float), "x should be float"
    assert isinstance(coords["y"], float), "y should be float"

    # Check altitude is present for aircraft
    assert "alt" in coords, "Aircraft group should have altitude"
    assert coords["alt"] > 0, "Altitude should be positive"

    # Test with non-existent group
    try:
        get_group_coordinates(content, "NonExistentGroup-999")
        assert False, "Should raise ValueError for non-existent group"
    except ValueError:
        pass  # Expected

    print("[OK] get_group_coordinates tests passed")
    print(f"     Player F16: x={coords['x']:.1f}, y={coords['y']:.1f}, alt={coords['alt']:.1f}")


def test_get_unit_coordinates():
    """Test extracting unit coordinates."""
    content = load_test_mission()

    # Test with known unit
    coords = get_unit_coordinates(content, "Aerial-1-1")
    assert "x" in coords, "Should have x coordinate"
    assert "y" in coords, "Should have y coordinate"
    assert isinstance(coords["x"], float), "x should be float"
    assert isinstance(coords["y"], float), "y should be float"

    # Test another unit
    coords2 = get_unit_coordinates(content, "Veteran f18-1-1")
    assert "x" in coords2, "Should have x coordinate"
    assert "y" in coords2, "Should have y coordinate"

    # Test with non-existent unit
    try:
        get_unit_coordinates(content, "NonExistentUnit-999")
        assert False, "Should raise ValueError for non-existent unit"
    except ValueError:
        pass  # Expected

    print("[OK] get_unit_coordinates tests passed")
    print(f"     Aerial-1-1: x={coords['x']:.1f}, y={coords['y']:.1f}")


def test_get_all_positions():
    """Test extracting all group positions."""
    content = load_test_mission()

    # Get all positions
    positions = get_all_positions(content)
    assert len(positions) > 0, "Should find at least one group"

    # Check structure of returned data
    for name, pos in positions.items():
        assert "x" in pos, f"Group {name} should have x coordinate"
        assert "y" in pos, f"Group {name} should have y coordinate"
        assert "coalition" in pos, f"Group {name} should have coalition"
        assert "unit_type" in pos, f"Group {name} should have unit_type"

    # Test coalition filter
    blue_positions = get_all_positions(content, coalition="blue")
    for name, pos in blue_positions.items():
        assert pos["coalition"] == "blue", f"Group {name} should be blue coalition"

    # Test unit_type filter
    plane_positions = get_all_positions(content, unit_type="plane")
    for name, pos in plane_positions.items():
        assert pos["unit_type"] == "plane", f"Group {name} should be plane type"

    # Test invalid coalition
    try:
        get_all_positions(content, coalition="invalid")
        assert False, "Should raise ValueError for invalid coalition"
    except ValueError:
        pass  # Expected

    print("[OK] get_all_positions tests passed")
    print(f"     Found {len(positions)} total groups")
    print(f"     Blue groups: {len(blue_positions)}")


def test_file_wrappers():
    """Test convenience file wrapper functions."""
    if not TEST_MIZ.exists():
        print("[SKIP] test.miz not found")
        return

    # Test get_group_coordinates_file
    coords = get_group_coordinates_file(str(TEST_MIZ), "Player F16")
    assert "x" in coords and "y" in coords, "Should extract coordinates"

    # Test get_unit_coordinates_file
    unit_coords = get_unit_coordinates_file(str(TEST_MIZ), "Aerial-1-1")
    assert "x" in unit_coords and "y" in unit_coords, "Should extract unit coordinates"

    # Test get_all_positions_file
    positions = get_all_positions_file(str(TEST_MIZ))
    assert len(positions) > 0, "Should find groups"

    # Test file not found
    try:
        get_group_coordinates_file("nonexistent.miz", "Group")
        assert False, "Should raise FileNotFoundError"
    except FileNotFoundError:
        pass  # Expected

    print("[OK] File wrapper tests passed")


# ==============================================================================
# Individual Test Runner
# ==============================================================================

if __name__ == "__main__":
    print("=" * 70)
    print("Testing coordinates/extract.py - Coordinate Extraction")
    print("=" * 70)
    print()

    tests = [
        ("Get Group Coordinates", test_get_group_coordinates),
        ("Get Unit Coordinates", test_get_unit_coordinates),
        ("Get All Positions", test_get_all_positions),
        ("File Wrappers", test_file_wrappers),
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

    sys.exit(0 if failed == 0 else 1)
