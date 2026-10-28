-- director.lua: L4D-style AI director.
-- Per player-flight intensity (hits, near shots, nearby kills, SAM launches) decays every second.
-- States cycle BUILD_UP -> PEAK -> RELAX. canSpawn() combines a spawns-per-minute budget with
-- state gating. A hidden difficulty level adapts to player performance, clamped to config.
DMS = DMS or {}
DMS.Director = DMS.Director or {}

local Director = DMS.Director
local P = "Director"

Director.BUILD_UP, Director.PEAK, Director.RELAX = "BUILD_UP", "PEAK", "RELAX"

Director.defaults = {
  enabled = true,
  peak = 70,
  relaxSec = { 40, 90 },
  peakHoldSec = 15,
  decayPerSec = 1.5,
  maxIntensity = 100,
  nearM = 10000, -- "near a player" for shots/kills
  spawnsPerMin = 3,
  adapt = { min = -1, max = 1 },
  gain = { hit = 25, nearShot = 5, samLaunch = 15, nearKill = 8, playerDead = 40 },
  adaptStep = { playerDead = -0.5, playerHit = -0.05, enemyKill = 0.04, calmBonus = 0.25 },
  calmSec = 300, -- seconds without player damage that earns calmBonus
}

local SKILLS = { "Average", "Good", "High", "Excellent" }

local function settings()
  local c = (DMS_CONFIG and DMS_CONFIG.director) or {}
  local d = Director.defaults
  local s = {}
  for k, v in pairs(d) do
    s[k] = v
  end
  for k, v in pairs(c) do
    s[k] = v
  end
  local b = DMS_CONFIG and DMS_CONFIG.budgets
  s.spawnsPerMin = (b and b.spawnsPerMin) or s.spawnsPerMin
  s.adapt = c.adapt or d.adapt
  s.gain = d.gain
  if c.gain then
    s.gain = {}
    for k, v in pairs(d.gain) do
      s.gain[k] = c.gain[k] or v
    end
  end
  return s
end

local function playersCoalition()
  return (DMS_CONFIG and DMS_CONFIG.players and DMS_CONFIG.players.coalition) or 2
end

function Director.reset()
  if Director._tick then
    DMS.Clock.cancel(Director._tick)
  end
  for _, t in ipairs(Director._tokens or {}) do
    DMS.Bus.off(t)
  end
  Director._tick = nil
  Director._tokens = {}
  Director._flights = {} -- flight(group) -> state record
  Director._unitFlight = {} -- player unit name -> flight group
  Director._spawns = {} -- timestamps (with cost) of recent spawns
  Director._level = 0
  Director._lastDamage = nil
  Director._started = false
  Director._cfg = settings()
end
if not Director._flights then
  Director.reset()
end

-- ---------------------------------------------------------------- flights

local function newFlight(name)
  return { name = name, intensity = 0, state = Director.BUILD_UP, since = DMS.Clock.now(), relaxFor = 0 }
end

local function flight(name)
  if not name then
    return nil
  end
  local f = Director._flights[name]
  if not f then
    f = newFlight(name)
    Director._flights[name] = f
  end
  return f
end

function Director.addPlayer(unitName, groupName)
  groupName = groupName or unitName
  Director._unitFlight[unitName] = groupName
  flight(groupName)
end

function Director.removePlayer(unitName)
  local g = Director._unitFlight[unitName]
  Director._unitFlight[unitName] = nil
  if g then
    for _, gg in pairs(Director._unitFlight) do
      if gg == g then
        return
      end
    end
    Director._flights[g] = nil
  end
end

local function setState(f, st)
  if f.state == st then
    return
  end
  f.state = st
  f.since = DMS.Clock.now()
  if st == Director.RELAX then
    f.relaxFor = DMS.Rng.range(Director._cfg.relaxSec)
  end
  DMS.Log.debug(P, "Flight '%s' state -> %s (intensity %.0f)", f.name, st, f.intensity)
  DMS.Bus.emit("director.state", { flight = f.name, state = st, intensity = f.intensity })
end

