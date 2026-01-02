"""
Trigger addition functions for .miz files.

Functions for adding trigger zones, trigger rules, and DO SCRIPT triggers to missions.

Adding a trigger requires modifying THREE sections:
1. ["trigrules"] - Human-readable trigger definition
2. ["trig"]["conditions"] - Compiled condition Lua code
3. ["trig"]["actions"] - Compiled action Lua code
4. ["trig"]["func"] - Execution function code
5. ["trig"]["flag"] - Trigger enabled flag
"""

import re
from typing import Dict, List, Optional, Any

from .list import list_trigger_zones, list_trigger_rules, list_compiled_triggers


# ============================================================================
# TRIGGER ZONE FUNCTIONS
# ============================================================================

def add_trigger_zone(
    mission_content: str,
    name: str,
    x: float,
    y: float,
    radius: float,
    hidden: bool = False,
    zone_type: int = 0,
    heading: float = 0
) -> str:
    """
    Add a new trigger zone to the mission.

    Args:
        mission_content: Raw mission file content as string
        name: Zone name (must be unique)
        x: X coordinate (meters)
        y: Y coordinate (meters)
        radius: Zone radius (meters)
        hidden: Whether zone is hidden on F10 map (default False)
        zone_type: Zone type (0=circle, 2=quad, default 0)
        heading: Zone heading in radians (default 0)

    Returns:
        Modified mission content with new zone added

    Example:
        >>> content = add_trigger_zone(content, "Target Area", 150000, 55000, 5000)
        >>> content = add_trigger_zone(content, "Hidden Zone", 100000, 40000, 3000, hidden=True)
    """
    # Get existing zones to find max zone ID and index
    existing_zones = list_trigger_zones(mission_content)

    max_zone_id = 0
    max_index = 0
    for zone in existing_zones:
        if zone['zoneId'] and zone['zoneId'] > max_zone_id:
            max_zone_id = zone['zoneId']
        if zone['index'] and zone['index'] > max_index:
            max_index = zone['index']

    new_zone_id = max_zone_id + 1
    new_index = max_index + 1

    # Generate zone Lua code
    zone_lua = f'''
\t\t\t[{new_index}] =
\t\t\t{{
\t\t\t\t["radius"] = {radius},
\t\t\t\t["zoneId"] = {new_zone_id},
\t\t\t\t["color"] =
\t\t\t\t{{
\t\t\t\t\t[1] = 0.50196078431373,
\t\t\t\t\t[2] = 1,
\t\t\t\t\t[3] = 1,
\t\t\t\t\t[4] = 0.14901960784314,
\t\t\t\t}}, -- end of ["color"]
\t\t\t\t["properties"] = {{}},
\t\t\t\t["hidden"] = {"true" if hidden else "false"},
\t\t\t\t["y"] = {y},
\t\t\t\t["x"] = {x},
\t\t\t\t["name"] = "{name}",
\t\t\t\t["heading"] = {heading},
\t\t\t\t["type"] = {zone_type},
\t\t\t}}, -- end of [{new_index}]'''

    # Find zones section end and insert before it
    zones_end_pattern = r'(\},\s*--\s*end of \["zones"\])'
    zones_end_match = re.search(zones_end_pattern, mission_content)

    if not zones_end_match:
        raise ValueError("Could not find zones section in mission")

    insert_pos = zones_end_match.start()

    # Insert the new zone
    modified = (
        mission_content[:insert_pos] +
        zone_lua + '\n\t\t' +
        mission_content[insert_pos:]
    )

    return modified


def add_trigger_zone_file(
    input_miz: str,
    output_miz: str,
    name: str,
    x: float,
    y: float,
    radius: float,
    **kwargs
) -> None:
    """
    Add a trigger zone to a .miz file (convenience wrapper).

    Args:
        input_miz: Path to input .miz file
        output_miz: Path to output .miz file
        name: Zone name
        x: X coordinate
        y: Y coordinate
        radius: Zone radius
        **kwargs: Additional zone parameters (hidden, zone_type, heading)

    Example:
        >>> add_trigger_zone_file("mission.miz", "mission_mod.miz",
        ...                       "Target Area", 150000, 55000, 5000)
    """
    from pathlib import Path
    from ..parsing.miz_parser import MizParser

    if not Path(input_miz).exists():
        raise FileNotFoundError(f"Input .miz file not found: {input_miz}")

    parser = MizParser(input_miz)
    parser.extract()

    try:
        content = parser.get_mission_content()
        modified = add_trigger_zone(content, name, x, y, radius, **kwargs)
        parser.write_mission_content(modified)
        parser.repackage(output_miz)
    finally:
        parser.cleanup()


