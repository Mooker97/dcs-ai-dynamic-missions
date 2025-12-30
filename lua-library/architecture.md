# Lua Scripting Library - Architecture

**Authoritative architecture reference for the `lua-library` dynamic mission scripting system.**

---

## 🔴 Critical Rules

### ALWAYS Use Event-Driven Architecture

**Mandatory Pattern**: All dynamic mission behaviors MUST follow the event-driven workflow:

```
DCS Mission Start → Library Init → Event Handlers Registered → React to Mission Events → Dynamic Spawns/Behaviors
```

**Why**:
- ✅ Integrates naturally with DCS scripting environment
- ✅ Performant (events only fire when needed)
- ✅ Flexible (can react to any mission event)
- ✅ Extensible (easy to add new behaviors)
- ❌ Don't use frame-based logic (performance killer)

**Never**:
- ❌ Don't poll every frame for conditions
- ❌ Don't create circular dependencies between modules
- ❌ Don't spawn all units at mission start (defeats purpose)
- ❌ Don't use external files (DCS sandbox doesn't allow)

---

## Library Philosophy

### Core Principles

1. **Event-Driven** - React to DCS events, don't poll
2. **Config-Driven** - Mission behavior defined in embedded configuration
3. **Self-Contained** - Single Lua file, no external dependencies
4. **Performant** - Minimal FPS impact through smart spawning
5. **Modular** - Separate concerns (spawning, randomization, behaviors)
6. **MCP-Generated** - Config and injection handled by MCP server
7. **Well-Tested** - Each module tested in real DCS missions

### Design Goals

- **Replayability** - No two mission runs are identical
- **Balance** - Randomization within reasonable bounds
- **Performance** - Smooth gameplay (>30 FPS with dynamic content)
- **Flexibility** - Support all mission types (SEAD, CAP, Strike, etc.)
- **Debuggability** - Clear logging for troubleshooting

---

## Architecture Overview

### Folder Structure

```
lua-library/
├── architecture.md             # This document
├── README.md                   # Library overview and usage
├── build.py                    # Compiles modules into single Lua file
│
├── core/                       # Core system
│   ├── init.lua               # Initialization and state management
│   ├── event_handler.lua      # DCS event system integration
│   └── utils.lua              # Helper functions
│
├── spawners/                   # Spawning modules
│   ├── air_spawner.lua        # Aircraft spawning
│   ├── ground_spawner.lua     # Ground unit spawning
│   └── naval_spawner.lua      # Ship spawning
│
├── randomizers/                # Randomization modules
│   ├── location.lua           # Random position generation
│   ├── loadout.lua            # Weapon loadout randomization
│   ├── timing.lua             # Spawn delay randomization
│   └── weather.lua            # Weather variation (future)
│
├── behaviors/                  # Behavior modules
│   ├── adaptive_difficulty.lua  # Performance-based difficulty
│   ├── reinforcements.lua     # Reinforcement spawning logic
│   └── rescue.lua             # Rescue mission logic (future)
│
├── mission_types/              # Mission-specific presets
│   ├── sead.lua               # SEAD mission configuration
│   ├── cap.lua                # CAP mission configuration
│   ├── strike.lua             # Strike mission configuration
│   └── escort.lua             # Escort mission configuration
│
├── utils/                      # Utility modules
│   ├── templates.lua          # Unit/group templates
│   ├── zones.lua              # Zone manipulation utilities
│   └── validation.lua         # Input validation
│
└── tests/                      # Test missions
    ├── README.md              # Testing guide
    ├── test_spawning.miz      # Basic spawn test
    ├── test_events.miz        # Event handling test
    └── test_performance.miz   # Performance stress test
```

### Module Organization

**By Function**:
- `core/` - Foundation (init, events, utilities)
- `spawners/` - Unit creation logic
- `randomizers/` - Variation generators
- `behaviors/` - Complex mission behaviors
- `mission_types/` - Pre-configured mission templates

