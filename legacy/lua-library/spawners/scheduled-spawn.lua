--[[
  DMS Scheduled Spawn System
  Schedule late activation groups to spawn at random times with chance rolls

  Features:
    - Random spawn timing within configurable windows
    - Spawn chance rolls (percentage-based)
    - Multiple spawn configurations (testing vs production)
    - Callback support for post-spawn actions

  Requires:
    - spawners/spawn-core.lua

  Usage:
    -- Register a group to spawn
    DMS.ScheduledSpawn.register({
        groupName = "Enemy QRF",
        minTime = 300,          -- 5 minutes minimum
        maxTime = 600,          -- 10 minutes maximum
        spawnChance = 25,       -- 25% chance to spawn
        onSpawn = function(groupName)
            env.info("QRF spawned: " .. groupName)
        end
    })

    -- Start the scheduler
    DMS.ScheduledSpawn.start()
]]

DMS = DMS or {}
DMS.ScheduledSpawn = {}

--------------------------------------------------------------------------------
-- State
--------------------------------------------------------------------------------

local state = {
    registeredGroups = {},      -- Groups waiting to spawn
    spawnedGroups = {},          -- Groups that have spawned
    active = false,              -- System running
}

--------------------------------------------------------------------------------
-- Configuration
--------------------------------------------------------------------------------

DMS.ScheduledSpawn.Config = {
    debug = nil,                 -- nil = follow DMS.Settings.isDebug(); true/false = override
}

--------------------------------------------------------------------------------
-- Core Functions
--------------------------------------------------------------------------------

local function log(msg, level)
    level = level or "info"
    local debug = DMS.ScheduledSpawn.Config.debug
    if debug == nil then
        debug = DMS.Settings and DMS.Settings.isDebug and DMS.Settings.isDebug()
    end
    if debug or level == "warning" then
        local timestamp = timer.getTime and timer.getTime() or 0
        if level == "warning" then
            env.warning(string.format("[ScheduledSpawn %.1f] %s", timestamp, msg))
        else
            env.info(string.format("[ScheduledSpawn %.1f] %s", timestamp, msg))
        end
    end
end

--- Register a group for scheduled spawning
-- @param config table Configuration:
--   - groupName (string, required): Group name in ME (must be Late Activation)
--   - minTime (number, required): Minimum spawn time in seconds
--   - maxTime (number, required): Maximum spawn time in seconds
--   - spawnChance (number, optional): Spawn chance 0-100 (default: 100)
--   - onSpawn (function, optional): Callback when spawned: function(groupName, success)
--   - onSpawnFail (function, optional): Callback when spawn roll fails
function DMS.ScheduledSpawn.register(config)
    if not config.groupName then
        log("ERROR: groupName required for registration", "warning")
        return false
    end

    if not config.minTime or not config.maxTime then
        log("ERROR: minTime and maxTime required for " .. config.groupName, "warning")
        return false
    end

    local groupData = {
        groupName = config.groupName,
        minTime = config.minTime,
        maxTime = config.maxTime,
        spawnChance = config.spawnChance or 100,
        onSpawn = config.onSpawn,
        onSpawnFail = config.onSpawnFail,
        hidden = config.hidden,     -- Fog of war override (nil = settings default)
        scheduled = false,
        spawned = false,
    }

    table.insert(state.registeredGroups, groupData)
    log(string.format("Registered '%s' for spawn (%.0f-%.0fs, %d%% chance)",
        config.groupName, config.minTime, config.maxTime, groupData.spawnChance))

    return true
end

--- Register multiple groups with same timing and chance
-- @param groupNames table Array of group names
-- @param minTime number Minimum spawn time
-- @param maxTime number Maximum spawn time
-- @param spawnChance number Spawn chance (0-100)
-- @param onSpawn function Optional callback
function DMS.ScheduledSpawn.registerBulk(groupNames, minTime, maxTime, spawnChance, onSpawn)
    for _, groupName in ipairs(groupNames) do
        DMS.ScheduledSpawn.register({
            groupName = groupName,
            minTime = minTime,
            maxTime = maxTime,
            spawnChance = spawnChance,
            onSpawn = onSpawn,
        })
    end
end

--- Attempt to spawn a group (with chance roll)
-- @param groupData table Group data
local function attemptSpawn(groupData)
    groupData.timerId = nil
    if not state.active then
        log(string.format("'%s' spawn skipped - system stopped", groupData.groupName))
        return
    end
    if groupData.spawned then
        return
    end

    local Core = DMS.SpawnCore
    if not Core then
        log("ERROR: spawners/spawn-core.lua is not loaded", "warning")
        return
    end

    local success, roll = Core.roll(groupData.spawnChance)

    log(string.format("'%s' spawn roll: %d (need <= %d) - %s",
        groupData.groupName, roll, groupData.spawnChance,
        success and "SPAWNED" or "FAILED"))

    if success then
        local ok, activated = Core.safeCall(Core.activate,
            "ScheduledSpawn.activate(" .. groupData.groupName .. ")",
            groupData.groupName, {hidden = groupData.hidden, prefix = "ScheduledSpawn"})
        if not (ok and activated) then
            log("ERROR: Group '" .. groupData.groupName .. "' could not be activated", "warning")
        end

        groupData.spawned = true
        table.insert(state.spawnedGroups, groupData.groupName)

        -- Call spawn callback
        if groupData.onSpawn then
            Core.safeCall(groupData.onSpawn, "ScheduledSpawn.onSpawn(" .. groupData.groupName .. ")",
                groupData.groupName, ok and activated or false)
        end
    else
        if groupData.onSpawnFail then
            Core.safeCall(groupData.onSpawnFail, "ScheduledSpawn.onSpawnFail(" .. groupData.groupName .. ")",
                groupData.groupName)
        end
    end
