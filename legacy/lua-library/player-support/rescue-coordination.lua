-- Rescue Coordination System for DCS Missions
-- Track ejected pilots and coordinate CSAR
-- Requires: utils/messaging.lua, utils/coordinates.lua
-- Place in mission via DO SCRIPT FILE

DMS = DMS or {}
DMS.Rescue = {}

-- ============================================================
-- LOCAL HELPERS (no cross-module dependencies)
-- ============================================================

local LOG_PREFIX = "[Rescue]"

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

-- Downed pilots
DMS.Rescue.DownedPilots = {}
DMS.Rescue.EventHandler = nil
DMS.Rescue.Active = false
DMS.Rescue.TimerId = nil
DMS.Rescue.PilotIdCounter = 0

-- Configuration
DMS.Rescue.Config = {
    playerCoalition = coalition.side.BLUE,
    trackAIPilots = false,       -- Track AI pilot ejections too
    pilotSurvivalTime = 1800,    -- Seconds pilot survives (30 min)
    rescueRadius = 500,          -- Meters for successful rescue
    checkInterval = 10,
    announceEjections = true,
    announceRescues = true,
    smokeOnEjection = true,
    smokeColor = trigger.smokeColor.Orange,
    useFlares = true,
    flareInterval = 300,         -- Seconds between flares
}

--- Configure rescue system
-- @param settings table Configuration overrides
function DMS.Rescue.configure(settings)
    for key, value in pairs(settings) do
        DMS.Rescue.Config[key] = value
    end
end

--- Generate grid reference from position
-- @param pos table Vec3 position
-- @return string Grid reference
local function getGridReference(pos)
    -- Simple grid reference (in real use, would use MGRS)
    return string.format("X:%.0f Z:%.0f", pos.x / 1000, pos.z / 1000)
end

--- Calculate distance between positions
-- @param pos1 table Vec3
-- @param pos2 table Vec3
-- @return number Distance in meters
local function getDistance(pos1, pos2)
    local dx = pos2.x - pos1.x
    local dz = pos2.z - pos1.z
    return math.sqrt(dx * dx + dz * dz)
end

--- Register a downed pilot
-- @param position table Vec3 position
-- @param pilotName string Pilot name
-- @param isPlayer boolean Is player pilot
local function registerDownedPilot(position, pilotName, isPlayer)
    -- Ejection point is at aircraft altitude; the survivor ends up on the ground
    local groundY = position.y
    local okH, h = pcall(land.getHeight, {x = position.x, y = position.z})
    if okH and h then groundY = h end
    position = {x = position.x, y = groundY, z = position.z}

    DMS.Rescue.PilotIdCounter = DMS.Rescue.PilotIdCounter + 1

    local pilotId = "PILOT-" .. DMS.Rescue.PilotIdCounter

    DMS.Rescue.DownedPilots[pilotId] = {
        id = pilotId,
        name = pilotName or "Unknown",
        isPlayer = isPlayer,
        position = {x = position.x, y = position.y, z = position.z},
        ejectionTime = timer.getTime(),
        expirationTime = timer.getTime() + DMS.Rescue.Config.pilotSurvivalTime,
        rescued = false,
        lastFlareTime = 0,
        status = "awaiting_rescue",
    }

    -- Add smoke marker
    if DMS.Rescue.Config.smokeOnEjection then
        trigger.action.smoke(position, DMS.Rescue.Config.smokeColor)
    end

    -- Announce ejection
    if DMS.Rescue.Config.announceEjections then
        local grid = getGridReference(position)
        local msg = string.format(
            "MAYDAY MAYDAY MAYDAY!\n%s has ejected!\nLast position: %s\nInitiate CSAR operations.",
            pilotName or "Pilot",
            grid
        )

        trigger.action.outTextForCoalition(
            DMS.Rescue.Config.playerCoalition,
            msg,
            20,
            true
        )
    end

    debugLog("Registered downed pilot %s (%s, player=%s)", pilotId, tostring(pilotName), tostring(isPlayer))

    return pilotId
end

