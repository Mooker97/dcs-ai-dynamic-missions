-- ============================================
-- DUSTOFF CORRIDOR - MASTER INIT SCRIPT
-- Combined all dependencies with debug enabled
-- Load as single DO SCRIPT FILE (trigger: ONCE, TIME MORE 5)
-- ============================================

--[[
This master init script combines all required Lua modules into a single file.
Place in Mission Editor as: DO SCRIPT FILE → dustoff-master-init.lua
Set to: ONCE + TIME MORE (5) -- see MISSION-SETUP.md
]]

DMS = DMS or {}

-- ============================================
-- 1. MISSION SETTINGS (utils/mission-settings.lua)
-- ============================================

DMS.Settings = {}

DMS.Settings.Defaults = {
    playerCoalition = coalition.side.BLUE,
    enemyCoalition = coalition.side.RED,
    fogOfWar = true,  -- ENABLED: FOW now active for spawned enemies
    fogOfWarRevealRange = 5000,
    fogOfWarRevealOnRadar = true,
    fogOfWarRevealOnVisual = true,
    fogOfWarRevealOnDamage = true,
    spawnHiddenByDefault = false,
    spawnAnnouncementsEnabled = true,
    difficultyMultiplier = 1.0,
    adaptiveDifficulty = false,
    missionTimeLimit = 0,
    reinforcementDelay = 60,
    debug = true,  -- ENABLED
    debugVerbose = false,
    showErrorAlerts = true,
}

DMS.Settings.Current = {}

function DMS.Settings.init()
    DMS.Settings.Current = {}
    for key, value in pairs(DMS.Settings.Defaults) do
        DMS.Settings.Current[key] = value
    end
end

DMS.Settings.init()

function DMS.Settings.configure(overrides)
    if not overrides then return end
    for key, value in pairs(overrides) do
        if DMS.Settings.Defaults[key] ~= nil then
            DMS.Settings.Current[key] = value
        else
            if DMS.Settings.Current.debug then
                env.info(string.format("[DMS.Settings] Warning: Unknown setting '%s'", key))
            end
            DMS.Settings.Current[key] = value
        end
    end
    if overrides.fogOfWar == true and overrides.spawnHiddenByDefault == nil then
        DMS.Settings.Current.spawnHiddenByDefault = true
    end
    if DMS.Settings.Current.debug then
        env.info("[DMS.Settings] Configuration updated")
    end
end

function DMS.Settings.get(key)
    if DMS.Settings.Current[key] ~= nil then
        return DMS.Settings.Current[key]
    end
    return DMS.Settings.Defaults[key]
end

function DMS.Settings.set(key, value)
    DMS.Settings.Current[key] = value
end

function DMS.Settings.isFogOfWarEnabled()
    return DMS.Settings.get("fogOfWar") == true
end

function DMS.Settings.shouldSpawnHidden()
    return DMS.Settings.get("fogOfWar") and DMS.Settings.get("spawnHiddenByDefault")
end

function DMS.Settings.getSpawnHidden(explicitHidden)
    if explicitHidden ~= nil then
        return explicitHidden
    end
    return DMS.Settings.shouldSpawnHidden()
end

function DMS.Settings.reset()
    DMS.Settings.init()
end

function DMS.Settings.getAll()
    local copy = {}
    for key, value in pairs(DMS.Settings.Current) do
        copy[key] = value
    end
    return copy
end

function DMS.Settings.dump()
    env.info("=== DMS Settings ===")
    for key, value in pairs(DMS.Settings.Current) do
        local default = DMS.Settings.Defaults[key]
        local marker = (value ~= default) and " *" or ""
        env.info(string.format("  %s: %s%s", key, tostring(value), marker))
    end
    env.info("(* = overridden from default)")
end

function DMS.Settings.getPlayerCoalition()
    return DMS.Settings.get("playerCoalition")
end

function DMS.Settings.getEnemyCoalition()
    return DMS.Settings.get("enemyCoalition")
end

function DMS.Settings.isDebug()
    return DMS.Settings.get("debug") == true
end

env.info("[DMS] Mission Settings module loaded")

-- ============================================
-- 2. ERROR HANDLER (for other modules)
-- ============================================

DMS.Error = {}
DMS.Error.Errors = {}

function DMS.Error.log(context, errorMsg)
    local entry = {
        timestamp = timer.getTime(),
        context = context,
        message = tostring(errorMsg),
    }
    table.insert(DMS.Error.Errors, entry)
    env.error(string.format("[DMS ERROR] %s: %s", context, tostring(errorMsg)))
end

function DMS.Error.safeCall(func, context)
    local success, result = pcall(func)
    if not success then
        DMS.Error.log(context or "unknown", result)
        return nil
    end
    return result
end

function DMS.Error.safeSchedule(func, delay, context)
    local wrappedFunc = function()
        DMS.Error.safeCall(func, context)
        return nil
    end
    return timer.scheduleFunction(wrappedFunc, nil, timer.getTime() + (delay or 0))
end

function DMS.Error.safeHandler(handlerTable, context)
    local wrappedHandler = {
        onEvent = function(self, event)
            DMS.Error.safeCall(function()
                handlerTable:onEvent(event)
            end, context)
        end
    }
    return wrappedHandler
end

env.info("[DMS] Error Handler module loaded")

-- Wrap a timer.scheduleFunction callback in pcall. On error the error is logged
-- (env.error) and, if retryInterval is given, the loop is rescheduled anyway.
function DMS.Error.wrapTimer(func, context, retryInterval)
    return function(arg, time)
        local ok, result = pcall(func, arg, time)
        if not ok then
            DMS.Error.log(context or "timer", result)
            if retryInterval then
                return (time or timer.getTime()) + retryInterval
            end
            return nil
        end
        return result
    end
end

-- ============================================
-- 2b. SHARED UTILITIES
-- ============================================

DMS.Util = {}

-- Returns the Group of a world object, or nil for statics/scenery/weapons/dead objects.
function DMS.Util.getUnitGroup(obj)
    if not obj then return nil end
    local ok, group = pcall(function()
        if Object.getCategory(obj) ~= Object.Category.UNIT then return nil end
        if not obj:isExist() then return nil end
        return obj:getGroup()
    end)
    if ok then return group end
    return nil
end

-- Alive units of a group (safe on nil / dead groups).
function DMS.Util.getAliveUnits(group)
    local alive = {}
    if not group or not group:isExist() then return alive end
    for _, unit in ipairs(group:getUnits() or {}) do
        if unit and unit:isExist() and unit:getLife() >= 1 then
            table.insert(alive, unit)
        end
    end
    return alive
end

function DMS.Util.getCentroid(units)
    local sx, sz = 0, 0
    for _, unit in ipairs(units) do
        local p = unit:getPoint()
        sx, sz = sx + p.x, sz + p.z
    end
    local cx, cz = sx / #units, sz / #units
    return {x = cx, y = land.getHeight({x = cx, y = cz}), z = cz}
end

function DMS.Util.dist2D(a, b)
    local dx, dz = a.x - b.x, a.z - b.z
    return math.sqrt(dx * dx + dz * dz)
end

function DMS.Util.countKeys(t)
    local n = 0
    for _ in pairs(t or {}) do n = n + 1 end
    return n
end

-- Zone shape: quad zones (type 2) use their vertices, otherwise circle.
-- Returns {name, point, radius, verts} or nil.
function DMS.Util.getZoneShape(zoneName)
    local zone = trigger.misc.getZone(zoneName)
    if not zone then return nil end
    local shape = {name = zoneName, point = zone.point, radius = zone.radius}
    local zones = env.mission and env.mission.triggers and env.mission.triggers.zones
    if zones then
        for _, z in pairs(zones) do
            if z.name == zoneName and z.type == 2 and z.verticies and #z.verticies >= 3 then
                shape.verts = z.verticies  -- {x = mapX, y = mapZ}
                break
            end
        end
    end
    return shape
end

local function pointInPolygon(px, pz, verts)
    local inside = false
    local j = #verts
    for i = 1, #verts do
        local xi, zi = verts[i].x, verts[i].y
        local xj, zj = verts[j].x, verts[j].y
        if ((zi > pz) ~= (zj > pz)) and (px < (xj - xi) * (pz - zi) / (zj - zi) + xi) then
            inside = not inside
        end
        j = i
    end
    return inside
end

function DMS.Util.isPointInZone(point, shape)
    if not shape or not point then return false end
    if shape.verts then
        return pointInPolygon(point.x, point.z, shape.verts)
    end
    return DMS.Util.dist2D(point, shape.point) <= shape.radius
end

env.info("[DMS] Utilities module loaded")

-- ============================================
-- 3. FOG OF WAR (F10 marks for detected enemies)
-- ============================================
--[[
DCS cannot hide/reveal a group on the F10 map at runtime. Design:
  * Enemy groups are spawned with `hidden = true` (never drawn on F10).
  * When BLUE detects a group (proximity + line of sight, or combat events),
    a BLUE-only F10 mark + circle is drawn at the group's position.
  * Marks are refreshed periodically (removeMark + redraw) and removed when
    the group dies.
Recommended mission option: F10 View = "Fog of War" or "Only allies".
]]

DMS.FogOfWar = {}
DMS.FogOfWar.HiddenGroups = {}
DMS.FogOfWar.Running = false
DMS.FogOfWar.CheckScheduleID = nil
DMS.FogOfWar.NextMarkId = 870000  -- unique ID range for FOW marks/drawings

DMS.FogOfWar.Config = {
    checkInterval = 3,        -- proximity check interval (s)
    markRefresh = 15,         -- mark redraw interval for revealed groups (s)
    markRadius = 300,         -- circle radius drawn around detected group (m)
    revealRange = 5000,
    revealOnRadar = true,
    revealOnVisual = true,    -- require line of sight for proximity reveal
    revealOnDamage = true,
    announceReveals = false,
}

local function fowDebug(fmt, ...)
    if DMS.Settings and DMS.Settings.isDebug() then
        env.info(string.format("[FOW] " .. fmt, ...))
    end
end

