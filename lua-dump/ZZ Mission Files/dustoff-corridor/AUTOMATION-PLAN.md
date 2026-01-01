# Dustoff Corridor - Dynamic Spawn Mission Setup

## Philosophy

**User places ONLY zones and player/convoy. Lua spawns all enemies dynamically.**

With the new `DMS.UnitTemplates` and `DMS.DynamicSpawn` systems, mission creation is dramatically simplified:

| Old Approach | New Approach |
|--------------|--------------|
| Place ~35 enemy groups in ME | Place 5 zones in ME |
| Name each group correctly | Just name zones |
| Set LATE ACTIVATION on each | No LATE ACTIVATION needed |
| ~2 hours of ME work | ~15 minutes of ME work |

---

## What User Places (Mission Editor)

### Required Elements (7 items total)

| Element | Name | Notes |
|---------|------|-------|
| Player Aircraft | Any | AH-64D, Client slot |
| Convoy Group | `Convoy-Main` | Trucks + escorts with route |
| Zone | `Alpha-Zone` | Trigger zone ~800m radius |
| Zone | `Bravo-Zone` | Trigger zone ~1000m radius |
| Zone | `Charlie-Zone` | Trigger zone ~800m radius |
| Zone | `QRF-Staging` | Where reinforcements spawn |
| Zone | `FOB-Victory` | Convoy destination |

**That's it.** No enemy groups to place.

---

## Script Load Order

Create DO SCRIPT FILE triggers at mission start:

| # | Script Path | Description |
|---|-------------|-------------|
| 1 | `lua-dump/utils/mission-settings.lua` | Core settings |
| 2 | `lua-dump/utils/fog-of-war.lua` | F10 map hiding |
| 3 | `lua-dump/comms/audio-player.lua` | Audio playback system |
| 4 | `lua-dump/spawners/unit-templates.lua` | Unit dictionary |
| 5 | `lua-dump/spawners/dynamic-spawn.lua` | Zone spawner |
| 6 | `lua-dump/ai-behavior/sam-ambush.lua` | SAM behavior |
| 7 | `lua-dump/events/reinforcement-waves.lua` | QRF system |
| 8 | `ZZ Mission Files/dustoff-corridor/init.lua` | Mission config |

### Audio via ME Triggers (Flag-Based)

Lua sets numeric flags that you can use in Mission Editor to trigger audio:

| Flag # | Name | When Set | Suggested Audio |
|--------|------|----------|-----------------|
| 100 | Mission Start | Mission begins | `good hunting.wav` |
| 101 | Mission Victory | Convoy reaches FOB | `Mission Success.wav` |
| 102 | Mission Defeat | Convoy destroyed / player killed | (optional) |

**ME Trigger Setup:**
1. Create trigger: `FLAG IS TRUE` → Flag 101
2. Action: `SOUND TO COALITION` → Blue → `Mission Success.wav`

**Available audio in `DMS/mission assets/audio/`:**
- `generic/mission start/` - mission is a go.wav, stay sharp.wav, good hunting.wav
- `generic/mission complete/` - Obj complete.wav, Mission Success.wav
- `generic/ground troops/` - Good Kill.wav, Keep em coming.wav

---

## Win / Loss Conditions

| Condition | Trigger | Flag # | Text Message |
|-----------|---------|--------|--------------|
| **VICTORY** | Any convoy vehicle reaches `FOB-Victory` zone | 101 | Shows survivor count |
| **DEFEAT** | All convoy vehicles destroyed | 102 | "Convoy has been destroyed" |
| **DEFEAT** | Player crashes/ejects/killed | 102 | "Dustoff is down" |

### Condition Monitoring

- **Victory check**: Every 10 seconds, checks convoy position vs FOB-Victory zone
- **Convoy status**: Every 5 seconds, checks if any convoy vehicles alive
- **Player death**: Event-based, triggers on crash/eject/pilot death

