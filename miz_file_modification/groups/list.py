"""
Group listing and inspection functions for .miz files.

Read-only functions for finding, counting, and inspecting groups in missions.
"""

import re
from typing import Dict, List, Tuple, Optional

from ..utils import patterns, validation


# ============================================================================
# CORE INSPECTION FUNCTIONS
# ============================================================================

def _find_coalition_boundaries(mission_content: str) -> Dict[str, Tuple[int, int]]:
    """
    Find the start and end positions of each coalition section.

    Uses proper brace counting to handle nested structures.

    Returns:
        Dict mapping coalition names to (start, end) position tuples
    """
    boundaries = {}

    # Find the main coalition section: ["coalition"] = {
    coalition_section = re.search(r'\["coalition"\]\s*=\s*\{', mission_content)
    if not coalition_section:
        return boundaries

    # Find all coalition markers within the mission
    # Look for ["red"] = {, ["blue"] = {, etc. that come after ["coalition"]
    for coalition in patterns.COALITIONS:
        # Find all occurrences of this coalition marker
        pattern = rf'\["{coalition}"\]\s*=\s*\{{'
        for match in re.finditer(pattern, mission_content):
            pos = match.start()
            # Check if this is within the main coalition section (has bullseye)
            # by looking at nearby content
            context = mission_content[match.end():match.end()+200]
            if '["bullseye"]' in context or '["country"]' in context:
                # This is the main coalition section
                start = match.end()

                # Count braces to find the end
                depth = 1
                end = start
                while depth > 0 and end < len(mission_content):
                    if mission_content[end] == '{':
                        depth += 1
                    elif mission_content[end] == '}':
                        depth -= 1
                    end += 1

                boundaries[coalition] = (start, end - 1)
                break

    return boundaries


def list_all_groups(mission_content: str) -> Dict[str, List[Dict]]:
    """
    List all groups in mission by coalition.

    Args:
        mission_content: Raw mission file content as string

    Returns:
        Dict with coalition names as keys and lists of group info dicts as values:
        {"blue": [{"name": "Group1", "category": "plane", "units": [...]}, ...],
         "red": [...], "neutrals": [...]}

    Example:
        >>> content = parser.get_mission_content()
        >>> groups = list_all_groups(content)
        >>> print(f"Blue groups: {len(groups['blue'])}")
        >>> print(f"Total groups: {sum(len(g) for g in groups.values())}")
    """
    result = {"blue": [], "red": [], "neutrals": []}

    # Find coalition section boundaries
    boundaries = _find_coalition_boundaries(mission_content)

    for coalition in patterns.COALITIONS:
        if coalition not in boundaries:
            continue

        start, end = boundaries[coalition]
        coalition_content = mission_content[start:end]

        # Pattern to find groups: matches units section followed by name
        # Groups have: ["units"] = { ... }, -- end of ["units"] ... ["name"] = "GroupName"
        group_pattern = re.compile(
            r'\["units"\]\s*=\s*\{(.+?)\},\s*--\s*end of \["units"\].+?\["name"\]\s*=\s*"([^"]+)"',
            re.DOTALL
        )

        for match in group_pattern.finditer(coalition_content):
            units_content = match.group(1)
            group_name = match.group(2)

            # Extract unit types from units content
            unit_types = re.findall(r'\["type"\]\s*=\s*"([^"]+)"', units_content)

            # Determine category by looking backwards for category marker
            pos_in_content = match.start()
            search_back = coalition_content[max(0, pos_in_content-20000):pos_in_content]

            category = "vehicle"  # Default for ground units
            best_idx = -1
            for cat in ['vehicle', 'helicopter', 'plane', 'ship', 'static']:
                cat_marker = f'["{cat}"]'
                idx = search_back.rfind(cat_marker)
                if idx > best_idx:
                    best_idx = idx
                    category = cat

            result[coalition].append({
                'name': group_name,
                'category': category,
                'units': unit_types
            })

    return result


