"""
Test suite for coordinates/extract.py functions.

Tests coordinate extraction from groups, units, and waypoints.
"""

import re
import sys
from pathlib import Path

# Add parent directory to path for imports
sys.path.insert(0, str(Path(__file__).parent.parent))

from parsing.miz_parser import MizParser
from utils import patterns
from core import find_context, UNIT_TYPES


# ==============================================================================
# Test Configuration
# ==============================================================================

TEST_MIZ = Path(__file__).parent / "test.miz"


# ==============================================================================
# Local Function Implementations (to avoid relative import issues)
# ==============================================================================

def get_group_coordinates(mission_content: str, group_name: str):
    """Get coordinates of a group (first unit's position)."""
    # Find the group name in the content
    name_pattern = rf'\["name"\]\s*=\s*"{re.escape(group_name)}"'
    name_match = re.search(name_pattern, mission_content)

    if not name_match:
        raise ValueError(f"Group '{group_name}' not found in mission")

    group_start_pos = name_match.start()
    search_start = max(0, group_start_pos - 5000)
    preceding_content = mission_content[search_start:group_start_pos]

    group_starts = list(re.finditer(r'\[(\d+)\]\s*=\s*\{', preceding_content))
    if not group_starts:
        raise ValueError(f"Could not find group block for '{group_name}'")

    last_start = group_starts[-1]
    actual_group_start = search_start + last_start.start()
    group_content = mission_content[actual_group_start:actual_group_start + 10000]

    units_match = patterns.UNITS_SECTION_PATTERN_COMPILED.search(group_content)
    if units_match:
        units_content = units_match.group(1)
        x_match = patterns.X_COORD_PATTERN_COMPILED.search(units_content)
        y_match = patterns.Y_COORD_PATTERN_COMPILED.search(units_content)
        alt_match = patterns.ALT_PATTERN_COMPILED.search(units_content)
    else:
        x_match = patterns.X_COORD_PATTERN_COMPILED.search(group_content)
        y_match = patterns.Y_COORD_PATTERN_COMPILED.search(group_content)
        alt_match = patterns.ALT_PATTERN_COMPILED.search(group_content)

    coords = {}
    if x_match:
        coords["x"] = float(x_match.group(1))
    if y_match:
        coords["y"] = float(y_match.group(1))
    if alt_match:
        coords["alt"] = float(alt_match.group(1))

    if "x" not in coords or "y" not in coords:
        raise ValueError(f"Could not extract coordinates from group '{group_name}'")

    return coords


def get_unit_coordinates(mission_content: str, unit_name: str):
    """Get coordinates of a specific unit."""
    name_pattern = rf'\["name"\]\s*=\s*"{re.escape(unit_name)}"'
    name_match = re.search(name_pattern, mission_content)

    if not name_match:
        raise ValueError(f"Unit '{unit_name}' not found in mission")

    search_start = max(0, name_match.start() - 1000)
    search_end = min(len(mission_content), name_match.end() + 500)
    unit_content = mission_content[search_start:search_end]

    coords = {}
    name_pos_in_content = name_match.start() - search_start

    x_matches = list(patterns.X_COORD_PATTERN_COMPILED.finditer(unit_content))
    if x_matches:
        closest_x = min(x_matches, key=lambda m: abs(m.start() - name_pos_in_content))
        coords["x"] = float(closest_x.group(1))

    y_matches = list(patterns.Y_COORD_PATTERN_COMPILED.finditer(unit_content))
    if y_matches:
        closest_y = min(y_matches, key=lambda m: abs(m.start() - name_pos_in_content))
        coords["y"] = float(closest_y.group(1))

    alt_matches = list(patterns.ALT_PATTERN_COMPILED.finditer(unit_content))
    if alt_matches:
        closest_alt = min(alt_matches, key=lambda m: abs(m.start() - name_pos_in_content))
        coords["alt"] = float(closest_alt.group(1))

    if "x" not in coords or "y" not in coords:
        raise ValueError(f"Could not extract coordinates from unit '{unit_name}'")

    return coords


def get_all_positions(mission_content: str, coalition=None, unit_type=None):
    """Get positions of all groups."""
    result = {}

    group_matches = list(patterns.GROUP_PATTERN_COMPILED.finditer(mission_content))

    for match in group_matches:
        units_content = match.group(1)
        group_name = match.group(2)

        context = find_context(mission_content, match.start())
        group_coalition = context.get('coalition')
        group_unit_type = context.get('unit_type')

        if coalition is not None and group_coalition != coalition:
            continue
        if unit_type is not None and group_unit_type != unit_type:
            continue

        x_match = patterns.X_COORD_PATTERN_COMPILED.search(units_content)
        y_match = patterns.Y_COORD_PATTERN_COMPILED.search(units_content)

        if x_match and y_match:
            group_info = {
                "x": float(x_match.group(1)),
                "y": float(y_match.group(1)),
                "coalition": group_coalition,
                "unit_type": group_unit_type
            }

            alt_match = patterns.ALT_PATTERN_COMPILED.search(units_content)
            if alt_match:
                group_info["alt"] = float(alt_match.group(1))

            result[group_name] = group_info

    return result


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

    print("[OK] get_all_positions tests passed")
    print(f"     Found {len(positions)} total groups")
    print(f"     Blue groups: {len(blue_positions)}")


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
            import traceback
            traceback.print_exc()
            failed += 1

    print()
    print("=" * 70)
    print(f"Results: {passed} passed, {failed} failed")
    print("=" * 70)

    sys.exit(0 if failed == 0 else 1)
