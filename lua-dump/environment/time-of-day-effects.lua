-- Time of Day Effects System for DCS Missions
-- Adjusts mission elements based on time of day
-- Requires: utils/messaging.lua
-- Place in mission via DO SCRIPT FILE

DMS = DMS or {}
DMS.TimeEffects = {}

-- Time periods
DMS.TimeEffects.Period = {
    NIGHT = "night",       -- 00:00 - 05:00
    DAWN = "dawn",         -- 05:00 - 07:00
    MORNING = "morning",   -- 07:00 - 12:00
    AFTERNOON = "afternoon", -- 12:00 - 17:00
    DUSK = "dusk",         -- 17:00 - 19:00
    EVENING = "evening",   -- 19:00 - 24:00
}

DMS.TimeEffects.CurrentPeriod = nil
DMS.TimeEffects.Active = false
DMS.TimeEffects.TimerId = nil
DMS.TimeEffects.PeriodHandlers = {}

-- Configuration
DMS.TimeEffects.Config = {
    playerCoalition = coalition.side.BLUE,
    checkInterval = 60,           -- Check time every minute
    announceTransitions = true,
    enableVisibilityEffects = true,
    enableAIBehaviorChanges = true,
}

-- Period time ranges (in seconds from midnight)
local periodRanges = {
    {start = 0, finish = 5 * 3600, period = "night"},
    {start = 5 * 3600, finish = 7 * 3600, period = "dawn"},
    {start = 7 * 3600, finish = 12 * 3600, period = "morning"},
    {start = 12 * 3600, finish = 17 * 3600, period = "afternoon"},
    {start = 17 * 3600, finish = 19 * 3600, period = "dusk"},
    {start = 19 * 3600, finish = 24 * 3600, period = "evening"},
}

--- Configure time effects
-- @param settings table Configuration overrides
function DMS.TimeEffects.configure(settings)
    for key, value in pairs(settings) do
        DMS.TimeEffects.Config[key] = value
    end
end

--- Get current mission time of day
-- @return number Seconds since midnight
local function getTimeOfDay()
    local absTime = timer.getAbsTime()
    return absTime % 86400  -- Seconds in a day
end

--- Determine current period
-- @return string Current period name
local function getCurrentPeriod()
    local tod = getTimeOfDay()

    for _, range in ipairs(periodRanges) do
        if tod >= range.start and tod < range.finish then
            return range.period
        end
    end

    return "night"  -- Default
end

--- Format time for display
-- @param seconds number Seconds since midnight
-- @return string Formatted time (HH:MM)
local function formatTime(seconds)
    local hours = math.floor(seconds / 3600)
    local mins = math.floor((seconds % 3600) / 60)
    return string.format("%02d:%02d", hours, mins)
end

--- Register a handler for period transitions
-- @param period string Period name
-- @param handler function Handler function
function DMS.TimeEffects.onPeriod(period, handler)
    if not DMS.TimeEffects.PeriodHandlers[period] then
        DMS.TimeEffects.PeriodHandlers[period] = {}
    end
    table.insert(DMS.TimeEffects.PeriodHandlers[period], handler)
end

--- Register handler for any period change
-- @param handler function Handler(oldPeriod, newPeriod)
function DMS.TimeEffects.onPeriodChange(handler)
    if not DMS.TimeEffects.PeriodHandlers["_change"] then
        DMS.TimeEffects.PeriodHandlers["_change"] = {}
    end
    table.insert(DMS.TimeEffects.PeriodHandlers["_change"], handler)
end

--- Trigger period handlers
-- @param period string Current period
-- @param oldPeriod string|nil Previous period
local function triggerHandlers(period, oldPeriod)
    -- Period-specific handlers
    if DMS.TimeEffects.PeriodHandlers[period] then
        for _, handler in ipairs(DMS.TimeEffects.PeriodHandlers[period]) do
            handler()
        end
    end

    -- Change handlers
    if oldPeriod and DMS.TimeEffects.PeriodHandlers["_change"] then
        for _, handler in ipairs(DMS.TimeEffects.PeriodHandlers["_change"]) do
            handler(oldPeriod, period)
        end
    end
end

--- Get period description
-- @param period string Period name
-- @return string Human-readable description
local function getPeriodDescription(period)
    local descriptions = {
        night = "Night operations - Limited visibility, use NVG",
        dawn = "Dawn breaking - Transitional lighting",
        morning = "Morning - Good visibility",
        afternoon = "Afternoon - Clear conditions",
        dusk = "Dusk approaching - Decreasing visibility",
        evening = "Evening - Low light conditions",
    }
    return descriptions[period] or "Unknown"
end

--- Apply visibility effects
-- @param period string Current period
local function applyVisibilityEffects(period)
    if not DMS.TimeEffects.Config.enableVisibilityEffects then
        return
    end

    -- These are conceptual - actual implementation would depend on
    -- mission-specific mechanics (e.g., SAM detection ranges)

    local visibility = {
        night = 0.3,
        dawn = 0.6,
        morning = 1.0,
        afternoon = 1.0,
        dusk = 0.7,
        evening = 0.4,
    }

    -- Could set a flag or global variable for other scripts to use
    trigger.action.setUserFlag("visibility_factor", math.floor((visibility[period] or 1.0) * 100))
