# Unit Operations

Complete reference for all unit-level operations in the miz-modification library.

## Overview

Unit operations allow you to add, remove, and modify individual units within existing groups. While group operations work on entire formations, unit operations provide fine-grained control over specific aircraft, vehicles, ships, or helicopters.

**Module**: `miz_modification.units`

---

## Create Operations

### `add_unit_to_group()`

Add a new unit to an existing group.

**Module**: `miz_modification.units.add`

**Signature**:
```python
def add_unit_to_group(mission_content: str, group_name: str, unit_type: str,
                     position_offset: Optional[Dict[str, float]] = None,
                     **kwargs) -> str
```

**Parameters**:

| Name | Type | Required | Description |
|------|------|----------|-------------|
| `mission_content` | `str` | Yes | Raw mission file content as string |
| `group_name` | `str` | Yes | Name of group to add unit to |
| `unit_type` | `str` | Yes | DCS unit type (e.g., "F-16C_50", "UH-1H") |
| `position_offset` | `dict` | No | Position offset from group position `{"x": dx, "y": dy}` |
| `**kwargs` | various | No | Optional unit properties (see below) |

**Optional Unit Properties** (kwargs):

| Property | Type | Default | Description |
|----------|------|---------|-------------|
| `skill` | `str` | "Average" | Skill level (Rookie, Trained, Average, Good, High, Excellent) |
| `speed` | `float` | varies | Speed in m/s (default depends on category) |
| `alt` | `float` | varies | Altitude in meters (aircraft/heli only) |
| `heading` | `float` | 0.0 | Heading in radians |
| `alt_type` | `str` | "BARO" | Altitude type: "BARO" or "RADIO" |

**Returns**:

| Type | Description |
|------|-------------|
| `str` | Modified mission content with new unit added |

**Usage Example**:

```python
from miz_modification.units.add import add_unit_to_group
from miz_modification.parsing.miz_parser import MizParser

parser = MizParser("input.miz")
parser.extract()
content = parser.get_mission_content()

# Add F-16 at same position as group
content = add_unit_to_group(content, "Fighter-1", "F-16C_50")

# Add F-16 offset 100m east, 50m north with custom properties
content = add_unit_to_group(
    content,
    "Fighter-1",
    "F-16C_50",
    position_offset={"x": 100, "y": 50},
    skill="Good",
    alt=3000,
    speed=250
)

parser.write_mission_content(content)
parser.repackage("output.miz")
```

**File Wrapper**:

```python
from miz_modification.units.add import add_unit_to_group_file

add_unit_to_group_file(
    input_miz="input.miz",
    output_miz="output.miz",
    group_name="Fighter-1",
    unit_type="F-16C_50",
    position_offset={"x": 100, "y": 0},
    skill="Good"
)
```

**Error Conditions**:

- `ValueError`: Group not found in mission
- `ValueError`: Invalid unit_type
- `ValueError`: Group has no position information

**Related Operations**:
- `add_multiple_units_to_group()` - Add multiple units at once
- `groups.add_group()` - Add entire new group

---

### `add_multiple_units_to_group()`

Add multiple units to a group with automatic spacing.

**Module**: `miz_modification.units.add`

**Signature**:
```python
def add_multiple_units_to_group(mission_content: str, group_name: str,
                                units: list, spacing: float = 50.0) -> str
```

**Parameters**:

| Name | Type | Required | Description |
|------|------|----------|-------------|
| `mission_content` | `str` | Yes | Raw mission file content as string |
| `group_name` | `str` | Yes | Name of group to add units to |
| `units` | `list[str]` | Yes | List of unit type strings to add |
| `spacing` | `float` | No | Spacing between units in meters (default: 50m) |

**Returns**:

| Type | Description |
|------|-------------|
| `str` | Modified mission content with all units added |

**Usage Example**:

```python
from miz_modification.units.add import add_multiple_units_to_group

# Add 3 F-16s with 50m spacing
units_to_add = ["F-16C_50", "F-16C_50", "F-16C_50"]
content = add_multiple_units_to_group(content, "Fighter-1", units_to_add)

# Add mixed unit types with 100m spacing
units_to_add = ["F-16C_50", "F-15C", "F-16C_50"]
content = add_multiple_units_to_group(content, "Fighter-1", units_to_add, spacing=100.0)
```

**File Wrapper**:

```python
from miz_modification.units.add import add_multiple_units_to_group_file

units_to_add = ["F-16C_50", "F-16C_50", "F-16C_50"]
add_multiple_units_to_group_file(
    "input.miz",
    "output.miz",
    "Fighter-1",
    units_to_add,
    spacing=100.0
)
```

