-- Adaptive Difficulty System for DCS Missions
-- Monitors player performance and adjusts enemy pressure
-- Place in mission via DO SCRIPT FILE
-- Optional: utils/mission-settings.lua (debug logging), utils/error-handler.lua
--
-- IMPORTANT - WHAT CAN AND CANNOT CHANGE AT RUNTIME:
--   DCS AI skill (Average/Good/High/Excellent) is baked into each unit when the
--   group is created and CANNOT be changed by script on an existing group.
--   This system therefore only adjusts things that can change at runtime:
--     * Spawn counts / spawn chances / reinforcement odds that spawners query
--       (getSpawnChance, getSpawnCount, shouldReinforce, getSpawnMultiplier)
--     * Which reinforcement pool is used (spawnReinforcement)
--     * ROE and alarm state of registered (managed) groups (applyToGroup)
--   The per-level "aiSkill" value is ADVISORY ONLY: spawners that build new
--   groups (e.g. coalition.addGroup templates) may read it via getSpawnSkill()
--   for groups they create AFTER a level change. Existing units keep their skill.

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
--   spawnRate          multiplier for spawn chances and counts (exposed to spawners)
--   reinforceThreshold probability used by shouldReinforce()
--   groundAlarm        alarm state applied to managed ground groups ("AUTO"|"GREEN"|"RED")
--   groundROE          ROE applied to managed ground groups ("OPEN_FIRE"|"RETURN_FIRE"|"WEAPON_HOLD")
--   airROE             ROE applied to managed air groups ("WEAPON_FREE"|"OPEN_FIRE_WEAPON_FREE"|"OPEN_FIRE"|"RETURN_FIRE"|"WEAPON_HOLD")
--   aiSkill            ADVISORY for newly spawned groups only (see header)
DMS.Difficulty.Levels = {
    [1] = {name = "Easy", spawnRate = 0.5, reinforceThreshold = 0.3,
           groundAlarm = "AUTO", groundROE = "OPEN_FIRE", airROE = "OPEN_FIRE", aiSkill = "Average"},
    [2] = {name = "Normal", spawnRate = 1.0, reinforceThreshold = 0.5,
           groundAlarm = "AUTO", groundROE = "OPEN_FIRE", airROE = "OPEN_FIRE_WEAPON_FREE", aiSkill = "Good"},
    [3] = {name = "Hard", spawnRate = 1.5, reinforceThreshold = 0.7,
           groundAlarm = "RED", groundROE = "OPEN_FIRE", airROE = "WEAPON_FREE", aiSkill = "High"},
    [4] = {name = "Extreme", spawnRate = 2.0, reinforceThreshold = 0.9,
           groundAlarm = "RED", groundROE = "OPEN_FIRE", airROE = "WEAPON_FREE", aiSkill = "Excellent"},
}

-- Configuration
DMS.Difficulty.Config = {
    adjustInterval = 120,        -- Seconds between periodic re-application of ROE/alarm
    killsToIncrease = 5,         -- Kills to trigger difficulty increase
    deathsToDecrease = 2,        -- Deaths to trigger difficulty decrease
    announceChanges = true,      -- Show difficulty change messages
    minLevel = 1,
    maxLevel = 4,
    deathDedupeTime = 15,        -- Seconds: crash + eject + pilot dead count as ONE death
}

-- Reinforcement pools by difficulty
DMS.Difficulty.ReinforcementPools = {
    [1] = {},  -- Easy - group names
    [2] = {},  -- Normal
    [3] = {},  -- Hard
    [4] = {},  -- Extreme
}

-- Groups whose ROE/alarm follow the difficulty level
DMS.Difficulty.ManagedGroups = {}
DMS.Difficulty.Started = false
DMS.Difficulty.RecentDeaths = {}

-- ============================================================
-- INTERNAL HELPERS
-- ============================================================

local function logDebug(fmt, ...)
    if DMS.Settings and DMS.Settings.isDebug and DMS.Settings.isDebug() then
        env.info(string.format("[Difficulty] " .. fmt, ...))
    end
