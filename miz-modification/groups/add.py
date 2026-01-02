"""
Group addition functions for .miz files.

Functions for adding new groups to missions with proper ID management.
"""

import re
import math
from typing import Dict, Optional, List

from ..utils import patterns, validation, id_manager
from .list import find_group_by_name


# ============================================================================
# UNIT TYPE TEMPLATES
# ============================================================================

# Default values for different unit type categories
UNIT_TYPE_DEFAULTS = {
    'plane': {
        'skill': 'Average',
        'speed': 150.0,  # m/s
        'alt': 2000.0,   # meters
        'alt_type': 'BARO',
    },
    'helicopter': {
        'skill': 'Average',
        'speed': 50.0,
        'alt': 500.0,
        'alt_type': 'BARO',
    },
    'ship': {
        'skill': 'Average',
        'speed': 0.0,
        'modulation': 0,
        'frequency': 127500000,
    },
    'vehicle': {
        'skill': 'Average',
        'speed': 0.0,
    },
    'static': {
        'skill': 'Average',
    }
}

# Country ID mappings for coalitions
# Common countries - extend as needed
COUNTRY_IDS = {
    'blue': {
        'USA': 2,
        'UK': 4,
        'France': 5,
        'Germany': 6,
        'Canada': 8,
        'Turkey': 37,
        'Israel': 15,
        'Australia': 21,
    },
    'red': {
        'Russia': 0,
        'Ukraine': 1,
        'China': 19,
        'Iran': 34,
        'Syria': 47,
        'North Korea': 88,
    },
    'neutrals': {
        'UN': 7,
        'Austria': 9,
        'Switzerland': 25,
    }
}


# ============================================================================
# CORE ADDITION FUNCTIONS
# ============================================================================

def add_group(
    mission_content: str,
    group_name: str,
    unit_type_category: str,
    unit_type: str,
    coalition: str,
    country: str,
    position: Dict[str, float],
    num_units: int = 1,
    route: Optional[List[Dict]] = None,
    skill: str = "Average",
    heading: float = 0.0
) -> str:
    """
    Add a new group to the mission.

    Creates a completely new group with specified parameters, generating
    new unique IDs for the group and all units.

    Args:
        mission_content: Raw mission file content as string
        group_name: Name for the new group
        unit_type_category: Category (plane, helicopter, ship, vehicle, static)
        unit_type: Specific unit type (e.g., "F-16C_50", "M-1 Abrams")
        coalition: Coalition to add group to (blue, red, neutrals)
        country: Country name (e.g., "USA", "Russia")
        position: Dict with 'x', 'y', and optionally 'alt', 'heading' keys
        num_units: Number of units in the group (default 1)
        route: Optional list of waypoint dicts (if None, creates simple route)
        skill: Skill level for all units (default "Average")
        heading: Heading in radians (default 0.0 = North)

    Returns:
        Modified mission content with new group added

    Raises:
        ValueError: If parameters are invalid or group name already exists

    Example:
        >>> content = parser.get_mission_content()
        >>> content = add_group(
        ...     content,
        ...     group_name="Fighter-2",
        ...     unit_type_category="plane",
        ...     unit_type="F-16C_50",
        ...     coalition="blue",
        ...     country="USA",
        ...     position={"x": -50000, "y": 30000, "alt": 5000},
        ...     num_units=2,
        ...     skill="Good"
        ... )
        >>> parser.write_mission_content(content)
    """
    # Validate parameters
    _validate_add_group_params(
        mission_content, group_name, unit_type_category, coalition,
        country, position, num_units, skill
    )

    # Generate new IDs
    new_group_id = id_manager.generate_new_group_id(mission_content)
    new_unit_ids = id_manager.generate_new_unit_ids(mission_content, num_units)

    # Get position values
    x = float(position['x'])
    y = float(position['y'])
    alt = float(position.get('alt', UNIT_TYPE_DEFAULTS.get(unit_type_category, {}).get('alt', 0)))

    # Generate the group Lua code
    group_lua = _generate_group_lua(
        group_name=group_name,
        unit_type_category=unit_type_category,
        unit_type=unit_type,
        group_id=new_group_id,
        unit_ids=new_unit_ids,
        x=x,
        y=y,
        alt=alt,
        heading=heading,
        skill=skill,
        route=route
    )

    # Find insertion point and insert group
    modified_content = _insert_group_into_mission(
        mission_content=mission_content,
        group_lua=group_lua,
        coalition=coalition,
        country=country,
        unit_type_category=unit_type_category
    )

    return modified_content


