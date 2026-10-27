"""
Trigger listing and inspection functions for .miz files.

Read-only functions for finding, counting, and inspecting triggers in missions.

DCS missions have THREE trigger-related sections:
- ["triggers"]["zones"] - Trigger zones (circular map areas)
- ["trig"] - Compiled Lua code (actions, conditions, func arrays)
- ["trigrules"] - Human-readable trigger definitions
"""

import re
from typing import Dict, List, Optional, Any


# ============================================================================
# TRIGGER ZONE FUNCTIONS
# ============================================================================

def list_trigger_zones(mission_content: str) -> List[Dict[str, Any]]:
    """
    List all trigger zones in the mission.

    Args:
        mission_content: Raw mission file content as string

    Returns:
        List of zone dictionaries with:
        - name: Zone name
        - zoneId: Zone ID
        - x: X coordinate
        - y: Y coordinate
        - radius: Zone radius in meters
        - type: Zone type (0=circle, 2=quad)
        - hidden: Whether zone is hidden

    Example:
        >>> zones = list_trigger_zones(content)
        >>> for zone in zones:
        >>>     print(f"{zone['name']}: radius={zone['radius']}m at ({zone['x']}, {zone['y']})")
    """
    zones = []

    # Find the triggers zones section
    zones_pattern = r'\["triggers"\]\s*=\s*\{[^}]*\["zones"\]\s*=\s*\{(.*?)\},\s*--\s*end of \["zones"\]'
    zones_match = re.search(zones_pattern, mission_content, re.DOTALL)

    if not zones_match:
        # Try alternative pattern without nested triggers
        zones_pattern = r'\["zones"\]\s*=\s*\{(.*?)\},\s*--\s*end of \["zones"\]'
        zones_match = re.search(zones_pattern, mission_content, re.DOTALL)

    if not zones_match:
        return zones

    zones_content = zones_match.group(1)

    # Find each zone block [n] = { ... }
    zone_blocks = re.finditer(
        r'\[(\d+)\]\s*=\s*\{(.*?)\},\s*--\s*end of \[\d+\]',
        zones_content,
        re.DOTALL
    )

    for block in zone_blocks:
        zone_index = int(block.group(1))
        zone_content = block.group(2)

        zone_info = {
            'index': zone_index,
            'name': _extract_string_field(zone_content, 'name'),
            'zoneId': _extract_int_field(zone_content, 'zoneId'),
            'x': _extract_float_field(zone_content, 'x'),
            'y': _extract_float_field(zone_content, 'y'),
            'radius': _extract_float_field(zone_content, 'radius'),
            'type': _extract_int_field(zone_content, 'type') or 0,
            'hidden': _extract_bool_field(zone_content, 'hidden'),
            'heading': _extract_float_field(zone_content, 'heading') or 0,
        }

        zones.append(zone_info)

    return zones


def find_zone_by_name(mission_content: str, zone_name: str) -> Optional[Dict[str, Any]]:
    """
    Find a trigger zone by name.

    Args:
        mission_content: Raw mission file content as string
        zone_name: Name of the zone to find

    Returns:
        Zone dictionary if found, None otherwise
    """
    zones = list_trigger_zones(mission_content)
    for zone in zones:
        if zone['name'] == zone_name:
            return zone
    return None


def find_zone_by_id(mission_content: str, zone_id: int) -> Optional[Dict[str, Any]]:
    """
    Find a trigger zone by its ID.

    Args:
        mission_content: Raw mission file content as string
        zone_id: ID of the zone to find

    Returns:
        Zone dictionary if found, None otherwise
    """
    zones = list_trigger_zones(mission_content)
    for zone in zones:
        if zone['zoneId'] == zone_id:
            return zone
    return None


# ============================================================================
# TRIGGER RULES FUNCTIONS (trigrules - human readable)
# ============================================================================

