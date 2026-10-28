-- encounters.lua: runs DMS_CONFIG.encounters.
-- Kinds: pool, ambush_sam, waves, hunt, convoy, cap. Triggers: time, proximity, beat, event, director,
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
  -- cap
  capCheckSec = 10,
  capAltM = 7000,
  capSpeed = 220, -- m/s
  capLegM = 30000, -- race-track leg length
  capEngageRadiusM = 40000,
  capArriveM = 10000, -- within leg/2 + this of the station centre = on station
  capStationTimeoutSec = 1200, -- never seen arriving: start the station clock anyway
  capRtbDespawnSec = 600, -- RTB this long (or home reached): despawn when out of sight
  capHomeM = 5000,
  capDespawnMinPlayerM = 37000, -- never despawn within ~20 nm of an enemy player
  capReplaceDelaySec = { 60, 180 },
  capMaxDeferSec = 900,
}

local function cfg()
  return DMS_CONFIG or {}
end
local function playersCoalition()
  return (cfg().players and cfg().players.coalition) or 2
end

function Enc.reset()
  for _, st in pairs(Enc._state or {}) do
    for _, t in ipairs(st.tokens) do
      DMS.Bus.off(t)
    end
    for _, id in ipairs(st.timers) do
      DMS.Clock.cancel(id)
    end
    for _, h in ipairs(st.handles) do
      pcall(h.stop)
    end
  end
  if Enc._clearTimer then
    DMS.Clock.cancel(Enc._clearTimer)
  end
  if Enc._deadToken then
    DMS.Bus.off(Enc._deadToken)
  end
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
  if p.z ~= nil then
    return { x = p.x, y = p.z }
  end
  return { x = p.x, y = p.y }
end

