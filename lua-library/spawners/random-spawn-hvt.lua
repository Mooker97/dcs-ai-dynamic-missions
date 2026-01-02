-- Random HVT Spawn System for DCS Missions
-- Rare timed spawns with flag triggers for special targets
-- Supports flags on spawn AND on kill
-- Place in mission via DO SCRIPT FILE

DMS = DMS or {}
DMS.HVTSpawn = {}

-- Registered HVT targets
DMS.HVTSpawn.Targets = {}
DMS.HVTSpawn.SpawnedTargets = {}
DMS.HVTSpawn.KilledTargets = {}

-- Track group names to HVT IDs for kill detection
DMS.HVTSpawn.GroupToHVT = {}

-- Configuration
DMS.HVTSpawn.Config = {
    defaultChance = 10,      -- Default spawn chance (rare)
    defaultMinTime = 600,    -- Default 10 min minimum
    defaultMaxTime = 900,    -- Default 15 min maximum
    announceSpawns = false,  -- Announce HVT spawns to players
    announceKills = false,   -- Announce HVT kills to players
    playerCoalition = coalition.side.BLUE,
}

-- Event handler for tracking HVT kills (internal, will be wrapped)
DMS.HVTSpawn._EventHandlerInternal = {
    onEvent = function(self, event)
        -- Check for unit death events
        if event.id == world.event.S_EVENT_DEAD or
           event.id == world.event.S_EVENT_UNIT_LOST then

            local unit = event.initiator
            if not unit then return end

            local group = unit:getGroup()
            if not group then return end

            local groupName = group:getName()
            local hvtId = DMS.HVTSpawn.GroupToHVT[groupName]

            if hvtId then
                -- Check if group is fully destroyed (all units dead)
                local allDead = true
                local units = group:getUnits()
                if units then
                    for _, u in ipairs(units) do
                        if u and u:isExist() and u:getLife() > 1 then
                            allDead = false
                            break
                        end
                    end
                end

                if allDead then
                    DMS.HVTSpawn.onHVTKilled(hvtId)
                end
            end
        end
    end
}

--- Handle HVT kill event
-- @param hvtId string HVT identifier
function DMS.HVTSpawn.onHVTKilled(hvtId)
    local hvt = DMS.HVTSpawn.Targets[hvtId]
    if not hvt or hvt.killed then return end

    hvt.killed = true
    table.insert(DMS.HVTSpawn.KilledTargets, hvtId)

    -- Set kill flag if configured
    if hvt.flagOnKill then
        trigger.action.setUserFlag(hvt.flagOnKill, hvt.flagOnKillValue or 1)
    end

    -- Announce kill if configured
    if DMS.HVTSpawn.Config.announceKills or hvt.killAnnouncement then
        local msg = hvt.killAnnouncement or
            string.format("CONFIRMED: High Value Target DESTROYED - %s", hvtId)

        trigger.action.outTextForCoalition(
            DMS.HVTSpawn.Config.playerCoalition,
            msg,
            15,
            true
        )
    end
end

--- Configure HVT spawn system
-- @param settings table Configuration overrides
function DMS.HVTSpawn.configure(settings)
    for key, value in pairs(settings) do
        DMS.HVTSpawn.Config[key] = value
    end
end

--- Register an HVT for potential spawning
-- @param hvtId string Unique HVT identifier
-- @param groupName string Group name (must be LATE ACTIVATION in ME)
-- @param options table|nil Spawn options
function DMS.HVTSpawn.register(hvtId, groupName, options)
    options = options or {}

    DMS.HVTSpawn.Targets[hvtId] = {
        id = hvtId,
        groupName = groupName,
        chance = options.chance or DMS.HVTSpawn.Config.defaultChance,
        minTime = options.minTime or DMS.HVTSpawn.Config.defaultMinTime,
        maxTime = options.maxTime or DMS.HVTSpawn.Config.defaultMaxTime,
        -- Spawn flags
        flag = options.flag or nil,              -- Flag to set on spawn
        flagValue = options.flagValue or 1,      -- Value to set flag to on spawn
        announcement = options.announcement,      -- Custom spawn announcement
        -- Kill flags
        flagOnKill = options.flagOnKill or nil,          -- Flag to set on kill
        flagOnKillValue = options.flagOnKillValue or 1,  -- Value to set flag to on kill
        killAnnouncement = options.killAnnouncement,      -- Custom kill announcement
        -- State tracking
        scheduled = false,
        spawned = false,
        willSpawn = false,
        killed = false,
    }

    -- Map group name to HVT ID for kill detection
    DMS.HVTSpawn.GroupToHVT[groupName] = hvtId
