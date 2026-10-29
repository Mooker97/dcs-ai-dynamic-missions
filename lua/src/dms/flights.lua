-- DMS.Flights: AI flights that follow a list of orders (DMS_CONFIG.flights), plus the watch-mode
-- stand-in registration of the focus flight. See CONTRACTS "AI flights and watch missions (v0.9)".
-- Inert without DMS_CONFIG.flights (and without DMS_CONFIG.watch). Lua 5.1.
-- Depends on: DMS.Log, DMS.Clock, DMS.Bus, DMS.Rng; optional DMS.Narrative (when-form matcher,
-- flags, beats), DMS.Spawner (zones).
--
-- Order lifecycle: an order waits for its `when` (latched from Flights.start), then issues its DCS
-- task and is polled every TICK_SEC until done. Done -> the next order; after the last one
-- flight.done. A dead group ends everything with flight.lost. A missing zone, target or escorted
-- flight logs a warning and skips the order; nothing here raises into DCS.
DMS = DMS or {}
DMS.Flights = DMS.Flights or {}

local F = DMS.Flights
local P = "Flights"

F.TICK_SEC = 2
F.FIND_TRIES = 15 -- group lookups at start (FIND_RETRY_SEC apart) before the flight is lost
F.FIND_RETRY_SEC = 2
F.ARRIVE_MIN_M = 300 -- fly: done within max(this, zone radius) of the zone centre
F.LANDED_AGL_M = 3
F.LANDED_SPEED_MPS = 2
F.LAND_AREA_MIN_M = 300 -- land: ground contact counts within max(this, zone radius) of the point
F.AIRBASE_AREA_M = 4000 -- landing at an airbase: ground contact within this of the airbase point
F.PICKUP_RADIUS_M = 300
F.STRIKE_AFTER_RELEASE_SEC = 60 -- Bombing fallback: done this long after the first release
F.STRIKE_PASS_SEC = 45 -- AttackUnit pass: over this long after the pass's last release
F.STRIKE_MAX_PASSES = 3
F.LAND_APPROACH_M = 2000 -- helicopter land: route at cruise speed until this close, then the Land task
F.TELEM_SEC = 10
F.LAND_EXTRA_SEC = 120 -- Land task ground time beyond groundSec (the next order lifts the group)
F.DEFAULT_RADIUS_M = 2778 -- 1.5 nm
F.DEFAULT_GROUND_SEC = 60
F.DEFAULT_MAX_SEC = { hold = 900, escort = 900, engage = 900, strike = 360 }
F.DEFAULT_ALT = { helicopter = { 150, "RADIO" }, airplane = { 3000, "BARO" } }
F.DEFAULT_SPEED = { helicopter = 50, airplane = 160 }

-- DCS weaponType flags (Hoggit "weaponFlag" / MOOSE ENUMS.WeaponFlag).
-- [? Auto: Hoggit lists 1073741822, newer MOOSE 3221225470; headless check pending]
F.WEAPON_FLAGS = {
  guided_bomb = 14, -- GuidedBomb = LGB + TvGB + SNSGB
  bomb = 2147485694, -- AnyBomb
  missile = 4161536, -- AnyASM
  rockets = 30720, -- Rockets
  gun = 805306368, -- Cannons
  any = 1073741822, -- Auto
}
F.WEAPON_ALIASES = {
  GuidedBomb = "guided_bomb",
  AnyBomb = "bomb",
  AnyASM = "missile",
  Rockets = "rockets",
  Cannons = "gun",
  Auto = "any",
}
F.TARGET_ATTRS = {
  ground = "Ground Units",
  armor = "Armored vehicles",
  aaa = "Air Defence",
  infantry = "Infantry",
  air = "Air",
}

-- ---------------------------------------------------------------------------
-- helpers
-- ---------------------------------------------------------------------------

local function cfg()
  return DMS_CONFIG or {}
end
local function now()
  return (DMS.Clock and DMS.Clock.now()) or 0
end
local function log(level, fmt, ...)
  if DMS.Log and DMS.Log[level] then
    DMS.Log[level](P, fmt, ...)
  end
end
local function emit(name, payload)
  if DMS.Bus and DMS.Bus.emit then
    DMS.Bus.emit(name, payload)
  end
end
local function range(v, default)
  if v == nil then
    return default
  end
  if type(v) == "table" and DMS.Rng and DMS.Rng.range then
    return DMS.Rng.range(v)
  end
  return tonumber(v) or default
end

local function freshState()
  return { flights = {}, ids = {}, tokens = {}, clocks = {}, started = false }
end
F._s = F._s or freshState()

local function liveGroup(name)
  if not (name and Group and Group.getByName) then
    return nil
  end
  local ok, g = pcall(Group.getByName, name)
  if not ok or not g then
    return nil
  end
  local okE, ex = pcall(g.isExist, g)
  if okE and ex then
    return g
  end
  return nil
end