**By Purpose**:
- `*.lua` files - Individual Lua modules
- `build.py` - Python script to compile modules into single file
- `tests/` - Test missions for validation

**Integration Flow**:
```
1. MCP Server generates config
2. build.py compiles all modules → dynamic_mission_lib.lua
3. Config + Library injected into .miz as trigger script
4. DCS runs script on mission start
5. Library reacts to mission events
```

---

## API Design Patterns

### Pattern 1: Module Structure

**Standard Module Layout**:
```lua
-- Module: spawners/air_spawner.lua

DynamicMission = DynamicMission or {}
DynamicMission.AirSpawner = {}

-- Private functions
local function validateTemplate(template)
    -- Validation logic
end

local function generateGroup(template, position)
    -- Group generation logic
end

-- Public API
function DynamicMission.AirSpawner.spawn(template)
    """
    Spawn aircraft group from template.

    Args:
        template (table): Spawn template configuration

    Returns:
        Group|nil: Spawned group or nil if failed
    """

    -- 1. Validate template
    if not validateTemplate(template) then
        DynamicMission.log("Invalid template", "ERROR")
        return nil
    end

    -- 2. Get random position
    local position = DynamicMission.LocationRandomizer.getSpawnPoint(template.spawn.location)

    -- 3. Generate group
    local group = generateGroup(template, position)

    -- 4. Track in state
    DynamicMission.state.spawned_groups[group:getName()] = {
        template_id = template.id,
        spawn_time = timer.getTime()
    }

    return group
end
```

---

### Pattern 2: Event Handler Structure

**Standard Event Handler**:
```lua
-- Module: core/event_handler.lua

DynamicMission.EventHandler = {}

function DynamicMission.EventHandler:onEvent(event)
    """
    Main event dispatcher.
    Called by DCS when mission events occur.
    """

    if event.id == world.event.S_EVENT_BIRTH then
        self:handleBirth(event)
    elseif event.id == world.event.S_EVENT_DEAD then
        self:handleDeath(event)
    elseif event.id == world.event.S_EVENT_TAKEOFF then
        self:handleTakeoff(event)
    -- ... more events
    end
end

function DynamicMission.EventHandler:handleDeath(event)
    """
    Handle unit death events.
    Triggers reinforcements, adaptive difficulty, etc.
    """

    local unit = event.initiator
    if not unit then return end

    -- Check if player died
    if unit:getPlayerName() then
        DynamicMission.state.player_stats.deaths = DynamicMission.state.player_stats.deaths + 1
        DynamicMission.AdaptiveDifficulty.update()
    end

    -- Check if enemy died (player kill)
    if unit:getCoalition() ~= coalition.side.BLUE then
        DynamicMission.state.player_stats.kills = DynamicMission.state.player_stats.kills + 1
        DynamicMission.AdaptiveDifficulty.update()
    end

    -- Trigger reinforcements if configured
    DynamicMission.Reinforcements.checkTriggers(event)
end

-- Register with DCS
world.addEventHandler(DynamicMission.EventHandler)
```

---

### Pattern 3: Configuration Structure