end

local function logError(context, err)
    local msg = tostring(err)
    if DMS.Error and DMS.Error.log then
        if pcall(DMS.Error.log, "Difficulty." .. context, msg) then return end
    end
    env.error(string.format("[DMS LUA ERROR] Difficulty.%s: %s", context, msg))
end

local function groupIsAlive(group)
    if not group or not group:isExist() then return false end
    for _, u in ipairs(group:getUnits() or {}) do
        if u and u:isExist() then return true end
    end
    return false
end

local function safeCall(obj, method)
    if not obj or not obj[method] then return nil end
    local ok, result = pcall(obj[method], obj)
    if ok then return result end
    return nil
end

-- ============================================================
-- PUBLIC API
-- ============================================================

--- Configure the difficulty system
function DMS.Difficulty.configure(settings)
    for key, value in pairs(settings) do
        DMS.Difficulty.Config[key] = value
    end
end

--- Set reinforcement pool for a difficulty level
function DMS.Difficulty.setReinforcementPool(level, groupNames)
    DMS.Difficulty.ReinforcementPools[level] = groupNames
end

--- Get current difficulty settings
function DMS.Difficulty.getCurrentSettings()
    return DMS.Difficulty.Levels[DMS.Difficulty.State.currentLevel]
end

--- Apply current level's ROE / alarm state to one group (the runtime-changeable knobs)
-- @param groupName string
-- @return boolean True if applied
function DMS.Difficulty.applyToGroup(groupName)
    local group = Group.getByName(groupName)
    if not groupIsAlive(group) then return false end
    local controller = group:getController()
    if not controller then return false end

    local settings = DMS.Difficulty.getCurrentSettings()
    local cat = safeCall(group, "getCategory")

    if cat == Group.Category.GROUND or cat == Group.Category.SHIP then
        if cat == Group.Category.GROUND then
            local alarm = AI.Option.Ground.val.ALARM_STATE[settings.groundAlarm or "AUTO"]
            if alarm then
                controller:setOption(AI.Option.Ground.id.ALARM_STATE, alarm)
            end
        end
        local roe = AI.Option.Ground.val.ROE[settings.groundROE or "OPEN_FIRE"]
        if roe then
            local opt = (cat == Group.Category.SHIP) and AI.Option.Naval.id.ROE or AI.Option.Ground.id.ROE
            local val = roe
            if cat == Group.Category.SHIP then
                val = AI.Option.Naval.val.ROE[settings.groundROE or "OPEN_FIRE"]
            end
            if val then controller:setOption(opt, val) end
        end
    elseif cat == Group.Category.AIRPLANE or cat == Group.Category.HELICOPTER then
        local roe = AI.Option.Air.val.ROE[settings.airROE or "OPEN_FIRE"]
        if roe then
            controller:setOption(AI.Option.Air.id.ROE, roe)
        end
    else
        return false
    end
    return true
end

--- Register groups whose ROE/alarm should follow the difficulty level
-- @param groupNames table|string
function DMS.Difficulty.manageGroups(groupNames)
    if type(groupNames) == "string" then groupNames = {groupNames} end
    for _, name in ipairs(groupNames) do
        DMS.Difficulty.ManagedGroups[name] = true
        DMS.Difficulty.applyToGroup(name)
    end
end

--- Re-apply ROE/alarm to all managed groups (dead groups are dropped)
function DMS.Difficulty.applyToManaged()
    local applied = 0
    for name, _ in pairs(DMS.Difficulty.ManagedGroups) do
        local ok, res = pcall(DMS.Difficulty.applyToGroup, name)
        if not ok then
            logError("applyToGroup:" .. name, res)
        elseif res then
            applied = applied + 1
        elseif not groupIsAlive(Group.getByName(name)) then
            DMS.Difficulty.ManagedGroups[name] = nil
        end
    end
    return applied
end

