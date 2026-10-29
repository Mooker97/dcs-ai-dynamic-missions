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
local SEVERITY = { BUILD_UP = 0, RELAX = 1, PEAK = 2 }

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
  Director._recentLeft = {} -- unit name -> {flight, t}: player.left without a death yet (LEFT_GRACE_SEC)
  Director._spawns = {} -- timestamps (with cost) of recent spawns
  Director._level = 0
  Director._lastDamage = nil
  Director._startT = nil
  Director._started = false
  Director._cfg = settings()
end
if not Director._flights then
  Director.reset()
end

-- ---------------------------------------------------------------- flights

-- units: live player units mapped to this flight. A flight with units == 0 is an orphan (its last
-- player died, or it was created by addIntensity): it keeps pacing (a death still earns a breather)
-- and tick() prunes it once it is back in BUILD_UP. player.left keeps it as an orphan for
-- LEFT_GRACE_SEC: a unit.dead / unit.ejected / unit.pilot_dead for that unit inside the window still
-- counts as a player death (DCS may send PLAYER_LEAVE_UNIT first when a player ejects or leaves the
-- slot while going down). Without a death the flight is deleted when the window ends.
Director.LEFT_GRACE_SEC = 10
local function newFlight(name)
  return { name = name, intensity = 0, state = Director.BUILD_UP, since = DMS.Clock.now(), relaxFor = 0, units = 0 }
end

