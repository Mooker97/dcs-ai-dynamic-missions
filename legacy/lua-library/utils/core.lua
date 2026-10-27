-- DMS Core Utilities
-- Shared helpers used across DMS modules (table, logging, group/unit liveness, vectors)
-- Safe to load multiple times; never overwrites helpers already defined.
-- Place in mission via DO SCRIPT FILE (load first, before other DMS scripts)

DMS = DMS or {}
DMS.Utils = DMS.Utils or {}

local U = DMS.Utils

local function define(name, fn)
    if U[name] == nil then
        U[name] = fn
    end
end

-- ============================================================
-- TABLE HELPERS
-- ============================================================

--- Count entries in any table (array or hash)
define("tableLength", function(t)
    if type(t) ~= "table" then return 0 end
    local n = 0
    for _ in pairs(t) do n = n + 1 end
    return n
end)

--- Shallow copy a table
define("shallowCopy", function(t)
    if type(t) ~= "table" then return t end
    local c = {}
    for k, v in pairs(t) do c[k] = v end
    return c
end)

--- Deep copy a table (cycle-safe)
define("deepCopy", function(t)
    local seen = {}
    local function copy(o)
        if type(o) ~= "table" then return o end
        if seen[o] then return seen[o] end
        local c = {}
        seen[o] = c
        for k, v in pairs(o) do c[copy(k)] = copy(v) end
        return c
    end
    return copy(t)
end)

--- Check if an array contains a value
define("contains", function(t, value)
    if type(t) ~= "table" then return false end
    for _, v in pairs(t) do
        if v == value then return true end
    end
    return false
end)

-- ============================================================
-- SAFE LOGGING
-- ============================================================

local function isDebug()
    if DMS.Settings and type(DMS.Settings.isDebug) == "function" then
        local ok, v = pcall(DMS.Settings.isDebug)
        return ok and v and true or false
    end
    return false
end

define("isDebug", isDebug)

local function fmt(prefix, msg, ...)
    local text
    if select("#", ...) > 0 then
        local ok, s = pcall(string.format, tostring(msg), ...)
        text = ok and s or tostring(msg)
    else
        text = tostring(msg)
    end
    if prefix and prefix ~= "" then
        return "[" .. tostring(prefix) .. "] " .. text
    end
    return text
end

--- Info log (always)
define("logInfo", function(prefix, msg, ...)
    if env and env.info then pcall(env.info, fmt(prefix, msg, ...)) end
end)

--- Warning log (always)
define("logWarn", function(prefix, msg, ...)
    if env and env.warning then pcall(env.warning, fmt(prefix, msg, ...)) end
end)

--- Error log (always)
define("logError", function(prefix, msg, ...)
    if env and env.error then pcall(env.error, fmt(prefix, msg, ...)) end
end)

--- Debug log (only when DMS.Settings.isDebug() is true)
define("logDebug", function(prefix, msg, ...)
    if isDebug() and env and env.info then pcall(env.info, fmt(prefix, msg, ...)) end
end)

-- ============================================================
-- OBJECT / GROUP / UNIT LIVENESS
-- ============================================================

--- Check a DCS object handle still exists
define("objectExists", function(obj)
    if obj == nil or type(obj) ~= "table" then return false end
    if type(obj.isExist) ~= "function" then return false end
    local ok, exists = pcall(obj.isExist, obj)
    return ok and exists and true or false
end)

--- Resolve a group from a name or Group object
define("getGroup", function(groupOrName)
    if type(groupOrName) == "string" then
        if not Group or not Group.getByName then return nil end
        local ok, g = pcall(Group.getByName, groupOrName)
        if ok then return g end
        return nil
    end
    return groupOrName
end)

--- Check a unit is alive (exists, life > 0)
-- @param unit Unit
-- @param requireActive boolean|nil If true, late-activated (inactive) units count as not alive
define("isUnitAlive", function(unit, requireActive)
    if not U.objectExists(unit) then return false end
    if type(unit.getLife) == "function" then
        local ok, life = pcall(unit.getLife, unit)
        if ok and type(life) == "number" and life < 1 then return false end
    end
    if requireActive and type(unit.isActive) == "function" then
        local ok, active = pcall(unit.isActive, unit)
        if ok and not active then return false end
    end
    return true
end)

--- Check a group has at least one alive unit
-- Late-activated groups exist in DCS before activation; pass requireActive=true
-- to treat a not-yet-activated group as not alive.
-- @param groupOrName string|Group
-- @param requireActive boolean|nil
define("isGroupAlive", function(groupOrName, requireActive)
    local group = U.getGroup(groupOrName)
    if not U.objectExists(group) then return false end
    local ok, units = pcall(group.getUnits, group)
    if not ok or type(units) ~= "table" then return false end
    for _, unit in ipairs(units) do
        if U.isUnitAlive(unit, requireActive) then return true end
    end
    return false
end)

