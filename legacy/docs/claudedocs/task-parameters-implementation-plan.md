# Task Parameters Implementation Plan

## Overview

This document provides a comprehensive implementation plan for adding **Task Parameters** support to the `miz-modifier` library. Task parameters define AI behavior patterns like CAP race tracks, SEAD engagement zones, tanker orbits, AWACS patterns, and more.

**Goal**: Enable reading, modification, and creation of complex AI task behaviors for dynamic mission generation.

---

## Task Parameters in DCS Mission Structure

### Location in Mission File

Task parameters are found within the `["route"]` section of groups:

```lua
["route"] = {
    ["points"] = {
        [1] = { ... },  -- Waypoints
        [2] = { ... },
    },
    -- Task parameters appear here
    ["tasks"] = {
        [1] = {
            ["id"] = "ComboTask",
            ["params"] = {
                ["tasks"] = {
                    [1] = {
                        ["id"] = "CAP",  -- Task type identifier
                        ["params"] = {
                            -- Task-specific parameters
                        },
                    },
                },
            },
        },
    },
}
```

### Common Task Types

| Task ID | Purpose | Common Parameters |
|---------|---------|-------------------|
| `CAP` | Combat Air Patrol | Pattern, altitude, speed |
| `CAS` | Close Air Support | Engagement zone, altitude |
| `SEAD` | Suppression of Enemy Air Defenses | Target types, weapons |
| `Tanker` | Refueling orbit | Race track pattern, altitude, speed, frequency, TACAN |
| `AWACS` | Airborne Early Warning | Orbit pattern, altitude, frequency |
| `GroundAttack` | Strike missions | Target area, weapon restrictions |
| `Escort` | Escort formation | Formation type, protected group |
| `Intercept` | Intercept missions | Engagement rules, weapons free range |

---

## Implementation Phases

### Phase 1: Pattern Recognition & Extraction (Foundation)

**Goal**: Add regex patterns to identify and extract task parameter structures.

#### 1.1 Add Task Section Patterns to `utils/patterns.py`

```python
# ============================================================================
# TASK PARAMETER PATTERNS
# ============================================================================

# Find tasks section within route
# Captures: (tasks_content)
TASKS_SECTION_PATTERN = r'\["tasks"\]\s*=\s*\{(.*?)\},\s*--\s*end\s*of\s*\["tasks"\]'
TASKS_SECTION_PATTERN_COMPILED = re.compile(TASKS_SECTION_PATTERN, re.DOTALL)

# Find individual task block
# Captures: (task_index, task_content)
TASK_BLOCK_PATTERN = r'\[(\d+)\]\s*=\s*\{(.*?)\},'
TASK_BLOCK_PATTERN_COMPILED = re.compile(TASK_BLOCK_PATTERN, re.DOTALL)

# Find task ID field
# Captures: (task_id)
TASK_ID_PATTERN = r'\["id"\]\s*=\s*"([^"]+)"'
TASK_ID_PATTERN_COMPILED = re.compile(TASK_ID_PATTERN)

# Find task params section
# Captures: (params_content)
TASK_PARAMS_PATTERN = r'\["params"\]\s*=\s*\{(.*?)\},'
TASK_PARAMS_PATTERN_COMPILED = re.compile(TASK_PARAMS_PATTERN, re.DOTALL)

# Find enabled flag
# Captures: (enabled - true/false)
TASK_ENABLED_PATTERN = r'\["enabled"\]\s*=\s*(true|false)'
TASK_ENABLED_PATTERN_COMPILED = re.compile(TASK_ENABLED_PATTERN)

# Find auto flag
# Captures: (auto - true/false)
TASK_AUTO_PATTERN = r'\["auto"\]\s*=\s*(true|false)'
TASK_AUTO_PATTERN_COMPILED = re.compile(TASK_AUTO_PATTERN)
```

#### 1.2 Add Task Type Constants

