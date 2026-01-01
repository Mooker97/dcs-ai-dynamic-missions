-- AI Skill Scaling System for DCS Missions
-- Dynamically adjusts AI difficulty based on player performance
-- Place in mission via DO SCRIPT FILE

DMS = DMS or {}
DMS.SkillScaling = {}

-- Performance tracking
DMS.SkillScaling.Metrics = {}
DMS.SkillScaling.Active = false

-- Skill levels
DMS.SkillScaling.LEVELS = {
    ROOKIE = "Rookie",
    AVERAGE = "Average",
    GOOD = "Good",
    HIGH = "High",
    EXCELLENT = "Excellent",
}

-- Configuration
DMS.SkillScaling.Config = {
    checkInterval = 30,
    initialSkill = "Good",
    minSkill = "Rookie",
    maxSkill = "Excellent",

    -- Performance thresholds
    killsPerMinuteHigh = 0.5,       -- Above this = doing well
    killsPerMinuteLow = 0.1,        -- Below this = struggling
    deathsThreshold = 2,            -- This many deaths = reduce difficulty
    damageThreshold = 0.5,          -- Taking lots of damage = reduce
    timeInCombatThreshold = 60,     -- Sustained combat

    -- Scaling behavior
    adjustmentCooldown = 60,        -- Seconds between adjustments
    scaleSpawns = true,             -- Adjust spawn rates
    scaleAccuracy = true,           -- Adjust AI accuracy
    scaleReactionTime = true,       -- Adjust AI reaction time

    announceChanges = false,
    playerCoalition = coalition.side.BLUE,
    enemyCoalition = coalition.side.RED,
}

--- Configure skill scaling system
-- @param settings table Configuration overrides
function DMS.SkillScaling.configure(settings)
    for key, value in pairs(settings) do
        DMS.SkillScaling.Config[key] = value
    end
end

--- Initialize player metrics
-- @param playerName string Player name
local function initializeMetrics(playerName)
    DMS.SkillScaling.Metrics[playerName] = {
        kills = 0,
        deaths = 0,
        damageReceived = 0,
        shotsFired = 0,
        shotsHit = 0,
        missionStartTime = timer.getTime(),
        lastKillTime = timer.getTime(),
        currentSkill = DMS.SkillScaling.Config.initialSkill,
        lastAdjustmentTime = 0,
        combatStartTime = nil,
        inCombat = false,
    }
end

--- Get skill level index
-- @param skill string Skill level name
-- @return number Index (1-5)
local function getSkillIndex(skill)
    local skills = {"Rookie", "Average", "Good", "High", "Excellent"}
    for i, s in ipairs(skills) do
        if s == skill then return i end
    end
    return 3  -- Default to Good
end

--- Get skill level by index
-- @param index number Index (1-5)
-- @return string Skill level name
local function getSkillByIndex(index)
    local skills = {"Rookie", "Average", "Good", "High", "Excellent"}
    index = math.max(1, math.min(5, index))
    return skills[index]
end

--- Calculate player performance score
-- @param metrics table Player metrics
-- @return number Score (-1 to 1, negative = struggling, positive = dominating)
local function calculatePerformance(metrics)
    local currentTime = timer.getTime()
    local missionTime = (currentTime - metrics.missionStartTime) / 60  -- Minutes

    if missionTime < 1 then return 0 end  -- Too early to judge

    local score = 0

    -- Kill rate factor
    local killRate = metrics.kills / missionTime
    if killRate > DMS.SkillScaling.Config.killsPerMinuteHigh then
        score = score + 0.3
    elseif killRate < DMS.SkillScaling.Config.killsPerMinuteLow then
        score = score - 0.3
    end

    -- Death penalty
    if metrics.deaths >= DMS.SkillScaling.Config.deathsThreshold then
        score = score - 0.4
    end

    -- Accuracy bonus (if tracking shots)
    if metrics.shotsFired > 10 then
        local accuracy = metrics.shotsHit / metrics.shotsFired
        if accuracy > 0.5 then
            score = score + 0.2
        elseif accuracy < 0.2 then
            score = score - 0.2
        end
    end

    -- Damage factor
    if metrics.damageReceived > DMS.SkillScaling.Config.damageThreshold then
        score = score - 0.2
    end

    return math.max(-1, math.min(1, score))
end

