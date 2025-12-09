"""
Read-only loadout listing functions for DCS mission files.

This module provides functions to extract and list loadout information from units,
including pylons, weapons, chaff/flare quantities, gun ammunition, and fuel.
"""

from typing import Dict, List, Optional, Any
from ..utils.patterns import (
    PAYLOAD_SECTION_PATTERN_COMPILED,
    PYLONS_SECTION_PATTERN_COMPILED,
    PYLON_BLOCK_PATTERN_COMPILED,
    CLSID_PATTERN_COMPILED,
    WEAPON_SETTINGS_PATTERN_COMPILED,
    CHAFF_PATTERN_COMPILED,
    FLARE_PATTERN_COMPILED,
    GUN_AMMO_PATTERN_COMPILED,
    FUEL_PATTERN_COMPILED,
    UNIT_BLOCK_PATTERN_COMPILED,
    UNIT_NAME_PATTERN_COMPILED
)


def list_loadout(mission_content: str, unit_name: str) -> Optional[Dict[str, Any]]:
    """
    Extract complete loadout information for a specific unit.

    Args:
        mission_content: Raw mission file content as string
        unit_name: Name of the unit to extract loadout from

    Returns:
        Dictionary with loadout information:
        {
            'pylons': {
                1: {'CLSID': '...', 'settings': {...}},
                2: {'CLSID': '...'},
                ...
            },
            'chaff': 60,
            'flare': 120,
            'gun': 100,
            'fuel': 6103.0
        }
        Returns None if unit not found or has no payload section.

    Example:
        loadout = list_loadout(content, "Viper-1-1")
        print(f"Chaff: {loadout['chaff']}, Flare: {loadout['flare']}")
        print(f"Pylons: {list(loadout['pylons'].keys())}")
    """
    # Find the unit block
    unit_block = None
    for match in UNIT_BLOCK_PATTERN_COMPILED.finditer(mission_content):
        unit_content = match.group(2)
        name_match = UNIT_NAME_PATTERN_COMPILED.search(unit_content)
        if name_match and name_match.group(1) == unit_name:
            unit_block = unit_content
            break

    if not unit_block:
        return None

    # Find payload section
    payload_match = PAYLOAD_SECTION_PATTERN_COMPILED.search(unit_block)
    if not payload_match:
        return None

    payload_content = payload_match.group(1)

    # Initialize loadout dictionary
    loadout = {
        'pylons': {},
        'chaff': None,
        'flare': None,
        'gun': None,
        'fuel': None
    }

    # Extract pylons
    pylons_match = PYLONS_SECTION_PATTERN_COMPILED.search(payload_content)
    if pylons_match:
        pylons_content = pylons_match.group(1)
        for pylon_match in PYLON_BLOCK_PATTERN_COMPILED.finditer(pylons_content):
            pylon_index = int(pylon_match.group(1))
            pylon_content = pylon_match.group(2)

            pylon_data = {}

            # Extract CLSID
            clsid_match = CLSID_PATTERN_COMPILED.search(pylon_content)
            if clsid_match:
                pylon_data['CLSID'] = clsid_match.group(1)

            # Extract settings if present
            settings_match = WEAPON_SETTINGS_PATTERN_COMPILED.search(pylon_content)
            if settings_match:
                pylon_data['settings'] = settings_match.group(1).strip()

            loadout['pylons'][pylon_index] = pylon_data

    # Extract chaff
    chaff_match = CHAFF_PATTERN_COMPILED.search(payload_content)
    if chaff_match:
        loadout['chaff'] = int(chaff_match.group(1))

    # Extract flare
    flare_match = FLARE_PATTERN_COMPILED.search(payload_content)
    if flare_match:
        loadout['flare'] = int(flare_match.group(1))

    # Extract gun ammo
    gun_match = GUN_AMMO_PATTERN_COMPILED.search(payload_content)
    if gun_match:
        loadout['gun'] = int(gun_match.group(1))

    # Extract fuel
    fuel_match = FUEL_PATTERN_COMPILED.search(payload_content)
    if fuel_match:
        loadout['fuel'] = float(fuel_match.group(1))

    return loadout


def list_loadout_file(input_miz: str, unit_name: str) -> Optional[Dict[str, Any]]:
    """
    Convenience wrapper to extract loadout from .miz file.

    Args:
        input_miz: Path to input .miz file
        unit_name: Name of the unit to extract loadout from

    Returns:
        Dictionary with loadout information, or None if not found

    Example:
        loadout = list_loadout_file("mission.miz", "Viper-1-1")
    """
    from ..parsing.miz_parser import MizParser

    parser = MizParser(input_miz)
    parser.extract()
    content = parser.get_mission_content()

    return list_loadout(content, unit_name)


def get_pylon_info(mission_content: str, unit_name: str, pylon_index: int) -> Optional[Dict[str, Any]]:
    """
    Get information about a specific pylon on a unit.

    Args:
        mission_content: Raw mission file content as string
        unit_name: Name of the unit
        pylon_index: Pylon number (1-based index)

    Returns:
        Dictionary with pylon information:
        {
            'CLSID': '...',
            'settings': '...'  # Optional, only if weapon has settings
        }
        Returns None if unit, payload, or pylon not found.

    Example:
        pylon = get_pylon_info(content, "Viper-1-1", 3)
        if pylon:
            print(f"Weapon: {pylon['CLSID']}")
    """
    loadout = list_loadout(mission_content, unit_name)
    if not loadout or not loadout['pylons']:
        return None

    return loadout['pylons'].get(pylon_index)


def get_pylon_info_file(input_miz: str, unit_name: str, pylon_index: int) -> Optional[Dict[str, Any]]:
    """
    Convenience wrapper to get pylon info from .miz file.

    Args:
        input_miz: Path to input .miz file
        unit_name: Name of the unit
        pylon_index: Pylon number (1-based index)

    Returns:
        Dictionary with pylon information, or None if not found

    Example:
        pylon = get_pylon_info_file("mission.miz", "Viper-1-1", 3)
    """
    from ..parsing.miz_parser import MizParser

    parser = MizParser(input_miz)
    parser.extract()
    content = parser.get_mission_content()

    return get_pylon_info(content, unit_name, pylon_index)
