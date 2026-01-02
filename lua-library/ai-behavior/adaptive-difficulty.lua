-- Adaptive Difficulty System for DCS Missions
-- Monitors player performance and adjusts enemy spawns
-- Requires: utils/group-utils.lua, utils/timer-utils.lua, events system
-- Place in mission via DO SCRIPT FILE

DMS = DMS or {}
DMS.Difficulty = {}

-- State tracking
DMS.Difficulty.State = {
    playerKills = 0,
    playerDeaths = 0,
    missionTime = 0,
    currentLevel = 2,  -- 1=Easy, 2=Normal, 3=Hard, 4=Extreme
    lastAdjustTime = 0,
    killStreak = 0,
    deathStreak = 0,
}

-- Difficulty levels configuration
DMS.Difficulty.Levels = {
    [1] = {name = "Easy", spawnRate = 0.5, aiSkill = "Average", reinforceThreshold = 0.3},
    [2] = {name = "Normal", spawnRate = 1.0, aiSkill = "Good", reinforceThreshold = 0.5},
    [3] = {name = "Hard", spawnRate = 1.5, aiSkill = "High", reinforceThreshold = 0.7},
    [4] = {name = "Extreme", spawnRate = 2.0, aiSkill = "Excellent", reinforceThreshold = 0.9},
}

-- Configuration
DMS.Difficulty.Config = {
    adjustInterval = 120,        -- Seconds between difficulty checks
    killsToIncrease = 5,         -- Kills to trigger difficulty increase
    deathsToDecrease = 2,        -- Deaths to trigger difficulty decrease
    announceChanges = true,      -- Show difficulty change messages
    minLevel = 1,
    maxLevel = 4,
}

-- Reinforcement pools by difficulty
DMS.Difficulty.ReinforcementPools = {
    [1] = {},  -- Easy - group names
    [2] = {},  -- Normal
    [3] = {},  -- Hard
    [4] = {},  -- Extreme
}

--- Configure the difficulty system
-- @param settings table Configuration overrides
function DMS.Difficulty.configure(settings)
    for key, value in pairs(settings) do
        DMS.Difficulty.Config[key] = value
    end
end

--- Set reinforcement pool for a difficulty level
-- @param level number Difficulty level (1-4)
-- @param groupNames table Array of group names
function DMS.Difficulty.setReinforcementPool(level, groupNames)
    DMS.Difficulty.ReinforcementPools[level] = groupNames
end

--- Get current difficulty settings
-- @return table Current difficulty level config
function DMS.Difficulty.getCurrentSettings()
    return DMS.Difficulty.Levels[DMS.Difficulty.State.currentLevel]
end

--- Manually set difficulty level
-- @param level number Target level (1-4)
function DMS.Difficulty.setLevel(level)
    level = math.max(DMS.Difficulty.Config.minLevel,
                     math.min(DMS.Difficulty.Config.maxLevel, level))

    if level ~= DMS.Difficulty.State.currentLevel then
        DMS.Difficulty.State.currentLevel = level
        local settings = DMS.Difficulty.getCurrentSettings()

        if DMS.Difficulty.Config.announceChanges then
            trigger.action.outText(
                "Difficulty adjusted: " .. settings.name,
                10, true
            )
        end
    end
end

--- Increase difficulty
function DMS.Difficulty.increase()
    DMS.Difficulty.setLevel(DMS.Difficulty.State.currentLevel + 1)
end

--- Decrease difficulty
function DMS.Difficulty.decrease()
    DMS.Difficulty.setLevel(DMS.Difficulty.State.currentLevel - 1)
end

--- Record a player kill
-- @param targetType string|nil Type of target killed
function DMS.Difficulty.recordKill(targetType)
    DMS.Difficulty.State.playerKills = DMS.Difficulty.State.playerKills + 1
    DMS.Difficulty.State.killStreak = DMS.Difficulty.State.killStreak + 1
    DMS.Difficulty.State.deathStreak = 0

    -- Check for difficulty increase
    if DMS.Difficulty.State.killStreak >= DMS.Difficulty.Config.killsToIncrease then
        DMS.Difficulty.increase()
        DMS.Difficulty.State.killStreak = 0
    end
end

--- Record a player death
function DMS.Difficulty.recordDeath()
    DMS.Difficulty.State.playerDeaths = DMS.Difficulty.State.playerDeaths + 1
    DMS.Difficulty.State.deathStreak = DMS.Difficulty.State.deathStreak + 1
    DMS.Difficulty.State.killStreak = 0

    -- Check for difficulty decrease
    if DMS.Difficulty.State.deathStreak >= DMS.Difficulty.Config.deathsToDecrease then
        DMS.Difficulty.decrease()
        DMS.Difficulty.State.deathStreak = 0
    end