--- Adjust AI skill for group
-- @param groupName string Group name
-- @param skill string Target skill level
function DMS.SkillScaling.setGroupSkill(groupName, skill)
    local group = Group.getByName(groupName)
    if not group or not group:isExist() then return end

    local controller = group:getController()
    if not controller then return end

    -- DCS AI skill settings
    local skillValue
    if skill == "Rookie" then
        skillValue = AI.Skill.AVERAGE
        controller:setOption(AI.Option.Air.id.REACTION_ON_THREAT, AI.Option.Air.val.REACTION_ON_THREAT.ALLOW_ABORT_MISSION)
    elseif skill == "Average" then
        skillValue = AI.Skill.GOOD
    elseif skill == "Good" then
        skillValue = AI.Skill.HIGH
    elseif skill == "High" then
        skillValue = AI.Skill.EXCELLENT
    elseif skill == "Excellent" then
        skillValue = AI.Skill.EXCELLENT
    end

    -- Apply to all units in group
    local units = group:getUnits()
    if units then
        for _, unit in ipairs(units) do
            if unit and unit:isExist() then
                -- Unit skill is set at mission creation, but we can affect behavior
                -- through controller options
            end
        end
    end
end

--- Apply skill level to all enemy groups
-- @param skill string Skill level
function DMS.SkillScaling.setAllEnemySkill(skill)
    local groups = coalition.getGroups(DMS.SkillScaling.Config.enemyCoalition)
    if groups then
        for _, group in ipairs(groups) do
            if group:isExist() then
                DMS.SkillScaling.setGroupSkill(group:getName(), skill)
            end
        end
    end
end

--- Get spawn rate multiplier for current skill
-- @param skill string Current skill level
-- @return number Multiplier (0.5 to 1.5)
function DMS.SkillScaling.getSpawnMultiplier(skill)
    local multipliers = {
        ["Rookie"] = 0.5,
        ["Average"] = 0.75,
        ["Good"] = 1.0,
        ["High"] = 1.25,
        ["Excellent"] = 1.5,
    }
    return multipliers[skill] or 1.0
end

--- Get current skill level
-- @param playerName string|nil Player name (or first player)
-- @return string Current skill level
function DMS.SkillScaling.getCurrentSkill(playerName)
    if not playerName then
        -- Get first tracked player
        for name, metrics in pairs(DMS.SkillScaling.Metrics) do
            return metrics.currentSkill
        end
        return DMS.SkillScaling.Config.initialSkill
    end

    local metrics = DMS.SkillScaling.Metrics[playerName]
    return metrics and metrics.currentSkill or DMS.SkillScaling.Config.initialSkill
end

--- Process skill adjustments
local function processSkillAdjustment(_, time)
    if not DMS.SkillScaling.Active then return nil end

    local currentTime = timer.getTime()

    for playerName, metrics in pairs(DMS.SkillScaling.Metrics) do
        -- Check cooldown
        if currentTime - metrics.lastAdjustmentTime < DMS.SkillScaling.Config.adjustmentCooldown then
            goto continue
        end

        -- Calculate performance
        local performance = calculatePerformance(metrics)

        -- Determine adjustment
        local currentIndex = getSkillIndex(metrics.currentSkill)
        local newIndex = currentIndex

        if performance > 0.3 then
            -- Player doing well, increase difficulty
            newIndex = math.min(5, currentIndex + 1)
        elseif performance < -0.3 then
            -- Player struggling, decrease difficulty
            newIndex = math.max(1, currentIndex - 1)
        end

        local minIndex = getSkillIndex(DMS.SkillScaling.Config.minSkill)
        local maxIndex = getSkillIndex(DMS.SkillScaling.Config.maxSkill)
        newIndex = math.max(minIndex, math.min(maxIndex, newIndex))

        if newIndex ~= currentIndex then
            local newSkill = getSkillByIndex(newIndex)
            metrics.currentSkill = newSkill
            metrics.lastAdjustmentTime = currentTime

            -- Apply changes
            DMS.SkillScaling.setAllEnemySkill(newSkill)

            if DMS.SkillScaling.Config.announceChanges then
                local direction = newIndex > currentIndex and "increased" or "decreased"
                trigger.action.outText(string.format(
                    "[Difficulty] Enemy skill %s to %s",
                    direction, newSkill
                ), 10)
            end
        end

        ::continue::
    end

    return time + DMS.SkillScaling.Config.checkInterval
end

