-- DMS.Test: in-mission assertions + player proxy for headless DCS runs (tools/dcs_harness).
-- Inert unless DMS_CONFIG.test.enabled (or DMS.Test.* is called directly). Lua 5.1.
--
-- Log protocol (parsed by tools/dcs_harness/run_mission.py):
--   [DMS.TEST] PASS|FAIL|SKIP|INFO <name> <detail>
--   [DMS.TEST] DONE <passed>/<total>        -- the harness exits DCS a few seconds after this
--
-- DMS_CONFIG.test = {
--   enabled = true,
--   playerProxy = "<AI group name>",   -- treated as the player by every player-dependent module
--   minutes = 40,                      -- model minutes; pending checks fail and DONE is logged at the end
--   checks = { {kind = "booted"}, {kind = "beats_in_order", beats = {...}, deadlineSec = 600}, ... },
--   loiter = { zone, x, y, radiusM, altM, altType, speedMps, startBeat, untilBeat, returnSec }, -- optional
-- }
-- Check kinds: booted | spawns {min} | beats_in_order {beats} | beat {id} | comms {min} |
--   encounter {id, optional, group} | convoy_halt | outcome {requireResult} | ambient_cycle {site}.
--   Optional per check: name, deadlineSec.
-- encounter optional=true never FAILs and never holds the run open: PASS if spawned, else INFO
--   "optional encounter X not spawned" (naming spawned siblings of the same exclusive `group`).
-- outcome passes on any end outcome (detail reports the result) unless requireResult (or legacy
--   result) names one.
-- Loiter: once startBeat fired (or the proxy is within radiusM of x/y) the proxy gets a pushed
--   Orbit task until untilBeat fires or minutes*60 - 15 - returnSec, then popTask resumes its route.
--
-- Player proxy: on mission.start the proxy's units are registered as players (DMS.Bus._players)
-- and a synthetic "player.spawned" is emitted for each, so Narrative/Intel/Director/Comms and
-- DMS.Spawner.playerUnits() (encounter proximity, hunts, spawn distance) treat it as the player.
-- The proxy is made immortal, weapons-hold and non-reacting so it flies its route.

DMS = DMS or {}
DMS.Test = DMS.Test or {}
local T = DMS.Test
local P = "Test"

T._pending = T._pending or 0
T._total = T._total or 0
T._passed = T._passed or 0
T._done = T._done or false

local function now()
  return timer.getTime()
end

local function tlog(status, name, detail)
  local safeName = (tostring(name or "-"):gsub("%s", "_"))
  env.info(string.format("[DMS.TEST] %s %s %s", status, safeName, tostring(detail or "")))
end

local function schedule(fn, delay)
  if DMS.Clock and DMS.Clock.after then
    return DMS.Clock.after(delay, fn)
  end
  return timer.scheduleFunction(function()
    fn()
    return nil
  end, nil, now() + delay)
end

-- ---------------------------------------------------------------- assertion API

function T.pass(name, detail)
  T._total = T._total + 1
  T._passed = T._passed + 1
  tlog("PASS", name, detail)
end
function T.fail(name, detail)
  T._total = T._total + 1
  tlog("FAIL", name, detail)
end
function T.skip(name, detail)
  tlog("SKIP", name, detail)
end
function T.info(name, detail)
  tlog("INFO", name, detail)
end

function T.check(name, cond, detail)
  if cond then
    T.pass(name, detail)
  else
    T.fail(name, detail or "check failed")
  end
  return cond and true or false
end

function T.done()
  if T._done then
    return
  end
  T._done = true
  tlog("DONE", string.format("%d/%d", T._passed, T._total), "")
end

function T.autoDone(graceSec)
  if T._autoArmed or T.manualDone then
    return
  end
  T._autoArmed = true
  local function tick()
    if T._done then
      return
    end
    if T._pending <= 0 then
      schedule(T.done, graceSec or 2)
    else
      schedule(tick, 2)
    end
  end
  schedule(tick, 2)
end