function DMS.FogOfWar.configure(settings)
    for key, value in pairs(settings or {}) do
        DMS.FogOfWar.Config[key] = value
    end
    if DMS.Settings then
        DMS.FogOfWar.Config.revealRange = DMS.Settings.get("fogOfWarRevealRange") or DMS.FogOfWar.Config.revealRange
        DMS.FogOfWar.Config.revealOnRadar = DMS.Settings.get("fogOfWarRevealOnRadar")
        DMS.FogOfWar.Config.revealOnVisual = DMS.Settings.get("fogOfWarRevealOnVisual")
        DMS.FogOfWar.Config.revealOnDamage = DMS.Settings.get("fogOfWarRevealOnDamage")
    end
end

local function allocMarkId()
    DMS.FogOfWar.NextMarkId = DMS.FogOfWar.NextMarkId + 1
    return DMS.FogOfWar.NextMarkId
end

local function removeGroupMarks(hidden)
    if hidden.markId then
        trigger.action.removeMark(hidden.markId)
        hidden.markId = nil
    end
    if hidden.circleId then
        trigger.action.removeMark(hidden.circleId)
        hidden.circleId = nil
    end
end

function DMS.FogOfWar.registerHiddenGroup(groupName, ownerCoalition)
    DMS.FogOfWar.HiddenGroups[groupName] = {
        name = groupName,
        owner = ownerCoalition,
        revealed = false,
        dead = false,
        markId = nil,
        circleId = nil,
        lastDraw = 0,
        reason = nil,
    }
    fowDebug("Registered hidden group: %s", groupName)
end

