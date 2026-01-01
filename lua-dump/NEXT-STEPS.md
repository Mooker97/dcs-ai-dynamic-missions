# DMS Lua Library - Remaining Scripts to Build

This document outlines the remaining scripts to complete the DMS Lua library enhancement.

## Completed This Session

- [x] ai-behavior/task-force.lua - Coordinated multi-group tactics
- [x] ai-behavior/flanking.lua - Automatic flanking maneuvers
- [x] ai-behavior/fire-support.lua - Groups call for help
- [x] ai-behavior/awareness-state.lua - UNAWARE->SUSPICIOUS->ALERT->HUNTING state machine
- [x] ai-behavior/search-pattern.lua - Spiral/grid/random search patterns
- [x] ai-behavior/threat-reaction.lua - React to player flight profile
- [x] ai-behavior/skill-scaling.lua - Dynamic difficulty adjustment
- [x] player-support/command-menu.lua - F10 menu builder

---

## Remaining Scripts

### 1. player-support/support-requests.lua

**Purpose**: Player can call in various support assets through F10 menu

**Features**:
- Artillery/mortar strikes at marked positions
- Smoke markers (colored) for CAS coordination
- Illumination flares for night operations
- MEDEVAC requests for downed pilots
- SEAD requests to suppress air defenses
- Resupply drops at designated locations

**Key Functions**:
```lua
DMS.SupportRequests.configure(settings)
DMS.SupportRequests.registerAsset(assetId, assetType, groupName, options)
DMS.SupportRequests.requestArtillery(targetPos, options)
DMS.SupportRequests.requestSmoke(pos, color)
DMS.SupportRequests.requestIllumination(pos)
DMS.SupportRequests.requestMEDEVAC(pos)
DMS.SupportRequests.requestSEAD(targetArea)
DMS.SupportRequests.requestResupply(pos)
```

**Integration Points**:
- Works with command-menu.lua for F10 interface
- Integrates with spawners for asset activation
- Uses player position for request origin

---

### 2. mission-state/phase-manager.lua

**Purpose**: Mission phase state machine with automatic transitions

**Phases**:
```
BRIEFING -> INGRESS -> ATTACK -> EGRESS -> RTB -> COMPLETE
                |         |
                v         v
             [ABORT] <- [ABORT]
```

**Features**:
- Define phase transition conditions (zone entry, kills, time, flags)
- Phase-specific behaviors (spawn enemies on ATTACK, stop spawns on EGRESS)
- Automatic briefing updates per phase
- Phase timeout handling
- Mission success/failure evaluation
- Hooks for custom phase entry/exit logic

**Key Functions**:
```lua
DMS.PhaseManager.configure(settings)
DMS.PhaseManager.definePhase(phaseId, options)
DMS.PhaseManager.addTransition(fromPhase, toPhase, conditions)
DMS.PhaseManager.start(initialPhase)
DMS.PhaseManager.getCurrentPhase()
DMS.PhaseManager.forceTransition(phaseId)
DMS.PhaseManager.onPhaseEnter(phaseId, callback)
DMS.PhaseManager.onPhaseExit(phaseId, callback)
```

**Example Usage**:
```lua
DMS.PhaseManager.definePhase("INGRESS", {
    briefing = "Proceed to target area",
    duration = 600,  -- 10 minute timeout
    onEnter = function() DMS.RandomSpawn.start() end,
})

DMS.PhaseManager.addTransition("INGRESS", "ATTACK", {
    type = "zone",
    zone = "TARGET_AREA",
})

DMS.PhaseManager.addTransition("ATTACK", "EGRESS", {
    type = "objectives",
    required = {"destroy_radar", "destroy_sam"},
})
```

---

### 3. events/event-chain.lua

**Purpose**: Linked event sequences that create cause-and-effect chains

**Features**:
- Chain events together: Kill A -> Triggers B -> Enables C
- Delay between chain links
- Branching chains (success/failure paths)
- Chain status tracking
- Parallel chain execution
- Chain cancellation/reset

