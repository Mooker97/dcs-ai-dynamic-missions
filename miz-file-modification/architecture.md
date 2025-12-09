# MIZ File Modification Library - Architecture

**Authoritative architecture reference for the `miz-file-modification` library.**

---

## 🔴 Critical Rules

### ALWAYS Use MizParser-Based Approach

**Mandatory Pattern**: All .miz modifications MUST follow the MizParser workflow:

```
Extract .miz → Read mission content → Apply regex modifications → Write content → Repackage .miz
```

**Why**:
- ✅ No DCS installation required
- ✅ No dependency issues (pure Python stdlib)
- ✅ Lightweight and fast
- ✅ Works with any .miz file regardless of version
- ❌ pydcs is DEPRECATED for modification operations

**Never**:
- ❌ Don't use pydcs for reading/modifying missions
- ❌ Don't parse Lua as Python objects
- ❌ Don't create external dependencies unless absolutely necessary

---

## Library Philosophy

### Core Principles

1. **MizParser First** - All operations use MizParser extract/repackage workflow
2. **String-Based** - Work on mission content as strings, not objects
3. **Regex Patterns** - Use regex for finding/extracting Lua structures
4. **Functional** - Pure functions: `content string → modified string`
5. **Composable** - Functions can be chained together
6. **No DCS Required** - Zero external dependencies for basic operations
7. **Well-Tested** - Each function tested against real .miz files

### Design Goals

- **Simplicity** - Easy to understand and maintain
- **Reliability** - Predictable behavior with clear error messages
- **Performance** - Fast operations even on large mission files
- **Composability** - Functions work together naturally
- **Extensibility** - Easy to add new modification types

---

## Architecture Overview

### Folder Structure

```
miz-file-modification/
├── __init__.py                 # Package initialization
├── architecture.md             # This document
├── core.py                     # Core modification utilities
│
├── groups/                     # Group operations
│   ├── __init__.py
│   ├── list.py                # List groups (read-only)
│   ├── add.py                 # Add new groups
│   ├── remove.py              # Remove groups
│   ├── duplicate.py           # Duplicate existing groups
│   └── modify.py              # Modify group properties
│
├── units/                      # Unit operations
│   ├── __init__.py
│   ├── add.py                 # Add units to groups
│   ├── remove.py              # Remove units from groups
│   └── modify.py              # Modify unit properties
│
├── waypoints/                  # Waypoint operations
│   ├── __init__.py
│   ├── list.py                # List waypoints (read-only)
│   ├── add.py                 # Add waypoints to routes
│   ├── remove.py              # Remove waypoints
│   └── modify.py              # Modify waypoint properties
│
├── coordinates/                # Coordinate operations
│   ├── __init__.py
│   ├── extract.py             # Get coordinates from groups/units
│   └── transform.py           # Coordinate transformations
│
├── triggers/                   # Trigger operations (future)
│   └── __init__.py
│
├── utils/                      # Utilities
│   ├── __init__.py
│   ├── id_manager.py          # Find/generate IDs
│   ├── patterns.py            # Regex patterns
│   └── validation.py          # Validation functions
│
├── parsing/                    # MizParser
│   ├── __init__.py
│   └── miz_parser.py          # Core parser class
│
└── tests/                      # Test suite
    ├── README.md              # Testing documentation
    ├── run_tests.py           # Master test runner (runs all tests)
    ├── test.miz               # Standard test mission file
    ├── test_patterns.py       # Tests for utils/patterns.py
    ├── test_groups_list.py    # Tests for groups/list.py
    ├── test_groups_remove.py  # Tests for groups/remove.py
    ├── test_groups_add.py     # Tests for groups/add.py
    ├── test_units.py          # Tests for units module
    ├── test_waypoints.py      # Tests for waypoints module
    ├── test_coordinates.py    # Tests for coordinates module
    └── test_utils.py          # Tests for utilities
```

### Module Organization

**By Operation Type**:
- `groups/` - All group-level operations
- `units/` - All unit-level operations
- `waypoints/` - All waypoint-level operations
- `coordinates/` - Position extraction and transformation

