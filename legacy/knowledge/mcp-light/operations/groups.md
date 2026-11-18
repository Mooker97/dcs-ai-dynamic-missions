# Group Operations

Complete reference for all group-level operations in the miz-modification library.

## Overview

Group operations allow you to add, remove, modify, duplicate, and inspect entire groups of units in mission files. Groups are the primary organizational unit in DCS missions - they contain multiple units (aircraft, vehicles, ships) that operate together.

**Module**: `miz_modification.groups`

---

## Read-Only Operations

### `list_all_groups()`

List all groups in a mission by coalition.

**Module**: `miz_modification.groups.list`

**Signature**:
```python
def list_all_groups(mission_content: str) -> Dict[str, List[Dict]]
```

**Parameters**:

| Name | Type | Required | Description |
|------|------|----------|-------------|
| `mission_content` | `str` | Yes | Raw mission file content as string |

**Returns**:

```python
{
    "blue": [
        {
            "name": "Viper 1",
            "country": "USA",
            "category": "plane",
            "unit_count": 4
        },
        ...
    ],
    "red": [...]
}
```

**Usage Example**:

```python
from miz_modification.groups.list import list_all_groups
from miz_modification.parsing.miz_parser import MizParser

parser = MizParser("mission.miz")
parser.extract()
content = parser.get_mission_content()

groups = list_all_groups(content)
print(f"Blue groups: {len(groups['blue'])}")
print(f"Red groups: {len(groups['red'])}")

# List all blue aircraft groups
for group in groups['blue']:
    if group['category'] == 'plane':
        print(f"  {group['name']}: {group['unit_count']} aircraft")
```

**File Wrapper**:

```python
from miz_modification.groups.list import list_all_groups_file

groups = list_all_groups_file("mission.miz")
```

**Related Operations**:
- `find_group_by_name()` - Find specific group
- `get_group_info()` - Get detailed group information

---

## Create Operations

### `add_group()`

Add a new group with units and optional waypoints to a mission.

**Module**: `miz_modification.groups.add`

**Signature**:
```python
def add_group(mission_content: str, coalition: str, group_data: Dict) -> str
```

**Parameters**:

| Name | Type | Required | Description |
|------|------|----------|-------------|
| `mission_content` | `str` | Yes | Raw mission file content as string |
| `coalition` | `str` | Yes | Coalition: "blue" or "red" |
| `group_data` | `dict` | Yes | Group configuration (see schema below) |

**Group Data Schema**:

```python
{
    "name": str,                    # Group name (must be unique)
    "country": str,                 # Country ID (e.g., "USA", "Russia")
    "category": str,                # "plane", "helicopter", "ship", "vehicle"
    "units": [                      # List of units in group
        {
            "type": str,            # Aircraft/vehicle type (e.g., "F-16C_50")
            "name": str,            # Unit name (optional, auto-generated if omitted)
            "x": float,             # X coordinate
            "y": float,             # Y coordinate
            "alt": float,           # Altitude in meters (aircraft/heli only)
            "speed": float,         # Speed in m/s (optional)
            "heading": float        # Heading in radians (optional)
        }
    ],
    "waypoints": [                  # List of waypoints (optional)
        {
            "x": float,             # X coordinate
            "y": float,             # Y coordinate
            "alt": float,           # Altitude in meters
            "speed": float,         # Speed in m/s
            "action": str           # "Turning Point", "FlyOverPoint", etc.
        }
    ],
    "frequency": float,             # Radio frequency (optional)
    "modulation": int               # 0=AM, 1=FM (optional)
}
```

**Returns**:

| Type | Description |
|------|-------------|
| `str` | Modified mission content with new group added |

**Usage Example**:

```python
from miz_modification.groups.add import add_group
from miz_modification.parsing.miz_parser import MizParser

# Define group data
group_data = {
    "name": "Viper 1",
    "country": "USA",
    "category": "plane",
    "units": [
        {
            "type": "F-16C_50",
            "x": -280000,
            "y": 615000,
            "alt": 8000,
            "speed": 200,
            "heading": 0
        },
        {
            "type": "F-16C_50",
            "x": -280050,
            "y": 614950,
            "alt": 8000,
            "speed": 200,
            "heading": 0
        }
    ],
    "waypoints": [
        {
            "x": -280000,
            "y": 615000,
            "alt": 8000,
            "speed": 200,
            "action": "Turning Point"
        },
        {
            "x": -250000,
            "y": 630000,
            "alt": 8000,
            "speed": 250,
            "action": "Turning Point"
        }
    ],
    "frequency": 251.0,
    "modulation": 0  # AM
}

# Add group
parser = MizParser("input.miz")
parser.extract()
content = parser.get_mission_content()

content = add_group(content, "blue", group_data)

parser.write_mission_content(content)
parser.repackage("output.miz")
```

**File Wrapper**:

```python
from miz_modification.groups.add import add_group_file

add_group_file(
    input_miz="input.miz",
    output_miz="output.miz",
    coalition="blue",
    group_data=group_data
)
```

**Error Conditions**:

- `ValueError`: Invalid coalition (not "blue" or "red")
- `ValueError`: Duplicate group name
- `ValueError`: Invalid aircraft/vehicle type
- `ValueError`: Invalid category
- `ValueError`: Missing required fields in group_data
- `ValueError`: Invalid coordinates (out of map bounds)

**Related Operations**:
- `duplicate_group()` - Clone existing group
- `modify_group()` - Modify existing group properties

---

### `duplicate_group()`

Clone an existing group with a new name and optional modifications.

**Module**: `miz_modification.groups.duplicate`

**Signature**:
```python
def duplicate_group(mission_content: str, source_group_name: str,
                   new_group_name: str, offset: Optional[Dict[str, float]] = None,
                   modifications: Optional[Dict] = None) -> str
```

**Parameters**:

| Name | Type | Required | Description |
|------|------|----------|-------------|
| `mission_content` | `str` | Yes | Raw mission file content as string |
| `source_group_name` | `str` | Yes | Name of group to duplicate |
| `new_group_name` | `str` | Yes | Name for new group (must be unique) |
| `offset` | `dict` | No | Position offset `{"x": dx, "y": dy}` |
| `modifications` | `dict` | No | Properties to modify (frequency, country, etc.) |

**Returns**:

| Type | Description |
|------|-------------|
| `str` | Modified mission content with duplicated group |

**Usage Example**:

```python
from miz_modification.groups.duplicate import duplicate_group

# Duplicate with position offset
content = duplicate_group(
    content,
    source_group_name="Enemy SAM 1",
    new_group_name="Enemy SAM 2",
    offset={"x": 50000, "y": 10000}  # 50km east, 10km north
)

# Duplicate with modifications
content = duplicate_group(
    content,
    source_group_name="Viper 1",
    new_group_name="Viper 2",
    offset={"x": -1000, "y": -1000},
    modifications={
        "frequency": 252.0,  # Different radio frequency
        "country": "France"  # Different country
    }
)
```

**File Wrapper**:

```python
from miz_modification.groups.duplicate import duplicate_group_file

duplicate_group_file(
    input_miz="input.miz",
    output_miz="output.miz",
    source_group_name="Viper 1",
    new_group_name="Viper 2",
    offset={"x": -1000, "y": -1000}
)
```

**Error Conditions**:

- `ValueError`: Source group not found
- `ValueError`: New group name already exists
- `ValueError`: Invalid offset coordinates
- `ValueError`: Invalid modification properties

**Related Operations**:
- `add_group()` - Add new group from scratch
- `modify_group()` - Modify existing group

---

## Delete Operations

### `remove_group()`

Remove a specific group by name.

**Module**: `miz_modification.groups.remove`