### State Tracking

```lua
DMS.DustoffCorridor.State = {
    missionEnded = false,        -- Prevents double-triggers
    result = nil,                -- "victory" or "defeat"
    convoyStartCount = 0,        -- Initial vehicle count
}
```

---

## Mission Init Configuration

The `init.lua` now uses dynamic spawning:

```lua
-- ============================================
-- DUSTOFF CORRIDOR - DYNAMIC SPAWN CONFIG
-- ============================================

DMS = DMS or {}
DMS.DustoffCorridor = {}

-- ============================================
-- FLAG DEFINITIONS (for ME triggers)
-- ============================================

DMS.DustoffCorridor.Flags = {
    MISSION_START   = 100,
    MISSION_VICTORY = 101,
    MISSION_DEFEAT  = 102,
    -- Reserve 103-110 for future use
    CONVOY_HIT      = 103,
    QRF_DISPATCHED  = 104,
}

-- ============================================
-- SETTINGS
-- ============================================

-- Enable debug logging
DMS.Settings.configure({
    debug = true,
    playerCoalition = coalition.side.BLUE,
    enemyCoalition = coalition.side.RED,
    fogOfWar = true,
})

-- ============================================
-- ALPHA ZONE - Light AA + Infantry
-- ============================================

DMS.DynamicSpawn.createPool("alpha-aa", {
    zone = "Alpha-Zone",
    templates = {"zu23_truck", "zu23_technical", "manpads_team", "manpads_single"},
    chance = 70,
    count = 2,
    minDistance = 200,
    maxDistance = 700,
    heading = "center",
})

DMS.DynamicSpawn.createPool("alpha-ground", {
    zone = "Alpha-Zone",
    templates = {"infantry_squad", "rpg_team", "technical_mg", "mg_nest"},
    chance = 80,
    count = 2,
    minDistance = 100,
    maxDistance = 500,
})

-- ============================================
-- BRAVO ZONE - Heavy AA + Armor
-- ============================================

DMS.DynamicSpawn.createPool("bravo-aa", {
    zone = "Bravo-Zone",
    templates = {"tunguska", "shilka", "strela_section", "zu23_battery", "aa_ambush"},
    chance = 80,
    count = 2,
    minDistance = 300,
    maxDistance = 900,
})

DMS.DynamicSpawn.createPool("bravo-armor", {
    zone = "Bravo-Zone",
    templates = {"bmp_section", "btr_squad", "t72_single", "checkpoint"},
    chance = 70,
    count = 2,
    minDistance = 200,
    maxDistance = 800,
})

DMS.DynamicSpawn.createPool("bravo-infantry", {
    zone = "Bravo-Zone",
    templates = {"infantry_squad", "ambush_team", "rpg_team"},
    chance = 60,
    count = 1,
    minDistance = 100,
    maxDistance = 400,
})

-- ============================================
-- CHARLIE ZONE - Urban Defense
-- ============================================

DMS.DynamicSpawn.createPool("charlie-aa", {
    zone = "Charlie-Zone",
    templates = {"tunguska", "zu23_technical", "manpads_team"},
    chance = 70,
    count = 1,
    minDistance = 200,
    maxDistance = 600,
})

DMS.DynamicSpawn.createPool("charlie-defense", {
    zone = "Charlie-Zone",
    templates = {"checkpoint", "btr_squad", "mg_nest", "infantry_squad"},
    chance = 80,
    count = 2,
    minDistance = 100,
    maxDistance = 500,
})

-- ============================================
-- QRF REINFORCEMENTS
-- ============================================

DMS.DynamicSpawn.createPool("qrf-light", {
    zone = "QRF-Staging",
    templates = {"qrf_light", "technical_pair"},
    chance = 100,  -- Always available
    count = 1,
    minDistance = 50,
    maxDistance = 200,
})

DMS.DynamicSpawn.createPool("qrf-medium", {
    zone = "QRF-Staging",
    templates = {"qrf_medium", "bmp_section"},
    chance = 100,
    count = 1,
    minDistance = 50,
    maxDistance = 200,
})

DMS.DynamicSpawn.createPool("qrf-heavy", {
    zone = "QRF-Staging",
    templates = {"qrf_heavy", "t72_platoon"},
    chance = 100,
    count = 1,
    minDistance = 50,
    maxDistance = 200,
})

-- ============================================
-- START FUNCTION
-- ============================================

function DMS.DustoffCorridor.start()
    -- Set flag for ME audio trigger
    trigger.action.setUserFlag(DMS.DustoffCorridor.Flags.MISSION_START, true)

    -- Execute initial spawn pools
    DMS.DynamicSpawn.executePool("alpha-aa")
    DMS.DynamicSpawn.executePool("alpha-ground")
    DMS.DynamicSpawn.executePool("bravo-aa")
    DMS.DynamicSpawn.executePool("bravo-armor")
    DMS.DynamicSpawn.executePool("bravo-infantry")
    DMS.DynamicSpawn.executePool("charlie-aa")
    DMS.DynamicSpawn.executePool("charlie-defense")

    -- QRF pools are NOT executed at start - triggered later

    -- ============================================
    -- AI TASKING - Configure unit behaviors
    -- ============================================

    -- AA units: Ambush posture (stationary, high alert, weapons free)
    DMS.DynamicSpawn.setAmbushPools({"alpha-aa", "bravo-aa", "charlie-aa"})

    -- Armor units: Hunt the convoy (staggered attacks)
    DMS.DynamicSpawn.huntConvoy(
        {"bravo-armor"},           -- Pools to assign hunting
        "Convoy-Main",             -- Target convoy name
        {delay = 120, staggerDelay = 60}  -- 2min delay, then attack every 60s
    )

    -- Ground units: Ambush posture (engage if convoy passes nearby)
    DMS.DynamicSpawn.setAmbushPools({"alpha-ground", "bravo-infantry", "charlie-defense"})

    -- Register spawned AA groups with SAM Ambush system
    local aaGroups = {}
    for _, poolId in ipairs({"alpha-aa", "bravo-aa", "charlie-aa"}) do
        for _, groupName in ipairs(DMS.DynamicSpawn.getPoolGroups(poolId)) do
            table.insert(aaGroups, groupName)
        end
    end

    for _, groupName in ipairs(aaGroups) do
        DMS.SAMAmbush.register(groupName, {
            activationRange = 8000,
            fireChance = 80,
        })
    end

    -- Start fog of war
    DMS.FogOfWar.start()

    -- Display briefing (after audio delay)
    timer.scheduleFunction(function()
        trigger.action.outTextForCoalition(coalition.side.BLUE,
            "DUSTOFF CORRIDOR\n\n" ..
            "Escort convoy through hostile territory.\n" ..
            "Expect AA threats in all sectors.\n\n" ..
            "Good hunting.",
            20
        )
        return nil
    end, nil, timer.getTime() + 3)

    env.info("[DUSTOFF] Mission started - enemies spawned dynamically")
end

-- ============================================
-- WIN / LOSS CONDITIONS
-- ============================================

DMS.DustoffCorridor.State = {
    missionEnded = false,
    result = nil,  -- "victory", "defeat"
    convoyStartCount = 0,
    convoyDestroyedCount = 0,
}

-- Count initial convoy vehicles
function DMS.DustoffCorridor.initConvoyTracking()
    local convoy = Group.getByName("Convoy-Main")
    if convoy then
        local units = convoy:getUnits()
        if units then
            DMS.DustoffCorridor.State.convoyStartCount = #units
        end
    end
    env.info(string.format("[DUSTOFF] Tracking %d convoy vehicles",
        DMS.DustoffCorridor.State.convoyStartCount))
end

-- ============================================
-- VICTORY: Convoy reaches FOB-Victory
-- ============================================

function DMS.DustoffCorridor.checkVictory()
    if DMS.DustoffCorridor.State.missionEnded then return end

    local convoy = Group.getByName("Convoy-Main")
    if not convoy then return timer.getTime() + 10 end

    local zone = trigger.misc.getZone("FOB-Victory")
    if not zone then return timer.getTime() + 10 end

    local units = convoy:getUnits()
    if not units then return timer.getTime() + 10 end

    for _, unit in ipairs(units) do
        if unit and unit:isExist() then
            local pos = unit:getPoint()
            local dx = pos.x - zone.point.x
            local dy = pos.z - zone.point.z
            local dist = math.sqrt(dx*dx + dy*dy)

            if dist < zone.radius then
                DMS.DustoffCorridor.onVictory()
                return  -- Stop checking
            end
        end
    end

    return timer.getTime() + 10  -- Keep checking
end

function DMS.DustoffCorridor.onVictory()
    if DMS.DustoffCorridor.State.missionEnded then return end
    DMS.DustoffCorridor.State.missionEnded = true
    DMS.DustoffCorridor.State.result = "victory"

    -- Count survivors
    local survivors = 0
    local convoy = Group.getByName("Convoy-Main")
    if convoy then
        local units = convoy:getUnits()
        if units then
            for _, unit in ipairs(units) do
                if unit and unit:isExist() then
                    survivors = survivors + 1
                end
            end
        end
    end

    -- Set flag for ME audio trigger
    trigger.action.setUserFlag(DMS.DustoffCorridor.Flags.MISSION_VICTORY, true)

    -- Display victory message
    local startCount = DMS.DustoffCorridor.State.convoyStartCount
    trigger.action.outTextForCoalition(coalition.side.BLUE,
        "MISSION COMPLETE\n\n" ..
        string.format("Convoy reached FOB Victory.\n") ..
        string.format("Survivors: %d/%d vehicles\n\n", survivors, startCount) ..
        "Outstanding work, Dustoff.",
        30
    )

    env.info(string.format("[DUSTOFF] VICTORY - %d/%d convoy survived", survivors, startCount))
end

-- ============================================
-- DEFEAT: Convoy destroyed
-- ============================================

function DMS.DustoffCorridor.checkConvoyDestroyed()
    if DMS.DustoffCorridor.State.missionEnded then return end

    local convoy = Group.getByName("Convoy-Main")

    -- Group doesn't exist or has no living units
    if not convoy then
        DMS.DustoffCorridor.onDefeat("convoy_destroyed")
        return
    end

    local units = convoy:getUnits()
    if not units or #units == 0 then
        DMS.DustoffCorridor.onDefeat("convoy_destroyed")
        return
    end

    -- Check if any unit is still alive
    local aliveCount = 0
    for _, unit in ipairs(units) do
        if unit and unit:isExist() and unit:getLife() > 1 then
            aliveCount = aliveCount + 1
        end
    end

    if aliveCount == 0 then
        DMS.DustoffCorridor.onDefeat("convoy_destroyed")
        return
    end

    return timer.getTime() + 5  -- Check more frequently
end

-- ============================================
-- DEFEAT: Player killed
-- ============================================

function DMS.DustoffCorridor.setupPlayerDeathHandler()
    world.addEventHandler({
        onEvent = function(self, event)
            if DMS.DustoffCorridor.State.missionEnded then return end

            -- Player crash or eject
            if event.id == world.event.S_EVENT_CRASH or
               event.id == world.event.S_EVENT_EJECTION or
               event.id == world.event.S_EVENT_PILOT_DEAD then

                if event.initiator then
                    local group = event.initiator:getGroup()
                    if group then
                        -- Check if it's a player group (client slot)
                        local controller = group:getController()
                        if controller then
                            -- Small delay to confirm death
                            timer.scheduleFunction(function()
                                DMS.DustoffCorridor.onDefeat("player_killed")
                                return nil
                            end, nil, timer.getTime() + 3)
                        end
                    end
                end
            end
        end
    })
end

-- ============================================
-- DEFEAT HANDLER
-- ============================================

function DMS.DustoffCorridor.onDefeat(reason)
    if DMS.DustoffCorridor.State.missionEnded then return end
    DMS.DustoffCorridor.State.missionEnded = true
    DMS.DustoffCorridor.State.result = "defeat"

    -- Set flag for ME audio trigger
    trigger.action.setUserFlag(DMS.DustoffCorridor.Flags.MISSION_DEFEAT, true)

    local message = "MISSION FAILED\n\n"

    if reason == "convoy_destroyed" then
        message = message .. "The convoy has been destroyed.\n"
        message = message .. "All vehicles lost.\n\n"
        message = message .. "The enemy controls this corridor."
    elseif reason == "player_killed" then
        message = message .. "Dustoff is down.\n"
        message = message .. "Convoy left without air support.\n\n"
        message = message .. "Mission aborted."
    else
        message = message .. "Objective failed."
    end

    trigger.action.outTextForCoalition(coalition.side.BLUE, message, 30)

    env.info(string.format("[DUSTOFF] DEFEAT - reason: %s", reason))
end

-- ============================================
-- START CONDITION MONITORING
-- ============================================

function DMS.DustoffCorridor.startConditionMonitoring()
    -- Initialize convoy tracking
    DMS.DustoffCorridor.initConvoyTracking()

    -- Setup player death handler
    DMS.DustoffCorridor.setupPlayerDeathHandler()

    -- Start victory check (every 10s)
    timer.scheduleFunction(DMS.DustoffCorridor.checkVictory, nil, timer.getTime() + 30)

    -- Start convoy destroyed check (every 5s)
    timer.scheduleFunction(DMS.DustoffCorridor.checkConvoyDestroyed, nil, timer.getTime() + 30)

    env.info("[DUSTOFF] Win/loss condition monitoring started")
end

-- Call this after mission start
timer.scheduleFunction(function()
    DMS.DustoffCorridor.startConditionMonitoring()
    return nil
end, nil, timer.getTime() + 10)
```

