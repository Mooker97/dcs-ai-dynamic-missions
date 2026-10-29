-- ground_move_spec.lua: the Narrative `moveGroup` effect (route on cue, ground.arrived) against the
-- DCS mock with the real DMS.Clock / DMS.Bus / DMS.Ground / DMS.Spawner / DMS.Intel.

local function reset(beats)
  DMS_CONFIG = {
    players = { coalition = 2 },
    budgets = {},
    zones = {
      lz_bravo = { kind = "circle", x = 2000, y = 0, radius = 300 },
      tiny = { kind = "circle", x = 1000, y = 0, radius = 20 },
    },
    narrative = { minGapSec = 0 },
    beats = beats or {},
  }
  DMS.Rng.seed(5)
  DMS.Ground.reset()
  DMS.Narrative.start()
end

local function blueGroup(name, x, y)
  return MOCK.addGroup({
    name = name,
    coalition = 2,
    category = "ground",
    units = { { name = name .. "-1", x = x, y = y }, { name = name .. "-2", x = x - 20, y = y } },
  })
end

local function lastRoute(name)
  local t = Group.getByName(name):getController().task
  return t and t.params.route.points
end

local function arrivals()
  local got = {}
  DMS.Bus.on("ground.arrived", function(p)
    got[#got + 1] = p
  end)
  return got
end

describe("Narrative moveGroup", function()
  after_each(function()
    DMS.Narrative.stop()
  end)

  it("routes to the zone centre with speed and action", function()
    reset()
    blueGroup("kestrel_1", 0, 0)
    assert.is_true(DMS.Narrative.moveGroup({ group = "kestrel_1", to = "lz_bravo", speedMps = 3, action = "Off Road" }))
    local pts = lastRoute("kestrel_1")
    assert.are.equal(2000, pts[#pts].x)
    assert.are.equal(0, pts[#pts].y)
    assert.are.equal(3, pts[#pts].speed)
    assert.are.equal("Off Road", pts[#pts].action)
    assert.truthy(MOCK.logContains("moveGroup 'kestrel_1' %-> lz_bravo %(Off Road, 3.0 m/s%)"))
  end)

  it("defaults to On Road at 4 m/s and resolves a prefix", function()
    reset()
    blueGroup("kestrel_1", 0, 0)
    assert.is_true(DMS.Narrative.moveGroup({ group = "kestrel", to = "lz_bravo" }))
    local pts = lastRoute("kestrel_1")
    assert.are.equal(4, pts[#pts].speed)
    assert.are.equal("On Road", pts[#pts].action)
  end)

  it("emits ground.arrived once inside max(150, zone radius)", function()
    reset()
    blueGroup("kestrel_1", 0, 0)
    local got = arrivals()
    DMS.Narrative.moveGroup({ group = "kestrel_1", to = "lz_bravo", speedMps = 4 })
    MOCK.moveUnit("kestrel_1-1", 1500, 0) -- 500 m out: not there
    MOCK.advance(6)
    assert.are.equal(0, #got)
    MOCK.moveUnit("kestrel_1-1", 1750, 0) -- 250 m: inside the 300 m zone radius
    MOCK.advance(4)
    assert.are.equal(1, #got)
    assert.are.equal("kestrel_1", got[1].group)
    assert.are.equal("lz_bravo", got[1].zone)
    MOCK.advance(30)
    assert.are.equal(1, #got)
    assert.truthy(MOCK.logContains("moveGroup 'kestrel_1' arrived at lz_bravo"))
  end)

  it("uses 150 m for small zones", function()
    reset()
    blueGroup("g_1", 0, 0)
    local got = arrivals()
    DMS.Narrative.moveGroup({ group = "g_1", to = "tiny" })
    MOCK.moveUnit("g_1-1", 860, 0) -- 140 m from a 20 m zone
    MOCK.advance(4)
    assert.are.equal(1, #got)
  end)

  it("stops polling when the group dies", function()
    reset()
    blueGroup("g_1", 0, 0)
    local got = arrivals()
    DMS.Narrative.moveGroup({ group = "g_1", to = "lz_bravo" })
    MOCK.killGroup("g_1")
    MOCK.advance(10)
    MOCK.advance(10)
    assert.are.equal(0, #got)
    assert.truthy(MOCK.logContains("moveGroup 'g_1': group dead"))
  end)

  it("skips unknown groups and zones with a warning", function()
    reset()
    blueGroup("g_1", 0, 0)
    assert.is_false(DMS.Narrative.moveGroup({ group = "nobody", to = "lz_bravo" }))
    assert.is_false(DMS.Narrative.moveGroup({ group = "g_1", to = "nowhere" }))
    assert.truthy(MOCK.logContains("no live group 'nobody'"))
    assert.truthy(MOCK.logContains("unknown zone 'nowhere'"))
  end)

  it("a beat effect moves the group and ground.arrived triggers a beat by id prefix", function()
    reset({
      {
        id = "go",
        when = { event = "mission.start" },
        effects = { moveGroup = { group = "kestrel_1", to = "lz_bravo", speedMps = 3, action = "Off Road" } },
      },
      { id = "there", when = { event = "ground.arrived", group = "kestrel" }, effects = { setFlag = "at_lz" } },
      { id = "wrong", when = { event = "ground.arrived", group = "kes" }, effects = { setFlag = "bad" } },
    })
    blueGroup("kestrel_1", 0, 0)
    DMS.Bus.emit("mission.start", {})
    MOCK.advance(2)
    assert.are.equal("Off Road", lastRoute("kestrel_1")[2].action)
    MOCK.moveUnit("kestrel_1-1", 1990, 10)
    MOCK.advance(10)
    assert.is_true(DMS.Narrative.isFlagSet("at_lz"))
    assert.is_false(DMS.Narrative.isFlagSet("bad"))
  end)

  it("group filter: exact name, or id followed by _ / - (DMS_ stripped)", function()
    local m = DMS.Narrative._groupIdMatch
    assert.is_true(m("kestrel_1", "kestrel"))
    assert.is_true(m("DMS_kestrel_1", "kestrel"))
    assert.is_true(m("kestrel-2", "kestrel"))
    assert.is_false(m("sam_10", "sam_1"))
    assert.is_false(m("kestrelx_1", "kestrel"))
  end)
end)