def find_group_by_name(mission_content: str, group_name: str) -> Optional[Tuple[str, int, int]]:
    """
    Find group by name and return its content and position.

    Uses brace counting to find correct group boundaries, handling nested
    structures properly.

    Args:
        mission_content: Raw mission file content as string
        group_name: Name of the group to find

    Returns:
        Tuple of (group_content, start_pos, end_pos) if found, None if not found
        - group_content: Full group definition as string (with balanced braces)
        - start_pos: Character position where group starts
        - end_pos: Character position where group ends

    Example:
        >>> result = find_group_by_name(content, "Fighter-1")
        >>> if result:
        >>>     group_content, start, end = result
        >>>     print(f"Found at position {start}")
    """
    # Find the group name in content
    name_pattern = rf'\["name"\]\s*=\s*"{re.escape(group_name)}"'
    name_match = re.search(name_pattern, mission_content)
    if not name_match:
        return None

    name_pos = name_match.start()

    # Find ["group"] section before this name
    group_section = re.search(r'\["group"\]\s*=\s*\{', mission_content[:name_pos])
    if not group_section:
        return None

    # Find [n] = { entries between group section and name
    between = mission_content[group_section.end():name_pos]
    entries = list(re.finditer(r'\[(\d+)\]\s*=\s*\{', between))
    if not entries:
        return None

    # First entry is the group containing this name
    group_start = group_section.end() + entries[0].start()

    # Find opening brace
    open_brace = mission_content.index('{', group_start)

    # Count braces to find matching close
    depth = 0
    for i in range(open_brace, len(mission_content)):
        if mission_content[i] == '{':
            depth += 1
        elif mission_content[i] == '}':
            depth -= 1
            if depth == 0:
                # Include end marker if present
                end_marker = re.match(r'\},\s*--[^\n]*', mission_content[i:])
                group_end = i + (end_marker.end() if end_marker else 1)
                return (mission_content[group_start:group_end], group_start, group_end)

    return None


def count_groups(mission_content: str, unit_type: Optional[str] = None) -> int:
    """
    Count total groups or groups of specific unit type.

    Args:
        mission_content: Raw mission file content as string
        unit_type: Optional unit type to filter by (plane, helicopter, ship, vehicle, static)
                   If None, counts all groups

    Returns:
        Number of groups found

    Raises:
        ValueError: If unit_type is provided but invalid

    Example:
        >>> total = count_groups(content)
        >>> print(f"Total groups: {total}")
        >>>
        >>> planes = count_groups(content, "plane")
        >>> print(f"Aircraft groups: {planes}")
    """
    if unit_type is not None:
        # Validate unit type
        is_valid, error = validation.validate_unit_type_category(unit_type)
        if not is_valid:
            raise ValueError(error)

        # Count groups in specific unit type section
        count = 0
        for coalition in patterns.COALITIONS:
            coalition_pattern = patterns.get_coalition_section_pattern(coalition)
            coalition_match = coalition_pattern.search(mission_content)

            if not coalition_match:
                continue

            coalition_content = coalition_match.group(1)

            # Get unit type section
            unit_type_pattern = patterns.get_unit_type_section_pattern(unit_type)
            unit_type_match = unit_type_pattern.search(coalition_content)

            if not unit_type_match:
                continue

            unit_type_content = unit_type_match.group(1)

            # Count groups in this section
            group_names = patterns.GROUP_NAME_PATTERN_COMPILED.findall(unit_type_content)
            count += len(group_names)

        return count
    else:
        # Count all groups
        all_names = patterns.GROUP_NAME_PATTERN_COMPILED.findall(mission_content)
        return len(all_names)


def get_group_info(mission_content: str, group_name: str) -> Dict:
    """
    Get detailed information about a specific group.

    Args:
        mission_content: Raw mission file content as string
        group_name: Name of the group to inspect

    Returns:
        Dictionary with group information:
        {
            "name": str,
            "groupId": int,
            "unit_count": int,
            "units": List[Dict],  # List of unit info dicts
            "position": {"x": float, "y": float},
            "exists": bool
        }

    Raises:
        ValueError: If group not found in mission

    Example:
        >>> info = get_group_info(content, "Fighter-1")
        >>> print(f"Group has {info['unit_count']} units")
        >>> print(f"Position: {info['position']}")
        >>> for unit in info['units']:
        >>>     print(f"  - {unit['name']} ({unit['type']})")
    """
    # Find the group
    result = find_group_by_name(mission_content, group_name)

    if not result:
        raise ValueError(f"Group '{group_name}' not found in mission")

    group_content, _, _ = result

    # Extract group information
    info = {
        "name": group_name,
        "exists": True
    }

    # Extract group ID
    group_id_match = patterns.GROUP_ID_PATTERN_COMPILED.search(group_content)
    if group_id_match:
        info["groupId"] = int(group_id_match.group(1))

    # Extract position (first unit's position typically)
    pos_match = patterns.POSITION_PATTERN_COMPILED.search(group_content)
    if pos_match:
        info["position"] = {
            "y": float(pos_match.group(1)),  # Note: DCS uses y, x order
            "x": float(pos_match.group(2))
        }

    # Extract units section
    units_match = patterns.UNITS_SECTION_PATTERN_COMPILED.search(group_content)
    if units_match:
        units_content = units_match.group(1)

        # Find all unit blocks
        unit_blocks = patterns.UNIT_BLOCK_PATTERN_COMPILED.findall(units_content)

        units = []
        for unit_index, unit_content in unit_blocks:
            unit_info = {"index": int(unit_index)}

            # Extract unit name
            name_match = patterns.UNIT_NAME_PATTERN_COMPILED.search(unit_content)
            if name_match:
                unit_info["name"] = name_match.group(1)

            # Extract unit type
            type_match = patterns.UNIT_TYPE_PATTERN_COMPILED.search(unit_content)
            if type_match:
                unit_info["type"] = type_match.group(1)

            # Extract unit ID
            unit_id_match = patterns.UNIT_ID_PATTERN_COMPILED.search(unit_content)
            if unit_id_match:
                unit_info["unitId"] = int(unit_id_match.group(1))

            # Extract skill
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


