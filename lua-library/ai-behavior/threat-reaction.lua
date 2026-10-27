-- Threat Reaction System for DCS Missions
-- AI reacts to player flight profile and tactics
-- Place in mission via DO SCRIPT FILE
-- Optional: flanking.lua, retreat-scatter.lua, sam-ambush.lua, reinforcements,
--           utils/mission-settings.lua (debug logging), utils/error-handler.lua

DMS = DMS or {}
DMS.ThreatReaction = {}

-- Player profile tracking
DMS.ThreatReaction.PlayerProfiles = {}
DMS.ThreatReaction.Active = false
DMS.ThreatReaction.TimerId = nil

-- Reaction rules
DMS.ThreatReaction.Rules = {}

-- Configuration
DMS.ThreatReaction.Config = {
    checkInterval = 5,
    lowAltitudeThreshold = 100,     -- Below this = low level flight (meters AGL)
    highAltitudeThreshold = 3000,   -- Above this = high altitude
    fastSpeedThreshold = 150,       -- Above this = fast (m/s)
    slowSpeedThreshold = 30,        -- Below this = slow
    hoveringSpeedThreshold = 5,     -- Below this = hovering
    stationaryTime = 10,            -- Seconds stationary = loitering
    playerCoalition = coalition.side.BLUE,
    announceReactions = false,
}

-- Flight profile states
DMS.ThreatReaction.PROFILES = {
    LOW_FAST = "LOW_FAST",
    LOW_SLOW = "LOW_SLOW",
    HIGH_FAST = "HIGH_FAST",
    HIGH_SLOW = "HIGH_SLOW",
    HOVERING = "HOVERING",
    DIVING = "DIVING",
    CLIMBING = "CLIMBING",
    LOITERING = "LOITERING",
}

-- ============================================================
-- INTERNAL HELPERS
-- ============================================================

local function logDebug(fmt, ...)
    if DMS.Settings and DMS.Settings.isDebug and DMS.Settings.isDebug() then
        env.info(string.format("[ThreatReaction] " .. fmt, ...))
    end
end

local function logError(context, err)
    local msg = tostring(err)
    if DMS.Error and DMS.Error.log then
        if pcall(DMS.Error.log, "ThreatReaction." .. context, msg) then return end
    end
    env.error(string.format("[DMS LUA ERROR] ThreatReaction.%s: %s", context, msg))
end

local function groupIsAlive(group)
    if not group or not group:isExist() then return false end
    for _, u in ipairs(group:getUnits() or {}) do
        if u and u:isExist() then return true end
    end
    return false
end

-- ============================================================
-- PUBLIC API
-- ============================================================

--- Configure threat reaction system
function DMS.ThreatReaction.configure(settings)
    for key, value in pairs(settings) do
        DMS.ThreatReaction.Config[key] = value
    end
end

--- Add a reaction rule
-- @param ruleId string Unique rule ID
-- @param profile string Player profile to react to
-- @param action function(playerUnit, profile) Action to execute
-- @param options table|nil {cooldown, zone (trigger zone name), minTime}
function DMS.ThreatReaction.addRule(ruleId, profile, action, options)
    options = options or {}

    DMS.ThreatReaction.Rules[ruleId] = {
        id = ruleId,
        profile = profile,
        action = action,
        cooldown = options.cooldown or 30,
        lastTriggered = -math.huge,
        enabled = true,
        zone = options.zone,  -- Optional: only trigger while player is inside this trigger zone
        minTime = options.minTime or 3,  -- Minimum time in profile to trigger
    }
end

