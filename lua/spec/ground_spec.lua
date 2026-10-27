-- ground_spec.lua: scenario tests for DMS.Ground against the DCS mock.

local function reset()
  DMS_CONFIG = { players = { coalition = 2 }, budgets = {} }
  DMS.Rng.seed(3)
  DMS.Ground.reset()
end

local function redGroup(name, x, y)
  return MOCK.addGroup({ name = name, coalition = 1, category = "ground",
    units = { { name = name .. "-1", x = x, y = y }, { name = name .. "-2", x = x + 20, y = y } } })
end

local function ctrl(name) return Group.getByName(name):getController() end

local function lastRoute(name)
  local t = ctrl(name).task
  return t and t.params.route.points
end

local function lastCommand(name)
  local c = ctrl(name).commands
  return c[#c]
end

local function setTasks(name) return MOCK.countCalls("Controller.setTask", name) end

local G = AI.Option.Ground

describe("Ground", function()
  before_each(reset)

  it("routeTo issues a Mission route with current position first", function()
    redGroup("g1", 100, 200)
    assert.is_true(DMS.Ground.routeTo("g1", { x = 5000, y = 6000 }, { speed = 10 }))
    local pts = lastRoute("g1")
    assert.truthy(#pts >= 2)
    assert.are.equal(100, pts[1].x)
    assert.are.equal(200, pts[1].y)
    assert.are.equal(5000, pts[#pts].x)
    assert.are.equal(10, pts[#pts].speed)
    assert.are.equal("Off Road", pts[#pts].action)
  end)

  it("accepts vec3 targets and stops short", function()
    redGroup("g1", 0, 0)
    DMS.Ground.routeTo("g1", { x = 1000, y = 50, z = 0 }, { stopShortM = 300 })
    local pts = lastRoute("g1")
    assert.near(700, pts[#pts].x, 0.01)
    assert.near(0, pts[#pts].y, 0.01)
  end)

  it("still produces 2 distinct points when already at the target", function()
    redGroup("g1", 0, 0)
    DMS.Ground.routeTo("g1", { x = 0, y = 0 })
    assert.are.equal(2, #lastRoute("g1"))
  end)

  it("halt/resume uses StopRoute", function()
    redGroup("g1", 0, 0)
    DMS.Ground.halt("g1")
    assert.are.equal("StopRoute", lastCommand("g1").id)
    assert.is_true(lastCommand("g1").params.value)
    DMS.Ground.resume("g1")
    assert.is_false(lastCommand("g1").params.value)
  end)

  it("uses ground-valid ROE and alarm values only", function()
    redGroup("g1", 0, 0)
    assert.is_true(DMS.Ground.holdFire("g1"))
    assert.are.equal(G.val.ROE.WEAPON_HOLD, ctrl("g1").options[G.id.ROE])
    assert.is_true(DMS.Ground.openFire("g1"))
    assert.are.equal(G.val.ROE.OPEN_FIRE, ctrl("g1").options[G.id.ROE])
    assert.is_true(DMS.Ground.returnFire("g1"))
    assert.are.equal(G.val.ROE.RETURN_FIRE, ctrl("g1").options[G.id.ROE])
    assert.is_true(DMS.Ground.alarm("g1", "GREEN"))
    assert.are.equal(G.val.ALARM_STATE.GREEN, ctrl("g1").options[G.id.ALARM_STATE])
    assert.is_true(DMS.Ground.alarm("g1", "RED"))
    assert.is_false(DMS.Ground.alarm("g1", "PURPLE"))
  end)

  it("uses the air ROE enum for air groups and skips alarm", function()
    MOCK.addGroup({ name = "air1", coalition = 1, category = "airplane", units = { { name = "air1-1", x = 0, y = 0, alt = 3000 } } })
    assert.is_true(DMS.Ground.openFire("air1"))
    assert.are.equal(AI.Option.Air.val.ROE.OPEN_FIRE, ctrl("air1").options[AI.Option.Air.id.ROE])
    assert.is_false(DMS.Ground.alarm("air1", "RED"))
  end)

  it("fireAtPoint pushes a FireAtPoint task", function()
    redGroup("g1", 0, 0)
    DMS.Ground.fireAtPoint("g1", { x = 10, y = 0, z = 20 }, { radius = 50, expendQty = 4 })
    local t = ctrl("g1").task
    assert.are.equal("FireAtPoint", t.id)
    assert.are.equal(20, t.params.point.y)
    assert.is_true(t.params.expendQtyEnabled)
  end)

  it("hunt re-issues valid intercept routes with lead prediction", function()
    redGroup("hunter", 0, 0)
    MOCK.addGroup({ name = "convoy", coalition = 2, category = "ground", units = { { name = "c1", x = 5000, y = 0 } } })
    MOCK.units["c1"].velocity = { x = 0, y = 0, z = 10 }
    DMS.Ground.hunt("hunter", "convoy", { intervalSec = 10, speed = 10, standoffM = 0 })
    MOCK.advance(1)
    local pts = lastRoute("hunter")
    assert.truthy(#pts >= 2)
    assert.truthy(pts[#pts].y > 100, "should lead the target along +z")
    assert.are.equal(G.val.ROE.OPEN_FIRE, ctrl("hunter").options[G.id.ROE])
    assert.are.equal(G.val.ALARM_STATE.RED, ctrl("hunter").options[G.id.ALARM_STATE])
    MOCK.advance(25)
    assert.truthy(setTasks("hunter") >= 3)
  end)

  it("hunt stops when the target dies and when the hunter dies", function()
    redGroup("hunter", 0, 0)
    redGroup("hunter2", 0, 0)
    MOCK.addGroup({ name = "convoy", coalition = 2, category = "ground", units = { { name = "c1", x = 5000, y = 0 } } })
    local ended = {}
    DMS.Ground.hunt("hunter", "convoy", { intervalSec = 5, onEnd = function(r) ended.h1 = r end })
    DMS.Ground.hunt("hunter2", "convoy", { intervalSec = 5, onEnd = function(r) ended.h2 = r end })
    MOCK.advance(6)
    MOCK.killGroup("hunter2")
    MOCK.advance(6)
    assert.are.equal("dead", ended.h2)
    MOCK.killGroup("convoy")
    MOCK.advance(6)
    assert.are.equal("target", ended.h1)
    assert.is_false(DMS.Ground.isHunting("hunter"))
  end)

  it("hunt with a target function waits until a target appears", function()
    redGroup("hunter", 0, 0)
    local tgt
    DMS.Ground.hunt("hunter", function() return tgt end, { intervalSec = 5 })
    MOCK.advance(6)
    assert.are.equal(0, setTasks("hunter"))
    MOCK.spawnPlayer({ name = "Viper1-1", group = "Viper1", x = 3000, y = 3000 })
    tgt = "Viper1"
    MOCK.advance(6)
    assert.truthy(setTasks("hunter") >= 1)
  end)

  it("stuck watchdog re-routes and finally reports", function()
    redGroup("g1", 0, 0)
    DMS.Ground.routeTo("g1", { x = 5000, y = 0 })
    local stuck
    DMS.Bus.on("ground.stuck", function(ev) stuck = ev.group end)
    DMS.Ground.watch("g1", { checkSec = 5, stuckSec = 20, maxRetries = 2 })
    MOCK.advance(200)
    assert.are.equal(3, setTasks("g1"))
    assert.are.equal("g1", stuck)
  end)

  it("stuck watchdog leaves moving and halted groups alone", function()
    redGroup("g1", 0, 0)
    redGroup("g2", 0, 0)
    DMS.Ground.routeTo("g1", { x = 5000, y = 0 })
    DMS.Ground.routeTo("g2", { x = 5000, y = 0 })
    DMS.Ground.halt("g2")
    local stuck = {}
    DMS.Bus.on("ground.stuck", function(ev) stuck[#stuck + 1] = ev.group end)
    DMS.Ground.watch("g1", { checkSec = 5, stuckSec = 20 })
    DMS.Ground.watch("g2", { checkSec = 5, stuckSec = 20 })
    for i = 1, 40 do
      MOCK.moveUnit("g1-1", i * 50, 0)
      MOCK.advance(5)
    end
    assert.are.equal(0, #stuck)
    assert.are.equal(1, setTasks("g1"))
    assert.are.equal(1, setTasks("g2"))
  end)

  it("haltOnHit halts the convoy and resumes later", function()
    redGroup("convoy", 0, 0)
    local h = DMS.Ground.haltOnHit("convoy", 30)
    DMS.Bus.emit("unit.hit", { target = "convoy-1", targetGroup = "convoy", initiator = "x" })
    assert.is_true(lastCommand("convoy").params.value)
    assert.are.equal(G.val.ALARM_STATE.RED, ctrl("convoy").options[G.id.ALARM_STATE])
    MOCK.advance(20)
    DMS.Bus.emit("unit.hit", { target = "convoy-2", targetGroup = "convoy" }) -- restarts timer
    MOCK.advance(20)
    assert.is_true(lastCommand("convoy").params.value)
    MOCK.advance(15)
    assert.is_false(lastCommand("convoy").params.value)
    h.stop()
    DMS.Bus.emit("unit.hit", { target = "convoy-1", targetGroup = "convoy" })
    assert.is_false(lastCommand("convoy").params.value)
  end)

  it("haltOnHit reacts to real HIT events through the bus", function()
    redGroup("convoy", 0, 0)
    MOCK.addGroup({ name = "ins", coalition = 2, category = "ground", units = { { name = "ins-1", x = 900, y = 0 } } })
    DMS.Ground.haltOnHit("convoy", { 30, 60 })
    MOCK.hitUnit("convoy-1", { initiator = "ins-1", weapon = "RPG" })
    local c = lastCommand("convoy")
    assert.truthy(c and c.id == "StopRoute" and c.params.value == true)
  end)

  it("tolerates missing groups everywhere", function()
    assert.is_false(DMS.Ground.routeTo("nope", { x = 0, y = 0 }))
    assert.is_false(DMS.Ground.halt("nope"))
    assert.is_false(DMS.Ground.openFire("nope"))
    assert.is_false(DMS.Ground.alarm("nope", "RED"))
    assert.is_false(DMS.Ground.fireAtPoint("nope", { x = 0, y = 0 }))
  end)
end)
