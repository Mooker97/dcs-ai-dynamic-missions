-- Spec: DMS.Narrative (lua/src/dms/narrative.lua)
-- ---------------------------------------------------------------------------
-- Self-contained test world (installed per test, restored afterwards) so these specs only
-- depend on the contract API (DMS.Log, DMS.Bus, DMS.Rng, DMS.safeCall) and a callable assert.
-- DMS.Clock is replaced by a deterministic fake that implements the contract signatures.
-- ---------------------------------------------------------------------------
local W -- current world

local function eq(a, b, msg)
  if a ~= b then
    error((msg or "values differ") .. ": expected " .. tostring(b) .. ", got " .. tostring(a), 2)
  end
end

local function fakeClock()
  local C = { t = 0, tasks = {}, nextId = 0 }
  C.api = {
    now = function()
      return C.t
    end,
    after = function(d, fn, ...)
      local args = { n = select("#", ...), ... }
      C.nextId = C.nextId + 1
      C.tasks[C.nextId] = { at = C.t + (d or 0), fn = fn, args = args, id = C.nextId }
      return C.nextId
    end,
    every = function(i, fn, opts)
      opts = opts or {}
      C.nextId = C.nextId + 1
      C.tasks[C.nextId] = { at = C.t + (opts.firstDelay or i), fn = fn, every = i, args = { n = 0 }, id = C.nextId }
      return C.nextId
    end,
    cancel = function(id)
      if id then
        C.tasks[id] = nil
      end
    end,
  }
  function C.advance(dt)
    local target = C.t + dt
    while true do
      local best
      for _, task in pairs(C.tasks) do
        if task.at <= target and (not best or task.at < best.at or (task.at == best.at and task.id < best.id)) then
          best = task
        end
      end
      if not best then
        break
      end
      C.t = best.at
      if best.every then
        best.at = C.t + best.every
      else
        C.tasks[best.id] = nil
      end
      local ok, r = pcall(best.fn, unpack(best.args, 1, best.args.n))
      if not ok then
        W.errors[#W.errors + 1] = "clock task: " .. tostring(r)
      end
      if best.every and ok and r == false then
        C.tasks[best.id] = nil
      end
    end
    C.t = target
  end
  return C
end

local function newWorld()
  local w = {
    units = {},
    groups = {},
    calls = {},
    flags = {},
    menus = {},
    detected = {},
    infos = {},
    errors = {},
    visible = true,
    nextGid = 100,
  }
  w.clock = fakeClock()
  local function rec(name)
    return function(...)
      w.calls[#w.calls + 1] = { name, ... }
    end
  end
  w.trigger = {
    action = {
      outText = rec("outText"),
      outTextForCoalition = rec("outTextForCoalition"),
      outTextForGroup = rec("outTextForGroup"),
      outSound = rec("outSound"),
      outSoundForCoalition = rec("outSoundForCoalition"),
      outSoundForGroup = rec("outSoundForGroup"),
      radioTransmission = rec("radioTransmission"),
      removeMark = rec("removeMark"),
      markToCoalition = rec("markToCoalition"),
      circleToAll = rec("circleToAll"),
      markToAll = rec("markToAll"),
      setUserFlag = function(n, v)
        w.flags[n] = v
        w.calls[#w.calls + 1] = { "setUserFlag", n, v }
      end,
    },
    misc = {
      getUserFlag = function(n)
        return w.flags[n] or 0
      end,
      getZone = function()
        return nil
      end,
    },
  }
  -- missionCommands: paths are lists, like DCS
  local function key(p)
    return table.concat(p, "/")
  end
  w.missionCommands = {
    addSubMenuForGroup = function(gid, name, parent)
      local p = {}
      for i, v in ipairs(parent or {}) do
        p[i] = v
      end
      p[#p + 1] = name
      w.menus[gid] = w.menus[gid] or {}
      w.menus[gid][key(p)] = { kind = "menu", path = p }
      return p
    end,
    addCommandForGroup = function(gid, name, parent, fn, arg)
      local p = {}
      for i, v in ipairs(parent or {}) do
        p[i] = v
      end
      p[#p + 1] = name
      w.menus[gid] = w.menus[gid] or {}
      w.menus[gid][key(p)] = { kind = "cmd", path = p, fn = fn, arg = arg }
      return p
    end,
    removeItemForGroup = function(gid, path)
      local k = key(path)
      for kk in pairs(w.menus[gid] or {}) do
        if kk == k or string.sub(kk, 1, #k + 1) == k .. "/" then
          w.menus[gid][kk] = nil
        end
      end
    end,
  }
  local UnitM, GroupM = {}, {}
  UnitM.__index = UnitM
  GroupM.__index = GroupM
  function UnitM:getName()
    return self.name
  end
  function UnitM:getPoint()
    return { x = self.pos.x, y = self.pos.y or 0, z = self.pos.z }
  end
  function UnitM:isExist()
    return self.alive
  end
  function UnitM:getLife()
    return self.alive and 10 or 0
  end
  function UnitM:getTypeName()
    return self.type
  end
  function UnitM:getGroup()
    return self.group
  end
  function UnitM:getCoalition()
    return self.group.coal
  end
  function UnitM:getPlayerName()
    return self.player
  end
  function GroupM:getName()
    return self.name
  end
  function GroupM:getCoalition()
    return self.coal
  end
  function GroupM:getID()
    return self.id
  end
  function GroupM:isExist()
    return true
  end
  function GroupM:getUnits()
    local o = {}
    for _, u in ipairs(self.units) do
      if u.alive then
        o[#o + 1] = u
      end
    end
    return o
  end
  function GroupM:getController()
    local g = self
    return {
      getDetectedTargets = function()
        return w.detected[g.name] or {}
      end,
    }
  end
  function w.addGroup(name, coal, units, opts)
    opts = opts or {}
    w.nextGid = w.nextGid + 1
    local g = setmetatable({ name = name, coal = coal, units = {}, id = opts.id or w.nextGid }, GroupM)
    for i, u in ipairs(units) do
      local un = setmetatable(
        {
          name = u.name or (name .. "-" .. i),
          type = u.type or "BTR-80",
          pos = { x = u.x, y = 0, z = u.z },
          alive = true,
          group = g,
          player = u.player,
        },
        UnitM
      )
      g.units[#g.units + 1] = un
      w.units[un.name] = un
    end
    w.groups[name] = g
    return g
  end
  w.Group = {
    getByName = function(n)
      return w.groups[n]
    end,
    Category = { GROUND = 2 },
  }
  w.Unit = {
    getByName = function(n)
      local u = w.units[n]
      if u and u.alive then
        return u
      end
      return nil
    end,
  }
  w.coalition = {
    side = { NEUTRAL = 0, RED = 1, BLUE = 2 },
    getPlayers = function(c)
      local o = {}
      for _, u in pairs(w.units) do
        if u.player and u.alive and u.group.coal == c then
          o[#o + 1] = u
        end
      end
      table.sort(o, function(a, b)
        return a.name < b.name
      end)
      return o
    end,
    getGroups = function(c)
      local o = {}
      for _, g in pairs(w.groups) do
        if g.coal == c then
          o[#o + 1] = g
        end
      end
      table.sort(o, function(a, b)
        return a.name < b.name
      end)
      return o
    end,
  }
  w.land = {
    isVisible = function()
      return w.visible
    end,
    getHeight = function()
      return 0
    end,
  }
  function w.callsOf(name)
    local o = {}
    for _, c in ipairs(w.calls) do
      if c[1] == name then
        o[#o + 1] = c
      end
    end
    return o
  end
  function w.clear()
    w.calls = {}
  end
  return w
end

local GLOBALS = { "trigger", "missionCommands", "Group", "Unit", "coalition", "land", "DMS_CONFIG" }

-- Run fn(w) inside a fresh world; restores globals + DMS.Clock even when fn fails.
local function withWorld(config, fn)
  local saved = {}
  for _, g in ipairs(GLOBALS) do
    saved[g] = _G[g]
  end
  local savedClock, savedEnc, savedErr = DMS.Clock, DMS.Encounters, DMS.Log.error
  local savedInfo, savedWarn = env and env.info, env and env.warning
  W = newWorld()
  local w = W
  trigger, missionCommands, Group, Unit, coalition, land =
    w.trigger, w.missionCommands, w.Group, w.Unit, w.coalition, w.land
  DMS_CONFIG = config
  DMS.Clock = w.clock.api
  DMS.Log.error = function(p, f, ...)
    local ok, m = pcall(string.format, f, ...)
    w.errors[#w.errors + 1] = "[" .. tostring(p) .. "] " .. tostring(ok and m or f)
  end
  if env then
    env.info = function(s)
      w.infos[#w.infos + 1] = s
    end
    env.warning = function(s)
      w.infos[#w.infos + 1] = s
    end
  end
  if DMS.Rng and DMS.Rng.seed then
    DMS.Rng.seed(config and config.seed or 1)
  end
  local ok, err = pcall(fn, w)
  for _, m in ipairs({ "Narrative", "Comms", "Intel" }) do
    if DMS[m] and DMS[m].stop then
      pcall(DMS[m].stop)
    end
  end
  if DMS.Comms and DMS.Comms._resetAll then
    pcall(DMS.Comms._resetAll)
  end
  for _, g in ipairs(GLOBALS) do
    _G[g] = saved[g]
  end
  DMS.Clock, DMS.Encounters, DMS.Log.error = savedClock, savedEnc, savedErr
  if env then
    env.info, env.warning = savedInfo, savedWarn
  end
  if not ok then
    error(err, 0)
  end
  if #w.errors > 0 then
    error("logged errors: " .. table.concat(w.errors, "\n"), 0)
  end
end

local function cfgWith(beats, extra)
  local c = {
    seed = 7,
    missionId = "m-test",
    players = { coalition = 2 },
    beats = beats,
    narrative = { minGapSec = 8, pendingTtlSec = 45 },
    zones = {},
    voice = {},
    qualities = {},
  }
  for k, v in pairs(extra or {}) do
    c[k] = v
  end
  return c
end

local function outcomes(w)
  local o = {}
  for _, l in ipairs(w.infos) do
    if string.sub(l, 1, 14) == "[DMS.OUTCOME] " then
      o[#o + 1] = string.sub(l, 15)
    end
  end
  return o
end

describe("DMS.Narrative", function()
  it("fires the highest-priority eligible beat first and spaces the rest by the min gap", function()
    withWorld(
      cfgWith({
        { id = "low", when = { event = "group.dead", group = "HVT" }, priority = 10, once = true, text = "low" },
        { id = "high", when = { event = "group.dead", group = "HVT" }, priority = 80, once = true, text = "high" },
        { id = "other", when = { event = "group.dead", group = "NOPE" }, priority = 99, once = true },
      }),
      function(w)
        DMS.Narrative.start()
        DMS.Bus.emit("group.dead", { group = "HVT", coalition = 1 })
        local fired = DMS.Narrative.firedList()
        eq(#fired, 1, "one beat at a time")
        eq(fired[1], "high")
        w.clock.advance(5)
        eq(#DMS.Narrative.firedList(), 1, "min gap holds the lower beat")
        w.clock.advance(5)
        eq(#DMS.Narrative.firedList(), 2)
        eq(DMS.Narrative.firedList()[2], "low")
        eq(DMS.Narrative.firedCount("other"), 0, "filter mismatch never fires")
      end
    )
  end)

  it("respects once and cooldownSec", function()
    local c = cfgWith({
      { id = "one", when = { event = "x.ping" }, priority = 1, once = true },
      { id = "cd", when = { event = "x.pong" }, priority = 1, once = false, cooldownSec = 30 },
    })
    c.narrative = { minGapSec = 0, pendingTtlSec = 5 }
    withWorld(c, function(w)
      DMS.Narrative.start()
      DMS.Bus.emit("x.ping", {})
      w.clock.advance(20)
      DMS.Bus.emit("x.ping", {})
      w.clock.advance(20)
      eq(DMS.Narrative.firedCount("one"), 1, "once")
      DMS.Bus.emit("x.pong", {}) -- t=40 fires
      w.clock.advance(10)
      DMS.Bus.emit("x.pong", {}) -- t=50, in cooldown; pending expires at 55
      w.clock.advance(10)
      eq(DMS.Narrative.firedCount("cd"), 1, "cooldown blocks")
      w.clock.advance(15) -- t=75
      DMS.Bus.emit("x.pong", {})
      eq(DMS.Narrative.firedCount("cd"), 2, "fires again after cooldown")
    end)
  end)

  it("rolls chance once per trigger", function()
    local c = cfgWith({
      { id = "never", when = { event = "x.e" }, chance = 0, once = false },
      { id = "always", when = { event = "x.e" }, chance = 100, once = false },
      { id = "half", when = { event = "x.e" }, requires = { chance = 50 }, once = false },
    })
    c.narrative = { minGapSec = 0, pendingTtlSec = 0.5 }
    withWorld(c, function(w)
      DMS.Narrative.start()
      for _ = 1, 200 do
        DMS.Bus.emit("x.e", {})
        w.clock.advance(1)
      end
      eq(DMS.Narrative.firedCount("never"), 0)
      eq(DMS.Narrative.firedCount("always"), 200)
      local h = DMS.Narrative.firedCount("half")
      assert(h > 60 and h < 140, "chance 50 fired " .. h .. "/200")
    end)
  end)

  it("applies quality deltas and gates beats on quality comparisons", function()
    local c = cfgWith({
      { id = "brave", when = { event = "x.brave" }, once = false, effects = { qualities = { morale = 1 } } },
      { id = "rally", when = { flag = "go" }, once = true, requires = { qualities = { morale = ">=2" } } },
      { id = "despair", when = { flag = "go" }, once = true, requires = { qualities = { morale = { max = 0 } } } },
    }, { qualities = { morale = 1 } })
    c.narrative = { minGapSec = 0, pendingTtlSec = 3 }
    withWorld(c, function(w)
      DMS.Narrative.start()
      eq(DMS.Narrative.getQuality("morale"), 1, "seeded from config")
      w.flags.go = 1
      w.clock.advance(5)
      eq(DMS.Narrative.firedCount("rally"), 0, "morale 1 < 2")
      w.flags.go = 0
      w.clock.advance(2)
      DMS.Bus.emit("x.brave", {})
      eq(DMS.Narrative.getQuality("morale"), 2)
      w.flags.go = 1
      w.clock.advance(2)
      eq(DMS.Narrative.firedCount("rally"), 1, "fires once morale >= 2")
      eq(DMS.Narrative.firedCount("despair"), 0)
      assert(
        DMS.Narrative._compare(3, "<4")
          and not DMS.Narrative._compare(3, "==4")
          and DMS.Narrative._compare(1, { op = "~=", value = 2 }),
        "comparisons"
      )
    end)
  end)

  it("supports timer, beat-chain, director, flag-requirement and zone triggers", function()
    local c = cfgWith(
      {
        { id = "t60", when = { afterSec = 60 }, once = true },
        { id = "chain", when = { beat = "t60" }, once = true, effects = { setFlag = "chained" } },
        { id = "gated", when = { event = "x.g" }, once = true, requires = { flags = { chained = true } } },
        { id = "peak", when = { director = "PEAK" }, once = true },
        { id = "ridge", when = { zone = "ridge" }, once = true },
      },
      {
        zones = {
          ridge = { kind = "circle", x = 10000, y = 0, radius = 2000 },
          box = {
            kind = "polygon",
            points = { { x = 0, y = 0 }, { x = 10, y = 0 }, { x = 10, y = 10 }, { x = 0, y = 10 } },
          },
        },
      }
    )
    c.narrative = { minGapSec = 2, pendingTtlSec = 30, zonePollSec = 3 }
    withWorld(c, function(w)
      w.addGroup("Viper1", 2, { { name = "Viper1-1", x = 0, z = 0, player = "Mav" } })
      DMS.Narrative.start()
      DMS.Bus.emit("x.g", {})
      w.clock.advance(59)
      eq(DMS.Narrative.firedCount("t60"), 0)
      eq(DMS.Narrative.firedCount("gated"), 0, "flag not yet set")
      w.clock.advance(5)
      eq(DMS.Narrative.firedCount("t60"), 1)
      eq(DMS.Narrative.firedCount("chain"), 1, "chained after gap")
      eq(w.flags.chained, 1, "setUserFlag called")
      DMS.Bus.emit("x.g", {})
      w.clock.advance(3)
      eq(DMS.Narrative.firedCount("gated"), 1)
      DMS.Bus.emit("director.state", { flight = "Viper1", state = "RELAX" })
      w.clock.advance(3)
      eq(DMS.Narrative.firedCount("peak"), 0)
      DMS.Bus.emit("director.state", { flight = "Viper1", state = "PEAK" })
      w.clock.advance(3)
      eq(DMS.Narrative.firedCount("peak"), 1)
      local entered = {}
      DMS.Bus.on("zone.entered", function(p)
        entered[#entered + 1] = p
      end)
      w.units["Viper1-1"].pos = { x = 9500, y = 0, z = 500 }
      w.clock.advance(4)
      eq(#entered, 1, "zone.entered once")
      eq(entered[1].zone, "ridge")
      eq(entered[1].unit, "Viper1-1")
      eq(entered[1].group, "Viper1")
      w.clock.advance(10)
      eq(#entered, 1, "no repeat while inside")
      eq(DMS.Narrative.firedCount("ridge"), 1)
      assert(DMS.Narrative._inZone(c.zones.box, { x = 5, y = 0, z = 5 }), "polygon inside")
      assert(not DMS.Narrative._inZone(c.zones.box, { x = 15, y = 0, z = 5 }), "polygon outside")
    end)
  end)

  it("delegates effects to Comms, Intel, Encounters and writes [DMS.OUTCOME] json", function()
    local c = cfgWith(
      {
        {
          id = "tgt_down",
          when = { event = "group.dead", group = "HVT" },
          priority = 80,
          once = true,
          speaker = "ops",
          lines = { "tgt_v1", "tgt_v2" },
          text = "Splash HVT.",
          mark = "zone:town",
          effects = { setFlag = "tgt_down", outcome = { hvtKilled = true }, startEncounter = "egress_cap" },
        },
        { id = "win", when = { beat = "tgt_down" }, once = true, text = "RTB.", effects = { finish = "victory" } },
      },
      {
        voice = {
          tgt_v1 = { file = "tgt_v1.ogg", text = "Splash one", durSec = 3, speaker = "ops" },
          tgt_v2 = { file = "tgt_v2.ogg", text = "Target down", durSec = 3, speaker = "ops" },
        },
        zones = { town = { kind = "circle", x = 100, y = 200, radius = 1500 } },
      }
    )
    withWorld(c, function(w)
      local started = {}
      DMS.Encounters = {
        trigger = function(id, ctx)
          started[#started + 1] = { id, ctx }
        end,
      }
      DMS.Comms.start()
      DMS.Intel.start()
      DMS.Narrative.start()
      DMS.Bus.emit("group.dead", { group = "HVT", coalition = 1 })
      eq(#started, 1)
      eq(started[1][1], "egress_cap")
      eq(started[1][2].beat, "tgt_down")
      eq(w.flags.tgt_down, 1)
      local snd = w.callsOf("outSoundForCoalition")
      eq(#snd, 1)
      assert(snd[1][3] == "l10n/DEFAULT/tgt_v1.ogg" or snd[1][3] == "l10n/DEFAULT/tgt_v2.ogg", tostring(snd[1][3]))
      assert(#w.callsOf("markToCoalition") == 1 and #w.callsOf("circleToAll") == 1, "zone mark drawn")
      local o = outcomes(w)
      eq(#o, 1, "outcome written on change")
      assert(string.find(o[1], '"hvtKilled"%s*:%s*true'), o[1])
      assert(string.sub(o[1], 1, 1) == "{", "json object")
      w.clock.advance(10)
      o = outcomes(w)
      eq(#o, 2, "final outcome on finish")
      assert(string.find(o[2], '"victory"'), o[2])
      assert(string.find(o[2], '"end"'), o[2])
      DMS.Narrative.finish("defeat")
      eq(#outcomes(w), 2, "finish only once")
    end)
  end)

  it("survives 200 random seeds with random beats and events", function()
    local events = { "group.dead", "unit.hit", "x.a", "x.b", "director.state", "mission.end" }
    for seed = 1, 200 do
      math.randomseed(seed)
      local beats = {}
      for i = 1, math.random(3, 10) do
        local kinds = {
          { event = events[math.random(1, 5)], group = (math.random() < 0.5) and "G" .. math.random(1, 3) or nil },
          { afterSec = math.random(0, 300) },
          { flag = "f" .. math.random(1, 3) },
          { beat = "b" .. math.random(1, 10) },
          { zone = "z1" },
          { director = "PEAK", delaySec = math.random(0, 5) },
          { event = "x.a", groupPrefix = "G" },
          { bogus = true },
        }
        beats[#beats + 1] = {
          id = "b" .. i,
          when = kinds[math.random(1, #kinds)],
          priority = math.random(0, 100),
          once = math.random() < 0.5,
          cooldownSec = math.random(0, 60),
          chance = math.random(0, 100),
          requires = {
            flags = { ["f" .. math.random(1, 3)] = math.random() < 0.5 },
            qualities = { q = (math.random() < 0.5) and ">=0" or { min = -1, max = 3 } },
          },
          speaker = "s",
          lines = { "l1", "l2" },
          text = "beat " .. i,
          effects = {
            qualities = { q = math.random(-1, 1) },
            setFlag = { ["f" .. math.random(1, 3)] = math.random(0, 1) },
            outcome = { ["k" .. i] = math.random(1, 3) },
            mark = (math.random() < 0.2) and "zone:z1" or nil,
          },
        }
      end
      local c = cfgWith(
        beats,
        {
          seed = seed,
          zones = { z1 = { kind = "circle", x = 0, y = 0, radius = 3000 } },
          qualities = { q = 0 },
          voice = { l1 = { file = "l1.ogg", durSec = 2 } },
        }
      )
      c.narrative = { minGapSec = math.random(0, 10), pendingTtlSec = math.random(1, 60) }
      withWorld(c, function(w)
        w.addGroup("P1", 2, { { name = "P1-1", x = 5000, z = 5000, player = "p" } })
        DMS.Comms.start()
        DMS.Intel.start()
        DMS.Narrative.start()
        for _ = 1, 60 do
          local e = events[math.random(1, #events)]
          DMS.Bus.emit(e, { group = "G" .. math.random(1, 3), state = "PEAK", flight = "P1" })
          if math.random() < 0.2 then
            w.flags["f" .. math.random(1, 3)] = math.random(0, 1)
          end
          if math.random() < 0.1 then
            w.units["P1-1"].pos = { x = math.random(-4000, 4000), y = 0, z = 0 }
          end
          w.clock.advance(math.random(1, 20))
        end
      end)
    end
  end)
end)

describe("Narrative + Comms + Intel on the real core and DCS mock", function()
  it("player spawn -> menu, proximity -> mark, kill -> beat, voice and outcome", function()
    DMS_CONFIG = {
      seed = 9,
      missionId = "m-int",
      players = { coalition = 2 },
      intel = { revealRadiusM = 8000, markRefreshSec = 10, staleSec = 60, scanSec = 5 },
      beats = {
        {
          id = "hvt_down",
          when = { event = "group.dead", group = "HVT" },
          priority = 50,
          once = true,
          speaker = "ops",
          lines = { "hvt_v1" },
          text = "HVT destroyed",
          effects = { setFlag = "hvt_down", outcome = { hvtKilled = true }, finish = "victory" },
        },
      },
      voice = { hvt_v1 = { file = "hvt_v1.ogg", text = "Good kill, HVT is down", durSec = 3, speaker = "ops" } },
    }
    DMS.Rng.seed(9)
    DMS.Bus.install()
    DMS.Narrative.start()
    DMS.Comms.start()
    DMS.Intel.start()
    local u = MOCK.spawnPlayer({ name = "Viper1-1", group = "Viper1", playerName = "Mav", x = 0, y = 0, alt = 3000 })
    local gid = u:getGroup():getID()
    local items = MOCK.menuItems("group:" .. gid)
    assert(#items > 0, "per-group menu built on player.spawned")
    MOCK.addGroup({ name = "HVT", coalition = 1, category = "ground", units = { { type = "T-72B", x = 3000, y = 0 } } })
    MOCK.advance(12)
    local nMarks = 0
    for id in pairs(MOCK.marks) do
      assert(id >= 50000, "mark id " .. id)
      nMarks = nMarks + 1
    end
    eq(nMarks, 2, "circle + text for the HVT contact")
    MOCK.killGroup("HVT")
    MOCK.advance(10)
    eq(DMS.Narrative.firedCount("hvt_down"), 1)
    eq(MOCK.flags.hvt_down, 1)
    local snd = MOCK.callsTo("trigger.action.outSoundForCoalition")
    eq(#snd, 1)
    eq(snd[1].args[2], "l10n/DEFAULT/hvt_v1.ogg")
    assert(MOCK.logContains("%[DMS%.OUTCOME%].*hvtKilled"), "outcome logged")
    assert(MOCK.logContains("%[DMS%.OUTCOME%].*victory"), "final outcome logged")
    eq(next(MOCK.marks), nil, "marks removed when the group died")
    MOCK.invokeMenu("group:" .. gid, { "DMS", "Repeat last message" })
    local t = MOCK.callsTo("trigger.action.outTextForGroup")
    assert(#t >= 1 and string.find(t[#t].args[2], "HVT is down", 1, true), "repeat last message")
  end)
end)
