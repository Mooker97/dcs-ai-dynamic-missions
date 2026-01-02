# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

DCS Dynamic Mission System - An AI-powered mission generation system that transforms natural language prompts into complete, playable DCS World mission files (.miz).

**Vision**: Transform DCS mission creation from a multi-hour technical process into a 30-second conversation.

**Current Phase**: Phase 1 - Local Development System (MVP in progress)

## /dms Command - MCP Light Mode

When the user types `/dms [request]`, activate **MCP Light Mode** for .miz file modification operations.

**IMPORTANT**: This mode is for **mission file modification only**, NOT for development work on the DMS system itself.

### Mode Behavior

1. **Consult MCP Light Documentation First**
   - Read `knowledge/mcp-light/OPERATIONS_INDEX.md` to find relevant operations
   - Check detailed operation docs in `knowledge/mcp-light/operations/` for usage patterns
   - Use JSON schemas in `knowledge/mcp-light/schemas/` for parameter validation

2. **Focus on Mission Modification**
   - Only help with modifying existing .miz files
   - Use operations from the `miz-modification/` library
   - Follow MCP Light documented patterns and examples
   - Do NOT work on developing the DMS system, library code, or documentation

3. **Available Operation Categories**
   - **Mission Analysis**: List groups, waypoints, coordinates (read-only)
   - **Group Operations**: Add, remove, modify, duplicate groups
   - **Unit Operations**: Add, remove, modify individual units
   - **Waypoint Operations**: Add, remove, modify waypoints
   - **Coordinate Operations**: Extract and transform coordinates
   - **Loadout Operations**: List and modify weapon loadouts
   - **Trigger Operations**: Add and list triggers

4. **Response Pattern**
   ```
   [Brief explanation of what operations will be used]

   [Python code using miz-modification operations]

   [Expected result/next steps]
   ```

5. **Always Use MizParser Pattern**
   ```python
   from miz_modification.parsing.miz_parser import MizParser
   from miz_modification.groups.add import add_group

   parser = MizParser("input.miz")
   parser.extract()
   content = parser.get_mission_content()

   # Apply operations
   content = add_group(content, "blue", group_data)

   parser.write_mission_content(content)
   parser.repackage("output.miz")
   ```

### Example Usage

**User**: `/dms Remove all ship groups from mission.miz`
**Response**: Uses `remove_groups_by_type_file()` operation from MCP Light docs

**User**: `/dms Add a 4-ship F-16 flight at coordinates X Y`
**Response**: Uses `add_group_file()` operation with proper group_data structure

**User**: `/dms List all waypoints for group "Viper 1"`
**Response**: Uses `list_waypoints_file()` operation

### What NOT to Do in /dms Mode

- ❌ Don't modify miz-modification library code
- ❌ Don't update MCP Light documentation
- ❌ Don't work on DMS system development
- ❌ Don't implement new operations
- ✅ Only help with actual .miz file modification tasks

### Key References

- **Operations Index**: `knowledge/mcp-light/OPERATIONS_INDEX.md`
- **Group Ops**: `knowledge/mcp-light/operations/groups.md`
- **Unit Ops**: `knowledge/mcp-light/operations/units.md`
- **Waypoint Ops**: `knowledge/mcp-light/operations/waypoints.md`
- **Coordinate Ops**: `knowledge/mcp-light/operations/coordinates.md`

---

## Development Setup

### Prerequisites

```bash
# Python 3.10+
python --version

# Install dependencies (if needed for coordinate transformations)
pip install pyproj>=3.7.0
```

**Dependencies**:
- **No dependencies required** - MizParser uses only Python standard library (zipfile, os, shutil, pathlib)
- `pyproj>=3.7.0` - *Optional* for coordinate transformations (lat/lon ↔ x/y)
- ~~`pydcs>=0.15.0`~~ - *DEPRECATED* for modifications (kept for future mission generation only)

## Project Architecture

### High-Level Structure

```
User Input (Natural Language)
    ↓
Claude AI (Orchestration & Mission Design)
    ↓
MCP Server Layer (Mission Generation Tools)
    ↓
miz-modifier Library (MizParser-based)
    ↓
.miz Files (DCS Mission Files)
```

