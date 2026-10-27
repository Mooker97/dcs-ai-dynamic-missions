-- Damage Reporter System for DCS Missions
-- Report aircraft damage status to players
-- Requires: utils/messaging.lua
-- Place in mission via DO SCRIPT FILE

DMS = DMS or {}
DMS.Damage = {}

-- ============================================================
-- LOCAL HELPERS (no cross-module dependencies)
-- ============================================================

local LOG_PREFIX = "[Damage]"

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

-- Tracked damage
DMS.Damage.Players = {}
DMS.Damage.EventHandler = nil
DMS.Damage.Active = false
DMS.Damage.TimerId = nil

-- Configuration
DMS.Damage.Config = {
    playerCoalition = coalition.side.BLUE,
    checkInterval = 10,
    reportOnHit = true,          -- Report when hit
    reportPeriodic = true,       -- Periodic damage summary
    periodicInterval = 60,       -- Seconds between periodic reports
    damageThreshold = 0.90,      -- Report when below this health %
    criticalThreshold = 0.50,    -- Critical damage warning
}

--- Configure damage reporter
-- @param settings table Configuration overrides
function DMS.Damage.configure(settings)
    for key, value in pairs(settings) do
        DMS.Damage.Config[key] = value
    end
end

--- Get unit health percentage
-- @param unit table DCS unit
-- @return number Health percentage (0-1)
local function getHealthPercentage(unit)
    if unitAlive(unit) and unit.getLife and unit.getLife0 then
        local ok1, life = pcall(unit.getLife, unit)
        local ok2, life0 = pcall(unit.getLife0, unit)
        if ok1 and ok2 and life and life0 and life0 > 0 then
            return math.max(0, math.min(1, life / life0))
        end
    end
    return 1.0
end

--- Get damage status string
-- @param healthPct number Health percentage
-- @return string Status description
local function getDamageStatus(healthPct)
    if healthPct >= 0.95 then
        return "Nominal"
    elseif healthPct >= 0.80 then
        return "Light Damage"
    elseif healthPct >= 0.60 then
        return "Moderate Damage"
    elseif healthPct >= 0.40 then
        return "Heavy Damage"
    elseif healthPct >= 0.20 then
        return "Critical Damage"
    else
        return "Severe - RTB Immediately"
    end
end

--- Get or create player damage record
-- @param playerName string Player name
-- @return table Damage record
local function getPlayerRecord(playerName)
    if not DMS.Damage.Players[playerName] then
        DMS.Damage.Players[playerName] = {
            name = playerName,
            lastHealth = 1.0,
            hitCount = 0,
            lastHitTime = 0,
            lastReportTime = 0,
        }
    end
    return DMS.Damage.Players[playerName]
end

--- Report damage to player
-- @param playerName string Player name
-- @param unit table DCS unit
-- @param reason string|nil Reason for report
local function reportDamage(playerName, unit, reason)
    local healthPct = getHealthPercentage(unit)
    local status = getDamageStatus(healthPct)

    local msg = string.format("DAMAGE REPORT: %s\n", playerName)
    msg = msg .. string.format("Aircraft Status: %s (%.0f%% integrity)\n", status, healthPct * 100)

    if reason then
        msg = msg .. reason
    end

    if healthPct < DMS.Damage.Config.criticalThreshold then
        msg = msg .. "\nWARNING: Consider RTB for repairs!"
    end

    -- Send to player's group
    if not unitAlive(unit) then return end
    local group = unit:getGroup()
    if group and group:isExist() then
        trigger.action.outTextForGroup(group:getID(), msg, 10)
        debugLog("Damage report to %s: %.0f%% (%s)", playerName, healthPct * 100, status)
    end
end

--- Event handler for hit detection (internal)
DMS.Damage._EventHandlerInternal = {
    onEvent = function(self, event)
        if not DMS.Damage.Active then
            return
        end

        -- Track hits on players
        if event.id == world.event.S_EVENT_HIT then
            local target = event.target

            if target then
                local playerName = playerNameOf(target)
                if playerName then
                    local record = getPlayerRecord(playerName)
                    local currentHealth = getHealthPercentage(target)

                    record.hitCount = record.hitCount + 1
                    record.lastHitTime = timer.getTime()

                    -- Report if enabled and damage exceeds threshold
                    if DMS.Damage.Config.reportOnHit and
                       currentHealth < DMS.Damage.Config.damageThreshold then

                        local damageTaken = record.lastHealth - currentHealth
                        local reason = nil

                        if damageTaken > 0.10 then
                            reason = string.format("Significant damage received: -%.0f%%", damageTaken * 100)
                        end

                        reportDamage(playerName, target, reason)
                    end

                    record.lastHealth = currentHealth
                end
            end
        end
    end
}

