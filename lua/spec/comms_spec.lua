-- Spec: DMS.Comms (lua/src/dms/comms.lua)
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
      local un = setmetatable({
        name = u.name or (name .. "-" .. i),
        type = u.type or "BTR-80",
        pos = { x = u.x, y = 0, z = u.z },
        alive = true,
        group = g,
        player = u.player,
      }, UnitM)
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

local function voiceCfg(extra)
  local c = {
    seed = 3,
    missionId = "m-test",
    players = { coalition = 2 },
    speakers = { ops = { callsign = "Mustang" } },
    voice = {
      a = { file = "a.ogg", text = "Alpha", durSec = 3, speaker = "ops" },
      b = { file = "b.ogg", text = "Bravo", durSec = 4.5, speaker = "ops" },
      c = { file = "c.ogg", text = "Charlie", durSec = 2, speaker = "ops" },
      d = { file = "d.ogg", text = "Delta", durSec = 6, speaker = "ops" },
    },
  }
  for k, v in pairs(extra or {}) do
    c[k] = v
  end
  return c
end

local function spawn(gid, name, unit, player)
  DMS.Bus.emit(
    "player.spawned",
    { unit = unit, group = name, groupId = gid, playerName = player, coalition = 2, typeName = "F-16C_50" }
  )
end

local function countKind(w, gid, kind)
  local n = 0
  for _, item in pairs(w.menus[gid] or {}) do
    if item.kind == kind then
      n = n + 1
    end
  end
  return n
end

