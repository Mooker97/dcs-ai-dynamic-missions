# Trigger Operations

Complete reference for trigger and trigger zone operations in the miz-modification library.

## Overview

Triggers are the event system in DCS missions. They define conditions (when something happens) and actions (what to do). Trigger zones are circular or quadrilateral areas on the map used in trigger conditions.

**Use Cases**:
- Adding custom Lua scripts to missions (DO SCRIPT triggers)
- Creating trigger zones for objectives, spawn areas, or detection
- Inspecting existing mission triggers and zones
- Mission event automation

**Important**: DCS missions have THREE trigger-related sections:
1. `["triggers"]["zones"]` - Trigger zones (map areas)
2. `["trigrules"]` - Human-readable trigger definitions
3. `["trig"]` - Compiled Lua code (conditions, actions, execution functions)

**Module**: `miz_modification.triggers`

---

## Trigger Zone Operations

### `list_trigger_zones()`

List all trigger zones in the mission.

**Module**: `miz_modification.triggers.list`

**Signature**:
```python
def list_trigger_zones(mission_content: str) -> List[Dict[str, Any]]
```

**Returns**:

```python
[
    {
        "index": int,        # Zone array index
        "name": str,         # Zone name
        "zoneId": int,       # Unique zone ID
        "x": float,          # X coordinate (meters)
        "y": float,          # Y coordinate (meters)
        "radius": float,     # Zone radius (meters)
        "type": int,         # 0=circle, 2=quad
        "hidden": bool,      # Hidden from F10 map
        "heading": float     # Zone heading (radians)
    },
    ...
]
```

**Usage Example**:

```python
from miz_modification.triggers.list import list_trigger_zones
from miz_modification.parsing.miz_parser import MizParser

parser = MizParser("mission.miz")
parser.extract()
content = parser.get_mission_content()

zones = list_trigger_zones(content)
print(f"Found {len(zones)} trigger zones")

for zone in zones:
    print(f"{zone['name']}:")
    print(f"  Position: x={zone['x']}, y={zone['y']}")
    print(f"  Radius: {zone['radius']}m")
    print(f"  Hidden: {zone['hidden']}")

parser.cleanup()
```

**File Wrapper**:

```python
from miz_modification.triggers.list import list_trigger_zones_file

zones = list_trigger_zones_file("mission.miz")
for zone in zones:
    print(f"{zone['name']}: {zone['radius']}m radius")
```

---

### `find_zone_by_name()`

Find a trigger zone by its name.

**Module**: `miz_modification.triggers.list`

**Signature**:
```python
def find_zone_by_name(mission_content: str, zone_name: str) -> Optional[Dict[str, Any]]
```

**Returns**:

Zone dictionary if found, `None` otherwise.

**Usage Example**:

```python
from miz_modification.triggers.list import find_zone_by_name

zone = find_zone_by_name(content, "Target Area")

if zone:
    print(f"Found zone at x={zone['x']}, y={zone['y']}")
    print(f"Radius: {zone['radius']}m")
else:
    print("Zone not found")
```

---

### `find_zone_by_id()`

Find a trigger zone by its ID.

**Module**: `miz_modification.triggers.list`

**Signature**:
```python
def find_zone_by_id(mission_content: str, zone_id: int) -> Optional[Dict[str, Any]]
```

**Returns**:

Zone dictionary if found, `None` otherwise.

**Usage Example**:

```python
from miz_modification.triggers.list import find_zone_by_id

zone = find_zone_by_id(content, 1)
if zone:
    print(f"Zone {zone_id}: {zone['name']}")
```

---

### `add_trigger_zone()`

Add a new trigger zone to the mission.

**Module**: `miz_modification.triggers.add`

**Signature**:
```python
def add_trigger_zone(mission_content: str, name: str, x: float, y: float,
                     radius: float, hidden: bool = False, zone_type: int = 0,
                     heading: float = 0) -> str
```

**Parameters**:

| Name | Type | Required | Description |
|------|------|----------|-------------|
| `mission_content` | `str` | Yes | Raw mission file content |
| `name` | `str` | Yes | Zone name (must be unique) |
| `x` | `float` | Yes | X coordinate in meters |
| `y` | `float` | Yes | Y coordinate in meters |
| `radius` | `float` | Yes | Zone radius in meters |
| `hidden` | `bool` | No | Hide from F10 map (default: False) |
| `zone_type` | `int` | No | 0=circle, 2=quad (default: 0) |
| `heading` | `float` | No | Zone heading in radians (default: 0) |

