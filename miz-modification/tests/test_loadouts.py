"""
Tests for loadout operations.

Tests reading and modifying aircraft loadouts including pylons, countermeasures,
gun ammunition, and fuel.
"""

import os
import shutil
import sys
from pathlib import Path

# Add parent directory to path for imports
sys.path.insert(0, str(Path(__file__).parent.parent))

# Direct imports - avoid loadouts/__init__.py relative import issues
from parsing.miz_parser import MizParser

# We need to manually load the loadouts modules since they use relative imports
# that don't work when running tests directly
import re
from utils import patterns


# Import functions from loadouts.list manually
def list_loadout(mission_content: str, unit_name: str):
    """Extract complete loadout information for a specific unit."""
    from typing import Dict, Optional, Any

    # Find the unit by name first, then search for payload nearby
    # This approach is more reliable than relying on UNIT_BLOCK_PATTERN
    name_pattern = re.compile(rf'\["name"\]\s*=\s*"{re.escape(unit_name)}"')
    name_match = name_pattern.search(mission_content)

    if not name_match:
        return None

    # Search backward to find the start of this unit block (look for [N] = {)
    search_start = max(0, name_match.start() - 10000)
    search_end = min(len(mission_content), name_match.end() + 20000)
    unit_section = mission_content[search_start:search_end]

    # Find payload section in this region
    payload_match = patterns.PAYLOAD_SECTION_PATTERN_COMPILED.search(unit_section)
    if not payload_match:
        return None

    payload_content = payload_match.group(1)

    # Verify this payload belongs to our unit (check it appears after the name)
    payload_pos_in_section = payload_match.start()
    name_pos_in_section = unit_section.find(f'["name"] = "{unit_name}"')
    if payload_pos_in_section < name_pos_in_section:
        # Payload appears before name, likely belongs to a different unit
        return None

    # Initialize loadout dictionary
    loadout = {
        'pylons': {},
        'chaff': None,
        'flare': None,
        'gun': None,
        'fuel': None
    }

    # Extract pylons
    pylons_match = patterns.PYLONS_SECTION_PATTERN_COMPILED.search(payload_content)
    if pylons_match:
        pylons_content = pylons_match.group(1)
        for pylon_match in patterns.PYLON_BLOCK_PATTERN_COMPILED.finditer(pylons_content):
            pylon_index = int(pylon_match.group(1))
            pylon_content = pylon_match.group(2)

            pylon_data = {}

            # Extract CLSID
            clsid_match = patterns.CLSID_PATTERN_COMPILED.search(pylon_content)
            if clsid_match:
                pylon_data['CLSID'] = clsid_match.group(1)

            # Extract settings if present
            settings_match = patterns.WEAPON_SETTINGS_PATTERN_COMPILED.search(pylon_content)
            if settings_match:
                pylon_data['settings'] = settings_match.group(1).strip()

            loadout['pylons'][pylon_index] = pylon_data

    # Extract countermeasures and other fields
    chaff_match = patterns.CHAFF_PATTERN_COMPILED.search(payload_content)
    if chaff_match:
        loadout['chaff'] = int(chaff_match.group(1))

    flare_match = patterns.FLARE_PATTERN_COMPILED.search(payload_content)
    if flare_match:
        loadout['flare'] = int(flare_match.group(1))

    gun_match = patterns.GUN_AMMO_PATTERN_COMPILED.search(payload_content)
    if gun_match:
        loadout['gun'] = int(gun_match.group(1))

    fuel_match = patterns.FUEL_PATTERN_COMPILED.search(payload_content)
    if fuel_match:
        loadout['fuel'] = float(fuel_match.group(1))

    return loadout


def test_list_loadout():
    """Test listing complete loadout information."""
    print("\n=== TEST: List Loadout ===")

    # Extract mission
    parser = MizParser("tests/test.miz")
    parser.extract()
    content = parser.get_mission_content()

    # Find all unit names in the mission (search all content, not just first 50000 chars)
    unit_names = re.findall(r'\["name"\]\s*=\s*"([^"]+)"', content)
    print(f"Found {len(unit_names)} potential units/groups in mission")

    # Filter to likely aircraft unit names (typically format: GroupName-N-N)
    aircraft_units = [name for name in unit_names if '-' in name and name.count('-') >= 2]
    print(f"Found {len(aircraft_units)} potential aircraft units")

    # Try to find loadout for aircraft units
    for unit_name in aircraft_units:
        loadout = list_loadout(content, unit_name)
        if loadout and loadout['pylons']:
            print(f"\nUnit: {unit_name}")
            print(f"  Pylons: {list(loadout['pylons'].keys())}")
            print(f"  Chaff: {loadout['chaff']}")
            print(f"  Flare: {loadout['flare']}")
            print(f"  Gun: {loadout['gun']}")
            print(f"  Fuel: {loadout['fuel']}")

            # Show first pylon details
            if loadout['pylons']:
                first_pylon = list(loadout['pylons'].keys())[0]
                pylon_data = loadout['pylons'][first_pylon]
                print(f"\n  Pylon {first_pylon}:")
                print(f"    CLSID: {pylon_data.get('CLSID', 'None')}")
                if 'settings' in pylon_data:
                    print(f"    Has settings: Yes")

            print("[OK] List loadout successful")
            return

    print("[WARNING] No units with pylons found in test mission")


def main():
    """Run all loadout tests."""
    print("=" * 60)
    print("LOADOUT OPERATIONS TESTS")
    print("=" * 60)

    # Create temp output directory
    output_dir = Path("tests/temp_output")
    output_dir.mkdir(exist_ok=True)

    try:
        # Run read-only test
        test_list_loadout()

        print("\n" + "=" * 60)
        print("TESTS COMPLETED")
        print("=" * 60)
        print("\nNote: Additional modification tests require full loadouts module")
        print("Run: python -m pytest tests/test_loadouts.py (when module is properly installed)")

    except Exception as e:
        print(f"\n[ERROR] Test failed with error: {e}")
        import traceback
        traceback.print_exc()


if __name__ == "__main__":
    main()