end

--- Schedule spawn for a specific group
-- @param groupData table Group data from registration
local function scheduleSpawnForGroup(groupData)
    if groupData.scheduled or groupData.spawned then
        return
    end

    -- Calculate random spawn time
    local spawnDelay = groupData.minTime + math.random() * (groupData.maxTime - groupData.minTime)
    groupData.scheduled = true

    log(string.format("'%s' spawn scheduled in %.1fs (chance: %d%%)",
        groupData.groupName, spawnDelay, groupData.spawnChance))

    -- Schedule the (pcall-guarded) spawn attempt and remember the id for stop()
    groupData.timerId = timer.scheduleFunction(function()
        local ok, err = pcall(attemptSpawn, groupData)
        if not ok then
            if DMS.SpawnCore then
                DMS.SpawnCore.logError("ScheduledSpawn.attemptSpawn", err)
            else
                env.error("[ScheduledSpawn] attemptSpawn: " .. tostring(err))
            end
        end
        return nil
    end, nil, timer.getTime() + spawnDelay)
end

--- Start the scheduled spawn system
function DMS.ScheduledSpawn.start()
    if state.active then
        log("Already started", "warning")
        return
    end

    state.active = true
    log(string.format("Started - %d groups registered", #state.registeredGroups))

    -- Schedule all registered groups
    for _, groupData in ipairs(state.registeredGroups) do
        scheduleSpawnForGroup(groupData)
    end
end

--- Stop the spawn system (cancels all pending spawns)
function DMS.ScheduledSpawn.stop()
    state.active = false
    local cancelled = 0
    for _, groupData in ipairs(state.registeredGroups) do
        if groupData.timerId then
            pcall(timer.removeFunction, groupData.timerId)
            groupData.timerId = nil
            cancelled = cancelled + 1
        end
        -- Allow a later start() to reschedule groups that never spawned
        if not groupData.spawned then
            groupData.scheduled = false
        end
    end
    log(string.format("Stopped (%d pending spawns cancelled)", cancelled))
end

--- Check if a specific group has spawned
-- @param groupName string Group name
-- @return boolean True if spawned
function DMS.ScheduledSpawn.hasSpawned(groupName)
    for _, name in ipairs(state.spawnedGroups) do
        if name == groupName then
            return true
        end
    end
    return false
end

--- Get list of all spawned groups
-- @return table Array of spawned group names
function DMS.ScheduledSpawn.getSpawnedGroups()
    return state.spawnedGroups
end

--- Get spawn statistics
-- @return table Stats table
function DMS.ScheduledSpawn.getStats()
    local scheduled = 0
    local spawned = 0

    for _, groupData in ipairs(state.registeredGroups) do
        if groupData.scheduled then scheduled = scheduled + 1 end
        if groupData.spawned then spawned = spawned + 1 end
    end

    return {
        registered = #state.registeredGroups,
        scheduled = scheduled,
        spawned = spawned,
        active = state.active,
    }
end

--- Clear all registrations (for mission restart)
function DMS.ScheduledSpawn.clear()
    DMS.ScheduledSpawn.stop()
    state.registeredGroups = {}
    state.spawnedGroups = {}
    state.active = false
    log("Cleared all registrations")
end

--------------------------------------------------------------------------------
-- Preset Configurations
--------------------------------------------------------------------------------

--- Create a testing configuration (short time, high chance)
-- @param groupName string Group name
-- @param onSpawn function Optional callback
function DMS.ScheduledSpawn.registerTest(groupName, onSpawn)
    return DMS.ScheduledSpawn.register({
        groupName = groupName,
        minTime = 60,           -- 1 minute
        maxTime = 120,          -- 2 minutes
        spawnChance = 100,      -- 100% chance
        onSpawn = onSpawn,
    })
end

--- Create a production configuration (long time, variable chance)
-- @param groupName string Group name
-- @param spawnChance number Spawn chance (default: 25%)
-- @param onSpawn function Optional callback
function DMS.ScheduledSpawn.registerProduction(groupName, spawnChance, onSpawn)
    return DMS.ScheduledSpawn.register({
        groupName = groupName,
        minTime = 300,          -- 5 minutes
        maxTime = 600,          -- 10 minutes
        spawnChance = spawnChance or 25,
        onSpawn = onSpawn,
    })
end

--------------------------------------------------------------------------------
-- Configuration
--------------------------------------------------------------------------------

--- Configure the system
-- @param settings table Configuration overrides
function DMS.ScheduledSpawn.configure(settings)
    for key, value in pairs(settings) do
        DMS.ScheduledSpawn.Config[key] = value
    end
end

log("DMS.ScheduledSpawn loaded")

return DMS.ScheduledSpawn
