"""
Loadout modification functions for DCS mission files.

This module provides functions to modify aircraft loadouts, including changing
weapons on pylons, adjusting chaff/flare quantities, modifying gun ammunition, and fuel.

WEAPON CLSID REFERENCE:
To find valid CLSID values for weapons, consult the DCS Stores List:
https://www.airgoons.com/w/DCS_Reference/Stores_List

This database contains all weapon identifiers, pylon compatibility,
and aircraft-specific loadout configurations.
"""

import re
from typing import Optional, Dict, Any
from ..utils.patterns import (
    PAYLOAD_SECTION_PATTERN_COMPILED,
    PYLONS_SECTION_PATTERN_COMPILED,
    PYLON_BLOCK_PATTERN_COMPILED,
    CLSID_PATTERN_COMPILED,
    CHAFF_PATTERN_COMPILED,
    FLARE_PATTERN_COMPILED,
    GUN_AMMO_PATTERN_COMPILED,
    FUEL_PATTERN_COMPILED,
    UNIT_BLOCK_PATTERN_COMPILED,
    UNIT_NAME_PATTERN_COMPILED
)


def modify_pylon(
    mission_content: str,
    unit_name: str,
    pylon_index: int,
    clsid: str,
    settings: Optional[str] = None
) -> str:
    """
    Modify a specific pylon's weapon loadout.

    Args:
        mission_content: Raw mission file content as string
        unit_name: Name of the unit to modify
        pylon_index: Pylon number (1-based index)
        clsid: Weapon CLSID identifier (e.g., "{40EF17B7-F508-45de-8566-6FFECC0C1AB8}")
               Find CLSIDs at: https://www.airgoons.com/w/DCS_Reference/Stores_List
        settings: Optional settings block for the weapon (as Lua string)

    Returns:
        Modified mission content as string

    Example:
        # Change pylon 3 to AIM-120C (CLSID from DCS Stores List)
        content = modify_pylon(
            content,
            "Viper-1-1",
            3,
            "{40EF17B7-F508-45de-8566-6FFECC0C1AB8}"  # AIM-120C
        )

        # Change with custom settings (e.g., GBU-12 with laser code)
        content = modify_pylon(
            content,
            "Viper-1-1",
            5,
            "{51F9AAE5-964F-4D21-83FB-502E3BFE5F8A}",  # GBU-12
            settings='["laser_code"] = 1688'
        )
    """
    # Find the unit block
    unit_start = None
    unit_end = None
    unit_content = None

    for match in UNIT_BLOCK_PATTERN_COMPILED.finditer(mission_content):
        content = match.group(2)
        name_match = UNIT_NAME_PATTERN_COMPILED.search(content)
        if name_match and name_match.group(1) == unit_name:
            unit_start = match.start()
            unit_end = match.end()
            unit_content = content
            break

    if not unit_content:
        raise ValueError(f"Unit '{unit_name}' not found")

    # Find payload section
    payload_match = PAYLOAD_SECTION_PATTERN_COMPILED.search(unit_content)
    if not payload_match:
        raise ValueError(f"Unit '{unit_name}' has no payload section")

    payload_content = payload_match.group(1)

    # Find pylons section
    pylons_match = PYLONS_SECTION_PATTERN_COMPILED.search(payload_content)
    if not pylons_match:
        raise ValueError(f"Unit '{unit_name}' has no pylons section")

    pylons_content = pylons_match.group(1)

    # Find the specific pylon
    pylon_found = False
    new_pylons_content = pylons_content

    for pylon_match in PYLON_BLOCK_PATTERN_COMPILED.finditer(pylons_content):
        if int(pylon_match.group(1)) == pylon_index:
            pylon_found = True
            old_pylon_block = pylon_match.group(0)

            # Build new pylon block
            if settings:
                new_pylon_block = f'''[{pylon_index}] =
												{{
													["CLSID"] = "{clsid}",
													["settings"] =
													{{
														{settings}
													}}, -- end of ["settings"]
												}}, -- end of [{pylon_index}]'''
            else:
                new_pylon_block = f'''[{pylon_index}] =
												{{
													["CLSID"] = "{clsid}",
												}}, -- end of [{pylon_index}]'''

            new_pylons_content = new_pylons_content.replace(old_pylon_block, new_pylon_block)
            break

    if not pylon_found:
        raise ValueError(f"Pylon {pylon_index} not found on unit '{unit_name}'")

    # Replace pylons section in payload
    new_payload_content = PYLONS_SECTION_PATTERN_COMPILED.sub(
        f'["pylons"] = \n\t\t\t\t\t\t\t\t\t{{\n{new_pylons_content}\n\t\t\t\t\t\t\t\t\t}}, -- end of ["pylons"]',
        payload_content
    )

    # Replace payload section in unit
    new_unit_content = PAYLOAD_SECTION_PATTERN_COMPILED.sub(
        f'["payload"] = \n\t\t\t\t\t\t\t{{\n{new_payload_content}\n\t\t\t\t\t\t\t}}, -- end of ["payload"]',
        unit_content
    )

    # Replace unit in mission content
    unit_block = mission_content[unit_start:unit_end]
    new_unit_block = unit_block.replace(unit_content, new_unit_content)

    return mission_content[:unit_start] + new_unit_block + mission_content[unit_end:]


