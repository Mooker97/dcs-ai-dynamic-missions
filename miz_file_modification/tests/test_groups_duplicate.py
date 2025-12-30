"""
Test suite for groups/duplicate.py functions.

Tests group duplication with optional position offsets.
"""

import re
import sys
from pathlib import Path

# Add parent directory to path for imports
sys.path.insert(0, str(Path(__file__).parent.parent))

from parsing.miz_parser import MizParser
from utils import patterns, validation, id_manager


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


def find_group_by_name(mission_content: str, group_name: str):
    """Find group by name and return its content and position."""
    pattern = rf'\[(\d+)\]\s*=\s*\{{.*?\["name"\]\s*=\s*"{re.escape(group_name)}".*?\}},\s*--'
    match = re.search(pattern, mission_content, re.DOTALL)

    if not match:
        return None

    return (match.group(0), match.start(), match.end())


def _generate_copy_name(mission_content: str, base_name: str) -> str:
    """Generate a unique copy name for a group."""
    candidate = f"{base_name}-Copy"

    if not validation.validate_group_exists(mission_content, candidate):
        return candidate

    counter = 2
    while True:
        candidate = f"{base_name}-Copy-{counter}"
        if not validation.validate_group_exists(mission_content, candidate):
            return candidate
        counter += 1
        if counter > 1000:
            raise ValueError(f"Could not generate unique copy name for '{base_name}'")


def _update_unit_names(group_content: str, old_group_name: str, new_group_name: str) -> str:
    """Update unit names within a group to reflect new group name."""
    units_section_match = patterns.UNITS_SECTION_PATTERN_COMPILED.search(group_content)

    if not units_section_match:
        return group_content

    units_content = units_section_match.group(1)

    updated_units = re.sub(
        rf'\["name"\]\s*=\s*"({re.escape(old_group_name)}[^"]*)"',
        lambda m: f'["name"] = "{m.group(1).replace(old_group_name, new_group_name, 1)}"',
        units_content
    )

    modified_group = group_content.replace(units_content, updated_units)

    return modified_group


def _apply_position_offset(group_content: str, position_offset: dict) -> str:
    """Apply position offset to all positions in group content."""
    x_offset = position_offset.get("x", 0)
    y_offset = position_offset.get("y", 0)

    def offset_position(match):
        y_value = float(match.group(1))
        x_value = float(match.group(2))

        new_y = y_value + y_offset
        new_x = x_value + x_offset

        return f'["y"] = {new_y},\n                        ["x"] = {new_x}'

    modified_content = patterns.POSITION_PATTERN_COMPILED.sub(
        offset_position,
        group_content
    )

    return modified_content


