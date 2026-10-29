-- spawner.lua: template + zone -> coalition.addGroup
-- Builds addGroup tables from DMS_CONFIG.templates, picks valid random points inside zones
-- (land only, away from players, optionally out of LOS / clear of buildings), applies
-- fog-of-war hiding at spawn time, checks budgets and tracks every group in DMS.Registry.
DMS = DMS or {}
DMS.Spawner = DMS.Spawner or {}

local Spawner = DMS.Spawner
local P = "Spawner"

Spawner.defaults = {
  tries = 40, -- candidate points per spawn
  minPlayerDistGround = 5000, -- m (research notes: ~5 km ground, out of LOS)
  minPlayerDistAir = 37000, -- m (~20 nm)
  readyDelaySec = 1, -- delay before touching a new group's controller
  buildingRadius = 0, -- m; 0 = no building check
  airAltM = 3000,
  airSpeed = 180,
}

local CATEGORY = {
  ground = function()
    return Group.Category.GROUND
  end,
  air = function()
    return Group.Category.AIRPLANE
  end,
  airplane = function()
    return Group.Category.AIRPLANE
  end,
  helicopter = function()
    return Group.Category.HELICOPTER
  end,
  ship = function()
    return Group.Category.SHIP
  end,
}

local function cfg()
  return DMS_CONFIG or {}
end

local function registryCategory(cat)
  if cat == "air" or cat == "airplane" or cat == "helicopter" then
    return "air"
  end
  if cat == "ship" then
    return "ship"
  end
  return "ground"
end

-- ---------------------------------------------------------------- geometry

function Spawner.pointInPolygon(px, py, pts)
  local inside = false
  local n = #pts
  local j = n
  for i = 1, n do
    local xi, yi = pts[i].x, pts[i].y
    local xj, yj = pts[j].x, pts[j].y
    if ((yi > py) ~= (yj > py)) and (px < (xj - xi) * (py - yi) / ((yj - yi) ~= 0 and (yj - yi) or 1e-9) + xi) then
      inside = not inside
    end
    j = i
  end
  return inside
end

-- Normalise a point-ish table to a 2D map point {x, y} (map y == vec3 z).
function Spawner.toVec2(p)
  if not p then
    return nil
  end
  if p.z ~= nil then
    return { x = p.x, y = p.z }
  end
  return { x = p.x, y = p.y }
end

local function dist2(a, b)
  local dx, dy = a.x - b.x, a.y - b.y
  return math.sqrt(dx * dx + dy * dy)
end
Spawner.dist2D = dist2

-- Resolve a zone id: DMS_CONFIG.zones first, then mission editor quad zones, then trigger zones.
function Spawner.getZone(zoneId)
  if type(zoneId) == "table" then
    return zoneId
  end
  local zones = cfg().zones
  if zones and zones[zoneId] then
    return zones[zoneId]
  end
  local ok, z = pcall(function()
    local tz = env and env.mission and env.mission.triggers and env.mission.triggers.zones
    if tz then
      for _, zz in pairs(tz) do
        if zz.name == zoneId and zz.type == 2 and zz.verticies and #zz.verticies >= 3 then
          local pts = {}
          for i, v in ipairs(zz.verticies) do
            pts[i] = { x = v.x, y = v.y }
          end
          return { kind = "polygon", points = pts }
        end
      end
    end
    return nil
  end)
  if ok and z then
    return z
  end
  local ok2, mz = pcall(trigger.misc.getZone, zoneId)
  if ok2 and mz and mz.point then
    return { kind = "circle", x = mz.point.x, y = mz.point.z, radius = mz.radius }
  end
  return nil
end

function Spawner.zoneCenter(zone)
  if not zone then
    return nil
  end
  if zone.kind == "polygon" and zone.points then
    local sx, sy, n = 0, 0, #zone.points
    for _, p in ipairs(zone.points) do
      sx, sy = sx + p.x, sy + p.y
    end
    return { x = sx / n, y = sy / n }
  end
  return { x = zone.x, y = zone.y }
end

function Spawner.zoneRadius(zone)
  if not zone then
    return 0
  end
  if zone.kind == "polygon" and zone.points then
    local c, r = Spawner.zoneCenter(zone), 0
    for _, p in ipairs(zone.points) do
      r = math.max(r, dist2(c, p))
    end
    return r
  end
  return zone.radius or 0
end