**Key Functions**:
```lua
DMS.EventChain.configure(settings)
DMS.EventChain.defineChain(chainId, steps)
DMS.EventChain.start(chainId)
DMS.EventChain.pause(chainId)
DMS.EventChain.resume(chainId)
DMS.EventChain.cancel(chainId)
DMS.EventChain.getStatus(chainId)
DMS.EventChain.onComplete(chainId, callback)
```

**Example Usage**:
```lua
DMS.EventChain.defineChain("sead_cascade", {
    {
        trigger = {type = "kill", target = "EWR-1"},
        action = function()
            trigger.action.outText("Early warning radar destroyed!", 10)
        end,
        delay = 0,
    },
    {
        trigger = {type = "delay", seconds = 30},
        action = function()
            -- SAMs go blind, reduce detection range
            DMS.SAMAmbush.setDetectionMultiplier(0.3)
        end,
    },
    {
        trigger = {type = "delay", seconds = 60},
        action = function()
            -- QRF responds
            DMS.SpawnPool.forceSpawn("QRF-Helicopters")
        end,
    },
})
```

---

### 4. events/conditional-triggers.lua

**Purpose**: Complex if/then/else logic for mission events

**Features**:
- Boolean conditions (AND, OR, NOT)
- Comparison operators (<, >, ==, !=)
- Variable tracking (player kills, time, flags)
- Nested conditions
- Condition groups
- Time-based conditions
- Zone-based conditions

**Key Functions**:
```lua
DMS.ConditionalTrigger.configure(settings)
DMS.ConditionalTrigger.define(triggerId, conditions, actions)
DMS.ConditionalTrigger.setVariable(name, value)
DMS.ConditionalTrigger.getVariable(name)
DMS.ConditionalTrigger.evaluate(triggerId)
DMS.ConditionalTrigger.enable(triggerId)
DMS.ConditionalTrigger.disable(triggerId)
```

**Example Usage**:
```lua
DMS.ConditionalTrigger.define("reinforcement_logic", {
    conditions = {
        type = "AND",
        {type = "variable", name = "player_kills", operator = ">=", value = 5},
        {type = "variable", name = "mission_time", operator = ">", value = 300},
        {
            type = "OR",
            {type = "flag", name = "SAM_DESTROYED", value = true},
            {type = "zone", zone = "DEEP_STRIKE", occupied = true},
        },
    },
    actions = {
        {type = "spawn", pool = "heavy_reinforcements"},
        {type = "message", text = "Enemy reinforcements inbound!"},
        {type = "setVariable", name = "reinforcements_called", value = true},
    },
})
```

---

### 5. comms/enemy-network.lua

**Purpose**: AI-to-AI communications that players can intercept

**Features**:
- Context-aware enemy radio chatter
- Interceptable transmissions based on player equipment/position
- Message types: Contact reports, reinforcement requests, retreat orders
- Frequency hopping simulation
- Intel gathering mechanic
- Language/encryption levels

**Key Functions**:
```lua
DMS.EnemyNetwork.configure(settings)
DMS.EnemyNetwork.registerNode(nodeId, groupName, options)
DMS.EnemyNetwork.broadcast(nodeId, messageType, data)
DMS.EnemyNetwork.setInterceptable(enabled, range)
DMS.EnemyNetwork.onIntercept(callback)
DMS.EnemyNetwork.getNetworkStatus()
DMS.EnemyNetwork.disruptNetwork(area, duration)
```

**Message Types**:
```lua
-- Contact reports
"CONTACT: Враг замечен, квадрат 34TFK!"  -- Russian
"Contact report: Enemy aircraft bearing 270, low altitude"  -- English translation if intercepted

-- Reinforcement requests
"Requesting immediate support, heavy casualties"

-- Retreat orders
"All units fall back to secondary positions"

-- Status updates
"Ammunition critical, requesting resupply"
```