**Related Operations**:
- `add_unit_to_group()` - Add single unit with full control
- `groups.add_group()` - Add entire new group

---

## Delete Operations

### `remove_unit_from_group()`

Remove a unit from a group by its index.

**Module**: `miz_modification.units.remove`

**Signature**:
```python
def remove_unit_from_group(mission_content: str, group_name: str, unit_index: int) -> str
```

**Parameters**:

| Name | Type | Required | Description |
|------|------|----------|-------------|
| `mission_content` | `str` | Yes | Raw mission file content as string |
| `group_name` | `str` | Yes | Name of group containing the unit |
| `unit_index` | `int` | Yes | Index of unit to remove (1, 2, 3, etc.) |

**Returns**:

| Type | Description |
|------|-------------|
| `str` | Modified mission content with unit removed |

**Usage Example**:

```python
from miz_modification.units.remove import remove_unit_from_group

# Remove the 2nd unit from Fighter-1 group
content = remove_unit_from_group(content, "Fighter-1", 2)
```

**File Wrapper**:

```python
from miz_modification.units.remove import remove_unit_from_group_file

remove_unit_from_group_file("input.miz", "output.miz", "Fighter-1", 2)
```

**Error Conditions**:

- `ValueError`: Group not found
- `ValueError`: Unit index doesn't exist in group

---

### `remove_unit_by_name()`

Remove a unit by its name from mission.

**Module**: `miz_modification.units.remove`

**Signature**:
```python
def remove_unit_by_name(mission_content: str, unit_name: str) -> str
```

**Parameters**:

| Name | Type | Required | Description |
|------|------|----------|-------------|
| `mission_content` | `str` | Yes | Raw mission file content as string |
| `unit_name` | `str` | Yes | Name of unit to remove |

**Returns**:

| Type | Description |
|------|-------------|
| `str` | Modified mission content with unit removed |

**Usage Example**:

```python
from miz_modification.units.remove import remove_unit_by_name

# Remove specific unit
content = remove_unit_by_name(content, "Fighter-1-2")
```

**File Wrapper**:

```python
from miz_modification.units.remove import remove_unit_by_name_file

remove_unit_by_name_file("input.miz", "output.miz", "Fighter-1-2")
```

**Error Conditions**:

- `ValueError`: Unit not found in mission

---

### `remove_units_by_type()`

Remove all units of a specific type from mission.

**Module**: `miz_modification.units.remove`

**Signature**:
```python
def remove_units_by_type(mission_content: str, unit_type: str) -> str
```

**Parameters**:

| Name | Type | Required | Description |
|------|------|----------|-------------|
| `mission_content` | `str` | Yes | Raw mission file content as string |
| `unit_type` | `str` | Yes | Unit type to remove (exact match) |

**Returns**:

| Type | Description |
|------|-------------|
| `str` | Modified mission content with all matching units removed |

**Usage Example**:

```python
from miz_modification.units.remove import remove_units_by_type

# Remove all F-16Cs
content = remove_units_by_type(content, "F-16C_50")

# Remove all M-1 Abrams tanks
content = remove_units_by_type(content, "M-1 Abrams")
```

**File Wrapper**:

```python
from miz_modification.units.remove import remove_units_by_type_file

remove_units_by_type_file("input.miz", "output.miz", "F-16C_50")
```

---

### `remove_all_units_from_group()`

Remove all units from a group (leaves group with empty units section).

**Module**: `miz_modification.units.remove`

**Signature**:
```python
def remove_all_units_from_group(mission_content: str, group_name: str) -> str
```

**Parameters**:

| Name | Type | Required | Description |
|------|------|----------|-------------|
| `mission_content` | `str` | Yes | Raw mission file content as string |
| `group_name` | `str` | Yes | Name of group to clear |

**Returns**:

| Type | Description |
|------|-------------|
| `str` | Modified mission content with all units removed from group |

**Usage Example**:

```python
from miz_modification.units.remove import remove_all_units_from_group

# Clear all units from a group
content = remove_all_units_from_group(content, "Fighter-1")
```

**File Wrapper**:

```python
from miz_modification.units.remove import remove_all_units_from_group_file

remove_all_units_from_group_file("input.miz", "output.miz", "Fighter-1")
```

**Note**: This leaves the group with an empty units section. To remove the entire group, use `groups.remove.remove_group()` instead.

**Error Conditions**:

- `ValueError`: Group not found

---

## Modify Operations

### `modify_unit_skill()`

Modify a unit's skill level.

**Module**: `miz_modification.units.modify`

