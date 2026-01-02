# Waypoint Operations

Complete reference for all waypoint operations in the miz-modification library.

## Overview

Waypoint operations allow you to manage the routes that groups follow. Waypoints define the path aircraft fly, where ground units drive, and what actions they perform at each point. Every group that moves has a route with one or more waypoints.

**Module**: `miz_modification.waypoints`

---

## Read-Only Operations

### `list_waypoints()`

List all waypoints in a group's route.

**Module**: `miz_modification.waypoints.list`

**Signature**:
```python
def list_waypoints(mission_content: str, group_name: str) -> List[Dict]
```

**Parameters**:

| Name | Type | Required | Description |
|------|------|----------|-------------|
| `mission_content` | `str` | Yes | Raw mission file content as string |
| `group_name` | `str` | Yes | Name of group to get waypoints for |

**Returns**:

```python
[
    {
        "index": 1,
        "x": -50000.0,
        "y": 30000.0,
        "alt": 2000.0,
        "speed": 150.0,
        "action": "Turning Point",
        "type": "Turning Point",
        "alt_type": "BARO"
    },
    ...
]
```

**Usage Example**:

```python
from miz_modification.waypoints.list import list_waypoints
from miz_modification.parsing.miz_parser import MizParser

parser = MizParser("input.miz")
parser.extract()
content = parser.get_mission_content()

waypoints = list_waypoints(content, "Fighter-1")
print(f"Group has {len(waypoints)} waypoints")

for wp in waypoints:
    print(f"WP{wp['index']}: ({wp['x']}, {wp['y']}) @ {wp['alt']}m - {wp['action']}")
```

**File Wrapper**:

```python
from miz_modification.waypoints.list import list_waypoints_file

waypoints = list_waypoints_file("input.miz", "Fighter-1")
for wp in waypoints:
    print(f"WP{wp['index']}: {wp['action']}")
```

**Error Conditions**:

- `ValueError`: Group not found
- `ValueError`: Group has no route section
- `ValueError`: Group has no waypoints (empty route)

**Related Operations**:
- `get_waypoint_count()` - Get count of waypoints
- `get_waypoint_info()` - Get single waypoint details

---

### `get_waypoint_count()`

Get the number of waypoints in a group's route.

**Module**: `miz_modification.waypoints.list`

**Signature**:
```python
def get_waypoint_count(mission_content: str, group_name: str) -> int
```

**Parameters**:

| Name | Type | Required | Description |
|------|------|----------|-------------|
| `mission_content` | `str` | Yes | Raw mission file content as string |
| `group_name` | `str` | Yes | Name of group |

**Returns**:

| Type | Description |
|------|-------------|
| `int` | Number of waypoints in route |

**Usage Example**:

```python
from miz_modification.waypoints.list import get_waypoint_count

count = get_waypoint_count(content, "Fighter-1")
print(f"Group has {count} waypoints")
```

**File Wrapper**:

```python
from miz_modification.waypoints.list import get_waypoint_count_file

count = get_waypoint_count_file("input.miz", "Fighter-1")
```

**Error Conditions**:

- `ValueError`: Group not found or has no route

---

### `get_waypoint_info()`

Get detailed information about a specific waypoint.

**Module**: `miz_modification.waypoints.list`

**Signature**:
```python
def get_waypoint_info(mission_content: str, group_name: str, waypoint_index: int) -> Dict
```

**Parameters**:

| Name | Type | Required | Description |
|------|------|----------|-------------|
| `mission_content` | `str` | Yes | Raw mission file content as string |
| `group_name` | `str` | Yes | Name of group |
| `waypoint_index` | `int` | Yes | Index of waypoint (1-based) |

**Returns**:

| Type | Description |
|------|-------------|
| `dict` | Waypoint information dict (same structure as list_waypoints items) |

**Usage Example**:

```python
from miz_modification.waypoints.list import get_waypoint_info

wp = get_waypoint_info(content, "Fighter-1", 2)
print(f"WP2: {wp['action']} at ({wp['x']}, {wp['y']})")
```

**File Wrapper**:

```python
from miz_modification.waypoints.list import get_waypoint_info_file

wp = get_waypoint_info_file("input.miz", "Fighter-1", 2)
```

**Error Conditions**:

