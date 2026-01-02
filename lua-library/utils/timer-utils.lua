-- Timer Utilities for DCS Missions
-- Schedule helpers, recurring tasks, debouncing
-- Place in mission via DO SCRIPT FILE or embed in mission

DMS = DMS or {}
DMS.Timer = {}

-- Store active timer IDs for management
DMS.Timer._active = {}
DMS.Timer._nextId = 1

--- Schedule a one-time function call
-- @param func function Function to call (receives args, time)
-- @param delay number Delay in seconds
-- @param args any|nil Arguments to pass to function
-- @return number Internal timer ID
function DMS.Timer.once(func, delay, args)
    local timerId = DMS.Timer._nextId
    DMS.Timer._nextId = DMS.Timer._nextId + 1

    local function wrapper(passedArgs, time)
        DMS.Timer._active[timerId] = nil
        func(passedArgs, time)
        return nil  -- Don't reschedule
    end

    local scheduledId = timer.scheduleFunction(wrapper, args, timer.getTime() + delay)
    DMS.Timer._active[timerId] = scheduledId
    return timerId
end

--- Schedule a recurring function call
-- DCS pattern: return next time to reschedule, or nil to stop
-- @param func function Function to call (return false to stop)
-- @param interval number Interval in seconds
-- @param startDelay number|nil Initial delay (default: interval)
-- @param args any|nil Arguments to pass to function
-- @return number Internal timer ID
function DMS.Timer.recurring(func, interval, startDelay, args)
    local timerId = DMS.Timer._nextId
    DMS.Timer._nextId = DMS.Timer._nextId + 1
    startDelay = startDelay or interval

    local function wrapper(passedArgs, time)
        local result = func(passedArgs, time)
        if result == false then
            DMS.Timer._active[timerId] = nil
            return nil  -- Stop
        end
        return time + interval  -- Reschedule
    end

    local scheduledId = timer.scheduleFunction(wrapper, args, timer.getTime() + startDelay)
    DMS.Timer._active[timerId] = scheduledId
    return timerId
end

--- Schedule function to run every second
-- @param func function Function to call (return false to stop)
-- @param duration number|nil Total duration in seconds (nil = forever)
-- @param args any|nil Arguments to pass
-- @return number Timer ID
function DMS.Timer.everySecond(func, duration, args)
    local startTime = timer.getTime()

    local function wrapper(passedArgs, time)
        if duration and (time - startTime) >= duration then
            return false
        end
        return func(passedArgs, time)
    end

    return DMS.Timer.recurring(wrapper, 1, 1, args)
end

--- Schedule function to run every N seconds
-- @param func function Function to call (return false to stop)
-- @param seconds number Interval in seconds
-- @param args any|nil Arguments to pass
-- @return number Timer ID
function DMS.Timer.every(func, seconds, args)
    return DMS.Timer.recurring(func, seconds, seconds, args)
end

--- Cancel a scheduled timer
-- @param timerId number Timer ID from DMS.Timer functions
-- @return boolean True if cancelled
function DMS.Timer.cancel(timerId)
    local scheduledId = DMS.Timer._active[timerId]
    if scheduledId then
        timer.removeFunction(scheduledId)
        DMS.Timer._active[timerId] = nil
        return true
    end
    return false
end

--- Cancel all active DMS timers
function DMS.Timer.cancelAll()
    for timerId, scheduledId in pairs(DMS.Timer._active) do
        timer.removeFunction(scheduledId)
    end
    DMS.Timer._active = {}
end

--- Execute function after random delay within range
-- @param func function Function to call
-- @param minDelay number Minimum delay in seconds
-- @param maxDelay number Maximum delay in seconds
-- @param args any|nil Arguments to pass
-- @return number Timer ID
function DMS.Timer.randomDelay(func, minDelay, maxDelay, args)
    local delay = minDelay + math.random() * (maxDelay - minDelay)
    return DMS.Timer.once(func, delay, args)
end