**Mission Configuration Template**:
```lua
-- Generated by MCP Server

MissionConfig = {
    -- Metadata
    mission_name = "SEAD Caucasus",
    mission_type = "SEAD",
    difficulty = "medium",

    -- Settings
    settings = {
        max_concurrent_spawns = 8,
        despawn_distance = 100000,
        logging_level = "INFO",
        seed = nil  -- nil = random, number = reproducible
    },

    -- Spawn definitions
    spawns = {
        {
            id = "mig29_cap_1",
            enabled = true,

            template = {
                name = "MiG-29-CAP",
                unit_type = "MiG-29S",
                coalition = "red",
                category = "airplane",

                group = {
                    count = 2,
                    skill = "Good",
                    skill_variance = true
                },

                loadout = {
                    type = "CAP",
                    randomize = true
                },

                spawn = {
                    location = {
                        type = "random_in_zone",
                        zone_name = "EnemySpawn1",
                        altitude_min = 5000,
                        altitude_max = 8000
                    },
                    timing = {
                        initial_delay = 300,
                        random_offset = 120
                    }
                },

                behavior = {
                    task = "CAP",
                    waypoints = "generate_patrol",
                    patrol_center = {x = -50000, y = 30000},
                    patrol_radius = 20000
                }
            },

            schedule = {
                repeat_interval = 600,
                max_spawns = 3
            },

            conditions = {
                player_takeoff = true,
                time_of_day = "any"
            }
        }
        -- ... more spawns
    },

    -- Event-driven behaviors
    events = {
        {
            id = "sam_destroyed_reinforcement",
            trigger = "sam_destroyed",

            conditions = {
                probability = 0.7,
                max_reinforcements = 2
            },

            actions = {
                {
                    type = "spawn",
                    template_id = "sa11_backup",
                    delay = 600,
                    location = "near_destroyed_unit"
                },
                {
                    type = "message",
                    text = "Enemy reinforcements detected",
                    duration = 10,
                    coalition = "blue"
                }
            }
        }
        -- ... more events
    },

    -- Adaptive difficulty
    adaptive = {
        enabled = true,
        adjustment_threshold = 5,
        difficulty_step = 0.2,
        min_difficulty = 0.5,
        max_difficulty = 2.0
    }
}
```

---

## Complete API Specification

### Core Module (`core/`)

#### init.lua - Initialization

```lua
DynamicMission.init(config)
    """
    Initialize dynamic mission system.

    Args:
        config (table): Mission configuration

    Returns:
        bool: Success status
    """

DynamicMission.log(message, level)
    """
    Log message to DCS.log file.

    Args:
        message (string): Message text
        level (string): "INFO", "WARNING", "ERROR" (default: "INFO")
    """

DynamicMission.getTime()
    """
    Get current mission time in seconds.

    Returns:
        number: Seconds since mission start
    """

DynamicMission.random(min, max)
    """
    Generate random number in range.

    Args:
        min (number): Minimum value
        max (number): Maximum value

    Returns:
        number: Random value between min and max
    """
```

---

#### event_handler.lua - Event System

```lua
DynamicMission.EventHandler:onEvent(event)
    """
    Main event dispatcher (called by DCS).
    """

DynamicMission.EventHandler:handleBirth(event)
    """Handle unit spawn events."""

DynamicMission.EventHandler:handleDeath(event)
    """Handle unit death events."""

DynamicMission.EventHandler:handleTakeoff(event)
    """Handle aircraft takeoff events."""

DynamicMission.EventHandler:handleEjection(event)
    """Handle pilot ejection events."""
```

---

#### utils.lua - Utilities

```lua
DynamicMission.getDistance(point1, point2)
    """
    Calculate distance between two points.

    Args:
        point1 (table): {x, y} or {x, y, z}
        point2 (table): {x, y} or {x, y, z}

    Returns:
        number: Distance in meters
    """

DynamicMission.getHeading(from_point, to_point)
    """
    Calculate heading from one point to another.

    Returns:
        number: Heading in radians
    """

DynamicMission.offsetPosition(point, distance, heading)
    """
    Calculate position offset by distance and heading.

    Returns:
        table: {x, y} new position
    """
```

---

### Spawners Module (`spawners/`)

#### air_spawner.lua - Aircraft Spawning

```lua
DynamicMission.AirSpawner.spawn(template)
    """
    Spawn aircraft group from template.

    Args:
        template (table): Spawn template

    Returns:
        Group|nil: Spawned group or nil if failed
    """

DynamicMission.AirSpawner.generateWaypoints(task_type, center, radius, altitude)
    """
    Generate waypoints for patrol/intercept tasks.

    Args:
        task_type (string): "CAP", "INTERCEPT", "PATROL"
        center (table): {x, y} patrol center
        radius (number): Patrol radius in meters
        altitude (number): Patrol altitude in meters

    Returns:
        table: Array of waypoint definitions
    """
```

