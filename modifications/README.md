# MIZ Modifications

This folder contains utilities for reading, parsing, and modifying DCS World mission (.miz) files.

## Architecture

The modification system is organized into two main components:

### 📦 Parsing (`parsing/`)
Handles extraction and repackaging of .miz files (ZIP archives containing Lua mission files).

### ⚙️ Methods (`methods/`)
Contains modification functions that alter mission content between extraction and repackaging.

### Workflow
```
Input .miz → Extract → Modify → Repackage → Output .miz
              ↑                    ↑
          parsing/             methods/
```

## Setup

### Install Dependencies

```bash
pip install -r requirements.txt
```

This installs:
- `pydcs` - Python library for DCS mission file manipulation
- `pyproj` - Required dependency for coordinate transformations

## File Structure

```
modifications/
├── parsing/
│   ├── miz_parser.py         # Core extraction/repackaging functionality
│   └── miz_inspector.py      # Lightweight mission inspection tool
├── methods/
│   ├── groups/
│   │   ├── add_group.py      # Add new unit groups to missions
│   │   └── list_groups.py    # List all groups in a mission
│   ├── remove_groups.py      # Remove any unit/group types (generic)
│   ├── remove_ship.py        # Convenience wrapper for removing ships
│   └── pydcs_patch.py        # Compatibility patches for pydcs
├── miz_utils.py              # Full-featured MizHandler class (legacy)
├── example.py                # Example usage scripts
├── requirements.txt          # Python dependencies
└── README.md                 # This file
```

## Quick Start

### Inspect a Mission (Lightweight)

Inspect a .miz file without modifying it:

```bash
python parsing/miz_inspector.py "../miz-files/input/f16 A-G.miz"
```

### Remove Unit Groups from Mission

Remove any type of unit groups (ships, planes, helicopters, vehicles):

```bash
# Remove ships only
python methods/remove_groups.py ship "../miz-files/input/f16 A-G.miz" "../miz-files/output/no_ships.miz"

# Remove multiple types
python methods/remove_groups.py "ship,vehicle" "../miz-files/input/mission.miz" "../miz-files/output/modified.miz"

# Remove all unit types
python methods/remove_groups.py all "../miz-files/input/mission.miz" "../miz-files/output/empty.miz"

# Convenience shortcut for ships
python methods/remove_ship.py "../miz-files/input/f16 A-G.miz" "../miz-files/output/no_ships.miz"
```

### List Groups in Mission

List all unit groups present in a mission file:

```bash
# Basic summary
python methods/groups/list_groups.py "../miz-files/input/f16 A-G.miz"

# Detailed information showing each group
python methods/groups/list_groups.py "../miz-files/input/f16 A-G.miz" -v

# JSON output for programmatic use
python methods/groups/list_groups.py "../miz-files/input/f16 A-G.miz" --json
```

**Output shows:**
- Groups organized by coalition (blue, red, neutrals)
- Groups organized by type (planes, helicopters, ships, vehicles, static)
- Unit counts per group
- Specific unit types (e.g., F-16C_50, Mi-8MT)

### Add Group to Mission

Add a new unit group to a mission file with minimal configuration:

```bash
# Add a plane group
python methods/groups/add_group.py "Fighter-1" plane F-16C_50 -50000 30000 blue "../miz-files/input/mission.miz" "../miz-files/output/modified.miz"

# Add a vehicle group with heading
python methods/groups/add_group.py "Tank-1" vehicle "M-1 Abrams" 10000 -5000 red "../miz-files/input/mission.miz" "../miz-files/output/modified.miz" 1.57

# Add a ship (output file optional)
python methods/groups/add_group.py "Ship-1" ship CVN_71 0 0 blue "mission.miz"
```

**Arguments:**
- `group_name`: Name for the new group
- `type_category`: plane, helicopter, ship, or vehicle
- `unit_type`: Specific unit type (e.g., F-16C_50, Mi-8MT, CVN_71, M-1 Abrams)
- `x`: X coordinate in meters
- `y`: Y coordinate in meters
- `coalition`: blue, red, or neutrals
- `input.miz`: Input mission file
- `output.miz`: Output file (optional, defaults to input_with_group.miz)
- `heading`: Heading in radians (optional, defaults to 0)

**Supported Unit Types:**
- **Planes**: F-16C_50, F-15C, Su-27, MiG-29S, A-10C
- **Helicopters**: UH-1H, Mi-8MT, AH-64D, Ka-50
- **Ships**: CHAP_Project22160, CVN_71, LHA_Tarawa
- **Vehicles**: M-1 Abrams, T-72B, BMP-3, M-113

**How it works:**
- Creates a minimal group with one unit at the specified position
- Automatically assigns unique groupId and unitId
- Creates one starting waypoint at the unit's position
- Uses appropriate defaults for unit type (speed, altitude, skill level)

## Parsing Module Usage

### MizParser Class

The `MizParser` class provides clean extract/modify/repackage workflow:

```python
from parsing.miz_parser import MizParser

# Create parser
parser = MizParser("../miz-files/input/mission.miz")

# Extract mission
parser.extract()  # Creates temp directory

# Read mission content
content = parser.get_mission_content()

# Modify content
modified_content = content.replace("old", "new")

# Write modified content
parser.write_mission_content(modified_content)

# Repackage and cleanup
parser.repackage("../miz-files/output/modified.miz", cleanup=True)
```

