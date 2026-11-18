# MCP Light - Local Mission Modification System

**Purpose**: A comprehensive documentation system that provides Claude with structured access to all DMS .miz file modification capabilities in an MCP-like format, without requiring actual MCP server implementation.

## What is MCP Light?

MCP Light is a **documentation-first approach** to organizing the DMS mission modification library. It documents every operation in a standardized format similar to Model Context Protocol (MCP) tools, making it easy for Claude to:

- Discover available operations
- Understand parameters and return types
- See usage examples and error conditions
- Chain operations together in workflows
- Validate inputs before executing operations

Unlike a real MCP server, MCP Light is **pure documentation** - it describes the Python API of the `miz-modifier` library in a format optimized for AI consumption.

## Why MCP Light?

### Benefits

1. **Standardized Interface**: Every operation documented with same structure (parameters, returns, errors, examples)
2. **Easy Discovery**: Claude can quickly find the right operation for any task
3. **Type Safety**: Clear parameter types and validation rules prevent errors
4. **Composability**: Operations designed to chain together for complex modifications
5. **Blueprint for MCP Server**: This documentation will directly inform the real MCP server implementation

### Comparison with Alternatives

| Approach | Speed | Flexibility | Server Required |
|----------|-------|-------------|-----------------|
| Direct Python API | Fast | High | No |
| **MCP Light (docs)** | Fast | High | No |
| Real MCP Server | Medium | Medium | Yes |

**MCP Light gives us the best of both worlds**: the speed and flexibility of direct API access with the structure and discoverability of MCP tools.

## Structure

```
knowledge/mcp-light/
├── README.md                      # This file - overview and quick start
├── OPERATIONS_INDEX.md            # Master list of all operations
├── operations/                    # Detailed operation documentation
│   ├── mission-analysis.md       # Read-only inspection operations
│   ├── groups.md                 # Group add/remove/modify/duplicate/list
│   ├── units.md                  # Unit add/remove/modify
│   ├── waypoints.md              # Waypoint add/remove/modify/list
│   ├── coordinates.md            # Coordinate extraction and transformation
│   └── metadata.md               # Weather, time, briefing operations
├── workflows/                     # Common workflows and patterns
│   ├── basic-modification.md     # Simple single-operation modifications
│   ├── mission-generation.md     # Multi-step mission creation workflows
│   └── debugging.md              # Troubleshooting and validation
└── schemas/                       # JSON schemas for operation parameters
    ├── group-schema.json
    ├── unit-schema.json
    └── waypoint-schema.json
```

## Operation Categories

### 1. Mission Analysis (Read-Only)
Operations that inspect mission files without modifying them:
- `list_groups` - List all groups by coalition
- `list_waypoints` - List waypoints for a group
- `get_mission_info` - Extract mission metadata
- `extract_coordinates` - Get coordinates for units/groups

### 2. Group Operations
Add, remove, modify, and duplicate entire groups:
- `add_group` - Add new group with units and waypoints
- `remove_group` - Remove group by name or criteria
- `modify_group` - Change group properties (country, frequency, etc.)
- `duplicate_group` - Clone existing group with new name/position
- `list_groups` - List all groups

### 3. Unit Operations
Modify individual units within groups:
- `add_unit` - Add unit to existing group
- `remove_unit` - Remove unit from group
- `modify_unit` - Change unit properties (type, position, heading, etc.)

### 4. Waypoint Operations
Manage waypoints for groups:
- `add_waypoint` - Add new waypoint to group's route
- `remove_waypoint` - Remove waypoint by index
- `modify_waypoint` - Change waypoint properties (position, speed, action)
- `list_waypoints` - List all waypoints for a group

### 5. Coordinate Operations
Work with DCS coordinate systems:
- `extract_coordinates` - Get x/y coordinates from units
- `transform_coordinates` - Convert between lat/lon and x/y

### 6. Mission Metadata (Future)
Modify mission settings:
- `set_weather` - Change weather conditions
- `set_time` - Set mission date/time
- `set_briefing` - Update mission briefing text

## Quick Start

### Basic Usage Pattern

Every MCP Light operation follows this pattern:

```python
# 1. Import the operation
from miz_modifier.groups.add import add_group

# 2. Load mission content
from miz_modifier.parsing.miz_parser import MizParser
parser = MizParser("input.miz")
parser.extract()
content = parser.get_mission_content()

# 3. Perform operation
modified_content = add_group(content, "blue", group_data)

# 4. Save result
parser.write_mission_content(modified_content)
parser.repackage("output.miz")
```