---

## Available Templates

### AA Templates
| Name | Units | Threat |
|------|-------|--------|
| `tunguska` | 1x 2S6 Tunguska | HIGH |
| `tunguska_pair` | 2x 2S6 Tunguska | VERY HIGH |
| `shilka` | 1x ZSU-23-4 Shilka | MEDIUM |
| `strela_section` | 2x Strela-10 | MEDIUM |
| `zu23_truck` | 1x Ural with ZU-23 | MEDIUM |
| `zu23_technical` | 1x Technical with ZU-23 | MEDIUM |
| `zu23_battery` | 2x Ural with ZU-23 | MEDIUM |
| `manpads_team` | 2x Igla MANPADS | HIGH |
| `manpads_single` | 1x Igla MANPADS | MEDIUM |
| `aa_ambush` | ZU-23 + 2x MANPADS | HIGH |

### Armor Templates
| Name | Units | Threat |
|------|-------|--------|
| `t72_platoon` | 2x T-72B3 | HIGH |
| `t72_single` | 1x T-72B3 | MEDIUM |
| `bmp_section` | 2x BMP-2 | MEDIUM |
| `btr_squad` | 3x BTR-80 | LOW |
| `recon_patrol` | 1x BRDM-2 | LOW |

### Infantry/Technical Templates
| Name | Units | Threat |
|------|-------|--------|
| `infantry_squad` | 3x AK + 1x RPG | LOW |
| `infantry_fireteam` | 3x AK | LOW |
| `rpg_team` | 2x RPG | MEDIUM |
| `mg_nest` | KORD HMG + AK | LOW |
| `technical_mg` | 1x Technical KORD | LOW |
| `technical_pair` | 2x Technical KORD | LOW |
| `technical_aa_mg` | ZU-23 + KORD technical | MEDIUM |