--- Manually set difficulty level
function DMS.Difficulty.setLevel(level)
    level = math.max(DMS.Difficulty.Config.minLevel,
                     math.min(DMS.Difficulty.Config.maxLevel, level))

    if level ~= DMS.Difficulty.State.currentLevel then
        local old = DMS.Difficulty.State.currentLevel
        DMS.Difficulty.State.currentLevel = level
        DMS.Difficulty.State.lastAdjustTime = timer.getTime()
        local settings = DMS.Difficulty.getCurrentSettings()

        local applied = DMS.Difficulty.applyToManaged()
        logDebug("Level changed %d -> %d (%s): spawnRate x%.1f, ROE/alarm applied to %d groups",
            old, level, settings.name, settings.spawnRate, applied)

        if DMS.Difficulty.Config.announceChanges then
            trigger.action.outText("Difficulty adjusted: " .. settings.name, 10, true)
        end
    end
end

function DMS.Difficulty.increase()
    DMS.Difficulty.setLevel(DMS.Difficulty.State.currentLevel + 1)
end

function DMS.Difficulty.decrease()
    DMS.Difficulty.setLevel(DMS.Difficulty.State.currentLevel - 1)
end

--- Record a player kill
function DMS.Difficulty.recordKill(targetType)
    local st = DMS.Difficulty.State
    st.playerKills = st.playerKills + 1
    st.killStreak = st.killStreak + 1
    st.deathStreak = 0
    logDebug("Player kill (%s) - streak %d", tostring(targetType), st.killStreak)

    if st.killStreak >= DMS.Difficulty.Config.killsToIncrease then
        st.killStreak = 0
        DMS.Difficulty.increase()
    end
end

--- Record a player death
function DMS.Difficulty.recordDeath()
    local st = DMS.Difficulty.State
    st.playerDeaths = st.playerDeaths + 1
    st.deathStreak = st.deathStreak + 1
    st.killStreak = 0
    logDebug("Player death - streak %d", st.deathStreak)

    if st.deathStreak >= DMS.Difficulty.Config.deathsToDecrease then
        st.deathStreak = 0
        DMS.Difficulty.decrease()
    end
end

--- Spawn chance modified by current difficulty (for spawners)
-- @param baseChance number Base spawn chance (0-100)
function DMS.Difficulty.getSpawnChance(baseChance)
    return math.min(100, baseChance * DMS.Difficulty.getCurrentSettings().spawnRate)
end

--- Spawn count modified by current difficulty (for spawners); at least 1 if base >= 1
-- @param baseCount number
function DMS.Difficulty.getSpawnCount(baseCount)
    local n = math.floor(baseCount * DMS.Difficulty.getCurrentSettings().spawnRate + 0.5)
    if baseCount >= 1 and n < 1 then n = 1 end
    return n
end

--- Raw spawn multiplier (for spawners)
function DMS.Difficulty.getSpawnMultiplier()
    return DMS.Difficulty.getCurrentSettings().spawnRate
end

--- Advisory skill for NEWLY created groups only (existing units cannot change skill)
function DMS.Difficulty.getSpawnSkill()
    return DMS.Difficulty.getCurrentSettings().aiSkill
end

--- Check if should spawn reinforcements
function DMS.Difficulty.shouldReinforce()
    return math.random() < DMS.Difficulty.getCurrentSettings().reinforceThreshold
end