def _validate_add_group_params(
    mission_content: str,
    group_name: str,
    unit_type_category: str,
    coalition: str,
    country: str,
    position: Dict[str, float],
    num_units: int,
    skill: str
) -> None:
    """Validate all parameters for add_group."""
    # Validate group name
    is_valid, error = validation.validate_group_name(group_name)
    if not is_valid:
        raise ValueError(error)

    # Check group name doesn't already exist
    if validation.validate_group_exists(mission_content, group_name):
        raise ValueError(f"Group '{group_name}' already exists in mission")

    # Validate unit type category
    is_valid, error = validation.validate_unit_type_category(unit_type_category)
    if not is_valid:
        raise ValueError(error)

    # Validate coalition
    is_valid, error = validation.validate_coalition(coalition)
    if not is_valid:
        raise ValueError(error)

    # Validate country
    if coalition not in COUNTRY_IDS:
        raise ValueError(f"Invalid coalition: {coalition}")
    if country not in COUNTRY_IDS[coalition]:
        valid_countries = list(COUNTRY_IDS[coalition].keys())
        raise ValueError(f"Invalid country '{country}' for coalition '{coalition}'. Valid: {valid_countries}")

    # Validate position
    require_alt = unit_type_category in ['plane', 'helicopter']
    is_valid, error = validation.validate_position(position, require_altitude=require_alt)
    if not is_valid:
        raise ValueError(error)

    # Validate num_units
    if num_units < 1:
        raise ValueError(f"num_units must be at least 1, got {num_units}")
    if num_units > 100:
        raise ValueError(f"num_units too large: {num_units} (max 100)")

    # Validate skill
    is_valid, error = validation.validate_skill_level(skill)
    if not is_valid:
        raise ValueError(error)


def _generate_group_lua(
    group_name: str,
    unit_type_category: str,
    unit_type: str,
    group_id: int,
    unit_ids: List[int],
    x: float,
    y: float,
    alt: float,
    heading: float,
    skill: str,
    route: Optional[List[Dict]] = None
) -> str:
    """
    Generate Lua code for a new group.

    Args:
        group_name: Name of the group
        unit_type_category: plane, helicopter, ship, vehicle, static
        unit_type: Specific unit type string
        group_id: Unique group ID
        unit_ids: List of unique unit IDs
        x, y, alt: Position coordinates
        heading: Heading in radians
        skill: Skill level
        route: Optional route waypoints

    Returns:
        Lua code string for the group (without index)
    """
    # Get defaults for this unit type category
    defaults = UNIT_TYPE_DEFAULTS.get(unit_type_category, {})

    # Generate units section
    units_lua = _generate_units_lua(
        group_name=group_name,
        unit_type=unit_type,
        unit_type_category=unit_type_category,
        unit_ids=unit_ids,
        x=x,
        y=y,
        alt=alt,
        heading=heading,
        skill=skill,
        defaults=defaults
    )

    # Generate route section
    route_lua = _generate_route_lua(
        x=x,
        y=y,
        alt=alt,
        unit_type_category=unit_type_category,
        route=route
    )

    # Build the complete group Lua
    indent = "\t\t\t\t\t\t\t"
    group_lua = f"""[{{NEW_GROUP_INDEX}}] =
{indent}{{
{indent}\t["visible"] = false,
{indent}\t["tasks"] =
{indent}\t{{
{indent}\t}}, -- end of ["tasks"]
{indent}\t["uncontrolled"] = false,
{indent}\t["groupId"] = {group_id},
{indent}\t["hidden"] = false,
{indent}\t["units"] =
{indent}\t{{
{units_lua}
{indent}\t}}, -- end of ["units"]
{indent}\t["y"] = {y},
{indent}\t["x"] = {x},
{indent}\t["name"] = "{group_name}",
{indent}\t["start_time"] = 0,
{route_lua}
{indent}}}, -- end of [{{NEW_GROUP_INDEX}}]
"""
    return group_lua