**Returns**:

Modified mission content as string.

**Usage Example**:

```python
from miz_modification.triggers.add import add_trigger_zone
from miz_modification.parsing.miz_parser import MizParser

parser = MizParser("input.miz")
parser.extract()
content = parser.get_mission_content()

# Add circular zone with 5km radius
content = add_trigger_zone(
    content,
    name="Target Area",
    x=150000,
    y=55000,
    radius=5000
)

# Add hidden zone (not shown on F10 map)
content = add_trigger_zone(
    content,
    name="Spawn Zone",
    x=100000,
    y=40000,
    radius=3000,
    hidden=True
)

parser.write_mission_content(content)
parser.repackage("output.miz")
parser.cleanup()
```

**File Wrapper**:

```python
from miz_modification.triggers.add import add_trigger_zone_file

add_trigger_zone_file(
    "input.miz",
    "output.miz",
    "Target Area",
    150000,
    55000,
    5000
)
```

**Error Conditions**:

- `ValueError`: Could not find zones section in mission

---

## Trigger Rule Operations

### `list_trigger_rules()`

List all trigger rules (human-readable trigger definitions).

**Module**: `miz_modification.triggers.list`

**Signature**:
```python
def list_trigger_rules(mission_content: str) -> List[Dict[str, Any]]
```

**Returns**:

```python
[
    {
        "index": int,            # Trigger index
        "comment": str,          # Trigger name/description
        "predicate": str,        # "triggerOnce", "triggerContinuous", etc.
        "eventlist": str,        # Event list filter
        "rules": [               # List of conditions
            {
                "predicate": str,    # Condition type
                "seconds": int,      # Time parameter (if applicable)
                ...                  # Other condition parameters
            },
            ...
        ],
        "actions": [             # List of actions
            {
                "predicate": str,    # Action type
                "file": str,         # Script file (if DO SCRIPT)
                ...                  # Other action parameters
            },
            ...
        ]
    },
    ...
]
```

**Usage Example**:

```python
from miz_modification.triggers.list import list_trigger_rules

triggers = list_trigger_rules(content)
print(f"Found {len(triggers)} triggers")

for trigger in triggers:
    print(f"\n{trigger['comment']}:")
    print(f"  Type: {trigger['predicate']}")
    print(f"  Conditions: {len(trigger['rules'])}")
    print(f"  Actions: {len(trigger['actions'])}")

    # Show condition types
    for rule in trigger['rules']:
        print(f"    - {rule['predicate']}")

    # Show action types
    for action in trigger['actions']:
        print(f"    → {action['predicate']}")
```

**File Wrapper**:

```python
from miz_modification.triggers.list import list_trigger_rules_file

triggers = list_trigger_rules_file("mission.miz")
for t in triggers:
    print(f"{t['comment']}: {len(t['actions'])} actions")
```

---

### `find_trigger_by_comment()`

Find a trigger rule by its comment/name.

**Module**: `miz_modification.triggers.list`

**Signature**:
```python
def find_trigger_by_comment(mission_content: str, comment: str) -> Optional[Dict[str, Any]]
```

**Returns**:

Trigger rule dictionary if found, `None` otherwise.

**Usage Example**:

```python
from miz_modification.triggers.list import find_trigger_by_comment

trigger = find_trigger_by_comment(content, "Start Mission")

if trigger:
    print(f"Trigger: {trigger['comment']}")
    print(f"Type: {trigger['predicate']}")
    print(f"Actions: {len(trigger['actions'])}")
```

---

### `list_compiled_triggers()`

List compiled trigger data from the trig section (Lua code).

**Module**: `miz_modification.triggers.list`

**Signature**:
```python
def list_compiled_triggers(mission_content: str) -> Dict[str, Any]
```

**Returns**:

```python
{
    "conditions": [str],     # List of condition code strings
    "actions": [str],        # List of action code strings
    "func": [str],           # List of execution function strings
    "flag": [bool],          # List of trigger enabled flags
    "count": int             # Number of triggers
}
```

**Usage Example**:

```python
from miz_modification.triggers.list import list_compiled_triggers

trig = list_compiled_triggers(content)
print(f"Total triggers: {trig['count']}")

for i, cond in enumerate(trig['conditions']):
    print(f"\nTrigger {i+1}:")
    print(f"  Condition: {cond[:50]}...")  # First 50 chars
    print(f"  Action: {trig['actions'][i][:50]}...")
    print(f"  Enabled: {trig['flag'][i]}")
```