local function sortedNames()
  local out = {}
  for name in pairs(Director._flights) do
    out[#out + 1] = name
  end
  table.sort(out)
  return out
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

-- removePlayer(unit, keepFlight?): drop the unit. When it was the flight's last unit the flight is
-- deleted, or kept as an orphan when keepFlight (player death, or player.left during its
-- LEFT_GRACE_SEC death window: pacing continues).
function Director.removePlayer(unitName, keepFlight)
  local g = unitName and Director._unitFlight[unitName]
  if not g then
    return
  end
  Director._unitFlight[unitName] = nil
  local f = Director._flights[g]
  if not f then
    return
  end
  f.units = math.max(0, (f.units or 1) - 1)
  if f.units == 0 then
    if keepFlight then
      DMS.Log.info(P, "Flight '%s' has no live players; kept until BUILD_UP (now %s)", g, f.state)
    else
      Director._flights[g] = nil
      DMS.Log.info(P, "Flight '%s' removed (last player left during %s)", g, f.state)
    end
  end
end

function Director.addPlayer(unitName, groupName)
  if not unitName then
    return
  end
  groupName = groupName or unitName
  local old = Director._unitFlight[unitName]
  if old == groupName and Director._flights[groupName] then
    return -- duplicate BIRTH
  end
  if old then
    Director.removePlayer(unitName)
  end
  local isNew = Director._flights[groupName] == nil
  local f = flight(groupName)
  Director._unitFlight[unitName] = groupName
  f.units = (f.units or 0) + 1
  f.leaving = nil
  Director._recentLeft[unitName] = nil
  DMS.Log.info(
    P,
    "Player unit '%s' joined flight '%s' (%s, %d unit(s))",
    unitName,
    groupName,
    isNew and "new" or f.state,
    f.units
  )
end

local function setState(f, st)
  if f.state == st then
    return
  end
  local from = f.state
  f.state = st
  f.since = DMS.Clock.now()
  if st == Director.RELAX then
    f.relaxFor = DMS.Rng.range(Director._cfg.relaxSec)
  end
  DMS.Log.info(P, "Flight '%s' %s -> %s (intensity %.0f)", f.name, from, st, f.intensity)
  DMS.Bus.emit("director.state", { flight = f.name, state = st, intensity = f.intensity })
end

function Director.addIntensity(flightName, amount, why)
  local f = flight(flightName)
  if not f then
    return
  end
  local c = Director._cfg
  f.intensity = math.max(0, math.min(c.maxIntensity, f.intensity + (tonumber(amount) or 0)))
  DMS.Log.debug(P, "Flight '%s' +%.0f intensity (%s) = %.0f", f.name, tonumber(amount) or 0, tostring(why), f.intensity)
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

-- Clamp from config adapt {min, max} (default -1/+1 tier). min is never above 0, max never below 0.
local function clampLevel(x)
  local a = Director._cfg.adapt or {}
  local lo, hi = tonumber(a.min) or -1, tonumber(a.max) or 1
  if lo > 0 then
    lo = 0
  end
  if hi < 0 then
    hi = 0
  end
  return math.max(lo, math.min(hi, x))
end

local function tierOf(l)
  if l >= 0 then
    return math.floor(l + 0.5)
  end
  return -math.floor(-l + 0.5)
end

function Director.adapt(delta, why)
  local before = Director._level
  Director._level = clampLevel(Director._level + (tonumber(delta) or 0))
  if Director._level ~= before then
    DMS.Log.debug(P, "Difficulty %.2f -> %.2f (%s)", before, Director._level, tostring(why))
    if tierOf(before) ~= tierOf(Director._level) then
      DMS.Log.info(P, "Difficulty tier %d -> %d (%s)", tierOf(before), tierOf(Director._level), tostring(why))
    end
  end
  return Director._level
end

function Director.level()
  return Director._level
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
  idx = math.max(1, math.min(#SKILLS, idx + tierOf(Director._level)))
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
  if not sec then
    return sec
  end
  return math.max(0, sec * (1 - 0.25 * Director._level))
end

-- ---------------------------------------------------------------- queries

function Director.state(flightName)
  if flightName then
    local f = Director._flights[flightName]
    return f and f.state or Director.BUILD_UP
  end
  -- aggregate: state of the most intense flight; ties go to the more restrictive state
  -- (PEAK > RELAX > BUILD_UP), then name order, so the answer never depends on pairs() order.
  local best
  for _, name in ipairs(sortedNames()) do
    local f = Director._flights[name]
    if
      not best
      or f.intensity > best.intensity
      or (f.intensity == best.intensity and SEVERITY[f.state] > SEVERITY[best.state])
    then
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
  return sortedNames()
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
-- The budget is a rolling 60 s window of noted spawn costs. With an empty window one spawn is always
-- allowed, so an encounter whose cost exceeds the whole budget is throttled, never starved.
function Director.canSpawn(cost, flightName)
  cost = tonumber(cost) or 1
  local c = Director._cfg
  local used = spawnsInLastMinute()
  if used > 0 and used + cost > Director.spawnBudget() then
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
  Director._spawns[#Director._spawns + 1] = { t = DMS.Clock.now(), cost = tonumber(cost) or 1 }
end

-- ---------------------------------------------------------------- loop

function Director.tick(dt)
  dt = dt or 1
  local c = Director._cfg
  local now = DMS.Clock.now()
  local expired = {}
  for unitName, r in pairs(Director._recentLeft) do
    if now - r.t >= Director.LEFT_GRACE_SEC then
      expired[#expired + 1] = unitName
    end
  end
  table.sort(expired)
  for _, unitName in ipairs(expired) do
    local r = Director._recentLeft[unitName]
    Director._recentLeft[unitName] = nil
    local f = Director._flights[r.flight]
    if f and (f.units or 0) == 0 and not f.died then
      Director._flights[r.flight] = nil
      DMS.Log.info(P, "Flight '%s' removed (last player left during %s, no death)", r.flight, f.state)
    end
  end
  for _, name in ipairs(sortedNames()) do
    local f = Director._flights[name]
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
    if (f.units or 0) == 0 and f.state == Director.BUILD_UP and not f.leaving then
      Director._flights[name] = nil
      DMS.Log.info(P, "Flight '%s' pruned (no live players, back in BUILD_UP)", name)
    end
  end
  -- calm bonus: a long stretch with players aboard and no player damage nudges difficulty up.
  -- The calm clock only runs while a player unit is live (nothing is banked while nobody flies).
  if next(Director._unitFlight) then
    local last = Director._lastDamage or Director._startT or now
    if now - last >= (c.calmSec or 300) then
      Director._lastDamage = now
      Director.adapt(Director.defaults.adaptStep.calmBonus, "calm")
    end
  else
    Director._lastDamage = now
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

  on("spawner.spawned", function(ev)
    Director.noteSpawn(ev.cost)
  end)
  if c.enabled == false then
    -- passthrough: only the spawn budget applies; no flights, no pacing, no difficulty adaptation
    DMS.Log.info(P, "Started disabled (spawn budget only, spawnsPerMin=%s)", tostring(c.spawnsPerMin))
    return
  end

  on("player.spawned", function(ev)
    Director.addPlayer(ev.unit, ev.group)
  end)
  on("player.left", function(ev)
    local g = ev.unit and Director._unitFlight[ev.unit]
    if not g then
      return -- already unmapped (unit.dead ran first) or unknown
    end
    Director.removePlayer(ev.unit, true)
    local f = Director._flights[g]
    if f and (f.units or 0) == 0 then
      f.leaving = true
      f.died = nil
    end
    Director._recentLeft[ev.unit] = { flight = g, t = DMS.Clock.now() }
    DMS.Log.debug(
      P,
      "Player unit '%s' left flight '%s'; watching %ss for its death",
      ev.unit,
      g,
      Director.LEFT_GRACE_SEC
    )
  end)

  -- a player death: the unit is still mapped, or it left (player.left) within LEFT_GRACE_SEC.
  local function playerDeath(unitName, why)
    local g = unitName and Director._unitFlight[unitName]
    local r = unitName and Director._recentLeft[unitName]
    if not g and r and DMS.Clock.now() - r.t < Director.LEFT_GRACE_SEC then
      g = r.flight
    end
    if not g then
      return false
    end
    Director._recentLeft[unitName] = nil
    Director.addIntensity(g, c.gain.playerDead, "player dead")
    Director.adapt(step.playerDead, "player dead")
    Director._lastDamage = DMS.Clock.now()
    -- keep the flight: a death earns a breather, and a respawn into the same group resumes it.
    -- The bus emits player.left right after unit.dead; the unit is already unmapped, so that is a no-op.
    Director.removePlayer(unitName, true)
    local f = Director._flights[g]
    if f then
      f.leaving = nil
      f.died = true
    end
    DMS.Log.info(P, "Player death in flight '%s' (%s, unit %s)", g, why, unitName)
    return true
  end

  on("unit.ejected", function(ev)
    playerDeath(ev.unit, "ejected")
  end)
  on("unit.pilot_dead", function(ev)
    playerDeath(ev.unit, "pilot dead")
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
    if playerDeath(ev.unit, "unit dead") then
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
    "Started (peak=%s spawnsPerMin=%s adapt=[%s, %s])",
    tostring(c.peak),
    tostring(c.spawnsPerMin),
    tostring(c.adapt and c.adapt.min),
    tostring(c.adapt and c.adapt.max)
  )
end
