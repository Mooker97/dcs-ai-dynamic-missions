-- Waypoint Helper System for DCS Missions
-- Provides waypoint information and navigation assistance
-- Requires: utils/coordinates.lua, utils/messaging.lua
-- Place in mission via DO SCRIPT FILE

DMS = DMS or {}
DMS.Waypoint = {}

-- ============================================================
-- LOCAL HELPERS (no cross-module dependencies)
-- ============================================================

local LOG_PREFIX = "[Waypoint]"

local function debugLog(fmt, ...)
    if DMS.Settings and DMS.Settings.isDebug and DMS.Settings.isDebug() then
        local ok, msg = pcall(string.format, fmt, ...)
        env.info(LOG_PREFIX .. " " .. (ok and msg or tostring(fmt)))
    end
end

local function logError(context, err)
    if DMS.Error and DMS.Error.log then
        local ok = pcall(DMS.Error.log, context, err)
        if ok then return end
    end
    env.error("[DMS LUA ERROR] " .. tostring(context) .. ": " .. tostring(err))
end

--- Wrap an event handler table so errors never escape into DCS
local function protectHandler(handler, name)
    if DMS.Error and DMS.Error.safeHandler then
        local ok, wrapped = pcall(DMS.Error.safeHandler, handler, name)
        if ok and wrapped then return wrapped end
    end
    return {
        onEvent = function(_, event)
            local ok, err = pcall(handler.onEvent, handler, event)
            if not ok then logError(name, err) end
        end
    }
end

--- Is this object a live unit?
local function unitAlive(unit)
    if not unit then return false end
    local ok, exists = pcall(function() return unit:isExist() end)
    return ok and exists == true
end

--- Return the player name of a unit (nil for AI / non-units)
local function playerNameOf(unit)
    if not unitAlive(unit) or not unit.getPlayerName then return nil end
    local ok, name = pcall(unit.getPlayerName, unit)
    if ok then return name end
    return nil
end

--- Find the player-controlled (or first alive) unit of a group by name
local function getGroupUnit(groupName)
    local group = groupName and Group.getByName(groupName)
    if not group or not group:isExist() then return nil end
    local units = group:getUnits() or {}
    local fallback = nil
    for _, unit in ipairs(units) do
        if unitAlive(unit) then
            if playerNameOf(unit) then return unit end
            fallback = fallback or unit
        end
    end
    return fallback
end

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
-- @param playerName string|nil Specific player
-- @param groupName string|nil Calling group (preferred; from per-group menus)
-- @return table|nil Vec3 position
local function getPlayerPosition(playerName, groupName)
    if groupName then
        local unit = getGroupUnit(groupName)
        if unit then return unit:getPoint() end
        return nil
    end

    local players = coalition.getPlayers(DMS.Waypoint.Config.playerCoalition)

    if not players or #players == 0 then
        return nil
    end

    if playerName then
        for _, unit in ipairs(players) do
            if playerNameOf(unit) == playerName then
                return unit:getPoint()
            end
        end
        return nil
    end

    -- Legacy fallback: first live player (ambiguous in multiplayer)
    for _, unit in ipairs(players) do
        if unitAlive(unit) then
            return unit:getPoint()
        end
    end

    return nil
end

--- Send text to a group (by name) if given, else to the player coalition
local function sendText(groupName, msg, duration)
    local group = groupName and Group.getByName(groupName)
    if group and group:isExist() then
        trigger.action.outTextForGroup(group:getID(), msg, duration, true)
    else
        trigger.action.outTextForCoalition(DMS.Waypoint.Config.playerCoalition, msg, duration, true)
    end
end

--- Register a custom waypoint
-- @param name string Waypoint name
-- @param position table Vec3 or {x, z} position
-- @param options table|nil Additional options
function DMS.Waypoint.register(name, position, options)
    options = options or {}
    if not name or type(position) ~= "table" or not position.x or not position.z then
        logError("Waypoint.register", "invalid name/position for waypoint " .. tostring(name))
        return false
    end

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
    debugLog("Registered waypoint '%s' [%s]", name, DMS.Waypoint.CustomPoints[name].type)
    return true
end

--- Register a waypoint from a unit's position
-- @param name string Waypoint name
-- @param unitName string Unit name to get position from
-- @param options table|nil Additional options
function DMS.Waypoint.registerFromUnit(name, unitName, options)
    local unit = Unit.getByName(unitName)
    if unit and unit:isExist() then
        local pos = unit:getPoint()
        return DMS.Waypoint.register(name, pos, options)
    end
    debugLog("registerFrom* failed for '%s' (source not found)", tostring(name))
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
        return DMS.Waypoint.register(name, pos, options)
    end
    debugLog("registerFrom* failed for '%s' (source not found)", tostring(name))
    return false
end

