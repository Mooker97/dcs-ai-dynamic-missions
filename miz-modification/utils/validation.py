"""
Validation functions for .miz file modifications.

Validates parameters before applying modifications to prevent errors and
ensure data integrity.
"""

import re
from typing import Dict, Union, List, Optional

from . import patterns


# ============================================================================
# COORDINATE VALIDATION
# ============================================================================

def validate_position(position: Dict[str, float], require_altitude: bool = False) -> tuple:
    """
    Validate position dictionary has required coordinates.

    Args:
        position: Dict with 'x', 'y', and optionally 'alt', 'heading'
        require_altitude: Whether altitude is required

    Returns:
        Tuple of (is_valid: bool, error_message: str or None)

    Example:
        valid, error = validate_position({'x': 1000, 'y': 2000})
        if not valid:
            raise ValueError(error)
    """
    if not isinstance(position, dict):
        return False, "Position must be a dictionary"

    # Check required keys
    if 'x' not in position:
        return False, "Position missing required key 'x'"
    if 'y' not in position:
        return False, "Position missing required key 'y'"

    # Validate x coordinate
    try:
        x = float(position['x'])
    except (ValueError, TypeError):
        return False, f"Invalid x coordinate: {position['x']}"

    # Validate y coordinate
    try:
        y = float(position['y'])
    except (ValueError, TypeError):
        return False, f"Invalid y coordinate: {position['y']}"

    # Check coordinate bounds (DCS maps typically within ±500km)
    if not (-500000 <= x <= 500000):
        return False, f"X coordinate out of typical bounds: {x} (expected -500000 to 500000)"
    if not (-500000 <= y <= 500000):
        return False, f"Y coordinate out of typical bounds: {y} (expected -500000 to 500000)"

    # Validate altitude if present or required
    if 'alt' in position or require_altitude:
        if 'alt' not in position and require_altitude:
            return False, "Altitude required but not provided"

        try:
            alt = float(position['alt'])
        except (ValueError, TypeError):
            return False, f"Invalid altitude: {position.get('alt')}"

        # Check altitude bounds (0 to 25000m typical for DCS)
        if not (0 <= alt <= 25000):
            return False, f"Altitude out of typical bounds: {alt} (expected 0 to 25000)"

    # Validate heading if present
    if 'heading' in position:
        try:
            heading = float(position['heading'])
        except (ValueError, TypeError):
            return False, f"Invalid heading: {position['heading']}"

        # Heading should be in radians (0 to 2π) or degrees (0 to 360)
        # Accept both ranges for flexibility
        if not (-360 <= heading <= 360 or 0 <= heading <= 6.28319):
            return False, f"Heading out of typical bounds: {heading}"

    return True, None


def validate_coordinates(x: float, y: float) -> tuple:
    """
    Validate x,y coordinates are within reasonable bounds.

    Args:
        x: X coordinate (meters)
        y: Y coordinate (meters)

    Returns:
        Tuple of (is_valid: bool, error_message: str or None)
    """
    return validate_position({'x': x, 'y': y})


# ============================================================================
# GROUP VALIDATION
# ============================================================================

def validate_group_name(group_name: str) -> tuple:
    """
    Validate group name is acceptable for Lua.

    Args:
        group_name: Group name to validate

    Returns:
        Tuple of (is_valid: bool, error_message: str or None)

    Rules:
        - Not empty
        - Not too long (max 255 chars)
        - No quotes (would break Lua string)
        - No newlines (would break Lua formatting)
    """
    if not group_name:
        return False, "Group name cannot be empty"

    if not isinstance(group_name, str):
        return False, "Group name must be a string"

    if len(group_name) > 255:
        return False, f"Group name too long: {len(group_name)} chars (max 255)"

    # Check for problematic characters
    if '"' in group_name or "'" in group_name:
        return False, "Group name cannot contain quotes"

    if '\n' in group_name or '\r' in group_name:
        return False, "Group name cannot contain newlines"

    # Check for Lua reserved keywords (basic check)
    lua_keywords = ['and', 'break', 'do', 'else', 'elseif', 'end', 'false',
                    'for', 'function', 'if', 'in', 'local', 'nil', 'not',
                    'or', 'repeat', 'return', 'then', 'true', 'until', 'while']

    if group_name.lower() in lua_keywords:
        return False, f"Group name cannot be Lua keyword: {group_name}"

    return True, None


def validate_group_exists(mission_content: str, group_name: str) -> bool:
    """
    Check if a group with given name exists in mission.

    Args:
        mission_content: Raw mission file content
        group_name: Name of group to find

    Returns:
        True if group exists, False otherwise

    Example:
        if not validate_group_exists(content, "Fighter-1"):
            raise ValueError("Group 'Fighter-1' not found")
    """
    # Use GROUP_NAME_PATTERN to find all group names
    matches = patterns.GROUP_NAME_PATTERN_COMPILED.findall(mission_content)

    return group_name in matches


# ============================================================================
# UNIT TYPE VALIDATION
# ============================================================================

def validate_unit_type_category(category: str) -> tuple:
    """
    Validate unit type category is valid.

    Args:
        category: Unit type category (plane, helicopter, ship, vehicle, static)

    Returns:
        Tuple of (is_valid: bool, error_message: str or None)
    """
    if category not in patterns.UNIT_TYPE_CATEGORIES:
        return False, f"Invalid unit type category: {category}. Must be one of {patterns.UNIT_TYPE_CATEGORIES}"

    return True, None


def validate_coalition(coalition: str) -> tuple:
    """
    Validate coalition name is valid.

    Args:
        coalition: Coalition name (blue, red, neutrals)

    Returns:
        Tuple of (is_valid: bool, error_message: str or None)
    """
    if coalition not in patterns.COALITIONS:
        return False, f"Invalid coalition: {coalition}. Must be one of {patterns.COALITIONS}"

    return True, None


