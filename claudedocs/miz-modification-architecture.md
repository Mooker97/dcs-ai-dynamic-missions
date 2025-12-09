# MIZ File Modification Architecture Plan

## Overview
Unified architecture for .miz file modification using MizParser as the foundation.

**Location**: `miz-file-modification/` (new folder, replacing `modifications/`)

**Philosophy**:
- MizParser-based: Extract → Modify string → Repackage
- Simple regex patterns on Lua text
- No DCS installation required
- Pure Python functions returning modified content strings

---

## Folder Structure

```
miz-file-modification/
├── __init__.py                 # Package initialization
├── core.py                     # Core modification utilities
│
├── groups/
│   ├── __init__.py
│   ├── list.py                 # List groups (read-only)
│   ├── add.py                  # Add new groups
│   ├── remove.py               # Remove groups
│   ├── duplicate.py            # Duplicate existing groups
│   └── modify.py               # Modify group properties
│
├── units/
│   ├── __init__.py
│   ├── add.py                  # Add units to groups
│   ├── remove.py               # Remove units from groups
│   └── modify.py               # Modify unit properties (loadout, position, etc)
│
├── waypoints/
│   ├── __init__.py
│   ├── list.py                 # List waypoints (read-only)
│   ├── add.py                  # Add waypoints to routes
│   ├── remove.py               # Remove waypoints
│   └── modify.py               # Modify waypoint properties
│
├── coordinates/
│   ├── __init__.py
│   ├── extract.py              # Get coordinates from groups/units
│   └── transform.py            # Coordinate transformations (lat/lon ↔ x/y)
│
├── triggers/                   # Future: trigger manipulation
│   └── __init__.py
│
├── utils/
│   ├── __init__.py
│   ├── id_manager.py           # Find max IDs, generate new IDs
│   ├── patterns.py             # Common regex patterns
│   └── validation.py           # Validate modifications before applying
│
└── parsing/
    ├── __init__.py
    └── miz_parser.py           # MizParser class (moved from modifications/parsing/)
```

---

## API Design

### Core Pattern
All modification functions follow this signature:

```python
def modify_something(mission_content: str, **params) -> str:
    """
    Modify mission content.

    Args:
        mission_content: Raw mission file content as string
        **params: Operation-specific parameters

    Returns:
        Modified mission content as string
    """
    # Extract relevant section using regex
    # Modify using string operations
    # Return modified content
    pass
```

### Wrapper Functions
Each modification also provides a convenience wrapper:

```python
def modify_something_file(input_miz: str, output_miz: str, **params) -> None:
    """
    Modify a .miz file directly.

    Args:
        input_miz: Path to input .miz file
        output_miz: Path to output .miz file
        **params: Operation-specific parameters
    """
    from parsing.miz_parser import quick_modify

    def modify_func(content):
        return modify_something(content, **params)

    quick_modify(input_miz, output_miz, modify_func)
```

---

## Function List

### Groups (groups/)

```python
# list.py - Read-only
def list_all_groups(mission_content: str) -> dict
def find_group_by_name(mission_content: str, group_name: str) -> tuple
def count_groups(mission_content: str, unit_type: str = None) -> int

# add.py
def add_group(mission_content: str, group_name: str, unit_type_category: str,
              unit_type: str, coalition: str, country: str, position: dict,
              num_units: int = 1, route: list = None) -> str

# remove.py
def remove_group(mission_content: str, group_name: str) -> str
def remove_groups_by_type(mission_content: str, unit_types: list) -> str
def remove_groups_by_coalition(mission_content: str, coalition: str) -> str

# duplicate.py
def duplicate_group(mission_content: str, group_name: str, new_group_name: str = None,
                   offset: dict = None) -> str

# modify.py
def rename_group(mission_content: str, old_name: str, new_name: str) -> str
def move_group(mission_content: str, group_name: str, new_position: dict) -> str
def change_group_coalition(mission_content: str, group_name: str, new_coalition: str) -> str
```

### Units (units/)

```python
# add.py
def add_unit_to_group(mission_content: str, group_name: str, unit_type: str,
                     position_offset: dict = None) -> str

# remove.py
def remove_unit_from_group(mission_content: str, group_name: str, unit_index: int) -> str
def remove_unit_by_name(mission_content: str, unit_name: str) -> str

# modify.py
def modify_unit_loadout(mission_content: str, unit_name: str, loadout: dict) -> str
def modify_unit_skill(mission_content: str, unit_name: str, skill: str) -> str
def modify_unit_position(mission_content: str, unit_name: str, new_position: dict) -> str
```

### Waypoints (waypoints/)