**Signature**:
```python
def modify_unit_skill(mission_content: str, unit_name: str, skill: str) -> str
```

**Parameters**:

| Name | Type | Required | Description |
|------|------|----------|-------------|
| `mission_content` | `str` | Yes | Raw mission file content as string |
| `unit_name` | `str` | Yes | Name of unit to modify |
| `skill` | `str` | Yes | New skill level |

**Valid Skill Levels**:
- `"Rookie"` - Beginner AI
- `"Trained"` - Basic training
- `"Average"` - Standard AI
- `"Good"` - Above average
- `"High"` - Skilled AI
- `"Excellent"` - Expert AI
- `"Random"` - Randomly selected
- `"Player"` - Player-controlled unit

**Returns**:

| Type | Description |
|------|-------------|
| `str` | Modified mission content with updated skill |

**Usage Example**:

```python
from miz_modification.units.modify import modify_unit_skill

# Make unit more challenging
content = modify_unit_skill(content, "Fighter-1-1", "Excellent")
```

**File Wrapper**:

```python
from miz_modification.units.modify import modify_unit_skill_file

modify_unit_skill_file("input.miz", "output.miz", "Fighter-1-1", "Good")
```

**Error Conditions**:

- `ValueError`: Unit not found
- `ValueError`: Invalid skill level

---

### `modify_unit_position()`

Modify a unit's position coordinates.

**Module**: `miz_modification.units.modify`

**Signature**:
```python
def modify_unit_position(mission_content: str, unit_name: str, new_position: Dict[str, float]) -> str
```

**Parameters**:

| Name | Type | Required | Description |
|------|------|----------|-------------|
| `mission_content` | `str` | Yes | Raw mission file content as string |
| `unit_name` | `str` | Yes | Name of unit to modify |
| `new_position` | `dict` | Yes | Dict with 'x' and 'y' coordinates in meters |

**Returns**:

| Type | Description |
|------|-------------|
| `str` | Modified mission content with updated position |

**Usage Example**:

```python
from miz_modification.units.modify import modify_unit_position

# Move unit to new coordinates
new_pos = {"x": -50000, "y": 30000}
content = modify_unit_position(content, "Fighter-1-1", new_pos)
```

**File Wrapper**:

```python
from miz_modification.units.modify import modify_unit_position_file

modify_unit_position_file(
    "input.miz",
    "output.miz",
    "Fighter-1-1",
    {"x": -50000, "y": 30000}
)
```

**Error Conditions**:

- `ValueError`: Unit not found
- `ValueError`: new_position missing 'x' or 'y' keys

---

### `modify_unit_heading()`

Modify a unit's heading (direction it's facing).

**Module**: `miz_modification.units.modify`

**Signature**:
```python
def modify_unit_heading(mission_content: str, unit_name: str, heading: float) -> str
```

**Parameters**:

| Name | Type | Required | Description |
|------|------|----------|-------------|
| `mission_content` | `str` | Yes | Raw mission file content as string |
| `unit_name` | `str` | Yes | Name of unit to modify |
| `heading` | `float` | Yes | New heading in radians (0=North, π/2=East, π=South, 3π/2=West) |

**Returns**:

| Type | Description |
|------|-------------|
| `str` | Modified mission content with updated heading |

**Usage Example**:

```python
import math
from miz_modification.units.modify import modify_unit_heading

# Point unit East
content = modify_unit_heading(content, "Fighter-1-1", math.pi/2)

# Point unit South
content = modify_unit_heading(content, "Tank-1-1", math.pi)
```

**File Wrapper**:

```python
import math
from miz_modification.units.modify import modify_unit_heading_file

modify_unit_heading_file("input.miz", "output.miz", "Fighter-1-1", math.pi/2)
```

**Error Conditions**:

- `ValueError`: Unit not found

---

### `modify_unit_loadout()`

Modify a unit's weapon loadout (aircraft/helicopters only).

**Module**: `miz_modification.units.modify`

**Signature**:
```python
def modify_unit_loadout(mission_content: str, unit_name: str, loadout: Dict) -> str
```

**Parameters**:

| Name | Type | Required | Description |
|------|------|----------|-------------|
| `mission_content` | `str` | Yes | Raw mission file content as string |
| `unit_name` | `str` | Yes | Name of unit to modify |
| `loadout` | `dict` | Yes | Loadout configuration (see schema below) |

**Loadout Schema**:

```python
{
    "pylons": {
        1: "{LAU-115 - AIM-7MH}",  # pylon_num: weapon_CLSID
        7: "{LAU-115 - AIM-7MH}",
        2: "{LAU-115 - AIM-9M}",
        # ... more pylons
    },
    "fuel": 3249,    # Optional: fuel quantity in kg
    "chaff": 60,     # Optional: chaff count
    "flare": 60,     # Optional: flare count
    "gun": 100       # Optional: gun ammo percentage
}
```

**Returns**:

| Type | Description |
|------|-------------|
| `str` | Modified mission content with updated loadout |

**Usage Example**:

```python
from miz_modification.units.modify import modify_unit_loadout

# Air-to-air loadout for F-16
loadout = {
    "pylons": {
        1: "{LAU-115 - AIM-7MH}",
        7: "{LAU-115 - AIM-7MH}",
        2: "{LAU-115 - AIM-9M}",
        8: "{LAU-115 - AIM-9M}",
        3: "{F-16C bl.50 wing tank}",
        9: "{F-16C bl.50 wing tank}"
    },
    "fuel": 3000,
    "chaff": 120,
    "flare": 120
}

content = modify_unit_loadout(content, "Fighter-1-1", loadout)
```

**File Wrapper**:

```python
from miz_modification.units.modify import modify_unit_loadout_file

loadout = {
    "pylons": {1: "{LAU-115 - AIM-7MH}", 7: "{LAU-115 - AIM-7MH}"},
    "fuel": 3000
}

modify_unit_loadout_file("input.miz", "output.miz", "Fighter-1-1", loadout)
```

