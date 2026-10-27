-- Fog of War System for DCS Missions
-- Hides enemy groups on the F10 map and shows F10 contact marks once detected.
--
-- HOW IT WORKS (DCS limitations):
--   DCS has NO scripting call to hide/reveal an existing group on the F10 map at
--   runtime (there is no trigger.action.groupKnown). So this module:
--     1. HIDE at spawn time: sets hidden=true / hiddenOnMFD=true / hiddenOnPlanner=true
--        in the coalition.addGroup() table (DMS.FogOfWar.applyToSpawnTable). Late
--        activation groups are respawned from their ME definition to apply the flag
--        (via DMS.SpawnCore, if loaded) - otherwise tick "Hidden on map" in the ME.
--     2. REVEAL = F10 drawings for the detecting coalition: a circle
--        (trigger.action.circleToAll) + text mark (trigger.action.markToCoalition)
--        at the detected position, refreshed periodically, expired when contact is
--        lost for revealTimeout seconds and removed when the group dies.
--     3. DETECTION = proximity of the detecting coalition's units +
--        Controller:getDetectedTargets() of the detecting coalition's groups +
--        hit / shot / kill events.
--
-- MISSION EDITOR: set Options -> Map view to "Fog of War" (or "Only allies"/"My
-- aircraft") and enforce it, otherwise the F10 map already shows every unit and
-- the hidden flag/marks are pointless.
--
-- Requires: utils/mission-settings.lua (optional), utils/error-handler.lua (optional)
-- Place in mission via DO SCRIPT FILE (after mission-settings.lua)

DMS = DMS or {}
DMS.FogOfWar = {}

local FOW = DMS.FogOfWar

-- ============================================================
-- STATE TRACKING
-- ============================================================

-- Units that have been revealed to each coalition (unitName -> true)
FOW.RevealedUnits = {
    [coalition.side.RED] = {},
    [coalition.side.BLUE] = {},
    [coalition.side.NEUTRAL] = {},
}

-- Tracked hidden groups:
-- name -> {name, owner, revealed, revealedTo = {[side]=true}, lastSeen = {[side]=time},
--          marks = {[side] = {circle=id, text=id, time=t}}}
FOW.HiddenGroups = {}

FOW.Running = false
FOW.CheckScheduleID = nil

-- Mark ID range reserved for FOW drawings (keep away from ME/other scripts)
FOW.NextMarkId = 7300000

-- ============================================================
-- CONFIGURATION
-- ============================================================

FOW.Config = {
    enabled = nil,              -- nil = follow DMS.Settings.fogOfWar; true/false = override
    checkInterval = 3,          -- Seconds between detection checks
    revealRange = 5000,         -- Proximity detection range (meters)
    revealOnRadar = true,       -- Use RADAR/RWR/DLINK detections
    revealOnVisual = true,      -- Use VISUAL/OPTIC/IRST detections
    revealOnDamage = true,      -- Reveal on hit/shot/kill events
    announceReveals = false,    -- Text notification to the detecting coalition
    markRefresh = 30,           -- Seconds between mark position refreshes
    revealTimeout = 180,        -- Seconds without detection before marks expire (0 = never)
    markRadius = 300,           -- Circle radius (meters)
    markColor = {1, 0, 0, 1},           -- RGBA outline
    markFill = {1, 0, 0, 0.15},         -- RGBA fill
    markText = true,            -- Also place a text mark
    detectingSides = nil,       -- nil = every side that is not the owner (except NEUTRAL)
}

local function isDebug()
    return DMS.Settings and DMS.Settings.isDebug and DMS.Settings.isDebug()
end

local function log(fmt, ...)
    if isDebug() then
        env.info(string.format("[FOW] " .. fmt, ...))
    end
end

local function logError(context, err)
    local logged = false
    if DMS.Error and DMS.Error.log then
        logged = pcall(DMS.Error.log, context, tostring(err))
    end
    if not logged then
        env.error(string.format("[DMS LUA ERROR] %s: %s", context, tostring(err)))
    end
end

--- Configure fog of war system
-- @param settings table Configuration overrides
-- Keys explicitly set through configure() win over DMS.Settings values
FOW._explicit = {}

function FOW.configure(settings)
    for key, value in pairs(settings or {}) do
        FOW.Config[key] = value
        FOW._explicit[key] = true
    end

    if DMS.Settings and DMS.Settings.get then
        local function sync(cfgKey, settingsKey)
            if FOW._explicit[cfgKey] then return end
            local v = DMS.Settings.get(settingsKey)
            if v ~= nil then FOW.Config[cfgKey] = v end
        end
        sync("revealRange", "fogOfWarRevealRange")
        sync("revealOnRadar", "fogOfWarRevealOnRadar")
        sync("revealOnVisual", "fogOfWarRevealOnVisual")
        sync("revealOnDamage", "fogOfWarRevealOnDamage")
    end
end

--- Is fog of war enabled (config override > DMS.Settings.fogOfWar)?
function FOW.isEnabled()
    if FOW.Config.enabled ~= nil then return FOW.Config.enabled end
    if DMS.Settings and DMS.Settings.isFogOfWarEnabled then
        return DMS.Settings.isFogOfWarEnabled()
    end
    return false
end

-- ============================================================
-- SPAWN-TIME HIDING
-- ============================================================

--- Apply hidden flags to a coalition.addGroup() table
-- @param groupTable table Group spawn table (modified in place)
-- @param force boolean|nil true = always hide, false = never, nil = when FOW enabled
-- @return table groupTable, boolean hidden
function FOW.applyToSpawnTable(groupTable, force)
    if type(groupTable) ~= "table" then return groupTable, false end
    local hide = force
    if hide == nil then hide = FOW.isEnabled() end
    if hide then
        groupTable.hidden = true
        groupTable.hiddenOnMFD = true
        groupTable.hiddenOnPlanner = true
    end
    return groupTable, hide and true or false
end

-- ============================================================
-- MARK HELPERS
-- ============================================================

local function newMarkId()
    FOW.NextMarkId = FOW.NextMarkId + 1
    return FOW.NextMarkId
end

local function removeMark(id)
    if id then pcall(trigger.action.removeMark, id) end
end

local function getAliveUnits(group)
    local out = {}
    if not group then return out end
    local ok, units = pcall(group.getUnits, group)
    if not ok or not units then return out end
    for _, u in ipairs(units) do
        if u and u:isExist() and u:getLife() >= 1 then
            out[#out + 1] = u
        end
    end
    return out
end

local function groupCenter(units)
    local sx, sy, sz, n = 0, 0, 0, 0
    for _, u in ipairs(units) do
        local p = u:getPoint()
        sx, sy, sz, n = sx + p.x, sy + p.y, sz + p.z, n + 1
    end
    if n == 0 then return nil end
    return {x = sx / n, y = sy / n, z = sz / n}
end

local function clearMarksForSide(hidden, side)
    local m = hidden.marks[side]
    if m then
        removeMark(m.circle)
        removeMark(m.text)
        hidden.marks[side] = nil
    end
end

local function clearAllMarks(hidden)
    for side, _ in pairs(hidden.marks) do
        clearMarksForSide(hidden, side)
    end
end

--- Draw (or redraw) the contact marks for a group to a coalition
local function drawMarks(hidden, side, units)
    local center = groupCenter(units)
    if not center then return false end
    clearMarksForSide(hidden, side)

    local cfg = FOW.Config
    local typeName = units[1]:getTypeName() or "unknown"
    local text = string.format("Enemy contact: %s x%d", typeName, #units)

    local m = {time = timer.getTime()}
    m.circle = newMarkId()
    local ok, err = pcall(trigger.action.circleToAll, side, m.circle, center, cfg.markRadius,
        cfg.markColor, cfg.markFill, 1, true, "")
    if not ok then
        logError("FogOfWar.circleToAll", err)
        m.circle = nil
    end
    if cfg.markText then
        m.text = newMarkId()
        local okT, errT = pcall(trigger.action.markToCoalition, m.text, text, center, side, true)
        if not okT then
            logError("FogOfWar.markToCoalition", errT)
            m.text = nil
        end
    end
    hidden.marks[side] = m
    return true
end

-- ============================================================
-- CORE FUNCTIONS
-- ============================================================

--- Register a group as hidden (called by spawn functions)
-- @param groupName string Group name
-- @param ownerCoalition number|nil Coalition that owns this group (looked up if nil)
function FOW.registerHiddenGroup(groupName, ownerCoalition)
    if not groupName then return end
    if ownerCoalition == nil then
        local g = Group.getByName(groupName)
        if g then ownerCoalition = g:getCoalition() end
    end
    local existing = FOW.HiddenGroups[groupName]
    if existing then clearAllMarks(existing) end

    FOW.HiddenGroups[groupName] = {
        name = groupName,
        owner = ownerCoalition,
        revealed = false,
        revealedTo = {},
        lastSeen = {},
        marks = {},
    }
    log("Registered hidden group: %s (owner %s)", groupName, tostring(ownerCoalition))
end

--- Reveal a group to a coalition (draws/refreshes F10 marks)
-- @param groupName string Group to reveal
-- @param toCoalition number Coalition to reveal to
-- @param reason string|nil Reason for reveal (for logging)
-- @return boolean True if this was a NEW reveal for that coalition
function FOW.revealGroup(groupName, toCoalition, reason)
    local hidden = FOW.HiddenGroups[groupName]
    if not hidden or not toCoalition then
        return false
    end

    local now = timer.getTime()
    hidden.lastSeen[toCoalition] = now

    if hidden.revealedTo[toCoalition] then
        return false  -- Already revealed; lastSeen refreshed, tick handles mark refresh
    end

    local units = getAliveUnits(Group.getByName(groupName))
    if #units == 0 then
        return false
    end

    hidden.revealedTo[toCoalition] = true
    hidden.revealed = true
    drawMarks(hidden, toCoalition, units)

    FOW.RevealedUnits[toCoalition] = FOW.RevealedUnits[toCoalition] or {}
    for _, unit in ipairs(units) do
        FOW.RevealedUnits[toCoalition][unit:getName()] = true
    end

    if FOW.Config.announceReveals then
        local msg = string.format("Contact! Enemy forces detected%s",
            reason and (" - " .. reason) or "")
        trigger.action.outTextForCoalition(toCoalition, msg, 5)
    end

    log("Revealed %s to coalition %d (%s)", groupName, toCoalition, reason or "unknown")
    return true
end

--- Remove a reveal (marks) for a coalition; the group stays tracked
function FOW.concealGroup(groupName, fromCoalition, reason)
    local hidden = FOW.HiddenGroups[groupName]
    if not hidden or not hidden.revealedTo[fromCoalition] then return false end
    hidden.revealedTo[fromCoalition] = nil
    clearMarksForSide(hidden, fromCoalition)
    local any = false
    for _ in pairs(hidden.revealedTo) do any = true break end
    hidden.revealed = any
    log("Contact lost: %s for coalition %d (%s)", groupName, fromCoalition, reason or "timeout")
    return true
end

--- Stop tracking a group and remove all of its marks (e.g. on death)
function FOW.unregisterGroup(groupName, reason)
    local hidden = FOW.HiddenGroups[groupName]
    if not hidden then return false end
    clearAllMarks(hidden)
    FOW.HiddenGroups[groupName] = nil
    log("Untracked %s (%s)", groupName, reason or "removed")
    return true
end

--- Reveal a unit's group to a coalition
function FOW.revealUnit(unitName, toCoalition)
    local unit = Unit.getByName(unitName)
    if not unit then return false end
    local group = unit:getGroup()
    if group then
        return FOW.revealGroup(group:getName(), toCoalition, "unit detected")
    end
    return false
end

--- Check if a group is revealed to a coalition
function FOW.isRevealed(groupName, toCoalition)
    local hidden = FOW.HiddenGroups[groupName]
    if not hidden then
        return true  -- Not tracked = visible
    end
    return hidden.revealedTo[toCoalition] == true
end

-- ============================================================
-- DETECTION
-- ============================================================

local function detectingSidesFor(owner)
    if FOW.Config.detectingSides then return FOW.Config.detectingSides end
    local sides = {}
    for _, side in ipairs({coalition.side.RED, coalition.side.BLUE}) do
        if side ~= owner then sides[#sides + 1] = side end
    end
    return sides
end

local function detectionTypes()
    local D = Controller and Controller.Detection
    if not D then return {} end
    local types = {}
    if FOW.Config.revealOnVisual then
        types[#types + 1] = D.VISUAL
        types[#types + 1] = D.OPTIC
        types[#types + 1] = D.IRST
    end
    if FOW.Config.revealOnRadar then
        types[#types + 1] = D.RADAR
        types[#types + 1] = D.RWR
        types[#types + 1] = D.DLINK
    end
    return types
end

-- Collect positions of all living units for a side, and detected target
-- group names reported by that side's controllers
local function scanSide(side, wantDetections)
    local positions = {}
    local detected = {}
    local types = wantDetections and detectionTypes() or {}
    for _, cat in ipairs({Group.Category.AIRPLANE, Group.Category.HELICOPTER,
                          Group.Category.GROUND, Group.Category.SHIP}) do
        for _, group in ipairs(coalition.getGroups(side, cat) or {}) do
            local units = getAliveUnits(group)
            for _, u in ipairs(units) do
                positions[#positions + 1] = u:getPoint()
            end
            if #units > 0 and #types > 0 then
                local ok, targets = pcall(function()
                    local ctrl = group:getController()
                    return ctrl and ctrl:getDetectedTargets(unpack(types))
                end)
                if ok and targets then
                    for _, t in ipairs(targets) do
                        local obj = t.object
                        if obj then
                            local okG, g = pcall(function() return obj:getGroup() end)
                            if okG and g then
                                detected[g:getName()] = true
                            end
                        end
                    end
                end
            end
        end
    end
    return positions, detected
end

--- One detection pass over all tracked groups
function FOW.checkDetection()
    local now = timer.getTime()
    local cfg = FOW.Config
    local range2 = cfg.revealRange * cfg.revealRange
    local sideCache = {}
    local wantDetections = cfg.revealOnRadar or cfg.revealOnVisual

    for groupName, hidden in pairs(FOW.HiddenGroups) do
        local group = Group.getByName(groupName)
        local units = getAliveUnits(group)
        if #units == 0 then
            FOW.unregisterGroup(groupName, "destroyed")
        else
            for _, side in ipairs(detectingSidesFor(hidden.owner)) do
                if not sideCache[side] then
                    local positions, detected = scanSide(side, wantDetections)
                    sideCache[side] = {positions = positions, detected = detected}
                end
                local sc = sideCache[side]

                local seen, reason = false, nil
                if sc.detected[groupName] then
                    seen, reason = true, "sensor"
                else
                    for _, eu in ipairs(units) do
                        local ep = eu:getPoint()
                        for _, pp in ipairs(sc.positions) do
                            local dx, dy, dz = ep.x - pp.x, ep.y - pp.y, ep.z - pp.z
                            if dx * dx + dy * dy + dz * dz <= range2 then
                                seen, reason = true, "proximity"
                                break
                            end
                        end
                        if seen then break end
                    end
                end

                if seen then
                    FOW.revealGroup(groupName, side, reason)
                end

                -- Refresh / expire existing reveal
                if hidden.revealedTo[side] then
                    local last = hidden.lastSeen[side] or 0
                    if cfg.revealTimeout > 0 and (now - last) > cfg.revealTimeout then
                        FOW.concealGroup(groupName, side, "contact lost")
                    else
                        local m = hidden.marks[side]
                        if seen and (not m or (now - m.time) >= cfg.markRefresh) then
                            drawMarks(hidden, side, units)
                        end
                    end
                end
            end
        end
    end
end

local function scheduleCheck()
    FOW.CheckScheduleID = timer.scheduleFunction(function(_, time)
        if not FOW.Running then
            FOW.CheckScheduleID = nil
            return nil
        end
        local ok, err = pcall(FOW.checkDetection)
        if not ok then logError("FogOfWar.checkDetection", err) end
        return time + FOW.Config.checkInterval
    end, nil, timer.getTime() + FOW.Config.checkInterval)
end

-- ============================================================
-- EVENT HANDLERS
-- ============================================================

local function groupOf(obj)
    if not obj then return nil end
    local ok, g = pcall(function()
        if obj.getGroup then return obj:getGroup() end
        return nil
    end)
    if ok then return g end
    return nil
end

local function coalitionOf(obj)
    local ok, c = pcall(function() return obj:getCoalition() end)
    if ok then return c end
    return nil
end

local function revealToOpponent(obj, otherObj, reason)
    local g = groupOf(obj)
    if not g then return end
    local name = g:getName()
    if not FOW.HiddenGroups[name] then return end
    local side = otherObj and coalitionOf(otherObj)
    if side and side ~= FOW.HiddenGroups[name].owner and side ~= coalition.side.NEUTRAL then
        FOW.revealGroup(name, side, reason)
    else
        -- Unknown counterpart: reveal to every opposing side
        for _, s in ipairs(detectingSidesFor(FOW.HiddenGroups[name].owner)) do
            FOW.revealGroup(name, s, reason)
        end
    end
end

FOW._EventHandlerInternal = {
    onEvent = function(self, event)
        if not FOW.Running then return end
        local E = world.event

        -- Death: remove marks / stop tracking when the whole group is gone
        if event.id == E.S_EVENT_DEAD or event.id == E.S_EVENT_UNIT_LOST or
           (E.S_EVENT_KILL and event.id == E.S_EVENT_KILL) then
            local victim = (event.id == E.S_EVENT_KILL) and event.target or event.initiator
            local g = groupOf(victim)
            if g then
                local name = g:getName()
                if FOW.HiddenGroups[name] then
                    local okN, victimName = pcall(function() return victim:getName() end)
                    if not okN then victimName = nil end
                    local alive = 0
                    for _, u in ipairs(getAliveUnits(g)) do
                        if u:getName() ~= victimName then alive = alive + 1 end
                    end
                    if alive == 0 then
                        FOW.unregisterGroup(name, "destroyed")
                    end
                end
            end
        end

        if not FOW.Config.revealOnDamage then return end

        if event.id == E.S_EVENT_HIT then
            revealToOpponent(event.target, event.initiator, "combat")
            revealToOpponent(event.initiator, event.target, "engaged")
        elseif event.id == E.S_EVENT_SHOT then
            revealToOpponent(event.initiator, nil, "firing")
        end
    end
}

-- ============================================================
-- SPAWN INTEGRATION
-- ============================================================

--- Spawn a group with fog of war handling
-- @param countryId number Country ID
-- @param category number Group.Category.*
-- @param groupData table coalition.addGroup() table
-- @param hidden boolean|nil Override hidden state (nil = settings / FOW enabled)
-- @return Group|nil
function FOW.spawnGroup(countryId, category, groupData, hidden)
    local shouldHide = hidden
    if shouldHide == nil and DMS.Settings and DMS.Settings.getSpawnHidden then
        shouldHide = DMS.Settings.getSpawnHidden()
    end
    if shouldHide == nil then shouldHide = FOW.isEnabled() end

    FOW.applyToSpawnTable(groupData, shouldHide and true or false)

    local group = coalition.addGroup(countryId, category, groupData)
    if shouldHide and group then
        FOW.registerHiddenGroup(groupData.name, group:getCoalition())
    end
    return group
end

--- Activate a Late Activation group with fog of war handling.
-- Hiding needs a respawn from the ME definition (DMS.SpawnCore) since DCS
-- can't hide an existing group; without SpawnCore set "Hidden on map" in the ME.
-- @param groupName string
-- @param hidden boolean|nil Override hidden state
-- @return boolean Success
function FOW.activateGroup(groupName, hidden)
    local shouldHide = hidden
    if shouldHide == nil and DMS.Settings and DMS.Settings.getSpawnHidden then
        shouldHide = DMS.Settings.getSpawnHidden()
    end

    if DMS.SpawnCore and DMS.SpawnCore.activate then
        return (DMS.SpawnCore.activate(groupName, {hidden = shouldHide and true or false, prefix = "FOW"}))
    end

    local group = Group.getByName(groupName)
    if not group then return false end
    trigger.action.activateGroup(group)
    if shouldHide then
        FOW.registerHiddenGroup(groupName, group:getCoalition())
    end
    return true
end

-- ============================================================
-- CONTROL FUNCTIONS
-- ============================================================

--- Start the fog of war system
function FOW.start()
    if FOW.Running then return end
    FOW.Running = true
    FOW.configure({})

    if DMS.Error and DMS.Error.safeHandler then
        FOW.EventHandler = DMS.Error.safeHandler(FOW._EventHandlerInternal, "FogOfWar.EventHandler")
    else
        FOW.EventHandler = {
            onEvent = function(_, event)
                local ok, err = pcall(FOW._EventHandlerInternal.onEvent, FOW._EventHandlerInternal, event)
                if not ok then logError("FogOfWar.EventHandler", err) end
            end
        }
    end
    world.addEventHandler(FOW.EventHandler)

    scheduleCheck()

    log("Fog of War started (range %dm, interval %ds, refresh %ds, timeout %ds)",
        FOW.Config.revealRange, FOW.Config.checkInterval, FOW.Config.markRefresh, FOW.Config.revealTimeout)
end

--- Stop the fog of war system (marks are kept; call clearMarks() to remove)
function FOW.stop()
    FOW.Running = false
    if FOW.CheckScheduleID then
        pcall(timer.removeFunction, FOW.CheckScheduleID)
        FOW.CheckScheduleID = nil
    end
    if FOW.EventHandler then
        pcall(world.removeEventHandler, FOW.EventHandler)
        FOW.EventHandler = nil
    end
    log("Fog of War stopped")
end

--- Remove every FOW mark
function FOW.clearMarks()
    for _, hidden in pairs(FOW.HiddenGroups) do
        clearAllMarks(hidden)
        hidden.revealedTo = {}
        hidden.revealed = false
    end
end

--- Reveal all hidden groups to the player coalition (end of mission, etc)
function FOW.revealAll()
    local playerCoalition = DMS.Settings and DMS.Settings.getPlayerCoalition() or coalition.side.BLUE
    for groupName, _ in pairs(FOW.HiddenGroups) do
        FOW.revealGroup(groupName, playerCoalition, "mission end")
    end
end

--- Get statistics
-- @return table {totalHidden, revealed, stillHidden}
function FOW.getStats()
    local total, revealed = 0, 0
    local playerCoalition = DMS.Settings and DMS.Settings.getPlayerCoalition() or coalition.side.BLUE
    for _, hidden in pairs(FOW.HiddenGroups) do
        total = total + 1
        if hidden.revealedTo[playerCoalition] then
            revealed = revealed + 1
        end
    end
    return {totalHidden = total, revealed = revealed, stillHidden = total - revealed}
end

--[[
USAGE EXAMPLES:

-- Mission Editor: Options -> Map view = "Fog of War" (enforced)

DMS.Settings.configure({ fogOfWar = true, spawnHiddenByDefault = true })
DMS.FogOfWar.configure({ revealRange = 4000, markRefresh = 20, revealTimeout = 240 })
DMS.FogOfWar.start()

-- Hide a scripted spawn
local data = { name = "Ambush-1", units = {...}, route = {...} }
DMS.FogOfWar.applyToSpawnTable(data)          -- hidden only if FOW enabled
local g = coalition.addGroup(country.id.RUSSIA, Group.Category.GROUND, data)
DMS.FogOfWar.registerHiddenGroup("Ambush-1", g:getCoalition())

-- Or in one call
DMS.FogOfWar.spawnGroup(country.id.RUSSIA, Group.Category.GROUND, data)

-- Late activation group (respawned hidden when spawners/spawn-core.lua is loaded)
DMS.FogOfWar.activateGroup("Enemy-AA-1", true)

-- Manual reveal (e.g. intel report) -> F10 marks for BLUE
DMS.FogOfWar.revealGroup("Enemy-AA-1", coalition.side.BLUE, "intel report")
]]

_G.DMS = DMS
