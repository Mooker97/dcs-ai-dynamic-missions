-- Damage Reporter System for DCS Missions
-- Report aircraft damage status to players
-- Requires: utils/messaging.lua
-- Place in mission via DO SCRIPT FILE

DMS = DMS or {}
DMS.Damage = {}

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
    if unit and unit:isExist() and unit.getLife and unit.getLife0 then
        local life = unit:getLife()
        local life0 = unit:getLife0()
        if life0 > 0 then
            return life / life0
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
    local group = unit:getGroup()
    if group then
        trigger.action.outTextForGroup(group:getID(), msg, 10)
    end
end

--- Create event handler for hit detection
local function createEventHandler()
    local handler = {}

    function handler:onEvent(event)
        if not DMS.Damage.Active then
            return
        end

        -- Track hits on players
        if event.id == world.event.S_EVENT_HIT then
            local target = event.target

            if target and target.getPlayerName then
                local playerName = target:getPlayerName()
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

    return handler
end

--- Periodic damage check
local function periodicCheck(_, time)
    if not DMS.Damage.Active or not DMS.Damage.Config.reportPeriodic then
        return nil
    end

    local players = coalition.getPlayers(DMS.Damage.Config.playerCoalition)

    if players then
        for _, unit in ipairs(players) do
            if unit:isExist() then
                local playerName = unit:getPlayerName()
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

--- Start damage reporter
function DMS.Damage.start()
    if DMS.Damage.Active then
        return
    end

    DMS.Damage.Active = true

    -- Add event handler
    DMS.Damage.EventHandler = createEventHandler()
    world.addEventHandler(DMS.Damage.EventHandler)

    -- Start periodic checker
    if DMS.Damage.Config.reportPeriodic then
        DMS.Damage.TimerId = timer.scheduleFunction(
            periodicCheck,
            nil,
            timer.getTime() + DMS.Damage.Config.checkInterval
        )
    end
end

--- Stop damage reporter
function DMS.Damage.stop()
    DMS.Damage.Active = false
    if DMS.Damage.TimerId then
        timer.removeFunction(DMS.Damage.TimerId)
        DMS.Damage.TimerId = nil
    end
end

--- Request damage report for player
-- @param playerName string Player name
function DMS.Damage.requestReport(playerName)
    local players = coalition.getPlayers(DMS.Damage.Config.playerCoalition)

    if players then
        for _, unit in ipairs(players) do
            if unit:isExist() and unit:getPlayerName() == playerName then
                reportDamage(playerName, unit, "Manual damage report requested")
                return
            end
        end
    end

    trigger.action.outTextForCoalition(
        DMS.Damage.Config.playerCoalition,
        "Player not found: " .. playerName,
        5,
        true
    )
end

--- Show damage status for all players
function DMS.Damage.showAllStatus()
    local players = coalition.getPlayers(DMS.Damage.Config.playerCoalition)
    local lines = {"=== FLIGHT DAMAGE STATUS ===", ""}

    if players and #players > 0 then
        for _, unit in ipairs(players) do
            if unit:isExist() then
                local playerName = unit:getPlayerName()
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
            if unit:isExist() and unit:getPlayerName() == playerName then
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

-- Add F10 menu commands
local dmgMenu = missionCommands.addSubMenuForCoalition(coalition.side.BLUE, "Damage")

missionCommands.addCommandForCoalition(coalition.side.BLUE, "Flight Status", dmgMenu,
    function() DMS.Damage.showAllStatus() end)

missionCommands.addCommandForCoalition(coalition.side.BLUE, "My Damage Report", dmgMenu,
    function()
        local players = coalition.getPlayers(coalition.side.BLUE)
        if players and #players > 0 then
            local name = players[1]:getPlayerName()
            if name then DMS.Damage.requestReport(name) end
        end
    end)
]]

-- Export
_G.DMS = DMS
