-- DMS registry: unique names, tracked groups, unit budgets.
-- Budgets come from DMS_CONFIG.budgets: maxActiveGround / maxActiveAir / maxActiveShip
-- (per coalition when a coalition is given) and spawnsPerMin (see spawnRateAvailable).

DMS = DMS or {}
DMS.Registry = DMS.Registry or {}

local Reg = DMS.Registry
Reg._groups = Reg._groups or {}     -- groupName -> meta
Reg._counters = Reg._counters or {} -- prefix -> last n
Reg._allocated = Reg._allocated or {}
Reg._spawnTimes = Reg._spawnTimes or {}

local function call(obj, method, ...)
  if obj == nil then return nil end
  local f = obj[method]
  if type(f) ~= "function" then return nil end
  local ok, a = pcall(f, obj, ...)
  if ok then return a end
  return nil
end

local function nameTaken(name)
  if Reg._allocated[name] or Reg._groups[name] then return true end
  local okG, g = pcall(Group.getByName, name)
  if okG and g ~= nil then return true end
  local okU, u = pcall(Unit.getByName, name)
  if okU and u ~= nil then return true end
  local okS, s = pcall(StaticObject.getByName, name)
  if okS and s ~= nil then return true end
  return false
end

-- "DMS_<prefix>_<n>", unique among allocated names and existing groups/units/statics.
function Reg.allocName(prefix)
  prefix = tostring(prefix or "obj")
  local n = Reg._counters[prefix] or 0
  local name
  repeat
    n = n + 1
    name = "DMS_" .. prefix .. "_" .. n
  until not nameTaken(name)
  Reg._counters[prefix] = n
  Reg._allocated[name] = true
  return name
end

local function categoryOf(grp)
  local c = call(grp, "getCategory")
  if c == 0 or c == 1 then return "air" end
  if c == 3 then return "ship" end
  if c == nil then return nil end
  return "ground"
end

-- meta: {category="ground"|"air"|"ship", coalition=1|2, encounter=id, units=n}
-- Missing fields are filled from the live group when it exists.
function Reg.track(groupName, meta)
  if type(groupName) ~= "string" then return nil end
  local m = {}
  for k, v in pairs(meta or {}) do m[k] = v end
  local grp = Group.getByName(groupName)
  if grp then
    m.category = m.category or categoryOf(grp)
    m.coalition = m.coalition or call(grp, "getCoalition")
    m.units = m.units or call(grp, "getInitialSize") or call(grp, "getSize")
  end
  m.category = m.category or "ground"
  m.trackedAt = timer.getTime()
  m.dead = nil
  Reg._groups[groupName] = m
  Reg._spawnTimes[#Reg._spawnTimes + 1] = m.trackedAt
  if DMS.Bus and DMS.Bus.learnGroup then DMS.Bus.learnGroup(groupName) end
  DMS.Log.debug("Registry", "track %s (%s, coalition %s, %s units)", groupName, m.category, tostring(m.coalition), tostring(m.units))
  return m
end

function Reg.untrack(groupName)
  Reg._groups[groupName] = nil
end

function Reg.get(groupName) return Reg._groups[groupName] end

local function activeUnits(groupName)
  local grp = Group.getByName(groupName)
  if not grp or not call(grp, "isExist") then return 0 end
  local n = 0
  for _, u in ipairs(call(grp, "getUnits") or {}) do
    if call(u, "isExist") and call(u, "isActive") then n = n + 1 end
  end
  return n
end
Reg._activeUnits = activeUnits

-- exists AND has >= 1 active unit (late-activated groups are not alive until activated)
function Reg.isAlive(groupName)
  local ok, n = pcall(activeUnits, groupName)
  return ok and n > 0
end

-- active unit count of tracked groups; nil category/coalition = any
function Reg.count(category, coalition)
  local total = 0
  for name, m in pairs(Reg._groups) do
    if (category == nil or m.category == category) and (coalition == nil or m.coalition == coalition) then
      local ok, n = pcall(activeUnits, name)
      if ok then total = total + n end
    end
  end
  return total
end

local BUDGET_KEY = { ground = "maxActiveGround", air = "maxActiveAir", ship = "maxActiveShip" }

function Reg.budgetAvailable(category, coalition, nUnits)
  local cfg = DMS_CONFIG
  local budgets = type(cfg) == "table" and cfg.budgets or nil
  if type(budgets) ~= "table" then return true end
  local key = BUDGET_KEY[category]
  local max = key and tonumber(budgets[key])
  if not max then return true end
  local used = Reg.count(category, coalition)
  local ok = used + (tonumber(nUnits) or 1) <= max
  if not ok then
    DMS.Log.debug("Registry", "budget full: %s %d + %d > %d", tostring(category), used, tonumber(nUnits) or 1, max)
  end
  return ok
end

-- true when fewer than budgets.spawnsPerMin groups were tracked in the last 60 s
function Reg.spawnRateAvailable()
  local cfg = DMS_CONFIG
  local budgets = type(cfg) == "table" and cfg.budgets or nil
  local max = type(budgets) == "table" and tonumber(budgets.spawnsPerMin) or nil
  if not max then return true end
  local cutoff = timer.getTime() - 60
  local keep = {}
  for _, t in ipairs(Reg._spawnTimes) do if t > cutoff then keep[#keep + 1] = t end end
  Reg._spawnTimes = keep
  return #keep < max
end

-- sorted list of tracked group names where filterFn(name, meta) is truthy (or all)
function Reg.list(filterFn)
  local out = {}
  for name, m in pairs(Reg._groups) do
    if filterFn == nil then
      out[#out + 1] = name
    else
      local ok, keep = pcall(filterFn, name, m)
      if ok and keep then out[#out + 1] = name end
    end
  end
  table.sort(out)
  return out
end

if DMS.Bus and DMS.Bus.on and not Reg._busToken then
  Reg._busToken = DMS.Bus.on("group.dead", function(p)
    local m = p and Reg._groups[p.group]
    if m then m.dead = true end
  end)
end