--- Event handler (internal)
DMS.Rescue._EventHandlerInternal = {
    onEvent = function(self, event)
        if not DMS.Rescue.Active then
            return
        end

        -- Track ejections
        if event.id == world.event.S_EVENT_EJECTION then
            local unit = event.initiator

            if unitAlive(unit) then
                local okC, side = pcall(unit.getCoalition, unit)
                if not okC or side ~= DMS.Rescue.Config.playerCoalition then
                    return
                end

                local isPlayer = false
                local pilotName = "Unknown Pilot"

                local pName = playerNameOf(unit)
                if pName then
                    isPlayer = true
                    pilotName = pName
                else
                    local okN, uName = pcall(unit.getName, unit)
                    if okN and uName then pilotName = uName end
                end

                -- Only track if player or config allows AI
                if isPlayer or DMS.Rescue.Config.trackAIPilots then
                    local okP, position = pcall(unit.getPoint, unit)
                    if okP and position then
                        registerDownedPilot(position, pilotName, isPlayer)
                    end
                else
                    debugLog("Skipped AI ejection '%s' (trackAIPilots=false)", pilotName)
                end
            end
        end
    end
}

--- Check for rescue opportunities (internal)
local function checkRescuesInternal(_, time)
    if not DMS.Rescue.Active then
        return nil
    end

    local rescuers = coalition.getPlayers(DMS.Rescue.Config.playerCoalition)

    for pilotId, pilot in pairs(DMS.Rescue.DownedPilots) do
        if pilot.status == "awaiting_rescue" then
            -- Check expiration
            if time >= pilot.expirationTime then
                pilot.status = "expired"
                debugLog("%s expired (survival time elapsed)", pilot.name)

                trigger.action.outTextForCoalition(
                    DMS.Rescue.Config.playerCoalition,
                    string.format("CSAR UPDATE: %s is no longer responding. Rescue operation cancelled.",
                        pilot.name),
                    15,
                    true
                )
            else
                -- Fire periodic flares
                if DMS.Rescue.Config.useFlares and
                   time - pilot.lastFlareTime >= DMS.Rescue.Config.flareInterval then
                    pilot.lastFlareTime = time
                    trigger.action.signalFlare(pilot.position, trigger.flareColor.Green, 0)
                end

                -- Check for rescue by helicopters or slow aircraft
                if rescuers then
                    for _, rescuer in ipairs(rescuers) do
                        if pilot.status ~= "awaiting_rescue" then break end
                        if unitAlive(rescuer) then
                            local rescuerPos = rescuer:getPoint()
                            local distance = getDistance(rescuerPos, pilot.position)
                            local altitude = rescuerPos.y - pilot.position.y

                            -- Must be close and low
                            if distance < DMS.Rescue.Config.rescueRadius and altitude < 50 then
                                -- Check if slow enough (hovering or landing)
                                local velocity = rescuer:getVelocity()
                                local speed = math.sqrt(velocity.x^2 + velocity.z^2)

                                if speed < 30 then  -- Less than ~60 knots
                                    -- Successful rescue!
                                    pilot.status = "rescued"
                                    pilot.rescuedBy = playerNameOf(rescuer) or "Unknown"
                                    debugLog("%s rescued by %s", pilot.name, pilot.rescuedBy)
                                    pilot.rescueTime = time

                                    if DMS.Rescue.Config.announceRescues then
                                        local msg = string.format(
                                            "CSAR SUCCESS!\n%s has been rescued by %s!\nRTB with survivor.",
                                            pilot.name,
                                            pilot.rescuedBy
                                        )

                                        trigger.action.outTextForCoalition(
                                            DMS.Rescue.Config.playerCoalition,
                                            msg,
                                            15,
                                            true
                                        )
                                    end

                                    -- Could set flag or trigger reward here
                                    trigger.action.setUserFlag("pilot_rescued_" .. pilotId, 1)
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    return time + DMS.Rescue.Config.checkInterval
end

--- Check for rescue opportunities with error handling
local function checkRescues(args, time)
    local success, result = pcall(checkRescuesInternal, args, time)
    if not success then
        logError("Rescue.checkRescues", result)
        return time + (DMS.Rescue.Config.checkInterval or 10)
    end
    return result
end