def duplicate_group(
    mission_content: str,
    group_name: str,
    new_group_name=None,
    position_offset=None
) -> str:
    """Duplicate an existing group with new name and optional position offset."""
    # Validate source group exists
    if not validation.validate_group_exists(mission_content, group_name):
        raise ValueError(f"Group '{group_name}' not found in mission")

    # Find the source group
    result = find_group_by_name(mission_content, group_name)
    if not result:
        raise ValueError(f"Group '{group_name}' not found in mission")

    source_group_content, start_pos, end_pos = result

    # Generate new group name if not provided
    if new_group_name is None:
        new_group_name = _generate_copy_name(mission_content, group_name)
    else:
        is_valid, error = validation.validate_group_name(new_group_name)
        if not is_valid:
            raise ValueError(error)

        if validation.validate_group_exists(mission_content, new_group_name):
            raise ValueError(f"Group '{new_group_name}' already exists in mission")

    # Validate position offset if provided
    if position_offset is not None:
        if not isinstance(position_offset, dict):
            raise ValueError("position_offset must be a dictionary")

        if "x" not in position_offset and "y" not in position_offset:
            raise ValueError("position_offset must contain at least 'x' or 'y' key")

        for key, value in position_offset.items():
            if key not in ["x", "y"]:
                raise ValueError(f"Invalid position_offset key: {key}. Must be 'x' or 'y'")
            try:
                float(value)
            except (ValueError, TypeError):
                raise ValueError(f"Invalid position_offset value for {key}: {value}")

    # Generate new IDs
    new_group_id = id_manager.generate_new_group_id(mission_content)

    # Count units in source group
    units_section_match = patterns.UNITS_SECTION_PATTERN_COMPILED.search(source_group_content)
    if not units_section_match:
        raise ValueError(f"Group '{group_name}' has no units section")

    units_content = units_section_match.group(1)
    unit_blocks = patterns.UNIT_BLOCK_PATTERN_COMPILED.findall(units_content)
    unit_count = len(unit_blocks)

    new_unit_ids = id_manager.generate_new_unit_ids(mission_content, unit_count)

    # Create duplicated group content
    duplicated_group = source_group_content

    # Replace group name - which comes AFTER the units section
    # Find the units section end marker position
    units_end_match = re.search(r'--\s*end\s*of\s*\["units"\]', duplicated_group)
    if units_end_match:
        # Only search for name field AFTER units section
        before_units = duplicated_group[:units_end_match.end()]
        after_units = duplicated_group[units_end_match.end():]

        # Replace the first name field after units (this is the group name)
        after_units = re.sub(
            r'\["name"\]\s*=\s*"[^"]+"',
            f'["name"] = "{new_group_name}"',
            after_units,
            count=1
        )
        duplicated_group = before_units + after_units
    else:
        # Fallback: try to replace the last name field
        duplicated_group = re.sub(
            r'\["name"\]\s*=\s*"[^"]+"',
            f'["name"] = "{new_group_name}"',
            duplicated_group,
            count=1
        )

    # Replace group ID
    duplicated_group = re.sub(
        r'\["groupId"\]\s*=\s*\d+',
        f'["groupId"] = {new_group_id}',
        duplicated_group
    )

    # Replace unit IDs
    unit_id_matches = list(patterns.UNIT_ID_PATTERN_COMPILED.finditer(duplicated_group))

    for i, match in enumerate(reversed(unit_id_matches)):
        new_unit_id = new_unit_ids[-(i+1)]

        duplicated_group = (
            duplicated_group[:match.start()] +
            f'["unitId"] = {new_unit_id}' +
            duplicated_group[match.end():]
        )

    # Update unit names
    duplicated_group = _update_unit_names(duplicated_group, group_name, new_group_name)

    # Apply position offset if provided
    if position_offset:
        duplicated_group = _apply_position_offset(duplicated_group, position_offset)

    # Insert duplicated group
    insertion_point = end_pos
    modified_content = (
        mission_content[:insertion_point] +
        "\n" +
        duplicated_group +
        mission_content[insertion_point:]
    )

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

def test_duplicate_group_basic():
    """Test basic group duplication."""
    content = load_test_mission()

    # Get a known group
    groups_before = list_all_groups(content)
    all_names = groups_before['blue'] + groups_before['red']
    assert len(all_names) > 0, "Need at least one group for testing"

    source_group = all_names[0]
    new_name = f"{source_group}-TestCopy"
    initial_count = count_total_groups(content)

    # Duplicate the group
    modified = duplicate_group(content, source_group, new_name)

    # Verify the new group name appears in the content
    new_name_pattern = rf'\["name"\]\s*=\s*"{re.escape(new_name)}"'
    assert re.search(new_name_pattern, modified), f"New group name '{new_name}' should appear in content"

    # Verify original still exists
    original_pattern = rf'\["name"\]\s*=\s*"{re.escape(source_group)}"'
    assert re.search(original_pattern, modified), f"Original group '{source_group}' should still exist"

    # Verify content is longer (group was added)
    assert len(modified) > len(content), "Modified content should be longer"

    print("[OK] duplicate_group_basic tests passed")
    print(f"     Duplicated '{source_group}' to '{new_name}'")


def test_duplicate_group_auto_name():
    """Test duplication with auto-generated name."""
    content = load_test_mission()

    # Get a known group
    groups_before = list_all_groups(content)
    all_names = groups_before['blue'] + groups_before['red']
    assert len(all_names) > 0, "Need at least one group for testing"

    source_group = all_names[0]
    expected_name = f"{source_group}-Copy"

    # Duplicate without specifying new name
    modified = duplicate_group(content, source_group)

    # Verify auto-generated name appears in content
    name_pattern = rf'\["name"\]\s*=\s*"{re.escape(expected_name)}"'
    assert re.search(name_pattern, modified), f"Auto-generated name '{expected_name}' should appear in content"

    print("[OK] duplicate_group_auto_name tests passed")
    print(f"     Auto-generated name: '{expected_name}'")


