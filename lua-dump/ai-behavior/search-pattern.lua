-- Search Pattern System for DCS Missions
-- AI groups execute search patterns when hunting for lost contacts
-- Place in mission via DO SCRIPT FILE

DMS = DMS or {}
DMS.SearchPattern = {}

-- Active searches
DMS.SearchPattern.Active = {}

-- Configuration
DMS.SearchPattern.Config = {
    defaultSearchRadius = 1000,     -- Search area radius
    defaultSearchSpeed = 15,        -- Search speed (kph)
    defaultSearchTime = 120,        -- Max search duration (seconds)
    waypointCount = 6,              -- Points in search pattern
    announceSearches = false,       -- Debug output
}

--- Configure search pattern system
-- @param settings table Configuration overrides
function DMS.SearchPattern.configure(settings)
    for key, value in pairs(settings) do
        DMS.SearchPattern.Config[key] = value
    end
end

--- Generate expanding spiral search pattern
-- @param centerPos table Center position {x, z}
-- @param radius number Search radius
-- @param numPoints number Number of waypoints
-- @return table Array of waypoints
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

--- Generate grid search pattern
-- @param centerPos table Center position
-- @param radius number Search area size
-- @param numPoints number Number of waypoints
-- @return table Array of waypoints
local function generateGridPattern(centerPos, radius, numPoints)
    local waypoints = {}
    local gridSize = math.ceil(math.sqrt(numPoints))
    local step = (radius * 2) / gridSize

    local startX = centerPos.x - radius
    local startZ = centerPos.z - radius

    local direction = 1
    for row = 0, gridSize - 1 do
        if direction == 1 then
            for col = 0, gridSize - 1 do
                table.insert(waypoints, {
                    x = startX + col * step,
                    z = startZ + row * step,
                })
            end
        else
            for col = gridSize - 1, 0, -1 do
                table.insert(waypoints, {
                    x = startX + col * step,
                    z = startZ + row * step,
                })
            end
        end
        direction = direction * -1
    end

    return waypoints
end

--- Generate random search pattern
-- @param centerPos table Center position
-- @param radius number Search area radius
-- @param numPoints number Number of waypoints
-- @return table Array of waypoints
local function generateRandomPattern(centerPos, radius, numPoints)
    local waypoints = {}

    for i = 1, numPoints do
        local angle = math.random() * 2 * math.pi
        local r = math.random() * radius

        table.insert(waypoints, {
            x = centerPos.x + r * math.cos(angle),
            z = centerPos.z + r * math.sin(angle),
        })
    end

    return waypoints
end

--- Generate sector search pattern
-- @param centerPos table Center position
-- @param radius number Search radius
-- @param bearing number Initial bearing (radians)
-- @param arcWidth number Arc width (radians)
-- @param numPoints number Number of waypoints
-- @return table Array of waypoints
local function generateSectorPattern(centerPos, radius, bearing, arcWidth, numPoints)
    local waypoints = {}
    local startAngle = bearing - arcWidth / 2
    local angleStep = arcWidth / (numPoints - 1)

    for i = 0, numPoints - 1 do
        local angle = startAngle + i * angleStep
        -- Alternating near/far pattern
        local r = (i % 2 == 0) and radius or (radius * 0.5)

        table.insert(waypoints, {
            x = centerPos.x + r * math.cos(angle),
            z = centerPos.z + r * math.sin(angle),
        })
    end

    return waypoints
end