end

--- Check time and handle transitions
local function checkTime(_, time)
    if not DMS.TimeEffects.Active then
        return nil
    end

    local currentPeriod = getCurrentPeriod()

    if currentPeriod ~= DMS.TimeEffects.CurrentPeriod then
        local oldPeriod = DMS.TimeEffects.CurrentPeriod
        DMS.TimeEffects.CurrentPeriod = currentPeriod

        -- Announce transition
        if DMS.TimeEffects.Config.announceTransitions and oldPeriod then
            local tod = getTimeOfDay()
            local msg = string.format("TIME: %s - %s\n%s",
                formatTime(tod),
                currentPeriod:upper(),
                getPeriodDescription(currentPeriod)
            )

            trigger.action.outTextForCoalition(
                DMS.TimeEffects.Config.playerCoalition,
                msg,
                15,
                true
            )
        end

        -- Apply effects
        applyVisibilityEffects(currentPeriod)

        -- Trigger handlers
        triggerHandlers(currentPeriod, oldPeriod)
    end

    return time + DMS.TimeEffects.Config.checkInterval
end

--- Start time effects system
function DMS.TimeEffects.start()
    if DMS.TimeEffects.Active then
        return
    end

    DMS.TimeEffects.Active = true

    -- Initialize current period
    DMS.TimeEffects.CurrentPeriod = getCurrentPeriod()
    applyVisibilityEffects(DMS.TimeEffects.CurrentPeriod)
    triggerHandlers(DMS.TimeEffects.CurrentPeriod, nil)

    DMS.TimeEffects.TimerId = timer.scheduleFunction(
        checkTime,
        nil,
        timer.getTime() + DMS.TimeEffects.Config.checkInterval
    )
end

--- Stop time effects system
function DMS.TimeEffects.stop()
    DMS.TimeEffects.Active = false
    if DMS.TimeEffects.TimerId then
        timer.removeFunction(DMS.TimeEffects.TimerId)
        DMS.TimeEffects.TimerId = nil
    end
end

--- Get current time info
-- @return table Time information
function DMS.TimeEffects.getTimeInfo()
    local tod = getTimeOfDay()
    return {
        secondsSinceMidnight = tod,
        formatted = formatTime(tod),
        period = getCurrentPeriod(),
        description = getPeriodDescription(getCurrentPeriod()),
    }
end

--- Display current time
function DMS.TimeEffects.showTime()
    local info = DMS.TimeEffects.getTimeInfo()

    local msg = string.format("=== MISSION TIME ===\n\nTime: %s\nPeriod: %s\n\n%s",
        info.formatted,
        info.period:upper(),
        info.description
    )

    trigger.action.outTextForCoalition(
        DMS.TimeEffects.Config.playerCoalition,
        msg,
        15,
        true
    )
end

--- Check if currently in period
-- @param period string Period to check
-- @return boolean True if current period matches
function DMS.TimeEffects.isPeriod(period)
    return getCurrentPeriod() == period
end

--- Check if night time
-- @return boolean True if night or evening
function DMS.TimeEffects.isNight()
    local period = getCurrentPeriod()
    return period == "night" or period == "evening"
end

--- Check if day time
-- @return boolean True if morning or afternoon
function DMS.TimeEffects.isDay()
    local period = getCurrentPeriod()
    return period == "morning" or period == "afternoon"
end

--[[
USAGE EXAMPLE:

-- Configure
DMS.TimeEffects.configure({
    announceTransitions = true,
    enableVisibilityEffects = true
})

-- Register period-specific handlers
DMS.TimeEffects.onPeriod("night", function()
    -- Activate night patrol groups
    local group = Group.getByName("Night-Patrol")
    if group then trigger.action.activateGroup(group) end

    -- Reduce SAM engagement range conceptually
    trigger.action.setUserFlag("sam_range_modifier", 70)
end)

DMS.TimeEffects.onPeriod("dawn", function()
    -- Morning patrol swap
    trigger.action.outText("Enemy patrol shift change in progress...", 10)
end)

DMS.TimeEffects.onPeriod("morning", function()
    -- Activate day patrol groups
    local group = Group.getByName("Day-Patrol")
    if group then trigger.action.activateGroup(group) end

    trigger.action.setUserFlag("sam_range_modifier", 100)
end)

-- Register change handler
DMS.TimeEffects.onPeriodChange(function(oldPeriod, newPeriod)
    -- Log all transitions
    env.info(string.format("DMS: Time period changed from %s to %s", oldPeriod, newPeriod))
end)

-- Start system
DMS.TimeEffects.start()

-- Add F10 menu
missionCommands.addCommandForCoalition(coalition.side.BLUE, "Check Time", nil,
    function() DMS.TimeEffects.showTime() end)

-- In other scripts, check time conditions
if DMS.TimeEffects.isNight() then
    -- Apply night-specific logic
end
]]

-- Export
_G.DMS = DMS
