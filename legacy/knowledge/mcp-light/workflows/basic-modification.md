# Basic Mission Modification Workflow

Step-by-step guide for performing simple mission modifications using the miz-modification library.

## Quick Start

### Single Operation Pattern

For simple, one-time modifications, use file wrapper functions:

```python
from miz_modification.groups.remove import remove_group_file

# Remove a group in one line
remove_group_file("input.miz", "output.miz", "Enemy SAM 1")
```

This pattern is best for:
- Single modifications
- Quick edits
- Simple scripts

---

## Common Workflows

### Workflow 1: Remove Groups by Type

**Goal**: Remove all ships from a mission.

```python
from miz_modification.groups.remove import remove_groups_by_type_file

# Remove all ship groups
remove_groups_by_type_file(
    input_miz="../miz-files/input/mission.miz",
    output_miz="../miz-files/output/no_ships.miz",
    unit_types=["ship"]
)

print("All ships removed successfully")
```

**Use Cases**:
- Removing naval units from land-only missions
- Clearing specific unit categories
- Simplifying missions for testing

---

### Workflow 2: Add a New Group

**Goal**: Add a friendly fighter group to the mission.

```python
from miz_modification.groups.add import add_group_file

# Define group data
fighter_group = {
    "name": "CAP Flight 1",
    "groupId": 100,
    "units": [
        {
            "name": "Pilot #001",
            "unitId": 101,
            "type": "F-16C_50",
            "skill": "High",
            "x": -50000,
            "y": 30000,
            "alt": 3000,
            "speed": 250,
            "heading": 0
        }
    ]
}

# Add group to mission
add_group_file(
    input_miz="../miz-files/input/mission.miz",
    output_miz="../miz-files/output/with_cap.miz",
    coalition="blue",
    group_data=fighter_group
)

print("CAP flight added")
```

**Use Cases**:
- Adding player aircraft
- Inserting escort flights
- Adding enemy forces

---

### Workflow 3: Modify Unit Loadout

**Goal**: Change weapons on an aircraft.

```python
from miz_modification.loadouts.modify import modify_pylon_file

# Change weapon on pylon 3 to AIM-120C
modify_pylon_file(
    input_miz="../miz-files/input/mission.miz",
    output_miz="../miz-files/output/new_loadout.miz",
    group_name="Fighter-1",
    pylon_number=3,
    clsid="{40EF17B7-F508-45de-8566-6FFECC0C1AB8}",  # AIM-120C
    unit_index=1
)

print("Loadout updated")
```

**Use Cases**:
- Changing mission loadouts
- Testing different weapons
- Balancing missions

---

### Workflow 4: Add Waypoints

**Goal**: Add waypoints to a group's route.

```python
from miz_modification.waypoints.add import add_waypoint_file

# Add waypoint at new location
add_waypoint_file(
    input_miz="../miz-files/input/mission.miz",
    output_miz="../miz-files/output/new_route.miz",
    group_name="Fighter-1",
    position={"x": -45000, "y": 35000},
    speed=250,
    alt=3000,
    action="Turning Point"
)

print("Waypoint added")
```

**Use Cases**:
- Extending routes
- Adding patrol points
- Creating new flight paths

---

### Workflow 5: Add Trigger Zone

**Goal**: Add a circular trigger zone for objectives.

```python
from miz_modification.triggers.add import add_trigger_zone_file

# Add 5km radius zone at coordinates
add_trigger_zone_file(
    input_miz="../miz-files/input/mission.miz",
    output_miz="../miz-files/output/with_zone.miz",
    name="Target Area",
    x=150000,
    y=55000,
    radius=5000
)

print("Trigger zone added")
```

**Use Cases**:
- Defining objective areas
- Creating spawn zones
- Setting up detection areas

---

### Workflow 6: Add DO SCRIPT Trigger

**Goal**: Inject custom Lua script into mission.

```python
from miz_modification.triggers.add import add_do_script_trigger_file

# Script to display message
script = '''
trigger.action.outText("Welcome to the mission!", 15)
env.info("Mission script loaded successfully")
'''

add_do_script_trigger_file(
    input_miz="../miz-files/input/mission.miz",
    output_miz="../miz-files/output/with_script.miz",
    comment="Welcome Message",
    script=script,
    time_after=5  # 5 seconds after mission start
)

print("Script trigger added")
```

**Use Cases**:
- Adding custom mission logic
- Loading external Lua modules
- Creating dynamic events

---

## Inspection Workflows

### Workflow 7: List All Groups

**Goal**: See what groups are in a mission.

```python
from miz_modification.groups.list import list_all_groups_file

groups = list_all_groups_file("../miz-files/input/mission.miz")

print(f"Blue groups: {len(groups['blue'])}")
print(f"Red groups: {len(groups['red'])}")

for coalition, group_list in groups.items():
    print(f"\n{coalition.upper()} Coalition:")
    for group in group_list:
        print(f"  - {group['name']} ({group['category']})")
```

**Use Cases**:
- Understanding mission structure
- Validating modifications
- Mission analysis

---

### Workflow 8: Get Group Positions

**Goal**: Extract coordinates for all groups.