### Mixed/QRF Templates
| Name | Units | Threat |
|------|-------|--------|
| `checkpoint` | BTR + 3x Infantry | MEDIUM |
| `ambush_team` | 2x RPG + MANPADS | MEDIUM |
| `convoy_escort` | 2x BTR + 2x Trucks | LOW |
| `qrf_light` | 2x Technicals | LOW |
| `qrf_medium` | BMP + BTR | MEDIUM |
| `qrf_heavy` | T-72 + BMP | HIGH |

---

## Replayability

Each playthrough is unique because:

| System | Randomization |
|--------|---------------|
| Pool Chance | 60-80% per pool - some won't spawn |
| Template Selection | Random 1-2 from 3-5 options |
| Position | Random distance/angle from zone center |
| Heading | Facing zone center (ambush posture) |
| **Unit Skill** | Random skill per unit (Rookie → Excellent) |

**Estimated unique combinations:** 50,000+ different threat layouts

### Skill Randomization

All templates use `skill = "Random"` by default. DCS assigns one of:
- **Rookie** - Poor accuracy, slow reactions
- **Average** - Standard performance
- **Good** - Above average
- **High** - Skilled operators
- **Excellent** - Elite crews

This means the same Tunguska might be crewed by rookies (easy) or veterans (deadly).