- `ValueError`: Group not found, has no route, or waypoint index doesn't exist

---

## Create Operations

### `add_waypoint()`

Add a new waypoint to a group's route.

**Module**: `miz_modification.waypoints.add`

**Signature**:
```python
def add_waypoint(mission_content: str, group_name: str, position: Dict[str, float],
                speed: float = 150.0, alt: float = 2000.0,
                action: str = "Turning Point", alt_type: str = "BARO",
                index: Optional[int] = None, **kwargs) -> str
```

**Parameters**:

| Name | Type | Required | Description |
|------|------|----------|-------------|
| `mission_content` | `str` | Yes | Raw mission file content as string |
| `group_name` | `str` | Yes | Name of group to add waypoint to |
| `position` | `dict` | Yes | Position dict with 'x' and 'y' coordinates |
| `speed` | `float` | No | Speed in m/s (default: 150) |
| `alt` | `float` | No | Altitude in meters (default: 2000) |
| `action` | `str` | No | Waypoint action (default: "Turning Point") |
| `alt_type` | `str` | No | Altitude type: "BARO" or "RADIO" (default: "BARO") |
| `index` | `int` | No | Position to insert. If None, appends to end |
| `**kwargs` | various | No | Additional waypoint properties |

**Valid Waypoint Actions**:
- `"Turning Point"` - Standard navigation waypoint
- `"Fly Over Point"` - Must fly directly over this point
- `"From Parking Area"` - Takeoff/spawn point
- `"From Parking Area Hot"` - Hot start from parking
- `"From Ground Area"` - Ground spawn point
- `"From Ground Area Hot"` - Hot start from ground
- `"Takeoff"` - Takeoff waypoint
- `"Land"` - Landing waypoint

**Valid Altitude Types**:
- `"BARO"` - Barometric altitude (MSL - Mean Sea Level)
- `"RADIO"` - Radio altitude (AGL - Above Ground Level)

**Returns**:

| Type | Description |
|------|-------------|
| `str` | Modified mission content with waypoint added |

**Usage Example**:

```python
from miz_modification.waypoints.add import add_waypoint

# Add waypoint at end of route
position = {"x": -50000, "y": 30000}
content = add_waypoint(content, "Fighter-1", position, speed=200, alt=3000)

# Add at specific position (currently limited - see note below)
# content = add_waypoint(content, "Fighter-1", position, index=2)
```

**File Wrapper**:

```python
from miz_modification.waypoints.add import add_waypoint_file

add_waypoint_file(
    "input.miz",
    "output.miz",
    "Fighter-1",
    {"x": -50000, "y": 30000},
    speed=200,
    alt=3000
)
```

**Note**: Currently, inserting at specific positions (index parameter) is not fully implemented. Only appending to end (index=None) is supported.

**Error Conditions**:

- `ValueError`: Group not found or has no route
- `ValueError`: Invalid action or altitude type
- `ValueError`: Index specified (insertion not yet supported)

**Related Operations**:
- `add_multiple_waypoints()` - Add multiple waypoints at once

---

### `add_multiple_waypoints()`

Add multiple waypoints to a group's route.

**Module**: `miz_modification.waypoints.add`

**Signature**:
```python
def add_multiple_waypoints(mission_content: str, group_name: str,
                           waypoints: list) -> str
```

**Parameters**:

| Name | Type | Required | Description |
|------|------|----------|-------------|
| `mission_content` | `str` | Yes | Raw mission file content as string |
| `group_name` | `str` | Yes | Name of group to add waypoints to |
| `waypoints` | `list[dict]` | Yes | List of waypoint dicts (see schema below) |

**Waypoint Dict Schema**:

```python
{
    "position": {"x": float, "y": float},  # Required
    "speed": float,                         # Optional, default: 150
    "alt": float,                           # Optional, default: 2000
    "action": str,                          # Optional, default: "Turning Point"
    "alt_type": str                         # Optional, default: "BARO"
}
```

**Returns**:

| Type | Description |
|------|-------------|
| `str` | Modified mission content with all waypoints added |

**Usage Example**:

```python
from miz_modification.waypoints.add import add_multiple_waypoints

# Create a route with 3 waypoints
waypoints = [
    {"position": {"x": -50000, "y": 30000}, "speed": 200, "alt": 3000},
    {"position": {"x": -45000, "y": 35000}, "speed": 250, "alt": 3500},
    {"position": {"x": -40000, "y": 40000}, "speed": 300, "alt": 4000}
]

content = add_multiple_waypoints(content, "Fighter-1", waypoints)
```

**File Wrapper**:

```python
from miz_modification.waypoints.add import add_multiple_waypoints_file

waypoints = [
    {"position": {"x": -50000, "y": 30000}, "speed": 200, "alt": 3000},
    {"position": {"x": -45000, "y": 35000}, "speed": 250, "alt": 3500}
]

add_multiple_waypoints_file("input.miz", "output.miz", "Fighter-1", waypoints)
```

**Error Conditions**:

- `ValueError`: Group not found or has no route
- `ValueError`: Waypoint missing required 'position' field

---

## Delete Operations

### `remove_waypoint()`

Remove a specific waypoint from a group's route.

**Module**: `miz_modification.waypoints.remove`

**Signature**:
```python
def remove_waypoint(mission_content: str, group_name: str, waypoint_index: int) -> str
```

**Parameters**:

| Name | Type | Required | Description |
|------|------|----------|-------------|
| `mission_content` | `str` | Yes | Raw mission file content as string |
| `group_name` | `str` | Yes | Name of group |
| `waypoint_index` | `int` | Yes | Index of waypoint to remove (1-based) |

**Returns**:

| Type | Description |
|------|-------------|
| `str` | Modified mission content with waypoint removed |

**Usage Example**:

```python
from miz_modification.waypoints.remove import remove_waypoint

# Remove the 2nd waypoint
content = remove_waypoint(content, "Fighter-1", 2)
```

**File Wrapper**:

```python
from miz_modification.waypoints.remove import remove_waypoint_file

remove_waypoint_file("input.miz", "output.miz", "Fighter-1", 2)
```

**Note**: Cannot remove the only waypoint in a route. Use `clear_route()` to remove all waypoints.

**Error Conditions**:

- `ValueError`: Group not found, has no route, or waypoint doesn't exist
- `ValueError`: Trying to remove the only waypoint

---

### `clear_route()`

Clear all waypoints from a group's route.

**Module**: `miz_modification.waypoints.remove`

**Signature**:
```python
def clear_route(mission_content: str, group_name: str, keep_first: bool = True) -> str
```

**Parameters**:

| Name | Type | Required | Description |
|------|------|----------|-------------|
| `mission_content` | `str` | Yes | Raw mission file content as string |
| `group_name` | `str` | Yes | Name of group |
| `keep_first` | `bool` | No | If True, keeps first waypoint (default: True) |

**Returns**:

| Type | Description |
|------|-------------|
| `str` | Modified mission content with waypoints cleared |

**Usage Example**:

```python
from miz_modification.waypoints.remove import clear_route

# Remove all waypoints except the first one
content = clear_route(content, "Fighter-1", keep_first=True)

# Remove all waypoints including first (empty route)
content = clear_route(content, "Fighter-1", keep_first=False)
```

**File Wrapper**:

```python
from miz_modification.waypoints.remove import clear_route_file

clear_route_file("input.miz", "output.miz", "Fighter-1", keep_first=True)
```

**Note**: Keeping the first waypoint is recommended as it usually represents the starting position (takeoff point, spawn point, etc.).

**Error Conditions**:

- `ValueError`: Group not found or has no route

---

### `remove_waypoints_after()`

Remove all waypoints after a specified index.

**Module**: `miz_modification.waypoints.remove`

**Signature**:
```python
def remove_waypoints_after(mission_content: str, group_name: str, waypoint_index: int) -> str
```

**Parameters**:

| Name | Type | Required | Description |
|------|------|----------|-------------|
| `mission_content` | `str` | Yes | Raw mission file content as string |
| `group_name` | `str` | Yes | Name of group |
| `waypoint_index` | `int` | Yes | Keep waypoints up to and including this index |

**Returns**:

| Type | Description |
|------|-------------|
| `str` | Modified mission content with waypoints after index removed |

**Usage Example**:

```python
from miz_modification.waypoints.remove import remove_waypoints_after

# Keep waypoints 1-3, remove 4 onwards
content = remove_waypoints_after(content, "Fighter-1", 3)
```