function Director.addIntensity(flightName, amount, why)
  local f = flight(flightName)
  if not f then
    return
  end
  local c = Director._cfg
  f.intensity = math.max(0, math.min(c.maxIntensity, f.intensity + amount))
  DMS.Log.debug(P, "Flight '%s' +%.0f intensity (%s) = %.0f", f.name, amount, tostring(why), f.intensity)
  if f.state == Director.BUILD_UP and f.intensity >= c.peak then
    setState(f, Director.PEAK)
  end
end

local function unitPos(unitName)
  local ok, p = pcall(function()
    local u = Unit.getByName(unitName)
    return u and u:isExist() and u:getPoint() or nil
  end)
  return ok and p or nil
end

-- flights with a unit within radius of pos (vec3)
local function flightsNear(pos, radius)
  local out = {}
  if not pos then
    return out
  end
  for unitName, g in pairs(Director._unitFlight) do
    local p = unitPos(unitName)
    if p then
      local dx, dz = p.x - pos.x, p.z - pos.z
      if dx * dx + dz * dz <= radius * radius then
        out[g] = true
      end
    end
  end
  return out
end

-- ---------------------------------------------------------------- adapt

local function clampLevel(x)
  local a = Director._cfg.adapt or { min = -1, max = 1 }
  return math.max(a.min or -1, math.min(a.max or 1, x))
end

function Director.adapt(delta, why)
  local before = Director._level
  Director._level = clampLevel(Director._level + (delta or 0))
  if Director._level ~= before then
    DMS.Log.debug(P, "Difficulty %.2f -> %.2f (%s)", before, Director._level, tostring(why))
  end
  return Director._level
end

function Director.level()
  return Director._level
end

local function tier()
  local l = Director._level
  if l >= 0 then
    return math.floor(l + 0.5)
  end
  return -math.floor(-l + 0.5)
end

