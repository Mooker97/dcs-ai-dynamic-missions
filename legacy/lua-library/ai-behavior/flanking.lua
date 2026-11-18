-- Flanking Maneuver System for DCS Missions
-- AI ground groups execute flanking movements around targets
-- Place in mission via DO SCRIPT FILE
-- Optional: utils/mission-settings.lua (debug logging), utils/error-handler.lua

DMS = DMS or {}
DMS.Flanking = {}

-- Active flanking maneuvers
DMS.Flanking.Maneuvers = {}
DMS.Flanking.NextManeuverId = 0

-- Configuration
DMS.Flanking.Config = {
    defaultFlankDistance = 500,     -- Distance to flank (meters)
    defaultFlankAngle = 90,         -- Angle of flank (degrees)
    defaultApproachSpeed = 30,      -- Speed during flank (kph)
    attackSpeed = 15,               -- Speed during final assault (kph)
    flankFormation = "Off Road",    -- Route action while flanking
    attackFormation = "Rank",       -- Route action during assault (line abreast)
    executionTime = 30,             -- Time to reach flank position (seconds)
    announceManeuvers = false,      -- On-screen output
}

-- ============================================================
-- INTERNAL HELPERS
-- ============================================================

local function logDebug(fmt, ...)
    if DMS.Settings and DMS.Settings.isDebug and DMS.Settings.isDebug() then
        env.info(string.format("[Flanking] " .. fmt, ...))
    end
end

local function logError(context, err)
    local msg = tostring(err)
    if DMS.Error and DMS.Error.log then
        if pcall(DMS.Error.log, "Flanking." .. context, msg) then return end
    end
    env.error(string.format("[DMS LUA ERROR] Flanking.%s: %s", context, msg))
end

local function safeScheduleOnce(context, func, delay)
    return timer.scheduleFunction(function(_, time)
        local ok, err = pcall(func, time)
        if not ok then logError(context, err) end
        return nil
    end, nil, timer.getTime() + delay)
end

local function getLeadUnit(group)
    if not group or not group:isExist() then return nil end
    local units = group:getUnits()
    if not units then return nil end
    for _, u in ipairs(units) do
        if u and u:isExist() then return u end
    end
    return nil
end

local function isGroundGroup(group)
    local ok, cat = pcall(group.getCategory, group)
    return ok and cat == Group.Category.GROUND
end

local function makeGroundPoint(x, z, speed, action)
    return {
        x = x, y = z,   -- route y = Vec3.z
        alt = land.getHeight({x = x, y = z}), alt_type = "BARO",
        type = "Turning Point", action = action or "Off Road",
        speed = speed, speed_locked = true,
        ETA = 0, ETA_locked = false,
        formation_template = "",
        task = {id = "ComboTask", params = {tasks = {}}},
    }
end

