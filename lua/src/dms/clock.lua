-- DMS clock: the only module allowed to call timer.scheduleFunction.
-- Every callback is guarded; repeating tasks always re-arm even if the body errors.

DMS = DMS or {}
DMS.Clock = DMS.Clock or {}

local Clock = DMS.Clock
Clock._tasks = Clock._tasks or {}
Clock._nextId = Clock._nextId or 1

local MIN_INTERVAL = 0.05

function Clock.now() return timer.getTime() end

local function newTask(kind)
  local id = Clock._nextId
  Clock._nextId = id + 1
  local task = { id = id, kind = kind, active = true }
  Clock._tasks[id] = task
  return task
end

local function finish(task)
  task.active = false
  Clock._tasks[task.id] = nil
end

local function jitterValue(spread)
  if not spread or spread <= 0 then return 0 end
  if DMS.Rng and DMS.Rng.random then return (DMS.Rng.random() * 2 - 1) * spread end
  return (math.random() * 2 - 1) * spread
end

-- One-shot: fn(...) after delaySec. Returns a clock id.
function Clock.after(delaySec, fn, ...)
  local task = newTask("after")
  local n = select("#", ...)
  local args = { ... }
  local delay = tonumber(delaySec) or 0
  if delay < 0 then delay = 0 end
  task.timerId = timer.scheduleFunction(function()
    local ok, err = pcall(function()
      if not task.active then return end
      finish(task)
      DMS.safeCall(fn, unpack(args, 1, n))
    end)
    if not ok then pcall(DMS.Log.error, "Clock", "after #%d failed: %s", task.id, err) end
    return nil
  end, nil, timer.getTime() + delay)
  return task.id
end

-- Repeating: fn(id) every intervalSec (+/- opts.jitter). opts.firstDelay (default interval).
-- Return false from fn to stop. Errors are logged and the task keeps running.
function Clock.every(intervalSec, fn, opts)
  opts = opts or {}
  local interval = tonumber(intervalSec) or 1
  if interval < MIN_INTERVAL then interval = MIN_INTERVAL end
  local task = newTask("every")
  task.interval = interval
  local first = tonumber(opts.firstDelay)
  if first == nil then first = interval + jitterValue(opts.jitter) end
  if first < 0 then first = 0 end
  task.timerId = timer.scheduleFunction(function(_, t)
    local nextT
    local ok, err = pcall(function()
      if not task.active then return end
      local okc, res = DMS.safeCall(fn, task.id)
      if okc and res == false then finish(task); return end
      if not task.active then return end -- cancelled from inside fn
      local step = interval + jitterValue(opts.jitter)
      if step < MIN_INTERVAL then step = MIN_INTERVAL end
      nextT = (t or timer.getTime()) + step
    end)
    if not ok then
      pcall(DMS.Log.error, "Clock", "every #%d wrapper failed: %s", task.id, err)
      if task.active then nextT = timer.getTime() + interval end
    end
    return nextT
  end, nil, timer.getTime() + first)
  return task.id
end

function Clock.cancel(id)
  local task = id and Clock._tasks[id]
  if not task then return false end
  finish(task)
  if task.timerId then pcall(timer.removeFunction, task.timerId) end
  return true
end

function Clock.isActive(id)
  return id ~= nil and Clock._tasks[id] ~= nil
end
