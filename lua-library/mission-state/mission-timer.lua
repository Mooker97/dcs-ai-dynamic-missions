-- Mission Timer System for DCS Missions
-- Track mission time, countdowns, and time-based events
-- Requires: utils/messaging.lua
-- Place in mission via DO SCRIPT FILE

DMS = DMS or {}
DMS.Timer = {}

-- Timer state
DMS.Timer.Timers = {}
DMS.Timer.Active = false
DMS.Timer.UpdateTimerId = nil
DMS.Timer.MissionStartTime = 0

-- Configuration
DMS.Timer.Config = {
    playerCoalition = coalition.side.BLUE,
    updateInterval = 1,          -- Check timers every second
    showWarnings = true,         -- Show countdown warnings
    warningTimes = {60, 30, 10, 5},  -- Seconds before deadline to warn
    displayDuration = 5,
}

--- Configure timer system
-- @param settings table Configuration overrides
function DMS.Timer.configure(settings)
    for key, value in pairs(settings) do
        DMS.Timer.Config[key] = value
    end
end

--- Format seconds to MM:SS or HH:MM:SS
-- @param seconds number Time in seconds
-- @return string Formatted time
local function formatTime(seconds)
    if seconds < 0 then seconds = 0 end

    local hours = math.floor(seconds / 3600)
    local mins = math.floor((seconds % 3600) / 60)
    local secs = math.floor(seconds % 60)

    if hours > 0 then
        return string.format("%02d:%02d:%02d", hours, mins, secs)
    else
        return string.format("%02d:%02d", mins, secs)
    end
end

--- Create a countdown timer
-- @param id string Unique timer ID
-- @param duration number Duration in seconds
-- @param options table|nil Timer options
function DMS.Timer.createCountdown(id, duration, options)
    options = options or {}

    local startTime = timer.getTime()

    DMS.Timer.Timers[id] = {
        id = id,
        type = "countdown",
        duration = duration,
        startTime = startTime,
        endTime = startTime + duration,
        paused = false,
        pausedAt = nil,
        remainingAtPause = nil,
        label = options.label or id,
        onComplete = options.onComplete,
        onWarning = options.onWarning,
        showOnHUD = options.showOnHUD or false,
        warningsGiven = {},
        completed = false,
        setFlagOnComplete = options.setFlagOnComplete,
    }

    return DMS.Timer.Timers[id]
end

--- Create a stopwatch (count up)
-- @param id string Unique timer ID
-- @param options table|nil Timer options
function DMS.Timer.createStopwatch(id, options)
    options = options or {}

    DMS.Timer.Timers[id] = {
        id = id,
        type = "stopwatch",
        startTime = timer.getTime(),
        paused = false,
        pausedAt = nil,
        elapsedAtPause = 0,
        label = options.label or id,
        showOnHUD = options.showOnHUD or false,
    }

    return DMS.Timer.Timers[id]
end

--- Get remaining time for countdown
-- @param id string Timer ID
-- @return number|nil Remaining seconds or nil
function DMS.Timer.getRemaining(id)
    local t = DMS.Timer.Timers[id]
    if not t or t.type ~= "countdown" then
        return nil
    end

    if t.paused then
        return t.remainingAtPause
    end

    return math.max(0, t.endTime - timer.getTime())
end

--- Get elapsed time for stopwatch
-- @param id string Timer ID
-- @return number|nil Elapsed seconds or nil
function DMS.Timer.getElapsed(id)
    local t = DMS.Timer.Timers[id]
    if not t then
        return nil
    end

    if t.type == "stopwatch" then
        if t.paused then
            return t.elapsedAtPause
        end
        return timer.getTime() - t.startTime + (t.elapsedAtPause or 0)
    elseif t.type == "countdown" then
        return t.duration - DMS.Timer.getRemaining(id)
    end

    return nil
end

