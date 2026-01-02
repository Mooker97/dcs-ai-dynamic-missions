# Mission Analysis Operations

Complete guide to inspecting and analyzing DCS mission files using read-only operations.

## Overview

Mission analysis operations allow you to understand what's in a .miz file without modifying it. This includes discovering groups, units, positions, loadouts, waypoints, and mission structure.

**Use Cases**:
- Understanding existing missions before modification
- Validating mission structure
- Extracting mission data for reports or analysis
- Finding specific groups, units, or positions
- Analyzing enemy placement and routes

**Key Principle**: All operations in this guide are read-only. They inspect mission content but never modify it.

---

## Quick Start

### Basic Mission Inspection

```python
from miz_modification.parsing.miz_parser import MizParser
from miz_modification.groups.list import list_all_groups

# Load mission
parser = MizParser("mission.miz")
parser.extract()
content = parser.get_mission_content()

# Get overview
groups = list_all_groups(content)

print(f"Blue groups: {len(groups['blue'])}")
print(f"Red groups: {len(groups['red'])}")
print(f"Neutral groups: {len(groups['neutrals'])}")
print(f"Total: {sum(len(g) for g in groups.values())}")

# List each group
for coalition, group_list in groups.items():
    print(f"\n{coalition.upper()} Coalition:")
    for group in group_list:
        print(f"  - {group['name']} ({group['category']}) - {len(group['units'])} units")

parser.cleanup()
```

---

## Group Inspection

### `list_all_groups()`

Get all groups in the mission organized by coalition.

**Module**: `miz_modification.groups.list`

**Signature**:
```python
def list_all_groups(mission_content: str) -> Dict[str, List[Dict]]
```

**Returns**:

```python
{
    "blue": [
        {
            "name": str,        # Group name
            "category": str,    # plane, helicopter, ship, vehicle, static
            "units": [str]      # List of unit type names
        },
        ...
    ],
    "red": [...],
    "neutrals": [...]
}
```

**Usage Example**:

```python
from miz_modification.groups.list import list_all_groups

groups = list_all_groups(content)

# Count by category
plane_count = sum(1 for g in groups['blue'] if g['category'] == 'plane')
print(f"Blue aircraft groups: {plane_count}")

# Find specific group
fighter_groups = [g for g in groups['blue'] if 'Fighter' in g['name']]
for group in fighter_groups:
    print(f"Fighter group: {group['name']} with {len(group['units'])} units")
```

**File Wrapper**:
```python
from miz_modification.groups.list import list_all_groups_file

groups = list_all_groups_file("mission.miz")
```

---

### `count_groups()`

Count total groups or groups of a specific type.

**Module**: `miz_modification.groups.list`

**Signature**:
```python
def count_groups(mission_content: str, unit_type: Optional[str] = None) -> int
```

**Parameters**:

| Name | Type | Required | Description |
|------|------|----------|-------------|
| `mission_content` | `str` | Yes | Raw mission file content |
| `unit_type` | `str` | No | Filter by type: "plane", "helicopter", "ship", "vehicle", "static" |

**Usage Example**:

```python
from miz_modification.groups.list import count_groups

# Count all groups
total = count_groups(content)
print(f"Total groups: {total}")

# Count by type
planes = count_groups(content, "plane")
helicopters = count_groups(content, "helicopter")
ships = count_groups(content, "ship")
vehicles = count_groups(content, "vehicle")

print(f"Aircraft: {planes}")
print(f"Helicopters: {helicopters}")
print(f"Ships: {ships}")
print(f"Ground units: {vehicles}")
```

---

### `get_group_info()`

Get detailed information about a specific group.

**Module**: `miz_modification.groups.list`

**Signature**:
```python
def get_group_info(mission_content: str, group_name: str) -> Dict
```

**Returns**:

```python
{
    "name": str,
    "groupId": int,
    "unit_count": int,
    "units": [
        {
            "index": int,
            "name": str,
            "type": str,
            "unitId": int,
            "skill": str
        },
        ...
    ],
    "position": {"x": float, "y": float},
    "exists": bool
}
```

**Usage Example**:

```python
from miz_modification.groups.list import get_group_info

info = get_group_info(content, "Fighter-1")

print(f"Group: {info['name']}")
print(f"Group ID: {info['groupId']}")
print(f"Position: x={info['position']['x']}, y={info['position']['y']}")
print(f"Units: {info['unit_count']}")

for unit in info['units']:
    print(f"  {unit['index']}: {unit['name']} ({unit['type']}) - {unit['skill']}")
```