---

## Workflow Summary

### User (15 minutes)
1. Create new mission
2. Place player aircraft
3. Place convoy with route
4. Create 5 trigger zones
5. Add DO SCRIPT FILE triggers
6. Save

### Lua (Automatic)
1. Load templates and spawner
2. Execute spawn pools on mission start
3. Position enemies randomly around zones
4. Register with SAM ambush / fog of war
5. Handle QRF reinforcements on events

---

## Extending the System

### Custom Group Builder API

You're not limited to predefined templates. Create any group composition at runtime:

#### Method 1: Register a Reusable Template
```lua
-- Register once, use anywhere
DMS.UnitTemplates.register("heavy_aa_site", {
    {type = "2S6 Tunguska"},
    {type = "2S6 Tunguska"},
    {type = "Strela-10M3"},
    {type = "SA-18 Igla-S manpad"},
    {type = "SA-18 Igla-S manpad"},
}, {
    displayName = "Heavy AA Site",
    description = "Layered radar + IR defense",
    category = "AA",
})

-- Now use like any built-in template
DMS.DynamicSpawn.createPool("boss-aa", {
    zone = "Boss-Zone",
    templates = {"heavy_aa_site"},  -- Your custom template
    chance = 100,
})
```

#### Method 2: Create and Spawn Directly
```lua
-- One-off custom group (no registration needed)
local customGroup = DMS.UnitTemplates.createGroup("ambush_alpha", {
    {type = "Soldier RPG"},
    {type = "Soldier RPG"},
    {type = "SA-18 Igla-S manpad"},
    {type = "HL_KORD"},
})

DMS.DynamicSpawn.spawnGroupDirect(customGroup, {x = 100000, y = 200000}, {
    heading = 180,
    formation = "vee",
})
```