---

#### ground_spawner.lua - Ground Unit Spawning

```lua
DynamicMission.GroundSpawner.spawn(template)
    """
    Spawn ground unit group from template.
    """

DynamicMission.GroundSpawner.spawnSAM(template)
    """
    Spawn complete SAM site with radars and launchers.

    Args:
        template (table): SAM site template

    Returns:
        table: Array of spawned groups (radars, launchers)
    """

DynamicMission.GroundSpawner.spawnOnRoad(template, road_point)
    """
    Spawn ground units on road network.
    """
```

---

### Randomizers Module (`randomizers/`)

#### location.lua - Position Randomization

```lua
DynamicMission.LocationRandomizer.randomInZone(zone_name, altitude_min, altitude_max)
    """
    Generate random position in trigger zone.

    Args:
        zone_name (string): Name of trigger zone
        altitude_min (number): Min altitude AGL (meters)
        altitude_max (number): Max altitude AGL (meters)

    Returns:
        table|nil: {x, y, alt} or nil if zone not found
    """

DynamicMission.LocationRandomizer.randomNearPoint(center, radius, altitude_min, altitude_max)
    """
    Generate random position near a point.
    """

DynamicMission.LocationRandomizer.findSafeSpawn(center, radius, coalition, min_distance)
    """
    Find spawn point away from enemy units.

    Args:
        min_distance (number): Minimum distance from enemies (meters)
    """
```

---

#### timing.lua - Timing Randomization

```lua
DynamicMission.TimingRandomizer.getSpawnDelay(base_delay, random_offset)
    """
    Calculate spawn delay with randomization.

    Args:
        base_delay (number): Base delay in seconds
        random_offset (number): Random offset (+/-) in seconds

    Returns:
        number: Final delay in seconds
    """

DynamicMission.TimingRandomizer.scheduleWave(templates, base_delay, spacing)
    """
    Schedule multiple spawns with spacing.
    """
```

---

#### loadout.lua - Loadout Randomization

```lua
DynamicMission.LoadoutRandomizer.getLoadout(aircraft_type, role)
    """
    Get random loadout for aircraft and role.

    Args:
        aircraft_type (string): Aircraft type (e.g., "F-16C_50")
        role (string): Mission role ("CAP", "SEAD", "STRIKE", "CAS")

    Returns:
        table: Loadout configuration
    """

DynamicMission.LoadoutRandomizer.getWeaponPool(role)
    """
    Get weapon pool for mission role.

    Returns:
        table: Array of valid weapons for role
    """
```

---

### Behaviors Module (`behaviors/`)

#### adaptive_difficulty.lua - Adaptive Difficulty

```lua
DynamicMission.AdaptiveDifficulty.update()
    """
    Update difficulty based on player performance.
    Adjusts spawn frequency, enemy skill, and group sizes.
    """

DynamicMission.AdaptiveDifficulty.getDifficultyModifier()
    """
    Get current difficulty multiplier.

    Returns:
        number: Difficulty modifier (0.5 - 2.0)
    """
```

---

#### reinforcements.lua - Reinforcement Logic

```lua
DynamicMission.Reinforcements.checkTriggers(event)
    """
    Check if event should trigger reinforcements.

    Args:
        event (table): DCS event data
    """

DynamicMission.Reinforcements.spawn(config)
    """
    Spawn reinforcement group.

    Args:
        config (table): Reinforcement configuration
    """
```

---

## Integration with MCP Server

### Build Process

