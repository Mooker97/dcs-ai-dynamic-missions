-- test_spec.lua: DMS.Test (lua/src/dms/test.lua): player proxy + built-in checks, full runtime.

local function tests(level)
  local out = {}
  for _, l in ipairs(MOCK.log) do
    local st, name, detail = string.match(l.msg, "^%[DMS%.TEST%] (%u+) (%S+) ?(.*)$")
    if st and (level == nil or st == level) then
      out[#out + 1] = { status = st, name = name, detail = detail }
    end
  end
  return out
end

local function byName(name)
  for _, t in ipairs(tests()) do
    if t.name == name and t.status ~= "INFO" then
      return t
    end
  end
  return nil
end

local function config(checks, extra)
  local c = {
    seed = 7,
    missionId = "t01",
    players = { coalition = 2 },
    budgets = { maxActiveGround = 100, maxActiveAir = 10, spawnsPerMin = 60 },
    director = { enabled = false },
    templates = { truck = { country = "RUSSIA", category = "ground", units = { { type = "Ural-375" } } } },
    zones = {
      gate = { kind = "circle", x = 10000, y = 0, radius = 1000 },
      box = { kind = "circle", x = 30000, y = 0, radius = 2000 },
    },
    pools = { trucks = { members = { { tpl = "truck" } }, pick = 1, zones = { "box" } } },
    encounters = {
      {
        id = "near_box",
        kind = "pool",
        pool = "trucks",
        chance = 100,
        gated = false,
        trigger = { type = "proximity", zone = "box", radiusM = 12000, checkSec = 1 },
      },
    },
    beats = {
      { id = "start", when = { event = "player.spawned", playersOnly = true }, text = "go", speaker = "ops" },
      {
        id = "at_gate",
        when = { event = "zone.entered", zone = "gate", playersOnly = true },
        text = "gate",
        speaker = "ops",
      },
      {
        id = "home",
        when = { event = "unit.landed", playersOnly = true },
        text = "home",
        speaker = "ops",
        effects = { endMission = "success" },
      },
    },
    narrative = { minGapSec = 1, zonePollSec = 1 },
    test = { enabled = true, playerProxy = "Proxy Dusty 1", minutes = 10, checks = checks },
  }
  for k, v in pairs(extra or {}) do
    c[k] = v
  end
  return c
end

local function proxy(x, y)
  MOCK.addGroup({
    name = "Proxy Dusty 1",
    coalition = 2,
    country = "USA",
    category = "helicopter",
    units = { { name = "Proxy Dusty 1-1", type = "AH-64D_BLK_II", x = x or 0, y = y or 0, alt = 100 } },
  })
end

describe("DMS.Test player proxy", function()
  it("registers the proxy as the player for bus, spawner, narrative and encounters", function()
    proxy(0, 0)
    DMS_CONFIG = config({})
    local spawned = {}
    DMS.Bus.on("player.spawned", function(ev)
      spawned[#spawned + 1] = ev
    end)
    DMS.boot()
    MOCK.advance(2)
    assert.are.equal(1, #spawned)
    assert.are.equal("Proxy Dusty 1-1", spawned[1].unit)
    assert.is_truthy(DMS.Bus._players["Proxy Dusty 1-1"])
    local pu = DMS.Spawner.playerUnits()
    assert.are.equal(1, #pu)
    assert.are.equal(2, pu[1].coalition)
    -- proxy options: immortal + weapons hold + no reaction
    local cmds = MOCK.callsTo("Controller.setCommand", "Proxy Dusty 1")
    assert.is_true(#cmds >= 1)
    assert.are.equal("SetImmortal", cmds[1].args[1].id)
    -- zone beat fires for the AI proxy (playersOnly)
    MOCK.advance(12)
    MOCK.moveUnit("Proxy Dusty 1-1", 10000, 0)
    MOCK.advance(5)
    assert.are.equal(1, DMS.Narrative.firedCount("at_gate"))
    -- proximity encounter sees the proxy
    MOCK.moveUnit("Proxy Dusty 1-1", 20000, 0)
    MOCK.advance(5)
    assert.is_truthy(DMS.Encounters.get("near_box").spawnedAny)
  end)

  it("is inert without DMS_CONFIG.test", function()
    proxy(0, 0)
    DMS_CONFIG = config({})
    DMS_CONFIG.test = nil
    DMS.boot()
    MOCK.advance(30)
    assert.is_nil(next(DMS.Bus._players))
    assert.are.equal(0, #tests())
  end)

  it("fails proxy_present when the proxy group never appears", function()
    DMS_CONFIG = config({})
    DMS.boot()
    MOCK.advance(40)
    local t = byName("proxy_present")
    assert.is_truthy(t)
    assert.are.equal("FAIL", t.status)
  end)
end)

describe("DMS.Test checks", function()
  it("runs the default check kinds to PASS and logs DONE", function()
    proxy(0, 0)
    DMS_CONFIG = config({
      { kind = "booted", name = "runtime_booted" },
      { kind = "spawns", name = "spawns_on_land", min = 1 },
      { kind = "beats_in_order", name = "spine", beats = { "start", "at_gate", "home" } },
      { kind = "comms", name = "comms_queued", min = 3 },
      { kind = "encounter", name = "encounter_near_box", id = "near_box" },
      { kind = "convoy_halt", name = "convoy_halt_on_hit" },
      { kind = "outcome", name = "outcome_end", result = "success" },
    })
    DMS.boot()
    MOCK.advance(15)
    MOCK.moveUnit("Proxy Dusty 1-1", 10000, 0)
    MOCK.advance(10)
    MOCK.moveUnit("Proxy Dusty 1-1", 20000, 0)
    MOCK.advance(10)
    MOCK.fireEvent({ id = world.event.S_EVENT_LAND, initiator = Unit.getByName("Proxy Dusty 1-1") })
    MOCK.advance(30)
    for _, n in ipairs({
      "runtime_booted",
      "spawns_on_land",
      "spine",
      "comms_queued",
      "encounter_near_box",
      "convoy_halt_on_hit",
      "outcome_end",
    }) do
      local t = byName(n)
      assert.is_truthy(t, "missing " .. n)
      assert.are.equal("PASS", t.status, n .. ": " .. tostring(t and t.detail))
    end
    assert.is_true((MOCK.logContains("%[DMS%.TEST%] DONE 7/7")))
  end)

  it("fails spawns_on_land at once when a ground unit stands on water", function()
    proxy(0, 0)
    MOCK.waterAreas = { { x = 30000, y = 0, radius = 50000 } }
    DMS_CONFIG = config({ { kind = "spawns", name = "spawns_on_land" } })
    DMS.boot()
    -- bypass the spawner's own land check to simulate a bad spawn reaching DCS
    DMS.Bus.emit("spawner.spawned", { group = "Proxy Dusty 1", category = "ground" })
    MOCK.advance(5)
    local t = byName("spawns_on_land")
    assert.are.equal("FAIL", t.status)
    assert.is_truthy(string.find(t.detail, "on water", 1, true))
  end)

  it("fails beats_in_order when the spine fires out of order, and times out the rest at the end", function()
    proxy(0, 0)
    DMS_CONFIG = config({
      { kind = "beats_in_order", name = "spine", beats = { "at_gate", "start" } },
      { kind = "beat", name = "never", id = "home" },
    })
    DMS.boot()
    MOCK.advance(15)
    MOCK.moveUnit("Proxy Dusty 1-1", 10000, 0)
    MOCK.advance(10)
    assert.are.equal("FAIL", byName("spine").status)
    MOCK.advance(600)
    local t = byName("never")
    assert.are.equal("FAIL", t.status)
    assert.is_truthy(string.find(t.detail, "timeout", 1, true))
    assert.is_true((MOCK.logContains("%[DMS%.TEST%] DONE 0/2")))
  end)

  it("convoy_halt fails when a hit convoy does not halt", function()
    proxy(0, 0)
    DMS_CONFIG = config({ { kind = "convoy_halt", name = "convoy_halt_on_hit" } })
    DMS_CONFIG.encounters = { { id = "conv", kind = "convoy", group = "Conv", trigger = { type = "manual" } } }
    MOCK.addGroup({
      name = "Conv",
      coalition = 1,
      category = "ground",
      units = { { name = "Conv-1", x = 5000, y = 0 } },
    })
    DMS.boot()
    DMS.Encounters.trigger("conv", true)
    DMS.Ground.haltOnHit = DMS.Ground.haltOnHit -- real reaction in place
    MOCK.advance(3)
    -- simulate the bus seeing a hit without the ground reaction (as if haltOnHit were missing)
    DMS.Encounters.get("conv").handles[1].stop()
    MOCK.hitUnit("Conv-1", { damage = 0 })
    MOCK.advance(600)
    local t = byName("convoy_halt_on_hit")
    assert.are.equal("FAIL", t.status)
  end)
end)

describe("DMS.Test optional encounters", function()
  it("never fails optional encounters, names spawned group siblings, and does not hold the run", function()
    proxy(0, 0)
    DMS_CONFIG = config({
      { kind = "booted", name = "runtime_booted" },
      { kind = "encounter", name = "encounter_near_box", id = "near_box", optional = true, group = "route_set" },
      { kind = "encounter", name = "encounter_far_box", id = "far_box", optional = true, group = "route_set" },
      { kind = "encounter", name = "encounter_lonely", id = "lonely", optional = true },
      { kind = "encounter", name = "encounter_required", id = "near_box" },
    })
    DMS_CONFIG.encounters[2] = {
      id = "far_box",
      kind = "pool",
      pool = "trucks",
      gated = false,
      trigger = { type = "manual" },
    }
    DMS_CONFIG.encounters[3] = {
      id = "lonely",
      kind = "pool",
      pool = "trucks",
      gated = false,
      trigger = { type = "manual" },
    }
    DMS.boot()
    MOCK.advance(15)
    MOCK.moveUnit("Proxy Dusty 1-1", 20000, 0)
    MOCK.advance(10)
    -- every required check resolved; the optional ones do not hold the run open
    MOCK.advance(10)
    assert.is_true((MOCK.logContains("%[DMS%.TEST%] DONE 3/3")))
    assert.are.equal("PASS", byName("encounter_near_box").status)
    assert.are.equal("PASS", byName("encounter_required").status)
    assert.is_nil(byName("encounter_far_box"))
    local far, lonely
    for _, t in ipairs(tests("INFO")) do
      if t.name == "encounter_far_box" then
        far = t
      elseif t.name == "encounter_lonely" then
        lonely = t
      end
    end
    assert.is_truthy(far)
    assert.is_truthy(string.find(far.detail, "optional encounter far_box not spawned", 1, true))
    assert.is_truthy(string.find(far.detail, "group route_set: near_box spawned", 1, true))
    assert.is_truthy(lonely)
    assert.are.equal("optional encounter lonely not spawned", lonely.detail)
    assert.are.equal(0, #tests("FAIL"))
  end)
end)

describe("DMS.Test outcome", function()
  local function failingHome()
    local c = config({ { kind = "outcome", name = "outcome_end" } })
    c.beats[3].effects = { endMission = "failure" }
    return c
  end

  it("passes on any mission end and reports the result", function()
    proxy(0, 0)
    DMS_CONFIG = failingHome()
    DMS.boot()
    MOCK.advance(15)
    MOCK.fireEvent({ id = world.event.S_EVENT_LAND, initiator = Unit.getByName("Proxy Dusty 1-1") })
    MOCK.advance(20)
    local t = byName("outcome_end")
    assert.are.equal("PASS", t.status)
    assert.are.equal("end result=failure", t.detail)
  end)

  it("fails when requireResult names a different result", function()
    proxy(0, 0)
    DMS_CONFIG = failingHome()
    DMS_CONFIG.test.checks[1].requireResult = "success"
    DMS.boot()
    MOCK.advance(15)
    MOCK.fireEvent({ id = world.event.S_EVENT_LAND, initiator = Unit.getByName("Proxy Dusty 1-1") })
    MOCK.advance(20)
    local t = byName("outcome_end")
    assert.are.equal("FAIL", t.status)
    assert.is_truthy(string.find(t.detail, "required success", 1, true))
  end)
end)

describe("DMS.Test proxy loiter", function()
  local function loiterConfig(returnSec)
    -- the pending beat check keeps the run open (DONE ends the loiter too)
    local c = config({ { kind = "booted", name = "runtime_booted" }, { kind = "beat", name = "home", id = "home" } })
    c.beats[#c.beats + 1] = {
      id = "rtb_call",
      when = { event = "flag", flag = "convoy_resolved" },
      text = "rtb",
      speaker = "ops",
    }
    c.test.loiter = {
      zone = "gate",
      x = 10000,
      y = 0,
      radiusM = 1000,
      altM = 120,
      altType = "RADIO",
      speedMps = 41.7,
      startBeat = "at_gate",
      untilBeat = "rtb_call",
      returnSec = returnSec or 120,
    }
    return c
  end

  local function info(prefix)
    for _, t in ipairs(tests("INFO")) do
      if t.name == "loiter" and string.sub(t.detail, 1, #prefix) == prefix then
        return t
      end
    end
    return nil
  end

  it("orbits at the loiter zone until the RTB beat fires, then resumes the route", function()
    proxy(0, 0)
    DMS_CONFIG = loiterConfig()
    DMS.boot()
    MOCK.advance(15)
    assert.are.equal("wait", DMS.Test._loiter.state)
    assert.are.equal(0, #MOCK.callsTo("Controller.pushTask", "Proxy Dusty 1"))
    MOCK.moveUnit("Proxy Dusty 1-1", 10000, 0)
    MOCK.advance(15)
    assert.are.equal("orbit", DMS.Test._loiter.state)
    local pushed = MOCK.callsTo("Controller.pushTask", "Proxy Dusty 1")
    assert.are.equal(1, #pushed)
    local task = pushed[1].args[1]
    assert.are.equal("Orbit", task.id)
    assert.are.equal("Circle", task.params.pattern)
    assert.are.equal(10000, task.params.point.x)
    assert.is_true(task.params.altitude >= 120) -- RADIO: AGL over the centre
    assert.is_truthy(info("start gate ("))
    MOCK.advance(60)
    assert.are.equal("orbit", DMS.Test._loiter.state)
    DMS.Narrative.setFlag("convoy_resolved")
    MOCK.advance(15)
    assert.are.equal("done", DMS.Test._loiter.state)
    assert.are.equal(1, #MOCK.callsTo("Controller.popTask", "Proxy Dusty 1"))
    assert.is_truthy(info("stop gate (rtb_call fired)"))
    assert.is_true((MOCK.logContains("proxy loiter stop over gate")))
  end)

  it("stops at the return-flight budget when the RTB beat never fires", function()
    proxy(0, 0)
    DMS_CONFIG = loiterConfig(300) -- minutes = 10: endAt 585 s, loiter until 285 s
    DMS.boot()
    MOCK.advance(15)
    MOCK.moveUnit("Proxy Dusty 1-1", 10000, 0)
    MOCK.advance(15)
    assert.are.equal("orbit", DMS.Test._loiter.state)
    MOCK.advance(300)
    assert.are.equal("done", DMS.Test._loiter.state)
    assert.are.equal(1, #MOCK.callsTo("Controller.popTask", "Proxy Dusty 1"))
    assert.is_truthy(info("stop gate (timeout"))
  end)

  it("skips the loiter when the RTB beat fired before the zone", function()
    proxy(0, 0)
    DMS_CONFIG = loiterConfig()
    DMS.boot()
    MOCK.advance(5)
    DMS.Narrative.setFlag("convoy_resolved")
    MOCK.advance(15)
    assert.are.equal("done", DMS.Test._loiter.state)
    assert.are.equal(0, #MOCK.callsTo("Controller.pushTask", "Proxy Dusty 1"))
    assert.is_truthy(info("skip gate (rtb_call fired before the loiter zone)"))
  end)
end)

-- ---------------------------------------------------------------- F10 marks, fog, comms checks

local function finalChecks(extra)
  local checks = {
    { kind = "booted", name = "runtime_booted" },
    { kind = "beat", name = "home", id = "home" },
  }
  for _, c in ipairs(extra) do
    checks[#checks + 1] = c
  end
  local c = config(checks)
  c.debug = true
  c.intel = { fogOfWar = true, revealRadiusM = 5000, markRefreshSec = 15, staleSec = 120, scanSec = 5 }
  c.beats[1].guaranteed = true
  c.beats[2].guaranteed = true
  c.beats[3].guaranteed = true
  return c
end

-- A pre-placed enemy group Intel can reveal (runtime spawns never appear near the proxy).
local function enemy()
  MOCK.addGroup({
    name = "Red Armour",
    coalition = 1,
    country = "RUSSIA",
    category = "ground",
    units = {
      { name = "Red Armour-1", type = "T-72B", x = 20000, y = 0 },
      { name = "Red Armour-2", x = 20050, y = 30 },
    },
  })
end

-- Fly the proxy past the enemy armour (revealed by Intel) and land: every beat fires and speaks.
local function flyAndLand(midway)
  enemy()
  DMS.boot()
  MOCK.advance(15)
  MOCK.moveUnit("Proxy Dusty 1-1", 10000, 0)
  MOCK.advance(10)
  MOCK.moveUnit("Proxy Dusty 1-1", 17000, 0)
  MOCK.advance(20)
  if midway then
    midway()
  end
  MOCK.moveUnit("Proxy Dusty 1-1", 27000, 0)
  MOCK.advance(20)
  MOCK.fireEvent({ id = world.event.S_EVENT_LAND, initiator = Unit.getByName("Proxy Dusty 1-1") })
  MOCK.advance(60)
end

describe("DMS.Test F10 mark checks", function()
  it("marks passes when Intel drew contacts and getMarkPanels lists every live id", function()
    proxy(0, 0)
    DMS_CONFIG = finalChecks({ { kind = "marks", name = "f10_marks", min = 2 } })
    flyAndLand()
    local t = byName("f10_marks")
    assert.is_truthy(t, "f10_marks resolved")
    assert.are.equal("PASS", t.status, t.detail)
    assert.is_truthy(string.find(t.detail, "getMarkPanels text", 1, true), t.detail)
    -- DCS (and the mock) list drawn shapes too, so circles are verified, not "unverified"
    local cf, cn = string.match(t.detail, "circles (%d+)/(%d+)")
    assert.is_truthy(cf, t.detail)
    assert.are.equal(cf, cn, t.detail)
    assert.is_true(tonumber(cf) > 0, t.detail)
    assert.is_nil(string.find(t.detail, "unverified", 1, true), t.detail)
    assert.is_true(DMS.Intel.markStats().added >= 2)
    assert.is_true((MOCK.logContains("%[DMS%]%[Intel%] MARK add id=%d+ kind=text coal=2")))
  end)

  it("marks fails when a live mark is missing from the map", function()
    proxy(0, 0)
    DMS_CONFIG = finalChecks({ { kind = "marks", name = "f10_marks" } })
    enemy()
    DMS.boot()
    MOCK.advance(15)
    MOCK.moveUnit("Proxy Dusty 1-1", 17000, 0)
    MOCK.advance(10)
    -- simulate DCS losing a text mark Intel believes is live
    local lost
    for id, m in pairs(DMS.Intel.liveMarks()) do
      if m.kind == "text" then
        lost = id
      end
    end
    assert.is_truthy(lost, "a contact text mark exists")
    MOCK.marks[lost] = nil
    MOCK.advance(15)
    MOCK.fireEvent({ id = world.event.S_EVENT_LAND, initiator = Unit.getByName("Proxy Dusty 1-1") })
    MOCK.advance(60)
    local t = byName("f10_marks")
    assert.are.equal("FAIL", t.status)
    assert.is_truthy(string.find(t.detail, "text ids not on map", 1, true), t.detail)
  end)

  it("marks fails when a live circle is missing while other circles are listed", function()
    proxy(0, 0)
    DMS_CONFIG = finalChecks({ { kind = "marks", name = "f10_marks" } })
    DMS.boot()
    MOCK.advance(1)
    DMS.Intel.mark({ type = "circle", at = { x = 100, y = 100 }, radius = 500, text = "A" })
    DMS.Intel.mark({ type = "circle", at = { x = 900, y = 900 }, radius = 500, text = "B" })
    local lost
    for id, m in pairs(DMS.Intel.liveMarks()) do
      if m.kind == "circle" then
        lost = id
      end
    end
    assert.is_truthy(lost, "a circle exists")
    MOCK.marks[lost] = nil
    MOCK.advance(15)
    MOCK.fireEvent({ id = world.event.S_EVENT_LAND, initiator = Unit.getByName("Proxy Dusty 1-1") })
    MOCK.advance(60)
    local t = byName("f10_marks")
    assert.are.equal("FAIL", t.status, t.detail)
    assert.is_truthy(string.find(t.detail, "circle ids not on map", 1, true), t.detail)
  end)

  it("marks ignores player-made marks and all-coalition shapes outside our ids", function()
    proxy(0, 0)
    DMS_CONFIG = finalChecks({ { kind = "marks", name = "f10_marks" } })
    MOCK.addPlayerMark({ idx = 251000001, text = "my target" })
    trigger.action.circleToAll(-1, 7, { x = 0, y = 0, z = 0 }, 1000, { 1, 0, 0, 1 }, { 1, 0, 0, 0.2 }, 1, true, "ME")
    local p
    for _, e in ipairs(world.getMarkPanels()) do
      if e.idx == 7 then
        p = e
      end
    end
    assert.are.equal(255, p.coalition, "all-coalition shape reports coalition 255")
    flyAndLand()
    local t = byName("f10_marks")
    assert.are.equal("PASS", t.status, t.detail)
    assert.is_true(DMS.Intel._nextId < 251000000, "ids never follow the player mark")
  end)

  it("marks fails on ghosts (removed ids still on the map) and on too few marks", function()
    proxy(0, 0)
    DMS_CONFIG = finalChecks({ { kind = "marks", name = "f10_marks", min = 50 } })
    DMS.boot()
    MOCK.advance(5)
    DMS.Intel._nextId = DMS.Intel._nextId + 1
    MOCK.marks[DMS.Intel._nextId] = { kind = "markToCoalition", id = DMS.Intel._nextId, args = { "ghost" } }
    MOCK.advance(15)
    MOCK.fireEvent({ id = world.event.S_EVENT_LAND, initiator = Unit.getByName("Proxy Dusty 1-1") })
    MOCK.advance(60)
    local t = byName("f10_marks")
    assert.are.equal("FAIL", t.status)
    assert.is_truthy(string.find(t.detail, "removed ids still on map", 1, true), t.detail)
    assert.is_truthy(string.find(t.detail, "want >= 50", 1, true), t.detail)
  end)

  it("marks passes unverified when world.getMarkPanels is missing", function()
    proxy(0, 0)
    DMS_CONFIG = finalChecks({ { kind = "marks", name = "f10_marks" } })
    world.getMarkPanels = nil
    flyAndLand()
    local t = byName("f10_marks")
    assert.are.equal("PASS", t.status)
    assert.is_truthy(string.find(t.detail, "unverified", 1, true), t.detail)
  end)
end)

describe("DMS.Test fog_hidden", function()
  it("passes when runtime enemy spawns are hidden and fails on a placed enemy group that is not", function()
    proxy(0, 0)
    DMS_CONFIG = finalChecks({ { kind = "fog_hidden", name = "fog_hidden" } })
    DMS_CONFIG.intel.knownGroups = { "Known AAA" }
    env.mission.coalition = {
      red = {
        country = {
          {
            id = 0,
            vehicle = {
              group = {
                { name = "Hidden SAM", hidden = true },
                { name = "Known AAA", hidden = false },
                { name = "Leaky Armour", hidden = false },
              },
            },
            static = { group = { { name = "Bunker", hidden = false } } },
          },
        },
      },
    }
    flyAndLand(function()
      coalition.addGroup(country.id.RUSSIA, Group.Category.GROUND, {
        name = "Hidden Runtime Tank",
        hidden = true,
        units = { { name = "Hidden Runtime Tank-1", type = "T-72B", x = 60000, y = 0 } },
      })
    end)
    local t = byName("fog_hidden")
    assert.are.equal("FAIL", t.status)
    assert.is_truthy(string.find(t.detail, "placed not hidden: Leaky Armour", 1, true), t.detail)
    assert.is_nil(string.find(t.detail, "Known AAA", 1, true))
    assert.is_nil(string.find(t.detail, "Bunker", 1, true))
    assert.is_truthy(string.find(t.detail, "2 placed + 1 spawned", 1, true), t.detail)
  end)

  it("fails on a runtime enemy spawn without hidden", function()
    proxy(0, 0)
    DMS_CONFIG = finalChecks({ { kind = "fog_hidden", name = "fog_hidden" } })
    DMS.boot()
    MOCK.advance(5)
    coalition.addGroup(country.id.RUSSIA, Group.Category.GROUND, {
      name = "Visible Tank",
      units = { { name = "Visible Tank-1", type = "T-72B", x = 40000, y = 0 } },
    })
    MOCK.advance(10)
    MOCK.fireEvent({ id = world.event.S_EVENT_LAND, initiator = Unit.getByName("Proxy Dusty 1-1") })
    MOCK.advance(60)
    local t = byName("fog_hidden")
    assert.are.equal("FAIL", t.status)
    assert.is_truthy(string.find(t.detail, "spawned not hidden: Visible Tank", 1, true), t.detail)
  end)

  it("is vacuous with fogOfWar off", function()
    proxy(0, 0)
    DMS_CONFIG = finalChecks({ { kind = "fog_hidden", name = "fog_hidden" } })
    DMS_CONFIG.intel.fogOfWar = false
    flyAndLand()
    assert.are.equal("PASS", byName("fog_hidden").status)
  end)
end)

describe("DMS.Test comms checks", function()
  it("comms_no_overlap and comms_beats pass for a normal run", function()
    proxy(0, 0)
    DMS_CONFIG = finalChecks({
      { kind = "comms_no_overlap", name = "radio_no_overlap" },
      { kind = "comms_beats", name = "spine_lines_played" },
    })
    flyAndLand()
    local o = byName("radio_no_overlap")
    assert.are.equal("PASS", o.status, o.detail)
    local b = byName("spine_lines_played")
    assert.are.equal("PASS", b.status, b.detail)
    assert.are.equal("3 fired beat(s) with speech checked", b.detail)
  end)

  it("comms_no_overlap fails when two lines overlap", function()
    proxy(0, 0)
    DMS_CONFIG = finalChecks({ { kind = "comms_no_overlap", name = "radio_no_overlap" } })
    DMS.boot()
    MOCK.advance(5)
    local h = DMS.Comms.history()
    h[#h + 1] = { t = 100, dur = 6, line = "a_v1", text = "A" }
    h[#h + 1] = { t = 103, dur = 4, line = "b_v1", text = "B" }
    MOCK.advance(5)
    MOCK.fireEvent({ id = world.event.S_EVENT_LAND, initiator = Unit.getByName("Proxy Dusty 1-1") })
    MOCK.advance(60)
    local t = byName("radio_no_overlap")
    assert.are.equal("FAIL", t.status)
    assert.is_truthy(string.find(t.detail, "a_v1@100.0+6.0 overlaps b_v1@103.0", 1, true), t.detail)
  end)

  it("comms_no_overlap skips when history has no timing", function()
    proxy(0, 0)
    DMS_CONFIG = finalChecks({ { kind = "comms_no_overlap", name = "radio_no_overlap" } })
    DMS.boot()
    MOCK.advance(5)
    local h = DMS.Comms.history()
    for i = #h, 1, -1 do
      h[i] = nil
    end
    h[1] = { line = "x" }
    DMS.Comms.say = function()
      return false
    end
    MOCK.fireEvent({ id = world.event.S_EVENT_LAND, initiator = Unit.getByName("Proxy Dusty 1-1") })
    MOCK.advance(60)
    assert.is_truthy((MOCK.logContains("%[DMS%.TEST%] SKIP radio_no_overlap")))
    assert.is_nil(byName("radio_no_overlap") and byName("radio_no_overlap").status == "FAIL" or nil)
  end)

  it("comms_beats fails when a guaranteed beat fired but its line never played", function()
    proxy(0, 0)
    DMS_CONFIG = finalChecks({ { kind = "comms_beats", name = "spine_lines_played" } })
    DMS.boot()
    local say = DMS.Comms.say
    DMS.Comms.say = function(speaker, lines, text, opts)
      if text == "gate" then
        return false -- swallowed
      end
      return say(speaker, lines, text, opts)
    end
    MOCK.advance(15)
    MOCK.moveUnit("Proxy Dusty 1-1", 10000, 0)
    MOCK.advance(10)
    MOCK.fireEvent({ id = world.event.S_EVENT_LAND, initiator = Unit.getByName("Proxy Dusty 1-1") })
    MOCK.advance(60)
    local t = byName("spine_lines_played")
    assert.are.equal("FAIL", t.status)
    assert.is_truthy(string.find(t.detail, "fired but never played: at_gate", 1, true), t.detail)
  end)
end)

-- Many seeds: random proxy paths and timings; the four end-of-run checks never FAIL on a healthy
-- runtime and the Intel MARK log always matches the map.
describe("DMS.Test end-of-run checks across seeds", function()
  for seed = 1, 12 do
    it("seed " .. seed .. ": marks, fog_hidden, comms_no_overlap, comms_beats hold", function()
      math.randomseed(seed * 104729)
      proxy(0, 0)
      DMS_CONFIG = finalChecks({
        { kind = "marks", name = "f10_marks" },
        { kind = "fog_hidden", name = "fog_hidden" },
        { kind = "comms_no_overlap", name = "radio_no_overlap" },
        { kind = "comms_beats", name = "spine_lines_played" },
      })
      DMS_CONFIG.seed = seed
      DMS_CONFIG.intel.staleSec = math.random(20, 120)
      DMS_CONFIG.intel.markRefreshSec = math.random(5, 20)
      DMS.boot()
      for _ = 1, math.random(5, 15) do
        MOCK.moveUnit("Proxy Dusty 1-1", math.random(-5000, 35000), math.random(-5000, 5000))
        MOCK.advance(math.random(2, 40))
        if math.random() < 0.2 then
          DMS.Comms.say("ops", nil, "chatter " .. math.random(1, 99), { coalition = 2 })
        end
      end
      MOCK.moveUnit("Proxy Dusty 1-1", 10000, 0)
      MOCK.advance(10)
      MOCK.fireEvent({ id = world.event.S_EVENT_LAND, initiator = Unit.getByName("Proxy Dusty 1-1") })
      MOCK.advance(120)
      for _, n in ipairs({ "f10_marks", "fog_hidden", "radio_no_overlap", "spine_lines_played" }) do
        local t = byName(n)
        assert.is_truthy(t, "missing " .. n)
        assert.are.equal("PASS", t.status, n .. ": " .. tostring(t.detail))
      end
      -- MARK log replay == Intel.liveMarks()
      local live = {}
      for _, l in ipairs(MOCK.log) do
        local op, id = string.match(l.msg, "^%[DMS%]%[Intel%] MARK (%a+) id=(%d+)")
        if op == "add" then
          live[tonumber(id)] = true
        elseif op == "remove" then
          live[tonumber(id)] = nil
        end
      end
      for id in pairs(DMS.Intel.liveMarks()) do
        assert.is_truthy(live[id], "live id " .. id .. " missing from log")
        live[id] = nil
      end
      assert.is_nil(next(live), "log shows marks Intel no longer has")
    end)
  end
end)