#### Method 3: Quick Spawn Helper
```lua
-- Shortest way - create and spawn in one call
DMS.UnitTemplates.spawnCustom("roadblock_1", {
    {type = "BTR-80"},
    {type = "Soldier AK"},
    {type = "Soldier AK"},
    {type = "Soldier RPG"},
}, {x = 150000, y = 250000}, {heading = 90})
```

#### Method 4: Combine Existing Templates
```lua
-- Merge multiple templates into one mega-group
local superDefense = DMS.UnitTemplates.combineTemplates("super_defense", {
    "tunguska_pair",
    "manpads_team",
    "infantry_squad",
}, {
    displayName = "Combined Defense",
})

-- Register for pool use
DMS.UnitTemplates.Groups["super_defense"] = superDefense
```

### Custom Group Builder Reference

| Function | Purpose |
|----------|---------|
| `register(name, units, opts)` | Create reusable template |
| `createGroup(name, units, opts)` | Create group definition |
| `spawnCustom(name, units, pos, opts)` | Create + spawn in one call |
| `combineTemplates(name, templates, opts)` | Merge existing templates |
| `spawnGroupDirect(def, pos, opts)` | Spawn a group definition |

### Unit Array Format
```lua
{
    {type = "2S6 Tunguska"},                    -- Defaults: skill="Random"
    {type = "Soldier AK", skill = "Excellent"}, -- Override skill
    {type = "BTR-80"},
}
```

