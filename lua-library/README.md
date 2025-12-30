# Lua Scripting Library

Dynamic runtime scripting system for DCS World missions. Adds randomization, event-driven behaviors, and adaptive difficulty to missions.

## Overview

This library transforms static DCS missions into dynamic, replayable experiences:

- **Random Spawning**: Units spawn at varied locations and times
- **Event-Driven**: Reacts to player actions (kills, deaths, zone entry)
- **Adaptive Difficulty**: Adjusts challenge based on player performance
- **Reinforcements**: Dynamic enemy/friendly reinforcements
- **Mission-Type Specific**: Tailored behaviors for SEAD, CAP, Strike, etc.

## Quick Start

### For Users (MCP Server Handles This)

Users don't interact with this library directly. The MCP server:
1. Generates configuration from natural language
2. Compiles library modules
3. Injects into .miz files automatically

**Example User Flow**:
```
User: "Create SEAD mission with random enemy spawns"
    ↓
MCP: Generates mission with dynamic library
    ↓
Result: Mission file ready to fly
```

### For Developers

**Building the Library**:
```bash
cd lua-library
python build.py
# Outputs: dynamic_mission_lib.lua
```

**Testing**:
```bash
# Load test missions in DCS
# Check DCS.log for initialization messages
```

## Architecture

```
lua-library/
├── core/               # Initialization, events, utilities
├── spawners/           # Unit spawning logic
├── randomizers/        # Variation generators
├── behaviors/          # Complex mission behaviors
├── mission_types/      # Mission-specific presets
├── utils/              # Helper functions
└── tests/              # Test missions
```

## Module Overview

### Core (`core/`)
- **init.lua** - System initialization and state management
- **event_handler.lua** - DCS event system integration
- **utils.lua** - Helper functions (distance, heading, etc.)

### Spawners (`spawners/`)
- **air_spawner.lua** - Aircraft group spawning
- **ground_spawner.lua** - Ground units and SAM sites
- **naval_spawner.lua** - Ship spawning

### Randomizers (`randomizers/`)
- **location.lua** - Random position generation
- **timing.lua** - Spawn delay randomization
- **loadout.lua** - Weapon loadout variation

### Behaviors (`behaviors/`)
- **adaptive_difficulty.lua** - Performance-based difficulty adjustment
- **reinforcements.lua** - Event-triggered reinforcement spawning

### Mission Types (`mission_types/`)
- **sead.lua** - SEAD mission configuration preset
- **cap.lua** - CAP mission configuration preset
- **strike.lua** - Strike mission configuration preset

## How It Works

### 1. Build Phase (Python)

```python
# build.py compiles all modules
python build.py
# → dynamic_mission_lib.lua (single file)
```

### 2. Generation Phase (MCP Server)

```python
# MCP generates config from user request
config = generate_lua_config({
    'mission_type': 'SEAD',
    'difficulty': 'medium',
    'dynamic_spawns': True
})

# Inject library + config into mission
inject_dynamic_library(
    'base.miz',
    'output.miz',
    config
)
```

### 3. Runtime Phase (DCS)

```lua
-- Mission starts
-- Trigger fires at T+1 second
DynamicMission.init(MissionConfig)

-- Events occur
-- Library reacts
DynamicMission.EventHandler:onEvent(event)

-- Dynamic spawns
-- Random locations/timing
AirSpawner.spawn(template)
```

## Configuration Example

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
                group = {count = 2},
                spawn = {
                    location = {
                        type = "random_in_zone",
                        zone_name = "EnemySpawn1"
                    },
                    timing = {
                        initial_delay = 600,
                        random_offset = 300
                    }
                }
            }
        }
    },

    events = {
        {
            trigger = "sam_destroyed",
            actions = {
                {type = "spawn", template_id = "backup_sam"}
            }
        }
    },

    adaptive = {enabled = true}
}
```

## API Quick Reference

### Core
```lua
DynamicMission.init(config)
DynamicMission.log(message, level)
DynamicMission.getTime()
DynamicMission.random(min, max)
```

### Spawning
```lua
AirSpawner.spawn(template)
GroundSpawner.spawn(template)
GroundSpawner.spawnSAM(template)
```

### Randomization
```lua
LocationRandomizer.randomInZone(zone, alt_min, alt_max)
TimingRandomizer.getSpawnDelay(base, offset)
LoadoutRandomizer.getLoadout(aircraft, role)
```

### Behaviors
```lua
AdaptiveDifficulty.update()
Reinforcements.checkTriggers(event)
```

## Development

### Adding New Module

1. Create module file in appropriate folder
2. Follow module structure pattern:
```lua
DynamicMission = DynamicMission or {}
DynamicMission.ModuleName = {}

