-- Reinforcement Waves System for DCS Missions
-- Spawns enemy reinforcements based on triggers
-- Requires: utils/timer-utils.lua, utils/group-utils.lua
-- Place in mission via DO SCRIPT FILE

DMS = DMS or {}
DMS.Reinforcements = {}

-- Wave definitions
DMS.Reinforcements.Waves = {}
DMS.Reinforcements.CurrentWave = 0
DMS.Reinforcements.Active = false
DMS.Reinforcements.TimerId = nil

-- Configuration
DMS.Reinforcements.Config = {
    playerCoalition = coalition.side.BLUE,
    enemyCoalition = coalition.side.RED,
    announceWaves = true,
    delayBetweenWaves = 60,     -- Seconds between waves
    maxConcurrentEnemies = 20,   -- Max enemies alive at once
    spawnDelay = 2,              -- Delay between individual spawns
}

--- Configure reinforcement system
-- @param settings table Configuration overrides
function DMS.Reinforcements.configure(settings)
    for key, value in pairs(settings) do
        DMS.Reinforcements.Config[key] = value
    end
end

--- Register a reinforcement wave
-- @param waveNumber number Wave number (1, 2, 3...)
-- @param groups table Array of group names to spawn
-- @param options table|nil Optional wave settings
function DMS.Reinforcements.registerWave(waveNumber, groups, options)
    options = options or {}

    DMS.Reinforcements.Waves[waveNumber] = {
        groups = groups,
        triggered = false,
        spawned = false,
        delay = options.delay or 0,
        announcement = options.announcement or string.format("Warning: Enemy reinforcements inbound! (Wave %d)", waveNumber),
        condition = options.condition or nil,  -- Function that returns true when wave should trigger
    }
end

--- Count current enemy units
-- @return number Count of alive enemy units
local function countEnemies()
    local count = 0
    local groups = coalition.getGroups(DMS.Reinforcements.Config.enemyCoalition)

    if groups then
        for _, group in ipairs(groups) do
            if group:isExist() then
                local units = group:getUnits()
                if units then
                    for _, unit in ipairs(units) do
                        if unit:isExist() and unit:getLife() >= 1 then
                            count = count + 1
                        end
                    end
                end
            end
        end
    end

    return count
end

--- Spawn a wave
-- @param waveNumber number Wave to spawn
local function spawnWave(waveNumber)
    local wave = DMS.Reinforcements.Waves[waveNumber]
    if not wave or wave.spawned then
        return
    end

    wave.spawned = true

    -- Announce wave
    if DMS.Reinforcements.Config.announceWaves and wave.announcement then
        trigger.action.outTextForCoalition(
            DMS.Reinforcements.Config.playerCoalition,
            wave.announcement,
            15,
            true
        )
    end

    -- Spawn groups with delay
    for i, groupName in ipairs(wave.groups) do
        timer.scheduleFunction(function()
            local group = Group.getByName(groupName)
            if group then
                trigger.action.activateGroup(group)
            end
            return nil
        end, nil, timer.getTime() + (i - 1) * DMS.Reinforcements.Config.spawnDelay)
    end
end

--- Trigger a specific wave manually
-- @param waveNumber number Wave to trigger
function DMS.Reinforcements.triggerWave(waveNumber)
    local wave = DMS.Reinforcements.Waves[waveNumber]
    if not wave or wave.triggered then
        return false
    end

    wave.triggered = true

    if wave.delay > 0 then
        timer.scheduleFunction(function()
            spawnWave(waveNumber)
            return nil
        end, nil, timer.getTime() + wave.delay)
    else
        spawnWave(waveNumber)
    end

    return true
end

--- Trigger next wave in sequence
-- @return number|nil Wave number triggered, or nil if none available
function DMS.Reinforcements.triggerNextWave()
    local nextWave = DMS.Reinforcements.CurrentWave + 1

    if DMS.Reinforcements.Waves[nextWave] then
        if DMS.Reinforcements.triggerWave(nextWave) then
            DMS.Reinforcements.CurrentWave = nextWave
            return nextWave
        end
    end

    return nil
end

--- Check wave conditions and trigger automatically
local function checkWaveConditions(_, time)
    if not DMS.Reinforcements.Active then
        return nil
    end

    -- Check each wave's condition
    for waveNumber, wave in pairs(DMS.Reinforcements.Waves) do
        if not wave.triggered and wave.condition then
            if wave.condition() then
                DMS.Reinforcements.triggerWave(waveNumber)
            end
        end
    end

    return time + 5  -- Check every 5 seconds
