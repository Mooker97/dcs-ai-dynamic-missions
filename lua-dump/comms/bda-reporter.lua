-- Battle Damage Assessment Reporter for DCS Missions
-- Provides strike feedback to players
-- Requires: utils/messaging.lua
-- Place in mission via DO SCRIPT FILE

DMS = DMS or {}
DMS.BDA = {}

-- State
DMS.BDA.EventHandler = nil
DMS.BDA.Active = false
DMS.BDA.Stats = {
    groundKills = 0,
    airKills = 0,
    shipKills = 0,
    friendlyFire = 0,
}

-- Track pending BDA for delayed reporting
DMS.BDA.PendingReports = {}

-- Configuration
DMS.BDA.Config = {
    reportDelay = 3,             -- Seconds delay before BDA report
    observerCallsign = "Warhawk",
    playerCoalition = coalition.side.BLUE,
    reportGroundKills = true,
    reportAirKills = true,
    reportShipKills = true,
    reportFriendlyFire = true,
    groupKillsByType = true,     -- Group "2 vehicles destroyed" vs individual
    showKillType = true,         -- Show what type was destroyed
}

-- Kill aggregation for grouped reporting
DMS.BDA.KillBuffer = {}
DMS.BDA.BufferTimer = nil

-- Type category mapping
local function getCategoryName(category)
    if category == Unit.Category.AIRPLANE then return "aircraft"
    elseif category == Unit.Category.HELICOPTER then return "helicopter"
    elseif category == Unit.Category.GROUND_UNIT then return "vehicle"
    elseif category == Unit.Category.SHIP then return "ship"
    elseif category == Unit.Category.STRUCTURE then return "structure"
    else return "target"
    end
end

--- Configure BDA system
-- @param settings table Configuration overrides
function DMS.BDA.configure(settings)
    for key, value in pairs(settings) do
        DMS.BDA.Config[key] = value
    end
end

--- Generate BDA message
-- @param attackerName string Attacker callsign
-- @param targetType string Type of target
-- @param count number Number destroyed
-- @param category string Category name
-- @return string BDA message
local function generateBDAMessage(attackerName, targetType, count, category)
    local callsign = DMS.BDA.Config.observerCallsign

    if count > 1 then
        return string.format('%s: %s, good hits. %d %ss destroyed.',
            callsign, attackerName, count, category)
    else
        if DMS.BDA.Config.showKillType and targetType then
            return string.format('%s: %s, good hits on %s. Target destroyed.',
                callsign, attackerName, targetType)
        else
            return string.format('%s: %s, good hits. Target destroyed.',
                callsign, attackerName)
        end
    end
end

--- Generate friendly fire warning
-- @param attackerName string Attacker callsign
-- @return string Warning message
local function generateFriendlyFireMessage(attackerName)
    return string.format('*** WARNING *** %s, CEASE FIRE! You hit friendlies!', attackerName)
end

--- Process buffered kills
local function processKillBuffer()
    if not DMS.BDA.Active then
        return
    end

    for attackerKey, data in pairs(DMS.BDA.KillBuffer) do
        local msg = generateBDAMessage(
            data.attackerName,
            data.lastType,
            data.count,
            data.category
        )

        trigger.action.outTextForCoalition(
            DMS.BDA.Config.playerCoalition,
            msg,
            10,
            true
        )
    end

    DMS.BDA.KillBuffer = {}
    DMS.BDA.BufferTimer = nil
end

--- Add kill to buffer for grouped reporting
-- @param attackerName string Attacker name
-- @param targetType string Target type name
-- @param category string Category name
local function addToKillBuffer(attackerName, targetType, category)
    local key = attackerName .. "_" .. category

    if not DMS.BDA.KillBuffer[key] then
        DMS.BDA.KillBuffer[key] = {
            attackerName = attackerName,
            category = category,
            lastType = targetType,
            count = 0
        }
    end

    DMS.BDA.KillBuffer[key].count = DMS.BDA.KillBuffer[key].count + 1
    DMS.BDA.KillBuffer[key].lastType = targetType

    -- Reset/start buffer timer
    if DMS.BDA.BufferTimer then
        timer.removeFunction(DMS.BDA.BufferTimer)
    end

    DMS.BDA.BufferTimer = timer.scheduleFunction(function()
        processKillBuffer()
        return nil
    end, nil, timer.getTime() + DMS.BDA.Config.reportDelay)
end