end

--- Start the HVT system (registers event handler)
-- Call this after registering all HVTs
function DMS.HVTSpawn.start()
    -- Wrap event handler with error protection
    DMS.HVTSpawn.EventHandler = DMS.Error.safeHandler(
        DMS.HVTSpawn._EventHandlerInternal,
        "HVTSpawn.EventHandler"
    )
    world.addEventHandler(DMS.HVTSpawn.EventHandler)
end

--- Execute spawn check for a specific HVT
-- @param hvtId string HVT identifier
-- @return table Result {scheduled, willSpawn, spawnTime}
function DMS.HVTSpawn.schedule(hvtId)
    local hvt = DMS.HVTSpawn.Targets[hvtId]
    if not hvt or hvt.scheduled then
        return {scheduled = false, willSpawn = false}
    end

    hvt.scheduled = true

    -- Roll for spawn at registration time (not at spawn time)
    local roll = math.random(1, 100)
    hvt.willSpawn = roll <= hvt.chance

    if not hvt.willSpawn then
        return {scheduled = true, willSpawn = false}
    end

    -- Calculate spawn time
    local spawnTime = math.random(hvt.minTime, hvt.maxTime)

    -- Schedule the spawn with error handling
    DMS.Error.safeSchedule(function()
        local group = Group.getByName(hvt.groupName)
        if group then
            trigger.action.activateGroup(group)
            hvt.spawned = true

            table.insert(DMS.HVTSpawn.SpawnedTargets, hvtId)

            -- Set spawn flag if configured
            if hvt.flag then
                trigger.action.setUserFlag(hvt.flag, hvt.flagValue)
            end

            -- Announce spawn if configured
            if DMS.HVTSpawn.Config.announceSpawns or hvt.announcement then
                local msg = hvt.announcement or
                    string.format("INTEL: High Value Target detected - %s", hvtId)

                trigger.action.outTextForCoalition(
                    DMS.HVTSpawn.Config.playerCoalition,
                    msg,
                    15,
                    true
                )
            end
        end
    end, spawnTime, "HVTSpawn.spawn(" .. hvtId .. ")")

    return {
        scheduled = true,
        willSpawn = true,
        spawnTime = spawnTime,
    }
end

--- Schedule all registered HVTs
-- @return table Results by HVT ID
function DMS.HVTSpawn.scheduleAll()
    local results = {}

    for hvtId, _ in pairs(DMS.HVTSpawn.Targets) do
        results[hvtId] = DMS.HVTSpawn.schedule(hvtId)
    end

    return results
end

--- Check if an HVT has spawned
-- @param hvtId string HVT identifier
-- @return boolean True if spawned
function DMS.HVTSpawn.hasSpawned(hvtId)
    local hvt = DMS.HVTSpawn.Targets[hvtId]
    return hvt and hvt.spawned
end

--- Check if an HVT has been killed
-- @param hvtId string HVT identifier
-- @return boolean True if killed
function DMS.HVTSpawn.hasBeenKilled(hvtId)
    local hvt = DMS.HVTSpawn.Targets[hvtId]
    return hvt and hvt.killed
end

--- Check if an HVT will spawn (after scheduling)
-- @param hvtId string HVT identifier
-- @return boolean True if will spawn
function DMS.HVTSpawn.willSpawn(hvtId)
    local hvt = DMS.HVTSpawn.Targets[hvtId]
    return hvt and hvt.willSpawn