def list_trigger_rules(mission_content: str) -> List[Dict[str, Any]]:
    """
    List all trigger rules (trigrules section) in the mission.

    The trigrules section contains human-readable trigger definitions with
    conditions (rules) and actions.

    Args:
        mission_content: Raw mission file content as string

    Returns:
        List of trigger rule dictionaries with:
        - index: Trigger index
        - comment: Trigger name/description
        - predicate: Trigger type (triggerOnce, triggerContinuous, etc.)
        - rules: List of condition dictionaries
        - actions: List of action dictionaries

    Example:
        >>> rules = list_trigger_rules(content)
        >>> for rule in rules:
        >>>     print(f"{rule['comment']}: {rule['predicate']}")
        >>>     print(f"  Conditions: {len(rule['rules'])}")
        >>>     print(f"  Actions: {len(rule['actions'])}")
    """
    triggers = []

    # Find trigrules section
    trigrules_start = mission_content.find('["trigrules"]')
    if trigrules_start == -1:
        return triggers

    # Find the end of trigrules section using brace counting
    open_brace = mission_content.find('{', trigrules_start)
    if open_brace == -1:
        return triggers

    depth = 0
    end_pos = open_brace
    for i in range(open_brace, len(mission_content)):
        if mission_content[i] == '{':
            depth += 1
        elif mission_content[i] == '}':
            depth -= 1
            if depth == 0:
                end_pos = i
                break

    trigrules_content = mission_content[open_brace + 1:end_pos]

    # Find top-level trigger blocks by finding [n] = { at exactly 2 tabs indentation
    # Top-level triggers have pattern like: \n\t\t[n] = { (2 tabs, not more)
    # Nested blocks inside rules/actions have 4+ tabs
    trigger_pattern = re.compile(r'^\t\t\[(\d+)\]\s*=\s*\{', re.MULTILINE)

    matches = list(trigger_pattern.finditer(trigrules_content))

    for i, match in enumerate(matches):
        trigger_index = int(match.group(1))
        start_pos = match.end() - 1  # Position of opening brace

        # Count braces to find the end of this trigger block
        depth = 0
        end_trigger = start_pos
        for j in range(start_pos, len(trigrules_content)):
            if trigrules_content[j] == '{':
                depth += 1
            elif trigrules_content[j] == '}':
                depth -= 1
                if depth == 0:
                    end_trigger = j
                    break

        trigger_content = trigrules_content[start_pos:end_trigger + 1]

        trigger_info = {
            'index': trigger_index,
            'comment': _extract_string_field(trigger_content, 'comment') or f'Trigger {trigger_index}',
            'predicate': _extract_string_field(trigger_content, 'predicate') or 'triggerOnce',
            'eventlist': _extract_string_field(trigger_content, 'eventlist') or '',
            'rules': _extract_rules(trigger_content),
            'actions': _extract_actions(trigger_content),
        }

        triggers.append(trigger_info)

    return triggers


def find_trigger_by_comment(mission_content: str, comment: str) -> Optional[Dict[str, Any]]:
    """
    Find a trigger rule by its comment/name.

    Args:
        mission_content: Raw mission file content as string
        comment: Comment/name of the trigger to find

    Returns:
        Trigger rule dictionary if found, None otherwise
    """
    triggers = list_trigger_rules(mission_content)
    for trigger in triggers:
        if trigger['comment'] == comment:
            return trigger
    return None


# ============================================================================
# COMPILED TRIGGER FUNCTIONS (trig section)
# ============================================================================

def list_compiled_triggers(mission_content: str) -> Dict[str, Any]:
    """
    List compiled trigger data from the trig section.

    The trig section contains Lua code strings that DCS executes.

    Args:
        mission_content: Raw mission file content as string

    Returns:
        Dictionary with:
        - conditions: List of condition code strings
        - actions: List of action code strings
        - func: List of execution function strings
        - flag: List of trigger enabled flags
        - count: Number of triggers

    Example:
        >>> trig = list_compiled_triggers(content)
        >>> print(f"Total triggers: {trig['count']}")
        >>> for i, cond in enumerate(trig['conditions']):
        >>>     print(f"Trigger {i+1}: {cond}")
    """
    result = {
        'conditions': [],
        'actions': [],
        'func': [],
        'flag': [],
        'count': 0
    }

    # Find trig section
    trig_start = mission_content.find('["trig"]')
    if trig_start == -1:
        return result

    # Find the end of trig section
    open_brace = mission_content.find('{', trig_start)
    if open_brace == -1:
        return result

    depth = 0
    end_pos = open_brace
    for i in range(open_brace, len(mission_content)):
        if mission_content[i] == '{':
            depth += 1
        elif mission_content[i] == '}':
            depth -= 1
            if depth == 0:
                end_pos = i
                break

    trig_content = mission_content[open_brace:end_pos + 1]

    # Extract conditions array
    result['conditions'] = _extract_string_array(trig_content, 'conditions')

    # Extract actions array
    result['actions'] = _extract_string_array(trig_content, 'actions')

    # Extract func array
    result['func'] = _extract_string_array(trig_content, 'func')

    # Extract flag array
    result['flag'] = _extract_bool_array(trig_content, 'flag')

    result['count'] = len(result['conditions'])

    return result


# ============================================================================
# SUMMARY FUNCTIONS
# ============================================================================