---

### `get_trigger_summary()`

Get a summary of all triggers and zones in the mission.

**Module**: `miz_modification.triggers.list`

**Signature**:
```python
def get_trigger_summary(mission_content: str) -> Dict[str, Any]
```

**Returns**:

```python
{
    "zone_count": int,           # Number of trigger zones
    "trigger_count": int,        # Number of trigger rules
    "zones": [str],              # List of zone names
    "triggers": [str],           # List of trigger comments
    "predicates": {              # Count by predicate type
        "triggerOnce": int,
        "triggerContinuous": int,
        ...
    }
}
```

**Usage Example**:

```python
from miz_modification.triggers.list import get_trigger_summary

summary = get_trigger_summary(content)

print("Mission Trigger Summary")
print("=" * 40)
print(f"Trigger Zones: {summary['zone_count']}")
print(f"Trigger Rules: {summary['trigger_count']}")

print("\nZones:")
for zone_name in summary['zones']:
    print(f"  - {zone_name}")

print("\nTriggers:")
for trig_name in summary['triggers']:
    print(f"  - {trig_name}")

print("\nTrigger Types:")
for pred, count in summary['predicates'].items():
    print(f"  {pred}: {count}")
```

---

## DO SCRIPT Trigger Operations

### `add_do_script_trigger()`

Add a DO SCRIPT trigger that runs Lua code after a time delay.

**This is the most common trigger type for injecting custom Lua scripts into missions.**

**Module**: `miz_modification.triggers.add`

**Signature**:
```python
def add_do_script_trigger(mission_content: str, comment: str, script: str,
                          time_after: int = 1, trigger_type: str = "triggerOnce") -> str
```

**Parameters**:

| Name | Type | Required | Description |
|------|------|----------|-------------|
| `mission_content` | `str` | Yes | Raw mission file content |
| `comment` | `str` | Yes | Trigger name (shown in Mission Editor) |
| `script` | `str` | Yes | Lua script code to execute |
| `time_after` | `int` | No | Seconds after mission start (default: 1) |
| `trigger_type` | `str` | No | "triggerOnce" or "triggerContinuous" (default: "triggerOnce") |

**Returns**:

Modified mission content as string.

**Usage Example**:

```python
from miz_modification.triggers.add import add_do_script_trigger
from miz_modification.parsing.miz_parser import MizParser

parser = MizParser("input.miz")
parser.extract()
content = parser.get_mission_content()

# Simple message trigger
script = '''
trigger.action.outText("Mission started!", 10)
'''
content = add_do_script_trigger(
    content,
    "Welcome Message",
    script,
    time_after=5
)

# Load external Lua module
init_script = '''
-- Load custom mission script
dofile(lfs.writedir() .. 'Scripts/MyMission.lua')
MyMission.init()
'''
content = add_do_script_trigger(
    content,
    "Initialize Mission",
    init_script,
    time_after=1
)

parser.write_mission_content(content)
parser.repackage("output.miz")
parser.cleanup()
```

**File Wrapper**:

```python
from miz_modification.triggers.add import add_do_script_trigger_file

script = '''
trigger.action.outText("Hello World!", 10)
'''

add_do_script_trigger_file(
    "input.miz",
    "output.miz",
    "Say Hello",
    script,
    time_after=3
)
```

---

## Advanced Usage

### Pattern 1: Multi-Zone Setup for Objectives

```python
from miz_modification.triggers.add import add_trigger_zone

# Define objective zones
objectives = [
    {"name": "Objective Alpha", "x": 150000, "y": 55000, "radius": 5000},
    {"name": "Objective Bravo", "x": 145000, "y": 60000, "radius": 4000},
    {"name": "Objective Charlie", "x": 155000, "y": 50000, "radius": 3000},
]

# Add all zones
for obj in objectives:
    content = add_trigger_zone(
        content,
        obj["name"],
        obj["x"],
        obj["y"],
        obj["radius"]
    )
```

### Pattern 2: Spawn Zones (Hidden)

```python
# Create hidden spawn zones
spawn_zones = [
    {"name": "Blue CAP Spawn", "x": 100000, "y": 40000, "radius": 1000},
    {"name": "Red Fighter Spawn", "x": 200000, "y": 80000, "radius": 1000},
]

for zone in spawn_zones:
    content = add_trigger_zone(
        content,
        zone["name"],
        zone["x"],
        zone["y"],
        zone["radius"],
        hidden=True  # Not shown on F10 map
    )
```

