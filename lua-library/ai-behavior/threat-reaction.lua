-- Threat Reaction System for DCS Missions
-- AI reacts intelligently to player flight profile and tactics
-- Place in mission via DO SCRIPT FILE

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
    slowSpeedThreshold = 30,        -- Below this = slow/hovering
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

--- Configure threat reaction system
-- @param settings table Configuration overrides
function DMS.ThreatReaction.configure(settings)
    for key, value in pairs(settings) do
        DMS.ThreatReaction.Config[key] = value
    end
end

--- Add a reaction rule
-- @param ruleId string Unique rule ID
-- @param profile string Player profile to react to
-- @param action function Action to execute
-- @param options table|nil Rule options
function DMS.ThreatReaction.addRule(ruleId, profile, action, options)
    options = options or {}

    DMS.ThreatReaction.Rules[ruleId] = {
        id = ruleId,
        profile = profile,
        action = action,
        cooldown = options.cooldown or 30,
        lastTriggered = 0,
        enabled = true,
        zone = options.zone,  -- Optional: only trigger in specific zone
        minTime = options.minTime or 3,  -- Minimum time in profile to trigger
    }
end

--- Add common reaction patterns
function DMS.ThreatReaction.addStandardRules()
    -- React to low-level flight with AAA
    DMS.ThreatReaction.addRule("low_aaa", DMS.ThreatReaction.PROFILES.LOW_FAST, function(playerUnit, profile)
        -- Activate nearby AAA groups
        DMS.ThreatReaction.activateGroupsByType("AAA")
        if DMS.ThreatReaction.Config.announceReactions then
            trigger.action.outText("[ThreatReaction] AAA activated - low altitude contact", 5)
        end
    end, {cooldown = 60})

    -- React to high altitude with SAMs
    DMS.ThreatReaction.addRule("high_sam", DMS.ThreatReaction.PROFILES.HIGH_SLOW, function(playerUnit, profile)
        -- SAMs go hot
        DMS.ThreatReaction.activateGroupsByType("SAM")
        if DMS.SAMAmbush then
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
        -- Send flanking units
        if DMS.Flanking then
            local flankers = DMS.ThreatReaction.getGroupsByRole("flanker")
            for _, groupName in ipairs(flankers) do
                DMS.Flanking.executeFlank(groupName, playerPos)
            end
        end
        if DMS.ThreatReaction.Config.announceReactions then
            trigger.action.outText("[ThreatReaction] Flankers dispatched - stationary target", 5)
        end
    end, {cooldown = 90, minTime = 10})

    -- React to loitering with reinforcements
    DMS.ThreatReaction.addRule("loiter_reinforce", DMS.ThreatReaction.PROFILES.LOITERING, function(playerUnit, profile)
        if DMS.Reinforcements then
            DMS.Reinforcements.triggerNextWave()
        end
        if DMS.ThreatReaction.Config.announceReactions then
            trigger.action.outText("[ThreatReaction] Reinforcements called - prolonged contact", 5)
        end
    end, {cooldown = 120, minTime = 30})

    -- React to diving attack with scatter
    DMS.ThreatReaction.addRule("dive_scatter", DMS.ThreatReaction.PROFILES.DIVING, function(playerUnit, profile)
        if DMS.Retreat then
            local playerPos = playerUnit:getPoint()
            DMS.Retreat.scatterNear(playerPos, 2000)
        end
        if DMS.ThreatReaction.Config.announceReactions then
            trigger.action.outText("[ThreatReaction] Units scattering - incoming attack", 5)
        end
    end, {cooldown = 30, minTime = 2})
end

--- Activate groups by type
-- @param unitType string Type to activate ("AAA", "SAM", etc.)
function DMS.ThreatReaction.activateGroupsByType(unitType)
    -- This would integrate with spawn pool or group tracking
    -- For now, placeholder that missions can override
end

--- Get groups by role
-- @param role string Role to filter
-- @return table Array of group names
function DMS.ThreatReaction.getGroupsByRole(role)
    -- Missions can populate this with their group assignments
    return DMS.ThreatReaction.RoleAssignments and DMS.ThreatReaction.RoleAssignments[role] or {}
end

--- Assign groups to roles
-- @param assignments table {role = {groupNames}}
function DMS.ThreatReaction.assignRoles(assignments)
    DMS.ThreatReaction.RoleAssignments = assignments
end

--- Get terrain height at position
-- @param pos table Position
-- @return number Terrain height
local function getTerrainHeight(pos)
    return land.getHeight({x = pos.x, y = pos.z})
end

--- Analyze player flight profile
-- @param unit table Player unit
-- @return string Profile state
local function analyzeProfile(unit)
    local pos = unit:getPoint()
    local vel = unit:getVelocity()

    -- Calculate AGL altitude
    local terrainHeight = getTerrainHeight(pos)
    local agl = pos.y - terrainHeight

    -- Calculate speed
    local speed = math.sqrt(vel.x * vel.x + vel.y * vel.y + vel.z * vel.z)

    -- Calculate vertical rate
    local verticalRate = vel.y

    local config = DMS.ThreatReaction.Config

    -- Check for diving/climbing
    if verticalRate < -10 then
        return DMS.ThreatReaction.PROFILES.DIVING
    elseif verticalRate > 10 then
        return DMS.ThreatReaction.PROFILES.CLIMBING
    end

    -- Check for hovering
    if speed < config.hoveringSpeedThreshold then
        return DMS.ThreatReaction.PROFILES.HOVERING
    end

    -- Determine altitude category
    local isLow = agl < config.lowAltitudeThreshold
    local isHigh = agl > config.highAltitudeThreshold

    -- Determine speed category
    local isFast = speed > config.fastSpeedThreshold
    local isSlow = speed < config.slowSpeedThreshold

    -- Determine combined profile
    if isLow then
        if isFast then
            return DMS.ThreatReaction.PROFILES.LOW_FAST
        else
            return DMS.ThreatReaction.PROFILES.LOW_SLOW
        end
    elseif isHigh then
        if isFast then
            return DMS.ThreatReaction.PROFILES.HIGH_FAST
        else
            return DMS.ThreatReaction.PROFILES.HIGH_SLOW
        end
    else
        -- Mid altitude
        if isSlow then
            return DMS.ThreatReaction.PROFILES.LOW_SLOW
        else
            return DMS.ThreatReaction.PROFILES.HIGH_FAST
        end
    end