end

--- Get all spawned HVT IDs
-- @return table Array of spawned HVT IDs
function DMS.HVTSpawn.getSpawned()
    return DMS.HVTSpawn.SpawnedTargets
end

--- Get all killed HVT IDs
-- @return table Array of killed HVT IDs
function DMS.HVTSpawn.getKilled()
    return DMS.HVTSpawn.KilledTargets
end

--- Get HVT status
-- @param hvtId string HVT identifier
-- @return table|nil HVT status
function DMS.HVTSpawn.getStatus(hvtId)
    local hvt = DMS.HVTSpawn.Targets[hvtId]
    if hvt then
        return {
            id = hvt.id,
            groupName = hvt.groupName,
            chance = hvt.chance,
            scheduled = hvt.scheduled,
            willSpawn = hvt.willSpawn,
            spawned = hvt.spawned,
            killed = hvt.killed,
            flag = hvt.flag,
            flagOnKill = hvt.flagOnKill,
        }
    end
    return nil
end

--- Reset an HVT for re-scheduling
-- @param hvtId string HVT identifier
function DMS.HVTSpawn.reset(hvtId)
    local hvt = DMS.HVTSpawn.Targets[hvtId]
    if hvt then
        hvt.scheduled = false
        hvt.willSpawn = false
        hvt.spawned = false
        hvt.killed = false
    end
end

--[[
USAGE EXAMPLE:

-- Configure
DMS.HVTSpawn.configure({
    announceSpawns = true,
    announceKills = true,
    playerCoalition = coalition.side.BLUE,
})

-- Register HVT targets with spawn AND kill flags
DMS.HVTSpawn.register("supply_convoy", "hvt-1", {
    chance = 10,            -- 10% chance
    minTime = 720,          -- 12 minutes
    maxTime = 840,          -- 14 minutes
    -- Spawn flags
    flag = "100",           -- Set flag 100 when spawned
    flagValue = 1,
    announcement = "INTEL: Enemy supply convoy detected moving through sector!",
    -- Kill flags
    flagOnKill = "101",     -- Set flag 101 when destroyed
    flagOnKillValue = 1,
    killAnnouncement = "BDA: Supply convoy DESTROYED. Well done!",
})

DMS.HVTSpawn.register("enemy_commander", "hvt-commander", {
    chance = 5,             -- 5% chance (very rare)
    minTime = 900,          -- 15 minutes
    maxTime = 1200,         -- 20 minutes
    flag = "hvt_commander_spawn",
    flagOnKill = "hvt_commander_killed",
    announcement = "FLASH: Enemy field commander identified! High priority target!",
    killAnnouncement = "PRIORITY: Enemy commander ELIMINATED! Outstanding work!",
})

DMS.HVTSpawn.register("weapons_cache", "hvt-cache", {
    chance = 15,            -- 15% chance
    minTime = 300,          -- 5 minutes
    maxTime = 600,          -- 10 minutes
    flag = "weapons_cache_active",
    flagOnKill = "weapons_cache_destroyed",
})

-- Start the system (registers kill event handler)
DMS.HVTSpawn.start()

-- Schedule all HVTs
local results = DMS.HVTSpawn.scheduleAll()

-- Check results
for hvtId, result in pairs(results) do
    if result.willSpawn then
        env.info(string.format("HVT %s will spawn in ~%d seconds", hvtId, result.spawnTime))
    else
        env.info(string.format("HVT %s will NOT spawn this mission", hvtId))
    end
end

-- In Mission Editor, use flag triggers:
-- Trigger: FLAG IS TRUE(100) -> Message "Supply convoy spotted..."
-- Trigger: FLAG IS TRUE(101) -> Message "Convoy destroyed, +500 points"
-- This allows radio callouts timed to HVT spawn AND kill events
]]

-- Export
_G.DMS = DMS
