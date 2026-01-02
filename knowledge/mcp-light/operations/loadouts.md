# Loadout Operations

Complete reference for aircraft and vehicle loadout operations in the miz-modification library.

## Overview

Loadout operations allow you to inspect and modify weapons, countermeasures, fuel, and ammunition for aircraft and vehicles. This includes pylon weapons (missiles, bombs, pods), chaff/flare quantities, gun ammunition, and fuel levels.

**Module**: `miz_modification.loadouts`

**Important**: Loadouts are unit-specific. Each unit in a group can have different weapons. Use unit index (1-based) to target specific units.

---

## Read-Only Operations

### `list_loadout()`

Get complete loadout information for a unit including all pylons, weapons, countermeasures, fuel, and gun ammo.

**Module**: `miz_modification.loadouts.list`

**Signature**:
```python
def list_loadout(mission_content: str, group_name: str, unit_index: int = 1) -> Dict[str, Any]
```

**Parameters**:

| Name | Type | Required | Description |
|------|------|----------|-------------|
| `mission_content` | `str` | Yes | Raw mission file content as string |
| `group_name` | `str` | Yes | Name of group |
| `unit_index` | `int` | No | Unit index in group (1-based, default: 1) |

**Returns**:

```python
{
    "pylons": {
        1: {
            "CLSID": str,        # Weapon CLSID identifier
            "num": int           # Pylon number
        },
        ...
    },
    "chaff": int,                # Chaff count
    "flare": int,                # Flare count
    "fuel": float,               # Fuel in kg
    "gun": int,                  # Gun ammunition rounds
    "unit_type": str,            # Aircraft/vehicle type
    "unit_name": str             # Unit name
}
```

**Usage Example**:

```python
from miz_modification.loadouts.list import list_loadout
from miz_modification.parsing.miz_parser import MizParser

parser = MizParser("input.miz")
parser.extract()
content = parser.get_mission_content()

# Get loadout for first unit in group
loadout = list_loadout(content, "Fighter-1", 1)

print(f"Aircraft: {loadout['unit_type']}")
print(f"Fuel: {loadout['fuel']}kg")
print(f"Chaff: {loadout['chaff']}, Flare: {loadout['flare']}")
print(f"Gun ammo: {loadout['gun']} rounds")

# List all weapons
for pylon_num, pylon_data in loadout['pylons'].items():
    print(f"Pylon {pylon_num}: {pylon_data['CLSID']}")
```

**File Wrapper**:

```python
from miz_modification.loadouts.list import list_loadout_file

loadout = list_loadout_file("input.miz", "Fighter-1", 1)
print(f"Loadout: {loadout}")
```

**Error Conditions**:

- `ValueError`: Group not found in mission
- `ValueError`: Unit index out of range
- `ValueError`: Could not extract loadout data

---

### `get_pylon_info()`

Get information about a specific pylon's weapon.

**Module**: `miz_modification.loadouts.list`

**Signature**:
```python
def get_pylon_info(mission_content: str, group_name: str,
                   pylon_number: int, unit_index: int = 1) -> Optional[Dict[str, Any]]
```

**Parameters**:

| Name | Type | Required | Description |
|------|------|----------|-------------|
| `mission_content` | `str` | Yes | Raw mission file content as string |
| `group_name` | `str` | Yes | Name of group |
| `pylon_number` | `int` | Yes | Pylon number to query |
| `unit_index` | `int` | No | Unit index in group (1-based, default: 1) |

**Returns**:

```python
{
    "CLSID": str,      # Weapon CLSID identifier
    "num": int         # Pylon number
}
# Returns None if pylon is empty or doesn't exist
```

**Usage Example**:

```python
from miz_modification.loadouts.list import get_pylon_info

# Check what's on pylon 3
pylon = get_pylon_info(content, "Fighter-1", 3, 1)

if pylon:
    print(f"Pylon 3: {pylon['CLSID']}")
else:
    print("Pylon 3 is empty")
```

**File Wrapper**:

```python
from miz_modification.loadouts.list import get_pylon_info_file

pylon = get_pylon_info_file("input.miz", "Fighter-1", 3)
```

**Error Conditions**:

- `ValueError`: Group not found
- `ValueError`: Unit index out of range

---