**File Wrapper**:

```python
from miz_modification.waypoints.remove import remove_waypoints_after_file

remove_waypoints_after_file("input.miz", "output.miz", "Fighter-1", 3)
```

**Error Conditions**:

- `ValueError`: Group not found, has no route, or index is invalid

---

## Modify Operations

### `modify_waypoint()`

Modify properties of a waypoint.

**Module**: `miz_modification.waypoints.modify`

**Signature**:
```python
def modify_waypoint(mission_content: str, group_name: str, waypoint_index: int,
                   position: Optional[Dict[str, float]] = None,
                   speed: Optional[float] = None,
                   alt: Optional[float] = None,
                   action: Optional[str] = None,
                   alt_type: Optional[str] = None) -> str
```

**Parameters**:

| Name | Type | Required | Description |
|------|------|----------|-------------|
| `mission_content` | `str` | Yes | Raw mission file content as string |
| `group_name` | `str` | Yes | Name of group |
| `waypoint_index` | `int` | Yes | Index of waypoint to modify (1-based) |
| `position` | `dict` | No | New position {"x": float, "y": float} |
| `speed` | `float` | No | New speed in m/s |
| `alt` | `float` | No | New altitude in meters |
| `action` | `str` | No | New action string |
| `alt_type` | `str` | No | New altitude type ("BARO" or "RADIO") |

**Returns**:

| Type | Description |
|------|-------------|
| `str` | Modified mission content with waypoint updated |

**Note**: Only provided parameters are modified. Unprovided parameters remain unchanged.

**Usage Example**:

```python
from miz_modification.waypoints.modify import modify_waypoint

# Change waypoint 2 position and speed
content = modify_waypoint(
    content, "Fighter-1", 2,
    position={"x": -50000, "y": 30000},
    speed=250
)

# Change only altitude
content = modify_waypoint(content, "Fighter-1", 3, alt=5000)

# Change action
content = modify_waypoint(content, "Fighter-1", 2, action="Fly Over Point")
```

**File Wrapper**:

```python
from miz_modification.waypoints.modify import modify_waypoint_file

modify_waypoint_file(
    "input.miz",
    "output.miz",
    "Fighter-1",
    2,
    position={"x": -50000, "y": 30000},
    speed=250
)
```

**Error Conditions**:

- `ValueError`: Group/waypoint not found
- `ValueError`: Invalid action or altitude type
- `ValueError`: Position missing 'x' or 'y' keys

**Related Operations**:
- `modify_waypoint_position()` - Modify only position
- `modify_waypoint_speed()` - Modify only speed
- `modify_waypoint_altitude()` - Modify only altitude
- `modify_waypoint_action()` - Modify only action

---

### `modify_waypoint_position()`

Modify only the position of a waypoint (convenience function).

**Module**: `miz_modification.waypoints.modify`

**Signature**:
```python
def modify_waypoint_position(mission_content: str, group_name: str,
                            waypoint_index: int, position: Dict[str, float]) -> str
```

**Parameters**:

| Name | Type | Required | Description |
|------|------|----------|-------------|
| `mission_content` | `str` | Yes | Raw mission file content as string |
| `group_name` | `str` | Yes | Name of group |
| `waypoint_index` | `int` | Yes | Index of waypoint to modify |
| `position` | `dict` | Yes | New position {"x": float, "y": float} |

**Returns**:

| Type | Description |
|------|-------------|
| `str` | Modified mission content |

**Usage Example**:

```python
from miz_modification.waypoints.modify import modify_waypoint_position

content = modify_waypoint_position(
    content, "Fighter-1", 2,
    {"x": -50000, "y": 30000}
)
```

**File Wrapper**:

```python
from miz_modification.waypoints.modify import modify_waypoint_position_file

modify_waypoint_position_file(
    "input.miz", "output.miz", "Fighter-1", 2,
    {"x": -50000, "y": 30000}
)
```

---

### `modify_waypoint_speed()`

Modify only the speed of a waypoint (convenience function).

**Module**: `miz_modification.waypoints.modify`

**Signature**:
```python
def modify_waypoint_speed(mission_content: str, group_name: str,
                         waypoint_index: int, speed: float) -> str
```

**Parameters**:

| Name | Type | Required | Description |
|------|------|----------|-------------|
| `mission_content` | `str` | Yes | Raw mission file content as string |
| `group_name` | `str` | Yes | Name of group |
| `waypoint_index` | `int` | Yes | Index of waypoint to modify |
| `speed` | `float` | Yes | New speed in m/s |

**Returns**:

| Type | Description |
|------|-------------|
| `str` | Modified mission content |

**Usage Example**:

```python
from miz_modification.waypoints.modify import modify_waypoint_speed

content = modify_waypoint_speed(content, "Fighter-1", 2, 250.0)
```

**File Wrapper**:

```python
from miz_modification.waypoints.modify import modify_waypoint_speed_file

modify_waypoint_speed_file("input.miz", "output.miz", "Fighter-1", 2, 250.0)
```

---

### `modify_waypoint_altitude()`

Modify the altitude (and optionally altitude type) of a waypoint (convenience function).

**Module**: `miz_modification.waypoints.modify`

**Signature**:
```python
def modify_waypoint_altitude(mission_content: str, group_name: str,
                            waypoint_index: int, alt: float,
                            alt_type: Optional[str] = None) -> str
```

**Parameters**:

| Name | Type | Required | Description |
|------|------|----------|-------------|
| `mission_content` | `str` | Yes | Raw mission file content as string |
| `group_name` | `str` | Yes | Name of group |
| `waypoint_index` | `int` | Yes | Index of waypoint to modify |
| `alt` | `float` | Yes | New altitude in meters |
| `alt_type` | `str` | No | New altitude type ("BARO" or "RADIO") |

**Returns**:

| Type | Description |
|------|-------------|
| `str` | Modified mission content |

**Usage Example**:

```python
from miz_modification.waypoints.modify import modify_waypoint_altitude

# Change to 5000m BARO altitude
content = modify_waypoint_altitude(content, "Fighter-1", 2, 5000, "BARO")

# Change altitude only, keep existing type
content = modify_waypoint_altitude(content, "Fighter-1", 2, 5000)
```

**File Wrapper**:

```python
from miz_modification.waypoints.modify import modify_waypoint_altitude_file

modify_waypoint_altitude_file("input.miz", "output.miz", "Fighter-1", 2, 5000, "BARO")
```

---

### `modify_waypoint_action()`

Modify only the action of a waypoint (convenience function).

**Module**: `miz_modification.waypoints.modify`

**Signature**:
```python
def modify_waypoint_action(mission_content: str, group_name: str,
                          waypoint_index: int, action: str) -> str
```

**Parameters**:

| Name | Type | Required | Description |
|------|------|----------|-------------|
| `mission_content` | `str` | Yes | Raw mission file content as string |
| `group_name` | `str` | Yes | Name of group |
| `waypoint_index` | `int` | Yes | Index of waypoint to modify |
| `action` | `str` | Yes | New action string |

**Returns**:

| Type | Description |
|------|-------------|
| `str` | Modified mission content |

**Usage Example**:

```python
from miz_modification.waypoints.modify import modify_waypoint_action

content = modify_waypoint_action(content, "Fighter-1", 2, "Fly Over Point")
```

**File Wrapper**:

```python
from miz_modification.waypoints.modify import modify_waypoint_action_file

modify_waypoint_action_file("input.miz", "output.miz", "Fighter-1", 2, "Fly Over Point")
```

---

## Advanced Usage

### Building Complete Routes

```python
from miz_modification.waypoints.add import add_multiple_waypoints
from miz_modification.waypoints.remove import clear_route

# Clear existing route (keep spawn point)
content = clear_route(content, "Fighter-1", keep_first=True)

# Build new route
route = [
    {"position": {"x": -50000, "y": 30000}, "speed": 200, "alt": 1000, "action": "Turning Point"},
    {"position": {"x": -45000, "y": 35000}, "speed": 250, "alt": 2000, "action": "Turning Point"},
    {"position": {"x": -40000, "y": 40000}, "speed": 300, "alt": 3000, "action": "Turning Point"},
    {"position": {"x": -35000, "y": 35000}, "speed": 200, "alt": 1000, "action": "Land"}
]

content = add_multiple_waypoints(content, "Fighter-1", route)
```

### Modifying Existing Routes

