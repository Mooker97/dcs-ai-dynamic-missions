-- ============================================================
-- DUSTOFF CORRIDOR - Dynamic Convoy Escort Mission
-- ============================================================
-- AH-64 Apache mission: Escort friendly convoy through contested territory
-- Every playthrough features randomized threats, positions, and timing
--
-- Required Scripts (load via DO SCRIPT FILE before this):
--   1. utils/coordinates.lua
--   2. utils/group-utils.lua
--   3. utils/timer-utils.lua
--   4. utils/messaging.lua
--   5. spawners/random-spawn-pool.lua
--   6. ai-behavior/proximity-activation.lua
--   7. ai-behavior/sam-ambush.lua
--   8. events/reinforcement-waves.lua
--   9. comms/bda-reporter.lua
--
-- Load this init.lua LAST via DO SCRIPT FILE
-- ============================================================

DMS = DMS or {}
DMS.DustoffCorridor = {}

-- ============================================================
-- MISSION CONFIGURATION
-- ============================================================
DMS.DustoffCorridor.Config = {
    playerCoalition = coalition.side.BLUE,
    enemyCoalition = coalition.side.RED,
    convoyGroupName = "Convoy-Main",

    -- Difficulty scaling (affects QRF response)
    difficultyMultiplier = 1.0,  -- 0.5 = easier, 1.5 = harder

    -- Debug mode - uses DMS.Settings.isDebug() if available, falls back to this
    debug = false,
}

-- Helper to check debug mode (prefers central settings)
local function isDebugEnabled()
    if DMS.Settings and DMS.Settings.isDebug then
        return DMS.Settings.isDebug()
    end
    return DMS.DustoffCorridor.Config.debug
end

-- Track mission state
DMS.DustoffCorridor.State = {
    playerKills = 0,
    convoyUnderFire = false,
    missionStartTime = 0,
}

-- ============================================================
-- LAYER 1: POSITION RANDOMIZATION
-- Threats are placed at multiple positions in ME
-- Pool selection gives BOTH type AND position randomization
-- ============================================================

local function setupAlphaZone()
    -- ALPHA ZONE: Light resistance, first contact
    -- Pool contains units at different positions
    -- Naming: Zone-Type-Position

    DMS.SpawnPool.create("alpha-aa", {
        chance = 60,        -- 60% chance any AA spawns
        count = 1,          -- Pick exactly 1
    })
    DMS.SpawnPool.addGroups("alpha-aa", {
        "Alpha-ZU23-Hill",      -- ZU-23 on hilltop overwatch
        "Alpha-ZU23-Road",      -- ZU-23 by roadside
        "Alpha-MANPADS-Compound", -- Igla team in compound
        "Alpha-MANPADS-Wadi",   -- Igla team in dry riverbed
    })

    DMS.SpawnPool.create("alpha-ground", {
        chance = 50,        -- 50% chance ground threat
        count = 1,          -- Pick 1
    })
    DMS.SpawnPool.addGroups("alpha-ground", {
        "Alpha-Technical-Road",     -- Technicals on road
        "Alpha-Technical-Ridge",    -- Technicals behind ridge
        "Alpha-Infantry-Compound",  -- Infantry in compound
        "Alpha-Infantry-Treeline",  -- Infantry in treeline
    })
end

local function setupBravoZone()
    -- BRAVO ZONE: Heavy resistance, main ambush area

    DMS.SpawnPool.create("bravo-aa", {
        chance = 80,        -- 80% chance (almost guaranteed)
        count = 2,          -- Pick up to 2 AA threats
    })
    DMS.SpawnPool.addGroups("bravo-aa", {
        "Bravo-Shilka-Village",     -- Shilka at village edge
        "Bravo-Shilka-Treeline",    -- Shilka in treeline
        "Bravo-Shilka-Hill",        -- Shilka on hilltop
        "Bravo-Tunguska-Road",      -- Tunguska covering road
        "Bravo-ZU23-Bridge",        -- ZU-23 at bridge
    })

    DMS.SpawnPool.create("bravo-armor", {
        chance = 70,        -- 70% chance armor
        count = 1,          -- Pick 1 armor group
    })
    DMS.SpawnPool.addGroups("bravo-armor", {
        "Bravo-BMP-Wadi",           -- BMPs in wadi/ditch
        "Bravo-BMP-Village",        -- BMPs in village
        "Bravo-BTR-Road",           -- BTRs on road
        "Bravo-BTR-Treeline",       -- BTRs in treeline
    })
