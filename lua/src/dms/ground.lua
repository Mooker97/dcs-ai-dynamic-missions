-- ground.lua: correct ground (and naval) AI control.
-- Routes always have >= 2 points with the current position first. ROE uses the right domain
-- enum (ground: OPEN_FIRE/RETURN_FIRE/WEAPON_HOLD only). Hunt re-issues intercept routes with
-- lead prediction; a stuck watchdog re-routes groups that stop moving.
DMS = DMS or {}
DMS.Ground = DMS.Ground or {}

local Ground = DMS.Ground
local P = "Ground"

Ground.defaults = {
  speed = 8,            -- m/s
  huntIntervalSec = 30,
  huntStandoffM = 300,
  huntMaxLeadSec = 90,
  stuckCheckSec = 15,
  stuckSec = 60,
  stuckMinMoveM = 25,
  stuckArriveM = 150,
  stuckMaxRetries = 3,
}

Ground._dest = Ground._dest or {}     -- groupName -> {point, opts}
Ground._halted = Ground._halted or {} -- groupName -> true
Ground._hunts = Ground._hunts or {}   -- groupName -> clock id
Ground._watch = Ground._watch or {}   -- groupName -> clock id

-- ---------------------------------------------------------------- helpers

local function getGroup(name)
  local ok, g = pcall(Group.getByName, name)
  if ok and g then
    local ok2, ex = pcall(g.isExist, g)
    if ok2 and ex then return g end
  end
  return nil
end
Ground.getGroup = getGroup