def modify_pylon_file(
    input_miz: str,
    output_miz: str,
    unit_name: str,
    pylon_index: int,
    clsid: str,
    settings: Optional[str] = None
) -> None:
    """
    Convenience wrapper to modify pylon in .miz file.

    Args:
        input_miz: Path to input .miz file
        output_miz: Path to output .miz file
        unit_name: Name of the unit to modify
        pylon_index: Pylon number (1-based index)
        clsid: Weapon CLSID identifier
        settings: Optional settings block for the weapon

    Example:
        modify_pylon_file(
            "input.miz",
            "output.miz",
            "Viper-1-1",
            3,
            "{40EF17B7-F508-45de-8566-6FFECC0C1AB8}"
        )
    """
    from ..parsing.miz_parser import quick_modify

    def modify_func(content):
        return modify_pylon(content, unit_name, pylon_index, clsid, settings)

    quick_modify(input_miz, output_miz, modify_func)


def modify_countermeasures(
    mission_content: str,
    unit_name: str,
    chaff: Optional[int] = None,
    flare: Optional[int] = None
) -> str:
    """
    Modify chaff and/or flare quantities for a unit.

    Args:
        mission_content: Raw mission file content as string
        unit_name: Name of the unit to modify
        chaff: New chaff quantity (None to leave unchanged)
        flare: New flare quantity (None to leave unchanged)

    Returns:
        Modified mission content as string

    Example:
        # Set chaff to 120 and flare to 60
        content = modify_countermeasures(content, "Viper-1-1", chaff=120, flare=60)

        # Only change chaff
        content = modify_countermeasures(content, "Viper-1-1", chaff=200)
    """
    if chaff is None and flare is None:
        return mission_content

    # Find the unit block
    unit_start = None
    unit_end = None
    unit_content = None

    for match in UNIT_BLOCK_PATTERN_COMPILED.finditer(mission_content):
        content = match.group(2)
        name_match = UNIT_NAME_PATTERN_COMPILED.search(content)
        if name_match and name_match.group(1) == unit_name:
            unit_start = match.start()
            unit_end = match.end()
            unit_content = content
            break

    if not unit_content:
        raise ValueError(f"Unit '{unit_name}' not found")

    # Find payload section
    payload_match = PAYLOAD_SECTION_PATTERN_COMPILED.search(unit_content)
    if not payload_match:
        raise ValueError(f"Unit '{unit_name}' has no payload section")

    payload_content = payload_match.group(1)
    new_payload_content = payload_content

    # Modify chaff if specified
    if chaff is not None:
        chaff_match = CHAFF_PATTERN_COMPILED.search(new_payload_content)
        if chaff_match:
            new_payload_content = CHAFF_PATTERN_COMPILED.sub(
                f'["chaff"] = {chaff}',
                new_payload_content
            )
        else:
            raise ValueError(f"Unit '{unit_name}' has no chaff field in payload")

    # Modify flare if specified
    if flare is not None:
        flare_match = FLARE_PATTERN_COMPILED.search(new_payload_content)
        if flare_match:
            new_payload_content = FLARE_PATTERN_COMPILED.sub(
                f'["flare"] = {flare}',
                new_payload_content
            )
        else:
            raise ValueError(f"Unit '{unit_name}' has no flare field in payload")

    # Replace payload section in unit
    new_unit_content = PAYLOAD_SECTION_PATTERN_COMPILED.sub(
        lambda m: f'["payload"] = \n\t\t\t\t\t\t\t{{\n{new_payload_content}\n\t\t\t\t\t\t\t}}, -- end of ["payload"]',
        unit_content
    )

    # Replace unit in mission content
    unit_block = mission_content[unit_start:unit_end]
    new_unit_block = unit_block.replace(unit_content, new_unit_content)

    return mission_content[:unit_start] + new_unit_block + mission_content[unit_end:]