**build.py - Module Compiler**:
```python
#!/usr/bin/env python3
"""
Compile Lua modules into single dynamic_mission_lib.lua file.
"""

def load_module(module_path):
    """Load Lua module file."""
    with open(module_path, 'r') as f:
        return f.read()

def compile_library():
    """Compile all modules into single file."""

    modules = [
        # Core modules (order matters)
        "core/init.lua",
        "core/utils.lua",
        "core/event_handler.lua",

        # Randomizers
        "randomizers/location.lua",
        "randomizers/timing.lua",
        "randomizers/loadout.lua",

        # Spawners
        "spawners/air_spawner.lua",
        "spawners/ground_spawner.lua",
        "spawners/naval_spawner.lua",

        # Behaviors
        "behaviors/adaptive_difficulty.lua",
        "behaviors/reinforcements.lua",

        # Utils
        "utils/templates.lua",
        "utils/zones.lua",
        "utils/validation.lua"
    ]

    compiled = "-- Dynamic Mission Library\n"
    compiled += f"-- Generated: {datetime.now()}\n"
    compiled += "-- DO NOT EDIT - Generated from modules\n\n"

    for module_path in modules:
        full_path = Path(__file__).parent / module_path
        compiled += f"\n-- Module: {module_path}\n"
        compiled += load_module(full_path)
        compiled += "\n"

    # Write compiled file
    output_path = Path(__file__).parent / "dynamic_mission_lib.lua"
    with open(output_path, 'w') as f:
        f.write(compiled)

    print(f"Library compiled: {output_path}")
    print(f"Modules: {len(modules)}")
    print(f"Size: {len(compiled)} characters")

    return output_path

if __name__ == "__main__":
    compile_library()
```

---

### MCP Server Integration

**Injection Workflow**:
```python
# In MCP server

from pathlib import Path
import subprocess

def inject_dynamic_library(miz_path, output_path, mission_params):
    """
    Inject dynamic mission library into .miz file.

    Args:
        miz_path: Path to base .miz file
        output_path: Path for output .miz file
        mission_params: Mission parameters from user
    """

    # 1. Generate configuration
    config_lua = generate_lua_config(mission_params)

    # 2. Compile library (runs build.py)
    library_path = Path("lua-library")
    result = subprocess.run(
        ["python", "build.py"],
        cwd=library_path,
        capture_output=True
    )

    if result.returncode != 0:
        raise Exception(f"Library compilation failed: {result.stderr}")

    # 3. Load compiled library
    with open(library_path / "dynamic_mission_lib.lua", 'r') as f:
        library_code = f.read()

    # 4. Combine config + library + init call
    full_script = f"""
{config_lua}

{library_code}

-- Initialize on mission start
DynamicMission.init(MissionConfig)
"""

    # 5. Inject into mission
    from miz_file_modification.parsing.miz_parser import MizParser
    from miz_file_modification.triggers.add import inject_script_trigger

    parser = MizParser(miz_path)
    parser.extract()
    content = parser.get_mission_content()

    # Add trigger that runs script at mission start
    modified_content = inject_script_trigger(content, full_script, time=1)

    parser.write_mission_content(modified_content)
    parser.repackage(output_path)

    return output_path
```

---

## Usage Examples

### Example 1: Basic SEAD Mission with Dynamic Spawns

**User Request**:
```
"Create a SEAD mission on Caucasus with random enemy fighter spawns"
```

**MCP Generates Config**:
```lua
MissionConfig = {
    mission_type = "SEAD",
    difficulty = "medium",

    spawns = {
        {
            id = "enemy_cap",
            template = {
                name = "MiG-29-CAP",
                unit_type = "MiG-29S",
                coalition = "red",
                category = "airplane",
                group = {count = 2, skill = "Good"},
                spawn = {
                    location = {
                        type = "random_in_zone",
                        zone_name = "EnemySpawn1",
                        altitude_min = 6000,
                        altitude_max = 8000
                    },
                    timing = {
                        initial_delay = 600,
                        random_offset = 300
                    }
                },
                behavior = {
                    task = "CAP",
                    waypoints = "generate_patrol"
                }
            },
            schedule = {
                repeat_interval = 900,
                max_spawns = 2
            }
        }
    },

    adaptive = {enabled = true}
}
```

