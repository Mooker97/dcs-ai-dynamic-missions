-- Fuel Monitor System for DCS Missions
-- Track player fuel and provide warnings
-- Requires: utils/messaging.lua
-- Place in mission via DO SCRIPT FILE

DMS = DMS or {}
DMS.Fuel = {}

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
    if unit and unit:isExist() and unit.getFuel then
        return unit:getFuel()
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
        local group = unit:getGroup()
        if group then
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

--- Process fuel checks
local function processFuelChecks(_, time)
    if not DMS.Fuel.Active then
        return nil
    end

    local players = coalition.getPlayers(DMS.Fuel.Config.playerCoalition)

    if players then
        for _, unit in ipairs(players) do
            if unit:isExist() then
                local playerName = unit:getPlayerName()
                if playerName then
                    checkPlayerFuel(playerName, unit)
                end
            end
        end
    end

    return time + DMS.Fuel.Config.checkInterval
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
end

--- Stop fuel monitoring
function DMS.Fuel.stop()
    DMS.Fuel.Active = false
    if DMS.Fuel.TimerId then
        timer.removeFunction(DMS.Fuel.TimerId)
        DMS.Fuel.TimerId = nil
    end
end

--- Get current fuel status for a player
-- @param playerName string Player name
-- @return table|nil Fuel status
function DMS.Fuel.getStatus(playerName)
    local players = coalition.getPlayers(DMS.Fuel.Config.playerCoalition)

    if players then
        for _, unit in ipairs(players) do
            if unit:isExist() and unit:getPlayerName() == playerName then
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
function DMS.Fuel.showAllStatus()
    local players = coalition.getPlayers(DMS.Fuel.Config.playerCoalition)
    local lines = {"=== FLIGHT FUEL STATUS ===", ""}

    if players and #players > 0 then
        for _, unit in ipairs(players) do
            if unit:isExist() then
                local playerName = unit:getPlayerName()
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

    trigger.action.outTextForCoalition(
        DMS.Fuel.Config.playerCoalition,
        table.concat(lines, "\n"),
        15,
        true
    )
end

--- Request individual fuel check
-- @param playerName string Player name
function DMS.Fuel.requestStatus(playerName)
    local status = DMS.Fuel.getStatus(playerName)

    if status then
        local msg = string.format("FUEL CHECK: %s - %s (%s)",
            playerName, status.percentageDisplay, status.level)

        trigger.action.outTextForCoalition(
            DMS.Fuel.Config.playerCoalition,
            msg,
            10,
            true
        )
    end
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

-- Add F10 menu commands
local fuelMenu = missionCommands.addSubMenuForCoalition(coalition.side.BLUE, "Fuel")

missionCommands.addCommandForCoalition(coalition.side.BLUE, "Flight Fuel Status", fuelMenu,
    function() DMS.Fuel.showAllStatus() end)

missionCommands.addCommandForCoalition(coalition.side.BLUE, "My Fuel Status", fuelMenu,
    function()
        local players = coalition.getPlayers(coalition.side.BLUE)
        if players and #players > 0 then
            local name = players[1]:getPlayerName()
            if name then DMS.Fuel.requestStatus(name) end
        end
    end)
]]

-- Export
_G.DMS = DMS