```python
# list.py - Read-only
def list_waypoints(mission_content: str, group_name: str) -> list
def get_waypoint_count(mission_content: str, group_name: str) -> int

# add.py
def add_waypoint(mission_content: str, group_name: str, position: dict,
                speed: float = 150, alt: float = 2000, action: str = "Turning Point") -> str

# remove.py
def remove_waypoint(mission_content: str, group_name: str, waypoint_index: int) -> str
def clear_route(mission_content: str, group_name: str) -> str

# modify.py
def modify_waypoint(mission_content: str, group_name: str, waypoint_index: int,
                   position: dict = None, speed: float = None, alt: float = None) -> str
```

### Coordinates (coordinates/)

```python
# extract.py - Read-only
def get_group_coordinates(mission_content: str, group_name: str) -> dict
def get_unit_coordinates(mission_content: str, unit_name: str) -> dict
def get_all_positions(mission_content: str) -> dict

# transform.py
def latlon_to_xy(lat: float, lon: float, theater: str = "Caucasus") -> tuple
def xy_to_latlon(x: float, y: float, theater: str = "Caucasus") -> tuple
```

### Utils (utils/)

```python
# id_manager.py
def find_max_group_id(mission_content: str) -> int
def find_max_unit_id(mission_content: str) -> int
def generate_new_group_id(mission_content: str) -> int
def generate_new_unit_ids(mission_content: str, count: int) -> list

# patterns.py - Regex patterns as constants
GROUP_PATTERN = r'\[(\d+)\]\s*=\s*{[^}]*?["\'']name["\'']]\s*=\s*["\'']([^"\']+)'
UNIT_PATTERN = ...
WAYPOINT_PATTERN = ...

# validation.py
def validate_group_exists(mission_content: str, group_name: str) -> bool
def validate_coordinates(position: dict) -> bool
def validate_unit_type(unit_type: str, category: str) -> bool
```

---

## Usage Examples

### Example 1: Remove all ships
```python
from miz_file_modification.groups.remove import remove_groups_by_type_file

remove_groups_by_type_file(
    input_miz="mission.miz",
    output_miz="mission_no_ships.miz",
    unit_types=["ship"]
)
```

### Example 2: Duplicate and move a group
```python
from miz_file_modification.parsing.miz_parser import MizParser
from miz_file_modification.groups.duplicate import duplicate_group
from miz_file_modification.groups.modify import move_group

parser = MizParser("mission.miz")
parser.extract()

content = parser.get_mission_content()
content = duplicate_group(content, "Fighter-1", "Fighter-2")
content = move_group(content, "Fighter-2", {"x": 100000, "y": 200000})

parser.write_mission_content(content)
parser.repackage("mission_modified.miz")
```

### Example 3: Add waypoint to existing group
```python
from miz_file_modification.waypoints.add import add_waypoint_file

add_waypoint_file(
    input_miz="mission.miz",
    output_miz="mission_with_waypoint.miz",
    group_name="Strike-1",
    position={"x": 50000, "y": 60000},
    speed=200,
    alt=3000
)
```

---

## Migration Notes

### From `modifications/` to `miz-file-modification/`

**Keep**:
- `parsing/miz_parser.py` → Move to `miz-file-modification/parsing/`
- Core function logic from all scripts

**Abandon**:
- `miz_utils.py` (pydcs-based approach)
- `pydcs_patch.py` (no longer needed)
- Old folder structure

**Consolidate**:
- All `methods/coords/*.py` → `coordinates/`
- All `methods/groups/*.py` → `groups/`
- All `methods/*.py` → Appropriate subdirectories

---

## Implementation Strategy

### Phase 1: Foundation (DO THIS FIRST)
1. Create folder structure
2. Move `miz_parser.py` to new location
3. Create `core.py` with common utilities
4. Create `utils/` modules (id_manager, patterns, validation)

### Phase 2: Core Operations
1. Implement `groups/` module (most important)
2. Implement `coordinates/` module
3. Test with existing .miz files

### Phase 3: Advanced Operations
1. Implement `units/` module
2. Implement `waypoints/` module
3. Add validation and error handling

### Phase 4: Future Enhancements
1. Triggers module
2. Weather modification
3. Start time/date modification

---

## Design Principles

1. **MizParser First**: All operations use MizParser workflow
2. **String-Based**: Work on mission content as strings, not objects
3. **Regex Patterns**: Use regex for finding/extracting Lua structures
4. **Functional**: Pure functions that take content string, return modified string
5. **Composable**: Functions can be chained together
6. **No DCS Required**: No pydcs dependency, works anywhere
7. **Well-Tested**: Each function tested against real .miz files

---

## Next Steps

1. **Review this plan** - Does this structure make sense?
2. **Prioritize functions** - Which operations are most important?
3. **Start small** - Implement foundation (Phase 1) first
4. **Test incrementally** - Validate each module with real .miz files
5. **Document as we go** - Keep examples and usage docs updated