--- Schedule multiple functions with spacing
-- @param funcs table Array of functions
-- @param spacing number Seconds between executions
-- @param startDelay number|nil Initial delay (default: 0)
function DMS.Timer.sequence(funcs, spacing, startDelay)
    startDelay = startDelay or 0
    for i, func in ipairs(funcs) do
        DMS.Timer.once(func, startDelay + (i - 1) * spacing)
    end
end

--- Wait for condition to be true, then execute callback
-- @param condition function Returns true when ready
-- @param callback function Function to call when condition met
-- @param timeout number|nil Maximum wait time in seconds (default: 60)
-- @param checkInterval number|nil Check interval in seconds (default: 1)
-- @return number Timer ID
function DMS.Timer.waitFor(condition, callback, timeout, checkInterval)
    timeout = timeout or 60
    checkInterval = checkInterval or 1
    local startTime = timer.getTime()

    local function check(_, time)
        if condition() then
            callback()
            return false  -- Stop
        end
        if time - startTime >= timeout then
            return false  -- Timeout, stop
        end
        return true  -- Continue checking
    end

    return DMS.Timer.recurring(check, checkInterval, checkInterval)
end

--- Get current mission time in seconds
-- @return number Current mission time
function DMS.Timer.getTime()
    return timer.getTime()
end

--- Get formatted mission time string (HH:MM:SS)
-- @return string Formatted time
function DMS.Timer.getFormattedTime()
    local totalSeconds = math.floor(timer.getTime())
    local hours = math.floor(totalSeconds / 3600)
    local minutes = math.floor((totalSeconds % 3600) / 60)
    local seconds = totalSeconds % 60
    return string.format("%02d:%02d:%02d", hours, minutes, seconds)
end

--- Check if duration has elapsed since start time
-- @param startTime number Start time from timer.getTime()
-- @param duration number Required elapsed time in seconds
-- @return boolean True if duration has elapsed
function DMS.Timer.hasElapsed(startTime, duration)
    return timer.getTime() - startTime >= duration
end

--- Get elapsed time since start
-- @param startTime number Start time from timer.getTime()
-- @return number Elapsed seconds
function DMS.Timer.elapsed(startTime)
    return timer.getTime() - startTime
end

--- Create a countdown timer with callbacks
-- @param duration number Duration in seconds
-- @param onTick function|nil Called each tick with remaining seconds
-- @param onComplete function Called when countdown reaches zero
-- @param tickInterval number|nil Tick interval in seconds (default: 1)
-- @return number Timer ID
function DMS.Timer.countdown(duration, onTick, onComplete, tickInterval)
    tickInterval = tickInterval or 1
    local endTime = timer.getTime() + duration

    local function tick(_, time)
        local remaining = math.max(0, endTime - time)

        if remaining <= 0 then
            if onComplete then
                onComplete()
            end
            return false  -- Stop
        end

        if onTick then
            onTick(math.floor(remaining))
        end
        return true  -- Continue
    end

    return DMS.Timer.recurring(tick, tickInterval, tickInterval)
end

--- Create a simple stopwatch object
-- @return table Stopwatch with start(), stop(), reset(), getTime() methods
function DMS.Timer.createStopwatch()
    local stopwatch = {
        _startTime = nil,
        _elapsed = 0,
        _running = false
    }

    function stopwatch:start()
        if not self._running then
            self._startTime = timer.getTime()
            self._running = true
        end
    end

    function stopwatch:stop()
        if self._running then
            self._elapsed = self._elapsed + (timer.getTime() - self._startTime)
            self._running = false
        end
    end

    function stopwatch:reset()
        self._elapsed = 0
        if self._running then
            self._startTime = timer.getTime()
        end
    end

    function stopwatch:getTime()
        if self._running then
            return self._elapsed + (timer.getTime() - self._startTime)
        end
        return self._elapsed
    end

    function stopwatch:isRunning()
        return self._running
    end

    return stopwatch
end

-- Export for global access
_G.DMS = DMS