--- Add common reaction patterns
function DMS.ThreatReaction.addStandardRules()
    -- React to low-level flight with AAA
    DMS.ThreatReaction.addRule("low_aaa", DMS.ThreatReaction.PROFILES.LOW_FAST, function(playerUnit, profile)
        DMS.ThreatReaction.activateGroupsByType("AAA")
        if DMS.ThreatReaction.Config.announceReactions then
            trigger.action.outText("[ThreatReaction] AAA activated - low altitude contact", 5)
        end
    end, {cooldown = 60})

    -- React to high altitude with SAMs
    DMS.ThreatReaction.addRule("high_sam", DMS.ThreatReaction.PROFILES.HIGH_SLOW, function(playerUnit, profile)
        DMS.ThreatReaction.activateGroupsByType("SAM")
        if DMS.SAMAmbush and DMS.SAMAmbush.Sites and DMS.SAMAmbush.forceHot then
            for groupName, _ in pairs(DMS.SAMAmbush.Sites) do
                DMS.SAMAmbush.forceHot(groupName)
            end
        end
        if DMS.ThreatReaction.Config.announceReactions then
            trigger.action.outText("[ThreatReaction] SAMs activated - high altitude contact", 5)
        end
    end, {cooldown = 60})

    -- React to hovering with flankers
    DMS.ThreatReaction.addRule("hover_flank", DMS.ThreatReaction.PROFILES.HOVERING, function(playerUnit, profile)
        local playerPos = playerUnit:getPoint()
        if DMS.Flanking and DMS.Flanking.executeFlank then
            for _, groupName in ipairs(DMS.ThreatReaction.getGroupsByRole("flanker")) do
                DMS.Flanking.executeFlank(groupName, playerPos)
            end
        end
        if DMS.ThreatReaction.Config.announceReactions then
            trigger.action.outText("[ThreatReaction] Flankers dispatched - stationary target", 5)
        end
    end, {cooldown = 90, minTime = 10})

    -- React to loitering with reinforcements
    DMS.ThreatReaction.addRule("loiter_reinforce", DMS.ThreatReaction.PROFILES.LOITERING, function(playerUnit, profile)
        if DMS.Reinforcements and DMS.Reinforcements.triggerNextWave then
            DMS.Reinforcements.triggerNextWave()
        end
        if DMS.ThreatReaction.Config.announceReactions then
            trigger.action.outText("[ThreatReaction] Reinforcements called - prolonged contact", 5)
        end
    end, {cooldown = 120, minTime = 30})

    -- React to diving attack with scatter (requires retreat-scatter.lua with scatterNear)
    DMS.ThreatReaction.addRule("dive_scatter", DMS.ThreatReaction.PROFILES.DIVING, function(playerUnit, profile)
        if DMS.Retreat and DMS.Retreat.scatterNear then
            DMS.Retreat.scatterNear(playerUnit:getPoint(), 2000)
        else
            logDebug("dive_scatter: DMS.Retreat.scatterNear not available - skipped")
        end
        if DMS.ThreatReaction.Config.announceReactions then
            trigger.action.outText("[ThreatReaction] Units scattering - incoming attack", 5)
        end
    end, {cooldown = 30, minTime = 2})
end

--- Activate groups by type: groups assigned to the matching role (case-insensitive,
-- e.g. "AAA" -> RoleAssignments.aaa) go alarm RED / ROE OPEN_FIRE.
-- Missions may override this function for custom behaviour.
-- @param unitType string Type to activate ("AAA", "SAM", etc.)
function DMS.ThreatReaction.activateGroupsByType(unitType)
    local groups = DMS.ThreatReaction.getGroupsByRole(string.lower(unitType))
    if #groups == 0 then
        groups = DMS.ThreatReaction.getGroupsByRole(unitType)
    end
    local count = 0
    for _, groupName in ipairs(groups) do
        local group = Group.getByName(groupName)
        if groupIsAlive(group) then
            local controller = group:getController()
            if controller then
                controller:setOption(AI.Option.Ground.id.ALARM_STATE, AI.Option.Ground.val.ALARM_STATE.RED)
                controller:setOption(AI.Option.Ground.id.ROE, AI.Option.Ground.val.ROE.OPEN_FIRE)
                count = count + 1
            end
        end
    end
    logDebug("Activated %d %s group(s) (RED / OPEN_FIRE)", count, tostring(unitType))