# ============================================================================
# DO SCRIPT TRIGGER FUNCTIONS
# ============================================================================

def add_do_script_trigger(
    mission_content: str,
    comment: str,
    script: str,
    time_after: int = 1,
    trigger_type: str = "triggerOnce"
) -> str:
    """
    Add a DO SCRIPT trigger that runs Lua code after a time delay.

    This is the most common trigger type for injecting custom Lua scripts.

    Args:
        mission_content: Raw mission file content as string
        comment: Trigger name/comment (displayed in ME)
        script: Lua script code to execute
        time_after: Seconds after mission start to run (default 1)
        trigger_type: "triggerOnce" or "triggerContinuous" (default "triggerOnce")

    Returns:
        Modified mission content with new trigger added

    Example:
        >>> script = '''
        ... trigger.action.outText("Hello World!", 10)
        ... '''
        >>> content = add_do_script_trigger(content, "Say Hello", script, time_after=5)
    """
    # Get existing triggers to find next index
    existing_rules = list_trigger_rules(mission_content)
    compiled = list_compiled_triggers(mission_content)

    next_trigger_index = len(existing_rules) + 1
    next_trig_index = compiled['count'] + 1

    # Escape script for Lua string (escape backslashes and quotes)
    escaped_script = script.replace('\\', '\\\\').replace('"', '\\"').replace('\n', '\\n')

    # Generate trigrules entry
    trigrules_entry = f'''
\t\t[{next_trigger_index}] =
\t\t{{
\t\t\t["rules"] =
\t\t\t{{
\t\t\t\t[1] =
\t\t\t\t{{
\t\t\t\t\t["predicate"] = "c_time_after",
\t\t\t\t\t["seconds"] = {time_after},
\t\t\t\t}}, -- end of [1]
\t\t\t}}, -- end of ["rules"]
\t\t\t["eventlist"] = "",
\t\t\t["predicate"] = "{trigger_type}",
\t\t\t["actions"] =
\t\t\t{{
\t\t\t\t[1] =
\t\t\t\t{{
\t\t\t\t\t["predicate"] = "a_do_script",
\t\t\t\t\t["file"] = "",
\t\t\t\t}}, -- end of [1]
\t\t\t}}, -- end of ["actions"]
\t\t\t["comment"] = "{comment}",
\t\t}}, -- end of [{next_trigger_index}]'''

    # Generate trig condition entry
    condition_code = f'return(c_time_after({time_after}) )'

    # Generate trig action entry
    action_code = f'a_do_script("{escaped_script}"); mission.trig.func[{next_trig_index}]=nil;'

    # Generate trig func entry
    func_code = f'if mission.trig.conditions[{next_trig_index}]() then mission.trig.actions[{next_trig_index}]() end'

    # Insert trigrules entry
    trigrules_end = re.search(r'(\},\s*--\s*end of \["trigrules"\])', mission_content)
    if trigrules_end:
        mission_content = (
            mission_content[:trigrules_end.start()] +
            trigrules_entry + '\n\t' +
            mission_content[trigrules_end.start():]
        )

    # Insert trig entries
    mission_content = _add_trig_condition(mission_content, next_trig_index, condition_code)
    mission_content = _add_trig_action(mission_content, next_trig_index, action_code)
    mission_content = _add_trig_func(mission_content, next_trig_index, func_code)
    mission_content = _add_trig_flag(mission_content, next_trig_index, True)

    return mission_content


def add_do_script_trigger_file(
    input_miz: str,
    output_miz: str,
    comment: str,
    script: str,
    time_after: int = 1,
    trigger_type: str = "triggerOnce"
) -> None:
    """
    Add a DO SCRIPT trigger to a .miz file (convenience wrapper).

    Args:
        input_miz: Path to input .miz file
        output_miz: Path to output .miz file
        comment: Trigger name/comment
        script: Lua script code to execute
        time_after: Seconds after mission start to run
        trigger_type: "triggerOnce" or "triggerContinuous"

    Example:
        >>> add_do_script_trigger_file(
        ...     "mission.miz", "mission_mod.miz",
        ...     "Init Script", "trigger.action.outText('Started!', 10)",
        ...     time_after=1
        ... )
    """
    from pathlib import Path
    from ..parsing.miz_parser import MizParser

    if not Path(input_miz).exists():
        raise FileNotFoundError(f"Input .miz file not found: {input_miz}")

    parser = MizParser(input_miz)
    parser.extract()

    try:
        content = parser.get_mission_content()
        modified = add_do_script_trigger(content, comment, script, time_after, trigger_type)
        parser.write_mission_content(modified)
        parser.repackage(output_miz)
    finally:
        parser.cleanup()