def modify_countermeasures_file(
    input_miz: str,
    output_miz: str,
    unit_name: str,
    chaff: Optional[int] = None,
    flare: Optional[int] = None
) -> None:
    """
    Convenience wrapper to modify countermeasures in .miz file.

    Args:
        input_miz: Path to input .miz file
        output_miz: Path to output .miz file
        unit_name: Name of the unit to modify
        chaff: New chaff quantity (None to leave unchanged)
        flare: New flare quantity (None to leave unchanged)

    Example:
        modify_countermeasures_file("input.miz", "output.miz", "Viper-1-1", chaff=120, flare=60)
    """
    from ..parsing.miz_parser import quick_modify

    def modify_func(content):
        return modify_countermeasures(content, unit_name, chaff, flare)

    quick_modify(input_miz, output_miz, modify_func)


def modify_gun_ammo(mission_content: str, unit_name: str, ammo: int) -> str:
    """
    Modify gun ammunition quantity for a unit.

    Args:
        mission_content: Raw mission file content as string
        unit_name: Name of the unit to modify
        ammo: New ammunition quantity

    Returns:
        Modified mission content as string

    Example:
        content = modify_gun_ammo(content, "Viper-1-1", 510)
    """
    # Find the unit block
    unit_start = None
    unit_end = None
    unit_content = None

    for match in UNIT_BLOCK_PATTERN_COMPILED.finditer(mission_content):
        content = match.group(2)
        name_match = UNIT_NAME_PATTERN_COMPILED.search(content)
        if name_match and name_match.group(1) == unit_name:
            unit_start = match.start()
            unit_end = match.end()
            unit_content = content
            break

    if not unit_content:
        raise ValueError(f"Unit '{unit_name}' not found")

    # Find payload section
    payload_match = PAYLOAD_SECTION_PATTERN_COMPILED.search(unit_content)
    if not payload_match:
        raise ValueError(f"Unit '{unit_name}' has no payload section")

    payload_content = payload_match.group(1)

    # Modify gun ammo
    gun_match = GUN_AMMO_PATTERN_COMPILED.search(payload_content)
    if not gun_match:
        raise ValueError(f"Unit '{unit_name}' has no gun field in payload")

    new_payload_content = GUN_AMMO_PATTERN_COMPILED.sub(
        f'["gun"] = {ammo}',
        payload_content
    )

    # Replace payload section in unit
    new_unit_content = PAYLOAD_SECTION_PATTERN_COMPILED.sub(
        lambda m: f'["payload"] = \n\t\t\t\t\t\t\t{{\n{new_payload_content}\n\t\t\t\t\t\t\t}}, -- end of ["payload"]',
        unit_content
    )

    # Replace unit in mission content
    unit_block = mission_content[unit_start:unit_end]
    new_unit_block = unit_block.replace(unit_content, new_unit_content)

    return mission_content[:unit_start] + new_unit_block + mission_content[unit_end:]


def modify_gun_ammo_file(input_miz: str, output_miz: str, unit_name: str, ammo: int) -> None:
    """
    Convenience wrapper to modify gun ammo in .miz file.

    Args:
        input_miz: Path to input .miz file
        output_miz: Path to output .miz file
        unit_name: Name of the unit to modify
        ammo: New ammunition quantity

    Example:
        modify_gun_ammo_file("input.miz", "output.miz", "Viper-1-1", 510)
    """
    from ..parsing.miz_parser import quick_modify

    def modify_func(content):
        return modify_gun_ammo(content, unit_name, ammo)

    quick_modify(input_miz, output_miz, modify_func)