end

--- Get groups by role
-- @return table Array of group names
function DMS.ThreatReaction.getGroupsByRole(role)
    return DMS.ThreatReaction.RoleAssignments and DMS.ThreatReaction.RoleAssignments[role] or {}
end

--- Assign groups to roles
-- @param assignments table {role = {groupNames}}
function DMS.ThreatReaction.assignRoles(assignments)
    DMS.ThreatReaction.RoleAssignments = assignments
end

--- Analyze player flight profile
-- @return string Profile state
local function analyzeProfile(unit)
    local pos = unit:getPoint()
    local vel = unit:getVelocity()

    local agl = pos.y - land.getHeight({x = pos.x, y = pos.z})
    local speed = math.sqrt(vel.x * vel.x + vel.y * vel.y + vel.z * vel.z)
    local verticalRate = vel.y

    local config = DMS.ThreatReaction.Config

    if verticalRate < -10 then
        return DMS.ThreatReaction.PROFILES.DIVING
    elseif verticalRate > 10 then
        return DMS.ThreatReaction.PROFILES.CLIMBING
    end

    if speed < config.hoveringSpeedThreshold then
        return DMS.ThreatReaction.PROFILES.HOVERING
    end

    local isLow = agl < config.lowAltitudeThreshold
    local isHigh = agl > config.highAltitudeThreshold
    local isFast = speed > config.fastSpeedThreshold
    local isSlow = speed < config.slowSpeedThreshold

    if isLow then
        return isFast and DMS.ThreatReaction.PROFILES.LOW_FAST or DMS.ThreatReaction.PROFILES.LOW_SLOW
    elseif isHigh then
        return isFast and DMS.ThreatReaction.PROFILES.HIGH_FAST or DMS.ThreatReaction.PROFILES.HIGH_SLOW
    else
        -- Mid altitude
        return isSlow and DMS.ThreatReaction.PROFILES.LOW_SLOW or DMS.ThreatReaction.PROFILES.HIGH_FAST
    end
end

--- True if pos is inside the named trigger zone (or no zone given)
local function inRuleZone(rule, pos)
    if not rule.zone then return true end
    local zone = trigger.misc.getZone(rule.zone)
    if not zone then return false end
    local dx = pos.x - zone.point.x
    local dz = pos.z - zone.point.z
    return (dx * dx + dz * dz) <= zone.radius * zone.radius
end

--- Process threat reactions (internal)
local function processReactionsInternal()
    local currentTime = timer.getTime()
    local players = coalition.getPlayers(DMS.ThreatReaction.Config.playerCoalition)
    if not players then return end

    for _, playerUnit in ipairs(players) do
        if playerUnit and playerUnit:isExist() then
            local unitName = playerUnit:getName()
            local currentPos = playerUnit:getPoint()

            local profile = DMS.ThreatReaction.PlayerProfiles[unitName]
            if not profile then
                profile = {
                    currentState = nil,
                    stateStartTime = currentTime,
                    lastPosition = currentPos,
                    stationaryTime = 0,
                }
                DMS.ThreatReaction.PlayerProfiles[unitName] = profile
            end

            local newState = analyzeProfile(playerUnit)

            -- Loitering = little horizontal movement for an extended time
            local dx = currentPos.x - profile.lastPosition.x
            local dz = currentPos.z - profile.lastPosition.z
            if math.sqrt(dx * dx + dz * dz) < 50 then
                profile.stationaryTime = profile.stationaryTime + DMS.ThreatReaction.Config.checkInterval
                if profile.stationaryTime > DMS.ThreatReaction.Config.stationaryTime then
                    newState = DMS.ThreatReaction.PROFILES.LOITERING
                end
            else
                profile.stationaryTime = 0
            end
            profile.lastPosition = currentPos

            if newState ~= profile.currentState then
                logDebug("'%s' profile changed to %s", unitName, newState)
                profile.currentState = newState
                profile.stateStartTime = currentTime
            end

            local timeInState = currentTime - profile.stateStartTime

            for ruleId, rule in pairs(DMS.ThreatReaction.Rules) do
                if rule.enabled and rule.profile == newState
                    and currentTime - rule.lastTriggered > rule.cooldown
                    and timeInState >= rule.minTime
                    and inRuleZone(rule, currentPos) then
                    rule.lastTriggered = currentTime
                    local ok, err = pcall(rule.action, playerUnit, profile)
                    if ok then
                        logDebug("Rule '%s' triggered by '%s' (%s for %.0fs)", ruleId, unitName, newState, timeInState)
                    else
                        logError("rule:" .. tostring(ruleId), err)
                    end
                end
            end
        end
    end
