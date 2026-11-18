-- Spawn Core for DCS Missions
-- Shared "roll chance -> activate group" logic used by every DMS spawner.
--
-- Load order: DO SCRIPT FILE this BEFORE (or at least in the same mission
-- start batch as) any other spawners/*.lua file. Spawners look DMS.SpawnCore
-- up lazily at call time, so it only has to be loaded before they *run*.
--
-- Optional: utils/mission-settings.lua, utils/error-handler.lua, utils/fog-of-war.lua
--
-- Features:
--   * pcall-guarded timers (schedule) that return the DCS timer id for timer.removeFunction
--   * guarded error logging (works with or without DMS.Error)
--   * chance rolls
--   * correct late-activation detection (Unit:isActive, NOT Group:isExist)
--   * activation of late-activation groups, optionally hidden (fog of war) and/or
--     relocated, by respawning a copy of the Mission Editor group from env.mission
--   * ground position validation (no water / shallow water, optional building check)

DMS = DMS or {}
DMS.SpawnCore = DMS.SpawnCore or {}

local Core = DMS.SpawnCore

Core.Config = Core.Config or {
    avoidBuildings = true,       -- Reject points with scenery objects within buildingRadius
    buildingRadius = 15,         -- Meters
    maxPositionAttempts = 20,    -- Rerolls when looking for a valid ground point
}

-- ============================================================
-- LOGGING / ERRORS
-- ============================================================

local function isDebug()
    return DMS.Settings and DMS.Settings.isDebug and DMS.Settings.isDebug()
end

--- Debug log with module prefix (only when DMS debug is on)
-- @param prefix string e.g. "SpawnPool"
-- @param fmt string format string
function Core.log(prefix, fmt, ...)
    if isDebug() then
        local ok, msg = pcall(string.format, fmt, ...)
        env.info(string.format("[%s] %s", prefix or "SpawnCore", ok and msg or tostring(fmt)))
    end
end

--- Log an error, using DMS.Error when available (guarded), env.error otherwise
-- @param context string
-- @param err any
function Core.logError(context, err)
    local logged = false
    if DMS.Error and DMS.Error.log then
        logged = pcall(DMS.Error.log, context, tostring(err))
    end
    if not logged then
        env.error(string.format("[DMS LUA ERROR] %s: %s", tostring(context), tostring(err)))
    end
end

--- pcall a function with arguments and log on failure
-- @return boolean ok, any result
function Core.safeCall(func, context, ...)
    if type(func) ~= "function" then
        Core.logError(context, "safeCall received " .. type(func))
        return false, nil
    end
    local args = {...}
    local n = select("#", ...)
    local ok, result = pcall(function() return func(unpack(args, 1, n)) end)
    if not ok then
        Core.logError(context, result)
    end
    return ok, result
end

--- Schedule a one-shot, pcall-guarded function
-- @param func function Called with no arguments
-- @param delay number Seconds from now
-- @param context string Error context
-- @return number timer id (usable with timer.removeFunction)
function Core.schedule(func, delay, context)
    return timer.scheduleFunction(function()
        local ok, err = pcall(func)
        if not ok then
            Core.logError(context or "SpawnCore.schedule", err)
        end
        return nil
    end, nil, timer.getTime() + math.max(0, delay or 0))
end

--- Schedule a repeating, pcall-guarded function. func returns false to stop.
-- @return table handle {id = timerId, stop = function}
function Core.scheduleRepeat(func, interval, context, initialDelay)
    local handle = {running = true}
    handle.id = timer.scheduleFunction(function(_, time)
        if not handle.running then return nil end
        local ok, result = pcall(func)
        if not ok then
            Core.logError(context or "SpawnCore.scheduleRepeat", result)
        elseif result == false then
            handle.running = false
            return nil
        end
        return time + interval
    end, nil, timer.getTime() + (initialDelay or interval))
    handle.stop = function()
        handle.running = false
        if handle.id then
            pcall(timer.removeFunction, handle.id)
            handle.id = nil
        end
    end
    return handle
end

--- Cancel a timer id safely
function Core.cancel(timerId)
    if timerId then
        pcall(timer.removeFunction, timerId)
    end
end

-- ============================================================
-- ROLLS / RANDOM
-- ============================================================

--- Roll percentage chance
-- @param chance number 0-100
-- @return boolean success, number roll
function Core.roll(chance)
    local r = math.random(1, 100)
    return r <= (chance or 100), r
end

--- Random integer delay between min and max (handles min == max / nil)
function Core.randomDelay(minT, maxT)
    minT = minT or 0
    maxT = maxT or minT
    if maxT <= minT then return minT end
    return minT + math.random() * (maxT - minT)
end

--- Pick n distinct random entries from an array (Fisher-Yates)
function Core.pickRandom(list, n)
    local copy = {}
    for i, v in ipairs(list or {}) do copy[i] = v end
    for i = #copy, 2, -1 do
        local j = math.random(1, i)
        copy[i], copy[j] = copy[j], copy[i]
    end
    local out = {}
    for i = 1, math.min(n or 1, #copy) do out[i] = copy[i] end
    return out
end

-- ============================================================
-- GROUP STATE
-- ============================================================

--- Is the group active? Group:isExist() is TRUE for inactive late-activation
-- groups, so check Unit:isActive() on the first existing unit.
-- @param group Group|string
-- @return boolean
function Core.isGroupActive(group)
    if type(group) == "string" then group = Group.getByName(group) end
    if not group then return false end
    local ok, units = pcall(group.getUnits, group)
    if not ok or not units then return false end
    for _, unit in ipairs(units) do
        if unit and unit:isExist() then
            local okA, active = pcall(unit.isActive, unit)
            return okA and active == true
        end
    end
    return false
end

--- Does the group exist, is it active and does it have a living unit?
function Core.isGroupAlive(group)
    if type(group) == "string" then group = Group.getByName(group) end
    if not group or not Core.isGroupActive(group) then return false end
    for _, unit in ipairs(group:getUnits() or {}) do
        if unit and unit:isExist() and unit:getLife() >= 1 then
            return true
        end
    end
    return false
end

--- Resolve hidden flag: explicit > DMS.Settings default > false
function Core.resolveHidden(explicit)
    if explicit ~= nil then return explicit end
    if DMS.Settings and DMS.Settings.getSpawnHidden then
        return DMS.Settings.getSpawnHidden() and true or false
    end
    return false
end

-- ============================================================
-- MISSION EDITOR TEMPLATE LOOKUP (env.mission)
-- ============================================================

local CATEGORY_MAP = {
    vehicle = "GROUND",
    plane = "AIRPLANE",
    helicopter = "HELICOPTER",
    ship = "SHIP",
}

local function deepCopy(obj, seen)
    if type(obj) ~= "table" then return obj end
    seen = seen or {}
    if seen[obj] then return seen[obj] end
    local res = {}
    seen[obj] = res
    for k, v in pairs(obj) do
        res[deepCopy(k, seen)] = deepCopy(v, seen)
    end
    return res
end
Core.deepCopy = deepCopy

local function resolveName(name)
    if type(name) == "string" and name:sub(1, 8) == "DictKey_" and env.getValueDictByKey then
        local ok, v = pcall(env.getValueDictByKey, name)
        if ok and v then return v end
    end
    return name
end

local templateCache = nil

local function buildTemplateCache()
    templateCache = {}
    if not env.mission or not env.mission.coalition then return end
    for _, coaData in pairs(env.mission.coalition) do
        if type(coaData) == "table" and coaData.country then
            for _, ctry in pairs(coaData.country) do
                for catKey, catName in pairs(CATEGORY_MAP) do
                    local cat = ctry[catKey]
                    if cat and cat.group then
                        for _, grp in pairs(cat.group) do
                            local gname = resolveName(grp.name)
                            if gname then
                                templateCache[gname] = {
                                    data = grp,
                                    countryId = ctry.id,
                                    categoryName = catName,
                                }
                            end
                        end
                    end
                end
            end
        end
    end
end

--- Get a deep copy of a Mission Editor group definition
-- @param groupName string
-- @return table|nil {data = groupTable, countryId, category}
function Core.getGroupTemplate(groupName)
    if not templateCache then
        local ok, err = pcall(buildTemplateCache)
        if not ok then
            Core.logError("SpawnCore.buildTemplateCache", err)
            templateCache = {}
        end
    end
    local entry = templateCache[groupName]
    if not entry then return nil end
    local data = deepCopy(entry.data)
    data.name = groupName
    for _, u in ipairs(data.units or {}) do
        u.name = resolveName(u.name)
    end
    return {
        data = data,
        countryId = entry.countryId,
        category = Group.Category[entry.categoryName],
    }
end

--- Translate all unit / route positions of a group table by (dx, dy)
local function translateGroupTable(data, dx, dy)
    if dx == 0 and dy == 0 then return end
    data.x = (data.x or 0) + dx
    data.y = (data.y or 0) + dy
    for _, u in ipairs(data.units or {}) do
        u.x = (u.x or 0) + dx
        u.y = (u.y or 0) + dy
    end
    if data.route and data.route.points then
        for _, p in ipairs(data.route.points) do
            if p.x then p.x = p.x + dx end
            if p.y then p.y = p.y + dy end
        end
    end
end
Core.translateGroupTable = translateGroupTable

--- Apply hidden flags to a spawn table (delegates to FogOfWar when loaded)
function Core.applyHidden(data)
    if DMS.FogOfWar and DMS.FogOfWar.applyToSpawnTable then
        DMS.FogOfWar.applyToSpawnTable(data, true)
    else
        data.hidden = true
        data.hiddenOnMFD = true
        data.hiddenOnPlanner = true
    end
end

-- ============================================================
-- ACTIVATION
-- ============================================================

local function registerFow(groupName, group, hidden)
    if hidden and DMS.FogOfWar and DMS.FogOfWar.registerHiddenGroup then
        local side = group and group:getCoalition() or nil
        DMS.FogOfWar.registerHiddenGroup(groupName, side)
    end
end

--- Activate a late-activation group.
-- Hidden and/or relocated activation respawns a copy of the ME group (same name,
-- replaces the inactive original) because DCS cannot change map visibility or
-- position of an existing group at runtime.
-- @param groupName string
-- @param opts table|nil {hidden=bool|nil, x=, y= (lead-unit position), prefix=string}
-- @return boolean success, string|nil reason
function Core.activate(groupName, opts)
    opts = opts or {}
    local prefix = opts.prefix or "SpawnCore"
    local group = Group.getByName(groupName)
    if not group then
        Core.log(prefix, "Group '%s' not found", tostring(groupName))
        return false, "not found"
    end
    if Core.isGroupActive(group) and not opts.allowActive then
        Core.log(prefix, "Group '%s' already active - skipped", groupName)
        return false, "already active"
    end

    local hidden = Core.resolveHidden(opts.hidden)
    local relocate = opts.x ~= nil and opts.y ~= nil

    if hidden or relocate then
        local tmpl = Core.getGroupTemplate(groupName)
        if tmpl and tmpl.category then
            local data = tmpl.data
            data.lateActivation = nil
            if relocate then
                local lead = data.units and data.units[1]
                local refX = lead and lead.x or data.x or 0
                local refY = lead and lead.y or data.y or 0
                translateGroupTable(data, opts.x - refX, opts.y - refY)
            end
            if hidden then Core.applyHidden(data) end
            local newGroup = coalition.addGroup(tmpl.countryId, tmpl.category, data)
            if newGroup then
                registerFow(groupName, newGroup, hidden)
                Core.log(prefix, "Activated '%s' via respawn (hidden: %s, relocated: %s)",
                    groupName, tostring(hidden), tostring(relocate))
                return true
            end
            Core.log(prefix, "Respawn of '%s' failed - falling back to activateGroup", groupName)
        else
            Core.log(prefix, "No ME template for '%s' - activating in place (hidden needs ME 'Hidden on map')",
                groupName)
        end
    end

    trigger.action.activateGroup(group)
    registerFow(groupName, group, hidden)
    Core.log(prefix, "Activated '%s' (hidden: %s)", groupName, tostring(hidden))
    return true
end

--- Roll a chance and activate on success (the shared "random spawn" primitive)
-- @return boolean spawned, number roll
function Core.rollAndActivate(groupName, chance, opts)
    opts = opts or {}
    local prefix = opts.prefix or "SpawnCore"
    local success, r = Core.roll(chance)
    if not success then
        Core.log(prefix, "Skipped '%s' (rolled %d > %d)", tostring(groupName), r, chance or 100)
        return false, r
    end
    local ok, spawned = Core.safeCall(Core.activate, prefix .. ".activate(" .. tostring(groupName) .. ")",
        groupName, opts)
    spawned = ok and spawned or false
    if spawned then
        Core.log(prefix, "Activated '%s' (rolled %d <= %d)", groupName, r, chance or 100)
    end
    return spawned, r
end

--- Activate (optionally rolled) after a delay. Returns the timer id.
-- @param onDone function|nil called with (spawned, groupName)
function Core.activateDelayed(groupName, delay, chance, opts, onDone, isActive)
    local prefix = (opts and opts.prefix) or "SpawnCore"
    return Core.schedule(function()
        if isActive and not isActive() then
            Core.log(prefix, "Delayed spawn of '%s' cancelled (system stopped)", groupName)
            return
        end
        local spawned = Core.rollAndActivate(groupName, chance or 100, opts)
        if onDone then onDone(spawned, groupName) end
    end, delay, prefix .. ".activateDelayed(" .. tostring(groupName) .. ")")
end

-- ============================================================
-- TERRAIN VALIDATION
-- ============================================================

--- Is (x, y) map point valid dry land for ground units?
-- @param x number map x (north)
-- @param y number map y (east, = vec3.z)
-- @param opts table|nil {avoidBuildings=bool, buildingRadius=m}
function Core.isValidGroundPoint(x, y, opts)
    opts = opts or {}
    if land and land.getSurfaceType and land.SurfaceType then
        local ok, st = pcall(land.getSurfaceType, {x = x, y = y})
        if ok and (st == land.SurfaceType.WATER or st == land.SurfaceType.SHALLOW_WATER) then
            return false, "water"
        end
    end
    local avoid = opts.avoidBuildings
    if avoid == nil then avoid = Core.Config.avoidBuildings end
    if avoid and world and world.searchObjects and Object and Object.Category and Object.Category.SCENERY then
        local radius = opts.buildingRadius or Core.Config.buildingRadius
        local alt = 0
        if land and land.getHeight then
            local okH, h = pcall(land.getHeight, {x = x, y = y})
            if okH and h then alt = h end
        end
        local found = false
        pcall(world.searchObjects, Object.Category.SCENERY, {
            id = world.VolumeType.SPHERE,
            params = {point = {x = x, y = alt, z = y}, radius = radius},
        }, function()
            found = true
            return false
        end)
        if found then return false, "building" end
    end
    return true
end

--- Reroll a position generator until it yields valid ground
-- @param generator function returns x, y, ...extra
-- @param validator function|nil (x, y, ...) -> bool; default isValidGroundPoint
-- @return x, y, ... or nil
function Core.findValidPoint(generator, validator, attempts)
    validator = validator or function(px, py) return Core.isValidGroundPoint(px, py) end
    attempts = attempts or Core.Config.maxPositionAttempts
    for _ = 1, attempts do
        local res = {generator()}
        if res[1] and validator(unpack(res)) then
            return unpack(res)
        end
    end
    return nil
end

--- Random point inside a zone def {x, z|y, radius} or {minX,maxX,minZ,maxZ}
-- @return x, y (map coords) or nil
function Core.randomPointInZone(zone)
    if not zone then return nil end
    if zone.type == "rect" or zone.minX then
        return zone.minX + math.random() * (zone.maxX - zone.minX),
               zone.minZ + math.random() * (zone.maxZ - zone.minZ)
    end
    local cx = zone.x or (zone.point and zone.point.x)
    local cy = zone.z or zone.y or (zone.point and zone.point.z)
    local r = (zone.radius or 0) * math.sqrt(math.random())
    local a = math.random() * 2 * math.pi
    return cx + r * math.cos(a), cy + r * math.sin(a)
end

Core.log("SpawnCore", "Spawn core loaded")

_G.DMS = DMS