# ============================================================================
# PROPERTY VALIDATION
# ============================================================================

def validate_skill_level(skill: str) -> tuple:
    """
    Validate skill level is valid.

    Args:
        skill: Skill level (Rookie, Trained, Average, Good, High, Excellent, Random, Player)

    Returns:
        Tuple of (is_valid: bool, error_message: str or None)
    """
    if skill not in patterns.SKILL_LEVELS:
        return False, f"Invalid skill level: {skill}. Must be one of {patterns.SKILL_LEVELS}"

    return True, None


def validate_waypoint_action(action: str) -> tuple:
    """
    Validate waypoint action is valid.

    Args:
        action: Waypoint action type

    Returns:
        Tuple of (is_valid: bool, error_message: str or None)
    """
    if action not in patterns.WAYPOINT_ACTIONS:
        return False, f"Invalid waypoint action: {action}. Must be one of {patterns.WAYPOINT_ACTIONS}"

    return True, None


def validate_altitude_type(alt_type: str) -> tuple:
    """
    Validate altitude type is valid.

    Args:
        alt_type: Altitude type (BARO, RADIO)

    Returns:
        Tuple of (is_valid: bool, error_message: str or None)
    """
    if alt_type not in patterns.ALT_TYPES:
        return False, f"Invalid altitude type: {alt_type}. Must be one of {patterns.ALT_TYPES}"

    return True, None


# ============================================================================
# ID VALIDATION
# ============================================================================

def validate_id(id_value: Union[int, str], id_type: str = "generic") -> tuple:
    """
    Validate ID is positive integer.

    Args:
        id_value: ID value to validate
        id_type: Type of ID for error message (e.g., "group", "unit")

    Returns:
        Tuple of (is_valid: bool, error_message: str or None)
    """
    try:
        id_int = int(id_value)
    except (ValueError, TypeError):
        return False, f"Invalid {id_type} ID: {id_value} (must be integer)"

    if id_int < 1:
        return False, f"{id_type.capitalize()} ID must be positive: {id_int}"

    return True, None


# ============================================================================
# BATCH VALIDATION
# ============================================================================

def validate_add_group_params(group_name: str, unit_type_category: str,
                              coalition: str, position: Dict[str, float],
                              skill: Optional[str] = None) -> tuple:
    """
    Validate all parameters for adding a group.

    This is a convenience function that runs multiple validations.

    Args:
        group_name: Name of the group
        unit_type_category: Category (plane, helicopter, ship, vehicle, static)
        coalition: Coalition (blue, red, neutrals)
        position: Position dict with x, y, optionally alt
        skill: Optional skill level

    Returns:
        Tuple of (is_valid: bool, error_message: str or None)

    Example:
        valid, error = validate_add_group_params(
            "Fighter-1", "plane", "blue", {"x": 1000, "y": 2000}, "Average"
        )
        if not valid:
            raise ValueError(f"Invalid parameters: {error}")
    """
    # Validate group name
    valid, error = validate_group_name(group_name)
    if not valid:
        return False, error

    # Validate unit type category
    valid, error = validate_unit_type_category(unit_type_category)
    if not valid:
        return False, error

    # Validate coalition
    valid, error = validate_coalition(coalition)
    if not valid:
        return False, error

    # Validate position (with altitude for aircraft)
    require_alt = unit_type_category in ['plane', 'helicopter']
    valid, error = validate_position(position, require_altitude=require_alt)
    if not valid:
        return False, error

    # Validate skill if provided
    if skill is not None:
        valid, error = validate_skill_level(skill)
        if not valid:
            return False, error

    return True, None


def validate_modify_group_params(mission_content: str, group_name: str,
                                 new_position: Optional[Dict[str, float]] = None,
                                 new_name: Optional[str] = None) -> tuple:
    """
    Validate parameters for modifying a group.

    Args:
        mission_content: Raw mission content to check group existence
        group_name: Current name of the group
        new_position: Optional new position
        new_name: Optional new name

    Returns:
        Tuple of (is_valid: bool, error_message: str or None)
    """
    # Check group exists
    if not validate_group_exists(mission_content, group_name):
        return False, f"Group '{group_name}' not found in mission"

    # Validate new position if provided
    if new_position is not None:
        valid, error = validate_position(new_position)
        if not valid:
            return False, error

    # Validate new name if provided
    if new_name is not None:
        valid, error = validate_group_name(new_name)
        if not valid:
            return False, error

    return True, None


# ============================================================================
# UTILITY FUNCTIONS
# ============================================================================

def get_validation_errors(validations: List[tuple]) -> List[str]:
    """
    Collect all error messages from multiple validations.

    Args:
        validations: List of (is_valid, error_message) tuples

    Returns:
        List of error messages (empty if all valid)

    Example:
        validations = [
            validate_coalition("blue"),
            validate_position({"x": 1000, "y": 2000}),
            validate_skill_level("Average")
        ]
        errors = get_validation_errors(validations)
        if errors:
            raise ValueError("\\n".join(errors))
    """
    errors = []
    for is_valid, error_msg in validations:
        if not is_valid:
            errors.append(error_msg)
    return errors


def raise_if_invalid(is_valid: bool, error_message: Optional[str]):
    """
    Raise ValueError if validation failed.

    Args:
        is_valid: Validation result
        error_message: Error message to raise

    Raises:
        ValueError: If is_valid is False

    Example:
        raise_if_invalid(*validate_coalition("blue"))
    """
    if not is_valid:
        raise ValueError(error_message)