describe("DMS.Comms", function()
  it("queues voice lines so transmissions never overlap and subtitles carry the callsign", function()
    withWorld(voiceCfg(), function(w)
      DMS.Comms.start()
      for _, id in ipairs({ "a", "b", "c", "d", "a", "c" }) do
        DMS.Comms.say("ops", id, nil, {})
      end
      DMS.Comms.say("ops", nil, "text only line", { durSec = 2 })
      w.clock.advance(120)
      local h = DMS.Comms.history()
      eq(#h, 7, "all played")
      for i = 2, #h do
        assert(
          h[i].t >= h[i - 1].t + h[i - 1].dur,
          string.format("overlap at %d: %.2f < %.2f + %.2f", i, h[i].t, h[i - 1].t, h[i - 1].dur)
        )
      end
      local snd = w.callsOf("outSoundForCoalition")
      eq(#snd, 6, "text-only line has no sound")
      eq(snd[1][2], 2)
      eq(snd[1][3], "l10n/DEFAULT/a.ogg")
      local txt = w.callsOf("outTextForCoalition")
      eq(txt[1][3], "Mustang: Alpha")
      eq(txt[7][3], "Mustang: text only line")
      assert(not DMS.Comms.isBusy(), "idle at end")
    end)
  end)

  it("higher priority lines jump the queue but never interrupt", function()
    withWorld(voiceCfg(), function(w)
      DMS.Comms.start()
      DMS.Comms.say("ops", "a", nil, { priority = 0 })
      DMS.Comms.say("ops", "b", nil, { priority = 0 })
      DMS.Comms.say("ops", "d", nil, { priority = 90 })
      w.clock.advance(60)
      local h = DMS.Comms.history()
      eq(h[1].line, "a", "already playing")
      eq(h[2].line, "d", "priority next")
      eq(h[3].line, "b")
    end)
  end)

  it("rotates line variants with a per-speaker shuffle-bag", function()
    withWorld(voiceCfg(), function(w)
      DMS.Comms.start()
      local picks, counts = {}, { a = 0, b = 0, c = 0, d = 0 }
      for _ = 1, 40 do
        local id = DMS.Comms.say("ops", { "a", "b", "c", "d" }, nil, {})
        picks[#picks + 1] = id
        counts[id] = counts[id] + 1
        w.clock.advance(10)
      end
      for i = 2, #picks do
        assert(picks[i] ~= picks[i - 1], "repeat at " .. i)
      end
      for k, n in pairs(counts) do
        eq(n, 10, "even rotation of " .. k)
      end
      for start = 1, 37, 4 do
        local seen = {}
        for i = start, start + 3 do
          assert(not seen[picks[i]], "bag repeated within a cycle at " .. i)
          seen[picks[i]] = true
        end
      end
    end)
  end)

  it("applies cooldowns, radio frequencies and group targets", function()
    withWorld(voiceCfg(), function(w)
      DMS.Comms.start()
      assert(DMS.Comms.say("ops", "a", nil, { cooldownSec = 30, key = "k" }), "first")
      eq(DMS.Comms.say("ops", "b", nil, { cooldownSec = 30, key = "k" }), false, "cooldown")
      w.clock.advance(31)
      assert(DMS.Comms.say("ops", "c", nil, { cooldownSec = 30, key = "k", frequency = 251.0, modulation = 0 }))
      DMS.Comms.say("ops", "a", nil, { groupId = 42 })
      w.clock.advance(30)
      local rt = w.callsOf("radioTransmission")
      eq(#rt, 1)
      eq(rt[1][2], "l10n/DEFAULT/c.ogg")
      eq(rt[1][6], 251000000, "MHz converted to Hz")
      local g = w.callsOf("outSoundForGroup")
      eq(#g, 1)
      eq(g[1][2], 42)
      eq(#w.callsOf("outTextForGroup"), 1)
    end)
  end)

  it("builds separate per-group F10 menus, rebuilds on respawn and passes ctx", function()
    withWorld(voiceCfg(), function(w)
      DMS.Comms.start()
      spawn(11, "Viper1", "Viper1-1", "Mav")
      spawn(12, "Viper2", "Viper2-1", "Goose")
      assert(w.menus[11]["DMS"] and w.menus[12]["DMS"], "root per group")
      assert(w.menus[11]["DMS/Repeat last message"] and w.menus[11]["DMS/Mission status"], "builtins")
      local got = {}
      DMS.Comms.addMenuCommand("Support/Smoke", "Red smoke", function(ctx)
        got[#got + 1] = ctx
      end)
      local c11 = w.menus[11]["DMS/Support/Smoke/Red smoke"]
      local c12 = w.menus[12]["DMS/Support/Smoke/Red smoke"]
      assert(c11 and c12, "late-registered command reaches existing groups")
      c12.fn(c12.arg)
      eq(#got, 1)
      eq(got[1].groupId, 12)
      eq(got[1].groupName, "Viper2")
      eq(got[1].unitName, "Viper2-1")
      eq(got[1].playerName, "Goose")
      eq(got[1].coalition, 2)
      local before = countKind(w, 11, "cmd")
      spawn(11, "Viper1", "Viper1-1", "Iceman") -- respawn
      eq(countKind(w, 11, "cmd"), before, "no duplicates after respawn")
      eq(#w.callsOf("removeItemForGroup") >= 0, true)
      local c = w.menus[11]["DMS/Support/Smoke/Red smoke"]
      c.fn(c.arg)
      eq(got[2].playerName, "Iceman", "ctx refreshed on respawn")
      DMS.Comms.addMenuCommand("Support/Smoke", "Red smoke", function(ctx)
        got[#got + 1] = ctx
      end)
      eq(countKind(w, 11, "cmd"), before, "re-registration dedupes")
    end)
  end)

  it("repeats the last message and reports mission status", function()
    withWorld(voiceCfg(), function(w)
      DMS.Comms.start()
      spawn(11, "Viper1", "Viper1-1", "Mav")
      DMS.Comms.say("ops", "b", nil, {})
      w.clock.advance(10)
      w.clear()
      local r = w.menus[11]["DMS/Repeat last message"]
      r.fn(r.arg)
      local t = w.callsOf("outTextForGroup")
      eq(#t, 1)
      eq(t[1][2], 11)
      eq(t[1][3], "Mustang: Bravo")
      local s = w.menus[11]["DMS/Mission status"]
      s.fn(s.arg)
      t = w.callsOf("outTextForGroup")
      assert(string.find(t[2][3], "m-test", 1, true), t[2][3])
      DMS.Comms.text("Plain", { coalition = 2, durSec = 5 })
      eq(w.callsOf("outTextForCoalition")[1][3], "Plain")
    end)
  end)

  it("survives 200 random seeds", function()
    for seed = 1, 200 do
      math.randomseed(seed)
      withWorld(voiceCfg({ seed = seed }), function(w)
        DMS.Comms.start()
        local ids = { "a", "b", "c", "d", "missing" }
        for _ = 1, 40 do
          local r = math.random()
          if r < 0.5 then
            DMS.Comms.say("ops", { ids[math.random(1, 5)], ids[math.random(1, 5)] }, "t", {
              priority = math.random(0, 3),
              cooldownSec = math.random(0, 5),
              groupId = (math.random() < 0.3) and 11 or nil,
              frequency = (math.random() < 0.2) and 124.5 or nil,
            })
          elseif r < 0.7 then
            spawn(math.random(10, 13), "G", "U", "P")
          elseif r < 0.8 then
            local m = w.menus[math.random(10, 13)]
            for _, item in pairs(m or {}) do
              if item.kind == "cmd" then
                item.fn(item.arg)
              end
            end
          else
            DMS.Comms.addMenuCommand(math.random() < 0.5 and "" or "X/Y", "c" .. math.random(1, 3), function() end)
          end
          w.clock.advance(math.random(0, 6))
        end
        w.clock.advance(400)
        local h = DMS.Comms.history()
        for i = 2, #h do
          assert(h[i].t >= h[i - 1].t + h[i - 1].dur, "overlap seed " .. seed)
        end
      end)
    end
  end)
end)
