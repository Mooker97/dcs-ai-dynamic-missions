# Lua Scripting Library Architecture
## DCS Dynamic Mission System

**Version:** 1.0
**Date:** 2024-12-30
**Status:** Architecture Design Complete

---

## Table of Contents
1. [Overview](#overview)
2. [Goals and Requirements](#goals-and-requirements)
3. [System Architecture](#system-architecture)
4. [Module Specifications](#module-specifications)
5. [API Reference](#api-reference)
6. [Configuration System](#configuration-system)
7. [Mission Type Presets](#mission-type-presets)
8. [Integration Guide](#integration-guide)
9. [Performance Optimization](#performance-optimization)
10. [Testing Strategy](#testing-strategy)
11. [Implementation Roadmap](#implementation-roadmap)

---

## Overview

The Lua Scripting Library transforms static DCS missions into dynamic, replayable experiences by adding runtime randomization, event-driven behaviors, and adaptive difficulty. The library is injected into .miz mission files by the MCP server and executes during mission runtime in the DCS scripting environment.

### Core Concept

```
Static Mission (.miz)
    ↓
+ Lua Library (injected by MCP)
    ↓
Dynamic Mission (different every time)
```

**Key Features:**
- **Random Spawning**: Units spawn at varied locations and times
- **Event-Driven**: Reacts to player actions and mission events
- **Adaptive Difficulty**: Adjusts challenge based on player performance
- **Reinforcements**: Dynamic enemy/friendly reinforcements
- **Weather Variation**: Randomized weather conditions
- **Mission-Type Specific**: Tailored behaviors for SEAD, CAP, Strike, etc.

---

## Goals and Requirements

### Primary Goals
1. **Replayability**: No two mission playthroughs should be identical
2. **Performance**: Maintain 30+ FPS with dynamic content
3. **Ease of Use**: MCP server handles all complexity
4. **Flexibility**: Support all common mission types
5. **Reliability**: Robust error handling, graceful degradation

### Technical Requirements
- **DCS Compatibility**: Works with current DCS World version
- **Self-Contained**: No external dependencies, runs in DCS sandbox
- **Single-File Deployment**: All modules compiled into one Lua file
- **Config-Driven**: Mission-specific behavior via embedded config
- **Performant**: Efficient spawning and event handling

### User Requirements
- **Invisible Complexity**: Users don't write Lua, they describe missions
- **Natural Language**: "Add random enemy spawns" → library handles it
- **Consistent Behavior**: Same difficulty setting produces similar challenge levels
- **Debuggable**: Clear logging for troubleshooting

---

## System Architecture

### High-Level Architecture

```
┌─────────────────────────────────────────────────────────┐
│                  DCS MISSION RUNTIME                     │
│                                                          │
│  ┌────────────────────────────────────────────────────┐ │
│  │         DCS Event System (Built-in)                │ │
│  │  • S_EVENT_BIRTH, S_EVENT_DEAD, etc.              │ │
│  └───────────────────┬────────────────────────────────┘ │
│                      │                                   │
│                      ↓                                   │
│  ┌────────────────────────────────────────────────────┐ │
│  │        Dynamic Mission Library (Injected)          │ │
│  │                                                    │ │
│  │  ┌──────────────┐  ┌──────────────┐              │ │
│  │  │ Core Module  │  │ Event Handler│              │ │
│  │  │  • Init      │←→│  • onEvent() │              │ │
│  │  │  • State     │  │  • Dispatch  │              │ │
│  │  └──────┬───────┘  └──────┬───────┘              │ │
│  │         │                  │                       │ │
│  │         ↓                  ↓                       │ │
│  │  ┌──────────────────────────────────┐            │ │
│  │  │        Spawner Modules           │            │ │
│  │  │  • Air   • Ground   • Naval      │            │ │
│  │  └──────────────┬───────────────────┘            │ │
│  │                 │                                 │ │
│  │                 ↓                                 │ │
│  │  ┌──────────────────────────────────┐            │ │
│  │  │      Randomizer Modules          │            │ │
│  │  │  • Location • Loadout • Timing   │            │ │
│  │  └──────────────────────────────────┘            │ │
│  │                                                   │ │
│  │  ┌──────────────────────────────────┐            │ │
│  │  │      Behavior Modules            │            │ │
│  │  │  • Adaptive Difficulty           │            │ │
│  │  │  • Reinforcements                │            │ │
│  │  └──────────────────────────────────┘            │ │
│  │                                                   │ │
│  │  ┌──────────────────────────────────┐            │ │
│  │  │      Mission Config (Embedded)    │            │ │
│  │  │  • Spawn templates               │            │
│  │  │  • Event rules                   │            │ │
│  │  │  • Difficulty params             │            │ │
│  │  └──────────────────────────────────┘            │ │
│  └────────────────────────────────────────────────────┘ │
│                                                          │
└─────────────────────────────────────────────────────────┘
```

### Data Flow

**Mission Start:**
```
1. DCS loads .miz file
2. Trigger executes DO_SCRIPT at time = 1 second
3. Library code runs: DynamicMission.init(MissionConfig)
4. Event handlers registered with DCS
5. Initial spawns scheduled via timer
6. State initialized
```

**Runtime Event:**
```
1. DCS event occurs (e.g., S_EVENT_DEAD)
2. DCS calls DynamicMission.onEvent(event)
3. Event handler dispatches to appropriate module
4. Module evaluates config rules
5. Actions executed (spawn, message, timer)
6. State updated
```

**Scheduled Spawn:**
```
1. Timer fires (e.g., 300 seconds into mission)
2. Spawner module called with template
3. Randomizer generates location/loadout
4. DCS API creates group in world
5. State tracks spawned group
6. Next spawn scheduled
```

---

## Module Specifications

### 1. Core Module (`core/init.lua`)

**Purpose:** System initialization, state management, coordination

**Responsibilities:**
- Initialize library on mission start
- Maintain runtime state
- Coordinate between modules
- Provide utility functions

**State Structure:**
```lua
DynamicMission.state = {
    initialized = false,
    mission_start_time = 0,
    spawned_groups = {},  -- Track all spawned groups
    player_stats = {
        kills = 0,
        deaths = 0,
        current_aircraft = nil
    },
    spawn_counters = {},  -- Track spawns per template
    difficulty_modifier = 1.0,  -- Adaptive difficulty multiplier
    active_timers = {}  -- Scheduled functions
}
```

**Key Functions:**
```lua
-- Initialize system
DynamicMission.init(config)

-- Get current mission time
DynamicMission.getTime()

-- Log message to DCS.log
DynamicMission.log(message, level)

-- Generate random number
DynamicMission.random(min, max)

-- Get distance between two points
DynamicMission.getDistance(point1, point2)
```

---

### 2. Event Handler (`core/event_handler.lua`)

**Purpose:** DCS event system integration and routing

**Key Events Handled:**
- `S_EVENT_BIRTH`: Unit spawned (track player)
- `S_EVENT_TAKEOFF`: Aircraft takeoff (trigger spawns)
- `S_EVENT_DEAD`: Unit destroyed (reinforcements, adaptive)
- `S_EVENT_MISSION_START`: Initialize on mission start
- `S_EVENT_PLAYER_ENTER_UNIT`: Track player aircraft changes
- `S_EVENT_CRASH`: Handle crashes
- `S_EVENT_EJECTION`: Trigger rescue missions

**Event Handler Structure:**
```lua
DynamicMission.EventHandler = {
    onEvent = function(self, event)
        if event.id == world.event.S_EVENT_DEAD then
            self:handleDeath(event)
        elseif event.id == world.event.S_EVENT_TAKEOFF then
            self:handleTakeoff(event)
        -- ... other events
        end
    end,

    handleDeath = function(self, event)
        -- Check if player died
        -- Check if enemy died (reinforcements?)
        -- Update stats
        -- Trigger adaptive difficulty
    end
}

world.addEventHandler(DynamicMission.EventHandler)
```

---

### 3. Air Spawner (`spawners/air_spawner.lua`)

**Purpose:** Spawn aircraft groups with randomization

**Spawn Template Structure:**
```lua
{
    name = "MiG-29-CAP-1",
    unit_type = "MiG-29S",
    coalition = "red",
    country = 0,  -- Russia
    category = "airplane",

    group = {
        count = 2,  -- 2-ship
        skill = "Random",  -- or "Average", "Good", "High", "Excellent"
        skill_variance = true  -- Each aircraft different skill
    },

    loadout = {
        type = "CAP",  -- Use preset loadout
        -- or specific: weapons = {"R-27ER", "R-73"}
    },

    spawn = {
        location = {
            type = "random_in_zone",
            zone_name = "EnemySpawn1",
            altitude_min = 5000,
            altitude_max = 8000
        },
        timing = {
            delay = 300,  -- 5 minutes
            random_offset = 120  -- +/- 2 minutes
        }
    },

    behavior = {
        task = "CAP",
        waypoints = "generate_patrol",  -- Auto-generate waypoints
        racetrack_center = {x = -50000, y = 30000},
        racetrack_radius = 20000
    }
}
```

**Key Functions:**
```lua
AirSpawner.spawn(template)
AirSpawner.generateWaypoints(task_type, center, radius)
AirSpawner.randomizeLoadout(aircraft_type, role)
```

---

### 4. Ground Spawner (`spawners/ground_spawner.lua`)

**Purpose:** Spawn ground units (vehicles, SAMs, infantry)

**Features:**
- Road spawning (find nearest road, spawn on it)
- SAM site templates (complete batteries with search/track radars)
- Formation spawning (units in realistic formations)
- Terrain avoidance (don't spawn in water, steep slopes)

**SAM Site Template:**
```lua
{
    name = "SA-6-Battery-1",
    site_type = "SA-6",  -- Predefined battery composition
    coalition = "red",

    spawn = {
        location = {
            type = "random_near_point",
            center = {x = -30000, y = 40000},
            radius = 5000,
            avoid_water = true,
            max_slope = 15  -- degrees
        }
    },

    composition = {
        search_radar = "Dog Ear radar",
        track_radar = "Straight Flush",
        launchers = 4,  -- 4x 2K12 Kub launchers
        spacing = 100  -- meters between units
    }
}
```

---

### 5. Location Randomizer (`randomizers/location.lua`)

**Purpose:** Generate valid spawn positions

**Methods:**
- `randomInZone(zone_name, altitude)`: Random point in trigger zone
- `randomNearPoint(center, radius, altitude)`: Random around point
- `randomOnRoad(center, search_radius)`: Find road and spawn on it
- `findSafeSpawn(center, radius, coalition)`: Avoid enemies

**Constraints:**
- Terrain checking (not in water, not on steep slope)
- Minimum distance from enemies
- Altitude limits (min/max AGL or MSL)
- Zone boundaries

**Implementation:**
```lua
LocationRandomizer.randomInZone = function(zone_name, altitude_min, altitude_max)
    local zone = trigger.misc.getZone(zone_name)
    if not zone then return nil end

    local angle = math.random() * 2 * math.pi
    local radius = math.sqrt(math.random()) * zone.radius

    local x = zone.x + radius * math.cos(angle)
    local y = zone.y + radius * math.sin(angle)

    -- Get terrain height
    local terrain_height = land.getHeight({x = x, y = y})
    local altitude = math.random(altitude_min, altitude_max)

    return {x = x, y = y, alt = terrain_height + altitude}
end
```

---

### 6. Timing Randomizer (`randomizers/timing.lua`)

**Purpose:** Randomize spawn timing and delays

**Features:**
- Base delay + random offset
- Exponential backoff (increasing delays)
- Wave timing (multiple groups with spacing)
- Event-triggered delays

```lua
TimingRandomizer.getSpawnDelay = function(base_delay, random_offset)
    local offset = (math.random() - 0.5) * 2 * random_offset
    return base_delay + offset
end

TimingRandomizer.scheduleWave = function(templates, base_delay, spacing)
    for i, template in ipairs(templates) do
        local delay = base_delay + (i - 1) * spacing
        timer.scheduleFunction(function()
            AirSpawner.spawn(template)
        end, nil, timer.getTime() + delay)
    end
end
```

---

### 7. Adaptive Difficulty (`behaviors/adaptive_difficulty.lua`)

**Purpose:** Adjust mission difficulty based on player performance

**Tracking Metrics:**
- Player kills
- Player deaths
- Time alive
- Mission objectives completed
- Damage taken

**Adjustments:**
- Spawn frequency (more kills → more enemies)
- Enemy skill level (better player → better AI)
- Enemy count per group
- Reinforcement timing

**Algorithm:**
```lua
AdaptiveDifficulty.update = function()
    local kills = DynamicMission.state.player_stats.kills
    local deaths = DynamicMission.state.player_stats.deaths

    if kills > 5 and deaths == 0 then
        -- Player doing well, increase difficulty
        DynamicMission.state.difficulty_modifier = 1.3
        DynamicMission.log("Adaptive difficulty increased to 1.3")
    elseif deaths > 2 then
        -- Player struggling, decrease difficulty
        DynamicMission.state.difficulty_modifier = 0.7
        DynamicMission.log("Adaptive difficulty decreased to 0.7")
    end
end
```

---

### 8. Reinforcements (`behaviors/reinforcements.lua`)

**Purpose:** Spawn reinforcements based on mission events

**Trigger Types:**
- Time-based (after X minutes)
- Loss-based (when unit/group destroyed)
- Zone-based (player enters area)
- Objective-based (target destroyed)

**Reinforcement Rules:**
```lua
{
    trigger = "sam_destroyed",
    delay = 600,  -- 10 minutes after SAM destroyed
    probability = 0.7,  -- 70% chance
    spawn_template = "SA-11-Backup",
    max_reinforcements = 2,  -- Only reinforce twice
    location = "near_destroyed_unit"  -- or "fixed_zone"
}
```

---

## API Reference

### Core API

#### `DynamicMission.init(config)`
Initialize library with mission configuration.

**Parameters:**
- `config` (table): Mission configuration

**Returns:** None

**Example:**
```lua
DynamicMission.init(MissionConfig)
```

---

#### `DynamicMission.log(message, level)`
Log message to DCS.log file.

**Parameters:**
- `message` (string): Message to log
- `level` (string): "INFO", "WARNING", "ERROR" (optional, default "INFO")

**Example:**
```lua
DynamicMission.log("Spawning MiG-29 group", "INFO")
```

---

#### `DynamicMission.getTime()`
Get current mission time in seconds.

**Returns:** (number) Seconds since mission start

---

#### `DynamicMission.random(min, max)`
Generate random number in range.

**Parameters:**
- `min` (number): Minimum value
- `max` (number): Maximum value

**Returns:** (number) Random value between min and max

---

### Spawner API

#### `AirSpawner.spawn(template)`
Spawn aircraft group from template.

**Parameters:**
- `template` (table): Spawn template (see structure above)

**Returns:** (Group|nil) Spawned group or nil if failed

**Example:**
```lua
local mig29_template = {
    name = "MiG-29-1",
    unit_type = "MiG-29S",
    coalition = "red",
    group = {count = 2, skill = "Good"},
    spawn = {
        location = {
            type = "random_in_zone",
            zone_name = "EnemySpawn",
            altitude_min = 6000,
            altitude_max = 8000
        }
    },
    behavior = {task = "CAP"}
}

AirSpawner.spawn(mig29_template)
```

---

#### `GroundSpawner.spawnSAM(template)`
Spawn complete SAM site.

**Parameters:**
- `template` (table): SAM site template

**Returns:** (table) Array of spawned groups

---

### Randomizer API

#### `LocationRandomizer.randomInZone(zone_name, alt_min, alt_max)`
Generate random position in trigger zone.

**Parameters:**
- `zone_name` (string): Name of trigger zone
- `alt_min` (number): Minimum altitude AGL (meters)
- `alt_max` (number): Maximum altitude AGL (meters)

**Returns:** (table|nil) {x, y, alt} or nil if zone not found

---

#### `LoadoutRandomizer.getLoadout(aircraft_type, role)`
Get random loadout for aircraft and role.

**Parameters:**
- `aircraft_type` (string): Aircraft type (e.g., "F-16C_50")
- `role` (string): Mission role ("CAP", "SEAD", "STRIKE", "CAS")

**Returns:** (table) Loadout configuration

---

## Configuration System

### Configuration Structure

```lua
MissionConfig = {
    -- Mission metadata
    mission_name = "SEAD Caucasus Night",
    mission_type = "SEAD",
    difficulty = "medium",  -- "easy", "medium", "hard"

    -- Global settings
    settings = {
        max_concurrent_spawns = 8,
        despawn_distance = 100000,  -- meters (100km)
        logging_level = "INFO"
    },

    -- Spawn definitions
    spawns = {
        {
            id = "mig29_cap_1",
            template = {
                -- (see spawn template structure)
            },
            schedule = {
                initial_delay = 300,
                repeat_interval = 600,
                max_spawns = 3
            },
            conditions = {
                player_takeoff = true,  -- Only spawn after player airborne
                time_of_day = "any"  -- or "day", "night", "dawn", "dusk"
            }
        }
        -- ... more spawns
    },

    -- Event-driven behaviors
    events = {
        {
            trigger = "sam_destroyed",
            actions = {
                {
                    type = "spawn_reinforcement",
                    template_id = "sa11_backup",
                    delay = 600,
                    probability = 0.7
                },
                {
                    type = "message",
                    text = "Enemy reinforcements en route",
                    duration = 10
                }
            }
        }
        -- ... more events
    },

    -- Adaptive difficulty settings
    adaptive = {
        enabled = true,
        adjustment_threshold = 5,  -- kills before adjustment
        difficulty_step = 0.2,  -- multiplier change
        min_difficulty = 0.5,
        max_difficulty = 2.0
    },

    -- Randomization settings
    randomization = {
        locations = true,
        loadouts = true,
        timing = true,
        weather = false,  -- weather changes require mission-level edits
        seed = nil  -- nil = truly random, number = reproducible
    }
}
```

### Configuration Generation

The MCP server generates configuration from natural language:

**User Input:**
```
"Create a SEAD mission on Caucasus, medium difficulty, with random enemy spawns"
```

**Generated Config:**
```lua
MissionConfig = {
    mission_name = "SEAD Mission - Caucasus",
    mission_type = "SEAD",
    difficulty = "medium",

    spawns = {
        {
            id = "sam_sites",
            template = {
                name = "SA-6-Site",
                -- ... SAM template
            },
            schedule = {initial_delay = 0}  -- Start active
        },
        {
            id = "enemy_cap",
            template = {
                name = "MiG-29-CAP",
                -- ... fighter template
            },
            schedule = {
                initial_delay = 600,  -- 10 min after mission start
                repeat_interval = 900,  -- Every 15 min
                max_spawns = 2
            }
        }
    },

    events = {
        {
            trigger = "sam_destroyed",
            actions = {
                {type = "spawn_reinforcement", template_id = "sa11_backup"}
            }
        }
    },

    adaptive = {enabled = true}
}
```

---

## Mission Type Presets

### SEAD (Suppression of Enemy Air Defenses)

**Characteristics:**
- Primary targets: SAM sites
- Threats: Enemy fighters, AAA
- Dynamic elements: SAM relocation, reinforcements

**Default Config:**
```lua
SEAD_Preset = {
    primary_targets = {"SA-6", "SA-2", "SA-11"},
    target_count = {min = 2, max = 4},

    spawns = {
        -- Enemy CAP spawns when player approaches SAMs
        {
            id = "escort_fighters",
            trigger = "player_distance",
            distance_threshold = 50000,  -- 50km from SAM
            template = "MiG-29-CAP"
        }
    },

    events = {
        -- Replace destroyed SAM after delay
        {
            trigger = "sam_destroyed",
            probability = 0.6,
            spawn_replacement = true,
            delay = 900
        }
    }
}
```

---

### CAP (Combat Air Patrol)

**Characteristics:**
- Primary targets: Enemy aircraft
- Dynamic elements: Random enemy waves, varying tactics

**Default Config:**
```lua
CAP_Preset = {
    enemy_waves = {
        count = 3,
        spacing = 600,  -- 10 minutes between waves
        size_variance = {min = 2, max = 4}  -- 2-4 aircraft per wave
    },

    spawns = {
        {
            id = "enemy_wave_1",
            template = "MiG-29-Intercept",
            schedule = {
                initial_delay = 300,
                spawn_pattern = "random"  -- Not always same location
            }
        }
    },

    tactics = {
        approach_vectors = "random",  -- North, South, East, West
        altitude_variation = {min = 3000, max = 9000},
        combat_style = "mixed"  -- BVR and dogfight
    }
}
```

---

### Strike Mission

**Characteristics:**
- Primary targets: Ground structures/vehicles
- Threats: AAA, MANPADS, SAMs, fighters
- Dynamic elements: Target damage states, defenses

**Default Config:**
```lua
Strike_Preset = {
    targets = {
        {
            type = "building",
            count = 5,
            damage_states = "random"  -- Some pre-damaged
        }
    },

    defenses = {
        -- AAA spawns near targets
        {
            type = "AAA",
            per_target = 2,
            radius = 2000
        },
        -- SAMs in area
        {
            type = "SAM",
            count = 2,
            coverage = "targets"
        }
    },

    events = {
        -- Fighters spawn on egress
        {
            trigger = "target_destroyed_percent",
            threshold = 50,  -- After 50% targets destroyed
            spawn = "MiG-29-Intercept",
            location = "player_heading"  -- Spawn ahead of player
        }
    }
}
```

---

## Integration Guide

### MCP Server Integration

**Step 1: Generate Configuration**
```python
# MCP server side (Python)
def generate_lua_config(mission_params):
    """Generate Lua config table from mission parameters."""

    config = {
        'mission_name': mission_params['name'],
        'mission_type': mission_params['type'],
        'difficulty': mission_params['difficulty'],
        'spawns': [],
        'events': []
    }

    # Add spawns based on mission type
    if mission_params['type'] == 'SEAD':
        config['spawns'].extend(generate_sead_spawns(mission_params))
    # ... other mission types

    # Convert to Lua table string
    lua_config = python_dict_to_lua_table(config)
    return f"MissionConfig = {lua_config}\n"
```

---

**Step 2: Load Library Modules**
```python
def load_library_code():
    """Load all Lua modules and combine."""
    library_path = Path("lua-library/")

    modules = [
        "core/init.lua",
        "core/event_handler.lua",
        "core/utils.lua",
        "spawners/air_spawner.lua",
        "spawners/ground_spawner.lua",
        "randomizers/location.lua",
        "randomizers/timing.lua",
        "randomizers/loadout.lua",
        "behaviors/adaptive_difficulty.lua",
        "behaviors/reinforcements.lua"
    ]

    combined_code = ""
    for module in modules:
        with open(library_path / module, 'r') as f:
            combined_code += f"-- {module}\n"
            combined_code += f.read()
            combined_code += "\n\n"

    return combined_code
```

---

**Step 3: Inject into Mission**
```python
def inject_dynamic_library(miz_path, output_path, mission_params):
    """Inject library into .miz file."""

    # 1. Generate config
    config_lua = generate_lua_config(mission_params)

    # 2. Load library
    library_code = load_library_code()

    # 3. Combine with init call
    full_script = f"""
-- Dynamic Mission Library
-- Generated: {datetime.now()}

{config_lua}

{library_code}

-- Initialize on mission start
DynamicMission.init(MissionConfig)
"""

    # 4. Inject into mission file
    parser = MizParser(miz_path)
    parser.extract()
    content = parser.get_mission_content()

    # Add trigger that runs script at time = 1 second
    modified_content = inject_mission_start_trigger(content, full_script)

    parser.write_mission_content(modified_content)
    parser.repackage(output_path)

    return output_path
```

---

**Step 4: Add Mission Start Trigger**
```python
def inject_mission_start_trigger(mission_content, script_code):
    """Add DO_SCRIPT trigger to mission."""

    # Find triggers section
    triggers_pattern = r'(\["trigrules"\]\s*=\s*\n\s*\{)(.*?)(\},\s*--\s*end\s*of\s*\["trigrules"\])'

    match = re.search(triggers_pattern, mission_content, re.DOTALL)
    if not match:
        # No triggers section, create one
        # (implementation details...)
        pass

    # Find max trigger ID
    trigger_ids = re.findall(r'\[(\d+)\]\s*=\s*\{', match.group(2))
    max_id = max([int(tid) for tid in trigger_ids]) if trigger_ids else 0
    new_id = max_id + 1

    # Create new trigger
    new_trigger = f'''
        [{new_id}] =
        {{
            ["rules"] =
            {{
                [1] =
                {{
                    ["coalitionlist"] = "all",
                    ["once"] = true,
                    ["seconds"] = 1,
                    ["predicate"] = "c_time_after",
                }},
            }},
            ["actions"] =
            {{
                [1] =
                {{
                    ["predicate"] = "a_do_script",
                    ["file"] = "",
                    ["text"] = {json.dumps(script_code)},
                }},
            }},
            ["eventlist"] = "",
            ["comment"] = "Dynamic Mission Library Initialization",
        }},
'''

    # Insert into triggers section
    new_triggers_section = match.group(2) + new_trigger
    modified_content = mission_content[:match.start(2)] + new_triggers_section + mission_content[match.end(2):]

    return modified_content
```

---

### Testing Integration

**Test Script:**
```python
def test_library_injection():
    """Test library injection process."""

    mission_params = {
        'name': 'Test SEAD Mission',
        'type': 'SEAD',
        'difficulty': 'medium',
        'map': 'Caucasus',
        'player_aircraft': 'F-16C_50'
    }

    # Inject library
    output_path = inject_dynamic_library(
        '../miz-files/input/base_caucasus.miz',
        '../miz-files/output/test_dynamic.miz',
        mission_params
    )

    print(f"Mission created: {output_path}")
    print("Load in DCS and check DCS.log for initialization messages")
```

---

## Performance Optimization

### Key Strategies

#### 1. Lazy Spawning
Don't spawn units until needed.

```lua
-- BAD: Spawn all at mission start
for i = 1, 10 do
    AirSpawner.spawn(template)
end

-- GOOD: Schedule spawns over time
for i = 1, 10 do
    timer.scheduleFunction(function()
        AirSpawner.spawn(template)
    end, nil, timer.getTime() + i * 300)
end
```

---

#### 2. Spawn Limits
Enforce maximum concurrent units.

```lua
Spawner.spawn = function(template)
    if DynamicMission.state.spawn_counters[template.id] >= template.max_concurrent then
        DynamicMission.log("Spawn limit reached for " .. template.id)
        return nil
    end

    -- Proceed with spawn
    -- ...
end
```

---

#### 3. Distance Culling
Despawn units far from player.

```lua
DespawnManager.checkDistance = function()
    local player = DynamicMission.state.player_stats.current_aircraft
    if not player then return end

    local player_pos = player:getPosition().p

    for group_name, group in pairs(DynamicMission.state.spawned_groups) do
        local group_pos = group:getPosition().p
        local distance = DynamicMission.getDistance(player_pos, group_pos)

        if distance > 100000 then  -- 100km
            group:destroy()
            DynamicMission.state.spawned_groups[group_name] = nil
            DynamicMission.log("Despawned distant group: " .. group_name)
        end
    end
end

-- Run every 60 seconds
timer.scheduleFunction(DespawnManager.checkDistance, nil, timer.getTime() + 60)
```

---

#### 4. Efficient Randomization
Pre-calculate random values at init.

```lua
-- BAD: Calculate every spawn
LocationRandomizer.getSpawnPoint = function(zone)
    -- Complex calculation every time
end

-- GOOD: Pre-calculate spawn points
DynamicMission.init = function(config)
    DynamicMission.state.precalculated_spawns = {}

    for zone_name, zone in pairs(config.spawn_zones) do
        local points = {}
        for i = 1, 20 do  -- Pre-calculate 20 points per zone
            table.insert(points, LocationRandomizer.getSpawnPoint(zone))
        end
        DynamicMission.state.precalculated_spawns[zone_name] = points
    end
end

-- Use pre-calculated point
LocationRandomizer.getRandomPreCalculated = function(zone_name)
    local points = DynamicMission.state.precalculated_spawns[zone_name]
    return points[math.random(#points)]
end
```

---

#### 5. Event Throttling
Don't react to every event.

```lua
EventHandler.handleDead = function(self, event)
    -- Only process if enough time passed since last
    local now = timer.getTime()
    local last_check = DynamicMission.state.last_death_check or 0

    if now - last_check < 10 then  -- Throttle to once per 10 seconds
        return
    end

    DynamicMission.state.last_death_check = now

    -- Process death event
    -- ...
end
```

---

### Performance Targets

- **Initialization**: < 1 second
- **Spawn Operation**: < 0.1 seconds per group
- **Event Handling**: < 0.01 seconds per event
- **FPS Impact**: < 5 FPS drop with 8 concurrent spawned groups
- **Memory**: < 50 MB additional usage

---

## Testing Strategy

### Unit Tests (Python Side)

**Test Config Generation:**
```python
def test_config_generation():
    params = {
        'type': 'SEAD',
        'difficulty': 'medium'
    }
    config_lua = generate_lua_config(params)

    assert 'mission_type = "SEAD"' in config_lua
    assert 'difficulty = "medium"' in config_lua
```

**Test Lua Syntax:**
```python
def test_lua_syntax():
    library_code = load_library_code()

    # Use lupa or subprocess to check Lua syntax
    proc = subprocess.run(
        ['luac', '-p', '-'],
        input=library_code.encode(),
        capture_output=True
    )

    assert proc.returncode == 0, f"Lua syntax error: {proc.stderr}"
```

**Test Injection:**
```python
def test_mission_injection():
    output = inject_dynamic_library(
        'test.miz',
        'test_output.miz',
        {'type': 'SEAD', 'difficulty': 'medium'}
    )

    assert Path(output).exists()

    # Extract and verify trigger exists
    parser = MizParser(output)
    parser.extract()
    content = parser.get_mission_content()

    assert 'DynamicMission.init' in content
```

---

### Integration Tests (DCS)

**Test Mission Set:**

1. **Minimal Test**: Single timed spawn
   - Load mission
   - Wait 5 minutes
   - Verify spawn occurs
   - Check DCS.log

2. **Randomization Test**: Run 5 times
   - Verify different spawn locations each time
   - Verify timing variance
   - Check loadout differences

3. **Event Test**: Trigger-based spawns
   - Destroy SAM site
   - Verify reinforcement spawns
   - Check timing and location

4. **Performance Test**: Maximum load
   - Spawn 8 groups simultaneously
   - Monitor FPS (should stay > 30)
   - Check memory usage

5. **Adaptive Difficulty Test**:
   - Get 6 kills quickly
   - Verify difficulty increases
   - Check spawn frequency and skill

---

### Test Checklist

**Before Release:**
- [ ] All unit tests pass
- [ ] Mission loads in DCS without errors
- [ ] DCS.log shows successful initialization
- [ ] Spawns occur at expected times (± variance)
- [ ] Random elements vary between runs
- [ ] Events trigger correctly
- [ ] Adaptive difficulty adjusts properly
- [ ] Performance acceptable (>30 FPS)
- [ ] Mission completable
- [ ] No Lua errors in DCS.log

---

## Implementation Roadmap

### Phase 1: Core Foundation (Week 1)

**Tasks:**
- [ ] Create file structure
- [ ] Implement core module (init, state, utils)
- [ ] Implement event handler (basic events)
- [ ] Create simple spawn template system
- [ ] Test injection into mission file
- [ ] Verify initialization in DCS

**Deliverable:** Basic library that initializes and logs to DCS.log

---

### Phase 2: Spawning System (Week 2)

**Tasks:**
- [ ] Implement air spawner (aircraft groups)
- [ ] Implement ground spawner (vehicles, SAMs)
- [ ] Create location randomizer
- [ ] Create timing randomizer
- [ ] Test spawning in DCS
- [ ] Verify spawn positions and timing

**Deliverable:** Can spawn aircraft and ground units dynamically

---

### Phase 3: Behaviors & Events (Week 3)

**Tasks:**
- [ ] Implement reinforcement system
- [ ] Implement adaptive difficulty
- [ ] Add event-driven spawning
- [ ] Create mission type presets (SEAD, CAP, Strike)
- [ ] Test complete mission lifecycle

**Deliverable:** Full dynamic mission experience

---

### Phase 4: Polish & Optimization (Week 4)

**Tasks:**
- [ ] Performance optimization (culling, limits, caching)
- [ ] Error handling and graceful degradation
- [ ] Comprehensive testing
- [ ] Documentation
- [ ] Example missions
- [ ] Integration with MCP server

**Deliverable:** Production-ready library

---

### Phase 5: Advanced Features (Future)

**Ideas:**
- Naval operations (carrier spawns, ship groups)
- Helicopter missions (CSAR, transport)
- Weather randomization
- Campaign progression (persistent state across missions)
- Voice messaging (random radio calls)
- Advanced AI tactics (coordinated attacks)
- Player performance analytics
- Mission director (real-time mission adaptation)

---

## Conclusion

The Lua Scripting Library provides the foundation for truly dynamic DCS missions. By combining:

- **Event-driven architecture** (responsive to mission events)
- **Smart randomization** (varied but balanced)
- **Adaptive difficulty** (matches player skill)
- **Mission-type presets** (tailored experiences)
- **Performance optimization** (smooth gameplay)

We transform static mission files into living, replayable experiences that feel different every time.

**Key Success Factors:**
1. ✅ **Config-Driven**: Easy for MCP server to generate
2. ✅ **Self-Contained**: No external dependencies
3. ✅ **Performant**: Minimal FPS impact
4. ✅ **Flexible**: Supports all mission types
5. ✅ **Tested**: Comprehensive validation

**Next Steps:**
1. Begin Phase 1 implementation
2. Create test missions
3. Integrate with MCP server
4. Iterate based on testing

---

**Document Version:** 1.0
**Last Updated:** 2024-12-30
**Status:** Ready for Implementation
