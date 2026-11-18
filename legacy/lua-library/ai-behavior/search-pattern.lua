-- Search Pattern System for DCS Missions
-- AI ground groups execute search patterns when hunting for lost contacts
-- Place in mission via DO SCRIPT FILE
-- Optional: utils/mission-settings.lua (debug logging), utils/error-handler.lua

DMS = DMS or {}
DMS.SearchPattern = {}

-- Active searches
DMS.SearchPattern.Active = {}
DMS.SearchPattern.NextSearchId = 0

-- Configuration
DMS.SearchPattern.Config = {
    defaultSearchRadius = 1000,     -- Search area radius
    defaultSearchSpeed = 15,        -- Search speed (kph)
    defaultSearchTime = 120,        -- Max search duration (seconds)
    waypointCount = 6,              -- Points in search pattern
    searchAction = "Off Road",      -- Route action ("Off Road", "Cone", "Vee", ...)
    announceSearches = false,       -- On-screen output
}

-- ============================================================
-- INTERNAL HELPERS
-- ============================================================

local function logDebug(fmt, ...)
    if DMS.Settings and DMS.Settings.isDebug and DMS.Settings.isDebug() then
        env.info(string.format("[SearchPattern] " .. fmt, ...))
    end
end

local function logError(context, err)
    local msg = tostring(err)
    if DMS.Error and DMS.Error.log then
        if pcall(DMS.Error.log, "SearchPattern." .. context, msg) then return end
    end
    env.error(string.format("[DMS LUA ERROR] SearchPattern.%s: %s", context, msg))
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

-- ============================================================
-- PATTERN GENERATORS (return arrays of {x, z})
-- ============================================================

local function generateSpiralPattern(centerPos, radius, numPoints)
    local waypoints = {}
    local angleStep = (2 * math.pi) / numPoints

    for i = 1, numPoints do
        local angle = (i - 1) * angleStep
        local r = (radius / numPoints) * i  -- Expanding radius
        table.insert(waypoints, {
            x = centerPos.x + r * math.cos(angle),
            z = centerPos.z + r * math.sin(angle),
        })
    end

    return waypoints
end

local function generateGridPattern(centerPos, radius, numPoints)
    local waypoints = {}
    local gridSize = math.max(2, math.ceil(math.sqrt(numPoints)))
    local step = (radius * 2) / (gridSize - 1)

    local startX = centerPos.x - radius
    local startZ = centerPos.z - radius

    local direction = 1
    for row = 0, gridSize - 1 do
        local c0, c1, cs = 0, gridSize - 1, 1
        if direction == -1 then
            c0, c1, cs = gridSize - 1, 0, -1
        end
        for col = c0, c1, cs do
            table.insert(waypoints, {
                x = startX + col * step,
                z = startZ + row * step,
            })
        end
        direction = direction * -1
    end

    return waypoints
end

local function generateRandomPattern(centerPos, radius, numPoints)
    local waypoints = {}
    for _ = 1, numPoints do
        local angle = math.random() * 2 * math.pi
        local r = math.random() * radius
        table.insert(waypoints, {
            x = centerPos.x + r * math.cos(angle),
            z = centerPos.z + r * math.sin(angle),
        })
    end
    return waypoints
end

local function generateSectorPattern(centerPos, radius, bearing, arcWidth, numPoints)
    local waypoints = {}
    numPoints = math.max(2, numPoints)
    local startAngle = bearing - arcWidth / 2
    local angleStep = arcWidth / (numPoints - 1)

    for i = 0, numPoints - 1 do
        local angle = startAngle + i * angleStep
        local r = (i % 2 == 0) and radius or (radius * 0.5)  -- Alternating near/far
        table.insert(waypoints, {
            x = centerPos.x + r * math.cos(angle),
            z = centerPos.z + r * math.sin(angle),
        })
    end

    return waypoints
end

-- ============================================================
-- PUBLIC API
-- ============================================================

--- Configure search pattern system
function DMS.SearchPattern.configure(settings)
    for key, value in pairs(settings) do
        DMS.SearchPattern.Config[key] = value
    end
end

