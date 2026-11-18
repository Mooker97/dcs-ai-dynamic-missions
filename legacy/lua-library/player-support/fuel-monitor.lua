-- Fuel Monitor System for DCS Missions
-- Track player fuel and provide warnings
-- Requires: utils/messaging.lua
-- Place in mission via DO SCRIPT FILE

DMS = DMS or {}
DMS.Fuel = {}

-- ============================================================
-- LOCAL HELPERS (no cross-module dependencies)
-- ============================================================

local LOG_PREFIX = "[Fuel]"

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

-- Tracked players
DMS.Fuel.Players = {}
DMS.Fuel.Active = false
DMS.Fuel.TimerId = nil

-- Configuration
DMS.Fuel.Config = {
    playerCoalition = coalition.side.BLUE,
    checkInterval = 30,          -- Check fuel every 30 seconds
    warningThreshold = 0.30,     -- 30% fuel warning
    criticalThreshold = 0.15,    -- 15% critical warning
    bingoThreshold = 0.10,       -- 10% bingo fuel
    showPercentage = true,
    showPoundage = true,
    repeatWarnings = true,
    repeatInterval = 120,        -- Seconds between repeat warnings
}

-- Warning states per player
local warningStates = {}

--- Configure fuel monitor
-- @param settings table Configuration overrides
function DMS.Fuel.configure(settings)
    for key, value in pairs(settings) do
        DMS.Fuel.Config[key] = value
    end
end

--- Get fuel percentage for a unit
-- @param unit table DCS unit
-- @return number Fuel percentage (0-1)
local function getFuelPercentage(unit)
    if unitAlive(unit) and unit.getFuel then
        local ok, fuel = pcall(unit.getFuel, unit)
        if ok and type(fuel) == "number" then
            return fuel
        end
    end
    return 1.0
end

--- Format fuel message
-- @param playerName string Player name
-- @param fuelPct number Fuel percentage
-- @param level string Warning level
-- @return string Formatted message
local function formatFuelMessage(playerName, fuelPct, level)
    local msg = string.format("FUEL %s: %s - ", level, playerName)

    if DMS.Fuel.Config.showPercentage then
        msg = msg .. string.format("%.0f%%", fuelPct * 100)
    end

    if level == "BINGO" then
        msg = msg .. " - RTB IMMEDIATELY"
    elseif level == "CRITICAL" then
        msg = msg .. " - Consider RTB"
    elseif level == "LOW" then
        msg = msg .. " - Monitor fuel state"
    end

    return msg
end

--- Check and warn player about fuel
-- @param playerName string Player name
-- @param unit table DCS unit
local function checkPlayerFuel(playerName, unit)
    local fuelPct = getFuelPercentage(unit)

    if not warningStates[playerName] then
        warningStates[playerName] = {
            lastWarningTime = 0,
            lastLevel = nil,
        }
    end

    local state = warningStates[playerName]
    local currentTime = timer.getTime()
    local shouldWarn = false
    local level = nil

    -- Determine warning level
    if fuelPct <= DMS.Fuel.Config.bingoThreshold then
        level = "BINGO"
    elseif fuelPct <= DMS.Fuel.Config.criticalThreshold then
        level = "CRITICAL"
    elseif fuelPct <= DMS.Fuel.Config.warningThreshold then
        level = "LOW"
    end

    -- Decide if we should warn
    if level then
        if state.lastLevel ~= level then
            -- New warning level
            shouldWarn = true
        elseif DMS.Fuel.Config.repeatWarnings and
               currentTime - state.lastWarningTime >= DMS.Fuel.Config.repeatInterval then
            -- Repeat warning
            shouldWarn = true
        end
    end

    -- Send warning
    if shouldWarn then
        state.lastLevel = level
        state.lastWarningTime = currentTime

        local msg = formatFuelMessage(playerName, fuelPct, level)

        -- Try to send to specific player's group
        debugLog("%s fuel %s (%.0f%%)", playerName, level, fuelPct * 100)
        local group = unitAlive(unit) and unit:getGroup() or nil
        if group and group:isExist() then
            trigger.action.outTextForGroup(group:getID(), msg, 15)
        else
            trigger.action.outTextForCoalition(
                DMS.Fuel.Config.playerCoalition,
                msg,
                15,
                true
            )
        end
    end

    -- Clear warning state if fuel recovered
    if not level then
        state.lastLevel = nil
    end

    return fuelPct