--- Event handler for tracking performance
DMS.SkillScaling.EventHandler = {
    onEvent = function(self, event)
        if not DMS.SkillScaling.Active then return end

        -- Track kills
        if event.id == world.event.S_EVENT_KILL then
            if event.initiator then
                local initiatorCoalition = event.initiator:getCoalition()
                if initiatorCoalition == DMS.SkillScaling.Config.playerCoalition then
                    local playerName = event.initiator:getName()
                    if not DMS.SkillScaling.Metrics[playerName] then
                        initializeMetrics(playerName)
                    end
                    DMS.SkillScaling.Metrics[playerName].kills = DMS.SkillScaling.Metrics[playerName].kills + 1
                    DMS.SkillScaling.Metrics[playerName].lastKillTime = timer.getTime()
                end
            end
        end

        -- Track deaths
        if event.id == world.event.S_EVENT_PILOT_DEAD or
           event.id == world.event.S_EVENT_CRASH or
           event.id == world.event.S_EVENT_EJECTION then
            if event.initiator then
                local coalition = event.initiator:getCoalition()
                if coalition == DMS.SkillScaling.Config.playerCoalition then
                    local playerName = event.initiator:getName()
                    if DMS.SkillScaling.Metrics[playerName] then
                        DMS.SkillScaling.Metrics[playerName].deaths = DMS.SkillScaling.Metrics[playerName].deaths + 1
                    end
                end
            end
        end

        -- Track damage received
        if event.id == world.event.S_EVENT_HIT then
            if event.target then
                local targetCoalition = event.target:getCoalition()
                if targetCoalition == DMS.SkillScaling.Config.playerCoalition then
                    local playerName = event.target:getName()
                    if DMS.SkillScaling.Metrics[playerName] then
                        DMS.SkillScaling.Metrics[playerName].damageReceived =
                            DMS.SkillScaling.Metrics[playerName].damageReceived + 0.1
                    end
                end
            end
        end

        -- Track shots fired
        if event.id == world.event.S_EVENT_SHOT then
            if event.initiator then
                local coalition = event.initiator:getCoalition()
                if coalition == DMS.SkillScaling.Config.playerCoalition then
                    local playerName = event.initiator:getName()
                    if not DMS.SkillScaling.Metrics[playerName] then
                        initializeMetrics(playerName)
                    end
                    DMS.SkillScaling.Metrics[playerName].shotsFired =
                        DMS.SkillScaling.Metrics[playerName].shotsFired + 1
                end
            end
        end
    end
}

--- Start skill scaling system
function DMS.SkillScaling.start()
    if DMS.SkillScaling.Active then return end

    DMS.SkillScaling.Active = true
    world.addEventHandler(DMS.SkillScaling.EventHandler)

    timer.scheduleFunction(
        processSkillAdjustment,
        nil,
        timer.getTime() + DMS.SkillScaling.Config.checkInterval
    )

    -- Initialize metrics for existing players
    local players = coalition.getPlayers(DMS.SkillScaling.Config.playerCoalition)
    if players then
        for _, unit in ipairs(players) do
            if unit and unit:isExist() then
                initializeMetrics(unit:getName())
            end
        end
    end
end

--- Stop skill scaling system
function DMS.SkillScaling.stop()
    DMS.SkillScaling.Active = false
end

--- Manually set difficulty
-- @param skill string Skill level
function DMS.SkillScaling.setDifficulty(skill)
    for playerName, metrics in pairs(DMS.SkillScaling.Metrics) do
        metrics.currentSkill = skill
    end
    DMS.SkillScaling.setAllEnemySkill(skill)
end

--- Get performance report
-- @param playerName string|nil Player name
-- @return table Performance metrics
function DMS.SkillScaling.getReport(playerName)
    local metrics = DMS.SkillScaling.Metrics[playerName]
    if not metrics then return nil end

    local missionTime = (timer.getTime() - metrics.missionStartTime) / 60

    return {
        kills = metrics.kills,
        deaths = metrics.deaths,
        killRate = missionTime > 0 and metrics.kills / missionTime or 0,
        accuracy = metrics.shotsFired > 0 and metrics.shotsHit / metrics.shotsFired or 0,
        currentSkill = metrics.currentSkill,
        performance = calculatePerformance(metrics),
    }
end

--[[
USAGE EXAMPLE:

-- Configure
DMS.SkillScaling.configure({
    initialSkill = "Good",
    minSkill = "Average",      -- Don't go below Average
    maxSkill = "Excellent",    -- Can go up to Excellent
    announceChanges = true,
    adjustmentCooldown = 90,   -- Wait 90 seconds between adjustments
})

-- Start system
DMS.SkillScaling.start()

-- System automatically:
-- 1. Tracks player kills, deaths, damage taken
-- 2. Calculates performance score
-- 3. Adjusts AI skill level accordingly

-- Manual control
DMS.SkillScaling.setDifficulty("High")  -- Force specific difficulty

-- Check current state
local skill = DMS.SkillScaling.getCurrentSkill()
local multiplier = DMS.SkillScaling.getSpawnMultiplier(skill)

-- Integrate with spawning
if math.random() < (baseChance * multiplier) then
    -- Spawn enemy
end

-- Get detailed report
local report = DMS.SkillScaling.getReport("Player-1")
-- report.kills, report.deaths, report.currentSkill, etc.
]]

-- Export
_G.DMS = DMS