# ============================================================================
# CONVENIENCE WRAPPER FUNCTIONS
# ============================================================================

def list_all_groups_file(input_miz: str) -> Dict[str, List[str]]:
    """
    List all groups from a .miz file (convenience wrapper).

    Args:
        input_miz: Path to input .miz file

    Returns:
        Dict with coalition names as keys and lists of group names as values

    Raises:
        FileNotFoundError: If input_miz doesn't exist

    Example:
        >>> groups = list_all_groups_file("../miz-files/input/mission.miz")
        >>> print(f"Blue: {len(groups['blue'])} groups")
        >>> print(f"Red: {len(groups['red'])} groups")
    """
    from pathlib import Path
    from ..parsing.miz_parser import MizParser

    if not Path(input_miz).exists():
        raise FileNotFoundError(f"Input .miz file not found: {input_miz}")

    parser = MizParser(input_miz)
    parser.extract()

    try:
        content = parser.get_mission_content()
        result = list_all_groups(content)
        return result
    finally:
        parser.cleanup()


def get_group_info_file(input_miz: str, group_name: str) -> Dict:
    """
    Get group information from a .miz file (convenience wrapper).

    Args:
        input_miz: Path to input .miz file
        group_name: Name of the group to inspect

    Returns:
        Dictionary with group information

    Raises:
        FileNotFoundError: If input_miz doesn't exist
        ValueError: If group not found in mission

    Example:
        >>> info = get_group_info_file("mission.miz", "Fighter-1")
        >>> print(f"Group has {info['unit_count']} units")
    """
    from pathlib import Path
    from ..parsing.miz_parser import MizParser

    if not Path(input_miz).exists():
        raise FileNotFoundError(f"Input .miz file not found: {input_miz}")

    parser = MizParser(input_miz)
    parser.extract()

    try:
        content = parser.get_mission_content()
        result = get_group_info(content, group_name)
        return result
    finally:
        parser.cleanup()


# ============================================================================
# UTILITY FUNCTIONS
# ============================================================================

def get_groups_by_coalition(mission_content: str, coalition: str) -> List[str]:
    """
    Get all groups for a specific coalition.

    Args:
        mission_content: Raw mission file content as string
        coalition: Coalition name (blue, red, neutrals)

    Returns:
        List of group names in the coalition

    Raises:
        ValueError: If coalition name is invalid

    Example:
        >>> blue_groups = get_groups_by_coalition(content, "blue")
        >>> for group in blue_groups:
        >>>     print(f"Blue group: {group}")
    """
    is_valid, error = validation.validate_coalition(coalition)
    if not is_valid:
        raise ValueError(error)

    all_groups = list_all_groups(mission_content)
    return all_groups[coalition]


def get_groups_by_type(mission_content: str, unit_type: str) -> List[str]:
    """
    Get all groups of a specific unit type.

    Args:
        mission_content: Raw mission file content as string
        unit_type: Unit type category (plane, helicopter, ship, vehicle, static)

    Returns:
        List of group names of that type

    Raises:
        ValueError: If unit_type is invalid

    Example:
        >>> aircraft = get_groups_by_type(content, "plane")
        >>> print(f"Found {len(aircraft)} aircraft groups")
    """
    is_valid, error = validation.validate_unit_type_category(unit_type)
    if not is_valid:
        raise ValueError(error)

    groups = []

    for coalition in patterns.COALITIONS:
        coalition_pattern = patterns.get_coalition_section_pattern(coalition)
        coalition_match = coalition_pattern.search(mission_content)

        if not coalition_match:
            continue

        coalition_content = coalition_match.group(1)

        # Get unit type section
        unit_type_pattern = patterns.get_unit_type_section_pattern(unit_type)
        unit_type_match = unit_type_pattern.search(coalition_content)

        if not unit_type_match:
            continue

        unit_type_content = unit_type_match.group(1)

        # Find all group names in this section
        group_names = patterns.GROUP_NAME_PATTERN_COMPILED.findall(unit_type_content)
        groups.extend(group_names)

    return groups
