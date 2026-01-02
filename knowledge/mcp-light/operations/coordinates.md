# Coordinate Operations

Complete reference for coordinate extraction and transformation operations in the miz-modification library.

## Overview

Coordinate operations allow you to extract position information from groups, units, and waypoints. DCS uses a Cartesian coordinate system with X (East/West) and Y (North/South) values in meters.

**Module**: `miz_modification.coordinates`

**Note**: These are read-only operations for extracting coordinates. To modify positions, use the modify operations in groups, units, or waypoints modules.

---

## Extract Operations

### `get_group_coordinates()`

Get coordinates of a group (first unit's position).

**Module**: `miz_modification.coordinates.extract`

**Signature**:
```python
def get_group_coordinates(mission_content: str, group_name: str) -> Dict[str, float]
```

**Parameters**:

| Name | Type | Required | Description |
|------|------|----------|-------------|
| `mission_content` | `str` | Yes | Raw mission file content as string |
| `group_name` | `str` | Yes | Name of group to find |

**Returns**:

```python
{
    "x": float,  # X coordinate in meters
    "y": float,  # Y coordinate in meters
    "alt": float # Altitude in meters (if available)
}
```

**Usage Example**:

```python
from miz_modification.coordinates.extract import get_group_coordinates
from miz_modification.parsing.miz_parser import MizParser

parser = MizParser("input.miz")
parser.extract()
content = parser.get_mission_content()

coords = get_group_coordinates(content, "Fighter-1")
print(f"Group position: x={coords['x']}, y={coords['y']}")
if 'alt' in coords:
    print(f"Altitude: {coords['alt']}m")
```

**File Wrapper**:

```python
from miz_modification.coordinates.extract import get_group_coordinates_file

coords = get_group_coordinates_file("input.miz", "Fighter-1")
print(f"Position: {coords}")
```

**Error Conditions**:

- `ValueError`: Group not found in mission
- `ValueError`: Could not extract coordinates from group

---

### `get_unit_coordinates()`

Get coordinates of a specific unit.

**Module**: `miz_modification.coordinates.extract`

**Signature**:
```python
def get_unit_coordinates(mission_content: str, unit_name: str) -> Dict[str, float]
```

**Parameters**:

| Name | Type | Required | Description |
|------|------|----------|-------------|
| `mission_content` | `str` | Yes | Raw mission file content as string |
| `unit_name` | `str` | Yes | Name of unit to find |

**Returns**:

```python
{
    "x": float,  # X coordinate in meters
    "y": float,  # Y coordinate in meters
    "alt": float # Altitude in meters (if available)
}
```

**Usage Example**:

```python
from miz_modification.coordinates.extract import get_unit_coordinates

coords = get_unit_coordinates(content, "Pilot #001")
print(f"Unit at: x={coords['x']}, y={coords['y']}, alt={coords.get('alt', 'N/A')}")
```

**File Wrapper**:

```python
from miz_modification.coordinates.extract import get_unit_coordinates_file

coords = get_unit_coordinates_file("input.miz", "Pilot #001")
```

**Error Conditions**:

- `ValueError`: Unit not found in mission
- `ValueError`: Could not extract coordinates from unit

---

### `get_all_positions()`

Get positions of all groups, optionally filtered by coalition and/or unit type.

**Module**: `miz_modification.coordinates.extract`

**Signature**:
```python
def get_all_positions(mission_content: str,
                      coalition: Optional[str] = None,
                      unit_type: Optional[str] = None) -> Dict[str, Dict[str, Any]]
```

**Parameters**:

| Name | Type | Required | Description |
|------|------|----------|-------------|
| `mission_content` | `str` | Yes | Raw mission file content as string |
| `coalition` | `str` | No | Coalition filter: "blue", "red", or "neutrals" |
| `unit_type` | `str` | No | Unit type filter: "plane", "helicopter", "ship", "vehicle", "static" |

**Returns**:

```python
{
    "GroupName": {
        "x": float,
        "y": float,
        "alt": float,           # If available
        "coalition": str,       # "blue", "red", "neutrals"
        "unit_type": str        # "plane", "helicopter", etc.
    },
    ...
}
```

**Usage Example**:

```python
from miz_modification.coordinates.extract import get_all_positions

# Get all group positions
all_positions = get_all_positions(content)
for name, pos in all_positions.items():
    print(f"{name}: x={pos['x']}, y={pos['y']}")

# Get only blue aircraft
blue_aircraft = get_all_positions(content, coalition="blue", unit_type="plane")
print(f"Found {len(blue_aircraft)} blue aircraft")
```

**File Wrapper**:

```python
from miz_modification.coordinates.extract import get_all_positions_file

# Get all blue groups
positions = get_all_positions_file("input.miz", coalition="blue")
```

**Error Conditions**:

- `ValueError`: Invalid coalition (not "blue", "red", or "neutrals")
- `ValueError`: Invalid unit_type

---

### `get_waypoint_coordinates()`

Get coordinates of a specific waypoint for a group.

**Module**: `miz_modification.coordinates.extract`

**Signature**:
```python
def get_waypoint_coordinates(mission_content: str, group_name: str,
                             waypoint_index: int = 1) -> Dict[str, float]
```

**Parameters**:

| Name | Type | Required | Description |
|------|------|----------|-------------|
| `mission_content` | `str` | Yes | Raw mission file content as string |
| `group_name` | `str` | Yes | Name of group |
| `waypoint_index` | `int` | No | Waypoint index (1-based, default: 1) |

**Returns**:

```python
{
    "x": float,      # X coordinate in meters
    "y": float,      # Y coordinate in meters
    "alt": float,    # Altitude in meters
    "speed": float   # Speed in m/s (if available)
}
```

**Usage Example**:

```python
from miz_modification.coordinates.extract import get_waypoint_coordinates

# Get first waypoint (spawn point)
wp1 = get_waypoint_coordinates(content, "Fighter-1", 1)
print(f"Spawn at: x={wp1['x']}, y={wp1['y']}, alt={wp1['alt']}")

# Get second waypoint
wp2 = get_waypoint_coordinates(content, "Fighter-1", 2)
print(f"WP2 at: x={wp2['x']}, y={wp2['y']}")
```

**File Wrapper**:

```python
from miz_modification.coordinates.extract import get_waypoint_coordinates_file

wp = get_waypoint_coordinates_file("input.miz", "Fighter-1", 2)
print(f"Waypoint 2: {wp}")
```

**Error Conditions**:

- `ValueError`: Group not found
- `ValueError`: Group has no route
- `ValueError`: Waypoint index not found
- `ValueError`: Could not extract coordinates from waypoint

---

## DCS Coordinate System

### Understanding DCS Coordinates

DCS uses a right-handed Cartesian coordinate system:

- **X axis**: East (+) / West (-)
- **Y axis**: North (+) / South (-)
- **Origin**: Map-specific (usually bottom-left corner)
- **Units**: Meters

### Altitude Types

- **Barometric (BARO/MSL)**: Altitude above Mean Sea Level
- **Radio (RADIO/AGL)**: Altitude Above Ground Level

### Coordinate Examples

```python
# Typical coordinate ranges (map-dependent)
# Caucasus Map example:
coordinates = {
    "x": -280000,  # 280km west of origin
    "y": 615000,   # 615km north of origin
    "alt": 8000    # 8000m altitude
}
```

---

## Advanced Usage

### Calculating Distances

```python
import math
from miz_modification.coordinates.extract import get_group_coordinates

# Get positions of two groups
coords1 = get_group_coordinates(content, "Fighter-1")
coords2 = get_group_coordinates(content, "Enemy SAM 1")

# Calculate 2D distance
dx = coords2['x'] - coords1['x']
dy = coords2['y'] - coords1['y']
distance_2d = math.sqrt(dx**2 + dy**2)

print(f"Distance: {distance_2d/1000:.1f} km")

# Calculate 3D distance (including altitude)
if 'alt' in coords1 and 'alt' in coords2:
    dz = coords2['alt'] - coords1['alt']
    distance_3d = math.sqrt(dx**2 + dy**2 + dz**2)
    print(f"3D Distance: {distance_3d/1000:.1f} km")
```

### Finding Nearest Groups

```python
from miz_modification.coordinates.extract import get_all_positions
import math

def find_nearest_group(reference_coords, all_positions, exclude_self=None):
    """Find the nearest group to a reference position."""
    nearest = None
    min_distance = float('inf')

    for name, pos in all_positions.items():
        if name == exclude_self:
            continue

        dx = pos['x'] - reference_coords['x']
        dy = pos['y'] - reference_coords['y']
        distance = math.sqrt(dx**2 + dy**2)

        if distance < min_distance:
            min_distance = distance
            nearest = name

    return nearest, min_distance

# Usage
my_pos = get_group_coordinates(content, "Fighter-1")
all_positions = get_all_positions(content, coalition="red")

nearest, distance = find_nearest_group(my_pos, all_positions)
print(f"Nearest threat: {nearest} at {distance/1000:.1f} km")
```

### Creating Formation Offsets

```python
# Calculate offsets for wingmen formation
leader_coords = get_group_coordinates(content, "Fighter-1")

# Wingmen positions (50m spacing)
formation_offsets = [
    {"x": 0, "y": 0},       # Leader
    {"x": 50, "y": -50},    # Right wingman
    {"x": -50, "y": -50},   # Left wingman
    {"x": 0, "y": -100}     # Trailing element
]

# Calculate actual positions
wingmen_positions = []
for offset in formation_offsets[1:]:  # Skip leader
    wingmen_positions.append({
        "x": leader_coords['x'] + offset['x'],
        "y": leader_coords['y'] + offset['y'],
        "alt": leader_coords.get('alt', 8000)
    })
```

### Generating Search Patterns

```python
import math

def generate_search_pattern(center_coords, radius, num_points):
    """Generate waypoints in a circular search pattern."""
    waypoints = []

    for i in range(num_points):
        angle = (2 * math.pi * i) / num_points
        x = center_coords['x'] + radius * math.cos(angle)
        y = center_coords['y'] + radius * math.sin(angle)

        waypoints.append({"x": x, "y": y})

    return waypoints

# Usage
target_coords = get_group_coordinates(content, "Enemy Base")
search_waypoints = generate_search_pattern(target_coords, 5000, 8)

# Now use waypoints.add to create the route
```

---

## Best Practices

### 1. Always Check for Altitude

```python
coords = get_group_coordinates(content, "Ground-1")

# Not all groups have altitude (ground units may not)
if 'alt' in coords:
    print(f"Altitude: {coords['alt']}m")
else:
    print("Ground unit - no altitude")
```

### 2. Use Filters for Performance

```python
# Get only what you need
blue_aircraft = get_all_positions(content, coalition="blue", unit_type="plane")

# More efficient than:
# all_groups = get_all_positions(content)
# blue_aircraft = {name: pos for name, pos in all_groups.items()
#                  if pos['coalition'] == 'blue' and pos['unit_type'] == 'plane'}
```

### 3. Handle Missing Coordinates

```python
try:
    coords = get_group_coordinates(content, "Unknown-Group")
except ValueError as e:
    print(f"Could not get coordinates: {e}")
    # Use default or fallback coordinates
    coords = {"x": 0, "y": 0, "alt": 0}
```

---

## Common Patterns

### Pattern 1: Mission Boundaries

```python
from miz_modification.coordinates.extract import get_all_positions

# Find mission area bounds
all_positions = get_all_positions(content)

min_x = min(pos['x'] for pos in all_positions.values())
max_x = max(pos['x'] for pos in all_positions.values())
min_y = min(pos['y'] for pos in all_positions.values())
max_y = max(pos['y'] for pos in all_positions.values())

print(f"Mission area: {(max_x-min_x)/1000:.1f}km x {(max_y-min_y)/1000:.1f}km")
print(f"Center: x={(min_x+max_x)/2:.0f}, y={(min_y+max_y)/2:.0f}")
```

### Pattern 2: Threat Analysis

```python
# Find all threats within range
player_pos = get_group_coordinates(content, "Player")
threats = get_all_positions(content, coalition="red")

threat_range_km = 50
threats_in_range = []

for name, pos in threats.items():
    dx = pos['x'] - player_pos['x']
    dy = pos['y'] - player_pos['y']
    distance = math.sqrt(dx**2 + dy**2) / 1000

    if distance <= threat_range_km:
        threats_in_range.append((name, distance))

threats_in_range.sort(key=lambda x: x[1])
print(f"Threats within {threat_range_km}km:")
for name, dist in threats_in_range:
    print(f"  {name}: {dist:.1f}km")
```

### Pattern 3: Waypoint Route Analysis

```python
# Analyze route length
from miz_modification.waypoints.list import list_waypoints

waypoints = list_waypoints(content, "Fighter-1")

total_distance = 0
for i in range(len(waypoints) - 1):
    wp1 = waypoints[i]
    wp2 = waypoints[i + 1]

    dx = wp2['x'] - wp1['x']
    dy = wp2['y'] - wp1['y']
    segment_distance = math.sqrt(dx**2 + dy**2)

    total_distance += segment_distance

print(f"Total route length: {total_distance/1000:.1f} km")
```

---

## See Also

- [Group Operations](groups.md) - Modify group positions
- [Unit Operations](units.md) - Modify unit positions
- [Waypoint Operations](waypoints.md) - Modify waypoint positions
- [Mission Analysis](mission-analysis.md) - Comprehensive mission inspection