```python
from miz_modification.waypoints.list import list_waypoints
from miz_modification.waypoints.modify import modify_waypoint_speed

# Get current waypoints
waypoints = list_waypoints(content, "Fighter-1")

# Increase speed at all waypoints by 50 m/s
for wp in waypoints:
    new_speed = wp["speed"] + 50
    content = modify_waypoint_speed(content, "Fighter-1", wp["index"], new_speed)
```

### Trimming Routes

```python
from miz_modification.waypoints.remove import remove_waypoints_after

# Shorten route to first 3 waypoints
content = remove_waypoints_after(content, "Fighter-1", 3)
```

---

## Best Practices

### 1. Always Inspect Before Modifying

```python
from miz_modification.waypoints.list import list_waypoints

# Check current waypoints
waypoints = list_waypoints(content, "Fighter-1")
print(f"Current waypoints: {len(waypoints)}")

for wp in waypoints:
    print(f"  WP{wp['index']}: {wp['action']} @ ({wp['x']}, {wp['y']})")
```

### 2. Use Appropriate Altitude Types

```python
# For aircraft - use BARO (barometric/MSL)
content = add_waypoint(
    content, "Fighter-1",
    {"x": -50000, "y": 30000},
    alt=8000,
    alt_type="BARO"  # 8000m above sea level
)

# For helicopters - use RADIO (radar/AGL)
content = add_waypoint(
    content, "Heli-1",
    {"x": -50000, "y": 30000},
    alt=100,
    alt_type="RADIO"  # 100m above ground
)
```

### 3. Keep First Waypoint When Clearing

```python
# Keep spawn point, clear rest
content = clear_route(content, "Fighter-1", keep_first=True)

# Now rebuild route from spawn point
route = [...]
content = add_multiple_waypoints(content, "Fighter-1", route)
```

### 4. Use Appropriate Actions

```python
# Navigation waypoints
content = add_waypoint(content, "Fighter-1", position, action="Turning Point")

# Must fly directly over (useful for precision)
content = add_waypoint(content, "Fighter-1", position, action="Fly Over Point")

# Landing waypoint (last in route)
content = add_waypoint(content, "Fighter-1", airfield_pos, speed=80, alt=0, action="Land")
```

---

## Common Patterns

### Pattern 1: Race Track Pattern

```python
# Create circular race track patrol
import math

center_x, center_y = -50000, 30000
radius = 5000
num_waypoints = 8

waypoints = []
for i in range(num_waypoints):
    angle = (2 * math.pi * i) / num_waypoints
    x = center_x + radius * math.cos(angle)
    y = center_y + radius * math.sin(angle)

    waypoints.append({
        "position": {"x": x, "y": y},
        "speed": 250,
        "alt": 3000,
        "action": "Turning Point"
    })

content = add_multiple_waypoints(content, "Fighter-1", waypoints)
```

### Pattern 2: Approach and Landing

```python
# Create approach to airfield
runway_threshold = {"x": -40000, "y": 30000}

# Final approach waypoint (3nm out, descending)
final_approach = {
    "position": {"x": runway_threshold["x"] - 5556, "y": runway_threshold["y"]},
    "speed": 100,
    "alt": 300,
    "action": "Turning Point",
    "alt_type": "RADIO"
}

# Touchdown
landing = {
    "position": runway_threshold,
    "speed": 80,
    "alt": 0,
    "action": "Land"
}

content = add_waypoint(content, "Fighter-1", final_approach["position"], **final_approach)
content = add_waypoint(content, "Fighter-1", landing["position"], **landing)
```

### Pattern 3: Gradual Climb

```python
# Create gradual climb to altitude
from miz_modification.waypoints.list import list_waypoints

waypoints = list_waypoints(content, "Fighter-1")

# Increase altitude at each waypoint by 500m
for i, wp in enumerate(waypoints):
    new_alt = 1000 + (i * 500)  # 1000m, 1500m, 2000m, etc.
    content = modify_waypoint_altitude(content, "Fighter-1", wp["index"], new_alt)
```

---

## See Also

- [Group Operations](groups.md) - Manage groups that have routes
- [Unit Operations](units.md) - Individual units in groups
- [Coordinates Operations](coordinates.md) - Work with positions
- [Mission Analysis](mission-analysis.md) - Inspect waypoint data