### Quick Modify Workflow

For simple modifications, use the `quick_modify` helper:

```python
from parsing.miz_parser import quick_modify

def my_modification(mission_content: str) -> str:
    # Modify and return mission content
    return mission_content.replace("old", "new")

quick_modify("input.miz", "output.miz", my_modification)
```

### Command Line Usage

Extract a mission:
```bash
python parsing/miz_parser.py extract "../miz-files/input/mission.miz" "temp_mission"
```

Repackage after modifications:
```bash
python parsing/miz_parser.py repackage "temp_mission" "../miz-files/output/modified.miz"
```

## Methods Usage

Methods are organized as individual modification functions that work with the parsing workflow.

### Remove Groups (Generic)

Remove any type of unit groups from a mission file:

**Command Line:**
```bash
# Remove specific type
python methods/remove_groups.py ship "../miz-files/input/mission.miz" "../miz-files/output/modified.miz"

# Remove multiple types (comma-separated)
python methods/remove_groups.py "ship,vehicle,helicopter" "input.miz" "output.miz"

# Remove all unit types
python methods/remove_groups.py all "input.miz" "output.miz"
```

**Supported Unit Types:**
- `plane` - Fixed-wing aircraft
- `helicopter` - Rotary-wing aircraft
- `ship` - Naval vessels
- `vehicle` - Ground vehicles
- `static` - Static objects
- `all` - All of the above

**How it works:**
- Extracts mission file
- Uses regex to find and remove specified unit type sections from Lua
- Repackages modified mission
- No DCS installation required

**In Python:**
```python
from methods.remove_groups import remove_groups_from_content
from parsing.miz_parser import quick_modify

def modify(content):
    return remove_groups_from_content(content, ['ship', 'vehicle'])

quick_modify("input.miz", "output.miz", modify)
```

### Remove Ships (Convenience)

Quick shortcut for removing ships only:

```bash
python methods/remove_ship.py "../miz-files/input/f16 A-G.miz" "../miz-files/output/no_ships.miz"
```

This is a convenience wrapper around `remove_groups.py` with the ship type pre-selected.

## Creating New Modification Methods

To create a new modification method:

1. Create a new file in `methods/` folder
2. Define a function that takes mission content and returns modified content:

```python
#!/usr/bin/env python3
"""My custom modification method."""

import sys
import os
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..'))

from parsing.miz_parser import quick_modify

def my_modification(mission_content: str) -> str:
    """Modify mission content."""
    # Your modification logic here
    modified_content = mission_content  # ... modifications ...
    return modified_content

if __name__ == "__main__":
    input_miz = sys.argv[1]
    output_miz = sys.argv[2]
    quick_modify(input_miz, output_miz, my_modification)
```

3. Use it from command line:
```bash
python methods/my_method.py "input.miz" "output.miz"
```

## Legacy Tools

### MizHandler Class (miz_utils.py)

Full-featured class using pydcs (requires DCS installation):

```python
from miz_utils import MizHandler

handler = MizHandler("../miz-files/input/mission.miz")
info = handler.get_mission_info()
groups = handler.list_aircraft_groups()
handler.export_to_json("mission_data.json")
```

**Note:** This approach may have compatibility issues with newer mission formats. The parsing/methods workflow is recommended for most use cases.

## Experimental / Non-Functional Scripts

### Waypoint Extraction (Incomplete)

Two waypoint extraction scripts exist as **learning examples** but are currently non-functional:

- `get_waypoints.py` - pydcs-based approach
  - **Status**: ❌ Non-functional
  - **Issue**: Fails with `KeyError: 35` on real mission files (unknown task IDs)
  - **Lesson**: pydcs is for generation, not parsing existing missions

- `get_waypoints_lite.py` - Direct Lua parsing approach
  - **Status**: 🚧 Incomplete
  - **Issue**: Regex patterns too complex for nested Lua structures
  - **Lesson**: Need Lua parser library OR hybrid string-finding approach

See `README_waypoints.md` for detailed explanation of both approaches and why they failed.

**For comprehensive lessons learned**, see:
- `../knowledge/miz-file-manipulation.md` - Section: "Lessons Learned from Waypoint Extraction"
- `../claudedocs/waypoint-extraction-lessons.md` - Full development experience summary

**Key Takeaways for Future Development**:
1. Always extract and inspect mission files FIRST before writing code
2. Use MizParser + string finding + simple regex (not complex nested patterns)
3. Reserve pydcs for mission generation, not parsing existing missions
4. Windows: Use ASCII output only (no Unicode emojis), Path objects
5. Build patterns incrementally with debug scripts

**Recommended Solution** (not implemented):
- Use `slpp` Lua parser library for clean Python dict navigation, OR
- Use hybrid approach: string finding for sections + simple regex for leaf data
- See knowledge base for working code examples

## Resources

- [pydcs Documentation](https://dcs.readthedocs.io/)
- [pydcs GitHub](https://github.com/pydcs/dcs)
- [DCS Mission Structure Wiki](https://wiki.hoggitworld.com/view/Miz_mission_structure)

## Notes

- .miz files are ZIP archives containing Lua mission files and resources
- Always test modifications on backup copies of mission files
- Keep original .miz files in `../miz-files/input/` directory
- Modified missions are saved to `../miz-files/output/` directory
- The parsing/methods separation allows for clean, reusable modification workflows