## Modify Operations

### `modify_pylon()`

Change or add a weapon to a specific pylon.

**Module**: `miz_modification.loadouts.modify`

**Signature**:
```python
def modify_pylon(mission_content: str, group_name: str,
                 pylon_number: int, clsid: str, unit_index: int = 1) -> str
```

**Parameters**:

| Name | Type | Required | Description |
|------|------|----------|-------------|
| `mission_content` | `str` | Yes | Raw mission file content as string |
| `group_name` | `str` | Yes | Name of group |
| `pylon_number` | `int` | Yes | Pylon number to modify |
| `clsid` | `str` | Yes | Weapon CLSID identifier |
| `unit_index` | `int` | No | Unit index in group (1-based, default: 1) |

**Returns**:

Modified mission content as string.

**Usage Example**:

```python
from miz_modification.loadouts.modify import modify_pylon
from miz_modification.parsing.miz_parser import MizParser

parser = MizParser("input.miz")
parser.extract()
content = parser.get_mission_content()

# Change pylon 3 to AIM-120C AMRAAM
content = modify_pylon(
    content,
    "Fighter-1",
    pylon_number=3,
    clsid="{40EF17B7-F508-45de-8566-6FFECC0C1AB8}",  # AIM-120C
    unit_index=1
)

parser.write_mission_content(content)
parser.repackage("output.miz")
```

**File Wrapper**:

```python
from miz_modification.loadouts.modify import modify_pylon_file

modify_pylon_file(
    "input.miz",
    "output.miz",
    "Fighter-1",
    3,
    "{40EF17B7-F508-45de-8566-6FFECC0C1AB8}"
)
```

**Error Conditions**:

- `ValueError`: Group not found
- `ValueError`: Unit index out of range
- `ValueError`: Invalid CLSID format

**Common CLSIDs**:

Reference: [DCS Stores/Weapons List](https://www.airgoons.com/w/DCS_Reference/Stores_List)

```python
# Air-to-Air Missiles
AIM_120C = "{40EF17B7-F508-45de-8566-6FFECC0C1AB8}"
AIM_9M = "{6CEB49FC-DED8-4DED-B053-E1F033FF72D3}"
AIM_9X = "{5CE2FF2A-645A-4197-B48D-8720AC69394F}"

# Air-to-Ground
AGM_65D = "{444BA8AE-82A7-4345-842E-76154EFCCA46}"
GBU_12 = "{51F9AAE5-964F-4D21-83FB-502E3BFE5F8A}"
GBU_38 = "{752AF1D2-EBCC-4bd7-A1E7-2357F5601C70}"

# Fuel Tanks
F16_370GAL = "{8D399DDA-FF81-4F14-904D-099B34FE7918}"
```

---

### `modify_countermeasures()`

Set chaff and flare quantities for a unit.

**Module**: `miz_modification.loadouts.modify`

**Signature**:
```python
def modify_countermeasures(mission_content: str, group_name: str,
                           chaff: Optional[int] = None,
                           flare: Optional[int] = None,
                           unit_index: int = 1) -> str
```

**Parameters**:

| Name | Type | Required | Description |
|------|------|----------|-------------|
| `mission_content` | `str` | Yes | Raw mission file content as string |
| `group_name` | `str` | Yes | Name of group |
| `chaff` | `int` | No | Chaff count (if provided) |
| `flare` | `int` | No | Flare count (if provided) |
| `unit_index` | `int` | No | Unit index in group (1-based, default: 1) |

**Returns**:

Modified mission content as string.

**Usage Example**:

```python
from miz_modification.loadouts.modify import modify_countermeasures

# Set both chaff and flare
content = modify_countermeasures(
    content,
    "Fighter-1",
    chaff=120,
    flare=60,
    unit_index=1
)

# Set only chaff (leave flare unchanged)
content = modify_countermeasures(
    content,
    "Fighter-1",
    chaff=240,
    unit_index=1
)

# Set only flare (leave chaff unchanged)
content = modify_countermeasures(
    content,
    "Fighter-1",
    flare=120,
    unit_index=1
)
```

**File Wrapper**:

```python
from miz_modification.loadouts.modify import modify_countermeasures_file

modify_countermeasures_file(
    "input.miz",
    "output.miz",
    "Fighter-1",
    chaff=120,
    flare=60
)
```

**Error Conditions**:

- `ValueError`: Group not found
- `ValueError`: Unit index out of range
- `ValueError`: Must specify at least one of chaff or flare

---

### `modify_gun_ammo()`

Set gun ammunition quantity for a unit.

**Module**: `miz_modification.loadouts.modify`

**Signature**:
```python
def modify_gun_ammo(mission_content: str, group_name: str,
                    ammo: int, unit_index: int = 1) -> str
```

**Parameters**:

| Name | Type | Required | Description |
|------|------|----------|-------------|
| `mission_content` | `str` | Yes | Raw mission file content as string |
| `group_name` | `str` | Yes | Name of group |
| `ammo` | `int` | Yes | Gun ammunition rounds |
| `unit_index` | `int` | No | Unit index in group (1-based, default: 1) |

**Returns**:

Modified mission content as string.

**Usage Example**:

```python
from miz_modification.loadouts.modify import modify_gun_ammo

# Set gun ammo to 511 rounds (F-16 M61 Vulcan)
content = modify_gun_ammo(content, "Fighter-1", 511, unit_index=1)

# Set gun ammo to 0 (no gun ammunition)
content = modify_gun_ammo(content, "Fighter-1", 0, unit_index=1)
```

**File Wrapper**:

```python
from miz_modification.loadouts.modify import modify_gun_ammo_file

modify_gun_ammo_file("input.miz", "output.miz", "Fighter-1", 511)
```

**Error Conditions**:

- `ValueError`: Group not found
- `ValueError`: Unit index out of range
- `ValueError`: Ammo must be >= 0

---

### `modify_fuel()`

Set fuel quantity for a unit.

**Module**: `miz_modification.loadouts.modify`

**Signature**:
```python
def modify_fuel(mission_content: str, group_name: str,
                fuel: float, unit_index: int = 1) -> str
```

**Parameters**:

| Name | Type | Required | Description |
|------|------|----------|-------------|
| `mission_content` | `str` | Yes | Raw mission file content as string |
| `group_name` | `str` | Yes | Name of group |
| `fuel` | `float` | Yes | Fuel quantity in kilograms |
| `unit_index` | `int` | No | Unit index in group (1-based, default: 1) |

**Returns**:

Modified mission content as string.

**Usage Example**:

```python
from miz_modification.loadouts.modify import modify_fuel

# Set fuel to 3000kg (typical F-16 internal fuel)
content = modify_fuel(content, "Fighter-1", 3000.0, unit_index=1)

# Set fuel to 5000kg (with external tanks)
content = modify_fuel(content, "Fighter-1", 5000.0, unit_index=1)
```

**File Wrapper**:

```python
from miz_modification.loadouts.modify import modify_fuel_file

modify_fuel_file("input.miz", "output.miz", "Fighter-1", 3000.0)
```

**Error Conditions**:

- `ValueError`: Group not found
- `ValueError`: Unit index out of range
- `ValueError`: Fuel must be > 0

---

### `clear_pylon()`

Remove weapon from a specific pylon (make pylon empty).

**Module**: `miz_modification.loadouts.modify`

**Signature**:
```python
def clear_pylon(mission_content: str, group_name: str,
                pylon_number: int, unit_index: int = 1) -> str
```

**Parameters**:

| Name | Type | Required | Description |
|------|------|----------|-------------|
| `mission_content` | `str` | Yes | Raw mission file content as string |
| `group_name` | `str` | Yes | Name of group |
| `pylon_number` | `int` | Yes | Pylon number to clear |
| `unit_index` | `int` | No | Unit index in group (1-based, default: 1) |

**Returns**:

Modified mission content as string.

**Usage Example**:

```python
from miz_modification.loadouts.modify import clear_pylon

# Remove weapon from pylon 3
content = clear_pylon(content, "Fighter-1", 3, unit_index=1)
```

**File Wrapper**:

```python
from miz_modification.loadouts.modify import clear_pylon_file

clear_pylon_file("input.miz", "output.miz", "Fighter-1", 3)
```

**Error Conditions**:

- `ValueError`: Group not found
- `ValueError`: Unit index out of range

---

### `clear_all_pylons()`

Remove all weapons from all pylons (clean configuration).

**Module**: `miz_modification.loadouts.modify`

**Signature**:
```python
def clear_all_pylons(mission_content: str, group_name: str,
                     unit_index: int = 1) -> str
```

**Parameters**:

| Name | Type | Required | Description |
|------|------|----------|-------------|
| `mission_content` | `str` | Yes | Raw mission file content as string |
| `group_name` | `str` | Yes | Name of group |
| `unit_index` | `int` | No | Unit index in group (1-based, default: 1) |

**Returns**:

Modified mission content as string.

**Usage Example**:

```python
from miz_modification.loadouts.modify import clear_all_pylons

# Remove all weapons (clean aircraft)
content = clear_all_pylons(content, "Fighter-1", unit_index=1)
```

**File Wrapper**:

```python
from miz_modification.loadouts.modify import clear_all_pylons_file

clear_all_pylons_file("input.miz", "output.miz", "Fighter-1")
```

**Error Conditions**:

- `ValueError`: Group not found
- `ValueError`: Unit index out of range

---

## Advanced Usage

### Complete Loadout Configuration

```python
from miz_modification.loadouts.modify import (
    modify_pylon, modify_countermeasures, modify_gun_ammo, modify_fuel
)
from miz_modification.parsing.miz_parser import MizParser

parser = MizParser("input.miz")
parser.extract()
content = parser.get_mission_content()

# Configure F-16 for air-to-air mission
group_name = "Fighter-1"

# Air-to-air loadout
# Pylon 1: AIM-9X (left wingtip)
content = modify_pylon(content, group_name, 1, "{5CE2FF2A-645A-4197-B48D-8720AC69394F}")
# Pylon 2: AIM-120C
content = modify_pylon(content, group_name, 2, "{40EF17B7-F508-45de-8566-6FFECC0C1AB8}")
# Pylon 3: 370gal fuel tank
content = modify_pylon(content, group_name, 3, "{8D399DDA-FF81-4F14-904D-099B34FE7918}")
# Pylon 7: 370gal fuel tank
content = modify_pylon(content, group_name, 7, "{8D399DDA-FF81-4F14-904D-099B34FE7918}")
# Pylon 8: AIM-120C
content = modify_pylon(content, group_name, 8, "{40EF17B7-F508-45de-8566-6FFECC0C1AB8}")
# Pylon 9: AIM-9X (right wingtip)
content = modify_pylon(content, group_name, 9, "{5CE2FF2A-645A-4197-B48D-8720AC69394F}")

# Set countermeasures
content = modify_countermeasures(content, group_name, chaff=120, flare=60)

# Set gun ammo
content = modify_gun_ammo(content, group_name, 511)

# Set fuel (internal + 2x370gal tanks = ~5000kg)
content = modify_fuel(content, group_name, 5000.0)

parser.write_mission_content(content)
parser.repackage("output.miz")
```

### Multi-Unit Loadout Configuration

```python
# Configure different loadouts for each unit in a 4-ship flight
from miz_modification.loadouts.modify import modify_pylon

# Lead: Full A/A with fuel tanks
for pylon, clsid in [
    (1, "{5CE2FF2A-645A-4197-B48D-8720AC69394F}"),  # AIM-9X
    (2, "{40EF17B7-F508-45de-8566-6FFECC0C1AB8}"),  # AIM-120C
    (3, "{8D399DDA-FF81-4F14-904D-099B34FE7918}"),  # Fuel tank
]:
    content = modify_pylon(content, "Fighter-1", pylon, clsid, unit_index=1)

# Wingman 2: Same as lead
for pylon, clsid in [
    (1, "{5CE2FF2A-645A-4197-B48D-8720AC69394F}"),
    (2, "{40EF17B7-F508-45de-8566-6FFECC0C1AB8}"),
    (3, "{8D399DDA-FF81-4F14-904D-099B34FE7918}"),
]:
    content = modify_pylon(content, "Fighter-1", pylon, clsid, unit_index=2)

# Wingman 3: More AMRAAMs, less fuel
for pylon, clsid in [
    (1, "{40EF17B7-F508-45de-8566-6FFECC0C1AB8}"),  # AIM-120C
    (2, "{40EF17B7-F508-45de-8566-6FFECC0C1AB8}"),  # AIM-120C
    (3, "{40EF17B7-F508-45de-8566-6FFECC0C1AB8}"),  # AIM-120C
]:
    content = modify_pylon(content, "Fighter-1", pylon, clsid, unit_index=3)

# Wingman 4: Same as wingman 3
for pylon, clsid in [
    (1, "{40EF17B7-F508-45de-8566-6FFECC0C1AB8}"),
    (2, "{40EF17B7-F508-45de-8566-6FFECC0C1AB8}"),
    (3, "{40EF17B7-F508-45de-8566-6FFECC0C1AB8}"),
]:
    content = modify_pylon(content, "Fighter-1", pylon, clsid, unit_index=4)
```

### Loadout Templates

```python
# Define loadout templates for common mission types
LOADOUT_TEMPLATES = {
    "F-16C_CAP": {
        # Combat Air Patrol
        "pylons": {
            1: "{5CE2FF2A-645A-4197-B48D-8720AC69394F}",  # AIM-9X
            2: "{40EF17B7-F508-45de-8566-6FFECC0C1AB8}",  # AIM-120C
            3: "{8D399DDA-FF81-4F14-904D-099B34FE7918}",  # 370gal tank
            4: "{40EF17B7-F508-45de-8566-6FFECC0C1AB8}",  # AIM-120C
            6: "{40EF17B7-F508-45de-8566-6FFECC0C1AB8}",  # AIM-120C
            7: "{8D399DDA-FF81-4F14-904D-099B34FE7918}",  # 370gal tank
            8: "{40EF17B7-F508-45de-8566-6FFECC0C1AB8}",  # AIM-120C
            9: "{5CE2FF2A-645A-4197-B48D-8720AC69394F}",  # AIM-9X
        },
        "chaff": 120,
        "flare": 60,
        "gun": 511,
        "fuel": 5000.0
    },
    "F-16C_SEAD": {
        # Suppression of Enemy Air Defenses
        "pylons": {
            1: "{5CE2FF2A-645A-4197-B48D-8720AC69394F}",  # AIM-9X
            2: "{444BA8AE-82A7-4345-842E-76154EFCCA46}",  # AGM-65D
            3: "{8D399DDA-FF81-4F14-904D-099B34FE7918}",  # 370gal tank
            4: "{69DC8AE7-8F77-427B-B8AA-B19D3F478B65}",  # AGM-88C
            6: "{69DC8AE7-8F77-427B-B8AA-B19D3F478B65}",  # AGM-88C
            7: "{8D399DDA-FF81-4F14-904D-099B34FE7918}",  # 370gal tank
            8: "{444BA8AE-82A7-4345-842E-76154EFCCA46}",  # AGM-65D
            9: "{5CE2FF2A-645A-4197-B48D-8720AC69394F}",  # AIM-9X
        },
        "chaff": 120,
        "flare": 60,
        "gun": 511,
        "fuel": 5000.0
    }
}

def apply_loadout_template(content, group_name, template_name, unit_index=1):
    """Apply a loadout template to a unit."""
    template = LOADOUT_TEMPLATES[template_name]

    # Apply pylons
    for pylon_num, clsid in template["pylons"].items():
        content = modify_pylon(content, group_name, pylon_num, clsid, unit_index)

    # Apply countermeasures
    content = modify_countermeasures(
        content, group_name,
        chaff=template["chaff"],
        flare=template["flare"],
        unit_index=unit_index
    )

    # Apply gun ammo
    content = modify_gun_ammo(content, group_name, template["gun"], unit_index)

    # Apply fuel
    content = modify_fuel(content, group_name, template["fuel"], unit_index)

    return content

# Usage
content = apply_loadout_template(content, "Fighter-1", "F-16C_CAP", unit_index=1)
```

### Clean and Rebuild Loadout

```python
from miz_modification.loadouts.modify import clear_all_pylons, modify_pylon

# Start with clean aircraft
content = clear_all_pylons(content, "Fighter-1", unit_index=1)

# Build custom loadout
custom_loadout = [
    (1, "{5CE2FF2A-645A-4197-B48D-8720AC69394F}"),  # AIM-9X
    (3, "{8D399DDA-FF81-4F14-904D-099B34FE7918}"),  # Fuel tank
    (7, "{8D399DDA-FF81-4F14-904D-099B34FE7918}"),  # Fuel tank
    (9, "{5CE2FF2A-645A-4197-B48D-8720AC69394F}"),  # AIM-9X
]

for pylon_num, clsid in custom_loadout:
    content = modify_pylon(content, "Fighter-1", pylon_num, clsid, unit_index=1)
```

---

## Best Practices

### 1. Always Verify Pylon Compatibility

```python
# Different aircraft have different pylon numbers and capabilities
# F-16: Pylons 1-9
# F/A-18: Pylons 1-11
# A-10C: Pylons 1-11

# Check aircraft type before setting loadout
from miz_modification.loadouts.list import list_loadout

loadout = list_loadout(content, "Fighter-1", 1)
aircraft_type = loadout['unit_type']

if aircraft_type == "F-16C_50":
    # F-16 specific loadout
    pass
elif aircraft_type == "FA-18C_hornet":
    # F/A-18 specific loadout
    pass
```

### 2. Use CLSID Constants

```python
# Define CLSID constants for readability
class Weapons:
    AIM_9X = "{5CE2FF2A-645A-4197-B48D-8720AC69394F}"
    AIM_120C = "{40EF17B7-F508-45de-8566-6FFECC0C1AB8}"
    AGM_65D = "{444BA8AE-82A7-4345-842E-76154EFCCA46}"
    GBU_12 = "{51F9AAE5-964F-4D21-83FB-502E3BFE5F8A}"
    F16_370GAL = "{8D399DDA-FF81-4F14-904D-099B34FE7918}"

# Easier to read
content = modify_pylon(content, "Fighter-1", 1, Weapons.AIM_9X)
```

### 3. Set Realistic Quantities

```python
# Aircraft-specific realistic quantities
REALISTIC_LOADOUTS = {
    "F-16C_50": {
        "chaff": 120,   # 2x60 chaff cartridges
        "flare": 60,    # 2x30 flare cartridges
        "gun": 511,     # M61 Vulcan max capacity
        "fuel_internal": 3175,  # kg
        "fuel_with_2x370": 5000  # approximate
    },
    "FA-18C_hornet": {
        "chaff": 60,
        "flare": 60,
        "gun": 578,     # M61A1
        "fuel_internal": 4900,
        "fuel_with_3x480": 7500
    },
    "A-10C": {
        "chaff": 240,
        "flare": 120,
        "gun": 1174,    # GAU-8 Avenger
        "fuel_internal": 4853,
        "fuel_with_3xtanks": 6500
    }
}
```

### 4. Preserve Loadout When Modifying Positions

```python
# When moving units, loadouts are preserved
from miz_modification.units.modify import modify_unit_position

# Position change doesn't affect loadout
content = modify_unit_position(
    content,
    "Fighter-1",
    unit_index=1,
    x=-50000,
    y=30000
)

# Loadout remains unchanged - no need to reapply
```

---

## Common Patterns

### Pattern 1: Mission Role Loadouts

```python
def configure_flight_by_role(content, group_name, role):
    """Configure entire flight based on mission role."""

    if role == "CAP":
        # All aircraft: Air-to-air configuration
        loadout = {
            "pylons": {
                1: "{5CE2FF2A-645A-4197-B48D-8720AC69394F}",  # AIM-9X
                2: "{40EF17B7-F508-45de-8566-6FFECC0C1AB8}",  # AIM-120C
                3: "{8D399DDA-FF81-4F14-904D-099B34FE7918}",  # Tank
                8: "{40EF17B7-F508-45de-8566-6FFECC0C1AB8}",  # AIM-120C
                9: "{5CE2FF2A-645A-4197-B48D-8720AC69394F}",  # AIM-9X
            }
        }
    elif role == "STRIKE":
        # All aircraft: Air-to-ground configuration
        loadout = {
            "pylons": {
                1: "{5CE2FF2A-645A-4197-B48D-8720AC69394F}",  # AIM-9X (self-defense)
                2: "{51F9AAE5-964F-4D21-83FB-502E3BFE5F8A}",  # GBU-12
                3: "{51F9AAE5-964F-4D21-83FB-502E3BFE5F8A}",  # GBU-12
                7: "{51F9AAE5-964F-4D21-83FB-502E3BFE5F8A}",  # GBU-12
                8: "{51F9AAE5-964F-4D21-83FB-502E3BFE5F8A}",  # GBU-12
                9: "{5CE2FF2A-645A-4197-B48D-8720AC69394F}",  # AIM-9X (self-defense)
            }
        }

    # Apply to all units in group
    for unit_idx in range(1, 5):  # 4-ship flight
        for pylon_num, clsid in loadout["pylons"].items():
            content = modify_pylon(content, group_name, pylon_num, clsid, unit_idx)

    return content

# Usage
content = configure_flight_by_role(content, "Strike-1", "STRIKE")
```

### Pattern 2: Progressive Loadout Building

```python
# Build loadout step by step for clarity
def build_multirole_loadout(content, group_name, unit_index=1):
    """Build a multirole loadout progressively."""

    # Step 1: Self-defense A/A missiles
    content = modify_pylon(content, group_name, 1, Weapons.AIM_9X, unit_index)
    content = modify_pylon(content, group_name, 9, Weapons.AIM_9X, unit_index)

    # Step 2: BVR missiles
    content = modify_pylon(content, group_name, 2, Weapons.AIM_120C, unit_index)
    content = modify_pylon(content, group_name, 8, Weapons.AIM_120C, unit_index)

    # Step 3: A/G weapons
    content = modify_pylon(content, group_name, 4, Weapons.GBU_12, unit_index)
    content = modify_pylon(content, group_name, 6, Weapons.GBU_12, unit_index)

    # Step 4: Fuel tanks
    content = modify_pylon(content, group_name, 3, Weapons.F16_370GAL, unit_index)
    content = modify_pylon(content, group_name, 7, Weapons.F16_370GAL, unit_index)

    # Step 5: Countermeasures and gun
    content = modify_countermeasures(content, group_name, chaff=120, flare=60, unit_index=unit_index)
    content = modify_gun_ammo(content, group_name, 511, unit_index)
    content = modify_fuel(content, group_name, 5000.0, unit_index)

    return content
```

### Pattern 3: Loadout Inspection and Modification

```python
from miz_modification.loadouts.list import list_loadout
from miz_modification.loadouts.modify import modify_pylon

# Inspect current loadout
loadout = list_loadout(content, "Fighter-1", 1)

# Find and replace specific weapons
for pylon_num, pylon_data in loadout['pylons'].items():
    if pylon_data['CLSID'] == Weapons.AIM_9M:
        # Replace AIM-9M with AIM-9X
        content = modify_pylon(content, "Fighter-1", pylon_num, Weapons.AIM_9X, 1)
        print(f"Upgraded pylon {pylon_num}: AIM-9M -> AIM-9X")
```

### Pattern 4: Fuel Planning

```python
def calculate_fuel_requirement(distance_nm, speed_kts, loiter_minutes=30):
    """Calculate fuel requirement for mission."""
    # Simple fuel burn estimation
    cruise_burn_rate = 2000  # kg/hour at cruise
    loiter_burn_rate = 1500  # kg/hour at loiter

    # Transit time
    transit_hours = (distance_nm * 2) / speed_kts  # Round trip
    transit_fuel = transit_hours * cruise_burn_rate

    # Loiter time
    loiter_hours = loiter_minutes / 60
    loiter_fuel = loiter_hours * loiter_burn_rate

    # Reserve (20%)
    total_fuel = (transit_fuel + loiter_fuel) * 1.2

    return total_fuel

# Usage
mission_distance = 150  # nm
fuel_needed = calculate_fuel_requirement(mission_distance, 450, loiter_minutes=45)
print(f"Fuel required: {fuel_needed:.0f}kg")

# Set fuel accordingly
content = modify_fuel(content, "Fighter-1", fuel_needed, unit_index=1)
```

---

## See Also

- [Unit Operations](units.md) - Modify unit properties
- [Group Operations](groups.md) - Manage groups
- [DCS Stores/Weapons List](https://www.airgoons.com/w/DCS_Reference/Stores_List) - Complete CLSID reference
- [Mission Analysis](mission-analysis.md) - Inspect mission loadouts
