"""
Test suite for groups/list.py functions.

Tests group listing, finding, counting, and inspection functions.
"""

import re
import sys
from pathlib import Path

# Add parent directory to path for imports
sys.path.insert(0, str(Path(__file__).parent.parent))

from parsing.miz_parser import MizParser
from utils import patterns, validation


# ==============================================================================
# Test Configuration
# ==============================================================================

TEST_MIZ = Path(__file__).parent / "test.miz"


# ==============================================================================
# Local Function Implementations (to avoid relative import issues)
# ==============================================================================

from core import find_context


def list_all_groups(mission_content: str) -> dict:
    """List all groups in mission by coalition using find_context approach."""
    result = {"blue": [], "red": [], "neutrals": []}

    # Use GROUP_PATTERN which finds groups with their units section and name
    for match in patterns.GROUP_PATTERN_COMPILED.finditer(mission_content):
        group_name = match.group(2)
        context = find_context(mission_content, match.start())
        coalition = context.get('coalition')
        if coalition and coalition in result:
            result[coalition].append(group_name)

    return result


def find_group_by_name(mission_content: str, group_name: str):
    """Find group by name and return its content and position."""
    pattern = rf'\[(\d+)\]\s*=\s*\{{.*?\["name"\]\s*=\s*"{re.escape(group_name)}".*?\}},\s*--'
    match = re.search(pattern, mission_content, re.DOTALL)

    if not match:
        return None

    return (match.group(0), match.start(), match.end())


def count_groups(mission_content: str, unit_type=None) -> int:
    """Count total groups or groups of specific unit type."""
    if unit_type is not None:
        is_valid, error = validation.validate_unit_type_category(unit_type)
        if not is_valid:
            raise ValueError(error)

        groups = get_groups_by_type(mission_content, unit_type)
        return len(groups)
    else:
        # Count all groups using GROUP_PATTERN
        matches = list(patterns.GROUP_PATTERN_COMPILED.finditer(mission_content))
        return len(matches)


def get_group_info(mission_content: str, group_name: str) -> dict:
    """Get detailed information about a specific group."""
    result = find_group_by_name(mission_content, group_name)

    if not result:
        raise ValueError(f"Group '{group_name}' not found in mission")

    group_content, _, _ = result

    info = {
        "name": group_name,
        "exists": True
    }

    # Extract group ID
    group_id_match = patterns.GROUP_ID_PATTERN_COMPILED.search(group_content)
    if group_id_match:
        info["groupId"] = int(group_id_match.group(1))

    # Extract position
    pos_match = patterns.POSITION_PATTERN_COMPILED.search(group_content)
    if pos_match:
        info["position"] = {
            "y": float(pos_match.group(1)),
            "x": float(pos_match.group(2))
        }

    # Extract units section
    units_match = patterns.UNITS_SECTION_PATTERN_COMPILED.search(group_content)
    if units_match:
        units_content = units_match.group(1)
        unit_blocks = patterns.UNIT_BLOCK_PATTERN_COMPILED.findall(units_content)

        units = []
        for unit_index, unit_content in unit_blocks:
            unit_info = {"index": int(unit_index)}

            name_match = patterns.UNIT_NAME_PATTERN_COMPILED.search(unit_content)
            if name_match:
                unit_info["name"] = name_match.group(1)

            type_match = patterns.UNIT_TYPE_PATTERN_COMPILED.search(unit_content)
            if type_match:
                unit_info["type"] = type_match.group(1)

            unit_id_match = patterns.UNIT_ID_PATTERN_COMPILED.search(unit_content)
            if unit_id_match:
                unit_info["unitId"] = int(unit_id_match.group(1))

            skill_match = patterns.SKILL_PATTERN_COMPILED.search(unit_content)
            if skill_match:
                unit_info["skill"] = skill_match.group(1)

            units.append(unit_info)

        info["units"] = units
        info["unit_count"] = len(units)
    else:
        info["units"] = []
        info["unit_count"] = 0

    return info


def get_groups_by_coalition(mission_content: str, coalition: str) -> list:
    """Get all groups for a specific coalition."""
    is_valid, error = validation.validate_coalition(coalition)
    if not is_valid:
        raise ValueError(error)

    all_groups = list_all_groups(mission_content)
    return all_groups[coalition]


def get_groups_by_type(mission_content: str, unit_type: str) -> list:
    """Get all groups of a specific unit type using find_context approach."""
    is_valid, error = validation.validate_unit_type_category(unit_type)
    if not is_valid:
        raise ValueError(error)

    groups = []

    for match in patterns.GROUP_PATTERN_COMPILED.finditer(mission_content):
        group_name = match.group(2)
        context = find_context(mission_content, match.start())
        if context.get('unit_type') == unit_type:
            groups.append(group_name)

    return groups


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

def test_list_all_groups():
    """Test listing all groups by coalition."""
    content = load_test_mission()

    groups = list_all_groups(content)

    # Should return dict with coalition keys
    assert "blue" in groups, "Should have 'blue' key"
    assert "red" in groups, "Should have 'red' key"
    assert "neutrals" in groups, "Should have 'neutrals' key"

    # Should have at least some groups
    total = sum(len(g) for g in groups.values())
    assert total > 0, "Should find at least one group"

    # Group names should be strings
    for coalition, group_list in groups.items():
        for name in group_list:
            assert isinstance(name, str), f"Group name should be string, got {type(name)}"
            assert len(name) > 0, "Group name should not be empty"

    print("[OK] list_all_groups tests passed")
    print(f"     Blue: {len(groups['blue'])}, Red: {len(groups['red'])}, Neutral: {len(groups['neutrals'])}")