def _generate_units_lua(
    group_name: str,
    unit_type: str,
    unit_type_category: str,
    unit_ids: List[int],
    x: float,
    y: float,
    alt: float,
    heading: float,
    skill: str,
    defaults: Dict
) -> str:
    """Generate Lua code for the units section."""
    units = []
    indent = "\t\t\t\t\t\t\t\t"

    # Calculate formation offset (simple line formation)
    formation_offset = 50  # meters between units

    for i, unit_id in enumerate(unit_ids):
        # Calculate offset position for formation
        offset_x = x + (i * formation_offset * math.sin(heading + math.pi/2))
        offset_y = y + (i * formation_offset * math.cos(heading + math.pi/2))

        unit_name = f"{group_name}-{i+1}"

        # Build unit-specific properties
        unit_props = f"""[{i+1}] =
{indent}{{
{indent}\t["type"] = "{unit_type}",
{indent}\t["unitId"] = {unit_id},
{indent}\t["skill"] = "{skill}",
{indent}\t["y"] = {offset_y},
{indent}\t["x"] = {offset_x},
{indent}\t["name"] = "{unit_name}",
{indent}\t["heading"] = {heading},"""

        # Add altitude for aircraft
        if unit_type_category in ['plane', 'helicopter']:
            unit_props += f"""
{indent}\t["alt"] = {alt},
{indent}\t["alt_type"] = "{defaults.get('alt_type', 'BARO')}",
{indent}\t["speed"] = {defaults.get('speed', 150.0)},"""

        # Add ship-specific properties
        elif unit_type_category == 'ship':
            unit_props += f"""
{indent}\t["frequency"] = {defaults.get('frequency', 127500000)},
{indent}\t["modulation"] = {defaults.get('modulation', 0)},"""

        unit_props += f"""
{indent}}}, -- end of [{i+1}]"""

        units.append(unit_props)

    return "\n".join(units)


def _generate_route_lua(
    x: float,
    y: float,
    alt: float,
    unit_type_category: str,
    route: Optional[List[Dict]] = None
) -> str:
    """Generate Lua code for the route section."""
    indent = "\t\t\t\t\t\t\t"

    # Default simple route with single waypoint at spawn position
    if route is None:
        defaults = UNIT_TYPE_DEFAULTS.get(unit_type_category, {})
        speed = defaults.get('speed', 0)
        alt_type = defaults.get('alt_type', 'BARO')

        route_lua = f"""{indent}\t["route"] =
{indent}\t{{
{indent}\t\t["points"] =
{indent}\t\t{{
{indent}\t\t\t[1] =
{indent}\t\t\t{{
{indent}\t\t\t\t["type"] = "Turning Point",
{indent}\t\t\t\t["action"] = "Turning Point",
{indent}\t\t\t\t["x"] = {x},
{indent}\t\t\t\t["y"] = {y},
{indent}\t\t\t\t["alt"] = {alt},
{indent}\t\t\t\t["alt_type"] = "{alt_type}",
{indent}\t\t\t\t["speed"] = {speed},
{indent}\t\t\t\t["speed_locked"] = true,
{indent}\t\t\t}}, -- end of [1]
{indent}\t\t}}, -- end of ["points"]
{indent}\t}}, -- end of ["route"]"""
    else:
        # Custom route provided - generate from waypoint list
        route_lua = _generate_custom_route_lua(route, indent, unit_type_category)

    return route_lua


def _generate_custom_route_lua(
    route: List[Dict],
    indent: str,
    unit_type_category: str
) -> str:
    """Generate route Lua from custom waypoint list."""
    defaults = UNIT_TYPE_DEFAULTS.get(unit_type_category, {})

    points = []
    for i, wp in enumerate(route):
        point_lua = f"""{indent}\t\t\t[{i+1}] =
{indent}\t\t\t{{
{indent}\t\t\t\t["type"] = "{wp.get('type', 'Turning Point')}",
{indent}\t\t\t\t["action"] = "{wp.get('action', 'Turning Point')}",
{indent}\t\t\t\t["x"] = {wp['x']},
{indent}\t\t\t\t["y"] = {wp['y']},
{indent}\t\t\t\t["alt"] = {wp.get('alt', defaults.get('alt', 0))},
{indent}\t\t\t\t["alt_type"] = "{wp.get('alt_type', defaults.get('alt_type', 'BARO'))}",
{indent}\t\t\t\t["speed"] = {wp.get('speed', defaults.get('speed', 0))},
{indent}\t\t\t\t["speed_locked"] = true,
{indent}\t\t\t}}, -- end of [{i+1}]"""
        points.append(point_lua)

    points_str = "\n".join(points)

    route_lua = f"""{indent}\t["route"] =
{indent}\t{{
{indent}\t\t["points"] =
{indent}\t\t{{
{points_str}
{indent}\t\t}}, -- end of ["points"]
{indent}\t}}, -- end of ["route"]"""

    return route_lua


