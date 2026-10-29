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

  it("player.left removes the flight after the death window", function()
    spawnPlayer("Viper1")
    DMS.Bus.emit("player.left", { unit = "Viper1-1", group = "Viper1" })
    assert.are.equal(1, #DMS.Director.flights()) -- orphan while a late death may still arrive
    MOCK.advance(DMS.Director.LEFT_GRACE_SEC + 1)
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

-- ------------------------------------------------------------------ scenario helpers

-- Fresh mock world + bus + director for one seed.
local function reboot(seed, dirCfg, budgets)
  DMS.Bus.uninstall()
  MOCK.reset()
  DMS.Bus.install()
  DMS.Rng.seed(seed)
  DMS_CONFIG = {
    players = { coalition = 2 },
    budgets = budgets or { spawnsPerMin = 100 },
    director = dirCfg,
  }
  DMS.Director.reset()
  DMS.Director.start()
end

local function record(name)
  local out = {}
  DMS.Bus.on(name or "director.state", function(ev)
    out[#out + 1] = { t = DMS.Clock.now(), flight = ev.flight, state = ev.state, intensity = ev.intensity }
  end)
  return out
end

-- Advance 1 s at a time until fn() is true (or maxSec); returns elapsed seconds or nil.
local function advanceUntil(fn, maxSec)
  for s = 1, maxSec do
    MOCK.advance(1)
    if fn() then
      return s
    end
  end
  return nil
end

local SEEDS = 50

describe("Director scenarios (fake clock, many seeds)", function()
  it("50 seeds: full BUILD_UP -> PEAK -> RELAX -> BUILD_UP cycle, twice, with documented timing", function()
    for seed = 1, SEEDS do
      local peak = 40 + seed % 50
      local hold = 5 + seed % 20
      local relax = { 10 + seed % 20, 30 + seed % 40 }
      local decay = 0.5 + (seed % 5) * 0.5
      reboot(seed * 104729, { peak = peak, peakHoldSec = hold, relaxSec = relax, decayPerSec = decay })
      local ctx = "seed " .. seed
      spawnPlayer("Viper1", 0, 0)
      local ev = record()
      for cycle = 1, 2 do
        assert.are.equal("BUILD_UP", DMS.Director.state("Viper1"), ctx)
        assert.is_true(DMS.Director.canSpawn(1, "Viper1"), ctx)
        local t0 = DMS.Clock.now()
        DMS.Director.addIntensity("Viper1", peak, "test")
        assert.are.equal("PEAK", DMS.Director.state("Viper1"), ctx)
        local ok, why = DMS.Director.canSpawn(1, "Viper1")
        assert.is_false(ok, ctx)
        assert.are.equal("PEAK", why, ctx)
        local inPeak = advanceUntil(function()
          return DMS.Director.state("Viper1") ~= "PEAK"
        end, 200)
        assert.truthy(inPeak, ctx .. ": never left PEAK")
        local held = DMS.Clock.now() - t0
        assert.truthy(held >= hold - 1e-6 and held <= hold + 1 + 1e-6, ctx .. ": PEAK held " .. held)
        assert.are.equal("RELAX", DMS.Director.state("Viper1"), ctx)
        local f = DMS.Director._flights.Viper1
        assert.truthy(f.relaxFor >= relax[1] and f.relaxFor <= relax[2], ctx .. ": relaxFor " .. f.relaxFor)
        local ok2, why2 = DMS.Director.canSpawn(1, "Viper1")
        assert.is_false(ok2, ctx)
        assert.are.equal("RELAX", why2, ctx)
        local tR, iR = DMS.Clock.now(), DMS.Director.intensity("Viper1")
        assert.truthy(advanceUntil(function()
          return DMS.Director.state("Viper1") == "BUILD_UP"
        end, 400), ctx .. ": never left RELAX")
        local relaxed = DMS.Clock.now() - tR
        local drain = math.max(0, (iR - peak * 0.5) / decay)
        assert.truthy(relaxed >= f.relaxFor - 1e-6, ctx .. ": RELAX only " .. relaxed)
        assert.truthy(relaxed <= math.max(f.relaxFor, drain) + 1 + 1e-6, ctx .. ": RELAX too long " .. relaxed)
        assert.truthy(DMS.Director.intensity("Viper1") < peak * 0.5, ctx)
        assert.is_true(DMS.Director.canSpawn(1, "Viper1"), ctx)
        assert.are.equal(cycle * 3, #ev, ctx)
      end
      local want = { "PEAK", "RELAX", "BUILD_UP", "PEAK", "RELAX", "BUILD_UP" }
      for i, w in ipairs(want) do
        assert.are.equal(w, ev[i].state, ctx .. " event " .. i)
        assert.are.equal("Viper1", ev[i].flight, ctx)
      end
      assert.truthy(MOCK.logContains("%[Director%] Flight 'Viper1' BUILD_UP %-> PEAK"), ctx .. ": state change not logged")
      assert.are.equal(0, #MOCK.rawErrors, ctx)
    end
  end)

  it("50 seeds: intensity decays decayPerSec per tick, floors at 0 and clamps at maxIntensity", function()
    for seed = 1, SEEDS do
      local decay = 0.25 + (seed % 8) * 0.25
      local maxI = 60 + seed % 80
      reboot(seed, { peak = 1000, decayPerSec = decay, maxIntensity = maxI })
      local ctx = "seed " .. seed
      spawnPlayer("Viper1")
      DMS.Director.addIntensity("Viper1", maxI * 5, "flood")
      assert.are.equal(maxI, DMS.Director.intensity("Viper1"), ctx)
      local prev = maxI
      for _ = 1, 30 do
        MOCK.advance(1)
        local i = DMS.Director.intensity("Viper1")
        assert.near(math.max(0, prev - decay), i, 1e-9, ctx)
        prev = i
      end
      DMS.Director.addIntensity("Viper1", -10000, "drain")
      assert.are.equal(0, DMS.Director.intensity("Viper1"), ctx)
      MOCK.advance(5)
      assert.are.equal(0, DMS.Director.intensity("Viper1"), ctx)
      assert.are.equal("BUILD_UP", DMS.Director.state("Viper1"), ctx)
    end
  end)

  it("50 seeds: rolling 60 s spawn budget matches a reference model (refusal and recovery)", function()
    local refusals, recoveries = 0, 0
    for seed = 1, SEEDS do
      local spm = 1 + seed % 6
      reboot(seed * 31, { enabled = true }, { spawnsPerMin = spm })
      local ctx = "seed " .. seed
      local noted = {}
      local wasRefused = false
      for step = 1, 200 do
        local cost = DMS.Rng.int(1, 3)
        local now, used = DMS.Clock.now(), 0
        for _, s in ipairs(noted) do
          if now - s.t < 60 then
            used = used + s.cost
          end
        end
        local expect = used == 0 or used + cost <= spm
        local ok, why = DMS.Director.canSpawn(cost)
        assert.are.equal(expect, ok, ctx .. " step " .. step .. " used " .. used .. " cost " .. cost)
        if ok then
          if wasRefused then
            recoveries = recoveries + 1
          end
          wasRefused = false
          DMS.Bus.emit("spawner.spawned", { group = "g" .. step, cost = cost })
          noted[#noted + 1] = { t = now, cost = cost }
        else
          assert.are.equal("budget", why, ctx)
          refusals = refusals + 1
          wasRefused = true
        end
        MOCK.advance(DMS.Rng.int(0, 15))
      end
    end
    assert.truthy(refusals > 500, "refusals " .. refusals)
    assert.truthy(recoveries > 200, "recoveries " .. recoveries)
  end)

  it("budget: refused until the oldest spawn ages past 60 s; oversized cost allowed on an empty window", function()
    reboot(1, {}, { spawnsPerMin = 3 })
    DMS.Director.noteSpawn(1) -- t=0
    MOCK.advance(20)
    DMS.Director.noteSpawn(1) -- t=20
    MOCK.advance(20)
    DMS.Director.noteSpawn(1) -- t=40
    local ok, why = DMS.Director.canSpawn(1)
    assert.is_false(ok)
    assert.are.equal("budget", why)
    MOCK.advance(19.9) -- t=59.9: the t=0 spawn still counts
    assert.is_false(DMS.Director.canSpawn(1))
    MOCK.advance(0.1) -- t=60: it has aged out
    assert.is_true(DMS.Director.canSpawn(1))
    assert.is_false(DMS.Director.canSpawn(2))
    MOCK.advance(120)
    assert.is_true(DMS.Director.canSpawn(10)) -- empty window: throttled, never starved
    DMS.Director.noteSpawn(10)
    assert.is_false(DMS.Director.canSpawn(1))
    MOCK.advance(60)
    assert.is_true(DMS.Director.canSpawn(1))
  end)

  it("budget scales with difficulty level and never drops below 1/min", function()
    reboot(1, {}, { spawnsPerMin = 4 })
    assert.are.equal(4, DMS.Director.spawnBudget())
    DMS.Director.adapt(1, "test")
    assert.are.equal(5, DMS.Director.spawnBudget())
    DMS.Director.adapt(-2, "test")
    assert.are.equal(3, DMS.Director.spawnBudget())
    reboot(1, {}, { spawnsPerMin = 0 })
    assert.are.equal(1, DMS.Director.spawnBudget())
  end)

  it("50 seeds: adapt() stays within config clamps under repeated random calls", function()
    local hitMin, hitMax = 0, 0
    for seed = 1, SEEDS do
      local amin = -(seed % 4) -- schema range: -3..0
      local amax = seed % 4 == 0 and 0.5 or (seed % 3) -- fractional and 0..2
      reboot(seed * 7, { adapt = { min = amin, max = amax } })
      local ctx = "seed " .. seed .. " [" .. amin .. ", " .. amax .. "]"
      for _ = 1, 300 do
        local lvl = DMS.Director.adapt((DMS.Rng.random() * 4) - 2, "fuzz")
        assert.are.equal(lvl, DMS.Director.level(), ctx)
        assert.truthy(lvl >= amin - 1e-9 and lvl <= amax + 1e-9, ctx .. ": level " .. lvl)
        if lvl == amin then
          hitMin = hitMin + 1
        end
        if lvl == amax then
          hitMax = hitMax + 1
        end
        local t = lvl >= 0 and math.floor(lvl + 0.5) or -math.floor(-lvl + 0.5)
        local SK = { "Average", "Good", "High", "Excellent" }
        assert.are.equal(SK[math.max(1, math.min(4, 2 + t))], DMS.Director.skillFor("Good"), ctx)
        assert.truthy(DMS.Director.scaleCount(1) >= 1, ctx)
        assert.truthy(DMS.Director.scaleDelay(10) >= 0, ctx)
      end
    end
    assert.truthy(hitMin > 100 and hitMax > 100, "clamps not exercised: " .. hitMin .. "/" .. hitMax)
  end)

  it("adapt defaults to +/-1 tier and repairs inverted clamps to 0", function()
    reboot(1, {})
    for _ = 1, 50 do
      DMS.Director.adapt(1, "up")
    end
    assert.are.equal(1, DMS.Director.level())
    for _ = 1, 50 do
      DMS.Director.adapt(-1, "down")
    end
    assert.are.equal(-1, DMS.Director.level())
    assert.truthy(MOCK.logContains("%[Director%] Difficulty tier"), "tier change not logged")
    reboot(1, { adapt = { min = 0.5, max = -0.5 } })
    DMS.Director.adapt(3, "up")
    assert.are.equal(0, DMS.Director.level())
    DMS.Director.adapt(-3, "down")
    assert.are.equal(0, DMS.Director.level())
    assert.are.equal(0, DMS.Director.adapt(nil, "nil delta"))
  end)

  it("skillFor/scaleCount/scaleDelay respect the level", function()
    reboot(1, { adapt = { min = -3, max = 3 } })
    assert.are.equal("High", DMS.Director.skillFor("High"))
    assert.are.equal(4, DMS.Director.scaleCount(4))
    assert.are.equal(10, DMS.Director.scaleDelay(10))
    assert.are.equal("Random", DMS.Director.skillFor("Random"))
    assert.are.equal("Client", DMS.Director.skillFor("Client"))
    assert.are.equal("weird", DMS.Director.skillFor("weird"))
    assert.are.equal(0, DMS.Director.scaleCount(0))
    DMS.Director.adapt(0.4, "below half a tier")
    assert.are.equal("High", DMS.Director.skillFor("High"))
    DMS.Director.adapt(0.2, "rounds up")
    assert.are.equal("Excellent", DMS.Director.skillFor("High"))
    DMS.Director.adapt(-3.6, "to -3")
    assert.are.equal(-3, DMS.Director.level())
    assert.are.equal("Average", DMS.Director.skillFor("Excellent"))
    assert.are.equal(1, DMS.Director.scaleCount(1))
    assert.are.equal(1, DMS.Director.scaleCount(4))
    assert.are.equal(17.5, DMS.Director.scaleDelay(10))
    DMS.Director.adapt(6, "to +3")
    assert.are.equal(3, DMS.Director.level())
    assert.are.equal(7, DMS.Director.scaleCount(4))
    assert.are.equal(2.5, DMS.Director.scaleDelay(10))
  end)

  it("50 seeds: multiple flights are independent; flights() is sorted", function()
    for seed = 1, SEEDS do
      reboot(seed, { peak = 70, peakHoldSec = 10, relaxSec = { 20, 40 } })
      local ctx = "seed " .. seed
      local names = { "Hog1", "Viper2", "Apache1" }
      for i, n in ipairs(names) do
        spawnPlayer(n, i * 50000, 0)
      end
      assert.are.same({ "Apache1", "Hog1", "Viper2" }, DMS.Director.flights(), ctx)
      local hot = names[1 + seed % 3]
      local amounts = {}
      for _, n in ipairs(names) do
        amounts[n] = n == hot and 80 or DMS.Rng.int(0, 60)
        DMS.Director.addIntensity(n, amounts[n], "test")
      end
      for _, n in ipairs(names) do
        assert.are.equal(n == hot and "PEAK" or "BUILD_UP", DMS.Director.state(n), ctx .. " " .. n)
        assert.are.equal(amounts[n], DMS.Director.intensity(n), ctx)
        assert.are.equal(n ~= hot, (DMS.Director.canSpawn(1, n)), ctx .. " " .. n)
      end
      assert.are.equal("PEAK", DMS.Director.state(), ctx)
      assert.are.equal(80, DMS.Director.intensity(), ctx)
      MOCK.advance(11)
      for _, n in ipairs(names) do
        assert.are.equal(n == hot and "RELAX" or "BUILD_UP", DMS.Director.state(n), ctx .. " " .. n)
        assert.near(math.max(0, amounts[n] - 11 * 1.5), DMS.Director.intensity(n), 1e-9, ctx)
      end
      assert.are.equal(0, #MOCK.rawErrors, ctx)
    end
  end)

  it("player leaving mid-PEAK drops the flight and unblocks aggregate spawns", function()
    reboot(3, { peak = 70 })
    spawnPlayer("Viper1", 0, 0)
    spawnPlayer("Hog1", 90000, 0)
    local ev = record()
    DMS.Director.addIntensity("Viper1", 80, "test")
    assert.are.equal("PEAK", DMS.Director.state())
    assert.is_false(DMS.Director.canSpawn(1))
    MOCK.fireEvent({ id = "PLAYER_LEAVE_UNIT", initiator = Unit.getByName("Viper1-1") })
    assert.are.same({ "Hog1", "Viper1" }, DMS.Director.flights()) -- death window
    MOCK.advance(DMS.Director.LEFT_GRACE_SEC + 1)
    assert.are.same({ "Hog1" }, DMS.Director.flights())
    assert.are.equal("BUILD_UP", DMS.Director.state())
    assert.are.equal("BUILD_UP", DMS.Director.state("Viper1"))
    assert.are.equal(0, DMS.Director.intensity("Viper1"))
    assert.is_true(DMS.Director.canSpawn(1))
    MOCK.advance(200)
    assert.are.equal(1, #ev) -- only the PEAK; the dropped flight never transitions again
    assert.is_nil(next(DMS.Director._recentLeft))
    assert.truthy(MOCK.logContains("Flight 'Viper1' removed"))
    -- rejoining starts a fresh flight
    DMS.Bus.emit("player.spawned", { unit = "Viper1-1", group = "Viper1" })
    assert.are.equal("BUILD_UP", DMS.Director.state("Viper1"))
    assert.are.equal(0, DMS.Director.intensity("Viper1"))
  end)

  it("player death keeps the flight for a breather, then prunes it; respawn resumes pacing", function()
    reboot(5, { peak = 70, peakHoldSec = 15, relaxSec = { 40, 40 } })
    spawnPlayer("Viper1", 0, 0)
    hit("Viper1")
    hit("Viper1") -- 50
    MOCK.killUnit("Viper1-1") -- +40 -> PEAK; bus also emits player.left
    assert.are.equal("PEAK", DMS.Director.state("Viper1"))
    assert.are.same({ "Viper1" }, DMS.Director.flights())
    assert.is_nil(next(DMS.Director._unitFlight))
    assert.truthy(DMS.Director.level() < 0)
    MOCK.advance(20)
    assert.are.equal("RELAX", DMS.Director.state("Viper1"))
    spawnPlayer("Viper1", 0, 0) -- respawn into the same group mid-RELAX
    assert.are.equal("RELAX", DMS.Director.state("Viper1"))
    assert.are.equal(1, DMS.Director._flights.Viper1.units)
    MOCK.advance(200)
    assert.are.equal("BUILD_UP", DMS.Director.state("Viper1"))
    assert.are.same({ "Viper1" }, DMS.Director.flights()) -- live again: not pruned
    -- die again without respawn: pruned once back in BUILD_UP
    MOCK.killUnit("Viper1-1")
    assert.are.same({ "Viper1" }, DMS.Director.flights())
    MOCK.advance(300)
    assert.are.same({}, DMS.Director.flights())
    assert.truthy(MOCK.logContains("Flight 'Viper1' pruned"))
  end)

  it("multi-unit flights: duplicate BIRTH is idempotent, the flight lives until its last unit leaves", function()
    reboot(1, {})
    DMS.Bus.emit("player.spawned", { unit = "V-1", group = "V" })
    DMS.Bus.emit("player.spawned", { unit = "V-1", group = "V" })
    DMS.Bus.emit("player.spawned", { unit = "V-2", group = "V" })
    assert.are.equal(2, DMS.Director._flights.V.units)
    DMS.Director.addIntensity("V", 80, "test")
    DMS.Bus.emit("player.left", { unit = "V-1", group = "V" })
    assert.are.equal("PEAK", DMS.Director.state("V"))
    DMS.Bus.emit("player.left", { unit = "V-1", group = "V" }) -- duplicate leave: no-op
    assert.are.same({ "V" }, DMS.Director.flights())
    -- a unit switching flights moves its count
    DMS.Bus.emit("player.spawned", { unit = "V-2", group = "W" })
    assert.are.same({ "W" }, DMS.Director.flights())
    DMS.Bus.emit("player.left", { unit = "V-2", group = "W" })
    MOCK.advance(DMS.Director.LEFT_GRACE_SEC + 1)
    assert.are.same({}, DMS.Director.flights())
  end)

  it("player.left then unit.dead within the window still counts as a player death", function()
    reboot(5, { peak = 70, peakHoldSec = 15, relaxSec = { 40, 40 } })
    spawnPlayer("Viper1", 0, 0)
    DMS.Director.addIntensity("Viper1", 50, "test")
    local lvl = DMS.Director.level()
    MOCK.fireEvent({ id = "PLAYER_LEAVE_UNIT", initiator = Unit.getByName("Viper1-1") })
    MOCK.advance(3)
    MOCK.killUnit("Viper1-1", { crash = true }) -- +playerDead -> PEAK
    assert.are.equal("PEAK", DMS.Director.state("Viper1"))
    assert.truthy(DMS.Director.level() < lvl)
    assert.truthy(MOCK.logContains("Player death in flight 'Viper1'"))
    MOCK.advance(20) -- past LEFT_GRACE_SEC and peakHoldSec
    assert.are.same({ "Viper1" }, DMS.Director.flights()) -- kept for the breather, not deleted
    assert.are.equal("RELAX", DMS.Director.state("Viper1"))
  end)

  it("a death after the window is not a player death", function()
    reboot(5, {})
    spawnPlayer("Viper1", 0, 0)
    local lvl = DMS.Director.level()
    MOCK.fireEvent({ id = "PLAYER_LEAVE_UNIT", initiator = Unit.getByName("Viper1-1") })
    MOCK.advance(DMS.Director.LEFT_GRACE_SEC + 1)
    MOCK.killUnit("Viper1-1", { crash = true })
    assert.are.same({}, DMS.Director.flights())
    assert.are.equal(lvl, DMS.Director.level())
    assert.falsy(MOCK.logContains("Player death in flight"))
  end)

  it("ejection counts once as a player death (then leave and crash are no-ops)", function()
    reboot(5, { peak = 70 })
    spawnPlayer("Viper1", 0, 0)
    DMS.Director.addIntensity("Viper1", 50, "test")
    local u = Unit.getByName("Viper1-1")
    MOCK.fireEvent({ id = "EJECTION", initiator = u })
    assert.are.equal("PEAK", DMS.Director.state("Viper1"))
    local lvl = DMS.Director.level()
    MOCK.fireEvent({ id = "PLAYER_LEAVE_UNIT", initiator = u })
    MOCK.advance(2)
    MOCK.killUnit("Viper1-1", { crash = true })
    assert.are.equal(lvl, DMS.Director.level())
    assert.are.same({ "Viper1" }, DMS.Director.flights())
  end)

  it("pilot dead after player.left counts as a player death", function()
    reboot(5, { peak = 70 })
    spawnPlayer("Viper1", 0, 0)
    DMS.Director.addIntensity("Viper1", 50, "test")
    local u = Unit.getByName("Viper1-1")
    MOCK.fireEvent({ id = "PLAYER_LEAVE_UNIT", initiator = u })
    MOCK.fireEvent({ id = "PILOT_DEAD", initiator = u })
    assert.are.equal("PEAK", DMS.Director.state("Viper1"))
    assert.truthy(MOCK.logContains("pilot dead, unit Viper1-1"))
  end)

  it("disabled director is a passthrough: budget only, no flights, no pacing, no adaptation", function()
    reboot(1, { enabled = false }, { spawnsPerMin = 3 })
    local ev = record()
    spawnPlayer("Viper1", 0, 0)
    for _ = 1, 5 do
      hit("Viper1")
    end
    for _ = 1, 40 do
      DMS.Bus.emit("unit.dead", { unit = "e", group = "eg", coalition = 1, pos = { x = 0, y = 0, z = 0 } })
    end
    MOCK.advance(400)
    assert.are.same({}, DMS.Director.flights())
    assert.are.equal(0, #ev)
    assert.are.equal(0, DMS.Director.level())
    assert.are.equal("High", DMS.Director.skillFor("High"))
    assert.are.equal(4, DMS.Director.scaleCount(4))
    assert.are.equal(10, DMS.Director.scaleDelay(10))
    assert.is_nil(DMS.Director._tick)
    for i = 1, 3 do
      assert.is_true(DMS.Director.canSpawn(1), "spawn " .. i)
      DMS.Bus.emit("spawner.spawned", { group = "g", cost = 1 })
    end
    local ok, why = DMS.Director.canSpawn(1)
    assert.is_false(ok)
    assert.are.equal("budget", why)
    MOCK.advance(60)
    assert.is_true(DMS.Director.canSpawn(1))
    assert.truthy(MOCK.logContains("%[Director%] Started disabled"))
  end)

  it("ambient groups never move pacing or difficulty", function()
    reboot(1, {})
    local realAmbient = DMS.Ambient
    DMS.Ambient = {
      isAmbient = function(g)
        return g == "amb"
      end,
    }
    spawnPlayer("Viper1", 0, 0)
    MOCK.addGroup({ name = "amb", coalition = 1, category = "ground", units = { { name = "amb-1", x = 500, y = 0 } } })
    DMS.Bus.emit("unit.dead", { unit = "amb-1", group = "amb", coalition = 1, pos = { x = 500, y = 0, z = 0 } })
    DMS.Bus.emit("unit.shot", { initiator = "amb-1", initiatorGroup = "amb", coalition = 1, weapon = "SA-8" })
    local i, l = DMS.Director.intensity("Viper1"), DMS.Director.level()
    DMS.Ambient = realAmbient
    assert.are.equal(0, i)
    assert.are.equal(0, l)
    -- the same events from a non-ambient group do count
    DMS.Bus.emit("unit.dead", { unit = "x-1", group = "x", coalition = 1, pos = { x = 500, y = 0, z = 0 } })
    assert.are.equal(8, DMS.Director.intensity("Viper1"))
    assert.truthy(DMS.Director.level() > 0)
  end)

  it("calm bonus is not banked while no player is flying", function()
    reboot(1, { calmSec = 300 })
    MOCK.advance(400)
    spawnPlayer("Viper1")
    MOCK.advance(295)
    assert.are.equal(0, DMS.Director.level())
    MOCK.advance(10)
    assert.are.equal(0.25, DMS.Director.level())
    hit("Viper1") -- damage resets the calm clock
    local l = DMS.Director.level()
    MOCK.advance(299)
    assert.are.equal(l, DMS.Director.level())
  end)

  it("aggregate state is deterministic: ties go to the more restrictive state", function()
    reboot(1, {})
    DMS.Bus.emit("player.spawned", { unit = "B-1", group = "B" })
    DMS.Bus.emit("player.spawned", { unit = "A-1", group = "A" })
    DMS.Director._flights.B.state = "RELAX"
    assert.are.equal("RELAX", DMS.Director.state())
    DMS.Director._flights.A.state = "PEAK"
    assert.are.equal("PEAK", DMS.Director.state())
    DMS.Director._flights.A.intensity = 1
    DMS.Director._flights.A.state = "BUILD_UP"
    assert.are.equal("BUILD_UP", DMS.Director.state())
  end)

  it("same seed, same event history (replayable)", function()
    local function run()
      reboot(4242, { peak = 60, relaxSec = { 20, 80 } })
      local ev = record()
      spawnPlayer("Viper1", 0, 0)
      spawnPlayer("Hog1", 5000, 0)
      for step = 1, 300 do
        if DMS.Rng.chance(20) then
          DMS.Director.addIntensity(DMS.Rng.chance(50) and "Viper1" or "Hog1", DMS.Rng.int(5, 40), "r")
        end
        MOCK.advance(1 + step % 3)
      end
      local parts = {}
      for _, e in ipairs(ev) do
        parts[#parts + 1] = string.format("%.0f:%s:%s", e.t, e.flight, e.state)
      end
      return table.concat(parts, ","), #ev
    end
    local a, n = run()
    local b = run()
    assert.truthy(n > 6, "too few transitions: " .. n)
    assert.are.equal(a, b)
  end)
end)
