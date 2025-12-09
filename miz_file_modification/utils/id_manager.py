"""
ID management utilities for DCS mission files.

Provides functions to find maximum IDs and generate new unique IDs
for groups and units in .miz mission files.
"""

import re
from typing import List


def find_max_group_id(mission_content: str) -> int:
    """
    Find the maximum group ID in mission content.

    Args:
        mission_content: Raw mission file content as string

    Returns:
        Maximum group ID found, or 0 if no groups exist

    Example:
        >>> content = parser.get_mission_content()
        >>> max_id = find_max_group_id(content)
        >>> print(f"Max group ID: {max_id}")
    """
    group_ids = re.findall(r'\["groupId"\]\s*=\s*(\d+)', mission_content)

    if not group_ids:
        return 0

    return max(int(gid) for gid in group_ids)


def find_max_unit_id(mission_content: str) -> int:
    """
    Find the maximum unit ID in mission content.

    Args:
        mission_content: Raw mission file content as string

    Returns:
        Maximum unit ID found, or 0 if no units exist

    Example:
        >>> content = parser.get_mission_content()
        >>> max_id = find_max_unit_id(content)
        >>> print(f"Max unit ID: {max_id}")
    """
    unit_ids = re.findall(r'\["unitId"\]\s*=\s*(\d+)', mission_content)

    if not unit_ids:
        return 0

    return max(int(uid) for uid in unit_ids)


def find_max_ids(mission_content: str) -> dict:
    """
    Find both maximum group ID and unit ID in mission content.

    Convenience function that finds both max IDs in a single pass.

    Args:
        mission_content: Raw mission file content as string

    Returns:
        Dictionary with 'max_group_id' and 'max_unit_id' keys

    Example:
        >>> content = parser.get_mission_content()
        >>> max_ids = find_max_ids(content)
        >>> print(f"Max group: {max_ids['max_group_id']}, Max unit: {max_ids['max_unit_id']}")
    """
    return {
        'max_group_id': find_max_group_id(mission_content),
        'max_unit_id': find_max_unit_id(mission_content)
    }


def generate_new_group_id(mission_content: str) -> int:
    """
    Generate a new unique group ID.

    Finds the maximum existing group ID and returns max + 1.

    Args:
        mission_content: Raw mission file content as string

    Returns:
        New unique group ID (max_existing_id + 1)

    Example:
        >>> content = parser.get_mission_content()
        >>> new_id = generate_new_group_id(content)
        >>> print(f"New group ID: {new_id}")
    """
    max_id = find_max_group_id(mission_content)
    return max_id + 1


def generate_new_unit_ids(mission_content: str, count: int) -> List[int]:
    """
    Generate multiple new unique unit IDs.

    Finds the maximum existing unit ID and returns a list of sequential
    new IDs starting from max + 1.

    Args:
        mission_content: Raw mission file content as string
        count: Number of new unit IDs to generate

    Returns:
        List of new unique unit IDs

    Raises:
        ValueError: If count is less than 1

    Example:
        >>> content = parser.get_mission_content()
        >>> new_ids = generate_new_unit_ids(content, 4)
        >>> print(f"New unit IDs: {new_ids}")
        [15, 16, 17, 18]
    """
    if count < 1:
        raise ValueError(f"Count must be at least 1, got {count}")

    max_id = find_max_unit_id(mission_content)
    return list(range(max_id + 1, max_id + 1 + count))


def generate_new_unit_id(mission_content: str) -> int:
    """
    Generate a single new unique unit ID.

    Convenience function for generating a single unit ID.

    Args:
        mission_content: Raw mission file content as string

    Returns:
        New unique unit ID (max_existing_id + 1)

    Example:
        >>> content = parser.get_mission_content()
        >>> new_id = generate_new_unit_id(content)
        >>> print(f"New unit ID: {new_id}")
    """
    return generate_new_unit_ids(mission_content, 1)[0]
