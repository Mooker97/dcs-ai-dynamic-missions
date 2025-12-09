"""
Regex patterns for parsing DCS mission files.

This module provides compiled regex patterns used throughout the library
for finding and extracting Lua structures from .miz mission files.
"""

import re

# ============================================================================
# GROUP PATTERNS
# ============================================================================

# Find groups by units section + name (matches group definitions)
# Captures: (units_content, group_name)
GROUP_PATTERN = r'\["units"\]\s*=\s*\{(.*?)\},\s*--\s*end\s*of\s*\["units"\]\s*\n(?:.*?\n){0,5}?\s*\["name"\]\s*=\s*"([^"]+)"'
GROUP_PATTERN_COMPILED = re.compile(GROUP_PATTERN, re.DOTALL)

# Find entire group block (including all properties)
# Captures full group definition from opening [ to closing },
GROUP_BLOCK_PATTERN = r'\[(\d+)\]\s*=\s*\{[^}]*?\["name"\]\s*=\s*"([^"]+)".*?\},(?:\s*--.*?\n)?'
GROUP_BLOCK_PATTERN_COMPILED = re.compile(GROUP_BLOCK_PATTERN, re.DOTALL)

# Find group opening with index
# Captures: (group_index)
GROUP_INDEX_PATTERN = r'\[(\d+)\]\s*='
GROUP_INDEX_PATTERN_COMPILED = re.compile(GROUP_INDEX_PATTERN)

# Find group name field
# Captures: (group_name)
GROUP_NAME_PATTERN = r'\["name"\]\s*=\s*"([^"]+)"'
GROUP_NAME_PATTERN_COMPILED = re.compile(GROUP_NAME_PATTERN)

# ============================================================================
# UNIT PATTERNS
# ============================================================================

# Find units section within a group
# Captures: (units_content)
UNITS_SECTION_PATTERN = r'\["units"\]\s*=\s*\{(.*?)\},\s*--\s*end\s*of\s*\["units"\]'
UNITS_SECTION_PATTERN_COMPILED = re.compile(UNITS_SECTION_PATTERN, re.DOTALL)

# Find individual unit block
# Captures: (unit_index, unit_content)
UNIT_BLOCK_PATTERN = r'\[(\d+)\]\s*=\s*\{(.*?)\},'
UNIT_BLOCK_PATTERN_COMPILED = re.compile(UNIT_BLOCK_PATTERN, re.DOTALL)

# Find unit name field
# Captures: (unit_name)
UNIT_NAME_PATTERN = r'\["name"\]\s*=\s*"([^"]+)"'
UNIT_NAME_PATTERN_COMPILED = re.compile(UNIT_NAME_PATTERN)

# Find unit type field
# Captures: (unit_type)
UNIT_TYPE_PATTERN = r'\["type"\]\s*=\s*"([^"]+)"'
UNIT_TYPE_PATTERN_COMPILED = re.compile(UNIT_TYPE_PATTERN)

# ============================================================================
# WAYPOINT PATTERNS
# ============================================================================

# Find route section within a group
# Captures: (route_content)
ROUTE_SECTION_PATTERN = r'\["route"\]\s*=\s*\{(.*?)\},\s*--\s*end\s*of\s*\["route"\]'
ROUTE_SECTION_PATTERN_COMPILED = re.compile(ROUTE_SECTION_PATTERN, re.DOTALL)

# Find points section within a route
# Captures: (points_content)
POINTS_SECTION_PATTERN = r'\["points"\]\s*=\s*\{(.*?)\},\s*--\s*end\s*of\s*\["points"\]'
POINTS_SECTION_PATTERN_COMPILED = re.compile(POINTS_SECTION_PATTERN, re.DOTALL)

# Find individual waypoint block
# Captures: (waypoint_index, waypoint_content)
WAYPOINT_BLOCK_PATTERN = r'\[(\d+)\]\s*=\s*\{(.*?)\},'
WAYPOINT_BLOCK_PATTERN_COMPILED = re.compile(WAYPOINT_BLOCK_PATTERN, re.DOTALL)

# Find waypoint action field
# Captures: (action)
WAYPOINT_ACTION_PATTERN = r'\["action"\]\s*=\s*"([^"]+)"'
WAYPOINT_ACTION_PATTERN_COMPILED = re.compile(WAYPOINT_ACTION_PATTERN)

# ============================================================================
# COORDINATE PATTERNS
# ============================================================================

# Find x,y position (matches both in groups and waypoints)
# Captures: (x, y)
POSITION_PATTERN = r'\["x"\]\s*=\s*([+-]?\d+\.?\d*),\s*\["y"\]\s*=\s*([+-]?\d+\.?\d*)'
POSITION_PATTERN_COMPILED = re.compile(POSITION_PATTERN)