**By Function Type**:
- `list.py` / `extract.py` - Read-only inspection functions
- `add.py` - Adding new elements
- `remove.py` - Removing elements
- `modify.py` - Modifying existing elements
- `duplicate.py` - Copying and creating variants

**Supporting Modules**:
- `utils/` - Shared utilities (ID management, patterns, validation)
- `parsing/` - MizParser class for extract/repackage workflow
- `core.py` - Common modification utilities used across modules

---

## API Design Patterns

### Pattern 1: Core Modification Function

**Signature**:
```python
def modify_something(mission_content: str, **params) -> str:
    """
    Modify mission content using regex patterns.

    Args:
        mission_content: Raw mission file content as string
        **params: Operation-specific parameters

    Returns:
        Modified mission content as string

    Raises:
        ValueError: If modification fails or invalid parameters
    """
    # 1. Find target using regex
    # 2. Extract relevant section
    # 3. Modify using string operations
    # 4. Return modified content
    pass
```

**Example**:
```python
def remove_groups_by_type(mission_content: str, unit_types: list) -> str:
    """Remove all groups of specified unit types."""
    for unit_type in unit_types:
        pattern = rf'\["{unit_type}"\]\s*=\s*{{.*?}},?\s*(?=\["|\s*}})'
        mission_content = re.sub(pattern, '', mission_content, flags=re.DOTALL)
    return mission_content
```

### Pattern 2: Convenience Wrapper Function

**Signature**:
```python
def modify_something_file(input_miz: str, output_miz: str, **params) -> None:
    """
    Modify a .miz file directly (convenience wrapper).

    Args:
        input_miz: Path to input .miz file
        output_miz: Path to output .miz file
        **params: Operation-specific parameters

    Raises:
        FileNotFoundError: If input_miz doesn't exist
        ValueError: If modification fails
    """
    from miz_file_modification.parsing.miz_parser import quick_modify

    def modify_func(content):
        return modify_something(content, **params)

    quick_modify(input_miz, output_miz, modify_func)
```

**Example**:
```python
def remove_groups_by_type_file(input_miz: str, output_miz: str, unit_types: list) -> None:
    """Remove all groups of specified types from a .miz file."""
    from miz_file_modification.parsing.miz_parser import quick_modify

    def modify_func(content):
        return remove_groups_by_type(content, unit_types)

    quick_modify(input_miz, output_miz, modify_func)
```

### Pattern 3: Read-Only Inspection Function

**Signature**:
```python
def get_something(mission_content: str, **params) -> Any:
    """
    Extract information from mission content (read-only).

    Args:
        mission_content: Raw mission file content as string
        **params: Query parameters

    Returns:
        Extracted information (dict, list, str, etc.)
    """
    # Use regex to extract information
    # Parse and structure the results
    # Return structured data
    pass
```

**Example**:
```python
def list_all_groups(mission_content: str) -> dict:
    """
    List all groups in mission by coalition.

    Returns:
        dict: {"blue": [...], "red": [...], "neutrals": [...]}
    """
    groups = {"blue": [], "red": [], "neutrals": []}
    # Extract and parse groups
    return groups
```

---

## Complete API Specification

### Groups Module (`groups/`)

#### list.py - Inspection

```python
def list_all_groups(mission_content: str) -> dict:
    """List all groups by coalition."""

def find_group_by_name(mission_content: str, group_name: str) -> tuple:
    """Find group and return (content, position)."""

def count_groups(mission_content: str, unit_type: str = None) -> int:
    """Count total groups or groups of specific type."""

def get_group_info(mission_content: str, group_name: str) -> dict:
    """Get detailed info about a specific group."""
```

#### add.py - Adding Groups

```python
def add_group(mission_content: str, group_name: str, unit_type_category: str,
              unit_type: str, coalition: str, country: str, position: dict,
              num_units: int = 1, route: list = None, skill: str = "Good") -> str:
    """Add new group to mission."""

def add_group_file(input_miz: str, output_miz: str, **params) -> None:
    """Convenience wrapper for add_group."""
```