-- Skill of NEW spawns, shifted by the rounded difficulty level.
function Director.skillFor(skill)
  if skill == "Random" or skill == "Player" or skill == "Client" then
    return skill
  end
  local idx
  for i, s in ipairs(SKILLS) do
    if s == skill then
      idx = i
    end
  end
  if not idx then
    return skill
  end
  idx = math.max(1, math.min(#SKILLS, idx + tier()))
  return SKILLS[idx]
end

-- Pool size scaling: +/-25% per level (at least 1 if base >= 1).
function Director.scaleCount(n)
  if not n or n <= 0 then
    return n
  end
  local scaled = math.floor(n * (1 + 0.25 * Director._level) + 0.5)
  return math.max(1, scaled)
end

-- Reaction delay scaling (e.g. SAM go-hot delay): harder => faster.
function Director.scaleDelay(sec)
  return math.max(0, sec * (1 - 0.25 * Director._level))
end

-- ---------------------------------------------------------------- queries

function Director.state(flightName)
  if flightName then
    local f = Director._flights[flightName]
    return f and f.state or Director.BUILD_UP
  end
  -- aggregate: state of the most intense flight
  local best
  for _, f in pairs(Director._flights) do
    if not best or f.intensity > best.intensity then
      best = f
    end
  end
  return best and best.state or Director.BUILD_UP
end

function Director.intensity(flightName)
  if flightName then
    local f = Director._flights[flightName]
    return f and f.intensity or 0
  end
  local m = 0
  for _, f in pairs(Director._flights) do
    m = math.max(m, f.intensity)
  end
  return m
end

function Director.flights()
  local out = {}
  for name in pairs(Director._flights) do
    out[#out + 1] = name
  end
  table.sort(out)
  return out
end

local function spawnsInLastMinute()
  local now, total, keep = DMS.Clock.now(), 0, {}
  for _, s in ipairs(Director._spawns) do
    if now - s.t < 60 then
      keep[#keep + 1] = s
      total = total + s.cost
    end
  end
  Director._spawns = keep
  return total
end

function Director.spawnBudget()
  local base = Director._cfg.spawnsPerMin or 3
  return math.max(1, base * (1 + 0.25 * Director._level))
end

-- canSpawn(cost, flight?) -> bool, reason
function Director.canSpawn(cost, flightName)
  cost = cost or 1
  local c = Director._cfg
  if spawnsInLastMinute() + cost > Director.spawnBudget() then
    return false, "budget"
  end
  if c.enabled == false then
    return true
  end
  local st = Director.state(flightName)
  if st == Director.PEAK or st == Director.RELAX then
    return false, st
  end
  return true
end

function Director.noteSpawn(cost)
  Director._spawns[#Director._spawns + 1] = { t = DMS.Clock.now(), cost = cost or 1 }
end

-- ---------------------------------------------------------------- loop

function Director.tick(dt)
  dt = dt or 1
  local c = Director._cfg
  local now = DMS.Clock.now()
  for _, f in pairs(Director._flights) do
    f.intensity = math.max(0, f.intensity - c.decayPerSec * dt)
    if f.state == Director.BUILD_UP then
      if f.intensity >= c.peak then
        setState(f, Director.PEAK)
      end
    elseif f.state == Director.PEAK then
      if now - f.since >= (c.peakHoldSec or 15) then
        setState(f, Director.RELAX)
      end
    elseif f.state == Director.RELAX then
      if now - f.since >= f.relaxFor and f.intensity < c.peak * 0.5 then
        setState(f, Director.BUILD_UP)
      end
    end
  end
  -- calm bonus: long stretch without player damage nudges difficulty up
  if next(Director._flights) then
    local last = Director._lastDamage or Director._startT or now
    if now - last >= (c.calmSec or 300) then
      Director._lastDamage = now
      Director.adapt(Director.defaults.adaptStep.calmBonus, "calm")
    end
  end
end

local function on(name, fn)
  Director._tokens[#Director._tokens + 1] = DMS.Bus.on(name, function(ev)
    if ev then
      fn(ev)
    end
  end)
end

function Director.start()
  if Director._started then
    return
  end
  Director.reset()
  Director._started = true
  Director._startT = DMS.Clock.now()
  local c = Director._cfg
  local pc = playersCoalition()
  local step = Director.defaults.adaptStep

  on("player.spawned", function(ev)
    Director.addPlayer(ev.unit, ev.group)
  end)
  on("player.left", function(ev)
    Director.removePlayer(ev.unit)
  end)
  on("spawner.spawned", function(ev)
    Director.noteSpawn(ev.cost)
  end)

  on("unit.hit", function(ev)
    local g = Director._unitFlight[ev.target]
    if g then
      Director.addIntensity(g, c.gain.hit, "hit")
      Director._lastDamage = DMS.Clock.now()
      Director.adapt(step.playerHit, "player hit")
    end
  end)

  local function ambient(group)
    return DMS.Ambient and DMS.Ambient.isAmbient and DMS.Ambient.isAmbient(group)
  end

  on("unit.shot", function(ev)
    if ev.coalition == pc or not ev.initiator or ambient(ev.initiatorGroup) then
      return
    end
    local pos = unitPos(ev.initiator)
    local isSam = false
    pcall(function()
      local u = Unit.getByName(ev.initiator)
      local g = u and u:getGroup()
      isSam = g and g:getCategory() == Group.Category.GROUND and true or false
    end)
    local radius = isSam and c.nearM * 4 or c.nearM
    for g in pairs(flightsNear(pos, radius)) do
      Director.addIntensity(g, isSam and c.gain.samLaunch or c.gain.nearShot, isSam and "SAM launch" or "near shot")
    end
  end)

  on("unit.dead", function(ev)
    if ambient(ev.group) then
      return -- friendly base traffic (DMS.Ambient) never moves pacing
    end
    local g = Director._unitFlight[ev.unit]
    if g then
      Director.addIntensity(g, c.gain.playerDead, "player dead")
      Director.adapt(step.playerDead, "player dead")
      Director._lastDamage = DMS.Clock.now()
      Director.removePlayer(ev.unit)
      return
    end
    for fg in pairs(flightsNear(ev.pos, c.nearM)) do
      Director.addIntensity(fg, c.gain.nearKill, "nearby kill")
    end
    if ev.coalition and ev.coalition ~= pc and ev.coalition ~= 0 then
      Director.adapt(step.enemyKill, "enemy kill")
    end
  end)

  Director._tick = DMS.Clock.every(1, function()
    Director.tick(1)
  end)
  DMS.Log.info(
    P,
    "Started (enabled=%s peak=%s spawnsPerMin=%s)",
    tostring(c.enabled ~= false),
    tostring(c.peak),
    tostring(c.spawnsPerMin)
  )
end
