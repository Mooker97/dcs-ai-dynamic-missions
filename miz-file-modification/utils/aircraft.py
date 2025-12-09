"""
Aircraft utilities for DCS mission files.

Functions for identifying player, client, and AI-controlled aircraft,
and working with aircraft-specific properties.
"""

import re
from typing import Dict, List, Optional


# Valid skill levels for AI aircraft
AI_SKILL_LEVELS = ['Random', 'Average', 'Good', 'High', 'Excellent']

# Player/Client designations
PLAYER_DESIGNATIONS = ['Player', 'Client']

# All valid skill values
ALL_SKILL_VALUES = AI_SKILL_LEVELS + PLAYER_DESIGNATIONS


def is_player_aircraft(unit_content: str) -> bool:
    """
    Check if a unit is designated as a player aircraft.

    Args:
        unit_content: String content of a unit block

    Returns:
        True if unit has skill="Player", False otherwise

    Example:
        >>> unit_block = '["skill"] = "Player", ["type"] = "F-16C_50"'
        >>> is_player_aircraft(unit_block)
        True
    """
    skill_match = re.search(r'\["skill"\]\s*=\s*"Player"', unit_content, re.IGNORECASE)
    return skill_match is not None


def is_client_aircraft(unit_content: str) -> bool:
    """
    Check if a unit is designated as a client (multiplayer) aircraft.

    Args:
        unit_content: String content of a unit block

    Returns:
        True if unit has skill="Client", False otherwise

    Example:
        >>> unit_block = '["skill"] = "Client", ["type"] = "F-16C_50"'
        >>> is_client_aircraft(unit_block)
        True
    """
    skill_match = re.search(r'\["skill"\]\s*=\s*"Client"', unit_content, re.IGNORECASE)
    return skill_match is not None


def is_playable_aircraft(unit_content: str) -> bool:
    """
    Check if a unit is playable (either Player or Client).

    Args:
        unit_content: String content of a unit block

    Returns:
        True if unit has skill="Player" or skill="Client", False otherwise

    Example:
        >>> unit_block = '["skill"] = "Client", ["type"] = "F-16C_50"'
        >>> is_playable_aircraft(unit_block)
        True
    """
    return is_player_aircraft(unit_content) or is_client_aircraft(unit_content)


def is_ai_aircraft(unit_content: str) -> bool:
    """
    Check if a unit is AI-controlled.

    Args:
        unit_content: String content of a unit block

    Returns:
        True if unit has AI skill level (Random/Average/Good/High/Excellent), False otherwise

    Example:
        >>> unit_block = '["skill"] = "High", ["type"] = "F-16C_50"'
        >>> is_ai_aircraft(unit_block)
        True
    """
    skill_match = re.search(r'\["skill"\]\s*=\s*"([^"]+)"', unit_content)
    if not skill_match:
        return False

    skill_value = skill_match.group(1)
    return skill_value in AI_SKILL_LEVELS


def get_aircraft_control_type(unit_content: str) -> str:
    """
    Get the control type of an aircraft (Player, Client, or AI).

    Args:
        unit_content: String content of a unit block

    Returns:
        'Player', 'Client', 'AI', or 'Unknown'

    Example:
        >>> unit_block = '["skill"] = "High", ["type"] = "F-16C_50"'
        >>> get_aircraft_control_type(unit_block)
        'AI'
    """
    if is_player_aircraft(unit_content):
        return 'Player'
    elif is_client_aircraft(unit_content):
        return 'Client'
    elif is_ai_aircraft(unit_content):
        return 'AI'
    else:
        return 'Unknown'


def get_skill_level(unit_content: str) -> Optional[str]:
    """
    Extract the skill level from a unit block.

    Args:
        unit_content: String content of a unit block

    Returns:
        Skill level string (Player/Client/High/Good/etc.) or None if not found

    Example:
        >>> unit_block = '["skill"] = "High", ["type"] = "F-16C_50"'
        >>> get_skill_level(unit_block)
        'High'
    """
    skill_match = re.search(r'\["skill"\]\s*=\s*"([^"]+)"', unit_content)
    return skill_match.group(1) if skill_match else None


def find_all_playable_aircraft(mission_content: str) -> List[Dict]:
    """
    Find all playable aircraft (Player or Client) in mission content.

    Args:
        mission_content: Raw mission file content as string

    Returns:
        List of dictionaries containing playable aircraft info:
        - name: Unit name
        - type: Aircraft type
        - control_type: 'Player' or 'Client'
        - unit_id: Unit ID

    Example:
        >>> content = parser.get_mission_content()
        >>> playable = find_all_playable_aircraft(content)
        >>> print(f"Found {len(playable)} playable slots")
    """
    results = []

    # Find all units with Player or Client skill
    playable_pattern = r'\[(\d+)\]\s*=\s*\{.*?\["skill"\]\s*=\s*"(Player|Client)".*?\},\s*--\s*end\s*of\s*\[\d+\]'
    matches = re.finditer(playable_pattern, mission_content, re.DOTALL | re.IGNORECASE)

    for match in matches:
        unit_block = match.group(0)
        control_type = match.group(2)

        # Extract unit details
        name_match = re.search(r'\["name"\]\s*=\s*"([^"]+)"', unit_block)
        type_match = re.search(r'\["type"\]\s*=\s*"([^"]+)"', unit_block)
        unitid_match = re.search(r'\["unitId"\]\s*=\s*(\d+)', unit_block)

        results.append({
            'name': name_match.group(1) if name_match else 'Unknown',
            'type': type_match.group(1) if type_match else 'Unknown',
            'control_type': control_type,
            'unit_id': int(unitid_match.group(1)) if unitid_match else None
        })

    return results


def find_all_ai_aircraft(mission_content: str) -> List[Dict]:
    """
    Find all AI-controlled aircraft in mission content.

    Args:
        mission_content: Raw mission file content as string

    Returns:
        List of dictionaries containing AI aircraft info:
        - name: Unit name
        - type: Aircraft type
        - skill: AI skill level
        - unit_id: Unit ID

    Example:
        >>> content = parser.get_mission_content()
        >>> ai_aircraft = find_all_ai_aircraft(content)
        >>> print(f"Found {len(ai_aircraft)} AI aircraft")
    """
    results = []

    # Build pattern for AI skill levels
    ai_skills = '|'.join(AI_SKILL_LEVELS)
    ai_pattern = rf'\[(\d+)\]\s*=\s*\{{.*?\["skill"\]\s*=\s*"({ai_skills})".*?\}},\s*--\s*end\s*of\s*\[\d+\]'
    matches = re.finditer(ai_pattern, mission_content, re.DOTALL | re.IGNORECASE)

    for match in matches:
        unit_block = match.group(0)
        skill = match.group(2)

        # Extract unit details
        name_match = re.search(r'\["name"\]\s*=\s*"([^"]+)"', unit_block)
        type_match = re.search(r'\["type"\]\s*=\s*"([^"]+)"', unit_block)
        unitid_match = re.search(r'\["unitId"\]\s*=\s*(\d+)', unit_block)

        results.append({
            'name': name_match.group(1) if name_match else 'Unknown',
            'type': type_match.group(1) if type_match else 'Unknown',
            'skill': skill,
            'unit_id': int(unitid_match.group(1)) if unitid_match else None
        })

    return results


def validate_skill_level(skill: str) -> bool:
    """
    Validate that a skill level is valid.

    Args:
        skill: Skill level to validate

    Returns:
        True if valid, False otherwise

    Example:
        >>> validate_skill_level('High')
        True
        >>> validate_skill_level('Expert')
        False
    """
    return skill in ALL_SKILL_VALUES