### Key Architectural Concepts

**MIZ Files**: DCS mission files are ZIP archives containing Lua tables that define mission structure, units, triggers, and scripts.

**MizParser-Based Architecture** (Current):
- Extract → Modify String → Repackage workflow
- Direct Lua text manipulation using regex patterns
- No DCS installation required
- Pure Python, lightweight and fast

**Modification Approach**:
1. Extract .miz file (standard ZIP archive)
2. Read mission file (Lua table as text)
3. Apply modifications using regex patterns
4. Write modified content back
5. Repackage as .miz file

**Mission Generation Pipeline**:
1. Parse user intent from natural language
2. Design mission structure (aircraft, objectives, threats)
3. Modify template mission or build from scratch
4. Inject dynamic Lua scripts for randomization
5. Package as .miz file with triggers and events

**Dynamic Scripting System** (Planned):
- Lua library for runtime randomization
- Random spawn systems
- Dynamic events and reinforcements
- Adaptive difficulty based on player performance

## Common Development Commands

### Working with MizParser

```python
from miz-modifier.parsing.miz_parser import MizParser

# Extract mission
parser = MizParser("../miz-files/input/mission.miz")
parser.extract()

# Read mission content
content = parser.get_mission_content()

# Modify content (using modification functions)
from miz-modifier.groups.remove import remove_groups_by_type
modified_content = remove_groups_by_type(content, ["ship"])

# Write back and repackage
parser.write_mission_content(modified_content)
parser.repackage("../miz-files/output/modified.miz")
```

### Using Convenience Wrappers

```python
# Quick modification without manual extract/repackage
from miz-modifier.groups.remove import remove_groups_by_type_file

remove_groups_by_type_file(
    input_miz="../miz-files/input/mission.miz",
    output_miz="../miz-files/output/modified.miz",
    unit_types=["ship"]
)
```

### Listing Groups

```python
from miz-modifier.groups.list import list_all_groups_file

groups = list_all_groups_file("../miz-files/input/mission.miz")
print(f"Found {len(groups['blue'])} blue groups")
```

## File Organization

```
DMS/
├── miz-modifier/      # Main library (MizParser-based)
│   ├── __init__.py
│   ├── core.py                # Core utilities
│   ├── groups/                # Group operations
│   │   ├── __init__.py
│   │   ├── list.py           # List groups (read-only)
│   │   ├── add.py            # Add groups
│   │   ├── remove.py         # Remove groups
│   │   ├── duplicate.py      # Duplicate groups
│   │   └── modify.py         # Modify group properties
│   ├── units/                 # Unit operations
│   │   ├── __init__.py
│   │   ├── add.py            # Add units
│   │   ├── remove.py         # Remove units
│   │   └── modify.py         # Modify unit properties
│   ├── waypoints/             # Waypoint operations
│   │   ├── __init__.py
│   │   ├── list.py           # List waypoints
│   │   ├── add.py            # Add waypoints
│   │   ├── remove.py         # Remove waypoints
│   │   └── modify.py         # Modify waypoints
│   ├── coordinates/           # Coordinate operations
│   │   ├── __init__.py
│   │   ├── extract.py        # Get coordinates
│   │   └── transform.py      # Transform coordinates
│   ├── utils/                 # Utilities
│   │   ├── __init__.py
│   │   ├── id_manager.py     # ID generation
│   │   ├── patterns.py       # Regex patterns
│   │   └── validation.py     # Validation
│   └── parsing/               # MizParser
│       ├── __init__.py
│       └── miz_parser.py     # Core parser class
├── miz-files/                 # Mission file storage
│   ├── input/                # Original mission files
│   ├── output/               # Modified/generated missions
│   └── temp_extract/         # Temporary extraction directory
├── modifications/             # DEPRECATED - Old approach
│   └── ...                   # (kept for reference)
├── lua-library/              # Dynamic Lua scripting system (planned)
├── knowledge/                # Documentation
│   └── miz-file-manipulation.md  # Complete reference guide
└── claudedocs/               # Claude-specific analysis and reports
    └── miz-modification-architecture.md  # Architecture plan
```

