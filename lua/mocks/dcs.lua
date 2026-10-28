-- lua/mocks/dcs.lua
-- A DCS World mission-scripting environment mock for offline tests (Lua 5.1 / lupa).
--
-- Installs the DCS globals (env, timer, trigger, coalition, country, Group, Unit,
-- StaticObject, Controller, AI, world, land, missionCommands, Object, Spot, coord, net)
-- plus a MOCK table for driving and inspecting them from specs.
--
-- Quick reference (see the README block at the bottom of the file for details):
--   MOCK.reset()                         wipe all state (the runner already gives each test a fresh VM)
--   MOCK.now() / MOCK.advance(sec)       fake clock; runs due timer callbacks in time order
--   MOCK.addGroup{...} -> Group          coalition.addGroup wrapper with friendly args
--   MOCK.spawnPlayer{...} -> Unit        client unit + BIRTH event with a player name
--   MOCK.killUnit(name, opts)            KILL (if opts.killer) + DEAD + UNIT_LOST, or opts.events
--   MOCK.hitUnit(name, opts)             HIT event and life reduction
--   MOCK.fireEvent(e)                    deliver an event to every world event handler
--   MOCK.calls / MOCK.callsTo(fn)        recorded trigger.action / Controller / missionCommands calls
--   MOCK.log / MOCK.logContains(pat)     env.info/warning/error capture
--   MOCK.rawErrors                       errors that escaped a timer callback or onEvent (unguarded!)
--   MOCK.strictGlobals(on)               error on undeclared global reads/writes

local M = {}
MOCK = M

-- ---------------------------------------------------------------------------
-- helpers
-- ---------------------------------------------------------------------------

local function packn(...)
  return { n = select("#", ...), ... }
end

local function strictTable(t, label)
  for k, v in pairs(t) do
    if type(v) == "table" and getmetatable(v) == nil then
      strictTable(v, label .. "." .. tostring(k))
    end
  end
  return setmetatable(t, {
    __index = function(_, k)
      error(string.format("MOCK: unknown key '%s' in %s", tostring(k), label), 2)
    end,
  })
end

local function shallowCopy(t)
  local r = {}
  for k, v in pairs(t or {}) do
    r[k] = v
  end
  return r
end