--- Get information about a waypoint
-- @param name string Waypoint name
-- @param playerName string|nil Player for relative calculations
-- @param groupName string|nil Calling group for relative calculations
-- @return table|nil Waypoint info
function DMS.Waypoint.getInfo(name, playerName, groupName)
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
    local playerPos = getPlayerPosition(playerName, groupName)
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
-- @param groupName string|nil Calling group (relative info + private message)
function DMS.Waypoint.showInfo(name, groupName)
    local info = DMS.Waypoint.getInfo(name, nil, groupName)

    if not info then
        sendText(groupName, "Waypoint not found: " .. tostring(name), 5)
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

    sendText(groupName, table.concat(lines, "\n"), DMS.Waypoint.Config.displayDuration)
end

--- Display all registered waypoints
-- @param groupName string|nil Calling group
function DMS.Waypoint.showAll(groupName)
    local playerPos = getPlayerPosition(nil, groupName)
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

    sendText(groupName, table.concat(lines, "\n"), 20)
end

--- Display nearest waypoint of a type
-- @param wpType string Waypoint type to find
-- @param groupName string|nil Calling group
function DMS.Waypoint.showNearest(wpType, groupName)
    local playerPos = getPlayerPosition(nil, groupName)
    if not playerPos then
        sendText(groupName, "No player position available.", 5)
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
        DMS.Waypoint.showInfo(nearest, groupName)
    else
        sendText(groupName, "No waypoints of type '" .. (wpType or "any") .. "' found.", 5)
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

--- Build the Waypoints menu for one player group (used by setupMenus)
local function buildGroupMenu(groupId, groupName)
    local function safe(context, fn, ...)
        local args = {...}
        return function()
            local ok, err = pcall(fn, unpack(args))
            if not ok then logError(context, err) end
        end
    end

    local menu = missionCommands.addSubMenuForGroup(groupId, "Waypoints")
    missionCommands.addCommandForGroup(groupId, "Show All", menu,
        safe("Waypoint.menu.showAll", DMS.Waypoint.showAll, groupName))
    missionCommands.addCommandForGroup(groupId, "Nearest Tanker", menu,
        safe("Waypoint.menu.tanker", DMS.Waypoint.showNearest, "tanker", groupName))
    missionCommands.addCommandForGroup(groupId, "Nearest Divert", menu,
        safe("Waypoint.menu.divert", DMS.Waypoint.showNearest, "divert", groupName))

    -- Individual waypoints (DCS shows ~10 items per menu level)
    local names = {}
    for name, _ in pairs(DMS.Waypoint.CustomPoints) do
        table.insert(names, name)
    end
    if #names > 0 then
        table.sort(names)
        local listMenu = missionCommands.addSubMenuForGroup(groupId, "Waypoint Info", menu)
        for i = 1, math.min(#names, 9) do
            missionCommands.addCommandForGroup(groupId, names[i], listMenu,
                safe("Waypoint.menu.info", DMS.Waypoint.showInfo, names[i], groupName))
        end
    end
end

-- ============================================================
-- PER-GROUP F10 MENUS
-- Coalition menus cannot tell who pressed them, so menus are built per
-- player group on S_EVENT_BIRTH / S_EVENT_PLAYER_ENTER_UNIT (deduped by
-- group id) and callbacks receive the group name.
-- ============================================================

DMS.Waypoint.MenuGroups = DMS.Waypoint.MenuGroups or {}
DMS.Waypoint.MenuEventHandler = nil

local function ensureGroupMenu(unit)
    if not playerNameOf(unit) then return end
    local okC, side = pcall(unit.getCoalition, unit)
    if not okC or side ~= DMS.Waypoint.Config.playerCoalition then return end
    local group = unit:getGroup()
    if not group or not group:isExist() then return end
    local groupId = group:getID()
    local groupName = group:getName()
    if DMS.Waypoint.MenuGroups[groupId] then return end
    local ok, err = pcall(buildGroupMenu, groupId, groupName)
    if ok then
        DMS.Waypoint.MenuGroups[groupId] = true
        debugLog("Menu built for group '%s' (id %d)", groupName, groupId)
    else
        logError("Waypoint.buildGroupMenu", err)
    end
end

--- Register the F10 menus (call once from mission init, not at load time)
function DMS.Waypoint.setupMenus()
    if DMS.Waypoint.MenuEventHandler then return end
    DMS.Waypoint.MenuEventHandler = protectHandler({
        onEvent = function(_, event)
            if event.id == world.event.S_EVENT_BIRTH or
               event.id == world.event.S_EVENT_PLAYER_ENTER_UNIT then
                ensureGroupMenu(event.initiator)
            end
        end
    }, "Waypoint.MenuEventHandler")
    world.addEventHandler(DMS.Waypoint.MenuEventHandler)

    -- Catch players already in their aircraft
    for _, unit in ipairs(coalition.getPlayers(DMS.Waypoint.Config.playerCoalition) or {}) do
        ensureGroupMenu(unit)
    end
    debugLog("Per-group menus enabled")
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

-- Add per-group F10 menus (Show All / Nearest Tanker / Nearest Divert / each
-- waypoint). Register waypoints BEFORE calling this; the per-waypoint list is
-- built when a group's menu is first created.
DMS.Waypoint.setupMenus()
]]

-- Export
_G.DMS = DMS