```python
# Valid task types
TASK_TYPES = [
    'ComboTask',      # Container for multiple tasks
    'CAP',            # Combat Air Patrol
    'CAS',            # Close Air Support
    'SEAD',           # Suppression of Enemy Air Defenses
    'Tanker',         # Refueling orbit
    'AWACS',          # Airborne Early Warning
    'GroundAttack',   # Strike missions
    'Escort',         # Escort formation
    'Intercept',      # Intercept missions
    'Orbit',          # Simple orbit pattern
    'EngageTargets',  # Ground attack with specific targets
    'EngageGroup',    # Engage specific enemy group
    'FAC',            # Forward Air Controller
    'Transport',      # Transport/cargo missions
]
```

---

### Phase 2: Read Operations - List & Inspect Tasks

**Goal**: Create read-only functions to inspect existing task parameters.

#### 2.1 Create `tasks/list.py`

**Functions to implement**:

```python
def list_tasks_for_group(mission_content: str, group_name: str) -> List[Dict]:
    """
    List all tasks assigned to a specific group.

    Args:
        mission_content: Raw mission file content
        group_name: Name of the group to inspect

    Returns:
        List of task dictionaries with structure:
        [
            {
                'index': 1,
                'id': 'CAP',
                'enabled': True,
                'auto': True,
                'params': {...}  # Task-specific parameters
            },
            ...
        ]
    """
    pass

def list_tasks_for_group_file(input_miz: str, group_name: str) -> List[Dict]:
    """Convenience wrapper for file-based operation."""
    pass

def get_task_params(mission_content: str, group_name: str, task_id: str) -> Dict:
    """
    Get parameters for a specific task type assigned to a group.

    Args:
        mission_content: Raw mission file content
        group_name: Name of the group
        task_id: Task type identifier (e.g., 'CAP', 'Tanker')

    Returns:
        Dictionary of task parameters or None if not found
    """
    pass

def has_task_type(mission_content: str, group_name: str, task_id: str) -> bool:
    """
    Check if a group has a specific task type assigned.

    Args:
        mission_content: Raw mission file content
        group_name: Name of the group
        task_id: Task type identifier

    Returns:
        True if group has the task, False otherwise
    """
    pass
```

#### 2.2 Create Task-Specific Inspection Functions

```python
def get_cap_parameters(mission_content: str, group_name: str) -> Dict:
    """
    Extract CAP (Combat Air Patrol) parameters.

    Returns:
        {
            'altitude': 8000,
            'speed': 250,
            'pattern': 'Race-Track',
            'length': 50000,  # meters
            'enabled': True
        }
    """
    pass

def get_tanker_parameters(mission_content: str, group_name: str) -> Dict:
    """
    Extract Tanker orbit parameters.

    Returns:
        {
            'altitude': 20000,
            'speed': 450,
            'frequency': 251000000,
            'modulation': 0,  # AM
            'tacan': {
                'channel': 1,
                'mode': 'Y',
                'callsign': 'TEX'
            },
            'enabled': True
        }
    """
    pass

def get_awacs_parameters(mission_content: str, group_name: str) -> Dict:
    """
    Extract AWACS orbit parameters.

    Returns:
        {
            'altitude': 25000,
            'speed': 500,
            'frequency': 133000000,
            'modulation': 0,
            'callsign': 9,  # Magic callsign
            'enabled': True
        }
    """
    pass
```

---

### Phase 3: Modification Operations - Update Task Parameters

**Goal**: Enable modification of existing task parameters.

#### 3.1 Create `tasks/modify.py`

**Core modification functions**:

```python
def modify_task_params(
    mission_content: str,
    group_name: str,
    task_id: str,
    **params
) -> str:
    """
    Modify parameters for a specific task.

    Args:
        mission_content: Raw mission file content
        group_name: Name of the group
        task_id: Task type identifier
        **params: Task-specific parameters to update

    Returns:
        Modified mission content

    Example:
        # Modify CAP altitude and speed
        content = modify_task_params(
            content,
            "CAP Flight",
            "CAP",
            altitude=10000,
            speed=300
        )
    """
    pass

def modify_task_params_file(
    input_miz: str,
    output_miz: str,
    group_name: str,
    task_id: str,
    **params
) -> None:
    """Convenience wrapper for file-based operation."""
    pass
```