## Architecture Patterns

### MizParser-Based Modification Pattern

All modifications follow a consistent pattern:

**Core Function Pattern**:
```python
def modify_something(mission_content: str, **params) -> str:
    """
    Modify mission content using regex patterns.

    Args:
        mission_content: Raw mission file content as string
        **params: Operation-specific parameters

    Returns:
        Modified mission content as string
    """
    # 1. Find target using regex
    # 2. Extract relevant section
    # 3. Modify using string operations
    # 4. Return modified content
    pass
```

**Convenience Wrapper Pattern**:
```python
def modify_something_file(input_miz: str, output_miz: str, **params) -> None:
    """Convenience wrapper for file-based operations."""
    from miz-modifier.parsing.miz_parser import quick_modify

    def modify_func(content):
        return modify_something(content, **params)

    quick_modify(input_miz, output_miz, modify_func)
```

### Design Principles

1. **MizParser First** - All operations use MizParser extract/repackage workflow
2. **String-Based** - Work on mission content as strings, not objects
3. **Regex Patterns** - Use regex for finding/extracting Lua structures
4. **Functional** - Pure functions: content string in → modified string out
5. **Composable** - Functions can be chained together
6. **No DCS Required** - No dependencies on DCS installation
7. **Well-Tested** - Each function tested against real .miz files

### Function Organization

- **Read-only functions** - Named `list_*`, `get_*`, `find_*` (inspection only)
- **Modification functions** - Named `add_*`, `remove_*`, `modify_*`, `duplicate_*`
- **File wrappers** - All modification functions have `*_file()` versions
- **Utils** - Helper functions in `utils/` for ID management, patterns, validation

## Development Workflow

### Current Status

- ✅ Architecture design complete (MizParser-based)
- ✅ Architecture documented in CLAUDE.md
- ⏳ Implementing miz-modifier library (Phase 1 Foundation)
- ⏳ MCP server implementation
- ⏳ Mission generation pipeline
- ⏳ Unit templates and mission types

### Working with Mission Files

**Input files**: Place source .miz files in `miz-files/input/`
**Output files**: Modified/generated missions go to `miz-files/output/`
**Testing**: Always test modifications by loading in DCS World before deploying

**Important**: .miz files are just ZIP archives - you can extract them manually to inspect:
```bash
unzip mission.miz -d temp_mission/
cat temp_mission/mission  # View Lua mission data
```

### Implementation Phases

**Phase 1: Foundation** (Current)
1. Create folder structure for `miz-modifier/`
2. Move MizParser to new location
3. Implement core utilities (ID manager, patterns, validation)

**Phase 2: Core Operations**
1. Implement groups module (most critical)
2. Implement coordinates module
3. Test extensively with real .miz files

**Phase 3: Advanced Operations**
1. Implement units module
2. Implement waypoints module
3. Add comprehensive validation

**Phase 4: Future**
1. Triggers module
2. Weather/time modification
3. MCP server integration

### Mission File Manipulation Resources

**⚠️ IMPORTANT REFERENCES**:

📚 **[knowledge/miz-file-manipulation.md](knowledge/miz-file-manipulation.md)**
- Complete .miz file structure documentation
- Regex patterns and context detection techniques
- ID management and coordinate system handling
- Error handling and best practices

📐 **[claudedocs/miz-modification-architecture.md](claudedocs/miz-modification-architecture.md)**
- Complete architecture design
- API specifications for all functions
- Usage examples and patterns
- Migration guide from old approach

## Mission Generation Concepts

### Planned Mission Types

- **SEAD** (Suppression of Enemy Air Defenses)
- **CAP** (Combat Air Patrol)
- **Strike** (Ground attack missions)
- **Escort** (Protect bombers/transports)
- **CSAR** (Combat Search and Rescue)

### Dynamic Content Strategy

Missions will include embedded Lua scripts that provide:
- Random enemy spawn locations
- Variable weather conditions
- Dynamic reinforcement waves
- Adaptive AI difficulty
- Randomized loadouts

This ensures no two playthroughs are identical, dramatically increasing replayability.

