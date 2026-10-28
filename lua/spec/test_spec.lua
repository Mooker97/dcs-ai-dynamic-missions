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