--- Pause a timer
-- @param id string Timer ID
function DMS.Timer.pause(id)
    local t = DMS.Timer.Timers[id]
    if not t or t.paused then
        return
    end

    t.paused = true
    t.pausedAt = timer.getTime()

    if t.type == "countdown" then
        t.remainingAtPause = t.endTime - timer.getTime()
    elseif t.type == "stopwatch" then
        t.elapsedAtPause = timer.getTime() - t.startTime + (t.elapsedAtPause or 0)
    end
end

--- Resume a paused timer
-- @param id string Timer ID
function DMS.Timer.resume(id)
    local t = DMS.Timer.Timers[id]
    if not t or not t.paused then
        return
    end

    t.paused = false

    if t.type == "countdown" then
        t.endTime = timer.getTime() + t.remainingAtPause
    elseif t.type == "stopwatch" then
        t.startTime = timer.getTime()
    end
end

--- Reset a timer
-- @param id string Timer ID
function DMS.Timer.reset(id)
    local t = DMS.Timer.Timers[id]
    if not t then
        return
    end

    local currentTime = timer.getTime()

    if t.type == "countdown" then
        t.startTime = currentTime
        t.endTime = currentTime + t.duration
        t.warningsGiven = {}
        t.completed = false
    elseif t.type == "stopwatch" then
        t.startTime = currentTime
        t.elapsedAtPause = 0
    end

    t.paused = false
end

--- Remove a timer
-- @param id string Timer ID
function DMS.Timer.remove(id)
    DMS.Timer.Timers[id] = nil
end

--- Add time to countdown
-- @param id string Timer ID
-- @param seconds number Seconds to add (can be negative)
function DMS.Timer.addTime(id, seconds)
    local t = DMS.Timer.Timers[id]
    if not t or t.type ~= "countdown" then
        return
    end

    if t.paused then
        t.remainingAtPause = t.remainingAtPause + seconds
    else
        t.endTime = t.endTime + seconds
    end
end

--- Process timer updates (internal)
local function updateTimersInternal(_, time)
    if not DMS.Timer.Active then
        return nil
    end

    for id, t in pairs(DMS.Timer.Timers) do
        if not t.paused and t.type == "countdown" and not t.completed then
            local remaining = t.endTime - time

            -- Check for warnings
            if DMS.Timer.Config.showWarnings then
                for _, warnTime in ipairs(DMS.Timer.Config.warningTimes) do
                    if remaining <= warnTime and remaining > warnTime - 1 and not t.warningsGiven[warnTime] then
                        t.warningsGiven[warnTime] = true

                        local msg = string.format("%s: %s remaining!", t.label, formatTime(warnTime))
                        trigger.action.outTextForCoalition(
                            DMS.Timer.Config.playerCoalition,
                            msg,
                            DMS.Timer.Config.displayDuration,
                            true
                        )

                        if t.onWarning then
                            t.onWarning(warnTime)
                        end
                    end
                end
            end

            -- Check for completion
            if remaining <= 0 then
                t.completed = true

                local msg = string.format("%s: TIME!", t.label)
                trigger.action.outTextForCoalition(
                    DMS.Timer.Config.playerCoalition,
                    msg,
                    DMS.Timer.Config.displayDuration,
                    true
                )

                if t.setFlagOnComplete then
                    trigger.action.setUserFlag(t.setFlagOnComplete, 1)
                end

                if t.onComplete then
                    t.onComplete()
                end
            end
        end
    end

    return time + DMS.Timer.Config.updateInterval
end

--- Process timer updates with error handling
local function updateTimers(args, time)
    local success, result = pcall(updateTimersInternal, args, time)
    if not success then
        if DMS.Error then
            DMS.Error.log("Timer.updateTimers", result)
        else
            env.error("[DMS LUA ERROR] Timer.updateTimers: " .. tostring(result))
        end
        return time + (DMS.Timer.Config.updateInterval or 1)
    end
    return result
end

--- Start timer system
function DMS.Timer.start()
    if DMS.Timer.Active then
        return
    end

    DMS.Timer.Active = true
    DMS.Timer.MissionStartTime = timer.getTime()

    DMS.Timer.UpdateTimerId = timer.scheduleFunction(
        updateTimers,
        nil,
        timer.getTime() + DMS.Timer.Config.updateInterval
    )
