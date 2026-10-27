--# modules: core, clock, rng, bus, registry, init
describe("DMS.boot", function()
  it("does not boot at load without DMS_CONFIG", function()
    assert.is_nil(DMS._booted)
    assert.is_true((MOCK.logContains("DMS_CONFIG missing")))
  end)

  it("starts present modules in order, isolating failures, and logs a banner", function()
    local order = {}
    DMS.Director = { start = function() order[#order + 1] = "Director" end }
    DMS.Spawner = { start = function() order[#order + 1] = "Spawner" end }
    DMS.Comms = { start = function() error("comms broke") end }
    DMS.Intel = { start = function(self) order[#order + 1] = (self == DMS.Intel) and "Intel(self)" or "Intel" end }
    DMS_CONFIG = { seed = 99, debug = true, missionId = "m01", budgets = { maxActiveGround = 150 } }
    assert.is_true(DMS.boot())
    assert.same({ "Spawner", "Director", "Intel(self)" }, order)
    assert.is_true(DMS.Log.isDebug())
    assert.is_number(DMS.Rng.lastSeed)
    assert.is_true((MOCK.logContains("DMS dev started: mission=m01")))
    assert.is_true((MOCK.logContains("FAILED=%[Comms%]")))
    assert.is_true((MOCK.logContains("comms broke", "error")))
    assert.is_false(DMS.boot())
  end)
end)

describe("DMS.boot load order", function()
  local function banners()
    local n = 0
    for _, l in ipairs(MOCK.log) do if string.find(l.msg, "started: mission=", 1, true) then n = n + 1 end end
    return n
  end

  it("bundle loaded before dms_config.lua boots once the config appears", function()
    assert.is_nil(DMS._booted)
    MOCK.advance(0.5)
    DMS_CONFIG = { missionId = "late" }
    MOCK.advance(1.5)
    assert.is_true(DMS._booted)
    assert.are.equal(1, banners())
    assert.is_true((MOCK.logContains("DMS_CONFIG appeared after load")))
    MOCK.advance(10)
    assert.are.equal(1, banners())
  end)

  it("never-appearing config warns once and does not boot", function()
    MOCK.advance(20)
    assert.is_nil(DMS._booted)
    local n = 0
    for _, l in ipairs(MOCK.log) do if string.find(l.msg, "never appeared", 1, true) then n = n + 1 end end
    assert.are.equal(1, n)
    assert.is_true((MOCK.logContains("never appeared", "warning")))
  end)

  it("a manual DMS.boot() before the deferred check is not repeated", function()
    DMS_CONFIG = { missionId = "manual" }
    assert.is_true(DMS.boot())
    MOCK.advance(10)
    assert.are.equal(1, banners())
    assert.is_false(DMS.boot())
  end)
end)