def _insert_group_into_mission(
    mission_content: str,
    group_lua: str,
    coalition: str,
    country: str,
    unit_type_category: str
) -> str:
    """
    Insert the generated group Lua into the correct position in mission content.

    Finds the correct coalition > country > unit_type > group section and inserts
    the new group with the correct index.
    """
    country_id = COUNTRY_IDS[coalition][country]

    # First find the main ["coalition"] section to scope our search
    main_coalition_pattern = r'\["coalition"\]\s*=\s*\{(.*?)\},\s*--\s*end\s*of\s*\["coalition"\]'
    main_coalition_match = re.search(main_coalition_pattern, mission_content, re.DOTALL)

    if not main_coalition_match:
        raise ValueError("Main coalition section not found in mission")

    main_coalition_content = main_coalition_match.group(1)
    main_coalition_start = main_coalition_match.start(1)

    # Now find the specific coalition (blue/red/neutrals) within the main coalition section
    coalition_pattern = rf'\["{coalition}"\]\s*=\s*\{{(.*?)\}},\s*--\s*end\s*of\s*\["{coalition}"\]'
    coalition_match = re.search(coalition_pattern, main_coalition_content, re.DOTALL)

    if not coalition_match:
        raise ValueError(f"Coalition '{coalition}' section not found in mission")

    coalition_content = coalition_match.group(1)
    coalition_start_in_main = coalition_match.start(1)

    # Find the country section within coalition - look for ["country"] = { ... }
    country_section_pattern = r'\["country"\]\s*=\s*\{(.*?)\},\s*--\s*end\s*of\s*\["country"\]'
    country_section_match = re.search(country_section_pattern, coalition_content, re.DOTALL)

    if not country_section_match:
        raise ValueError(f"Country section not found in coalition '{coalition}'")

    country_section_content = country_section_match.group(1)
    country_section_start = country_section_match.start(1)

    # Find the specific country by ID within the country section
    # Use simple pattern with brace counting for reliable extraction
    simple_country_pattern = rf'\[(\d+)\]\s*=\s*\{{\s*\["id"\]\s*=\s*{country_id}'
    simple_match = re.search(simple_country_pattern, country_section_content)

    if not simple_match:
        raise ValueError(f"Country with id={country_id} not found in coalition '{coalition}'")

    # Find the full country block using balanced brace matching
    country_start_in_section = simple_match.start()

    # Find the end of this country block by looking for the end marker
    remaining_content = country_section_content[country_start_in_section:]

    # Count braces to find the matching end
    brace_count = 0
    country_end_in_section = country_start_in_section
    for i, char in enumerate(remaining_content):
        if char == '{':
            brace_count += 1
        elif char == '}':
            brace_count -= 1
            if brace_count == 0:
                # Found the matching closing brace
                # Look for the end marker
                end_marker_match = re.match(r'\},\s*--\s*end\s*of\s*\[\d+\]', remaining_content[i:])
                if end_marker_match:
                    country_end_in_section = country_start_in_section + i + len(end_marker_match.group(0))
                else:
                    country_end_in_section = country_start_in_section + i + 1
                break

    country_content = country_section_content[country_start_in_section:country_end_in_section]

    # Find the unit type section within country
    unit_type_pattern = patterns.get_unit_type_section_pattern(unit_type_category)
    unit_type_match = unit_type_pattern.search(country_content)

    if not unit_type_match:
        raise ValueError(f"Unit type '{unit_type_category}' section not found in country (id={country_id})")

    unit_type_content = unit_type_match.group(1)
    unit_type_start_in_country = unit_type_match.start(1)

    # Find the group section within unit type
    group_section_pattern = r'\["group"\]\s*=\s*\{(.*?)\},\s*--\s*end\s*of\s*\["group"\]'
    group_match = re.search(group_section_pattern, unit_type_content, re.DOTALL)

    if not group_match:
        raise ValueError(f"Group section not found in unit type '{unit_type_category}'")

    groups_content = group_match.group(1)
    group_section_start = group_match.start(1)

    # Find the highest group index in this section
    group_indices = re.findall(r'\[(\d+)\]\s*=', groups_content)
    new_index = max([int(idx) for idx in group_indices]) + 1 if group_indices else 1

    # Replace the placeholder index
    group_lua = group_lua.replace('{NEW_GROUP_INDEX}', str(new_index))

    # Calculate absolute position for insertion
    # We need to add up all the offsets from each nesting level
    abs_position = (
        main_coalition_start +
        coalition_start_in_main +
        country_section_start +
        country_start_in_section +
        unit_type_start_in_country +
        group_section_start +
        len(groups_content)
    )

    # Find the exact insertion point (before the closing }, -- end of ["group"])
    # We want to insert after the last group entry
    insert_content = groups_content.rstrip()
    if insert_content:
        # Add newline if there's existing content
        group_lua = "\n" + group_lua.rstrip()

    # Build modified content
    modified_content = (
        mission_content[:abs_position] +
        group_lua +
        mission_content[abs_position:]
    )

    return modified_content


