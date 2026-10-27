-- spawner_spec.lua: scenario tests for DMS.Spawner against the DCS mock.

local function config()
  DMS_CONFIG = {
    seed = 1,
    budgets = { maxActiveGround = 40, maxActiveAir = 8, spawnsPerMin = 100 },
    templates = {
      sa8 = { country = "RUSSIA", category = "ground", skill = "High",
        units = { { type = "Osa 9A33 ln", dx = 0, dy = 0 }, { type = "Ural-375", dx = 50, dy = 0 } } },
      zsu = { country = "RUSSIA", category = "ground", skill = "Average",
        units = { { type = "ZSU-23-4 Shilka", dx = 0, dy = 0 } } },
    },
    zones = {
      town = { kind = "circle", x = 0, y = 0, radius = 3000 },
      ridge = { kind = "polygon", points = { { x = 10000, y = 0 }, { x = 14000, y = 0 }, { x = 14000, y = 4000 }, { x = 10000, y = 4000 } } },
    },
    pools = { aaa = { members = { { tpl = "zsu", w = 3 }, { tpl = "sa8", w = 1 } }, pick = { 2, 4 }, zones = { "town", "ridge" } } },
    intel = { fogOfWar = true },
    players = { coalition = 2 },
  }
end

local function reset()
  config()
  DMS.Rng.seed(7)
end

local function unitPositions(name)
  local out = {}
  for _, un in ipairs(MOCK.groups[name].units) do
    local u = MOCK.units[un]
    out[#out + 1] = { x = u.x, z = u.z }
  end
  return out
end

local function player(name, x, y)
  MOCK.spawnPlayer({ name = name .. "-1", group = name, coalition = 2, x = x, y = y, alt = 3000 })
end

-- stripes of water every 700 m (x % 700 < 200) across the test area
local function stripes()
  MOCK.waterAreas = {}
  for x = -21000, 21000, 700 do
    MOCK.waterAreas[#MOCK.waterAreas + 1] = { points = { { x = x, y = -30000 }, { x = x + 200, y = -30000 },
      { x = x + 200, y = 30000 }, { x = x, y = 30000 } } }
  end
end

local function inStripe(x) return (x + 21000) % 700 < 200 and x >= -21000 and x <= 21200 end