#### remove.py - Removing Groups

```python
def remove_group(mission_content: str, group_name: str) -> str:
    """Remove specific group by name."""

def remove_groups_by_type(mission_content: str, unit_types: list) -> str:
    """Remove all groups of specified types (e.g., ["ship", "helicopter"])."""

def remove_groups_by_coalition(mission_content: str, coalition: str) -> str:
    """Remove all groups from coalition ("blue", "red", "neutrals")."""

def remove_empty_groups(mission_content: str) -> str:
    """Remove groups with no units."""

# Convenience wrappers
def remove_group_file(input_miz: str, output_miz: str, group_name: str) -> None:
def remove_groups_by_type_file(input_miz: str, output_miz: str, unit_types: list) -> None:
def remove_groups_by_coalition_file(input_miz: str, output_miz: str, coalition: str) -> None:
```

#### duplicate.py - Duplicating Groups

```python
def duplicate_group(mission_content: str, group_name: str, new_group_name: str = None,
                   position_offset: dict = None) -> str:
    """
    Duplicate group with new name and optional position offset.

    Args:
        position_offset: {"x": 1000, "y": 2000} to move duplicate
    """

def duplicate_group_file(input_miz: str, output_miz: str, **params) -> None:
    """Convenience wrapper for duplicate_group."""
```

#### modify.py - Modifying Groups

```python
def rename_group(mission_content: str, old_name: str, new_name: str) -> str:
    """Rename group."""

def move_group(mission_content: str, group_name: str, new_position: dict) -> str:
    """Move group to new position {"x": ..., "y": ...}."""

def change_group_coalition(mission_content: str, group_name: str,
                          new_coalition: str, new_country: str) -> str:
    """Change group's coalition and country."""

def modify_group_skill(mission_content: str, group_name: str, skill: str) -> str:
    """Change skill level ("Rookie", "Trained", "Veteran", "Ace")."""

# Convenience wrappers for each
def rename_group_file(...) -> None:
def move_group_file(...) -> None:
def change_group_coalition_file(...) -> None:
```

---

### Units Module (`units/`)

#### add.py - Adding Units

```python
def add_unit_to_group(mission_content: str, group_name: str, unit_type: str,
                     position_offset: dict = None, skill: str = None) -> str:
    """Add unit to existing group."""

def add_unit_to_group_file(input_miz: str, output_miz: str, **params) -> None:
    """Convenience wrapper."""
```

#### remove.py - Removing Units

```python
def remove_unit_from_group(mission_content: str, group_name: str, unit_index: int) -> str:
    """Remove unit by index (0-based) from group."""

def remove_unit_by_name(mission_content: str, unit_name: str) -> str:
    """Remove specific unit by name."""

# Convenience wrappers
def remove_unit_from_group_file(...) -> None:
def remove_unit_by_name_file(...) -> None:
```

#### modify.py - Modifying Units

```python
def modify_unit_loadout(mission_content: str, unit_name: str, loadout: dict) -> str:
    """Change unit's weapon loadout."""

def modify_unit_skill(mission_content: str, unit_name: str, skill: str) -> str:
    """Change unit skill level."""

def modify_unit_position(mission_content: str, unit_name: str, new_position: dict) -> str:
    """Move unit to new position."""

def rename_unit(mission_content: str, old_name: str, new_name: str) -> str:
    """Rename unit."""

# Convenience wrappers for each
def modify_unit_loadout_file(...) -> None:
def modify_unit_skill_file(...) -> None:
```

---

### Waypoints Module (`waypoints/`)

#### list.py - Inspection

```python
def list_waypoints(mission_content: str, group_name: str) -> list:
    """List all waypoints for group."""

def get_waypoint_count(mission_content: str, group_name: str) -> int:
    """Count waypoints in group's route."""

def get_waypoint_info(mission_content: str, group_name: str, waypoint_index: int) -> dict:
    """Get detailed info about specific waypoint."""
```

#### add.py - Adding Waypoints