#### 3.2 Task-Specific Modification Functions

```python
def modify_cap_pattern(
    mission_content: str,
    group_name: str,
    altitude: Optional[float] = None,
    speed: Optional[float] = None,
    pattern: Optional[str] = None,
    length: Optional[float] = None
) -> str:
    """
    Modify CAP race track pattern parameters.

    Args:
        mission_content: Raw mission file content
        group_name: Name of the CAP group
        altitude: New altitude in meters (optional)
        speed: New speed in m/s (optional)
        pattern: Pattern type ('Race-Track', 'Circle') (optional)
        length: Race track length in meters (optional)

    Returns:
        Modified mission content
    """
    pass

def modify_tanker_orbit(
    mission_content: str,
    group_name: str,
    altitude: Optional[float] = None,
    speed: Optional[float] = None,
    frequency: Optional[int] = None,
    tacan_channel: Optional[int] = None,
    tacan_mode: Optional[str] = None,
    callsign: Optional[str] = None
) -> str:
    """
    Modify tanker orbit parameters.

    Args:
        mission_content: Raw mission file content
        group_name: Name of the tanker group
        altitude: Orbit altitude in meters (optional)
        speed: Orbit speed in m/s (optional)
        frequency: Radio frequency in Hz (optional)
        tacan_channel: TACAN channel number (optional)
        tacan_mode: TACAN mode ('X' or 'Y') (optional)
        callsign: TACAN callsign (optional)

    Returns:
        Modified mission content
    """
    pass

def modify_sead_parameters(
    mission_content: str,
    group_name: str,
    target_types: Optional[List[str]] = None,
    engagement_range: Optional[float] = None,
    weapons_free_range: Optional[float] = None
) -> str:
    """
    Modify SEAD engagement parameters.

    Args:
        mission_content: Raw mission file content
        group_name: Name of the SEAD group
        target_types: List of target types to engage (optional)
        engagement_range: Maximum engagement range in meters (optional)
        weapons_free_range: Range to go weapons free in meters (optional)

    Returns:
        Modified mission content
    """
    pass
```

---

### Phase 4: Creation Operations - Add New Tasks

**Goal**: Enable adding task parameters to groups that don't have them.

#### 4.1 Create `tasks/add.py`

```python
def add_cap_task(
    mission_content: str,
    group_name: str,
    altitude: float = 8000,
    speed: float = 250,
    pattern: str = 'Race-Track',
    length: float = 50000
) -> str:
    """
    Add CAP task parameters to a group.

    Args:
        mission_content: Raw mission file content
        group_name: Name of the group
        altitude: Patrol altitude in meters
        speed: Patrol speed in m/s
        pattern: Pattern type ('Race-Track', 'Circle')
        length: Race track length in meters

    Returns:
        Modified mission content with CAP task added

    Example:
        content = add_cap_task(
            content,
            "F-15C CAP",
            altitude=10000,
            speed=300,
            length=60000
        )
    """
    pass

def add_tanker_task(
    mission_content: str,
    group_name: str,
    altitude: float = 20000,
    speed: float = 450,
    frequency: int = 251000000,
    tacan_channel: int = 1,
    tacan_mode: str = 'Y',
    callsign: str = 'TEX'
) -> str:
    """
    Add tanker orbit task to a group.

    Args:
        mission_content: Raw mission file content
        group_name: Name of the tanker group
        altitude: Orbit altitude in meters
        speed: Orbit speed in m/s
        frequency: Radio frequency in Hz
        tacan_channel: TACAN channel number (1-126)
        tacan_mode: TACAN mode ('X' or 'Y')
        callsign: TACAN callsign

    Returns:
        Modified mission content with tanker task added
    """
    pass

def add_awacs_task(
    mission_content: str,
    group_name: str,
    altitude: float = 25000,
    speed: float = 500,
    frequency: int = 133000000,
    callsign: int = 9
) -> str:
    """
    Add AWACS orbit task to a group.

    Args:
        mission_content: Raw mission file content
        group_name: Name of the AWACS group
        altitude: Orbit altitude in meters
        speed: Orbit speed in m/s
        frequency: Radio frequency in Hz
        callsign: AWACS callsign number

    Returns:
        Modified mission content with AWACS task added
    """
    pass
```