end

--- Process fuel checks (internal)
local function processFuelChecksInternal(_, time)
    if not DMS.Fuel.Active then
        return nil
    end

    local players = coalition.getPlayers(DMS.Fuel.Config.playerCoalition)

    if players then
        for _, unit in ipairs(players) do
            if unitAlive(unit) then
                local playerName = playerNameOf(unit)
                if playerName then
                    checkPlayerFuel(playerName, unit)
                end
            end
        end
    end

    return time + DMS.Fuel.Config.checkInterval
end

--- Process fuel checks with error handling
local function processFuelChecks(args, time)
    local success, result = pcall(processFuelChecksInternal, args, time)
    if not success then
        logError("Fuel.processFuelChecks", result)
        return time + (DMS.Fuel.Config.checkInterval or 30)
    end
    return result
end

--- Start fuel monitoring
function DMS.Fuel.start()
    if DMS.Fuel.Active then
        return
    end

    DMS.Fuel.Active = true

    DMS.Fuel.TimerId = timer.scheduleFunction(
        processFuelChecks,
        nil,
        timer.getTime() + DMS.Fuel.Config.checkInterval
    )
    debugLog("Started (interval %ds, low %.0f%%, critical %.0f%%, bingo %.0f%%)",
        DMS.Fuel.Config.checkInterval, DMS.Fuel.Config.warningThreshold * 100,
        DMS.Fuel.Config.criticalThreshold * 100, DMS.Fuel.Config.bingoThreshold * 100)
end

--- Stop fuel monitoring
function DMS.Fuel.stop()
    DMS.Fuel.Active = false
    if DMS.Fuel.TimerId then
        timer.removeFunction(DMS.Fuel.TimerId)
        DMS.Fuel.TimerId = nil
    end
    debugLog("Stopped")
end

--- Get current fuel status for a player
-- @param playerName string Player name
-- @return table|nil Fuel status
function DMS.Fuel.getStatus(playerName)
    local players = coalition.getPlayers(DMS.Fuel.Config.playerCoalition)

    if players then
        for _, unit in ipairs(players) do
            if playerNameOf(unit) == playerName then
                local fuelPct = getFuelPercentage(unit)
                local level = "OK"

                if fuelPct <= DMS.Fuel.Config.bingoThreshold then
                    level = "BINGO"
                elseif fuelPct <= DMS.Fuel.Config.criticalThreshold then
                    level = "CRITICAL"
                elseif fuelPct <= DMS.Fuel.Config.warningThreshold then
                    level = "LOW"
                end

                return {
                    percentage = fuelPct,
                    percentageDisplay = string.format("%.0f%%", fuelPct * 100),
                    level = level,
                }
            end
        end
    end

    return nil
end

--- Display fuel status to all players
-- @param groupId number|nil Show only to this group (nil = coalition)
function DMS.Fuel.showAllStatus(groupId)
    local players = coalition.getPlayers(DMS.Fuel.Config.playerCoalition)
    local lines = {"=== FLIGHT FUEL STATUS ===", ""}

    if players and #players > 0 then
        for _, unit in ipairs(players) do
            if unitAlive(unit) then
                local playerName = playerNameOf(unit)
                if playerName then
                    local fuelPct = getFuelPercentage(unit)
                    local indicator = ""

                    if fuelPct <= DMS.Fuel.Config.bingoThreshold then
                        indicator = " [BINGO!]"
                    elseif fuelPct <= DMS.Fuel.Config.criticalThreshold then
                        indicator = " [CRITICAL]"
                    elseif fuelPct <= DMS.Fuel.Config.warningThreshold then
                        indicator = " [LOW]"
                    end

                    table.insert(lines, string.format("%s: %.0f%%%s",
                        playerName, fuelPct * 100, indicator))
                end
            end
        end
    else
        table.insert(lines, "No players found.")
    end

    if groupId then
        trigger.action.outTextForGroup(groupId, table.concat(lines, "\n"), 15, true)
        return
    end

    trigger.action.outTextForCoalition(
        DMS.Fuel.Config.playerCoalition,
        table.concat(lines, "\n"),
        15,
        true
    )
end

