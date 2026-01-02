# MCP Light Operations Index

Complete reference of all available mission modification operations.

## Quick Navigation

- [Mission Analysis (Read-Only)](#mission-analysis-read-only)
- [Group Operations](#group-operations)
- [Unit Operations](#unit-operations)
- [Waypoint Operations](#waypoint-operations)
- [Coordinate Operations](#coordinate-operations)
- [Mission Metadata](#mission-metadata-future)

---

## Mission Analysis (Read-Only)

Operations that inspect mission files without modifying them.

| Operation | Module | Description |
|-----------|--------|-------------|
| `list_all_groups` | `miz_modifier.groups.list` | List all groups in a mission by coalition |
| `list_all_groups_file` | `miz_modifier.groups.list` | File wrapper for listing groups |
| `list_waypoints` | `miz_modifier.waypoints.list` | List all waypoints for a specific group |
| `list_waypoints_file` | `miz_modifier.waypoints.list` | File wrapper for listing waypoints |
| `extract_group_coordinates` | `miz_modifier.coordinates.extract` | Extract coordinates for all units in a group |
| `extract_coordinates_file` | `miz_modifier.coordinates.extract` | File wrapper for coordinate extraction |

**Documentation**: [operations/mission-analysis.md](operations/mission-analysis.md)

---

## Group Operations

Add, remove, modify, and duplicate entire groups of units.

### Create Operations

| Operation | Module | Description |
|-----------|--------|-------------|
| `add_group` | `miz_modifier.groups.add` | Add a new group with units and waypoints |
| `add_group_file` | `miz_modifier.groups.add` | File wrapper for adding groups |
| `duplicate_group` | `miz_modifier.groups.duplicate` | Clone an existing group with modifications |
| `duplicate_group_file` | `miz_modifier.groups.duplicate` | File wrapper for duplicating groups |

### Delete Operations

| Operation | Module | Description |
|-----------|--------|-------------|
| `remove_group` | `miz_modifier.groups.remove` | Remove a group by name |
| `remove_group_file` | `miz_modifier.groups.remove` | File wrapper for removing group by name |
| `remove_groups_by_type` | `miz_modifier.groups.remove` | Remove all groups of specific unit type(s) |
| `remove_groups_by_type_file` | `miz_modifier.groups.remove` | File wrapper for removing by type |

### Modify Operations

| Operation | Module | Description |
|-----------|--------|-------------|
| `modify_group` | `miz_modifier.groups.modify` | Modify group properties (frequency, country, etc.) |
| `modify_group_file` | `miz_modifier.groups.modify` | File wrapper for modifying groups |

**Documentation**: [operations/groups.md](operations/groups.md)

---

## Unit Operations

Modify individual units within existing groups.

### Create Operations

| Operation | Module | Description |
|-----------|--------|-------------|
| `add_unit` | `miz_modifier.units.add` | Add a new unit to an existing group |
| `add_unit_file` | `miz_modifier.units.add` | File wrapper for adding units |

### Delete Operations

| Operation | Module | Description |
|-----------|--------|-------------|
| `remove_unit` | `miz_modifier.units.remove` | Remove a unit from a group by name |
| `remove_unit_file` | `miz_modifier.units.remove` | File wrapper for removing units |

### Modify Operations

| Operation | Module | Description |
|-----------|--------|-------------|
| `modify_unit` | `miz_modifier.units.modify` | Modify unit properties (type, position, heading, etc.) |
| `modify_unit_file` | `miz_modifier.units.modify` | File wrapper for modifying units |
| `modify_unit_position` | `miz_modifier.units.modify` | Change unit's position (x, y, alt) |
| `modify_unit_type` | `miz_modifier.units.modify` | Change unit's aircraft/vehicle type |
| `modify_unit_heading` | `miz_modifier.units.modify` | Change unit's heading |
| `modify_pylon` | `miz_modifier.units.modify` | Modify weapon loadout on specific pylon |

**Documentation**: [operations/units.md](operations/units.md)

---

## Waypoint Operations

Manage waypoints for groups.

### Create Operations

| Operation | Module | Description |
|-----------|--------|-------------|
| `add_waypoint` | `miz_modifier.waypoints.add` | Add a new waypoint to a group's route |
| `add_waypoint_file` | `miz_modifier.waypoints.add` | File wrapper for adding waypoints |

### Delete Operations

| Operation | Module | Description |
|-----------|--------|-------------|
| `remove_waypoint` | `miz_modifier.waypoints.remove` | Remove a waypoint by index |
| `remove_waypoint_file` | `miz_modifier.waypoints.remove` | File wrapper for removing waypoints |

### Modify Operations

| Operation | Module | Description |
|-----------|--------|-------------|
| `modify_waypoint` | `miz_modifier.waypoints.modify` | Modify waypoint properties (position, speed, action) |
| `modify_waypoint_file` | `miz_modifier.waypoints.modify` | File wrapper for modifying waypoints |
| `modify_waypoint_position` | `miz_modifier.waypoints.modify` | Change waypoint coordinates |
| `modify_waypoint_altitude` | `miz_modifier.waypoints.modify` | Change waypoint altitude |
| `modify_waypoint_speed` | `miz_modifier.waypoints.modify` | Change waypoint speed |
| `modify_waypoint_action` | `miz_modifier.waypoints.modify` | Change waypoint action type |

**Documentation**: [operations/waypoints.md](operations/waypoints.md)

---

## Coordinate Operations

Extract and transform coordinates between different systems.

| Operation | Module | Description |
|-----------|--------|-------------|
| `extract_group_coordinates` | `miz_modifier.coordinates.extract` | Get x/y coordinates for all units in a group |
| `extract_coordinates_file` | `miz_modifier.coordinates.extract` | File wrapper for coordinate extraction |
| `transform_to_latlon` | `miz_modifier.coordinates.transform` | Convert x/y to latitude/longitude |
| `transform_to_xy` | `miz_modifier.coordinates.transform` | Convert latitude/longitude to x/y |

**Documentation**: [operations/coordinates.md](operations/coordinates.md)

---

## Mission Metadata (Future)

Operations for modifying mission-level settings (not yet implemented).

| Operation | Status | Description |
|-----------|--------|-------------|
| `set_weather` | Planned | Change weather conditions (clouds, wind, etc.) |
| `set_time` | Planned | Set mission date and time |
| `set_start_time` | Planned | Set mission start time offset |
| `set_briefing` | Planned | Update mission briefing text |
| `set_description` | Planned | Update mission description |
| `add_kneeboard_page` | Planned | Add custom kneeboard image/text |

**Documentation**: [operations/metadata.md](operations/metadata.md)

---

## Operation Naming Convention

All operations follow a consistent naming pattern:

### Core Functions

```
{verb}_{object}[_{criteria}]
```

Examples:
- `add_group` - Add a group
- `remove_group` - Remove a group
- `modify_group` - Modify a group
- `remove_groups_by_type` - Remove groups with specific criteria

### File Wrappers

```
{verb}_{object}[_{criteria}]_file
```

Examples:
- `add_group_file` - File wrapper for adding a group
- `list_all_groups_file` - File wrapper for listing groups

### Verbs

- `add` - Create new element
- `remove` - Delete element
- `modify` - Change properties of existing element
- `duplicate` - Clone existing element
- `list` - Inspect/read elements (read-only)
- `extract` - Get specific data from elements (read-only)
- `transform` - Convert data between formats

### Objects

- `group` - Entire group of units
- `unit` - Individual unit within a group
- `waypoint` - Waypoint in a group's route
- `coordinates` - Position data

---

## Usage Patterns

### Pattern 1: Single Operation

For simple modifications, use file wrappers:

```python
from miz_modifier.groups.remove import remove_group_file

remove_group_file("input.miz", "output.miz", "Enemy SAM 1")
```

### Pattern 2: Multiple Operations

For complex modifications, extract once and chain operations:

```python
from miz_modifier.parsing.miz_parser import MizParser
from miz_modifier.groups.remove import remove_groups_by_type
from miz_modifier.groups.add import add_group

parser = MizParser("input.miz")
parser.extract()
content = parser.get_mission_content()

# Chain operations
content = remove_groups_by_type(content, ["ship"])
content = add_group(content, "blue", player_flight_data)

parser.write_mission_content(content)
parser.repackage("output.miz")
```

### Pattern 3: Conditional Modification

Inspect first, then modify:

```python
from miz_modifier.groups.list import list_all_groups_file
from miz_modifier.groups.remove import remove_group_file

# Check what exists
groups = list_all_groups_file("input.miz")

if any(g["name"] == "Old Group" for g in groups["blue"]):
    remove_group_file("input.miz", "temp.miz", "Old Group")
    # Continue with temp.miz
```

### Pattern 4: Validation

Use read-only operations to validate before and after:

```python
from miz_modifier.groups.list import list_all_groups
from miz_modifier.parsing.miz_parser import MizParser

parser = MizParser("input.miz")
parser.extract()
content = parser.get_mission_content()

# Before
before_groups = list_all_groups(content)
print(f"Groups before: {len(before_groups['blue'])} blue, {len(before_groups['red'])} red")

# Modify...
content = add_group(content, "blue", new_group)

# After
after_groups = list_all_groups(content)
print(f"Groups after: {len(after_groups['blue'])} blue, {len(after_groups['red'])} red")

parser.write_mission_content(content)
parser.repackage("output.miz")
```

---

## Error Handling

All operations can raise `ValueError` for invalid inputs:

```python
try:
    content = add_group(content, "blue", group_data)
except ValueError as e:
    if "duplicate" in str(e).lower():
        # Handle duplicate group name
        print(f"Group already exists: {e}")
    elif "invalid" in str(e).lower():
        # Handle invalid data
        print(f"Invalid group data: {e}")
    else:
        raise
```

Common error conditions:
- **Duplicate names**: Group/unit name already exists
- **Invalid types**: Unknown aircraft/vehicle type
- **Invalid coordinates**: Position outside map bounds
- **Missing groups**: Target group not found
- **Invalid coalition**: Coalition not "blue" or "red"

---

## Performance Considerations

### Extract Once, Modify Multiple Times

**Good**:
```python
parser.extract()
content = parser.get_mission_content()
content = operation1(content, ...)
content = operation2(content, ...)
content = operation3(content, ...)
parser.write_mission_content(content)
parser.repackage("output.miz")
```

**Bad** (multiple extractions):
```python
operation1_file("input.miz", "temp1.miz", ...)
operation2_file("temp1.miz", "temp2.miz", ...)
operation3_file("temp2.miz", "output.miz", ...)
```

### Use Type-Specific Removals

**Good**:
```python
# Remove all ships in one pass
content = remove_groups_by_type(content, ["ship"])
```

**Bad** (individual removals):
```python
# Remove ships one by one
for ship_group in ship_groups:
    content = remove_group(content, ship_group["name"])
```

---

## See Also

- [Mission Analysis Operations](operations/mission-analysis.md)
- [Group Operations](operations/groups.md)
- [Unit Operations](operations/units.md)
- [Waypoint Operations](operations/waypoints.md)
- [Coordinate Operations](operations/coordinates.md)
- [Common Workflows](workflows/basic-modification.md)
- [JSON Schemas](schemas/)