--- Activate a late-activation group from the current difficulty pool
-- @return string|nil Group name that was activated
function DMS.Difficulty.spawnReinforcement()
    local pool = DMS.Difficulty.ReinforcementPools[DMS.Difficulty.State.currentLevel]
    if not pool or #pool == 0 then
        return nil
    end

    local groupName = pool[math.random(#pool)]
    local group = Group.getByName(groupName)

    if group then
        local ok, err = pcall(trigger.action.activateGroup, group)
        if ok then
            logDebug("Reinforcement '%s' activated (level %d)", groupName, DMS.Difficulty.State.currentLevel)
            DMS.Difficulty.ManagedGroups[groupName] = true
            return groupName
        end
        logError("spawnReinforcement", err)
    end

    return nil
end

--- Get current state
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

--- Count a player death once per unit within deathDedupeTime
local function recordDeathOnce(unitName)
    local now = timer.getTime()
    local last = DMS.Difficulty.RecentDeaths[unitName]
    if last and now - last < DMS.Difficulty.Config.deathDedupeTime then
        return
    end
    DMS.Difficulty.RecentDeaths[unitName] = now
    DMS.Difficulty.recordDeath()
end

--- Handle events (internal)
local function handleEvent(event)
    local unit = event.initiator
    if not unit then return end
    local playerName = safeCall(unit, "getPlayerName")

    if event.id == world.event.S_EVENT_KILL then
        local target = event.target
        if playerName and target then
            -- Ignore friendly kills
            local tc, ic = safeCall(target, "getCoalition"), safeCall(unit, "getCoalition")
            if tc and ic and tc ~= ic then
                DMS.Difficulty.recordKill(safeCall(target, "getTypeName"))
            end
        end
        -- Player killed by AI
        if target and safeCall(target, "getPlayerName") then
            recordDeathOnce(safeCall(target, "getName") or "?")
        end

    elseif event.id == world.event.S_EVENT_PILOT_DEAD
        or event.id == world.event.S_EVENT_CRASH
        or event.id == world.event.S_EVENT_EJECTION then
        if playerName then
            recordDeathOnce(safeCall(unit, "getName") or playerName)
        end
    end
end

--- Create event handler for automatic tracking (pcall-guarded)
function DMS.Difficulty.createEventHandler()
    local handler = {}
    function handler:onEvent(event)
        local ok, err = pcall(handleEvent, event)
        if not ok then logError("onEvent", err) end
    end
    return handler
end

--- Periodic tick: re-apply ROE/alarm (covers newly activated managed groups)
local function periodicTick(_, time)
    local ok, err = pcall(function()
        DMS.Difficulty.State.missionTime = time
        DMS.Difficulty.applyToManaged()
    end)
    if not ok then logError("periodicTick", err) end
    return time + (DMS.Difficulty.Config.adjustInterval or 120)
end

--- Start the adaptive difficulty system
function DMS.Difficulty.start()
    if DMS.Difficulty.Started then return end
    DMS.Difficulty.Started = true

    world.addEventHandler(DMS.Difficulty.createEventHandler())
    timer.scheduleFunction(periodicTick, nil, timer.getTime() + DMS.Difficulty.Config.adjustInterval)

    logDebug("Started at level %d (%s)", DMS.Difficulty.State.currentLevel,
        DMS.Difficulty.getCurrentSettings().name)
end

--[[
USAGE EXAMPLE:

DMS.Difficulty.configure({killsToIncrease = 4, deathsToDecrease = 2, announceChanges = true})

DMS.Difficulty.setReinforcementPool(1, {"Easy-Reinforce-1", "Easy-Reinforce-2"})
DMS.Difficulty.setReinforcementPool(2, {"Normal-Reinforce-1", "Normal-Reinforce-2"})
DMS.Difficulty.setReinforcementPool(3, {"Hard-Reinforce-1", "Hard-Reinforce-2", "Hard-Reinforce-3"})
DMS.Difficulty.setReinforcementPool(4, {"Extreme-Reinforce-1", "Extreme-Reinforce-2"})

-- Groups whose ROE / alarm state follow the level
DMS.Difficulty.manageGroups({"SAM-1", "Armor-1", "AAA-1"})

DMS.Difficulty.start()

DMS.Difficulty.setLevel(3)  -- Hard: managed ground groups go alarm RED

-- In spawner logic (spawn chances / counts CAN change at runtime):
if math.random(100) <= DMS.Difficulty.getSpawnChance(50) then
    local count = DMS.Difficulty.getSpawnCount(4)
    -- spawn `count` groups ...
end

if DMS.Difficulty.shouldReinforce() then
    DMS.Difficulty.spawnReinforcement()
end
]]

-- Export
_G.DMS = DMS
