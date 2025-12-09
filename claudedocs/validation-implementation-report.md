# Validation Module Implementation Report

**Date**: 2025-12-08
**File**: `miz-file-modification/utils/validation.py`
**Test File**: `miz-file-modification/tests/test_validation.py`

## Overview

Implemented comprehensive validation module for .miz file modifications. Provides validation functions to check parameters before applying modifications, preventing errors and ensuring data integrity.

## Test Results

✅ **All 14 validation tests PASSED**

```
Results: 14 passed, 0 failed, 0 skipped
```

## Implemented Functions

### 1. Coordinate Validation

| Function | Purpose | Returns |
|----------|---------|---------|
| `validate_position(position, require_altitude)` | Validate position dict with x, y, optional alt, heading | `(bool, error_msg)` |
| `validate_coordinates(x, y)` | Validate x, y coordinates within bounds | `(bool, error_msg)` |

**Features**:
- Checks required keys (x, y)
- Validates numeric types
- Checks bounds (±500km typical for DCS)
- Optional altitude validation (0-25000m)
- Optional heading validation (radians or degrees)

**Example**:
```python
valid, error = validate_position({'x': 1000, 'y': 2000, 'alt': 5000})
if not valid:
    raise ValueError(error)
```

### 2. Group Validation

| Function | Purpose | Returns |
|----------|---------|---------|
| `validate_group_name(group_name)` | Validate group name for Lua compatibility | `(bool, error_msg)` |
| `validate_group_exists(content, group_name)` | Check if group exists in mission | `bool` |

**Name Rules**:
- Not empty
- Max 255 characters
- No quotes (breaks Lua strings)
- No newlines (breaks formatting)
- Not Lua keywords (and, if, end, etc.)

**Example**:
```python
valid, error = validate_group_name("Fighter-1")
if not valid:
    raise ValueError(error)

if not validate_group_exists(mission_content, "Fighter-1"):
    raise ValueError("Group not found")
```

### 3. Unit Type Validation

| Function | Purpose | Returns |
|----------|---------|---------|
| `validate_unit_type_category(category)` | Validate unit category (plane, helicopter, etc.) | `(bool, error_msg)` |
| `validate_coalition(coalition)` | Validate coalition (blue, red, neutrals) | `(bool, error_msg)` |

**Valid Values**:
- **Categories**: plane, helicopter, ship, vehicle, static
- **Coalitions**: blue, red, neutrals

**Example**:
```python
valid, error = validate_unit_type_category("plane")
valid, error = validate_coalition("blue")
```

### 4. Property Validation

| Function | Purpose | Returns |
|----------|---------|---------|
| `validate_skill_level(skill)` | Validate skill level | `(bool, error_msg)` |
| `validate_waypoint_action(action)` | Validate waypoint action | `(bool, error_msg)` |
| `validate_altitude_type(alt_type)` | Validate altitude type | `(bool, error_msg)` |

**Valid Values**:
- **Skills**: Rookie, Trained, Average, Good, High, Excellent, Random, Player
- **Actions**: Turning Point, Takeoff, Land, From Parking Area, etc.
- **Alt Types**: BARO, RADIO

**Example**:
```python
valid, error = validate_skill_level("Average")
valid, error = validate_waypoint_action("Turning Point")
valid, error = validate_altitude_type("BARO")
```

### 5. ID Validation

| Function | Purpose | Returns |
|----------|---------|---------|
| `validate_id(id_value, id_type)` | Validate ID is positive integer | `(bool, error_msg)` |

**Rules**:
- Must be integer or convertible to integer
- Must be positive (>= 1)

**Example**:
```python
valid, error = validate_id(123, "group")
valid, error = validate_id("456", "unit")
```

### 6. Batch Validation

| Function | Purpose | Returns |
|----------|---------|---------|
| `validate_add_group_params(...)` | Validate all params for adding group | `(bool, error_msg)` |
| `validate_modify_group_params(...)` | Validate all params for modifying group | `(bool, error_msg)` |

**Features**:
- Combines multiple validations
- Convenience for common operations
- Checks altitude requirement for aircraft

**Example**:
```python
valid, error = validate_add_group_params(
    group_name="Fighter-1",
    unit_type_category="plane",
    coalition="blue",
    position={"x": 1000, "y": 2000, "alt": 5000},
    skill="Average"
)
if not valid:
    raise ValueError(f"Invalid parameters: {error}")
```

### 7. Utility Functions

| Function | Purpose | Returns |
|----------|---------|---------|
| `get_validation_errors(validations)` | Collect all error messages | `List[str]` |
| `raise_if_invalid(is_valid, error_msg)` | Raise ValueError if invalid | raises `ValueError` |

**Example**:
```python
# Collect multiple errors
validations = [
    validate_coalition("blue"),
    validate_position({"x": 1000, "y": 2000}),
    validate_skill_level("Average")
]
errors = get_validation_errors(validations)
if errors:
    raise ValueError("\n".join(errors))

# Quick raise
raise_if_invalid(*validate_coalition("blue"))
```

## Usage Patterns

### Pattern 1: Single Validation

```python
from utils.validation import validate_position

valid, error = validate_position({'x': 1000, 'y': 2000})
if not valid:
    print(f"Error: {error}")
    return
```

### Pattern 2: Raise on Error

```python
from utils.validation import raise_if_invalid, validate_coalition

raise_if_invalid(*validate_coalition("blue"))
```

### Pattern 3: Multiple Validations