---

### Add New Zone
In your `init.lua`:
```lua
DMS.DynamicSpawn.createPool("delta-defense", {
    zone = "Delta-Zone",  -- Create this zone in ME
    templates = {"checkpoint", "infantry_squad"},
    chance = 70,
    count = 1,
})
```

### Mix Custom + Built-in Templates
```lua
-- Register your custom template
DMS.UnitTemplates.register("reinforced_checkpoint", {
    {type = "BTR-80"},
    {type = "BTR-80"},
    {type = "BMP-2"},
    {type = "Soldier AK"},
    {type = "Soldier AK"},
    {type = "Soldier RPG"},
    {type = "HL_KORD"},
})

-- Use alongside built-in templates
DMS.DynamicSpawn.createPool("charlie-defense", {
    zone = "Charlie-Zone",
    templates = {"reinforced_checkpoint", "checkpoint", "btr_squad"},
    chance = 80,
    count = 2,
})
```

### Trigger QRF on Event
```lua
-- When convoy takes fire, spawn light QRF
world.addEventHandler({
    onEvent = function(self, event)
        if event.id == world.event.S_EVENT_HIT then
            if event.target and event.target:getGroup() then
                if event.target:getGroup():getName() == "Convoy-Main" then
                    DMS.DynamicSpawn.executePool("qrf-light")
                end
            end
        end
    end
})
```

### Spawn Custom Group on Event
```lua
-- Spawn a custom ambush when player enters zone
world.addEventHandler({
    onEvent = function(self, event)
        if event.id == world.event.S_EVENT_BIRTH then
            -- Spawn custom RPG ambush near convoy route
            DMS.UnitTemplates.spawnCustom("rpg_ambush_1", {
                {type = "Soldier RPG"},
                {type = "Soldier RPG"},
                {type = "Soldier RPG"},
            }, {x = 145000, y = 267000}, {
                heading = 270,
                formation = "line",
            })
        end
    end
})
```

---

## Debug Commands

Enable debug mode to see spawn info in DCS.log:
```lua
DMS.Settings.configure({ debug = true })
```

Log entries:
```
[DynamicSpawn] Created pool 'alpha-aa' with 4 templates in zone 'Alpha-Zone'
[DynamicSpawn] Spawned 'alpha-aa-1' from template 'tunguska' at (102340, 193450)
[DynamicSpawn] Pool 'alpha-aa' executed: spawned 2 groups (rolled 45 <= 70)
```

---

## Unit Dictionary Reference

All verified unit type strings are in `unit-templates.lua`. Key units:

### AA Systems
| Type String | Description |
|-------------|-------------|
| `2S6 Tunguska` | Gun/missile SPAAG, deadly to helos |
| `ZSU-23-4 Shilka` | Quad 23mm radar AAA |
| `Strela-10M3` | IR SAM on MT-LB |
| `Ural-375 ZU-23` | ZU-23 on Ural truck |
| `tt_ZU-23` | ZU-23 on technical |
| `SA-18 Igla-S manpad` | Igla MANPADS |

