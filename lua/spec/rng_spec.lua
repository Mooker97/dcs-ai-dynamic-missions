--# modules: core, rng
describe("DMS.Rng", function()
  it("is deterministic per seed and differs across seeds", function()
    DMS.Rng.seed(42)
    local a = { DMS.Rng.random(), DMS.Rng.random(), DMS.Rng.int(1, 1000) }
    DMS.Rng.seed(42)
    local b = { DMS.Rng.random(), DMS.Rng.random(), DMS.Rng.int(1, 1000) }
    DMS.Rng.seed(43)
    local c = { DMS.Rng.random(), DMS.Rng.random(), DMS.Rng.int(1, 1000) }
    assert.same(a, b)
    assert.not_equals(a[1], c[1])
  end)

  it("seed(nil) mixes DMS_CONFIG.seed and time", function()
    DMS_CONFIG = { seed = 5 }
    local s1 = DMS.Rng.seed()
    MOCK.advance(0.123)
    local s2 = DMS.Rng.seed()
    assert.is_number(s1)
    assert.not_equals(s1, s2)
    assert.equals(s2, DMS.Rng.lastSeed)
  end)

  it("seed(nil) adds per-launch entropy (heap addresses), so a fixed start time still varies", function()
    local e = DMS.Rng.launchEntropy()
    assert.is_number(e)
    assert(e >= 0 and e < 1000003 and e == math.floor(e), tostring(e))
    DMS_CONFIG = { seed = 5 }
    local real = DMS.Rng.launchEntropy
    DMS.Rng.launchEntropy = function()
      return 0
    end
    local a = DMS.Rng.seed()
    DMS.Rng.launchEntropy = function()
      return 1
    end
    local b = DMS.Rng.seed()
    DMS.Rng.launchEntropy = real
    assert.not_equals(a, b)
    assert.equals(b - a, 2003)
    -- an explicit seed stays deterministic
    DMS.Rng.seed(a)
    local x = DMS.Rng.random()
    DMS.Rng.seed(a)
    assert.equals(x, DMS.Rng.random())
  end)

  it("random() is in [0,1) with a sane mean over 1000 draws", function()
    DMS.Rng.seed(1)
    local sum = 0
    for _ = 1, 1000 do
      local r = DMS.Rng.random()
      assert.truthy(r >= 0 and r < 1)
      sum = sum + r
    end
    assert.near(0.5, sum / 1000, 0.05)
  end)

  it("int() covers the inclusive range roughly uniformly", function()
    DMS.Rng.seed(2)
    local counts = {}
    for _ = 1, 1000 do
      local v = DMS.Rng.int(1, 6)
      assert.truthy(v >= 1 and v <= 6 and v == math.floor(v))
      counts[v] = (counts[v] or 0) + 1
    end
    for v = 1, 6 do
      assert.truthy(counts[v] > 110 and counts[v] < 230, "face " .. v .. ": " .. tostring(counts[v]))
    end
    assert.equals(3, DMS.Rng.int(3, 3))
    local x = DMS.Rng.int(5)
    assert.truthy(x >= 1 and x <= 5)
  end)

  it("chance() matches its percentage", function()
    DMS.Rng.seed(3)
    local hits = 0
    for _ = 1, 1000 do
      if DMS.Rng.chance(30) then
        hits = hits + 1
      end
    end
    assert.truthy(hits > 250 and hits < 350, "hits " .. hits)
    assert.is_false(DMS.Rng.chance(0))
    assert.is_true(DMS.Rng.chance(100))
  end)

  it("weighted() respects weights (default 1, zero never)", function()
    DMS.Rng.seed(4)
    local items = { { w = 3, id = "a" }, { id = "b" }, { w = 0, id = "never" } }
    local c = { a = 0, b = 0, never = 0 }
    for _ = 1, 1000 do
      local item = DMS.Rng.weighted(items)
      c[item.id] = c[item.id] + 1
    end
    assert.equals(0, c.never)
    assert.truthy(c.a > 680 and c.a < 820, "a " .. c.a)
    assert.is_nil(DMS.Rng.weighted({}))
    assert.is_nil(DMS.Rng.weighted({ { w = 0 } }))
  end)

  it("pickN() returns distinct elements without mutating input", function()
    DMS.Rng.seed(5)
    local list = { 1, 2, 3, 4, 5 }
    for _ = 1, 100 do
      local p = DMS.Rng.pickN(list, 3)
      assert.equals(3, #p)
      local seen = {}
      for _, v in ipairs(p) do
        assert.is_nil(seen[v])
        seen[v] = true
      end
    end
    assert.same({ 1, 2, 3, 4, 5 }, list)
    assert.equals(5, #DMS.Rng.pickN(list, 10))
    assert.equals(0, #DMS.Rng.pickN(list, 0))
  end)

  it("shuffleBag() never repeats within a cycle nor back-to-back across refills", function()
    DMS.Rng.seed(6)
    local bag = DMS.Rng.shuffleBag({ "a", "b", "c", "d" })
    local prev
    for cycle = 1, 250 do
      local seen = {}
      for _ = 1, 4 do
        local v = bag:next()
        assert.is_nil(seen[v], "repeat within cycle " .. cycle)
        assert.not_equals(prev, v)
        seen[v] = true
        prev = v
      end
    end
    local two = DMS.Rng.shuffleBag({ 1, 2 })
    local last
    for _ = 1, 200 do
      local v = two:next()
      assert.not_equals(last, v)
      last = v
    end
    assert.is_nil(DMS.Rng.shuffleBag({}):next())
    assert.equals("x", DMS.Rng.shuffleBag({ "x" }):next())
  end)

  it("jitter(), range() and rangeInt() stay within bounds", function()
    DMS.Rng.seed(8)
    for _ = 1, 1000 do
      local j = DMS.Rng.jitter(10, 2)
      assert.truthy(j >= 8 and j <= 12)
      local r = DMS.Rng.range({ 40, 90 })
      assert.truthy(r >= 40 and r <= 90)
      local ri = DMS.Rng.rangeInt({ 2, 4 })
      assert.truthy(ri >= 2 and ri <= 4 and ri == math.floor(ri))
    end
    assert.equals(7, DMS.Rng.range(7))
    assert.equals(3, DMS.Rng.range({ min = 3, max = 3 }))
  end)

  it("is independent of math.random", function()
    DMS.Rng.seed(9)
    local a = DMS.Rng.random()
    DMS.Rng.seed(9)
    math.randomseed(1234)
    math.random()
    local b = DMS.Rng.random()
    assert.equals(a, b)
  end)
end)