```python
def add_waypoint(mission_content: str, group_name: str, position: dict,
                speed: float = 150, alt: float = 2000,
                action: str = "Turning Point", index: int = None) -> str:
    """
    Add waypoint to group's route.

    Args:
        index: Insert at specific position (None = append to end)
    """

def add_waypoint_file(input_miz: str, output_miz: str, **params) -> None:
    """Convenience wrapper."""
```

#### remove.py - Removing Waypoints

```python
def remove_waypoint(mission_content: str, group_name: str, waypoint_index: int) -> str:
    """Remove waypoint by index."""

def clear_route(mission_content: str, group_name: str, keep_first: bool = True) -> str:
    """Clear all waypoints (optionally keeping first/spawn point)."""

# Convenience wrappers
def remove_waypoint_file(...) -> None:
def clear_route_file(...) -> None:
```

#### modify.py - Modifying Waypoints

```python
def modify_waypoint(mission_content: str, group_name: str, waypoint_index: int,
                   position: dict = None, speed: float = None,
                   alt: float = None, action: str = None) -> str:
    """Modify waypoint properties (only specified params changed)."""

def modify_waypoint_file(input_miz: str, output_miz: str, **params) -> None:
    """Convenience wrapper."""
```

---

### Coordinates Module (`coordinates/`)

#### extract.py - Extraction

```python
def get_group_coordinates(mission_content: str, group_name: str) -> dict:
    """
    Get group's position.

    Returns:
        {"x": float, "y": float, "alt": float}
    """

def get_unit_coordinates(mission_content: str, unit_name: str) -> dict:
    """Get unit's position."""

def get_all_positions(mission_content: str, coalition: str = None) -> dict:
    """
    Get all group positions (optionally filtered by coalition).

    Returns:
        {"GroupName": {"x": ..., "y": ..., "alt": ...}, ...}
    """
```

#### transform.py - Coordinate Transformations

```python
def latlon_to_xy(lat: float, lon: float, theater: str = "Caucasus") -> tuple:
    """
    Convert lat/lon to DCS x/y coordinates.

    Requires: pyproj library (optional dependency)

    Returns:
        (x, y) tuple
    """

def xy_to_latlon(x: float, y: float, theater: str = "Caucasus") -> tuple:
    """
    Convert DCS x/y to lat/lon coordinates.

    Returns:
        (lat, lon) tuple
    """
```

---

### Utils Module (`utils/`)

#### id_manager.py - ID Management

```python
def find_max_group_id(mission_content: str) -> int:
    """Find highest group ID in mission."""

def find_max_unit_id(mission_content: str) -> int:
    """Find highest unit ID in mission."""

def generate_new_group_id(mission_content: str) -> int:
    """Generate new unique group ID (max + 1)."""

def generate_new_unit_ids(mission_content: str, count: int) -> list:
    """Generate list of new unique unit IDs."""

def find_max_ids(mission_content: str) -> dict:
    """
    Find all max IDs in mission.

    Returns:
        {"group_id": int, "unit_id": int, "trigger_id": int, ...}
    """
```

#### patterns.py - Regex Patterns

```python
# Common regex patterns as module constants

# Group patterns
GROUP_PATTERN = r'\[(\d+)\]\s*=\s*{[^}]*?["\']name["\']\]\s*=\s*["\']([^"\']+)["\']'
GROUP_BLOCK_PATTERN = r'(\["\w+"\]\s*=\s*{.*?}),?\s*(?=\["|}})'

# Unit patterns
UNIT_PATTERN = r'\["units"\]\s*=\s*{(.*?)},'
UNIT_BLOCK_PATTERN = ...

# Waypoint patterns
WAYPOINT_PATTERN = r'\["points"\]\s*=\s*{(.*?)},'
WAYPOINT_BLOCK_PATTERN = ...

# Coordinate patterns
POSITION_PATTERN = r'\["x"\]\s*=\s*([+-]?\d+\.?\d*),\s*\["y"\]\s*=\s*([+-]?\d+\.?\d*)'

# ID patterns
GROUP_ID_PATTERN = r'\["groupId"\]\s*=\s*(\d+)'
UNIT_ID_PATTERN = r'\["unitId"\]\s*=\s*(\d+)'
```

