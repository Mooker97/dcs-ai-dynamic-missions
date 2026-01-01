-- Random Spawn Delayed System for DCS Missions
-- Percentage-based spawning with random time delays
-- Place in mission via DO SCRIPT FILE

DMS = DMS or {}
DMS.DelayedSpawn = {}

-- Registered spawn groups
DMS.DelayedSpawn.Groups = {}
DMS.DelayedSpawn.Pending = {}

-- Configuration
DMS.DelayedSpawn.Config = {
    defaultChance = 50,      -- Default spawn chance if not specified
    defaultMinTime = 60,     -- Default minimum delay (seconds)
    defaultMaxTime = 180,    -- Default maximum delay (seconds)
}

--- Configure delayed spawn system
-- @param settings table Configuration overrides
function DMS.DelayedSpawn.configure(settings)
    for key, value in pairs(settings) do
        DMS.DelayedSpawn.Config[key] = value
    end
end

--- Register a group for delayed random spawning
-- @param groupName string Group name (must be LATE ACTIVATION in ME)
-- @param spawnChance number|nil Percentage chance to spawn (1-100)
-- @param minTime number|nil Minimum delay in seconds
-- @param maxTime number|nil Maximum delay in seconds
function DMS.DelayedSpawn.register(groupName, spawnChance, minTime, maxTime)
    table.insert(DMS.DelayedSpawn.Groups, {
        name = groupName,
        chance = spawnChance or DMS.DelayedSpawn.Config.defaultChance,
        minTime = minTime or DMS.DelayedSpawn.Config.defaultMinTime,
        maxTime = maxTime or DMS.DelayedSpawn.Config.defaultMaxTime,
    })
end

--- Register multiple groups with same settings
-- @param groupNames table Array of group names
-- @param spawnChance number|nil Percentage chance for all groups
-- @param minTime number|nil Minimum delay in seconds
-- @param maxTime number|nil Maximum delay in seconds
function DMS.DelayedSpawn.registerBatch(groupNames, spawnChance, minTime, maxTime)
    for _, name in ipairs(groupNames) do
        DMS.DelayedSpawn.register(name, spawnChance, minTime, maxTime)
    end
end

--- Register groups with pattern matching
-- Groups named "Prefix-1", "Prefix-2", etc.
-- @param prefix string Group name prefix
-- @param count number Number of groups
-- @param spawnChance number|nil Percentage chance
-- @param minTime number|nil Minimum delay
-- @param maxTime number|nil Maximum delay
function DMS.DelayedSpawn.registerPattern(prefix, count, spawnChance, minTime, maxTime)
    for i = 1, count do
        DMS.DelayedSpawn.register(prefix .. "-" .. i, spawnChance, minTime, maxTime)
    end
end

--- Attempt spawn callback (for timer)
-- @param groupConfig table Group configuration
-- @return nil Always returns nil (no reschedule)
local function trySpawn(groupConfig)
    DMS.Error.safeCall(function()
        local roll = math.random(1, 100)

        if roll <= groupConfig.chance then
            local group = Group.getByName(groupConfig.name)
            if group then
                trigger.action.activateGroup(group)
                groupConfig.spawned = true
            end
        end
    end, "DelayedSpawn.trySpawn(" .. groupConfig.name .. ")")

    return nil  -- Don't reschedule
end

--- Schedule all registered spawns
-- Call this at mission start
-- @return number Number of spawns scheduled
function DMS.DelayedSpawn.execute()
    local scheduled = 0

    for _, groupConfig in ipairs(DMS.DelayedSpawn.Groups) do
        local delay = math.random(groupConfig.minTime, groupConfig.maxTime)

        timer.scheduleFunction(
            trySpawn,
            groupConfig,
            timer.getTime() + delay
        )

        table.insert(DMS.DelayedSpawn.Pending, {
            name = groupConfig.name,
            scheduledTime = timer.getTime() + delay,
        })

        scheduled = scheduled + 1
    end

    return scheduled
end

--- Clear all registered groups
function DMS.DelayedSpawn.clear()
    DMS.DelayedSpawn.Groups = {}
    DMS.DelayedSpawn.Pending = {}
end

--- Get registration count
-- @return number Number of registered groups
function DMS.DelayedSpawn.getCount()
    return #DMS.DelayedSpawn.Groups
end

--[[
USAGE EXAMPLE:

-- Configure default timing
DMS.DelayedSpawn.configure({
    defaultMinTime = 60,   -- 1 minute minimum
    defaultMaxTime = 300,  -- 5 minutes maximum
})

-- Register individual groups with custom timing
DMS.DelayedSpawn.register("Enemy-QRF", 75, 120, 300)  -- 75%, 2-5 min delay

-- Register batch with same settings
DMS.DelayedSpawn.registerBatch({
    "Infantry-1", "Infantry-2", "Infantry-3", "Infantry-4"
}, 33, 60, 180)  -- 33% chance, 1-3 min delay

-- Register pattern (Tech-1 through Tech-10)
DMS.DelayedSpawn.registerPattern("Tech", 10, 25, 60, 180)

-- Schedule all spawns
local count = DMS.DelayedSpawn.execute()
env.info(string.format("Scheduled %d delayed spawns", count))
]]

-- Export
_G.DMS = DMS
