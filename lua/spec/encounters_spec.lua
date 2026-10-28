-- encounters_spec.lua: scenario tests for DMS.Encounters (with spawner, ground, director).

local function baseConfig()
  return {
    seed = 1,
    players = { coalition = 2 },
    budgets = { maxActiveGround = 200, maxActiveAir = 16, spawnsPerMin = 50 },
    director = { enabled = true, peak = 70, relaxSec = { 40, 90 }, decayPerSec = 1.5, adapt = { min = -1, max = 1 } },
    intel = { fogOfWar = true },
    templates = {
      sa8 = { country = "RUSSIA", category = "ground", skill = "High", units = { { type = "Osa 9A33 ln" } } },
      btr = { country = "RUSSIA", category = "ground", units = { { type = "BTR-80" }, { type = "BTR-80", dx = -30 } } },
    },
    zones = {
      ridge = { kind = "circle", x = 40000, y = 0, radius = 2000 },
      valley = {
        kind = "polygon",
        points = {
          { x = 20000, y = 20000 },
          { x = 24000, y = 20000 },
          { x = 24000, y = 24000 },
          { x = 20000, y = 24000 },
        },
      },
    },
    pools = {
      aaa = { members = { { tpl = "sa8" } }, pick = 1, zones = { "ridge" } },
      btr = { members = { { tpl = "btr" } }, pick = { 1, 2 }, zones = { "valley" } },
    },
    encounters = {},
  }
end

local function boot(encounters, mutate)
  DMS_CONFIG = baseConfig()
  DMS_CONFIG.encounters = encounters or {}
  if mutate then
    mutate(DMS_CONFIG)
  end
  DMS.Rng.seed(DMS_CONFIG.seed)
  DMS.Ground.reset()
  DMS.Director.reset()
  DMS.Director.start()
  DMS.Encounters.start()
end

-- returns a mover: mv(x, y) relocates the player unit
local function player(name, x, y)
  MOCK.spawnPlayer({ name = name .. "-1", group = name, x = x, y = y, alt = 3000 })
  return function(nx, ny)
    MOCK.moveUnit(name .. "-1", nx, ny)
  end
end

local G = AI.Option.Ground
local function opt(g, id)
  return Group.getByName(g):getController().options[id]
end
local function hitPlayer(name)
  MOCK.addGroup({
    name = "shooter",
    coalition = 1,
    category = "ground",
    units = { { name = "shooter-1", x = 0, y = -90000 } },
    silent = true,
  })
  MOCK.hitUnit(name .. "-1", { initiator = "shooter-1", damage = 0 })
end

