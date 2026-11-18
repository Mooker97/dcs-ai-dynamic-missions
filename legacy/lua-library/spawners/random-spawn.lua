-- Random Spawn System for DCS Missions
-- Basic percentage-based spawning at mission start
-- Requires: spawners/spawn-core.lua
-- Place in mission via DO SCRIPT FILE

DMS = DMS or {}
DMS.RandomSpawn = {}

-- Registered spawn groups
DMS.RandomSpawn.Groups = {}
DMS.RandomSpawn.Active = false
DMS.RandomSpawn.TimerId = nil

-- Configuration
DMS.RandomSpawn.Config = {
    defaultChance = 50,  -- Default spawn chance if not specified
}

--- Configure random spawn system
-- @param settings table Configuration overrides
function DMS.RandomSpawn.configure(settings)
    for key, value in pairs(settings) do
        DMS.RandomSpawn.Config[key] = value
    end
end

--- Register a group for random spawning
-- @param groupName string Group name (must be LATE ACTIVATION in ME)
-- @param spawnChance number|nil Percentage chance to spawn (1-100)
-- @param hidden boolean|nil Fog of war override (nil = settings default)
function DMS.RandomSpawn.register(groupName, spawnChance, hidden)
    table.insert(DMS.RandomSpawn.Groups, {
        name = groupName,
        chance = spawnChance or DMS.RandomSpawn.Config.defaultChance,
        hidden = hidden,
    })
end

--- Register multiple groups with same spawn chance
-- @param groupNames table Array of group names
-- @param spawnChance number|nil Percentage chance for all groups
function DMS.RandomSpawn.registerBatch(groupNames, spawnChance)
    for _, name in ipairs(groupNames) do
        DMS.RandomSpawn.register(name, spawnChance)
    end
end

--- Register groups with pattern matching
-- Groups named "Prefix-1", "Prefix-2", etc.
-- @param prefix string Group name prefix
-- @param count number Number of groups
-- @param spawnChance number|nil Percentage chance for all groups
function DMS.RandomSpawn.registerPattern(prefix, count, spawnChance)
    for i = 1, count do
        DMS.RandomSpawn.register(prefix .. "-" .. i, spawnChance)
    end
end

--- Attempt to spawn a single group (thin wrapper over DMS.SpawnCore)
-- @param groupConfig table Group configuration {name, chance, hidden}
-- @return boolean True if spawned
local function trySpawn(groupConfig)
    local Core = DMS.SpawnCore
    if not Core then
        env.error("[RandomSpawn] spawners/spawn-core.lua is not loaded")
        return false
    end
    return (Core.rollAndActivate(groupConfig.name, groupConfig.chance,
        {hidden = groupConfig.hidden, prefix = "RandomSpawn"}))
end

--- Execute all registered spawns
-- Call this at mission start or when ready to spawn
-- @return table Results {spawned = count, total = count}
function DMS.RandomSpawn.execute()
    local results = {
        spawned = 0,
        total = #DMS.RandomSpawn.Groups,
        spawnedGroups = {},
    }

    for _, groupConfig in ipairs(DMS.RandomSpawn.Groups) do
        if not groupConfig.processed then
            groupConfig.processed = true
            if trySpawn(groupConfig) then
                results.spawned = results.spawned + 1
                table.insert(results.spawnedGroups, groupConfig.name)
            end
        end
    end

    if DMS.Settings and DMS.Settings.isDebug() then
        env.info(string.format("[RandomSpawn] Executed: %d of %d groups spawned", results.spawned, results.total))
    end

    return results
end

--- Start the random spawn system (used by mission-state/phase-manager.lua)
-- Executes all not-yet-processed registrations once, optionally after a delay.
-- @param delay number|nil Seconds before executing (default 0)
-- @return table|nil Results when executed immediately
function DMS.RandomSpawn.start(delay)
    DMS.RandomSpawn.Active = true
    if delay and delay > 0 and DMS.SpawnCore then
        DMS.RandomSpawn.TimerId = DMS.SpawnCore.schedule(function()
            DMS.RandomSpawn.TimerId = nil
            if DMS.RandomSpawn.Active then
                DMS.RandomSpawn.execute()
            end
        end, delay, "RandomSpawn.start")
        return nil
    end
    return DMS.RandomSpawn.execute()
end

--- Stop the random spawn system (cancels a pending delayed start)
function DMS.RandomSpawn.stop()
    DMS.RandomSpawn.Active = false
    if DMS.RandomSpawn.TimerId then
        pcall(timer.removeFunction, DMS.RandomSpawn.TimerId)
        DMS.RandomSpawn.TimerId = nil
    end
    if DMS.Settings and DMS.Settings.isDebug() then
        env.info("[RandomSpawn] Stopped")
    end
end

--- Clear all registered groups
function DMS.RandomSpawn.clear()
    DMS.RandomSpawn.Groups = {}
end

--- Get registration count
-- @return number Number of registered groups
function DMS.RandomSpawn.getCount()
    return #DMS.RandomSpawn.Groups
end

--[[
USAGE EXAMPLE:

-- Register individual groups
DMS.RandomSpawn.register("Enemy-Patrol-1", 50)   -- 50% chance
DMS.RandomSpawn.register("Enemy-Patrol-2", 50)
DMS.RandomSpawn.register("Enemy-Armor", 25)      -- 25% chance

-- Register batch with same chance
DMS.RandomSpawn.registerBatch({
    "Infantry-1", "Infantry-2", "Infantry-3", "Infantry-4"
}, 33)  -- 33% chance each

-- Register pattern (Tech-1 through Tech-10)
DMS.RandomSpawn.registerPattern("Tech", 10, 25)  -- 25% chance each

-- Execute spawns
local results = DMS.RandomSpawn.execute()
env.info(string.format("Spawned %d of %d groups", results.spawned, results.total))
]]

-- Export
_G.DMS = DMS