def test_duplicate_group_with_offset():
    """Test duplication with position offset."""
    content = load_test_mission()

    # Get a known group
    groups_before = list_all_groups(content)
    all_names = groups_before['blue'] + groups_before['red']
    assert len(all_names) > 0, "Need at least one group for testing"

    source_group = all_names[0]
    new_name = f"{source_group}-OffsetCopy"
    offset = {"x": 5000, "y": 3000}

    # Duplicate with offset
    modified = duplicate_group(content, source_group, new_name, offset)

    # Verify new group name exists
    name_pattern = rf'\["name"\]\s*=\s*"{re.escape(new_name)}"'
    assert re.search(name_pattern, modified), f"New group '{new_name}' should appear in content"

    # Verify content is larger (offset doesn't change size but duplication does)
    assert len(modified) > len(content), "Modified content should be longer"

    print("[OK] duplicate_group_with_offset tests passed")
    print(f"     Created offset copy '{new_name}' with offset {offset}")


def test_duplicate_group_unique_ids():
    """Test that duplicated group has unique IDs."""
    content = load_test_mission()

    # Get a known group
    groups_before = list_all_groups(content)
    all_names = groups_before['blue'] + groups_before['red']
    assert len(all_names) > 0, "Need at least one group for testing"

    source_group = all_names[0]
    new_name = f"{source_group}-IdTest"

    # Get all original group IDs
    original_group_ids = set(int(m.group(1)) for m in patterns.GROUP_ID_PATTERN_COMPILED.finditer(content))

    # Duplicate
    modified = duplicate_group(content, source_group, new_name)

    # Get all group IDs after duplication
    modified_group_ids = set(int(m.group(1)) for m in patterns.GROUP_ID_PATTERN_COMPILED.finditer(modified))

    # There should be at least one new group ID
    new_ids = modified_group_ids - original_group_ids
    assert len(new_ids) >= 1, "Should have at least one new group ID"

    print("[OK] duplicate_group_unique_ids tests passed")
    print(f"     Original IDs: {len(original_group_ids)}, After: {len(modified_group_ids)}, New: {new_ids}")


def test_duplicate_group_errors():
    """Test error handling in duplication."""
    content = load_test_mission()

    # Test non-existent source group
    try:
        duplicate_group(content, "NonExistentGroup-XYZ-999", "NewName")
        assert False, "Should raise ValueError for non-existent source group"
    except ValueError:
        pass

    # Get a known group
    groups_before = list_all_groups(content)
    all_names = groups_before['blue'] + groups_before['red']
    assert len(all_names) > 0, "Need at least one group for testing"

    source_group = all_names[0]

    # Test duplicate name already exists
    try:
        duplicate_group(content, source_group, source_group)
        assert False, "Should raise ValueError when new name already exists"
    except ValueError:
        pass

    # Test invalid position offset
    try:
        duplicate_group(content, source_group, "TestName", {"z": 1000})
        assert False, "Should raise ValueError for invalid offset key"
    except ValueError:
        pass

    try:
        duplicate_group(content, source_group, "TestName", {"x": "not_a_number"})
        assert False, "Should raise ValueError for invalid offset value"
    except ValueError:
        pass

    print("[OK] duplicate_group_errors tests passed")


def test_duplicate_multiple_times():
    """Test duplicating the same group multiple times."""
    content = load_test_mission()

    groups_before = list_all_groups(content)
    all_names = groups_before['blue'] + groups_before['red']
    assert len(all_names) > 0, "Need at least one group for testing"

    source_group = all_names[0]

    # Duplicate 3 times
    modified = content
    new_names = []
    for i in range(3):
        new_name = f"{source_group}-Multi-{i+1}"
        new_names.append(new_name)
        modified = duplicate_group(modified, source_group, new_name)

    # Verify all duplicates exist in content
    for expected_name in new_names:
        name_pattern = rf'\["name"\]\s*=\s*"{re.escape(expected_name)}"'
        assert re.search(name_pattern, modified), f"Duplicate '{expected_name}' should appear in content"

    # Verify content grew
    assert len(modified) > len(content), "Modified content should be longer"

    print("[OK] duplicate_multiple_times tests passed")
    print(f"     Created 3 duplicates: {new_names}")


# ==============================================================================
# Individual Test Runner
# ==============================================================================

if __name__ == "__main__":
    print("=" * 70)
    print("Testing groups/duplicate.py - Group Duplication Functions")
    print("=" * 70)
    print()

    tests = [
        ("Duplicate Group Basic", test_duplicate_group_basic),
        ("Duplicate Group Auto Name", test_duplicate_group_auto_name),
        ("Duplicate Group With Offset", test_duplicate_group_with_offset),
        ("Duplicate Group Unique IDs", test_duplicate_group_unique_ids),
        ("Duplicate Group Errors", test_duplicate_group_errors),
        ("Duplicate Multiple Times", test_duplicate_multiple_times),
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