**Runtime Behavior**:
1. Mission starts, library initializes
2. At 5-10 minutes (600±300s), first MiG-29 pair spawns in random location
3. If player performs well, difficulty increases
4. At ~20 minutes, second pair spawns
5. Every playthrough has different timing and locations

---

### Example 2: Reinforcement on SAM Destruction

**Config**:
```lua
events = {
    {
        trigger = "sam_destroyed",
        conditions = {probability = 0.7},
        actions = {
            {
                type = "spawn",
                template_id = "backup_sam",
                delay = 600,
                location = "near_destroyed_unit"
            }
        }
    }
}
```

**Runtime Behavior**:
1. Player destroys SA-6 site
2. EventHandler:handleDeath detects SAM death
3. 70% chance reinforcement triggered
4. 10 minutes later, SA-11 spawns nearby
5. Creates dynamic challenge

---

## Performance Optimization

### Critical Performance Rules

1. **Lazy Spawning**
   ```lua
   -- BAD: Spawn everything at start
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

2. **Spawn Limits**
   ```lua
   -- Enforce max concurrent spawns
   if #DynamicMission.state.spawned_groups >= config.max_concurrent then
       return nil  -- Don't spawn more
   end
   ```

3. **Distance Culling**
   ```lua
   -- Despawn distant groups every 60 seconds
   timer.scheduleFunction(function()
       for name, group in pairs(DynamicMission.state.spawned_groups) do
           local distance = getDistanceToPlayer(group)
           if distance > 100000 then
               group:destroy()
               DynamicMission.state.spawned_groups[name] = nil
           end
       end
   end, nil, timer.getTime() + 60)
   ```

4. **Event Throttling**
   ```lua
   -- Don't process every death event immediately
   local last_death_check = 0

   function handleDeath(event)
       local now = timer.getTime()
       if now - last_death_check < 10 then
           return  -- Throttle to once per 10 seconds
       end
       last_death_check = now
       -- Process event
   end
   ```

### Performance Targets

- **Initialization**: < 1 second
- **Spawn Operation**: < 0.1 seconds per group
- **Event Handling**: < 0.01 seconds per event
- **FPS Impact**: < 5 FPS drop with 8 concurrent groups
- **Memory**: < 50 MB additional usage

---

## Testing Strategy

### Test Missions

**test_spawning.miz**:
- Tests basic spawn functionality
- Single timed spawn at 1 minute
- Verify unit appears in correct location
- Check DCS.log for success

**test_events.miz**:
- Tests event-driven behaviors
- Destroy SAM → verify reinforcement
- Player eject → verify rescue spawn
- Check event triggers fire correctly

**test_performance.miz**:
- Stress test with 8 concurrent spawns
- Monitor FPS (should stay >30)
- Check memory usage
- Verify distance culling works

### Testing Checklist

**Before Release**:
- [ ] Library compiles without errors
- [ ] Mission loads in DCS
- [ ] DCS.log shows successful initialization
- [ ] Spawns occur at expected times
- [ ] Random elements vary between runs
- [ ] Events trigger correctly
- [ ] Adaptive difficulty adjusts
- [ ] Performance acceptable (>30 FPS)
- [ ] No Lua errors in DCS.log

---

## Implementation Phases

### Phase 1: Core Foundation (Week 1)
- [ ] Create module structure
- [ ] Implement core/init.lua
- [ ] Implement core/event_handler.lua
- [ ] Implement core/utils.lua
- [ ] Create build.py compiler
- [ ] Test initialization in DCS

**Deliverable**: Basic library that initializes and logs

---

### Phase 2: Spawning System (Week 2)
- [ ] Implement air_spawner.lua
- [ ] Implement ground_spawner.lua
- [ ] Implement location.lua (randomizer)
- [ ] Implement timing.lua (randomizer)
- [ ] Test spawning in DCS
- [ ] Verify spawn positions and timing

**Deliverable**: Working spawn system

---

### Phase 3: Behaviors & Events (Week 3)
- [ ] Implement reinforcements.lua
- [ ] Implement adaptive_difficulty.lua
- [ ] Add event-driven spawning
- [ ] Create mission type presets
- [ ] Test complete mission lifecycle

**Deliverable**: Full dynamic mission experience

---

### Phase 4: Polish & Integration (Week 4)
- [ ] Performance optimization
- [ ] Error handling and logging
- [ ] Integration with MCP server
- [ ] Comprehensive testing
- [ ] Documentation

**Deliverable**: Production-ready library

---

## Dependencies

### Required
- **DCS World** - Runtime environment
- **Python 3.10+** - For build.py compiler

### Build-Time
- **pathlib** - File path handling
- **datetime** - Timestamp generation

### Runtime (DCS Environment)
- **DCS Lua API** - world, timer, coalition, trigger
- **Standard Lua** - math, string, table

### No External Dependencies
- ✅ Pure Lua (no external libraries)
- ✅ Self-contained (single file deployment)
- ✅ DCS sandbox compatible

---

## Integration with miz-file-modification

### Two-System Approach

**miz-file-modification**: Static mission editing
- Add/remove/modify groups
- Change unit properties
- Modify waypoints
- Coordinate transformations

**lua-library**: Dynamic runtime behavior
- Random spawning
- Event-driven actions
- Adaptive difficulty
- Reinforcements

**Together**: Complete mission generation
```
User: "Create SEAD mission with random spawns"
    ↓
