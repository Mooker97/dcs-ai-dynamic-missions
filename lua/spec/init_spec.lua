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