function Spawner.inZone(zone, p)
  if not zone or not p then
    return false
  end
  p = Spawner.toVec2(p)
  if zone.kind == "polygon" and zone.points then
    return Spawner.pointInPolygon(p.x, p.y, zone.points)
  end
  return dist2(p, { x = zone.x, y = zone.y }) <= (zone.radius or 0)
end

function Spawner.randomPointInZone(zone)
  if zone.kind == "polygon" and zone.points then
    local minx, maxx, miny, maxy = math.huge, -math.huge, math.huge, -math.huge
    for _, p in ipairs(zone.points) do
      minx, maxx = math.min(minx, p.x), math.max(maxx, p.x)
      miny, maxy = math.min(miny, p.y), math.max(maxy, p.y)
    end
    for _ = 1, 50 do
      local x = minx + DMS.Rng.random() * (maxx - minx)
      local y = miny + DMS.Rng.random() * (maxy - miny)
      if Spawner.pointInPolygon(x, y, zone.points) then
        return { x = x, y = y }
      end
    end
    return Spawner.zoneCenter(zone)
  end
  local r = (zone.radius or 0) * math.sqrt(DMS.Rng.random())
  local a = DMS.Rng.random() * 2 * math.pi
  return { x = zone.x + r * math.cos(a), y = zone.y + r * math.sin(a) }
end

-- ---------------------------------------------------------------- checks

function Spawner.isLand(p)
  local ok, st = pcall(land.getSurfaceType, { x = p.x, y = p.y })
  if not ok or st == nil then
    return true
  end
  local S = land.SurfaceType
  return st ~= S.WATER and st ~= S.SHALLOW_WATER
end

function Spawner.isWater(p)
  local ok, st = pcall(land.getSurfaceType, { x = p.x, y = p.y })
  if not ok or st == nil then
    return false
  end
  return st == land.SurfaceType.WATER
end

function Spawner.groundHeight(p)
  local ok, h = pcall(land.getHeight, { x = p.x, y = p.y })
  if ok and type(h) == "number" then
    return h
  end
  return 0
end

