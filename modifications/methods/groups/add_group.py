#!/usr/bin/env python3
"""
Add a new unit group to a DCS mission file.

Creates a minimal group with one unit at a specified position.
The group will have one starting waypoint at the unit's position.
"""

import re
import sys
import os

# Import from new location
from miz_file_modification.parsing.miz_parser import quick_modify


# Unit type definitions with minimal required fields
UNIT_TYPES = {
    'plane': {
        'example_types': ['F-16C_50', 'F-15C', 'Su-27', 'MiG-29S', 'A-10C'],
        'default_type': 'F-16C_50',
        'fields': {
            'skill': 'Average',
            'speed': 150.0,
            'alt': 2000.0,
            'task': 'CAP'
        }
    },
    'helicopter': {
        'example_types': ['UH-1H', 'Mi-8MT', 'AH-64D', 'Ka-50'],
        'default_type': 'UH-1H',
        'fields': {
            'skill': 'Average',
            'speed': 50.0,
            'alt': 500.0,
            'task': 'Transport'
        }
    },
    'ship': {
        'example_types': ['CHAP_Project22160', 'CVN_71', 'LHA_Tarawa'],
        'default_type': 'CHAP_Project22160',
        'fields': {
            'skill': 'Average',
            'speed': 0.0,
            'modulation': 0,
            'frequency': 127500000
        }
    },
    'vehicle': {
        'example_types': ['M-1 Abrams', 'T-72B', 'BMP-3', 'M-113'],
        'default_type': 'M-1 Abrams',
        'fields': {
            'skill': 'Average',
            'speed': 0.0,
            'task': 'Ground Nothing'
        }
    }
}

COALITIONS = ['blue', 'red', 'neutrals']


def find_max_ids(mission_content: str) -> dict:
    """
    Find the maximum groupId and unitId in the mission.

    Returns:
        Dict with 'max_group_id' and 'max_unit_id'
    """
    group_ids = re.findall(r'\["groupId"\]\s*=\s*(\d+)', mission_content)
    unit_ids = re.findall(r'\["unitId"\]\s*=\s*(\d+)', mission_content)

    max_group_id = max([int(gid) for gid in group_ids]) if group_ids else 0
    max_unit_id = max([int(uid) for uid in unit_ids]) if unit_ids else 0

    return {'max_group_id': max_group_id, 'max_unit_id': max_unit_id}


def generate_group_lua(group_name: str, unit_type_category: str, unit_type: str,
                       x: float, y: float, heading: float, coalition: str,
                       group_id: int, unit_id: int, country_id: int = 2) -> str:
    """
    Generate Lua code for a new group.

    Args:
        group_name: Name of the group
        unit_type_category: Category (plane, helicopter, ship, vehicle)
        unit_type: Specific unit type (e.g., 'F-16C_50')
        x: X coordinate
        y: Y coordinate
        heading: Heading in radians
        coalition: Coalition name (blue, red, neutrals)
        group_id: Group ID number
        unit_id: Unit ID number
        country_id: Country ID (default 2 for USA/Russia)

    Returns:
        Lua code string for the group
    """
    type_config = UNIT_TYPES.get(unit_type_category, {})
    fields = type_config.get('fields', {})

    # Unit name
    unit_name = f"{group_name}-1"

    # Build unit section based on type
    unit_section = f'''									[1] =
									{{
										["type"] = "{unit_type}",
										["unitId"] = {unit_id},
										["skill"] = "{fields.get('skill', 'Average')}",
										["y"] = {y},
										["x"] = {x},
										["name"] = "{unit_name}",
										["heading"] = {heading},'''

    # Add type-specific fields
    if unit_type_category == 'ship':
        unit_section += f'''
										["modulation"] = {fields.get('modulation', 0)},
										["frequency"] = {fields.get('frequency', 127500000)},'''
    elif unit_type_category in ['plane', 'helicopter']:
        unit_section += f'''
										["alt"] = {fields.get('alt', 2000.0)},
										["speed"] = {fields.get('speed', 150.0)},
										["alt_type"] = "BARO",
										["payload"] = {{}},'''

    unit_section += '''
									}, -- end of [1]'''

    # Build route section
    route_section = ''
    if unit_type_category in ['plane', 'helicopter']:
        # Aircraft need altitude in route
        alt = fields.get('alt', 2000.0)
        speed = fields.get('speed', 150.0)
        route_section = f'''								["route"] =
								{{
									["points"] =
									{{
										[1] =
										{{
											["alt"] = {alt},
											["type"] = "Turning Point",
											["ETA"] = 0,
											["alt_type"] = "BARO",
											["formation_template"] = "",
											["y"] = {y},
											["x"] = {x},
											["speed"] = {speed},
											["action"] = "Turning Point",
											["task"] =
											{{
												["id"] = "ComboTask",
												["params"] =
												{{
													["tasks"] = {{}},
												}}, -- end of ["params"]
											}}, -- end of ["task"]
											["speed_locked"] = true,
										}}, -- end of [1]
									}}, -- end of ["points"]
								}}, -- end of ["route"]'''
    else:
        # Ground units and ships
        speed = fields.get('speed', 0.0)
        route_section = f'''								["route"] =
								{{
									["points"] =
									{{
										[1] =
										{{
											["alt"] = 0,
											["type"] = "Turning Point",
											["ETA"] = 0,
											["alt_type"] = "BARO",
											["formation_template"] = "",
											["y"] = {y},
											["x"] = {x},
											["speed"] = {speed},
											["action"] = "Turning Point",
											["task"] =
											{{
												["id"] = "ComboTask",
												["params"] =
												{{
													["tasks"] = {{}},
												}}, -- end of ["params"]
											}}, -- end of ["task"]
											["speed_locked"] = true,
										}}, -- end of [1]
									}}, -- end of ["points"]
								}}, -- end of ["route"]'''

    # Get task for group
    task = fields.get('task', 'CAP')

    # Build complete group
    group_lua = f'''							[{{NEW_GROUP_INDEX}}] =
							{{
								["visible"] = true,
								["tasks"] = {{}},
								["uncontrolled"] = false,'''

    if unit_type_category in ['plane', 'helicopter', 'vehicle']:
        group_lua += f'''
								["task"] = "{task}",
								["taskSelected"] = true,'''

    # Add required fields for aircraft
    if unit_type_category in ['plane', 'helicopter']:
        group_lua += f'''
								["modulation"] = 0,
								["radioSet"] = false,'''

    group_lua += f'''
{route_section}
								["groupId"] = {group_id},
								["hidden"] = false,
								["units"] =
								{{
{unit_section}
								}}, -- end of ["units"]
								["y"] = {y},
								["x"] = {x},
								["name"] = "{group_name}",
								["start_time"] = 0,
							}}, -- end of [{{NEW_GROUP_INDEX}}]'''

    return group_lua