**Example Usage**:
```lua
DMS.EnemyNetwork.configure({
    defaultLanguage = "russian",
    interceptRange = 15000,  -- 15km
    decryptionChance = 0.7,  -- 70% chance to understand
})

-- Automatically generate comms when awareness state changes
DMS.Awareness.onStateChange(function(groupName, oldState, newState)
    if newState == "ALERT" then
        DMS.EnemyNetwork.broadcast(groupName, "CONTACT", {
            bearing = calculateBearing(groupName),
            distance = calculateDistance(groupName),
        })
    end
end)
```

---

### 6. comms/brevity-codes.lua

**Purpose**: Proper military brevity code generation

**Features**:
- BRAA (Bearing, Range, Altitude, Aspect) calls
- Bullseye references
- 9-line CAS briefs
- SITREP formats
- Contact classifications (HOSTILE, FRIENDLY, UNKNOWN)
- Altitude calls (ANGELS, CHERUBS)
- Tactical calls (FOX, RIFLE, MAGNUM, etc.)

**Key Functions**:
```lua
DMS.Brevity.configure(settings)
DMS.Brevity.setBullseye(pos)
DMS.Brevity.formatBRAA(fromPos, toPos)
DMS.Brevity.formatBullseye(pos)
DMS.Brevity.format9Line(targetData)
DMS.Brevity.formatSITREP(data)
DMS.Brevity.formatAltitude(meters)
DMS.Brevity.getContactCall(unitType)
DMS.Brevity.getWeaponCall(weaponType)
```

**Example Output**:
```lua
-- BRAA call
DMS.Brevity.formatBRAA(playerPos, targetPos)
-- Returns: "BRAA 045/15/12000/HOT"  (bearing 045, 15nm, 12000ft, hot aspect)

-- Bullseye
DMS.Brevity.formatBullseye(targetPos)
-- Returns: "BULLSEYE 270/45"  (270 degrees, 45nm from bullseye)

-- 9-Line
DMS.Brevity.format9Line({
    ip = "IP ALPHA",
    heading = 180,
    distance = 5,
    elevation = 150,
    targetDesc = "T-72 PLATOON",
    location = {x = 100000, z = 200000},
    mark = "SMOKE",
    friendlies = "SOUTH 500M",
    egress = "EAST",
})
-- Returns formatted 9-line brief
```

---

### 7. spawners/adaptive-spawner.lua

**Purpose**: Dynamically adjust spawn density based on player performance

**Features**:
- Integrates with skill-scaling.lua
- Adjusts spawn rates up/down based on performance
- Enemy composition changes (easier/harder units)
- Spawn timing adjustments
- Wave size scaling
- Resource-based spawning (finite enemy pool)
- "Rubber-banding" prevention (limits how far difficulty can swing)

**Key Functions**:
```lua
DMS.AdaptiveSpawner.configure(settings)
DMS.AdaptiveSpawner.registerPool(poolId, groups, options)
DMS.AdaptiveSpawner.start()
DMS.AdaptiveSpawner.stop()
DMS.AdaptiveSpawner.setDifficulty(level)
DMS.AdaptiveSpawner.getSpawnRate()
DMS.AdaptiveSpawner.getUnitComposition()
DMS.AdaptiveSpawner.getRemainingResources()
```

**Example Usage**:
```lua
DMS.AdaptiveSpawner.configure({
    baseSpawnInterval = 120,      -- Base: spawn every 2 minutes
    minSpawnInterval = 60,        -- Min: every 1 minute (hard)
    maxSpawnInterval = 300,       -- Max: every 5 minutes (easy)

    -- Unit composition by difficulty
    compositions = {
        easy = {
            {type = "infantry", weight = 0.7},
            {type = "technical", weight = 0.3},
        },
        normal = {
            {type = "infantry", weight = 0.4},
            {type = "bmp", weight = 0.4},
            {type = "tank", weight = 0.2},
        },
        hard = {
            {type = "bmp", weight = 0.3},
            {type = "tank", weight = 0.4},
            {type = "aa", weight = 0.3},
        },
    },

    -- Total resources (optional finite pool)
    maxSpawns = 50,

    -- Rubber-banding limits
    maxDifficultyChange = 2,  -- Can only change 2 levels per check
})

-- Link to skill scaling
DMS.SkillScaling.onSkillChange(function(newSkill)
    local difficultyMap = {
        Rookie = "easy",
        Average = "easy",
        Good = "normal",
        High = "hard",
        Excellent = "hard",
    }
    DMS.AdaptiveSpawner.setDifficulty(difficultyMap[newSkill])
end)
```

