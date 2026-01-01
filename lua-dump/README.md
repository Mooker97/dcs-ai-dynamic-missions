# DMS Lua Script Library

Reusable Lua scripts for DCS World mission scripting. These scripts provide common functionality that can be injected into any mission via `DO SCRIPT FILE` triggers.

---

## IMPORTANT: Mission-Specific Scripts

**Mission-specific scripts should be placed in the `ZZ mission files/` folder, NOT here.**

This `lua-dump/` folder contains **reusable library scripts** that work across any mission. When creating scripts that are specific to a particular mission (custom triggers, unique spawn logic, mission-specific events), place them in:

```
DMS/
├── lua-dump/           <-- Reusable library scripts (this folder)
└── ZZ mission files/   <-- Mission-specific scripts go HERE
```

---

## Folder Structure

```
lua-dump/
├── utils/              # Core utilities - LOAD THESE FIRST
│   ├── coordinates.lua    # Coordinate conversions and calculations
│   ├── group-utils.lua    # Group/unit operations
│   ├── timer-utils.lua    # Timer scheduling helpers
│   └── messaging.lua      # Message formatting (BRA, Bullseye, etc.)
│
├── spawners/           # Unit spawning systems
│   ├── random-spawn.lua        # Basic % chance spawn at mission start
│   ├── random-spawn-delayed.lua # Time-delayed random spawns
│   ├── random-spawn-pool.lua   # Pick N random from pool (AA, patrols, etc.)
│   ├── random-spawn-hvt.lua    # Rare timed HVT spawn with kill flags
│   ├── spawn-zones.lua         # Zone-based activation
│   ├── spawn-formations.lua    # Formation patterns
│   ├── spawn-escalation.lua    # Progressive wave system
│   └── template-spawner.lua    # Template-based dynamic spawning
│
├── ai-behavior/        # AI behavior modifications
│   ├── adaptive-difficulty.lua  # Dynamic difficulty adjustment
│   ├── proximity-activation.lua # Activate groups on player approach
│   ├── sam-ambush.lua          # SAMs stay dark until optimal
│   ├── hunt-pack.lua           # Coordinated enemy hunting
│   └── retreat-scatter.lua     # Damaged units flee
│
├── comms/              # Communication systems
│   ├── awacs-gci.lua          # Radar picture calls (BRA/Bullseye)
│   ├── bda-reporter.lua       # Battle damage assessment
│   ├── intel-updates.lua      # Dynamic intelligence reports
│   ├── jtac-support.lua       # Target marking and 9-line briefs
│   └── radio-intercepts.lua   # Enemy communications intercepts
│
├── events/             # Event-driven systems
│   ├── reinforcement-waves.lua # Triggered reinforcement spawns
│   ├── alarm-system.lua        # Zone-based alert propagation
│   ├── kill-chain-reaction.lua # Cascade effects on target destruction
│   ├── narrative-events.lua    # Scripted story moments
│   └── objective-tracker.lua   # Mission objective management
│
├── mission-state/      # Mission state tracking
│   ├── score-tracker.lua       # Player scoring system
│   ├── mission-timer.lua       # Countdown/stopwatch timers
│   ├── victory-conditions.lua  # Win/lose condition tracking
│   ├── persistence-lite.lua    # Save/load mission state
│   └── stats-collector.lua     # Comprehensive statistics
│
├── player-support/     # Player assistance features
│   ├── fuel-monitor.lua        # Fuel warnings (bingo, critical)
│   ├── damage-reporter.lua     # Aircraft damage status
│   ├── rescue-coordination.lua # CSAR for ejected pilots
│   └── waypoint-helper.lua     # Navigation assistance
│
└── environment/        # Environment and atmosphere
    ├── time-of-day-effects.lua # Time-based gameplay changes
    ├── weather-impact.lua      # Weather operational effects
    ├── ambient-traffic.lua     # Non-combat AI for immersion
    └── decoy-system.lua        # Fake targets and deception
```

---

## Quick Reference by Use Case

### "I want to..."

