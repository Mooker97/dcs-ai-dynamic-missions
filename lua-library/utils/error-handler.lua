-- Error Handler for DCS Missions
-- Wraps functions with pcall to catch Lua errors
-- Logs errors with searchable prefix and optional on-screen alerts
-- Place in mission via DO SCRIPT FILE (load after mission-settings.lua)

DMS = DMS or {}
DMS.Error = {}

-- Error log prefix - easy to grep in dcs.log
local ERROR_PREFIX = "[DMS LUA ERROR]"
local ERROR_SEPARATOR = "============================================================"

-- Error counter for tracking
DMS.Error.count = 0
DMS.Error.history = {}

-- ============================================================
-- CORE ERROR LOGGING
-- ============================================================

--- Log an error to dcs.log with clear formatting
-- @param context string Where the error occurred (module/function name)
-- @param errorMsg string The error message
-- @param showAlert boolean|nil Override for on-screen alert (nil = use setting)
local function logError(context, errorMsg, showAlert)
    DMS.Error.count = DMS.Error.count + 1

    local timestamp = timer.getTime()
    local formattedError = string.format(
        "\n%s\n%s\n  Context: %s\n  Error: %s\n  Time: %.1f\n  Count: %d\n%s",
        ERROR_SEPARATOR,
        ERROR_PREFIX,
        context or "Unknown",
        tostring(errorMsg),
        timestamp,
        DMS.Error.count,
        ERROR_SEPARATOR
    )

    -- Always log to dcs.log
    env.error(formattedError)

    -- Store in history (keep last 20)
    table.insert(DMS.Error.history, {
        context = context,
        error = errorMsg,
        time = timestamp,
    })
    if #DMS.Error.history > 20 then
        table.remove(DMS.Error.history, 1)
    end

    -- On-screen alert (check setting)
    local shouldAlert = showAlert
    if shouldAlert == nil then
        -- Check setting, default to true if settings not loaded
        if DMS.Settings and DMS.Settings.get then
            shouldAlert = DMS.Settings.get("showErrorAlerts")
        else
            shouldAlert = true
        end
    end

    if shouldAlert then
        local alertMsg = string.format(
            "[DMS ERROR] %s\nCheck dcs.log for details",
            context or "Script error"
        )
        trigger.action.outText(alertMsg, 15)
    end
end

-- ============================================================
-- SAFE CALL WRAPPERS
-- ============================================================

--- Wrap a function call with error handling
-- @param func function The function to call
-- @param context string Description of what's being called (for error messages)
-- @return boolean success, any result
-- @usage local ok, result = DMS.Error.safeCall(myFunction, "MyModule.doThing")
function DMS.Error.safeCall(func, context)
    if type(func) ~= "function" then
        logError(context, "safeCall received non-function: " .. type(func))
        return false, nil
    end

    local success, result = pcall(func)
    if not success then
        logError(context, result)
    end
    return success, result
end

--- Wrap a function call with arguments
-- @param func function The function to call
-- @param context string Description of what's being called
-- @param ... any Arguments to pass to the function
-- @return boolean success, any result
-- @usage local ok, result = DMS.Error.safeCallArgs(myFunc, "MyModule.process", arg1, arg2)
function DMS.Error.safeCallArgs(func, context, ...)
    if type(func) ~= "function" then
        logError(context, "safeCallArgs received non-function: " .. type(func))
        return false, nil
    end

    local args = {...}
    local success, result = pcall(function()
        return func(unpack(args))
    end)

    if not success then
        logError(context, result)
    end
    return success, result
end

--- Create a wrapped version of a function that catches errors
-- @param func function The function to wrap
-- @param context string Description for error messages
-- @return function Wrapped function that catches errors
-- @usage local safeFunc = DMS.Error.wrap(riskyFunction, "MyModule.riskyThing")
function DMS.Error.wrap(func, context)
    return function(...)
        local args = {...}
        local success, result = pcall(function()
            return func(unpack(args))
        end)

        if not success then
            logError(context, result)
            return nil
        end
        return result
    end
end

-- ============================================================
-- TIMER WRAPPERS
-- ============================================================

--- Schedule a function with error handling
-- @param func function The function to call
-- @param delay number Delay in seconds
-- @param context string Description for error messages
-- @usage DMS.Error.safeSchedule(myUpdate, 5, "MyModule.update")
function DMS.Error.safeSchedule(func, delay, context)
    timer.scheduleFunction(function(_, time)
        local success, result = pcall(func)
        if not success then
            logError(context, result)
        end
        return nil  -- One-shot, doesn't reschedule
    end, nil, timer.getTime() + (delay or 0))