--- Route a ground group from its current position through {x, z} waypoints
local function routeGroundGroup(group, waypoints, speed, action)
    if not isGroundGroup(group) then return false end
    local lead = getLeadUnit(group)
    if not lead then return false end
    local cur = lead:getPoint()
    local points = {makeGroundPoint(cur.x, cur.z, speed, action)}
    for _, wp in ipairs(waypoints) do
        points[#points + 1] = makeGroundPoint(wp.x, wp.z, speed, action)
    end
    local controller = group:getController()
    if not controller or #points < 2 then return false end
    local ok, err = pcall(controller.setTask, controller,
        {id = "Mission", params = {route = {points = points}}})
    if not ok then
        logError("routeGroundGroup", err)
        return false
    end
    return true
end

--- Calculate flank position
-- @return table Flank position {x, z}
local function calculateFlankPosition(originPos, targetPos, distance, angle, side)
    local dx = targetPos.x - originPos.x
    local dz = targetPos.z - originPos.z
    local bearing = math.atan2(dz, dx)

    local flankAngleRad = math.rad(angle)
    if side == "left" then
        flankAngleRad = -flankAngleRad
    end

    local flankBearing = bearing + flankAngleRad
    return {
        x = targetPos.x + distance * math.cos(flankBearing),
        z = targetPos.z + distance * math.sin(flankBearing),
    }
end

-- ============================================================
-- PUBLIC API
-- ============================================================

--- Configure flanking system
function DMS.Flanking.configure(settings)
    for key, value in pairs(settings) do
        DMS.Flanking.Config[key] = value
    end
end

--- Execute flanking maneuver (ground groups only)
-- @param groupName string Group to flank
-- @param targetPos table Target position {x, z}
-- @param options table|nil {distance, angle, side, speed (kph)}
-- @return boolean True if the maneuver was ordered
function DMS.Flanking.executeFlank(groupName, targetPos, options)
    options = options or {}

    local group = Group.getByName(groupName)
    local lead = getLeadUnit(group)
    if not lead or not targetPos then return false end
    if not isGroundGroup(group) then
        logDebug("'%s' is not a ground group - flank ignored", groupName)
        return false
    end

    local originPos = lead:getPoint()
    local distance = options.distance or DMS.Flanking.Config.defaultFlankDistance
    local angle = options.angle or DMS.Flanking.Config.defaultFlankAngle
    local side = options.side or (math.random() > 0.5 and "left" or "right")
    local speed = options.speed or DMS.Flanking.Config.defaultApproachSpeed

    local flankPos = calculateFlankPosition(originPos, targetPos, distance, angle, side)

    DMS.Flanking.NextManeuverId = DMS.Flanking.NextManeuverId + 1
    local maneuverId = DMS.Flanking.NextManeuverId

    DMS.Flanking.Maneuvers[groupName] = {
        id = maneuverId,
        targetPos = targetPos,
        flankPos = flankPos,
        side = side,
        startTime = timer.getTime(),
        phase = "moving", -- moving, attacking
    }

    local controller = group:getController()
    if controller then
        -- Alert, but only return fire while repositioning
        controller:setOption(AI.Option.Ground.id.ALARM_STATE, AI.Option.Ground.val.ALARM_STATE.RED)
        controller:setOption(AI.Option.Ground.id.ROE, AI.Option.Ground.val.ROE.RETURN_FIRE)
    end

    if not routeGroundGroup(group, {flankPos}, speed / 3.6, DMS.Flanking.Config.flankFormation) then
        DMS.Flanking.Maneuvers[groupName] = nil
        return false
    end

    -- Schedule attack phase (skipped if the maneuver was cancelled/replaced)
    safeScheduleOnce("executeAttack", function()
        local m = DMS.Flanking.Maneuvers[groupName]
        if m and m.id == maneuverId then
            DMS.Flanking.executeAttack(groupName, targetPos)
        end
    end, DMS.Flanking.Config.executionTime)

    logDebug("'%s' executing %s flank to (%.0f, %.0f), attack in %ds",
        groupName, side, flankPos.x, flankPos.z, DMS.Flanking.Config.executionTime)

    if DMS.Flanking.Config.announceManeuvers then
        trigger.action.outText(string.format("[Flanking] %s executing %s flank", groupName, side), 10)
    end

    return true
end

--- Execute attack after flanking
-- @param groupName string Group name
-- @param targetPos table Target position {x, z}
function DMS.Flanking.executeAttack(groupName, targetPos)
    local group = Group.getByName(groupName)
    if not getLeadUnit(group) then
        DMS.Flanking.Maneuvers[groupName] = nil
        logDebug("'%s' destroyed before attack phase", groupName)
        return
    end

    local maneuver = DMS.Flanking.Maneuvers[groupName]
    if maneuver then
        maneuver.phase = "attacking"
    end

    local controller = group:getController()
    if controller then
        controller:setOption(AI.Option.Ground.id.ROE, AI.Option.Ground.val.ROE.OPEN_FIRE)
        controller:setOption(AI.Option.Ground.id.ALARM_STATE, AI.Option.Ground.val.ALARM_STATE.RED)
    end

    routeGroundGroup(group, {targetPos}, DMS.Flanking.Config.attackSpeed / 3.6,
        DMS.Flanking.Config.attackFormation)

    logDebug("'%s' attacking from flank toward (%.0f, %.0f)", groupName, targetPos.x, targetPos.z)

    if DMS.Flanking.Config.announceManeuvers then
        trigger.action.outText(string.format("[Flanking] %s attacking from flank!", groupName), 10)
    end
end

--- Execute pincer movement (two groups flank from opposite sides)
function DMS.Flanking.executePincer(group1, group2, targetPos, options)
    options = options or {}

    DMS.Flanking.executeFlank(group1, targetPos, {
        side = "left", distance = options.distance, angle = options.angle,
    })
    DMS.Flanking.executeFlank(group2, targetPos, {
        side = "right", distance = options.distance, angle = options.angle,
    })
end

--- Execute envelopment (multiple groups surround target)
function DMS.Flanking.executeEnvelopment(groupNames, targetPos, options)
    options = options or {}
    local distance = options.distance or DMS.Flanking.Config.defaultFlankDistance

    local numGroups = #groupNames
    if numGroups == 0 then return end
    local angleStep = 360 / numGroups

    for i, groupName in ipairs(groupNames) do
        DMS.Flanking.executeFlank(groupName, targetPos, {
            angle = (i - 1) * angleStep,
            distance = distance,
            side = "right",  -- Angle determines position
        })
    end
end

--- Cancel flanking maneuver
function DMS.Flanking.cancel(groupName)
    DMS.Flanking.Maneuvers[groupName] = nil

    local group = Group.getByName(groupName)
    if getLeadUnit(group) then
        local controller = group:getController()
        if controller then
            controller:resetTask()
        end
    end
    logDebug("'%s' maneuver cancelled", groupName)
end

--- Get maneuver status
function DMS.Flanking.getStatus(groupName)
    return DMS.Flanking.Maneuvers[groupName]
end

--[[
USAGE EXAMPLE:

DMS.Flanking.configure({
    defaultFlankDistance = 600,
    defaultFlankAngle = 90,
    announceManeuvers = true,
})

local targetPos = {x = -50000, y = 0, z = 40000}
DMS.Flanking.executeFlank("Infantry-1", targetPos, {side = "left", distance = 500})

DMS.Flanking.executePincer("Infantry-1", "Infantry-2", targetPos)

DMS.Flanking.executeEnvelopment({"Squad-1", "Squad-2", "Squad-3", "Squad-4"}, targetPos, {distance = 400})

-- TaskForce "flanker" role calls: DMS.Flanking.executeFlank(groupName, contactPos)
]]

-- Export
_G.DMS = DMS