def get_trigger_summary(mission_content: str) -> Dict[str, Any]:
    """
    Get a summary of all triggers in the mission.

    Args:
        mission_content: Raw mission file content as string

    Returns:
        Dictionary with:
        - zone_count: Number of trigger zones
        - trigger_count: Number of trigger rules
        - zones: List of zone names
        - triggers: List of trigger comments
        - predicates: Dict counting each predicate type

    Example:
        >>> summary = get_trigger_summary(content)
        >>> print(f"Zones: {summary['zone_count']}")
        >>> print(f"Triggers: {summary['trigger_count']}")
    """
    zones = list_trigger_zones(mission_content)
    triggers = list_trigger_rules(mission_content)

    # Count predicate types
    predicates = {}
    for trigger in triggers:
        pred = trigger['predicate']
        predicates[pred] = predicates.get(pred, 0) + 1

    return {
        'zone_count': len(zones),
        'trigger_count': len(triggers),
        'zones': [z['name'] for z in zones],
        'triggers': [t['comment'] for t in triggers],
        'predicates': predicates
    }


# ============================================================================
# CONVENIENCE WRAPPER FUNCTIONS
# ============================================================================

def list_trigger_zones_file(input_miz: str) -> List[Dict[str, Any]]:
    """
    List trigger zones from a .miz file (convenience wrapper).

    Args:
        input_miz: Path to input .miz file

    Returns:
        List of zone dictionaries

    Example:
        >>> zones = list_trigger_zones_file("mission.miz")
        >>> for zone in zones:
        >>>     print(f"{zone['name']}: {zone['radius']}m")
    """
    from pathlib import Path
    from ..parsing.miz_parser import MizParser

    if not Path(input_miz).exists():
        raise FileNotFoundError(f"Input .miz file not found: {input_miz}")

    parser = MizParser(input_miz)
    parser.extract()

    try:
        content = parser.get_mission_content()
        return list_trigger_zones(content)
    finally:
        parser.cleanup()


def list_trigger_rules_file(input_miz: str) -> List[Dict[str, Any]]:
    """
    List trigger rules from a .miz file (convenience wrapper).

    Args:
        input_miz: Path to input .miz file

    Returns:
        List of trigger rule dictionaries

    Example:
        >>> triggers = list_trigger_rules_file("mission.miz")
        >>> for t in triggers:
        >>>     print(f"{t['comment']}: {len(t['actions'])} actions")
    """
    from pathlib import Path
    from ..parsing.miz_parser import MizParser

    if not Path(input_miz).exists():
        raise FileNotFoundError(f"Input .miz file not found: {input_miz}")

    parser = MizParser(input_miz)
    parser.extract()

    try:
        content = parser.get_mission_content()
        return list_trigger_rules(content)
    finally:
        parser.cleanup()


def get_trigger_summary_file(input_miz: str) -> Dict[str, Any]:
    """
    Get trigger summary from a .miz file (convenience wrapper).

    Args:
        input_miz: Path to input .miz file

    Returns:
        Summary dictionary

    Example:
        >>> summary = get_trigger_summary_file("mission.miz")
        >>> print(f"Zones: {summary['zone_count']}, Triggers: {summary['trigger_count']}")
    """
    from pathlib import Path
    from ..parsing.miz_parser import MizParser

    if not Path(input_miz).exists():
        raise FileNotFoundError(f"Input .miz file not found: {input_miz}")

    parser = MizParser(input_miz)
    parser.extract()

    try:
        content = parser.get_mission_content()
        return get_trigger_summary(content)
    finally:
        parser.cleanup()


# ============================================================================
# HELPER FUNCTIONS
# ============================================================================

def _extract_string_field(content: str, field_name: str) -> Optional[str]:
    """Extract a string field value from Lua content."""
    pattern = rf'\["{field_name}"\]\s*=\s*"([^"]*)"'
    match = re.search(pattern, content)
    return match.group(1) if match else None


def _extract_int_field(content: str, field_name: str) -> Optional[int]:
    """Extract an integer field value from Lua content."""
    pattern = rf'\["{field_name}"\]\s*=\s*(\d+)'
    match = re.search(pattern, content)
    return int(match.group(1)) if match else None


def _extract_float_field(content: str, field_name: str) -> Optional[float]:
    """Extract a float field value from Lua content."""
    pattern = rf'\["{field_name}"\]\s*=\s*([+-]?\d+\.?\d*)'
    match = re.search(pattern, content)
    return float(match.group(1)) if match else None


def _extract_bool_field(content: str, field_name: str) -> Optional[bool]:
    """Extract a boolean field value from Lua content."""
    pattern = rf'\["{field_name}"\]\s*=\s*(true|false)'
    match = re.search(pattern, content)
    return match.group(1) == 'true' if match else None


