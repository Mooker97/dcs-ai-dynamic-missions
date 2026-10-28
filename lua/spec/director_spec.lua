-- director_spec.lua: scenario tests for DMS.Director (driven by mocked DCS events via DMS.Bus).

local function start(dirCfg)
  DMS_CONFIG = {
    players = { coalition = 2 },
    budgets = { spawnsPerMin = 3 },
    director = dirCfg
      or { enabled = true, peak = 70, relaxSec = { 40, 90 }, decayPerSec = 1.5, adapt = { min = -1, max = 1 } },
  }
  DMS.Rng.seed(11)
  DMS.Director.reset()
  DMS.Director.start()
end

local function spawnPlayer(group, x, y)
  MOCK.spawnPlayer({ name = group .. "-1", group = group, x = x or 0, y = y or 0, alt = 3000 })
end

local function hit(group)
  MOCK.addGroup({
    name = "shooter",
    coalition = 1,
    category = "ground",
    units = { { name = "shooter-1", x = 9000, y = 0 } },
    silent = true,
  })
  MOCK.hitUnit(group .. "-1", { initiator = "shooter-1", weapon = "SA-8", damage = 0 })
end

describe("Director", function()
  before_each(function()
    start()
  end)

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
    DMS.Bus.on("director.state", function(ev)
      changes[#changes + 1] = ev.state
    end)
    hit("Viper1")
    hit("Viper1")
    hit("Viper1")
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
    hit("Viper1")
    hit("Viper1")
    hit("Viper1")
    assert.are.equal("PEAK", DMS.Director.state("Viper1"))
    assert.are.equal("BUILD_UP", DMS.Director.state("Hog1"))
    assert.is_true(DMS.Director.canSpawn(1, "Hog1"))
    assert.are.equal("PEAK", DMS.Director.state())
  end)

  it("enemy SAM launches near a player and nearby kills add intensity", function()
    spawnPlayer("Viper1", 0, 0)
    MOCK.addGroup({ name = "sam", coalition = 1, category = "ground", units = { { name = "sam-1", x = 3000, y = 0 } } })
    MOCK.addGroup({
      name = "truck",
      coalition = 1,
      category = "ground",
      units = { { name = "truck-1", x = 500, y = 0 } },
    })
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
    for _ = 1, 3 do
      DMS.Bus.emit("spawner.spawned", { group = "g", cost = 1 })
    end
    local ok, why = DMS.Director.canSpawn(1)
    assert.is_false(ok)
    assert.are.equal("budget", why)
    MOCK.advance(61)
    assert.is_true(DMS.Director.canSpawn(1))
  end)

  it("disabled director only applies the budget", function()
    start({ enabled = false })
    spawnPlayer("Viper1")
    hit("Viper1")
    hit("Viper1")
    hit("Viper1")
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
    for _ = 1, 60 do
      DMS.Bus.emit("unit.dead", { unit = "e", group = "eg", coalition = 1 })
    end
    assert.are.equal(1, DMS.Director.level())
    assert.are.equal("Excellent", DMS.Director.skillFor("High"))
    assert.are.equal("Excellent", DMS.Director.skillFor("Excellent"))
    assert.are.equal(5, DMS.Director.scaleCount(4))
    assert.truthy(DMS.Director.scaleDelay(10) < 10)
  end)

  it("respects custom adapt clamps", function()
    start({ adapt = { min = 0, max = 0.5 } })
    for _ = 1, 60 do
      DMS.Bus.emit("unit.dead", { unit = "e", group = "eg", coalition = 1 })
    end
    assert.are.equal(0.5, DMS.Director.level())
    spawnPlayer("Viper1")
    for _ = 1, 5 do
      DMS.Bus.emit("unit.dead", { unit = "Viper1-1", group = "Viper1", coalition = 2 })
      spawnPlayer("Viper1")
    end
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
  it("200 seeds: phases cycle in order, spawn budget never exceeded, difficulty within clamps", function()
    local NEXT = { BUILD_UP = "PEAK", PEAK = "RELAX", RELAX = "BUILD_UP" }
    local SKILL_OK = { Average = true, Good = true, High = true, Excellent = true }
    local cycles, spawns, peaks = 0, 0, 0
    for seed = 1, 200 do
      DMS.Bus.uninstall()
      MOCK.reset()
      DMS.Bus.install()
      DMS.Rng.seed(seed * 7919)
      local amin = -(seed % 3) * 0.5 -- 0, -0.5, -1
      local amax = (1 + seed % 4) * 0.25 -- 0.25 .. 1
      local relax = { 20 + seed % 30, 60 + seed % 40 }
      local peakHold = 10 + seed % 10
      DMS_CONFIG = {
        players = { coalition = 2 },
        budgets = { spawnsPerMin = 1 + seed % 5 },
        director = {
          enabled = true,
          peak = 50 + seed % 40,
          relaxSec = relax,
          peakHoldSec = peakHold,
          decayPerSec = 0.5 + (seed % 4) * 0.5,
          adapt = { min = amin, max = amax },
        },
      }
      DMS.Director.reset()
      DMS.Director.start()
      local maxI = DMS.Director._cfg.maxIntensity
      local track, costs, problems = {}, {}, {}
      local function bad(msg)
        problems[#problems + 1] = string.format("t=%.0f %s", DMS.Clock.now(), msg)
      end
      local tok = DMS.Bus.on("director.state", function(ev)
        local f = DMS.Director._flights[ev.flight]
        local tr = track[ev.flight]
        if not tr or tr.obj ~= f then
          tr = { obj = f, state = "BUILD_UP", since = DMS.Clock.now() }
        end
        if NEXT[tr.state] ~= ev.state then
          bad(ev.flight .. " " .. tr.state .. " -> " .. ev.state)
        end
        local held = DMS.Clock.now() - tr.since
        if tr.state == "PEAK" and held < peakHold - 1e-6 then
          bad("PEAK held only " .. held)
        end
        if tr.state == "RELAX" and held < relax[1] - 1e-6 then
          bad("RELAX held only " .. held)
        end
        if ev.state == "PEAK" then
          peaks = peaks + 1
        end
        if tr.state == "RELAX" then
          cycles = cycles + 1
        end
        tr.state, tr.since = ev.state, DMS.Clock.now()
        track[ev.flight] = tr
      end)
      local nFlights = 1 + seed % 3
      for i = 1, nFlights do
        spawnPlayer("Viper" .. i, i * 20000, 0)
      end
      MOCK.addGroup({
        name = "shooter",
        coalition = 1,
        category = "ground",
        units = { { name = "shooter-1", x = 9000, y = 0 } },
        silent = true,
      })
      for _ = 1, 360 do
        local r = DMS.Rng.random()
        local who = "Viper" .. DMS.Rng.int(1, nFlights)
        local rec = MOCK.units[who .. "-1"]
        local alive = rec ~= nil and not rec.dead
        if r < 0.15 and alive then
          MOCK.hitUnit(who .. "-1", { initiator = "shooter-1", weapon = "SA-8", damage = 0 })
        elseif r < 0.20 then
          DMS.Bus.emit("unit.dead", { unit = "e", group = "eg", coalition = 1 })
        elseif r < 0.21 and alive then
          MOCK.killUnit(who .. "-1")
        elseif r < 0.25 and not alive then
          spawnPlayer(who, 0, 0)
        end
        for _ = 1, DMS.Rng.int(0, 3) do
          local ok = DMS.Director.canSpawn(1)
          local st = DMS.Director.state()
          if ok and (st == "PEAK" or st == "RELAX") then
            bad("canSpawn true in " .. st)
          end
          if ok then
            DMS.Bus.emit("spawner.spawned", { group = "g", cost = 1 })
            spawns = spawns + 1
            local now, sum = DMS.Clock.now(), 0
            costs[#costs + 1] = now
            for _, t in ipairs(costs) do
              if now - t < 60 then
                sum = sum + 1
              end
            end
            if sum > DMS.Director.spawnBudget() + 1e-9 then
              bad("budget " .. sum .. " > " .. DMS.Director.spawnBudget())
            end
          end
        end
        local lvl = DMS.Director.level()
        if lvl < amin - 1e-9 or lvl > amax + 1e-9 then
          bad("level " .. lvl .. " outside [" .. amin .. ", " .. amax .. "]")
        end
        if not SKILL_OK[DMS.Director.skillFor("High")] then
          bad("skillFor " .. tostring(DMS.Director.skillFor("High")))
        end
        if DMS.Director.scaleCount(1) < 1 then
          bad("scaleCount < 1")
        end
        for _, name in ipairs(DMS.Director.flights()) do
          local i = DMS.Director.intensity(name)
          if i < 0 or i > maxI then
            bad("intensity " .. i)
          end
        end
        MOCK.advance(5)
      end
      DMS.Bus.off(tok)
      assert.are.equal(0, #problems, "seed " .. seed .. ": " .. table.concat(problems, "; "))
      assert.are.equal(0, #MOCK.rawErrors, "raw errors at seed " .. seed)
    end
    assert.truthy(peaks > 200, "too few PEAKs: " .. peaks)
    assert.truthy(cycles > 100, "too few full cycles: " .. cycles)
    assert.truthy(spawns > 1000, "too few spawns: " .. spawns)
  end)
end)