```python
from miz_modification.coordinates.extract import get_all_positions_file

positions = get_all_positions_file(
    "../miz-files/input/mission.miz",
    coalition="red"
)

print(f"Found {len(positions)} red groups:")
for name, pos in positions.items():
    print(f"{name}: x={pos['x']}, y={pos['y']}")
```

**Use Cases**:
- Finding group locations
- Planning routes
- Threat analysis

---

### Workflow 9: List Waypoints

**Goal**: See a group's flight path.

```python
from miz_modification.waypoints.list import list_waypoints_file

waypoints = list_waypoints_file(
    "../miz-files/input/mission.miz",
    "Fighter-1"
)

print(f"Fighter-1 has {len(waypoints)} waypoints:")
for wp in waypoints:
    print(f"WP{wp['index']}: {wp['action']} at ({wp['x']}, {wp['y']}) "
          f"alt={wp['alt']}m speed={wp['speed']:.0f}m/s")
```

**Use Cases**:
- Understanding routes
- Validating flight paths
- Route analysis

---

### Workflow 10: Inspect Loadout

**Goal**: See what weapons a unit has.

```python
from miz_modification.loadouts.list import list_loadout_file

loadout = list_loadout_file(
    "../miz-files/input/mission.miz",
    "Fighter-1",
    unit_index=1
)

print(f"Aircraft: {loadout['unit_type']}")
print(f"Fuel: {loadout['fuel']}kg")
print(f"Countermeasures: {loadout['chaff']} chaff, {loadout['flare']} flare")
print(f"Gun: {loadout['gun']} rounds")

print("Weapons:")
for pylon_num, pylon in loadout['pylons'].items():
    print(f"  Pylon {pylon_num}: {pylon['CLSID']}")
```

**Use Cases**:
- Checking current loadouts
- Planning loadout changes
- Mission balance analysis

---

## Best Practices

### 1. Always Use Absolute Paths

```python
# Good - Clear and portable
input_miz = "../miz-files/input/mission.miz"
output_miz = "../miz-files/output/modified.miz"

# Better - Absolute paths
from pathlib import Path

input_miz = Path("C:/DCS/Missions/mission.miz")
output_miz = Path("C:/DCS/Missions/modified.miz")
```

### 2. Validate Before Modifying

```python
from pathlib import Path
from miz_modification.groups.list import list_all_groups_file

input_miz = "../miz-files/input/mission.miz"

# Check file exists
if not Path(input_miz).exists():
    raise FileNotFoundError(f"Mission file not found: {input_miz}")

# Check what's in it
groups = list_all_groups_file(input_miz)
print(f"Found {len(groups['blue'])} blue groups")

# Now modify
# ...
```

### 3. Use Descriptive Output Names

```python
# Good - Clear what was changed
output_miz = "../miz-files/output/mission_no_ships.miz"
output_miz = "../miz-files/output/mission_with_cap.miz"

# Bad - Unclear
output_miz = "../miz-files/output/mission2.miz"
output_miz = "../miz-files/output/output.miz"
```

### 4. Handle Errors Gracefully

```python
try:
    remove_group_file(input_miz, output_miz, "Enemy SAM 1")
    print("Group removed successfully")
except FileNotFoundError as e:
    print(f"Error: Mission file not found: {e}")
except ValueError as e:
    print(f"Error: {e}")
except Exception as e:
    print(f"Unexpected error: {e}")
```

### 5. Test in DCS

Always load modified missions in DCS World to verify:

```python
# After modification
print("Mission modified successfully")
print("Please test in DCS World:")
print(f"  1. Load: {output_miz}")
print("  2. Start mission")
print("  3. Check for errors in DCS.log")
print(f"  4. Verify changes are correct")
```

---

## Quick Reference

### File Wrapper Pattern

All operations have file wrappers that follow this pattern:

```python
operation_name_file(
    input_miz="path/to/input.miz",
    output_miz="path/to/output.miz",
    ...operation-specific parameters...
)
```

### Common Parameters

| Parameter | Type | Description |
|-----------|------|-------------|
| `input_miz` | `str` | Path to input .miz file |
| `output_miz` | `str` | Path to output .miz file |
| `group_name` | `str` | Name of group to target |
| `coalition` | `str` | "blue", "red", or "neutrals" |
| `unit_index` | `int` | Unit index in group (1-based) |

---

## Troubleshooting

### File Not Found

```python
FileNotFoundError: Input .miz file not found: mission.miz
```

**Solution**: Check file path is correct and file exists.

### Group Not Found

```python
ValueError: Group 'Fighter-1' not found in mission
```

**Solution**: Use `list_all_groups_file()` to see available groups.

### Invalid Parameters

```python
ValueError: Invalid coalition: 'Blue' (expected: 'blue', 'red', 'neutrals')
```

**Solution**: Check parameter values match expected format (lowercase coalitions, etc.).

---

## See Also

- [Complex Modifications Workflow](complex-modifications.md) - Multi-operation workflows
- [Debugging Workflow](debugging.md) - Validation and troubleshooting
- [Operations Index](../OPERATIONS_INDEX.md) - All available operations
- [Group Operations](../operations/groups.md) - Group operation details
- [Unit Operations](../operations/units.md) - Unit operation details
- [Loadout Operations](../operations/loadouts.md) - Loadout operation details