end

--- Schedule a repeating function with error handling
-- @param func function The function to call (return false to stop)
-- @param interval number Interval in seconds between calls
-- @param context string Description for error messages
-- @param initialDelay number|nil Optional initial delay (defaults to interval)
-- @return function stopFunc Call this to stop the repeating schedule
-- @usage local stop = DMS.Error.safeRepeat(myCheck, 10, "MyModule.check")
function DMS.Error.safeRepeat(func, interval, context, initialDelay)
    local running = true

    local function tick(_, time)
        if not running then
            return nil
        end

        local success, result = pcall(func)
        if not success then
            logError(context, result)
            -- Continue running despite error
        elseif result == false then
            -- Function returned false, stop repeating
            return nil
        end

        return time + interval
    end

    timer.scheduleFunction(tick, nil, timer.getTime() + (initialDelay or interval))

    -- Return stop function
    return function()
        running = false
    end
end

-- ============================================================
-- EVENT HANDLER WRAPPER
-- ============================================================

--- Create a protected event handler
-- @param handler table Event handler with onEvent function
-- @param name string Name for error messages
-- @return table Protected event handler
-- @usage world.addEventHandler(DMS.Error.safeHandler(myHandler, "MyModule"))
function DMS.Error.safeHandler(handler, name)
    return {
        onEvent = function(self, event)
            local success, result = pcall(handler.onEvent, handler, event)
            if not success then
                local eventName = "unknown"
                if event and event.id then
                    eventName = tostring(event.id)
                end
                logError(name .. ".onEvent(" .. eventName .. ")", result)
            end
        end
    }
end

-- ============================================================
-- UTILITY FUNCTIONS
-- ============================================================

--- Get error count
-- @return number Total errors caught
function DMS.Error.getCount()
    return DMS.Error.count
end

--- Get error history
-- @return table Array of recent errors
function DMS.Error.getHistory()
    return DMS.Error.history
end

--- Clear error history and count
function DMS.Error.clear()
    DMS.Error.count = 0
    DMS.Error.history = {}
end

--- Manually log an error (for custom error handling)
-- @param context string Where the error occurred
-- @param errorMsg string The error message
-- @param showAlert boolean|nil Override for on-screen alert
function DMS.Error.log(context, errorMsg, showAlert)
    logError(context, errorMsg, showAlert)
end

--- Check if any errors have occurred
-- @return boolean
function DMS.Error.hasErrors()
    return DMS.Error.count > 0
end

--[[
USAGE EXAMPLES:

-- Example 1: Simple safe call
local ok, result = DMS.Error.safeCall(function()
    local group = Group.getByName("BadName")
    return group:getUnits()  -- Would crash if group is nil
end, "GetUnits")

-- Example 2: Safe call with arguments
local ok, result = DMS.Error.safeCallArgs(someFunction, "ProcessData", arg1, arg2)

-- Example 3: Wrap a function for repeated use
local safeGetGroup = DMS.Error.wrap(function(name)
    return Group.getByName(name):getUnits()
end, "GetGroupUnits")

local units = safeGetGroup("MyGroup")  -- Returns nil on error instead of crashing

-- Example 4: Safe scheduled function
DMS.Error.safeSchedule(function()
    -- Risky code here
    DMS.SpawnPool.checkSpawns()
end, 30, "SpawnPool.checkSpawns")

-- Example 5: Safe repeating function (with stop capability)
local stopChecking = DMS.Error.safeRepeat(function()
    -- Called every 10 seconds
    updateStuff()
    return true  -- Keep going (return false to stop)
end, 10, "UpdateLoop")

-- Later: stopChecking()  -- Stop the loop

-- Example 6: Protected event handler
local myHandler = {
    onEvent = function(self, event)
        if event.id == world.event.S_EVENT_KILL then
            -- Handle kill - might error if event data is weird
            processKill(event)
        end
    end
}
world.addEventHandler(DMS.Error.safeHandler(myHandler, "KillTracker"))

-- Example 7: Manual error logging
if not group then
    DMS.Error.log("SpawnSystem", "Group not found: " .. groupName)
end

-- Example 8: Disable on-screen alerts
DMS.Settings.configure({ showErrorAlerts = false })

-- Example 9: Check for errors at mission end
if DMS.Error.hasErrors() then
    env.info("Mission had " .. DMS.Error.getCount() .. " script errors")
end
]]

-- Export
_G.DMS = DMS