# Find x coordinate only
# Captures: (x)
X_COORD_PATTERN = r'\["x"\]\s*=\s*([+-]?\d+\.?\d*)'
X_COORD_PATTERN_COMPILED = re.compile(X_COORD_PATTERN)

# Find y coordinate only
# Captures: (y)
Y_COORD_PATTERN = r'\["y"\]\s*=\s*([+-]?\d+\.?\d*)'
Y_COORD_PATTERN_COMPILED = re.compile(Y_COORD_PATTERN)

# Find altitude field
# Captures: (alt)
ALT_PATTERN = r'\["alt"\]\s*=\s*([+-]?\d+\.?\d*)'
ALT_PATTERN_COMPILED = re.compile(ALT_PATTERN)

# Find heading field
# Captures: (heading)
HEADING_PATTERN = r'\["heading"\]\s*=\s*([+-]?\d+\.?\d*)'
HEADING_PATTERN_COMPILED = re.compile(HEADING_PATTERN)

# ============================================================================
# ID PATTERNS
# ============================================================================

# Find group ID field
# Captures: (group_id)
GROUP_ID_PATTERN = r'\["groupId"\]\s*=\s*(\d+)'
GROUP_ID_PATTERN_COMPILED = re.compile(GROUP_ID_PATTERN)

# Find unit ID field
# Captures: (unit_id)
UNIT_ID_PATTERN = r'\["unitId"\]\s*=\s*(\d+)'
UNIT_ID_PATTERN_COMPILED = re.compile(UNIT_ID_PATTERN)

# Find trigger ID field (for future triggers module)
# Captures: (trigger_id)
TRIGGER_ID_PATTERN = r'\["id"\]\s*=\s*(\d+)'
TRIGGER_ID_PATTERN_COMPILED = re.compile(TRIGGER_ID_PATTERN)

# ============================================================================
# COALITION AND UNIT TYPE PATTERNS
# ============================================================================

# Find coalition sections
# Captures: (coalition_name)
COALITION_PATTERN = r'\["(blue|red|neutrals)"\]\s*='
COALITION_PATTERN_COMPILED = re.compile(COALITION_PATTERN)

# Find unit type category sections
# Captures: (unit_type_category)
UNIT_TYPE_CATEGORY_PATTERN = r'\["(plane|helicopter|ship|vehicle|static)"\]\s*='
UNIT_TYPE_CATEGORY_PATTERN_COMPILED = re.compile(UNIT_TYPE_CATEGORY_PATTERN)

# Find specific coalition section with full content
# Use with .format(coalition_name) to get specific coalition
# Example: COALITION_SECTION_PATTERN.format('blue')
COALITION_SECTION_TEMPLATE = r'\["{0}"\]\s*=\s*\{{(.*?)\}},\s*--\s*end\s*of\s*\["{0}"\]'

# Find specific unit type section with full content
# Use with .format(unit_type) to get specific type
# Example: UNIT_TYPE_SECTION_TEMPLATE.format('plane')
UNIT_TYPE_SECTION_TEMPLATE = r'\["{0}"\]\s*=\s*\{{(.*?)\}},\s*--\s*end\s*of\s*\["{0}"\]'

# ============================================================================
# PROPERTY PATTERNS
# ============================================================================

# Find skill field
# Captures: (skill)
SKILL_PATTERN = r'\["skill"\]\s*=\s*"([^"]+)"'
SKILL_PATTERN_COMPILED = re.compile(SKILL_PATTERN)

# Find speed field
# Captures: (speed)
SPEED_PATTERN = r'\["speed"\]\s*=\s*([+-]?\d+\.?\d*)'
SPEED_PATTERN_COMPILED = re.compile(SPEED_PATTERN)

# Find task field
# Captures: (task)
TASK_PATTERN = r'\["task"\]\s*=\s*"([^"]+)"'
TASK_PATTERN_COMPILED = re.compile(TASK_PATTERN)

# Find frequency field (for ships/radios)
# Captures: (frequency)
FREQUENCY_PATTERN = r'\["frequency"\]\s*=\s*(\d+)'
FREQUENCY_PATTERN_COMPILED = re.compile(FREQUENCY_PATTERN)

# Find modulation field (for ships/radios)
# Captures: (modulation)
MODULATION_PATTERN = r'\["modulation"\]\s*=\s*(\d+)'
MODULATION_PATTERN_COMPILED = re.compile(MODULATION_PATTERN)

# Find start_time field
# Captures: (start_time)
START_TIME_PATTERN = r'\["start_time"\]\s*=\s*([+-]?\d+\.?\d*)'
START_TIME_PATTERN_COMPILED = re.compile(START_TIME_PATTERN)

