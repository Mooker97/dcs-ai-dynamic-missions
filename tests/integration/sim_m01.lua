-- Flight simulation driver for test_config_roundtrip.py (runs inside the DCS mock).
-- Expects global SIM = {start={x,y}, route={{x,y}...}, minSec=, killCivilian=}.
local P = "Dusty-1"
local S = SIM
S.events, S.marks, S.did = {}, {}, {}
S.spawnPos = {}   -- unit name -> {x, y} at spawn time (before the sim drives convoys around)
DMS.Bus.on("*", function(p, name)
  S.events[#S.events + 1] = { name = name, t = timer.getTime(), p = p }
  if name == "spawner.spawned" then
    for _, u in ipairs(Group.getByName(p.group):getUnits()) do
      local pt = u:getPoint()
      S.spawnPos[u:getName()] = { x = pt.x, y = pt.z }
    end
  end
end)

local function events(name)
  local out = {}
  for _, e in ipairs(S.events) do if e.name == name then out[#out + 1] = e end end
  return out
end
S.eventsNamed = events

local function encounterGroups(id)
  local out = {}
  for _, e in ipairs(events("spawner.spawned")) do
    if e.p.encounter == id and Group.getByName(e.p.group) then out[#out + 1] = e.p.group end
  end
  return out
end

-- pre-placed groups: exact name, else first red group whose name starts with it (planner: aaa_x_1)
local function staticGroup(prefix)
  if Group.getByName(prefix) then return prefix end
  for _, g in ipairs(coalition.getGroups(1)) do
    local n = g:getName()
    if string.sub(n, 1, #prefix) == prefix then return n end
  end
  return nil
end

local function firstUnit(g)
  local grp = g and Group.getByName(g)
  local units = grp and grp:getUnits() or {}
  return units[1] and units[1]:getName() or nil
end

-- One player action at most every PACE seconds, so the radio is not flooded in a single frame.
local PACE = 20
S.lastAct = -1000
local function once(key, fn)
  if S.did[key] or timer.getTime() - S.lastAct < PACE then return end
  local ok = fn()
  if ok ~= false then
    S.did[key] = timer.getTime()
    S.lastAct = timer.getTime()
  end
end

local function flag(name) return DMS.Narrative.isFlagSet(name) end

local function isHot(g)
  for _, e in ipairs(events("encounter.sam_hot")) do if e.p.group == g then return true end end
  return false
end

local function shoot(unitName)
  MOCK.fireEvent({ id = "SHOT", initiator = Unit.getByName(unitName), weapon = MOCK.makeWeapon("ZU-23") })
end

-- what the player does while flying (called every sim step)
local function act()
  local t = timer.getTime()
  -- convoys drive north (the mock has no ground AI)
  for _, id in ipairs({ "staging_convoy", "civ_traffic" }) do
    for _, g in ipairs(encounterGroups(id)) do
      local grp = Group.getByName(g)
      for _, u in ipairs(grp and grp:getUnits() or {}) do
        local r = MOCK.units[u:getName()]
        if r and not r.dead then MOCK.moveUnit(r.name, r.x + 15, r.z - 3) end
      end
    end
  end
  if not flag("on_station") then return end
  once("aaa_shoots", function()
    local u = firstUnit(staticGroup("aaa_kirikhan")); if not u then return false end
    shoot(u)
  end)
  once("player_hit", function()
    local u = firstUnit(staticGroup("aaa_kirikhan")); if not u then return false end
    MOCK.hitUnit(P, { initiator = u, weapon = "ZU-23", damage = 0.1 })
  end)
  once("kill_reyhanli", function()
    local g = staticGroup("aaa_reyhanli")
    if not g then return false end
    MOCK.killGroup(g, { killer = P, weapon = "AGM_114K" })
  end)
  -- the pop-up gun opens fire once it goes hot; we find it and kill it
  local gun = encounterGroups("popup_aa")[1]
  if gun and isHot(gun) then
    once("gun_fires", function()
      local u = firstUnit(gun); if not u then return false end
      shoot(u)
    end)
    if S.did.gun_fires and t - S.did.gun_fires > 20 then
      once("gun_killed", function() MOCK.killGroup(gun, { killer = P, weapon = "AGM_114K" }) end)
    end
  end
  -- militia patrol contact: kill one group
  local pat = encounterGroups("patrol_contact")[1]
  if pat then
    once("patrol_killed", function() MOCK.killGroup(pat, { killer = P, weapon = "M230" }) end)
  end
  -- the staging convoy (or the civilian traffic) gets hit
  local cv = encounterGroups("staging_convoy")[1] or encounterGroups("civ_traffic")[1]
  if cv then
    once("convoy_hit", function()
      local u = firstUnit(cv); if not u then return false end
      MOCK.hitUnit(u, { initiator = P, weapon = "M230", damage = 0.5 })
      S.convoyHit = cv
    end)
  end
  local civ = S.killCivilian and encounterGroups("civ_traffic")[1]
  if civ then
    once("civ_killed", function()
      local u = firstUnit(civ); if not u then return false end
      MOCK.killUnit(u, { killer = P, weapon = "M230" })
    end)
  end
end

local function step(dt)
  MOCK.advance(dt)
  act()
end

local function flyTo(x, y)
  local speed = 70
  for _ = 1, 5000 do
    local r = MOCK.units[P]
    if not r or r.dead then return end
    local dx, dy = x - r.x, y - r.z
    local d = math.sqrt(dx * dx + dy * dy)
    if d < 1 then return end
    local s = math.min(d, speed * 2)
    MOCK.moveUnit(P, r.x + dx / d * s, r.z + dy / d * s, 150)
    step(2)
  end
end

MOCK.spawnPlayer({ name = P, group = "Dusty", playerName = "Mook", type = "AH-64D_BLK_II",
  category = "helicopter", coalition = 2, country = "AUSTRALIA", x = S.start[1], y = S.start[2], alt = 0 })
step(30)
MOCK.fireEvent({ id = "TAKEOFF", initiator = Unit.getByName(P) })
for _, wp in ipairs(S.route) do flyTo(wp[1], wp[2]) end
MOCK.moveUnit(P, S.start[1], S.start[2], 0)
step(5)
MOCK.fireEvent({ id = "LAND", initiator = Unit.getByName(P) })
S.landedAt = timer.getTime()
while timer.getTime() < S.minSec do step(10) end
MOCK.fireEvent({ id = "MISSION_END" })
step(5)
S.endedAt = timer.getTime()

function S.unitsInWater()
  local n, ST = 0, land.SurfaceType
  for _, p in pairs(S.spawnPos) do
    local st = land.getSurfaceType({ x = p.x, y = p.y })
    if st == ST.WATER or st == ST.SHALLOW_WATER then n = n + 1 end
  end
  return n
end
