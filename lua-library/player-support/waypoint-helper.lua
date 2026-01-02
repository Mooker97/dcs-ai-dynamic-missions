-- Waypoint Helper System for DCS Missions
-- Provides waypoint information and navigation assistance
-- Requires: utils/coordinates.lua, utils/messaging.lua
-- Place in mission via DO SCRIPT FILE

DMS = DMS or {}
DMS.Waypoint = {}

-- Custom waypoints
DMS.Waypoint.CustomPoints = {}
DMS.Waypoint.Active = false

-- Configuration
DMS.Waypoint.Config = {
    playerCoalition = coalition.side.BLUE,
    displayDuration = 15,
    showBearing = true,
    showDistance = true,
    showETA = true,
    defaultSpeed = 250,          -- Knots for ETA calculation
}

--- Configure waypoint helper
-- @param settings table Configuration overrides
function DMS.Waypoint.configure(settings)
    for key, value in pairs(settings) do
        DMS.Waypoint.Config[key] = value
    end
end

--- Calculate bearing between positions
-- @param from table Vec3
-- @param to table Vec3
-- @return number Bearing in degrees
local function getBearing(from, to)
    local dx = to.x - from.x
    local dz = to.z - from.z
    local bearing = math.deg(math.atan2(dz, dx))
    if bearing < 0 then bearing = bearing + 360 end
    return bearing
end

--- Calculate distance between positions
-- @param from table Vec3
-- @param to table Vec3
-- @return number Distance in meters
local function getDistance(from, to)
    local dx = to.x - from.x
    local dz = to.z - from.z
    return math.sqrt(dx * dx + dz * dz)
end

--- Format distance with appropriate units
-- @param meters number Distance in meters
-- @return string Formatted distance
local function formatDistance(meters)
    local nm = meters / 1852
    if nm >= 1 then
        return string.format("%.1f NM", nm)
    else
        return string.format("%.0f m", meters)
    end
end

--- Calculate ETA in minutes
-- @param distance number Distance in meters
-- @param speed number Speed in knots
-- @return number ETA in minutes
local function calculateETA(distance, speed)
    local nm = distance / 1852
    local hours = nm / speed
    return hours * 60
end

--- Get player position
-- @param playerName string|nil Specific player or first player
-- @return table|nil Vec3 position
local function getPlayerPosition(playerName)
    local players = coalition.getPlayers(DMS.Waypoint.Config.playerCoalition)

    if not players or #players == 0 then
        return nil
    end

    if playerName then
        for _, unit in ipairs(players) do
            if unit:isExist() and unit:getPlayerName() == playerName then
                return unit:getPoint()
            end
        end
    end

    -- Return first player
    if players[1]:isExist() then
        return players[1]:getPoint()
    end

    return nil
end

--- Register a custom waypoint
-- @param name string Waypoint name
-- @param position table Vec3 or {x, z} position
-- @param options table|nil Additional options
function DMS.Waypoint.register(name, position, options)
    options = options or {}

    -- Normalize position to Vec3
    local pos = {
        x = position.x,
        y = position.y or 0,
        z = position.z
    }

    DMS.Waypoint.CustomPoints[name] = {
        name = name,
        position = pos,
        description = options.description or "",
        type = options.type or "custom",  -- custom, tanker, divert, target, etc.
        altitude = options.altitude,
        heading = options.heading,
    }
end

--- Register a waypoint from a unit's position
-- @param name string Waypoint name
-- @param unitName string Unit name to get position from
-- @param options table|nil Additional options
function DMS.Waypoint.registerFromUnit(name, unitName, options)
    local unit = Unit.getByName(unitName)
    if unit and unit:isExist() then
        local pos = unit:getPoint()
        DMS.Waypoint.register(name, pos, options)
        return true
    end
    return false
end

--- Register a waypoint from a zone
-- @param name string Waypoint name
-- @param zoneName string Zone name
-- @param options table|nil Additional options
function DMS.Waypoint.registerFromZone(name, zoneName, options)
    local zone = trigger.misc.getZone(zoneName)
    if zone then
        local pos = {x = zone.point.x, y = 0, z = zone.point.z}
        DMS.Waypoint.register(name, pos, options)
        return true
    end
    return false
end

--- Get information about a waypoint
-- @param name string Waypoint name
-- @param playerName string|nil Player for relative calculations
-- @return table|nil Waypoint info
function DMS.Waypoint.getInfo(name, playerName)
    local waypoint = DMS.Waypoint.CustomPoints[name]
    if not waypoint then
        return nil
    end

    local info = {
        name = waypoint.name,
        description = waypoint.description,
        type = waypoint.type,
        position = waypoint.position,
    }

    -- Calculate relative info if player available
    local playerPos = getPlayerPosition(playerName)
    if playerPos then
        info.bearing = getBearing(playerPos, waypoint.position)
        info.distance = getDistance(playerPos, waypoint.position)
        info.distanceFormatted = formatDistance(info.distance)

        if DMS.Waypoint.Config.showETA then
            info.eta = calculateETA(info.distance, DMS.Waypoint.Config.defaultSpeed)
        end
    end

    return info
end

