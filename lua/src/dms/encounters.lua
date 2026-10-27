-- encounters.lua: runs DMS_CONFIG.encounters.
-- Kinds: pool, ambush_sam, waves, hunt, convoy. Triggers: time, proximity, beat, event, director,
-- manual. chance / once per encounter. Emits encounter.spawned / encounter.cleared.
DMS = DMS or {}
DMS.Encounters = DMS.Encounters or {}

local Enc = DMS.Encounters
local P = "Encounters"

Enc.defaults = {
  proximityCheckSec = 5,
  samCheckSec = 2,
  samEngageRadiusM = 15000,
  telegraphSec = { 30, 60 },
  samReactSec = { 2, 8 },
  gateRetrySec = 15,
  maxDeferSec = 300,
  clearCheckSec = 10,
  convoyResumeSec = { 60, 120 },
  huntIntervalSec = 30,
  huntSpeed = 8,
}

local function cfg() return DMS_CONFIG or {} end
local function playersCoalition() return (cfg().players and cfg().players.coalition) or 2 end

function Enc.reset()
  for _, st in pairs(Enc._state or {}) do
    for _, t in ipairs(st.tokens) do DMS.Bus.off(t) end
    for _, id in ipairs(st.timers) do DMS.Clock.cancel(id) end
    for _, h in ipairs(st.handles) do pcall(h.stop) end
  end
  if Enc._clearTimer then DMS.Clock.cancel(Enc._clearTimer) end
  if Enc._deadToken then DMS.Bus.off(Enc._deadToken) end
  Enc._state = {}
  Enc._order = {}
  Enc._clearTimer = nil
  Enc._deadToken = nil
  Enc._started = false
end

-- ---------------------------------------------------------------- helpers

local function d2(a, b)
  local dx, dy = a.x - b.x, a.y - b.y
  return math.sqrt(dx * dx + dy * dy)
end

local function v2(p)
  if p.z ~= nil then return { x = p.x, y = p.z } end
  return { x = p.x, y = p.y }
end