## Important Technical Notes

### MIZ File Structure

- .miz files are standard ZIP archives
- Main mission data stored in `mission` file (Lua table)
- Additional files: dictionaries, map resources, custom Lua scripts
- pydcs handles serialization/deserialization automatically

### Coordinate Systems

DCS uses multiple coordinate systems:
- Latitude/Longitude (geographic)
- X/Y (map coordinates)
- MGRS (Military Grid Reference System)

The `pyproj` dependency handles transformations between these systems.

### Testing Requirements

Always verify modifications by:
1. Loading .miz file in DCS World
2. Starting mission
3. Checking for errors in DCS.log
4. Validating all units spawn correctly

### DCS Log Files

Log files for debugging Lua scripts and mission issues:

| Version | Path |
|---------|------|
| Stable | `C:\Users\mook\Saved Games\DCS\Logs\dcs.log` |
| Open Beta | `C:\Users\mook\Saved Games\DCS.openbeta\Logs\dcs.log` |

**Quick access**: `Win + R` → `%USERPROFILE%\Saved Games\DCS\Logs`

**Debug logging**: Enable with `DMS.Settings.configure({ debug = true })` - messages prefixed with `[SpawnPool]`, `[FOW]`, `[Templates]`, etc.

## MCP Server Integration (Planned)

The future MCP server will expose these tools to Claude:

- `create_mission()` - Generate new .miz from parameters
- `modify_mission()` - Edit existing .miz files
- `read_mission()` - Analyze mission structure
- `add_units()` - Add aircraft/ground/naval units
- `add_triggers()` - Add mission events and conditions
- `inject_lua_script()` - Add dynamic scripting
- `validate_mission()` - Check for structural errors
- `generate_briefing()` - Create mission briefing text

## Key Resources

