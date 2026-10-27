-- Reinforcement Waves System for DCS Missions
-- Spawns enemy reinforcements based on triggers
-- Optional: utils/error-handler.lua, utils/mission-settings.lua
-- Place in mission via DO SCRIPT FILE

DMS = DMS or {}
DMS.Reinforcements = DMS.Reinforcements or {}

-- Wave definitions
DMS.Reinforcements.Waves = DMS.Reinforcements.Waves or {}
DMS.Reinforcements.CurrentWave = DMS.Reinforcements.CurrentWave or 0
DMS.Reinforcements.Active = DMS.Reinforcements.Active or false

-- Configuration
DMS.Reinforcements.Config = DMS.Reinforcements.Config or {
    playerCoalition = coalition.side.BLUE,
    enemyCoalition = coalition.side.RED,
    announceWaves = true,
    delayBetweenWaves = 60,     -- Seconds between waves
    maxConcurrentEnemies = 20,   -- Max enemies alive at once
    spawnDelay = 2,              -- Delay between individual spawns
}

local function isDebug()
    return DMS.Settings and DMS.Settings.isDebug and DMS.Settings.isDebug()
end

local function logError(context, err)
    if DMS.Error and DMS.Error.log then
        DMS.Error.log(context, err)
    else
        env.error("[DMS LUA ERROR] " .. tostring(context) .. ": " .. tostring(err))
    end
end

--- One-shot pcall-guarded schedule (works without utils/error-handler.lua)
local function safeSchedule(func, delay, context)
    timer.scheduleFunction(function()
        local ok, err = pcall(func)
        if not ok then logError(context, err) end
        return nil
    end, nil, timer.getTime() + (tonumber(delay) or 0))
end

--- Safely call obj:method(...) returning nil on error
local function safeMethod(obj, method, ...)
    if obj == nil or type(obj) ~= "table" or type(obj[method]) ~= "function" then
        return nil
    end
    local ok, res = pcall(obj[method], obj, ...)
    if ok then return res end
    return nil
end

--- Configure reinforcement system
-- @param settings table Configuration overrides
function DMS.Reinforcements.configure(settings)
    if type(settings) ~= "table" then return end
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
        groups = type(groups) == "table" and groups or {},
        triggered = false,
        spawned = false,
        delay = options.delay or 0,
        announcement = options.announcement or string.format("Warning: Enemy reinforcements inbound! (Wave %s)", tostring(waveNumber)),
        condition = options.condition or nil,  -- Function that returns true when wave should trigger
    }
end

--- Count current enemy units
-- Late-activated (not yet active) units are excluded, otherwise the
-- reinforcement groups themselves would count as "alive enemies".
-- @return number Count of alive, active enemy units
local function countEnemies()
    local count = 0
    local ok, groups = pcall(coalition.getGroups, DMS.Reinforcements.Config.enemyCoalition)
    if not ok or type(groups) ~= "table" then return 0 end

    for _, group in ipairs(groups) do
        if safeMethod(group, "isExist") then
            local units = safeMethod(group, "getUnits")
            if type(units) == "table" then
                for _, unit in ipairs(units) do
                    if safeMethod(unit, "isExist") then
                        local life = safeMethod(unit, "getLife")
                        local active = safeMethod(unit, "isActive")
                        if (life == nil or life >= 1) and active ~= false then
                            count = count + 1
                        end
                    end
                end
            end
        end
    end

    return count
end

--- Public: count alive, active enemy units
DMS.Reinforcements.countEnemies = countEnemies

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

    if isDebug() then
        env.info(string.format("[Reinforcements] Spawning wave %s (%d groups)", tostring(waveNumber), #wave.groups))
    end

    -- Spawn groups with delay
    for i, groupName in ipairs(wave.groups) do
        local delay = (i - 1) * (tonumber(DMS.Reinforcements.Config.spawnDelay) or 0)
        safeSchedule(function()
            local group = Group.getByName(groupName)
            if group and safeMethod(group, "isExist") then
                trigger.action.activateGroup(group)
                if isDebug() then
                    env.info(string.format("[Reinforcements] Activated '%s' (wave %s)", tostring(groupName), tostring(waveNumber)))
                end
            elseif isDebug() then
                env.info(string.format("[Reinforcements] Skipped '%s' (group not found)", tostring(groupName)))
            end
        end, delay, "Reinforcements.spawnGroup(" .. tostring(groupName) .. ")")
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

    local delay = tonumber(wave.delay) or 0
    if isDebug() then
        env.info(string.format("[Reinforcements] Wave %s triggered (delay: %ds, groups: %d)",
            tostring(waveNumber), delay, #wave.groups))
    end

    local context = "Reinforcements.spawnWave(" .. tostring(waveNumber) .. ")"
    if delay > 0 then
        safeSchedule(function()
            spawnWave(waveNumber)
        end, delay, context)
    else
        local ok, err = pcall(spawnWave, waveNumber)
        if not ok then logError(context, err) end
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

--- Check wave conditions and trigger automatically (internal)
local function checkWaveConditionsInternal(_, time)
    if not DMS.Reinforcements.Active then
        return nil
    end

    -- Check each wave's condition
    for waveNumber, wave in pairs(DMS.Reinforcements.Waves) do
        if not wave.triggered and type(wave.condition) == "function" then
            local ok, met = pcall(wave.condition)
            if not ok then
                logError("Reinforcements.condition(wave " .. tostring(waveNumber) .. ")", met)
            elseif met then
                DMS.Reinforcements.triggerWave(waveNumber)
            end
        end
    end

    return time + 5  -- Check every 5 seconds
end

--- Check wave conditions with error handling
local function checkWaveConditions(args, time)
    local success, result = pcall(checkWaveConditionsInternal, args, time)
    if not success then
        logError("Reinforcements.checkWaveConditions", result)
        if not DMS.Reinforcements.Active then return nil end
        return time + 5
    end
    if result == nil then DMS.Reinforcements.TimerId = nil end
    return result
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

    if isDebug() then
        local count = 0
        for _ in pairs(DMS.Reinforcements.Waves) do count = count + 1 end
        env.info(string.format("[Reinforcements] Started monitoring %d waves", count))
    end
end

--- Stop automatic wave system
function DMS.Reinforcements.stop()
    DMS.Reinforcements.Active = false
    if DMS.Reinforcements.TimerId then
        pcall(timer.removeFunction, DMS.Reinforcements.TimerId)
        DMS.Reinforcements.TimerId = nil
    end
    if isDebug() then
        env.info("[Reinforcements] Stopped")
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
        announcement = string.format("Enemy reinforcements detected! (Wave %s - they're bringing more!)", tostring(waveNumber))
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
        announcement = string.format("INTEL: Enemy reinforcements arriving on schedule. (Wave %s)", tostring(waveNumber))
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