--- Request individual fuel check
-- @param playerName string Player name
-- @param groupId number|nil Send only to this group (nil = coalition)
function DMS.Fuel.requestStatus(playerName, groupId)
    local status = DMS.Fuel.getStatus(playerName)

    if status then
        local msg = string.format("FUEL CHECK: %s - %s (%s)",
            playerName, status.percentageDisplay, status.level)

        if groupId then
            trigger.action.outTextForGroup(groupId, msg, 10, true)
        else
            trigger.action.outTextForCoalition(DMS.Fuel.Config.playerCoalition, msg, 10, true)
        end
    end
end

--- Fuel check for the player in a given group (per-group menu callback)
-- @param groupName string Calling group name
function DMS.Fuel.requestStatusForGroup(groupName)
    local unit = getGroupUnit(groupName)
    if not unit then return end
    local group = unit:getGroup()
    local groupId = group and group:getID() or nil
    local name = playerNameOf(unit)
    if name then
        DMS.Fuel.requestStatus(name, groupId)
    elseif groupId then
        trigger.action.outTextForGroup(groupId,
            string.format("FUEL CHECK: %.0f%%", getFuelPercentage(unit) * 100), 10, true)
    end
end

--- Build the Fuel menu for one player group (used by setupMenus)
local function buildGroupMenu(groupId, groupName)
    local menu = missionCommands.addSubMenuForGroup(groupId, "Fuel")
    missionCommands.addCommandForGroup(groupId, "Flight Fuel Status", menu, function()
        local ok, err = pcall(DMS.Fuel.showAllStatus, groupId)
        if not ok then logError("Fuel.menu.flightStatus", err) end
    end)
    missionCommands.addCommandForGroup(groupId, "My Fuel Status", menu, function()
        local ok, err = pcall(DMS.Fuel.requestStatusForGroup, groupName)
        if not ok then logError("Fuel.menu.myStatus", err) end
    end)
end

-- ============================================================
-- PER-GROUP F10 MENUS
-- Coalition menus cannot tell who pressed them, so menus are built per
-- player group on S_EVENT_BIRTH / S_EVENT_PLAYER_ENTER_UNIT (deduped by
-- group id) and callbacks receive the group name.
-- ============================================================

DMS.Fuel.MenuGroups = DMS.Fuel.MenuGroups or {}
DMS.Fuel.MenuEventHandler = nil

local function ensureGroupMenu(unit)
    if not playerNameOf(unit) then return end
    local okC, side = pcall(unit.getCoalition, unit)
    if not okC or side ~= DMS.Fuel.Config.playerCoalition then return end
    local group = unit:getGroup()
    if not group or not group:isExist() then return end
    local groupId = group:getID()
    local groupName = group:getName()
    if DMS.Fuel.MenuGroups[groupId] then return end
    local ok, err = pcall(buildGroupMenu, groupId, groupName)
    if ok then
        DMS.Fuel.MenuGroups[groupId] = true
        debugLog("Menu built for group '%s' (id %d)", groupName, groupId)
    else
        logError("Fuel.buildGroupMenu", err)
    end
end

--- Register the F10 menus (call once from mission init, not at load time)
function DMS.Fuel.setupMenus()
    if DMS.Fuel.MenuEventHandler then return end
    DMS.Fuel.MenuEventHandler = protectHandler({
        onEvent = function(_, event)
            if event.id == world.event.S_EVENT_BIRTH or
               event.id == world.event.S_EVENT_PLAYER_ENTER_UNIT then
                ensureGroupMenu(event.initiator)
            end
        end
    }, "Fuel.MenuEventHandler")
    world.addEventHandler(DMS.Fuel.MenuEventHandler)

    -- Catch players already in their aircraft
    for _, unit in ipairs(coalition.getPlayers(DMS.Fuel.Config.playerCoalition) or {}) do
        ensureGroupMenu(unit)
    end
    debugLog("Per-group menus enabled")
end

--[[
USAGE EXAMPLE:

-- Configure
DMS.Fuel.configure({
    checkInterval = 20,
    warningThreshold = 0.35,     -- 35%
    criticalThreshold = 0.20,    -- 20%
    bingoThreshold = 0.12,       -- 12%
    repeatWarnings = true,
    repeatInterval = 90
})

-- Start monitoring
DMS.Fuel.start()

-- Add per-group F10 menus (Flight Fuel Status / My Fuel Status)
DMS.Fuel.setupMenus()
]]

-- Export
_G.DMS = DMS