function Ground.aliveUnits(name)
  local g = getGroup(name)
  local out = {}
  if not g then return out end
  local ok, units = pcall(g.getUnits, g)
  if not ok or not units then return out end
  for _, u in ipairs(units) do
    local ok2, alive = pcall(function() return u:isExist() and (u:getLife() or 1) >= 1 end)
    if ok2 and alive then out[#out + 1] = u end
  end
  return out
end

-- lead unit position (vec3) or nil
function Ground.leadPos(name)
  local u = Ground.aliveUnits(name)[1]
  if not u then return nil end
  local ok, p = pcall(u.getPoint, u)
  return ok and p or nil
end

function Ground.leadVel(name)
  local u = Ground.aliveUnits(name)[1]
  if not u then return { x = 0, y = 0, z = 0 } end
  local ok, v = pcall(u.getVelocity, u)
  return (ok and v) or { x = 0, y = 0, z = 0 }
end

local function controller(name)
  local g = getGroup(name)
  if not g then return nil end
  local ok, c = pcall(g.getController, g)
  return ok and c or nil
end

local function domain(name)
  local g = getGroup(name)
  if not g then return nil end
  local ok, cat = pcall(g.getCategory, g)
  if not ok then return "ground" end
  if cat == Group.Category.SHIP then return "naval" end
  if cat == Group.Category.AIRPLANE or cat == Group.Category.HELICOPTER then return "air" end
  return "ground"
end
Ground.domain = domain

local function v2(p)
  if p.z ~= nil then return { x = p.x, y = p.z } end
  return { x = p.x, y = p.y }
end

local function d2(a, b)
  local dx, dy = a.x - b.x, a.y - b.y
  return math.sqrt(dx * dx + dy * dy)
end

function Ground.makePoint(p, speed, action)
  return {
    x = p.x, y = p.y, type = "Turning Point", action = action or "Off Road",
    speed = speed or Ground.defaults.speed, ETA = 0, ETA_locked = false, speed_locked = true,
    task = { id = "ComboTask", params = { tasks = {} } },
  }
end

-- ---------------------------------------------------------------- routing

-- routeTo(groupName, point, {speed, action, stopShortM, via={points}}) -> bool
function Ground.routeTo(name, point, opts)
  opts = opts or {}
  local c = controller(name)
  local here = Ground.leadPos(name)
  if not c or not here or not point then return false end
  local from = v2(here)
  local to = v2(point)
  local stop = opts.stopShortM or 0
  if stop > 0 then
    local d = d2(from, to)
    if d > stop then
      to = { x = from.x + (to.x - from.x) * (1 - stop / d), y = from.y + (to.y - from.y) * (1 - stop / d) }
    else
      to = { x = from.x, y = from.y }
    end
  end
  local speed = opts.speed or Ground.defaults.speed
  local action = opts.action or "Off Road"
  local pts = { Ground.makePoint(from, speed, action) }
  for _, vp in ipairs(opts.via or {}) do pts[#pts + 1] = Ground.makePoint(v2(vp), speed, action) end
  if d2(to, from) < 1 then to = { x = from.x + 1, y = from.y + 1 } end -- keep 2 distinct points
  pts[#pts + 1] = Ground.makePoint(to, speed, action)
  local ok, err = pcall(c.setTask, c, { id = "Mission", params = { route = { points = pts } } })
  if not ok then
    DMS.Log.warn(P, "routeTo '%s' failed: %s", name, tostring(err))
    return false
  end
  Ground._dest[name] = { point = to, opts = opts }
  Ground._halted[name] = nil
  DMS.Log.debug(P, "'%s' routed to (%.0f, %.0f) at %.1f m/s (%s)", name, to.x, to.y, speed, action)
  return true
end

local function stopRoute(name, value)
  local c = controller(name)
  if not c then return false end
  local ok = pcall(c.setCommand, c, { id = "StopRoute", params = { value = value } })
  return ok
end

function Ground.halt(name)
  if stopRoute(name, true) then
    Ground._halted[name] = true
    DMS.Log.debug(P, "'%s' halted", name)
    return true
  end
  return false
end

function Ground.resume(name)
  if stopRoute(name, false) then
    Ground._halted[name] = nil
    DMS.Log.debug(P, "'%s' resumed", name)
    return true
  end
  return false
end

-- ---------------------------------------------------------------- ROE / alarm

local function setROE(name, which)
  local c = controller(name)
  if not c then return false end
  local dom = domain(name)
  local id, val
  if dom == "air" then
    id = AI.Option.Air.id.ROE
    local map = { open = "OPEN_FIRE", ret = "RETURN_FIRE", hold = "WEAPON_HOLD" }
    val = AI.Option.Air.val.ROE[map[which]]
  elseif dom == "naval" then
    id = AI.Option.Naval.id.ROE
    local map = { open = "OPEN_FIRE", ret = "RETURN_FIRE", hold = "WEAPON_HOLD" }
    val = AI.Option.Naval.val.ROE[map[which]]
  else
    id = AI.Option.Ground.id.ROE
    local map = { open = "OPEN_FIRE", ret = "RETURN_FIRE", hold = "WEAPON_HOLD" }
    val = AI.Option.Ground.val.ROE[map[which]]
  end
  if id == nil or val == nil then return false end
  local ok, err = pcall(c.setOption, c, id, val)
  if not ok then DMS.Log.warn(P, "ROE on '%s' failed: %s", name, tostring(err)) end
  DMS.Log.debug(P, "'%s' ROE -> %s (%s)", name, which, dom)
  return ok
end

function Ground.holdFire(name) return setROE(name, "hold") end
function Ground.openFire(name) return setROE(name, "open") end
function Ground.returnFire(name) return setROE(name, "ret") end

-- alarm(groupName, "GREEN"|"RED"|"AUTO") -- ground only
function Ground.alarm(name, state)
  if domain(name) ~= "ground" then return false end
  local c = controller(name)
  if not c then return false end
  state = state or "AUTO"
  if state ~= "AUTO" and state ~= "GREEN" and state ~= "RED" then return false end
  local val = AI.Option.Ground.val.ALARM_STATE[state]
  local ok = pcall(c.setOption, c, AI.Option.Ground.id.ALARM_STATE, val)
  DMS.Log.debug(P, "'%s' alarm -> %s", name, tostring(state))
  return ok
end

-- fireAtPoint(groupName, point, {radius, expendQty})
function Ground.fireAtPoint(name, point, opts)
  opts = opts or {}
  local c = controller(name)
  if not c or not point then return false end
  local p = v2(point)
  local params = { point = { x = p.x, y = p.y }, radius = opts.radius or 100 }
  if opts.expendQty then
    params.expendQty = opts.expendQty
    params.expendQtyEnabled = true
  end
  local ok = pcall(c.pushTask, c, { id = "FireAtPoint", params = params })
  DMS.Log.debug(P, "'%s' fire at (%.0f, %.0f) r=%d", name, p.x, p.y, params.radius)
  return ok
end

-- ---------------------------------------------------------------- hunt

-- Intercept point: target lead + velocity * leadTime, clamped.
function Ground.interceptPoint(hunterPos, targetPos, targetVel, speed, maxLead)
  local hp, tp = v2(hunterPos), v2(targetPos)
  local vel = targetVel and v2(targetVel) or { x = 0, y = 0 }
  local dist = d2(hp, tp)
  local lead = math.min(dist / math.max(speed or 1, 1), maxLead or Ground.defaults.huntMaxLeadSec)
  return { x = tp.x + vel.x * lead, y = tp.y + vel.y * lead }
end

-- hunt(groupName, target, opts)
--   target: group name, or function() -> groupName|nil (re-evaluated each tick, e.g. nearest player)
--   opts: intervalSec, speed, standoffM, maxLeadSec, radiusM (only hunt when within), onEnd(reason)
function Ground.hunt(name, target, opts)
  opts = opts or {}
  Ground.stopHunt(name)
  local interval = opts.intervalSec or Ground.defaults.huntIntervalSec
  local speed = opts.speed or Ground.defaults.speed
  local engaged = false
  local function tick()
    if not DMS.Registry.isAlive(name) and not getGroup(name) then
      Ground._hunts[name] = nil
      DMS.Log.debug(P, "Hunter '%s' gone - hunt ended", name)
      if opts.onEnd then opts.onEnd("dead") end
      return false
    end
    local hp = Ground.leadPos(name)
    if not hp then
      Ground._hunts[name] = nil
      if opts.onEnd then opts.onEnd("dead") end
      return false
    end
    local tgt = target
    if type(target) == "function" then tgt = target(name) end
    local tp = tgt and Ground.leadPos(tgt)
    if not tp then
      if type(target) ~= "function" then
        Ground._hunts[name] = nil
        DMS.Log.debug(P, "Hunter '%s': target '%s' gone - hunt ended", name, tostring(tgt))
        if opts.onEnd then opts.onEnd("target") end
        return false
      end
      return true -- wait for a target to appear
    end
    if opts.radiusM and d2(v2(hp), v2(tp)) > opts.radiusM then return true end
    if not engaged then
      engaged = true
      Ground.alarm(name, "RED")
      Ground.openFire(name)
      DMS.Log.debug(P, "'%s' hunting '%s'", name, tgt)
    end
    local ip = Ground.interceptPoint(hp, tp, Ground.leadVel(tgt), speed, opts.maxLeadSec)
    Ground.routeTo(name, ip, { speed = speed, action = opts.action or "Off Road",
      stopShortM = opts.standoffM or Ground.defaults.huntStandoffM })
    return true
  end
  Ground._hunts[name] = DMS.Clock.every(interval, tick, { firstDelay = opts.firstDelay or 0.5, jitter = opts.jitter })
  return Ground._hunts[name]
end

function Ground.stopHunt(name)
  local id = Ground._hunts[name]
  if id then
    DMS.Clock.cancel(id)
    Ground._hunts[name] = nil
  end
end

function Ground.isHunting(name) return Ground._hunts[name] ~= nil end

-- ---------------------------------------------------------------- stuck watchdog

-- watch(groupName, {checkSec, stuckSec, minMoveM, maxRetries, onStuck(name)})
function Ground.watch(name, opts)
  opts = opts or {}
  Ground.unwatch(name)
  local stuckSec = opts.stuckSec or Ground.defaults.stuckSec
  local minMove = opts.minMoveM or Ground.defaults.stuckMinMoveM
  local maxRetries = opts.maxRetries or Ground.defaults.stuckMaxRetries
  local lastPos, lastMoveT, retries = nil, DMS.Clock.now(), 0
  local function tick()
    local p = Ground.leadPos(name)
    if not p then Ground._watch[name] = nil return false end
    local now = DMS.Clock.now()
    p = v2(p)
    if not lastPos or d2(p, lastPos) >= minMove then
      lastPos, lastMoveT = p, now
      return true
    end
    local dest = Ground._dest[name]
    if Ground._halted[name] or not dest or d2(p, dest.point) <= Ground.defaults.stuckArriveM then
      lastMoveT = now
      return true
    end
    if now - lastMoveT >= stuckSec then
      lastMoveT = now
      if retries < maxRetries then
        retries = retries + 1
        -- nudge: detour point offset sideways, then the real destination
        local a = DMS.Rng.random() * 2 * math.pi
        local via = { x = p.x + 200 * math.cos(a), y = p.y + 200 * math.sin(a) }
        local o = {}
        for k, v in pairs(dest.opts or {}) do o[k] = v end
        o.via = { via }
        o.stopShortM = nil
        DMS.Log.info(P, "'%s' stuck for %ds - re-routing (%d/%d)", name, stuckSec, retries, maxRetries)
        Ground.routeTo(name, dest.point, o)
      else
        DMS.Log.warn(P, "'%s' stuck - giving up after %d retries", name, maxRetries)
        DMS.Bus.emit("ground.stuck", { group = name })
        if opts.onStuck then opts.onStuck(name) end
        Ground._watch[name] = nil
        return false
      end
    end
    return true
  end
  Ground._watch[name] = DMS.Clock.every(opts.checkSec or Ground.defaults.stuckCheckSec, tick)
  return Ground._watch[name]
end

function Ground.unwatch(name)
  local id = Ground._watch[name]
  if id then DMS.Clock.cancel(id) Ground._watch[name] = nil end
end

-- ---------------------------------------------------------------- convoy reaction

-- haltOnHit(convoyGroup, resumeAfterSec) -> handle {stop=fn}
-- On any hit: halt, alarm RED, open fire; resume after resumeAfterSec (number or {min,max}).
-- Further hits restart the resume timer.
function Ground.haltOnHit(convoy, resumeAfterSec)
  resumeAfterSec = resumeAfterSec or { 60, 120 }
  local resumeId
  local token
  token = DMS.Bus.on("unit.hit", function(ev)
    if not ev or ev.targetGroup ~= convoy then return end
    if not getGroup(convoy) then return end
    if resumeId then DMS.Clock.cancel(resumeId) resumeId = nil end
    if not Ground._halted[convoy] then
      Ground.halt(convoy)
      Ground.alarm(convoy, "RED")
      Ground.openFire(convoy)
      DMS.Log.info(P, "Convoy '%s' hit - halting", convoy)
      DMS.Bus.emit("convoy.halted", { group = convoy, by = ev.initiator })
    end
    local delay = DMS.Rng.range(resumeAfterSec)
    resumeId = DMS.Clock.after(delay, function()
      resumeId = nil
      if getGroup(convoy) then
        Ground.resume(convoy)
        DMS.Log.info(P, "Convoy '%s' resuming", convoy)
        DMS.Bus.emit("convoy.resumed", { group = convoy })
      end
    end)
  end)
  return {
    stop = function()
      DMS.Bus.off(token)
      if resumeId then DMS.Clock.cancel(resumeId) end
    end,
  }
end

function Ground.reset()
  for _, id in pairs(Ground._hunts) do DMS.Clock.cancel(id) end
  for _, id in pairs(Ground._watch) do DMS.Clock.cancel(id) end
  Ground._dest, Ground._halted, Ground._hunts, Ground._watch = {}, {}, {}, {}
end

function Ground.start()
  DMS.Log.debug(P, "Started")
end