end

local function processReactions(_, time)
    if not DMS.ThreatReaction.Active then return nil end
    local ok, err = pcall(processReactionsInternal)
    if not ok then
        logError("processReactions", err)
    end
    return time + (DMS.ThreatReaction.Config.checkInterval or 5)
end

--- Start threat reaction system
function DMS.ThreatReaction.start()
    if DMS.ThreatReaction.Active then return end

    DMS.ThreatReaction.Active = true
    DMS.ThreatReaction.TimerId = timer.scheduleFunction(
        processReactions,
        nil,
        timer.getTime() + DMS.ThreatReaction.Config.checkInterval
    )

    local count = 0
    for _ in pairs(DMS.ThreatReaction.Rules) do count = count + 1 end
    logDebug("Started with %d rules (interval: %ds)", count, DMS.ThreatReaction.Config.checkInterval)
end

--- Stop threat reaction system
function DMS.ThreatReaction.stop()
    DMS.ThreatReaction.Active = false
    if DMS.ThreatReaction.TimerId then
        pcall(timer.removeFunction, DMS.ThreatReaction.TimerId)
        DMS.ThreatReaction.TimerId = nil
    end
    logDebug("Stopped")
end

--- Enable/disable a rule
function DMS.ThreatReaction.setRuleEnabled(ruleId, enabled)
    if DMS.ThreatReaction.Rules[ruleId] then
        DMS.ThreatReaction.Rules[ruleId].enabled = enabled
    end
end

--- Get player profile
function DMS.ThreatReaction.getPlayerProfile(unitName)
    return DMS.ThreatReaction.PlayerProfiles[unitName]
end

--[[
USAGE EXAMPLE:

DMS.ThreatReaction.configure({lowAltitudeThreshold = 150, announceReactions = true})

DMS.ThreatReaction.addStandardRules()

-- Custom rule
DMS.ThreatReaction.addRule("custom_dive", DMS.ThreatReaction.PROFILES.DIVING, function(playerUnit, profile)
    trigger.action.outText("INCOMING!", 3)
    local group = Group.getByName("Point-Defense-1")
    if group and group:isExist() then
        local controller = group:getController()
        -- Ground ROE values: OPEN_FIRE, RETURN_FIRE, WEAPON_HOLD (no WEAPON_FREE for ground)
        controller:setOption(AI.Option.Ground.id.ROE, AI.Option.Ground.val.ROE.OPEN_FIRE)
    end
end, {cooldown = 15, minTime = 1, zone = "Defense Zone"})

-- Role names are matched case-insensitively by activateGroupsByType ("AAA" -> aaa)
DMS.ThreatReaction.assignRoles({
    flanker = {"Infantry-1", "Infantry-2"},
    aaa = {"ZU23-1", "ZU23-2"},
    sam = {"SA-6-1", "SA-8-1"},
})

DMS.ThreatReaction.start()

-- LOW_FAST -> AAA hot | HIGH_SLOW -> SAMs hot | HOVERING -> flankers
-- DIVING -> scatter (needs DMS.Retreat.scatterNear) | LOITERING -> reinforcements
]]

-- Export
_G.DMS = DMS