--- Start search pattern for a group
-- @param groupName string Group name
-- @param lastContactPos table Last known contact position
-- @param options table|nil Search options
function DMS.SearchPattern.start(groupName, lastContactPos, options)
    options = options or {}

    local group = Group.getByName(groupName)
    if not group or not group:isExist() then return false end

    local radius = options.radius or DMS.SearchPattern.Config.defaultSearchRadius
    local speed = options.speed or DMS.SearchPattern.Config.defaultSearchSpeed
    local duration = options.duration or DMS.SearchPattern.Config.defaultSearchTime
    local numPoints = options.numPoints or DMS.SearchPattern.Config.waypointCount
    local patternType = options.pattern or "spiral"

    -- Generate pattern
    local waypoints
    if patternType == "spiral" then
        waypoints = generateSpiralPattern(lastContactPos, radius, numPoints)
    elseif patternType == "grid" then
        waypoints = generateGridPattern(lastContactPos, radius, numPoints)
    elseif patternType == "random" then
        waypoints = generateRandomPattern(lastContactPos, radius, numPoints)
    elseif patternType == "sector" then
        local bearing = options.bearing or 0
        local arcWidth = options.arcWidth or math.pi
        waypoints = generateSectorPattern(lastContactPos, radius, bearing, arcWidth, numPoints)
    else
        waypoints = generateSpiralPattern(lastContactPos, radius, numPoints)
    end

    -- Store search info
    DMS.SearchPattern.Active[groupName] = {
        centerPos = lastContactPos,
        waypoints = waypoints,
        currentWaypoint = 1,
        startTime = timer.getTime(),
        duration = duration,
        pattern = patternType,
    }

    -- Build route for DCS
    local routePoints = {}
    for i, wp in ipairs(waypoints) do
        table.insert(routePoints, {
            x = wp.x,
            y = wp.z,
            type = "Turning Point",
            action = "Off Road",
            speed = speed / 3.6,
        })
    end

    -- Set mission
    local controller = group:getController()
    if controller then
        controller:setOption(AI.Option.Ground.id.ALARM_STATE, AI.Option.Ground.val.ALARM_STATE.RED)
        controller:setOption(AI.Option.Ground.id.ROE, AI.Option.Ground.val.ROE.WEAPON_FREE)

        local mission = {
            id = 'Mission',
            params = {
                route = {
                    points = routePoints
                }
            }
        }
        controller:setTask(mission)
    end

    -- Schedule search end
    timer.scheduleFunction(function()
        DMS.SearchPattern.stop(groupName)
        return nil
    end, nil, timer.getTime() + duration)

    if DMS.SearchPattern.Config.announceSearches then
        trigger.action.outText(string.format(
            "[Search] %s starting %s search pattern",
            groupName, patternType
        ), 10)
    end

    return true
end

--- Stop search pattern
-- @param groupName string Group name
function DMS.SearchPattern.stop(groupName)
    local search = DMS.SearchPattern.Active[groupName]
    if not search then return end

    DMS.SearchPattern.Active[groupName] = nil

    local group = Group.getByName(groupName)
    if group and group:isExist() then
        local controller = group:getController()
        if controller then
            controller:resetTask()
        end
    end

    if DMS.SearchPattern.Config.announceSearches then
        trigger.action.outText(string.format(
            "[Search] %s search complete",
            groupName
        ), 5)
    end
end

--- Check if group is searching
-- @param groupName string Group name
-- @return boolean True if searching
function DMS.SearchPattern.isSearching(groupName)
    return DMS.SearchPattern.Active[groupName] ~= nil
end

--- Get search status
-- @param groupName string Group name
-- @return table|nil Search info
function DMS.SearchPattern.getStatus(groupName)
    local search = DMS.SearchPattern.Active[groupName]
    if search then
        return {
            pattern = search.pattern,
            elapsed = timer.getTime() - search.startTime,
            remaining = search.duration - (timer.getTime() - search.startTime),
            centerPos = search.centerPos,
        }
    end
    return nil
end

--- Start coordinated area search (multiple groups)
-- @param groupNames table Array of group names
-- @param areaCenter table Center of search area
-- @param areaRadius number Total area radius
-- @param options table|nil Options
function DMS.SearchPattern.coordinatedSearch(groupNames, areaCenter, areaRadius, options)
    options = options or {}

    local numGroups = #groupNames
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
        })
    end
end

--[[
USAGE EXAMPLE:

-- Configure
DMS.SearchPattern.configure({
    defaultSearchRadius = 1500,
    defaultSearchTime = 180,
    announceSearches = true,
})

-- Start spiral search at last contact position
local lastContact = {x = -50000, z = 40000}
DMS.SearchPattern.start("Infantry-1", lastContact, {
    pattern = "spiral",
    radius = 800,
})

-- Grid search pattern
DMS.SearchPattern.start("Patrol-1", lastContact, {
    pattern = "grid",
    radius = 1000,
})

-- Sector search (searching a specific direction)
DMS.SearchPattern.start("QRF-1", lastContact, {
    pattern = "sector",
    bearing = math.rad(45),  -- NE direction
    arcWidth = math.rad(90), -- 90 degree arc
})

-- Coordinated search (multiple groups divide area)
DMS.SearchPattern.coordinatedSearch(
    {"Squad-1", "Squad-2", "Squad-3"},
    lastContact,
    2000
)

-- Integration with Awareness system:
-- When a group enters HUNTING state, Awareness calls:
-- DMS.SearchPattern.start(groupName, lastContactPos)
]]

-- Export
_G.DMS = DMS