### Pattern 3: Complex Lua Script Injection

```python
from miz_modification.triggers.add import add_do_script_trigger

# Complex mission script with randomization
mission_script = '''
-- Mission Configuration
MissionConfig = {
    difficulty = "hard",
    randomSpawns = true,
    respawnTime = 300,
}

-- Random spawn function
function spawnRandomEnemies()
    local zones = {"Zone1", "Zone2", "Zone3"}
    local selectedZone = zones[math.random(#zones)]

    trigger.action.outText("Enemy spawned in " .. selectedZone, 10)

    -- Spawn logic here
    -- coalition.addGroup(...)
end

-- Schedule first spawn
timer.scheduleFunction(spawnRandomEnemies, nil, timer.getTime() + 60)

-- Debug message
env.info("Mission script initialized")
'''

content = add_do_script_trigger(
    content,
    "Mission Init",
    mission_script,
    time_after=1
)
```

### Pattern 4: Loading External Lua Files

```python
# Trigger to load external Lua script file
loader_script = '''
-- Load mission library
local scriptPath = lfs.writedir() .. 'Scripts/Missions/DynamicMission.lua'

local f = io.open(scriptPath, "r")
if f then
    f:close()
    dofile(scriptPath)
    DynamicMission.start()
    trigger.action.outText("Mission loaded successfully", 5)
else
    trigger.action.outText("ERROR: Mission script not found", 30)
end
'''

content = add_do_script_trigger(
    content,
    "Load Mission Script",
    loader_script,
    time_after=1
)
```

### Pattern 5: Multiple Timed Events

```python
# Multiple triggers for timed events
events = [
    {
        "comment": "Mission Start",
        "script": 'trigger.action.outText("Mission begins!", 10)',
        "time": 1
    },
    {
        "comment": "First Wave",
        "script": 'trigger.action.outText("First wave incoming!", 15)',
        "time": 300  # 5 minutes
    },
    {
        "comment": "Second Wave",
        "script": 'trigger.action.outText("Second wave detected!", 15)',
        "time": 600  # 10 minutes
    },
    {
        "comment": "Mission End Warning",
        "script": 'trigger.action.outText("Mission ends in 5 minutes", 20)',
        "time": 1500  # 25 minutes
    },
]

for event in events:
    content = add_do_script_trigger(
        content,
        event["comment"],
        event["script"],
        time_after=event["time"]
    )
```

### Pattern 6: Zone-Based Trigger Setup

```python
# Create zone and trigger that monitors it
zone_name = "Target Area"

# Add the zone
content = add_trigger_zone(
    content,
    zone_name,
    150000,
    55000,
    5000
)

# Add trigger to monitor zone
monitor_script = f'''
-- Monitor zone: {zone_name}
local zoneName = "{zone_name}"

local function checkZone()
    local zone = trigger.misc.getZone(zoneName)

    if zone then
        -- Check for units in zone
        local units = mist.getUnitsInZones({{zoneName}}, "blue", "plane")

        if #units > 0 then
            trigger.action.outText("Blue aircraft in target area!", 10)
        end
    end

    -- Repeat check every 5 seconds
    return timer.getTime() + 5
end

-- Start monitoring
timer.scheduleFunction(checkZone, nil, timer.getTime() + 1)
'''

content = add_do_script_trigger(
    content,
    f"Monitor {zone_name}",
    monitor_script,
    time_after=2,
    trigger_type="triggerOnce"
)
```

---

## Best Practices

### 1. Test Scripts Before Adding

```python
# Test Lua syntax in DCS Mission Editor first
# Then add to mission programmatically

# Simple test script
test_script = '''
trigger.action.outText("Test message", 5)
env.info("Script executed successfully")
'''

# If this works in ME, add it programmatically
content = add_do_script_trigger(content, "Test", test_script)
```

### 2. Use env.info() for Debugging

```python
debug_script = '''
env.info("Mission script started")

-- Your mission code here
local result = someFunction()

env.info("Result: " .. tostring(result))
'''

# Check DCS.log for debug messages:
# C:\\Users\\<username>\\Saved Games\\DCS\\Logs\\dcs.log
```

### 3. Handle Errors Gracefully

```python
safe_script = '''
local success, error = pcall(function()
    -- Your mission code here
    dangerousFunction()
end)

if not success then
    env.error("Mission script error: " .. tostring(error))
    trigger.action.outText("Mission script error!", 30)
end
'''

content = add_do_script_trigger(content, "Safe Script", safe_script)
```