# ============================================================================
# FLAG TRIGGER FUNCTIONS
# ============================================================================

def add_set_flag_trigger(
    mission_content: str,
    comment: str,
    flag: str,
    condition_type: str,
    condition_params: Dict[str, Any],
    trigger_type: str = "triggerOnce"
) -> str:
    """
    Add a trigger that sets a flag when a condition is met.

    Args:
        mission_content: Raw mission file content as string
        comment: Trigger name/comment
        flag: Flag name/number to set
        condition_type: Condition predicate (c_time_after, c_group_in_zone, etc.)
        condition_params: Parameters for the condition
        trigger_type: "triggerOnce" or "triggerContinuous"

    Returns:
        Modified mission content with new trigger added

    Example:
        >>> # Set flag when group enters zone
        >>> content = add_set_flag_trigger(
        ...     content, "Player Arrived",
        ...     flag="1",
        ...     condition_type="c_part_of_group_in_zone",
        ...     condition_params={"group": 63, "zone": 241}
        ... )
    """
    existing_rules = list_trigger_rules(mission_content)
    compiled = list_compiled_triggers(mission_content)

    next_trigger_index = len(existing_rules) + 1
    next_trig_index = compiled['count'] + 1

    # Build condition params Lua
    condition_params_lua = ""
    for key, value in condition_params.items():
        if isinstance(value, str):
            condition_params_lua += f'\t\t\t\t\t["{key}"] = "{value}",\n'
        else:
            condition_params_lua += f'\t\t\t\t\t["{key}"] = {value},\n'

    # Generate trigrules entry
    trigrules_entry = f'''
\t\t[{next_trigger_index}] =
\t\t{{
\t\t\t["rules"] =
\t\t\t{{
\t\t\t\t[1] =
\t\t\t\t{{
\t\t\t\t\t["predicate"] = "{condition_type}",
{condition_params_lua}\t\t\t\t}}, -- end of [1]
\t\t\t}}, -- end of ["rules"]
\t\t\t["eventlist"] = "",
\t\t\t["predicate"] = "{trigger_type}",
\t\t\t["actions"] =
\t\t\t{{
\t\t\t\t[1] =
\t\t\t\t{{
\t\t\t\t\t["flag"] = "{flag}",
\t\t\t\t\t["predicate"] = "a_set_flag",
\t\t\t\t}}, -- end of [1]
\t\t\t}}, -- end of ["actions"]
\t\t\t["comment"] = "{comment}",
\t\t}}, -- end of [{next_trigger_index}]'''

    # Generate compiled code based on condition type
    condition_code = _build_condition_code(condition_type, condition_params)
    action_code = f'a_set_flag("{flag}"); mission.trig.func[{next_trig_index}]=nil;'
    func_code = f'if mission.trig.conditions[{next_trig_index}]() then mission.trig.actions[{next_trig_index}]() end'

    # Insert trigrules entry
    trigrules_end = re.search(r'(\},\s*--\s*end of \["trigrules"\])', mission_content)
    if trigrules_end:
        mission_content = (
            mission_content[:trigrules_end.start()] +
            trigrules_entry + '\n\t' +
            mission_content[trigrules_end.start():]
        )

    # Insert trig entries
    mission_content = _add_trig_condition(mission_content, next_trig_index, condition_code)
    mission_content = _add_trig_action(mission_content, next_trig_index, action_code)
    mission_content = _add_trig_func(mission_content, next_trig_index, func_code)
    mission_content = _add_trig_flag(mission_content, next_trig_index, True)

    return mission_content


# ============================================================================
# MESSAGE TRIGGER FUNCTIONS
# ============================================================================