--- Create event handler
-- @return table Event handler object
local function createEventHandler()
    local handler = {}

    function handler:onEvent(event)
        if not DMS.BDA.Active then
            return
        end

        -- Only process kill events
        if event.id ~= world.event.S_EVENT_KILL then
            return
        end

        local initiator = event.initiator
        local target = event.target

        if not initiator or not target then
            return
        end

        -- Check if initiator is player
        local playerName = nil
        if initiator.getPlayerName then
            playerName = initiator:getPlayerName()
        end

        if not playerName then
            return  -- Not a player kill
        end

        -- Get initiator coalition
        local initiatorCoalition = initiator:getCoalition()
        local targetCoalition = target:getCoalition()

        -- Check for friendly fire
        if initiatorCoalition == targetCoalition then
            DMS.BDA.Stats.friendlyFire = DMS.BDA.Stats.friendlyFire + 1

            if DMS.BDA.Config.reportFriendlyFire then
                local msg = generateFriendlyFireMessage(playerName)
                trigger.action.outText(msg, 10, true)
            end
            return
        end

        -- Get target info
        local targetType = "unknown"
        if target.getTypeName then
            targetType = target:getTypeName()
        end

        local category = Unit.Category.GROUND_UNIT
        if target.getCategory then
            category = target:getCategory()
        end

        local categoryName = getCategoryName(category)

        -- Update stats
        if category == Unit.Category.AIRPLANE or category == Unit.Category.HELICOPTER then
            DMS.BDA.Stats.airKills = DMS.BDA.Stats.airKills + 1
            if not DMS.BDA.Config.reportAirKills then return end
        elseif category == Unit.Category.SHIP then
            DMS.BDA.Stats.shipKills = DMS.BDA.Stats.shipKills + 1
            if not DMS.BDA.Config.reportShipKills then return end
        else
            DMS.BDA.Stats.groundKills = DMS.BDA.Stats.groundKills + 1
            if not DMS.BDA.Config.reportGroundKills then return end
        end

        if DMS.Settings and DMS.Settings.isDebug() then
            env.info(string.format("[BDA] Kill recorded: %s destroyed %s (%s)",
                playerName, targetType, categoryName))
        end

        -- Report kill
        if DMS.BDA.Config.groupKillsByType then
            addToKillBuffer(playerName, targetType, categoryName)
        else
            -- Immediate individual report
            timer.scheduleFunction(function()
                local msg = generateBDAMessage(playerName, targetType, 1, categoryName)
                trigger.action.outTextForCoalition(
                    DMS.BDA.Config.playerCoalition,
                    msg,
                    10,
                    true
                )
                return nil
            end, nil, timer.getTime() + DMS.BDA.Config.reportDelay)
        end
    end

    return handler
end

--- Start BDA reporting
function DMS.BDA.start()
    if DMS.BDA.Active then
        return
    end

    DMS.BDA.Active = true
    DMS.BDA.EventHandler = createEventHandler()
    world.addEventHandler(DMS.BDA.EventHandler)

    if DMS.Settings and DMS.Settings.isDebug() then
        env.info(string.format("[BDA] Started reporting (callsign: %s, delay: %ds)",
            DMS.BDA.Config.observerCallsign, DMS.BDA.Config.reportDelay))
    end
end

--- Stop BDA reporting
function DMS.BDA.stop()
    DMS.BDA.Active = false
    -- Note: DCS doesn't have removeEventHandler, handler will check Active flag
end

--- Get kill statistics
-- @return table Kill stats
function DMS.BDA.getStats()
    return {
        ground = DMS.BDA.Stats.groundKills,
        air = DMS.BDA.Stats.airKills,
        ship = DMS.BDA.Stats.shipKills,
        friendlyFire = DMS.BDA.Stats.friendlyFire,
        total = DMS.BDA.Stats.groundKills + DMS.BDA.Stats.airKills + DMS.BDA.Stats.shipKills
    }
end

--- Reset statistics
function DMS.BDA.resetStats()
    DMS.BDA.Stats = {
        groundKills = 0,
        airKills = 0,
        shipKills = 0,
        friendlyFire = 0,
    }
end

--- Manual BDA report
-- @param playerCallsign string Player callsign
-- @param targetDesc string Target description
-- @param result string Result (e.g., "destroyed", "damaged")
function DMS.BDA.manualReport(playerCallsign, targetDesc, result)
    local msg = string.format('%s: %s, %s on %s. %s.',
        DMS.BDA.Config.observerCallsign,
        playerCallsign,
        result == "destroyed" and "good hits" or "hits observed",
        targetDesc,
        result == "destroyed" and "Target destroyed" or "Target " .. result
    )

    trigger.action.outTextForCoalition(
        DMS.BDA.Config.playerCoalition,
        msg,
        10,
        true
    )
end

--[[
USAGE EXAMPLE:

-- Configure
DMS.BDA.configure({
    observerCallsign = "Warhawk",
    reportDelay = 2,
    groupKillsByType = true,
    showKillType = true,
    reportGroundKills = true,
    reportAirKills = true,
    reportShipKills = true,
    reportFriendlyFire = true
})

-- Start BDA reporting
DMS.BDA.start()

-- Get stats at end of mission
local stats = DMS.BDA.getStats()
trigger.action.outText(string.format(
    "Mission Stats: Ground:%d Air:%d Ship:%d Total:%d",
    stats.ground, stats.air, stats.ship, stats.total
), 30)

-- Manual BDA for scripted events
DMS.BDA.manualReport("Viper 1-1", "enemy bunker", "destroyed")
]]

-- Export
_G.DMS = DMS