```python
from utils.validation import get_validation_errors, validate_position, validate_coalition

validations = [
    validate_coalition("blue"),
    validate_position({"x": 1000, "y": 2000, "alt": 5000})
]

errors = get_validation_errors(validations)
if errors:
    print("Validation failed:")
    for error in errors:
        print(f"  - {error}")
    raise ValueError("Invalid parameters")
```

### Pattern 4: Batch Validation

```python
from utils.validation import validate_add_group_params

valid, error = validate_add_group_params(
    "Fighter-1", "plane", "blue",
    {"x": 1000, "y": 2000, "alt": 5000},
    skill="Average"
)

if not valid:
    raise ValueError(f"Cannot add group: {error}")
```

## Integration with Modification Functions

Validation functions are designed to be used in modification functions:

```python
# In groups/add.py
from utils.validation import validate_add_group_params, raise_if_invalid

def add_group(mission_content: str, group_name: str, unit_type_category: str,
              coalition: str, position: dict, skill: str = "Average") -> str:
    """Add new group to mission."""

    # Validate all parameters
    raise_if_invalid(*validate_add_group_params(
        group_name, unit_type_category, coalition, position, skill
    ))

    # Proceed with modification...
    # ...
```

## Test Coverage

### Test Categories

| Category | Tests | Status |
|----------|-------|--------|
| Position Validation | 8 test cases | ✅ PASS |
| Group Name Validation | 6 test cases | ✅ PASS |
| Group Existence | 2 test cases | ✅ PASS |
| Unit Type Category | 6 test cases | ✅ PASS |
| Coalition | 3 test cases | ✅ PASS |
| Skill Level | 3 test cases | ✅ PASS |
| Waypoint Action | 2 test cases | ✅ PASS |
| Altitude Type | 2 test cases | ✅ PASS |
| ID Validation | 4 test cases | ✅ PASS |
| Batch Validation | 8 test cases | ✅ PASS |
| Utility Functions | 4 test cases | ✅ PASS |

**Total**: 48 individual assertions across 14 test functions

### Test Cases Include

**Valid Cases**:
- Correct formats and values
- Edge cases (zero coordinates, max bounds)
- Optional parameters

**Invalid Cases**:
- Missing required fields
- Wrong types (string instead of number)
- Out of bounds values
- Empty/null values
- Invalid enum values
- Case sensitivity (skill/coalition/action names)

## Validation Rules Summary

### Coordinate Bounds

| Parameter | Min | Max | Unit |
|-----------|-----|-----|------|
| X coordinate | -500,000 | 500,000 | meters |
| Y coordinate | -500,000 | 500,000 | meters |
| Altitude | 0 | 25,000 | meters |
| Heading | -360 or 0 | 360 or 2π | degrees or radians |

### String Constraints

| Parameter | Max Length | Special Rules |
|-----------|-----------|---------------|
| Group name | 255 chars | No quotes, newlines, or Lua keywords |
| Unit name | 255 chars | Same as group name |

### Required Fields by Unit Type

| Unit Type | Required Position Fields |
|-----------|--------------------------|
| Plane | x, y, alt |
| Helicopter | x, y, alt |
| Ship | x, y |
| Vehicle | x, y |
| Static | x, y |

## Benefits for Phase 1 Implementation

### 1. Error Prevention
- Catch invalid parameters before modification
- Clear error messages for debugging
- Prevent mission file corruption

### 2. Code Quality
- Consistent validation across all modules
- DRY principle (don't repeat validation logic)
- Self-documenting (validation rules are explicit)

### 3. Developer Experience
- Easy to use validation functions
- Multiple usage patterns (single, batch, raise)
- Comprehensive test coverage ensures reliability

### 4. Future Extension
- Easy to add new validation functions
- Validation rules centralized in one module
- Consistent patterns for new validations

## Next Steps

With validation.py complete, Phase 1 can proceed with:

1. ✅ **utils/patterns.py** - Complete and tested
2. ✅ **utils/validation.py** - Complete and tested
3. ⏳ **utils/id_manager.py** - Next to implement
4. ⏳ **groups/** module - Can use validation functions
5. ⏳ **coordinates/** module - Can use validation functions

## Usage in Phase 2+

Validation functions will be used throughout:

- **groups/add.py** - `validate_add_group_params()`
- **groups/modify.py** - `validate_modify_group_params()`
- **units/add.py** - Position, skill, type validation
- **waypoints/add.py** - Position, action validation
- **coordinates/transform.py** - Coordinate bounds checking

## Lessons Learned

### 1. Return Tuple Pattern Works Well

```python
valid, error = validate_something(param)
```

This pattern is:
- Easy to use
- Self-documenting
- Allows error message propagation
- Optional (can ignore error with `_`)

### 2. Batch Validation Reduces Boilerplate

Instead of:
```python
valid1, error1 = validate_coalition(coalition)
if not valid1: raise ValueError(error1)
valid2, error2 = validate_position(position)
if not valid2: raise ValueError(error2)
```

Use:
```python
raise_if_invalid(*validate_add_group_params(...))
```

### 3. Case Sensitivity Matters

DCS Lua is case-sensitive:
- Skill levels: "Average" not "average"
- Coalitions: "blue" not "Blue"
- Actions: "Turning Point" not "turning point"

Validation enforces exact case to prevent runtime errors.

### 4. Bounds Are Important

Without validation:
- Coordinates outside map bounds → units spawn off-map
- Negative altitude → crash or strange behavior
- Invalid IDs → mission won't load

Validation catches these before modification.

## Conclusion

✅ **validation.py is complete and fully tested**

All validation functions:
- Implemented according to architecture spec
- Tested with 48 assertions
- Ready for use in Phase 1 implementation
- Designed for extensibility in Phase 2+

No additional validation work needed for Phase 1.