MCP Server:
  1. Use miz-file-modification to:
     - Add player aircraft
     - Add initial SAM sites
     - Set up trigger zones
     - Create base mission structure
  2. Use lua-library to:
     - Generate dynamic spawn config
     - Inject event handlers
     - Enable adaptive difficulty
    ↓
Result: Static + Dynamic = Complete Mission
```

### Workflow Example

```python
# In MCP server

def create_sead_mission(params):
    """Create complete SEAD mission."""

    # 1. Start with base mission
    base_miz = "templates/caucasus_base.miz"

    # 2. Use miz-file-modification to add static elements
    from miz_file_modification.groups.add import add_group_file
    from miz_file_modification.units.modify import modify_loadout_file

    temp_miz = "temp/step1.miz"

    # Add player aircraft
    add_group_file(
        base_miz, temp_miz,
        group_name="Player-1",
        unit_type="F-16C_50",
        coalition="blue",
        position={"x": -50000, "y": 30000}
    )

    # Add initial SAM sites (static)
    add_group_file(
        temp_miz, temp_miz,
        group_name="SAM-1",
        unit_type="SA-6",
        coalition="red",
        position={"x": 100000, "y": 50000}
    )

    # 3. Use lua-library for dynamic elements
    output_miz = params['output_path']

    inject_dynamic_library(
        temp_miz,
        output_miz,
        {
            'mission_type': 'SEAD',
            'difficulty': params['difficulty'],
            'dynamic_spawns': True,
            'reinforcements': True
        }
    )

    return output_miz
```

---

## Version History

### v0.1.0 - Architecture (Current)
- Architecture defined
- Folder structure created
- API specifications complete
- Ready for implementation

### Future Versions
- v0.2.0 - Core + spawning system
- v0.3.0 - Behaviors and events
- v0.4.0 - Mission type presets
- v1.0.0 - Production ready

---

## References

### Internal Documentation
- `../claudedocs/lua-library-architecture.md` - Detailed architecture design
- `../CLAUDE.md` - Project-wide guidelines
- `../miz-file-modification/architecture.md` - Static modification system

### External Resources
- [DCS Scripting Engine Documentation](https://wiki.hoggitworld.com/view/Scripting_Engine)
- [DCS Lua API Reference](https://wiki.hoggitworld.com/view/Category:Scripting)
- [DCS Event System](https://wiki.hoggitworld.com/view/DCS_event)

---

**Last Updated**: 2024-12-30
**Maintained By**: DCS Dynamic Mission System Project
