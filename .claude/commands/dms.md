---
description: DCS mission file modification mode - uses MCP Light documentation and miz-modification library
---

# DCS Mission Modification Mode (/dms)

You are now in **DCS Mission Modification Mode**. Your role is to help modify DCS World mission files (.miz) using the miz-modification library.

## Core Principles

1. **Consult MCP Light Documentation First**
   - **Operations Index**: `knowledge/mcp-light/OPERATIONS_INDEX.md`
   - **Operation Details**: `knowledge/mcp-light/operations/`
   - **JSON Schemas**: `knowledge/mcp-light/schemas/`
   - **Workflows**: `knowledge/mcp-light/workflows/`

2. **This Mode is ONLY for Mission File Modification**
   - ✅ Modify existing .miz files
   - ✅ Use miz-modification library operations
   - ✅ Follow documented patterns from MCP Light
   - ❌ Do NOT work on DMS system development
   - ❌ Do NOT modify library code
   - ❌ Do NOT update documentation

## Available Operations

### Mission Analysis (Read-Only)
- `list_all_groups()` - List all groups by coalition
- `get_group_info()` - Get detailed group information
- `list_waypoints()` - List waypoints for a group
- `get_all_positions()` - Get positions with filtering
- `list_loadout()` - Get unit loadout info
- `list_trigger_zones()` - List all trigger zones
- `list_trigger_rules()` - List all triggers

### Group Operations
- `add_group()` - Add new group with units
- `remove_group()` - Remove group by name
- `remove_groups_by_type()` - Remove all groups of type
- `duplicate_group()` - Clone existing group
- `modify_group()` - Modify group properties

### Unit Operations
- `add_unit_to_group()` - Add unit to existing group
- `remove_unit_from_group()` - Remove unit by index
- `remove_unit_by_name()` - Remove unit by name
- `modify_unit_skill()` - Change AI skill level
- `modify_unit_position()` - Change unit coordinates
- `modify_unit_loadout()` - Change weapons/fuel/ammo

### Waypoint Operations
- `add_waypoint()` - Add waypoint to route
- `add_multiple_waypoints()` - Add multiple waypoints
- `remove_waypoint()` - Remove waypoint by index
- `modify_waypoint_position()` - Change waypoint coordinates
- `modify_waypoint_speed()` - Change waypoint speed
- `modify_waypoint_altitude()` - Change waypoint altitude

### Coordinate Operations
- `get_group_coordinates()` - Get group position
- `get_unit_coordinates()` - Get unit position
- `get_waypoint_coordinates()` - Get waypoint position

### Loadout Operations
- `modify_pylon()` - Change weapon on pylon
- `modify_countermeasures()` - Set chaff/flare
- `modify_gun_ammo()` - Set gun ammunition
- `modify_fuel()` - Set fuel quantity
- `clear_pylon()` - Remove weapon from pylon
- `clear_all_pylons()` - Remove all weapons

### Trigger Operations
- `add_trigger_zone()` - Add circular/quad zone
- `add_do_script_trigger()` - Add Lua script trigger

## Standard MizParser Pattern

**Always use this pattern** for mission modifications:

```python
from miz_modification.parsing.miz_parser import MizParser
from miz_modification.groups.remove import remove_groups_by_type

# Extract mission
parser = MizParser("input.miz")
parser.extract()
content = parser.get_mission_content()

# Apply modifications
content = remove_groups_by_type(content, ["ship"])

# Repackage
parser.write_mission_content(content)
parser.repackage("output.miz")
parser.cleanup()
```

## File Wrapper Pattern

For simple single operations, use file wrappers:

```python
from miz_modification.groups.remove import remove_groups_by_type_file

remove_groups_by_type_file(
    "input.miz",
    "output.miz",
    ["ship"]
)
```

## Response Format

When helping with mission modifications:

1. **Explain** what operations you'll use (reference MCP Light docs)
2. **Provide code** using miz-modification library
3. **Expected result** and next steps

## Key References

- **MCP Light Index**: `knowledge/mcp-light/OPERATIONS_INDEX.md`
- **Groups**: `knowledge/mcp-light/operations/groups.md`
- **Units**: `knowledge/mcp-light/operations/units.md`
- **Waypoints**: `knowledge/mcp-light/operations/waypoints.md`
- **Coordinates**: `knowledge/mcp-light/operations/coordinates.md`
- **Loadouts**: `knowledge/mcp-light/operations/loadouts.md`
- **Triggers**: `knowledge/mcp-light/operations/triggers.md`
- **Mission Analysis**: `knowledge/mcp-light/operations/mission-analysis.md`
- **Basic Workflow**: `knowledge/mcp-light/workflows/basic-modification.md`
- **Schemas**: `knowledge/mcp-light/schemas/`

## Mission File Locations

- **Input**: `miz-files/input/` - Place source .miz files here
- **Output**: `miz-files/output/` - Modified missions go here
- **Temp**: `miz-files/temp_extract/` - Temporary extraction directory

## Important Notes

- .miz files are ZIP archives containing Lua mission data
- MizParser uses string manipulation with regex patterns
- No DCS installation required
- Always test modifications by loading in DCS World
- Check `C:\Users\mook\Saved Games\DCS\Logs\dcs.log` for errors

## Coalition Types

- `"blue"` - Blue coalition
- `"red"` - Red coalition
- `"neutrals"` - Neutral coalition

## Unit Categories

- `"plane"` - Aircraft
- `"helicopter"` - Helicopters
- `"ship"` - Naval units
- `"vehicle"` - Ground vehicles
- `"static"` - Static objects

## Altitude Types

- `"BARO"` - Barometric (Mean Sea Level)
- `"RADIO"` - Radio (Above Ground Level)

## Skill Levels

- `"Average"`, `"Good"`, `"High"`, `"Excellent"`, `"Random"`, `"Player"`

Now ready to help with DCS mission file modifications!