**Signature**:
```python
def remove_group(mission_content: str, group_name: str) -> str
```

**Parameters**:

| Name | Type | Required | Description |
|------|------|----------|-------------|
| `mission_content` | `str` | Yes | Raw mission file content as string |
| `group_name` | `str` | Yes | Name of group to remove |

**Returns**:

| Type | Description |
|------|-------------|
| `str` | Modified mission content with group removed |

**Usage Example**:

```python
from miz_modification.groups.remove import remove_group

content = remove_group(content, "Enemy SAM 1")
```

**File Wrapper**:

```python
from miz_modification.groups.remove import remove_group_file

remove_group_file("input.miz", "output.miz", "Enemy SAM 1")
```

**Error Conditions**:

- `ValueError`: Group not found

---

### `remove_groups_by_type()`

Remove all groups containing specific unit types.

**Module**: `miz_modification.groups.remove`

**Signature**:
```python
def remove_groups_by_type(mission_content: str, unit_types: List[str]) -> str
```

**Parameters**:

| Name | Type | Required | Description |
|------|------|----------|-------------|
| `mission_content` | `str` | Yes | Raw mission file content as string |
| `unit_types` | `list[str]` | Yes | List of unit type keywords (e.g., ["ship", "SA-10"]) |

**Returns**:

| Type | Description |
|------|-------------|
| `str` | Modified mission content with matching groups removed |

**Usage Example**:

```python
from miz_modification.groups.remove import remove_groups_by_type

# Remove all ship groups
content = remove_groups_by_type(content, ["ship"])

# Remove specific SAM types
content = remove_groups_by_type(content, ["SA-10", "SA-20"])

# Remove all helicopters
content = remove_groups_by_type(content, ["UH-", "AH-", "Mi-", "Ka-"])
```

**File Wrapper**:

```python
from miz_modification.groups.remove import remove_groups_by_type_file

remove_groups_by_type_file("input.miz", "output.miz", ["ship"])
```

**How It Works**:

The function searches for groups containing units whose type includes any of the specified keywords. The search is case-insensitive and matches partial strings.

**Related Operations**:
- `remove_group()` - Remove single group by name

---

## Modify Operations

### `modify_group()`

Modify properties of an existing group.

**Module**: `miz_modification.groups.modify`

**Signature**:
```python
def modify_group(mission_content: str, group_name: str,
                modifications: Dict) -> str
```

**Parameters**:

| Name | Type | Required | Description |
|------|------|----------|-------------|
| `mission_content` | `str` | Yes | Raw mission file content as string |
| `group_name` | `str` | Yes | Name of group to modify |
| `modifications` | `dict` | Yes | Properties to change (see modifiable properties) |

**Modifiable Properties**:

| Property | Type | Description |
|----------|------|-------------|
| `frequency` | `float` | Radio frequency in MHz |
| `modulation` | `int` | Radio modulation (0=AM, 1=FM) |
| `country` | `str` | Country ID |
| `name` | `str` | Group name (renames the group) |
| `hidden` | `bool` | Whether group is hidden on map |
| `uncontrolled` | `bool` | Whether group starts uncontrolled |

**Returns**:

| Type | Description |
|------|-------------|
| `str` | Modified mission content with updated group properties |

**Usage Example**:

```python
from miz_modification.groups.modify import modify_group

# Change radio frequency
content = modify_group(
    content,
    "Viper 1",
    {"frequency": 252.0, "modulation": 0}
)

# Rename group
content = modify_group(
    content,
    "Old Name",
    {"name": "New Name"}
)

# Change country
content = modify_group(
    content,
    "NATO Fighter 1",
    {"country": "France"}
)
```

**File Wrapper**:

```python
from miz_modification.groups.modify import modify_group_file

modify_group_file(
    "input.miz",
    "output.miz",
    "Viper 1",
    {"frequency": 252.0}
)
```

**Error Conditions**:

- `ValueError`: Group not found
- `ValueError`: Invalid property name
- `ValueError`: Invalid property value
- `ValueError`: New group name already exists (when renaming)

**Related Operations**:
- `modify_unit()` - Modify individual unit properties
- `duplicate_group()` - Clone group with modifications

---

## Advanced Usage

### Chaining Group Operations

```python
from miz_modification.parsing.miz_parser import MizParser
from miz_modification.groups.remove import remove_groups_by_type
from miz_modification.groups.add import add_group
from miz_modification.groups.modify import modify_group

parser = MizParser("input.miz")
parser.extract()
content = parser.get_mission_content()

# Chain multiple operations
content = remove_groups_by_type(content, ["ship"])  # Remove all ships
content = add_group(content, "blue", player_flight)  # Add player group
content = modify_group(content, "AWACS", {"frequency": 251.0})  # Change AWACS freq

parser.write_mission_content(content)
parser.repackage("output.miz")
```

### Conditional Group Operations

```python
from miz_modification.groups.list import list_all_groups, find_group_by_name

# Check if group exists before modifying
if find_group_by_name(content, "Viper 1"):
    content = modify_group(content, "Viper 1", {"frequency": 252.0})

# Remove only if specific count exceeded
groups = list_all_groups(content)
if len(groups["red"]) > 10:
    # Remove some red groups to balance mission
    content = remove_groups_by_type(content, ["SA-6"])
```

### Batch Group Creation

```python
# Create multiple SAM sites from template
sam_positions = [
    (-280000, 615000),
    (-250000, 630000),
    (-220000, 645000)
]

for i, (x, y) in enumerate(sam_positions, start=1):
    group_data = {
        "name": f"Enemy SAM {i}",
        "country": "Russia",
        "category": "vehicle",
        "units": [
            {"type": "S-300PS 40B6M tr", "x": x, "y": y},
            {"type": "S-300PS 40B6MD sr", "x": x+100, "y": y+100},
        ]
    }
    content = add_group(content, "red", group_data)
```

---

## Best Practices

### 1. Always Validate Before Adding

```python
from miz_modification.groups.list import find_group_by_name

# Check for duplicates
if find_group_by_name(content, "Viper 1"):
    raise ValueError("Group 'Viper 1' already exists")

content = add_group(content, "blue", group_data)
```

### 2. Use Type-Based Removal for Cleanup

```python
# Remove all unnecessary groups in one operation
content = remove_groups_by_type(content, ["ship", "train", "static"])
```

### 3. Generate Unique Names

```python
from miz_modification.groups.list import list_all_groups

groups = list_all_groups(content)
existing_names = [g["name"] for g in groups["blue"]]

# Generate unique name
base_name = "Viper"
counter = 1
while f"{base_name} {counter}" in existing_names:
    counter += 1

group_data["name"] = f"{base_name} {counter}"
```

### 4. Use Offsets for Formations

```python
# Create 4-ship formation
leader_pos = (-280000, 615000)
formation_offsets = [
    (0, 0),        # Leader
    (50, -50),     # Wingman (right echelon)
    (100, 0),      # Element lead
    (150, -50)     # Element wingman
]

units = []
for i, (dx, dy) in enumerate(formation_offsets, start=1):
    units.append({
        "type": "F-16C_50",
        "name": f"Viper 1-{i}",
        "x": leader_pos[0] + dx,
        "y": leader_pos[1] + dy,
        "alt": 8000,
        "speed": 200
    })

group_data = {
    "name": "Viper 1",
    "country": "USA",
    "category": "plane",
    "units": units
}
```

---

## See Also

- [Unit Operations](units.md) - Modify individual units within groups
- [Waypoint Operations](waypoints.md) - Manage group waypoints
- [Mission Analysis](mission-analysis.md) - Read-only inspection operations
- [JSON Schema](../schemas/group-schema.json) - Complete group data schema