### Armor
| Type String | Description |
|-------------|-------------|
| `T-72B3` | Modernized T-72 MBT |
| `BMP-2` | 30mm IFV + AT missile |
| `BTR-80` | 8-wheeled APC |
| `BRDM-2` | Scout car |

### Infantry
| Type String | Description |
|-------------|-------------|
| `Soldier AK` | Rifleman with AK |
| `Soldier RPG` | RPG-7 gunner |
| `Infantry AK` | Insurgent rifleman |

### Technicals
| Type String | Description |
|-------------|-------------|
| `tt_KORD` | Pickup with KORD HMG |
| `HL_KORD` | Static KORD on tripod |

---

## Files Created

```
DMS/lua-dump/
├── spawners/
│   ├── unit-templates.lua    # 35 unit types, 24 templates + custom builder
│   └── dynamic-spawn.lua     # Zone spawner + direct spawn API
│
└── ZZ Mission Files/
    └── dustoff-corridor/
        ├── AUTOMATION-PLAN.md  # This document
        └── init.lua            # Mission configuration
```

## API Quick Reference

### UnitTemplates
| Function | Description |
|----------|-------------|
| `getUnit(type)` | Get unit definition by type string |
| `getTemplate(name)` | Get predefined template |
| `listTemplates(category)` | List templates by category |
| `listUnits(category)` | List unit types by category |
| `describe(name)` | Print template info to log |
| **Custom Builder** | |
| `createGroup(name, units, opts)` | Build group definition |
| `register(name, units, opts)` | Register as reusable template |
| `spawnCustom(name, units, pos, opts)` | Create and spawn directly |
| `combineTemplates(name, templates, opts)` | Merge templates |

### DynamicSpawn
| Function | Description |
|----------|-------------|
| `createPool(id, opts)` | Register a spawn pool |
| `executePool(id)` | Execute pool (roll chance, spawn) |
| `executeAll()` | Execute all registered pools |
| `quickSpawn(zone, templates, opts)` | Create + execute in one call |
| `spawnAt(template, x, y, opts)` | Spawn template at position |
| `spawnGroupDirect(def, pos, opts)` | Spawn custom group definition |
| `getPoolGroups(id)` | Get spawned group names |
| `getAllGroups()` | Get all spawned groups |
| `isSpawned(name)` | Check if dynamically spawned |
| `getGroupInfo(name)` | Get spawn metadata |
| `resetPool(id)` | Allow re-execution |
| `removePool(id)` | Delete pool |
| `listPools()` | List all pool IDs |
| **AI Tasking** | |
| `assignAttackTask(group, target, opts)` | Order group to attack target |
| `assignHuntTask(group, point, opts)` | Move to point, engage enemies |
| `huntConvoy(poolIds, convoy, opts)` | Make pools hunt convoy |
| `setAmbush(groupName)` | Set high alert, hold position |
| `setAmbushPools(poolIds)` | Set ambush for multiple pools |

### AI Behavior Patterns

| Behavior | Function | Use Case |
|----------|----------|----------|
| **Ambush** | `setAmbush()` | AA units, infantry - hold position, engage when in range |
| **Hunt** | `huntConvoy()` | Armor, QRF - actively pursue and attack convoy |
| **Attack** | `assignAttackTask()` | Direct attack on specific group |
| **Patrol** | `assignHuntTask()` | Move to area, engage en route |

### Example: Staggered QRF Response
```lua
-- When convoy is hit, QRF responds in waves
world.addEventHandler({
    onEvent = function(self, event)
        if event.id == world.event.S_EVENT_HIT then
            if event.target and event.target:getGroup() then
                if event.target:getGroup():getName() == "Convoy-Main" then
                    -- Spawn and immediately hunt
                    DMS.DynamicSpawn.executePool("qrf-light")
                    DMS.DynamicSpawn.huntConvoy({"qrf-light"}, "Convoy-Main", {
                        staggerDelay = 15
                    })
                end
            end
        end
    end
})
```
