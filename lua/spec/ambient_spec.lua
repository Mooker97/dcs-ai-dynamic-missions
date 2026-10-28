-- ambient_spec.lua: DMS.Ambient (friendly base traffic) against the DCS mock with the fake clock.

local AB = { name = "Testbase", x = 0, y = 0 }
local PLAYER_SPOT = { x = -300, y = 200 }

local function parking()
  local spots = {}
  for i = 0, 11 do
    spots[#spots + 1] = { x = -300 + i * 60, y = 200, termType = (i % 4 == 3) and 40 or 104 }
  end
  return spots
end

local function ambientConfig(over)
  local site = {
    id = "testbase",
    airbase = AB.name,
    coalition = 2,
    country = "USA",
    activeRadiusM = 8000,
    despawnRadiusM = 12000,
    maxGroups = 8,
    maxUnits = 16,
    avoid = { { x = PLAYER_SPOT.x, y = PLAYER_SPOT.y, radiusM = 60 } },
    layers = {
      departures = { count = 1, types = { "C-130" }, intervalSec = { 100, 200 }, distanceM = 40000 },
      arrivals = { count = 1, types = { "C-130" }, intervalSec = { 100, 200 }, distanceM = 25000 },
      ground = { count = 3, types = { "M978 HEMTT Tanker", "Hummer" }, radiusM = 500, speed = 4 },
      helo = { count = 1, types = { "UH-60A" }, radiusM = 3000 },
      statics = { count = 2, types = { "FARP Fuel Depot" }, radiusM = 400 },
    },
  }
  for k, v in pairs(over or {}) do
    site[k] = v
  end
  return {
    enabled = true,
    checkSec = 5,
    graceSec = 30,
    staggerSec = 2,
    departureDelaySec = 600,
    maxGroups = 12,
    maxUnits = 24,
    sites = { site },
  }
end

local function boot(mutate)
  DMS_CONFIG = {
    seed = 3,
    missionId = "amb",
    budgets = { maxActiveGround = 40, maxActiveAir = 8, spawnsPerMin = 3 },
    players = { coalition = 2 },
    intel = { fogOfWar = true },
    ambient = ambientConfig(),
  }
  if mutate then
    mutate(DMS_CONFIG)
  end
  MOCK.addAirbase({ name = AB.name, x = AB.x, y = AB.y, coalition = 2, id = 7, parking = parking() })
  DMS.Bus.install()
  DMS.Rng.seed(DMS_CONFIG.seed)
  DMS.Director.reset()
  DMS.Director.start()
  DMS.Ambient.reset()
  return DMS.Ambient.start()
end

local function player(x, y)
  return MOCK.spawnPlayer({ name = "Dusty1-1", group = "Dusty1", category = "helicopter", x = x, y = y, alt = 0 })
end

local function owned()
  return DMS.Ambient.owned("testbase")
end

local function kindsOf()
  local out = {}
  for name, o in pairs(DMS.Ambient._s.owners) do
    out[o.kind] = (out[o.kind] or 0) + 1
    out[name] = o.kind
  end
  return out
end

local function unitOf(group)
  return MOCK.groups[group].units[1]
end

local function surfaceAt(x, y)
  return land.getSurfaceType({ x = x, y = y })
end

describe("DMS.Ambient", function()
  it("is inert without DMS_CONFIG.ambient or with enabled=false", function()
    DMS_CONFIG = { missionId = "x" }
    assert.is_false(DMS.Ambient.start())
    DMS_CONFIG = { missionId = "x", ambient = { enabled = false, sites = {} } }
    assert.is_false(DMS.Ambient.start())
  end)

  it("activates when the player is near, staggering spawns, and keeps the director untouched", function()
    assert.is_true(boot())
    player(PLAYER_SPOT.x, PLAYER_SPOT.y)
    local acts = {}
    DMS.Bus.on("ambient.activated", function(ev)
      acts[#acts + 1] = ev
    end)
    MOCK.advance(3)
    assert.is_true(DMS.Ambient.isActive("testbase"))
    assert.are.equal(1, #acts)
    assert.are.equal("testbase", acts[1].site)
    -- staggered: only the first item exists right after activation
    local g0, u0 = DMS.Ambient.counts("testbase")
    assert.is_true(g0 + u0 <= 2)
    MOCK.advance(60)
    local k = kindsOf()
    assert.are.equal(2, k.statics)
    assert.are.equal(3, k.ground)
    assert.are.equal(1, k.departures)
    assert.are.equal(1, k.helo)
    assert.is_nil(k.arrivals) -- runway gate closed: player has not taken off, delay not over
    -- not in the registry, no spawner.spawned, no director spawn cost
    assert.are.equal(0, #DMS.Registry.list())
    assert.are.equal(0, #DMS.Director._spawns)
    assert.is_true(MOCK.logContains("%[DMS%]%[Ambient%] Site 'testbase' activated"))
    assert.is_true(MOCK.logContains("skipped arrivals spawn %(runway gate closed"))
  end)

  it("parks departures uncontrolled on free spots outside the avoid circles, then starts them after takeoff", function()
    boot()
    local pu = player(PLAYER_SPOT.x, PLAYER_SPOT.y)
    MOCK.advance(60)
    local dep
    for name, o in pairs(DMS.Ambient._s.owners) do
      if o.kind == "departures" then
        dep = name
      end
    end
    assert.is_not_nil(dep)
    local data = MOCK.groups[dep].data
    assert.is_true(data.uncontrolled)
    assert.are.equal("TakeOffParking", data.route.points[1].type)
    assert.are.equal(7, data.route.points[1].airdromeId)
    local u = MOCK.units[unitOf(dep)]
    assert.is_true(math.sqrt((u.x - PLAYER_SPOT.x) ^ 2 + (u.z - PLAYER_SPOT.y) ^ 2) >= 60)
    assert.is_not_nil(data.units[1].parking)
    -- no Start before the gate opens
    MOCK.advance(300)
    assert.are.equal(0, #MOCK.callsTo("Controller.setCommand", dep) - 2) -- only SetImmortal/SetInvisible
    MOCK.moveUnit("Dusty1-1", PLAYER_SPOT.x, PLAYER_SPOT.y, 100)
    MOCK.fireEvent({ id = world.event.S_EVENT_TAKEOFF, initiator = pu, place = Airbase.getByName(AB.name) })
    assert.is_true(DMS.Ambient.runwayGateOpen())
    MOCK.advance(300)
    local started = false
    for _, c in ipairs(MOCK.callsTo("Controller.setCommand", dep)) do
      if c.args[1].id == "Start" then
        started = true
      end
    end
    assert.is_true(started)
    assert.is_true((kindsOf().arrivals or 0) >= 1)
    -- every ambient group: immortal, invisible, weapons hold
    for name in pairs(MOCK.groups) do
      if DMS.Ambient.isAmbient(name) and Group.getByName(name) then
        local ctrl = Group.getByName(name):getController()
        local ids = {}
        for _, c in ipairs(ctrl.commands) do
          ids[c.id] = true
        end
        assert.is_true(ids.SetImmortal and ids.SetInvisible and true or false)
        assert.is_not_nil(ctrl.options[0]) -- ROE
      end
    end
  end)

  it("removes a departure once it is far out and replaces it after the interval", function()
    boot(function(c)
      c.ambient.departureDelaySec = 0
    end)
    player(PLAYER_SPOT.x, PLAYER_SPOT.y)
    MOCK.advance(300)
    local dep
    for name, o in pairs(DMS.Ambient._s.owners) do
      if o.kind == "departures" then
        dep = name
      end
    end
    assert.is_not_nil(dep)
    MOCK.moveUnit(unitOf(dep), 35000, 0, 1500)
    MOCK.advance(6)
    assert.is_nil(Group.getByName(dep))
    MOCK.advance(260)
    local dep2
    for name, o in pairs(DMS.Ambient._s.owners) do
      if o.kind == "departures" then
        dep2 = name
      end
    end
    assert.is_not_nil(dep2)
    assert.are_not.equal(dep, dep2)
  end)

  it("lands arrivals with a Land waypoint and removes them after landing", function()
    boot(function(c)
      c.ambient.departureDelaySec = 0
    end)
    player(PLAYER_SPOT.x, PLAYER_SPOT.y)
    MOCK.advance(60)
    local arr
    for name, o in pairs(DMS.Ambient._s.owners) do
      if o.kind == "arrivals" then
        arr = name
      end
    end
    assert.is_not_nil(arr)
    local pts = MOCK.groups[arr].data.route.points
    assert.are.equal("Land", pts[#pts].type)
    local u = MOCK.units[unitOf(arr)]
    assert.is_true(math.sqrt(u.x * u.x + u.z * u.z) > 20000)
    MOCK.moveUnit(u.name, 0, 0, 0)
    MOCK.fireEvent({ id = world.event.S_EVENT_LAND, initiator = u.obj, place = Airbase.getByName(AB.name) })
    MOCK.advance(80)
    assert.is_not_nil(Group.getByName(arr))
    MOCK.advance(20)
    assert.is_nil(Group.getByName(arr))
  end)

  it("loops ground vehicles: a new route when the lead reaches its last point", function()
    boot()
    player(PLAYER_SPOT.x, PLAYER_SPOT.y)
    MOCK.advance(60)
    local gnd
    for name, o in pairs(DMS.Ambient._s.owners) do
      if o.kind == "ground" then
        gnd = name
      end
    end
    local rec = DMS.Ambient._s.sites.testbase.groups[gnd]
    local last = rec.loop[#rec.loop]
    MOCK.moveUnit(unitOf(gnd), last.x, last.y)
    local before = #MOCK.callsTo("Controller.setTask", gnd)
    MOCK.advance(6)
    assert.are.equal(before + 1, #MOCK.callsTo("Controller.setTask", gnd))
    assert.are.equal("Off Road", MOCK.groups[gnd].controller.task.params.route.points[1].action)
  end)

  it("hysteresis: stays active between the radii, despawns everything after the grace, re-activates", function()
    boot()
    player(PLAYER_SPOT.x, PLAYER_SPOT.y)
    local deacts = {}
    DMS.Bus.on("ambient.deactivated", function(ev)
      deacts[#deacts + 1] = ev
    end)
    MOCK.advance(60)
    local o = owned()
    assert.is_true(#o.groups > 0 and #o.statics > 0)
    MOCK.moveUnit("Dusty1-1", 10000, 0, 300) -- outside active, inside despawn
    MOCK.advance(300)
    assert.is_true(DMS.Ambient.isActive("testbase"))
    MOCK.moveUnit("Dusty1-1", 30000, 0, 300)
    MOCK.advance(20)
    assert.is_true(DMS.Ambient.isActive("testbase")) -- grace not over yet
    MOCK.advance(20)
    assert.is_false(DMS.Ambient.isActive("testbase"))
    assert.are.equal(1, #deacts)
    assert.are.equal("left", deacts[1].reason)
    for _, g in ipairs(o.groups) do
      assert.is_nil(Group.getByName(g))
    end
    for _, s in ipairs(o.statics) do
      assert.is_nil(StaticObject.getByName(s))
    end
    assert.are.equal(0, select(1, DMS.Ambient.counts()))
    assert.are.equal(0, select(2, DMS.Ambient.counts()))
    -- inside the despawn radius but outside the active radius: no re-activation
    MOCK.moveUnit("Dusty1-1", 10000, 0, 300)
    MOCK.advance(60)
    assert.is_false(DMS.Ambient.isActive("testbase"))
    MOCK.moveUnit("Dusty1-1", 500, 0, 0)
    MOCK.advance(10)
    assert.is_true(DMS.Ambient.isActive("testbase"))
    assert.are.equal(2, DMS.Ambient._s.sites.testbase.activations)
    assert.is_true(MOCK.logContains("deactivated %(left%): removed"))
  end)

  it("ignores red players and the director ignores ambient deaths", function()
    boot()
    MOCK.spawnPlayer({ name = "Red1-1", group = "Red1", coalition = 1, x = 0, y = 0 })
    MOCK.advance(30)
    assert.is_false(DMS.Ambient.isActive("testbase"))
    player(PLAYER_SPOT.x, PLAYER_SPOT.y)
    MOCK.advance(60)
    local gnd
    for name, o in pairs(DMS.Ambient._s.owners) do
      if o.kind == "ground" then
        gnd = name
      end
    end
    local before = DMS.Director.intensity()
    MOCK.killGroup(gnd)
    assert.are.equal(before, DMS.Director.intensity())
    assert.is_true(DMS.Ambient.isAmbient(gnd))
  end)

  it("DMS.Test ambient_cycle passes after an activation and a deactivation", function()
    boot(function(c)
      c.test = { enabled = true, minutes = 30, checks = { { kind = "ambient_cycle", name = "amb_cycle" } } }
    end)
    DMS.Test._reset()
    DMS.Test.start()
    player(PLAYER_SPOT.x, PLAYER_SPOT.y)
    MOCK.advance(60)
    assert.is_false(MOCK.logContains("%[DMS.TEST%] PASS amb_cycle"))
    MOCK.moveUnit("Dusty1-1", 40000, 0, 300)
    MOCK.advance(60)
    assert.is_true(MOCK.logContains("%[DMS.TEST%] PASS amb_cycle testbase%(act=1 deact=1%)"))
  end)

  it("DMS.Test ambient_cycle fails at the deadline without a cycle", function()
    boot(function(c)
      c.test = {
        enabled = true,
        minutes = 30,
        checks = { { kind = "ambient_cycle", name = "amb_cycle", deadlineSec = 100 } },
      }
    end)
    DMS.Test._reset()
    DMS.Test.start()
    player(PLAYER_SPOT.x, PLAYER_SPOT.y)
    MOCK.advance(120)
    assert.is_true(MOCK.logContains("%[DMS.TEST%] FAIL amb_cycle timeout: testbase%(act=1 deact=0%)"))
  end)

  it("runs 200 seeds: budgets, hysteresis, cleanup, re-activation, land-only, no director impact", function()
    local totalSpawned = 0
    for seed = 1, 200 do
      DMS.Bus.uninstall()
      MOCK.reset()
      DMS.Registry._groups, DMS.Registry._counters, DMS.Registry._allocated, DMS.Registry._spawnTimes = {}, {}, {}, {}
      DMS.Rng.seed(seed)
      local maxG = 2 + seed % 7
      local maxU = 3 + seed % 13
      local gMaxG = 1 + seed % 9
      local gMaxU = 2 + seed % 17
      -- water east of the base, a runway strip along y = 0
      MOCK.waterAreas = { { x = 0, y = -700, radius = 350 + (seed % 3) * 100 } }
      local base = land.getSurfaceType
      MOCK.surface = function(x, y)
        local dx, dy = x - 0, y - (-700)
        if dx * dx + dy * dy <= (350 + (seed % 3) * 100) ^ 2 then
          return land.SurfaceType.WATER
        end
        if math.abs(y) < 40 and math.abs(x) < 1500 then
          return land.SurfaceType.RUNWAY
        end
        return land.SurfaceType.LAND
      end
      local _ = base
      local ok = boot(function(c)
        c.seed = seed
        local a = c.ambient
        a.maxGroups, a.maxUnits = gMaxG, gMaxU
        a.staggerSec = 1 + seed % 3
        a.departureDelaySec = (seed % 2 == 0) and 0 or 600
        local s = a.sites[1]
        s.maxGroups, s.maxUnits = maxG, maxU
        s.activeRadiusM = 5000 + (seed % 4) * 1000
        s.despawnRadiusM = s.activeRadiusM + 3000
        s.layers.ground.count = 1 + seed % 5
        s.layers.statics.count = seed % 4
        s.layers.departures.count = seed % 3
        s.layers.arrivals.count = seed % 2
        s.layers.helo.count = (seed % 5 == 0) and 0 or 1
        if seed % 3 == 0 then
          c.templates = {
            hemtt_pair = {
              country = "USA",
              category = "ground",
              units = { { type = "M978 HEMTT Tanker" }, { type = "Hummer", dx = -15, dy = 0 } },
            },
          }
          s.layers.ground.templates = { "hemtt_pair" }
        end
      end)
      assert.is_true(ok)
      local spawnedEvents = 0
      DMS.Bus.on("spawner.spawned", function()
        spawnedEvents = spawnedEvents + 1
      end)
      local acts, deacts = 0, 0
      DMS.Bus.on("ambient.activated", function()
        acts = acts + 1
      end)
      DMS.Bus.on("ambient.deactivated", function()
        deacts = deacts + 1
      end)
      local site = DMS_CONFIG.ambient.sites[1]
      local function checkInvariants(label)
        local sg, su = DMS.Ambient.counts("testbase")
        assert.is_true(sg <= maxG, string.format("seed %d %s: site groups %d > %d", seed, label, sg, maxG))
        assert.is_true(su <= maxU, string.format("seed %d %s: site units %d > %d", seed, label, su, maxU))
        assert.is_true(sg <= gMaxG, string.format("seed %d %s: global groups %d > %d", seed, label, sg, gMaxG))
        assert.is_true(su <= gMaxU, string.format("seed %d %s: global units %d > %d", seed, label, su, gMaxU))
        if not DMS.Ambient.isActive("testbase") then
          assert.are.equal(0, sg + su, string.format("seed %d %s: inactive site owns objects", seed, label))
        end
        for name, o in pairs(DMS.Ambient._s.owners) do
          if o.kind == "ground" then
            for _, un in ipairs(MOCK.groups[name].units) do
              local u = MOCK.units[un]
              if not u.dead then
                local st = surfaceAt(u.x, u.z)
                assert.is_true(
                  st == land.SurfaceType.LAND,
                  string.format("seed %d: %s on surface %s", seed, un, tostring(st))
                )
              end
            end
          elseif o.kind == "statics" then
            local r = MOCK.statics[name]
            assert.are.equal(land.SurfaceType.LAND, surfaceAt(r.x, r.z))
          end
        end
      end
      local pu = player(PLAYER_SPOT.x, PLAYER_SPOT.y)
      for _ = 1, 24 do
        MOCK.advance(5)
        checkInvariants("start")
      end
      assert.is_true(DMS.Ambient.isActive("testbase"), "seed " .. seed .. ": not active with player on the base")
      if seed % 4 == 1 then
        MOCK.moveUnit("Dusty1-1", PLAYER_SPOT.x, PLAYER_SPOT.y, 100)
        MOCK.fireEvent({ id = world.event.S_EVENT_TAKEOFF, initiator = pu })
      end
      -- loiter between the radii: must stay active
      MOCK.moveUnit("Dusty1-1", site.activeRadiusM + 1000, 0, 300)
      for _ = 1, 30 do
        MOCK.advance(5)
        checkInvariants("between")
      end
      assert.is_true(DMS.Ambient.isActive("testbase"), "seed " .. seed .. ": deactivated inside despawn radius")
      totalSpawned = totalSpawned + #owned().groups + #owned().statics
      -- leave
      MOCK.moveUnit("Dusty1-1", site.despawnRadiusM + 5000 + seed * 10, 0, 300)
      for _ = 1, 12 do
        MOCK.advance(5)
        checkInvariants("leaving")
      end
      assert.is_false(DMS.Ambient.isActive("testbase"), "seed " .. seed .. ": still active after leaving")
      assert.are.equal(0, select(1, DMS.Ambient.counts()))
      for name, g in pairs(MOCK.groups) do
        if DMS.Ambient.isAmbient(name) then
          assert.is_nil(Group.getByName(name), "seed " .. seed .. ": " .. name .. " not destroyed")
          local _ = g
        end
      end
      for name, r in pairs(MOCK.statics) do
        if DMS.Ambient.isAmbient(name) then
          assert.is_true(r.dead == true, "seed " .. seed .. ": static " .. name .. " not destroyed")
        end
      end
      -- return
      MOCK.moveUnit("Dusty1-1", 200, 300, 0)
      for _ = 1, 24 do
        MOCK.advance(5)
        checkInvariants("return")
      end
      assert.is_true(DMS.Ambient.isActive("testbase"), "seed " .. seed .. ": no re-activation")
      assert.are.equal(2, acts)
      assert.are.equal(1, deacts)
      -- no director / registry impact
      assert.are.equal(0, spawnedEvents)
      assert.are.equal(0, #DMS.Director._spawns)
      assert.are.equal(0, #DMS.Registry.list())
      assert.are.equal(0, DMS.Director.intensity())
    end
    assert.is_true(totalSpawned > 200)
  end)
end)