local function liveUnits(g)
  local out = {}
  if not g then
    return out
  end
  local ok, units = pcall(g.getUnits, g)
  if not ok or type(units) ~= "table" then
    return out
  end
  for _, u in ipairs(units) do
    local okE, ex = pcall(u.isExist, u)
    if okE and ex then
      out[#out + 1] = u
    end
  end
  return out
end

local function unitPoint(u)
  local ok, p = pcall(u.getPoint, u)
  if ok and type(p) == "table" and p.x and p.z then
    return p
  end
  return nil
end

local function groundHeight(x, y)
  if land and land.getHeight then
    local ok, h = pcall(land.getHeight, { x = x, y = y })
    if ok and type(h) == "number" then
      return h
    end
  end
  return 0
end

local function dist2D(p, c)
  local dx, dy = p.x - c.x, (p.z or p.y) - c.y
  return math.sqrt(dx * dx + dy * dy)
end

local function prefixMatch(name, prefix)
  if type(name) ~= "string" or type(prefix) ~= "string" then
    return false
  end
  if string.sub(name, 1, #prefix) == prefix then
    return true
  end
  return string.sub(name, 1, 4) == "DMS_" and string.sub(name, 5, 4 + #prefix) == prefix
end
F._prefixMatch = prefixMatch

-- Zone id (DMS_CONFIG.zones / ME zone) or airbase name -> {x, y, radius, airbase}.
local function resolvePlace(name)
  if name == nil then
    return nil
  end
  local z
  if DMS.Spawner and DMS.Spawner.getZone then
    local ok, r = pcall(DMS.Spawner.getZone, name)
    z = ok and r or nil
  else
    z = (cfg().zones or {})[name]
  end
  if type(z) == "table" then
    local c = DMS.Spawner and DMS.Spawner.zoneCenter and DMS.Spawner.zoneCenter(z) or { x = z.x, y = z.y }
    if c and c.x and c.y then
      local r = DMS.Spawner and DMS.Spawner.zoneRadius and DMS.Spawner.zoneRadius(z) or z.radius
      return { x = c.x, y = c.y, radius = tonumber(r) or 0, zone = name }
    end
  end
  if Airbase and Airbase.getByName then
    local ok, ab = pcall(Airbase.getByName, name)
    if ok and ab then
      local okP, p = pcall(ab.getPoint, ab)
      if okP and p then
        return { x = p.x, y = p.z, radius = 0, airbase = ab, zone = name }
      end
    end
  end
  return nil
end
F._resolvePlace = resolvePlace

local function airbaseList(side)
  local list
  if coalition and coalition.getAirbases and side then
    local ok, r = pcall(coalition.getAirbases, side)
    if ok and type(r) == "table" and #r > 0 then
      list = r
    end
  end
  if not list and world and world.getAirbases then
    local ok, r = pcall(world.getAirbases)
    if ok and type(r) == "table" then
      list = r
    end
  end
  return list or {}
end

-- Nearest airdrome (helipads and ships excluded when the category is known) of `side`.
local function nearestAirbase(p, side)
  local best, bestD
  for _, ab in ipairs(airbaseList(side)) do
    local okP, ap = pcall(ab.getPoint, ab)
    local okD, desc = pcall(ab.getDesc, ab)
    local cat = okD and type(desc) == "table" and desc.category or nil
    if okP and ap and (cat == nil or cat == 0) then
      local d = dist2D(ap, { x = p.x, y = p.z or p.y })
      if not bestD or d < bestD then
        best, bestD = ab, d
      end
    end
  end
  return best
end

-- ---------------------------------------------------------------------------
-- when / until (same forms as beat `when`)
-- ---------------------------------------------------------------------------

local IGNORED = { event = true, delaySec = true, value = true, afterSec = true, timer = true }

local function whenKind(w)
  local N = DMS.Narrative
  if N and N._whenKind then
    return N._whenKind(w)
  end
  if type(w) ~= "table" then
    return nil
  end
  if w.event then
    return "event"
  end
  if w.beat then
    return "beat"
  end
  if w.zone then
    return "zone"
  end
  if w.flag then
    return "flag"
  end
  if w.afterSec or w.timer then
    return "timer"
  end
  return nil
end

local function filtersMatch(w, payload, name)
  local N = DMS.Narrative
  if N and N._matchesFilters then
    return N._matchesFilters(w, payload, name)
  end
  for k, v in pairs(w) do
    if not IGNORED[k] then
      local got = payload[k]
      if k == "beat" then
        got = payload.beat or payload.id
      end
      if got ~= v then
        return false
      end
    end
  end
  return true
end

local function beatFired(id)
  local N = DMS.Narrative
  return N ~= nil and N.firedCount ~= nil and N.firedCount(id) > 0
end

local function flagHolds(w)
  local N = DMS.Narrative
  if not (N and N.getFlag) then
    return false
  end
  local v = N.getFlag(w.flag)
  if w.value ~= nil and N._compare then
    return N._compare(v, type(w.value) == "number" and ("==" .. w.value) or w.value)
  end
  return v ~= 0
end

-- A latch over a `when` form: true once the event happened (since Flights.start) or while the
-- state (beat fired, flag set, mission time) holds. nil form -> always ready.
local function newCondition(w)
  local c = { w = w, latched = false }
  local kind = whenKind(w)
  c.kind = kind
  if w == nil then
    c.latched = true
    return c
  end
  if not kind then
    log("warn", "unrecognised when/until form; treated as never")
    return c
  end
  local evName
  if kind == "event" then
    evName = w.event
  elseif kind == "beat" then
    evName = "beat.fired"
  elseif kind == "zone" then
    evName = "zone.entered"
  elseif kind == "director" then
    evName = "director.state"
  end
  if evName and DMS.Bus and DMS.Bus.on then
    F._s.tokens[#F._s.tokens + 1] = DMS.Bus.on(evName, function(payload)
      if c.latched then
        return
      end
      payload = payload or {}
      local hit
      if kind == "event" then
        hit = filtersMatch(w, payload, evName)
      elseif kind == "beat" then
        hit = (payload.beat or payload.id) == w.beat
      elseif kind == "zone" then
        hit = payload.zone == w.zone and (not w.group or w.group == payload.group)
      else
        local want = w.director or w.directorState
        hit = payload.state == want and (not w.flight or w.flight == payload.flight)
      end
      if hit then
        c.latched = true
      end
    end)
  end
  return c
end

local function conditionReady(c)
  if c == nil or c.latched then
    return true
  end
  local w, k = c.w, c.kind
  if k == "beat" or (k == "event" and w.event == "beat.fired" and w.beat) then
    if beatFired(w.beat) then
      c.latched = true
    end
  elseif k == "flag" then
    return flagHolds(w)
  elseif k == "timer" then
    local after = tonumber(w.afterSec or w.timer)
    if after and now() >= after then
      c.latched = true
    end
  end
  return c.latched
end
F._conditionReady = conditionReady

-- ---------------------------------------------------------------------------
-- DCS tasks
-- ---------------------------------------------------------------------------

local function flightCategory(fl)
  local c = fl.def.category
  if c == "helicopter" or c == "heli" then
    return "helicopter"
  end
  if c == "airplane" or c == "plane" then
    return "airplane"
  end
  local g = liveGroup(fl.group)
  if g then
    local ok, gc = pcall(g.getCategory, g)
    if ok and gc == 1 then
      return "helicopter"
    end
  end
  return "airplane"
end

local function altOf(fl, order)
  local d = F.DEFAULT_ALT[flightCategory(fl)]
  local alt = tonumber(order.altM) or d[1]
  local altType = order.altType or (order.altM and (flightCategory(fl) == "helicopter" and "RADIO" or "BARO")) or d[2]
  return alt, altType
end

local function speedOf(fl, order)
  return tonumber(order.speedMps) or F.DEFAULT_SPEED[flightCategory(fl)]
end

-- MSL altitude at a map point for Orbit/attack tasks (which have no alt_type).
local function mslAlt(alt, altType, x, y)
  if altType == "RADIO" then
    return alt + groundHeight(x, y)
  end
  return alt
end

local function waypoint(x, y, alt, altType, speed, tasks)
  return {
    type = "Turning Point",
    action = "Turning Point",
    x = x,
    y = y,
    alt = alt,
    alt_type = altType,
    speed = speed,
    speed_locked = true,
    ETA = 0,
    ETA_locked = false,
    task = { id = "ComboTask", params = { tasks = tasks or {} } },
  }
end

local function leadPoint(fl)
  local u = liveUnits(liveGroup(fl.group))[1]
  return u and unitPoint(u) or nil
end

-- Two-point Mission (current position first; see dcs-scripting-gotchas "Routes").
local function routeTask(fl, to, alt, altType, speed, fromTasks, toTasks, toWp)
  local from = leadPoint(fl) or { x = to.x, z = to.y }
  local wp2 = toWp or waypoint(to.x, to.y, alt, altType, speed, toTasks)
  return {
    id = "Mission",
    params = { route = { points = { waypoint(from.x, from.z, alt, altType, speed, fromTasks), wp2 } } },
  }
end

local function orbitTask(c, alt, altType, speed)
  local pattern = (AI and AI.Task and AI.Task.OrbitPattern and AI.Task.OrbitPattern.CIRCLE) or "Circle"
  return {
    id = "Orbit",
    params = {
      pattern = pattern,
      point = { x = c.x, y = c.y },
      altitude = mslAlt(alt, altType, c.x, c.y),
      speed = speed,
    },
  }
end

local function targetTypes(list)
  local out = {}
  for _, t in ipairs(type(list) == "table" and list or {}) do
    out[#out + 1] = F.TARGET_ATTRS[t] or t
  end
  if #out == 0 then
    out[1] = "Ground Units"
  end
  return out
end

local function engageTask(c, radius, targets)
  return {
    id = "EngageTargetsInZone",
    params = { point = { x = c.x, y = c.y }, zoneRadius = radius, targetTypes = targetTypes(targets), priority = 0 },
  }
end

function F.weaponFlag(w)
  if type(w) == "number" then
    return w
  end
  w = F.WEAPON_ALIASES[w] or w or "guided_bomb"
  return F.WEAPON_FLAGS[w] or F.WEAPON_FLAGS.guided_bomb
end

local function landingWaypoint(ab, fl, order)
  local okP, p = pcall(ab.getPoint, ab)
  local okI, id = pcall(ab.getID, ab)
  if not (okP and p) then
    return nil
  end
  local wp = waypoint(p.x, p.z, 0, "RADIO", speedOf(fl, order))
  wp.type = "Land"
  wp.action = "Landing"
  wp.airdromeId = okI and id or nil
  return wp, { x = p.x, y = p.z }
end

local function controller(fl)
  local g = liveGroup(fl.group)
  if not g then
    return nil
  end
  local ok, c = pcall(g.getController, g)
  if ok then
    return c
  end
  return nil
end

local function setTask(fl, task)
  local c = controller(fl)
  if not c then
    return false, "no controller"
  end
  local ok, err = pcall(c.setTask, c, task)
  if not ok then
    return false, tostring(err)
  end
  return true
end

local function setRoe(fl, value)
  local c = controller(fl)
  if not (c and AI and AI.Option and AI.Option.Air) then
    return
  end
  local ok, err = pcall(c.setOption, c, AI.Option.Air.id.ROE, value)
  if not ok then
    log("warn", "flight '%s': ROE option failed: %s", fl.id, tostring(err))
  end
end

local function openFire(fl)
  setRoe(fl, AI.Option.Air.val.ROE.OPEN_FIRE)
end

-- ---------------------------------------------------------------------------
-- landing detection
-- ---------------------------------------------------------------------------

-- A unit of the flight on the ground inside area {x, y, radius}: AGL < 3 m and speed < 2 m/s.
local function onGroundIn(fl, area)
  for _, u in ipairs(liveUnits(liveGroup(fl.group))) do
    local p = unitPoint(u)
    if p and dist2D(p, area) <= area.radius then
      local agl = p.y - groundHeight(p.x, p.z)
      local okV, v = pcall(u.getVelocity, u)
      local speed = 0
      if okV and type(v) == "table" then
        speed = math.sqrt((v.x or 0) ^ 2 + (v.y or 0) ^ 2 + (v.z or 0) ^ 2)
      end
      if agl < F.LANDED_AGL_M and speed < F.LANDED_SPEED_MPS then
        return true
      end
    end
  end
  return false
end

-- ---------------------------------------------------------------------------
-- orders
-- ---------------------------------------------------------------------------

local finishOrder, nextOrder

local function payload(fl, extra)
  local p = { flight = fl.id, group = fl.group }
  for k, v in pairs(extra or {}) do
    p[k] = v
  end
  return p
end

local function skip(fl, why)
  log("warn", "flight '%s' order %d (%s) skipped: %s", fl.id, fl.index, tostring(fl.cur and fl.cur.kind), why)
  fl.cur = nil
  nextOrder(fl)
end

local BEGIN = {}

local function setTaskErr(fl, task)
  local ok, err = setTask(fl, task)
  if not ok then
    return err
  end
  return nil
end

-- Altitude/speed for a transit without its own: the order's, else the latest earlier order's.
local function cruiseOf(fl, o)
  local c = { altM = o.altM, altType = o.altType, speedMps = o.speedMps }
  for k = fl.index - 1, 1, -1 do
    local p = fl.orders[k] or {}
    if c.speedMps == nil and p.speedMps then
      c.speedMps = p.speedMps
    end
    if c.altM == nil and p.altM then
      c.altM, c.altType = p.altM, p.altType
    end
  end
  return c
end

local function heliLandTask(fl, cur)
  cur.approach = false
  local last = fl.index >= #fl.orders
  return setTaskErr(fl, {
    id = "Land",
    params = {
      point = { x = cur.area.x, y = cur.area.y },
      durationFlag = not last,
      duration = math.floor(cur.groundSec + F.LAND_EXTRA_SEC),
    },
  })
end

BEGIN.fly = function(fl, o, cur)
  local to = resolvePlace(o.to)
  if not to then
    return "unknown zone '" .. tostring(o.to) .. "'"
  end
  local alt, altType = altOf(fl, o)
  cur.place = to
  cur.arriveM = math.max(F.ARRIVE_MIN_M, to.radius or 0)
  local ok, err = setTask(fl, routeTask(fl, to, alt, altType, speedOf(fl, o)))
  if not ok then
    return err
  end
  return nil
end

BEGIN.hold = function(fl, o, cur)
  local at = resolvePlace(o.at)
  if not at then
    return "unknown zone '" .. tostring(o.at) .. "'"
  end
  local alt, altType = altOf(fl, o)
  local speed = speedOf(fl, o)
  cur.place = at
  local ok, err = setTask(fl, routeTask(fl, at, alt, altType, speed, nil, { orbitTask(at, alt, altType, speed) }))
  if not ok then
    return err
  end
  return nil
end

BEGIN.engage = function(fl, o, cur)
  local at = resolvePlace(o.at)
  if not at then
    return "unknown zone '" .. tostring(o.at) .. "'"
  end
  local alt, altType = altOf(fl, o)
  local speed = speedOf(fl, o)
  local radius = tonumber(o.radiusM) or F.DEFAULT_RADIUS_M
  cur.place = at
  openFire(fl)
  local task = routeTask(
    fl,
    at,
    alt,
    altType,
    speed,
    { engageTask(at, radius, o.targets) },
    { orbitTask(at, alt, altType, speed) }
  )
  local ok, err = setTask(fl, task)
  if not ok then
    return err
  end
  return nil
end

BEGIN.escort = function(fl, o, cur)
  local other = o.flight and F._s.flights[o.flight]
  local gname = other and other.group or o.flight
  local tg = liveGroup(gname)
  if not tg then
    return "escorted flight '" .. tostring(o.flight) .. "' not alive"
  end
  local okI, gid = pcall(tg.getID, tg)
  if not okI then
    return "escorted group has no id"
  end
  cur.escorted = gname
  openFire(fl)
  local ok, err = setTask(fl, {
    id = "Escort",
    params = {
      groupId = gid,
      pos = { x = -200, y = 0, z = 200 },
      lastWptIndexFlag = false,
      engagementDistMax = tonumber(o.radiusM) or F.DEFAULT_RADIUS_M,
      targetTypes = targetTypes(o.targets),
    },
  })
  if not ok then
    return err
  end
  return nil
end

-- First live group whose name starts with `prefix` (DMS_ prefix allowed) and is not ours; one
-- inside `at` (within its radius + 2 km) wins over one elsewhere.
local function findTarget(fl, prefix, at)
  local mySide
  local g = liveGroup(fl.group)
  if g then
    local ok, s = pcall(g.getCoalition, g)
    mySide = ok and s or nil
  end
  local names = {}
  for _, side in ipairs({ 0, 1, 2 }) do
    if side ~= mySide and coalition and coalition.getGroups then
      local ok, groups = pcall(coalition.getGroups, side)
      if ok and type(groups) == "table" then
        for _, grp in ipairs(groups) do
          local okN, n = pcall(grp.getName, grp)
          if okN and prefixMatch(n, prefix) and #liveUnits(liveGroup(n)) > 0 then
            names[#names + 1] = n
          end
        end
      end
    end
  end
  table.sort(names)
  if at then
    for _, n in ipairs(names) do
      local u = liveUnits(liveGroup(n))[1]
      local p = u and unitPoint(u)
      if p and dist2D(p, at) <= (at.radius or 0) + 2000 then
        return n
      end
    end
  end
  return names[1]
end
F._findTarget = findTarget

local function unitName(u)
  local ok, n = pcall(u.getName, u)
  return ok and n or "?"
end

local function unitAlive(name)
  if not (Unit and Unit.getByName) then
    return false
  end
  local ok, u = pcall(Unit.getByName, name)
  if not ok or not u then
    return false
  end
  local okE, ex = pcall(u.isExist, u)
  return okE and ex == true
end

-- Weapon keyword -> does an ammo entry's desc match? (Weapon.Category: SHELL 0, MISSILE 1, ROCKET 2,
-- BOMB 3; Weapon.MissileCategory AAM 1, SAM 2.) [? desc.guidance only on guided bombs: headless check]
local AMMO_MATCH = {
  guided_bomb = function(d)
    return d.category == 3 and d.guidance ~= nil
  end,
  bomb = function(d)
    return d.category == 3
  end,
  missile = function(d)
    return d.category == 1 and d.missileCategory ~= 1 and d.missileCategory ~= 2
  end,
  rockets = function(d)
    return d.category == 2
  end,
  gun = function(d)
    return d.category == 0
  end,
  any = function(d)
    return d.category ~= 1 or (d.missileCategory ~= 1 and d.missileCategory ~= 2)
  end,
}

local function weaponKey(w)
  if type(w) == "number" then
    return "any"
  end
  w = F.WEAPON_ALIASES[w] or w or "guided_bomb"
  return AMMO_MATCH[w] and w or "guided_bomb"
end

-- Best effort: true when any live unit of the flight carries ammo of the order's weapon kind (or
-- when DCS gives no usable answer). Unit.getAmmo returns nil for an empty unit.
local function flightHasAmmo(fl, weapon)
  local match = AMMO_MATCH[weaponKey(weapon)]
  for _, u in ipairs(liveUnits(liveGroup(fl.group))) do
    local ok, ammo = pcall(u.getAmmo, u)
    if not ok then
      return true
    end
    if type(ammo) == "table" then
      for _, a in ipairs(ammo) do
        local d = type(a) == "table" and a.desc or nil
        if
          type(a) == "table"
          and (tonumber(a.count) or 0) > 0
          and (type(d) ~= "table" or d.category == nil or match(d))
        then
          return true
        end
      end
    end
  end
  return false
end
F._flightHasAmmo = flightHasAmmo

-- One strike pass: a ComboTask with one AttackUnit per aircraft, each on a different live unit of
-- the target group (ordered by unit). -> error string or nil.
local function startStrikePass(fl, cur)
  local targets = liveUnits(liveGroup(cur.target))
  if #targets == 0 then
    return "target group has no live units"
  end
  local aircraft = math.max(1, #liveUnits(liveGroup(fl.group)))
  local expend = (#targets <= aircraft) and "One" or "Two"
  local tasks, names = {}, {}
  for i = 1, math.min(aircraft, #targets) do
    local u = targets[i]
    local okI, uid = pcall(u.getID, u)
    if okI and uid then
      tasks[#tasks + 1] = {
        id = "AttackUnit",
        number = #tasks + 1,
        enabled = true,
        auto = false,
        params = {
          unitId = uid,
          weaponType = cur.flag,
          expend = expend,
          attackQtyLimit = true,
          attackQty = 1,
          groupAttack = false,
          directionEnabled = false,
          altitudeEnabled = cur.attackAlt ~= nil,
          altitude = cur.attackAlt,
        },
      }
      names[#names + 1] = unitName(u)
    end
  end
  if #tasks == 0 then
    return "target units have no id"
  end
  cur.pass = (cur.pass or 0) + 1
  cur.passUnits = names
  cur.passReleasedAt = nil
  log("info", "flight '%s' strike pass %d: targets %s", fl.id, cur.pass, table.concat(names, ","))
  return setTaskErr(fl, { id = "ComboTask", params = { tasks = tasks } })
end

BEGIN.strike = function(fl, o, cur)
  local at = resolvePlace(o.at)
  local target = o.group and findTarget(fl, o.group, at) or nil
  if not at and not target then
    return "unknown zone '" .. tostring(o.at) .. "' and no target group"
  end
  local alt, altType = altOf(fl, o)
  local flag = F.weaponFlag(o.weapon)
  cur.place = at
  cur.flag = flag
  openFire(fl)
  if target then
    cur.target = target
    if o.altM then
      local u = liveUnits(liveGroup(target))[1]
      local p = u and unitPoint(u)
      cur.attackAlt = mslAlt(alt, altType, p and p.x or (at and at.x or 0), p and p.z or (at and at.y or 0))
    end
    log("info", "flight '%s' strike: AttackUnit on %s weaponType=%s", fl.id, target, tostring(flag))
    return startStrikePass(fl, cur)
  end
  cur.target = nil
  log("info", "flight '%s' strike: Bombing on %s weaponType=%s", fl.id, tostring(o.at), tostring(flag))
  return setTaskErr(fl, {
    id = "Bombing",
    params = {
      point = { x = at.x, y = at.y },
      weaponType = flag,
      expend = "All",
      attackQty = 1,
      groupAttack = true,
      directionEnabled = false,
      altitudeEnabled = o.altM ~= nil,
      altitude = o.altM and mslAlt(alt, altType, at.x, at.y) or nil,
    },
  })
end

-- Landing at an airbase (planes; rtb for both): route with a Landing waypoint.
local function beginAirbaseLanding(fl, o, cur, ab)
  local wp, p = landingWaypoint(ab, fl, o)
  if not wp then
    return "airbase has no position"
  end
  local alt, altType = altOf(fl, o)
  cur.area = { x = p.x, y = p.y, radius = F.AIRBASE_AREA_M }
  local okN, abName = pcall(ab.getName, ab)
  cur.zone = o.at or (okN and abName) or nil
  local ok, err = setTask(fl, routeTask(fl, p, alt, altType, speedOf(fl, o), nil, nil, wp))
  if not ok then
    return err
  end
  return nil
end

BEGIN.land = function(fl, o, cur)
  local at = resolvePlace(o.at)
  if not at then
    return "unknown zone or airbase '" .. tostring(o.at) .. "'"
  end
  cur.groundSec = range(o.groundSec, F.DEFAULT_GROUND_SEC)
  cur.zone = o.at
  if flightCategory(fl) == "helicopter" then
    cur.place = at
    cur.area = { x = at.x, y = at.y, radius = math.max(F.LAND_AREA_MIN_M, at.radius or 0) }
    local p = leadPoint(fl)
    if p and dist2D(p, at) > F.LAND_APPROACH_M then
      -- A bare Land task flies the transit at the AI's own approach speed [? headless check]:
      -- route there at cruise first, Land when within LAND_APPROACH_M (see landProgress).
      local c = cruiseOf(fl, o)
      local alt, altType = altOf(fl, c)
      cur.approach = true
      log("info", "flight '%s' land: approach to %s at %.0f m/s first", fl.id, tostring(o.at), speedOf(fl, c))
      return setTaskErr(fl, routeTask(fl, at, alt, altType, speedOf(fl, c)))
    end
    return heliLandTask(fl, cur)
  end
  local ab = at.airbase or nearestAirbase({ x = at.x, y = at.y }, fl.side)
  if not ab then
    return "no airbase near '" .. tostring(o.at) .. "' for a plane"
  end
  return beginAirbaseLanding(fl, o, cur, ab)
end

BEGIN.rtb = function(fl, o, cur)
  local ab
  if fl.def.startAirbase and Airbase and Airbase.getByName then
    local ok, r = pcall(Airbase.getByName, fl.def.startAirbase)
    ab = ok and r or nil
  end
  if not ab then
    local p = leadPoint(fl)
    ab = p and nearestAirbase(p, fl.side) or nil
  end
  if not ab then
    return "no airbase to return to"
  end
  cur.groundSec = 0
  return beginAirbaseLanding(fl, o, cur, ab)
end

-- Pickup: remove the pickup group's units within PICKUP_RADIUS_M of the flight's lead.
local function doPickup(fl, o)
  local pg = liveGroup(o.pickup)
  local lead = leadPoint(fl)
  local n = 0
  if pg and lead then
    for _, u in ipairs(liveUnits(pg)) do
      local p = unitPoint(u)
      if p and dist2D(p, { x = lead.x, y = lead.z }) <= F.PICKUP_RADIUS_M then
        local ok = pcall(u.destroy, u)
        if ok then
          n = n + 1
        end
      end
    end
  end
  log("info", "flight '%s' pickup '%s': %d unit(s) boarded", fl.id, tostring(o.pickup), n)
  emit("flight.pickup", payload(fl, { pickup = o.pickup, units = n }))
end

local function markLanded(fl, cur)
  if cur.landedAt then
    return
  end
  cur.landedAt = now()
  log("info", "flight '%s' landed at %s", fl.id, tostring(cur.zone))
  emit("flight.landed", payload(fl, { zone = cur.zone }))
end

-- -> true when the current order is done
local PROGRESS = {}

PROGRESS.fly = function(fl, cur)
  local p = leadPoint(fl)
  if p and dist2D(p, cur.place) <= cur.arriveM then
    emit("flight.arrived", payload(fl, { zone = cur.order.to }))
    return true, "arrived"
  end
  return false
end

local function untilOrMax(_, cur)
  if cur.untilCond and conditionReady(cur.untilCond) then
    return true, "until"
  end
  if now() - cur.startedAt >= cur.maxSec then
    return true, "maxSec"
  end
  return false
end
PROGRESS.hold = untilOrMax
PROGRESS.engage = untilOrMax
PROGRESS.escort = function(fl, cur)
  if cur.escorted and not liveGroup(cur.escorted) then
    return true, "escorted group gone"
  end
  return untilOrMax(fl, cur)
end

-- A pass is over STRIKE_PASS_SEC after its last release, or when all of its targeted units died.
local function strikePassOver(cur)
  if cur.passReleasedAt and now() - cur.passReleasedAt >= F.STRIKE_PASS_SEC then
    return true
  end
  for _, name in ipairs(cur.passUnits or {}) do
    if unitAlive(name) then
      return false
    end
  end
  return true
end

PROGRESS.strike = function(fl, cur)
  if cur.target then
    if #liveUnits(liveGroup(cur.target)) == 0 then
      return true, "target dead"
    end
  elseif cur.releasedAt and now() - cur.releasedAt >= F.STRIKE_AFTER_RELEASE_SEC then
    return true, "weapon released"
  end
  if now() - cur.startedAt >= cur.maxSec then
    return true, "maxSec"
  end
  if cur.target and strikePassOver(cur) then
    if (cur.pass or 0) >= F.STRIKE_MAX_PASSES then
      return true, "passes exhausted"
    end
    if not flightHasAmmo(fl, cur.order.weapon) then
      return true, "no ammo"
    end
    local err = startStrikePass(fl, cur)
    if err then
      return true, err
    end
  end
  return false
end

local function landProgress(fl, cur)
  if cur.approach then
    local p = leadPoint(fl)
    if p and dist2D(p, cur.area) <= F.LAND_APPROACH_M then
      log("info", "flight '%s' land: approach done, Land at %s", fl.id, tostring(cur.zone))
      local err = heliLandTask(fl, cur)
      if err then
        return true, "land task failed: " .. err
      end
    end
    return false
  end
  if not cur.landedAt and cur.area and onGroundIn(fl, cur.area) then
    markLanded(fl, cur)
  end
  if not cur.landedAt then
    return false
  end
  if now() - cur.landedAt < (cur.groundSec or 0) then
    return false
  end
  local o = cur.order
  if o.pickup then
    doPickup(fl, o)
  end
  if o.kind == "land" and fl.index < #fl.orders then
    log("info", "flight '%s' lifting from %s", fl.id, tostring(cur.zone))
    emit("flight.lifted", payload(fl, { zone = cur.zone }))
  end
  return true, "ground time over"
end
PROGRESS.land = landProgress
PROGRESS.rtb = landProgress

local function beginOrder(fl)
  local o = fl.orders[fl.index]
  local cur = fl.cur
  cur.waiting = false
  cur.startedAt = now()
  cur.maxSec = range(o.maxSec, F.DEFAULT_MAX_SEC[o.kind] or math.huge)
  local fn = BEGIN[o.kind]
  if not fn then
    skip(fl, "unknown order kind")
    return
  end
  local ok, err = pcall(fn, fl, o, cur)
  if not ok then
    skip(fl, "error: " .. tostring(err))
    return
  end
  if err then
    skip(fl, err)
    return
  end
  fl.since = now()
  log("info", "flight '%s' order %d/%d started: %s", fl.id, fl.index, #fl.orders, o.kind)
  emit("flight.order", payload(fl, { index = fl.index, kind = o.kind }))
end

nextOrder = function(fl)
  if fl.status ~= "running" then
    return
  end
  fl.index = fl.index + 1
  local o = fl.orders[fl.index]
  if not o then
    fl.status = "done"
    fl.since = now()
    fl.cur = nil
    log("info", "flight '%s' done (%d order(s))", fl.id, #fl.orders)
    emit("flight.done", payload(fl))
    return
  end
  fl.cur = { kind = o.kind, order = o, waiting = true, untilCond = fl.untils[fl.index] }
  if not conditionReady(fl.whens[fl.index]) then
    log("info", "flight '%s' order %d (%s) waiting for its start condition", fl.id, fl.index, tostring(o.kind))
    fl.since = now()
    return
  end
  beginOrder(fl)
end

finishOrder = function(fl, why)
  local cur = fl.cur
  if not cur or fl.status ~= "running" then
    return
  end
  log("info", "flight '%s' order %d (%s) done: %s", fl.id, fl.index, tostring(cur.kind), tostring(why))
  fl.cur = nil
  nextOrder(fl)
end

local function lose(fl, reason)
  if fl.status == "lost" or fl.status == "done" then
    return
  end
  fl.status = "lost"
  fl.since = now()
  fl.cur = nil
  log("info", "flight '%s' lost (%s)", fl.id, tostring(reason))
  emit("flight.lost", payload(fl, { reason = reason }))
end

local function tickFlight(fl)
  if fl.status ~= "running" then
    return
  end
  if not fl.found then
    return
  end
  if #liveUnits(liveGroup(fl.group)) == 0 then
    lose(fl, "dead")
    return
  end
  local cur = fl.cur
  if not cur then
    return
  end
  if cur.waiting then
    if conditionReady(fl.whens[fl.index]) then
      beginOrder(fl)
    end
    return
  end
  local fn = PROGRESS[cur.kind]
  if not fn then
    return
  end
  local done, why = fn(fl, cur)
  if done then
    finishOrder(fl, why)
  end
end

-- ---------------------------------------------------------------------------
-- telemetry (debug builds or DMS_CONFIG.flightsTelemetry)
-- ---------------------------------------------------------------------------

local function telemetryOn()
  return (DMS.Log and DMS.Log.isDebug and DMS.Log.isDebug()) or cfg().flightsTelemetry == true
end

local function groupLeadXY(name)
  local u = name and liveUnits(liveGroup(name))[1]
  local p = u and unitPoint(u)
  return p and { x = p.x, y = p.z } or nil
end

local function orderTargetXY(cur)
  if not cur then
    return nil
  end
  return (cur.target and groupLeadXY(cur.target))
    or (cur.escorted and groupLeadXY(cur.escorted))
    or cur.area
    or cur.place
end

local function round(v)
  return math.floor(v + 0.5)
end

local function telemFlight(fl)
  if fl.status ~= "running" or not fl.found then
    return
  end
  local u = liveUnits(liveGroup(fl.group))[1]
  local p = u and unitPoint(u)
  if not p then
    return
  end
  local spd = 0
  local okV, v = pcall(u.getVelocity, u)
  if okV and type(v) == "table" then
    spd = math.sqrt((v.x or 0) ^ 2 + (v.y or 0) ^ 2 + (v.z or 0) ^ 2)
  end
  local tp = orderTargetXY(fl.cur)
  log(
    "info",
    "TELEM flight=%s order=%d/%s spd=%d agl=%d msl=%d dist=%s",
    fl.id,
    fl.index,
    fl.cur and tostring(fl.cur.kind) or "-",
    round(spd * 1.943844),
    round((p.y - groundHeight(p.x, p.z)) * 3.28084),
    round(p.y * 3.28084),
    tp and tostring(round(dist2D(p, tp))) or "-"
  )
end

-- ---------------------------------------------------------------------------
-- bus handlers
-- ---------------------------------------------------------------------------

local function flightOfGroup(gname)
  if not gname then
    return nil
  end
  for _, id in ipairs(F._s.ids) do
    local fl = F._s.flights[id]
    if fl.group == gname then
      return fl
    end
  end
  return nil
end

local function onLanded(ev)
  local fl = ev and flightOfGroup(ev.group)
  local cur = fl and fl.status == "running" and fl.cur
  if not cur or cur.waiting or not (cur.kind == "land" or cur.kind == "rtb") or not cur.area then
    return
  end
  local p
  if Unit and ev.unit then
    local ok, u = pcall(Unit.getByName, ev.unit)
    if ok and u then
      p = unitPoint(u)
    end
  end
  if p and dist2D(p, cur.area) <= cur.area.radius then
    markLanded(fl, cur)
  end
end

local function onShot(ev)
  local fl = ev and flightOfGroup(ev.initiatorGroup)
  local cur = fl and fl.status == "running" and fl.cur
  if not cur or cur.waiting or cur.kind ~= "strike" then
    return
  end
  cur.releasedAt = cur.releasedAt or now()
  cur.passReleasedAt = now() -- the pass ends STRIKE_PASS_SEC after its last release
  emit("flight.weapon", payload(fl, { weapon = ev.weapon, target = cur.target or cur.order.at }))
end

local function onGroupDead(ev)
  local fl = ev and flightOfGroup(ev.group)
  if fl then
    lose(fl, "dead")
  end
end

-- ---------------------------------------------------------------------------
-- watch focus (stand-in player)
-- ---------------------------------------------------------------------------

-- Register the watch focus group's units as players (DMS.Bus._players + player.spawned), the same
-- way DMS.Test registers its proxy, so Narrative/Intel/Director/Comms/Ambient treat it as the
-- player. Not used in a test run: there DMS.Test registers the proxy (= the focus flight).
function F.registerFocus()
  local w = cfg().watch
  local name = type(w) == "table" and w.focus or nil
  if not (name and DMS.Bus and DMS.Bus.emit) then
    return false
  end
  local g = liveGroup(name)
  local units = liveUnits(g)
  if #units == 0 then
    return false
  end
  local okI, gid = pcall(g.getID, g)
  local okS, side = pcall(g.getCoalition, g)
  for _, u in ipairs(units) do
    local okN, uname = pcall(u.getName, u)
    if okN and uname and not DMS.Bus._players[uname] then
      local okT, tname = pcall(u.getTypeName, u)
      local p = {
        unit = uname,
        group = name,
        groupId = okI and gid or nil,
        playerName = "WATCH",
        coalition = okS and side or nil,
        typeName = okT and tname or nil,
        standIn = true,
      }
      DMS.Bus._players[uname] = p
      DMS.Bus.emit("player.spawned", p)
    end
  end
  log("info", "watch focus '%s' stands in for the player (%d unit(s))", name, #units)
  return true
end

local function testProxyRun()
  local t = cfg().test
  return type(t) == "table" and t.enabled ~= false and t.playerProxy ~= nil
end

-- ---------------------------------------------------------------------------
-- public API
-- ---------------------------------------------------------------------------

function F.state(id)
  local fl = F._s.flights[id]
  if not fl then
    return nil
  end
  return { index = fl.index, kind = fl.cur and fl.cur.kind or nil, status = fl.status, since = fl.since }
end

function F.advance(id, why)
  local fl = F._s.flights[id]
  if not fl or fl.status ~= "running" or not fl.cur then
    return false
  end
  if fl.cur.waiting then
    beginOrder(fl)
    return true
  end
  finishOrder(fl, why or "advanced")
  return true
end

function F.groupName(id)
  local fl = F._s.flights[id]
  return fl and fl.group or nil
end

function F.ids()
  local out = {}
  for _, id in ipairs(F._s.ids) do
    out[#out + 1] = id
  end
  table.sort(out)
  return out
end

local function findAndRun(fl, tries)
  if fl.status ~= "running" or not F._s.started or F._s.flights[fl.id] ~= fl then
    return
  end
  if #liveUnits(liveGroup(fl.group)) > 0 then
    fl.found = true
    local g = liveGroup(fl.group)
    local ok, s = pcall(g.getCoalition, g)
    fl.side = (ok and s) or fl.def.coalition
    log("info", "flight '%s' (%s) found, %d order(s)", fl.id, fl.group, #fl.orders)
    nextOrder(fl)
    return
  end
  if tries >= F.FIND_TRIES then
    log("warn", "flight '%s': group '%s' not found", fl.id, tostring(fl.group))
    lose(fl, "missing")
    return
  end
  DMS.Clock.after(F.FIND_RETRY_SEC, function()
    findAndRun(fl, tries + 1)
  end)
end

function F.start()
  F.stop()
  F._s = freshState()
  local s = F._s
  local list = cfg().flights
  local watch = DMS.isWatch and DMS.isWatch()
  if type(list) ~= "table" or #list == 0 then
    list = {}
  end
  if #list == 0 and not watch then
    return
  end
  s.started = true
  if DMS.Bus and DMS.Bus.on then
    s.tokens[#s.tokens + 1] = DMS.Bus.on("unit.landed", onLanded)
    s.tokens[#s.tokens + 1] = DMS.Bus.on("unit.shot", onShot)
    s.tokens[#s.tokens + 1] = DMS.Bus.on("group.dead", onGroupDead)
  end
  for i, def in ipairs(list) do
    if type(def) == "table" then
      local id = def.id or ("flight_" .. i)
      if s.flights[id] then
        log("warn", "duplicate flight id '%s' ignored", id)
      elseif type(def.group) ~= "string" then
        log("warn", "flight '%s' has no group; ignored", id)
      else
        local fl = {
          id = id,
          def = def,
          group = def.group,
          orders = type(def.orders) == "table" and def.orders or {},
          index = 0,
          status = "running",
          since = now(),
          whens = {},
          untils = {},
        }
        for k, o in ipairs(fl.orders) do
          fl.whens[k] = o.when and newCondition(o.when) or nil
          fl.untils[k] = o["until"] and newCondition(o["until"]) or nil
        end
        s.flights[id] = fl
        s.ids[#s.ids + 1] = id
      end
    end
  end
  if DMS.Clock then
    for _, id in ipairs(s.ids) do
      local fl = s.flights[id]
      DMS.Clock.after(1, function()
        findAndRun(fl, 1)
      end)
    end
    s.clocks[#s.clocks + 1] = DMS.Clock.every(F.TICK_SEC, function()
      for _, id in ipairs(s.ids) do
        local ok, err = pcall(tickFlight, s.flights[id])
        if not ok then
          log("error", "flight '%s' tick: %s", id, tostring(err))
        end
      end
    end, { firstDelay = F.TICK_SEC })
    if #s.ids > 0 then
      s.clocks[#s.clocks + 1] = DMS.Clock.every(F.TELEM_SEC, function()
        if not telemetryOn() then
          return
        end
        for _, id in ipairs(s.ids) do
          local ok, err = pcall(telemFlight, s.flights[id])
          if not ok then
            log("warn", "flight '%s' telemetry: %s", id, tostring(err))
          end
        end
      end, { firstDelay = F.TELEM_SEC })
    end
    if watch and not testProxyRun() then
      local tries = 0
      local function arm()
        tries = tries + 1
        if not F.registerFocus() then
          if tries < F.FIND_TRIES then
            DMS.Clock.after(F.FIND_RETRY_SEC, arm)
          else
            log("warn", "watch focus '%s' not found; no stand-in player", tostring((cfg().watch or {}).focus))
          end
        end
      end
      DMS.Clock.after(1, arm)
    end
  end
  log("info", "started with %d flight(s)%s", #s.ids, watch and " (watch mission)" or "")
end

function F.stop()
  local s = F._s
  if not s then
    return
  end
  if DMS.Bus then
    for _, t in ipairs(s.tokens) do
      DMS.Bus.off(t)
    end
  end
  if DMS.Clock then
    for _, id in ipairs(s.clocks) do
      DMS.Clock.cancel(id)
    end
  end
  s.tokens, s.clocks, s.started = {}, {}, false
end