# Find visible field
# Captures: (visible - true/false)
VISIBLE_PATTERN = r'\["visible"\]\s*=\s*(true|false)'
VISIBLE_PATTERN_COMPILED = re.compile(VISIBLE_PATTERN)

# Find uncontrolled field
# Captures: (uncontrolled - true/false)
UNCONTROLLED_PATTERN = r'\["uncontrolled"\]\s*=\s*(true|false)'
UNCONTROLLED_PATTERN_COMPILED = re.compile(UNCONTROLLED_PATTERN)

# Find hidden field
# Captures: (hidden - true/false)
HIDDEN_PATTERN = r'\["hidden"\]\s*=\s*(true|false)'
HIDDEN_PATTERN_COMPILED = re.compile(HIDDEN_PATTERN)

# ============================================================================
# COUNTRY PATTERNS
# ============================================================================

# Find country section
# Captures: (country_index, country_content)
COUNTRY_SECTION_PATTERN = r'\[(\d+)\]\s*=\s*\{(.*?)\},'
COUNTRY_SECTION_PATTERN_COMPILED = re.compile(COUNTRY_SECTION_PATTERN, re.DOTALL)

# Find country ID field
# Captures: (country_id)
COUNTRY_ID_PATTERN = r'\["id"\]\s*=\s*(\d+)'
COUNTRY_ID_PATTERN_COMPILED = re.compile(COUNTRY_ID_PATTERN)

# Find country name field
# Captures: (country_name)
COUNTRY_NAME_PATTERN = r'\["name"\]\s*=\s*"([^"]+)"'
COUNTRY_NAME_PATTERN_COMPILED = re.compile(COUNTRY_NAME_PATTERN)

# ============================================================================
# UTILITY FUNCTIONS
# ============================================================================

def get_coalition_section_pattern(coalition: str) -> re.Pattern:
    """
    Get compiled pattern for specific coalition section.

    Args:
        coalition: Coalition name ('blue', 'red', or 'neutrals')

    Returns:
        Compiled regex pattern

    Example:
        pattern = get_coalition_section_pattern('blue')
        match = pattern.search(mission_content)
        blue_content = match.group(1)
    """
    pattern = COALITION_SECTION_TEMPLATE.format(coalition)
    return re.compile(pattern, re.DOTALL)


def get_unit_type_section_pattern(unit_type: str) -> re.Pattern:
    """
    Get compiled pattern for specific unit type section.

    Args:
        unit_type: Unit type category ('plane', 'helicopter', 'ship', 'vehicle', 'static')

    Returns:
        Compiled regex pattern

    Example:
        pattern = get_unit_type_section_pattern('plane')
        match = pattern.search(coalition_content)
        plane_content = match.group(1)
    """
    pattern = UNIT_TYPE_SECTION_TEMPLATE.format(unit_type)
    return re.compile(pattern, re.DOTALL)


def extract_field(content: str, field_name: str, field_type=str):
    """
    Extract a single field value from Lua content.

    Args:
        content: Lua content string to search
        field_name: Name of the field to extract
        field_type: Type to convert to (str, int, float, bool)

    Returns:
        Extracted value or None if not found

    Example:
        x = extract_field(group_content, 'x', float)
        name = extract_field(group_content, 'name', str)
        visible = extract_field(group_content, 'visible', bool)
    """
    if field_type == str:
        pattern = rf'\["{field_name}"\]\s*=\s*"([^"]+)"'
    elif field_type == bool:
        pattern = rf'\["{field_name}"\]\s*=\s*(true|false)'
    else:
        pattern = rf'\["{field_name}"\]\s*=\s*([+-]?\d+\.?\d*)'

    match = re.search(pattern, content)
    if not match:
        return None

    value = match.group(1)

    if field_type == bool:
        return value == 'true'
    elif field_type in (int, float):
        return field_type(value)
    else:
        return value


# ============================================================================
# CONSTANTS
# ============================================================================

# Valid coalition names
COALITIONS = ['blue', 'red', 'neutrals']

# Valid unit type categories
UNIT_TYPE_CATEGORIES = ['plane', 'helicopter', 'ship', 'vehicle', 'static']

# Valid skill levels
SKILL_LEVELS = ['Rookie', 'Trained', 'Average', 'Good', 'High', 'Excellent', 'Random', 'Player']

# Valid waypoint actions
WAYPOINT_ACTIONS = [
    'Turning Point',
    'Fly Over Point',
    'From Parking Area',
    'From Parking Area Hot',
    'From Ground Area',
    'From Ground Area Hot',
    'Takeoff',
    'Land',
    'Refueling'
]

# Valid altitude types
ALT_TYPES = ['BARO', 'RADIO']