### 4. Use Descriptive Trigger Names

```python
# Good - Clear purpose
content = add_do_script_trigger(content, "Initialize Random Spawns", script, 1)
content = add_do_script_trigger(content, "First Enemy Wave Spawner", script, 300)

# Bad - Unclear
content = add_do_script_trigger(content, "Trigger 1", script, 1)
content = add_do_script_trigger(content, "Script", script, 300)
```

### 5. Organize Zones by Purpose

```python
# Group zones by purpose using naming convention
zones_config = {
    "objectives": [
        {"name": "OBJ_Alpha", "x": 150000, "y": 55000, "radius": 5000},
        {"name": "OBJ_Bravo", "x": 145000, "y": 60000, "radius": 4000},
    ],
    "spawns": [
        {"name": "SPAWN_Blue_CAP", "x": 100000, "y": 40000, "radius": 1000, "hidden": True},
        {"name": "SPAWN_Red_SAM", "x": 200000, "y": 80000, "radius": 2000, "hidden": True},
    ],
    "detection": [
        {"name": "DETECT_SAM_Range", "x": 180000, "y": 70000, "radius": 25000, "hidden": True},
    ]
}

for category, zone_list in zones_config.items():
    for zone in zone_list:
        content = add_trigger_zone(
            content,
            zone["name"],
            zone["x"],
            zone["y"],
            zone["radius"],
            hidden=zone.get("hidden", False)
        )
```

---

## Common Trigger Use Cases

### 1. Mission Briefing at Start

```python
briefing = '''
local briefing = [[
MISSION: Strike Package Alpha

OBJECTIVE: Destroy enemy SAM sites in AO Charlie

THREATS: SA-10, SA-15, AAA

RESTRICTIONS: Do not engage civilian targets
]]

trigger.action.outText(briefing, 60)
'''

content = add_do_script_trigger(content, "Mission Briefing", briefing, time_after=3)
```

### 2. Time-Based Weather Changes

```python
weather_script = '''
-- Change weather after 30 minutes
local function changeWeather()
    trigger.action.setWeather({
        clouds = {
            density = 8,
            thickness = 2000,
            base = 2000
        }
    })
    trigger.action.outText("Weather deteriorating", 15)
end

timer.scheduleFunction(changeWeather, nil, timer.getTime() + 1800)
'''

content = add_do_script_trigger(content, "Weather Change", weather_script, time_after=1)
```

### 3. Victory/Defeat Conditions

```python
victory_check = '''
local function checkVictory()
    -- Check if all objectives complete
    local obj1 = trigger.misc.getUserFlag("OBJ1_COMPLETE")
    local obj2 = trigger.misc.getUserFlag("OBJ2_COMPLETE")
    local obj3 = trigger.misc.getUserFlag("OBJ3_COMPLETE")

    if obj1 == 1 and obj2 == 1 and obj3 == 1 then
        trigger.action.outText("MISSION ACCOMPLISHED!", 30)
        trigger.action.setUserFlag("MISSION_COMPLETE", 1)
    else
        -- Check again in 10 seconds
        return timer.getTime() + 10
    end
end

timer.scheduleFunction(checkVictory, nil, timer.getTime() + 5)
'''

content = add_do_script_trigger(content, "Victory Check", victory_check, time_after=1)
```

### 4. Dynamic Difficulty Adjustment

```python
difficulty_script = '''
-- Adjust difficulty based on player performance
local playerKills = 0

local function adjustDifficulty()
    playerKills = trigger.misc.getUserFlag("PLAYER_KILLS") or 0

    if playerKills > 10 then
        trigger.action.outText("Enemy reinforcements inbound!", 15)
        -- Spawn more enemies
        -- spawnReinforcements()
    elseif playerKills < 3 then
        trigger.action.outText("Enemy withdrawing", 10)
        -- Reduce enemy activity
    end

    return timer.getTime() + 120  -- Check every 2 minutes
end

timer.scheduleFunction(adjustDifficulty, nil, timer.getTime() + 300)
'''

content = add_do_script_trigger(content, "Difficulty Adjustment", difficulty_script, time_after=1)
```

---

## See Also

- [Mission Analysis](mission-analysis.md) - Inspect mission triggers
- [DCS Scripting Engine](https://wiki.hoggitworld.com/view/Simulator_Scripting_Engine) - DCS Lua API reference
- [MIST Documentation](https://github.com/mrSkortch/MissionScriptingTools) - Mission Scripting Tools library
