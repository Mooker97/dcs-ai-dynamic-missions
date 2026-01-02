# DMS Lua Script Reference

Complete documentation for all scripts in the DMS Lua library.

---

## Table of Contents

1. [Utils](#utils) - Core utilities (load first)
2. [Spawners](#spawners) - Unit spawning systems
3. [AI Behavior](#ai-behavior) - AI behavior modifications
4. [Communications](#communications) - Communication systems
5. [Events](#events) - Event-driven systems
6. [Mission State](#mission-state) - Mission state tracking
7. [Player Support](#player-support) - Player assistance features
8. [Environment](#environment) - Environment and atmosphere

---

## Utils

Core utility scripts that provide foundational functionality. **Load these first** before other scripts.

### coordinates.lua
**Module**: `DMS.Coordinates`

Coordinate system conversions and calculations for DCS World.

**Key Functions**:
| Function | Description |
|----------|-------------|
| `toVec3(x, y, z)` | Create Vec3 from components |
| `distance(pos1, pos2)` | Calculate distance between two points |
| `bearing(from, to)` | Calculate bearing between positions |
| `offset(pos, bearing, distance)` | Get position offset by bearing/distance |
| `toLatLon(pos)` | Convert DCS coords to lat/lon |
| `fromLatLon(lat, lon)` | Convert lat/lon to DCS coords |
| `toMGRS(pos)` | Convert to Military Grid Reference |

**Usage**:
```lua
local dist = DMS.Coordinates.distance(playerPos, targetPos)
local brg = DMS.Coordinates.bearing(playerPos, targetPos)
```

---

### group-utils.lua
**Module**: `DMS.GroupUtils`

Utilities for working with DCS groups and units.

**Key Functions**:
| Function | Description |
|----------|-------------|
| `getAliveUnits(groupName)` | Get all living units in group |
| `getGroupPosition(groupName)` | Get group's lead unit position |
| `isGroupAlive(groupName)` | Check if any units alive |
| `getGroupsByCoalition(side)` | Get all groups for coalition |
| `activateGroup(groupName)` | Activate LATE ACTIVATION group |
| `destroyGroup(groupName)` | Remove group from mission |

**Usage**:
```lua
if DMS.GroupUtils.isGroupAlive("Enemy-Patrol-1") then
    local pos = DMS.GroupUtils.getGroupPosition("Enemy-Patrol-1")
end
```

---

### timer-utils.lua
**Module**: `DMS.TimerUtils`

Helper functions for DCS timer scheduling.

**Key Functions**:
| Function | Description |
|----------|-------------|
| `schedule(func, delay)` | Schedule one-time function |
| `scheduleRepeat(func, interval)` | Schedule repeating function |
| `cancel(timerId)` | Cancel scheduled function |
| `delay(seconds)` | Get time value for delay |

**Usage**:
```lua
local id = DMS.TimerUtils.scheduleRepeat(function()
    -- Check something every 30 seconds
end, 30)
```

---

### messaging.lua
**Module**: `DMS.Messaging`

Message formatting and display utilities.

**Key Functions**:
| Function | Description |
|----------|-------------|
| `toCoalition(side, msg, duration)` | Send message to coalition |
| `toAll(msg, duration)` | Send message to all players |
| `formatTime(seconds)` | Format seconds as MM:SS |
| `formatDistance(meters)` | Format distance with units |

**Usage**:
```lua
DMS.Messaging.toCoalition(coalition.side.BLUE, "Objective complete!", 10)
```

---

### fog-of-war.lua
**Module**: `DMS.FogOfWar`

Fog of war and visibility management.

**Key Functions**:
| Function | Description |
|----------|-------------|
| `hideGroup(groupName)` | Hide group from enemy |
| `revealGroup(groupName)` | Reveal hidden group |
| `setDetectionRange(range)` | Set detection parameters |

---

### mission-settings.lua
**Module**: `DMS.MissionSettings`

Mission-wide configuration and settings management.

**Key Functions**:
| Function | Description |
|----------|-------------|
| `set(key, value)` | Set a mission setting |
| `get(key, default)` | Get a mission setting |
| `getPlayerCoalition()` | Get player coalition side |

---

## Spawners

Systems for spawning and managing units dynamically.

### random-spawn.lua
**Module**: `DMS.RandomSpawn`

Basic percentage-based random spawning at mission start.

**Key Functions**:
| Function | Description |
|----------|-------------|
| `configure(settings)` | Set configuration options |
| `register(groupName, chance)` | Register group with spawn chance |
| `registerBatch(groups)` | Register multiple groups |
| `start()` | Process all registered spawns |
| `getSpawned()` | Get list of spawned groups |

**Configuration**:
```lua
DMS.RandomSpawn.configure({
    defaultChance = 0.5,      -- 50% default spawn chance
    announceSpawns = false,   -- Don't announce spawns
})
```

**Usage**:
```lua
DMS.RandomSpawn.register("Patrol-1", 0.75)  -- 75% chance
DMS.RandomSpawn.register("Patrol-2", 0.50)  -- 50% chance
DMS.RandomSpawn.start()
```

---

### random-spawn-delayed.lua
**Module**: `DMS.DelayedSpawn`

Time-delayed random spawning with windows.

**Key Functions**:
| Function | Description |
|----------|-------------|
| `configure(settings)` | Set configuration options |
| `register(groupName, options)` | Register with delay options |
| `start()` | Begin delayed spawn processing |
| `stop()` | Stop spawn processing |

**Options**:
- `chance` - Spawn probability (0-1)
- `minDelay` - Minimum delay in seconds
- `maxDelay` - Maximum delay in seconds
- `window` - Time window for spawn

**Usage**:
```lua
DMS.DelayedSpawn.register("Reinforcements", {
    chance = 0.8,
    minDelay = 300,   -- 5 minutes minimum
    maxDelay = 900,   -- 15 minutes maximum
})
DMS.DelayedSpawn.start()
```

---

### random-spawn-pool.lua
**Module**: `DMS.SpawnPool`

Pick N random groups from a larger pool.

**Key Functions**:
| Function | Description |
|----------|-------------|
| `configure(settings)` | Set configuration options |
| `createPool(poolId, groups, count)` | Create pool with groups |
| `addToPool(poolId, groupName)` | Add group to existing pool |
| `start()` | Spawn from all pools |
| `forceSpawn(poolId)` | Force spawn from specific pool |
| `getRemaining(poolId)` | Get unspawned groups count |

**Usage**:
```lua
DMS.SpawnPool.createPool("AA_Sites", {
    "SA-6-1", "SA-6-2", "SA-6-3", "SA-8-1", "SA-8-2"
}, 2)  -- Spawn 2 random from 5

DMS.SpawnPool.start()
```

---

### random-spawn-hvt.lua
**Module**: `DMS.HVTSpawn`

Rare, timed High Value Target spawns with kill tracking.

**Key Functions**:
| Function | Description |
|----------|-------------|
| `configure(settings)` | Set configuration options |
| `register(hvtId, groupName, options)` | Register HVT |
| `start()` | Begin HVT spawn system |
| `stop()` | Stop HVT system |
| `hasBeenKilled(hvtId)` | Check if HVT was killed |
| `getKilled()` | Get all killed HVTs |

**Options**:
- `chance` - Spawn probability
- `spawnWindow` - {min, max} time window
- `flagOnKill` - Flag to set when killed
- `flagOnKillValue` - Value to set
- `killAnnouncement` - Message on kill

**Usage**:
```lua
DMS.HVTSpawn.register("general_convoy", "HVT-General", {
    chance = 0.3,
    spawnWindow = {600, 1800},
    flagOnKill = "HVT_KILLED",
    flagOnKillValue = 1,
    killAnnouncement = "High Value Target eliminated!",
})
DMS.HVTSpawn.start()
```

---

### adaptive-spawner.lua
**Module**: `DMS.AdaptiveSpawner`

Dynamic spawn density based on player performance. Integrates with skill-scaling.

**Key Functions**:
| Function | Description |
|----------|-------------|
| `configure(settings)` | Set configuration options |
| `registerPool(poolId, groups, options)` | Register spawn pool |
| `setCompositions(compositions)` | Set unit compositions by difficulty |
| `addToComposition(diff, type, pools)` | Add pools to composition |
| `start()` | Begin adaptive spawning |
| `stop()` | Stop spawning |
| `setDifficulty(level)` | Manually set difficulty |
| `forceSpawn(poolId)` | Force immediate spawn |
| `getStats()` | Get spawner statistics |
| `getSpawnInterval()` | Get current spawn interval |

**Difficulty Levels**: `easy`, `normal`, `hard`, `nightmare`

**Configuration**:
```lua
DMS.AdaptiveSpawner.configure({
    baseSpawnInterval = 120,
    minSpawnInterval = 45,
    maxSpawnInterval = 300,
    maxSpawns = 50,
    maxActiveGroups = 10,
    useSkillScaling = true,
})
```

**Usage**:
```lua
DMS.AdaptiveSpawner.registerPool("infantry", {"INF-1", "INF-2"}, {
    unitType = "infantry",
    difficulty = "easy",
})

DMS.AdaptiveSpawner.registerPool("armor", {"T72-1", "T72-2"}, {
    unitType = "tank",
    difficulty = "hard",
    cooldown = 180,
})

DMS.AdaptiveSpawner.start()
```

---

### spawn-zones.lua
**Module**: `DMS.SpawnZones`

Zone-based unit activation when players enter areas.

**Key Functions**:
| Function | Description |
|----------|-------------|
| `configure(settings)` | Set configuration options |
| `registerZone(zoneName, groups)` | Register zone with groups |
| `start()` | Begin zone monitoring |
| `stop()` | Stop zone monitoring |

**Usage**:
```lua
DMS.SpawnZones.registerZone("AMBUSH_ZONE", {
    "Ambush-Infantry-1",
    "Ambush-Infantry-2",
})
DMS.SpawnZones.start()
```

---

### spawn-formations.lua
**Module**: `DMS.SpawnFormations`

Spawn units in specific formation patterns.

**Key Functions**:
| Function | Description |
|----------|-------------|
| `line(centerPos, heading, spacing, count)` | Line formation |
| `wedge(centerPos, heading, spacing, count)` | Wedge/V formation |
| `column(centerPos, heading, spacing, count)` | Column formation |
| `circle(centerPos, radius, count)` | Circular formation |

---

### spawn-escalation.lua
**Module**: `DMS.SpawnEscalation`

Progressive wave-based spawning system.

**Key Functions**:
| Function | Description |
|----------|-------------|
| `configure(settings)` | Set configuration options |
| `defineWave(waveNum, groups)` | Define wave composition |
| `start()` | Begin escalation system |
| `triggerNextWave()` | Force next wave |
| `getCurrentWave()` | Get current wave number |

---

### template-spawner.lua
**Module**: `DMS.TemplateSpawner`

Spawn units from templates with customization.

**Key Functions**:
| Function | Description |
|----------|-------------|
| `registerTemplate(templateId, data)` | Register unit template |
| `spawn(templateId, position, options)` | Spawn from template |

---

## AI Behavior

Scripts that modify and enhance AI behavior.

### awareness-state.lua
**Module**: `DMS.Awareness`

Realistic detection and alert state machine for AI groups.

**States**: `UNAWARE` → `SUSPICIOUS` → `ALERT` → `HUNTING` → `ENGAGED`

**Key Functions**:
| Function | Description |
|----------|-------------|
| `configure(settings)` | Set configuration options |
| `register(groupName, options)` | Register group for tracking |
| `registerBatch(groupNames)` | Register multiple groups |
| `setState(groupName, state, contactPos)` | Set group state |
| `spreadAlert(sourcePos, state, contactPos)` | Spread alert to nearby |
| `start()` | Begin awareness system |
| `stop()` | Stop awareness system |
| `getStatus(groupName)` | Get group awareness info |
| `getGroupsInState(state)` | Get all groups in state |
| `setAllState(state)` | Set all groups to state |

**Configuration**:
```lua
DMS.Awareness.configure({
    spreadRadius = 5000,
    detectionRange = 3000,
    suspiciousDecayTime = 60,
    alertDecayTime = 180,
    huntingDuration = 120,
    announceStateChanges = true,
})
```

**Usage**:
```lua
DMS.Awareness.registerBatch({"Patrol-1", "Patrol-2", "Guard-Post"})
DMS.Awareness.start()

-- Manual state change
DMS.Awareness.setState("Patrol-1", DMS.Awareness.STATES.ALERT)
```

---

### search-pattern.lua
**Module**: `DMS.SearchPattern`

AI search patterns when contacts are lost. Used by awareness-state.

**Pattern Types**: `spiral`, `grid`, `random`, `sector`

**Key Functions**:
| Function | Description |
|----------|-------------|
| `configure(settings)` | Set configuration options |
| `start(groupName, lastContactPos, options)` | Start search pattern |
| `stop(groupName)` | Stop search pattern |
| `isSearching(groupName)` | Check if group searching |
| `getStatus(groupName)` | Get search status |
| `coordinatedSearch(groups, center, radius)` | Multi-group search |

**Usage**:
```lua
DMS.SearchPattern.start("Infantry-1", lastKnownPos, {
    pattern = "spiral",
    radius = 1000,
    duration = 180,
})
```

---

### skill-scaling.lua
**Module**: `DMS.SkillScaling`

Dynamic difficulty adjustment based on player performance.

**Skill Levels**: `Rookie`, `Average`, `Good`, `High`, `Excellent`

**Key Functions**:
| Function | Description |
|----------|-------------|
| `configure(settings)` | Set configuration options |
| `start()` | Begin tracking |
| `stop()` | Stop tracking |
| `getCurrentSkill(playerName)` | Get current skill level |
| `setDifficulty(skill)` | Manually set difficulty |
| `getSpawnMultiplier(skill)` | Get spawn rate multiplier |
| `getReport(playerName)` | Get performance report |
| `setGroupSkill(groupName, skill)` | Set AI group skill |
| `setAllEnemySkill(skill)` | Set all enemy skill |

**Tracked Metrics**: kills, deaths, damage received, shots fired, accuracy

**Configuration**:
```lua
DMS.SkillScaling.configure({
    initialSkill = "Good",
    minSkill = "Average",
    maxSkill = "Excellent",
    adjustmentCooldown = 90,
    announceChanges = false,
})
```

**Usage**:
```lua
DMS.SkillScaling.start()

-- Check current state
local skill = DMS.SkillScaling.getCurrentSkill()
local multiplier = DMS.SkillScaling.getSpawnMultiplier(skill)
```

---

### threat-reaction.lua
**Module**: `DMS.ThreatReaction`

AI reacts intelligently to player flight profile.

**Player Profiles**: `LOW_FAST`, `LOW_SLOW`, `HIGH_FAST`, `HIGH_SLOW`, `HOVERING`, `DIVING`, `CLIMBING`, `LOITERING`

**Key Functions**:
| Function | Description |
|----------|-------------|
| `configure(settings)` | Set configuration options |
| `addRule(ruleId, profile, action, options)` | Add reaction rule |
| `addStandardRules()` | Add default reaction rules |
| `assignRoles(assignments)` | Assign groups to roles |
| `start()` | Begin reaction system |
| `stop()` | Stop reaction system |
| `setRuleEnabled(ruleId, enabled)` | Enable/disable rule |
| `getPlayerProfile(unitName)` | Get player's current profile |

**Usage**:
```lua
DMS.ThreatReaction.addStandardRules()

-- Custom rule
DMS.ThreatReaction.addRule("custom_hover", DMS.ThreatReaction.PROFILES.HOVERING,
    function(playerUnit, profile)
        -- Send flankers when player hovers
        DMS.Flanking.executeFlank("Flanker-1", playerUnit:getPoint())
    end,
    {cooldown = 90, minTime = 10}
)

DMS.ThreatReaction.start()
```

---

### task-force.lua
**Module**: `DMS.TaskForce`

Coordinate multiple groups as a cohesive tactical unit.

**Roles**: `assault`, `support`, `flanker`, `reserve`

**Key Functions**:
| Function | Description |
|----------|-------------|
| `configure(settings)` | Set configuration options |
| `create(forceId, options)` | Create task force |
| `addGroup(forceId, groupName, role)` | Add group to force |
| `setObjective(forceId, objectivePos)` | Set force objective |
| `engage(forceId, targetPos)` | Order force to engage |
| `advance(forceId)` | Order force to advance |
| `hold(forceId)` | Order force to hold position |
| `retreat(forceId, retreatPos)` | Order force to retreat |
| `start()` | Begin task force system |

**Usage**:
```lua
DMS.TaskForce.create("Alpha", {name = "Task Force Alpha"})
DMS.TaskForce.addGroup("Alpha", "Infantry-1", "assault")
DMS.TaskForce.addGroup("Alpha", "Infantry-2", "support")
DMS.TaskForce.addGroup("Alpha", "Armor-1", "flanker")
DMS.TaskForce.setObjective("Alpha", targetPos)
DMS.TaskForce.start()
```

---

### flanking.lua
**Module**: `DMS.Flanking`

Automatic flanking maneuvers for AI groups.

**Key Functions**:
| Function | Description |
|----------|-------------|
| `configure(settings)` | Set configuration options |
| `calculateFlankPosition(groupPos, targetPos, side, distance)` | Calculate flank point |
| `executeFlank(groupName, targetPos, options)` | Execute flank maneuver |
| `executePincer(group1, group2, targetPos)` | Execute pincer movement |
| `executeEnvelopment(groups, targetPos)` | Execute envelopment |

**Usage**:
```lua
-- Single group flank
DMS.Flanking.executeFlank("Infantry-1", playerPos, {
    side = "left",
    distance = 500,
})

-- Pincer movement
DMS.Flanking.executePincer("Squad-1", "Squad-2", playerPos)
```

---

### fire-support.lua
**Module**: `DMS.FireSupport`

Groups call for help when engaged.

**Key Functions**:
| Function | Description |
|----------|-------------|
| `configure(settings)` | Set configuration options |
| `registerSupport(groupName, options)` | Register support asset |
| `registerRequester(groupName, options)` | Register group that can request |
| `start()` | Begin fire support system |
| `stop()` | Stop fire support system |
| `requestSupport(requesterGroup, targetPos)` | Manual support request |

**Usage**:
```lua
DMS.FireSupport.registerSupport("Artillery-1", {
    type = "artillery",
    range = 15000,
    cooldown = 120,
})

DMS.FireSupport.registerRequester("Infantry-1", {
    damageThreshold = 0.3,
})

DMS.FireSupport.start()
```

---

### sam-ambush.lua
**Module**: `DMS.SAMAmbush`

SAM sites stay dark until optimal engagement conditions.

**Key Functions**:
| Function | Description |
|----------|-------------|
| `configure(settings)` | Set configuration options |
| `register(groupName, options)` | Register SAM site |
| `start()` | Begin SAM ambush system |
| `stop()` | Stop SAM ambush system |
| `forceHot(groupName)` | Force SAM to go active |
| `forceCold(groupName)` | Force SAM to go dark |

**Usage**:
```lua
DMS.SAMAmbush.register("SA-6-1", {
    engagementRange = 20000,
    minAltitude = 100,
    maxAltitude = 8000,
})
DMS.SAMAmbush.start()
```

---

### hunt-pack.lua
**Module**: `DMS.HuntPack`

Coordinated group hunting behavior.

**Key Functions**:
| Function | Description |
|----------|-------------|
| `configure(settings)` | Set configuration options |
| `createPack(packId, groups)` | Create hunting pack |
| `setTarget(packId, targetPos)` | Set pack target |
| `start()` | Begin hunt pack system |

---

### retreat-scatter.lua
**Module**: `DMS.Retreat`

Damaged units flee and scatter.

**Key Functions**:
| Function | Description |
|----------|-------------|
| `configure(settings)` | Set configuration options |
| `register(groupName, options)` | Register group for retreat behavior |
| `start()` | Begin retreat system |
| `forceRetreat(groupName, retreatPos)` | Force immediate retreat |
| `scatterNear(position, radius)` | Scatter all units near position |

---

### proximity-activation.lua
**Module**: `DMS.ProximityActivation`

Activate groups when players approach.

**Key Functions**:
| Function | Description |
|----------|-------------|
| `configure(settings)` | Set configuration options |
| `register(groupName, triggerPos, radius)` | Register proximity trigger |
| `start()` | Begin proximity monitoring |
| `stop()` | Stop proximity monitoring |

---

### adaptive-difficulty.lua
**Module**: `DMS.AdaptiveDifficulty`

Legacy difficulty adjustment system.

**Key Functions**:
| Function | Description |
|----------|-------------|
| `configure(settings)` | Set configuration options |
| `start()` | Begin difficulty tracking |
| `getDifficulty()` | Get current difficulty |

---

## Communications

Systems for in-game communications and information display.

### brevity-codes.lua
**Module**: `DMS.Brevity`

Military brevity code generation (BRAA, bullseye, 9-line).

**Key Functions**:
| Function | Description |
|----------|-------------|
| `configure(settings)` | Set configuration options |
| `setBullseye(pos)` | Set bullseye reference point |
| `formatBRAA(fromPos, toPos, alt, heading)` | Format BRAA call |
| `formatBullseye(pos)` | Format bullseye reference |
| `format9Line(data)` | Format 9-line CAS brief |
| `formatSITREP(data)` | Format situation report |
| `formatAltitude(meters, format)` | Format as ANGELS/CHERUBS |
| `getContactCall(unitType)` | Get NATO reporting name |
| `getWeaponCall(weaponType)` | Get weapon brevity (FOX, RIFLE) |
| `formatThreatWarning(type, bearing, range)` | Format threat call |
| `formatDefensive(action, direction, threat)` | Format defensive call |

**Common Calls**: Available via `DMS.Brevity.Calls.*`
- `ENGAGED`, `SADDLED`, `BINGO`, `JOKER`, `WINCHESTER`
- `BLIND`, `VISUAL`, `TALLY`, `NO_JOY`, `CONTACT`, `CLEAN`
- `BREAK`, `EXTEND`, `JINK`, `NOTCH`
- `SPLASH`, `SHACK`, `BUDDY_SPIKE`, `NAILS`, `MUD`, `SPIKE`

**Usage**:
```lua
DMS.Brevity.setBullseye({x = 0, z = 0})

local braa = DMS.Brevity.formatBRAA(playerPos, targetPos, 5000, 180)
-- Returns: "BRAA 045/15/15000/HOT"

local nineLine = DMS.Brevity.format9Line({
    ip = "IP ALPHA",
    heading = 180,
    distance = 5,
    targetDesc = "T-72 PLATOON",
    mark = "SMOKE RED",
    friendlies = "SOUTH 500M",
    egress = "EAST",
})
```

---

### enemy-network.lua
**Module**: `DMS.EnemyNetwork`

Interceptable AI-to-AI radio communications.

**Message Types**: `CONTACT`, `REINFORCEMENT`, `RETREAT`, `CASUALTY`, `AMMO`, `SPOTTED`, `STATUS`, `DESTROYED`

**Key Functions**:
| Function | Description |
|----------|-------------|
| `configure(settings)` | Set configuration options |
| `registerNode(nodeId, groupName, options)` | Register comm node |
| `broadcast(nodeId, messageType, data)` | Broadcast message |
| `onIntercept(callback)` | Register intercept callback |
| `setInterceptable(enabled)` | Enable/disable interception |
| `getNetworkStatus()` | Get network status |
| `disruptNetwork(centerPos, radius, duration)` | EW jamming effect |
| `getIntercepted(since)` | Get intercepted messages |
| `start()` | Begin network system |
| `hookAwareness()` | Auto-broadcast on awareness changes |

**Configuration**:
```lua
DMS.EnemyNetwork.configure({
    defaultLanguage = "russian",
    interceptRange = 15000,
    decryptionChance = 0.7,
    showOriginal = true,
    showTranslation = true,
})
```

**Usage**:
```lua
DMS.EnemyNetwork.registerNode("patrol1", "Patrol-1", {
    callsign = "PATROL ONE",
    language = "russian",
})

DMS.EnemyNetwork.registerNode("hq", "HQ-Group", {
    callsign = "COMMAND",
    encrypted = true,
})

DMS.EnemyNetwork.start()

-- Manual broadcast
DMS.EnemyNetwork.broadcast("patrol1", "CONTACT", {
    targetPos = playerPos,
})
```

---

### awacs-gci.lua
**Module**: `DMS.AWACS`

AWACS/GCI radar picture calls.

**Key Functions**:
| Function | Description |
|----------|-------------|
| `configure(settings)` | Set configuration options |
| `setBullseye(pos)` | Set bullseye reference |
| `start()` | Begin AWACS calls |
| `stop()` | Stop AWACS calls |
| `requestPicture()` | Manual picture request |

---

### bda-reporter.lua
**Module**: `DMS.BDAReporter`

Battle Damage Assessment reporting.

**Key Functions**:
| Function | Description |
|----------|-------------|
| `configure(settings)` | Set configuration options |
| `start()` | Begin BDA tracking |
| `getReport()` | Get current BDA report |

---

### intel-updates.lua
**Module**: `DMS.Intel`

Dynamic intelligence reports.

**Key Functions**:
| Function | Description |
|----------|-------------|
| `configure(settings)` | Set configuration options |
| `addContact(contactId, data)` | Add intel contact |
| `updateContact(contactId, data)` | Update contact info |
| `broadcastUpdate()` | Send intel update to players |
| `start()` | Begin intel system |

---

### jtac-support.lua
**Module**: `DMS.JTAC`

JTAC target marking and 9-line briefs.

**Key Functions**:
| Function | Description |
|----------|-------------|
| `configure(settings)` | Set configuration options |
| `registerJTAC(jtacId, groupName, options)` | Register JTAC unit |
| `requestNineLine(jtacId, targetGroup)` | Request 9-line brief |
| `markTarget(jtacId, targetPos, markType)` | Mark target |
| `start()` | Begin JTAC system |

---

### radio-intercepts.lua
**Module**: `DMS.RadioIntercepts`

Pre-scripted enemy radio intercepts for atmosphere.

**Key Functions**:
| Function | Description |
|----------|-------------|
| `configure(settings)` | Set configuration options |
| `addIntercept(interceptId, message, options)` | Add intercept message |
| `playIntercept(interceptId)` | Play specific intercept |
| `start()` | Begin random intercepts |

---

## Events

Event-driven systems for mission logic.

### event-chain.lua
**Module**: `DMS.EventChain`

Linked cause-and-effect event sequences.

**Trigger Types**: `immediate`, `delay`, `kill`, `unit_dead`, `flag`, `zone`, `zone_exit`, `time_of_day`, `random`, `custom`, `chain_complete`, `AND`, `OR`

**Action Types**: `message`, `spawn`, `flag`, `explosion`, `smoke`, `flare`, `sound`, `activate`, `deactivate`, `start_chain`, `cancel_chain`, `awareness`, `custom`

**Key Functions**:
| Function | Description |
|----------|-------------|
| `configure(settings)` | Set configuration options |
| `defineChain(chainId, steps)` | Define event chain |
| `start(chainId, options)` | Start a chain |
| `pause(chainId)` | Pause chain execution |
| `resume(chainId)` | Resume paused chain |
| `cancel(chainId)` | Cancel chain |
| `getStatus(chainId)` | Get chain status |
| `isActive(chainId)` | Check if chain active |
| `onComplete(chainId, callback)` | Register completion callback |
| `stopAll()` | Stop all chains |

**Usage**:
```lua
DMS.EventChain.defineChain("sead_cascade", {
    {
        trigger = {type = "kill", target = "EWR-1"},
        actions = {
            {type = "message", text = "Radar destroyed!", duration = 10},
        },
    },
    {
        trigger = {type = "delay", seconds = 30},
        actions = {
            {type = "flag", flag = "SAM_DEGRADED", value = 1},
            {type = "spawn", pool = "QRF-Response"},
        },
    },
})

DMS.EventChain.start("sead_cascade")
```

---

### conditional-triggers.lua
**Module**: `DMS.ConditionalTrigger`

Complex boolean logic for mission triggers.

**Condition Types**: `AND`, `OR`, `NOT`, `XOR`, `variable`, `flag`, `mission_time`, `time_of_day`, `group_alive`, `group_dead`, `group_size`, `groups_alive_count`, `zone`, `zone_empty`, `player_alive`, `player_count`, `player_altitude`, `random`, `custom`, `phase`, `awareness_state`, `skill_level`

**Operators**: `==`, `!=`, `>`, `>=`, `<`, `<=`, `between`, `contains`

**Key Functions**:
| Function | Description |
|----------|-------------|
| `configure(settings)` | Set configuration options |
| `setVariable(name, value)` | Set a variable |
| `getVariable(name)` | Get a variable |
| `incrementVariable(name, amount)` | Increment variable |
| `define(triggerId, conditions, actions, options)` | Define trigger |
| `evaluate(triggerId)` | Manually evaluate |
| `enable(triggerId)` | Enable trigger |
| `disable(triggerId)` | Disable trigger |
| `reset(triggerId)` | Reset fired trigger |
| `start()` | Begin trigger processing |
| `stop()` | Stop trigger processing |

**Usage**:
```lua
DMS.ConditionalTrigger.setVariable("player_kills", 0)

DMS.ConditionalTrigger.define("reinforcements", {
    type = "AND",
    conditions = {
        {type = "variable", name = "player_kills", operator = ">=", value = 5},
        {type = "mission_time", operator = ">=", seconds = 300},
        {
            type = "OR",
            conditions = {
                {type = "group_dead", group = "SAM-Site-1"},
                {type = "zone", zone = "DEEP_STRIKE", occupied = true},
            },
        },
    },
}, {
    {type = "message", text = "Reinforcements inbound!", duration = 10},
    {type = "spawn", pool = "reinforcements"},
})

DMS.ConditionalTrigger.start()
```

---

### reinforcement-waves.lua
**Module**: `DMS.ReinforcementWaves`

Triggered reinforcement spawning.

**Key Functions**:
| Function | Description |
|----------|-------------|
| `configure(settings)` | Set configuration options |
| `defineWave(waveId, groups, options)` | Define reinforcement wave |
| `triggerWave(waveId)` | Trigger specific wave |
| `triggerNextWave()` | Trigger next wave in sequence |

---

### alarm-system.lua
**Module**: `DMS.AlarmSystem`

Zone-based alert propagation.

**Key Functions**:
| Function | Description |
|----------|-------------|
| `configure(settings)` | Set configuration options |
| `registerZone(zoneName, alertLevel)` | Register alarm zone |
| `triggerAlarm(zoneName)` | Trigger zone alarm |
| `start()` | Begin alarm monitoring |

---

### kill-chain-reaction.lua
**Module**: `DMS.KillChain`

Cascade effects when targets are destroyed.

**Key Functions**:
| Function | Description |
|----------|-------------|
| `configure(settings)` | Set configuration options |
| `register(targetGroup, effects)` | Register kill effects |
| `start()` | Begin kill chain monitoring |

---

### narrative-events.lua
**Module**: `DMS.NarrativeEvents`

Scripted story moments.

**Key Functions**:
| Function | Description |
|----------|-------------|
| `configure(settings)` | Set configuration options |
| `addEvent(eventId, options)` | Add narrative event |
| `triggerEvent(eventId)` | Trigger event |
| `start()` | Begin narrative system |

---

### objective-tracker.lua
**Module**: `DMS.Objectives`

Mission objective management.

**Key Functions**:
| Function | Description |
|----------|-------------|
| `configure(settings)` | Set configuration options |
| `addObjective(objId, description, options)` | Add objective |
| `completeObjective(objId)` | Mark objective complete |
| `failObjective(objId)` | Mark objective failed |
| `getStatusReport()` | Get objectives summary |
| `start()` | Begin objective tracking |

---

## Mission State

Systems for tracking mission state and progress.

### phase-manager.lua
**Module**: `DMS.PhaseManager`

Mission phase state machine with automatic transitions.

**Key Functions**:
| Function | Description |
|----------|-------------|
| `configure(settings)` | Set configuration options |
| `definePhase(phaseId, options)` | Define a mission phase |
| `addTransition(fromPhase, toPhase, conditions)` | Add phase transition |
| `start(initialPhase)` | Start phase manager |
| `stop()` | Stop phase manager |
| `transitionTo(phaseId, reason)` | Manual transition |
| `forceTransition(phaseId)` | Force phase change |
| `getCurrentPhase()` | Get current phase ID |
| `getPhaseInfo(phaseId)` | Get phase details |
| `onPhaseEnter(phaseId, callback)` | Register enter callback |
| `onPhaseExit(phaseId, callback)` | Register exit callback |
| `defineStandardPhases()` | Define standard phases |

**Transition Condition Types**: `zone`, `zone_exit`, `group_dead`, `group_alive`, `groups_dead`, `flag`, `time`, `time_less`, `objectives`, `any_objective`, `custom`, `AND`, `OR`, `NOT`

**Phase Options**:
- `name` - Display name
- `briefing` - Briefing text
- `duration` - Max duration (timeout)
- `timeoutPhase` - Phase on timeout
- `onEnter` - Function on phase enter
- `onExit` - Function on phase exit
- `flags` - Flags to set on enter

**Usage**:
```lua
DMS.PhaseManager.definePhase("INGRESS", {
    name = "Ingress",
    briefing = "Proceed to target area.",
    onEnter = function() DMS.RandomSpawn.start() end,
})

DMS.PhaseManager.definePhase("ATTACK", {
    name = "Attack",
    briefing = "Engage all targets.",
    duration = 1800,
    timeoutPhase = "EGRESS",
})

DMS.PhaseManager.addTransition("INGRESS", "ATTACK", {
    type = "zone",
    zone = "TARGET_ZONE",
})

DMS.PhaseManager.addTransition("ATTACK", "EGRESS", {
    type = "objectives",
    required = {"OBJ_1", "OBJ_2"},
})

DMS.PhaseManager.start("INGRESS")
```

---

### score-tracker.lua
**Module**: `DMS.ScoreTracker`

Player scoring system.

**Key Functions**:
| Function | Description |
|----------|-------------|
| `configure(settings)` | Set configuration options |
| `addPoints(amount, reason)` | Add to score |
| `subtractPoints(amount, reason)` | Subtract from score |
| `getScore()` | Get current score |
| `start()` | Begin score tracking |

---

### mission-timer.lua
**Module**: `DMS.MissionTimer`

Countdown and stopwatch timers.

**Key Functions**:
| Function | Description |
|----------|-------------|
| `configure(settings)` | Set configuration options |
| `startCountdown(seconds, onComplete)` | Start countdown |
| `startStopwatch()` | Start stopwatch |
| `pause()` | Pause timer |
| `resume()` | Resume timer |
| `getRemaining()` | Get remaining time |
| `getElapsed()` | Get elapsed time |

---

### victory-conditions.lua
**Module**: `DMS.VictoryConditions`

Win/lose condition tracking.

**Key Functions**:
| Function | Description |
|----------|-------------|
| `configure(settings)` | Set configuration options |
| `addWinCondition(condId, check)` | Add win condition |
| `addLoseCondition(condId, check)` | Add lose condition |
| `checkVictory()` | Check all conditions |
| `start()` | Begin condition monitoring |

---

### persistence-lite.lua
**Module**: `DMS.Persistence`

Save/load mission state.

**Key Functions**:
| Function | Description |
|----------|-------------|
| `configure(settings)` | Set configuration options |
| `save(key, value)` | Save value |
| `load(key, default)` | Load value |
| `saveState()` | Save full state |
| `loadState()` | Load full state |

---

### stats-collector.lua
**Module**: `DMS.StatsCollector`

Comprehensive mission statistics.

**Key Functions**:
| Function | Description |
|----------|-------------|
| `configure(settings)` | Set configuration options |
| `start()` | Begin stats collection |
| `getStats()` | Get all statistics |
| `getReport()` | Get formatted report |

---

## Player Support

Features to assist players during missions.

### command-menu.lua
**Module**: `DMS.CommandMenu`

F10 radio menu builder.

**Key Functions**:
| Function | Description |
|----------|-------------|
| `configure(settings)` | Set configuration options |
| `createRootMenu()` | Create root menu |
| `addMenu(menuId, menuName, parentId)` | Add submenu |
| `addCommand(cmdId, cmdName, menuId, callback, options)` | Add command |
| `removeCommand(commandId)` | Remove command |
| `removeMenu(menuId)` | Remove menu |
| `addStandardMenus()` | Add support/status/tactical menus |
| `addSupportMenu()` | Add support request menu |
| `addStatusMenu()` | Add mission status menu |
| `addTacticalMenu()` | Add tactical options menu |
| `buildFromDefinition(definition)` | Build from table definition |
| `clearAll()` | Remove all menus |

**Usage**:
```lua
DMS.CommandMenu.configure({
    rootMenuName = "Mission Commands",
    showConfirmations = true,
})

DMS.CommandMenu.addStandardMenus()

-- Custom menu
DMS.CommandMenu.addMenu("custom", "Special Commands")
DMS.CommandMenu.addCommand("call_extract", "Call Extraction", "custom", function()
    -- Spawn extraction helicopter
end, {confirmation = "Extraction requested", cooldown = 300})
```

---

### support-requests.lua
**Module**: `DMS.SupportRequests`

Player can call in support assets via F10 menu.

**Support Types**: `ARTILLERY`, `MORTAR`, `SMOKE`, `ILLUMINATION`, `MEDEVAC`, `SEAD`, `CAS`, `RESUPPLY`

**Key Functions**:
| Function | Description |
|----------|-------------|
| `configure(settings)` | Set configuration options |
| `registerAsset(assetId, assetType, groupName, options)` | Register support asset |
| `requestArtillery(targetPos, options)` | Request artillery strike |
| `requestSmoke(pos, color)` | Request smoke marker |
| `requestIllumination(pos)` | Request illumination flare |
| `requestMEDEVAC(pos, options)` | Request medical evacuation |
| `requestSEAD(targetArea, options)` | Request SEAD support |
| `requestCAS(targetArea, options)` | Request close air support |
| `requestResupply(pos, options)` | Request resupply drop |
| `buildMenu()` | Build F10 menu |
| `getAssetStatus(assetId)` | Get asset availability |
| `start()` | Initialize and build menu |

**Usage**:
```lua
DMS.SupportRequests.configure({
    artilleryDelay = 45,
    artilleryRounds = 6,
})

DMS.SupportRequests.registerAsset("battery_1", DMS.SupportRequests.TYPES.ARTILLERY, nil, {
    cooldown = 180,
    maxUses = 5,
})

DMS.SupportRequests.registerAsset("dustoff", DMS.SupportRequests.TYPES.MEDEVAC, "MEDEVAC-1", {
    cooldown = 300,
})

DMS.SupportRequests.start()
```

---

### fuel-monitor.lua
**Module**: `DMS.FuelMonitor`

Fuel state warnings.

**Key Functions**:
| Function | Description |
|----------|-------------|
| `configure(settings)` | Set configuration options |
| `setBingo(percent)` | Set bingo fuel level |
| `setJoker(percent)` | Set joker fuel level |
| `start()` | Begin fuel monitoring |

---

### damage-reporter.lua
**Module**: `DMS.DamageReporter`

Aircraft damage status reporting.

**Key Functions**:
| Function | Description |
|----------|-------------|
| `configure(settings)` | Set configuration options |
| `start()` | Begin damage monitoring |
| `getStatus()` | Get damage status |

---

### rescue-coordination.lua
**Module**: `DMS.RescueCoordination`

CSAR for ejected pilots.

**Key Functions**:
| Function | Description |
|----------|-------------|
| `configure(settings)` | Set configuration options |
| `registerRescueAsset(assetId, groupName)` | Register rescue helicopter |
| `start()` | Begin CSAR monitoring |
| `requestRescue(pilotPos)` | Request rescue at position |

---

### waypoint-helper.lua
**Module**: `DMS.WaypointHelper`

Navigation assistance.

**Key Functions**:
| Function | Description |
|----------|-------------|
| `configure(settings)` | Set configuration options |
| `getDistanceToWaypoint(waypointNum)` | Get distance to waypoint |
| `getBearingToWaypoint(waypointNum)` | Get bearing to waypoint |
| `announceNextWaypoint()` | Announce next waypoint info |

---

## Environment

Atmosphere and environment effects.

### time-of-day-effects.lua
**Module**: `DMS.TimeOfDay`

Time-based gameplay changes.

**Key Functions**:
| Function | Description |
|----------|-------------|
| `configure(settings)` | Set configuration options |
| `registerEffect(timeRange, effect)` | Register time-based effect |
| `start()` | Begin time monitoring |
| `getCurrentPeriod()` | Get current time period |

---

### weather-impact.lua
**Module**: `DMS.WeatherImpact`

Weather operational effects.

**Key Functions**:
| Function | Description |
|----------|-------------|
| `configure(settings)` | Set configuration options |
| `getVisibility()` | Get current visibility |
| `getWeatherPenalty()` | Get detection penalty |
| `start()` | Begin weather monitoring |

---

### ambient-traffic.lua
**Module**: `DMS.AmbientTraffic`

Non-combat AI for immersion.

**Key Functions**:
| Function | Description |
|----------|-------------|
| `configure(settings)` | Set configuration options |
| `addRoute(routeId, waypoints)` | Add traffic route |
| `spawnTraffic(routeId, unitType)` | Spawn traffic on route |
| `start()` | Begin ambient traffic |

---

### decoy-system.lua
**Module**: `DMS.DecoySystem`

Fake targets and deception.

**Key Functions**:
| Function | Description |
|----------|-------------|
| `configure(settings)` | Set configuration options |
| `createDecoy(position, type)` | Create decoy at position |
| `registerDecoyGroup(groupName)` | Register as decoy |
| `start()` | Begin decoy system |

---

## Version Information

- **Library Version**: 2.0
- **DCS Compatibility**: 2.8+
- **Lua Version**: 5.1 (DCS embedded)
- **Total Scripts**: 57