#### validation.py - Validation Functions

```python
def validate_group_exists(mission_content: str, group_name: str) -> bool:
    """Check if group exists in mission."""

def validate_coordinates(position: dict) -> bool:
    """
    Validate position dict has required fields and valid values.

    Args:
        position: {"x": float, "y": float, "alt": float (optional)}
    """

def validate_unit_type(unit_type: str, category: str) -> bool:
    """Validate unit type is valid for category."""

def validate_coalition(coalition: str) -> bool:
    """Validate coalition name ("blue", "red", "neutrals")."""

def validate_skill(skill: str) -> bool:
    """Validate skill level ("Rookie", "Trained", "Veteran", "Ace", "Player")."""

def validate_mission_content(mission_content: str) -> tuple:
    """
    Basic mission content validation.

    Returns:
        (is_valid: bool, error_message: str)
    """
```

---

### Parsing Module (`parsing/`)

#### miz_parser.py - MizParser Class

```python
class MizParser:
    """Handler for extracting and repackaging .miz mission files."""

    def __init__(self, miz_path: str):
        """Initialize parser with .miz file path."""

    def extract(self, output_dir: str = None) -> Path:
        """Extract .miz to directory."""

    def repackage(self, output_miz: str, cleanup: bool = True) -> None:
        """Repackage extracted files back to .miz."""

    def cleanup(self) -> None:
        """Remove extraction directory."""

    def get_mission_content(self) -> str:
        """Read mission file content as string."""

    def write_mission_content(self, content: str) -> None:
        """Write content to mission file."""


def quick_modify(input_miz: str, output_miz: str, modify_func, cleanup: bool = True):
    """
    Quick workflow: extract, modify, repackage in one function.

    Args:
        input_miz: Path to input .miz file
        output_miz: Path to output .miz file
        modify_func: Function(content: str) -> str that modifies content
        cleanup: Whether to cleanup temp files after repackaging
    """
```

---

## Usage Examples

### Example 1: Simple Modification with Wrapper

```python
from miz_file_modification.groups.remove import remove_groups_by_type_file

# One-line modification
remove_groups_by_type_file(
    input_miz="../miz-files/input/mission.miz",
    output_miz="../miz-files/output/mission_no_ships.miz",
    unit_types=["ship"]
)
```

### Example 2: Multiple Modifications with MizParser

```python
from miz_file_modification.parsing.miz_parser import MizParser
from miz_file_modification.groups.duplicate import duplicate_group
from miz_file_modification.groups.modify import move_group
from miz_file_modification.waypoints.add import add_waypoint

# Extract once
parser = MizParser("../miz-files/input/mission.miz")
parser.extract()

# Read content
content = parser.get_mission_content()

# Apply multiple modifications
content = duplicate_group(content, "Fighter-1", "Fighter-2")
content = move_group(content, "Fighter-2", {"x": 100000, "y": 200000})
content = add_waypoint(content, "Fighter-2", {"x": 120000, "y": 220000}, speed=250)

# Write and repackage once
parser.write_mission_content(content)
parser.repackage("../miz-files/output/mission_modified.miz")
```

### Example 3: Custom Modification Function

```python
from miz_file_modification.parsing.miz_parser import quick_modify
import re

def my_custom_modification(content: str) -> str:
    """Custom modification: change all skill levels to Ace."""
    content = re.sub(
        r'\["skill"\]\s*=\s*"[^"]*"',
        '["skill"] = "Ace"',
        content
    )
    return content

# Apply custom modification
quick_modify(
    input_miz="../miz-files/input/mission.miz",
    output_miz="../miz-files/output/mission_ace.miz",
    modify_func=my_custom_modification
)
```

### Example 4: Inspection Before Modification

