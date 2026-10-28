-- cap_spec.lua: scenario tests for the CAP encounter kind (DMS.Encounters, kind = "cap").

local A = AI.Option.Air

local function baseConfig()
  return {
    seed = 1,
    players = { coalition = 2 },
    budgets = { maxActiveGround = 200, maxActiveAir = 16, spawnsPerMin = 3 },
    director = { enabled = true, peak = 70, relaxSec = { 40, 90 }, decayPerSec = 1.5, adapt = { min = -1, max = 1 } },
    intel = { fogOfWar = true },
    templates = {
      mig29 = {
        country = "RUSSIA",
        category = "airplane",
        skill = "High",
        units = { { type = "MiG-29S" }, { type = "MiG-29S", dx = -200, dy = 200 } },
      },
      su27 = { country = "RUSSIA", category = "airplane", units = { { type = "Su-27" } } },
    },
    zones = {
      station = { kind = "circle", x = 100000, y = 0, radius = 20000 },
      airfield = { kind = "circle", x = 200000, y = 50000, radius = 5000 },
    },
    pools = {
      fighters = {
        members = { { tpl = "mig29", w = 2 }, { tpl = "su27", w = 1 } },
        pick = { 1, 2 },
        zones = { "airfield" },
      },
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

local function capture(evName)
  local list = {}
  DMS.Bus.on(evName, function(ev)
    list[#list + 1] = ev
  end)
  return list
end

local function ctrl(g)
  return Group.getByName(g):getController()
end

local function findTask(tasks, id)
  for _, t in ipairs(tasks or {}) do
    if t.id == id then
      return t
    end
  end
  return nil
end

-- move every unit of a group to (x, y)
local function moveGroup(g, x, y)
  for i, un in ipairs(MOCK.groups[g].units) do
    if not MOCK.units[un].dead then
      MOCK.moveUnit(un, x + i * 100, y)
    end
  end
end

local function dist(a, b)
  return math.sqrt((a.x - b.x) ^ 2 + (a.y - b.y) ^ 2)
end

local function capDef(extra)
  local d = {
    id = "cap",
    kind = "cap",
    template = "mig29",
    spawnZone = "airfield",
    zone = "station",
    orbit = { pattern = "Race-Track", legM = 30000, headingDeg = 90, altM = 8000, speed = 230 },
    trigger = { type = "time", afterSec = 5 },
  }
  for k, v in pairs(extra or {}) do
    d[k] = v
  end
  return d
end

describe("Encounters CAP", function()
  it("tasks a race-track orbit with an EngageTargetsInZone en-route task and air options", function()
    boot({ capDef({ engageRadiusM = 45000 }) })
    local spawned = capture("encounter.spawned")
    MOCK.spawnPlayer({ name = "Viper1-1", group = "Viper1", x = 0, y = 0, alt = 3000 })
    MOCK.advance(8)
    assert.are.equal(1, #spawned)
    assert.are.equal("cap", spawned[1].kind)
    local g = spawned[1].groups[1]
    assert.are.equal(0, MOCK.groups[g].category) -- Group.Category.AIRPLANE
    local t = ctrl(g).task
    assert.are.equal("Mission", t.id)
    local pts = t.params.route.points
    assert.are.equal(2, #pts)
    assert.are.equal(8000, pts[2].alt)
    assert.are.equal("BARO", pts[2].alt_type)
    assert.are.equal(230, pts[2].speed)
    local engage = findTask(pts[1].task.params.tasks, "EngageTargetsInZone")
    assert.is_not_nil(engage)
    assert.are.equal(100000, engage.params.point.x)
    assert.are.equal(0, engage.params.point.y)
    assert.are.equal(45000, engage.params.zoneRadius)
    assert.are.equal("Air", engage.params.targetTypes[1])
    local orbit = findTask(pts[2].task.params.tasks, "Orbit")
    assert.is_not_nil(orbit)
    assert.are.equal(AI.Task.OrbitPattern.RACE_TRACK, orbit.params.pattern)
    assert.near(30000, dist(orbit.params.point, orbit.params.point2), 0.01)
    assert.near(100000, (orbit.params.point.x + orbit.params.point2.x) / 2, 0.01)
    assert.are.equal(8000, orbit.params.altitude)
    assert.are.equal(230, orbit.params.speed)
    local o = ctrl(g).options
    assert.are.equal(A.val.ROE.OPEN_FIRE, o[A.id.ROE])
    assert.are.equal(A.val.REACTION_ON_THREAT.EVADE_FIRE, o[A.id.REACTION_ON_THREAT])
    assert.is_true(o[A.id.RTB_ON_BINGO])
    assert.is_true(o[A.id.PROHIBIT_AG])
  end)

  it("circle pattern, custom ROE/reaction, unknown enum falls back with a warning", function()
    boot({
      capDef({
        orbit = { pattern = "Circle" },
        roe = "WEAPON_FREE",
        reaction = "NOPE",
        point = { x = 50000, y = 9000 },
        zone = nil,
      }),
    })
    local spawned = capture("encounter.spawned")
    MOCK.advance(8)
    local g = spawned[1].groups[1]
    local orbit = findTask(ctrl(g).task.params.route.points[2].task.params.tasks, "Orbit")
    assert.are.equal("Circle", orbit.params.pattern)
    assert.is_nil(orbit.params.point2)
    assert.are.equal(50000, orbit.params.point.x)
    assert.are.equal(9000, orbit.params.point.y)
    assert.are.equal(A.val.ROE.WEAPON_FREE, ctrl(g).options[A.id.ROE])
    assert.are.equal(A.val.REACTION_ON_THREAT.EVADE_FIRE, ctrl(g).options[A.id.REACTION_ON_THREAT])
    assert.is_true(MOCK.logContains("NOPE"))
  end)

  it("on station -> time on station -> RTB home -> despawn, then one relief up to maxSpawns", function()
    boot({ capDef({ timeOnStationSec = 300, maxSpawns = 2, replaceDelaySec = 30, rtbDespawnSec = 200 }) })
    local spawned, onSt, rtb, gone =
      capture("encounter.spawned"),
      capture("encounter.cap_on_station"),
      capture("encounter.cap_rtb"),
      capture("encounter.cap_despawned")
    MOCK.advance(8)
    local g = spawned[1].groups[1]
    local home = { x = MOCK.units[g .. "-1"].x, y = MOCK.units[g .. "-1"].z }
    MOCK.advance(30)
    assert.are.equal(0, #onSt)
    moveGroup(g, 100000, 0)
    MOCK.advance(11)
    assert.are.equal(1, #onSt)
    MOCK.advance(280)
    assert.are.equal(0, #rtb)
    MOCK.advance(30)
    assert.are.equal(1, #rtb)
    assert.are.equal(A.val.ROE.RETURN_FIRE, ctrl(g).options[A.id.ROE])
    local pts = ctrl(g).task.params.route.points
    assert.near(home.x, pts[2].x, 0.01)
    assert.near(home.y, pts[2].y, 0.01)
    MOCK.advance(40) -- relief launched 30 s after RTB
    assert.are.equal(2, #spawned)
    moveGroup(g, home.x, home.y)
    MOCK.advance(11)
    assert.are.equal(1, #gone)
    assert.is_false(DMS.Registry.isAlive(g))
    -- the relief goes on station and leaves too; no third group (maxSpawns = 2)
    moveGroup(spawned[2].groups[1], 100000, 0)
    MOCK.advance(2000)
    assert.are.equal(2, #spawned)
    assert.are.equal(2, #rtb)
  end)

  it("despawn waits while an enemy player is close", function()
    boot({ capDef({ timeOnStationSec = 60, rtbDespawnSec = 100 }) })
    local spawned, gone = capture("encounter.spawned"), capture("encounter.cap_despawned")
    MOCK.spawnPlayer({ name = "Viper1-1", group = "Viper1", x = 0, y = 0, alt = 3000 })
    MOCK.advance(8)
    local g = spawned[1].groups[1]
    moveGroup(g, 100000, 0)
    MOCK.advance(80)
    MOCK.moveUnit("Viper1-1", 100000, 3000) -- player sits right next to the RTB'ing CAP
    MOCK.advance(300)
    assert.are.equal(0, #gone)
    assert.is_true(DMS.Registry.isAlive(g))
    MOCK.moveUnit("Viper1-1", -100000, 0)
    MOCK.advance(20)
    assert.are.equal(1, #gone)
  end)

  it("replaces losses up to maxSpawns, then clears", function()
    boot({ capDef({ maxSpawns = 3, replaceDelaySec = { 20, 40 } }) })
    local spawned, lost, cleared =
      capture("encounter.spawned"), capture("encounter.cap_lost"), capture("encounter.cleared")
    MOCK.advance(8)
    for i = 1, 3 do
      assert.are.equal(i, #spawned)
      MOCK.killGroup(spawned[i].groups[1])
      if i < 3 then
        assert.are.equal(0, #cleared)
      end
      MOCK.advance(80)
    end
    assert.are.equal(3, #lost)
    assert.are.equal(3, #spawned)
    assert.are.equal(1, #cleared)
    MOCK.advance(1000)
    assert.are.equal(3, #spawned)
  end)

  it("pool CAP: initial pick is clamped to maxSpawns", function()
    boot({ capDef({ template = false, pool = "fighters", maxSpawns = 1 }) }, function(c)
      c.pools.fighters.pick = 4
    end)
    DMS_CONFIG.encounters[1].template = nil
    local spawned = capture("spawner.spawned")
    MOCK.advance(8)
    assert.are.equal(1, #spawned)
  end)

  it("director refusal past maxDeferSec drops the launch (budget never forced)", function()
    boot({ capDef({ maxDeferSec = 60 }) })
    local real = DMS.Director.canSpawn
    DMS.Director.canSpawn = function()
      return false, "PEAK"
    end
    local spawned, cleared = capture("encounter.spawned"), capture("encounter.cleared")
    MOCK.advance(120)
    DMS.Director.canSpawn = real
    MOCK.advance(300)
    assert.are.equal(0, #spawned)
    assert.are.equal(0, #cleared)
    assert.are.equal(0, DMS.Encounters.get("cap").pending)
    assert.is_true(MOCK.logContains("spawn skipped"))
  end)

  it("warns and does nothing without a station", function()
    boot({ capDef({ zone = "nope" }) })
    local spawned = capture("encounter.spawned")
    MOCK.advance(10)
    assert.are.equal(0, #spawned)
    assert.is_true(MOCK.logContains("no station"))
  end)

  it("runs 200 seeds: spawn limit, director budget and air tasking invariants hold", function()
    local totalGroups, totalRtb = 0, 0
    for seed = 1, 200 do
      DMS.Bus.uninstall()
      MOCK.reset()
      DMS.Bus.install()
      -- fresh registry per seed (otherwise tracked groups pile up across seeds)
      DMS.Registry._groups, DMS.Registry._counters, DMS.Registry._allocated, DMS.Registry._spawnTimes = {}, {}, {}, {}
      local maxSpawns = 2 + seed % 4
      local encs = {
        capDef({
          id = "capA",
          maxSpawns = maxSpawns,
          timeOnStationSec = { 150, 400 },
          replaceDelaySec = { 20, 90 },
          orbit = {
            pattern = (seed % 2 == 0) and "Race-Track" or "Circle",
            legM = { 20000, 40000 },
            altM = { 5000, 9000 },
          },
          trigger = { type = "time", afterSec = { 1, 60 } },
        }),
        capDef({
          id = "capB",
          template = nil,
          pool = "fighters",
          maxSpawns = 3,
          chance = 70,
          trigger = { type = "director", state = "RELAX" },
        }),
      }
      boot(encs, function(c)
        c.seed = seed
        c.budgets.spawnsPerMin = 1 + seed % 3
        c.zones.station.x = 80000 + (seed % 5) * 10000
      end)
      local costs = {}
      local violations = {}
      local tok = DMS.Bus.on("spawner.spawned", function(ev)
        local now = DMS.Clock.now()
        costs[#costs + 1] = { t = now, cost = ev.cost or 1 }
        local sum = 0
        for _, s in ipairs(costs) do
          if now - s.t < 60 then
            sum = sum + s.cost
          end
        end
        if sum > DMS.Director.spawnBudget() + 1e-9 then
          violations[#violations + 1] = string.format("t=%.0f sum=%d budget=%.2f", now, sum, DMS.Director.spawnBudget())
        end
      end)
      MOCK.spawnPlayer({ name = "Viper1-1", group = "Viper1", x = 0, y = 0, alt = 3000 })
      MOCK.addGroup({
        name = "shooter",
        coalition = 1,
        category = "ground",
        units = { { name = "shooter-1", x = 0, y = -90000 } },
        silent = true,
      })
      for step = 1, 100 do
        -- fly every transiting CAP to its station; randomly shoot some down
        for _, id in ipairs({ "capA", "capB" }) do
          local st = DMS.Encounters.get(id)
          for _, g in ipairs(st.capOrder or {}) do
            local rec = st.cap[g]
            if DMS.Registry.isAlive(g) then
              if rec.state == "transit" and step % 3 == 0 then
                moveGroup(g, st.capStation.center.x, st.capStation.center.y)
              end
              if DMS.Rng.random() < 0.01 then
                MOCK.killGroup(g)
              end
            end
          end
        end
        if step % 17 == 0 then
          for _ = 1, 3 do
            MOCK.hitUnit("Viper1-1", { initiator = "shooter-1", damage = 0 })
          end
        end
        MOCK.advance(10)
      end
      DMS.Bus.off(tok)
      assert.are.equal(
        0,
        #violations,
        "seed " .. seed .. " director budget exceeded: " .. table.concat(violations, "; ")
      )
      for _, l in ipairs(MOCK.log) do
        assert.truthy(l.level ~= "error", "seed " .. seed .. ": " .. tostring(l.msg))
      end
      assert.are.equal(0, #MOCK.rawErrors, "raw errors at seed " .. seed)
      local stA, stB = DMS.Encounters.get("capA"), DMS.Encounters.get("capB")
      assert.truthy(stA.capSpawned <= maxSpawns, "seed " .. seed .. " capA spawned " .. stA.capSpawned)
      assert.truthy((stB.capSpawned or 0) <= 3, "seed " .. seed .. " capB spawned " .. tostring(stB.capSpawned))
      assert.truthy(stA.capSpawned + stA.capQueued <= maxSpawns, "seed " .. seed .. " capA queued past the limit")
      assert.truthy(stA.capQueued >= 0 and (stB.capQueued or 0) >= 0)
      for _, st in ipairs({ stA, stB }) do
        for _, g in ipairs(st.capOrder or {}) do
          totalGroups = totalGroups + 1
          local rec = st.cap[g]
          if rec.rtbAt then
            totalRtb = totalRtb + 1
          end
          assert.truthy(rec.tasked or rec.state == "dead", "seed " .. seed .. " untasked " .. g)
          if rec.tasked and rec.state ~= "dead" and rec.state ~= "gone" then
            local c = ctrl(g)
            local pts = c.task.params.route.points
            assert.truthy(#pts >= 2)
            for _, p in ipairs(pts) do
              assert.are.equal("BARO", p.alt_type)
              assert.truthy(p.alt >= 5000 and p.alt <= 9000, "seed " .. seed .. " alt " .. tostring(p.alt))
            end
            local roe = c.options[A.id.ROE]
            assert.truthy(roe == A.val.ROE.OPEN_FIRE or roe == A.val.ROE.RETURN_FIRE)
          end
        end
      end
    end
    assert.truthy(totalGroups > 400, "too few CAP groups: " .. totalGroups)
    assert.truthy(totalRtb > 100, "too few RTBs: " .. totalRtb)
  end)
end)