--- Start search pattern for a ground group
-- @param groupName string Group name
-- @param lastContactPos table Last known contact position {x, z}
-- @param options table|nil {radius, speed (kph), duration, numPoints, pattern, bearing, arcWidth, action}
-- @return boolean True if the search route was issued
function DMS.SearchPattern.start(groupName, lastContactPos, options)
    options = options or {}

    local group = Group.getByName(groupName)
    if not getLeadUnit(group) or not lastContactPos then return false end
    if not isGroundGroup(group) then
        logDebug("'%s' is not a ground group - search ignored", groupName)
        return false
    end

    local cfg = DMS.SearchPattern.Config
    local radius = options.radius or cfg.defaultSearchRadius
    local speed = options.speed or cfg.defaultSearchSpeed
    local duration = options.duration or cfg.defaultSearchTime
    local numPoints = math.max(1, options.numPoints or cfg.waypointCount)
    local patternType = options.pattern or "spiral"

    local waypoints
    if patternType == "grid" then
        waypoints = generateGridPattern(lastContactPos, radius, numPoints)
    elseif patternType == "random" then
        waypoints = generateRandomPattern(lastContactPos, radius, numPoints)
    elseif patternType == "sector" then
        waypoints = generateSectorPattern(lastContactPos, radius,
            options.bearing or 0, options.arcWidth or math.pi, numPoints)
    else
        patternType = "spiral"
        waypoints = generateSpiralPattern(lastContactPos, radius, numPoints)
    end

    DMS.SearchPattern.NextSearchId = DMS.SearchPattern.NextSearchId + 1
    local searchId = DMS.SearchPattern.NextSearchId

    local controller = group:getController()
    if controller then
        controller:setOption(AI.Option.Ground.id.ALARM_STATE, AI.Option.Ground.val.ALARM_STATE.RED)
        controller:setOption(AI.Option.Ground.id.ROE, AI.Option.Ground.val.ROE.OPEN_FIRE)
    end

    -- Current position is prepended by routeGroundGroup
    if not routeGroundGroup(group, waypoints, speed / 3.6, options.action or cfg.searchAction) then
        return false
    end

    DMS.SearchPattern.Active[groupName] = {
        id = searchId,
        centerPos = lastContactPos,
        waypoints = waypoints,
        currentWaypoint = 1,
        startTime = timer.getTime(),
        duration = duration,
        pattern = patternType,
    }

    -- Schedule search end (ignored if this search was replaced or stopped)
    safeScheduleOnce("searchTimeout", function()
        local s = DMS.SearchPattern.Active[groupName]
        if s and s.id == searchId then
            DMS.SearchPattern.stop(groupName)
        end
    end, duration)

    logDebug("'%s' starting %s search (%d points, radius %dm, %ds)",
        groupName, patternType, #waypoints, radius, duration)

    if cfg.announceSearches then
        trigger.action.outText(string.format("[Search] %s starting %s search pattern",
            groupName, patternType), 10)
    end

    return true
end

--- Stop search pattern (clears the route task; group halts / reverts to default AI)
function DMS.SearchPattern.stop(groupName)
    local search = DMS.SearchPattern.Active[groupName]
    if not search then return end

    DMS.SearchPattern.Active[groupName] = nil

    local group = Group.getByName(groupName)
    if getLeadUnit(group) then
        local controller = group:getController()
        if controller then
            controller:resetTask()
        end
    end

    logDebug("'%s' search complete", groupName)

    if DMS.SearchPattern.Config.announceSearches then
        trigger.action.outText(string.format("[Search] %s search complete", groupName), 5)
    end
end

function DMS.SearchPattern.isSearching(groupName)
    return DMS.SearchPattern.Active[groupName] ~= nil
end

function DMS.SearchPattern.getStatus(groupName)
    local search = DMS.SearchPattern.Active[groupName]
    if search then
        local elapsed = timer.getTime() - search.startTime
        return {
            pattern = search.pattern,
            elapsed = elapsed,
            remaining = search.duration - elapsed,
            centerPos = search.centerPos,
        }
    end
    return nil
end

--- Start coordinated area search (multiple groups divide the area into sectors)
function DMS.SearchPattern.coordinatedSearch(groupNames, areaCenter, areaRadius, options)
    options = options or {}

    local numGroups = #groupNames
    if numGroups == 0 then return end
    local sectorWidth = (2 * math.pi) / numGroups

    for i, groupName in ipairs(groupNames) do
        local sectorBearing = (i - 1) * sectorWidth
        local sectorCenter = {
            x = areaCenter.x + (areaRadius * 0.5) * math.cos(sectorBearing),
            z = areaCenter.z + (areaRadius * 0.5) * math.sin(sectorBearing),
        }

        DMS.SearchPattern.start(groupName, sectorCenter, {
            pattern = "sector",
            bearing = sectorBearing,
            arcWidth = sectorWidth,
            radius = areaRadius / numGroups,
            speed = options.speed,
            duration = options.duration,
        })
    end
end

--[[
USAGE EXAMPLE:

DMS.SearchPattern.configure({
    defaultSearchRadius = 1500,
    defaultSearchTime = 180,
    announceSearches = true,
})

local lastContact = {x = -50000, y = 0, z = 40000}
DMS.SearchPattern.start("Infantry-1", lastContact, {pattern = "spiral", radius = 800})
DMS.SearchPattern.start("Patrol-1", lastContact, {pattern = "grid", radius = 1000})
DMS.SearchPattern.start("QRF-1", lastContact, {
    pattern = "sector",
    bearing = math.rad(45),
    arcWidth = math.rad(90),
})

DMS.SearchPattern.coordinatedSearch({"Squad-1", "Squad-2", "Squad-3"}, lastContact, 2000)
]]

-- Export
_G.DMS = DMS