--- Periodic damage check (internal)
local function periodicCheckInternal(_, time)
    if not DMS.Damage.Active or not DMS.Damage.Config.reportPeriodic then
        return nil
    end

    local players = coalition.getPlayers(DMS.Damage.Config.playerCoalition)

    if players then
        for _, unit in ipairs(players) do
            if unitAlive(unit) then
                local playerName = playerNameOf(unit)
                if playerName then
                    local record = getPlayerRecord(playerName)
                    local healthPct = getHealthPercentage(unit)

                    -- Only report if damaged
                    if healthPct < DMS.Damage.Config.damageThreshold then
                        local timeSinceReport = time - record.lastReportTime

                        if timeSinceReport >= DMS.Damage.Config.periodicInterval then
                            record.lastReportTime = time
                            reportDamage(playerName, unit, nil)
                        end
                    end

                    record.lastHealth = healthPct
                end
            end
        end
    end

    return time + DMS.Damage.Config.checkInterval
end

--- Periodic damage check with error handling
local function periodicCheck(args, time)
    local success, result = pcall(periodicCheckInternal, args, time)
    if not success then
        logError("Damage.periodicCheck", result)
        return time + (DMS.Damage.Config.checkInterval or 10)
    end
    return result
end

--- Start damage reporter
function DMS.Damage.start()
    if DMS.Damage.Active then
        return
    end

    DMS.Damage.Active = true

    -- Wrap event handler with error protection
    if not DMS.Damage.EventHandler then
        DMS.Damage.EventHandler = protectHandler(
            DMS.Damage._EventHandlerInternal,
            "Damage.EventHandler"
        )
        world.addEventHandler(DMS.Damage.EventHandler)
    end

    -- Start periodic checker
    if DMS.Damage.Config.reportPeriodic then
        DMS.Damage.TimerId = timer.scheduleFunction(
            periodicCheck,
            nil,
            timer.getTime() + DMS.Damage.Config.checkInterval
        )
    end
    debugLog("Started (onHit=%s, periodic=%s, interval %ds)",
        tostring(DMS.Damage.Config.reportOnHit), tostring(DMS.Damage.Config.reportPeriodic),
        DMS.Damage.Config.periodicInterval)
end

--- Stop damage reporter
function DMS.Damage.stop()
    DMS.Damage.Active = false
    if DMS.Damage.TimerId then
        timer.removeFunction(DMS.Damage.TimerId)
        DMS.Damage.TimerId = nil
    end
    debugLog("Stopped")
end

--- Request damage report for player
-- @param playerName string Player name
function DMS.Damage.requestReport(playerName)
    local players = coalition.getPlayers(DMS.Damage.Config.playerCoalition)

    if players then
        for _, unit in ipairs(players) do
            if playerNameOf(unit) == playerName then
                reportDamage(playerName, unit, "Manual damage report requested")
                return
            end
        end
    end

    trigger.action.outTextForCoalition(
        DMS.Damage.Config.playerCoalition,
        "Player not found: " .. tostring(playerName),
        5,
        true
    )
end

--- Damage report for the player in a given group (per-group menu callback)
-- @param groupName string Calling group name
function DMS.Damage.requestReportForGroup(groupName)
    local unit = getGroupUnit(groupName)
    if unit then
        reportDamage(playerNameOf(unit) or unit:getName(), unit, "Manual damage report requested")
    end
end

--- Show damage status for all players
-- @param groupId number|nil Show only to this group (nil = coalition)
function DMS.Damage.showAllStatus(groupId)
    local players = coalition.getPlayers(DMS.Damage.Config.playerCoalition)
    local lines = {"=== FLIGHT DAMAGE STATUS ===", ""}

    if players and #players > 0 then
        for _, unit in ipairs(players) do
            if unitAlive(unit) then
                local playerName = playerNameOf(unit)
                if playerName then
                    local healthPct = getHealthPercentage(unit)
                    local status = getDamageStatus(healthPct)

                    table.insert(lines, string.format("%s: %s (%.0f%%)",
                        playerName, status, healthPct * 100))
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
        DMS.Damage.Config.playerCoalition,
        table.concat(lines, "\n"),
        15,
        true
    )