def add_message_trigger(
    mission_content: str,
    comment: str,
    message: str,
    duration: int = 10,
    time_after: int = 1,
    trigger_type: str = "triggerOnce"
) -> str:
    """
    Add a trigger that displays a text message after a time delay.

    Args:
        mission_content: Raw mission file content as string
        comment: Trigger name/comment
        message: Message text to display
        duration: How long to display message in seconds (default 10)
        time_after: Seconds after mission start to show (default 1)
        trigger_type: "triggerOnce" or "triggerContinuous"

    Returns:
        Modified mission content with new trigger added

    Example:
        >>> content = add_message_trigger(
        ...     content, "Welcome Message",
        ...     "Welcome to the mission!", duration=15, time_after=5
        ... )
    """
    existing_rules = list_trigger_rules(mission_content)
    compiled = list_compiled_triggers(mission_content)

    next_trigger_index = len(existing_rules) + 1
    next_trig_index = compiled['count'] + 1

    # Escape message
    escaped_message = message.replace('"', '\\"')

    # Generate trigrules entry
    trigrules_entry = f'''
\t\t[{next_trigger_index}] =
\t\t{{
\t\t\t["rules"] =
\t\t\t{{
\t\t\t\t[1] =
\t\t\t\t{{
\t\t\t\t\t["predicate"] = "c_time_after",
\t\t\t\t\t["seconds"] = {time_after},
\t\t\t\t}}, -- end of [1]
\t\t\t}}, -- end of ["rules"]
\t\t\t["eventlist"] = "",
\t\t\t["predicate"] = "{trigger_type}",
\t\t\t["actions"] =
\t\t\t{{
\t\t\t\t[1] =
\t\t\t\t{{
\t\t\t\t\t["seconds"] = {duration},
\t\t\t\t\t["start_delay"] = 0,
\t\t\t\t\t["predicate"] = "a_out_text_delay",
\t\t\t\t\t["text"] = "{escaped_message}",
\t\t\t\t\t["clearview"] = false,
\t\t\t\t}}, -- end of [1]
\t\t\t}}, -- end of ["actions"]
\t\t\t["comment"] = "{comment}",
\t\t}}, -- end of [{next_trigger_index}]'''

    # Generate compiled code
    condition_code = f'return(c_time_after({time_after}) )'
    action_code = f'a_out_text_delay("{escaped_message}", {duration}, false, 0); mission.trig.func[{next_trig_index}]=nil;'
    func_code = f'if mission.trig.conditions[{next_trig_index}]() then mission.trig.actions[{next_trig_index}]() end'

    # Insert trigrules entry
    trigrules_end = re.search(r'(\},\s*--\s*end of \["trigrules"\])', mission_content)
    if trigrules_end:
        mission_content = (
            mission_content[:trigrules_end.start()] +
            trigrules_entry + '\n\t' +
            mission_content[trigrules_end.start():]
        )

    # Insert trig entries
    mission_content = _add_trig_condition(mission_content, next_trig_index, condition_code)
    mission_content = _add_trig_action(mission_content, next_trig_index, action_code)
    mission_content = _add_trig_func(mission_content, next_trig_index, func_code)
    mission_content = _add_trig_flag(mission_content, next_trig_index, True)

    return mission_content


def add_message_trigger_file(
    input_miz: str,
    output_miz: str,
    comment: str,
    message: str,
    duration: int = 10,
    time_after: int = 1,
    trigger_type: str = "triggerOnce"
) -> None:
    """
    Add a message trigger to a .miz file (convenience wrapper).
    """
    from pathlib import Path
    from ..parsing.miz_parser import MizParser

    if not Path(input_miz).exists():
        raise FileNotFoundError(f"Input .miz file not found: {input_miz}")

    parser = MizParser(input_miz)
    parser.extract()

    try:
        content = parser.get_mission_content()
        modified = add_message_trigger(content, comment, message, duration, time_after, trigger_type)
        parser.write_mission_content(modified)
        parser.repackage(output_miz)
    finally:
        parser.cleanup()


# ============================================================================
# HELPER FUNCTIONS
# ============================================================================

def _add_trig_condition(mission_content: str, index: int, code: str) -> str:
    """Add a condition entry to the trig.conditions array."""
    # Find end of conditions array
    pattern = r'(\["conditions"\]\s*=\s*\{.*?)(\},\s*--\s*end of \["conditions"\])'
    match = re.search(pattern, mission_content, re.DOTALL)

    if not match:
        return mission_content

    # Escape code for Lua string
    escaped_code = code.replace('"', '\\"')

    # Insert new condition
    new_entry = f'\n\t\t\t[{index}] = "{escaped_code}",'
    insert_pos = match.end(1)

    return (
        mission_content[:insert_pos] +
        new_entry +
        mission_content[insert_pos:]
    )