--- Start rescue coordination
function DMS.Rescue.start()
    if DMS.Rescue.Active then
        return
    end

    DMS.Rescue.Active = true

    -- Wrap event handler with error protection
    if not DMS.Rescue.EventHandler then
        DMS.Rescue.EventHandler = protectHandler(
            DMS.Rescue._EventHandlerInternal,
            "Rescue.EventHandler"
        )
        world.addEventHandler(DMS.Rescue.EventHandler)
    end

    DMS.Rescue.TimerId = timer.scheduleFunction(
        checkRescues,
        nil,
        timer.getTime() + DMS.Rescue.Config.checkInterval
    )
    debugLog("Started (survival %ds, radius %dm, interval %ds)",
        DMS.Rescue.Config.pilotSurvivalTime, DMS.Rescue.Config.rescueRadius, DMS.Rescue.Config.checkInterval)
end

--- Stop rescue coordination
function DMS.Rescue.stop()
    DMS.Rescue.Active = false
    if DMS.Rescue.TimerId then
        timer.removeFunction(DMS.Rescue.TimerId)
        DMS.Rescue.TimerId = nil
    end
    debugLog("Stopped")
end

--- Get list of active downed pilots
-- @return table Array of downed pilots awaiting rescue
function DMS.Rescue.getActivePilots()
    local active = {}
    for _, pilot in pairs(DMS.Rescue.DownedPilots) do
        if pilot.status == "awaiting_rescue" then
            table.insert(active, pilot)
        end
    end
    return active
end

--- Send text to a group if given, else to the player coalition
local function sendText(groupId, msg, duration)
    if groupId then
        trigger.action.outTextForGroup(groupId, msg, duration, true)
    else
        trigger.action.outTextForCoalition(DMS.Rescue.Config.playerCoalition, msg, duration, true)
    end
end

--- Display CSAR status
-- @param groupId number|nil Group to show it to (nil = coalition)
function DMS.Rescue.showStatus(groupId)
    local active = DMS.Rescue.getActivePilots()
    local lines = {"=== CSAR STATUS ===", ""}

    if #active > 0 then
        for _, pilot in ipairs(active) do
            local timeRemaining = pilot.expirationTime - timer.getTime()
            local mins = math.floor(timeRemaining / 60)
            local grid = getGridReference(pilot.position)

            table.insert(lines, string.format("%s - Grid: %s", pilot.name, grid))
            table.insert(lines, string.format("  Time remaining: %d minutes", mins))
        end
    else
        table.insert(lines, "No active CSAR operations.")
    end

    -- Show rescued count
    local rescuedCount = 0
    for _, pilot in pairs(DMS.Rescue.DownedPilots) do
        if pilot.status == "rescued" then
            rescuedCount = rescuedCount + 1
        end
    end

    if rescuedCount > 0 then
        table.insert(lines, "")
        table.insert(lines, string.format("Pilots rescued this mission: %d", rescuedCount))
    end

    sendText(groupId, table.concat(lines, "\n"), 20)
end

--- Mark smoke at pilot location (refresh)
-- @param pilotId string Pilot ID
-- @param groupId number|nil Group to notify (nil = coalition)
function DMS.Rescue.markPilot(pilotId, groupId)
    local pilot = DMS.Rescue.DownedPilots[pilotId]
    if pilot and pilot.status == "awaiting_rescue" then
        trigger.action.smoke(pilot.position, DMS.Rescue.Config.smokeColor)

        sendText(groupId, string.format("Smoke marker refreshed for %s", pilot.name), 5)
    end
end

--- Get rescue statistics
-- @return table Rescue stats
function DMS.Rescue.getStats()
    local stats = {
        total = 0,
        awaiting = 0,
        rescued = 0,
        expired = 0,
    }

    for _, pilot in pairs(DMS.Rescue.DownedPilots) do
        stats.total = stats.total + 1
        if pilot.status == "awaiting_rescue" then
            stats.awaiting = stats.awaiting + 1
        elseif pilot.status == "rescued" then
            stats.rescued = stats.rescued + 1
        elseif pilot.status == "expired" then
            stats.expired = stats.expired + 1
        end
    end

    return stats
end