end

local function setupCharlieZone()
    -- CHARLIE ZONE: Final push to destination

    DMS.SpawnPool.create("charlie-aa", {
        chance = 75,        -- 75% chance
        count = 1,          -- Pick 1-2
    })
    DMS.SpawnPool.addGroups("charlie-aa", {
        "Charlie-Shilka-Crossroads",    -- Shilka at crossroads
        "Charlie-Tunguska-Urban",       -- Tunguska in urban area
        "Charlie-ZU23-Bridge",          -- ZU-23 at final bridge
        "Charlie-MANPADS-Rooftop",      -- MANPADS on rooftop
    })

    DMS.SpawnPool.create("charlie-ground", {
        chance = 65,        -- 65% chance
        count = 1,
    })
    DMS.SpawnPool.addGroups("charlie-ground", {
        "Charlie-Infantry-Urban",       -- Infantry in buildings
        "Charlie-Technical-Road",       -- Technicals blocking road
        "Charlie-RPG-Overwatch",        -- RPG teams on overwatch
    })
end

-- ============================================================
-- LAYER 2: THREAT SELECTION (Pools configured above)
-- ============================================================

local function executePools()
    -- Execute all zone pools
    local results = {}

    results.alpha_aa = DMS.SpawnPool.executePool("alpha-aa")
    results.alpha_ground = DMS.SpawnPool.executePool("alpha-ground")
    results.bravo_aa = DMS.SpawnPool.executePool("bravo-aa")
    results.bravo_armor = DMS.SpawnPool.executePool("bravo-armor")
    results.charlie_aa = DMS.SpawnPool.executePool("charlie-aa")
    results.charlie_ground = DMS.SpawnPool.executePool("charlie-ground")

    if isDebugEnabled() then
        for zone, result in pairs(results) do
            if result.success then
                env.info(string.format("[DUSTOFF] %s: Spawned %s",
                    zone, table.concat(result.selected, ", ")))
            else
                env.info(string.format("[DUSTOFF] %s: No spawn", zone))
            end
        end
    end

    return results
end

-- ============================================================
-- LAYER 3: TIMING (Proximity, HVTs, Reinforcements)
-- ============================================================

local function setupProximityActivation()
    -- Some threats activate when convoy/player approaches
    -- These are IN ADDITION to pool spawns

    DMS.Proximity.configure({
        checkInterval = 3,
        defaultRadius = 8000,       -- 8km activation range
        announceActivations = false,
    })

    -- Register trigger zones from Mission Editor
    -- These groups only activate when player gets close
    DMS.Proximity.registerWithZone("Ambush-Alpha-Hidden", "Alpha-Ambush-Zone", 70)
    DMS.Proximity.registerWithZone("Ambush-Bravo-Hidden", "Bravo-Ambush-Zone", 60)
    DMS.Proximity.registerWithZone("Ambush-Charlie-Hidden", "Charlie-Ambush-Zone", 50)

    DMS.Proximity.start()
end