def modify_fuel(mission_content: str, unit_name: str, fuel: float) -> str:
    """
    Modify fuel quantity for a unit.

    Args:
        mission_content: Raw mission file content as string
        unit_name: Name of the unit to modify
        fuel: New fuel quantity in kg

    Returns:
        Modified mission content as string

    Example:
        content = modify_fuel(content, "Viper-1-1", 5500.0)
    """
    # Find the unit block
    unit_start = None
    unit_end = None
    unit_content = None

    for match in UNIT_BLOCK_PATTERN_COMPILED.finditer(mission_content):
        content = match.group(2)
        name_match = UNIT_NAME_PATTERN_COMPILED.search(content)
        if name_match and name_match.group(1) == unit_name:
            unit_start = match.start()
            unit_end = match.end()
            unit_content = content
            break

    if not unit_content:
        raise ValueError(f"Unit '{unit_name}' not found")

    # Find payload section
    payload_match = PAYLOAD_SECTION_PATTERN_COMPILED.search(unit_content)
    if not payload_match:
        raise ValueError(f"Unit '{unit_name}' has no payload section")

    payload_content = payload_match.group(1)

    # Modify fuel
    fuel_match = FUEL_PATTERN_COMPILED.search(payload_content)
    if not fuel_match:
        raise ValueError(f"Unit '{unit_name}' has no fuel field in payload")

    new_payload_content = FUEL_PATTERN_COMPILED.sub(
        f'["fuel"] = {fuel}',
        payload_content
    )

    # Replace payload section in unit
    new_unit_content = PAYLOAD_SECTION_PATTERN_COMPILED.sub(
        lambda m: f'["payload"] = \n\t\t\t\t\t\t\t{{\n{new_payload_content}\n\t\t\t\t\t\t\t}}, -- end of ["payload"]',
        unit_content
    )

    # Replace unit in mission content
    unit_block = mission_content[unit_start:unit_end]
    new_unit_block = unit_block.replace(unit_content, new_unit_content)

    return mission_content[:unit_start] + new_unit_block + mission_content[unit_end:]


def modify_fuel_file(input_miz: str, output_miz: str, unit_name: str, fuel: float) -> None:
    """
    Convenience wrapper to modify fuel in .miz file.

    Args:
        input_miz: Path to input .miz file
        output_miz: Path to output .miz file
        unit_name: Name of the unit to modify
        fuel: New fuel quantity in kg

    Example:
        modify_fuel_file("input.miz", "output.miz", "Viper-1-1", 5500.0)
    """
    from ..parsing.miz_parser import quick_modify

    def modify_func(content):
        return modify_fuel(content, unit_name, fuel)

    quick_modify(input_miz, output_miz, modify_func)


def clear_pylon(mission_content: str, unit_name: str, pylon_index: int) -> str:
    """
    Remove weapon from a specific pylon (empty the pylon).

    Args:
        mission_content: Raw mission file content as string
        unit_name: Name of the unit to modify
        pylon_index: Pylon number (1-based index) to clear

    Returns:
        Modified mission content as string

    Example:
        content = clear_pylon(content, "Viper-1-1", 3)
    """
    # Find the unit block
    unit_start = None
    unit_end = None
    unit_content = None

    for match in UNIT_BLOCK_PATTERN_COMPILED.finditer(mission_content):
        content = match.group(2)
        name_match = UNIT_NAME_PATTERN_COMPILED.search(content)
        if name_match and name_match.group(1) == unit_name:
            unit_start = match.start()
            unit_end = match.end()
            unit_content = content
            break

    if not unit_content:
        raise ValueError(f"Unit '{unit_name}' not found")

    # Find payload section
    payload_match = PAYLOAD_SECTION_PATTERN_COMPILED.search(unit_content)
    if not payload_match:
        raise ValueError(f"Unit '{unit_name}' has no payload section")

    payload_content = payload_match.group(1)

    # Find pylons section
    pylons_match = PYLONS_SECTION_PATTERN_COMPILED.search(payload_content)
    if not pylons_match:
        raise ValueError(f"Unit '{unit_name}' has no pylons section")

    pylons_content = pylons_match.group(1)

    # Find and remove the specific pylon
    pylon_found = False
    new_pylons_content = pylons_content

    for pylon_match in PYLON_BLOCK_PATTERN_COMPILED.finditer(pylons_content):
        if int(pylon_match.group(1)) == pylon_index:
            pylon_found = True
            old_pylon_block = pylon_match.group(0)
            new_pylons_content = new_pylons_content.replace(old_pylon_block, "")
            break

    if not pylon_found:
        raise ValueError(f"Pylon {pylon_index} not found on unit '{unit_name}'")

    # Replace pylons section in payload
    new_payload_content = PYLONS_SECTION_PATTERN_COMPILED.sub(
        f'["pylons"] = \n\t\t\t\t\t\t\t\t\t{{\n{new_pylons_content}\n\t\t\t\t\t\t\t\t\t}}, -- end of ["pylons"]',
        payload_content
    )

    # Replace payload section in unit
    new_unit_content = PAYLOAD_SECTION_PATTERN_COMPILED.sub(
        f'["payload"] = \n\t\t\t\t\t\t\t{{\n{new_payload_content}\n\t\t\t\t\t\t\t}}, -- end of ["payload"]',
        unit_content
    )

    # Replace unit in mission content
    unit_block = mission_content[unit_start:unit_end]
    new_unit_block = unit_block.replace(unit_content, new_unit_content)

    return mission_content[:unit_start] + new_unit_block + mission_content[unit_end:]


