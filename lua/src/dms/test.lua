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
-- }
-- Check kinds: booted | spawns {min} | beats_in_order {beats} | beat {id} | comms {min} |
--   encounter {id} | convoy_halt | outcome {result} | ambient_cycle {site}. Optional per check:
--   name, deadlineSec.
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
function T.expect(name, fn, deadlineSec, opts)
  opts = opts or {}
  local interval = opts.interval or 2
  local deadline = now() + (deadlineSec or 60)
  local resolved = false
  T._pending = T._pending + 1
  local function resolve(ok, detail)
    if resolved then
      return
    end
    resolved = true
    T._pending = T._pending - 1
    if ok then
      T.pass(name, detail)
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

CHECKS.encounter = function(c, deadline)
  T.expect(c.name, function()
    local n = T._obs.encounters[c.id]
    if n then
      return true, string.format("%s spawned (%d)", c.id, n)
    end
    local st = DMS.Encounters and DMS.Encounters.get and DMS.Encounters.get(c.id)
    return false, string.format("%s not spawned (fired=%s)", c.id, tostring(st and st.fired))
  end, deadline)
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

CHECKS.outcome = function(c, deadline)
  T.expect(c.name, function()
    for _, o in ipairs(T._obs.outcomes) do
      if o.kind == "end" and (c.result == nil or o.result == c.result) then
        return true, "end result=" .. tostring(o.result)
      end
    end
    return false,
      string.format("%d outcome line(s), no end%s", #T._obs.outcomes, c.result and (" with result=" .. c.result) or "")
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
