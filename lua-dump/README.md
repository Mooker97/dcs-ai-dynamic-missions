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
│   ├── adaptive-spawner.lua    # Dynamic spawn density based on performance
│   ├── spawn-zones.lua         # Zone-based activation
│   ├── spawn-formations.lua    # Formation patterns
│   ├── spawn-escalation.lua    # Progressive wave system
│   └── template-spawner.lua    # Template-based dynamic spawning
│
├── ai-behavior/        # AI behavior modifications
│   ├── task-force.lua          # Coordinated multi-group tactics
│   ├── flanking.lua            # Automatic flanking maneuvers
│   ├── fire-support.lua        # Groups call for help when engaged
│   ├── awareness-state.lua     # UNAWARE→SUSPICIOUS→ALERT→HUNTING states
│   ├── search-pattern.lua      # Spiral/grid/random search patterns
│   ├── threat-reaction.lua     # AI reacts to player flight profile
│   ├── skill-scaling.lua       # Dynamic difficulty adjustment
│   ├── adaptive-difficulty.lua # Legacy difficulty adjustment
│   ├── proximity-activation.lua # Activate groups on player approach
│   ├── sam-ambush.lua          # SAMs stay dark until optimal
│   ├── hunt-pack.lua           # Coordinated enemy hunting
│   └── retreat-scatter.lua     # Damaged units flee
│
├── comms/              # Communication systems
│   ├── brevity-codes.lua      # Military brevity (BRAA, 9-line, etc.)
│   ├── enemy-network.lua      # Interceptable AI-to-AI comms
│   ├── awacs-gci.lua          # Radar picture calls (BRA/Bullseye)
│   ├── bda-reporter.lua       # Battle damage assessment
│   ├── intel-updates.lua      # Dynamic intelligence reports
│   ├── jtac-support.lua       # Target marking and 9-line briefs
│   └── radio-intercepts.lua   # Enemy communications intercepts
│
├── events/             # Event-driven systems
│   ├── event-chain.lua         # Linked cause-and-effect sequences
│   ├── conditional-triggers.lua # Complex if/then/else logic
│   ├── reinforcement-waves.lua # Triggered reinforcement spawns
│   ├── alarm-system.lua        # Zone-based alert propagation
│   ├── kill-chain-reaction.lua # Cascade effects on target destruction
│   ├── narrative-events.lua    # Scripted story moments
│   └── objective-tracker.lua   # Mission objective management
│
├── mission-state/      # Mission state tracking
│   ├── phase-manager.lua      # Mission phase state machine
│   ├── score-tracker.lua       # Player scoring system
│   ├── mission-timer.lua       # Countdown/stopwatch timers
│   ├── victory-conditions.lua  # Win/lose condition tracking
│   ├── persistence-lite.lua    # Save/load mission state
│   └── stats-collector.lua     # Comprehensive statistics
│
├── player-support/     # Player assistance features
│   ├── command-menu.lua       # F10 radio menu builder
│   ├── support-requests.lua   # Artillery, MEDEVAC, SEAD requests
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
| **Spawning** | |
| Randomly spawn enemies at mission start | `spawners/random-spawn.lua` |
| Randomly spawn with time delay | `spawners/random-spawn-delayed.lua` |
| Pick N random from a pool (AA sites, etc.) | `spawners/random-spawn-pool.lua` |
| Rare HVT spawns with kill tracking | `spawners/random-spawn-hvt.lua` |
| Dynamic spawn rate based on player skill | `spawners/adaptive-spawner.lua` |
| Create wave-based enemy spawns | `spawners/spawn-escalation.lua` |
| **AI Behavior** | |
| Coordinate multiple groups as one unit | `ai-behavior/task-force.lua` |
| Make AI flank player positions | `ai-behavior/flanking.lua` |
| AI calls for reinforcements when hit | `ai-behavior/fire-support.lua` |
| Realistic UNAWARE→ALERT→HUNTING states | `ai-behavior/awareness-state.lua` |
| AI search patterns when contact lost | `ai-behavior/search-pattern.lua` |
| AI reacts to player flight profile | `ai-behavior/threat-reaction.lua` |
| Dynamic difficulty based on performance | `ai-behavior/skill-scaling.lua` |
| Spawn enemies when player gets close | `ai-behavior/proximity-activation.lua` |
| Make SAMs ambush players | `ai-behavior/sam-ambush.lua` |
| **Communications** | |
| Generate BRAA, bullseye, 9-line briefs | `comms/brevity-codes.lua` |
| Interceptable enemy radio traffic | `comms/enemy-network.lua` |
| Give AWACS-style radar calls | `comms/awacs-gci.lua` |
| Provide JTAC support with 9-lines | `comms/jtac-support.lua` |
| Report battle damage to players | `comms/bda-reporter.lua` |
| **Events & Logic** | |
| Create cause-and-effect chains | `events/event-chain.lua` |
| Complex if/then/else conditions | `events/conditional-triggers.lua` |
| Trigger events when targets destroyed | `events/kill-chain-reaction.lua` |
| Create story/narrative moments | `events/narrative-events.lua` |
| Track mission objectives | `events/objective-tracker.lua` |
| **Mission Flow** | |
| INGRESS→ATTACK→EGRESS phase system | `mission-state/phase-manager.lua` |
| Set win/lose conditions | `mission-state/victory-conditions.lua` |
| Add mission time limits | `mission-state/mission-timer.lua` |
| Track player scores | `mission-state/score-tracker.lua` |
| **Player Support** | |
| Build F10 radio menus | `player-support/command-menu.lua` |
| Call in artillery, MEDEVAC, SEAD | `player-support/support-requests.lua` |
| Warn players about low fuel | `player-support/fuel-monitor.lua` |
| Coordinate CSAR for ejected pilots | `player-support/rescue-coordination.lua` |
| **Environment** | |
| Add civilian/ambient traffic | `environment/ambient-traffic.lua` |
| Create decoy targets | `environment/decoy-system.lua` |

