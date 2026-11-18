-- Spec: DMS.Intel (lua/src/dms/intel.lua)
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

local function intelCfg(extra)
  local c = {
    seed = 5,
    missionId = "m-test",
    players = { coalition = 2 },
    intel = { fogOfWar = true, revealRadiusM = 5000, markRefreshSec = 15, staleSec = 120, scanSec = 5 },
    zones = {
      town = { kind = "circle", x = 1000, y = 2000, radius = 1500 },
      ridge = { kind = "polygon", points = { { x = 0, y = 0 }, { x = 100, y = 0 }, { x = 100, y = 100 } } },
    },
  }
  for k, v in pairs(extra or {}) do
    c[k] = v
  end
  return c
end

local function setup(w)
  w.addGroup("Viper1", 2, { { name = "Viper1-1", x = 0, z = 0, player = "Mav" } })
  w.addGroup("SAM1", 1, {
    { name = "SAM1-1", x = 4000, z = 0, type = "Osa 9A33 ln" },
    { name = "SAM1-2", x = 4100, z = 100, type = "Osa 9A33 ln" },
  })
  w.addGroup("FAR", 1, { { name = "FAR-1", x = 60000, z = 0, type = "T-72B" } })
end

local function liveIds(w)
  local live = {}
  for _, c in ipairs(w.calls) do
    if c[1] == "markToCoalition" then
      live[c[2]] = c[3]
    end
    if c[1] == "circleToAll" then
      live[c[3]] = "circle"
    end
    if c[1] == "removeMark" then
      live[c[2]] = nil
    end
  end
  return live
end