### DCS Reference Documentation
- **[DCS Stores/Weapons List](https://www.airgoons.com/w/DCS_Reference/Stores_List)** - Complete reference of all weapons, stores, and CLSIDs for every aircraft
  - Essential for loadout operations and weapon configuration
  - Includes weapon names, CLSID identifiers, pylon compatibility
  - Reference when implementing `modify_pylon()` and loadout generation
- [DCS Mission Structure Wiki](https://wiki.hoggitworld.com/view/Miz_mission_structure)

### Library Documentation
- [pydcs Documentation](https://dcs.readthedocs.io/)
- [pydcs GitHub](https://github.com/pydcs/dcs)

### Project Documentation
- Project specs: `SpecSheet.md`
- Development plan: `MVP-Plan.md`

## Critical Development Rules

### 🔴 ALWAYS Use MizParser for .miz Modifications

**Rule**: All .miz file modifications MUST use the MizParser-based approach in `miz-modifier/`

**Why**:
- ✅ Works without DCS installation
- ✅ No dependency issues or errors
- ✅ Lightweight and fast
- ✅ Consistent with project architecture
- ❌ pydcs is DEPRECATED for modification operations

**Pattern to Follow**:
```python
from miz-modifier.parsing.miz_parser import MizParser
from miz-modifier.groups.remove import remove_groups_by_type

# Extract → Modify → Repackage
parser = MizParser("input.miz")
parser.extract()
content = parser.get_mission_content()
modified = remove_groups_by_type(content, ["ship"])
parser.write_mission_content(modified)
parser.repackage("output.miz")
```

**When to Use What**:
- ✅ **MizParser**: Reading, modifying, inspecting .miz files (ALWAYS)
- ❌ **pydcs**: Only for future mission generation from scratch (NOT YET IMPLEMENTED)
- ✅ **Regex patterns**: Extracting and modifying Lua structures (PRIMARY TOOL)

---

## Debug Logging Guidelines

### 🔴 REQUIRED: All Lua Modules Must Include Debug Logging

All DMS Lua modules **MUST** include debug logging for key operations. This enables mission creators to troubleshoot issues by enabling `DMS.Settings.configure({ debug = true })`.

### Standard Pattern

```lua
-- Check debug mode before logging
if DMS.Settings and DMS.Settings.isDebug() then
    env.info(string.format("[ModuleName] Action description: %s", variable))
end
```

### Log Prefix Convention

Each module uses a unique prefix in brackets:

| Module | Prefix |
|--------|--------|
| SpawnPool | `[SpawnPool]` |
| SpawnZones | `[SpawnZones]` |
| Templates | `[Templates]` |
| FogOfWar | `[FOW]` |
| Proximity | `[Proximity]` |
| SAMAmbush | `[SAMAmbush]` |
| Reinforcements | `[Reinforcements]` |
| BDA | `[BDA]` |
| Objectives | `[Objectives]` |
| Settings | `[DMS.Settings]` |

### What to Log

**Always log:**
- System start/stop with configuration summary
- Successful activations/spawns with key details
- Skipped operations with reason (e.g., failed roll)
- State changes (e.g., SAM going HOT/DARK)
- Important events (kills, objectives, waves triggered)

**Format examples:**
```lua
-- System start
env.info(string.format("[ModuleName] Started monitoring %d items (interval: %ds)", count, interval))

-- Activation with roll
env.info(string.format("[ModuleName] Activated '%s' (rolled %d <= %d)", name, roll, chance))

-- Skip with reason
env.info(string.format("[ModuleName] Skipped '%s' (rolled %d > %d)", name, roll, chance))

-- State change
env.info(string.format("[ModuleName] '%s' state changed to %s", name, newState))
```

### Fallback Pattern for Mission Scripts

For mission-specific scripts that may run without `DMS.Settings`:

```lua
local function isDebugEnabled()
    if DMS.Settings and DMS.Settings.isDebug then
        return DMS.Settings.isDebug()
    end
    return MyModule.Config.debug  -- Local fallback
end
```

---

## Lessons Learned

### [2025-12-08] Tools: Use MizParser for .miz File Operations, Not pydcs

**Context**: Creating script to extract group coordinates from .miz mission files

**Mistake**: Started implementation using pydcs/MizHandler without checking existing project patterns. Encountered errors:
- KeyError: 35 (unknown task ID in mission file)
- Liveries scanner errors requiring DCS installation
- Complex environment variable setup requirements
- Need for pydcs_patch.py to handle unknown options

**Correction**: Investigated existing scripts (`list_groups.py`, `remove_ship.py`) and found they use `MizParser` with direct Lua parsing via regex patterns. This approach:
- Works without DCS installation
- No pydcs dependency issues
- Consistent with project architecture
- Lighter weight and faster

**Lesson**: **ALWAYS check existing project scripts first** to identify established patterns before choosing implementation approach. In this project:
- **Use `MizParser`** (from `parsing/miz_parser.py`) for .miz file operations
- **Use direct Lua parsing with regex** for extracting mission data
- **Reserve pydcs** for future mission generation only (not parsing/reading)

**Detection**: When working with .miz files in this project:
1. Check `modifications/methods/` for similar scripts
2. Look for `from parsing.miz_parser import MizParser` pattern
3. Use regex patterns to extract Lua table data
4. Avoid pydcs unless generating new missions from scratch

### [2025-12-08] Tools: Environment Variables Must Be Set Before Library Imports

**Context**: Attempting to use pydcs library which scans for DCS liveries during import

**Mistake**: Set environment variables (`DCS_INSTALLATION`, `DCS_SAVED_GAMES`) after importing helper modules that themselves imported pydcs. The liveries scanner errors occurred during the import process, before our environment variable setup code could run.

**Correction**: Environment variables must be set at the very top of the script, before ANY imports that might trigger pydcs initialization:
```python
import os
# Set BEFORE any pydcs-related imports
os.environ['DCS_INSTALLATION'] = ''
os.environ['DCS_SAVED_GAMES'] = ''

# Now safe to import
from methods.pydcs_patch import apply_patch  # This imports pydcs internally
```

**Lesson**: When a library reads environment variables during initialization/import, those variables must be set before the import statement. Python imports are executed top-to-bottom, so environment setup must come first.

**Detection**:
- If library has initialization errors related to environment/configuration
- If errors occur during import rather than during function calls
- If error stack trace shows issues in module `__init__` or class definition blocks
- Set environment variables at script top, before all imports