local function addTimer(st, id) if id then st.timers[#st.timers + 1] = id end return id end
local function addToken(st, t) if t then st.tokens[#st.tokens + 1] = t end return t end

-- Units of coalition `coal` as list of {name, group, pos(vec3)}. Players only for the player side
-- (cheap); all units otherwise.
local function unitsOf(coal)
  local out = {}
  if coal == playersCoalition() then
    for _, pl in ipairs(DMS.Spawner.playerUnits()) do
      if pl.coalition == coal then
        local gname
        pcall(function() gname = pl.unit:getGroup():getName() end)
        local uname
        pcall(function() uname = pl.unit:getName() end)
        out[#out + 1] = { name = uname, group = gname, pos = pl.pos }
      end
    end
    return out
  end
  pcall(function()
    for _, g in ipairs(coalition.getGroups(coal) or {}) do
      for _, u in ipairs(g:getUnits() or {}) do
        if u:isExist() then out[#out + 1] = { name = u:getName(), group = g:getName(), pos = u:getPoint() } end
      end
    end
  end)
  return out
end

-- Nearest enemy player group to the given group (for hunters).
function Enc.nearestPlayerGroup(groupName, maxM)
  local hp = DMS.Ground.leadPos(groupName)
  if not hp then return nil end
  local myCoal = DMS.Registry.get(groupName) and DMS.Registry.get(groupName).coalition
  local best, bestD
  for _, pl in ipairs(DMS.Spawner.playerUnits()) do
    if pl.coalition ~= myCoal then
      local d = d2(v2(hp), v2(pl.pos))
      if (not maxM or d <= maxM) and (not bestD or d < bestD) then
        local gname
        pcall(function() gname = pl.unit:getGroup():getName() end)
        if gname then best, bestD = gname, d end
      end
    end
  end
  return best, bestD
end

local function aliveGroups(st)
  local n = 0
  for _, g in ipairs(st.groups) do
    if DMS.Registry.isAlive(g) then n = n + 1 end
  end
  return n
end

local function checkCleared(st)
  if st.cleared or not st.spawnedAny or st.pending > 0 then return end
  if aliveGroups(st) == 0 then
    st.cleared = true
    DMS.Log.info(P, "Encounter '%s' cleared", st.def.id)
    DMS.Bus.emit("encounter.cleared", { id = st.def.id })
  end
end

-- ---------------------------------------------------------------- spawning

local function spawnFor(st, opts)
  local def = st.def
  opts = opts or {}
  opts.encounter = def.id
  local groups
  if def.pool then
    groups = DMS.Spawner.spawnPool(def.pool, opts)
  elseif def.template then
    local g = DMS.Spawner.spawn(def.template, opts.zone or opts.point or def.zone, opts)
    groups = g and { g } or {}
  else
    groups = {}
  end
  for _, g in ipairs(groups) do st.groups[#st.groups + 1] = g end
  if #groups > 0 then
    st.spawnedAny = true
    st.cleared = false
    DMS.Log.info(P, "Encounter '%s' spawned %d group(s)", def.id, #groups)
    DMS.Bus.emit("encounter.spawned", { id = def.id, groups = groups, kind = def.kind })
  end
  return groups
end

local function zoneOpt(def)
  if def.spawnZone then return def.spawnZone end
  return nil -- pool zones
end

local function startHunts(st, groups)
  local def = st.def
  for _, g in ipairs(groups) do
    local target
    if type(def.hunt) == "string" then
      target = def.hunt
    elseif def.target then
      target = def.target
    else
      target = function(name) return Enc.nearestPlayerGroup(name, def.huntRadiusM) end
    end
    DMS.Clock.after(1, function()
      if DMS.Registry.isAlive(g) then
        DMS.Ground.hunt(g, target, {
          intervalSec = def.huntIntervalSec or Enc.defaults.huntIntervalSec,
          speed = def.huntSpeed or Enc.defaults.huntSpeed,
          jitter = 3,
        })
      end
    end)
  end
end

-- Spawn now if the director allows, otherwise retry until allowed or maxDeferSec elapsed.
local function gatedSpawn(st, opts, after)
  local def = st.def
  local gated = def.gated ~= false and DMS.Director and DMS.Director.canSpawn
  local started = DMS.Clock.now()
  local maxDefer = def.maxDeferSec or Enc.defaults.maxDeferSec
  st.pending = st.pending + 1
  local function attempt()
    if st.stopped then st.pending = st.pending - 1 return end
    if gated then
      local ok, why = DMS.Director.canSpawn(def.cost or 1)
      if not ok and DMS.Clock.now() - started < maxDefer then
        DMS.Log.debug(P, "Encounter '%s' deferred by director (%s)", def.id, tostring(why))
        addTimer(st, DMS.Clock.after(def.gateRetrySec or Enc.defaults.gateRetrySec, attempt))
        return
      end
    end
    st.pending = st.pending - 1
    local groups = spawnFor(st, opts)
    if after then after(groups) end
  end
  attempt()
end

-- ---------------------------------------------------------------- kinds

local KIND = {}

KIND.pool = function(st)
  gatedSpawn(st, { zone = zoneOpt(st.def) }, function(groups)
    if st.def.hunt then startHunts(st, groups) end
  end)
end

KIND.hunt = function(st)
  gatedSpawn(st, { zone = zoneOpt(st.def) }, function(groups) startHunts(st, groups) end)
end

KIND.waves = function(st)
  local def = st.def
  local n = math.max(1, math.floor(DMS.Rng.range(def.waves or 1) + 0.5))
  local wave = 0
  st.pending = st.pending + n
  local function nextWave()
    if st.stopped then return end
    wave = wave + 1
    st.pending = st.pending - 1
    DMS.Log.info(P, "Encounter '%s' wave %d/%d", def.id, wave, n)
    gatedSpawn(st, { zone = zoneOpt(def) }, function(groups)
      if def.hunt then startHunts(st, groups) end
      DMS.Bus.emit("encounter.wave", { id = def.id, wave = wave, of = n, groups = groups })
      if wave < n then
        addTimer(st, DMS.Clock.after(DMS.Rng.range(def.gapSec or { 120, 240 }), nextWave))
      end
    end)
  end
  nextWave()
end

-- telegraph spec: "beat:<id>" -> emits beat.request {id}; "event:<name>" or "<name>" -> emits <name>
local function telegraph(st, groups)
  local def = st.def
  local t = def.telegraph
  if not t then return end
  DMS.Bus.emit("encounter.telegraph", { id = def.id, telegraph = t, groups = groups })
  local beat = string.match(t, "^beat:(.+)$")
  if beat then
    DMS.Bus.emit("beat.request", { id = beat, encounter = def.id })
  else
    local ev = string.match(t, "^event:(.+)$") or t
    DMS.Bus.emit(ev, { encounter = def.id, groups = groups })
  end
  DMS.Log.debug(P, "Encounter '%s' telegraph '%s'", def.id, t)
end

local function goDark(g)
  DMS.Ground.alarm(g, "GREEN")
  DMS.Ground.holdFire(g)
end

local function goHot(st, g)
  DMS.Ground.alarm(g, "RED")
  DMS.Ground.openFire(g)
  DMS.Log.info(P, "SAM '%s' (%s) going HOT", g, st.def.id)
  DMS.Bus.emit("encounter.sam_hot", { id = st.def.id, group = g })
end

KIND.ambush_sam = function(st)
  local def = st.def
  -- dark from the start; controller touched only after spawn delay (onReady)
  local groups = spawnFor(st, { zone = zoneOpt(def), onReady = goDark })
  if #groups == 0 then return end
  local radius = def.engageRadiusM or Enc.defaults.samEngageRadiusM
  local pc = playersCoalition()
  local sites = {}
  for _, g in ipairs(groups) do sites[g] = { state = "dark" } end
  local id
  id = addTimer(st, DMS.Clock.every(def.checkSec or Enc.defaults.samCheckSec, function()
    if st.stopped then return false end
    local remaining = 0
    for g, site in pairs(sites) do
      if site.state == "dark" then
        if not DMS.Registry.isAlive(g) then
          site.state = "dead"
        else
          remaining = remaining + 1
          local sp = DMS.Ground.leadPos(g)
          local inRange = false
          if sp then
            for _, u in ipairs(unitsOf(pc)) do
              if d2(v2(sp), v2(u.pos)) <= radius then inRange = true break end
            end
          end
          if inRange then
            site.state = "arming"
            local roll = def.hotChance
            if roll and not DMS.Rng.chance(roll) then
              site.state = "skipped"
              DMS.Log.debug(P, "SAM '%s' stays dark (hotChance %d failed)", g, roll)
            else
              local delay
              if def.telegraph then
                telegraph(st, { g })
                delay = DMS.Rng.range(def.telegraphSec or Enc.defaults.telegraphSec)
              else
                delay = DMS.Rng.range(def.reactSec or Enc.defaults.samReactSec)
              end
              if DMS.Director and DMS.Director.scaleDelay then delay = DMS.Director.scaleDelay(delay) end
              addTimer(st, DMS.Clock.after(delay, function()
                if DMS.Registry.isAlive(g) then
                  site.state = "hot"
                  goHot(st, g)
                end
              end))
            end
          end
        end
      end
    end
    if remaining == 0 then return false end
    return true
  end, { firstDelay = 1.5 }))
end

KIND.convoy = function(st)
  local def = st.def
  local convoy = def.group
  if not convoy then
    local groups = spawnFor(st, { zone = zoneOpt(def) })
    convoy = groups[1]
  elseif def.pool then
    -- escorts spawned near the convoy lead
    local lp = DMS.Ground.leadPos(convoy)
    if lp then
      spawnFor(st, { point = { x = lp.x, y = lp.z }, radiusM = def.escortRadiusM or 500, minPlayerDistM = 0 })
    end
  end
  if not convoy then
    DMS.Log.warn(P, "Convoy encounter '%s' has no convoy group", def.id)
    return
  end
  st.groups[#st.groups + 1] = convoy
  st.spawnedAny = true
  local h = DMS.Ground.haltOnHit(convoy, def.resumeAfterSec or Enc.defaults.convoyResumeSec)
  st.handles[#st.handles + 1] = h
  if def.destination then
    local z = DMS.Spawner.getZone(def.destination)
    local dest = z and DMS.Spawner.zoneCenter(z) or (type(def.destination) == "table" and def.destination)
    if dest then
      DMS.Clock.after(1, function()
        DMS.Ground.routeTo(convoy, dest, { speed = def.speed or 10, action = def.action or "On Road" })
        DMS.Ground.watch(convoy)
      end)
    end
  end
  DMS.Log.info(P, "Convoy encounter '%s' tracking '%s'", def.id, convoy)
end
KIND.cap = KIND.pool

Enc.KIND = KIND

-- ---------------------------------------------------------------- firing

local function fire(st, why, manual)
  local def = st.def
  if st.done and not manual then return false end
  if def.once ~= false then st.done = true end
  if not manual and def.chance and not DMS.Rng.chance(def.chance) then
    DMS.Log.info(P, "Encounter '%s' skipped (chance %d%% failed, %s)", def.id, def.chance, why)
    return false
  end
  local fn = KIND[def.kind or "pool"]
  if not fn then
    DMS.Log.warn(P, "Encounter '%s': unknown kind '%s'", def.id, tostring(def.kind))
    return false
  end
  st.fired = st.fired + 1
  DMS.Log.info(P, "Encounter '%s' (%s) triggered by %s", def.id, tostring(def.kind), why)
  local ok, err = DMS.safeCall(fn, st)
  if not ok then DMS.Log.error(P, "Encounter '%s' failed: %s", def.id, tostring(err)) end
  return ok
end

local function matches(payload, filt)
  for k, v in pairs(filt) do
    if k ~= "type" and k ~= "name" and k ~= "event" and payload[k] ~= v then return false end
  end
  return true
end

local function arm(st)
  local def = st.def
  local t = def.trigger or { type = "manual" }
  local ty = t.type or "manual"
  if ty == "time" then
    addTimer(st, DMS.Clock.after(DMS.Rng.range(t.afterSec or 0), function() fire(st, "time") end))
  elseif ty == "beat" then
    addToken(st, DMS.Bus.on("beat.fired", function(ev)
      if ev and ev.id == t.beat then fire(st, "beat " .. tostring(t.beat)) end
    end))
  elseif ty == "event" then
    local name = t.name or t.event
    addToken(st, DMS.Bus.on(name, function(ev)
      if matches(ev or {}, t) then fire(st, "event " .. tostring(name)) end
    end))
  elseif ty == "director" then
    addToken(st, DMS.Bus.on("director.state", function(ev)
      if ev and ev.state == t.state then fire(st, "director " .. tostring(t.state)) end
    end))
  elseif ty == "proximity" then
    local zone = t.zone and DMS.Spawner.getZone(t.zone)
    local center = (t.point and v2(t.point)) or (zone and DMS.Spawner.zoneCenter(zone))
    if not center then
      DMS.Log.warn(P, "Encounter '%s': proximity trigger without zone/point", def.id)
      return
    end
    local radius = t.radiusM
    local coal = t.coalition or playersCoalition()
    addTimer(st, DMS.Clock.every(t.checkSec or Enc.defaults.proximityCheckSec, function()
      if st.done or st.stopped then return false end
      local who
      for _, u in ipairs(unitsOf(coal)) do
        local inside
        if radius then
          inside = d2(center, v2(u.pos)) <= radius
        else
          inside = DMS.Spawner.inZone(zone, u.pos)
        end
        if inside then who = u break end
      end
      if who and not st.inside then
        -- fire on entry only (re-arms after everyone leaves when once=false)
        st.inside = true
        DMS.Bus.emit("zone.entered", { zone = t.zone, group = who.group, unit = who.name, encounter = def.id })
        fire(st, "proximity " .. tostring(who.name))
        if st.done then return false end
      elseif not who then
        st.inside = false
      end
      return true
    end, { jitter = 1 }))
  end
end

-- Manual trigger. Ignores chance; respects once unless force.
function Enc.trigger(id, force)
  local st = Enc._state[id]
  if not st then
    DMS.Log.warn(P, "trigger: unknown encounter '%s'", tostring(id))
    return false
  end
  if st.done and not force then return false end
  st.done = false
  return fire(st, "manual", true)
end

function Enc.get(id) return Enc._state[id] end

function Enc.groups(id)
  local st = Enc._state[id]
  return st and st.groups or {}
end

function Enc.add(def)
  if not def or not def.id then return nil end
  local st = { def = def, groups = {}, tokens = {}, timers = {}, handles = {}, fired = 0, pending = 0,
    done = false, cleared = false, spawnedAny = false }
  Enc._state[def.id] = st
  Enc._order[#Enc._order + 1] = def.id
  arm(st)
  return st
end

function Enc.start()
  Enc.reset()
  Enc._started = true
  local list = cfg().encounters or {}
  for _, def in ipairs(list) do
    local ok, err = DMS.safeCall(Enc.add, def)
    if not ok then DMS.Log.error(P, "Bad encounter '%s': %s", tostring(def and def.id), tostring(err)) end
  end
  Enc._deadToken = DMS.Bus.on("group.dead", function()
    for _, st in pairs(Enc._state) do checkCleared(st) end
  end)
  Enc._clearTimer = DMS.Clock.every(Enc.defaults.clearCheckSec, function()
    for _, st in pairs(Enc._state) do checkCleared(st) end
  end)
  DMS.Log.info(P, "Started (%d encounters)", #list)
end

if not Enc._state then Enc._state, Enc._order = {}, {} end