```python
from miz_file_modification.parsing.miz_parser import MizParser
from miz_file_modification.groups.list import list_all_groups, get_group_info
from miz_file_modification.groups.remove import remove_group

# Extract and inspect
parser = MizParser("../miz-files/input/mission.miz")
parser.extract()
content = parser.get_mission_content()

# List all groups
groups = list_all_groups(content)
print(f"Blue groups: {groups['blue']}")
print(f"Red groups: {groups['red']}")

# Get detailed info
info = get_group_info(content, "Fighter-1")
print(f"Fighter-1 has {info['unit_count']} units")

# Remove specific groups
for group_name in groups['red']:
    content = remove_group(content, group_name)

# Save modified mission
parser.write_mission_content(content)
parser.repackage("../miz-files/output/mission_blue_only.miz")
```

---

## Implementation Guidelines

### Adding New Functions

**Checklist**:
1. ✅ Follow core function pattern (content string in/out)
2. ✅ Add convenience wrapper function (*_file)
3. ✅ Use regex patterns from `utils/patterns.py`
4. ✅ Validate inputs using `utils/validation.py`
5. ✅ Handle IDs using `utils/id_manager.py`
6. ✅ Document with docstrings (Args, Returns, Raises)
7. ✅ Add usage example
8. ✅ Test with real .miz files

### Error Handling

**Standard Error Patterns**:
```python
# Input validation
if not validate_group_exists(mission_content, group_name):
    raise ValueError(f"Group '{group_name}' not found in mission")

# Regex match validation
match = re.search(pattern, mission_content)
if not match:
    raise ValueError(f"Could not find expected pattern in mission file")

# File operations (in wrapper functions)
if not Path(input_miz).exists():
    raise FileNotFoundError(f"Input .miz file not found: {input_miz}")
```

### Testing

**Running Tests**:
```bash
# Run all tests (recommended)
cd tests/
python run_tests.py

# Run individual test file for debugging
python test_patterns.py
```

**Test Organization**:
- ✅ **All tests go in `tests/` folder** - Keep test files organized in a dedicated directory
- ✅ **Use `run_tests.py` master test runner** - Automatically discovers and runs all test_*.py files
- ✅ **Use `test.miz` as standard test file** - Consistent test mission for all functions
- ✅ **Tests match expected results** - Validate against known state of test.miz
- ✅ **Test both content and file functions** - Core functions and convenience wrappers

**Test File Structure**:
```
tests/
├── test.miz                  # Standard test mission file
├── test_groups_list.py       # Tests for groups/list.py
├── test_groups_remove.py     # Tests for groups/remove.py
├── test_groups_add.py        # Tests for groups/add.py
├── test_units.py             # Tests for units module
├── test_waypoints.py         # Tests for waypoints module
├── test_coordinates.py       # Tests for coordinates module
└── test_utils.py             # Tests for utilities
```

**Test Pattern with test.miz**:
```python
# Example: test_groups_remove.py
from pathlib import Path
from miz_file_modification.parsing.miz_parser import MizParser
from miz_file_modification.groups.remove import remove_group, remove_group_file
from miz_file_modification.groups.list import validate_group_exists

TEST_MIZ = Path(__file__).parent / "test.miz"

def test_remove_group():
    """Test removing a group using content function."""
    parser = MizParser(str(TEST_MIZ))
    parser.extract()
    content = parser.get_mission_content()

    # Expected: test.miz contains "TestGroup"
    assert validate_group_exists(content, "TestGroup"), "TestGroup should exist in test.miz"

    # Remove group
    modified = remove_group(content, "TestGroup")

    # Verify removed
    assert not validate_group_exists(modified, "TestGroup"), "TestGroup should be removed"

    # Cleanup
    parser.cleanup()

def test_remove_group_file():
    """Test removing a group using file wrapper."""
    output_miz = Path(__file__).parent / "temp_output.miz"

    # Remove group
    remove_group_file(str(TEST_MIZ), str(output_miz), "TestGroup")

    # Verify output
    parser = MizParser(str(output_miz))
    parser.extract()
    content = parser.get_mission_content()

    assert not validate_group_exists(content, "TestGroup"), "TestGroup should be removed"

    # Cleanup
    parser.cleanup()
    output_miz.unlink()
```