---

## Task Parameter Structure Examples

### CAP (Combat Air Patrol)

```lua
["tasks"] = {
    [1] = {
        ["id"] = "ComboTask",
        ["params"] = {
            ["tasks"] = {
                [1] = {
                    ["id"] = "CAP",
                    ["params"] = {
                        ["altitude"] = 8000,
                        ["speed"] = 250,
                        ["pattern"] = "Race-Track",
                        ["length"] = 50000,
                    },
                },
            },
        },
    },
}
```

### Tanker Orbit

```lua
["tasks"] = {
    [1] = {
        ["id"] = "Tanker",
        ["params"] = {
            ["altitude"] = 20000,
            ["speed"] = 450,
            ["frequency"] = 251000000,
            ["modulation"] = 0,
            ["tacan"] = {
                ["channel"] = 1,
                ["mode"] = "Y",
                ["callsign"] = "TEX",
            },
        },
    },
}
```

### AWACS Orbit

```lua
["tasks"] = {
    [1] = {
        ["id"] = "AWACS",
        ["params"] = {
            ["altitude"] = 25000,
            ["speed"] = 500,
            ["frequency"] = 133000000,
            ["modulation"] = 0,
            ["callsign"] = 9,
        },
    },
}
```

### SEAD Engagement

```lua
["tasks"] = {
    [1] = {
        ["id"] = "SEAD",
        ["params"] = {
            ["targetTypes"] = {
                [1] = "SAM SR",
                [2] = "SAM TR",
            },
            ["engagementRange"] = 75000,
            ["weaponsFreeRange"] = 50000,
        },
    },
}
```

---

## Testing Strategy

### Test Files Needed

1. **CAP Mission** - F-15C with CAP race track pattern
2. **Tanker Mission** - KC-135 with orbit and TACAN
3. **AWACS Mission** - E-3A with orbit pattern
4. **SEAD Mission** - F-16C with SEAD engagement zone
5. **Mixed Mission** - Multiple task types in one mission

### Test Cases

#### Read Operations
- ✅ List all tasks for a group
- ✅ Extract CAP parameters
- ✅ Extract tanker parameters
- ✅ Extract AWACS parameters
- ✅ Detect missing tasks gracefully

#### Modification Operations
- ✅ Modify CAP altitude and speed
- ✅ Modify tanker TACAN channel
- ✅ Modify AWACS frequency
- ✅ Handle groups without tasks section
- ✅ Preserve other task parameters when modifying

#### Creation Operations
- ✅ Add CAP task to group without tasks
- ✅ Add tanker task with full parameters
- ✅ Add multiple tasks to same group
- ✅ Validate parameters before insertion

---

## Implementation Priority

### High Priority (MVP Support)
1. ✅ **Phase 1**: Pattern recognition for tasks section
2. ✅ **Phase 2**: Read operations - list and inspect tasks
3. ⏳ **Phase 3**: Modify CAP, Tanker, AWACS parameters

### Medium Priority (Enhanced Missions)
4. ⏳ **Phase 4**: Add new task parameters to groups
5. ⏳ SEAD, CAS, Ground Attack task support
6. ⏳ Escort and formation task support

### Low Priority (Advanced Features)
7. ⏳ Complex task chaining and sequencing
8. ⏳ Conditional task execution
9. ⏳ Advanced AI behavior patterns

---

## Usage Examples

### Inspecting Existing Tasks

```python
from miz-modifier.tasks.list import list_tasks_for_group_file, get_tanker_parameters

# List all tasks for a group
tasks = list_tasks_for_group_file("mission.miz", "Texaco-1")
for task in tasks:
    print(f"Task: {task['id']}, Enabled: {task['enabled']}")

# Get specific task parameters
tanker_params = get_tanker_parameters(content, "Texaco-1")
print(f"TACAN: {tanker_params['tacan']['channel']}{tanker_params['tacan']['mode']}")
print(f"Frequency: {tanker_params['frequency'] / 1e6} MHz")
```

