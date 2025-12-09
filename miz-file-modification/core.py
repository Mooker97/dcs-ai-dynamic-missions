"""
Core utilities for DCS mission file modification.

Provides common constants and helper functions used across all modification modules.
"""

import re
from typing import Dict, Optional


# Valid unit types in DCS missions
UNIT_TYPES = ['plane', 'helicopter', 'ship', 'vehicle', 'static']

# Coalition display names
COALITION_NAMES = {
    'blue': 'Blue (Coalition)',
    'red': 'Red (Coalition)',
    'neutrals': 'Neutrals'
}

# Valid coalitions (used for validation and context detection)
COALITIONS = ['blue', 'red', 'neutrals']


def find_context(content: str, position: int, search_back: int = 2500000) -> Dict[str, Optional[str]]:
    r"""
    Find the coalition and unit type context for a position in mission content.

    This function searches backwards from a given position to find the most recent
    coalition marker (["blue"], ["red"], ["neutrals"]) and unit type marker
    (["plane"], ["helicopter"], etc.) to determine what context that position
    belongs to.

    This is essential for determining which coalition and unit type a group/unit
    belongs to when parsing mission files, since groups don't explicitly store
    this information - it's determined by their position in the file structure.

    Args:
        content: Mission file content as string
        position: Position (character index) in content to find context for
        search_back: Maximum number of characters to search backwards (default: 2.5MB)

    Returns:
        Dictionary with 'coalition' and 'unit_type' keys. Values are strings if found,
        None if not found.

    Example:
        >>> content = parser.get_mission_content()
        >>> match = re.search(r'\["name"\]\s*=\s*"Fighter-1"', content)
        >>> context = find_context(content, match.start())
        >>> print(context)
        {'coalition': 'blue', 'unit_type': 'plane'}

    Usage Pattern:
        When you find a group or unit via regex, use find_context() to determine
        which coalition and unit type it belongs to:

        >>> for match in re.finditer(group_pattern, content):
        ...     group_name = match.group(1)
        ...     context = find_context(content, match.start())
        ...     print(f"{group_name}: {context['coalition']} {context['unit_type']}")
    """
    # Search backwards from position
    start = max(0, position - search_back)
    context_section = content[start:position]

    # Find last coalition marker (closest to the position)
    coalition = None
    last_coalition_pos = -1
    for c in COALITIONS:
        pattern = rf'\["{c}"\]\s*='
        matches = list(re.finditer(pattern, context_section))
        if matches:
            last_match_pos = matches[-1].start()
            if last_match_pos > last_coalition_pos:
                last_coalition_pos = last_match_pos
                coalition = c

    # Find last unit type marker (closest to the position)
    unit_type = None
    last_type_pos = -1
    for ut in UNIT_TYPES:
        pattern = rf'\["{ut}"\]\s*='
        matches = list(re.finditer(pattern, context_section))
        if matches:
            last_match_pos = matches[-1].start()
            if last_match_pos > last_type_pos:
                last_type_pos = last_match_pos
                unit_type = ut

    return {'coalition': coalition, 'unit_type': unit_type}


def validate_coalition(coalition: str) -> bool:
    """
    Validate that a coalition name is valid.

    Args:
        coalition: Coalition name to validate

    Returns:
        True if valid, False otherwise

    Example:
        >>> validate_coalition('blue')
        True
        >>> validate_coalition('green')
        False
    """
    return coalition in COALITIONS


def validate_unit_type(unit_type: str) -> bool:
    """
    Validate that a unit type is valid.

    Args:
        unit_type: Unit type to validate

    Returns:
        True if valid, False otherwise

    Example:
        >>> validate_unit_type('plane')
        True
        >>> validate_unit_type('tank')
        False
    """
    return unit_type in UNIT_TYPES


def get_coalition_display_name(coalition: str) -> str:
    """
    Get the display name for a coalition.

    Args:
        coalition: Coalition key ('blue', 'red', 'neutrals')

    Returns:
        Display name for the coalition, or the original key if not found

    Example:
        >>> get_coalition_display_name('blue')
        'Blue (Coalition)'
        >>> get_coalition_display_name('red')
        'Red (Coalition)'
    """
    return COALITION_NAMES.get(coalition, coalition)