**CLSID Reference**: For valid CLSID values, see [DCS Stores/Weapons List](https://www.airgoons.com/w/DCS_Reference/Stores_List)

**Error Conditions**:

- `ValueError`: Unit not found
- `ValueError`: Unit has no payload section (not aircraft/helicopter)

**Related Operations**:
- `loadouts.modify_pylon()` - Modify single pylon

---

### `modify_unit_type()`

Change a unit's type (e.g., change F-16 to F-15).

**Module**: `miz_modification.units.modify`

**Signature**:
```python
def modify_unit_type(mission_content: str, unit_name: str, new_unit_type: str) -> str
```

**Parameters**:

| Name | Type | Required | Description |
|------|------|----------|-------------|
| `mission_content` | `str` | Yes | Raw mission file content as string |
| `unit_name` | `str` | Yes | Name of unit to modify |
| `new_unit_type` | `str` | Yes | New DCS unit type string |

**Returns**:

| Type | Description |
|------|-------------|
| `str` | Modified mission content with updated unit type |

**Usage Example**:

```python
from miz_modification.units.modify import modify_unit_type

# Change F-16 to F-15
content = modify_unit_type(content, "Fighter-1-1", "F-15C")

# Change tank type
content = modify_unit_type(content, "Tank-1-1", "T-72B")
```

**File Wrapper**:

```python
from miz_modification.units.modify import modify_unit_type_file

modify_unit_type_file("input.miz", "output.miz", "Fighter-1-1", "F-15C")
```

**Warning**: Changing unit type may create invalid loadout configurations. Consider clearing or updating loadout after type change.

**Error Conditions**:

- `ValueError`: Unit not found

---

### `modify_unit_name()`

Rename a unit.

**Module**: `miz_modification.units.modify`

**Signature**:
```python
def modify_unit_name(mission_content: str, old_name: str, new_name: str) -> str
```

**Parameters**:

| Name | Type | Required | Description |
|------|------|----------|-------------|
| `mission_content` | `str` | Yes | Raw mission file content as string |
| `old_name` | `str` | Yes | Current unit name |
| `new_name` | `str` | Yes | New unit name |

**Returns**:

| Type | Description |
|------|-------------|
| `str` | Modified mission content with renamed unit |

**Usage Example**:

```python
from miz_modification.units.modify import modify_unit_name

# Rename unit
content = modify_unit_name(content, "Fighter-1-1", "Viper-Lead")
```

**File Wrapper**:

```python
from miz_modification.units.modify import modify_unit_name_file

modify_unit_name_file("input.miz", "output.miz", "Fighter-1-1", "Viper-Lead")
```

**Error Conditions**:

- `ValueError`: Unit not found

---

## Advanced Usage

### Chaining Unit Operations

```python
from miz_modification.parsing.miz_parser import MizParser
from miz_modification.units.add import add_unit_to_group
from miz_modification.units.modify import modify_unit_skill, modify_unit_loadout

parser = MizParser("input.miz")
parser.extract()
content = parser.get_mission_content()

# Add unit
content = add_unit_to_group(content, "Fighter-1", "F-16C_50", position_offset={"x": 100, "y": 0})

# Modify the new unit (typically named "Fighter-1-5" if there were 4 units)
content = modify_unit_skill(content, "Fighter-1-5", "Excellent")

loadout = {
    "pylons": {1: "{LAU-115 - AIM-7MH}", 7: "{LAU-115 - AIM-7MH}"},
    "fuel": 3000
}
content = modify_unit_loadout(content, "Fighter-1-5", loadout)

parser.write_mission_content(content)
parser.repackage("output.miz")
```

### Building Custom Formations

```python
# Create 4-ship finger four formation
from miz_modification.units.add import add_unit_to_group

# Lead already exists, add wingmen
formations = [
    {"x": 50, "y": -50},   # Wingman right
    {"x": 100, "y": 0},    # Element lead
    {"x": 150, "y": -50}   # Element wingman
]

for offset in formations:
    content = add_unit_to_group(
        content,
        "Fighter-1",
        "F-16C_50",
        position_offset=offset,
        alt=8000,
        speed=200
    )
```

### Batch Unit Modifications

```python
from miz_modification.units.modify import modify_unit_skill
from miz_modification.groups.list import list_all_groups

# Get all units in a group
groups = list_all_groups(content)
fighter_group = next(g for g in groups["blue"] if g["name"] == "Fighter-1")

# Upgrade all units to Excellent skill
for i in range(1, fighter_group["unit_count"] + 1):
    unit_name = f"Fighter-1-{i}"
    try:
        content = modify_unit_skill(content, unit_name, "Excellent")
    except ValueError:
        # Unit might not exist or have different naming
        continue
```

---

## Best Practices

### 1. Verify Unit Names Before Modifying

```python
from miz_modification.groups.list import get_group_info

# Get unit names in group before modifying
group_info = get_group_info(content, "Fighter-1")
unit_names = [unit["name"] for unit in group_info.get("units", [])]
print(f"Units: {unit_names}")

# Now modify with confidence
if "Fighter-1-2" in unit_names:
    content = modify_unit_skill(content, "Fighter-1-2", "Good")
```

### 2. Use Position Offsets for Formation

```python
# Keep units in formation when adding
offsets = [
    {"x": 50, "y": 0},     # Right wing
    {"x": -50, "y": 0},    # Left wing
    {"x": 0, "y": -100}    # Trailing
]

for offset in offsets:
    content = add_unit_to_group(content, "Fighter-1", "F-16C_50", position_offset=offset)
```

### 3. Clear Loadout When Changing Aircraft Type

```python
from miz_modification.units.modify import modify_unit_type, modify_unit_loadout

# Change type
content = modify_unit_type(content, "Fighter-1-1", "F-15C")

# Clear incompatible loadout
empty_loadout = {"pylons": {}, "fuel": 3000}
content = modify_unit_loadout(content, "Fighter-1-1", empty_loadout)
```

### 4. Preserve Existing Properties

When modifying loadout, preserve properties you're not changing:

```python
# Modify only pylons, keep fuel/chaff/flare unchanged
minimal_loadout = {
    "pylons": {1: "{LAU-115 - AIM-7MH}", 7: "{LAU-115 - AIM-7MH}"}
    # fuel, chaff, flare will be preserved from existing unit
}
content = modify_unit_loadout(content, "Fighter-1-1", minimal_loadout)
```

---

## Common Patterns

### Pattern 1: Clone and Modify Unit

```python
# Add new unit similar to existing one
content = add_unit_to_group(content, "Fighter-1", "F-16C_50", position_offset={"x": 100, "y": 0})

# Assuming new unit is Fighter-1-5
content = modify_unit_skill(content, "Fighter-1-5", "Good")
content = modify_unit_heading(content, "Fighter-1-5", math.pi/4)
```

### Pattern 2: Replace Unit Type in Formation

```python
# Remove old unit
content = remove_unit_from_group(content, "Fighter-1", 2)

# Add new type in same spot
content = add_unit_to_group(
    content,
    "Fighter-1",
    "F-15C",
    position_offset={"x": 50, "y": -50},
    skill="Good"
)
```

### Pattern 3: Standardize Unit Properties

```python
# Make all units in group same skill level
for i in range(1, 5):
    try:
        content = modify_unit_skill(content, f"Fighter-1-{i}", "Average")
    except ValueError:
        continue  # Unit might not exist
```

---

## See Also

- [Group Operations](groups.md) - Work with entire groups
- [Waypoint Operations](waypoints.md) - Manage unit routes
- [Loadout Operations](loadouts.md) - Advanced weapon configuration
- [Mission Analysis](mission-analysis.md) - Inspect unit properties