end

--- Get spawn chance modifier based on current difficulty
-- @param baseChance number Base spawn chance (0-100)
-- @return number Modified spawn chance
function DMS.Difficulty.getSpawnChance(baseChance)
    local settings = DMS.Difficulty.getCurrentSettings()
    return math.min(100, baseChance * settings.spawnRate)
end

--- Check if should spawn reinforcements
-- @return boolean True if reinforcements should spawn
function DMS.Difficulty.shouldReinforce()
    local settings = DMS.Difficulty.getCurrentSettings()
    return math.random() < settings.reinforceThreshold
end

--- Spawn reinforcements from current difficulty pool
-- @return string|nil Group name that was spawned
function DMS.Difficulty.spawnReinforcement()
    local pool = DMS.Difficulty.ReinforcementPools[DMS.Difficulty.State.currentLevel]
    if not pool or #pool == 0 then
        return nil
    end

    local groupName = pool[math.random(#pool)]
    local group = Group.getByName(groupName)

    if group then
        trigger.action.activateGroup(group)
        return groupName
    end

    return nil
end

--- Get current state
-- @return table Current difficulty state
function DMS.Difficulty.getState()
    return {
        level = DMS.Difficulty.State.currentLevel,
        levelName = DMS.Difficulty.getCurrentSettings().name,
        kills = DMS.Difficulty.State.playerKills,
        deaths = DMS.Difficulty.State.playerDeaths,
        killStreak = DMS.Difficulty.State.killStreak,
        deathStreak = DMS.Difficulty.State.deathStreak,
    }
end

--- Create event handler for automatic tracking
-- @return table Event handler object
function DMS.Difficulty.createEventHandler()
    local handler = {}

    function handler:onEvent(event)
        if not event.initiator then
            return
        end

        -- Check if player involved
        local unit = event.initiator
        local playerName = unit:getPlayerName()

        if event.id == world.event.S_EVENT_KILL then
            -- Player got a kill
            if playerName and event.target then
                DMS.Difficulty.recordKill(event.target:getTypeName())
            end

        elseif event.id == world.event.S_EVENT_PILOT_DEAD then
            -- Player died
            if playerName then
                DMS.Difficulty.recordDeath()
            end

        elseif event.id == world.event.S_EVENT_CRASH then
            -- Player crashed
            if playerName then
                DMS.Difficulty.recordDeath()
            end

        elseif event.id == world.event.S_EVENT_EJECTION then
            -- Player ejected
            if playerName then
                DMS.Difficulty.recordDeath()
            end
        end
    end

    return handler
end

--- Start the adaptive difficulty system
function DMS.Difficulty.start()
    -- Register event handler
    local handler = DMS.Difficulty.createEventHandler()
    world.addEventHandler(handler)

    -- Start periodic check timer
    timer.scheduleFunction(function(_, time)
        DMS.Difficulty.State.missionTime = time
        -- Could add time-based adjustments here
        return time + DMS.Difficulty.Config.adjustInterval
    end, nil, timer.getTime() + DMS.Difficulty.Config.adjustInterval)
end

--[[
USAGE EXAMPLE:

-- Configure
DMS.Difficulty.configure({
    killsToIncrease = 4,
    deathsToDecrease = 2,
    announceChanges = true
})

-- Set reinforcement pools
DMS.Difficulty.setReinforcementPool(1, {"Easy-Reinforce-1", "Easy-Reinforce-2"})
DMS.Difficulty.setReinforcementPool(2, {"Normal-Reinforce-1", "Normal-Reinforce-2"})
DMS.Difficulty.setReinforcementPool(3, {"Hard-Reinforce-1", "Hard-Reinforce-2", "Hard-Reinforce-3"})
DMS.Difficulty.setReinforcementPool(4, {"Extreme-Reinforce-1", "Extreme-Reinforce-2"})

-- Start system
DMS.Difficulty.start()

-- Manual adjustments if needed
DMS.Difficulty.setLevel(3)  -- Set to Hard

-- Use in spawn logic
local baseChance = 50
local actualChance = DMS.Difficulty.getSpawnChance(baseChance)
if math.random(100) <= actualChance then
    -- Spawn enemy
end

-- Spawn reinforcements based on difficulty
if DMS.Difficulty.shouldReinforce() then
    DMS.Difficulty.spawnReinforcement()
end
]]

-- Export
_G.DMS = DMS
