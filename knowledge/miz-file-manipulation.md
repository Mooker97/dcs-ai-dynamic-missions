# MIZ File Manipulation Knowledge Base

Comprehensive guide for finding, editing, and adding information to DCS World .miz mission files.

## Table of Contents
- [MIZ File Structure](#miz-file-structure)
- [Two-Tier Approach](#two-tier-approach)
- [Working with pydcs](#working-with-pydcs)
- [Parsing Workflow](#parsing-workflow)
- [Finding Information](#finding-information)
- [Editing Information](#editing-information)
- [Adding Information](#adding-information)
- [Common Patterns](#common-patterns)
- [Coordinate Systems](#coordinate-systems)
- [Error Handling](#error-handling)

---

## MIZ File Structure

### What is a .miz file?
- **Format**: Standard ZIP archive (can be opened with any ZIP tool)
- **Main file**: `mission` (no extension) - Contains Lua table with all mission data
- **Additional files**:
  - `warehouses/` - Warehouse definitions
  - `l10n/DEFAULT/` - Localization/briefing text
  - `theatre` - Theater name
  - Various resource files (map data, scripts, etc.)

### Mission File Hierarchy
```lua
mission = {
  ["coalition"] = {
    ["blue"] = {
      ["country"] = {
        [1] = {  -- USA (country ID)
          ["id"] = 2,
          ["name"] = "USA",
          ["plane"] = {
            ["group"] = {
              [1] = {  -- Group array index
                ["groupId"] = 1,
                ["name"] = "Fighter-1",
                ["units"] = { ... },
                ["route"] = { ... }
              }
            }
          },
          ["helicopter"] = { ... },
          ["ship"] = { ... },
          ["vehicle"] = { ... },
          ["static"] = { ... }
        }
      }
    },
    ["red"] = { ... },
    ["neutrals"] = { ... }
  },
  ["triggers"] = { ... },
  ["weather"] = { ... },
  ["start_time"] = ...
}
```

---

## Two-Tier Approach

### Tier 1: Lightweight Inspection (No DCS Required)
**File**: `parsing/miz_inspector.py`

**Use When**:
- Quick information extraction
- No DCS World installation available
- Read-only operations
- Basic metadata queries

**Capabilities**:
- Extract archive contents
- Parse basic mission info (name, date)
- Count coalition entries
- Export raw mission text

**Example**:
```python
from parsing.miz_inspector import LightweightMizInspector

inspector = LightweightMizInspector("mission.miz")
info = inspector.inspect()
print(info['mission_name'])
print(info['estimated_blue_entries'])
```

### Tier 2: Full Manipulation (Requires DCS/pydcs)
**File**: `miz_utils.py`

**Use When**:
- Need to modify mission files
- Full mission parsing required
- Complex operations
- Working with pydcs library

**Capabilities**:
- Complete mission parsing via pydcs
- Access all mission properties
- Modify and save missions
- Export structured JSON

**Example**:
```python
from miz_utils import MizHandler

handler = MizHandler("mission.miz")
info = handler.get_mission_info()
groups = handler.list_aircraft_groups()
handler.save("modified.miz")
```

---

## Working with pydcs

### Environment Setup
```python
import os
from pathlib import Path

# Mock DCS path to avoid liveries scanner errors
os.environ.setdefault('DCS_HOME', str(Path.home() / '.dcs'))

# Disable DCS installation detection (optional)
os.environ['DCS_INSTALLATION'] = ''
os.environ['DCS_SAVED_GAMES'] = ''

import dcs
```

### Handling Unknown Options
**File**: `methods/pydcs_patch.py`

pydcs may fail on unknown option IDs. Apply monkey patch:

```python
from methods.pydcs_patch import apply_patch

apply_patch()  # Now pydcs handles unknown options gracefully
```

**What it does**: Creates generic `Option` objects for unknown option IDs instead of crashing.

---

## Parsing Workflow

### Basic Extract → Modify → Repackage
**File**: `parsing/miz_parser.py`

```python
from parsing.miz_parser import MizParser

# 1. Extract
parser = MizParser("input.miz")
parser.extract()  # Creates temp directory

# 2. Read mission content
content = parser.get_mission_content()

# 3. Modify content (string operations)
modified_content = content.replace("old", "new")

# 4. Write back
parser.write_mission_content(modified_content)

# 5. Repackage
parser.repackage("output.miz", cleanup=True)
```

### Quick Modify Workflow
For single-function modifications:

```python
from parsing.miz_parser import quick_modify

def my_modification(mission_content: str) -> str:
    # Modify and return content
    return modified_content

quick_modify("input.miz", "output.miz", my_modification)
```

---

## Finding Information

### Context Detection Pattern
**Source**: `methods/groups/list_groups.py:29-69`

To find what coalition/unit type a piece of content belongs to:

```python
import re

def find_context(content: str, position: int, search_back: int = 250000) -> dict:
    """Find coalition and unit type for a position in content."""
    start = max(0, position - search_back)
    context_section = content[start:position]

    # Find last coalition marker (closest to position)
    coalition = None
    last_coalition_pos = -1
    for c in ['blue', 'red', 'neutrals']:
        pattern = rf'\["{c}"\]\s*='
        matches = list(re.finditer(pattern, context_section))
        if matches:
            last_match_pos = matches[-1].start()
            if last_match_pos > last_coalition_pos:
                last_coalition_pos = last_match_pos
                coalition = c

    # Find last unit type marker
    unit_type = None
    last_type_pos = -1
    for ut in ['plane', 'helicopter', 'ship', 'vehicle', 'static']:
        pattern = rf'\["{ut}"\]\s*='
        matches = list(re.finditer(pattern, context_section))
        if matches:
            last_match_pos = matches[-1].start()
            if last_match_pos > last_type_pos:
                last_type_pos = last_match_pos
                unit_type = ut

    return {'coalition': coalition, 'unit_type': unit_type}
```

**Usage Pattern**: When you find a group via regex, use `find_context()` to determine which coalition and unit type it belongs to.

### Finding Groups
**Source**: `methods/groups/list_groups.py:72-122`

```python
# Pattern: Find groups by units section + name
group_pattern = r'\["units"\]\s*=\s*\{(.*?)\},\s*--\s*end\s*of\s*\["units"\]\s*\n(?:.*?\n){0,5}?\s*\["name"\]\s*=\s*"([^"]+)"'

matches = re.finditer(group_pattern, mission_content, re.DOTALL)

for match in matches:
    units_content = match.group(1)
    group_name = match.group(2)
    position = match.start()

    # Get context
    context = find_context(mission_content, position)
    coalition = context['coalition']
    unit_type = context['unit_type']
```

### Finding Unit Type Sections
**Source**: `methods/remove_groups.py:43-67`

```python
# Find unit type section
unit_type = 'ship'  # or 'plane', 'helicopter', 'vehicle', 'static'

unit_start_pattern = rf'(\["{unit_type}"\]\s*=\s*\n)'
unit_end_pattern = rf'(\}},\s*--\s*end\s*of\s*\["{unit_type}"\])'

if re.search(unit_start_pattern, content) and re.search(unit_end_pattern, content):
    # Section exists
    pattern = rf'(\["{unit_type}"\]\s*=\s*\n)(\s*\{{.*?\}}),(\s*--\s*end\s*of\s*\["{unit_type}"\])'
    match = re.search(pattern, content, re.DOTALL)
```

### Finding Max IDs
**Source**: `methods/groups/add_group.py:65-78`

Before adding new groups/units, find the maximum IDs:

```python
def find_max_ids(mission_content: str) -> dict:
    """Find maximum groupId and unitId in mission."""
    group_ids = re.findall(r'\["groupId"\]\s*=\s*(\d+)', mission_content)
    unit_ids = re.findall(r'\["unitId"\]\s*=\s*(\d+)', mission_content)

    max_group_id = max([int(gid) for gid in group_ids]) if group_ids else 0
    max_unit_id = max([int(uid) for uid in unit_ids]) if unit_ids else 0

    return {'max_group_id': max_group_id, 'max_unit_id': max_unit_id}
```

---

## Editing Information

### Removing Groups Pattern
**Source**: `methods/remove_groups.py:23-74`

```python
def remove_groups_from_content(mission_content: str, unit_types: list) -> str:
    """Remove specified unit group types."""
    modified_content = mission_content

    for unit_type in unit_types:
        # Find section
        pattern = rf'(\["{unit_type}"\]\s*=\s*\n)(\s*\{{.*?\}}),(\s*--\s*end\s*of\s*\["{unit_type}"\])'

        def replace_unit(match):
            # Keep opening/closing, replace middle with empty group
            indent = '\t\t\t\t\t'
            return f'{match.group(1)}{indent}{{\n{indent}}},{match.group(3)}'

        modified_content = re.sub(pattern, replace_unit, modified_content, flags=re.DOTALL)

    return modified_content
```

### String Replacement Pattern
```python
# Basic find/replace
modified = content.replace("old_value", "new_value")

# Regex replacement with capture groups
modified = re.sub(
    r'(\["parameter"\]\s*=\s*)"old"',
    r'\1"new"',
    content
)
```

---

## Adding Information

### Adding Groups Pattern
**Source**: `methods/groups/add_group.py:236-346`

**Key Steps**:
1. Find max groupId and unitId
2. Generate new IDs (max + 1)
3. Find target section (coalition + unit_type)
4. Find highest group index in section
5. Generate Lua code for new group
6. Insert at end of groups section

```python
def add_group_to_content(mission_content: str, group_name: str,
                        unit_type_category: str, unit_type: str,
                        x: float, y: float, heading: float = 0.0,
                        coalition: str = 'blue') -> str:
    """Add new group to mission."""

    # 1. Find max IDs
    ids = find_max_ids(mission_content)
    new_group_id = ids['max_group_id'] + 1
    new_unit_id = ids['max_unit_id'] + 1

    # 2. Generate group Lua code
    group_lua = generate_group_lua(
        group_name, unit_type_category, unit_type,
        x, y, heading, coalition, new_group_id, new_unit_id
    )

    # 3. Find target section
    # First find main coalition section
    main_coalition_pattern = r'\["coalition"\]\s*=\s*\{(.*?)\},\s*--\s*end\s*of\s*\["coalition"\]'
    main_match = re.search(main_coalition_pattern, mission_content, re.DOTALL)

    # Then find specific coalition within it
    coalition_pattern = rf'\["{coalition}"\]\s*=\s*\{{(.*?)\}},\s*--\s*end\s*of\s*\["{coalition}"\]'
    coalition_match = re.search(coalition_pattern, main_match.group(1), re.DOTALL)

    # Find unit type section
    pattern = rf'(\["{unit_type_category}"\]\s*=\s*\n\s*\{{\s*\n\s*\["group"\]\s*=\s*\n\s*\{{)(.*?)(\}},\s*--\s*end\s*of\s*\["group"\])'
    match = re.search(pattern, coalition_match.group(1), re.DOTALL)

    # 4. Find highest group index
    groups_section = match.group(2)
    group_indices = re.findall(r'\[(\d+)\]\s*=', groups_section)
    new_index = max([int(idx) for idx in group_indices]) + 1 if group_indices else 1

    # 5. Replace index placeholder
    group_lua = group_lua.replace('{NEW_GROUP_INDEX}', str(new_index))

    # 6. Insert new group
    new_groups_section = match.group(2) + group_lua + '\n\t\t\t\t\t\t'
    modified_content = mission_content[:abs_match_start] + new_groups_section + mission_content[abs_match_end:]

    return modified_content
```

---

## Common Patterns

### Unit Type Categories and Required Fields
**Source**: `methods/groups/add_group.py:20-60`

```python
UNIT_TYPES = {
    'plane': {
        'example_types': ['F-16C_50', 'F-15C', 'Su-27', 'A-10C'],
        'fields': {
            'skill': 'Average',
            'speed': 150.0,  # m/s
            'alt': 2000.0,   # meters
            'alt_type': 'BARO',
            'task': 'CAP'
        }
    },
    'helicopter': {
        'example_types': ['UH-1H', 'Mi-8MT', 'AH-64D', 'Ka-50'],
        'fields': {
            'skill': 'Average',
            'speed': 50.0,
            'alt': 500.0,
            'task': 'Transport'
        }
    },
    'ship': {
        'example_types': ['CHAP_Project22160', 'CVN_71', 'LHA_Tarawa'],
        'fields': {
            'skill': 'Average',
            'speed': 0.0,
            'modulation': 0,
            'frequency': 127500000
        }
    },
    'vehicle': {
        'example_types': ['M-1 Abrams', 'T-72B', 'BMP-3', 'M-113'],
        'fields': {
            'skill': 'Average',
            'speed': 0.0,
            'task': 'Ground Nothing'
        }
    }
}
```

### Coalition Names
```python
COALITIONS = ['blue', 'red', 'neutrals']
```

### Lua Structure Template
```lua
[index] = {
    ["visible"] = true,
    ["tasks"] = {},
    ["uncontrolled"] = false,
    ["groupId"] = 123,
    ["hidden"] = false,
    ["units"] = {
        [1] = {
            ["type"] = "F-16C_50",
            ["unitId"] = 456,
            ["skill"] = "Average",
            ["x"] = -50000,
            ["y"] = 30000,
            ["heading"] = 0,
            ["name"] = "Fighter-1-1",
            -- type-specific fields
        }
    },
    ["y"] = 30000,
    ["x"] = -50000,
    ["name"] = "Fighter-1",
    ["start_time"] = 0,
    ["route"] = { ... }
}
```

---

## Coordinate Systems

### DCS Coordinate System
- **X**: East-West (meters from map origin)
- **Y**: North-South (meters from map origin)
- **Z (altitude)**: Height above sea level (meters)
- **Heading**: Radians (0 = North, π/2 = East, π = South, 3π/2 = West)

### Common Coordinate Operations
```python
import math

# Convert degrees to radians
heading_rad = math.radians(90)  # 90° East

# Convert radians to degrees
heading_deg = math.degrees(1.57)  # ~90°

# Calculate offset position
def offset_position(x, y, distance, heading):
    """Move distance meters in heading direction."""
    new_x = x + distance * math.sin(heading)
    new_y = y + distance * math.cos(heading)
    return new_x, new_y
```

### Altitude Types
- `"BARO"`: Barometric altitude (AGL - Above Ground Level)
- `"RADIO"`: Radar altitude (height above terrain)

---

## Error Handling

### Common Issues

**1. pydcs Liveries Scanner Error**
```
KeyError: 'country_list'
```
**Solution**: Set mock DCS_HOME before importing dcs
```python
os.environ.setdefault('DCS_HOME', str(Path.home() / '.dcs'))
```

**2. Unknown Option IDs**
```
KeyError: 'SOME_OPTION_ID'
```
**Solution**: Apply pydcs patch
```python
from methods.pydcs_patch import apply_patch
apply_patch()
```

**3. Invalid Lua After Modification**
```
DCS fails to load mission
```
**Solution**:
- Preserve exact indentation (tabs/spaces)
- Keep comment markers: `-- end of ["section"]`
- Validate Lua structure before repackaging

**4. ID Conflicts**
```
Groups/units fail to spawn
```
**Solution**: Always find max IDs and increment
```python
ids = find_max_ids(mission_content)
new_id = ids['max_group_id'] + 1
```

### Safe Modification Checklist
- ✅ Always work on backup copies
- ✅ Find max IDs before adding groups/units
- ✅ Preserve Lua structure and indentation
- ✅ Keep end-of-section comments intact
- ✅ Test mission in DCS after modification
- ✅ Check DCS.log for errors
- ✅ Clean up temp directories after repackaging

---

## Quick Reference

### File Locations
```
modifications/
├── miz_utils.py              # Full pydcs handler
├── parsing/
│   ├── miz_inspector.py      # Lightweight inspector
│   └── miz_parser.py         # Extract/repackage workflow
├── methods/
│   ├── pydcs_patch.py        # pydcs error fix
│   ├── remove_groups.py      # Remove unit types
│   ├── remove_ship.py        # Remove ships (wrapper)
│   └── groups/
│       ├── list_groups.py    # List all groups
│       ├── add_group.py      # Add new groups
│       └── coords/
│           └── get_for_group.py  # Get group coordinates
```

### Command-Line Tools
```bash
# Lightweight inspection
python parsing/miz_inspector.py "mission.miz"

# Full inspection (pydcs)
python miz_utils.py "mission.miz"

# Extract mission
python parsing/miz_parser.py extract "mission.miz" "temp_dir"

# Repackage mission
python parsing/miz_parser.py repackage "temp_dir" "output.miz"

# List all groups
python methods/groups/list_groups.py "mission.miz" -v

# Remove ships
python methods/remove_ship.py "input.miz" "output.miz"

# Remove multiple types
python methods/remove_groups.py "ship,vehicle" "input.miz" "output.miz"

# Add group
python methods/groups/add_group.py "Fighter-1" plane F-16C_50 -50000 30000 blue "input.miz" "output.miz"
```

### Import Patterns
```python
# For lightweight operations
from parsing.miz_inspector import LightweightMizInspector

# For full manipulation
from miz_utils import MizHandler

# For string-based modifications
from parsing.miz_parser import MizParser, quick_modify

# For specific operations
from methods.remove_groups import remove_groups_from_content
from methods.groups.add_group import add_group_to_content
from methods.groups.list_groups import list_all_groups
```

---

## Best Practices

1. **Choose the Right Tool**:
   - **PREFER `miz_parser.py`** for most operations (extraction, parsing, modification)
   - Use `miz_inspector.py` for quick read-only checks when you don't need to extract
   - **AVOID `miz_utils.py` (pydcs)** for reading/parsing - it has dependency issues and requires DCS installation
   - **RESERVE pydcs** for future mission generation from scratch only

2. **ID Management**:
   - Always find max IDs before adding entities
   - Never reuse IDs within the same mission
   - groupId and unitId must be globally unique

3. **String Operations**:
   - Use `re.DOTALL` flag for multi-line patterns
   - Preserve whitespace and indentation exactly
   - Keep Lua comment markers intact

4. **Testing**:
   - Always test in DCS World after modifications
   - Check DCS.log for errors
   - Verify all groups spawn correctly

5. **Error Recovery**:
   - Keep backups of original missions
   - Use try/finally for temp directory cleanup
   - Apply pydcs patch if needed

6. **Performance**:
   - Use lightweight inspector for quick checks
   - Cache mission content for multiple operations
   - Clean up temp directories promptly

---

## Lessons Learned

### Why Prefer MizParser Over pydcs?

**Problem**: pydcs was initially used for reading/parsing .miz files but caused multiple issues:
- **KeyError: 35** - Unknown task IDs in mission files crash pydcs
- **Liveries scanner errors** - Requires DCS installation and proper environment setup
- **Import-time initialization** - Errors occur during import, before you can handle them
- **Brittle dependencies** - Requires patches (`pydcs_patch.py`) to work with real missions

**Solution**: Use `MizParser` with direct Lua parsing (regex patterns):
- **No dependencies** - Works without DCS installation
- **Robust** - Handles any mission file format
- **Consistent** - All existing project scripts use this pattern
- **Faster** - Lighter weight than full pydcs parsing

**Pattern**: See `methods/groups/list_groups.py` for reference implementation.

### When to Use Each Tool

| Task | Tool | Reason |
|------|------|--------|
| Extract group coordinates | `MizParser` + regex | Existing pattern, no dependencies |
| List all groups | `MizParser` + regex | Proven pattern in `list_groups.py` |
| Remove groups | `MizParser` + regex | String manipulation sufficient |
| Read mission metadata | `miz_inspector.py` | Quick, no extraction needed |
| Generate NEW mission | pydcs (future) | Build from scratch, not parsing |
| Parse EXISTING mission | **NEVER pydcs** | Use `MizParser` instead |

### Environment Variable Gotcha

If you must use pydcs, remember:
```python
import os
# MUST be set BEFORE any pydcs imports
os.environ['DCS_INSTALLATION'] = ''
os.environ['DCS_SAVED_GAMES'] = ''
os.environ.setdefault('DCS_HOME', str(Path.home() / '.dcs'))

# Now safe to import
import dcs
```

Environment variables are read during module initialization, so they must be set before the import statement.

---

## Lessons Learned from Waypoint Extraction (December 2024)

### The Problem: Two Failed Approaches

**Attempt 1: pydcs-based waypoint extraction (`get_waypoints.py`)**
- ✅ Clean, type-safe API
- ✅ Complete CLI with filtering and JSON export
- ❌ **FAILED**: `KeyError: 35` - Mission contains unknown task ID
- ❌ Cannot parse real-world mission files with custom tasks

**Attempt 2: Direct Lua regex parsing (`get_waypoints_lite.py`)**
- ✅ No dependencies, works without DCS
- ✅ Should handle any mission format
- ❌ **FAILED**: Nested Lua table regex patterns too complex
- ❌ Multiple levels of nesting ([coalition][blue][country][1][plane][group][1][route][points])
- ❌ Regex not powerful enough for arbitrary nesting depth

### Critical Mistakes Made

#### 1. Started Coding Before Understanding Structure
**Mistake**: Wrote regex patterns based on assumptions about Lua structure
**Result**: Patterns didn't match actual mission file format
**Should Have Done**:
```bash
# Extract and inspect FIRST
python parsing/miz_parser.py extract "mission.miz" "temp"
# Read the actual structure
less temp/mission
# THEN write patterns
```

#### 2. Used Windows-Incompatible Output
**Mistake**: Used Unicode emojis in print statements (✅, ❌, 📍)
**Result**: `UnicodeEncodeError: 'charmap' codec can't encode character`
**Solution**: Plain ASCII only
```python
# DON'T:
print(f"✅ Success")

# DO:
print(f"[OK] Success")
print(f"[ERROR] Failed")
print(f"> Group Name")
```

#### 3. Trusted pydcs Too Much
**Mistake**: Assumed pydcs could handle any mission file
**Reality**: pydcs is designed for missions it generates, not arbitrary real-world missions
**Result**: Crashes on unknown task IDs, options, or configurations
**Lesson**: **pydcs is for GENERATION, not PARSING**

#### 4. Regex for Complex Nested Structures
**Mistake**: Attempted to parse deeply nested Lua tables with regex
```python
# This doesn't work reliably:
pattern = r'\[(\d+)\]\s*=\s*\{((?:[^{}]|\{(?:[^{}]|\{[^{}]*\})*\})*)\}'
```
**Reality**: Lua tables can nest arbitrarily deep, regex cannot reliably match this
**Lesson**: For complex parsing, use a proper parser

### The Right Solution for Future Work

#### Option 1: Use slpp (Lua Parser)
```python
import slpp

# Parse Lua to Python dict
mission_dict = slpp.slpp.decode(mission_content)

# Navigate naturally
for country in mission_dict['coalition']['blue']['country']:
    for group in country['plane']['group']:
        waypoints = group['route']['points']
```

**Pros**:
- Handles any Lua structure
- Python dict navigation
- Reliable and maintainable

**Cons**:
- Another dependency
- Must handle Lua-specific syntax (comments, etc.)

#### Option 2: Simpler Targeted Regex
**Instead of**: Trying to match entire nested structures
**Do**: Match specific fields at specific levels

```python
# BAD: Try to match entire group structure
group_pattern = r'\[(\d+)\]\s*=\s*\{(.*?)\},\s*--\s*end'  # Too broad

# GOOD: Match specific waypoint fields directly
def find_waypoints_in_route_section(route_section: str):
    """Given a route section, extract waypoints."""
    waypoints = []

    # Find each [1] =, [2] =, etc.
    wp_starts = list(re.finditer(r'\[(\d+)\]\s*=\s*\{', route_section))

    for i, match in enumerate(wp_starts):
        wp_index = int(match.group(1))
        start = match.end()

        # Find matching }
        if i < len(wp_starts) - 1:
            end = wp_starts[i + 1].start()
        else:
            end = route_section.rfind('}')

        wp_content = route_section[start:end]

        # Now extract fields from flat string
        waypoints.append({
            'index': wp_index,
            'x': extract_field(wp_content, 'x', float),
            'y': extract_field(wp_content, 'y', float),
            'alt': extract_field(wp_content, 'alt', float),
            'speed': extract_field(wp_content, 'speed', float),
            'action': extract_field(wp_content, 'action', str)
        })

    return waypoints

def extract_field(content: str, field_name: str, field_type):
    """Extract single field value."""
    if field_type == str:
        pattern = rf'\["{field_name}"\]\s*=\s*"([^"]+)"'
    else:
        pattern = rf'\["{field_name}"\]\s*=\s*([-\d.]+)'

    match = re.search(pattern, content)
    return field_type(match.group(1)) if match else None
```

#### Option 3: Hybrid Approach (RECOMMENDED)
Use MizParser + string finding + simple regex:

```python
parser = MizParser("mission.miz")
parser.extract()
content = parser.get_mission_content()

# 1. Find section boundaries with simple string finding
coalition_start = content.find('["blue"] =')
coalition_end = content.find('}, -- end of ["blue"]', coalition_start)
blue_section = content[coalition_start:coalition_end]

# 2. Find plane groups section
plane_start = blue_section.find('["plane"] =')
plane_end = blue_section.find('}, -- end of ["plane"]', plane_start)
plane_section = blue_section[plane_start:plane_end]

# 3. Find each "route" section
for route_match in re.finditer(r'\["route"\]\s*=\s*\{', plane_section):
    route_start = route_match.end()
    route_end = plane_section.find('}, -- end of ["route"]', route_start)
    route_section = plane_section[route_start:route_end]

    # 4. Extract waypoints from this specific section
    waypoints = find_waypoints_in_route_section(route_section)
```

**Why This Works**:
- Uses string finding for section boundaries (fast, reliable)
- Only uses regex for leaf-level data extraction
- Doesn't try to match complex nested structures
- Follows natural Lua file structure

### Development Process Best Practices

#### Before Writing Any Code:

1. **Extract and Inspect**:
```bash
python parsing/miz_parser.py extract "test.miz" "inspect"
cat inspect/mission | less
# or grep for specific sections
grep -n "route" inspect/mission
```

2. **Identify Structure Levels**:
```
Level 1: ["coalition"]
Level 2: ["blue"], ["red"]
Level 3: ["country"]
Level 4: Country array [1], [2], ...
Level 5: ["plane"], ["helicopter"], ["ship"], ["vehicle"]
Level 6: ["group"]
Level 7: Group array [1], [2], ...
Level 8: ["route"]
Level 9: ["points"]
Level 10: Point array [1], [2], ...
Level 11: Individual fields (x, y, alt, speed)
```

3. **Build Patterns Incrementally**:
```python
# Test each level separately
def test_pattern():
    # Level 1
    assert re.search(r'\["coalition"\]', content)

    # Level 2
    assert re.search(r'\["blue"\]\s*=', content)

    # Level 3
    assert re.search(r'\["country"\]\s*=', content)

    # etc.
```

4. **Create Debug Script**:
```python
# debug_parse.py
def debug_parse(miz_path):
    """Print what sections are found."""
    parser = MizParser(miz_path)
    parser.extract()
    content = parser.get_mission_content()

    print(f"Coalition sections: {len(re.findall(r'\\[\"coalition\"\\]', content))}")
    print(f"Blue sections: {len(re.findall(r'\\[\"blue\"\\]', content))}")
    print(f"Route sections: {len(re.findall(r'\\[\"route\"\\]', content))}")
    print(f"Points sections: {len(re.findall(r'\\[\"points\"\\]', content))}")

    # Sample of what was found
    route_match = re.search(r'\["route"\]\s*=\s*\{(.{200})', content, re.DOTALL)
    if route_match:
        print("Sample route section:")
        print(route_match.group(1))
```

5. **Only Then Write Full Script**

### Windows-Specific Considerations

#### Console Encoding Issues
```python
# Problem: Windows cmd uses cp1252, can't handle Unicode
print("✅ Success")  # UnicodeEncodeError

# Solutions:
# 1. ASCII only (RECOMMENDED)
print("[OK] Success")

# 2. Force UTF-8 (doesn't work in all environments)
import sys
sys.stdout.reconfigure(encoding='utf-8')

# 3. Suppress errors (loses information)
print(str.encode('✅', 'ascii', 'ignore').decode())
```

#### Path Handling
```python
# DON'T: Forward slashes in Windows
path = "../miz-files/input/mission.miz"  # May fail

# DO: Use Path objects
from pathlib import Path
path = Path("..") / "miz-files" / "input" / "mission.miz"
```

### Testing Strategy

#### Minimum Viable Test
```python
def test_waypoint_extraction():
    """One test that catches most issues."""
    # 1. Extract known mission
    result = extract_waypoints("test.miz")

    # 2. Verify structure
    assert 'groups' in result
    assert 'blue' in result['groups']

    # 3. Check specific data
    blue_aircraft = result['groups']['blue']['aircraft']
    assert len(blue_aircraft) > 0

    # 4. Verify waypoint fields
    first_group = blue_aircraft[0]
    assert 'waypoints' in first_group
    assert len(first_group['waypoints']) > 0

    first_wp = first_group['waypoints'][0]
    assert 'x' in first_wp
    assert 'y' in first_wp
    assert 'alt' in first_wp
    assert isinstance(first_wp['x'], float)
```

### Key Takeaways

1. **Inspect before coding** - Always examine actual file structure first
2. **pydcs for generation only** - Not for parsing existing missions
3. **Simple patterns** - String finding + simple regex beats complex nested patterns
4. **Windows compatibility** - ASCII output, Path objects, test on Windows
5. **Incremental development** - Build and test one level at a time
6. **Debug tools** - Create small test scripts to validate patterns
7. **Consider alternatives** - Lua parser libraries may be better than regex
8. **Follow existing patterns** - See `methods/groups/list_groups.py` for proven approach

### Recommended Pattern for Future Scripts

```python
#!/usr/bin/env python3
"""Script description"""

import re
import sys
from pathlib import Path
from typing import Dict, List, Any

# Add parent to path
sys.path.insert(0, str(Path(__file__).parent.parent))
from parsing.miz_parser import MizParser

def extract_data(miz_path: str) -> Dict[str, Any]:
    """Main extraction logic."""
    # 1. Extract
    parser = MizParser(miz_path)
    try:
        parser.extract()
        content = parser.get_mission_content()
    finally:
        parser.cleanup()

    # 2. Find sections with string finding (fast, reliable)
    section_start = content.find('["target_section"]')
    section_end = content.find('-- end of ["target_section"]', section_start)
    section = content[section_start:section_end]

    # 3. Extract data with simple regex (only leaf-level patterns)
    items = []
    for match in re.finditer(r'\["field"\]\s*=\s*"([^"]+)"', section):
        items.append(match.group(1))

    return {'items': items}

def main():
    """CLI interface."""
    import argparse
    parser = argparse.ArgumentParser(description='...')
    parser.add_argument('miz_file')
    # Add other args

    args = parser.parse_args()

    # Validate
    if not Path(args.miz_file).exists():
        print(f"[ERROR] File not found: {args.miz_file}")
        sys.exit(1)

    # Extract
    try:
        data = extract_data(args.miz_file)
    except Exception as e:
        print(f"[ERROR] Extraction failed: {e}")
        sys.exit(1)

    # Output (ASCII only)
    print("[OK] Extraction complete")
    print(f"Found {len(data['items'])} items")

if __name__ == "__main__":
    main()
```

This pattern:
- ✅ Uses MizParser (proven, dependency-free)
- ✅ String finding for sections (fast, reliable)
- ✅ Simple regex for data (maintainable)
- ✅ ASCII output (Windows-compatible)
- ✅ Path objects (cross-platform)
- ✅ Error handling (cleanup, user-friendly messages)
- ✅ Follows project conventions
