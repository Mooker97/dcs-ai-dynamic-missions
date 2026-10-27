-- director_spec.lua: scenario tests for DMS.Director (driven by mocked DCS events via DMS.Bus).

local function start(dirCfg)
  DMS_CONFIG = {
    players = { coalition = 2 },
    budgets = { spawnsPerMin = 3 },
    director = dirCfg or { enabled = true, peak = 70, relaxSec = { 40, 90 }, decayPerSec = 1.5, adapt = { min = -1, max = 1 } },
  }
  DMS.Rng.seed(11)
  DMS.Director.reset()
  DMS.Director.start()
end

local function spawnPlayer(group, x, y)
  MOCK.spawnPlayer({ name = group .. "-1", group = group, x = x or 0, y = y or 0, alt = 3000 })
end

local function hit(group)
  MOCK.addGroup({ name = "shooter", coalition = 1, category = "ground", units = { { name = "shooter-1", x = 9000, y = 0 } }, silent = true })
  MOCK.hitUnit(group .. "-1", { initiator = "shooter-1", weapon = "SA-8", damage = 0 })
end

describe("Director", function()
  before_each(function() start() end)

  it("starts in BUILD_UP with no flights", function()
    assert.are.equal("BUILD_UP", DMS.Director.state())
    assert.is_true(DMS.Director.canSpawn(1))
  end)

  it("registers player flights from BIRTH events", function()
    spawnPlayer("Viper1")
    assert.are.equal(1, #DMS.Director.flights())
    assert.are.equal("Viper1", DMS.Director.flights()[1])
  end)

  it("hits on players raise intensity: PEAK, then RELAX, then BUILD_UP", function()
    spawnPlayer("Viper1")
    local changes = {}
    DMS.Bus.on("director.state", function(ev) changes[#changes + 1] = ev.state end)
    hit("Viper1"); hit("Viper1"); hit("Viper1")
    assert.are.equal("PEAK", DMS.Director.state("Viper1"))
    assert.are.equal("PEAK", changes[1])
    local ok, why = DMS.Director.canSpawn(1)
    assert.is_false(ok)
    assert.are.equal("PEAK", why)
    MOCK.advance(16)
    assert.are.equal("RELAX", DMS.Director.state("Viper1"))
    assert.is_false(DMS.Director.canSpawn(1))
    MOCK.advance(100)
    assert.are.equal("BUILD_UP", DMS.Director.state("Viper1"))
    assert.is_true(DMS.Director.canSpawn(1))
    assert.are.equal(3, #changes)
  end)

  it("intensity decays per second", function()
    spawnPlayer("Viper1")
    hit("Viper1")
    local before = DMS.Director.intensity("Viper1")
    MOCK.advance(10)
    assert.near(15, before - DMS.Director.intensity("Viper1"), 1.6)
  end)

  it("tracks flights independently", function()
    spawnPlayer("Viper1")
    spawnPlayer("Hog1", 90000, 0)
    hit("Viper1"); hit("Viper1"); hit("Viper1")
    assert.are.equal("PEAK", DMS.Director.state("Viper1"))
    assert.are.equal("BUILD_UP", DMS.Director.state("Hog1"))
    assert.is_true(DMS.Director.canSpawn(1, "Hog1"))
    assert.are.equal("PEAK", DMS.Director.state())
  end)

  it("enemy SAM launches near a player and nearby kills add intensity", function()
    spawnPlayer("Viper1", 0, 0)
    MOCK.addGroup({ name = "sam", coalition = 1, category = "ground", units = { { name = "sam-1", x = 3000, y = 0 } } })
    MOCK.addGroup({ name = "truck", coalition = 1, category = "ground", units = { { name = "truck-1", x = 500, y = 0 } } })
    MOCK.fireEvent({ id = "SHOT", initiator = Unit.getByName("sam-1"), weapon = MOCK.makeWeapon("SA-8") })
    assert.truthy(DMS.Director.intensity("Viper1") >= 15)
    local i = DMS.Director.intensity("Viper1")
    MOCK.killUnit("truck-1")
    assert.truthy(DMS.Director.intensity("Viper1") > i)
  end)

  it("ignores friendly shots", function()
    spawnPlayer("Viper1", 0, 0)
    MOCK.addGroup({ name = "blue", coalition = 2, category = "ground", units = { { name = "blue-1", x = 300, y = 0 } } })
    MOCK.fireEvent({ id = "SHOT", initiator = Unit.getByName("blue-1"), weapon = MOCK.makeWeapon("M2") })
    assert.are.equal(0, DMS.Director.intensity("Viper1"))
  end)

  it("enforces the spawns-per-minute budget", function()
    for _ = 1, 3 do DMS.Bus.emit("spawner.spawned", { group = "g", cost = 1 }) end
    local ok, why = DMS.Director.canSpawn(1)
    assert.is_false(ok)
    assert.are.equal("budget", why)
    MOCK.advance(61)
    assert.is_true(DMS.Director.canSpawn(1))
  end)

  it("disabled director only applies the budget", function()
    start({ enabled = false })
    spawnPlayer("Viper1")
    hit("Viper1"); hit("Viper1"); hit("Viper1")
    assert.is_true(DMS.Director.canSpawn(1))
  end)

  it("adapts hidden difficulty within clamps", function()
    for i = 1, 6 do
      spawnPlayer("Viper" .. i)
      MOCK.killUnit("Viper" .. i .. "-1")
    end
    assert.are.equal(-1, DMS.Director.level())
    assert.are.equal("Good", DMS.Director.skillFor("High"))
    assert.are.equal("Average", DMS.Director.skillFor("Average"))
    for _ = 1, 60 do DMS.Bus.emit("unit.dead", { unit = "e", group = "eg", coalition = 1 }) end
    assert.are.equal(1, DMS.Director.level())
    assert.are.equal("Excellent", DMS.Director.skillFor("High"))
    assert.are.equal("Excellent", DMS.Director.skillFor("Excellent"))
    assert.are.equal(5, DMS.Director.scaleCount(4))
    assert.truthy(DMS.Director.scaleDelay(10) < 10)
  end)

  it("respects custom adapt clamps", function()
    start({ adapt = { min = 0, max = 0.5 } })
    for _ = 1, 60 do DMS.Bus.emit("unit.dead", { unit = "e", group = "eg", coalition = 1 }) end
    assert.are.equal(0.5, DMS.Director.level())
    spawnPlayer("Viper1")
    for _ = 1, 5 do DMS.Bus.emit("unit.dead", { unit = "Viper1-1", group = "Viper1", coalition = 2 }); spawnPlayer("Viper1") end
    assert.are.equal(0, DMS.Director.level())
  end)

  it("calm periods nudge difficulty up", function()
    spawnPlayer("Viper1")
    MOCK.advance(301)
    assert.truthy(DMS.Director.level() > 0)
  end)

  it("player.left removes the flight", function()
    spawnPlayer("Viper1")
    DMS.Bus.emit("player.left", { unit = "Viper1-1", group = "Viper1" })
    assert.are.equal(0, #DMS.Director.flights())
  end)
end)