-- All player units currently alive, as list of {unit=, pos=vec3, coalition=}.
-- coalition.getPlayers plus units registered in DMS.Bus._players (BIRTH players and the
-- DMS.Test player proxy, which is an AI group and so never appears in getPlayers).
function Spawner.playerUnits()
  local out, seen = {}, {}
  for _, side in ipairs({ 1, 2 }) do
    local ok, players = pcall(coalition.getPlayers, side)
    if ok and players then
      for _, u in ipairs(players) do
        local ok2, pos, name = pcall(function()
          if u:isExist() then
            return u:getPoint(), u:getName()
          end
          return nil
        end)
        if ok2 and pos then
          out[#out + 1] = { unit = u, pos = pos, coalition = side }
          if name then
            seen[name] = true
          end
        end
      end
    end
  end
  local bp = DMS.Bus and DMS.Bus._players
  if type(bp) == "table" and Unit and Unit.getByName then
    local names = {}
    for name in pairs(bp) do
      if not seen[name] then
        names[#names + 1] = name
      end
    end
    table.sort(names)
    for _, name in ipairs(names) do
      local ok2, u, pos, side = pcall(function()
        local un = Unit.getByName(name)
        if un and un:isExist() then
          return un, un:getPoint(), un:getCoalition()
        end
        return nil
      end)
      if ok2 and u and pos then
        out[#out + 1] = { unit = u, pos = pos, coalition = side or bp[name].coalition }
      end
    end
  end
  return out
end

local function buildingsNear(p, radius)
  if not radius or radius <= 0 then
    return false
  end
  local found = false
  pcall(function()
    local vol = {
      id = world.VolumeType.SPHERE,
      params = { point = { x = p.x, y = Spawner.groundHeight(p), z = p.y }, radius = radius },
    }
    world.searchObjects(Object.Category.SCENERY, vol, function()
      found = true
      return false
    end)
  end)
  return found
end

-- Returns ok, reason
function Spawner.validPoint(p, opts, players)
  opts = opts or {}
  if opts.category == "ship" then
    if not Spawner.isWater(p) then
      return false, "not water"
    end
  elseif not (opts.category == "air" or opts.category == "airplane" or opts.category == "helicopter") then
    if not Spawner.isLand(p) then
      return false, "water"
    end
    if buildingsNear(p, opts.buildingRadius or Spawner.defaults.buildingRadius) then
      return false, "building"
    end
  end
  local minD = opts.minPlayerDistM
  for _, pl in ipairs(players or {}) do
    local pp = { x = pl.pos.x, y = pl.pos.z }
    if minD and minD > 0 and dist2(p, pp) < minD then
      return false, "near player"
    end
    if opts.outOfLOS then
      local eye = { x = p.x, y = Spawner.groundHeight(p) + (opts.losHeightM or 3), z = p.y }
      local ok, vis = pcall(land.isVisible, eye, pl.pos)
      if ok and vis then
        return false, "in LOS"
      end
    end
  end
  return true
end

-- ---------------------------------------------------------------- build

local SKILLS = { "Average", "Good", "High", "Excellent" }
local function adjustSkill(skill)
  if DMS.Director and DMS.Director.skillFor then
    local ok, s = pcall(DMS.Director.skillFor, skill)
    if ok and s then
      return s
    end
  end
  return skill
end
Spawner.SKILLS = SKILLS

local function resolveCountry(name)
  if type(name) == "number" then
    return name
  end
  if type(name) ~= "string" then
    return nil
  end
  local ok, id = pcall(function()
    return country.id[name]
  end) -- country.id may be strict
  if ok and type(id) == "number" then
    return id
  end
  return nil
end

local function routePoint(x, y, speed, action, alt)
  return {
    x = x,
    y = y,
    alt = alt or 0,
    alt_type = alt and "BARO" or nil,
    type = "Turning Point",
    action = action or "Off Road",
    speed = speed or 0,
    ETA = 0,
    ETA_locked = false,
    speed_locked = true,
    task = { id = "ComboTask", params = { tasks = {} } },
  }
end

function Spawner.buildGroupData(name, tpl, pos, headingRad, opts)
  opts = opts or {}
  local cat = tpl.category or "ground"
  local isAir = (cat == "air" or cat == "airplane" or cat == "helicopter")
  local cosH, sinH = math.cos(headingRad), math.sin(headingRad)
  local units = {}
  local alt = isAir and (opts.altM or tpl.altM or Spawner.defaults.airAltM) or nil
  for i, u in ipairs(tpl.units or {}) do
    local dx, dy = u.dx or 0, u.dy or 0
    local ux = pos.x + dx * cosH - dy * sinH
    local uy = pos.y + dx * sinH + dy * cosH
    units[i] = {
      type = u.type,
      name = name .. "-" .. i,
      x = ux,
      y = uy,
      heading = headingRad + math.rad(u.heading or 0),
      skill = adjustSkill(opts.skill or u.skill or tpl.skill or "Average"),
      playerCanDrive = false,
      alt = alt,
      alt_type = alt and "BARO" or nil,
      speed = isAir and (opts.speed or Spawner.defaults.airSpeed) or nil,
      payload = u.payload,
      livery_id = u.livery,
    }
  end
  local route
  if isAir then
    local sp = opts.speed or Spawner.defaults.airSpeed
    route = {
      points = {
        routePoint(pos.x, pos.y, sp, "Turning Point", alt),
        routePoint(pos.x + 1000 * cosH, pos.y + 1000 * sinH, sp, "Turning Point", alt),
      },
    }
  else
    -- 2-point hold route at the spawn position (single-point routes misbehave)
    route = { points = { routePoint(pos.x, pos.y, 0), routePoint(pos.x + 1, pos.y + 1, 0) } }
  end
  local data = {
    name = name,
    task = tpl.task or (isAir and "CAP" or "Ground Nothing"),
    x = pos.x,
    y = pos.y,
    units = units,
    route = route,
    visible = false,
    lateActivation = opts.lateActivation or nil,
    uncontrollable = false,
  }
  if opts.hidden then
    data.hidden = true
    data.hiddenOnMFD = true
    data.hiddenOnPlanner = true
  end
  return data
end

-- ---------------------------------------------------------------- spawn

local function resolveWhere(where, opts)
  -- Returns zone table (for random sampling) or nil plus a fixed point
  if type(where) == "string" then
    local z = Spawner.getZone(where)
    return z, nil
  end
  if type(where) == "table" then
    if where.zone then
      return Spawner.getZone(where.zone), nil
    end
    if where.kind then
      return where, nil
    end
    local p = Spawner.toVec2(where.point or where)
    local r = where.radiusM or opts.radiusM
    if r and r > 0 then
      return { kind = "circle", x = p.x, y = p.y, radius = r }, nil
    end
    return nil, p
  end
  return nil, nil
end

-- DMS.Spawner.spawn(templateId, zoneId|point, opts) -> groupName|nil, reason
-- opts: coalition/country override, heading (deg), hidden (bool override), encounter, minPlayerDistM,
--       outOfLOS, buildingRadius, tries, prefix, skill, lateActivation, ignoreBudget, onReady(groupName),
--       radiusM (scatter around a point), cost
function Spawner.spawn(templateId, where, opts)
  opts = opts or {}
  local templates = cfg().templates or {}
  local tpl = type(templateId) == "table" and templateId or templates[templateId]
  if not tpl then
    DMS.Log.warn(P, "Unknown template '%s'", tostring(templateId))
    return nil, "unknown template"
  end
  local cat = tpl.category or "ground"
  local gcatFn = CATEGORY[cat]
  if not gcatFn then
    DMS.Log.warn(P, "Unsupported category '%s' for template '%s'", tostring(cat), tostring(templateId))
    return nil, "bad category"
  end
  local cid = resolveCountry(opts.country or tpl.country)
  if not cid then
    DMS.Log.warn(
      P,
      "Unknown country '%s' for template '%s'",
      tostring(opts.country or tpl.country),
      tostring(templateId)
    )
    return nil, "bad country"
  end
  local coal = 0
  pcall(function()
    coal = coalition.getCountryCoalition(cid)
  end)
  local nUnits = #(tpl.units or {})
  if nUnits == 0 then
    return nil, "empty template"
  end

  local rcat = registryCategory(cat)
  if
    not opts.ignoreBudget
    and DMS.Registry.budgetAvailable
    and not DMS.Registry.budgetAvailable(rcat, coal, nUnits)
  then
    DMS.Log.debug(P, "Skipped '%s': %s budget exhausted (coalition %d)", tostring(templateId), rcat, coal)
    return nil, "budget"
  end

  local zone, fixed = resolveWhere(where, opts)
  if not zone and not fixed then
    DMS.Log.warn(P, "No valid zone/point for template '%s' (%s)", tostring(templateId), tostring(where))
    return nil, "bad zone"
  end

  local checkOpts = {
    category = cat,
    buildingRadius = opts.buildingRadius,
    outOfLOS = opts.outOfLOS,
    losHeightM = opts.losHeightM,
    minPlayerDistM = opts.minPlayerDistM,
  }
  if checkOpts.minPlayerDistM == nil then
    checkOpts.minPlayerDistM = (rcat == "air") and Spawner.defaults.minPlayerDistAir
      or Spawner.defaults.minPlayerDistGround
  end
  -- never check distance from own-side players
  local players = {}
  for _, pl in ipairs(Spawner.playerUnits()) do
    if pl.coalition ~= coal then
      players[#players + 1] = pl
    end
  end

  local heading = opts.heading and math.rad(opts.heading) or DMS.Rng.random() * 2 * math.pi
  local cosH, sinH = math.cos(heading), math.sin(heading)
  local pos, lastReason
  local tries = fixed and 1 or (opts.tries or Spawner.defaults.tries)
  for _ = 1, tries do
    local cand = fixed or Spawner.randomPointInZone(zone)
    local ok, reason = Spawner.validPoint(cand, checkOpts, players)
    if ok and rcat ~= "air" then
      -- every unit position must be valid too
      for _, u in ipairs(tpl.units) do
        local dx, dy = u.dx or 0, u.dy or 0
        local up = { x = cand.x + dx * cosH - dy * sinH, y = cand.y + dx * sinH + dy * cosH }
        local uok, ur = Spawner.validPoint(up, { category = cat }, nil)
        if not uok then
          ok, reason = false, "unit " .. ur
          break
        end
      end
    end
    if ok then
      pos = cand
      break
    end
    lastReason = reason
  end
  if not pos then
    DMS.Log.info(
      P,
      "No valid spawn point for '%s' after %d tries (last: %s)",
      tostring(templateId),
      tries,
      tostring(lastReason)
    )
    return nil, "no point"
  end

  local hidden = opts.hidden
  if hidden == nil then
    local intel = cfg().intel
    local playersCoal = cfg().players and cfg().players.coalition or 2
    -- fog of war is on unless DMS_CONFIG.intel.fogOfWar == false (same default as Intel/Test/dms check)
    hidden = (not (intel and intel.fogOfWar == false) and coal ~= playersCoal) and true or false
  end

  local name = DMS.Registry.allocName(opts.prefix or (type(templateId) == "string" and templateId or "grp"))
  local data = Spawner.buildGroupData(name, tpl, pos, heading, {
    hidden = hidden,
    skill = opts.skill,
    lateActivation = opts.lateActivation,
    altM = opts.altM,
    speed = opts.speed,
  })

  local ok, grp = pcall(coalition.addGroup, cid, gcatFn(), data)
  if not ok or not grp then
    DMS.Log.error(P, "coalition.addGroup failed for '%s': %s", name, tostring(grp))
    return nil, "addGroup failed"
  end

  DMS.Registry.track(name, {
    category = rcat,
    coalition = coal,
    encounter = opts.encounter,
    units = nUnits,
    template = type(templateId) == "string" and templateId or nil,
  })
  DMS.Log.debug(
    P,
    "Spawned '%s' from '%s' at (%.0f, %.0f) hidden=%s",
    name,
    tostring(templateId),
    pos.x,
    pos.y,
    tostring(hidden)
  )
  DMS.Bus.emit("spawner.spawned", {
    group = name,
    template = type(templateId) == "string" and templateId or nil,
    coalition = coal,
    category = rcat,
    units = nUnits,
    encounter = opts.encounter,
    pos = { x = pos.x, y = Spawner.groundHeight(pos), z = pos.y },
    cost = opts.cost or 1,
  })

  if opts.onReady then
    DMS.Clock.after(opts.readyDelaySec or Spawner.defaults.readyDelaySec, function()
      if DMS.Registry.isAlive(name) then
        opts.onReady(name)
      end
    end)
  end
  return name
end

local function poolOf(poolId)
  local pools = cfg().pools or {}
  return type(poolId) == "table" and poolId or pools[poolId]
end

-- poolCount(poolId) -> n: one roll of how many groups a launch of this pool spawns
-- (Rng.range(pool.pick), rounded, then Director.scaleCount). Callers that gate on the director roll
-- this first, check cost * n, then pass opts.count = n so the check and the spawn agree.
function Spawner.poolCount(poolId)
  local pool = poolOf(poolId)
  if not pool then
    return 0
  end
  local count = math.max(0, math.floor(DMS.Rng.range(pool.pick or 1) + 0.5))
  if DMS.Director and DMS.Director.scaleCount then
    count = DMS.Director.scaleCount(count)
  end
  return count
end

-- spawnPool(poolId, opts) -> {groupName...}
-- opts: zone (override pool zones), count (override pick, not scaled), plus spawn opts.
-- opts.cost is per group: each spawned group emits spawner.spawned{cost}.
function Spawner.spawnPool(poolId, opts)
  opts = opts or {}
  local pool = poolOf(poolId)
  if not pool or not pool.members or #pool.members == 0 then
    DMS.Log.warn(P, "Unknown or empty pool '%s'", tostring(poolId))
    return {}
  end
  local count
  if opts.count then
    count = math.max(0, math.floor(opts.count + 0.5))
  else
    count = Spawner.poolCount(pool)
  end
  local zones = pool.zones or {}
  local out = {}
  for i = 1, count do
    local member = DMS.Rng.weighted(pool.members)
    local where = opts.zone or opts.point
    if not where then
      if #zones == 0 then
        DMS.Log.warn(P, "Pool '%s' has no zones", tostring(poolId))
        break
      end
      where = zones[DMS.Rng.int(1, #zones)]
    end
    local sopts = {}
    for k, v in pairs(opts) do
      sopts[k] = v
    end
    sopts.zone, sopts.point, sopts.count = nil, nil, nil
    if sopts.prefix == nil and type(poolId) == "string" then
      sopts.prefix = poolId
    end
    local name = Spawner.spawn(member.tpl, where, sopts)
    if name then
      out[#out + 1] = name
    end
  end
  DMS.Log.debug(P, "Pool '%s': spawned %d/%d groups", tostring(poolId), #out, count)
  return out
end

function Spawner.start()
  DMS.Log.debug(
    P,
    "Started (%d templates)",
    (function()
      local n = 0
      for _ in pairs(cfg().templates or {}) do
        n = n + 1
      end
      return n
    end)()
  )
end
