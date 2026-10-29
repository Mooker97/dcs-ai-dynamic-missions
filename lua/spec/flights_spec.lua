-- flights_spec.lua: DMS.Flights (lua/src/dms/flights.lua) on the full runtime and the DCS mock.

local function events(name)
  local out = {}
  DMS.Bus.on(name, function(ev)
    out[#out + 1] = ev
  end)
  return out
end

local function heli(name, x, y, alt, side)
  MOCK.addGroup({
    name = name,
    coalition = side or 2,
    country = (side == 1) and "RUSSIA" or "USA",
    category = "helicopter",
    units = { { name = name .. "-1", type = "UH-60A", x = x or 0, y = y or 0, alt = alt or 150 } },
  })
end

local function plane(name, x, y, alt)
  MOCK.addGroup({
    name = name,
    coalition = 2,
    country = "USA",
    category = "airplane",
    units = { { name = name .. "-1", type = "F-16C_50", x = x or 0, y = y or 0, alt = alt or 4000 } },
  })
end

local function ground(name, x, y, side, n)
  local units = {}
  for i = 1, n or 1 do
    units[i] = { name = name .. "-" .. i, type = "Hummer", x = x + (i - 1) * 10, y = y, alt = 0 }
  end
  MOCK.addGroup({ name = name, coalition = side or 1, category = "ground", units = units })
end

local function config(flights, extra)
  local c = {
    seed = 5,
    missionId = "fl",
    players = { coalition = 2 },
    budgets = { maxActiveGround = 100, maxActiveAir = 10, spawnsPerMin = 60 },
    director = { enabled = false },
    zones = {
      gate = { kind = "circle", x = 10000, y = 0, radius = 500 },
      lz = { kind = "circle", x = 20000, y = 0, radius = 200 },
      target = { kind = "circle", x = 40000, y = 0, radius = 1000 },
    },
    narrative = { minGapSec = 1, zonePollSec = 1 },
    beats = {},
    flights = flights,
  }
  for k, v in pairs(extra or {}) do
    c[k] = v
  end
  return c
end

local function lastTask(group)
  local c = MOCK.lastCall("Controller.setTask", group)
  return c and c.args[1] or nil
end

local function move(unit, x, y, alt)
  MOCK.moveUnit(unit, x, y, alt)
end

describe("DMS.Flights", function()
  it("is inert without DMS_CONFIG.flights and watch", function()
    DMS_CONFIG = config(nil)
    DMS.boot()
    MOCK.advance(10)
    assert.are.same({}, DMS.Flights.ids())
    assert.is_nil(DMS.Flights.state("x"))
  end)

  it("flies, holds until a beat, lands with pickup, lifts and finishes", function()
    heli("Dustoff_dustoff", 0, 0, 150)
    ground("Kestrel_kestrel", 20050, 0, 2, 2)
    MOCK.units["Kestrel_kestrel-2"].x = 21000 -- outside the 300 m pickup radius
    DMS_CONFIG = config({
      {
        id = "dustoff",
        group = "Dustoff_dustoff",
        category = "helicopter",
        coalition = 2,
        orders = {
          { kind = "fly", to = "gate", altM = 90, altType = "RADIO", speedMps = 56.6 },
          { kind = "hold", at = "gate", ["until"] = { event = "beat.fired", beat = "lz_cold" }, maxSec = 360 },
          { kind = "land", at = "lz", groundSec = 30, pickup = "Kestrel_kestrel" },
          { kind = "fly", to = "target" },
        },
      },
    }, { beats = { { id = "lz_cold", when = { flag = "cold" } } } })
    local ord, arr, landed, lifted, pickup, done =
      events("flight.order"),
      events("flight.arrived"),
      events("flight.landed"),
      events("flight.lifted"),
      events("flight.pickup"),
      events("flight.done")
    DMS.boot()
    MOCK.advance(3)
    assert.are.equal(1, #ord)
    assert.are.equal("fly", ord[1].kind)
    assert.are.equal("dustoff", ord[1].flight)
    local t = lastTask("Dustoff_dustoff")
    assert.are.equal("Mission", t.id)
    local wp = t.params.route.points[2]
    assert.are.equal(10000, wp.x)
    assert.are.equal("RADIO", wp.alt_type)
    assert.are.equal(90, wp.alt)
    assert.are.equal(56.6, wp.speed)
    assert.are.same(
      { index = 1, kind = "fly", status = "running", since = DMS.Flights.state("dustoff").since },
      DMS.Flights.state("dustoff")
    )

    move("Dustoff_dustoff-1", 9900, 0)
    MOCK.advance(3)
    assert.are.equal(1, #arr)
    assert.are.equal("gate", arr[1].zone)
    t = lastTask("Dustoff_dustoff")
    local orbit = t.params.route.points[2].task.params.tasks[1]
    assert.are.equal("Orbit", orbit.id)
    assert.are.equal("Circle", orbit.params.pattern)
    assert.are.equal("hold", DMS.Flights.state("dustoff").kind)

    MOCK.advance(30)
    assert.are.equal("hold", DMS.Flights.state("dustoff").kind) -- until not reached
    DMS.Narrative.setFlag("cold", 1)
    MOCK.advance(4)
    assert.are.equal(1, DMS.Narrative.firedCount("lz_cold"))
    assert.are.equal("land", DMS.Flights.state("dustoff").kind)
    t = lastTask("Dustoff_dustoff")
    assert.are.equal("Land", t.id)
    assert.are.equal(20000, t.params.point.x)
    assert.is_true(t.params.durationFlag)

    -- on the ground in the LZ (AGL < 3 m, still)
    move("Dustoff_dustoff-1", 20020, 0, 0)
    MOCK.advance(3)
    assert.are.equal(1, #landed)
    assert.are.equal("lz", landed[1].zone)
    MOCK.advance(20)
    assert.are.equal(0, #pickup)
    MOCK.advance(12)
    assert.are.equal(1, #pickup)
    assert.are.equal(1, pickup[1].units)
    assert.are.equal("Kestrel_kestrel", pickup[1].pickup)
    assert.is_nil(Unit.getByName("Kestrel_kestrel-1"))
    assert.is_truthy(Unit.getByName("Kestrel_kestrel-2"))
    assert.are.equal(1, #lifted)
    assert.are.equal("fly", DMS.Flights.state("dustoff").kind)

    move("Dustoff_dustoff-1", 40000, 0, 150)
    MOCK.advance(3)
    assert.are.equal(1, #done)
    assert.are.equal("done", DMS.Flights.state("dustoff").status)
    assert.is_true((MOCK.logContains("%[DMS%]%[Flights%] flight 'dustoff' done")))
  end)

  it("waits for an order's when, and ends hold at maxSec", function()
    heli("Dusty_dusty", 10000, 0, 150)
    DMS_CONFIG = config({
      {
        id = "dusty",
        group = "Dusty_dusty",
        orders = {
          { kind = "hold", at = "gate", maxSec = { 20, 20 } },
          { kind = "fly", to = "lz", when = { event = "flight.done", flight = "other" } },
        },
      },
    })
    DMS.boot()
    MOCK.advance(10)
    assert.are.equal("hold", DMS.Flights.state("dusty").kind)
    MOCK.advance(14)
    local st = DMS.Flights.state("dusty")
    assert.are.equal(2, st.index)
    assert.are.equal(1, MOCK.countCalls("Controller.setTask", "Dusty_dusty")) -- fly not issued yet
    DMS.Bus.emit("flight.done", { flight = "other" })
    MOCK.advance(3)
    assert.are.equal(2, MOCK.countCalls("Controller.setTask", "Dusty_dusty"))
    assert.is_true(DMS.Flights.advance("dusty", "test"))
    assert.are.equal("done", DMS.Flights.state("dusty").status)
  end)

  it("strikes a group by name prefix (DMS_ prefix) with AttackGroup and emits flight.weapon", function()
    plane("Hog_hog", 0, 0, 4000)
    ground("DMS_technicals_1", 40100, 0, 1, 2)
    DMS_CONFIG = config({
      {
        id = "hog",
        group = "Hog_hog",
        category = "airplane",
        orders = {
          { kind = "strike", at = "target", group = "technicals", weapon = "guided_bomb", altM = 4572, maxSec = 360 },
        },
      },
    })
    local weapon, done = events("flight.weapon"), events("flight.done")
    DMS.boot()
    MOCK.advance(3)
    local t = lastTask("Hog_hog")
    assert.are.equal("AttackGroup", t.id)
    assert.are.equal(Group.getByName("DMS_technicals_1"):getID(), t.params.groupId)
    assert.are.equal(14, t.params.weaponType)
    assert.are.equal("All", t.params.expend)
    assert.are.equal(AI.Option.Air.val.ROE.OPEN_FIRE, MOCK.lastCall("Controller.setOption", "Hog_hog").args[2])
    MOCK.fireEvent({ id = "SHOT", initiator = Unit.getByName("Hog_hog-1"), weapon = MOCK.makeWeapon("GBU-12") })
    assert.are.equal(1, #weapon)
    assert.are.equal("GBU-12", weapon[1].weapon)
    assert.are.equal("DMS_technicals_1", weapon[1].target)
    MOCK.advance(30)
    assert.are.equal(0, #done)
    MOCK.killGroup("DMS_technicals_1")
    MOCK.advance(3)
    assert.are.equal(1, #done)
  end)

  it("falls back to Bombing on the zone centre and ends 60 s after a release", function()
    plane("Hog_hog", 0, 0, 4000)
    DMS_CONFIG = config({
      {
        id = "hog",
        group = "Hog_hog",
        orders = { { kind = "strike", at = "target", group = "nothing", weapon = "bomb" } },
      },
    })
    local done = events("flight.done")
    DMS.boot()
    MOCK.advance(3)
    local t = lastTask("Hog_hog")
    assert.are.equal("Bombing", t.id)
    assert.are.equal(40000, t.params.point.x)
    assert.are.equal(DMS.Flights.WEAPON_FLAGS.bomb, t.params.weaponType)
    MOCK.fireEvent({ id = "SHOT", initiator = Unit.getByName("Hog_hog-1"), weapon = MOCK.makeWeapon("Mk-82") })
    MOCK.advance(50)
    assert.are.equal(0, #done)
    MOCK.advance(14)
    assert.are.equal(1, #done)
  end)

  it("escorts another flight and engages a zone with EngageTargetsInZone", function()
    heli("Dustoff_dustoff", 0, 0, 150)
    heli("Cobra_cobra", 100, 0, 150)
    heli("Snake_snake", 200, 0, 150)
    DMS_CONFIG = config({
      { id = "dustoff", group = "Dustoff_dustoff", orders = { { kind = "hold", at = "gate" } } },
      {
        id = "cobra",
        group = "Cobra_cobra",
        orders = { { kind = "escort", flight = "dustoff", radiusM = 2778, targets = { "Ground Units" } } },
      },
      {
        id = "snake",
        group = "Snake_snake",
        orders = {
          {
            kind = "engage",
            at = "lz",
            radiusM = 2778,
            targets = { "armor" },
            ["until"] = { event = "flight.lifted", flight = "dustoff" },
          },
        },
      },
    })
    DMS.boot()
    MOCK.advance(3)
    local e = lastTask("Cobra_cobra")
    assert.are.equal("Escort", e.id)
    assert.are.equal(Group.getByName("Dustoff_dustoff"):getID(), e.params.groupId)
    assert.are.equal(2778, e.params.engagementDistMax)
    local g = lastTask("Snake_snake")
    local eng = g.params.route.points[1].task.params.tasks[1]
    assert.are.equal("EngageTargetsInZone", eng.id)
    assert.are.same({ "Armored vehicles" }, eng.params.targetTypes)
    assert.are.equal("Orbit", g.params.route.points[2].task.params.tasks[1].id)
    DMS.Bus.emit("flight.lifted", { flight = "dustoff" })
    MOCK.advance(3)
    assert.are.equal("done", DMS.Flights.state("snake").status)
    -- escorted flight dies -> escort order ends
    MOCK.killGroup("Dustoff_dustoff")
    MOCK.advance(3)
    assert.are.equal("lost", DMS.Flights.state("dustoff").status)
    assert.are.equal("done", DMS.Flights.state("cobra").status)
  end)

  it("plane rtb routes to the start airbase with a Landing waypoint and finishes on unit.landed", function()
    MOCK.addAirbase({ name = "Hatay", x = -5000, y = 0, coalition = 2, id = 12 })
    plane("Hog_hog", 0, 0, 4000)
    DMS_CONFIG = config({
      { id = "hog", group = "Hog_hog", category = "airplane", startAirbase = "Hatay", orders = { { kind = "rtb" } } },
    })
    local landed, done = events("flight.landed"), events("flight.done")
    DMS.boot()
    MOCK.advance(3)
    local t = lastTask("Hog_hog")
    local wp = t.params.route.points[2]
    assert.are.equal("Land", wp.type)
    assert.are.equal("Landing", wp.action)
    assert.are.equal(12, wp.airdromeId)
    move("Hog_hog-1", -4800, 0, 500) -- still moving (alt) but DCS says LAND
    MOCK.fireEvent({ id = "LAND", initiator = Unit.getByName("Hog_hog-1"), place = Airbase.getByName("Hatay") })
    assert.are.equal(1, #landed)
    MOCK.advance(3)
    assert.are.equal(1, #done)
  end)

  it("skips orders with a missing zone and loses dead or missing groups, never erroring", function()
    heli("Dusty_dusty", 0, 0, 150)
    DMS_CONFIG = config({
      {
        id = "dusty",
        group = "Dusty_dusty",
        orders = { { kind = "fly", to = "nowhere" }, { kind = "teleport" }, { kind = "hold", at = "gate" } },
      },
      { id = "ghost", group = "Ghost_ghost", orders = { { kind = "fly", to = "gate" } } },
    })
    local lost = events("flight.lost")
    DMS.boot()
    MOCK.advance(3)
    assert.is_true((MOCK.logContains("order 1 %(fly%) skipped: unknown zone 'nowhere'", "warning")))
    assert.is_true((MOCK.logContains("order 2 %(teleport%) skipped", "warning")))
    assert.are.equal("hold", DMS.Flights.state("dusty").kind)
    MOCK.killGroup("Dusty_dusty")
    MOCK.advance(3)
    assert.are.equal("lost", DMS.Flights.state("dusty").status)
    MOCK.advance(40)
    assert.are.equal("lost", DMS.Flights.state("ghost").status)
    assert.are.equal(2, #lost)
    assert.are.same({ "dusty", "ghost" }, DMS.Flights.ids())
    assert.are.equal("Dusty_dusty", DMS.Flights.groupName("dusty"))
  end)

  it("maps weapons and targets per the contract", function()
    local W = DMS.Flights.weaponFlag
    assert.are.equal(14, W("guided_bomb"))
    assert.are.equal(2147485694, W("bomb"))
    assert.are.equal(4161536, W("missile"))
    assert.are.equal(30720, W("rockets"))
    assert.are.equal(805306368, W("gun"))
    assert.are.equal(1073741822, W("any"))
    assert.are.equal(14, W(nil))
    assert.is_true(DMS.Flights._prefixMatch("DMS_technicals_3", "technicals"))
    assert.is_false(DMS.Flights._prefixMatch("Xtechnicals", "technicals"))
  end)
end)

describe("DMS.Flights + DMS.Test", function()
  it("flight_orders passes when every flight is done or lost (lost is INFO)", function()
    heli("Dusty_dusty", 10000, 0, 150)
    heli("Doomed_doomed", 0, 0, 150)
    DMS_CONFIG = config({
      { id = "dusty", group = "Dusty_dusty", orders = { { kind = "fly", to = "gate" } } },
      { id = "doomed", group = "Doomed_doomed", orders = { { kind = "hold", at = "gate" } } },
    }, {
      watch = { enabled = true, focus = "Dusty_dusty", cues = true },
      test = { enabled = true, playerProxy = "Dusty_dusty", minutes = 10, checks = { { kind = "flight_orders" } } },
    })
    DMS.boot()
    MOCK.advance(5)
    MOCK.killGroup("Doomed_doomed")
    MOCK.advance(10)
    assert.is_true((MOCK.logContains("^%[DMS%.TEST%] INFO flight_orders_1 flight doomed lost")))
    assert.is_true((MOCK.logContains("^%[DMS%.TEST%] PASS flight_orders_1 dusty=done,doomed=lost")))
    -- the proxy is the focus flight: no WEAPON_HOLD / immortal / re-route from DMS.Test
    assert.are.equal(0, MOCK.countCalls("Controller.setCommand", "Dusty_dusty"))
    assert.is_true((MOCK.logContains("watch run: proxy Dusty_dusty is the focus flight")))
    assert.is_truthy(DMS.Bus._players["Dusty_dusty-1"]) -- registered once, by DMS.Test
    assert.are.equal("PROXY", DMS.Bus._players["Dusty_dusty-1"].playerName)
  end)

  it("flight_orders fails at the end when a flight never finishes", function()
    heli("Dusty_dusty", 0, 0, 150)
    DMS_CONFIG = config({
      { id = "dusty", group = "Dusty_dusty", orders = { { kind = "fly", to = "target" } } },
    }, {
      test = { enabled = true, minutes = 2, checks = { { kind = "flight_orders", name = "fo" } } },
    })
    DMS.boot()
    MOCK.advance(130)
    assert.is_true((MOCK.logContains("^%[DMS%.TEST%] FAIL fo .*unfinished: dusty%(order 1 fly%)")))
  end)
end)