# ============================================================================
# CONVENIENCE WRAPPER FUNCTIONS
# ============================================================================

def add_group_file(
    input_miz: str,
    output_miz: str,
    group_name: str,
    unit_type_category: str,
    unit_type: str,
    coalition: str,
    country: str,
    position: Dict[str, float],
    num_units: int = 1,
    route: Optional[List[Dict]] = None,
    skill: str = "Average",
    heading: float = 0.0
) -> None:
    """
    Add a new group to a .miz file (convenience wrapper).

    Args:
        input_miz: Path to input .miz file
        output_miz: Path to output .miz file
        group_name: Name for the new group
        unit_type_category: Category (plane, helicopter, ship, vehicle, static)
        unit_type: Specific unit type (e.g., "F-16C_50")
        coalition: Coalition (blue, red, neutrals)
        country: Country name (e.g., "USA")
        position: Position dict with x, y, and optionally alt
        num_units: Number of units (default 1)
        route: Optional route waypoints
        skill: Skill level (default "Average")
        heading: Heading in radians (default 0.0)

    Raises:
        FileNotFoundError: If input_miz doesn't exist
        ValueError: If parameters are invalid

    Example:
        >>> add_group_file(
        ...     "../miz-files/input/mission.miz",
        ...     "../miz-files/output/mission_with_fighters.miz",
        ...     group_name="Fighter-2",
        ...     unit_type_category="plane",
        ...     unit_type="F-16C_50",
        ...     coalition="blue",
        ...     country="USA",
        ...     position={"x": -50000, "y": 30000, "alt": 5000},
        ...     num_units=4,
        ...     skill="Good"
        ... )
    """
    from ..parsing.miz_parser import quick_modify

    def modify_func(content):
        return add_group(
            content,
            group_name=group_name,
            unit_type_category=unit_type_category,
            unit_type=unit_type,
            coalition=coalition,
            country=country,
            position=position,
            num_units=num_units,
            route=route,
            skill=skill,
            heading=heading
        )

    quick_modify(input_miz, output_miz, modify_func)


# ============================================================================
# UTILITY FUNCTIONS
# ============================================================================

def get_available_countries(coalition: str) -> List[str]:
    """
    Get list of available countries for a coalition.

    Args:
        coalition: Coalition name (blue, red, neutrals)

    Returns:
        List of country names available for that coalition

    Example:
        >>> countries = get_available_countries("blue")
        >>> print(countries)
        ['USA', 'UK', 'France', ...]
    """
    is_valid, error = validation.validate_coalition(coalition)
    if not is_valid:
        raise ValueError(error)

    return list(COUNTRY_IDS.get(coalition, {}).keys())


def get_country_id(coalition: str, country: str) -> int:
    """
    Get the numeric country ID for a country name.

    Args:
        coalition: Coalition name
        country: Country name

    Returns:
        Country ID number

    Raises:
        ValueError: If coalition or country is invalid
    """
    if coalition not in COUNTRY_IDS:
        raise ValueError(f"Invalid coalition: {coalition}")

    if country not in COUNTRY_IDS[coalition]:
        raise ValueError(f"Invalid country '{country}' for coalition '{coalition}'")

    return COUNTRY_IDS[coalition][country]
