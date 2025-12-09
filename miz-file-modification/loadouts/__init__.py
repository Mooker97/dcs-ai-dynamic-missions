"""
Loadout operations for DCS mission files.

This module provides functions for reading and modifying aircraft loadouts,
including pylons, weapons, chaff/flare quantities, gun ammunition, and fuel.
"""

from .list import (
    list_loadout,
    list_loadout_file,
    get_pylon_info,
    get_pylon_info_file
)

from .modify import (
    modify_pylon,
    modify_pylon_file,
    modify_countermeasures,
    modify_countermeasures_file,
    modify_gun_ammo,
    modify_gun_ammo_file,
    modify_fuel,
    modify_fuel_file,
    clear_pylon,
    clear_pylon_file,
    clear_all_pylons,
    clear_all_pylons_file
)

__all__ = [
    # List functions
    'list_loadout',
    'list_loadout_file',
    'get_pylon_info',
    'get_pylon_info_file',
    # Modify functions
    'modify_pylon',
    'modify_pylon_file',
    'modify_countermeasures',
    'modify_countermeasures_file',
    'modify_gun_ammo',
    'modify_gun_ammo_file',
    'modify_fuel',
    'modify_fuel_file',
    'clear_pylon',
    'clear_pylon_file',
    'clear_all_pylons',
    'clear_all_pylons_file'
]