def _extract_rules(trigger_content: str) -> List[Dict[str, Any]]:
    """Extract rules array from trigger content."""
    rules = []

    # Find rules section
    rules_match = re.search(
        r'\["rules"\]\s*=\s*\{(.*?)\},\s*--\s*end of \["rules"\]',
        trigger_content,
        re.DOTALL
    )

    if not rules_match:
        return rules

    rules_content = rules_match.group(1)

    # Find each rule block
    rule_blocks = re.finditer(
        r'\[(\d+)\]\s*=\s*\{(.*?)\},\s*--\s*end of \[\d+\]',
        rules_content,
        re.DOTALL
    )

    for block in rule_blocks:
        rule_index = int(block.group(1))
        rule_content = block.group(2)

        rule_info = {
            'index': rule_index,
            'predicate': _extract_string_field(rule_content, 'predicate'),
        }

        # Extract common condition parameters
        if 'seconds' in rule_content:
            rule_info['seconds'] = _extract_int_field(rule_content, 'seconds')
        if 'group' in rule_content:
            rule_info['group'] = _extract_int_field(rule_content, 'group')
        if 'zone' in rule_content:
            rule_info['zone'] = _extract_int_field(rule_content, 'zone')
        if 'flag' in rule_content:
            rule_info['flag'] = _extract_string_field(rule_content, 'flag')
        if 'value' in rule_content:
            rule_info['value'] = _extract_int_field(rule_content, 'value')
        if 'unit' in rule_content:
            rule_info['unit'] = _extract_int_field(rule_content, 'unit')

        rules.append(rule_info)

    return rules


def _extract_actions(trigger_content: str) -> List[Dict[str, Any]]:
    """Extract actions array from trigger content."""
    actions = []

    # Find actions section
    actions_match = re.search(
        r'\["actions"\]\s*=\s*\{(.*?)\},\s*--\s*end of \["actions"\]',
        trigger_content,
        re.DOTALL
    )

    if not actions_match:
        return actions

    actions_content = actions_match.group(1)

    # Find each action block
    action_blocks = re.finditer(
        r'\[(\d+)\]\s*=\s*\{(.*?)\},\s*--\s*end of \[\d+\]',
        actions_content,
        re.DOTALL
    )

    for block in action_blocks:
        action_index = int(block.group(1))
        action_content = block.group(2)

        action_info = {
            'index': action_index,
            'predicate': _extract_string_field(action_content, 'predicate'),
        }

        # Extract common action parameters
        if 'flag' in action_content:
            action_info['flag'] = _extract_string_field(action_content, 'flag')
        if 'text' in action_content:
            action_info['text'] = _extract_string_field(action_content, 'text')
        if 'seconds' in action_content:
            action_info['seconds'] = _extract_int_field(action_content, 'seconds')
        if 'file' in action_content:
            action_info['file'] = _extract_string_field(action_content, 'file')
        if 'start_delay' in action_content:
            action_info['start_delay'] = _extract_int_field(action_content, 'start_delay')
        if 'group' in action_content:
            action_info['group'] = _extract_int_field(action_content, 'group')
        if 'zone' in action_content:
            action_info['zone'] = _extract_int_field(action_content, 'zone')
        if 'clearview' in action_content:
            action_info['clearview'] = _extract_bool_field(action_content, 'clearview')

        actions.append(action_info)

    return actions


def _extract_string_array(content: str, array_name: str) -> List[str]:
    """Extract an array of strings from Lua content."""
    result = []

    # Find the array section
    pattern = rf'\["{array_name}"\]\s*=\s*\{{(.*?)\}},\s*--\s*end of \["{array_name}"\]'
    match = re.search(pattern, content, re.DOTALL)

    if not match:
        return result

    array_content = match.group(1)

    # Find each [n] = "value" entry
    entries = re.finditer(r'\[(\d+)\]\s*=\s*"((?:[^"\\]|\\.)*)"', array_content)

    for entry in entries:
        index = int(entry.group(1))
        value = entry.group(2)
        # Ensure list is long enough
        while len(result) < index:
            result.append('')
        if index <= len(result):
            result[index - 1] = value
        else:
            result.append(value)

    return result


def _extract_bool_array(content: str, array_name: str) -> List[bool]:
    """Extract an array of booleans from Lua content."""
    result = []

    # Find the array section
    pattern = rf'\["{array_name}"\]\s*=\s*\{{(.*?)\}},\s*--\s*end of \["{array_name}"\]'
    match = re.search(pattern, content, re.DOTALL)

    if not match:
        return result

    array_content = match.group(1)

    # Find each [n] = true/false entry
    entries = re.finditer(r'\[(\d+)\]\s*=\s*(true|false)', array_content)

    for entry in entries:
        index = int(entry.group(1))
        value = entry.group(2) == 'true'
        # Ensure list is long enough
        while len(result) < index:
            result.append(False)
        if index <= len(result):
            result[index - 1] = value
        else:
            result.append(value)

    return result