---

## System Integration Map

These systems are designed to work together. Here's how they connect:

```
                     ┌─────────────────┐
                     │  skill-scaling  │
                     └────────┬────────┘
                              │ difficulty level
                              ▼
┌─────────────────┐   ┌─────────────────┐   ┌─────────────────┐
│ awareness-state │──▶│ adaptive-spawner│◀──│  threat-reaction │
└────────┬────────┘   └─────────────────┘   └────────┬────────┘
         │ state changes                              │ flight profile
         ▼                                            ▼
┌─────────────────┐                         ┌─────────────────┐
│ search-pattern  │                         │    flanking     │
└─────────────────┘                         └─────────────────┘
         │                                            │
         └───────────────┬───────────────────────────┘
                         ▼
              ┌─────────────────┐
              │   task-force    │
              └────────┬────────┘
                       │ coordinated response
                       ▼
              ┌─────────────────┐   broadcasts   ┌─────────────────┐
              │  fire-support   │──────────────▶│  enemy-network  │
              └─────────────────┘                └─────────────────┘


┌─────────────────┐   conditions   ┌─────────────────┐
│  phase-manager  │◀──────────────▶│ event-chain     │
└────────┬────────┘                └────────┬────────┘
         │                                  │
         └───────────────┬──────────────────┘
                         ▼
              ┌─────────────────────┐
              │ conditional-triggers │
              └─────────────────────┘


┌─────────────────┐   ┌─────────────────┐
│  command-menu   │──▶│ support-requests│
└─────────────────┘   └─────────────────┘
```

---

## Complete Mission Example

Here's how to set up a fully dynamic mission using multiple systems:

```lua
-- ============================================
-- INITIALIZATION (load order matters!)
-- ============================================

-- 1. Configure core systems
DMS.SkillScaling.configure({
    initialSkill = "Good",
    announceChanges = false,
})

DMS.Awareness.configure({
    spreadRadius = 5000,
    detectionRange = 3000,
})

DMS.PhaseManager.configure({
    announcePhaseChanges = true,
})

-- 2. Register enemy groups for awareness
DMS.Awareness.registerBatch({
    "Patrol-1", "Patrol-2", "Patrol-3",
    "Guard-Post-1", "Guard-Post-2",
    "SAM-Site-1",
})

-- 3. Set up spawn pools for adaptive spawner
DMS.AdaptiveSpawner.registerPool("infantry", {"INF-1", "INF-2", "INF-3"}, {
    unitType = "infantry",
    difficulty = "easy",
})

DMS.AdaptiveSpawner.registerPool("armor", {"T72-1", "T72-2"}, {
    unitType = "tank",
    difficulty = "hard",
    cooldown = 180,
})

-- 4. Configure enemy network nodes
DMS.EnemyNetwork.registerNode("hq", "HQ-Group", {
    callsign = "COMMAND",
    encrypted = true,
})

DMS.EnemyNetwork.registerNode("patrol1", "Patrol-1", {
    callsign = "PATROL ONE",
})

-- 5. Define mission phases
DMS.PhaseManager.definePhase("INGRESS", {
    name = "Ingress",
    briefing = "Proceed to target area via waypoint ALPHA.",
})

DMS.PhaseManager.definePhase("ATTACK", {
    name = "Attack",
    briefing = "Engage primary objectives.",
    onEnter = function()
        DMS.Awareness.setAllState("ALERT")
        DMS.AdaptiveSpawner.start()
    end,
})

DMS.PhaseManager.definePhase("EGRESS", {
    name = "Egress",
    briefing = "Objectives complete. RTB.",
    onEnter = function()
        DMS.AdaptiveSpawner.stop()
    end,
})

-- 6. Define phase transitions
DMS.PhaseManager.addTransition("INGRESS", "ATTACK", {
    type = "zone",
    zone = "TARGET_ZONE",
})

DMS.PhaseManager.addTransition("ATTACK", "EGRESS", {
    type = "objectives",
    required = {"OBJ_PRIMARY_1", "OBJ_PRIMARY_2"},
})

-- 7. Define event chains
DMS.EventChain.defineChain("radar_cascade", {
    {
        trigger = {type = "kill", target = "EWR-1"},
        actions = {
            {type = "message", text = "Early warning radar destroyed!", duration = 10},
        },
    },
    {
        trigger = {type = "delay", seconds = 30},
        actions = {
            {type = "message", text = "Enemy SAM network degraded.", duration = 10},
            {type = "flag", flag = "SAM_DEGRADED", value = 1},
        },
    },
})

-- 8. Set up support request menu
DMS.SupportRequests.registerAsset("arty_1", DMS.SupportRequests.TYPES.ARTILLERY, nil, {
    cooldown = 180,
})

DMS.SupportRequests.registerAsset("dustoff", DMS.SupportRequests.TYPES.MEDEVAC, "MEDEVAC-1", {
    cooldown = 300,
})

-- ============================================
-- START ALL SYSTEMS
-- ============================================

DMS.SkillScaling.start()
DMS.Awareness.start()
DMS.EnemyNetwork.start()
DMS.EventChain.start("radar_cascade")
DMS.SupportRequests.start()
DMS.PhaseManager.start("INGRESS")
DMS.ConditionalTrigger.start()
```

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

2. **Second** - Feature scripts (order by dependency):
   ```
   ai-behavior/awareness-state.lua
   ai-behavior/search-pattern.lua      (uses awareness-state)
   ai-behavior/skill-scaling.lua
   ai-behavior/threat-reaction.lua
   ai-behavior/flanking.lua
   ai-behavior/task-force.lua
   ai-behavior/fire-support.lua

   comms/brevity-codes.lua
   comms/enemy-network.lua             (uses awareness-state)

   spawners/adaptive-spawner.lua       (uses skill-scaling)

   events/event-chain.lua
   events/conditional-triggers.lua

   mission-state/phase-manager.lua

   player-support/command-menu.lua
   player-support/support-requests.lua (uses command-menu)
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

Use `command-menu.lua` for easy menu building:

```lua
-- Configure
DMS.CommandMenu.configure({
    rootMenuName = "Mission Commands",
})

-- Add standard menus
DMS.CommandMenu.addStandardMenus()

-- Add custom commands
DMS.CommandMenu.addMenu("custom", "Custom Options")
DMS.CommandMenu.addCommand("my_cmd", "Do Something", "custom", function()
    -- Your code here
end)
```

Or use the DCS API directly:

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

| Script | Requires/Enhances |
|--------|-------------------|
| `search-pattern.lua` | Used by `awareness-state.lua` |
| `enemy-network.lua` | Hooks into `awareness-state.lua` |
| `adaptive-spawner.lua` | Uses `skill-scaling.lua` |
| `support-requests.lua` | Uses `command-menu.lua` |
| `event-chain.lua` | Can trigger `phase-manager.lua` |
| `conditional-triggers.lua` | Can check `phase-manager.lua`, `awareness-state.lua` |
| `brevity-codes.lua` | Used by `comms/awacs-gci.lua`, `comms/jtac-support.lua` |

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

Library Version: 2.0
DCS Compatibility: 2.8+
Lua Version: 5.1 (DCS embedded)

### Changelog

**v2.0** - Major update
- Added AI coordination systems (task-force, flanking, fire-support)
- Added awareness state machine with search patterns
- Added threat reaction system
- Added skill scaling with adaptive difficulty
- Added phase manager for mission flow
- Added event chains and conditional triggers
- Added brevity codes generator
- Added enemy network communications
- Added adaptive spawner
- Added F10 command menu builder
- Added support request system
- Improved system integration and documentation

**v1.0** - Initial release
- Core spawning systems
- Basic AI behavior scripts
- Communication systems
- Mission state tracking