local function allDrawnIds(w)
  local ids = {}
  for _, c in ipairs(w.calls) do
    if c[1] == "markToCoalition" then
      ids[#ids + 1] = c[2]
    end
    if c[1] == "circleToAll" then
      ids[#ids + 1] = c[3]
    end
  end
  return ids
end

describe("DMS.Intel", function()
  it("reveals enemies in range with line of sight as circle + text marks with unique ids >= 50000", function()
    withWorld(intelCfg(), function(w)
      setup(w)
      DMS.Intel.start()
      w.visible = false
      w.clock.advance(5)
      eq(#w.callsOf("markToCoalition"), 0, "terrain masks contact")
      w.visible = true
      w.clock.advance(5)
      local m = w.callsOf("markToCoalition")
      local c = w.callsOf("circleToAll")
      eq(#m, 1)
      eq(#c, 1)
      eq(c[1][2], 2, "drawn for player coalition")
      eq(m[1][5], 2)
      assert(m[1][2] >= 50000 and c[1][3] >= 50000, "ids start at 50000")
      assert(m[1][2] ~= c[1][3], "unique ids")
      assert(string.find(m[1][3], "Osa 9A33 ln x2", 1, true), m[1][3])
      eq(m[1][4].x, 4050, "centroid x")
      assert(DMS.Intel.contact("SAM1") and not DMS.Intel.contact("FAR"), "far group stays hidden")
    end)
  end)

  it("refreshes moved contacts, stales them as last known and removes them later", function()
    withWorld(intelCfg(), function(w)
      setup(w)
      DMS.Intel.start()
      w.clock.advance(5)
      local first = liveIds(w)
      w.units["SAM1-1"].pos = { x = 6000, y = 0, z = 0 }
      w.units["SAM1-2"].pos = { x = 6000, y = 0, z = 200 }
      w.clock.advance(15)
      local now = liveIds(w)
      for id in pairs(first) do
        assert(now[id] == nil, "old mark " .. id .. " removed on refresh")
      end
      local n, label = 0, nil
      for _, v in pairs(now) do
        n = n + 1
        if v ~= "circle" then
          label = v
        end
      end
      eq(n, 2, "one circle + one text after refresh")
      assert(not string.find(label, "last known", 1, true))
      local last = w.callsOf("markToCoalition")
      eq(last[#last][4].x, 6000, "redrawn at new position")
      -- break contact: player flies away
      w.units["Viper1-1"].pos = { x = -50000, y = 0, z = 0 }
      w.clock.advance(130)
      now = liveIds(w)
      n, label = 0, nil
      for _, v in pairs(now) do
        n = n + 1
        if v ~= "circle" then
          label = v
        end
      end
      eq(n, 2)
      assert(label and string.find(label, "(last known)", 1, true), tostring(label))
      assert(DMS.Intel.contact("SAM1").stale, "stale flag")
      w.clock.advance(300)
      n = 0
      for _ in pairs(liveIds(w)) do
        n = n + 1
      end
      eq(n, 0, "removed after removeSec")
      eq(DMS.Intel.contact("SAM1"), nil)
      -- ids never reused
      local seen = {}
      for _, id in ipairs(allDrawnIds(w)) do
        assert(not seen[id], "mark id reused: " .. id)
        seen[id] = true
      end
    end)
  end)

  it("removes marks on group.dead and reveals shooters / engaged targets via events", function()
    withWorld(intelCfg(), function(w)
      setup(w)
      DMS.Intel.start()
      DMS.Bus.emit("unit.shot", { initiator = "FAR-1", initiatorGroup = "FAR", coalition = 1, weapon = "x" })
      assert(DMS.Intel.contact("FAR"), "launch reveals shooter")
      w.addGroup("TRUCKS", 1, { { name = "TRUCKS-1", x = 90000, z = 0 } })
      DMS.Bus.emit("unit.hit", {
        target = "TRUCKS-1",
        targetGroup = "TRUCKS",
        targetCoalition = 1,
        initiator = "Viper1-1",
        initiatorGroup = "Viper1",
      })
      assert(DMS.Intel.contact("TRUCKS"), "engaged target revealed")
      w.clear()
      DMS.Bus.emit("group.dead", { group = "FAR", coalition = 1 })
      eq(DMS.Intel.contact("FAR"), nil)
      eq(#w.callsOf("removeMark"), 2, "circle + text removed")
    end)
  end)

  it("reveals groups from player-side sensors (getDetectedTargets)", function()
    withWorld(intelCfg(), function(w)
      setup(w)
      DMS.Intel.start()
      w.detected["Viper1"] = { { object = w.units["FAR-1"] } }
      w.clock.advance(5)
      assert(DMS.Intel.contact("FAR"), "sensor contact")
    end)
  end)

  it("accumulates BDA per type and reports it", function()
    withWorld(intelCfg(), function(w)
      setup(w)
      DMS.Intel.start()
      DMS.Bus.emit("unit.dead", { unit = "a", group = "SAM1", coalition = 1, typeName = "Osa 9A33 ln" })
      DMS.Bus.emit("unit.dead", { unit = "b", group = "SAM1", coalition = 1, typeName = "Osa 9A33 ln" })
      DMS.Bus.emit("unit.dead", { unit = "c", group = "FAR", coalition = 1, typeName = "T-72B" })
      DMS.Bus.emit("unit.dead", { unit = "d", group = "Viper1", coalition = 2, typeName = "F-16C_50" })
      local _, total = DMS.Intel.kills()
      eq(total, 3, "friendly losses not counted")
      local r = DMS.Intel.report(11)
      assert(string.find(r, "3 enemy units", 1, true), r)
      assert(string.find(r, "Osa 9A33 ln x2", 1, true), r)
      assert(string.find(r, "T-72B x1", 1, true), r)
      eq(w.callsOf("outTextForGroup")[1][2], 11)
    end)
  end)

  it("draws narrative marks for groups, zones and points", function()
    withWorld(intelCfg(), function(w)
      setup(w)
      DMS.Intel.start()
      local h1 = DMS.Intel.mark("group:FAR")
      assert(h1 and DMS.Intel.contact("FAR"), "group mark reveals contact")
      local h2 = DMS.Intel.mark({ type = "circle", at = "zone:town", text = "Town" })
      local h3 = DMS.Intel.mark("zone:ridge")
      local h4 = DMS.Intel.mark({ type = "point", at = { x = 10, y = 20 }, text = "IP" })
      assert(h2 and h3 and h4, "handles")
      local m = w.callsOf("markToCoalition")
      eq(m[2][3], "Town")
      eq(m[2][4].x, 1000)
      eq(m[2][4].z, 2000, "vec2 y maps to vec3 z")
      eq(m[4][4].z, 20)
      eq(#w.callsOf("circleToAll"), 3, "point mark has no circle")
      eq(DMS.Intel.mark("zone:nope"), nil)
      assert(DMS.Intel.removeMarkHandle(h2))
      eq(#w.callsOf("removeMark"), 2)
    end)
  end)

  it("survives 200 random seeds", function()
    for seed = 1, 200 do
      math.randomseed(seed)
      local cfg = intelCfg({ seed = seed })
      cfg.intel = {
        revealRadiusM = math.random(1000, 20000),
        markRefreshSec = math.random(5, 30),
        staleSec = math.random(20, 200),
        scanSec = math.random(1, 10),
      }
      withWorld(cfg, function(w)
        for i = 1, 3 do
          w.addGroup("P" .. i, 2, { { name = "P" .. i .. "-1", x = 0, z = 0, player = "p" .. i } })
        end
        for i = 1, 6 do
          local units = {}
          for j = 1, math.random(1, 4) do
            units[j] = { x = math.random(-30000, 30000), z = math.random(-30000, 30000) }
          end
          w.addGroup("E" .. i, 1, units)
        end
        DMS.Intel.start()
        for _ = 1, 50 do
          local r = math.random()
          local g = "E" .. math.random(1, 6)
          if r < 0.1 then
            DMS.Bus.emit("unit.dead", { unit = g .. "-1", group = g, coalition = 1, typeName = "T" })
          elseif r < 0.15 then
            w.groups[g].units[1].alive = false
            DMS.Bus.emit("group.dead", { group = g, coalition = 1 })
          elseif r < 0.25 then
            DMS.Bus.emit("unit.shot", { initiatorGroup = g, coalition = 1 })
          elseif r < 0.3 then
            DMS.Intel.mark(math.random() < 0.5 and ("group:" .. g) or "zone:town")
          elseif r < 0.6 then
            local u = w.units["P" .. math.random(1, 3) .. "-1"]
            u.pos = { x = math.random(-30000, 30000), y = 0, z = math.random(-30000, 30000) }
          elseif r < 0.7 then
            w.visible = not w.visible
          end
          w.clock.advance(math.random(1, 30))
        end
        DMS.Intel.report()
        local seen = {}
        for _, id in ipairs(allDrawnIds(w)) do
          assert(id >= 50000 and not seen[id], "bad/reused id " .. id)
          seen[id] = true
        end
      end)
    end
  end)
end)

-- Replay the "[DMS][Intel] MARK add|remove" log lines -> id -> {kind, coal, text}; asserts the
-- protocol (no add of a live id, no remove of an unknown id, every field parseable).
local function replayMarkLog(w)
  local live, adds, removes = {}, 0, 0
  for _, line in ipairs(w.infos) do
    local op, id, rest = string.match(line, "^%[DMS%]%[Intel%] MARK (%a+) id=(%d+) (.*)$")
    if op == "add" then
      id = tonumber(id)
      local kind, coal, x, z, r, t, owner, text =
        string.match(rest, "^kind=(%a+) coal=(%-?%d) x=(%-?%d+) z=(%-?%d+) r=(%S+) t=([%d%.]+) owner=(%S+) text=(.*)$")
      assert(kind and r and t, "unparseable MARK add: " .. line)
      assert(live[id] == nil, "MARK add of a live id " .. id)
      live[id] = { kind = kind, coal = tonumber(coal), text = text, x = tonumber(x), z = tonumber(z), owner = owner }
      adds = adds + 1
    elseif op == "remove" then
      id = tonumber(id)
      local kind, t, why = string.match(rest, "^kind=(%a+) t=([%d%.]+) why=(.*)$")
      assert(kind and t and why ~= "", "unparseable MARK remove: " .. line)
      assert(live[id], "MARK remove of an unknown id " .. id)
      live[id] = nil
      removes = removes + 1
    end
  end
  return live, adds, removes
end

local function keys(t)
  local n = 0
  for _ in pairs(t) do
    n = n + 1
  end
  return n
end

local function sameIds(a, b, msg)
  for id in pairs(a) do
    assert(b[id] ~= nil, (msg or "") .. ": id " .. id .. " only in first set")
  end
  for id in pairs(b) do
    assert(a[id] ~= nil, (msg or "") .. ": id " .. id .. " only in second set")
  end
end

describe("DMS.Intel F10 mark bookkeeping", function()
  it("logs one parseable MARK line per add/remove, matching DCS calls and liveMarks()", function()
    local cfg = intelCfg()
    cfg.debug = true
    withWorld(cfg, function(w)
      setup(w)
      DMS.Intel.start()
      w.clock.advance(5)
      local live, adds = replayMarkLog(w)
      eq(adds, 2, "circle + text")
      sameIds(live, liveIds(w), "log vs DCS")
      sameIds(live, DMS.Intel.liveMarks(), "log vs liveMarks")
      for _, m in pairs(live) do
        eq(m.coal, 2)
        eq(m.owner, "contact:SAM1")
        assert(string.find(m.text, "Osa 9A33 ln x2", 1, true), m.text)
      end
      local st = DMS.Intel.markStats()
      eq(st.added, 2)
      eq(st.live, 2)
      -- death removes both marks with a reason
      for _, u in ipairs(w.groups.SAM1.units) do
        u.alive = false
      end
      DMS.Bus.emit("group.dead", { group = "SAM1", coalition = 1 })
      live = replayMarkLog(w)
      eq(keys(live), 0, "no marks after group.dead")
      eq(keys(liveIds(w)), 0)
      local why = 0
      for _, line in ipairs(w.infos) do
        if string.find(line, "MARK remove", 1, true) and string.find(line, "why=destroyed", 1, true) then
          why = why + 1
        end
      end
      eq(why, 2, "both removals say why=destroyed")
      eq(DMS.Intel.markStats().removed, 2)
    end)
  end)

  it("removes every mark it drew on stop and never reuses ids after a restart", function()
    local cfg = intelCfg()
    cfg.debug = true
    withWorld(cfg, function(w)
      setup(w)
      DMS.Intel.start()
      w.clock.advance(5)
      local h = DMS.Intel.mark({ type = "circle", at = "zone:town", text = "Town" })
      assert(h)
      eq(keys(liveIds(w)), 4)
      DMS.Intel.stop()
      eq(keys(liveIds(w)), 0, "stop clears the map")
      eq(keys(DMS.Intel.liveMarks()), 0)
      DMS.Intel.start()
      w.clock.advance(5)
      local seen = {}
      for _, id in ipairs(allDrawnIds(w)) do
        assert(not seen[id], "id reused after restart: " .. id)
        seen[id] = true
      end
      sameIds(replayMarkLog(w), liveIds(w), "log vs DCS after restart")
    end)
  end)

  it("starts ids above marks already on the map", function()
    withWorld(intelCfg(), function(w)
      setup(w)
      local saved = world.getMarkPanels
      world.getMarkPanels = function()
        return { { idx = 3 }, { idx = 70000 } }
      end
      local ok, err = pcall(function()
        DMS.Intel.start()
        w.clock.advance(5)
        for _, id in ipairs(allDrawnIds(w)) do
          assert(id > 70000, "id " .. id .. " collides with existing marks")
        end
      end)
      world.getMarkPanels = saved
      assert(ok, err)
    end)
  end)

  it("never follows player marks (~251,000,000+) or non-script panels outside our band", function()
    withWorld(intelCfg(), function(w)
      setup(w)
      local saved = world.getMarkPanels
      world.getMarkPanels = function()
        return {
          { idx = 60000 }, -- ours / script-made, in band: bump past it
          { idx = 251000003, initiator = { player = true } }, -- player mark
          { idx = 251000004 }, -- player range even without an initiator
          { idx = 20000000, initiator = { player = true } }, -- above the band, not script-made
        }
      end
      local ok, err = pcall(function()
        DMS.Intel.start()
        w.clock.advance(5)
        local ids = allDrawnIds(w)
        assert(#ids > 0, "drew marks")
        for _, id in ipairs(ids) do
          assert(id > 60000, "id " .. id .. " collides with an in-band panel")
          assert(id < DMS.Intel.FIRST_MARK_ID + DMS.Intel.MARK_ID_BAND, "id " .. id .. " left our band")
        end
      end)
      world.getMarkPanels = saved
      assert(ok, err)
    end)
  end)

  it("never reuses a mark id, even after removeMark", function()
    withWorld(intelCfg(), function(w)
      setup(w)
      DMS.Intel.start()
      local h = DMS.Intel.mark({ type = "circle", at = "zone:town", text = "Town" })
      w.clock.advance(1)
      DMS.Intel.removeMarkHandle(h)
      DMS.Intel.mark({ type = "circle", at = "zone:town", text = "Town again" })
      w.clock.advance(1)
      local seen = {}
      for _, id in ipairs(allDrawnIds(w)) do
        assert(not seen[id], "id reused: " .. id)
        seen[id] = true
      end
    end)
  end)

  it("honours the mark spec coalition and returns a stable handle for group marks", function()
    withWorld(intelCfg(), function(w)
      setup(w)
      DMS.Intel.start()
      local h = DMS.Intel.mark({ type = "circle", at = "zone:town", text = "Red Town", coalition = 1 })
      assert(h)
      local m = w.callsOf("markToCoalition")
      eq(m[1][5], 1, "text mark for coalition 1")
      eq(w.callsOf("circleToAll")[1][2], 1, "circle for coalition 1")
      local gh = DMS.Intel.mark({ at = "group:FAR", text = "Armour" })
      assert(gh, "group handle")
      local c = DMS.Intel.contact("FAR")
      local before = c.textId
      w.units["FAR-1"].pos = { x = 61000, y = 0, z = 0 }
      w.units["Viper1-1"].pos = { x = 59000, y = 0, z = 0 }
      w.clock.advance(20)
      assert(c.textId ~= before, "contact redrawn with new ids")
      assert(DMS.Intel.removeMarkHandle(gh), "stable handle still removes the contact")
      eq(DMS.Intel.contact("FAR"), nil)
      eq(DMS.Intel.removeMarkHandle(gh), false, "handle is single-use")
    end)
  end)

  it("reuses one handle per group and forgets the contact only if the mark created it", function()
    withWorld(intelCfg(), function(w)
      setup(w)
      DMS.Intel.start()
      w.clock.advance(5) -- SAM1 (4 km) detected by the scan
      assert(DMS.Intel.contact("SAM1"), "SAM1 detected")
      local h1 = DMS.Intel.mark({ at = "group:SAM1", text = "Target" })
      local h2 = DMS.Intel.mark("group:SAM1")
      assert(h1, "group handle")
      eq(h2, h1, "same group -> same handle")
      eq(DMS.Intel.contact("SAM1").label, "Target")
      eq(DMS.Intel.removeMarkHandle(h1), true, "handle removed")
      assert(DMS.Intel.contact("SAM1"), "independently detected contact is kept")
      eq(DMS.Intel.contact("SAM1").label, nil, "mark label undone")
      eq(DMS.Intel.removeMarkHandle(h1), false, "handle is single-use")
      -- FAR (60 km) is only known through the mark: removing the mark forgets it
      local hf = DMS.Intel.mark("group:FAR")
      assert(DMS.Intel.contact("FAR"))
      eq(DMS.Intel.removeMarkHandle(hf), true)
      eq(DMS.Intel.contact("FAR"), nil)
    end)
  end)

  it("returns true for a group handle whose contact is already gone", function()
    withWorld(intelCfg(), function(w)
      setup(w)
      DMS.Intel.start()
      local h = DMS.Intel.mark("group:FAR")
      DMS.Intel.forget("FAR", "test")
      eq(DMS.Intel.removeMarkHandle(h), true)
    end)
  end)

  it("keeps marks drawn before the first start and wipes them only on a restart", function()
    withWorld(intelCfg(), function(w)
      setup(w)
      local h = DMS.Intel.mark("zone:town")
      assert(h, "pre-start mark drawn")
      local n = DMS.Intel.markStats().live
      DMS.Intel.start()
      eq(DMS.Intel.markStats().live, n, "first start keeps earlier beat marks")
      assert(DMS.Intel.liveMarks()[h], "text mark still live")
      eq(DMS.Intel.removeMarkHandle(h), true, "handle survived the start")
      local h2 = DMS.Intel.mark("zone:town")
      assert(h2)
      DMS.Intel.start() -- restart
      eq(DMS.Intel.liveMarks()[h2], nil, "restart removes marks it drew")
    end)
  end)

  it("does not track a mark DCS rejected", function()
    withWorld(intelCfg(), function(w)
      setup(w)
      w.trigger.action.markToCoalition = function()
        error("boom")
      end
      DMS.Intel.start()
      w.clock.advance(5)
      local st = DMS.Intel.markStats()
      eq(st.failed, 1)
      eq(st.live, 1, "only the circle is live")
      for _, m in pairs(DMS.Intel.liveMarks()) do
        eq(m.kind, "circle")
      end
      assert(#w.errors == 1 and string.find(w.errors[1], "MARK add failed", 1, true), tostring(w.errors[1]))
      w.errors = {}
    end)
  end)

  it("keeps log, DCS calls and liveMarks() in sync over 100 random seeds", function()
    for seed = 1, 100 do
      math.randomseed(seed * 7919)
      local cfg = intelCfg({ seed = seed, debug = true })
      cfg.intel = {
        revealRadiusM = math.random(1000, 20000),
        markRefreshSec = math.random(5, 30),
        staleSec = math.random(20, 200),
        scanSec = math.random(1, 10),
      }
      withWorld(cfg, function(w)
        for i = 1, 2 do
          w.addGroup("P" .. i, 2, { { name = "P" .. i .. "-1", x = 0, z = 0, player = "p" .. i } })
        end
        for i = 1, 5 do
          local units = {}
          for j = 1, math.random(1, 3) do
            units[j] = { x = math.random(-20000, 20000), z = math.random(-20000, 20000) }
          end
          w.addGroup("E" .. i, 1, units)
        end
        local st0 = DMS.Intel.markStats() -- counters are mission-wide (they survive restarts)
        DMS.Intel.start()
        local handles = {}
        for _ = 1, 40 do
          local r = math.random()
          local g = "E" .. math.random(1, 5)
          if r < 0.1 then
            for _, u in ipairs(w.groups[g].units) do
              u.alive = false
            end
            DMS.Bus.emit("group.dead", { group = g, coalition = 1 })
          elseif r < 0.2 then
            local h = DMS.Intel.mark(math.random() < 0.5 and ("group:" .. g) or "zone:town")
            if h then
              handles[#handles + 1] = h
            end
          elseif r < 0.25 and #handles > 0 then
            DMS.Intel.removeMarkHandle(table.remove(handles, math.random(1, #handles)))
          elseif r < 0.6 then
            local u = w.units["P" .. math.random(1, 2) .. "-1"]
            u.pos = { x = math.random(-20000, 20000), y = 0, z = math.random(-20000, 20000) }
          elseif r < 0.7 then
            w.visible = not w.visible
          end
          w.clock.advance(math.random(1, 30))
          local fromLog = replayMarkLog(w)
          sameIds(fromLog, liveIds(w), "seed " .. seed .. " log vs DCS")
          sameIds(fromLog, DMS.Intel.liveMarks(), "seed " .. seed .. " log vs liveMarks")
        end
        local st = DMS.Intel.markStats()
        local _, adds, removes = replayMarkLog(w)
        eq(st.added - st0.added, adds, "added count")
        eq(st.removed - st0.removed, removes, "removed count")
        for name, c in pairs(DMS.Intel.contacts()) do
          assert(DMS.Intel.liveMarks()[c.textId], "contact " .. name .. " text mark live")
        end
        DMS.Intel.stop()
        eq(keys(liveIds(w)), 0, "seed " .. seed .. ": stop clears the map")
      end)
    end
  end)
end)