### File Convenience Wrappers

Most operations also have `*_file()` wrappers for simpler usage:

```python
from miz_modifier.groups.add import add_group_file

add_group_file(
    input_miz="input.miz",
    output_miz="output.miz",
    coalition="blue",
    group_data=group_data
)
```

### Chaining Operations

Multiple operations can be chained:

```python
# Extract
parser = MizParser("input.miz")
parser.extract()
content = parser.get_mission_content()

# Chain modifications
content = remove_groups_by_type(content, ["ship"])
content = add_group(content, "blue", player_group)
content = modify_group(content, "Enemy SAM 1", {"frequency": 127.5})

# Repackage
parser.write_mission_content(content)
parser.repackage("output.miz")
```

## Documentation Format

Each operation is documented with:

1. **Header**: Name, category, availability
2. **Description**: What the operation does
3. **Parameters**: Name, type, required/optional, description
4. **Returns**: Type and description of return value
5. **Schema**: Detailed structure for complex parameters
6. **Usage Example**: Practical code example
7. **File Wrapper**: Convenience function for file operations
8. **Error Conditions**: Common errors and validation failures
9. **Related Operations**: Links to similar/complementary operations

See [OPERATIONS_INDEX.md](OPERATIONS_INDEX.md) for the complete list of operations.

## Best Practices

### 1. Always Validate First

Before modifying a mission, inspect its current state:

```python
# Check what groups exist before adding/removing
groups = list_all_groups_file("mission.miz")
print(f"Current groups: {[g['name'] for g in groups['blue']]}")
```

### 2. Use Type Checking

MCP Light provides JSON schemas for all complex parameters. Validate before executing:

```python
import jsonschema

# Validate group data against schema
with open("knowledge/mcp-light/schemas/group-schema.json") as f:
    schema = json.load(f)

jsonschema.validate(group_data, schema)  # Raises exception if invalid
```

### 3. Handle Errors Gracefully

All operations can raise `ValueError` for invalid inputs:

```python
try:
    content = add_group(content, "blue", group_data)
except ValueError as e:
    print(f"Invalid group data: {e}")
    # Handle error appropriately
```

### 4. Test in DCS

Always test modified missions in DCS World:

```python
# After modifying
parser.repackage("output.miz")

# Load output.miz in DCS Mission Editor
# Start mission and check for errors in dcs.log
```

## Relationship to Actual MCP Server

MCP Light serves as the **design specification** for the future MCP server:

- **Now**: Claude reads MCP Light docs and calls Python functions directly
- **Future**: Claude calls MCP server tools, which wrap the same Python functions
- **Benefit**: Documentation is already complete when we build the server

### Future MCP Server Tools

When implemented, the MCP server will expose tools like:

```json
{
  "name": "dms_add_group",
  "description": "Add a new group to a mission file",
  "parameters": {
    "input_miz": {"type": "string", "description": "Path to input .miz file"},
    "output_miz": {"type": "string", "description": "Path to output .miz file"},
    "coalition": {"type": "string", "enum": ["blue", "red"]},
    "group_data": {"type": "object", "description": "See group-schema.json"}
  }
}
```

These tools will be thin wrappers around the existing `*_file()` functions.

## Next Steps

1. **Read Operations**: Start with [OPERATIONS_INDEX.md](OPERATIONS_INDEX.md) for a complete list
2. **Learn Workflows**: Check [workflows/](workflows/) for common patterns
3. **Try Examples**: Follow examples in operation documentation
4. **Build Missions**: Use the mission generation pipeline (see `mission-generation/`)

## Contributing

When adding new operations to `miz-modifier`, update MCP Light documentation:

1. Add operation to [OPERATIONS_INDEX.md](OPERATIONS_INDEX.md)
2. Create detailed documentation in appropriate `operations/*.md` file
3. Add JSON schema if operation uses complex parameters
4. Include usage examples and error conditions
5. Link related operations

## Support

- **Library API**: See `miz-modifier/architecture.md`
- **MIZ File Structure**: See `knowledge/miz-file-manipulation.md`
- **Mission Generation**: See `mission-generation/README.md`
- **Lua Scripts**: See `lua-library/SCRIPT-REFERENCE.md`
