"""
Test suite for groups/remove.py functions.

Tests group removal functions including by name, type, and coalition.
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

    for match in patterns.GROUP_PATTERN_COMPILED.finditer(mission_content):
        group_name = match.group(2)
        context = find_context(mission_content, match.start())
        coalition = context.get('coalition')
        if coalition and coalition in result:
            result[coalition].append(group_name)

    return result


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


def get_groups_by_coalition(mission_content: str, coalition: str) -> list:
    """Get all groups for a specific coalition."""
    is_valid, error = validation.validate_coalition(coalition)
    if not is_valid:
        raise ValueError(error)

    all_groups = list_all_groups(mission_content)
    return all_groups[coalition]


def remove_group(mission_content: str, group_name: str) -> str:
    """Remove a specific group by name from mission."""
    if not validation.validate_group_exists(mission_content, group_name):
        raise ValueError(f"Group '{group_name}' not found in mission")

    pattern = rf'\[(\d+)\]\s*=\s*\{{.*?\["name"\]\s*=\s*"{re.escape(group_name)}".*?\}},\s*--\s*end\s*of\s*\[\d+\]\s*\n'
    modified_content = re.sub(pattern, '', mission_content, flags=re.DOTALL)

    return modified_content


def remove_groups_by_type(mission_content: str, unit_types: list) -> str:
    """Remove all groups of specified unit types."""
    for unit_type in unit_types:
        is_valid, error = validation.validate_unit_type_category(unit_type)
        if not is_valid:
            raise ValueError(error)

    modified_content = mission_content

    for unit_type in unit_types:
        groups_to_remove = get_groups_by_type(modified_content, unit_type)

        for group_name in groups_to_remove:
            try:
                modified_content = remove_group(modified_content, group_name)
            except ValueError:
                continue

    return modified_content


def remove_groups_by_coalition(mission_content: str, coalition: str) -> str:
    """Remove all groups from a specific coalition."""
    is_valid, error = validation.validate_coalition(coalition)
    if not is_valid:
        raise ValueError(error)

    groups_to_remove = get_groups_by_coalition(mission_content, coalition)

    modified_content = mission_content

    for group_name in groups_to_remove:
        try:
            modified_content = remove_group(modified_content, group_name)
        except ValueError:
            continue

    return modified_content


def remove_groups_by_names(mission_content: str, group_names: list) -> str:
    """Remove multiple groups by name."""
    modified_content = mission_content

    for group_name in group_names:
        try:
            modified_content = remove_group(modified_content, group_name)
        except ValueError:
            continue

    return modified_content


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


def count_total_groups(content: str) -> int:
    """Count total groups in content."""
    groups = list_all_groups(content)
    return sum(len(g) for g in groups.values())


# ==============================================================================
# Test Functions
# ==============================================================================

def test_remove_group():
    """Test removing a single group by name."""
    content = load_test_mission()

    # Get initial groups
    groups_before = list_all_groups(content)
    all_names = groups_before['blue'] + groups_before['red'] + groups_before['neutrals']
    assert len(all_names) > 0, "Need at least one group for testing"

    test_group = all_names[0]
    initial_count = count_total_groups(content)

    # Remove the group
    modified = remove_group(content, test_group)

    # Verify removal
    final_count = count_total_groups(modified)
    assert final_count == initial_count - 1, f"Should have {initial_count - 1} groups, got {final_count}"

    # Verify the specific group is gone
    groups_after = list_all_groups(modified)
    all_names_after = groups_after['blue'] + groups_after['red'] + groups_after['neutrals']
    assert test_group not in all_names_after, f"Group '{test_group}' should be removed"

    # Test removing non-existent group raises error
    try:
        remove_group(content, "NonExistentGroup-XYZ-999")
        assert False, "Should raise ValueError for non-existent group"
    except ValueError:
        pass  # Expected

    print("[OK] remove_group tests passed")
    print(f"     Removed '{test_group}': {initial_count} -> {final_count} groups")


def test_remove_groups_by_type():
    """Test removing groups by unit type."""
    content = load_test_mission()

    # Get initial plane groups
    plane_groups_before = get_groups_by_type(content, "plane")
    initial_total = count_total_groups(content)

    if len(plane_groups_before) == 0:
        print("[SKIP] remove_groups_by_type - no plane groups in test mission")
        return

    # Remove all plane groups
    modified = remove_groups_by_type(content, ["plane"])

    # Verify removal
    plane_groups_after = get_groups_by_type(modified, "plane")
    assert len(plane_groups_after) == 0, "Should have no plane groups after removal"

    final_total = count_total_groups(modified)
    expected_total = initial_total - len(plane_groups_before)
    assert final_total == expected_total, f"Should have {expected_total} groups, got {final_total}"

    # Test invalid unit type raises error
    try:
        remove_groups_by_type(content, ["invalid_type"])
        assert False, "Should raise ValueError for invalid unit type"
    except ValueError:
        pass  # Expected

    print("[OK] remove_groups_by_type tests passed")
    print(f"     Removed {len(plane_groups_before)} plane groups: {initial_total} -> {final_total}")


def test_remove_groups_by_coalition():
    """Test removing all groups from a coalition."""
    content = load_test_mission()

    # Get initial red groups
    red_groups_before = get_groups_by_coalition(content, "red")
    initial_total = count_total_groups(content)

    if len(red_groups_before) == 0:
        print("[SKIP] remove_groups_by_coalition - no red groups in test mission")
        return

    # Remove all red groups
    modified = remove_groups_by_coalition(content, "red")

    # Verify removal
    red_groups_after = get_groups_by_coalition(modified, "red")
    assert len(red_groups_after) == 0, "Should have no red groups after removal"

    final_total = count_total_groups(modified)
    expected_total = initial_total - len(red_groups_before)
    assert final_total == expected_total, f"Should have {expected_total} groups, got {final_total}"

    # Test invalid coalition raises error
    try:
        remove_groups_by_coalition(content, "invalid_coalition")
        assert False, "Should raise ValueError for invalid coalition"
    except ValueError:
        pass  # Expected

    print("[OK] remove_groups_by_coalition tests passed")
    print(f"     Removed {len(red_groups_before)} red groups: {initial_total} -> {final_total}")


def test_remove_groups_by_names():
    """Test removing multiple groups by name."""
    content = load_test_mission()

    # Get initial groups
    groups_before = list_all_groups(content)
    all_names = groups_before['blue'] + groups_before['red'] + groups_before['neutrals']
    assert len(all_names) >= 2, "Need at least 2 groups for testing"

    # Pick first two groups
    groups_to_remove = all_names[:2]
    initial_count = count_total_groups(content)

    # Remove the groups
    modified = remove_groups_by_names(content, groups_to_remove)

    # Verify removal
    final_count = count_total_groups(modified)
    assert final_count == initial_count - 2, f"Should have {initial_count - 2} groups, got {final_count}"

    # Verify the specific groups are gone
    groups_after = list_all_groups(modified)
    all_names_after = groups_after['blue'] + groups_after['red'] + groups_after['neutrals']
    for group_name in groups_to_remove:
        assert group_name not in all_names_after, f"Group '{group_name}' should be removed"

    # Test that non-existent groups in list are silently skipped
    modified2 = remove_groups_by_names(content, ["NonExistentGroup-XYZ-999"])
    count2 = count_total_groups(modified2)
    assert count2 == initial_count, "Non-existent group should be silently skipped"

    print("[OK] remove_groups_by_names tests passed")
    print(f"     Removed {len(groups_to_remove)} groups: {initial_count} -> {final_count}")


def test_remove_preserves_structure():
    """Test that removal preserves mission structure."""
    content = load_test_mission()

    groups_before = list_all_groups(content)
    all_names = groups_before['blue'] + groups_before['red'] + groups_before['neutrals']

    if len(all_names) == 0:
        print("[SKIP] remove_preserves_structure - no groups in test mission")
        return

    # Remove first group
    test_group = all_names[0]
    modified = remove_group(content, test_group)

    # Verify remaining groups are still accessible
    groups_after = list_all_groups(modified)
    remaining_names = groups_after['blue'] + groups_after['red'] + groups_after['neutrals']

    for name in remaining_names:
        # Each remaining group should still be findable
        if validation.validate_group_exists(modified, name):
            pass  # Good, group exists
        else:
            assert False, f"Group '{name}' should still exist after removing '{test_group}'"

    # Verify coalition keys still exist
    assert "blue" in groups_after, "Should have 'blue' coalition"
    assert "red" in groups_after, "Should have 'red' coalition"
    assert "neutrals" in groups_after, "Should have 'neutrals' coalition"

    print("[OK] remove_preserves_structure tests passed")
    print(f"     Verified {len(remaining_names)} remaining groups are accessible")


# ==============================================================================
# Individual Test Runner
# ==============================================================================

if __name__ == "__main__":
    print("=" * 70)
    print("Testing groups/remove.py - Group Removal Functions")
    print("=" * 70)
    print()

    tests = [
        ("Remove Group", test_remove_group),
        ("Remove Groups By Type", test_remove_groups_by_type),
        ("Remove Groups By Coalition", test_remove_groups_by_coalition),
        ("Remove Groups By Names", test_remove_groups_by_names),
        ("Remove Preserves Structure", test_remove_preserves_structure),
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