--- Mark the survivor nearest to the calling group
-- @param groupName string Calling group name
function DMS.Rescue.markNearestFor(groupName)
    local active = DMS.Rescue.getActivePilots()
    local unit = getGroupUnit(groupName)
    local group = groupName and Group.getByName(groupName)
    local groupId = group and group:isExist() and group:getID() or nil
    if #active == 0 then
        sendText(groupId, "No active CSAR operations.", 5)
        return
    end
    local best, bestDist = active[1], math.huge
    if unit then
        local pos = unit:getPoint()
        for _, pilot in ipairs(active) do
            local dist = getDistance(pos, pilot.position)
            if dist < bestDist then best, bestDist = pilot, dist end
        end
    end
    DMS.Rescue.markPilot(best.id, groupId)
end

--- Build the CSAR menu for one player group (used by setupMenus)
local function buildGroupMenu(groupId, groupName)
    local menu = missionCommands.addSubMenuForGroup(groupId, "CSAR")
    missionCommands.addCommandForGroup(groupId, "CSAR Status", menu, function()
        local ok, err = pcall(DMS.Rescue.showStatus, groupId)
        if not ok then logError("Rescue.menu.status", err) end
    end)
    missionCommands.addCommandForGroup(groupId, "Mark Nearest Survivor", menu, function()
        local ok, err = pcall(DMS.Rescue.markNearestFor, groupName)
        if not ok then logError("Rescue.menu.mark", err) end
    end)
end

-- ============================================================
-- PER-GROUP F10 MENUS
-- Coalition menus cannot tell who pressed them, so menus are built per
-- player group on S_EVENT_BIRTH / S_EVENT_PLAYER_ENTER_UNIT (deduped by
-- group id) and callbacks receive the group name.
-- ============================================================

DMS.Rescue.MenuGroups = DMS.Rescue.MenuGroups or {}
DMS.Rescue.MenuEventHandler = nil

local function ensureGroupMenu(unit)
    if not playerNameOf(unit) then return end
    local okC, side = pcall(unit.getCoalition, unit)
    if not okC or side ~= DMS.Rescue.Config.playerCoalition then return end
    local group = unit:getGroup()
    if not group or not group:isExist() then return end
    local groupId = group:getID()
    local groupName = group:getName()
    if DMS.Rescue.MenuGroups[groupId] then return end
    local ok, err = pcall(buildGroupMenu, groupId, groupName)
    if ok then
        DMS.Rescue.MenuGroups[groupId] = true
        debugLog("Menu built for group '%s' (id %d)", groupName, groupId)
    else
        logError("Rescue.buildGroupMenu", err)
    end
end

--- Register the F10 menus (call once from mission init, not at load time)
function DMS.Rescue.setupMenus()
    if DMS.Rescue.MenuEventHandler then return end
    DMS.Rescue.MenuEventHandler = protectHandler({
        onEvent = function(_, event)
            if event.id == world.event.S_EVENT_BIRTH or
               event.id == world.event.S_EVENT_PLAYER_ENTER_UNIT then
                ensureGroupMenu(event.initiator)
            end
        end
    }, "Rescue.MenuEventHandler")
    world.addEventHandler(DMS.Rescue.MenuEventHandler)

    -- Catch players already in their aircraft
    for _, unit in ipairs(coalition.getPlayers(DMS.Rescue.Config.playerCoalition) or {}) do
        ensureGroupMenu(unit)
    end
    debugLog("Per-group menus enabled")
end

--[[
USAGE EXAMPLE:

-- Configure
DMS.Rescue.configure({
    trackAIPilots = false,       -- Only player pilots
    pilotSurvivalTime = 2400,    -- 40 minutes
    rescueRadius = 300,          -- 300m pickup radius
    smokeOnEjection = true,
    useFlares = true,
    flareInterval = 180          -- Flare every 3 minutes
})

-- Start system
DMS.Rescue.start()

-- Add per-group F10 menus (CSAR Status / Mark Nearest Survivor)
DMS.Rescue.setupMenus()

-- For helicopter CSAR missions, the rescue happens automatically
-- when the helicopter hovers low and slow near the survivor
]]

-- Export
_G.DMS = DMS