local function addTimer(st, id)
  if id then
    st.timers[#st.timers + 1] = id
  end
  return id
end
local function addToken(st, t)
  if t then
    st.tokens[#st.tokens + 1] = t
  end
  return t
end

-- Units of coalition `coal` as list of {name, group, pos(vec3)}. Players only for the player side
-- (cheap); all units otherwise.
local function unitsOf(coal)
  local out = {}
  if coal == playersCoalition() then
    for _, pl in ipairs(DMS.Spawner.playerUnits()) do
      if pl.coalition == coal then
        local gname
        pcall(function()
          gname = pl.unit:getGroup():getName()
        end)
        local uname
        pcall(function()
          uname = pl.unit:getName()
        end)
        out[#out + 1] = { name = uname, group = gname, pos = pl.pos }
      end
    end
    return out
  end
  pcall(function()
    for _, g in ipairs(coalition.getGroups(coal) or {}) do
      for _, u in ipairs(g:getUnits() or {}) do
        if u:isExist() then
          out[#out + 1] = { name = u:getName(), group = g:getName(), pos = u:getPoint() }
        end
      end
    end
  end)
  return out
end

-- Nearest enemy player group to the given group (for hunters).
function Enc.nearestPlayerGroup(groupName, maxM)
  local hp = DMS.Ground.leadPos(groupName)
  if not hp then
    return nil
  end
  local myCoal = DMS.Registry.get(groupName) and DMS.Registry.get(groupName).coalition
  local best, bestD
  for _, pl in ipairs(DMS.Spawner.playerUnits()) do
    if pl.coalition ~= myCoal then
      local d = d2(v2(hp), v2(pl.pos))
      if (not maxM or d <= maxM) and (not bestD or d < bestD) then
        local gname
        pcall(function()
          gname = pl.unit:getGroup():getName()
        end)
        if gname then
          best, bestD = gname, d
        end
      end
    end
  end
  return best, bestD
end

local function aliveGroups(st)
  local n = 0
  for _, g in ipairs(st.groups) do
    if DMS.Registry.isAlive(g) then
      n = n + 1
    end
  end
  return n
end

local function checkCleared(st)
  if st.cleared or not st.spawnedAny then
    return
  end
  if st.preClear then
    st.preClear()
  end -- cap: process losses (and queue replacements) first
  if st.pending > 0 or (st.capQueued or 0) > 0 then
    return
  end
  if aliveGroups(st) == 0 then
    st.cleared = true
    DMS.Log.info(P, "Encounter '%s' cleared", st.def.id)
    DMS.Bus.emit("encounter.cleared", { id = st.def.id, encounter = st.def.id })
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
  for _, g in ipairs(groups) do
    st.groups[#st.groups + 1] = g
  end
  if #groups > 0 then
    st.spawnedAny = true
    st.cleared = false
    DMS.Log.info(P, "Encounter '%s' spawned %d group(s)", def.id, #groups)
    DMS.Bus.emit("encounter.spawned", { id = def.id, encounter = def.id, groups = groups, kind = def.kind })
  end
  return groups
end

local function zoneOpt(def)
  if def.spawnZone then
    return def.spawnZone
  end
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
      target = function(name)
        return Enc.nearestPlayerGroup(name, def.huntRadiusM)
      end
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
-- gate (optional): {strict = bool, maxDeferSec = n, onDrop = fn(why)}. Non-strict spawns anyway once
-- maxDeferSec has passed; strict drops the spawn instead (the director budget is never exceeded).
local function gatedSpawn(st, opts, after, gate)
  local def = st.def
  gate = gate or {}
  local gated = def.gated ~= false and DMS.Director and DMS.Director.canSpawn
  local started = DMS.Clock.now()
  local maxDefer = gate.maxDeferSec or def.maxDeferSec or Enc.defaults.maxDeferSec
  st.pending = st.pending + 1
  local function attempt()
    if st.stopped then
      st.pending = st.pending - 1
      return
    end
    if gated then
      local ok, why = DMS.Director.canSpawn(def.cost or 1)
      if not ok then
        if DMS.Clock.now() - started < maxDefer then
          DMS.Log.debug(P, "Encounter '%s' deferred by director (%s)", def.id, tostring(why))
          addTimer(st, DMS.Clock.after(def.gateRetrySec or Enc.defaults.gateRetrySec, attempt))
          return
        end
        if gate.strict then
          st.pending = st.pending - 1
          DMS.Log.info(
            P,
            "Encounter '%s' spawn skipped: director refused for %.0fs (%s)",
            def.id,
            maxDefer,
            tostring(why)
          )
          if gate.onDrop then
            gate.onDrop(why)
          end
          return
        end
      end
    end
    st.pending = st.pending - 1
    local groups = spawnFor(st, opts)
    if after then
      after(groups)
    end
  end
  attempt()
end

-- ---------------------------------------------------------------- kinds

local KIND = {}

KIND.pool = function(st)
  gatedSpawn(st, { zone = zoneOpt(st.def) }, function(groups)
    if st.def.hunt then
      startHunts(st, groups)
    end
  end)
end

KIND.hunt = function(st)
  gatedSpawn(st, { zone = zoneOpt(st.def) }, function(groups)
    startHunts(st, groups)
  end)
end

KIND.waves = function(st)
  local def = st.def
  local n = math.max(1, math.floor(DMS.Rng.range(def.waves or 1) + 0.5))
  local wave = 0
  st.pending = st.pending + n
  local function nextWave()
    if st.stopped then
      return
    end
    wave = wave + 1
    st.pending = st.pending - 1
    DMS.Log.info(P, "Encounter '%s' wave %d/%d", def.id, wave, n)
    gatedSpawn(st, { zone = zoneOpt(def) }, function(groups)
      if def.hunt then
        startHunts(st, groups)
      end
      DMS.Bus.emit("encounter.wave", { id = def.id, encounter = def.id, wave = wave, of = n, groups = groups })
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
  if not t then
    return
  end
  DMS.Bus.emit("encounter.telegraph", { id = def.id, encounter = def.id, telegraph = t, groups = groups })
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
  DMS.Bus.emit("encounter.sam_hot", { id = st.def.id, encounter = st.def.id, group = g })
end

KIND.ambush_sam = function(st)
  local def = st.def
  -- dark from the start; controller touched only after spawn delay (onReady)
  local groups = spawnFor(st, { zone = zoneOpt(def), onReady = goDark })
  if #groups == 0 then
    return
  end
  local radius = def.engageRadiusM or Enc.defaults.samEngageRadiusM
  local pc = playersCoalition()
  local sites = {}
  for _, g in ipairs(groups) do
    sites[g] = { state = "dark" }
  end
  local id
  id = addTimer(
    st,
    DMS.Clock.every(def.checkSec or Enc.defaults.samCheckSec, function()
      if st.stopped then
        return false
      end
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
                if d2(v2(sp), v2(u.pos)) <= radius then
                  inRange = true
                  break
                end
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
                if DMS.Director and DMS.Director.scaleDelay then
                  delay = DMS.Director.scaleDelay(delay)
                end
                addTimer(
                  st,
                  DMS.Clock.after(delay, function()
                    if DMS.Registry.isAlive(g) then
                      site.state = "hot"
                      goHot(st, g)
                    end
                  end)
                )
              end
            end
          end
        end
      end
      if remaining == 0 then
        return false
      end
      return true
    end, { firstDelay = 1.5 })
  )
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
-- ---------------------------------------------------------------- cap
-- Enemy air group(s) fly to a station (zone centre or point), orbit there (Race-Track or Circle)
-- with an EngageTargetsInZone en-route task, optionally leave after timeOnStationSec (RTB route
-- home, then despawn out of sight), and may be replaced up to maxSpawns groups in total.
-- Every launch is strictly director-gated: if the director refuses for capMaxDeferSec the launch
-- is dropped, so the director spawn budget is never exceeded.
-- Task tables follow the Hoggit SSE docs (Orbit, EngageTargetsInZone en-route task in a
-- waypoint ComboTask, the same shape legacy/lua-library/ai-behavior/fire-support.lua uses).

local function optVal(path)
  local ok, v = pcall(path)
  if ok then
    return v
  end
  return nil
end

local function enumAir(group, name, fallback)
  local v = optVal(function()
    return AI.Option.Air.val[group][name]
  end)
  if v == nil then
    DMS.Log.warn(P, "Unknown AI.Option.Air.val.%s '%s', using %s", group, tostring(name), fallback)
    v = optVal(function()
      return AI.Option.Air.val[group][fallback]
    end)
  end
  return v
end

-- Resolved station geometry for a CAP def: {center, pattern, point, point2, altM, speed, radius}.
function Enc.capStation(def)
  local o = def.orbit or {}
  local z = def.zone and DMS.Spawner.getZone(def.zone)
  local center = (def.point and v2(def.point)) or (z and DMS.Spawner.zoneCenter(z))
  if not center then
    return nil
  end
  local pattern = o.pattern or "Race-Track"
  if pattern ~= "Race-Track" and pattern ~= "Circle" then
    DMS.Log.warn(P, "CAP '%s': unknown orbit pattern '%s', using Race-Track", tostring(def.id), tostring(pattern))
    pattern = "Race-Track"
  end
  local s = {
    center = center,
    pattern = pattern,
    altM = DMS.Rng.range(o.altM or Enc.defaults.capAltM),
    speed = DMS.Rng.range(o.speed or Enc.defaults.capSpeed),
    radius = def.engageRadiusM or math.max(Enc.defaults.capEngageRadiusM, (z and DMS.Spawner.zoneRadius(z)) or 0),
    legM = 0,
  }
  if pattern == "Race-Track" then
    local leg = DMS.Rng.range(o.legM or Enc.defaults.capLegM)
    local hdg = math.rad(o.headingDeg or (DMS.Rng.random() * 360))
    local hx, hy = math.cos(hdg) * leg / 2, math.sin(hdg) * leg / 2
    s.point = { x = center.x - hx, y = center.y - hy }
    s.point2 = { x = center.x + hx, y = center.y + hy }
    s.legM = leg
  else
    s.point = { x = center.x, y = center.y }
  end
  return s
end

-- {id="Orbit", params={pattern, point, point2?, speed, altitude}}
function Enc.capOrbitTask(s, number)
  local pattern = s.pattern
  if pattern == "Race-Track" then
    pattern = optVal(function()
      return AI.Task.OrbitPattern.RACE_TRACK
    end) or "Race-Track"
  else
    pattern = optVal(function()
      return AI.Task.OrbitPattern.CIRCLE
    end) or "Circle"
  end
  local params = { pattern = pattern, point = { x = s.point.x, y = s.point.y }, speed = s.speed, altitude = s.altM }
  if s.point2 then
    params.point2 = { x = s.point2.x, y = s.point2.y }
  end
  return { number = number or 1, auto = false, enabled = true, id = "Orbit", params = params }
end

-- En-route {id="EngageTargetsInZone", params={point, zoneRadius, targetTypes, priority}}
function Enc.capEngageTask(s, targetTypes, number)
  return {
    number = number or 1,
    auto = false,
    enabled = true,
    id = "EngageTargetsInZone",
    params = {
      point = { x = s.center.x, y = s.center.y },
      zoneRadius = s.radius,
      targetTypes = targetTypes or { "Air" },
      priority = 0,
    },
  }
end

local function airPoint(p, s, tasks)
  return {
    x = p.x,
    y = p.y,
    alt = s.altM,
    alt_type = "BARO",
    type = "Turning Point",
    action = "Turning Point",
    speed = s.speed,
    speed_locked = true,
    ETA = 0,
    ETA_locked = false,
    task = { id = "ComboTask", params = { tasks = tasks or {} } },
  }
end

local function airCtrl(g)
  local grp = DMS.Ground.getGroup(g)
  if not grp then
    return nil
  end
  local ok, c = pcall(grp.getController, grp)
  return ok and c or nil
end

local function capOptions(def, c)
  local A = AI.Option.Air
  local roe = enumAir("ROE", def.roe or "OPEN_FIRE", "OPEN_FIRE")
  local react = enumAir("REACTION_ON_THREAT", def.reaction or "EVADE_FIRE", "EVADE_FIRE")
  c:setOption(A.id.ROE, roe)
  c:setOption(A.id.REACTION_ON_THREAT, react)
  c:setOption(A.id.RTB_ON_BINGO, true)
  c:setOption(A.id.PROHIBIT_AG, true)
  if def.radar then
    c:setOption(A.id.RADAR_USING, enumAir("RADAR_USING", def.radar, "FOR_SEARCH_IF_REQUIRED"))
  end
end

local function capTask(st, g)
  local rec = st.cap[g]
  if not rec or rec.state ~= "transit" then
    return
  end
  local s = st.capStation
  local c = airCtrl(g)
  local lp = DMS.Ground.leadPos(g)
  if not c or not lp then
    DMS.Log.warn(P, "CAP '%s': group '%s' not taskable", st.def.id, g)
    return
  end
  rec.home = rec.home or v2(lp)
  local ok, err = pcall(function()
    capOptions(st.def, c)
    c:setTask({
      id = "Mission",
      params = {
        route = {
          points = {
            airPoint(v2(lp), s, { Enc.capEngageTask(s, st.def.targetTypes, 1) }),
            airPoint(s.point, s, { Enc.capOrbitTask(s, 1) }),
          },
        },
      },
    })
  end)
  if not ok then
    DMS.Log.error(P, "CAP '%s': tasking '%s' failed: %s", st.def.id, g, tostring(err))
    return
  end
  rec.tasked = true
  rec.since = DMS.Clock.now()
  DMS.Log.info(
    P,
    "CAP '%s': '%s' tasked to %s station (%.0f, %.0f) alt %.0f m, engage radius %.0f m",
    st.def.id,
    g,
    s.pattern,
    s.center.x,
    s.center.y,
    s.altM,
    s.radius
  )
end

local function capRtb(st, g, rec)
  local s = st.capStation
  local c = airCtrl(g)
  local lp = DMS.Ground.leadPos(g)
  rec.state = "rtb"
  rec.rtbAt = DMS.Clock.now()
  if c and lp then
    local ok, err = pcall(function()
      c:setOption(AI.Option.Air.id.ROE, AI.Option.Air.val.ROE.RETURN_FIRE)
      local home = rec.home or s.center
      c:setTask({
        id = "Mission",
        params = {
          route = { points = {
            airPoint(v2(lp), s, {}),
            airPoint(home, s, {}),
          } },
        },
      })
    end)
    if not ok then
      DMS.Log.error(P, "CAP '%s': RTB tasking '%s' failed: %s", st.def.id, g, tostring(err))
    end
  end
  DMS.Log.info(P, "CAP '%s': '%s' off station, RTB", st.def.id, g)
  DMS.Bus.emit("encounter.cap_rtb", { id = st.def.id, encounter = st.def.id, group = g })
end

local function nearestEnemyPlayerM(st, g, p)
  local myCoal = DMS.Registry.get(g) and DMS.Registry.get(g).coalition
  local best
  for _, pl in ipairs(DMS.Spawner.playerUnits()) do
    if pl.coalition ~= myCoal then
      local d = d2(v2(p), v2(pl.pos))
      if not best or d < best then
        best = d
      end
    end
  end
  return best
end

local capLaunch -- forward

local function capReplace(st, why)
  local def = st.def
  local max = def.maxSpawns or 0
  if st.capSpawned + st.capQueued >= max then
    DMS.Log.debug(
      P,
      "CAP '%s': no replacement after %s (%d/%d groups used)",
      def.id,
      why,
      st.capSpawned + st.capQueued,
      max
    )
    return
  end
  st.capQueued = st.capQueued + 1
  local delay = DMS.Rng.range(def.replaceDelaySec or Enc.defaults.capReplaceDelaySec)
  DMS.Log.info(
    P,
    "CAP '%s': replacement after %s in %.0fs (%d/%d groups used)",
    def.id,
    why,
    delay,
    st.capSpawned + st.capQueued,
    max
  )
  addTimer(
    st,
    DMS.Clock.after(delay, function()
      if st.stopped then
        st.capQueued = st.capQueued - 1
        return
      end
      capLaunch(st, true)
    end)
  )
end

local function capLost(st, g, rec)
  rec.state = "dead"
  DMS.Log.info(P, "CAP '%s': '%s' lost", st.def.id, g)
  DMS.Bus.emit("encounter.cap_lost", { id = st.def.id, encounter = st.def.id, group = g })
  if st.def.replaceOnDead ~= false then
    capReplace(st, "loss")
  end
end

local function capStep(st, g, rec, now)
  if rec.state == "dead" or rec.state == "gone" then
    return
  end
  if not DMS.Registry.isAlive(g) then
    capLost(st, g, rec)
    return
  end
  if not rec.tasked then
    return
  end
  local def = st.def
  local s = st.capStation
  local lp = DMS.Ground.leadPos(g)
  if rec.state == "transit" then
    local arrived = lp and d2(v2(lp), s.center) <= s.legM / 2 + (def.arriveM or Enc.defaults.capArriveM)
    local timedOut = now - rec.since >= (def.stationTimeoutSec or Enc.defaults.capStationTimeoutSec)
    if arrived or timedOut then
      rec.state = "station"
      rec.stationAt = now
      if def.timeOnStationSec then
        rec.leaveAt = now + DMS.Rng.range(def.timeOnStationSec)
      end
      DMS.Log.info(
        P,
        "CAP '%s': '%s' on station (%s)%s",
        def.id,
        g,
        arrived and "arrived" or "timeout",
        rec.leaveAt and string.format(", leaving in %.0fs", rec.leaveAt - now) or ""
      )
      DMS.Bus.emit("encounter.cap_on_station", { id = def.id, encounter = def.id, group = g })
    end
  elseif rec.state == "station" then
    if rec.leaveAt and now >= rec.leaveAt then
      capRtb(st, g, rec)
      if def.replaceOnRtb ~= false then
        capReplace(st, "rtb")
      end
    end
  elseif rec.state == "rtb" then
    local home = rec.home or s.center
    local atHome = lp and d2(v2(lp), home) <= Enc.defaults.capHomeM
    local late = now - rec.rtbAt >= (def.rtbDespawnSec or Enc.defaults.capRtbDespawnSec)
    if (atHome or late) and lp then
      local near = nearestEnemyPlayerM(st, g, lp)
      local minD = def.despawnMinPlayerM or Enc.defaults.capDespawnMinPlayerM
      if near and near < minD then
        DMS.Log.debug(P, "CAP '%s': despawn of '%s' deferred (player %.0f m < %.0f m)", def.id, g, near, minD)
        return
      end
      local grp = DMS.Ground.getGroup(g)
      if grp then
        pcall(grp.destroy, grp)
      end
      rec.state = "gone"
      DMS.Log.info(P, "CAP '%s': '%s' despawned after RTB (%s)", def.id, g, atHome and "home" or "timeout")
      DMS.Bus.emit("encounter.cap_despawned", { id = def.id, encounter = def.id, group = g })
    end
  end
end

local function capMonitor(st)
  if st.capTimer and DMS.Clock.isActive(st.capTimer) then
    return
  end
  st.capTimer = addTimer(
    st,
    DMS.Clock.every(st.def.checkSec or Enc.defaults.capCheckSec, function()
      if st.stopped then
        return false
      end
      local now = DMS.Clock.now()
      local live = 0
      for _, g in ipairs(st.capOrder) do
        local rec = st.cap[g]
        capStep(st, g, rec, now)
        if rec.state ~= "dead" and rec.state ~= "gone" then
          live = live + 1
        end
      end
      if live == 0 and st.capQueued == 0 and st.pending == 0 then
        DMS.Log.info(P, "CAP '%s' finished (%d group(s) used)", st.def.id, st.capSpawned)
        return false
      end
      return true
    end, { firstDelay = 2 })
  )
end

local function capInitialCount(def)
  if not def.pool then
    return nil
  end
  local pool = (cfg().pools or {})[def.pool]
  if not pool then
    return nil
  end
  local n = math.max(1, math.floor(DMS.Rng.range(pool.pick or 1) + 0.5))
  if DMS.Director and DMS.Director.scaleCount then
    n = DMS.Director.scaleCount(n)
  end
  return n
end

-- One gated launch = one group (pools spawn count = 1), so every group passes the director gate.
capLaunch = function(st, isReplacement)
  local def = st.def
  local s = st.capStation
  local opts = {
    zone = def.spawnZone,
    cost = def.cost or 1,
    altM = s.altM,
    speed = s.speed,
    onReady = function(g)
      capTask(st, g)
    end,
  }
  if def.pool then
    opts.count = 1
  end
  local function settle()
    if isReplacement then
      st.capQueued = st.capQueued - 1
    end
  end
  gatedSpawn(st, opts, function(groups)
    settle()
    for _, g in ipairs(groups) do
      st.capSpawned = st.capSpawned + 1
      st.cap[g] = { state = "transit", since = DMS.Clock.now(), tasked = false }
      st.capOrder[#st.capOrder + 1] = g
    end
    if #groups == 0 then
      DMS.Log.info(P, "CAP '%s': launch produced no group (spawner refused)", def.id)
    else
      DMS.Log.info(
        P,
        "CAP '%s': launched %d group(s)%s (%d/%s used)",
        def.id,
        #groups,
        isReplacement and " as replacement" or "",
        st.capSpawned,
        tostring(def.maxSpawns or st.capSpawned)
      )
    end
    capMonitor(st)
  end, { strict = true, maxDeferSec = def.maxDeferSec or Enc.defaults.capMaxDeferSec, onDrop = settle })
end

KIND.cap = function(st)
  local def = st.def
  if not def.pool and not def.template then
    DMS.Log.warn(P, "CAP '%s' has no pool/template", tostring(def.id))
    return
  end
  local s = Enc.capStation(def)
  if not s then
    DMS.Log.warn(P, "CAP '%s' has no station (zone/point)", tostring(def.id))
    return
  end
  st.capStation = s
  st.cap = st.cap or {}
  st.capOrder = st.capOrder or {}
  st.capSpawned = st.capSpawned or 0
  st.capQueued = st.capQueued or 0
  if def.maxSpawns and st.capSpawned >= def.maxSpawns then
    DMS.Log.info(P, "CAP '%s' skipped: spawn limit reached (%d)", def.id, def.maxSpawns)
    return
  end
  DMS.Log.info(
    P,
    "CAP '%s' starting: %s station (%.0f, %.0f), maxSpawns %s",
    def.id,
    s.pattern,
    s.center.x,
    s.center.y,
    tostring(def.maxSpawns or "-")
  )
  local n = capInitialCount(def) or 1
  if def.maxSpawns then
    n = math.min(n, def.maxSpawns - st.capSpawned)
  end
  st.preClear = function()
    local now = DMS.Clock.now()
    for _, g in ipairs(st.capOrder) do
      capStep(st, g, st.cap[g], now)
    end
  end
  for _ = 1, n do
    capLaunch(st, false)
  end
end

Enc.KIND = KIND

-- ---------------------------------------------------------------- firing

local function fire(st, why, manual)
  local def = st.def
  if st.done and not manual then
    return false
  end
  if def.once ~= false then
    st.done = true
  end
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
  if not ok then
    DMS.Log.error(P, "Encounter '%s' failed: %s", def.id, tostring(err))
  end
  return ok
end

-- trigger keys that configure the trigger rather than filter the event payload
local NOT_FILTERS = {
  type = true,
  name = true,
  event = true,
  checkSec = true,
  radiusM = true,
  afterSec = true,
  point = true,
  state = true,
}

local function matches(payload, filt)
  for k, v in pairs(filt) do
    if not NOT_FILTERS[k] and payload[k] ~= v then
      return false
    end
  end
  return true
end

local function arm(st)
  local def = st.def
  local t = def.trigger or { type = "manual" }
  local ty = t.type or "manual"
  if ty == "time" then
    addTimer(
      st,
      DMS.Clock.after(DMS.Rng.range(t.afterSec or 0), function()
        fire(st, "time")
      end)
    )
  elseif ty == "beat" then
    addToken(
      st,
      DMS.Bus.on("beat.fired", function(ev)
        if ev and ev.id == t.beat then
          fire(st, "beat " .. tostring(t.beat))
        end
      end)
    )
  elseif ty == "event" then
    local name = t.event or t.name
    if type(name) ~= "string" then
      DMS.Log.warn(P, "Encounter '%s': event trigger without event name", def.id)
      return
    end
    addToken(
      st,
      DMS.Bus.on(name, function(ev)
        if matches(ev or {}, t) then
          fire(st, "event " .. tostring(name))
        end
      end)
    )
  elseif ty == "director" then
    addToken(
      st,
      DMS.Bus.on("director.state", function(ev)
        if ev and ev.state == t.state then
          fire(st, "director " .. tostring(t.state))
        end
      end)
    )
  elseif ty == "proximity" then
    local zone = t.zone and DMS.Spawner.getZone(t.zone)
    local center = (t.point and v2(t.point)) or (zone and DMS.Spawner.zoneCenter(zone))
    if not center then
      DMS.Log.warn(P, "Encounter '%s': proximity trigger without zone/point", def.id)
      return
    end
    local radius = t.radiusM
    local coal = t.coalition or playersCoalition()
    addTimer(
      st,
      DMS.Clock.every(t.checkSec or Enc.defaults.proximityCheckSec, function()
        if st.done or st.stopped then
          return false
        end
        local who
        for _, u in ipairs(unitsOf(coal)) do
          local inside
          if radius then
            inside = d2(center, v2(u.pos)) <= radius
          else
            inside = DMS.Spawner.inZone(zone, u.pos)
          end
          if inside then
            who = u
            break
          end
        end
        if who and not st.inside then
          -- fire on entry only (re-arms after everyone leaves when once=false)
          st.inside = true
          DMS.Bus.emit(
            "encounter.proximity",
            { id = def.id, encounter = def.id, zone = t.zone, group = who.group, unit = who.name }
          )
          fire(st, "proximity " .. tostring(who.name))
          if st.done then
            return false
          end
        elseif not who then
          st.inside = false
        end
        return true
      end, { jitter = 1 })
    )
  end
end

-- Manual trigger: DMS.Encounters.trigger(id, opts). opts = true (force) or {force=bool, beat=id}.
-- Ignores chance; respects once unless force.
function Enc.trigger(id, opts)
  local st = Enc._state[id]
  if not st then
    DMS.Log.warn(P, "trigger: unknown encounter '%s'", tostring(id))
    return false
  end
  local force, beat = false, nil
  if opts == true then
    force = true
  elseif type(opts) == "table" then
    force = opts.force == true
    beat = opts.beat
  end
  if st.done and not force then
    DMS.Log.debug(P, "Encounter '%s' manual trigger ignored (already fired)", tostring(id))
    return false
  end
  st.done = false
  return fire(st, beat and ("beat " .. tostring(beat)) or "manual", true)
end

function Enc.get(id)
  return Enc._state[id]
end

function Enc.groups(id)
  local st = Enc._state[id]
  return st and st.groups or {}
end

function Enc.add(def)
  if not def or not def.id then
    return nil
  end
  local st = {
    def = def,
    groups = {},
    tokens = {},
    timers = {},
    handles = {},
    fired = 0,
    pending = 0,
    done = false,
    cleared = false,
    spawnedAny = false,
  }
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
    if not ok then
      DMS.Log.error(P, "Bad encounter '%s': %s", tostring(def and def.id), tostring(err))
    end
  end
  Enc._deadToken = DMS.Bus.on("group.dead", function()
    for _, st in pairs(Enc._state) do
      checkCleared(st)
    end
  end)
  Enc._clearTimer = DMS.Clock.every(Enc.defaults.clearCheckSec, function()
    for _, st in pairs(Enc._state) do
      checkCleared(st)
    end
  end)
  DMS.Log.info(P, "Started (%d encounters)", #list)
end

if not Enc._state then
  Enc._state, Enc._order = {}, {}
end