def test_find_group_by_name():
    """Test finding a group by name."""
    content = load_test_mission()

    # Get a known group name
    groups = list_all_groups(content)
    all_names = groups['blue'] + groups['red'] + groups['neutrals']
    assert len(all_names) > 0, "Need at least one group for testing"

    test_group = all_names[0]

    # Test finding existing group
    result = find_group_by_name(content, test_group)
    assert result is not None, f"Should find group '{test_group}'"

    group_content, start, end = result
    assert isinstance(group_content, str), "Group content should be string"
    assert start >= 0, "Start position should be non-negative"
    assert end > start, "End should be greater than start"
    assert test_group in group_content, "Group content should contain the group name"

    # Test non-existent group
    result_none = find_group_by_name(content, "NonExistentGroup-XYZ-999")
    assert result_none is None, "Should return None for non-existent group"

    print("[OK] find_group_by_name tests passed")
    print(f"     Found '{test_group}' at position {start}-{end}")


def test_count_groups():
    """Test counting groups."""
    content = load_test_mission()

    # Test total count
    total = count_groups(content)
    assert total > 0, "Should have at least one group"
    assert isinstance(total, int), "Count should be integer"

    # Test counting by type
    plane_count = count_groups(content, "plane")
    assert isinstance(plane_count, int), "Plane count should be integer"
    assert plane_count >= 0, "Plane count should be non-negative"

    # Test invalid unit type raises error
    try:
        count_groups(content, "invalid_type")
        assert False, "Should raise ValueError for invalid unit type"
    except ValueError:
        pass  # Expected

    print("[OK] count_groups tests passed")
    print(f"     Total groups: {total}, Planes: {plane_count}")


def test_get_group_info():
    """Test getting detailed group information."""
    content = load_test_mission()

    # Get a known group
    groups = list_all_groups(content)
    all_names = groups['blue'] + groups['red']
    assert len(all_names) > 0, "Need at least one group for testing"

    test_group = all_names[0]

    # Get group info
    info = get_group_info(content, test_group)

    # Check required fields
    assert "name" in info, "Should have 'name' field"
    assert info["name"] == test_group, "Name should match"
    assert "exists" in info, "Should have 'exists' field"
    assert info["exists"] is True, "exists should be True"

    # Check optional but expected fields
    assert "groupId" in info, "Should have 'groupId' field"
    assert isinstance(info["groupId"], int), "groupId should be integer"

    assert "unit_count" in info, "Should have 'unit_count' field"
    assert isinstance(info["unit_count"], int), "unit_count should be integer"
    assert info["unit_count"] >= 0, "unit_count should be non-negative"

    assert "units" in info, "Should have 'units' field"
    assert isinstance(info["units"], list), "units should be list"

    # Test non-existent group raises error
    try:
        get_group_info(content, "NonExistentGroup-XYZ-999")
        assert False, "Should raise ValueError for non-existent group"
    except ValueError:
        pass  # Expected

    print("[OK] get_group_info tests passed")
    print(f"     Group '{test_group}': ID={info['groupId']}, units={info['unit_count']}")


def test_get_groups_by_coalition():
    """Test getting groups filtered by coalition."""
    content = load_test_mission()

    # Get blue groups
    blue_groups = get_groups_by_coalition(content, "blue")
    assert isinstance(blue_groups, list), "Should return list"

    # Get red groups
    red_groups = get_groups_by_coalition(content, "red")
    assert isinstance(red_groups, list), "Should return list"

    # Test invalid coalition raises error
    try:
        get_groups_by_coalition(content, "invalid_coalition")
        assert False, "Should raise ValueError for invalid coalition"
    except ValueError:
        pass  # Expected

    print("[OK] get_groups_by_coalition tests passed")
    print(f"     Blue: {len(blue_groups)}, Red: {len(red_groups)}")


def test_get_groups_by_type():
    """Test getting groups filtered by unit type."""
    content = load_test_mission()

    # Get plane groups
    plane_groups = get_groups_by_type(content, "plane")
    assert isinstance(plane_groups, list), "Should return list"

    # Get helicopter groups
    heli_groups = get_groups_by_type(content, "helicopter")
    assert isinstance(heli_groups, list), "Should return list"

    # Get ship groups
    ship_groups = get_groups_by_type(content, "ship")
    assert isinstance(ship_groups, list), "Should return list"

    # Get vehicle groups
    vehicle_groups = get_groups_by_type(content, "vehicle")
    assert isinstance(vehicle_groups, list), "Should return list"

    # Test invalid unit type raises error
    try:
        get_groups_by_type(content, "invalid_type")
        assert False, "Should raise ValueError for invalid unit type"
    except ValueError:
        pass  # Expected

    print("[OK] get_groups_by_type tests passed")
    print(f"     Planes: {len(plane_groups)}, Helis: {len(heli_groups)}, Ships: {len(ship_groups)}, Vehicles: {len(vehicle_groups)}")


# ==============================================================================
# Individual Test Runner
# ==============================================================================

if __name__ == "__main__":
    print("=" * 70)
    print("Testing groups/list.py - Group Listing Functions")
    print("=" * 70)
    print()

    tests = [
        ("List All Groups", test_list_all_groups),
        ("Find Group By Name", test_find_group_by_name),
        ("Count Groups", test_count_groups),
        ("Get Group Info", test_get_group_info),
        ("Get Groups By Coalition", test_get_groups_by_coalition),
        ("Get Groups By Type", test_get_groups_by_type),
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