end

--- Stop timer system
function DMS.Timer.stop()
    DMS.Timer.Active = false
    if DMS.Timer.UpdateTimerId then
        timer.removeFunction(DMS.Timer.UpdateTimerId)
        DMS.Timer.UpdateTimerId = nil
    end
end

--- Get mission elapsed time
-- @return number Seconds since mission start
function DMS.Timer.getMissionTime()
    return timer.getTime() - DMS.Timer.MissionStartTime
end

--- Display timer status
-- @param id string Timer ID
function DMS.Timer.showTimer(id)
    local t = DMS.Timer.Timers[id]
    if not t then
        return
    end

    local msg
    if t.type == "countdown" then
        local remaining = DMS.Timer.getRemaining(id)
        msg = string.format("%s: %s remaining", t.label, formatTime(remaining))
        if t.paused then msg = msg .. " (PAUSED)" end
    else
        local elapsed = DMS.Timer.getElapsed(id)
        msg = string.format("%s: %s elapsed", t.label, formatTime(elapsed))
        if t.paused then msg = msg .. " (PAUSED)" end
    end

    trigger.action.outTextForCoalition(
        DMS.Timer.Config.playerCoalition,
        msg,
        DMS.Timer.Config.displayDuration,
        true
    )
end

--- Display all active timers
function DMS.Timer.showAllTimers()
    local lines = {"=== MISSION TIMERS ===", ""}

    -- Mission time
    table.insert(lines, string.format("Mission Time: %s", formatTime(DMS.Timer.getMissionTime())))
    table.insert(lines, "")

    for id, t in pairs(DMS.Timer.Timers) do
        local status
        if t.type == "countdown" then
            local remaining = DMS.Timer.getRemaining(id)
            status = string.format("%s: %s remaining", t.label, formatTime(remaining))
        else
            local elapsed = DMS.Timer.getElapsed(id)
            status = string.format("%s: %s elapsed", t.label, formatTime(elapsed))
        end
        if t.paused then status = status .. " (PAUSED)" end
        table.insert(lines, status)
    end

    if #DMS.Timer.Timers == 0 then
        table.insert(lines, "No active timers.")
    end

    trigger.action.outTextForCoalition(
        DMS.Timer.Config.playerCoalition,
        table.concat(lines, "\n"),
        15,
        true
    )
end

--[[
USAGE EXAMPLE:

-- Configure
DMS.Timer.configure({
    showWarnings = true,
    warningTimes = {300, 120, 60, 30, 10}  -- 5min, 2min, 1min, 30s, 10s
})

-- Start system
DMS.Timer.start()

-- Create mission deadline
DMS.Timer.createCountdown("mission_time", 1800, {  -- 30 minutes
    label = "Mission Time Limit",
    showOnHUD = true,
    setFlagOnComplete = "mission_timeout",
    onComplete = function()
        trigger.action.outText("MISSION TIME EXPIRED!", 30)
    end,
    onWarning = function(remaining)
        if remaining == 60 then
            trigger.action.outText("One minute warning!", 5)
        end
    end
})

-- Create objective timer
DMS.Timer.createCountdown("evac_timer", 300, {  -- 5 minutes
    label = "Evacuation Window",
    onComplete = function()
        trigger.action.outText("Evacuation window closed!", 10)
        -- Spawn enemy reinforcements
    end
})

-- Create mission stopwatch
DMS.Timer.createStopwatch("completion_time", {
    label = "Mission Duration"
})

-- Add F10 menu commands
missionCommands.addCommandForCoalition(coalition.side.BLUE, "Show Timers", nil,
    function() DMS.Timer.showAllTimers() end)

-- Timer control from triggers
-- DMS.Timer.pause("evac_timer")
-- DMS.Timer.resume("evac_timer")
-- DMS.Timer.addTime("mission_time", 300)  -- Add 5 minutes
-- DMS.Timer.reset("evac_timer")
]]

-- Export
_G.DMS = DMS