def _add_trig_action(mission_content: str, index: int, code: str) -> str:
    """Add an action entry to the trig.actions array."""
    # Find the trig section's actions array (not trigrules actions)
    # Look for ["trig"] = { ... ["actions"] = {
    trig_start = mission_content.find('["trig"]')
    if trig_start == -1:
        return mission_content

    # Find actions within trig section
    trig_section_end = mission_content.find('}, -- end of ["trig"]', trig_start)
    if trig_section_end == -1:
        trig_section_end = len(mission_content)

    trig_section = mission_content[trig_start:trig_section_end]

    # Find actions array in trig section
    actions_match = re.search(r'(\["actions"\]\s*=\s*\{)(.*?)(\},\s*--\s*end of \["actions"\])', trig_section, re.DOTALL)

    if not actions_match:
        return mission_content

    # Escape code for Lua string
    escaped_code = code.replace('\\', '\\\\').replace('"', '\\"')

    # Insert new action
    new_entry = f'\n\t\t\t[{index}] = "{escaped_code}",'
    insert_pos = trig_start + actions_match.end(2)

    return (
        mission_content[:insert_pos] +
        new_entry +
        mission_content[insert_pos:]
    )


def _add_trig_func(mission_content: str, index: int, code: str) -> str:
    """Add a func entry to the trig.func array."""
    # Find the trig section's func array
    trig_start = mission_content.find('["trig"]')
    if trig_start == -1:
        return mission_content

    trig_section_end = mission_content.find('}, -- end of ["trig"]', trig_start)
    if trig_section_end == -1:
        trig_section_end = len(mission_content)

    trig_section = mission_content[trig_start:trig_section_end]

    # Find func array in trig section
    func_match = re.search(r'(\["func"\]\s*=\s*\{)(.*?)(\},\s*--\s*end of \["func"\])', trig_section, re.DOTALL)

    if not func_match:
        return mission_content

    # Escape code for Lua string
    escaped_code = code.replace('"', '\\"')

    # Insert new func
    new_entry = f'\n\t\t\t[{index}] = "{escaped_code}",'
    insert_pos = trig_start + func_match.end(2)

    return (
        mission_content[:insert_pos] +
        new_entry +
        mission_content[insert_pos:]
    )


def _add_trig_flag(mission_content: str, index: int, enabled: bool) -> str:
    """Add a flag entry to the trig.flag array."""
    # Find the trig section's flag array
    trig_start = mission_content.find('["trig"]')
    if trig_start == -1:
        return mission_content

    trig_section_end = mission_content.find('}, -- end of ["trig"]', trig_start)
    if trig_section_end == -1:
        trig_section_end = len(mission_content)

    trig_section = mission_content[trig_start:trig_section_end]

    # Find flag array in trig section
    flag_match = re.search(r'(\["flag"\]\s*=\s*\{)(.*?)(\},\s*--\s*end of \["flag"\])', trig_section, re.DOTALL)

    if not flag_match:
        return mission_content

    # Insert new flag
    flag_value = 'true' if enabled else 'false'
    new_entry = f'\n\t\t\t[{index}] = {flag_value},'
    insert_pos = trig_start + flag_match.end(2)

    return (
        mission_content[:insert_pos] +
        new_entry +
        mission_content[insert_pos:]
    )


def _build_condition_code(condition_type: str, params: Dict[str, Any]) -> str:
    """Build compiled condition code from type and parameters."""
    if condition_type == "c_time_after":
        return f'return(c_time_after({params.get("seconds", 1)}) )'
    elif condition_type == "c_part_of_group_in_zone":
        return f'return(c_part_of_group_in_zone({params["group"]}, {params["zone"]}) )'
    elif condition_type == "c_group_dead":
        return f'return(c_group_dead({params["group"]}) )'
    elif condition_type == "c_flag_is_true":
        return f'return(c_flag_is_true("{params["flag"]}") )'
    elif condition_type == "c_flag_equals":
        return f'return(c_flag_equals("{params["flag"]}", {params["value"]}) )'
    elif condition_type == "c_unit_in_zone":
        return f'return(c_unit_in_zone({params["unit"]}, {params["zone"]}) )'
    else:
        # Generic fallback - may not work for all conditions
        param_str = ", ".join(str(v) for v in params.values())
        return f'return({condition_type}({param_str}) )'