**test.miz Expected Contents**:
Work together to document the expected state of test.miz:
```python
# Document what groups/units/waypoints exist in test.miz
# Example structure to be filled in:
"""
test.miz contains:
  Blue Groups:
    - "TestGroup" (plane, 2 units)
    - "BlueHelicopter-1" (helicopter, 1 unit)
  Red Groups:
    - "RedTank-1" (vehicle, 4 units)
    - "RedShip-1" (ship, 1 unit)
  Coordinates:
    - TestGroup at x=100000, y=200000
"""
```

---

## Performance Considerations

### Optimization Strategies

1. **Compile Regex Patterns Once**
   ```python
   # In patterns.py
   GROUP_PATTERN_COMPILED = re.compile(GROUP_PATTERN)

   # Use in functions
   matches = GROUP_PATTERN_COMPILED.finditer(content)
   ```

2. **Minimize String Copies**
   ```python
   # Good: Single modification
   content = re.sub(pattern, replacement, content)

   # Bad: Multiple intermediate strings
   temp1 = content.replace("foo", "bar")
   temp2 = temp1.replace("baz", "qux")
   ```

3. **Extract Once, Modify Multiple Times**
   ```python
   # Good: Extract once
   parser.extract()
   content = parser.get_mission_content()
   content = modify1(content)
   content = modify2(content)
   parser.write_mission_content(content)

   # Bad: Extract for each modification
   modify1_file(input_miz, temp1)
   modify2_file(temp1, output_miz)
   ```

### Memory Considerations

- Mission files are typically 100KB - 10MB as text
- Keep entire content in memory (acceptable for these sizes)
- Don't load multiple mission files simultaneously unless necessary

---

## Implementation Phases

### ✅ Phase 1: Foundation (CURRENT)
1. Create folder structure
2. Move `miz_parser.py` to `parsing/`
4. Implement `utils/patterns.py`
5. Implement `utils/validation.py`
3. Implement `utils/id_manager.py`
6. Create `core.py` with common utilities

### Phase 2: Core Operations
1. Implement `groups/list.py`
2. Implement `groups/remove.py`
3. Implement `groups/duplicate.py`
4. Implement `coordinates/extract.py`
5. Test all functions extensively

### Phase 3: Advanced Operations
1. Implement `groups/add.py`
2. Implement `groups/modify.py`
3. Implement `units/` module
4. Implement `waypoints/` module
5. Implement `coordinates/transform.py`

### Phase 4: Polish & Extend
1. Add comprehensive validation
2. Implement `triggers/` module (future)
3. Add weather/time modification
4. Performance optimization
5. Complete test coverage

---

## Dependencies

### Required
- **Python 3.10+** - Core requirement
- **Standard Library** - zipfile, os, shutil, pathlib, re

### Optional
- **pyproj** - For coordinate transformations (lat/lon ↔ x/y)
  - Only needed if using `coordinates/transform.py`
  - Install: `pip install pyproj>=3.7.0`

### Deprecated
- ~~**pydcs**~~ - No longer used for modifications
  - Kept in project for potential future mission generation
  - Not a dependency of miz-file-modification library

---

## Version History

### v0.1.0 - Foundation (Current)
- Architecture defined
- Folder structure created
- Core patterns established
- Ready for implementation

### Future Versions
- v0.2.0 - Core operations (groups, coordinates)
- v0.3.0 - Advanced operations (units, waypoints)
- v0.4.0 - Polish & validation
- v1.0.0 - Production ready

---

## References

### Internal Documentation
- `../knowledge/miz-file-manipulation.md` - Complete .miz file structure guide
- `../CLAUDE.md` - Project-wide development guidelines

### External Resources
- [DCS Mission Structure Wiki](https://wiki.hoggitworld.com/view/Miz_mission_structure)
- [DCS Lua Documentation](https://wiki.hoggitworld.com/view/Category:Scripting)

---

**Last Updated**: 2025-12-08
**Maintained By**: DCS Dynamic Mission System Project