local function setupReinforcements()
    -- Enemy QRF responds to combat

    DMS.Reinforcements.configure({
        playerCoalition = coalition.side.BLUE,
        enemyCoalition = coalition.side.RED,
        announceWaves = true,
    })

    -- Wave 1: Light QRF when convoy under attack (flag-triggered)
    DMS.Reinforcements.waveOnFlag(1,
        {"QRF-Technicals-1", "QRF-Technicals-2"},
        "convoy_under_fire",
        1
    )

    -- Wave 2: Heavier response at mission midpoint
    DMS.Reinforcements.registerWave(2,
        {"QRF-Armor-1", "QRF-Infantry-1"},
        {
            condition = function()
                -- Trigger at 10 minutes if player has many kills
                local missionTime = timer.getTime() - DMS.DustoffCorridor.State.missionStartTime
                return missionTime > 600 and DMS.DustoffCorridor.State.playerKills >= 5
            end,
            delay = 30,
            announcement = "WARNING: Enemy QRF mobilizing! Multiple vehicles inbound!",
        }
    )

    -- Wave 3: Desperate response - only if doing very well
    DMS.Reinforcements.registerWave(3,
        {"QRF-Heavy-1"},
        {
            condition = function()
                return DMS.DustoffCorridor.State.playerKills >= 12
            end,
            delay = 60,
            announcement = "ALERT: Enemy deploying heavy armor in response to your success!",
        }
    )

    DMS.Reinforcements.start()
end

-- ============================================================
-- LAYER 4: BEHAVIOR (SAM Ambush, Hold Fire)
-- ============================================================

local function setupSAMBehavior()
    -- SAMs stay dark until player enters engagement envelope

    DMS.SAMAmbush.configure({
        checkInterval = 2,
        defaultEngageRadius = 12000,    -- 12km for SHORAD
        announceThreats = true,         -- "Mud spike!" warnings
        trackingCoalition = coalition.side.BLUE,
    })

    -- Register SAM sites at their positions
    -- These are the AA units from the pools that get activated
    -- We register ALL possible SAM positions - system only tracks active ones

    local samGroups = {
        -- Shilkas
        "Bravo-Shilka-Village",
        "Bravo-Shilka-Treeline",
        "Bravo-Shilka-Hill",
        "Charlie-Shilka-Crossroads",
        -- Tunguskas
        "Bravo-Tunguska-Road",
        "Charlie-Tunguska-Urban",
    }

    for _, groupName in ipairs(samGroups) do
        DMS.SAMAmbush.registerAtPosition(groupName, 10000)  -- 10km envelope
    end

    DMS.SAMAmbush.start()
end

-- ============================================================
-- LAYER 5: ENVIRONMENT
-- ============================================================

local function setupEnvironment()
    -- Random time of day is set in Mission Editor
    -- This function sets up environmental messaging

    local timeOfDay = "day"
    local currentTime = timer.getAbsTime()
    local hours = math.floor(currentTime / 3600) % 24

    if hours >= 5 and hours < 7 then
        timeOfDay = "dawn"
    elseif hours >= 7 and hours < 17 then
        timeOfDay = "day"
    elseif hours >= 17 and hours < 19 then
        timeOfDay = "dusk"
    else
        timeOfDay = "night"
    end

    DMS.DustoffCorridor.State.timeOfDay = timeOfDay

    if isDebugEnabled() then
        env.info(string.format("[DUSTOFF] Time of day: %s (hour %d)", timeOfDay, hours))
    end
end

-- ============================================================
-- EVENT TRACKING
-- ============================================================

-- Track kills for adaptive difficulty
DMS.DustoffCorridor.EventHandler = {
    onEvent = function(self, event)
        if event.id == world.event.S_EVENT_KILL then
            -- Check if player got the kill
            if event.initiator then
                local initiatorCoalition = event.initiator:getCoalition()
                if initiatorCoalition == DMS.DustoffCorridor.Config.playerCoalition then
                    DMS.DustoffCorridor.State.playerKills = DMS.DustoffCorridor.State.playerKills + 1

                    if isDebugEnabled() then
                        env.info(string.format("[DUSTOFF] Player kills: %d",
                            DMS.DustoffCorridor.State.playerKills))
                    end
                end
            end
        end

        -- Track if convoy takes fire
        if event.id == world.event.S_EVENT_HIT then
            if event.target then
                local targetGroup = event.target:getGroup()
                if targetGroup and targetGroup:getName() == DMS.DustoffCorridor.Config.convoyGroupName then
                    if not DMS.DustoffCorridor.State.convoyUnderFire then
                        DMS.DustoffCorridor.State.convoyUnderFire = true
                        trigger.action.setUserFlag("convoy_under_fire", 1)

                        trigger.action.outTextForCoalition(
                            DMS.DustoffCorridor.Config.playerCoalition,
                            "MAYDAY! Convoy is taking fire! Requesting immediate support!",
                            10,
                            true
                        )
                    end
                end
            end
        end
    end
}