local function record(fn, owner, ...)
  local rec = { fn = fn, owner = owner, args = packn(...), t = M.time }
  M.calls[#M.calls + 1] = rec
  return rec
end

local function vec3(x, y, z)
  return { x = x or 0, y = y or 0, z = z or 0 }
end

local function pointInPoly(px, py, pts)
  local inside = false
  local j = #pts
  for i = 1, #pts do
    local xi, yi = pts[i].x, pts[i].y
    local xj, yj = pts[j].x, pts[j].y
    if ((yi > py) ~= (yj > py)) and (px < (xj - xi) * (py - yi) / ((yj - yi) ~= 0 and (yj - yi) or 1e-12) + xi) then
      inside = not inside
    end
    j = i
  end
  return inside
end

local function inArea(area, x, y)
  if area.points then
    return pointInPoly(x, y, area.points)
  end
  local dx, dy = x - area.x, y - area.y
  return dx * dx + dy * dy <= area.radius * area.radius
end

-- ---------------------------------------------------------------------------
-- enums
-- ---------------------------------------------------------------------------

coalition = { side = strictTable({ NEUTRAL = 0, RED = 1, BLUE = 2 }, "coalition.side") }

country = {
  id = strictTable({
    RUSSIA = 0,
    UKRAINE = 1,
    USA = 2,
    TURKEY = 3,
    UK = 4,
    FRANCE = 5,
    GERMANY = 6,
    AGGRESSORS = 7,
    CANADA = 8,
    SPAIN = 9,
    THE_NETHERLANDS = 10,
    BELGIUM = 11,
    NORWAY = 12,
    DENMARK = 13,
    ISRAEL = 15,
    GEORGIA = 16,
    INSURGENTS = 17,
    ABKHAZIA = 18,
    SOUTH_OSETIA = 19,
    ITALY = 20,
    AUSTRALIA = 21,
    BELARUS = 24,
    CHINA = 27,
    EGYPT = 29,
    IRAN = 34,
    IRAQ = 35,
    JAPAN = 36,
    NORTH_KOREA = 38,
    POLAND = 40,
    SAUDI_ARABIA = 42,
    SERBIA = 43,
    SOUTH_KOREA = 45,
    SYRIA = 47,
    YEMEN = 48,
    LIBYA = 58,
    JORDAN = 59,
    USSR = 68,
    KUWAIT = 71,
    QATAR = 72,
    UNITED_ARAB_EMIRATES = 74,
    CUBA = 76,
    LEBANON = 79,
    CJTF_BLUE = 80,
    CJTF_RED = 81,
    UN_PEACEKEEPERS = 82,
  }, "country.id"),
}

local RED_COUNTRIES = {
  RUSSIA = true,
  AGGRESSORS = true,
  INSURGENTS = true,
  ABKHAZIA = true,
  SOUTH_OSETIA = true,
  BELARUS = true,
  CHINA = true,
  IRAN = true,
  IRAQ = true,
  NORTH_KOREA = true,
  SERBIA = true,
  SYRIA = true,
  YEMEN = true,
  LIBYA = true,
  USSR = true,
  CUBA = true,
  CJTF_RED = true,
}

Object =
  { Category = strictTable({ UNIT = 1, WEAPON = 2, STATIC = 3, BASE = 4, SCENERY = 5, CARGO = 6 }, "Object.Category") }

world = {
  event = strictTable({
    S_EVENT_INVALID = 0,
    S_EVENT_SHOT = 1,
    S_EVENT_HIT = 2,
    S_EVENT_TAKEOFF = 3,
    S_EVENT_LAND = 4,
    S_EVENT_CRASH = 5,
    S_EVENT_EJECTION = 6,
    S_EVENT_REFUELING = 7,
    S_EVENT_DEAD = 8,
    S_EVENT_PILOT_DEAD = 9,
    S_EVENT_BASE_CAPTURED = 10,
    S_EVENT_MISSION_START = 11,
    S_EVENT_MISSION_END = 12,
    S_EVENT_TOOK_CONTROL = 13,
    S_EVENT_REFUELING_STOP = 14,
    S_EVENT_BIRTH = 15,
    S_EVENT_HUMAN_FAILURE = 16,
    S_EVENT_DETAILED_FAILURE = 17,
    S_EVENT_ENGINE_STARTUP = 18,
    S_EVENT_ENGINE_SHUTDOWN = 19,
    S_EVENT_PLAYER_ENTER_UNIT = 20,
    S_EVENT_PLAYER_LEAVE_UNIT = 21,
    S_EVENT_PLAYER_COMMENT = 22,
    S_EVENT_SHOOTING_START = 23,
    S_EVENT_SHOOTING_END = 24,
    S_EVENT_MARK_ADDED = 25,
    S_EVENT_MARK_CHANGE = 26,
    S_EVENT_MARK_REMOVED = 27,
    S_EVENT_KILL = 28,
    S_EVENT_SCORE = 29,
    S_EVENT_UNIT_LOST = 30,
    S_EVENT_LANDING_AFTER_EJECTION = 31,
    S_EVENT_DISCARD_CHAIR_AFTER_EJECTION = 33,
    S_EVENT_WEAPON_ADD = 34,
    S_EVENT_TRIGGER_ZONE = 35,
    S_EVENT_LANDING_QUALITY_MARK = 36,
    S_EVENT_BDA = 37,
    S_EVENT_AI_ABORT_MISSION = 38,
    S_EVENT_DAYNIGHT = 39,
    S_EVENT_FLIGHT_TIME = 40,
    S_EVENT_PLAYER_SELF_KILL_PILOT = 41,
    S_EVENT_PLAYER_CAPTURE_AIRFIELD = 42,
    S_EVENT_EMERGENCY_LANDING = 43,
    S_EVENT_UNIT_CREATE_TASK = 44,
    S_EVENT_UNIT_DELETE_TASK = 45,
    S_EVENT_SIMULATION_START = 46,
    S_EVENT_WEAPON_REARM = 47,
    S_EVENT_WEAPON_DROP = 48,
    S_EVENT_UNIT_TASK_COMPLETE = 49,
    S_EVENT_UNIT_TASK_STAGE = 50,
    S_EVENT_MAX = 56,
  }, "world.event"),
  VolumeType = strictTable({ SEGMENT = 0, BOX = 1, SPHERE = 2, PYRAMID = 3 }, "world.VolumeType"),
}

land =
  { SurfaceType = strictTable({ LAND = 1, SHALLOW_WATER = 2, WATER = 3, ROAD = 4, RUNWAY = 5 }, "land.SurfaceType") }

AI = {
  Option = {
    Air = {
      id = {
        NO_OPTION = -1,
        ROE = 0,
        REACTION_ON_THREAT = 1,
        RADAR_USING = 3,
        FLARE_USING = 4,
        FORMATION = 5,
        RTB_ON_BINGO = 6,
        SILENCE = 7,
        RTB_ON_OUT_OF_AMMO = 10,
        ECM_USING = 13,
        PROHIBIT_AA = 14,
        PROHIBIT_JETT = 15,
        PROHIBIT_AB = 16,
        PROHIBIT_AG = 17,
        MISSILE_ATTACK = 18,
        PROHIBIT_WP_PASS_REPORT = 19,
        JETT_TANKS_IF_EMPTY = 25,
        FORCED_ATTACK = 26,
      },
      val = {
        ROE = { WEAPON_FREE = 0, OPEN_FIRE_WEAPON_FREE = 1, OPEN_FIRE = 2, RETURN_FIRE = 3, WEAPON_HOLD = 4 },
        REACTION_ON_THREAT = {
          NO_REACTION = 0,
          PASSIVE_DEFENCE = 1,
          EVADE_FIRE = 2,
          BYPASS_AND_ESCAPE = 3,
          ALLOW_ABORT_MISSION = 4,
        },
        RADAR_USING = { NEVER = 0, FOR_ATTACK_ONLY = 1, FOR_SEARCH_IF_REQUIRED = 2, FOR_CONTINUOUS_SEARCH = 3 },
        FLARE_USING = { NEVER = 0, AGAINST_FIRED_MISSILE = 1, WHEN_FLYING_IN_SAM_WEZ = 2, WHEN_FLYING_NEAR_ENEMIES = 3 },
        ECM_USING = { NEVER_USE = 0, USE_IF_ONLY_LOCK_BY_RADAR = 1, USE_IF_DETECTED_LOCK_BY_RADAR = 2, ALWAYS_USE = 3 },
        MISSILE_ATTACK = {
          MAX_RANGE = 0,
          NEZ_RANGE = 1,
          HALF_WAY_RMAX_NEZ = 2,
          TARGET_THREAT_EST = 3,
          RANDOM_RANGE = 4,
        },
      },
    },
    Ground = {
      id = {
        NO_OPTION = -1,
        ROE = 0,
        FORMATION = 5,
        DISPERSE_ON_ATTACK = 8,
        ALARM_STATE = 9,
        ENGAGE_AIR_WEAPONS = 20,
        AC_ENGAGEMENT_RANGE_RESTRICTION = 24,
      },
      val = {
        ROE = { OPEN_FIRE = 2, RETURN_FIRE = 3, WEAPON_HOLD = 4 },
        ALARM_STATE = { AUTO = 0, GREEN = 1, RED = 2 },
      },
    },
    Naval = {
      id = { NO_OPTION = -1, ROE = 0 },
      val = { ROE = { OPEN_FIRE = 2, RETURN_FIRE = 3, WEAPON_HOLD = 4 } },
    },
  },
  Task = {
    OrbitPattern = { RACE_TRACK = "Race-Track", CIRCLE = "Circle" },
    WeaponExpend = { ONE = "One", TWO = "Two", FOUR = "Four", QUARTER = "Quarter", HALF = "Half", ALL = "All" },
    AltitudeType = { RADIO = "RADIO", BARO = "BARO" },
    TurnMethod = { FLY_OVER_POINT = "Fly Over Point", FIN_POINT = "Fin Point" },
    VehicleFormation = {
      OFF_ROAD = "Off Road",
      ON_ROAD = "On Road",
      RANK = "Rank",
      CONE = "Cone",
      VEE = "Vee",
      DIAMOND = "Diamond",
      ECHELON_LEFT = "EchelonL",
      ECHELON_RIGHT = "EchelonR",
    },
    WaypointType = {
      TAKEOFF = "TakeOff",
      TAKEOFF_PARKING = "TakeOffParking",
      TURNING_POINT = "Turning Point",
      LAND = "Land",
    },
    Designation = { NO = "No", AUTO = "Auto", WP = "WP", IR_POINTER = "IR-Pointer", LASER = "Laser" },
  },
  Skill = {
    AVERAGE = "Average",
    GOOD = "Good",
    HIGH = "High",
    EXCELLENT = "Excellent",
    PLAYER = "Player",
    CLIENT = "Client",
  },
}
strictTable(AI.Option, "AI.Option")
strictTable(AI.Task, "AI.Task")

-- ---------------------------------------------------------------------------
-- state
-- ---------------------------------------------------------------------------

function M.reset()
  M.time = 0
  M.t = 0 -- read-only mirror of M.time
  M.frameTime = 0.01
  M.log = {}
  M.echo = false -- true: print env.* output to stdout
  M.calls = {}
  M.rawErrors = {} -- errors escaping timer callbacks / event handlers
  M.expectRawErrors = false -- runner fails a test with rawErrors unless this is true
  M.timers = {}
  M.nextTimerId = 1
  M.timerSeq = 0
  M.handlers = {}
  M.groups = {} -- name -> group record
  M.units = {} -- name -> unit record
  M.statics = {} -- name -> static record
  M.nextGroupId = 1
  M.nextUnitId = 1
  M.flags = {}
  M.marks = {} -- id -> {kind=, args=}
  M.menus = {} -- key -> list of items; key = "all" | "coalition:N" | "group:N"
  M.zones = {} -- name -> zone record (same table as env.mission.triggers.zones[i])
  M.waterAreas = {} -- {x,y,radius} or {points={...}} ; y = map y (= vec3 z)
  M.roadAreas = {}
  M.surface = nil -- optional function(x, y) -> land.SurfaceType (overrides areas)
  M.terrainHeight = 0 -- number or function(x, y) -> h
  M.losFn = nil -- function(p1, p2) -> bool ; default always visible
  M.detectedTargets = {} -- groupOrUnitName -> list of detected-target tables
  M.countryCoalition = {}
  for name, id in pairs(country.id_raw or {}) do
    M.countryCoalition[id] = RED_COUNTRIES[name] and 1 or (name == "UN_PEACEKEEPERS" and 0 or 2)
  end
  env.mission = {
    theatre = "Caucasus",
    start_time = 28800,
    date = { Year = 2024, Month = 6, Day = 15 },
    triggers = { zones = {} },
    coalition = {},
    weather = {},
  }
end

-- country.id is strict; keep a raw copy for iteration
do
  local raw = {}
  for k, v in pairs(country.id) do
    raw[k] = v
  end
  country.id_raw = raw
end

-- ---------------------------------------------------------------------------
-- env
-- ---------------------------------------------------------------------------

env = {}
local function envLog(level, msg)
  msg = tostring(msg)
  M.log[#M.log + 1] = { level = level, msg = msg, t = M.time }
  if M.echo then
    print(string.format("[%8.2f] %-7s %s", M.time, level, msg))
  end
end
function env.info(msg)
  envLog("info", msg)
end
function env.warning(msg)
  envLog("warning", msg)
end
function env.error(msg)
  envLog("error", msg)
end
function env.setErrorMessageBoxEnabled() end
function env.getValueDictByKey(k)
  return k
end

function M.logContains(pattern, level)
  for _, e in ipairs(M.log) do
    if (level == nil or e.level == level) and string.find(e.msg, pattern) then
      return true, e
    end
  end
  return false
end

function M.logLines(level)
  local r = {}
  for _, e in ipairs(M.log) do
    if level == nil or e.level == level then
      r[#r + 1] = e.msg
    end
  end
  return r
end

local function rawError(where, err)
  M.rawErrors[#M.rawErrors + 1] = { where = where, err = tostring(err), t = M.time }
  envLog("error", "MOCK raw error in " .. where .. ": " .. tostring(err))
end

-- ---------------------------------------------------------------------------
-- timer
-- ---------------------------------------------------------------------------

timer = {}
function timer.getTime()
  return M.time
end
function timer.getAbsTime()
  return env.mission.start_time + M.time
end
function timer.getTime0()
  return env.mission.start_time
end

function timer.scheduleFunction(fn, arg, t)
  if type(fn) ~= "function" then
    error("timer.scheduleFunction: function expected", 2)
  end
  if type(t) ~= "number" then
    error("timer.scheduleFunction: time must be a number", 2)
  end
  local id = M.nextTimerId
  M.nextTimerId = id + 1
  M.timerSeq = M.timerSeq + 1
  M.timers[id] = { id = id, fn = fn, arg = arg, time = t, seq = M.timerSeq }
  return id
end

function timer.removeFunction(id)
  M.timers[id] = nil
end

function timer.setFunctionTime(id, t)
  if M.timers[id] then
    M.timers[id].time = t
  end
end

function M.pendingTimers()
  local n = 0
  for _ in pairs(M.timers) do
    n = n + 1
  end
  return n
end

function M.now()
  return M.time
end

-- Advance the fake clock by `sec`, running every callback due in time order.
-- A callback returning a number is re-armed (same id) at that time, like DCS.
-- A callback that errors is logged to MOCK.rawErrors and dies, like DCS.
function M.advance(sec)
  local target = M.time + (sec or 0)
  local guard = 0
  while true do
    local best
    for _, e in pairs(M.timers) do
      if e.time <= target and (best == nil or e.time < best.time or (e.time == best.time and e.seq < best.seq)) then
        best = e
      end
    end
    if not best then
      break
    end
    guard = guard + 1
    if guard > 200000 then
      error("MOCK.advance: runaway timers")
    end
    M.timers[best.id] = nil
    if best.time > M.time then
      M.time = best.time
      M.t = M.time
    end
    local ok, r = pcall(best.fn, best.arg, M.time)
    if not ok then
      rawError("timer callback #" .. best.id, r)
    elseif type(r) == "number" then
      if r <= M.time then
        r = M.time + M.frameTime
      end
      M.timerSeq = M.timerSeq + 1
      best.time, best.seq = r, M.timerSeq
      M.timers[best.id] = best
    end
  end
  M.time = target
  M.t = target
end

-- ---------------------------------------------------------------------------
-- objects: Unit, Group, StaticObject, Controller, Weapon, Scenery
-- ---------------------------------------------------------------------------

Unit = {
  Category = strictTable({ AIRPLANE = 0, HELICOPTER = 1, GROUND_UNIT = 2, SHIP = 3, STRUCTURE = 4 }, "Unit.Category"),
}
Unit.__index = Unit
Group = { Category = strictTable({ AIRPLANE = 0, HELICOPTER = 1, GROUND = 2, SHIP = 3, TRAIN = 4 }, "Group.Category") }
Group.__index = Group
StaticObject = {}
StaticObject.__index = StaticObject
Controller = {}
Controller.__index = Controller
Weapon = { Category = { SHELL = 0, MISSILE = 1, ROCKET = 2, BOMB = 3, TORPEDO = 4 } }
Weapon.__index = Weapon
SceneryObject = {}
SceneryObject.__index = SceneryObject
Airbase = { Category = { AIRDROME = 0, HELIPAD = 1, SHIP = 2 } }
Airbase.__index = Airbase

local GROUP_TO_UNIT_CAT = { [0] = 0, [1] = 1, [2] = 2, [3] = 3, [4] = 2 }

local function unitRec(self)
  local r = M.units[self.name_]
  if r and r.obj == self then
    return r
  end
  return nil
end

local function liveUnit(self, fname)
  local r = unitRec(self)
  if not r or r.dead then
    error(string.format("Unit.%s: unit '%s' does not exist", fname, tostring(self.name_)), 3)
  end
  return r
end

-- rec: the owning group/unit record; mirrors state for easy assertions:
--   rec.task (current task), rec.tasks (number of setTask+pushTask calls), rec.pushed (last pushed),
--   rec.stopped (last StopRoute value), rec.roe / rec.alarm (last ROE / ALARM_STATE option values)
local function newController(ownerName, ownerKind, rec)
  return setmetatable({
    owner = ownerName,
    kind = ownerKind,
    rec = rec or {},
    options = {},
    task = nil,
    tasks = {},
    commands = {},
    onOff = true,
  }, Controller)
end

-- Unit -----------------------------------------------------------------
function Unit.getByName(name)
  local r = M.units[name]
  if r and not r.dead then
    return r.obj
  end
  return nil
end
function Unit:isExist()
  local r = unitRec(self)
  return r ~= nil and not r.dead
end
function Unit:isActive()
  return liveUnit(self, "isActive").active
end
function Unit:getName()
  return self.name_
end
function Unit:getID()
  local r = M.units[self.name_]
  return r and r.id
end
function Unit:getTypeName()
  local r = M.units[self.name_]
  return r and r.type
end
function Unit:getCategory()
  liveUnit(self, "getCategory")
  return Object.Category.UNIT
end
function Unit:getCategoryEx()
  return liveUnit(self, "getCategoryEx").unitCategory
end
function Unit:getDesc()
  local r = liveUnit(self, "getDesc")
  return {
    typeName = r.type,
    displayName = r.type,
    category = r.unitCategory,
    life = r.life0,
    attributes = r.attributes or {},
  }
end
function Unit:hasAttribute(a)
  local r = liveUnit(self, "hasAttribute")
  return (r.attributes or {})[a] == true
end
function Unit:getGroup()
  return M.groups[liveUnit(self, "getGroup").group].obj
end
function Unit:getCoalition()
  return liveUnit(self, "getCoalition").coalition
end
function Unit:getCountry()
  return liveUnit(self, "getCountry").country
end
function Unit:getPoint()
  local r = liveUnit(self, "getPoint")
  return vec3(r.x, r.alt, r.z)
end
function Unit:getPosition()
  local r = liveUnit(self, "getPosition")
  local c, s = math.cos(r.heading), math.sin(r.heading)
  return { p = vec3(r.x, r.alt, r.z), x = vec3(c, 0, s), y = vec3(0, 1, 0), z = vec3(-s, 0, c) }
end
function Unit:getVelocity()
  local r = liveUnit(self, "getVelocity")
  return shallowCopy(r.velocity or vec3())
end
function Unit:getLife()
  return liveUnit(self, "getLife").life
end
function Unit:getLife0()
  return liveUnit(self, "getLife0").life0
end
function Unit:getPlayerName()
  return liveUnit(self, "getPlayerName").playerName
end
function Unit:getCallsign()
  return liveUnit(self, "getCallsign").callsign or self.name_
end
function Unit:getNumber()
  return liveUnit(self, "getNumber").number
end
function Unit:inAir()
  return liveUnit(self, "inAir").inAir == true
end
function Unit:getFuel()
  return liveUnit(self, "getFuel").fuel or 1
end
function Unit:getAmmo()
  return liveUnit(self, "getAmmo").ammo
end
function Unit:getSensors()
  return {}
end
function Unit:hasSensors()
  return false
end
function Unit:getRadar()
  return false, nil
end
function Unit:enableEmission(on)
  record("Unit.enableEmission", self.name_, on)
end
function Unit:getController()
  local r = liveUnit(self, "getController")
  r.controller = r.controller or newController(self.name_, "unit", r)
  return r.controller
end
function Unit:destroy()
  local r = unitRec(self)
  if r and not r.dead then
    r.dead = true
    r.destroyed = true
  end
  record("Unit.destroy", self.name_)
end

-- Group ----------------------------------------------------------------
local function groupRec(self)
  local r = M.groups[self.name_]
  if r and r.obj == self then
    return r
  end
  return nil
end
local function aliveUnitRecs(g)
  local list = {}
  for _, un in ipairs(g.units) do
    local u = M.units[un]
    if u and not u.dead and u.group == g.name then
      list[#list + 1] = u
    end
  end
  return list
end
local function groupExists(g)
  return g ~= nil and not g.destroyed and #aliveUnitRecs(g) > 0
end
local function liveGroup(self, fname)
  local g = groupRec(self)
  if not groupExists(g) then
    error(string.format("Group.%s: group '%s' does not exist", fname, tostring(self.name_)), 3)
  end
  return g
end

function Group.getByName(name)
  local g = M.groups[name]
  if groupExists(g) then
    return g.obj
  end
  return nil
end
function Group:isExist()
  return groupExists(groupRec(self))
end
function Group:getName()
  return self.name_
end
function Group:getID()
  local g = M.groups[self.name_]
  return g and g.id
end
function Group:getCategory()
  return liveGroup(self, "getCategory").category
end
function Group:getCategoryEx()
  return liveGroup(self, "getCategoryEx").category
end
function Group:getCoalition()
  return liveGroup(self, "getCoalition").coalition
end
function Group:getSize()
  return #aliveUnitRecs(liveGroup(self, "getSize"))
end
function Group:getInitialSize()
  return #liveGroup(self, "getInitialSize").units
end
function Group:getUnits()
  local r = {}
  for _, u in ipairs(aliveUnitRecs(liveGroup(self, "getUnits"))) do
    r[#r + 1] = u.obj
  end
  return r
end
function Group:getUnit(i)
  local list = aliveUnitRecs(liveGroup(self, "getUnit"))
  local u = list[i]
  return u and u.obj or nil
end
function Group:getController()
  local g = liveGroup(self, "getController")
  g.controller = g.controller or newController(self.name_, "group", g)
  return g.controller
end
function Group:activate()
  local g = liveGroup(self, "activate")
  record("Group.activate", self.name_)
  for _, u in ipairs(aliveUnitRecs(g)) do
    if not u.active then
      u.active = true
      if not g.silent then
        M.fireEvent({ id = world.event.S_EVENT_BIRTH, initiator = u.obj })
      end
    end
  end
end
function Group:destroy()
  local g = groupRec(self)
  record("Group.destroy", self.name_)
  if not g then
    return
  end
  for _, u in ipairs(aliveUnitRecs(g)) do
    u.dead = true
    u.destroyed = true
  end
  g.destroyed = true
end
function Group:enableEmission(on)
  record("Group.enableEmission", self.name_, on)
end

-- StaticObject ---------------------------------------------------------
local function liveStatic(self, fname)
  local r = M.statics[self.name_]
  if not r or r.obj ~= self or r.dead then
    error(string.format("StaticObject.%s: '%s' does not exist", fname, tostring(self.name_)), 3)
  end
  return r
end
function StaticObject.getByName(name)
  local r = M.statics[name]
  if r and not r.dead then
    return r.obj
  end
  return nil
end
function StaticObject:isExist()
  local r = M.statics[self.name_]
  return r ~= nil and r.obj == self and not r.dead
end
function StaticObject:getName()
  return self.name_
end
function StaticObject:getID()
  local r = M.statics[self.name_]
  return r and r.id
end
function StaticObject:getTypeName()
  local r = M.statics[self.name_]
  return r and r.type
end
function StaticObject:getCategory()
  liveStatic(self, "getCategory")
  return Object.Category.STATIC
end
function StaticObject:getCoalition()
  return liveStatic(self, "getCoalition").coalition
end
function StaticObject:getCountry()
  return liveStatic(self, "getCountry").country
end
function StaticObject:getPoint()
  local r = liveStatic(self, "getPoint")
  return vec3(r.x, 0, r.z)
end
function StaticObject:getPosition()
  local r = liveStatic(self, "getPosition")
  return { p = vec3(r.x, 0, r.z), x = vec3(1, 0, 0), y = vec3(0, 1, 0), z = vec3(0, 0, 1) }
end
function StaticObject:getLife()
  return liveStatic(self, "getLife").life
end
function StaticObject:getDesc()
  local r = liveStatic(self, "getDesc")
  return { typeName = r.type, life = r.life0 }
end
function StaticObject:destroy()
  local r = M.statics[self.name_]
  if r then
    r.dead = true
  end
  record("StaticObject.destroy", self.name_)
end

-- Weapon / Scenery (only what event consumers need) ------------------
function Weapon:isExist()
  return true
end
function Weapon:getCategory()
  return Object.Category.WEAPON
end
function Weapon:getTypeName()
  return self.type_
end
function Weapon:getName()
  return self.type_
end
function Weapon:getDesc()
  return { typeName = self.type_, category = 1 }
end
function Weapon:getLauncher()
  return self.launcher_
end
function Weapon:getTarget()
  return self.target_
end
function Weapon:getPoint()
  return vec3()
end
function M.makeWeapon(typeName, launcher)
  return setmetatable({ type_ = typeName or "AIM_120C", launcher_ = launcher }, Weapon)
end

function SceneryObject:isExist()
  return true
end
function SceneryObject:getCategory()
  return Object.Category.SCENERY
end
function SceneryObject:getTypeName()
  return self.type_
end
function SceneryObject:getName()
  return self.type_
end
function SceneryObject:getPoint()
  return shallowCopy(self.pos_)
end
function SceneryObject:getLife()
  return 1
end
function M.makeScenery(typeName, pos)
  return setmetatable({ type_ = typeName or "building", pos_ = pos or vec3() }, SceneryObject)
end

function Airbase:getName()
  return self.name_
end
function Airbase:getCategory()
  return Object.Category.BASE
end
function Airbase:getPoint()
  return shallowCopy(self.pos_)
end
function Airbase:getCoalition()
  return self.coalition_ or 0
end
function Airbase:getDesc()
  return { category = Airbase.Category.AIRDROME }
end
function M.makeAirbase(name, pos, side)
  return setmetatable({ name_ = name, pos_ = pos or vec3(), coalition_ = side }, Airbase)
end

-- Controller (STRICT) ---------------------------------------------------
local function validateTask(task, depth)
  depth = depth or 0
  if type(task) ~= "table" then
    error("Controller: task must be a table", 4 + depth)
  end
  if task.id == "Mission" then
    local pts = task.params and task.params.route and task.params.route.points
    if type(pts) ~= "table" or #pts < 2 then
      error("MOCK Controller: Mission task needs params.route.points with >= 2 points", 4 + depth)
    end
    for i, p in ipairs(pts) do
      if type(p.x) ~= "number" or type(p.y) ~= "number" then
        error("MOCK Controller: route point " .. i .. " needs numeric x and y", 4 + depth)
      end
    end
  elseif task.id == "ComboTask" then
    for _, t in ipairs((task.params and task.params.tasks) or {}) do
      validateTask(t, depth)
    end
  end
end

function Controller:setTask(task)
  validateTask(task)
  self.task = task
  self.tasks = { task }
  self.rec.task = task
  self.rec.tasks = (self.rec.tasks or 0) + 1
  record("Controller.setTask", self.owner, task)
end
function Controller:pushTask(task)
  validateTask(task)
  self.tasks[#self.tasks + 1] = task
  self.task = task
  self.rec.task = task
  self.rec.pushed = task
  self.rec.tasks = (self.rec.tasks or 0) + 1
  record("Controller.pushTask", self.owner, task)
end
function Controller:popTask()
  self.tasks[#self.tasks] = nil
  self.task = self.tasks[#self.tasks]
  record("Controller.popTask", self.owner)
end
function Controller:resetTask()
  self.task = nil
  self.tasks = {}
  record("Controller.resetTask", self.owner)
end
function Controller:hasTask()
  return self.task ~= nil
end
function Controller:setCommand(cmd)
  if type(cmd) ~= "table" or type(cmd.id) ~= "string" then
    error("MOCK Controller: setCommand needs {id=string, params=table}", 2)
  end
  self.commands[#self.commands + 1] = cmd
  if cmd.id == "StopRoute" and type(cmd.params) == "table" then
    self.rec.stopped = cmd.params.value == true
  end
  record("Controller.setCommand", self.owner, cmd)
end
function Controller:setOption(id, value)
  if type(id) ~= "number" then
    error("MOCK Controller: setOption id must be a number (got " .. tostring(id) .. ")", 2)
  end
  if value == nil then
    error("MOCK Controller: setOption value is nil for option id " .. id, 2)
  end
  self.options[id] = value
  if id == 0 then
    self.rec.roe = value
  elseif id == 9 and self.kind ~= "air" then
    self.rec.alarm = value
  end
  record("Controller.setOption", self.owner, id, value)
end
function Controller:setOnOff(on)
  self.onOff = on
  record("Controller.setOnOff", self.owner, on)
end
function Controller:knowTarget(obj, type_, dist)
  record("Controller.knowTarget", self.owner, obj, type_, dist)
end
function Controller:getDetectedTargets()
  return M.detectedTargets[self.owner] or {}
end
function Controller:isTargetDetected(obj)
  for _, d in ipairs(M.detectedTargets[self.owner] or {}) do
    if d.object == obj then
      return true, true, d.lastTime or M.time, d.type ~= false, d.distance ~= false, d.lastPos, d.lastVel
    end
  end
  return false
end

-- ---------------------------------------------------------------------------
-- coalition
-- ---------------------------------------------------------------------------

function coalition.getCountryCoalition(cid)
  local s = M.countryCoalition[cid]
  if s == nil then
    return 2
  end
  return s
end

-- data: DCS group table {name=, units={{name=, type=, x=, y=, alt=, heading=, skill=, playerName=}}, lateActivation=, hidden=, task=, route=}
-- opts (mock only): {silent=true} suppresses BIRTH events
function coalition.addGroup(countryId, groupCategory, data, opts)
  if type(countryId) ~= "number" then
    error("coalition.addGroup: country id must be a number", 2)
  end
  if type(groupCategory) ~= "number" then
    error("coalition.addGroup: group category must be a number", 2)
  end
  if type(data) ~= "table" or type(data.units) ~= "table" or #data.units == 0 then
    error("coalition.addGroup: data.units must be a non-empty list", 2)
  end
  opts = opts or {}
  local name = data.name or ("Group #" .. M.nextGroupId)
  local old = M.groups[name]
  if old then
    Group.destroy(old.obj)
  end -- DCS: name clash replaces the group
  local side = coalition.getCountryCoalition(countryId)
  local gid = data.groupId or M.nextGroupId
  M.nextGroupId = math.max(M.nextGroupId, gid) + 1
  local g = {
    name = name,
    id = gid,
    category = groupCategory,
    coalition = side,
    country = countryId,
    units = {},
    data = data,
    lateActivation = data.lateActivation == true,
    silent = opts.silent,
    obj = setmetatable({ id_ = gid, name_ = name }, Group),
  }
  M.groups[name] = g
  local ucat = GROUP_TO_UNIT_CAT[groupCategory] or 2
  for i, ud in ipairs(data.units) do
    local uname = ud.name or (name .. "-" .. i)
    local oldU = M.units[uname]
    if oldU and not oldU.dead then
      oldU.dead = true
      oldU.destroyed = true
    end
    local uid = ud.unitId or M.nextUnitId
    M.nextUnitId = math.max(M.nextUnitId, uid) + 1
    local alt = ud.alt
    if alt == nil then
      alt = land.getHeight({ x = ud.x or 0, y = ud.y or ud.z or 0 })
    end
    local u = {
      name = uname,
      id = uid,
      type = ud.type or "T-72B",
      x = ud.x or 0,
      z = ud.y or ud.z or 0,
      alt = alt,
      heading = ud.heading or 0,
      group = name,
      coalition = side,
      country = countryId,
      unitCategory = ucat,
      life = ud.life or 10,
      life0 = ud.life or 10,
      active = not g.lateActivation,
      playerName = ud.playerName,
      skill = ud.skill,
      number = i,
      inAir = (ucat <= 1) and (ud.alt or 0) > 50,
      attributes = ud.attributes,
      obj = setmetatable({ id_ = uid, name_ = uname }, Unit),
    }
    M.units[uname] = u
    g.units[#g.units + 1] = uname
  end
  record("coalition.addGroup", name, countryId, groupCategory, data)
  if not opts.silent then
    for _, un in ipairs(g.units) do
      local u = M.units[un]
      if u.active and not u.dead then
        M.fireEvent({ id = world.event.S_EVENT_BIRTH, initiator = u.obj })
      end
    end
  end
  return g.obj
end

function coalition.addStaticObject(countryId, data)
  local name = data.name or ("Static #" .. M.nextUnitId)
  local id = M.nextUnitId
  M.nextUnitId = id + 1
  local r = {
    name = name,
    id = id,
    type = data.type or "Warehouse",
    x = data.x or 0,
    z = data.y or 0,
    country = countryId,
    coalition = coalition.getCountryCoalition(countryId),
    life = data.life or 100,
    life0 = data.life or 100,
    obj = setmetatable({ id_ = id, name_ = name }, StaticObject),
  }
  M.statics[name] = r
  record("coalition.addStaticObject", name, countryId, data)
  return r.obj
end

function coalition.getGroups(side, cat)
  local list = {}
  local names = {}
  for name in pairs(M.groups) do
    names[#names + 1] = name
  end
  table.sort(names)
  for _, name in ipairs(names) do
    local g = M.groups[name]
    if groupExists(g) and g.coalition == side and (cat == nil or g.category == cat) then
      list[#list + 1] = g.obj
    end
  end
  return list
end

function coalition.getPlayers(side)
  local list = {}
  for _, u in pairs(M.units) do
    if not u.dead and u.playerName and u.coalition == side and u.active then
      list[#list + 1] = u.obj
    end
  end
  return list
end

function coalition.getStaticObjects(side)
  local list = {}
  for _, s in pairs(M.statics) do
    if not s.dead and s.coalition == side then
      list[#list + 1] = s.obj
    end
  end
  return list
end

function coalition.getAirbases()
  return {}
end
function coalition.addRefPoint() end
function coalition.getMainRefPoint()
  return vec3()
end

-- ---------------------------------------------------------------------------
-- trigger
-- ---------------------------------------------------------------------------

trigger = {
  action = {},
  misc = {},
  smokeColor = strictTable({ Green = 0, Red = 1, White = 2, Orange = 3, Blue = 4 }, "trigger.smokeColor"),
  flareColor = strictTable({ Green = 0, Red = 1, White = 2, Yellow = 3 }, "trigger.flareColor"),
}

local function recorder(name)
  return function(...)
    record("trigger.action." .. name, nil, ...)
  end
end
for _, name in ipairs({
  "outText",
  "outTextForCoalition",
  "outTextForCountry",
  "outTextForGroup",
  "outTextForUnit",
  "outSound",
  "outSoundForCoalition",
  "outSoundForCountry",
  "outSoundForGroup",
  "outSoundForUnit",
  "radioTransmission",
  "stopRadioTransmission",
  "smoke",
  "effectSmokeBig",
  "effectSmokeStop",
  "illuminationBomb",
  "signalFlare",
  "explosion",
  "setGroupAIOn",
  "setGroupAIOff",
  "groupStopMoving",
  "groupContinueMoving",
  "setAITask",
  "pushAITask",
  "ctfColorTag",
  "setMarkupText",
  "setMarkupColor",
  "setMarkupColorFill",
  "setMarkupFontSize",
  "setMarkupPositionStart",
  "setMarkupPositionEnd",
  "setMarkupRadius",
  "setMarkupTypeLine",
}) do
  trigger.action[name] = recorder(name)
end

local function addMark(kind, id, ...)
  if type(id) ~= "number" then
    error("trigger.action." .. kind .. ": mark id must be a number", 3)
  end
  M.marks[id] = { kind = kind, id = id, args = packn(...), t = M.time }
  record("trigger.action." .. kind, nil, id, ...)
end
function trigger.action.markToAll(id, text, pos, ro, msg)
  addMark("markToAll", id, text, pos, ro, msg)
end
function trigger.action.markToCoalition(id, text, pos, coal, ro, msg)
  addMark("markToCoalition", id, text, pos, coal, ro, msg)
end
function trigger.action.markToGroup(id, text, pos, gid, ro, msg)
  addMark("markToGroup", id, text, pos, gid, ro, msg)
end
-- shape functions take coalition first, id second
for _, name in ipairs({ "circleToAll", "lineToAll", "rectToAll", "quadToAll", "textToAll", "arrowToAll", "markupToAll" }) do
  trigger.action[name] = function(coal, id, ...)
    if type(id) ~= "number" then
      error("trigger.action." .. name .. ": mark id must be a number", 2)
    end
    M.marks[id] = { kind = name, id = id, coalition = coal, args = packn(...), t = M.time }
    record("trigger.action." .. name, nil, coal, id, ...)
  end
end
function trigger.action.removeMark(id)
  M.marks[id] = nil
  record("trigger.action.removeMark", nil, id)
end

function trigger.action.setUserFlag(flag, value)
  if value == true then
    value = 1
  elseif value == false or value == nil then
    value = 0
  end
  M.flags[tostring(flag)] = tonumber(value) or 0
  record("trigger.action.setUserFlag", nil, flag, value)
end
function trigger.misc.getUserFlag(flag)
  return M.flags[tostring(flag)] or 0
end

function trigger.action.activateGroup(g)
  record("trigger.action.activateGroup", g and g.name_)
  if g then
    g:activate()
  end
end
function trigger.action.deactivateGroup(g)
  record("trigger.action.deactivateGroup", g and g.name_)
  if g then
    g:destroy()
  end
end

function trigger.misc.getZone(name)
  local z = M.zones[name]
  if not z then
    return nil
  end
  return { point = vec3(z.x, 0, z.y), radius = z.radius }
end

-- MOCK.addZone{name=, x=, y=, radius=} or {name=, points={{x=,y=},...}} (quad/polygon, type 2)
function M.addZone(z)
  local rec = {
    name = z.name,
    x = z.x or 0,
    y = z.y or 0,
    radius = z.radius or 0,
    type = 0,
    zoneId = #env.mission.triggers.zones + 1,
    properties = z.properties or {},
    color = { 1, 1, 1, 0.15 },
  }
  if z.points then
    rec.type = 2
    rec.verticies = z.points
    local sx, sy = 0, 0
    for _, p in ipairs(z.points) do
      sx, sy = sx + p.x, sy + p.y
    end
    rec.x, rec.y = sx / #z.points, sy / #z.points
    local r = 0
    for _, p in ipairs(z.points) do
      r = math.max(r, math.sqrt((p.x - rec.x) ^ 2 + (p.y - rec.y) ^ 2))
    end
    if not z.radius then
      rec.radius = r
    end
  end
  M.zones[z.name] = rec
  local zl = env.mission.triggers.zones
  zl[#zl + 1] = rec
  return rec
end

-- ---------------------------------------------------------------------------
-- world
-- ---------------------------------------------------------------------------

function world.addEventHandler(h)
  if type(h) ~= "table" or type(h.onEvent) ~= "function" then
    error("world.addEventHandler: handler needs onEvent", 2)
  end
  for _, x in ipairs(M.handlers) do
    if x == h then
      return
    end
  end
  M.handlers[#M.handlers + 1] = h
end
function world.removeEventHandler(h)
  for i, x in ipairs(M.handlers) do
    if x == h then
      table.remove(M.handlers, i)
      return
    end
  end
end
function world.getPlayer()
  return nil
end
function world.getAirbases()
  return {}
end
function world.getMarkPanels()
  local r = {}
  for id, m in pairs(M.marks) do
    r[#r + 1] = { idx = id, text = m.args[1], pos = m.args[2] }
  end
  return r
end

-- MOCK.fireEvent{id = world.event.X | "BIRTH" | "S_EVENT_BIRTH", initiator=, target=, weapon=, ...}
function M.fireEvent(e)
  if type(e.id) == "string" then
    local key = e.id
    if string.sub(key, 1, 8) ~= "S_EVENT_" then
      key = "S_EVENT_" .. key
    end
    e.id = world.event[key]
  end
  if e.time == nil then
    e.time = M.time
  end
  local hs = {}
  for i, h in ipairs(M.handlers) do
    hs[i] = h
  end
  for _, h in ipairs(hs) do
    local ok, err = pcall(h.onEvent, h, e)
    if not ok then
      rawError("onEvent(" .. tostring(e.id) .. ")", err)
    end
  end
  return e
end

local function catMatches(cat, want)
  if type(cat) == "table" then
    for _, c in ipairs(cat) do
      if c == want then
        return true
      end
    end
    return false
  end
  return cat == want
end

-- Supports SPHERE volumes for UNIT and STATIC categories. Handler returns true to continue.
function world.searchObjects(cat, volume, handler, data)
  record("world.searchObjects", nil, cat, volume)
  if type(volume) ~= "table" or volume.id ~= world.VolumeType.SPHERE then
    return 0
  end
  local c, r = volume.params.point, volume.params.radius
  local found = {}
  if catMatches(cat, Object.Category.UNIT) then
    for _, u in pairs(M.units) do
      if not u.dead and u.active and (u.x - c.x) ^ 2 + (u.z - c.z) ^ 2 <= r * r then
        found[#found + 1] = u.obj
      end
    end
  end
  if catMatches(cat, Object.Category.STATIC) then
    for _, s in pairs(M.statics) do
      if not s.dead and (s.x - c.x) ^ 2 + (s.z - c.z) ^ 2 <= r * r then
        found[#found + 1] = s.obj
      end
    end
  end
  local n = 0
  for _, o in ipairs(found) do
    n = n + 1
    if handler and handler(o, data) ~= true then
      break
    end
  end
  return n
end

-- ---------------------------------------------------------------------------
-- land
-- ---------------------------------------------------------------------------

function land.getHeight(p)
  if type(M.terrainHeight) == "function" then
    return M.terrainHeight(p.x, p.y)
  end
  return M.terrainHeight or 0
end
function land.getSurfaceType(p)
  if M.surface then
    return M.surface(p.x, p.y)
  end
  for _, a in ipairs(M.waterAreas) do
    if inArea(a, p.x, p.y) then
      return a.shallow and land.SurfaceType.SHALLOW_WATER or land.SurfaceType.WATER
    end
  end
  for _, a in ipairs(M.roadAreas) do
    if inArea(a, p.x, p.y) then
      return land.SurfaceType.ROAD
    end
  end
  return land.SurfaceType.LAND
end
function land.isVisible(p1, p2)
  if M.losFn then
    return M.losFn(p1, p2) == true
  end
  return true
end
function land.getIP(origin, dir, dist)
  return nil
end
function land.getClosestPointOnRoads(roadType, x, y)
  return x, y
end
function land.findPathOnRoads(roadType, x1, y1, x2, y2)
  return { { x = x1, y = y1 }, { x = x2, y = y2 } }
end
function land.profile(p1, p2)
  return { vec3(p1.x, 0, p1.y), vec3(p2.x, 0, p2.y) }
end

-- ---------------------------------------------------------------------------
-- missionCommands
-- ---------------------------------------------------------------------------

missionCommands = {}
local function menuAdd(key, kind, name, path, fn, arg)
  M.menus[key] = M.menus[key] or {}
  local full = {}
  for i, p in ipairs(path or {}) do
    full[i] = p
  end
  full[#full + 1] = name
  M.menus[key][#M.menus[key] + 1] = { kind = kind, name = name, path = full, fn = fn, arg = arg }
  return full
end
local function pathEq(a, b)
  if #a ~= #b then
    return false
  end
  for i = 1, #a do
    if a[i] ~= b[i] then
      return false
    end
  end
  return true
end
local function pathPrefix(prefix, p)
  if #prefix > #p then
    return false
  end
  for i = 1, #prefix do
    if prefix[i] ~= p[i] then
      return false
    end
  end
  return true
end
local function menuRemove(key, path)
  local items = M.menus[key]
  if not items then
    return
  end
  if path == nil then
    M.menus[key] = {}
    return
  end
  local keep = {}
  for _, it in ipairs(items) do
    if not pathPrefix(path, it.path) then
      keep[#keep + 1] = it
    end
  end
  M.menus[key] = keep
end

function missionCommands.addCommand(name, path, fn, arg)
  record("missionCommands.addCommand", nil, name, path)
  return menuAdd("all", "command", name, path, fn, arg)
end
function missionCommands.addSubMenu(name, path)
  record("missionCommands.addSubMenu", nil, name, path)
  return menuAdd("all", "menu", name, path)
end
function missionCommands.removeItem(path)
  record("missionCommands.removeItem", nil, path)
  menuRemove("all", path)
end
function missionCommands.addCommandForCoalition(c, name, path, fn, arg)
  record("missionCommands.addCommandForCoalition", nil, c, name, path)
  return menuAdd("coalition:" .. c, "command", name, path, fn, arg)
end
function missionCommands.addSubMenuForCoalition(c, name, path)
  record("missionCommands.addSubMenuForCoalition", nil, c, name, path)
  return menuAdd("coalition:" .. c, "menu", name, path)
end
function missionCommands.removeItemForCoalition(c, path)
  record("missionCommands.removeItemForCoalition", nil, c, path)
  menuRemove("coalition:" .. c, path)
end
function missionCommands.addCommandForGroup(gid, name, path, fn, arg)
  if type(gid) ~= "number" then
    error("missionCommands.addCommandForGroup: group id must be a number", 2)
  end
  record("missionCommands.addCommandForGroup", gid, name, path)
  return menuAdd("group:" .. gid, "command", name, path, fn, arg)
end
function missionCommands.addSubMenuForGroup(gid, name, path)
  if type(gid) ~= "number" then
    error("missionCommands.addSubMenuForGroup: group id must be a number", 2)
  end
  record("missionCommands.addSubMenuForGroup", gid, name, path)
  return menuAdd("group:" .. gid, "menu", name, path)
end
function missionCommands.removeItemForGroup(gid, path)
  record("missionCommands.removeItemForGroup", gid, path)
  menuRemove("group:" .. gid, path)
end

-- MOCK.menuItems(key) -> list ; key "all" | "coalition:2" | "group:<gid>"
function M.menuItems(key)
  return M.menus[key] or {}
end
-- MOCK.invokeMenu(key, {"Root","Sub","Cmd"}) calls the command's function with its arg.
function M.invokeMenu(key, path)
  for _, it in ipairs(M.menus[key] or {}) do
    if it.kind == "command" and pathEq(it.path, path) then
      return it.fn(it.arg)
    end
  end
  error("MOCK.invokeMenu: no command " .. table.concat(path, "/") .. " for " .. key, 2)
end

-- ---------------------------------------------------------------------------
-- Spot, coord, net
-- ---------------------------------------------------------------------------

Spot = { Category = strictTable({ INFRA_RED = 0, LASER = 1 }, "Spot.Category") }
Spot.__index = Spot
local function newSpot(cat, src, target, code)
  local s = setmetatable({ cat = cat, source = src, point = target, code = code }, Spot)
  record("Spot.create", nil, cat, src, target, code)
  return s
end
function Spot.createLaser(src, localRef, target, code)
  return newSpot(Spot.Category.LASER, src, target, code or 1688)
end
function Spot.createInfraRed(src, localRef, target)
  return newSpot(Spot.Category.INFRA_RED, src, target)
end
function Spot:destroy()
  self.destroyed = true
  record("Spot.destroy", nil, self)
end
function Spot:getPoint()
  return self.point
end
function Spot:setPoint(p)
  self.point = p
end
function Spot:getCode()
  return self.code
end
function Spot:setCode(c)
  self.code = c
end
function Spot:getCategory()
  return self.cat
end

coord = {}
-- crude flat-earth conversion around a fixed origin (good enough for tests)
local LAT0, LON0, MPD = 42.0, 42.0, 111320
function coord.LOtoLL(p)
  return LAT0 + p.x / MPD, LON0 + p.z / (MPD * math.cos(math.rad(LAT0))), p.y or 0
end
function coord.LLtoLO(lat, lon, alt)
  return vec3((lat - LAT0) * MPD, alt or 0, (lon - LON0) * MPD * math.cos(math.rad(LAT0)))
end
function coord.LLtoMGRS(lat, lon)
  return { UTMZone = "38T", MGRSDigraph = "KM", Easting = 0, Northing = 0 }
end

net = {}
function net.get_player_list()
  return {}
end
function net.get_player_info()
  return nil
end
function net.log(msg)
  envLog("info", "net: " .. tostring(msg))
end
function net.send_chat(msg)
  record("net.send_chat", nil, msg)
end

-- ---------------------------------------------------------------------------
-- MOCK conveniences
-- ---------------------------------------------------------------------------

local CAT_NAMES =
  { ground = 2, vehicle = 2, airplane = 0, plane = 0, air = 0, helicopter = 1, heli = 1, ship = 3, train = 4 }

-- MOCK.addGroup{name=, coalition=1|2, country=country.id.X, category="ground"|"airplane"|"helicopter"|"ship",
--               units={{type=, x=, y=, alt=, name=, playerName=}} | count + type + x + y,
--               lateActivation=bool, silent=bool}
function M.addGroup(spec)
  local cat = spec.category
  if type(cat) == "string" then
    cat = CAT_NAMES[cat]
  end
  if cat == nil then
    cat = Group.Category.GROUND
  end
  local cid = spec.country
  if type(cid) == "string" then
    cid = country.id[cid]
  end
  if cid == nil then
    local side = spec.coalition or 1
    cid = (side == 2 and country.id.CJTF_BLUE) or (side == 0 and country.id.UN_PEACEKEEPERS) or country.id.CJTF_RED
  end
  local units = spec.units
  if not units then
    units = {}
    for i = 1, (spec.count or 1) do
      units[i] = { type = spec.type, x = (spec.x or 0) + (i - 1) * 20, y = spec.y or 0, alt = spec.alt }
    end
  end
  return coalition.addGroup(
    cid,
    cat,
    { name = spec.name, units = units, lateActivation = spec.lateActivation },
    { silent = spec.silent }
  )
end

-- MOCK.spawnPlayer{name=, group=, playerName=, type=, coalition=2, category="airplane", x=, y=, alt=}
function M.spawnPlayer(spec)
  spec = spec or {}
  local uname = spec.name or ("Player-" .. M.nextUnitId)
  local g = M.addGroup({
    name = spec.group or (uname .. " Group"),
    coalition = spec.coalition or 2,
    country = spec.country,
    category = spec.category or "airplane",
    silent = spec.silent,
    units = {
      {
        name = uname,
        type = spec.type or "F-16C_50",
        x = spec.x or 0,
        y = spec.y or 0,
        alt = spec.alt or 0,
        playerName = spec.playerName or "Player",
        skill = "Client",
      },
    },
  })
  return Unit.getByName(uname), g
end

-- MOCK.killUnit(name, {killer=unitName|obj, weapon="...", events={"DEAD","UNIT_LOST"}, crash=bool})
-- Default events: KILL (only if killer given, target still alive), then DEAD (or CRASH), then UNIT_LOST.
-- The unit is marked dead before DEAD fires: afterwards only getName/getID/getTypeName/isExist work.
function M.killUnit(name, opts)
  opts = opts or {}
  local u = M.units[name]
  if not u then
    error("MOCK.killUnit: no unit " .. tostring(name), 2)
  end
  if u.dead then
    return
  end
  local killer = opts.killer
  if type(killer) == "string" then
    killer = (M.units[killer] or {}).obj
  end
  local events = opts.events
  if not events then
    events = {}
    if killer then
      events[#events + 1] = "KILL"
    end
    events[#events + 1] = opts.crash and "CRASH" or "DEAD"
    events[#events + 1] = "UNIT_LOST"
  end
  local weapon = opts.weapon and M.makeWeapon(opts.weapon, killer) or nil
  for _, ev in ipairs(events) do
    if ev == "KILL" then
      M.fireEvent({ id = "KILL", initiator = killer, target = u.obj, weapon = weapon, weapon_name = opts.weapon })
    end
  end
  u.dead = true
  u.life = 0
  for _, ev in ipairs(events) do
    if ev ~= "KILL" then
      M.fireEvent({ id = ev, initiator = u.obj })
    end
  end
end

function M.killGroup(groupName, opts)
  local g = M.groups[groupName]
  if not g then
    error("MOCK.killGroup: no group " .. tostring(groupName), 2)
  end
  for _, un in ipairs(g.units) do
    M.killUnit(un, opts)
  end
end

-- MOCK.hitUnit(name, {initiator=unitName|obj, weapon="AGM_65D", damage=n})
function M.hitUnit(name, opts)
  opts = opts or {}
  local u = M.units[name]
  if not u or u.dead then
    error("MOCK.hitUnit: no live unit " .. tostring(name), 2)
  end
  local init = opts.initiator
  if type(init) == "string" then
    init = (M.units[init] or {}).obj
  end
  u.life = math.max(0, u.life - (opts.damage or 1))
  return M.fireEvent({
    id = "HIT",
    initiator = init,
    target = u.obj,
    weapon = opts.weapon and M.makeWeapon(opts.weapon, init) or nil,
  })
end

function M.moveUnit(name, x, y, alt)
  local u = M.units[name]
  u.x, u.z = x, y
  if alt then
    u.alt = alt
  end
end

-- MOCK.addPlayer(name, coalition, x, y): player unit "<name>-1" in group "<name>" (BIRTH fired)
function M.addPlayer(name, side, x, y, opts)
  opts = opts or {}
  return M.spawnPlayer({
    name = name .. "-1",
    group = name,
    coalition = side or 2,
    x = x,
    y = y,
    alt = opts.alt,
    type = opts.type,
    playerName = opts.playerName or name,
    category = opts.category,
  })
end

function M.setPlayerName(unitName, playerName)
  M.units[unitName].playerName = playerName
end

-- calls ------------------------------------------------------------------
function M.callsTo(fn, owner)
  local r = {}
  for _, c in ipairs(M.calls) do
    if c.fn == fn and (owner == nil or c.owner == owner) then
      r[#r + 1] = c
    end
  end
  return r
end
function M.countCalls(fn, owner)
  return #M.callsTo(fn, owner)
end
function M.lastCall(fn, owner)
  local r = M.callsTo(fn, owner)
  return r[#r]
end
function M.clearCalls()
  M.calls = {}
end

-- ---------------------------------------------------------------------------
-- sanitizing + strict globals
-- ---------------------------------------------------------------------------

local SANITIZED =
  { os = true, io = true, lfs = true, require = true, package = true, loadlib = true, dofile = true, loadfile = true }

-- Remove what MissionScripting.lua removes in DCS.
function M.sanitize()
  for k in pairs(SANITIZED) do
    rawset(_G, k, nil)
  end
end

local declared = {}
-- Declare a global name as legitimate (reads return nil when unset, writes allowed).
function M.declare(name)
  declared[name] = true
end

-- MOCK.strictGlobals(true): reading or writing an undeclared global raises an error.
-- Every global existing at enable time, plus DMS and DMS_CONFIG, is declared.
-- Module code that probes for optional globals should use rawget(_G, "name").
function M.strictGlobals(on)
  if not on then
    setmetatable(_G, nil)
    return
  end
  for k in pairs(_G) do
    declared[k] = true
  end
  declared.DMS = true
  declared.DMS_CONFIG = true
  setmetatable(_G, {
    __newindex = function(t, k, v)
      if not declared[k] then
        error("assignment to undeclared global '" .. tostring(k) .. "' (use local, or MOCK.declare)", 2)
      end
      rawset(t, k, v)
    end,
    __index = function(_, k)
      if declared[k] then
        return nil
      end
      if SANITIZED[k] then
        error("global '" .. tostring(k) .. "' is sanitized in DCS mission scripting", 2)
      end
      error("read of undeclared global '" .. tostring(k) .. "'", 2)
    end,
  })
end

M.reset()

--[[ README
Object model: Unit/Group/StaticObject objects are tables {id_=, name_=} with class metatables.
  Dead units: Unit.getByName -> nil; obj:isExist() false; getName/getID/getTypeName still work;
  every other method errors ("does not exist") -- so production code must cache group/coalition/pos.
  Unit:getCategory() returns Object.Category.UNIT (modern DCS); unit kind via getDesc().category
  or getCategoryEx(). Unit:isActive() is false for lateActivation groups until Group:activate().
  Group exists while it has >= 1 non-dead unit. Group:getUnits() returns only living units.
  coalition.addGroup fires BIRTH for each active unit (Group:activate fires it for late units)
  unless opts.silent (4th arg) / spec.silent. Name clash replaces the old group (like DCS).
Controller (strict): setOption errors on non-number id or nil value; Mission tasks need >= 2
  route points with numeric x/y. All calls recorded: MOCK.callsTo("Controller.setTask", groupName).
  Controller state: ctrl.options[id], ctrl.task, ctrl.commands. MOCK.detectedTargets[name] = {...}.
AI.Option / country.id / world.event / *.Category tables are strict: unknown keys raise.
Timers: MOCK.advance(sec). Errors inside a callback go to MOCK.rawErrors and kill that timer.
  The spec runner fails any test that leaves MOCK.rawErrors non-empty unless
  MOCK.expectRawErrors = true -- so every DMS callback must be guarded.
Events: MOCK.fireEvent{id="HIT", initiator=, target=, weapon=}. Handler errors -> rawErrors.
  MOCK.killUnit / MOCK.killGroup / MOCK.hitUnit / MOCK.spawnPlayer build realistic sequences.
  MOCK.makeWeapon(type), MOCK.makeScenery(type, pos), MOCK.makeAirbase(name, pos, side).
Zones: MOCK.addZone{name, x, y, radius} or {name, points={{x,y}...}} -> env.mission.triggers.zones
  and trigger.misc.getZone. Terrain: MOCK.terrainHeight (num|fn), MOCK.waterAreas / roadAreas
  ({x,y,radius} | {points}, shallow=true), MOCK.losFn(p1,p2).
Records: MOCK.calls entries {fn, owner, args={n=,...}, t}. trigger.action.* recorded as
  "trigger.action.<name>"; marks in MOCK.marks[id]; flags in MOCK.flags (getUserFlag works).
  Menus: MOCK.menuItems("group:<gid>"), MOCK.invokeMenu("group:<gid>", {"Root","Cmd"}).
Log: MOCK.log entries {level, msg, t}; MOCK.logContains(luaPattern, level?); MOCK.echo = true prints.
]]