end

--- Get damage statistics for player
-- @param playerName string Player name
-- @return table|nil Damage stats
function DMS.Damage.getStats(playerName)
    local record = DMS.Damage.Players[playerName]
    if not record then
        return nil
    end

    local players = coalition.getPlayers(DMS.Damage.Config.playerCoalition)
    local currentHealth = 1.0

    if players then
        for _, unit in ipairs(players) do
            if playerNameOf(unit) == playerName then
                currentHealth = getHealthPercentage(unit)
                break
            end
        end
    end

    return {
        name = playerName,
        currentHealth = currentHealth,
        status = getDamageStatus(currentHealth),
        hitCount = record.hitCount,
        timeSinceLastHit = timer.getTime() - record.lastHitTime,
    }
end

--- Build the Damage menu for one player group (used by setupMenus)
local function buildGroupMenu(groupId, groupName)
    local menu = missionCommands.addSubMenuForGroup(groupId, "Damage")
    missionCommands.addCommandForGroup(groupId, "Flight Status", menu, function()
        local ok, err = pcall(DMS.Damage.showAllStatus, groupId)
        if not ok then logError("Damage.menu.flightStatus", err) end
    end)
    missionCommands.addCommandForGroup(groupId, "My Damage Report", menu, function()
        local ok, err = pcall(DMS.Damage.requestReportForGroup, groupName)
        if not ok then logError("Damage.menu.myReport", err) end
    end)
end

-- ============================================================
-- PER-GROUP F10 MENUS
-- Coalition menus cannot tell who pressed them, so menus are built per
-- player group on S_EVENT_BIRTH / S_EVENT_PLAYER_ENTER_UNIT (deduped by
-- group id) and callbacks receive the group name.
-- ============================================================

DMS.Damage.MenuGroups = DMS.Damage.MenuGroups or {}
DMS.Damage.MenuEventHandler = nil

local function ensureGroupMenu(unit)
    if not playerNameOf(unit) then return end
    local okC, side = pcall(unit.getCoalition, unit)
    if not okC or side ~= DMS.Damage.Config.playerCoalition then return end
    local group = unit:getGroup()
    if not group or not group:isExist() then return end
    local groupId = group:getID()
    local groupName = group:getName()
    if DMS.Damage.MenuGroups[groupId] then return end
    local ok, err = pcall(buildGroupMenu, groupId, groupName)
    if ok then
        DMS.Damage.MenuGroups[groupId] = true
        debugLog("Menu built for group '%s' (id %d)", groupName, groupId)
    else
        logError("Damage.buildGroupMenu", err)
    end
end

--- Register the F10 menus (call once from mission init, not at load time)
function DMS.Damage.setupMenus()
    if DMS.Damage.MenuEventHandler then return end
    DMS.Damage.MenuEventHandler = protectHandler({
        onEvent = function(_, event)
            if event.id == world.event.S_EVENT_BIRTH or
               event.id == world.event.S_EVENT_PLAYER_ENTER_UNIT then
                ensureGroupMenu(event.initiator)
            end
        end
    }, "Damage.MenuEventHandler")
    world.addEventHandler(DMS.Damage.MenuEventHandler)

    -- Catch players already in their aircraft
    for _, unit in ipairs(coalition.getPlayers(DMS.Damage.Config.playerCoalition) or {}) do
        ensureGroupMenu(unit)
    end
    debugLog("Per-group menus enabled")
end

--[[
USAGE EXAMPLE:

-- Configure
DMS.Damage.configure({
    reportOnHit = true,
    reportPeriodic = true,
    periodicInterval = 45,
    damageThreshold = 0.95,      -- Report any damage
    criticalThreshold = 0.50
})

-- Start reporter
DMS.Damage.start()

-- Add per-group F10 menus (Flight Status / My Damage Report)
DMS.Damage.setupMenus()
]]

-- Export
_G.DMS = DMS