**File Wrapper**:
```python
from miz_modification.groups.list import get_group_info_file

info = get_group_info_file("mission.miz", "Fighter-1")
```

**Error Conditions**:
- `ValueError`: Group not found in mission

---

### `get_groups_by_coalition()`

Get all groups for a specific coalition.

**Module**: `miz_modification.groups.list`

**Signature**:
```python
def get_groups_by_coalition(mission_content: str, coalition: str) -> List[str]
```

**Parameters**:

| Name | Type | Required | Description |
|------|------|----------|-------------|
| `mission_content` | `str` | Yes | Raw mission file content |
| `coalition` | `str` | Yes | Coalition: "blue", "red", or "neutrals" |

**Usage Example**:

```python
from miz_modification.groups.list import get_groups_by_coalition

blue_groups = get_groups_by_coalition(content, "blue")
print(f"Blue has {len(blue_groups)} groups:")
for group in blue_groups:
    print(f"  - {group['name']}")
```

**Error Conditions**:
- `ValueError`: Invalid coalition name

---

### `get_groups_by_type()`

Get all groups of a specific unit type.

**Module**: `miz_modification.groups.list`

**Signature**:
```python
def get_groups_by_type(mission_content: str, unit_type: str) -> List[str]
```

**Parameters**:

| Name | Type | Required | Description |
|------|------|----------|-------------|
| `mission_content` | `str` | Yes | Raw mission file content |
| `unit_type` | `str` | Yes | Type: "plane", "helicopter", "ship", "vehicle", "static" |

**Usage Example**:

```python
from miz_modification.groups.list import get_groups_by_type

# Find all aircraft
aircraft = get_groups_by_type(content, "plane")
print(f"Aircraft groups: {', '.join(aircraft)}")

# Find all SAM sites (usually vehicles)
sams = [g for g in get_groups_by_type(content, "vehicle") if 'SAM' in g]
print(f"SAM sites: {', '.join(sams)}")
```

**Error Conditions**:
- `ValueError`: Invalid unit_type

---

## Position Analysis

### `get_all_positions()`

Get positions of all groups with optional filtering.

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
| `mission_content` | `str` | Yes | Raw mission file content |
| `coalition` | `str` | No | Filter: "blue", "red", "neutrals" |
| `unit_type` | `str` | No | Filter: "plane", "helicopter", "ship", "vehicle", "static" |

**Returns**:

```python
{
    "GroupName": {
        "x": float,
        "y": float,
        "alt": float,           # If available
        "coalition": str,
        "unit_type": str
    },
    ...
}
```

**Usage Example**:

```python
from miz_modification.coordinates.extract import get_all_positions

# Get all positions
all_positions = get_all_positions(content)
print(f"Total groups positioned: {len(all_positions)}")

# Get only red aircraft
red_aircraft = get_all_positions(content, coalition="red", unit_type="plane")
print(f"Red aircraft: {len(red_aircraft)}")

for name, pos in red_aircraft.items():
    print(f"  {name}: x={pos['x']}, y={pos['y']}, alt={pos.get('alt', 'N/A')}")
```

**File Wrapper**:
```python
from miz_modification.coordinates.extract import get_all_positions_file

positions = get_all_positions_file("mission.miz", coalition="blue")
```

---

### `get_group_coordinates()`