-- ============================================================
-- MISSION BRIEFING
-- ============================================================

local function showBriefing()
    local briefing = [[
===============================================
       OPERATION DUSTOFF CORRIDOR
===============================================

SITUATION:
Friendly supply convoy must push through
contested territory to reach FOB Victory.
Enemy forces have established defensive
positions along the route.

MISSION:
Provide close air support and escort for
convoy "DUSTOFF" from RP ALPHA to FOB VICTORY.

THREATS:
- AAA and MANPADS along route
- Possible armor and infantry ambushes
- Intel suggests enemy QRF in area
- HVT targets may present themselves

ROUTE:
FARP → Checkpoint ALPHA → Checkpoint BRAVO
    → Checkpoint CHARLIE → FOB VICTORY

ROE: Weapons free on hostile forces.
     Protect the convoy at all costs.

===============================================
         CONVOY IS MOVING OUT - GO!
===============================================
]]

    trigger.action.outTextForCoalition(
        DMS.DustoffCorridor.Config.playerCoalition,
        briefing,
        30,
        false
    )
end

-- ============================================================
-- MISSION INITIALIZATION
-- ============================================================

function DMS.DustoffCorridor.start()
    env.info("[DUSTOFF CORRIDOR] Initializing mission...")

    -- Record start time
    DMS.DustoffCorridor.State.missionStartTime = timer.getTime()

    -- Setup all layers
    setupAlphaZone()
    setupBravoZone()
    setupCharlieZone()

    -- Execute pools (spawn random threats)
    local spawnResults = executePools()

    -- Setup remaining systems
    setupProximityActivation()
    setupReinforcements()
    setupSAMBehavior()
    setupEnvironment()

    -- Register event handler
    world.addEventHandler(DMS.DustoffCorridor.EventHandler)

    -- Show briefing after short delay
    timer.scheduleFunction(function()
        showBriefing()
        return nil
    end, nil, timer.getTime() + 5)

    env.info("[DUSTOFF CORRIDOR] Mission initialized successfully!")

    if isDebugEnabled() then
        -- Debug summary
        timer.scheduleFunction(function()
            local msg = string.format([[
[DEBUG] Dustoff Corridor Status:
- Alpha AA: %s
- Alpha Ground: %s
- Bravo AA: %s
- Bravo Armor: %s
- Charlie AA: %s
- Charlie Ground: %s
- Time: %s
]],
                spawnResults.alpha_aa.success and table.concat(spawnResults.alpha_aa.selected, ",") or "none",
                spawnResults.alpha_ground.success and table.concat(spawnResults.alpha_ground.selected, ",") or "none",
                spawnResults.bravo_aa.success and table.concat(spawnResults.bravo_aa.selected, ",") or "none",
                spawnResults.bravo_armor.success and table.concat(spawnResults.bravo_armor.selected, ",") or "none",
                spawnResults.charlie_aa.success and table.concat(spawnResults.charlie_aa.selected, ",") or "none",
                spawnResults.charlie_ground.success and table.concat(spawnResults.charlie_ground.selected, ",") or "none",
                DMS.DustoffCorridor.State.timeOfDay
            )
            trigger.action.outText(msg, 30)
            return nil
        end, nil, timer.getTime() + 10)
    end
end

-- ============================================================
-- AUTO-START
-- ============================================================
-- Uncomment the line below to auto-start when script loads
-- DMS.DustoffCorridor.start()

-- Or call manually from a Mission Start trigger:
-- DO SCRIPT: DMS.DustoffCorridor.start()

-- Export
_G.DMS = DMS