end

--- Process threat reactions
local function processReactions(_, time)
    if not DMS.ThreatReaction.Active then return nil end

    local currentTime = timer.getTime()
    local players = coalition.getPlayers(DMS.ThreatReaction.Config.playerCoalition)

    if not players then
        return time + DMS.ThreatReaction.Config.checkInterval
    end

    for _, playerUnit in ipairs(players) do
        if playerUnit and playerUnit:isExist() then
            local unitName = playerUnit:getName()

            -- Get or create player profile tracking
            local profile = DMS.ThreatReaction.PlayerProfiles[unitName]
            if not profile then
                profile = {
                    currentState = nil,
                    stateStartTime = currentTime,
                    lastPosition = playerUnit:getPoint(),
                    stationaryTime = 0,
                }
                DMS.ThreatReaction.PlayerProfiles[unitName] = profile
            end

            -- Analyze current profile
            local newState = analyzeProfile(playerUnit)

            -- Check for loitering (stationary for extended time)
            local currentPos = playerUnit:getPoint()
            local dx = currentPos.x - profile.lastPosition.x
            local dz = currentPos.z - profile.lastPosition.z
            local movement = math.sqrt(dx * dx + dz * dz)

            if movement < 50 then  -- Less than 50m movement
                profile.stationaryTime = profile.stationaryTime + DMS.ThreatReaction.Config.checkInterval
                if profile.stationaryTime > DMS.ThreatReaction.Config.stationaryTime then
                    newState = DMS.ThreatReaction.PROFILES.LOITERING
                end
            else
                profile.stationaryTime = 0
            end
            profile.lastPosition = currentPos

            -- Track state duration
            if newState ~= profile.currentState then
                profile.currentState = newState
                profile.stateStartTime = currentTime
            end

            local timeInState = currentTime - profile.stateStartTime

            -- Check rules
            for ruleId, rule in pairs(DMS.ThreatReaction.Rules) do
                if rule.enabled and rule.profile == newState then
                    -- Check cooldown
                    if currentTime - rule.lastTriggered > rule.cooldown then
                        -- Check minimum time in state
                        if timeInState >= rule.minTime then
                            -- Execute action
                            rule.action(playerUnit, profile)
                            rule.lastTriggered = currentTime
                        end
                    end
                end
            end
        end
    end

    return time + DMS.ThreatReaction.Config.checkInterval
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
end

--- Stop threat reaction system
function DMS.ThreatReaction.stop()
    DMS.ThreatReaction.Active = false
    if DMS.ThreatReaction.TimerId then
        timer.removeFunction(DMS.ThreatReaction.TimerId)
        DMS.ThreatReaction.TimerId = nil
    end
end

--- Enable/disable a rule
-- @param ruleId string Rule ID
-- @param enabled boolean Enable state
function DMS.ThreatReaction.setRuleEnabled(ruleId, enabled)
    if DMS.ThreatReaction.Rules[ruleId] then
        DMS.ThreatReaction.Rules[ruleId].enabled = enabled
    end
end

--- Get player profile
-- @param unitName string Player unit name
-- @return table|nil Profile info
function DMS.ThreatReaction.getPlayerProfile(unitName)
    return DMS.ThreatReaction.PlayerProfiles[unitName]
end

--[[
USAGE EXAMPLE:

-- Configure
DMS.ThreatReaction.configure({
    lowAltitudeThreshold = 150,
    announceReactions = true,
})

-- Add standard reaction rules
DMS.ThreatReaction.addStandardRules()

-- Add custom rule
DMS.ThreatReaction.addRule("custom_dive", DMS.ThreatReaction.PROFILES.DIVING, function(playerUnit, profile)
    -- Custom reaction when player is diving
    trigger.action.outText("INCOMING!", 3)

    -- Activate specific defenses
    local group = Group.getByName("Point-Defense-1")
    if group then
        local controller = group:getController()
        controller:setOption(AI.Option.Ground.id.ROE, AI.Option.Ground.val.ROE.WEAPON_FREE)
    end
end, {cooldown = 15, minTime = 1})

-- Assign groups to roles for reactions
DMS.ThreatReaction.assignRoles({
    flanker = {"Infantry-1", "Infantry-2"},
    aaa = {"ZU23-1", "ZU23-2"},
    sam = {"SA-6-1", "SA-8-1"},
})

-- Start system
DMS.ThreatReaction.start()

-- Player flight profiles and reactions:
-- LOW_FAST → Activate AAA (hard to track, use volume fire)
-- HIGH_SLOW → SAMs go hot (easy target at altitude)
-- HOVERING → Send flanking units (stationary = vulnerable)
-- DIVING → Units scatter (incoming attack)
-- LOITERING → Call reinforcements (player hunting area)
]]

-- Export
_G.DMS = DMS
