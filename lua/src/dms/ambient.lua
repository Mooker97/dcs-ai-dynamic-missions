-- ambient.lua: DMS.Ambient -- friendly "base traffic" around the player's airbases.
--
-- A site (DMS_CONFIG.ambient.sites[i]) activates when a player unit of its coalition (incl. the
-- DMS.Test player proxy, via DMS.Spawner.playerUnits) comes within activeRadiusM of its point and
-- fills its layers one spawn every staggerSec: parked departures (uncontrolled, started later),
-- arrivals on approach, ground service vehicles looping on the apron, a pattern helicopter and a
-- few statics. When no such player has been within despawnRadiusM (> activeRadiusM: hysteresis)
-- for graceSec, everything the site owns is destroyed to save CPU; it re-activates on return.
--
-- Ambient has its OWN budget (site + global maxGroups/maxUnits). Its groups are never tracked in
-- DMS.Registry and never emit spawner.spawned, so Director spawn budgets, encounter budgets and
-- DMS.Test spawn counts ignore them. They are friendly (player coalition), so Intel ignores them;
-- the Director skips unit.dead / unit.shot of ambient groups (DMS.Ambient.isAmbient). Every group
-- gets SetImmortal + SetInvisible + weapons hold.
--
-- Runway gate: departures stay parked (uncontrolled) and arrivals are not spawned until a player
-- of the site's coalition has taken off, or departureDelaySec after start -- so nothing blocks
-- the runway the player uses at mission start. Parked aircraft use Airbase:getParking(true)
-- (free spots only) and skip spots inside `avoid` circles (the player's own parking spots).
-- Lua 5.1. Scheduling via DMS.Clock, events via DMS.Bus, logging via DMS.Log("Ambient").
DMS = DMS or {}
DMS.Ambient = DMS.Ambient or {}

local A = DMS.Ambient
local P = "Ambient"

A.KINDS = { "statics", "ground", "departures", "helo", "arrivals" } -- fill order

A.defaults = {
  enabled = true,
  checkSec = 5,
  graceSec = 30,
  staggerSec = 3,
  departureDelaySec = 600,
  maxGroups = 12,
  maxUnits = 24,
  readyDelaySec = 1, -- before touching a new group's controller
  landedDespawnSec = 90, -- arrivals: destroy this long after unit.landed
  maxAirLifeSec = 2400, -- any ambient aircraft older than this is removed
  failRetrySec = 60, -- a layer whose spawn failed waits this long before retrying
  site = {
    activeRadiusM = 8000,
    despawnRadiusM = 12000,
    maxGroups = 8,
    maxUnits = 16,
    coalition = 2,
    avoidRadiusM = 60,
  },
  layers = {
    departures = {
      count = 1,
      intervalSec = { 240, 480 },
      distanceM = 40000,
      altM = 1500,
      speed = 120,
      category = "airplane",
      startDelaySec = { 60, 240 },
    },
    arrivals = {
      count = 1,
      intervalSec = { 300, 600 },
      distanceM = 25000,
      altM = 1000,
      speed = 110,
      category = "airplane",
    },
    ground = { count = 2, radiusM = 500, speed = 4 },
    helo = { count = 1, radiusM = 3000, altM = 150, speed = 45, category = "helicopter" },
    statics = { count = 2, radiusM = 400 },
  },
}

-- free parking terminal types usable per category (Airbase:getParking Term_Type)
-- 16 runway, 40 helicopter only, 68 hardened shelter, 72 airplane only, 100/104 open/apron
local TERM_OK = {
  airplane = { [68] = true, [72] = true, [100] = true, [104] = true },
  helicopter = { [40] = true, [68] = true, [72] = true, [100] = true, [104] = true },
}

-- ---------------------------------------------------------------- helpers

local function now()
  return DMS.Clock.now()
end

local function merge(base, over)
  local out = {}
  for k, v in pairs(base or {}) do
    out[k] = v
  end
  for k, v in pairs(over or {}) do
    out[k] = v
  end
  return out
end

local function dist(a, b)
  local dx, dy = a.x - b.x, a.y - b.y
  return math.sqrt(dx * dx + dy * dy)
end

local function cfg()
  local c = DMS_CONFIG and DMS_CONFIG.ambient
  if type(c) ~= "table" then
    return nil
  end
  return c
end

local function settings()
  return merge(A.defaults, cfg() or {})
end

local function resolveCountry(name, side)
  if type(name) == "number" then
    return name
  end
  local cands = {}
  if type(name) == "string" then
    cands[#cands + 1] = name
  end
  cands[#cands + 1] = (side == 1) and "RUSSIA" or "USA"
  cands[#cands + 1] = (side == 1) and "CJTF_RED" or "CJTF_BLUE"
  for _, n in ipairs(cands) do
    local ok, id = pcall(function()
      return country.id[n]
    end)
    if ok and type(id) == "number" then
      return id
    end
  end
  return nil
end

local function groupObj(name)
  local ok, g = pcall(Group.getByName, name)
  if ok and g then
    local okE, ex = pcall(g.isExist, g)
    if okE and ex then
      return g
    end
  end
  return nil
end

local function groupSize(name)
  local g = groupObj(name)
  if not g then
    return 0
  end
  local ok, n = pcall(g.getSize, g)
  return ok and n or 0
end

local function leadPos(name)
  local g = groupObj(name)
  if not g then
    return nil
  end
  local ok, p = pcall(function()
    local u = g:getUnits()[1]
    return u and u:getPoint() or nil
  end)
  if ok and p then
    return { x = p.x, y = p.z }
  end
  return nil
end

local function staticAlive(name)
  local ok, alive = pcall(function()
    local s = StaticObject.getByName(name)
    return s ~= nil and s:isExist()
  end)
  return ok and alive
end

local function surfaceOk(p)
  local ok, st = pcall(land.getSurfaceType, { x = p.x, y = p.y })
  if not ok or st == nil then
    return true
  end
  local S = land.SurfaceType
  return st ~= S.WATER and st ~= S.SHALLOW_WATER and st ~= S.RUNWAY
end

local function wp(x, y, alt, speed, extra)
  local p = {
    x = x,
    y = y,
    alt = alt or 0,
    alt_type = "BARO",
    type = "Turning Point",
    action = "Turning Point",
    speed = speed or 0,
    ETA = 0,
    ETA_locked = false,
    speed_locked = true,
    formation_template = "",
    task = { id = "ComboTask", params = { tasks = {} } },
  }
  for k, v in pairs(extra or {}) do
    p[k] = v
  end
  return p
end

-- ---------------------------------------------------------------- state

function A.reset()
  local s = A._s
  if s then
    if s.tick then
      DMS.Clock.cancel(s.tick)
    end
    for _, t in ipairs(s.tokens or {}) do
      DMS.Bus.off(t)
    end
  end
  A._s = {
    started = false,
    tick = nil,
    tokens = {},
    sites = {}, -- id -> site state
    order = {}, -- site ids in config order
    owners = {}, -- group/static name -> {site=, kind=}
    ever = {}, -- every name ever owned (late events after destroy)
    playerTookOff = false,
    startT = 0,
  }
end
if not A._s then
  A.reset()
end

local function newSite(def, i)
  local d = A.defaults.site
  local s = merge(d, def)
  s.id = tostring(def.id or ("site" .. i))
  local st = {
    id = s.id,
    def = s,
    active = false,
    epoch = 0,
    lastNear = nil,
    groups = {}, -- name -> rec {kind, units, spawnedAt, state, ...}
    statics = {}, -- name -> type
    nextAt = {}, -- kind -> earliest next spawn
    filling = false,
    activations = 0,
    deactivations = 0,
    skipLogged = {},
  }
  -- center: explicit point, else the airbase position
  if type(s.point) == "table" and s.point.x and s.point.y then
    st.center = { x = s.point.x, y = s.point.y }
  end
  if s.airbase then
    local ok, ab = pcall(function()
      return Airbase.getByName(s.airbase)
    end)
    if ok and ab then
      st.airbase = ab
      if not st.center then
        local okP, p = pcall(ab.getPoint, ab)
        if okP and p then
          st.center = { x = p.x, y = p.z }
        end
      end
    else
      DMS.Log.warn(P, "Site '%s': airbase '%s' not found; departures/arrivals disabled", s.id, tostring(s.airbase))
    end
  end
  if not st.center then
    DMS.Log.warn(P, "Site '%s' has no point and no airbase position; skipped", s.id)
    return nil
  end
  if (s.despawnRadiusM or 0) <= (s.activeRadiusM or 0) then
    s.despawnRadiusM = s.activeRadiusM * 1.5
    DMS.Log.warn(P, "Site '%s': despawnRadiusM must exceed activeRadiusM; using %.0f", s.id, s.despawnRadiusM)
  end
  st.cid = resolveCountry(s.country, s.coalition)
  if not st.cid then
    DMS.Log.warn(P, "Site '%s': unknown country '%s'; skipped", s.id, tostring(s.country))
    return nil
  end
  st.layers = {}
  for _, kind in ipairs(A.KINDS) do
    local l = s.layers and s.layers[kind]
    if type(l) == "table" then
      st.layers[kind] = merge(A.defaults.layers[kind], l)
    end
  end
  return st
end

-- ---------------------------------------------------------------- queries

function A.sites()
  local out = {}
  for _, id in ipairs(A._s.order) do
    out[#out + 1] = id
  end
  table.sort(out)
  return out
end

function A.isActive(siteId)
  local st = A._s.sites[siteId]
  return st ~= nil and st.active
end

function A.isAmbient(name)
  return type(name) == "string" and (A._s.owners[name] ~= nil or A._s.ever[name] == true)
end

function A.owned(siteId)
  local st = A._s.sites[siteId]
  local out = { groups = {}, statics = {} }
  if not st then
    return out
  end
  for n in pairs(st.groups) do
    out.groups[#out.groups + 1] = n
  end
  for n in pairs(st.statics) do
    out.statics[#out.statics + 1] = n
  end
  table.sort(out.groups)
  table.sort(out.statics)
  return out
end

-- drop records whose objects no longer exist
local function prune(st)
  for name, rec in pairs(st.groups) do
    if not groupObj(name) then
      st.groups[name] = nil
      A._s.owners[name] = nil
      if rec.kind == "departures" or rec.kind == "arrivals" then
        local iv = (st.layers[rec.kind] or {}).intervalSec
        st.nextAt[rec.kind] = math.max(st.nextAt[rec.kind] or 0, now() + (iv and DMS.Rng.range(iv) or 0))
      end
    end
  end
  for name in pairs(st.statics) do
    if not staticAlive(name) then
      st.statics[name] = nil
      A._s.owners[name] = nil
    end
  end
end

local function siteCounts(st)
  local g, u = 0, 0
  for name in pairs(st.groups) do
    if groupObj(name) then
      g = g + 1
      u = u + groupSize(name)
    end
  end
  for name in pairs(st.statics) do
    if staticAlive(name) then
      u = u + 1
    end
  end
  return g, u
end

-- live ambient groups/units (statics count as units only)
function A.counts(siteId)
  if siteId then
    local st = A._s.sites[siteId]
    if not st then
      return 0, 0
    end
    return siteCounts(st)
  end
  local g, u = 0, 0
  for _, id in ipairs(A._s.order) do
    local sg, su = siteCounts(A._s.sites[id])
    g, u = g + sg, u + su
  end
  return g, u
end

local function layerCount(st, kind)
  if kind == "statics" then
    local n = 0
    for name in pairs(st.statics) do
      if staticAlive(name) then
        n = n + 1
      end
    end
    return n
  end
  local n = 0
  for name, rec in pairs(st.groups) do
    if rec.kind == kind and groupObj(name) then
      n = n + 1
    end
  end
  return n
end

-- budget check -> ok, reason
local function budgetOk(st, nUnits, isStatic)
  local s = settings()
  local sg, su = siteCounts(st)
  local gg, gu = A.counts()
  if not isStatic then
    if sg + 1 > (st.def.maxGroups or 0) then
      return false, "site group budget"
    end
    if gg + 1 > (s.maxGroups or 0) then
      return false, "global group budget"
    end
  end
  if su + nUnits > (st.def.maxUnits or 0) then
    return false, "site unit budget"
  end
  if gu + nUnits > (s.maxUnits or 0) then
    return false, "global unit budget"
  end
  return true
end

function A.runwayGateOpen()
  if A._s.playerTookOff then
    return true
  end
  return now() - (A._s.startT or 0) >= (settings().departureDelaySec or 0)
end

-- ---------------------------------------------------------------- placement

local function inAvoid(st, p, extra)
  for _, a in ipairs(st.def.avoid or {}) do
    if a.x and a.y then
      local r = (a.radiusM or st.def.avoidRadiusM or 60) + (extra or 0)
      if dist(p, a) < r then
        return true
      end
    end
  end
  return false
end

local function nearOwned(st, p, minM)
  for name in pairs(st.groups) do
    local lp = leadPos(name)
    if lp and dist(lp, p) < minM then
      return true
    end
  end
  for name in pairs(st.statics) do
    local ok, sp = pcall(function()
      local s = StaticObject.getByName(name)
      return s and s:getPoint() or nil
    end)
    if ok and sp and dist({ x = sp.x, y = sp.z }, p) < minM then
      return true
    end
  end
  return false
end

local function parkingSpots(st, available)
  if not st.airbase then
    return {}
  end
  local ok, list = pcall(st.airbase.getParking, st.airbase, available and true or false)
  if not ok or type(list) ~= "table" then
    return {}
  end
  local out = {}
  for _, sp in ipairs(list) do
    local v = sp.vTerminalPos
    if type(v) == "table" and v.x and v.z then
      out[#out + 1] = { index = sp.Term_Index, termType = sp.Term_Type, x = v.x, y = v.z }
    end
  end
  return out
end

-- a land point (not water/runway, not in avoid, clear of parking spots and owned objects)
local function groundPoint(st, layer)
  local spots = parkingSpots(st, false)
  local r = layer.radiusM or 400
  for _ = 1, 30 do
    local cand, fromSpot
    if #spots > 0 and DMS.Rng.random() < 0.7 then
      fromSpot = true
      local sp = spots[DMS.Rng.int(1, #spots)]
      local a = DMS.Rng.random() * 2 * math.pi
      local off = 30 + DMS.Rng.random() * 25
      cand = { x = sp.x + off * math.cos(a), y = sp.y + off * math.sin(a) }
    else
      local rr = r * math.sqrt(DMS.Rng.random())
      local a = DMS.Rng.random() * 2 * math.pi
      cand = { x = st.center.x + rr * math.cos(a), y = st.center.y + rr * math.sin(a) }
    end
    local dc = dist(cand, st.center)
    local ok = fromSpot or dc <= r
    if dc > (st.def.activeRadiusM or 8000) then
      ok = false
    end
    if ok then
      ok = surfaceOk(cand) and not inAvoid(st, cand, 20) and not nearOwned(st, cand, 20)
    end
    if ok then
      for _, sp in ipairs(spots) do
        if dist(sp, cand) < 25 then
          ok = false
          break
        end
      end
    end
    if ok then
      return cand
    end
  end
  return nil
end

-- ---------------------------------------------------------------- unit types

local function typesFor(layer)
  local out = {}
  for _, t in ipairs(layer.types or {}) do
    out[#out + 1] = { type = t }
  end
  local tpls = (DMS_CONFIG and DMS_CONFIG.templates) or {}
  for _, id in ipairs(layer.templates or {}) do
    local tpl = tpls[id]
    if tpl and tpl.units and #tpl.units > 0 then
      out[#out + 1] = { template = id, units = tpl.units }
    end
  end
  return out
end

local function pickUnits(layer, isAir)
  local c = typesFor(layer)
  if #c == 0 then
    return nil
  end
  local pick = c[DMS.Rng.int(1, #c)]
  if pick.type then
    return { { type = pick.type, dx = 0, dy = 0 } }, pick.type
  end
  if isAir then
    return { { type = pick.units[1].type, dx = 0, dy = 0 } }, pick.template
  end
  return pick.units, pick.template
end

local function airPayload(typeName)
  local fuel
  pcall(function()
    local d = Unit.getDescByName(typeName)
    fuel = d and d.fuelMassMax
  end)
  if type(fuel) == "number" and fuel > 0 then
    return { pylons = {}, fuel = fuel * 0.6, flare = 0, chaff = 0, gun = 0 }
  end
  return nil
end

-- ---------------------------------------------------------------- AI setup

local function configure(name, isAir)
  local g = groupObj(name)
  if not g then
    return
  end
  local okC, c = pcall(g.getController, g)
  if not okC or not c then
    return
  end
  pcall(c.setCommand, c, { id = "SetImmortal", params = { value = true } })
  pcall(c.setCommand, c, { id = "SetInvisible", params = { value = true } })
  pcall(function()
    if isAir then
      c:setOption(AI.Option.Air.id.ROE, AI.Option.Air.val.ROE.WEAPON_HOLD)
      c:setOption(AI.Option.Air.id.REACTION_ON_THREAT, AI.Option.Air.val.REACTION_ON_THREAT.NO_REACTION)
    else
      c:setOption(AI.Option.Ground.id.ROE, AI.Option.Ground.val.ROE.WEAPON_HOLD)
      c:setOption(AI.Option.Ground.id.ALARM_STATE, AI.Option.Ground.val.ALARM_STATE.GREEN)
    end
  end)
end

local function addGroup(st, kind, cat, data, nUnits, isAir, rec)
  local ok, grp = pcall(coalition.addGroup, st.cid, cat, data)
  if not ok or not grp then
    DMS.Log.warn(P, "Site '%s': addGroup failed for %s '%s': %s", st.id, kind, data.name, tostring(grp))
    return nil
  end
  rec = rec or {}
  rec.kind = kind
  rec.units = nUnits
  rec.spawnedAt = now()
  rec.isAir = isAir
  st.groups[data.name] = rec
  A._s.owners[data.name] = { site = st.id, kind = kind }
  A._s.ever[data.name] = true
  local epoch = st.epoch
  DMS.Clock.after(A.defaults.readyDelaySec, function()
    if st.epoch == epoch then
      configure(data.name, isAir)
    end
  end)
  DMS.Log.debug(P, "Site '%s': spawned %s '%s' (%d unit(s))", st.id, kind, data.name, nUnits)
  return data.name
end

local function unitsData(name, units, pos, heading, extra)
  local out = {}
  local cosH, sinH = math.cos(heading), math.sin(heading)
  for i, u in ipairs(units) do
    local dx, dy = u.dx or 0, u.dy or 0
    local rec = {
      type = u.type,
      name = name .. "-" .. i,
      x = pos.x + dx * cosH - dy * sinH,
      y = pos.y + dx * sinH + dy * cosH,
      heading = heading,
      skill = "Average",
      playerCanDrive = false,
    }
    for k, v in pairs(extra or {}) do
      rec[k] = v
    end
    out[i] = rec
  end
  return out
end

-- ---------------------------------------------------------------- layer spawners

local spawners = {}

spawners.statics = function(st, layer)
  local list = typesFor(layer)
  local types = {}
  for _, c in ipairs(list) do
    if c.type then
      types[#types + 1] = c.type
    end
  end
  if #types == 0 then
    return nil, "no static types"
  end
  local ok, why = budgetOk(st, 1, true)
  if not ok then
    return nil, why
  end
  local p = groundPoint(st, layer)
  if not p then
    return nil, "no valid point"
  end
  local name = DMS.Registry.allocName("amb_" .. st.id .. "_static")
  local data = {
    name = name,
    type = types[DMS.Rng.int(1, #types)],
    x = p.x,
    y = p.y,
    heading = DMS.Rng.random() * 2 * math.pi,
    dead = false,
  }
  if layer.category then
    data.category = layer.category
  end
  local okA, obj = pcall(coalition.addStaticObject, st.cid, data)
  if not okA or not obj then
    return nil, "addStaticObject failed: " .. tostring(obj)
  end
  st.statics[name] = data.type
  A._s.owners[name] = { site = st.id, kind = "statics" }
  A._s.ever[name] = true
  DMS.Log.debug(P, "Site '%s': static '%s' (%s)", st.id, name, data.type)
  return name
end

local function loopPoints(st, layer, n)
  local pts = {}
  for _ = 1, n do
    local p = groundPoint(st, layer)
    if p then
      pts[#pts + 1] = p
    end
  end
  return pts
end

local function groundRoute(pts, speed)
  local route = {}
  for i, p in ipairs(pts) do
    route[i] = wp(p.x, p.y, 0, speed, { action = "Off Road" })
  end
  return { points = route }
end

spawners.ground = function(st, layer)
  local units, label = pickUnits(layer, false)
  if not units then
    return nil, "no ground types"
  end
  local ok, why = budgetOk(st, #units, false)
  if not ok then
    return nil, why
  end
  local pts = loopPoints(st, layer, 4)
  if #pts < 2 then
    return nil, "no valid point"
  end
  local heading = math.atan2(pts[2].y - pts[1].y, pts[2].x - pts[1].x)
  -- every unit position valid too
  local cosH, sinH = math.cos(heading), math.sin(heading)
  for _, u in ipairs(units) do
    local up = {
      x = pts[1].x + (u.dx or 0) * cosH - (u.dy or 0) * sinH,
      y = pts[1].y + (u.dx or 0) * sinH + (u.dy or 0) * cosH,
    }
    if not surfaceOk(up) then
      return nil, "unit on water/runway"
    end
  end
  local name = DMS.Registry.allocName("amb_" .. st.id .. "_gnd")
  local speed = layer.speed or 4
  local data = {
    name = name,
    task = "Ground Nothing",
    x = pts[1].x,
    y = pts[1].y,
    units = unitsData(name, units, pts[1], heading),
    route = groundRoute(pts, speed),
    visible = false,
    uncontrollable = false,
  }
  local rec = { loop = pts, speed = speed, label = label }
  return addGroup(st, "ground", Group.Category.GROUND, data, #units, false, rec)
end

spawners.departures = function(st, layer)
  if not st.airbase then
    return nil, "no airbase"
  end
  local cat = layer.category == "helicopter" and "helicopter" or "airplane"
  local units, label = pickUnits(layer, true)
  if not units then
    return nil, "no aircraft types"
  end
  local ok, why = budgetOk(st, 1, false)
  if not ok then
    return nil, why
  end
  local spots = {}
  for _, sp in ipairs(parkingSpots(st, true)) do
    if (sp.termType == nil or TERM_OK[cat][sp.termType]) and not inAvoid(st, sp, 0) and not nearOwned(st, sp, 25) then
      spots[#spots + 1] = sp
    end
  end
  if #spots == 0 then
    return nil, "no free parking"
  end
  local sp = spots[DMS.Rng.int(1, #spots)]
  local okId, abId = pcall(st.airbase.getID, st.airbase)
  local bearing = DMS.Rng.random() * 2 * math.pi
  local d = layer.distanceM or 40000
  local gh = 0
  pcall(function()
    gh = land.getHeight({ x = sp.x, y = sp.y })
  end)
  local name = DMS.Registry.allocName("amb_" .. st.id .. "_dep")
  local alt = layer.altM or 1500
  local speed = layer.speed or 120
  local u = unitsData(name, units, sp, bearing, {
    alt = gh,
    alt_type = "RADIO",
    speed = 0,
    parking = sp.index,
    payload = airPayload(units[1].type),
  })
  local data = {
    name = name,
    task = "Transport",
    uncontrolled = true,
    x = sp.x,
    y = sp.y,
    units = u,
    route = {
      points = {
        wp(sp.x, sp.y, gh, 0, {
          type = "TakeOffParking",
          action = "From Parking Area",
          airdromeId = okId and abId or nil,
        }),
        wp(st.center.x + d * 0.5 * math.cos(bearing), st.center.y + d * 0.5 * math.sin(bearing), alt, speed),
        wp(st.center.x + d * math.cos(bearing), st.center.y + d * math.sin(bearing), alt, speed),
      },
    },
    visible = false,
  }
  local gcat = cat == "helicopter" and Group.Category.HELICOPTER or Group.Category.AIRPLANE
  return addGroup(st, "departures", gcat, data, 1, true, {
    state = "parked",
    spot = sp,
    startAt = now() + DMS.Rng.range(layer.startDelaySec or { 60, 240 }),
    label = label,
  })
end

spawners.arrivals = function(st, layer)
  if not st.airbase then
    return nil, "no airbase"
  end
  if not A.runwayGateOpen() then
    return nil, "runway gate closed (player not airborne yet)"
  end
  local cat = layer.category == "helicopter" and "helicopter" or "airplane"
  local units, label = pickUnits(layer, true)
  if not units then
    return nil, "no aircraft types"
  end
  local ok, why = budgetOk(st, 1, false)
  if not ok then
    return nil, why
  end
  local okId, abId = pcall(st.airbase.getID, st.airbase)
  local d = layer.distanceM or 25000
  local bearing = DMS.Rng.random() * 2 * math.pi
  local start = { x = st.center.x + d * math.cos(bearing), y = st.center.y + d * math.sin(bearing) }
  local mid = { x = st.center.x + d * 0.4 * math.cos(bearing), y = st.center.y + d * 0.4 * math.sin(bearing) }
  local alt = layer.altM or 1000
  local speed = layer.speed or 110
  local heading = bearing + math.pi
  local name = DMS.Registry.allocName("amb_" .. st.id .. "_arr")
  local data = {
    name = name,
    task = "Transport",
    x = start.x,
    y = start.y,
    units = unitsData(name, units, start, heading, {
      alt = alt,
      alt_type = "BARO",
      speed = speed,
      payload = airPayload(units[1].type),
    }),
    route = {
      points = {
        wp(start.x, start.y, alt, speed),
        wp(mid.x, mid.y, math.max(300, alt * 0.6), speed),
        wp(st.center.x, st.center.y, 0, speed * 0.7, {
          type = "Land",
          action = "Landing",
          airdromeId = okId and abId or nil,
        }),
      },
    },
    visible = false,
  }
  local gcat = cat == "helicopter" and Group.Category.HELICOPTER or Group.Category.AIRPLANE
  return addGroup(st, "arrivals", gcat, data, 1, true, { state = "inbound", label = label })
end

local function circlePoints(c, r, startA, n)
  local pts = {}
  for i = 0, n - 1 do
    local a = startA + i * 2 * math.pi / n
    pts[#pts + 1] = { x = c.x + r * math.cos(a), y = c.y + r * math.sin(a) }
  end
  return pts
end

local function airRoute(pts, alt, speed)
  local route = {}
  for i, p in ipairs(pts) do
    route[i] = wp(p.x, p.y, alt, speed, { alt_type = "RADIO" })
  end
  return { points = route }
end

spawners.helo = function(st, layer)
  local units, label = pickUnits(layer, true)
  if not units then
    return nil, "no helicopter types"
  end
  local ok, why = budgetOk(st, 1, false)
  if not ok then
    return nil, why
  end
  local r = layer.radiusM or 3000
  -- start on the far side of the circle from the nearest player
  local startA = DMS.Rng.random() * 2 * math.pi
  local best
  for _, pl in ipairs(DMS.Spawner.playerUnits()) do
    local pp = { x = pl.pos.x, y = pl.pos.z }
    local dd = dist(pp, st.center)
    if not best or dd < best.d then
      best = { d = dd, p = pp }
    end
  end
  if best and best.d > 1 then
    startA = math.atan2(best.p.y - st.center.y, best.p.x - st.center.x) + math.pi
  end
  local pts = circlePoints(st.center, r, startA, 6)
  local alt = layer.altM or 150
  local speed = layer.speed or 45
  local name = DMS.Registry.allocName("amb_" .. st.id .. "_helo")
  local heading = startA + math.pi / 2
  local data = {
    name = name,
    task = "Transport",
    x = pts[1].x,
    y = pts[1].y,
    units = unitsData(name, units, pts[1], heading, {
      alt = alt,
      alt_type = "RADIO",
      speed = speed,
      payload = airPayload(units[1].type),
    }),
    route = airRoute(pts, alt, speed),
    visible = false,
  }
  local gcat = layer.category == "airplane" and Group.Category.AIRPLANE or Group.Category.HELICOPTER
  return addGroup(st, "helo", gcat, data, 1, true, { loop = pts, alt = alt, speed = speed, label = label })
end

-- ---------------------------------------------------------------- fill / maintain

local function logSkip(st, kind, reason)
  local key = kind .. ":" .. tostring(reason)
  if st.skipLogged[key] then
    return
  end
  st.skipLogged[key] = true
  DMS.Log.info(P, "Site '%s': skipped %s spawn (%s)", st.id, kind, tostring(reason))
end

-- spawn at most one missing item; -> true if something spawned
local function fillOne(st)
  local t = now()
  for _, kind in ipairs(A.KINDS) do
    local layer = st.layers[kind]
    if layer and (layer.count or 0) > 0 and layerCount(st, kind) < layer.count and t >= (st.nextAt[kind] or 0) then
      local okS, name, why = pcall(spawners[kind], st, layer)
      if not okS then
        why = "error: " .. tostring(name)
        name = nil
        DMS.Log.error(P, "Site '%s': %s spawner failed: %s", st.id, kind, tostring(why))
      end
      if name then
        st.skipLogged[kind .. ":" .. "runway gate closed (player not airborne yet)"] = nil
        return true
      end
      logSkip(st, kind, why)
      -- budgets free up only when something goes away; gate opens with the clock -> short retry
      local retry = A.defaults.failRetrySec
      if why == "runway gate closed (player not airborne yet)" then
        retry = settings().checkSec or 5
      end
      st.nextAt[kind] = t + retry
    end
  end
  return false
end

local function fill(st, epoch)
  if not st.active or st.epoch ~= epoch then
    st.filling = false
    return
  end
  if fillOne(st) then
    DMS.Clock.after(settings().staggerSec or 3, fill, st, epoch)
  else
    st.filling = false
  end
end

local function startFill(st)
  if st.filling or not st.active then
    return
  end
  st.filling = true
  fill(st, st.epoch)
end

local function destroyGroup(st, name, reason)
  local g = groupObj(name)
  if g then
    pcall(g.destroy, g)
  end
  st.groups[name] = nil
  A._s.owners[name] = nil
  DMS.Log.debug(P, "Site '%s': removed '%s' (%s)", st.id, name, tostring(reason))
end

local function reroute(name, pts, alt, speed, isAir)
  local g = groupObj(name)
  if not g then
    return
  end
  -- rotate the loop so it starts at the point after the current one
  local route = isAir and airRoute(pts, alt, speed) or groundRoute(pts, speed)
  pcall(function()
    g:getController():setTask({ id = "Mission", params = { route = route } })
  end)
end

local function maintain(st)
  local t = now()
  local s = settings()
  local layers = st.layers
  for name, rec in pairs(st.groups) do
    local lp = leadPos(name)
    if lp then
      if rec.kind == "departures" then
        local layer = layers.departures or {}
        if rec.state == "parked" and A.runwayGateOpen() and t >= (rec.startAt or 0) then
          local g = groupObj(name)
          local ok = g
            and pcall(function()
              g:getController():setCommand({ id = "Start", params = {} })
            end)
          rec.state = "started"
          rec.startedAt = t
          DMS.Log.info(P, "Site '%s': departure '%s' starting up (%s)", st.id, name, tostring(ok and "ok" or "failed"))
        elseif rec.state == "started" then
          local d = layer.distanceM or 40000
          local farM = math.min((st.def.despawnRadiusM or 12000) + d * 0.5, d * 0.9)
          if dist(lp, st.center) > farM then
            destroyGroup(st, name, "departed")
            st.nextAt.departures = t + DMS.Rng.range(layer.intervalSec or { 240, 480 })
          elseif t - (rec.startedAt or t) > s.maxAirLifeSec then
            destroyGroup(st, name, "departure timeout")
            st.nextAt.departures = t + DMS.Rng.range(layer.intervalSec or { 240, 480 })
          end
        end
      elseif rec.kind == "arrivals" then
        local layer = layers.arrivals or {}
        local iv = layer.intervalSec or { 300, 600 }
        if rec.landedAt and t - rec.landedAt >= s.landedDespawnSec then
          destroyGroup(st, name, "landed")
          st.nextAt.arrivals = t + DMS.Rng.range(iv)
        elseif t - rec.spawnedAt > s.maxAirLifeSec then
          destroyGroup(st, name, "arrival timeout")
          st.nextAt.arrivals = t + DMS.Rng.range(iv)
        end
      elseif rec.loop and #rec.loop >= 2 then
        local last = rec.loop[#rec.loop]
        local near = rec.isAir and 400 or 40
        if dist(lp, last) < near then
          -- next lap: same points, reversed for ground (keeps vehicles moving), same for helo
          local pts = {}
          if rec.isAir then
            for i = 1, #rec.loop do
              pts[i] = rec.loop[i]
            end
          else
            for i = #rec.loop, 1, -1 do
              pts[#pts + 1] = rec.loop[i]
            end
          end
          rec.loop = pts
          reroute(name, pts, rec.alt, rec.speed, rec.isAir)
        end
      end
    end
  end
  prune(st)
end

-- ---------------------------------------------------------------- activation

local function nearestPlayer(st)
  local best
  for _, pl in ipairs(DMS.Spawner.playerUnits()) do
    if pl.coalition == st.def.coalition then
      local d = dist({ x = pl.pos.x, y = pl.pos.z }, st.center)
      if not best or d < best then
        best = d
      end
    end
  end
  return best
end

function A.activate(siteId)
  local st = A._s.sites[siteId]
  if not st or st.active then
    return false
  end
  st.active = true
  st.epoch = st.epoch + 1
  st.activations = st.activations + 1
  st.lastNear = now()
  st.nextAt = {}
  st.skipLogged = {}
  local groups, statics = 0, 0
  for kind, layer in pairs(st.layers) do
    if kind == "statics" then
      statics = statics + (layer.count or 0)
    else
      groups = groups + (layer.count or 0)
    end
  end
  groups = math.min(groups, st.def.maxGroups or groups)
  DMS.Log.info(
    P,
    "Site '%s' activated (#%d): queuing %d group(s), %d static(s), stagger %ss",
    st.id,
    st.activations,
    groups,
    statics,
    tostring(settings().staggerSec)
  )
  DMS.Bus.emit("ambient.activated", { site = st.id, groups = groups, statics = statics })
  startFill(st)
  return true
end

function A.deactivate(siteId, reason)
  local st = A._s.sites[siteId]
  if not st or not st.active then
    return 0
  end
  st.active = false
  st.epoch = st.epoch + 1
  st.filling = false
  st.deactivations = st.deactivations + 1
  local ng, ns = 0, 0
  for name in pairs(st.groups) do
    local g = groupObj(name)
    if g then
      pcall(g.destroy, g)
      ng = ng + 1
    end
    A._s.owners[name] = nil
  end
  for name in pairs(st.statics) do
    pcall(function()
      local s = StaticObject.getByName(name)
      if s and s:isExist() then
        s:destroy()
        ns = ns + 1
      end
    end)
    A._s.owners[name] = nil
  end
  st.groups, st.statics = {}, {}
  reason = reason or "manual"
  DMS.Log.info(P, "Site '%s' deactivated (%s): removed %d group(s), %d static(s)", st.id, reason, ng, ns)
  DMS.Bus.emit("ambient.deactivated", { site = st.id, groups = ng, statics = ns, reason = reason })
  return ng
end

function A.tick()
  local s = settings()
  local t = now()
  for _, id in ipairs(A._s.order) do
    local st = A._s.sites[id]
    local d = nearestPlayer(st)
    if not st.active then
      if d and d <= st.def.activeRadiusM then
        A.activate(id)
      end
    else
      if d and d <= st.def.despawnRadiusM then
        st.lastNear = t
      end
      if t - (st.lastNear or t) >= (s.graceSec or 30) then
        A.deactivate(id, "left")
      else
        maintain(st)
        startFill(st)
      end
    end
  end
end

-- ---------------------------------------------------------------- lifecycle

function A.start()
  local c = cfg()
  if A._s.started then
    return false
  end
  if not c or c.enabled == false then
    DMS.Log.debug(P, "Disabled (no DMS_CONFIG.ambient or enabled=false)")
    return false
  end
  A.reset()
  A._s.started = true
  A._s.startT = now()
  local s = settings()
  for i, def in ipairs(c.sites or {}) do
    if type(def) == "table" then
      local st = newSite(def, i)
      if st and not A._s.sites[st.id] then
        A._s.sites[st.id] = st
        A._s.order[#A._s.order + 1] = st.id
      end
    end
  end
  local tokens = A._s.tokens
  tokens[#tokens + 1] = DMS.Bus.on("unit.takeoff", function(ev)
    if A._s.playerTookOff or not ev or not ev.unit then
      return
    end
    local pl = DMS.Bus._players and DMS.Bus._players[ev.unit]
    if pl then
      A._s.playerTookOff = true
      DMS.Log.info(P, "Runway gate open: player '%s' took off", tostring(ev.unit))
    end
  end)
  tokens[#tokens + 1] = DMS.Bus.on("unit.landed", function(ev)
    local o = ev and ev.group and A._s.owners[ev.group]
    if o and o.kind == "arrivals" then
      local st = A._s.sites[o.site]
      local rec = st and st.groups[ev.group]
      if rec and not rec.landedAt then
        rec.landedAt = now()
        rec.state = "landed"
        DMS.Log.debug(P, "Site '%s': arrival '%s' landed", o.site, ev.group)
      end
    end
  end)
  local every = tonumber(s.checkSec) or 5
  A._s.tick = DMS.Clock.every(every, function()
    A.tick()
  end, { firstDelay = math.min(every, 2) })
  DMS.Log.info(
    P,
    "Started: %d site(s) [%s] checkSec=%s graceSec=%s budget(groups=%s units=%s)",
    #A._s.order,
    table.concat(A._s.order, ","),
    tostring(every),
    tostring(s.graceSec),
    tostring(s.maxGroups),
    tostring(s.maxUnits)
  )
  return true
end