function DynamicMission.ModuleName.functionName(args)
    -- Implementation
end
```
3. Add module to `build.py` compilation list
4. Test in DCS with test mission
5. Update documentation

### Testing

**Test Missions**:
- `tests/test_spawning.miz` - Basic spawn test
- `tests/test_events.miz` - Event handling test
- `tests/test_performance.miz` - Performance stress test

**Running Tests**:
1. Load test mission in DCS
2. Start mission
3. Check `DCS.log` for messages
4. Verify behavior matches expected

**What to Check**:
- [ ] Library initializes (log message)
- [ ] Spawns occur at correct times
- [ ] Random elements vary between runs
- [ ] Events trigger correctly
- [ ] No Lua errors in DCS.log
- [ ] FPS stays >30

### Build Script

**build.py**:
```python
#!/usr/bin/env python3
"""Compile Lua modules into single file."""

def compile_library():
    modules = [
        "core/init.lua",
        "core/utils.lua",
        "core/event_handler.lua",
        # ... all modules
    ]

    compiled = ""
    for module in modules:
        compiled += load_module(module)

    write_output("dynamic_mission_lib.lua", compiled)
```

## Integration with miz-file-modification

**Two-System Approach**:

| System | Purpose | When Used |
|--------|---------|-----------|
| **miz-file-modification** | Static mission editing | Add/remove/modify units, groups, waypoints |
| **lua-library** | Dynamic runtime behavior | Random spawning, events, adaptive difficulty |

**Together**:
```python
# MCP Server workflow
def create_mission(params):
    # 1. Use miz-file-modification for static elements
    add_player_aircraft(base_miz, temp_miz, params)
    add_initial_sam_sites(temp_miz, temp_miz, params)

    # 2. Use lua-library for dynamic elements
    inject_dynamic_library(temp_miz, output_miz, params)

    return output_miz
```

## Performance Guidelines

### Best Practices

**DO**:
- ✅ Schedule spawns over time (lazy spawning)
- ✅ Enforce spawn limits (max concurrent)
- ✅ Despawn distant units (distance culling)
- ✅ Throttle event processing
- ✅ Pre-calculate random values at init

**DON'T**:
- ❌ Spawn everything at mission start
- ❌ Poll every frame for conditions
- ❌ Create circular dependencies
- ❌ Use frame-based logic

### Performance Targets

- **Initialization**: < 1 second
- **Spawn Operation**: < 0.1 seconds
- **Event Handling**: < 0.01 seconds
- **FPS Impact**: < 5 FPS drop
- **Memory**: < 50 MB

## Documentation

- **architecture.md** - Complete architecture and API reference
- **README.md** - This file (overview and quick start)
- **../claudedocs/lua-library-architecture.md** - Detailed design document
- **tests/README.md** - Testing guide

## Examples

### Example 1: Simple Spawn

```lua
-- Config
spawns = {
    {
        template = {
            name = "MiG-29",
            unit_type = "MiG-29S",
            spawn = {
                location = {type = "random_in_zone", zone_name = "EnemySpawn"},
                timing = {initial_delay = 300}
            }
        }
    }
}

-- Result: MiG-29 spawns at 5 minutes in random location
```

### Example 2: Event-Driven

```lua
-- Config
events = {
    {
        trigger = "sam_destroyed",
        actions = {
            {type = "spawn", template_id = "backup_sam", delay = 600}
        }
    }
}

-- Result: When player destroys SAM, backup spawns 10 minutes later
```

### Example 3: Adaptive Difficulty

```lua
-- Config
adaptive = {
    enabled = true,
    adjustment_threshold = 5,
    difficulty_step = 0.2
}

-- Result: After 5 kills, difficulty increases by 20%
```

## Roadmap

### Phase 1: Core Foundation ✅
- [x] Architecture design
- [x] Folder structure
- [ ] Core modules implementation
- [ ] Build system

### Phase 2: Spawning System
- [ ] Air spawner
- [ ] Ground spawner
- [ ] Randomizers
- [ ] Testing

### Phase 3: Behaviors
- [ ] Adaptive difficulty
- [ ] Reinforcements
- [ ] Event system
- [ ] Mission type presets

### Phase 4: Production
- [ ] Performance optimization
- [ ] Error handling
- [ ] MCP integration
- [ ] Comprehensive testing

## Contributing

1. Follow module structure pattern
2. Update build.py with new modules
3. Test in DCS before committing
4. Document API in architecture.md
5. Add usage examples

## License

Part of DCS Dynamic Mission System project.

---

**Status**: Architecture Complete, Ready for Implementation
**Version**: 0.1.0
**Last Updated**: 2024-12-30