def add_group_to_content(mission_content: str, group_name: str, unit_type_category: str,
                        unit_type: str, x: float, y: float, heading: float = 0.0,
                        coalition: str = 'blue') -> str:
    """
    Add a new group to the mission content.

    Args:
        mission_content: Mission file content
        group_name: Name for the new group
        unit_type_category: Category (plane, helicopter, ship, vehicle)
        unit_type: Specific unit type
        x: X coordinate
        y: Y coordinate
        heading: Heading in radians (default 0)
        coalition: Coalition (blue, red, neutrals)

    Returns:
        Modified mission content
    """
    # Validate inputs
    if unit_type_category not in UNIT_TYPES:
        raise ValueError(f"Invalid unit type category: {unit_type_category}")
    if coalition not in COALITIONS:
        raise ValueError(f"Invalid coalition: {coalition}")

    # Find max IDs
    ids = find_max_ids(mission_content)
    new_group_id = ids['max_group_id'] + 1
    new_unit_id = ids['max_unit_id'] + 1

    print(f"Creating group '{group_name}' with ID {new_group_id}, unit ID {new_unit_id}")

    # Generate group Lua
    group_lua = generate_group_lua(
        group_name, unit_type_category, unit_type,
        x, y, heading, coalition,
        new_group_id, new_unit_id
    )

    # Find the unit type section within the coalition's first country
    # Structure is: mission -> coalition -> blue/red -> country -> [1] -> unit_type -> group
    # First find the main coalition section (not triggers or other "coalition" references)
    # Look for ["coalition"] = { ... ["blue"] = ... } pattern
    main_coalition_pattern = r'\["coalition"\]\s*=\s*\{(.*?)\},\s*--\s*end\s*of\s*\["coalition"\]'
    main_coalition_match = re.search(main_coalition_pattern, mission_content, re.DOTALL)

    if not main_coalition_match:
        print(f"Error: Could not find main coalition section")
        return mission_content

    main_coalition_content = main_coalition_match.group(1)
    main_coalition_start = main_coalition_match.start(1)

    # Now find the specific coalition (blue/red/neutrals) within the main coalition section
    coalition_pattern = rf'\["{coalition}"\]\s*=\s*\{{(.*?)\}},\s*--\s*end\s*of\s*\["{coalition}"\]'
    coalition_match = re.search(coalition_pattern, main_coalition_content, re.DOTALL)

    if not coalition_match:
        print(f"Error: Could not find {coalition} coalition within main coalition section")
        return mission_content

    coalition_content = coalition_match.group(1)
    # Calculate absolute position in mission_content
    coalition_start = main_coalition_start + coalition_match.start(1)

    # Find the unit type section directly (it's nested in country, but we can search for it)
    # Pattern: ["unit_type"] = \n { \n ["group"] = \n { ... }, \n }, -- end of ["unit_type"]
    # Use more flexible whitespace matching
    pattern = rf'(\["{unit_type_category}"\]\s*=\s*\n\s*\{{\s*\n\s*\["group"\]\s*=\s*\n\s*\{{)(.*?)(\}},\s*--\s*end\s*of\s*\["group"\]\s*\n\s*\}},\s*--\s*end\s*of\s*\["{unit_type_category}"\])'

    match = re.search(pattern, coalition_content, re.DOTALL)

    if not match:
        print(f"Warning: Could not find {unit_type_category} section in {coalition} coalition")
        print("The coalition/unit type section may not exist yet")
        return mission_content

    # Find the highest group index in this section
    groups_section = match.group(2)
    group_indices = re.findall(r'\[(\d+)\]\s*=\s*\n\s*\{', groups_section)

    if group_indices:
        max_index = max([int(idx) for idx in group_indices])
        new_index = max_index + 1
    else:
        new_index = 1

    # Replace placeholder with actual index
    group_lua = group_lua.replace('{NEW_GROUP_INDEX}', str(new_index))

    # Insert the new group at the end of the groups section
    # Add it before the closing }, }, -- end of ["unit_type"]
    new_groups_section = match.group(2) + group_lua + '\n\t\t\t\t\t\t'

    # Calculate absolute position in mission_content
    # match positions are relative to coalition_content
    match_start_in_coalition = match.start(2)
    match_end_in_coalition = match.end(2)

    abs_match_start = coalition_start + match_start_in_coalition
    abs_match_end = coalition_start + match_end_in_coalition

    modified_content = mission_content[:abs_match_start] + new_groups_section + mission_content[abs_match_end:]

    print(f"[OK] Group '{group_name}' added successfully!")
    print(f"  Type: {unit_type}")
    print(f"  Coalition: {coalition}")
    print(f"  Position: ({x}, {y})")
    print(f"  Unit count: 1")

    return modified_content


