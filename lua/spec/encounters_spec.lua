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

  it("telegraphed waves warn before each wave spawns", function()
    boot({
      {
        id = "push",
        kind = "waves",
        pool = "btr",
        waves = 2,
        gapSec = { 120, 120 },
        telegraph = "beat:massing",
        telegraphSec = { 30, 30 },
        trigger = { type = "beat", beat = "go" },
      },
    })
    local waves = capture("encounter.wave")
    local requests = capture("beat.request")
    player("Viper1", -50000, 0)
    DMS.Bus.emit("beat.fired", { id = "go" })
    assert.are.equal(1, #requests)
    assert.are.equal("massing", requests[1].id)
    assert.are.equal(0, #waves)
    MOCK.advance(31)
    assert.are.equal(1, #waves)
    MOCK.advance(121)
    assert.are.equal(2, #requests)
    assert.are.equal(1, #waves)
    MOCK.advance(31)
    assert.are.equal(2, #waves)
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

  it("pool launches never overspend the director budget (150 seeds)", function()
    -- every launch is checked for cost * groups; a launch with earlier spawns still in the 60 s window
    -- must fit the budget (an empty window may admit one oversized launch: throttled, never starved)
    local encs = {
      { id = "p1", kind = "pool", pool = "big", once = false, maxDeferSec = 1e9 },
      { id = "p2", kind = "pool", pool = "btr", once = false, cost = 2, maxDeferSec = 1e9 },
      { id = "w1", kind = "waves", pool = "big", waves = { 2, 4 }, gapSec = { 5, 40 }, once = false, maxDeferSec = 1e9 },
      { id = "t1", kind = "pool", template = "sa8", zone = "ridge", once = false, cost = 2, maxDeferSec = 1e9 },
    }
    local ids = { "p1", "p2", "w1", "t1" }
    local launches, oversized, bad = 0, 0, {}
    for seed = 1, 150 do
      DMS.Bus.uninstall()
      MOCK.reset()
      DMS.Bus.install()
      boot(encs, function(c)
        c.seed = seed
        c.budgets.spawnsPerMin = 2 + seed % 4
        c.budgets.maxActiveGround = 100000
        c.pools.big = { members = { { tpl = "sa8" }, { tpl = "btr" } }, pick = { 1, 1 + seed % 4 }, zones = { "ridge" } }
      end)
      local costs = {} -- group -> cost noted by the director
      local hist = {} -- {t, cost} per launch, in order
      -- bus handlers outlive MOCK.reset: drop this seed's listeners at the end of the seed
      local t1 = DMS.Bus.on("spawner.spawned", function(ev)
        costs[ev.group] = ev.cost
      end)
      local t2 = DMS.Bus.on("encounter.spawned", function(ev)
        local c = 0
        for _, g in ipairs(ev.groups) do
          c = c + (costs[g] or 1)
        end
        local now, prior = DMS.Clock.now(), 0
        for _, h in ipairs(hist) do
          if now - h.t < 60 then
            prior = prior + h.cost
          end
        end
        local budget = DMS.Director.spawnBudget()
        if prior > 0 then
          -- recorded, asserted after the run (bus handlers swallow errors)
          if prior + c > budget + 1e-9 then
            bad[#bad + 1] = string.format("seed %d %s: %s + %s > budget %s", seed, ev.id, prior, c, budget)
          end
        elseif c > budget then
          oversized = oversized + 1
        end
        hist[#hist + 1] = { t = now, cost = c }
        launches = launches + 1
      end)
      local r = seed * 7919
      for _ = 1, 40 do
        r = (r * 1103515245 + 12345) % 2147483648
        DMS.Encounters.trigger(ids[1 + r % #ids], true)
        MOCK.advance(5 + r % 20)
      end
      MOCK.advance(600)
      DMS.Bus.off(t1)
      DMS.Bus.off(t2)
      assert.are.equal(0, #MOCK.rawErrors, "raw errors at seed " .. seed)
    end
    assert.are.equal(0, #bad, bad[1])
    assert.truthy(launches > 3000, "too few launches: " .. launches)
    print(string.format("launches %d, oversized-on-empty-window %d", launches, oversized))
  end)

  it("director gate uses the flight nearest the encounter, not the busiest one", function()
    local function run(peakFlight)
      DMS.Bus.uninstall()
      MOCK.reset()
      DMS.Bus.install()
      boot({ { id = "near", kind = "pool", pool = "aaa", trigger = { type = "time", afterSec = 1 } } })
      local flights = {}
      local real = DMS.Director.canSpawn
      DMS.Director.canSpawn = function(cost, flight)
        flights[#flights + 1] = flight or "nil"
        return real(cost, flight)
      end
      local spawned = capture("encounter.spawned")
      player("Viper1", 30000, 0) -- ~10 km from the ridge pool zone
      player("Viper2", -60000, 0) -- far away
      for _ = 1, 3 do
        hitPlayer(peakFlight)
      end
      assert.are.equal("PEAK", DMS.Director.state(peakFlight))
      assert.are.equal("PEAK", DMS.Director.state()) -- aggregate is PEAK either way
      MOCK.advance(3)
      DMS.Director.canSpawn = real
      return #spawned, flights[1]
    end
    local n, f = run("Viper2") -- the distant flight is busy: the near one is calm, spawn now
    assert.are.equal(1, n)
    assert.are.equal("Viper1", f)
    n, f = run("Viper1") -- the near flight is busy: deferred
    assert.are.equal(0, n)
    assert.are.equal("Viper1", f)
  end)

  it("proximity encounters gate on the triggering flight; nil when no flight is tracked", function()
    DMS.Bus.uninstall()
    MOCK.reset()
    DMS.Bus.install()
    -- spawn zone near Viper2, but Viper1 trips the proximity trigger
    boot({
      {
        id = "prox",
        kind = "pool",
        pool = "btr",
        spawnZone = "valley",
        trigger = { type = "proximity", point = { x = 0, y = 60000 }, radiusM = 5000, checkSec = 2 },
      },
    })
    local flights = {}
    local real = DMS.Director.canSpawn
    DMS.Director.canSpawn = function(cost, flight)
      flights[#flights + 1] = flight or "nil"
      return real(cost, flight)
    end
    local spawned = capture("encounter.spawned")
    local mv1 = player("Viper1", 0, 0)
    player("Viper2", 22000, 32000) -- ~10 km from the valley spawn zone
    for _ = 1, 3 do
      hitPlayer("Viper1")
    end
    mv1(0, 60000)
    MOCK.advance(5)
    assert.are.equal("Viper1", flights[1])
    assert.are.equal(0, #spawned) -- Viper1 is in PEAK, Viper2 (nearest the spawn zone) is not
    DMS.Director.canSpawn = real

    -- no players tracked: the director gets nil and gates on the aggregate
    DMS.Bus.uninstall()
    MOCK.reset()
    DMS.Bus.install()
    boot({ { id = "lone", kind = "pool", pool = "aaa", trigger = { type = "time", afterSec = 1 } } })
    flights = {}
    DMS.Director.canSpawn = function(cost, flight)
      flights[#flights + 1] = flight or "nil"
      return real(cost, flight)
    end
    MOCK.advance(3)
    DMS.Director.canSpawn = real
    assert.are.equal("nil", flights[1])
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