-- Draw (or redraw) the BLUE-only mark for a revealed group. Removes marks if the group is dead.
function DMS.FogOfWar.refreshMark(groupName)
    local hidden = DMS.FogOfWar.HiddenGroups[groupName]
    if not hidden or not hidden.revealed or hidden.dead then return end

    local group = Group.getByName(groupName)
    local units = DMS.Util.getAliveUnits(group)
    removeGroupMarks(hidden)
    if #units == 0 then
        hidden.dead = true
        fowDebug("Group %s destroyed - marks removed", groupName)
        return
    end

    local center = DMS.Util.getCentroid(units)
    local playerCoalition = DMS.Settings.getPlayerCoalition()
    local typeName = units[1]:getTypeName() or "unknown"
    local text = string.format("ENEMY: %s x%d (%s)", typeName, #units, hidden.reason or "detected")

    hidden.markId = allocMarkId()
    trigger.action.markToCoalition(hidden.markId, text, center, playerCoalition, true)

    hidden.circleId = allocMarkId()
    trigger.action.circleToAll(playerCoalition, hidden.circleId, center, DMS.FogOfWar.Config.markRadius,
        {1, 0, 0, 1}, {1, 0, 0, 0.15}, 1, true)

    hidden.lastDraw = timer.getTime()
end

function DMS.FogOfWar.revealGroup(groupName, toCoalition, reason)
    local hidden = DMS.FogOfWar.HiddenGroups[groupName]
    if not hidden or hidden.revealed or hidden.dead then return false end
    if toCoalition ~= DMS.Settings.getPlayerCoalition() then return false end

    hidden.revealed = true
    hidden.reason = reason
    DMS.FogOfWar.refreshMark(groupName)

    if DMS.FogOfWar.Config.announceReveals then
        local msg = string.format("Contact! Enemy forces detected%s", reason and (" - " .. reason) or "")
        trigger.action.outTextForCoalition(toCoalition, msg, 5)
    end

    fowDebug("Revealed %s to coalition %d (%s)", groupName, toCoalition, reason or "unknown")
    return true
end

function DMS.FogOfWar.revealUnit(unitName, toCoalition)
    local unit = Unit.getByName(unitName)
    local group = DMS.Util.getUnitGroup(unit)
    if group then
        return DMS.FogOfWar.revealGroup(group:getName(), toCoalition, "unit detected")
    end
    return false
end

function DMS.FogOfWar.isRevealed(groupName, toCoalition)
    local hidden = DMS.FogOfWar.HiddenGroups[groupName]
    if not hidden then return true end
    return hidden.revealed == true
end

local function checkProximityDetection()
    local playerCoalition = DMS.Settings.getPlayerCoalition()
    local revealRange = DMS.FogOfWar.Config.revealRange
    local needLOS = DMS.FogOfWar.Config.revealOnVisual
    local now = timer.getTime()

    -- Active BLUE units (skips late-activated groups that are not yet active)
    local playerPoints = {}
    for _, group in pairs(coalition.getGroups(playerCoalition) or {}) do
        for _, unit in ipairs(DMS.Util.getAliveUnits(group)) do
            if unit:isActive() then
                local p = unit:getPoint()
                table.insert(playerPoints, {x = p.x, y = p.y + 2, z = p.z})
            end
        end
    end

    for groupName, hidden in pairs(DMS.FogOfWar.HiddenGroups) do
        if not hidden.dead then
            local group = Group.getByName(groupName)
            local units = DMS.Util.getAliveUnits(group)
            if #units == 0 then
                if hidden.revealed then
                    DMS.FogOfWar.refreshMark(groupName)  -- removes marks + flags dead
                else
                    hidden.dead = true
                end
            elseif hidden.revealed then
                if now - hidden.lastDraw >= DMS.FogOfWar.Config.markRefresh then
                    DMS.FogOfWar.refreshMark(groupName)
                end
            else
                local found = false
                for _, enemyUnit in ipairs(units) do
                    local ep = enemyUnit:getPoint()
                    local epRaised = {x = ep.x, y = ep.y + 2, z = ep.z}
                    for _, pp in ipairs(playerPoints) do
                        local dx, dz = ep.x - pp.x, ep.z - pp.z
                        if (dx * dx + dz * dz) <= revealRange * revealRange then
                            if (not needLOS) or land.isVisible(epRaised, pp) then
                                found = true
                                break
                            end
                        end
                    end
                    if found then break end
                end
                if found then
                    DMS.FogOfWar.revealGroup(groupName, playerCoalition, "visual")
                end
            end
        end
    end
end

local function scheduleProximityCheck()
    DMS.FogOfWar.CheckScheduleID = timer.scheduleFunction(DMS.Error.wrapTimer(function(_, time)
        if not DMS.FogOfWar.Running then return nil end
        checkProximityDetection()
        return time + DMS.FogOfWar.Config.checkInterval
    end, "FogOfWar.checkProximityDetection", DMS.FogOfWar.Config.checkInterval),
    nil, timer.getTime() + DMS.FogOfWar.Config.checkInterval)
end

DMS.FogOfWar._EventHandlerInternal = {
    onEvent = function(self, event)
        if not DMS.FogOfWar.Running then return end
        local playerCoalition = DMS.Settings.getPlayerCoalition()

        -- Unit death in a revealed group: redraw now (removes marks if group is gone)
        if event.id == world.event.S_EVENT_DEAD or event.id == world.event.S_EVENT_UNIT_LOST then
            local group = DMS.Util.getUnitGroup(event.initiator)
            if group then
                local name = group:getName()
                if DMS.FogOfWar.HiddenGroups[name] then
                    timer.scheduleFunction(DMS.Error.wrapTimer(function()
                        DMS.FogOfWar.refreshMark(name)
                        return nil
                    end, "FogOfWar.deathRefresh"), nil, timer.getTime() + 1)
                end
            end
            return
        end

        if not DMS.FogOfWar.Config.revealOnDamage then return end

        if event.id == world.event.S_EVENT_HIT then
            -- Enemy hit by anyone, or enemy hitting a BLUE unit
            local targetGroup = DMS.Util.getUnitGroup(event.target)
            if targetGroup and targetGroup:getCoalition() ~= playerCoalition then
                DMS.FogOfWar.revealGroup(targetGroup:getName(), playerCoalition, "hit")
            end
            local shooterGroup = DMS.Util.getUnitGroup(event.initiator)
            if shooterGroup and shooterGroup:getCoalition() ~= playerCoalition then
                DMS.FogOfWar.revealGroup(shooterGroup:getName(), playerCoalition, "engaged")
            end
        elseif event.id == world.event.S_EVENT_SHOT or event.id == world.event.S_EVENT_SHOOTING_START then
            local shooterGroup = DMS.Util.getUnitGroup(event.initiator)
            if shooterGroup and shooterGroup:getCoalition() ~= playerCoalition then
                DMS.FogOfWar.revealGroup(shooterGroup:getName(), playerCoalition, "firing")
            end
        end
    end
}

function DMS.FogOfWar.spawnGroup(countryId, category, groupData, hidden)
    local shouldHide = DMS.Settings.getSpawnHidden(hidden) and true or false
    groupData.hidden = shouldHide
    local group = coalition.addGroup(countryId, category, groupData)
    if shouldHide and group then
        DMS.FogOfWar.registerHiddenGroup(groupData.name, group:getCoalition())
    end
    return group
end

-- Activates a late-activation group. It can only be F10-hidden if "Hidden on map"
-- is ticked in the ME; registering it here makes it get a mark when detected.
function DMS.FogOfWar.activateGroup(groupName, hidden)
    local group = Group.getByName(groupName)
    if not group then return false end
    trigger.action.activateGroup(group)
    if DMS.Settings.getSpawnHidden(hidden) then
        DMS.FogOfWar.registerHiddenGroup(groupName, group:getCoalition())
    end
    return true
end

function DMS.FogOfWar.start()
    if DMS.FogOfWar.Running then return end
    DMS.FogOfWar.Running = true
    DMS.FogOfWar.configure({})
    DMS.FogOfWar.EventHandler = DMS.Error.safeHandler(
        DMS.FogOfWar._EventHandlerInternal,
        "FogOfWar.EventHandler"
    )
    world.addEventHandler(DMS.FogOfWar.EventHandler)
    scheduleProximityCheck()
    fowDebug("Fog of War system started (%d groups, range %dm, LOS %s)",
        DMS.Util.countKeys(DMS.FogOfWar.HiddenGroups), DMS.FogOfWar.Config.revealRange,
        tostring(DMS.FogOfWar.Config.revealOnVisual))
end

function DMS.FogOfWar.stop()
    DMS.FogOfWar.Running = false
    if DMS.FogOfWar.CheckScheduleID then
        timer.removeFunction(DMS.FogOfWar.CheckScheduleID)
        DMS.FogOfWar.CheckScheduleID = nil
    end
end

function DMS.FogOfWar.revealAll()
    local playerCoalition = DMS.Settings.getPlayerCoalition()
    for groupName, _ in pairs(DMS.FogOfWar.HiddenGroups) do
        DMS.FogOfWar.revealGroup(groupName, playerCoalition, "mission end")
    end
end

function DMS.FogOfWar.getStats()
    local total, revealed = 0, 0
    for _, hidden in pairs(DMS.FogOfWar.HiddenGroups) do
        total = total + 1
        if hidden.revealed then revealed = revealed + 1 end
    end
    return {totalHidden = total, revealed = revealed, stillHidden = total - revealed}
end

env.info("[DMS] Fog of War module loaded")

-- ============================================
-- 4. UNIT TEMPLATES (spawners/unit-templates.lua)
-- ============================================

DMS.UnitTemplates = {}
DMS.UnitTemplates.Units = {
    ["2S6 Tunguska"] = {type = "2S6 Tunguska", category = "AA", threat = "HIGH", country = "RUSSIA"},
    ["ZSU-23-4 Shilka"] = {type = "ZSU-23-4 Shilka", category = "AA", threat = "MEDIUM", country = "RUSSIA"},
    ["Strela-10M3"] = {type = "Strela-10M3", category = "AA", threat = "MEDIUM", country = "RUSSIA"},
    ["Ural-375 ZU-23"] = {type = "Ural-375 ZU-23", category = "AA", threat = "MEDIUM", country = "RUSSIA"},
    ["tt_ZU-23"] = {type = "tt_ZU-23", category = "AA", threat = "MEDIUM", country = "RUSSIA"},
    ["SA-18 Igla-S manpad"] = {type = "SA-18 Igla-S manpad", category = "AA", threat = "HIGH", country = "RUSSIA"},
    ["T-72B3"] = {type = "T-72B3", category = "ARMOR", threat = "HIGH", country = "RUSSIA"},
    ["BMP-2"] = {type = "BMP-2", category = "ARMOR", threat = "MEDIUM", country = "RUSSIA"},
    ["BMP-3"] = {type = "BMP-3", category = "ARMOR", threat = "HIGH", country = "RUSSIA"},
    ["BTR-80"] = {type = "BTR-80", category = "ARMOR", threat = "LOW", country = "RUSSIA"},
    ["BRDM-2"] = {type = "BRDM-2", category = "ARMOR", threat = "LOW", country = "RUSSIA"},
    ["tt_KORD"] = {type = "tt_KORD", category = "TECHNICAL", threat = "LOW", country = "RUSSIA"},
    ["HL_KORD"] = {type = "HL_KORD", category = "EMPLACEMENT", threat = "LOW", country = "RUSSIA"},
    ["Soldier AK"] = {type = "Soldier AK", category = "INFANTRY", threat = "LOW", country = "RUSSIA"},
    ["Soldier RPG"] = {type = "Soldier RPG", category = "INFANTRY", threat = "MEDIUM", country = "RUSSIA"},
}

DMS.UnitTemplates.Groups = {
    ["tunguska"] = {name = "tunguska", displayName = "2S6 Tunguska", category = "AA", country = country.id.RUSSIA, task = "Ground Nothing", units = {{type = "2S6 Tunguska", skill = "Random"}}},
    ["shilka"] = {name = "shilka", displayName = "ZSU-23-4 Shilka", category = "AA", country = country.id.RUSSIA, task = "Ground Nothing", units = {{type = "ZSU-23-4 Shilka", skill = "Random"}}},
    ["strela_section"] = {name = "strela_section", displayName = "Strela-10 Section", category = "AA", country = country.id.RUSSIA, task = "Ground Nothing", units = {{type = "Strela-10M3", skill = "Random"}, {type = "Strela-10M3", skill = "Random"}}},
    ["zu23_truck"] = {name = "zu23_truck", displayName = "ZU-23 on Ural", category = "AA", country = country.id.RUSSIA, task = "Ground Nothing", units = {{type = "Ural-375 ZU-23", skill = "Random"}}},
    ["zu23_technical"] = {name = "zu23_technical", displayName = "ZU-23 Technical", category = "AA", country = country.id.RUSSIA, task = "Ground Nothing", units = {{type = "tt_ZU-23", skill = "Random"}}},
    ["zu23_battery"] = {name = "zu23_battery", displayName = "ZU-23 Battery", category = "AA", country = country.id.RUSSIA, task = "Ground Nothing", units = {{type = "Ural-375 ZU-23", skill = "Random"}, {type = "Ural-375 ZU-23", skill = "Random"}}},
    ["manpads_team"] = {name = "manpads_team", displayName = "MANPADS Team", category = "AA", country = country.id.RUSSIA, task = "Ground Nothing", units = {{type = "SA-18 Igla-S manpad", skill = "Random"}, {type = "SA-18 Igla-S manpad", skill = "Random"}}},
    ["manpads_single"] = {name = "manpads_single", displayName = "MANPADS Gunner", category = "AA", country = country.id.RUSSIA, task = "Ground Nothing", units = {{type = "SA-18 Igla-S manpad", skill = "Random"}}},
    ["t72_platoon"] = {name = "t72_platoon", displayName = "T-72 Platoon", category = "ARMOR", country = country.id.RUSSIA, task = "Ground Nothing", units = {{type = "T-72B3", skill = "Random"}, {type = "T-72B3", skill = "Random"}}},
    ["t72_single"] = {name = "t72_single", displayName = "T-72 Tank", category = "ARMOR", country = country.id.RUSSIA, task = "Ground Nothing", units = {{type = "T-72B3", skill = "Random"}}},
    ["bmp_section"] = {name = "bmp_section", displayName = "BMP Section", category = "ARMOR", country = country.id.RUSSIA, task = "Ground Nothing", units = {{type = "BMP-2", skill = "Random"}, {type = "BMP-2", skill = "Random"}}},
    ["btr_squad"] = {name = "btr_squad", displayName = "BTR Squad", category = "ARMOR", country = country.id.RUSSIA, task = "Ground Nothing", units = {{type = "BTR-80", skill = "Random"}, {type = "BTR-80", skill = "Random"}, {type = "BTR-80", skill = "Random"}}},
    ["recon_patrol"] = {name = "recon_patrol", displayName = "Recon Patrol", category = "ARMOR", country = country.id.RUSSIA, task = "Ground Nothing", units = {{type = "BRDM-2", skill = "Random"}}},
    ["technical_mg"] = {name = "technical_mg", displayName = "Technical (MG)", category = "TECHNICAL", country = country.id.RUSSIA, task = "Ground Nothing", units = {{type = "tt_KORD", skill = "Random"}}},
    ["technical_pair"] = {name = "technical_pair", displayName = "Technical Pair", category = "TECHNICAL", country = country.id.RUSSIA, task = "Ground Nothing", units = {{type = "tt_KORD", skill = "Random"}, {type = "tt_KORD", skill = "Random"}}},
    ["infantry_squad"] = {name = "infantry_squad", displayName = "Infantry Squad", category = "INFANTRY", country = country.id.RUSSIA, task = "Ground Nothing", units = {{type = "Soldier AK", skill = "Random"}, {type = "Soldier AK", skill = "Random"}, {type = "Soldier AK", skill = "Random"}, {type = "Soldier RPG", skill = "Random"}}},
    ["rpg_team"] = {name = "rpg_team", displayName = "RPG Team", category = "INFANTRY", country = country.id.RUSSIA, task = "Ground Nothing", units = {{type = "Soldier RPG", skill = "Random"}, {type = "Soldier RPG", skill = "Random"}}},
    ["mg_nest"] = {name = "mg_nest", displayName = "MG Nest", category = "INFANTRY", country = country.id.RUSSIA, task = "Ground Nothing", static = true, units = {{type = "HL_KORD", skill = "Random"}, {type = "Soldier AK", skill = "Random"}}},
    ["checkpoint"] = {name = "checkpoint", displayName = "Checkpoint", category = "MIXED", country = country.id.RUSSIA, task = "Ground Nothing", units = {{type = "BTR-80", skill = "Random"}, {type = "Soldier AK", skill = "Random"}, {type = "Soldier AK", skill = "Random"}, {type = "Soldier RPG", skill = "Random"}}},
    ["ambush_team"] = {name = "ambush_team", displayName = "Ambush Team", category = "MIXED", country = country.id.RUSSIA, task = "Ground Nothing", units = {{type = "Soldier RPG", skill = "Random"}, {type = "Soldier RPG", skill = "Random"}, {type = "SA-18 Igla-S manpad", skill = "Random"}}},
    ["aa_ambush"] = {name = "aa_ambush", displayName = "AA Ambush", category = "AA", country = country.id.RUSSIA, task = "Ground Nothing", units = {{type = "Ural-375 ZU-23", skill = "Random"}, {type = "SA-18 Igla-S manpad", skill = "Random"}, {type = "SA-18 Igla-S manpad", skill = "Random"}}},
    ["convoy_escort"] = {name = "convoy_escort", displayName = "Convoy Escort", category = "MIXED", country = country.id.RUSSIA, task = "Ground Nothing", units = {{type = "BTR-80", skill = "Random"}, {type = "KAMAZ Truck", skill = "Random"}, {type = "KAMAZ Truck", skill = "Random"}, {type = "BTR-80", skill = "Random"}}},
    ["qrf_light"] = {name = "qrf_light", displayName = "Light QRF", category = "QRF", country = country.id.RUSSIA, task = "Ground Nothing", units = {{type = "tt_KORD", skill = "Random"}, {type = "tt_KORD", skill = "Random"}}},
    ["qrf_medium"] = {name = "qrf_medium", displayName = "Medium QRF", category = "QRF", country = country.id.RUSSIA, task = "Ground Nothing", units = {{type = "BMP-2", skill = "Random"}, {type = "BTR-80", skill = "Random"}}},
    ["qrf_heavy"] = {name = "qrf_heavy", displayName = "Heavy QRF", category = "QRF", country = country.id.RUSSIA, task = "Ground Nothing", units = {{type = "T-72B3", skill = "Random"}, {type = "BMP-2", skill = "Random"}}},
}

function DMS.UnitTemplates.getTemplate(templateName)
    return DMS.UnitTemplates.Groups[templateName]
end

function DMS.UnitTemplates.listTemplates(category)
    local result = {}
    for name, template in pairs(DMS.UnitTemplates.Groups) do
        if not category or template.category == category then
            table.insert(result, name)
        end
    end
    table.sort(result)
    return result
end

env.info("[DMS] Unit Templates module loaded")

-- ============================================
-- 5. DYNAMIC SPAWN (spawners/dynamic-spawn.lua)
-- ============================================

DMS.DynamicSpawn = {}
DMS.DynamicSpawn.Pools = {}
DMS.DynamicSpawn.SpawnedGroups = {}
DMS.DynamicSpawn.GroupCounter = 0
DMS.DynamicSpawn.UnitCounter = 0

DMS.DynamicSpawn.Config = {
    defaultMinDistance = 100,
    defaultMaxDistance = 500,
    defaultSpacing = 20,
    defaultHeading = "center",
    defaultHidden = true,
    defaultCountry = country.id.RUSSIA,
    defaultTask = "Ground Nothing",
}

local function calculateSpawnPosition(zoneX, zoneY, minDist, maxDist)
    local angle = math.random() * 2 * math.pi
    local distance = minDist + math.random() * (maxDist - minDist)
    local x = zoneX + distance * math.cos(angle)
    local y = zoneY + distance * math.sin(angle)
    return x, y, angle
end

local function calculateHeading(mode, unitX, unitY, zoneX, zoneY)
    if mode == "center" then
        return math.atan2(zoneY - unitY, zoneX - unitX)
    elseif mode == "random" then
        return math.random() * 2 * math.pi
    elseif type(mode) == "number" then
        return mode
    else
        return 0
    end
end

local function generateGroupName(poolId)
    DMS.DynamicSpawn.GroupCounter = DMS.DynamicSpawn.GroupCounter + 1
    return string.format("%s-%d", poolId, DMS.DynamicSpawn.GroupCounter)
end

local function generateUnitId()
    DMS.DynamicSpawn.UnitCounter = DMS.DynamicSpawn.UnitCounter + 1
    return 10000 + DMS.DynamicSpawn.UnitCounter
end

function DMS.DynamicSpawn.createPool(poolId, options)
    if not options.zone then
        env.error(string.format("[DynamicSpawn] Pool '%s' missing 'zone'", poolId))
        return false
    end
    if not options.templates or #options.templates == 0 then
        env.error(string.format("[DynamicSpawn] Pool '%s' missing 'templates'", poolId))
        return false
    end

    local zone = trigger.misc.getZone(options.zone)
    if not zone then
        env.warning(string.format("[DynamicSpawn] Zone '%s' not found for pool '%s'", options.zone, poolId))
    end

    DMS.DynamicSpawn.Pools[poolId] = {
        id = poolId,
        zone = options.zone,
        templates = options.templates,
        chance = options.chance or 100,
        count = options.count or 1,
        minDistance = options.minDistance or DMS.DynamicSpawn.Config.defaultMinDistance,
        maxDistance = options.maxDistance or DMS.DynamicSpawn.Config.defaultMaxDistance,
        heading = options.heading or DMS.DynamicSpawn.Config.defaultHeading,
        formation = options.formation or "line",
        spacing = options.spacing or DMS.DynamicSpawn.Config.defaultSpacing,
        hidden = options.hidden,
        country = options.country,
        hunt = options.hunt or false,
        huntRadius = options.huntRadius or 3000,
        huntSpeed = options.huntSpeed or 8,
        executed = false,
        spawned = {},
    }

    if DMS.Settings and DMS.Settings.isDebug() then
        env.info(string.format("[DynamicSpawn] Created pool '%s' (%d templates) in zone '%s'",
            poolId, #options.templates, options.zone))
    end

    return true
end

function DMS.DynamicSpawn.executePool(poolId)
    local pool = DMS.DynamicSpawn.Pools[poolId]
    if not pool then
        env.error(string.format("[DynamicSpawn] Pool '%s' not found", poolId))
        return {success = false, spawned = 0, groups = {}}
    end

    local roll = math.random(1, 100)
    if roll > pool.chance then
        if DMS.Settings and DMS.Settings.isDebug() then
            env.info(string.format("[DynamicSpawn] Pool '%s' skipped (rolled %d > %d)", poolId, roll, pool.chance))
        end
        pool.executed = true
        return {success = true, spawned = 0, groups = {}, skipped = true}
    end

    local zone = trigger.misc.getZone(pool.zone)
    if not zone then
        env.error(string.format("[DynamicSpawn] Zone '%s' not found", pool.zone))
        return {success = false, spawned = 0, groups = {}}
    end

    -- Pick `count` templates: shuffle-bag that refills, so count is honoured
    -- even when it exceeds the number of templates.
    local selectedTemplates = {}
    local bag = {}
    for _ = 1, pool.count do
        if #bag == 0 then
            for _, t in ipairs(pool.templates) do table.insert(bag, t) end
        end
        local idx = math.random(1, #bag)
        table.insert(selectedTemplates, bag[idx])
        table.remove(bag, idx)
    end

    local hideOnMap = DMS.Settings.getSpawnHidden(pool.hidden) and true or false

    local spawnedGroups = {}
    for _, templateName in ipairs(selectedTemplates) do
        local template = DMS.UnitTemplates and DMS.UnitTemplates.getTemplate(templateName)
        if template then
            local spawnX, spawnY = calculateSpawnPosition(
                zone.point.x, zone.point.z,
                pool.minDistance, pool.maxDistance
            )
            local heading = calculateHeading(pool.heading, spawnX, spawnY, zone.point.x, zone.point.z)
            local groupName = generateGroupName(poolId)
            local countryId = pool.country or template.country or DMS.DynamicSpawn.Config.defaultCountry

            local units = {}
            for i, unitDef in ipairs(template.units) do
                table.insert(units, {
                    type = unitDef.type,
                    name = string.format("%s-%d", groupName, i),
                    unitId = generateUnitId(),
                    x = spawnX + (i - 1) * pool.spacing * math.cos(heading),
                    y = spawnY + (i - 1) * pool.spacing * math.sin(heading),
                    heading = heading,
                    skill = unitDef.skill or "Average",
                    playerCanDrive = false,
                })
            end

            local groupData = {
                name = groupName,
                task = template.task or DMS.DynamicSpawn.Config.defaultTask,
                visible = false,
                hidden = hideOnMap,  -- hidden on F10 for everyone; FOW draws marks on detection
                units = units,
                x = spawnX,
                y = spawnY,
                -- Single holding waypoint; hunting groups get a Mission task later.
                route = {points = {{alt = 0, type = "Turning Point", action = "Off Road",
                    x = spawnX, y = spawnY, speed = 0, ETA = 0, ETA_locked = true, speed_locked = true,
                    task = {id = "ComboTask", params = {tasks = {}}}}}},
            }

            local group = coalition.addGroup(countryId, Group.Category.GROUND, groupData)
            if group then
                table.insert(spawnedGroups, groupName)
                pool.spawned[groupName] = {template = templateName, x = spawnX, y = spawnY, heading = heading}
                DMS.DynamicSpawn.SpawnedGroups[groupName] = {poolId = poolId, template = templateName}

                if hideOnMap and DMS.FogOfWar then
                    DMS.FogOfWar.registerHiddenGroup(groupName, group:getCoalition())
                end

                if DMS.Settings and DMS.Settings.isDebug() then
                    env.info(string.format("[DynamicSpawn] Spawned '%s' from '%s' at (%.0f, %.0f) hidden=%s",
                        groupName, templateName, spawnX, spawnY, tostring(hideOnMap)))
                end
            else
                env.error(string.format("[DynamicSpawn] coalition.addGroup failed for '%s'", groupName))
            end
        end
    end

    pool.executed = true
    if DMS.Settings and DMS.Settings.isDebug() then
        env.info(string.format("[DynamicSpawn] Pool '%s' executed: %d groups spawned (rolled %d <= %d)",
            poolId, #spawnedGroups, roll, pool.chance))
    end

    return {success = true, spawned = #spawnedGroups, groups = spawnedGroups}
end

function DMS.DynamicSpawn.getPoolGroups(poolId)
    local pool = DMS.DynamicSpawn.Pools[poolId]
    if not pool then return {} end
    local groups = {}
    for name, _ in pairs(pool.spawned) do
        table.insert(groups, name)
    end
    return groups
end

local function setEngageOptions(controller)
    controller:setOption(AI.Option.Ground.id.ROE, AI.Option.Ground.val.ROE.OPEN_FIRE)
    controller:setOption(AI.Option.Ground.id.ALARM_STATE, AI.Option.Ground.val.ALARM_STATE.RED)
end

function DMS.DynamicSpawn.setAmbush(groupName)
    local group = Group.getByName(groupName)
    if not group or not group:isExist() then return false end
    local controller = group:getController()
    if not controller then return false end
    setEngageOptions(controller)
    controller:setOption(AI.Option.Ground.id.DISPERSE_ON_ATTACK, 0)  -- seconds; 0 = never disperse
    if DMS.Settings and DMS.Settings.isDebug() then
        env.info(string.format("[DynamicSpawn] Set ambush: %s", groupName))
    end
    return true
end

function DMS.DynamicSpawn.setAmbushPools(poolIds)
    for _, poolId in ipairs(poolIds) do
        for _, groupName in ipairs(DMS.DynamicSpawn.getPoolGroups(poolId)) do
            DMS.DynamicSpawn.setAmbush(groupName)
        end
    end
end

-- ============================================
-- GROUND HUNTING (routes ground groups to intercept the convoy)
-- ============================================

DMS.DynamicSpawn.Hunt = {
    convoyName = nil,
    running = false,
    checkInterval = 5,    -- how often hunters are evaluated (s)
    retaskInterval = 30,  -- how often an active hunter's route is re-issued (s)
    standoff = 300,       -- stop this far short of the intercept point (m)
    maxLeadTime = 90,     -- max seconds to lead the convoy
    groups = {},          -- groupName -> {poolId, radius, speed, lastTask, active}
}

local function huntDebug(fmt, ...)
    if DMS.Settings and DMS.Settings.isDebug() then
        env.info(string.format("[Hunt] " .. fmt, ...))
    end
end

local function getConvoyLead(convoyName)
    local units = DMS.Util.getAliveUnits(Group.getByName(convoyName))
    return units[1]
end

-- Issue an off-road Mission route from the hunter's position to a point ahead of the convoy lead.
function DMS.DynamicSpawn.routeToIntercept(groupName, convoyName, speed)
    local hunters = DMS.Util.getAliveUnits(Group.getByName(groupName))
    local lead = getConvoyLead(convoyName)
    if #hunters == 0 or not lead then return false end

    local group = Group.getByName(groupName)
    local controller = group:getController()
    if not controller then return false end

    local hp = hunters[1]:getPoint()
    local cp = lead:getPoint()
    local vel = lead:getVelocity() or {x = 0, y = 0, z = 0}
    local dist = DMS.Util.dist2D(hp, cp)
    local leadTime = math.min(dist / math.max(speed, 1), DMS.DynamicSpawn.Hunt.maxLeadTime)
    local ix, iz = cp.x + vel.x * leadTime, cp.z + vel.z * leadTime

    -- Stop short of the intercept point so the group engages from standoff range
    local dx, dz = ix - hp.x, iz - hp.z
    local d = math.sqrt(dx * dx + dz * dz)
    local standoff = DMS.DynamicSpawn.Hunt.standoff
    if d > standoff then
        ix, iz = hp.x + dx * (1 - standoff / d), hp.z + dz * (1 - standoff / d)
    else
        ix, iz = hp.x, hp.z  -- already in position: hold and fight
    end

    local mission = {
        id = "Mission",
        params = {route = {points = {
            {x = hp.x, y = hp.z, type = "Turning Point", action = "Off Road", speed = speed,
             ETA = 0, ETA_locked = false, speed_locked = true, task = {id = "ComboTask", params = {tasks = {}}}},
            {x = ix, y = iz, type = "Turning Point", action = "Off Road", speed = speed,
             ETA = 0, ETA_locked = false, speed_locked = true, task = {id = "ComboTask", params = {tasks = {}}}},
        }}},
    }
    controller:setTask(mission)
    setEngageOptions(controller)
    huntDebug("'%s' routed to intercept (%.0f, %.0f), %.0fm from convoy", groupName, ix, iz, dist)
    return true
end

local function processHunters(_, time)
    local hunt = DMS.DynamicSpawn.Hunt
    if not hunt.running then return nil end
    if DMS.DustoffCorridor and DMS.DustoffCorridor.State and DMS.DustoffCorridor.State.missionEnded then
        hunt.running = false
        return nil
    end

    local lead = getConvoyLead(hunt.convoyName)
    if not lead then
        huntDebug("Convoy '%s' gone - hunting stopped", tostring(hunt.convoyName))
        hunt.running = false
        return nil
    end
    local cp = lead:getPoint()

    for groupName, h in pairs(hunt.groups) do
        local units = DMS.Util.getAliveUnits(Group.getByName(groupName))
        if #units == 0 then
            hunt.groups[groupName] = nil
            huntDebug("'%s' destroyed - removed from hunt list", groupName)
        else
            local dist = DMS.Util.dist2D(units[1]:getPoint(), cp)
            if dist <= h.radius then
                if not h.active then
                    h.active = true
                    huntDebug("'%s' convoy in hunt radius (%.0fm <= %dm) - hunting", groupName, dist, h.radius)
                end
                if time - h.lastTask >= hunt.retaskInterval then
                    if DMS.DynamicSpawn.routeToIntercept(groupName, hunt.convoyName, h.speed) then
                        h.lastTask = time
                    end
                end
            end
        end
    end

    return time + hunt.checkInterval
end

-- Register a group as a hunter. radius/speed default to the pool's settings.
function DMS.DynamicSpawn.addHunter(groupName, radius, speed)
    local info = DMS.DynamicSpawn.SpawnedGroups[groupName]
    local pool = info and DMS.DynamicSpawn.Pools[info.poolId]
    local template = info and DMS.UnitTemplates.getTemplate(info.template)
    if template and template.static then
        huntDebug("'%s' is a static emplacement - not hunting", groupName)
        return false
    end
    DMS.DynamicSpawn.Hunt.groups[groupName] = {
        poolId = info and info.poolId,
        radius = radius or (pool and pool.huntRadius) or 3000,
        speed = speed or (pool and pool.huntSpeed) or 8,
        lastTask = -math.huge,
        active = false,
    }
    return true
end

function DMS.DynamicSpawn.startHunting(convoyName)
    local hunt = DMS.DynamicSpawn.Hunt
    hunt.convoyName = convoyName
    if hunt.running then return end
    hunt.running = true
    timer.scheduleFunction(DMS.Error.wrapTimer(processHunters, "DynamicSpawn.processHunters", hunt.checkInterval),
        nil, timer.getTime() + hunt.checkInterval)
    huntDebug("Hunting started vs '%s' (%d hunters)", convoyName, DMS.Util.countKeys(hunt.groups))
end

-- Register every group of pools flagged `hunt = true` (or all given pools when force=true).
function DMS.DynamicSpawn.huntConvoy(poolIds, convoyName, force)
    local count = 0
    for _, poolId in ipairs(poolIds) do
        local pool = DMS.DynamicSpawn.Pools[poolId]
        if pool and (pool.hunt or force) then
            for _, groupName in ipairs(DMS.DynamicSpawn.getPoolGroups(poolId)) do
                if DMS.DynamicSpawn.addHunter(groupName) then count = count + 1 end
            end
        end
    end
    DMS.DynamicSpawn.startHunting(convoyName)
    huntDebug("Registered %d hunter groups", count)
    return count
end

env.info("[DMS] Dynamic Spawn module loaded")

-- ============================================
-- 6. SAM AMBUSH (ai-behavior/sam-ambush.lua)
-- ============================================

DMS.SAMAmbush = {}
DMS.SAMAmbush.Sites = {}
DMS.SAMAmbush.TimerId = nil
DMS.SAMAmbush.Active = false

DMS.SAMAmbush.Config = {
    checkInterval = 2,
    defaultEngageRadius = 30000,
    defaultMinAltitude = 0,       -- AGL (m); helicopters fly low
    defaultMaxAltitude = 25000,   -- AGL (m)
    hotHoldTime = 30,             -- stay hot at least this long after going hot (s)
    rerollDelay = 30,             -- after a failed fireChance roll, wait before re-rolling (s)
    trackingCoalition = coalition.side.BLUE,
}

local function samDebug(fmt, ...)
    if DMS.Settings and DMS.Settings.isDebug() then
        env.info(string.format("[SAMAmbush] " .. fmt, ...))
    end
end

function DMS.SAMAmbush.register(groupName, options)
    options = options or {}
    local units = DMS.Util.getAliveUnits(Group.getByName(groupName))
    if #units == 0 then
        samDebug("Cannot register '%s' - group not alive", groupName)
        return false
    end
    local pos = units[1]:getPoint()

    DMS.SAMAmbush.Sites[groupName] = {
        name = groupName,
        x = pos.x,
        z = pos.z,
        engageRadius = options.activationRange or DMS.SAMAmbush.Config.defaultEngageRadius,
        minAlt = options.minAltitude or DMS.SAMAmbush.Config.defaultMinAltitude,
        maxAlt = options.maxAltitude or DMS.SAMAmbush.Config.defaultMaxAltitude,
        radarOn = false,
        activateTime = 0,
        nextRollTime = 0,
        fireChance = options.fireChance or 100,
    }

    DMS.SAMAmbush.setRadar(groupName, false)
    samDebug("Registered '%s' (range %dm, fireChance %d%%)", groupName,
        DMS.SAMAmbush.Sites[groupName].engageRadius, DMS.SAMAmbush.Sites[groupName].fireChance)
    return true
end

-- state=true: go HOT (alarm RED, ROE OPEN_FIRE). state=false: go DARK (alarm GREEN, WEAPON_HOLD).
function DMS.SAMAmbush.setRadar(groupName, state)
    local group = Group.getByName(groupName)
    if group and group:isExist() then
        local controller = group:getController()
        if controller then
            if state then
                controller:setOption(AI.Option.Ground.id.ALARM_STATE, AI.Option.Ground.val.ALARM_STATE.RED)
                controller:setOption(AI.Option.Ground.id.ROE, AI.Option.Ground.val.ROE.OPEN_FIRE)
            else
                controller:setOption(AI.Option.Ground.id.ALARM_STATE, AI.Option.Ground.val.ALARM_STATE.GREEN)
                controller:setOption(AI.Option.Ground.id.ROE, AI.Option.Ground.val.ROE.WEAPON_HOLD)
            end
        end
    end

    local site = DMS.SAMAmbush.Sites[groupName]
    if site then
        site.radarOn = state
        if state then site.activateTime = timer.getTime() end
    end
end

local function getPlayerAircraft()
    local aircraft = {}
    for _, unit in ipairs(coalition.getPlayers(DMS.SAMAmbush.Config.trackingCoalition) or {}) do
        if unit and unit:isExist() then
            local pos = unit:getPoint()
            local agl = pos.y - land.getHeight({x = pos.x, y = pos.z})
            table.insert(aircraft, {pos = pos, alt = agl, unit = unit})
        end
    end
    return aircraft
end

local function isInEnvelope(site, aircraft)
    if aircraft.alt < site.minAlt or aircraft.alt > site.maxAlt then
        return false
    end
    local dx = aircraft.pos.x - site.x
    local dz = aircraft.pos.z - site.z
    return (dx * dx + dz * dz) <= site.engageRadius * site.engageRadius
end

local function processAmbushCheck(_, time)
    if not DMS.SAMAmbush.Active then return nil end

    local playerAircraft = getPlayerAircraft()
    for groupName, site in pairs(DMS.SAMAmbush.Sites) do
        local group = Group.getByName(groupName)
        if group and group:isExist() then
            local targetInEnvelope = false
            for _, aircraft in ipairs(playerAircraft) do
                if isInEnvelope(site, aircraft) then
                    targetInEnvelope = true
                    break
                end
            end

            if targetInEnvelope and not site.radarOn and time >= site.nextRollTime then
                local roll = math.random(1, 100)
                if roll <= site.fireChance then
                    DMS.SAMAmbush.setRadar(groupName, true)
                    samDebug("'%s' going HOT (rolled %d <= %d)", groupName, roll, site.fireChance)
                else
                    site.nextRollTime = time + DMS.SAMAmbush.Config.rerollDelay
                    samDebug("'%s' stays DARK (rolled %d > %d)", groupName, roll, site.fireChance)
                end
            elseif not targetInEnvelope and site.radarOn then
                if time - site.activateTime > DMS.SAMAmbush.Config.hotHoldTime then
                    DMS.SAMAmbush.setRadar(groupName, false)
                    samDebug("'%s' going DARK (no targets)", groupName)
                end
            end
        else
            DMS.SAMAmbush.Sites[groupName] = nil
            samDebug("'%s' destroyed - unregistered", groupName)
        end
    end

    return time + DMS.SAMAmbush.Config.checkInterval
end

function DMS.SAMAmbush.start()
    if DMS.SAMAmbush.Active then return end
    DMS.SAMAmbush.Active = true
    DMS.SAMAmbush.TimerId = timer.scheduleFunction(
        DMS.Error.wrapTimer(processAmbushCheck, "SAMAmbush.processAmbushCheck", DMS.SAMAmbush.Config.checkInterval),
        nil, timer.getTime() + DMS.SAMAmbush.Config.checkInterval)
    samDebug("System started (%d sites)", DMS.Util.countKeys(DMS.SAMAmbush.Sites))
end

env.info("[DMS] SAM Ambush module loaded")

-- ============================================
-- 7. REINFORCEMENT WAVES (events/reinforcement-waves.lua)
-- ============================================

DMS.Reinforcements = {}
DMS.Reinforcements.Waves = {}
DMS.Reinforcements.CurrentWave = 0
DMS.Reinforcements.Active = false
DMS.Reinforcements.TimerId = nil

DMS.Reinforcements.Config = {
    playerCoalition = coalition.side.BLUE,
    enemyCoalition = coalition.side.RED,
    announceWaves = true,
    delayBetweenWaves = 60,
    maxConcurrentEnemies = 20,
    spawnDelay = 2,
}

function DMS.Reinforcements.registerWave(waveNumber, groups, options)
    options = options or {}
    DMS.Reinforcements.Waves[waveNumber] = {
        groups = groups,
        triggered = false,
        spawned = false,
        delay = options.delay or 0,
        announcement = options.announcement or string.format("Warning: Enemy reinforcements inbound! (Wave %d)", waveNumber),
        condition = options.condition or nil,
    }
end

env.info("[DMS] Reinforcements module loaded")

-- ============================================
-- 8. DUSTOFF CORRIDOR MISSION CONFIG
-- ============================================

DMS.DustoffCorridor = {}

-- ============================================
-- FLAG DEFINITIONS FOR VOICE LINE TRIGGERS
-- ============================================

DMS.DustoffCorridor.Flags = {
    -- Mission State
    MISSION_START = 100,
    MISSION_VICTORY = 101,
    MISSION_DEFEAT = 102,

    -- Zone Transitions
    CONVOY_ALPHA_ENTER = 110,
    CONVOY_ALPHA_EXIT = 111,
    CONVOY_BRAVO_ENTER = 112,
    CONVOY_BRAVO_EXIT = 113,
    CONVOY_CHARLIE_ENTER = 114,
    CONVOY_CHARLIE_EXIT = 115,
    CONVOY_ARRIVED = 116,

    -- Combat Events
    CONVOY_FIRST_HIT = 117,
    CONVOY_CASUALTY = 118,

    -- A-10 Events
    A10_CHECKIN = 119,
}

-- ============================================
-- ZONE TRACKING STATE
-- ============================================

DMS.DustoffCorridor.ZoneState = {
    currentZone = nil,  -- "alpha", "bravo", "charlie", "victory", or nil
    zonesEntered = {},  -- Prevents duplicate enter flags
    convoyGroupName = "Convoy-Main",

    zones = {
        alpha = nil,
        bravo = nil,
        charlie = nil,
        victory = nil,
    },
}

-- ============================================
-- COMBAT EVENT TRACKING
-- ============================================

DMS.DustoffCorridor.CombatState = {
    convoyHasBeenHit = false,  -- Flag 117 fires once
    a10HasCheckedIn = false,   -- Flag 119 fires once
}

-- ============================================
-- HELPER: SET FLAG WITH DEBUG LOGGING AND TEXT
-- ============================================

-- Voice line text mapping (temporary until audio is ready)
local voiceLineText = {
    -- Mission State
    [100] = "Dustoff, this is Convoy Actual. We're rolling out now. Stick close, we're expecting contact.",
    [101] = "Dustoff, Convoy Actual. We've reached the FOB. All vehicles accounted for. Outstanding work up there.",
    [102] = "Dustoff... we're... we're not gonna make it. Too many casualties. Mission... failed...",

    -- Zone Position Reports
    [110] = "Convoy entering Alpha sector.",
    [111] = "Convoy clear of Alpha, continuing route.",
    [112] = "Convoy entering Bravo sector.",
    [113] = "Convoy clear of Bravo, continuing route.",
    [114] = "Convoy entering Charlie sector.",
    [115] = "Convoy clear of Charlie, final approach beginning.",
    [116] = "Convoy has reached destination. All vehicles accounted for, standing by for orders.",

    -- Combat Events
    [117] = "Contact! Contact! We are taking fire!",
    [118] = "Vehicle destroyed! We're taking casualties! Dustoff, we need immediate air support!",

    -- A-10 Events
    [119] = "Convoy Actual, Hawg One-One checking in. I've got eyes on multiple hostile contacts. Commencing attack run.",
}

local function setVoiceLineFlag(flagNumber, description)
    trigger.action.setUserFlag(flagNumber, true)

    -- Display text message to player
    local text = voiceLineText[flagNumber]
    if text then
        trigger.action.outTextForCoalition(coalition.side.BLUE, text, 10)
    end

    -- Debug logging
    if DMS.Settings and DMS.Settings.isDebug() then
        env.info(string.format("[DUSTOFF-VOICE] Flag %d set: %s", flagNumber, description))
    end
end

-- ============================================
-- ZONE MONITORING SYSTEM
-- ============================================

-- Quad zones are tested with point-in-polygon (vertices from env.mission), circles by radius.
local function isGroupInZone(groupName, shape)
    if not shape then return false end
    local units = DMS.Util.getAliveUnits(Group.getByName(groupName))
    if #units == 0 then return false end
    return DMS.Util.isPointInZone(units[1]:getPoint(), shape)  -- lead vehicle
end

local function checkConvoyZonePosition()
    if DMS.DustoffCorridor.State.missionEnded then return end

    local state = DMS.DustoffCorridor.ZoneState
    local zones = state.zones
    local flags = DMS.DustoffCorridor.Flags

    -- Priority: victory > charlie > bravo > alpha
    local newZone = nil
    if isGroupInZone(state.convoyGroupName, zones.victory) then newZone = "victory"
    elseif isGroupInZone(state.convoyGroupName, zones.charlie) then newZone = "charlie"
    elseif isGroupInZone(state.convoyGroupName, zones.bravo) then newZone = "bravo"
    elseif isGroupInZone(state.convoyGroupName, zones.alpha) then newZone = "alpha"
    end

    if newZone ~= state.currentZone then
        if state.currentZone == "alpha" then
            setVoiceLineFlag(flags.CONVOY_ALPHA_EXIT, "Convoy exits Alpha-Zone")
        elseif state.currentZone == "bravo" then
            setVoiceLineFlag(flags.CONVOY_BRAVO_EXIT, "Convoy exits Bravo-Zone")
        elseif state.currentZone == "charlie" then
            setVoiceLineFlag(flags.CONVOY_CHARLIE_EXIT, "Convoy exits Charlie-Zone")
        end

        if newZone == "alpha" and not state.zonesEntered.alpha then
            setVoiceLineFlag(flags.CONVOY_ALPHA_ENTER, "Convoy enters Alpha-Zone")
            state.zonesEntered.alpha = true
        elseif newZone == "bravo" and not state.zonesEntered.bravo then
            setVoiceLineFlag(flags.CONVOY_BRAVO_ENTER, "Convoy enters Bravo-Zone")
            state.zonesEntered.bravo = true
        elseif newZone == "charlie" and not state.zonesEntered.charlie then
            setVoiceLineFlag(flags.CONVOY_CHARLIE_ENTER, "Convoy enters Charlie-Zone")
            state.zonesEntered.charlie = true
            DMS.DustoffCorridor.triggerQRF("convoy entered Charlie")
        elseif newZone == "victory" and not state.zonesEntered.victory then
            setVoiceLineFlag(flags.CONVOY_ARRIVED, "Convoy arrives at FOB-Victory")
            state.zonesEntered.victory = true
        end

        state.currentZone = newZone
    end
end

function DMS.DustoffCorridor.startZoneMonitoring()
    local state = DMS.DustoffCorridor.ZoneState
    state.zones.alpha = DMS.Util.getZoneShape("Alpha-Zone")
    state.zones.bravo = DMS.Util.getZoneShape("Bravo-Zone")
    state.zones.charlie = DMS.Util.getZoneShape("Charlie-Zone")
    state.zones.victory = DMS.Util.getZoneShape("FOB-Victory")

    for key, zoneName in pairs({alpha = "Alpha-Zone", bravo = "Bravo-Zone", charlie = "Charlie-Zone", victory = "FOB-Victory"}) do
        local shape = state.zones[key]
        if not shape then
            env.warning(string.format("[DUSTOFF-VOICE] %s not found", zoneName))
        elseif DMS.Settings.isDebug() then
            env.info(string.format("[DUSTOFF-VOICE] Zone %s: %s", zoneName,
                shape.verts and string.format("quad (%d vertices)", #shape.verts) or string.format("circle r=%.0f", shape.radius)))
        end
    end

    timer.scheduleFunction(DMS.Error.wrapTimer(function(_, time)
        if DMS.DustoffCorridor.State.missionEnded then return nil end
        checkConvoyZonePosition()
        return time + 7
    end, "DustoffCorridor.checkConvoyZonePosition", 7), nil, timer.getTime() + 1)

    if DMS.Settings.isDebug() then
        env.info("[DUSTOFF-VOICE] Zone monitoring started (7s interval)")
    end
end

-- ============================================
-- CONVOY HALT-UNDER-FIRE
-- ============================================

DMS.DustoffCorridor.ConvoyHalt = {
    halted = false,
    lastHitTime = 0,
    resumeAfter = 50,   -- seconds without hits before the convoy resumes its route
    checking = false,
}

local function convoyDebug(fmt, ...)
    if DMS.Settings and DMS.Settings.isDebug() then
        env.info(string.format("[DUSTOFF-CONVOY] " .. fmt, ...))
    end
end

local function setConvoyStopped(stopped)
    local group = Group.getByName(DMS.DustoffCorridor.ZoneState.convoyGroupName)
    if not group or not group:isExist() then return false end
    local controller = group:getController()
    if not controller then return false end
    controller:setCommand({id = "StopRoute", params = {value = stopped}})
    return true
end

function DMS.DustoffCorridor.onConvoyHit()
    local halt = DMS.DustoffCorridor.ConvoyHalt
    halt.lastHitTime = timer.getTime()
    if halt.halted then return end  -- debounce: already halted, just extend the timer

    local group = Group.getByName(DMS.DustoffCorridor.ZoneState.convoyGroupName)
    if not group or not group:isExist() then return end
    local controller = group:getController()
    if controller then
        controller:setOption(AI.Option.Ground.id.ALARM_STATE, AI.Option.Ground.val.ALARM_STATE.RED)
        controller:setOption(AI.Option.Ground.id.ROE, AI.Option.Ground.val.ROE.OPEN_FIRE)
        controller:setOption(AI.Option.Ground.id.DISPERSE_ON_ATTACK, 0)  -- stay on the road
    end
    if setConvoyStopped(true) then
        halt.halted = true
        convoyDebug("Convoy halted under fire (resume after %ds without hits)", halt.resumeAfter)
    end

    if not halt.checking then
        halt.checking = true
        timer.scheduleFunction(DMS.Error.wrapTimer(function(_, time)
            if DMS.DustoffCorridor.State.missionEnded or not halt.halted then
                halt.checking = false
                return nil
            end
            if time - halt.lastHitTime >= halt.resumeAfter then
                setConvoyStopped(false)
                halt.halted = false
                halt.checking = false
                convoyDebug("Convoy resuming route (%.0fs without hits)", time - halt.lastHitTime)
                return nil
            end
            return time + 5
        end, "DustoffCorridor.convoyResumeCheck", 5), nil, timer.getTime() + 5)
    end
end

-- ============================================
-- COMBAT EVENT HANDLER
-- ============================================

DMS.DustoffCorridor.DeadConvoyUnits = {}

DMS.DustoffCorridor.CombatEventHandler = {
    onEvent = function(self, event)
        if DMS.DustoffCorridor.State.missionEnded then return end

        local flags = DMS.DustoffCorridor.Flags
        local combatState = DMS.DustoffCorridor.CombatState
        local convoyName = DMS.DustoffCorridor.ZoneState.convoyGroupName

        -- FLAG 117 + halt: convoy unit hit
        if event.id == world.event.S_EVENT_HIT then
            local targetGroup = DMS.Util.getUnitGroup(event.target)
            if targetGroup and targetGroup:getName() == convoyName then
                if not combatState.convoyHasBeenHit then
                    combatState.convoyHasBeenHit = true
                    setVoiceLineFlag(flags.CONVOY_FIRST_HIT, "Convoy taking fire (first hit)")
                end
                DMS.DustoffCorridor.onConvoyHit()
            end

        -- FLAG 118: convoy vehicle destroyed (once per unit)
        elseif event.id == world.event.S_EVENT_DEAD or event.id == world.event.S_EVENT_UNIT_LOST then
            local obj = event.initiator
            local deadGroup = DMS.Util.getUnitGroup(obj)
            if deadGroup and deadGroup:getName() == convoyName then
                local unitName = obj:getName()
                if not DMS.DustoffCorridor.DeadConvoyUnits[unitName] then
                    DMS.DustoffCorridor.DeadConvoyUnits[unitName] = true
                    setVoiceLineFlag(flags.CONVOY_CASUALTY, "Convoy vehicle destroyed")
                    local losses = DMS.Util.countKeys(DMS.DustoffCorridor.DeadConvoyUnits)
                    if losses >= DMS.DustoffCorridor.QRFConfig.lossThreshold then
                        DMS.DustoffCorridor.triggerQRF(string.format("convoy losses %d", losses))
                    end
                end
            end

        -- FLAG 119 backup: A-10 birth on activation
        elseif event.id == world.event.S_EVENT_BIRTH then
            local group = DMS.Util.getUnitGroup(event.initiator)
            if group and group:getName() == DMS.DustoffCorridor.A10Config.groupName then
                DMS.DustoffCorridor.onA10CheckIn("birth event")
            end
        end
    end
}

function DMS.DustoffCorridor.startCombatEventMonitoring()
    world.addEventHandler(DMS.Error.safeHandler(
        DMS.DustoffCorridor.CombatEventHandler,
        "DustoffCorridor.CombatEventHandler"
    ))
    if DMS.Settings.isDebug() then
        env.info("[DUSTOFF-VOICE] Combat event monitoring started")
    end
end

-- ============================================
-- A-10 CAS (late-activated "A-10 CAS" group)
-- ============================================

DMS.DustoffCorridor.A10Config = {
    groupName = "A-10 CAS",

    -- TESTING CONFIGURATION
    testing = true,  -- Set to false for production
    testSpawnChance = 100,
    testMinTime = 60,
    testMaxTime = 120,

    -- PRODUCTION CONFIGURATION
    prodSpawnChance = 25,
    prodMinTime = 300,
    prodMaxTime = 600,
}

local function a10Debug(fmt, ...)
    if DMS.Settings and DMS.Settings.isDebug() then
        env.info(string.format("[DUSTOFF-A10] " .. fmt, ...))
    end
end

function DMS.DustoffCorridor.onA10CheckIn(source)
    local combatState = DMS.DustoffCorridor.CombatState
    if combatState.a10HasCheckedIn then return end
    combatState.a10HasCheckedIn = true
    setVoiceLineFlag(DMS.DustoffCorridor.Flags.A10_CHECKIN, "A-10 enters area of operations")
    a10Debug("A-10 checked in (%s)", source or "?")
end

function DMS.DustoffCorridor.scheduleA10Spawn()
    local config = DMS.DustoffCorridor.A10Config
    local spawnChance = config.testing and config.testSpawnChance or config.prodSpawnChance
    local minTime = config.testing and config.testMinTime or config.prodMinTime
    local maxTime = config.testing and config.testMaxTime or config.prodMaxTime

    local delay = minTime + math.random() * (maxTime - minTime)
    a10Debug("Spawn attempt scheduled in %.0fs (chance %d%%, %s mode)", delay, spawnChance,
        config.testing and "TESTING" or "PRODUCTION")

    timer.scheduleFunction(DMS.Error.wrapTimer(function()
        DMS.DustoffCorridor.attemptA10Spawn(spawnChance)
        return nil
    end, "DustoffCorridor.attemptA10Spawn"), nil, timer.getTime() + delay)
end

function DMS.DustoffCorridor.attemptA10Spawn(spawnChance)
    if DMS.DustoffCorridor.State.missionEnded then return end
    local config = DMS.DustoffCorridor.A10Config

    local roll = math.random(1, 100)
    if roll > spawnChance then
        a10Debug("Skipped (rolled %d > %d)", roll, spawnChance)
        return
    end

    local group = Group.getByName(config.groupName)
    if not group then
        env.warning(string.format("[DUSTOFF-A10] Group '%s' not found (check name / Late Activation in ME)", config.groupName))
        return
    end

    -- Late-activated groups exist (isExist == true) before activation; check unit activity instead.
    local unit = group:getUnit(1)
    if unit and unit:isActive() then
        a10Debug("'%s' already active - skipping activation", config.groupName)
        DMS.DustoffCorridor.onA10CheckIn("already active")
        return
    end

    trigger.action.activateGroup(group)
    a10Debug("Activated '%s' (rolled %d <= %d)", config.groupName, roll, spawnChance)

    timer.scheduleFunction(DMS.Error.wrapTimer(function()
        local g = Group.getByName(config.groupName)
        local u = g and g:getUnit(1)
        if u and u:isActive() then
            DMS.DustoffCorridor.onA10CheckIn("activation verified")
        else
            env.warning("[DUSTOFF-A10] A-10 activation failed - unit not active")
        end
        return nil
    end, "DustoffCorridor.verifyA10"), nil, timer.getTime() + 2)
end

-- Manual test: call from an F10 menu / DO SCRIPT to force the A-10
function DMS.DustoffCorridor.forceA10Spawn()
    DMS.DustoffCorridor.attemptA10Spawn(100)
end

-- Enable all features
DMS.Settings.configure({
    debug = true,
    playerCoalition = coalition.side.BLUE,
    enemyCoalition = coalition.side.RED,
    fogOfWar = true,  -- also sets spawnHiddenByDefault = true
})

-- ============================================
-- ALPHA ZONE - Light AA + Infantry (static ambush)
-- ============================================

DMS.DynamicSpawn.createPool("sam-site", {
    zone = "Alpha-Zone",
    templates = {"tunguska", "shilka", "zu23_battery", "aa_ambush"},
    chance = 10,
    count = 1,
    minDistance = 200,
    maxDistance = 700,
    heading = "center",
})

DMS.DynamicSpawn.createPool("alpha-ground", {
    zone = "Alpha-Zone",
    templates = {"infantry_squad", "rpg_team", "technical_mg", "mg_nest"},
    chance = 80,
    count = 4,
    minDistance = 100,
    maxDistance = 500,
})

-- ============================================
-- BRAVO ZONE - Heavy Armor (hunts the convoy)
-- ============================================

DMS.DynamicSpawn.createPool("bravo-armor", {
    zone = "Bravo-Zone",
    templates = {"bmp_section", "btr_squad", "t72_single", "t72_platoon", "checkpoint"},
    chance = 80,
    count = 6,
    minDistance = 200,
    maxDistance = 800,
    hunt = true,
    huntRadius = 4000,
    huntSpeed = 10,
})

DMS.DynamicSpawn.createPool("bravo-infantry", {
    zone = "Bravo-Zone",
    templates = {"infantry_squad", "ambush_team", "rpg_team"},
    chance = 60,
    count = 2,
    minDistance = 100,
    maxDistance = 400,
})

-- ============================================
-- CHARLIE ZONE - Mixed Defense (static ambush)
-- ============================================

DMS.DynamicSpawn.createPool("charlie-defense", {
    zone = "Charlie-Zone",
    templates = {"checkpoint", "btr_squad", "t72_single", "bmp_section", "mg_nest", "infantry_squad"},
    chance = 80,
    count = 5,
    minDistance = 100,
    maxDistance = 500,
})

-- ============================================
-- QRF REINFORCEMENTS (spawned on trigger, hunt the convoy)
-- ============================================

DMS.DustoffCorridor.QRFConfig = {
    pools = {"qrf-light", "qrf-medium", "qrf-heavy"},
    lossThreshold = 2,   -- convoy vehicles lost before QRF launches (or convoy enters Charlie)
    triggered = false,
}

DMS.DynamicSpawn.createPool("qrf-light", {
    zone = "QRF-Staging",
    templates = {"qrf_light", "technical_pair"},
    chance = 50,
    count = 2,
    minDistance = 50,
    maxDistance = 200,
    hunt = true,
    huntRadius = 50000,  -- always hunt once launched
    huntSpeed = 15,
})

DMS.DynamicSpawn.createPool("qrf-medium", {
    zone = "QRF-Staging",
    templates = {"qrf_medium", "bmp_section"},
    chance = 25,
    count = 2,
    minDistance = 50,
    maxDistance = 200,
    hunt = true,
    huntRadius = 50000,
    huntSpeed = 12,
})

DMS.DynamicSpawn.createPool("qrf-heavy", {
    zone = "QRF-Staging",
    templates = {"qrf_heavy", "t72_platoon"},
    chance = 10,
    count = 2,
    minDistance = 50,
    maxDistance = 200,
    hunt = true,
    huntRadius = 50000,
    huntSpeed = 10,
})

function DMS.DustoffCorridor.triggerQRF(reason)
    local qrf = DMS.DustoffCorridor.QRFConfig
    if qrf.triggered or DMS.DustoffCorridor.State.missionEnded then return end
    qrf.triggered = true

    local total = 0
    for _, poolId in ipairs(qrf.pools) do
        total = total + (DMS.DynamicSpawn.executePool(poolId).spawned or 0)
    end
    DMS.DynamicSpawn.huntConvoy(qrf.pools, DMS.DustoffCorridor.ZoneState.convoyGroupName)

    if total > 0 then
        trigger.action.outTextForCoalition(coalition.side.BLUE,
            "Intel: enemy QRF moving from the east toward the convoy.", 10)
    end
    if DMS.Settings.isDebug() then
        env.info(string.format("[DUSTOFF] QRF triggered (%s): %d groups launched", reason or "?", total))
    end
end

-- ============================================
-- START FUNCTION
-- ============================================

function DMS.DustoffCorridor.start()
    env.info("[DUSTOFF] Mission starting...")

    setVoiceLineFlag(DMS.DustoffCorridor.Flags.MISSION_START, "Mission start")

    -- Initial spawn pools (QRF pools spawn later via triggerQRF)
    DMS.DynamicSpawn.executePool("sam-site")
    DMS.DynamicSpawn.executePool("alpha-ground")
    DMS.DynamicSpawn.executePool("bravo-armor")
    DMS.DynamicSpawn.executePool("bravo-infantry")
    DMS.DynamicSpawn.executePool("charlie-defense")

    -- Static ambush posture (SAM sites are handled by SAMAmbush instead)
    DMS.DynamicSpawn.setAmbushPools({"alpha-ground", "bravo-infantry", "charlie-defense"})

    -- Hunting armor (pools with hunt = true)
    DMS.DynamicSpawn.huntConvoy({"bravo-armor"}, "Convoy-Main")

    for _, groupName in ipairs(DMS.DynamicSpawn.getPoolGroups("sam-site")) do
        DMS.SAMAmbush.register(groupName, {activationRange = 8000, fireChance = 80})
    end

    DMS.FogOfWar.start()
    DMS.SAMAmbush.start()

    trigger.action.outTextForCoalition(coalition.side.BLUE,
        "DUSTOFF CORRIDOR\n\n" ..
        "Escort convoy through hostile territory.\n" ..
        "Expect AA threats in all sectors.\n" ..
        "Enemy positions are marked on F10 once detected.\n\n" ..
        "Good hunting.",
        20
    )

    DMS.DustoffCorridor.scheduleA10Spawn()

    env.info("[DUSTOFF] Mission started - enemies spawned dynamically")
end

-- ============================================
-- WIN / LOSS CONDITIONS
-- ============================================

DMS.DustoffCorridor.State = {
    missionEnded = false,
    result = nil,
    convoyStartCount = 0,
}

function DMS.DustoffCorridor.initConvoyTracking()
    local units = DMS.Util.getAliveUnits(Group.getByName("Convoy-Main"))
    DMS.DustoffCorridor.State.convoyStartCount = #units
    env.info(string.format("[DUSTOFF] Tracking %d convoy vehicles", #units))
end

function DMS.DustoffCorridor.checkVictory(_, time)
    if DMS.DustoffCorridor.State.missionEnded then return nil end
    local zone = DMS.DustoffCorridor.ZoneState.zones.victory or DMS.Util.getZoneShape("FOB-Victory")
    if not zone then return time + 10 end

    for _, unit in ipairs(DMS.Util.getAliveUnits(Group.getByName("Convoy-Main"))) do
        if DMS.Util.isPointInZone(unit:getPoint(), zone) then
            DMS.DustoffCorridor.onVictory()
            return nil
        end
    end
    return time + 10
end

function DMS.DustoffCorridor.onVictory()
    if DMS.DustoffCorridor.State.missionEnded then return end
    DMS.DustoffCorridor.State.missionEnded = true
    DMS.DustoffCorridor.State.result = "victory"

    setVoiceLineFlag(DMS.DustoffCorridor.Flags.MISSION_VICTORY, "Mission victory")

    local survivors = #DMS.Util.getAliveUnits(Group.getByName("Convoy-Main"))
    local startCount = DMS.DustoffCorridor.State.convoyStartCount
    trigger.action.outTextForCoalition(coalition.side.BLUE,
        "MISSION COMPLETE\n\n" ..
        "Convoy reached FOB Victory.\n" ..
        string.format("Survivors: %d/%d vehicles\n\n", survivors, startCount) ..
        "Outstanding work, Dustoff.",
        30
    )
    env.info(string.format("[DUSTOFF] VICTORY - %d/%d survived", survivors, startCount))
end

function DMS.DustoffCorridor.checkConvoyDestroyed(_, time)
    if DMS.DustoffCorridor.State.missionEnded then return nil end

    local alive = #DMS.Util.getAliveUnits(Group.getByName("Convoy-Main"))
    if alive == 0 then
        DMS.DustoffCorridor.onDefeat("convoy_destroyed")
        return nil
    end

    local losses = DMS.DustoffCorridor.State.convoyStartCount - alive
    if losses >= DMS.DustoffCorridor.QRFConfig.lossThreshold then
        DMS.DustoffCorridor.triggerQRF(string.format("convoy losses %d", losses))
    end
    return time + 5
end

function DMS.DustoffCorridor.setupPlayerDeathHandler()
    world.addEventHandler(DMS.Error.safeHandler({
        onEvent = function(self, event)
            if DMS.DustoffCorridor.State.missionEnded then return end
            if event.id == world.event.S_EVENT_CRASH or
               event.id == world.event.S_EVENT_EJECTION or
               event.id == world.event.S_EVENT_PILOT_DEAD then
                local group = DMS.Util.getUnitGroup(event.initiator)
                if group and group:getName() == "Player Group" then
                    timer.scheduleFunction(DMS.Error.wrapTimer(function()
                        DMS.DustoffCorridor.onDefeat("player_killed")
                        return nil
                    end, "DustoffCorridor.playerDefeat"), nil, timer.getTime() + 3)
                end
            end
        end
    }, "DustoffCorridor.PlayerDeathHandler"))
end

function DMS.DustoffCorridor.onDefeat(reason)
    if DMS.DustoffCorridor.State.missionEnded then return end
    DMS.DustoffCorridor.State.missionEnded = true
    DMS.DustoffCorridor.State.result = "defeat"

    setVoiceLineFlag(DMS.DustoffCorridor.Flags.MISSION_DEFEAT, "Mission defeat")

    local message = "MISSION FAILED\n\n"
    if reason == "convoy_destroyed" then
        message = message .. "The convoy has been destroyed.\nAll vehicles lost.\n\nThe enemy controls this corridor."
    elseif reason == "player_killed" then
        message = message .. "Dustoff is down.\nConvoy left without air support.\n\nMission aborted."
    else
        message = message .. "Objective failed."
    end

    trigger.action.outTextForCoalition(coalition.side.BLUE, message, 30)
    env.info(string.format("[DUSTOFF] DEFEAT - %s", reason))
end

function DMS.DustoffCorridor.startConditionMonitoring()
    DMS.DustoffCorridor.initConvoyTracking()
    DMS.DustoffCorridor.setupPlayerDeathHandler()

    DMS.DustoffCorridor.startZoneMonitoring()
    DMS.DustoffCorridor.startCombatEventMonitoring()

    timer.scheduleFunction(DMS.Error.wrapTimer(DMS.DustoffCorridor.checkVictory,
        "DustoffCorridor.checkVictory", 10), nil, timer.getTime() + 30)
    timer.scheduleFunction(DMS.Error.wrapTimer(DMS.DustoffCorridor.checkConvoyDestroyed,
        "DustoffCorridor.checkConvoyDestroyed", 5), nil, timer.getTime() + 30)
    env.info("[DUSTOFF] Win/loss monitoring started")
end

-- ============================================
-- EXECUTION
-- ============================================

timer.scheduleFunction(DMS.Error.wrapTimer(function()
    DMS.DustoffCorridor.start()
    return nil
end, "DustoffCorridor.start"), nil, timer.getTime() + 2)

timer.scheduleFunction(DMS.Error.wrapTimer(function()
    DMS.DustoffCorridor.startConditionMonitoring()
    return nil
end, "DustoffCorridor.startConditionMonitoring"), nil, timer.getTime() + 10)

env.info("[DUSTOFF] Dustoff Corridor master init script loaded")
_G.DMS = DMS