def add_group(input_miz: str, output_miz: str, group_name: str, unit_type_category: str,
             unit_type: str, x: float, y: float, heading: float = 0.0,
             coalition: str = 'blue') -> None:
    """
    Add a new group to a mission file.

    Args:
        input_miz: Input .miz file path
        output_miz: Output .miz file path
        group_name: Name for the new group
        unit_type_category: Category (plane, helicopter, ship, vehicle)
        unit_type: Specific unit type
        x: X coordinate
        y: Y coordinate
        heading: Heading in radians
        coalition: Coalition name
    """
    print(f"Adding group to: {input_miz}")

    def modify_func(content):
        return add_group_to_content(
            content, group_name, unit_type_category,
            unit_type, x, y, heading, coalition
        )

    quick_modify(input_miz, output_miz, modify_func)
    print(f"\nGroup addition complete!")


if __name__ == "__main__":
    if len(sys.argv) < 8:
        print("Add Group - DCS Mission Modifier")
        print("\nUsage: python add_group.py <group_name> <type_category> <unit_type> <x> <y> <coalition> <input.miz> [output.miz] [heading]")
        print("\nType Categories: plane, helicopter, ship, vehicle")
        print("Coalitions: blue, red, neutrals")
        print("\nExamples:")
        print('  python add_group.py "Fighter-1" plane F-16C_50 -50000 30000 blue "../../miz-files/input/mission.miz" "../../miz-files/output/modified.miz"')
        print('  python add_group.py "Tank-1" vehicle "M-1 Abrams" 10000 -5000 red "input.miz" "output.miz" 1.57')
        print('  python add_group.py "Ship-1" ship CVN_71 0 0 blue "mission.miz" "output.miz"')
        print("\nAvailable unit types:")
        for category, config in UNIT_TYPES.items():
            print(f"  {category}: {', '.join(config['example_types'])}")
        sys.exit(1)

    group_name = sys.argv[1]
    type_category = sys.argv[2].lower()
    unit_type = sys.argv[3]
    x = float(sys.argv[4])
    y = float(sys.argv[5])
    coalition = sys.argv[6].lower()
    input_file = sys.argv[7]
    output_file = sys.argv[8] if len(sys.argv) > 8 else input_file.replace('.miz', '_with_group.miz')
    heading = float(sys.argv[9]) if len(sys.argv) > 9 else 0.0

    if not os.path.exists(input_file):
        print(f"Error: Input file not found: {input_file}")
        sys.exit(1)

    add_group(input_file, output_file, group_name, type_category, unit_type, x, y, heading, coalition)