end

--- Start automatic wave system
function DMS.Reinforcements.start()
    if DMS.Reinforcements.Active then
        return
    end

    DMS.Reinforcements.Active = true
    DMS.Reinforcements.TimerId = timer.scheduleFunction(
        checkWaveConditions,
        nil,
        timer.getTime() + 5
    )
end

--- Stop automatic wave system
function DMS.Reinforcements.stop()
    DMS.Reinforcements.Active = false
    if DMS.Reinforcements.TimerId then
        timer.removeFunction(DMS.Reinforcements.TimerId)
        DMS.Reinforcements.TimerId = nil
    end
end

--- Create wave triggered by enemy count threshold
-- @param waveNumber number Wave number
-- @param groups table Groups to spawn
-- @param threshold number Trigger when enemies below this count
function DMS.Reinforcements.waveOnEnemyCount(waveNumber, groups, threshold)
    DMS.Reinforcements.registerWave(waveNumber, groups, {
        condition = function()
            return countEnemies() < threshold
        end,
        announcement = string.format("Enemy reinforcements detected! (Wave %d - they're bringing more!)", waveNumber)
    })
end

--- Create wave triggered by time
-- @param waveNumber number Wave number
-- @param groups table Groups to spawn
-- @param missionTime number Mission time in seconds to trigger
function DMS.Reinforcements.waveOnTime(waveNumber, groups, missionTime)
    DMS.Reinforcements.registerWave(waveNumber, groups, {
        condition = function()
            return timer.getTime() >= missionTime
        end,
        announcement = string.format("INTEL: Enemy reinforcements arriving on schedule. (Wave %d)", waveNumber)
    })
end

--- Create wave triggered by flag
-- @param waveNumber number Wave number
-- @param groups table Groups to spawn
-- @param flagName string Flag to check
-- @param flagValue number|nil Value to check (default: 1)
function DMS.Reinforcements.waveOnFlag(waveNumber, groups, flagName, flagValue)
    flagValue = flagValue or 1

    DMS.Reinforcements.registerWave(waveNumber, groups, {
        condition = function()
            return trigger.misc.getUserFlag(flagName) == flagValue
        end
    })
end

--- Get status of all waves
-- @return table Wave status information
function DMS.Reinforcements.getStatus()
    local status = {
        currentWave = DMS.Reinforcements.CurrentWave,
        totalWaves = 0,
        triggeredWaves = 0,
        spawnedWaves = 0,
        enemyCount = countEnemies(),
    }

    for _, wave in pairs(DMS.Reinforcements.Waves) do
        status.totalWaves = status.totalWaves + 1
        if wave.triggered then
            status.triggeredWaves = status.triggeredWaves + 1
        end
        if wave.spawned then
            status.spawnedWaves = status.spawnedWaves + 1
        end
    end

    return status
end

--[[
USAGE EXAMPLE:

-- Configure
DMS.Reinforcements.configure({
    announceWaves = true,
    delayBetweenWaves = 45
})

-- Register waves with conditions
DMS.Reinforcements.waveOnEnemyCount(1, {"Enemy-Group-1", "Enemy-Group-2"}, 5)
DMS.Reinforcements.waveOnTime(2, {"Enemy-Armor-1", "Enemy-Armor-2"}, 600)  -- 10 minutes
DMS.Reinforcements.waveOnFlag(3, {"Enemy-Air-1"}, "reinforcements_flag")

-- Or manual wave registration with custom condition
DMS.Reinforcements.registerWave(4, {"Boss-Group"}, {
    condition = function()
        -- Spawn boss when all other waves defeated
        local status = DMS.Reinforcements.getStatus()
        return status.spawnedWaves >= 3 and DMS.Reinforcements.countEnemies() < 3
    end,
    announcement = "WARNING: Enemy commander is deploying their elite forces!",
    delay = 10
})

-- Start automatic checking
DMS.Reinforcements.start()

-- Or trigger manually from F10 menu or trigger
missionCommands.addCommandForCoalition(coalition.side.BLUE, "Call Reinforcements", nil,
    function() DMS.Reinforcements.triggerNextWave() end)
]]

-- Export
_G.DMS = DMS
