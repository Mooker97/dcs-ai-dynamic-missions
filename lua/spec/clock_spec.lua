--# modules: core, clock, rng
describe("DMS.Clock", function()
  it("now() follows timer.getTime", function()
    MOCK.advance(12.5)
    assert.equals(12.5, DMS.Clock.now())
  end)

  it("after() runs once with arguments", function()
    local got = {}
    DMS.Clock.after(5, function(a, b) got[#got + 1] = { a, b } end, "x", nil)
    MOCK.advance(4.9)
    assert.equals(0, #got)
    MOCK.advance(0.2)
    assert.equals(1, #got)
    assert.equals("x", got[1][1])
    MOCK.advance(100)
    assert.equals(1, #got)
  end)

  it("after() guards errors so nothing escapes to DCS", function()
    DMS.Clock.after(1, function() error("bad") end)
    MOCK.advance(2)
    assert.equals(0, #MOCK.rawErrors)
    assert.is_true((MOCK.logContains("bad", "error")))
  end)

  it("every() repeats at the interval, honoring firstDelay", function()
    local times = {}
    DMS.Clock.every(10, function() times[#times + 1] = DMS.Clock.now() end, { firstDelay = 1 })
    MOCK.advance(35)
    assert.same({ 1, 11, 21, 31 }, times)
  end)

  it("every() re-arms after an error", function()
    local n = 0
    DMS.Clock.every(5, function()
      n = n + 1
      if n <= 2 then error("flaky") end
    end)
    MOCK.advance(30)
    assert.equals(6, n)
    assert.equals(0, #MOCK.rawErrors)
    assert.is_true((MOCK.logContains("flaky", "error")))
  end)

  it("every() stops when fn returns false", function()
    local n = 0
    DMS.Clock.every(1, function()
      n = n + 1
      if n == 3 then return false end
    end)
    MOCK.advance(10)
    assert.equals(3, n)
    assert.equals(0, MOCK.pendingTimers())
  end)

  it("cancel() stops one-shots and repeats, also from inside fn", function()
    local a, b, c = 0, 0, 0
    local id1 = DMS.Clock.after(5, function() a = a + 1 end)
    local id2 = DMS.Clock.every(1, function() b = b + 1 end)
    local id3
    id3 = DMS.Clock.every(1, function()
      c = c + 1
      DMS.Clock.cancel(id3)
    end)
    MOCK.advance(2.5)
    assert.is_true(DMS.Clock.cancel(id1))
    assert.is_true(DMS.Clock.cancel(id2))
    assert.is_false(DMS.Clock.cancel(id2))
    MOCK.advance(10)
    assert.equals(0, a)
    assert.equals(2, b)
    assert.equals(1, c)
    assert.equals(0, MOCK.pendingTimers())
  end)

  it("every() jitter stays within bounds", function()
    DMS.Rng.seed(7)
    local times = {}
    DMS.Clock.every(10, function() times[#times + 1] = DMS.Clock.now() end, { jitter = 2 })
    MOCK.advance(500)
    assert.truthy(#times > 30)
    for i = 2, #times do
      local d = times[i] - times[i - 1]
      assert.truthy(d >= 8 - 1e-9 and d <= 12 + 1e-9, "gap " .. d)
    end
  end)
end)

describe("MOCK timers (DCS semantics)", function()
  it("an unguarded error kills the timer and is recorded", function()
    MOCK.expectRawErrors = true
    local n = 0
    timer.scheduleFunction(function()
      n = n + 1
      error("x")
    end, nil, 1)
    MOCK.advance(10)
    assert.equals(1, n)
    assert.equals(1, #MOCK.rawErrors)
  end)

  it("returned times re-arm the same timer id", function()
    local n = 0
    local id = timer.scheduleFunction(function(_, t)
      n = n + 1
      return t + 1
    end, nil, 1)
    MOCK.advance(5.5)
    assert.equals(5, n)
    timer.removeFunction(id)
    MOCK.advance(5)
    assert.equals(5, n)
  end)
end)