### Modifying Task Parameters

```python
from miz-modifier.tasks.modify import modify_tanker_orbit_file

# Change tanker altitude and TACAN channel
modify_tanker_orbit_file(
    "input.miz",
    "output.miz",
    "Texaco-1",
    altitude=25000,
    tacan_channel=5,
    tacan_mode='Y'
)
```

### Creating New Tasks

```python
from miz-modifier.tasks.add import add_cap_task_file

# Add CAP task to an existing fighter group
add_cap_task_file(
    "input.miz",
    "output.miz",
    "Viper-1",
    altitude=10000,
    speed=300,
    pattern='Race-Track',
    length=70000
)
```

---

## Benefits for Dynamic Mission Generation

### Replayability Features

1. **Randomized CAP Patterns**
   - Vary altitude: 6000-12000m
   - Vary patrol length: 40000-80000m
   - Random race track orientation

2. **Dynamic Tanker Positioning**
   - Randomize orbit location
   - Vary altitude based on mission type
   - Random TACAN channels

3. **Variable AWACS Coverage**
   - Randomize orbit position
   - Adjust altitude for different radar coverage
   - Dynamic frequency assignment

4. **Adaptive SEAD Behavior**
   - Adjust engagement ranges based on threat
   - Randomize target priority
   - Dynamic weapons free range

### Mission Type Support

- **SEAD Missions**: Configure SEAD parameters for realistic suppression operations
- **CAP Missions**: Set up race track patterns for air defense
- **Strike Missions**: Configure ground attack parameters and target areas
- **Support Missions**: Place tankers and AWACS with proper orbits

---

## Integration with Existing Modules

### Coordinate System Integration

Task parameters often reference waypoints and zones by coordinates. Integration points:

```python
from miz-modifier.coordinates.extract import get_group_position
from miz-modifier.tasks.add import add_cap_task

# Get group starting position
pos = get_group_position(content, "CAP Flight")

# Add CAP task centered on starting position
content = add_cap_task(
    content,
    "CAP Flight",
    altitude=pos['alt'] + 2000,  # 2km above starting altitude
    speed=250
)
```

### Waypoint Integration

Tasks interact with route waypoints:

```python
from miz-modifier.waypoints.list import list_waypoints
from miz-modifier.tasks.modify import modify_cap_pattern

# Get race track waypoints
waypoints = list_waypoints(content, "CAP Flight")
wp1 = waypoints[0]
wp2 = waypoints[1]

# Calculate race track length from waypoints
import math
dx = wp2['x'] - wp1['x']
dy = wp2['y'] - wp1['y']
length = math.sqrt(dx**2 + dy**2)

# Update CAP task to match waypoint distance
content = modify_cap_pattern(content, "CAP Flight", length=length)
```

---

## Future Enhancements

### Advanced Task Types

- **FAC (Forward Air Controller)**: Coordinate CAS missions
- **Transport**: Cargo and troop transport missions
- **Reconnaissance**: Photo reconnaissance patterns
- **Anti-Ship**: Naval strike missions
- **Ground Attack**: Precision strike coordination

### Task Sequencing

Support for task chains and conditional execution:

```lua
["tasks"] = {
    [1] = {
        ["id"] = "ComboTask",
        ["params"] = {
            ["tasks"] = {
                [1] = { ["id"] = "EngageTargets", ... },
                [2] = { ["id"] = "RTB", ... },  -- After targets destroyed
            },
        },
    },
}
```

### Mission Scripting Integration

Connect task parameters with dynamic Lua scripting:

- Randomize task parameters at mission start
- Adjust behavior based on player performance
- Dynamic reinforcement spawning
- Adaptive AI difficulty

---

## Notes

- Task parameters are optional - not all groups have them
- Task structures can be nested (ComboTask contains multiple sub-tasks)
- Some parameters vary by aircraft type and mission capability
- Always validate against real .miz files from DCS Mission Editor
- Different DCS versions may have different parameter structures

---

*Document created: 2025-12-09*
*Status: Planning Phase - Ready for Implementation*