describe("Spawner", function()
  before_each(reset)

  it("spawns a template in a circle zone with unique names and no ids", function()
    local a = DMS.Spawner.spawn("sa8", "town")
    local b = DMS.Spawner.spawn("sa8", "town")
    assert.is_not_nil(a)
    assert.is_not_nil(b)
    assert.truthy(a ~= b)
    assert.are.equal(2, #Group.getByName(a):getUnits())
    for _, p in ipairs(unitPositions(a)) do
      assert.truthy(math.sqrt(p.x * p.x + p.z * p.z) <= 3100)
    end
    local data = MOCK.groups[a].data
    assert.is_nil(data.groupId)
    assert.is_nil(data.units[1].unitId)
    assert.is_not_nil(DMS.Registry.get(a))
    assert.are.equal("ground", DMS.Registry.get(a).category)
  end)

  it("rotates unit offsets by heading", function()
    local name = DMS.Spawner.spawn("sa8", { x = 0, y = 0 }, { heading = 90, minPlayerDistM = 0 })
    local p = unitPositions(name)
    -- heading 90 deg (east): dx=50 forward becomes +50 on map y (vec3 z)
    assert.near(p[1].x, p[2].x, 0.01)
    assert.near(50, p[2].z - p[1].z, 0.01)
  end)

  it("places points inside polygon zones", function()
    for _ = 1, 30 do
      local name = DMS.Spawner.spawn("zsu", "ridge")
      local p = unitPositions(name)[1]
      assert.truthy(p.x >= 10000 and p.x <= 14000 and p.z >= 0 and p.z <= 4000)
    end
  end)

  it("resolves mission-editor quad zones", function()
    MOCK.addZone({ name = "QuadZ", points = { { x = 50000, y = 0 }, { x = 51000, y = 0 }, { x = 51000, y = 1000 }, { x = 50000, y = 1000 } } })
    local name = DMS.Spawner.spawn("zsu", "QuadZ")
    local p = unitPositions(name)[1]
    assert.truthy(p.x >= 50000 and p.x <= 51000 and p.z >= 0 and p.z <= 1000)
  end)

  it("never spawns in water or shallow water", function()
    MOCK.waterAreas = {
      { points = { { x = -10000, y = -10000 }, { x = 0, y = -10000 }, { x = 0, y = 10000 }, { x = -10000, y = 10000 } } },
      { shallow = true, points = { { x = -10000, y = -10000 }, { x = 10000, y = -10000 }, { x = 10000, y = 0 }, { x = -10000, y = 0 } } },
    }
    local n = 0
    for _ = 1, 40 do
      local name = DMS.Spawner.spawn("sa8", "town")
      if name then
        n = n + 1
        for _, p in ipairs(unitPositions(name)) do
          assert.truthy(p.x >= 0 and p.z >= 0, "unit spawned in water")
        end
      end
    end
    assert.truthy(n > 0)
  end)

  it("returns nil when the whole zone is water", function()
    MOCK.waterAreas = { { x = 0, y = 0, radius = 10000 } }
    local name, why = DMS.Spawner.spawn("sa8", "town")
    assert.is_nil(name)
    assert.are.equal("no point", why)
  end)

  it("keeps the minimum distance from enemy players", function()
    player("Viper1", 0, 0)
    for _ = 1, 30 do
      local name = DMS.Spawner.spawn("zsu", "town", { minPlayerDistM = 2000 })
      if name then
        local p = unitPositions(name)[1]
        assert.truthy(math.sqrt(p.x * p.x + p.z * p.z) >= 2000, "too close to player")
      end
    end
  end)

  it("uses a 5 km default distance and fails if the player sits on the zone", function()
    player("Viper1", 0, 0)
    local name, why = DMS.Spawner.spawn("zsu", "town")
    assert.is_nil(name)
    assert.are.equal("no point", why)
  end)

  it("rejects points in line of sight when outOfLOS is set", function()
    player("Viper1", 50000, 50000)
    MOCK.losFn = function(a) return a.x > 0 end
    for _ = 1, 20 do
      local name = DMS.Spawner.spawn("zsu", "town", { outOfLOS = true })
      if name then assert.truthy(unitPositions(name)[1].x <= 0) end
    end
  end)

  it("avoids buildings when buildingRadius is set", function()
    world.searchObjects = function(cat, vol, cb)
      if cat == Object.Category.SCENERY and vol.params.point.z > 0 then cb({}) return 1 end
      return 0
    end
    for _ = 1, 20 do
      local name = DMS.Spawner.spawn("zsu", "town", { buildingRadius = 50 })
      if name then assert.truthy(unitPositions(name)[1].z <= 0) end
    end
  end)

  it("hides enemy spawns under fog of war but not friendly ones", function()
    DMS_CONFIG.templates.m1 = { country = "USA", category = "ground", units = { { type = "M-1 Abrams" } } }
    local red = DMS.Spawner.spawn("zsu", "town")
    local blue = DMS.Spawner.spawn("m1", "town")
    assert.is_true(MOCK.groups[red].data.hidden)
    assert.is_true(MOCK.groups[red].data.hiddenOnMFD)
    assert.is_nil(MOCK.groups[blue].data.hidden)
  end)

  it("gives ground groups a 2-point hold route", function()
    local name = DMS.Spawner.spawn("zsu", "town")
    assert.are.equal(2, #MOCK.groups[name].data.route.points)
  end)

  it("respects the unit budget", function()
    DMS_CONFIG.budgets.maxActiveGround = 3
    assert.is_not_nil(DMS.Spawner.spawn("sa8", "town"))
    local n, why = DMS.Spawner.spawn("sa8", "town")
    assert.is_nil(n)
    assert.are.equal("budget", why)
  end)

  it("emits spawner.spawned and calls onReady after ~1s", function()
    local seen, ready
    DMS.Bus.on("spawner.spawned", function(ev) seen = ev end)
    local name = DMS.Spawner.spawn("zsu", "town", { onReady = function(g) ready = g end })
    assert.are.equal(name, seen.group)
    assert.is_nil(ready)
    MOCK.advance(1.5)
    assert.are.equal(name, ready)
  end)

  it("spawnPool picks pick-range members from pool zones", function()
    for _ = 1, 20 do
      local groups = DMS.Spawner.spawnPool("aaa")
      assert.truthy(#groups >= 2 and #groups <= 4, "count " .. #groups)
      for _, g in ipairs(groups) do Group.getByName(g):destroy() end
    end
  end)

  it("handles unknown templates, countries and zones gracefully", function()
    DMS_CONFIG.templates.bad = { country = "ATLANTIS", category = "ground", units = { { type = "x" } } }
    assert.is_nil(DMS.Spawner.spawn("nope", "town"))
    assert.is_nil(DMS.Spawner.spawn("bad", "town"))
    assert.is_nil(DMS.Spawner.spawn("zsu", "nowhere"))
    assert.are.equal(0, #DMS.Spawner.spawnPool("nopool"))
  end)

  it("runs 200 random seeds without errors", function()
    stripes()
    for seed = 1, 200 do
      DMS.Rng.seed(seed)
      local groups = DMS.Spawner.spawnPool("aaa", { minPlayerDistM = 0 })
      for _, g in ipairs(groups) do
        for _, p in ipairs(unitPositions(g)) do assert.falsy(inStripe(p.x), "water spawn seed " .. seed) end
        Group.getByName(g):destroy()
      end
    end
  end)
end)