def clear_pylon_file(input_miz: str, output_miz: str, unit_name: str, pylon_index: int) -> None:
    """
    Convenience wrapper to clear pylon in .miz file.

    Args:
        input_miz: Path to input .miz file
        output_miz: Path to output .miz file
        unit_name: Name of the unit to modify
        pylon_index: Pylon number (1-based index) to clear

    Example:
        clear_pylon_file("input.miz", "output.miz", "Viper-1-1", 3)
    """
    from ..parsing.miz_parser import quick_modify

    def modify_func(content):
        return clear_pylon(content, unit_name, pylon_index)

    quick_modify(input_miz, output_miz, modify_func)


def clear_all_pylons(mission_content: str, unit_name: str) -> str:
    """
    Remove all weapons from all pylons (empty all pylons).

    Args:
        mission_content: Raw mission file content as string
        unit_name: Name of the unit to modify

    Returns:
        Modified mission content as string

    Example:
        content = clear_all_pylons(content, "Viper-1-1")
    """
    # Find the unit block
    unit_start = None
    unit_end = None
    unit_content = None

    for match in UNIT_BLOCK_PATTERN_COMPILED.finditer(mission_content):
        content = match.group(2)
        name_match = UNIT_NAME_PATTERN_COMPILED.search(content)
        if name_match and name_match.group(1) == unit_name:
            unit_start = match.start()
            unit_end = match.end()
            unit_content = content
            break

    if not unit_content:
        raise ValueError(f"Unit '{unit_name}' not found")

    # Find payload section
    payload_match = PAYLOAD_SECTION_PATTERN_COMPILED.search(unit_content)
    if not payload_match:
        raise ValueError(f"Unit '{unit_name}' has no payload section")

    payload_content = payload_match.group(1)

    # Replace pylons section with empty pylons
    new_payload_content = PYLONS_SECTION_PATTERN_COMPILED.sub(
        '["pylons"] = \n\t\t\t\t\t\t\t\t\t{\n\t\t\t\t\t\t\t\t\t}, -- end of ["pylons"]',
        payload_content
    )

    # Replace payload section in unit
    new_unit_content = PAYLOAD_SECTION_PATTERN_COMPILED.sub(
        f'["payload"] = \n\t\t\t\t\t\t\t{{\n{new_payload_content}\n\t\t\t\t\t\t\t}}, -- end of ["payload"]',
        unit_content
    )

    # Replace unit in mission content
    unit_block = mission_content[unit_start:unit_end]
    new_unit_block = unit_block.replace(unit_content, new_unit_content)

    return mission_content[:unit_start] + new_unit_block + mission_content[unit_end:]


def clear_all_pylons_file(input_miz: str, output_miz: str, unit_name: str) -> None:
    """
    Convenience wrapper to clear all pylons in .miz file.

    Args:
        input_miz: Path to input .miz file
        output_miz: Path to output .miz file
        unit_name: Name of the unit to modify

    Example:
        clear_all_pylons_file("input.miz", "output.miz", "Viper-1-1")
    """
    from ..parsing.miz_parser import quick_modify

    def modify_func(content):
        return clear_all_pylons(content, unit_name)

    quick_modify(input_miz, output_miz, modify_func)