local function capture(evName)
  local list = {}
  DMS.Bus.on(evName, function(ev)
    list[#list + 1] = ev
  end)
  return list
end

describe("Encounters", function()
  it("ambush_sam: spawns dark on proximity, telegraphs, then goes hot", function()
    boot({
      {
        id = "popup",
        kind = "ambush_sam",
        pool = "aaa",
        engageRadiusM = 15000,
        telegraph = "beat:sam_spike",
        trigger = { type = "proximity", point = { x = 40000, y = 0 }, radiusM = 30000 },
      },
    })
    local spawned, tele, hot, req =
      capture("encounter.spawned"),
      capture("encounter.telegraph"),
      capture("encounter.sam_hot"),
      capture("beat.request")
    local mv = player("Viper1", 0, 0)
    MOCK.advance(10)
    assert.are.equal(0, #spawned)
    mv(15000, 0) -- 25 km from the site centre: inside 30 km trigger, outside engage radius
    MOCK.advance(10)
    assert.are.equal(1, #spawned)
    local g = spawned[1].groups[1]
    assert.is_true(MOCK.groups[g].data.hidden)
    assert.are.equal(G.val.ALARM_STATE.GREEN, opt(g, G.id.ALARM_STATE))
    assert.are.equal(G.val.ROE.WEAPON_HOLD, opt(g, G.id.ROE))
    assert.are.equal(0, #tele)
    mv(30000, 0)
    MOCK.advance(5)
    assert.are.equal(1, #tele)
    assert.are.equal("sam_spike", req[1].id)
    assert.are.equal(0, #hot)
    MOCK.advance(80)
    assert.are.equal(1, #hot)
    assert.are.equal(G.val.ALARM_STATE.RED, opt(g, G.id.ALARM_STATE))
    assert.are.equal(G.val.ROE.OPEN_FIRE, opt(g, G.id.ROE))
  end)

  it("ambush_sam: chance 0 never spawns, once", function()
    boot({
      {
        id = "popup",
        kind = "ambush_sam",
        pool = "aaa",
        chance = 0,
        trigger = { type = "proximity", point = { x = 0, y = 0 }, radiusM = 5000 },
      },
    })
    local spawned = capture("encounter.spawned")
    player("Viper1", 0, 0)
    MOCK.advance(60)
    assert.are.equal(0, #spawned)
    assert.is_true(DMS.Encounters.get("popup").done)
  end)

  it("waves respect the director and keep their gaps", function()
    boot({
      {
        id = "qrf",
        kind = "waves",
        pool = "btr",
        waves = 3,
        gapSec = { 120, 120 },
        trigger = { type = "beat", beat = "convoy_hit" },
      },
    })
    local waves = capture("encounter.wave")
    player("Viper1", -50000, 0)
    -- push the flight into PEAK: director must defer the first wave
    for _ = 1, 3 do
      hitPlayer("Viper1")
    end
    assert.are.equal("PEAK", DMS.Director.state())
    DMS.Bus.emit("beat.fired", { id = "convoy_hit" })
    assert.are.equal(0, #waves)
    MOCK.advance(14)
    assert.are.equal(0, #waves)
    MOCK.advance(150) -- PEAK 15 s, RELAX 40-90 s, then BUILD_UP
    assert.are.equal(1, #waves)
    local t1 = MOCK.t
    MOCK.advance(130)
    assert.are.equal(2, #waves)
    MOCK.advance(130)
    assert.are.equal(3, #waves)
    MOCK.advance(1000)
    assert.are.equal(3, #waves)
    assert.truthy(t1 > 0)
  end)

  it("director-deferred waves eventually spawn after maxDeferSec", function()
    boot({
      {
        id = "qrf",
        kind = "waves",
        pool = "btr",
        waves = 1,
        maxDeferSec = 60,
        trigger = { type = "time", afterSec = 5 },
      },
    })
    local waves = capture("encounter.wave")
    local real = DMS.Director.canSpawn
    DMS.Director.canSpawn = function()
      return false, "PEAK"
    end
    MOCK.advance(50)
    local before = #waves
    MOCK.advance(30)
    DMS.Director.canSpawn = real
    assert.are.equal(0, before)
    assert.are.equal(1, #waves)
  end)

  it("hunt: spawned groups hunt the nearest player with valid routes", function()
    boot({
      { id = "hunters", kind = "hunt", pool = "btr", huntIntervalSec = 10, trigger = { type = "time", afterSec = 2 } },
    })
    local spawned = capture("encounter.spawned")
    player("Viper1", 0, 0)
    MOCK.advance(20)
    assert.are.equal(1, #spawned)
    for _, g in ipairs(spawned[1].groups) do
      local t = Group.getByName(g):getController().task
      assert.is_not_nil(t, "hunter has no route")
      assert.truthy(#t.params.route.points >= 2)
      local last = t.params.route.points[#t.params.route.points]
      assert.truthy(math.abs(last.x) < 22000 and math.abs(last.y) < 22000, "route should head toward the player")
    end
  end)

  it("event trigger matches payload fields; director trigger fires on state", function()
    boot({
      {
        id = "e1",
        kind = "pool",
        pool = "btr",
        gated = false,
        trigger = { type = "event", name = "group.dead", group = "HVT" },
      },
      { id = "d1", kind = "pool", pool = "btr", gated = false, trigger = { type = "director", state = "RELAX" } },
    })
    local spawned = capture("encounter.spawned")
    DMS.Bus.emit("group.dead", { group = "other" })
    assert.are.equal(0, #spawned)
    DMS.Bus.emit("group.dead", { group = "HVT" })
    assert.are.equal(1, #spawned)
    assert.are.equal("e1", spawned[1].id)
    DMS.Bus.emit("group.dead", { group = "HVT" }) -- once
    assert.are.equal(1, #spawned)
    DMS.Bus.emit("director.state", { flight = "x", state = "RELAX" })
    assert.are.equal(2, #spawned)
  end)

  it("manual trigger, once=false, and encounter.cleared", function()
    boot({ { id = "m", kind = "pool", pool = "aaa", once = false, gated = false } })
    local spawned, cleared = capture("encounter.spawned"), capture("encounter.cleared")
    assert.is_true(DMS.Encounters.trigger("m"))
    assert.is_true(DMS.Encounters.trigger("m"))
    assert.are.equal(2, #spawned)
    local groups = DMS.Encounters.groups("m")
    MOCK.killGroup(groups[1])
    MOCK.advance(11)
    assert.are.equal(0, #cleared)
    MOCK.killGroup(groups[2]) -- group.dead from the bus clears immediately
    assert.are.equal(1, #cleared)
    MOCK.advance(11)
    assert.are.equal(1, #cleared)
    assert.is_false(DMS.Encounters.trigger("nope"))
  end)

  it("convoy: named convoy halts when hit and gets escorts", function()
    boot({
      {
        id = "cv",
        kind = "convoy",
        group = "Convoy1",
        pool = "btr",
        resumeAfterSec = 30,
        trigger = { type = "time", afterSec = 1 },
      },
    }, function(c)
      c.intel.fogOfWar = false
    end)
    MOCK.addGroup({
      name = "Convoy1",
      coalition = 1,
      category = "ground",
      units = { { name = "cv-1", x = 60000, y = 60000 } },
    })
    local halted = capture("convoy.halted")
    MOCK.advance(2)
    assert.truthy(#DMS.Encounters.groups("cv") >= 2)
    DMS.Bus.emit("unit.hit", { target = "cv-1", targetGroup = "Convoy1" })
    assert.are.equal(1, #halted)
    local cmds = Group.getByName("Convoy1"):getController().commands
    assert.is_true(cmds[#cmds].params.value)
    MOCK.advance(31)
    cmds = Group.getByName("Convoy1"):getController().commands
    assert.is_false(cmds[#cmds].params.value)
  end)

  it("runs 200 random seeds of a full scenario without errors", function()
    local encs = {
      {
        id = "popup",
        kind = "ambush_sam",
        pool = "aaa",
        chance = 60,
        telegraph = "event:rwr_spike",
        trigger = { type = "proximity", zone = "ridge", radiusM = 30000 },
      },
      {
        id = "qrf",
        kind = "waves",
        pool = "btr",
        waves = { 2, 3 },
        gapSec = { 60, 120 },
        hunt = true,
        trigger = { type = "beat", beat = "go" },
      },
      { id = "late", kind = "hunt", pool = "btr", trigger = { type = "time", afterSec = { 100, 300 } } },
      { id = "react", kind = "pool", pool = "aaa", trigger = { type = "director", state = "RELAX" }, chance = 50 },
    }
    local total = 0
    for seed = 1, 200 do
      DMS.Bus.uninstall()
      MOCK.reset()
      DMS.Bus.install()
      boot(encs, function(c)
        c.seed = seed
        c.zones.ridge.x = 30000 + (seed % 7) * 3000
      end)
      MOCK.waterAreas = {}
      for x = -10000, 70000, 1000 do
        MOCK.waterAreas[#MOCK.waterAreas + 1] = {
          points = {
            { x = x, y = -40000 },
            { x = x + 150, y = -40000 },
            { x = x + 150, y = 40000 },
            { x = x, y = 40000 },
          },
        }
      end
      local mv = player("Viper1", 0, 0)
      for step = 1, 60 do
        mv(step * 800, (seed * 13 % 9) * 1000)
        if step == 10 then
          DMS.Bus.emit("beat.fired", { id = "go" })
        end
        if step % 7 == 0 then
          hitPlayer("Viper1")
        end
        MOCK.advance(10)
      end
      for _, l in ipairs(MOCK.log) do
        assert.truthy(l.level ~= "error", "seed " .. seed .. ": " .. tostring(l.msg))
      end
      assert.are.equal(0, #MOCK.rawErrors, "raw errors at seed " .. seed)
      -- every spawned unit is on land
      for name, g in pairs(MOCK.groups) do
        if string.sub(name, 1, 4) == "DMS_" then
          total = total + 1
          for _, un in ipairs(g.units) do
            local x = MOCK.units[un].x
            assert.truthy((x + 10000) % 1000 >= 150, "water spawn, seed " .. seed)
          end
        end
      end
    end
    assert.truthy(total > 400, "scenario spawned too little: " .. total)
  end)
end)