-- expect(name, fn, deadlineSec, opts): poll fn(atEnd) every opts.interval (2 s). fn returns
-- ok, detail, fatal: ok -> PASS(detail); fatal -> FAIL(detail) now; else retry until the deadline
-- (FAIL with the last detail, or "timeout"). fn errors count as not-yet.
-- opts.negate: PASS if fn never became truthy before the deadline.
-- opts.optional: never FAIL and never hold the run open (not counted in _pending): a miss is
-- logged as INFO (opts.missDetail(detail) when given) once the deadline or the run end arrives.
function T.expect(name, fn, deadlineSec, opts)
  opts = opts or {}
  local interval = opts.interval or 2
  local deadline = now() + (deadlineSec or 60)
  local resolved = false
  local optional = opts.optional == true
  if not optional then
    T._pending = T._pending + 1
  end
  local function resolve(ok, detail)
    if resolved then
      return
    end
    resolved = true
    if not optional then
      T._pending = T._pending - 1
    end
    if ok then
      T.pass(name, detail)
    elseif optional then
      T.info(name, opts.missDetail and opts.missDetail(detail) or ("optional: " .. tostring(detail)))
    else
      T.fail(name, detail)
    end
  end
  local function poll(forceEnd)
    if resolved or T._done then
      return
    end
    local atEnd = forceEnd == true or now() >= deadline
    local okCall, res, detail, fatal = pcall(fn, atEnd)
    local hit = okCall and res
    if opts.negate then
      if hit then
        resolve(false, "became true: " .. tostring(detail or ""))
        return
      end
      if atEnd then
        resolve(true, "stayed false")
        return
      end
    else
      if hit then
        resolve(true, detail or string.format("t=%.0f", now()))
        return
      end
      if okCall and fatal then
        resolve(false, detail)
        return
      end
      if atEnd then
        resolve(
          false,
          (detail and ("timeout: " .. tostring(detail)) or "timeout")
            .. (okCall and "" or (" last error: " .. tostring(res)))
        )
        return
      end
    end
    schedule(poll, interval)
  end
  schedule(poll, 0.5)
  T._open = T._open or {}
  T._open[#T._open + 1] = function()
    poll(true)
  end
  T.autoDone()
  return resolve
end

-- Resolve every still-open expectation now (final evaluation, else FAIL timeout).
function T.resolveOpen()
  local open = T._open or {}
  T._open = {}
  for _, f in ipairs(open) do
    pcall(f)
  end
end

-- ---------------------------------------------------------------- config / proxy

function T.config()
  local c = DMS_CONFIG and DMS_CONFIG.test
  if type(c) ~= "table" or c.enabled == false then
    return nil
  end
  return c
end

function T.isEnabled()
  return T.config() ~= nil
end

function T.proxyName()
  local c = T.config()
  return c and c.playerProxy or nil
end

function T.isProxyRun()
  return T.proxyName() ~= nil
end

local function proxyGroup()
  local n = T.proxyName()
  if not n then
    return nil
  end
  local ok, g = pcall(Group.getByName, n)
  if not ok or not g then
    return nil
  end
  local okE, ex = pcall(g.isExist, g)
  if okE and ex then
    return g
  end
  return nil
end

-- Kept for scripts written against tools/dcs_harness/test_mode.lua.
function T.playerGroups(realList)
  local g = proxyGroup()
  if g then
    return { g }
  end
  return realList
end

-- Configure the proxy AI: immortal, weapons hold, no threat reaction (each step pcall'd).
function T.setupProxy()
  local g = proxyGroup()
  if not g then
    return false
  end
  local okC, c = pcall(g.getController, g)
  if not okC or not c then
    return false
  end
  local okCmd, e1 = pcall(c.setCommand, c, { id = "SetImmortal", params = { value = true } })
  if not okCmd then
    DMS.Log.warn(P, "proxy SetImmortal failed: %s", tostring(e1))
  end
  local okCat, cat = pcall(g.getCategory, g)
  local air = okCat and (cat == Group.Category.AIRPLANE or cat == Group.Category.HELICOPTER)
  local okO, e2 = pcall(function()
    if air then
      c:setOption(AI.Option.Air.id.ROE, AI.Option.Air.val.ROE.WEAPON_HOLD)
      c:setOption(AI.Option.Air.id.REACTION_ON_THREAT, AI.Option.Air.val.REACTION_ON_THREAT.NO_REACTION)
    else
      c:setOption(AI.Option.Ground.id.ROE, AI.Option.Ground.val.ROE.WEAPON_HOLD)
    end
  end)
  if not okO then
    DMS.Log.warn(P, "proxy options failed: %s", tostring(e2))
  end
  return true
end

-- Register the proxy's units as players and emit player.spawned for each. -> bool
function T.emitProxySpawn()
  local n = T.proxyName()
  if not (n and DMS.Bus and DMS.Bus.emit) then
    return false
  end
  local g = proxyGroup()
  if not g then
    return false
  end
  local okU, units = pcall(g.getUnits, g)
  if not okU or type(units) ~= "table" or #units == 0 then
    return false
  end
  local okI, gid = pcall(g.getID, g)
  local okS, side = pcall(g.getCoalition, g)
  for _, u in ipairs(units) do
    local okN, uname = pcall(u.getName, u)
    if okN and uname then
      local okT, tname = pcall(u.getTypeName, u)
      local payload = {
        unit = uname,
        group = n,
        groupId = okI and gid or nil,
        playerName = "PROXY",
        coalition = okS and side or nil,
        typeName = okT and tname or nil,
        proxy = true,
      }
      DMS.Bus._players[uname] = payload
      DMS.Bus.emit("player.spawned", payload)
    end
  end
  T.info("proxy", "registered " .. n .. " as the player (" .. #units .. " unit(s))")
  return true
end

-- ---------------------------------------------------------------- observations

local function freshObs()
  return {
    spawned = {},
    spawnCount = 0,
    water = {},
    beats = {},
    beatIndex = {},
    encounters = {},
    convoyHits = {},
    convoyHalted = {},
    outcomes = {},
    proxyTakeoff = false,
    proxyLanded = false,
    ambient = {}, -- site -> {act=n, deact=n, cycled=bool}
  }
end
T._obs = T._obs or freshObs()

local WATER_OK = { ship = true, air = true }

local function checkSpawnSurface(ev)
  local O = T._obs
  if WATER_OK[ev.category or "ground"] then
    return
  end
  local okG, g = pcall(Group.getByName, ev.group)
  if not okG or not g then
    return
  end
  local okU, units = pcall(g.getUnits, g)
  for _, u in ipairs(okU and units or {}) do
    local okP, p = pcall(u.getPoint, u)
    if okP and p then
      local okS, st = pcall(land.getSurfaceType, { x = p.x, y = p.z })
      if okS and (st == land.SurfaceType.WATER or st == land.SurfaceType.SHALLOW_WATER) then
        O.water[#O.water + 1] = string.format("%s@(%.0f,%.0f)", tostring(u:getName()), p.x, p.z)
      end
    end
  end
end

local function convoyGroupOf(encId)
  if not (DMS.Encounters and DMS.Encounters.get) then
    return nil
  end
  local st = DMS.Encounters.get(encId)
  if not (st and st.def and st.def.kind == "convoy") then
    return nil
  end
  return st.def.group or st.groups[1]
end

local function isConvoyGroup(name)
  if not name or not (DMS.Encounters and DMS.Encounters._order) then
    return false
  end
  for _, id in ipairs(DMS.Encounters._order) do
    if convoyGroupOf(id) == name then
      return true
    end
  end
  return false
end

function T._observe()
  if T._observing then
    return
  end
  T._observing = true
  local O = T._obs
  local on = DMS.Bus.on
  on("spawner.spawned", function(ev)
    if not ev or not ev.group then
      return
    end
    O.spawnCount = O.spawnCount + 1
    O.spawned[#O.spawned + 1] = ev.group
    checkSpawnSurface(ev)
  end)
  on("beat.fired", function(ev)
    if ev and ev.id and not O.beatIndex[ev.id] then
      O.beats[#O.beats + 1] = ev.id
      O.beatIndex[ev.id] = #O.beats
      T.info("beat", string.format("%s t=%.0f", ev.id, now()))
    end
  end)
  on("encounter.spawned", function(ev)
    if ev and ev.id then
      O.encounters[ev.id] = (O.encounters[ev.id] or 0) + 1
      T.info("encounter", string.format("%s spawned %d group(s) t=%.0f", ev.id, ev.groups and #ev.groups or 0, now()))
    end
  end)
  on("unit.hit", function(ev)
    if ev and ev.targetGroup and isConvoyGroup(ev.targetGroup) and not O.convoyHits[ev.targetGroup] then
      O.convoyHits[ev.targetGroup] = now()
    end
  end)
  on("convoy.halted", function(ev)
    if ev and ev.group then
      O.convoyHalted[ev.group] = now()
    end
  end)
  on("unit.takeoff", function(ev)
    if ev and ev.group == T.proxyName() and not O.proxyTakeoff then
      O.proxyTakeoff = true
      T.info("proxy", string.format("takeoff t=%.0f", now()))
    end
  end)
  on("unit.landed", function(ev)
    if ev and ev.group == T.proxyName() then
      O.proxyLanded = true
      T.info("proxy", string.format("landed t=%.0f place=%s", now(), tostring(ev.place)))
    end
  end)
  on("ambient.activated", function(ev)
    if ev and ev.site then
      local a = O.ambient[ev.site] or { act = 0, deact = 0 }
      O.ambient[ev.site] = a
      a.act = a.act + 1
      T.info("ambient", string.format("%s activated (%s group(s)) t=%.0f", ev.site, tostring(ev.groups), now()))
    end
  end)
  on("ambient.deactivated", function(ev)
    if ev and ev.site then
      local a = O.ambient[ev.site] or { act = 0, deact = 0 }
      O.ambient[ev.site] = a
      a.deact = a.deact + 1
      if a.act > 0 then
        a.cycled = true
      end
      T.info(
        "ambient",
        string.format(
          "%s deactivated (%s, %s group(s) removed) t=%.0f",
          ev.site,
          tostring(ev.reason),
          tostring(ev.groups),
          now()
        )
      )
    end
  end)
  on("zone.entered", function(ev)
    if ev and ev.group == T.proxyName() then
      T.info("zone", string.format("%s t=%.0f", tostring(ev.zone), now()))
    end
  end)
  -- outcome lines: wrap DMS.Log.outcome so the check sees exactly what reached dcs.log
  if DMS.Log and DMS.Log.outcome and not T._origOutcome then
    T._origOutcome = DMS.Log.outcome
    DMS.Log.outcome = function(tbl)
      local line = T._origOutcome(tbl)
      if line and type(tbl) == "table" then
        O.outcomes[#O.outcomes + 1] = { kind = tbl.kind, result = tbl.result }
      end
      return line
    end
  end
end

-- ---------------------------------------------------------------- built-in checks

local CHECKS = {}

CHECKS.booted = function(c)
  local mods = {}
  for _, n in ipairs(DMS.START_ORDER or {}) do
    if DMS[n] then
      mods[#mods + 1] = n
    end
  end
  T.check(c.name, DMS._booted == true, "modules=" .. table.concat(mods, ","))
end

CHECKS.spawns = function(c, deadline)
  local min = c.min or 1
  T.expect(c.name, function()
    local O = T._obs
    if #O.water > 0 then
      return false, "on water: " .. table.concat(O.water, " "), true
    end
    if O.spawnCount >= min then
      return true, string.format("%d group(s), none on water", O.spawnCount)
    end
    return false, string.format("%d/%d group(s) spawned", O.spawnCount, min)
  end, deadline)
end

CHECKS.beats_in_order = function(c, deadline)
  local want = c.beats or {}
  T.expect(c.name, function()
    local O = T._obs
    local last, missing = 0, {}
    for _, id in ipairs(want) do
      local i = O.beatIndex[id]
      if not i then
        missing[#missing + 1] = id
      elseif i < last then
        return false, "out of order at " .. id .. " (fired: " .. table.concat(O.beats, ",") .. ")", true
      else
        last = i
      end
    end
    if #missing == 0 then
      return true, table.concat(want, ">")
    end
    return false, "missing " .. table.concat(missing, ",") .. " (fired: " .. table.concat(O.beats, ",") .. ")"
  end, deadline)
end

CHECKS.beat = function(c, deadline)
  T.expect(c.name, function()
    if T._obs.beatIndex[c.id] then
      return true, c.id .. " fired"
    end
    return false, c.id .. " not fired"
  end, deadline)
end

CHECKS.comms = function(c, deadline)
  local min = c.min or 1
  T.expect(c.name, function()
    local n = (DMS.Comms and DMS.Comms.history and #DMS.Comms.history()) or 0
    if n >= min then
      return true, string.format("%d line(s) played", n)
    end
    return false, string.format("%d/%d line(s) played", n, min)
  end, deadline)
end

-- optional=true: never FAIL (INFO "optional encounter X not spawned"); `group` names a mutually
-- exclusive set (encounters of sibling chance beats), whose spawned members the INFO lists.
CHECKS.encounter = function(c, deadline)
  local opts = nil
  if c.optional then
    if c.group then
      T._groups = T._groups or {}
      local g = T._groups[c.group] or {}
      T._groups[c.group] = g
      g[#g + 1] = c.id
    end
    opts = {
      optional = true,
      missDetail = function()
        local msg = "optional encounter " .. tostring(c.id) .. " not spawned"
        if c.group then
          local got = {}
          for _, id in ipairs((T._groups or {})[c.group] or {}) do
            if id ~= c.id and T._obs.encounters[id] then
              got[#got + 1] = id
            end
          end
          msg = msg
            .. " (group "
            .. tostring(c.group)
            .. ": "
            .. (#got > 0 and (table.concat(got, ",") .. " spawned") or "none spawned")
            .. ")"
        end
        return msg
      end,
    }
  end
  T.expect(c.name, function()
    local n = T._obs.encounters[c.id]
    if n then
      return true, string.format("%s spawned (%d)", c.id, n)
    end
    local st = DMS.Encounters and DMS.Encounters.get and DMS.Encounters.get(c.id)
    return false, string.format("%s not spawned (fired=%s)", c.id, tostring(st and st.fired))
  end, deadline, opts)
end

-- Resolved last (at the deadline or once every other check resolved): every hit convoy halted.
CHECKS.convoy_halt = function(c, deadline)
  T._finals[#T._finals + 1] = function()
    local O = T._obs
    local hit, bad = 0, {}
    for g, t in pairs(O.convoyHits) do
      hit = hit + 1
      local h = O.convoyHalted[g]
      if not h or h - t > 5 then
        bad[#bad + 1] = g
      end
    end
    if #bad > 0 then
      T.fail(c.name, "hit but not halted: " .. table.concat(bad, ","))
      return
    end
    T.pass(c.name, hit == 0 and "no convoy was hit (vacuous)" or string.format("%d convoy(s) hit and halted", hit))
  end
end

-- Any `kind=end` outcome passes and reports its result; requireResult (or legacy result) demands one.
CHECKS.outcome = function(c, deadline)
  local want = c.requireResult or c.result
  T.expect(c.name, function()
    local seen = {}
    for _, o in ipairs(T._obs.outcomes) do
      if o.kind == "end" then
        if want == nil or o.result == want then
          return true, "end result=" .. tostring(o.result)
        end
        seen[#seen + 1] = tostring(o.result)
      end
    end
    if #seen > 0 then
      return false, string.format("end result=%s, required %s", table.concat(seen, ","), tostring(want)), true
    end
    return false,
      string.format(
        "%d outcome line(s), no end%s",
        #T._obs.outcomes,
        want and (" (required result=" .. want .. ")") or ""
      )
  end, deadline)
end

-- An ambient site activated (proxy near the base) and later deactivated (proxy left).
CHECKS.ambient_cycle = function(c, deadline)
  T.expect(c.name, function()
    local parts, ok = {}, false
    local sites = {}
    for id in pairs(T._obs.ambient) do
      sites[#sites + 1] = id
    end
    table.sort(sites)
    for _, id in ipairs(sites) do
      local a = T._obs.ambient[id]
      parts[#parts + 1] = string.format("%s(act=%d deact=%d)", id, a.act, a.deact)
      if a.cycled and (c.site == nil or c.site == id) then
        ok = true
      end
    end
    local detail = #parts > 0 and table.concat(parts, " ") or "no ambient site activated"
    return ok, detail
  end, deadline)
end

T.CHECKS = CHECKS

function T.runChecks(checks, defaultDeadline)
  T._finals = T._finals or {}
  for i, c in ipairs(checks or {}) do
    if type(c) == "table" then
      c.name = c.name or (tostring(c.kind) .. (c.id and ("_" .. c.id) or "") .. "_" .. i)
      local fn = CHECKS[c.kind]
      if not fn then
        T.fail(c.name, "unknown check kind '" .. tostring(c.kind) .. "'")
      else
        local ok, err = pcall(fn, c, c.deadlineSec or defaultDeadline)
        if not ok then
          T.fail(c.name, "check setup error: " .. tostring(err))
        end
      end
    end
  end
end

local function summary()
  local O = T._obs
  local enc = {}
  for id, n in pairs(O.encounters) do
    enc[#enc + 1] = id .. "=" .. n
  end
  table.sort(enc)
  T.info(
    "summary",
    string.format(
      "t=%.0f beats=[%s] spawns=%d encounters=[%s] comms=%d proxy(takeoff=%s landed=%s)",
      now(),
      table.concat(O.beats, ","),
      O.spawnCount,
      table.concat(enc, ","),
      (DMS.Comms and DMS.Comms.history and #DMS.Comms.history()) or 0,
      tostring(O.proxyTakeoff),
      tostring(O.proxyLanded)
    )
  )
end
T.summary = summary

-- ---------------------------------------------------------------- proxy loiter

local function proxyPoint()
  local g = proxyGroup()
  if not g then
    return nil
  end
  local okU, units = pcall(g.getUnits, g)
  local u = okU and type(units) == "table" and units[1] or nil
  if not u then
    return nil
  end
  local okP, p = pcall(u.getPoint, u)
  if okP and p then
    return p
  end
  return nil
end

local function proxyController()
  local g = proxyGroup()
  if not g then
    return nil
  end
  local okC, c = pcall(g.getController, g)
  if okC then
    return c
  end
  return nil
end

local function orbitTask(L)
  local alt = tonumber(L.altM) or 4500
  if L.altType == "RADIO" then
    local okH, h = pcall(land.getHeight, { x = L.x, y = L.y })
    if okH and type(h) == "number" then
      alt = alt + h
    end
  end
  local pattern = (AI and AI.Task and AI.Task.OrbitPattern and AI.Task.OrbitPattern.CIRCLE) or "Circle"
  return {
    id = "Orbit",
    params = {
      pattern = pattern,
      point = { x = L.x, y = L.y },
      altitude = alt,
      speed = tonumber(L.speedMps) or 150,
    },
  }
end

-- Hold the proxy over the objective until the RTB beat (L.untilBeat) fires or the return-flight
-- budget runs out (endAt - L.returnSec), then pop the Orbit so the route home resumes.
-- T._loiter.state: wait -> orbit -> done (or wait -> done when skipped).
function T.startLoiter(L, endAt)
  if type(L) ~= "table" or not L.untilBeat or not L.x or not L.y then
    return false
  end
  local untilT = (endAt or math.huge) - (tonumber(L.returnSec) or 0)
  local zone = tostring(L.zone or "loiter")
  local S = { state = "wait" }
  T._loiter = S
  local function finish(status, reason)
    S.state = "done"
    S.reason = reason
    T.info("loiter", string.format("%s %s (%s) t=%.0f", status, zone, reason, now()))
    DMS.Log.info(P, "proxy loiter %s over %s: %s", status, zone, reason)
  end
  local function startReason(O)
    if L.startBeat and O.beatIndex[L.startBeat] then
      return L.startBeat .. " fired"
    end
    local p = proxyPoint()
    if p then
      local dx, dz = p.x - L.x, p.z - L.y
      if math.sqrt(dx * dx + dz * dz) <= (tonumber(L.radiusM) or 3000) then
        return "proxy within " .. tostring(L.radiusM) .. " m"
      end
    end
    return nil
  end
  DMS.Clock.every(5, function()
    if S.state == "done" or T._done then
      return false
    end
    local O = T._obs
    local rtb = O.beatIndex[L.untilBeat] ~= nil
    if S.state == "wait" then
      if rtb then
        finish("skip", L.untilBeat .. " fired before the loiter zone")
        return false
      end
      if now() >= untilT then
        finish("skip", "no time left before the return flight")
        return false
      end
      local why = startReason(O)
      if not why then
        return true
      end
      local c = proxyController()
      local ok, err = false, "no controller"
      if c then
        ok, err = pcall(c.pushTask, c, orbitTask(L))
      end
      if not ok then
        finish("skip", "orbit task failed: " .. tostring(err))
        return false
      end
      S.state = "orbit"
      S.startedAt = now()
      T.info("loiter", string.format("start %s (%s) until %s t=%.0f", zone, why, L.untilBeat, now()))
      DMS.Log.info(P, "proxy loiter start over %s (%s), until %s or t=%.0f", zone, why, L.untilBeat, untilT)
      return true
    end
    -- orbiting
    local reason = nil
    if rtb then
      reason = L.untilBeat .. " fired"
    elseif now() >= untilT then
      reason = "timeout, return flight budget"
    end
    if not reason then
      return true
    end
    local c = proxyController()
    if c then
      pcall(c.popTask, c)
    end
    finish("stop", reason)
    return false
  end, { firstDelay = 5 })
  return true
end

-- ---------------------------------------------------------------- lifecycle

function T.start()
  local c = T.config()
  if not c or T._started then
    return false
  end
  T._started = true
  T._finals = T._finals or {}
  T._obs = freshObs()
  T._observe()
  local minutes = tonumber(c.minutes) or 30
  local endAt = minutes * 60 - 15
  local deadline = math.max(10, endAt - now())
  T.info(
    "start",
    string.format(
      "proxy=%s minutes=%s checks=%d",
      tostring(c.playerProxy),
      tostring(minutes),
      type(c.checks) == "table" and #c.checks or 0
    )
  )

  if c.playerProxy then
    local tries = 0
    local function arm()
      tries = tries + 1
      if T.emitProxySpawn() then
        T.setupProxy()
        DMS.Clock.after(5, T.setupProxy) -- once more after the AI has its first task
      elseif tries < 15 then
        DMS.Clock.after(2, arm)
      else
        T.fail("proxy_present", "group '" .. tostring(c.playerProxy) .. "' not found")
      end
    end
    DMS.Clock.after(1, arm)
  end

  if type(c.loiter) == "table" and c.playerProxy then
    T.startLoiter(c.loiter, endAt)
  end

  T.runChecks(c.checks, deadline)
  -- finals + DONE: when every polled check resolved, or at the end of the run
  local finished = false
  local function finish()
    if finished then
      return
    end
    finished = true
    T.resolveOpen()
    for _, f in ipairs(T._finals) do
      pcall(f)
    end
    summary()
    T.done()
  end
  T.manualDone = true
  DMS.Clock.every(5, function()
    if finished then
      return false
    end
    if T._pending <= 0 or now() >= endAt then
      finish()
      return false
    end
    return true
  end, { firstDelay = 5 })
  DMS.Clock.every(120, function()
    if finished then
      return false
    end
    summary()
    return true
  end, { firstDelay = 120 })
  return true
end

function T._reset()
  T._pending, T._total, T._passed, T._done = 0, 0, 0, false
  T._autoArmed, T.manualDone, T._started, T._finals, T._open = nil, nil, nil, {}, {}
  T._groups, T._loiter = {}, nil
  T._obs = freshObs()
end

-- Start on mission.start (emitted by DMS.boot after every module started).
if DMS.Bus and DMS.Bus.on and not T._bootToken then
  T._bootToken = DMS.Bus.on("mission.start", function()
    if T.isEnabled() then
      local ok, err = pcall(T.start)
      if not ok then
        DMS.Log.error(P, "start failed: %s", tostring(err))
      end
    end
  end)
end