--- Display waypoint information
-- @param name string Waypoint name
function DMS.Waypoint.showInfo(name)
    local info = DMS.Waypoint.getInfo(name)

    if not info then
        trigger.action.outTextForCoalition(
            DMS.Waypoint.Config.playerCoalition,
            "Waypoint not found: " .. name,
            5,
            true
        )
        return
    end

    local lines = {
        string.format("=== WAYPOINT: %s ===", info.name),
    }

    if info.description ~= "" then
        table.insert(lines, info.description)
    end

    table.insert(lines, "")

    if info.bearing then
        table.insert(lines, string.format("Bearing: %03d", math.floor(info.bearing)))
    end

    if info.distanceFormatted then
        table.insert(lines, string.format("Distance: %s", info.distanceFormatted))
    end

    if info.eta then
        if info.eta >= 60 then
            table.insert(lines, string.format("ETA: %.0f hr %.0f min (at %d kts)",
                math.floor(info.eta / 60), info.eta % 60, DMS.Waypoint.Config.defaultSpeed))
        else
            table.insert(lines, string.format("ETA: %.0f min (at %d kts)",
                info.eta, DMS.Waypoint.Config.defaultSpeed))
        end
    end

    trigger.action.outTextForCoalition(
        DMS.Waypoint.Config.playerCoalition,
        table.concat(lines, "\n"),
        DMS.Waypoint.Config.displayDuration,
        true
    )
end

--- Display all registered waypoints
function DMS.Waypoint.showAll()
    local playerPos = getPlayerPosition()
    local lines = {"=== REGISTERED WAYPOINTS ===", ""}

    local waypoints = {}
    for name, wp in pairs(DMS.Waypoint.CustomPoints) do
        local info = {
            name = name,
            type = wp.type,
        }

        if playerPos then
            info.distance = getDistance(playerPos, wp.position)
            info.bearing = getBearing(playerPos, wp.position)
        end

        table.insert(waypoints, info)
    end

    -- Sort by distance if available
    if playerPos then
        table.sort(waypoints, function(a, b)
            return a.distance < b.distance
        end)
    end

    for _, wp in ipairs(waypoints) do
        local line = string.format("- %s [%s]", wp.name, wp.type)

        if wp.bearing and wp.distance then
            line = line .. string.format(" - %03d / %s",
                math.floor(wp.bearing), formatDistance(wp.distance))
        end

        table.insert(lines, line)
    end

    if #waypoints == 0 then
        table.insert(lines, "No waypoints registered.")
    end

    trigger.action.outTextForCoalition(
        DMS.Waypoint.Config.playerCoalition,
        table.concat(lines, "\n"),
        20,
        true
    )
end

--- Display nearest waypoint of a type
-- @param wpType string Waypoint type to find
function DMS.Waypoint.showNearest(wpType)
    local playerPos = getPlayerPosition()
    if not playerPos then
        trigger.action.outTextForCoalition(
            DMS.Waypoint.Config.playerCoalition,
            "No player position available.",
            5,
            true
        )
        return
    end

    local nearest = nil
    local nearestDist = math.huge

    for name, wp in pairs(DMS.Waypoint.CustomPoints) do
        if not wpType or wp.type == wpType then
            local dist = getDistance(playerPos, wp.position)
            if dist < nearestDist then
                nearestDist = dist
                nearest = name
            end
        end
    end

    if nearest then
        DMS.Waypoint.showInfo(nearest)
    else
        trigger.action.outTextForCoalition(
            DMS.Waypoint.Config.playerCoalition,
            "No waypoints of type '" .. (wpType or "any") .. "' found.",
            5,
            true
        )
    end
end

--- Remove a waypoint
-- @param name string Waypoint name
function DMS.Waypoint.remove(name)
    DMS.Waypoint.CustomPoints[name] = nil
end

--- Clear all waypoints
function DMS.Waypoint.clearAll()
    DMS.Waypoint.CustomPoints = {}
end

--- Start waypoint helper
function DMS.Waypoint.start()
    DMS.Waypoint.Active = true
end

--- Stop waypoint helper
function DMS.Waypoint.stop()
    DMS.Waypoint.Active = false
end

--[[
USAGE EXAMPLE:

-- Configure
DMS.Waypoint.configure({
    showETA = true,
    defaultSpeed = 300  -- Knots
})

-- Start system
DMS.Waypoint.start()

-- Register waypoints
DMS.Waypoint.register("BULLSEYE", {x = 0, z = 0}, {
    description = "Reference point BULLSEYE",
    type = "reference"
})

DMS.Waypoint.register("TANKER", {x = 50000, z = 30000}, {
    description = "KC-135 Track ARCO",
    type = "tanker",
    altitude = 25000
})

DMS.Waypoint.register("DIVERT", {x = -80000, z = 60000}, {
    description = "Al Dhafra AFB - Divert field",
    type = "divert"
})

-- Register from mission elements
DMS.Waypoint.registerFromUnit("TARGET-1", "Enemy-HQ", {
    description = "Primary target - Enemy HQ",
    type = "target"
})

DMS.Waypoint.registerFromZone("IP-NORTH", "IP-Zone-North", {
    description = "Initial Point for northern approach",
    type = "ip"
})

-- Add F10 menu
local wpMenu = missionCommands.addSubMenuForCoalition(coalition.side.BLUE, "Waypoints")

missionCommands.addCommandForCoalition(coalition.side.BLUE, "Show All", wpMenu,
    function() DMS.Waypoint.showAll() end)

missionCommands.addCommandForCoalition(coalition.side.BLUE, "Nearest Tanker", wpMenu,
    function() DMS.Waypoint.showNearest("tanker") end)

missionCommands.addCommandForCoalition(coalition.side.BLUE, "Nearest Divert", wpMenu,
    function() DMS.Waypoint.showNearest("divert") end)

-- Create commands for specific waypoints
for name, _ in pairs(DMS.Waypoint.CustomPoints) do
    missionCommands.addCommandForCoalition(coalition.side.BLUE, name, wpMenu,
        function() DMS.Waypoint.showInfo(name) end)
end
]]

-- Export
_G.DMS = DMS