---

### 8. README.md Updates

**Tasks**:
- Add all new ai-behavior scripts to documentation
- Add player-support scripts documentation
- Add events module documentation
- Add comms module documentation
- Add spawners/adaptive-spawner documentation
- Update integration examples showing systems working together
- Add "Quick Start" section for common use cases
- Add troubleshooting section

**New Sections to Add**:

```markdown
## AI Behavior Systems

### Task Force Coordination
Coordinate multiple groups as a cohesive unit...

### Flanking Maneuvers
Automatic flanking, pincer, and envelopment tactics...

### Fire Support System
Groups request and provide mutual support...

### Awareness State Machine
Realistic detection and alert progression...

### Search Patterns
AI search behaviors when contacts are lost...

### Threat Reaction
AI responds to player flight profile...

### Skill Scaling
Dynamic difficulty based on performance...

## Player Support Systems

### Command Menu
F10 radio menu builder...

### Support Requests
Call in artillery, smoke, MEDEVAC...

## Mission Flow Systems

### Phase Manager
Mission phase state machine...

### Event Chains
Cause-and-effect sequences...

### Conditional Triggers
Complex boolean logic...

## Communication Systems

### Enemy Network
Interceptable AI communications...

### Brevity Codes
Military brevity formatting...

## Integration Examples

### Complete Dynamic Mission
Example combining all systems...
```

---

## Implementation Priority

### High Priority (Core Functionality)
1. mission-state/phase-manager.lua - Essential for mission structure
2. events/event-chain.lua - Enables complex mission logic
3. player-support/support-requests.lua - Player agency

### Medium Priority (Enhanced Gameplay)
4. comms/brevity-codes.lua - Immersion and realism
5. spawners/adaptive-spawner.lua - Replayability
6. events/conditional-triggers.lua - Advanced logic

### Lower Priority (Polish)
7. comms/enemy-network.lua - Atmosphere/immersion
8. README.md updates - Documentation

---

## Dependencies Between Systems

```
skill-scaling.lua -----> adaptive-spawner.lua
                              |
awareness-state.lua --> enemy-network.lua
       |
       v
search-pattern.lua
threat-reaction.lua --> flanking.lua
                        task-force.lua
                        fire-support.lua

command-menu.lua -----> support-requests.lua

phase-manager.lua ----> event-chain.lua
                              |
                              v
                   conditional-triggers.lua
```

---

## Estimated Effort

| Script | Lines | Complexity | Est. Time |
|--------|-------|------------|-----------|
| support-requests.lua | ~250 | Medium | 20 min |
| phase-manager.lua | ~350 | High | 30 min |
| event-chain.lua | ~300 | High | 25 min |
| conditional-triggers.lua | ~400 | Very High | 35 min |
| enemy-network.lua | ~300 | Medium | 25 min |
| brevity-codes.lua | ~350 | Medium | 25 min |
| adaptive-spawner.lua | ~250 | Medium | 20 min |
| README.md updates | ~500 | Low | 30 min |

**Total Estimated: ~3.5 hours**

---

## Notes

- All scripts follow the `DMS.ModuleName = {}` namespace pattern
- All scripts include `configure()` function for customization
- All scripts export to `_G.DMS` for cross-module access
- Integration with existing systems via optional checks (`if DMS.OtherModule then`)
- Each script includes comprehensive usage examples in comments