Get position of a specific group (first unit's position).

**Module**: `miz_modification.coordinates.extract`

**Signature**:
```python
def get_group_coordinates(mission_content: str, group_name: str) -> Dict[str, float]
```

**Returns**:

```python
{
    "x": float,      # X coordinate in meters
    "y": float,      # Y coordinate in meters
    "alt": float     # Altitude in meters (if available)
}
```

**Usage Example**:

```python
from miz_modification.coordinates.extract import get_group_coordinates

coords = get_group_coordinates(content, "Fighter-1")
print(f"Position: x={coords['x']}, y={coords['y']}")
if 'alt' in coords:
    print(f"Altitude: {coords['alt']}m")
```

**File Wrapper**:
```python
from miz_modification.coordinates.extract import get_group_coordinates_file

coords = get_group_coordinates_file("mission.miz", "Fighter-1")
```

**Error Conditions**:
- `ValueError`: Group not found
- `ValueError`: Could not extract coordinates

---

## Waypoint Analysis

### `list_waypoints()`

Get all waypoints for a group's route.

**Module**: `miz_modification.waypoints.list`

**Signature**:
```python
def list_waypoints(mission_content: str, group_name: str) -> List[Dict[str, Any]]
```

**Returns**:

```python
[
    {
        "index": int,        # Waypoint number (1-based)
        "x": float,          # X coordinate
        "y": float,          # Y coordinate
        "alt": float,        # Altitude in meters
        "speed": float,      # Speed in m/s
        "action": str        # "Turning Point", "Fly Over Point", etc.
    },
    ...
]
```

**Usage Example**:

```python
from miz_modification.waypoints.list import list_waypoints

waypoints = list_waypoints(content, "Fighter-1")
print(f"Route has {len(waypoints)} waypoints")

for wp in waypoints:
    print(f"WP{wp['index']}: {wp['action']} at x={wp['x']}, y={wp['y']}, "
          f"alt={wp['alt']}m, speed={wp['speed']:.0f}m/s")
```

**File Wrapper**:
```python
from miz_modification.waypoints.list import list_waypoints_file

waypoints = list_waypoints_file("mission.miz", "Fighter-1")
```

---

### `get_waypoint_count()`

Get number of waypoints in a group's route.

**Module**: `miz_modification.waypoints.list`

**Signature**:
```python
def get_waypoint_count(mission_content: str, group_name: str) -> int
```

**Usage Example**:

```python
from miz_modification.waypoints.list import get_waypoint_count

count = get_waypoint_count(content, "Fighter-1")
print(f"Fighter-1 has {count} waypoints")
```

---

## Loadout Analysis

### `list_loadout()`

Get complete loadout information for a unit.

**Module**: `miz_modification.loadouts.list`

**Signature**:
```python
def list_loadout(mission_content: str, group_name: str, unit_index: int = 1) -> Dict[str, Any]
```

**Returns**:

```python
{
    "pylons": {
        1: {"CLSID": str, "num": int},
        ...
    },
    "chaff": int,
    "flare": int,
    "fuel": float,
    "gun": int,
    "unit_type": str,
    "unit_name": str
}
```

**Usage Example**:

```python
from miz_modification.loadouts.list import list_loadout

loadout = list_loadout(content, "Fighter-1", 1)

print(f"Aircraft: {loadout['unit_type']}")
print(f"Fuel: {loadout['fuel']}kg")
print(f"Countermeasures: {loadout['chaff']} chaff, {loadout['flare']} flare")
print(f"Gun: {loadout['gun']} rounds")

print("Weapons:")
for pylon_num, pylon_data in loadout['pylons'].items():
    print(f"  Pylon {pylon_num}: {pylon_data['CLSID']}")
```

**File Wrapper**:
```python
from miz_modification.loadouts.list import list_loadout_file

loadout = list_loadout_file("mission.miz", "Fighter-1", 1)
```

---

## Complete Mission Analysis

### Pattern 1: Mission Overview Report

```python
from miz_modification.parsing.miz_parser import MizParser
from miz_modification.groups.list import list_all_groups, count_groups
from miz_modification.coordinates.extract import get_all_positions

def generate_mission_report(miz_file):
    """Generate comprehensive mission overview report."""

    parser = MizParser(miz_file)
    parser.extract()
    content = parser.get_mission_content()

    print("=" * 60)
    print(f"MISSION ANALYSIS: {miz_file}")
    print("=" * 60)

    # Group counts
    print("\n--- GROUP SUMMARY ---")
    groups = list_all_groups(content)
    for coalition, group_list in groups.items():
        print(f"{coalition.upper()}: {len(group_list)} groups")

        # Count by category
        categories = {}
        for group in group_list:
            cat = group['category']
            categories[cat] = categories.get(cat, 0) + 1

        for cat, count in categories.items():
            print(f"  - {cat}: {count}")

    # Unit counts
    print("\n--- UNIT COUNTS ---")
    for unit_type in ['plane', 'helicopter', 'ship', 'vehicle']:
        count = count_groups(content, unit_type)
        if count > 0:
            print(f"{unit_type.capitalize()}: {count}")

    # Position analysis
    print("\n--- POSITION ANALYSIS ---")
    all_positions = get_all_positions(content)

    if all_positions:
        xs = [pos['x'] for pos in all_positions.values()]
        ys = [pos['y'] for pos in all_positions.values()]

        min_x, max_x = min(xs), max(xs)
        min_y, max_y = min(ys), max(ys)

        width_km = (max_x - min_x) / 1000
        height_km = (max_y - min_y) / 1000

        print(f"Mission area: {width_km:.1f}km x {height_km:.1f}km")
        print(f"Center: x={(min_x+max_x)/2:.0f}, y={(min_y+max_y)/2:.0f}")

    parser.cleanup()

# Usage
generate_mission_report("mission.miz")
```

### Pattern 2: Threat Analysis

```python
import math
from miz_modification.coordinates.extract import get_group_coordinates, get_all_positions

def analyze_threats(content, friendly_group, threat_range_km=50):
    """Analyze threats within range of a friendly group."""

    # Get friendly position
    friendly_pos = get_group_coordinates(content, friendly_group)

    # Get all enemy positions
    threats = get_all_positions(content, coalition="red")

    print(f"Threat analysis for {friendly_group}")
    print(f"Position: x={friendly_pos['x']:.0f}, y={friendly_pos['y']:.0f}")
    print(f"Scan range: {threat_range_km}km\n")

    threats_in_range = []

    for name, pos in threats.items():
        dx = pos['x'] - friendly_pos['x']
        dy = pos['y'] - friendly_pos['y']
        distance = math.sqrt(dx**2 + dy**2) / 1000

        if distance <= threat_range_km:
            # Calculate bearing
            bearing = math.degrees(math.atan2(dx, dy)) % 360

            threats_in_range.append({
                "name": name,
                "distance": distance,
                "bearing": bearing,
                "type": pos['unit_type']
            })

    # Sort by distance
    threats_in_range.sort(key=lambda x: x['distance'])

    print(f"Found {len(threats_in_range)} threats within {threat_range_km}km:\n")

    for threat in threats_in_range:
        print(f"{threat['name']}")
        print(f"  Distance: {threat['distance']:.1f}km")
        print(f"  Bearing: {threat['bearing']:.0f}°")
        print(f"  Type: {threat['type']}")
        print()

# Usage
analyze_threats(content, "Fighter-1", threat_range_km=100)
```

### Pattern 3: Route Analysis

```python
import math
from miz_modification.waypoints.list import list_waypoints

def analyze_route(content, group_name):
    """Analyze a group's flight route."""

    waypoints = list_waypoints(content, group_name)

    if not waypoints:
        print(f"{group_name} has no waypoints")
        return

    print(f"Route analysis for {group_name}")
    print(f"Total waypoints: {len(waypoints)}\n")

    total_distance = 0
    total_time = 0

    for i in range(len(waypoints) - 1):
        wp1 = waypoints[i]
        wp2 = waypoints[i + 1]

        # Calculate segment distance
        dx = wp2['x'] - wp1['x']
        dy = wp2['y'] - wp1['y']
        dz = wp2['alt'] - wp1['alt']

        distance_2d = math.sqrt(dx**2 + dy**2)
        distance_3d = math.sqrt(dx**2 + dy**2 + dz**2)

        # Calculate time (use wp2 speed for segment)
        if wp2['speed'] > 0:
            time_seconds = distance_3d / wp2['speed']
            time_minutes = time_seconds / 60
        else:
            time_minutes = 0

        total_distance += distance_3d
        total_time += time_minutes

        # Calculate heading
        heading = math.degrees(math.atan2(dx, dy)) % 360

        print(f"WP{wp1['index']} → WP{wp2['index']}: {wp2['action']}")
        print(f"  Distance: {distance_2d/1000:.1f}km (2D), {distance_3d/1000:.1f}km (3D)")
        print(f"  Altitude: {wp1['alt']:.0f}m → {wp2['alt']:.0f}m ({dz:+.0f}m)")
        print(f"  Heading: {heading:.0f}°")
        print(f"  Speed: {wp2['speed']:.0f}m/s ({wp2['speed']*1.94384:.0f}kts)")
        print(f"  Time: {time_minutes:.1f}min")
        print()

    print(f"Total route length: {total_distance/1000:.1f}km")
    print(f"Total flight time: {total_time:.0f}min ({total_time/60:.1f}hrs)")

# Usage
analyze_route(content, "Fighter-1")
```

### Pattern 4: Loadout Summary

```python
from miz_modification.groups.list import get_group_info
from miz_modification.loadouts.list import list_loadout

def summarize_loadouts(content, group_name):
    """Summarize loadouts for all units in a group."""

    group_info = get_group_info(content, group_name)

    print(f"Loadout summary for {group_name}")
    print(f"Total units: {group_info['unit_count']}\n")

    for unit in group_info['units']:
        unit_idx = unit['index']
        loadout = list_loadout(content, group_name, unit_idx)

        print(f"{unit['name']} ({unit['type']})")
        print(f"  Fuel: {loadout['fuel']:.0f}kg")
        print(f"  CM: {loadout['chaff']} chaff, {loadout['flare']} flare")
        print(f"  Gun: {loadout['gun']} rounds")

        weapon_count = {}
        for pylon_data in loadout['pylons'].values():
            clsid = pylon_data['CLSID']
            weapon_count[clsid] = weapon_count.get(clsid, 0) + 1

        print("  Weapons:")
        for clsid, count in weapon_count.items():
            print(f"    {count}x {clsid}")
        print()

# Usage
summarize_loadouts(content, "Fighter-1")
```

### Pattern 5: Coalition Comparison

```python
from miz_modification.groups.list import list_all_groups
from miz_modification.coordinates.extract import get_all_positions

def compare_coalitions(content):
    """Compare blue and red coalition capabilities."""

    groups = list_all_groups(content)

    print("COALITION COMPARISON")
    print("=" * 60)

    for coalition in ['blue', 'red']:
        print(f"\n{coalition.upper()} COALITION")
        print("-" * 60)

        group_list = groups[coalition]
        print(f"Total groups: {len(group_list)}")

        # Count by category
        categories = {}
        unit_count = 0

        for group in group_list:
            cat = group['category']
            categories[cat] = categories.get(cat, 0) + 1
            unit_count += len(group['units'])

        print(f"Total units: {unit_count}")
        print("\nBy category:")
        for cat in ['plane', 'helicopter', 'ship', 'vehicle', 'static']:
            if cat in categories:
                print(f"  {cat.capitalize()}: {categories[cat]} groups")

        # Position spread
        positions = get_all_positions(content, coalition=coalition)
        if positions:
            xs = [pos['x'] for pos in positions.values()]
            ys = [pos['y'] for pos in positions.values()]

            min_x, max_x = min(xs), max(xs)
            min_y, max_y = min(ys), max(ys)

            width = (max_x - min_x) / 1000
            height = (max_y - min_y) / 1000

            print(f"\nDeployment area: {width:.1f}km x {height:.1f}km")

# Usage
compare_coalitions(content)
```

---

## Best Practices

### 1. Always Use try/finally for Cleanup

```python
parser = MizParser("mission.miz")
parser.extract()

try:
    content = parser.get_mission_content()

    # Your analysis code here
    groups = list_all_groups(content)
    # ...

finally:
    parser.cleanup()  # Always cleanup temporary files
```

### 2. Cache Mission Content

```python
# Don't re-extract for multiple operations
parser = MizParser("mission.miz")
parser.extract()
content = parser.get_mission_content()

# Now perform multiple analyses with same content
groups = list_all_groups(content)
positions = get_all_positions(content)
# ...

parser.cleanup()
```

### 3. Handle Missing Data Gracefully

```python
try:
    info = get_group_info(content, "Fighter-1")
    print(f"Found {info['name']}")
except ValueError:
    print("Group not found")

# Check for optional fields
if 'alt' in coords:
    print(f"Altitude: {coords['alt']}m")
else:
    print("No altitude data")
```

### 4. Validate Input Parameters

```python
# Check coalition names
valid_coalitions = ['blue', 'red', 'neutrals']
if coalition not in valid_coalitions:
    raise ValueError(f"Invalid coalition: {coalition}")

# Check unit types
valid_types = ['plane', 'helicopter', 'ship', 'vehicle', 'static']
if unit_type not in valid_types:
    raise ValueError(f"Invalid unit type: {unit_type}")
```

---

## See Also

- [Group Operations](groups.md) - Read-only group functions
- [Coordinate Operations](coordinates.md) - Position extraction
- [Waypoint Operations](waypoints.md) - Route inspection
- [Loadout Operations](loadouts.md) - Weapon configuration inspection