--- Check whether a group has been activated (any unit active)
define("isGroupActive", function(groupOrName)
    local group = U.getGroup(groupOrName)
    if not U.objectExists(group) then return false end
    local ok, units = pcall(group.getUnits, group)
    if not ok or type(units) ~= "table" then return false end
    for _, unit in ipairs(units) do
        if U.objectExists(unit) and type(unit.isActive) == "function" then
            local okA, active = pcall(unit.isActive, unit)
            if okA and active then return true end
        end
    end
    return false
end)

--- Count alive units in a group
define("getAliveUnitCount", function(groupOrName, requireActive)
    local group = U.getGroup(groupOrName)
    if not U.objectExists(group) then return 0 end
    local ok, units = pcall(group.getUnits, group)
    if not ok or type(units) ~= "table" then return 0 end
    local n = 0
    for _, unit in ipairs(units) do
        if U.isUnitAlive(unit, requireActive) then n = n + 1 end
    end
    return n
end)

--- Check an event object (initiator/target) is a Unit
define("isUnitObject", function(obj)
    if not U.objectExists(obj) then return false end
    if not Object or not Object.Category or type(obj.getCategory) ~= "function" then return false end
    local ok, cat = pcall(obj.getCategory, obj)
    return ok and cat == Object.Category.UNIT
end)

--- Safely get a unit's group name (nil if not a unit / no group)
define("getUnitGroupName", function(unit)
    if not U.isUnitObject(unit) or type(unit.getGroup) ~= "function" then return nil end
    local ok, g = pcall(unit.getGroup, unit)
    if not ok or not g then return nil end
    local okN, name = pcall(g.getName, g)
    if okN then return name end
    return nil
end)

-- ============================================================
-- VECTOR HELPERS (DCS: x = north, z = east, y = altitude)
-- ============================================================

define("vec2", function(x, y) return { x = x or 0, y = y or 0 } end)
define("vec3", function(x, y, z) return { x = x or 0, y = y or 0, z = z or 0 } end)

--- Convert vec3 to vec2 (vec2.y = vec3.z)
define("toVec2", function(p)
    if not p then return nil end
    if p.z ~= nil then return { x = p.x, y = p.z } end
    return { x = p.x, y = p.y }
end)

--- Convert vec2 to vec3 (optionally with altitude; land height if available)
define("toVec3", function(p, alt)
    if not p then return nil end
    if p.z ~= nil then return { x = p.x, y = p.y or 0, z = p.z } end
    local y = alt
    if y == nil and land and land.getHeight then
        local ok, h = pcall(land.getHeight, { x = p.x, y = p.y })
        y = ok and h or 0
    end
    return { x = p.x, y = y or 0, z = p.y }
end)

--- 2D horizontal distance between two points (vec2 or vec3)
define("distance2D", function(a, b)
    if not a or not b then return math.huge end
    local az = a.z ~= nil and a.z or a.y
    local bz = b.z ~= nil and b.z or b.y
    local dx, dz = (a.x or 0) - (b.x or 0), (az or 0) - (bz or 0)
    return math.sqrt(dx * dx + dz * dz)
end)

--- 3D distance between two vec3 points
define("distance3D", function(a, b)
    if not a or not b then return math.huge end
    local dx = (a.x or 0) - (b.x or 0)
    local dy = (a.y or 0) - (b.y or 0)
    local dz = (a.z or 0) - (b.z or 0)
    return math.sqrt(dx * dx + dy * dy + dz * dz)
end)

--- Bearing in degrees (0-360, true north) from a to b
define("bearing", function(a, b)
    if not a or not b then return 0 end
    local az = a.z ~= nil and a.z or a.y
    local bz = b.z ~= nil and b.z or b.y
    local deg = math.deg(math.atan2((bz or 0) - (az or 0), (b.x or 0) - (a.x or 0)))
    if deg < 0 then deg = deg + 360 end
    return deg
end)

--- Safe position of a unit/object (vec3 or nil)
define("getPosition", function(obj)
    if not U.objectExists(obj) or type(obj.getPoint) ~= "function" then return nil end
    local ok, p = pcall(obj.getPoint, obj)
    if ok then return p end
    return nil
end)

-- ============================================================
-- SAFE SCHEDULING
-- ============================================================

--- Schedule a repeating pcall-guarded function. func(args, time) returns
-- false to stop, a number to set the next interval, anything else to keep interval.
-- @return number DCS timer id of the first schedule
define("scheduleRepeating", function(func, interval, prefix, firstDelay, args)
    interval = tonumber(interval) or 1
    if interval <= 0 then interval = 1 end
    local function tick(a, time)
        local ok, res = pcall(func, a, time)
        if not ok then
            U.logError(prefix or "DMS", "Scheduled function error: %s", tostring(res))
        elseif res == false then
            return nil
        elseif type(res) == "number" and res > 0 then
            return time + res
        end
        return time + interval
    end
    return timer.scheduleFunction(tick, args, timer.getTime() + (firstDelay or interval))
end)

_G.DMS = DMS