| Goal | Script(s) to Use |
|------|------------------|
| Randomly spawn enemies at mission start | `spawners/random-spawn.lua` |
| Randomly spawn with time delay | `spawners/random-spawn-delayed.lua` |
| Pick N random from a pool (AA sites, etc.) | `spawners/random-spawn-pool.lua` |
| Rare HVT spawns with kill tracking | `spawners/random-spawn-hvt.lua` |
| Spawn enemies when player gets close | `ai-behavior/proximity-activation.lua` |
| Create wave-based enemy spawns | `spawners/spawn-escalation.lua`, `events/reinforcement-waves.lua` |
| Make SAMs ambush players | `ai-behavior/sam-ambush.lua` |
| Adjust difficulty based on player skill | `ai-behavior/adaptive-difficulty.lua` |
| Give AWACS-style radar calls | `comms/awacs-gci.lua` |
| Provide JTAC support with 9-lines | `comms/jtac-support.lua` |
| Report battle damage to players | `comms/bda-reporter.lua` |
| Add atmospheric radio chatter | `comms/radio-intercepts.lua` |
| Track mission objectives | `events/objective-tracker.lua` |
| Set win/lose conditions | `mission-state/victory-conditions.lua` |
| Add mission time limits | `mission-state/mission-timer.lua` |
| Track player scores | `mission-state/score-tracker.lua` |
| Warn players about low fuel | `player-support/fuel-monitor.lua` |
| Coordinate CSAR for ejected pilots | `player-support/rescue-coordination.lua` |
| Add civilian/ambient traffic | `environment/ambient-traffic.lua` |
| Create decoy targets | `environment/decoy-system.lua` |
| Trigger events when targets destroyed | `events/kill-chain-reaction.lua` |
| Create story/narrative moments | `events/narrative-events.lua` |

---

## Loading Order

**Always load utility scripts first**, then load feature scripts as needed.

### Recommended Load Order in Mission Editor:

1. **First** - Core utilities:
   ```
   utils/coordinates.lua
   utils/group-utils.lua
   utils/timer-utils.lua
   utils/messaging.lua
   ```

2. **Second** - Feature scripts (any order):
   ```
   spawners/...
   ai-behavior/...
   comms/...
   etc.
   ```

3. **Last** - Mission-specific initialization (from ZZ mission files/)

---

## Common Patterns

### All scripts use the `DMS` namespace:

```lua
DMS = DMS or {}
DMS.ModuleName = {}
```

### Standard configuration pattern:

```lua
-- Configure before starting
DMS.ModuleName.configure({
    playerCoalition = coalition.side.BLUE,
    someOption = value,
})

-- Start the system
DMS.ModuleName.start()
```

### Event handler pattern:

```lua
-- Systems that need event monitoring create handlers
local handler = {
    onEvent = function(self, event)
        if event.id == world.event.S_EVENT_KILL then
            -- Handle kill event
        end
    end
}
world.addEventHandler(handler)
```

### Timer scheduling pattern:

```lua
-- DCS timer pattern: return nil to stop, return time to reschedule
timer.scheduleFunction(function(args, time)
    -- Do something
    if shouldStop then
        return nil  -- Stop the timer
    end
    return time + interval  -- Reschedule
end, args, timer.getTime() + initialDelay)
```

---

## DCS Coordinate System

**CRITICAL**: DCS uses a non-standard coordinate system:

```
Vec3 = {
    x = North/South axis (positive = North)
    z = East/West axis (positive = East)
    y = Altitude (height above sea level)
}
```

All scripts in this library handle this correctly. When writing custom scripts, remember:
- Ground position = `{x, z}` NOT `{x, y}`
- Altitude = `y` NOT `z`

---

## F10 Menu Integration

Most scripts support F10 radio menu commands. Example:

```lua
-- Create submenu
local myMenu = missionCommands.addSubMenuForCoalition(
    coalition.side.BLUE,
    "My Feature"
)

-- Add command
missionCommands.addCommandForCoalition(
    coalition.side.BLUE,
    "Do Something",
    myMenu,
    function() DMS.Feature.doSomething() end
)
```

---

## Dependencies

| Script | Requires |
|--------|----------|
| Most scripts | `utils/messaging.lua` (recommended) |
| `comms/awacs-gci.lua` | `utils/coordinates.lua` |
| `comms/jtac-support.lua` | `utils/coordinates.lua` |
| `player-support/waypoint-helper.lua` | `utils/coordinates.lua` |
| `spawners/spawn-formations.lua` | `utils/coordinates.lua` |

Scripts will work without dependencies but may have reduced functionality.

---

## Adding New Scripts

When adding new reusable scripts to this library:

1. Follow the `DMS.ModuleName` namespace pattern
2. Include configuration via `configure(settings)` function
3. Provide `start()` and `stop()` functions
4. Add usage examples in comments at bottom of file
5. Document dependencies at top of file
6. Place in appropriate category folder

**Remember**: Mission-specific scripts go in `ZZ mission files/`, not here!

---

## Testing

To test scripts:

1. Create a test mission in DCS Mission Editor
2. Add groups with LATE ACTIVATION as needed
3. Add `DO SCRIPT FILE` triggers for required scripts
4. Add initialization trigger to configure and start systems
5. Run mission and verify functionality

---

## Version

Library Version: 1.0
DCS Compatibility: 2.8+
Lua Version: 5.1 (DCS embedded)
