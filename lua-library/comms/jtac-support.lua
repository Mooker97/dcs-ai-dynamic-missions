-- JTAC Support System for DCS Missions
-- Provides target marking (laser + IR pointer + smoke) and 9-line briefs
-- Place in mission via DO SCRIPT FILE
--
-- Lasing requires a JTAC unit (any live ground/air unit, e.g. a HMMWV or
-- MQ-9) named in Config.jtacUnitName or passed to markTarget(). The laser
-- spot is created with Spot.createLaser and tracks the target group's first
-- alive unit; it is destroyed automatically when the target group dies.

DMS = DMS or {}
DMS.JTAC = {}

-- State
DMS.JTAC.Active = false
DMS.JTAC.CurrentTarget = nil
DMS.JTAC.MarkedTargets = {}
DMS.JTAC.LaserCode = 1688
DMS.JTAC.MenuGroups = {}        -- groupId -> true (menu dedupe)
DMS.JTAC.MenuEventHandler = nil
DMS.JTAC.TrackerScheduled = false

-- Configuration
DMS.JTAC.Config = {
    callsign = "Warrior",
    playerCoalition = coalition.side.BLUE,
    targetCoalition = coalition.side.RED,
    jtacUnitName = nil,          -- Unit that lases (nil = no laser, smoke only)
    laserCodeStart = 1688,
    laserCodeEnd = 1700,
    autoMarkRange = 10000,       -- Auto-mark targets within this range of JTAC
    smokeTargets = true,
    smokeColor = trigger.smokeColor.Red,
    useLaser = true,
    useInfraRed = true,
    laserUpdateInterval = 1,     -- Seconds between laser spot updates
    displayDuration = 20,
    menuName = "JTAC",
}

local function debugLog(fmt, ...)
    if DMS.Settings and DMS.Settings.isDebug and DMS.Settings.isDebug() then
        env.info(string.format("[JTAC] " .. fmt, ...))
    end
end

--- Configure JTAC
-- @param settings table Configuration overrides
function DMS.JTAC.configure(settings)
    for key, value in pairs(settings or {}) do
        DMS.JTAC.Config[key] = value
    end
end

--- Get next laser code
-- @return number Next available laser code
local function getNextLaserCode()
    DMS.JTAC.LaserCode = DMS.JTAC.LaserCode + 1
    if DMS.JTAC.LaserCode > DMS.JTAC.Config.laserCodeEnd then
        DMS.JTAC.LaserCode = DMS.JTAC.Config.laserCodeStart
    end
    return DMS.JTAC.LaserCode
end

--- Get bearing from player to target (DCS: x = north, z = east)
local function getBearing(playerPos, targetPos)
    local dx = targetPos.x - playerPos.x
    local dz = targetPos.z - playerPos.z
    local bearing = math.deg(math.atan2(dz, dx))
    if bearing < 0 then bearing = bearing + 360 end
    return bearing
end

--- Get 2D distance between positions
local function getDistance(pos1, pos2)
    local dx = pos2.x - pos1.x
    local dz = pos2.z - pos1.z
    return math.sqrt(dx * dx + dz * dz)
end

--- First alive unit of a group (or nil)
local function getFirstAliveUnit(groupName)
    local group = Group.getByName(groupName)
    if not group or not group:isExist() then return nil end
    local units = group:getUnits()
    if not units then return nil end
    for _, u in ipairs(units) do
        if u and u:isExist() and (u:getLife() or 0) >= 1 then
            return u
        end
    end
    return nil
end

--- Resolve JTAC source unit
local function getJtacUnit(unitName)
    unitName = unitName or DMS.JTAC.Config.jtacUnitName
    if not unitName then return nil end
    local u = Unit.getByName(unitName)
    if u and u:isExist() then return u end
    return nil
end

--- Aim point slightly above the target's origin
local function aimPoint(pos)
    return {x = pos.x, y = pos.y + 2, z = pos.z}
end

--- Destroy laser/IR spots on a mark
local function destroySpots(mark)
    if not mark then return end
    if mark.laserSpot then pcall(mark.laserSpot.destroy, mark.laserSpot) end
    if mark.irSpot then pcall(mark.irSpot.destroy, mark.irSpot) end
    mark.laserSpot = nil
    mark.irSpot = nil
end

--- Create laser/IR spots for a mark
local function createSpots(mark, jtacUnit, targetPos)
    destroySpots(mark)
    if not jtacUnit then return end
    local localRef = {x = 0, y = 2, z = 0}
    local pt = aimPoint(targetPos)
    if DMS.JTAC.Config.useLaser then
        local ok, spot = pcall(Spot.createLaser, jtacUnit, localRef, pt, mark.laserCode)
        if ok and spot then
            mark.laserSpot = spot
        else
            env.error("[JTAC] Spot.createLaser failed: " .. tostring(spot))
        end
    end
    if DMS.JTAC.Config.useInfraRed then
        local ok, spot = pcall(Spot.createInfraRed, jtacUnit, localRef, pt)
        if ok and spot then
            mark.irSpot = spot
        else
            env.error("[JTAC] Spot.createInfraRed failed: " .. tostring(spot))
        end
    end
    debugLog("Lasing '%s' code %d from '%s'", mark.groupName, mark.laserCode, mark.jtacUnitName or "?")
end

--- Remove a mark (destroys spots)
local function removeMark(groupName, reason)
    local mark = DMS.JTAC.MarkedTargets[groupName]
    if not mark then return end
    destroySpots(mark)
    DMS.JTAC.MarkedTargets[groupName] = nil
    if DMS.JTAC.CurrentTarget == mark then
        DMS.JTAC.CurrentTarget = nil
    end
    debugLog("Mark on '%s' removed (%s)", groupName, reason or "cleared")
end

--- Periodic laser tracker: follow moving targets, drop dead ones
local function updateMarks()
    for groupName, mark in pairs(DMS.JTAC.MarkedTargets) do
        local target = getFirstAliveUnit(groupName)
        if not target then
            removeMark(groupName, "target destroyed")
            trigger.action.outTextForCoalition(DMS.JTAC.Config.playerCoalition,
                string.format("%s: Target %s destroyed. Laser off.", DMS.JTAC.Config.callsign, mark.description),
                10)
        else
            local pos = target:getPoint()
            mark.position = pos
            mark.elevation = pos.y
            if mark.laserSpot or mark.irSpot then
                local jtac = getJtacUnit(mark.jtacUnitName)
                if not jtac then
                    destroySpots(mark)
                    debugLog("JTAC '%s' lost, laser off", tostring(mark.jtacUnitName))
                else
                    local pt = aimPoint(pos)
                    if mark.laserSpot then pcall(mark.laserSpot.setPoint, mark.laserSpot, pt) end
                    if mark.irSpot then pcall(mark.irSpot.setPoint, mark.irSpot, pt) end
                end
            end
        end
    end
end

local function trackerTick(_, time)
    local ok, err = pcall(updateMarks)
    if not ok then
        env.error("[JTAC] updateMarks failed: " .. tostring(err))
    end
    if next(DMS.JTAC.MarkedTargets) == nil then
        DMS.JTAC.TrackerScheduled = false
        return nil
    end
    return time + (DMS.JTAC.Config.laserUpdateInterval or 1)
end

local function ensureTracker()
    if DMS.JTAC.TrackerScheduled then return end
    DMS.JTAC.TrackerScheduled = true
    timer.scheduleFunction(trackerTick, nil, timer.getTime() + (DMS.JTAC.Config.laserUpdateInterval or 1))
end

--- Mark a target
-- @param groupName string Target group name
-- @param description string|nil Target description
-- @param jtacUnitName string|nil Lasing unit (defaults to Config.jtacUnitName)
-- @return table|nil Mark data or nil
function DMS.JTAC.markTarget(groupName, description, jtacUnitName)
    local leader = getFirstAliveUnit(groupName)
    if not leader then
        return nil
    end

    local pos = leader:getPoint()

    -- Re-marking: reuse existing code, rebuild spots
    local existing = DMS.JTAC.MarkedTargets[groupName]
    local laserCode = existing and existing.laserCode or getNextLaserCode()
    if existing then destroySpots(existing) end

    local mark = {
        groupName = groupName,
        description = description or leader:getTypeName(),
        position = pos,
        laserCode = laserCode,
        markTime = timer.getTime(),
        elevation = pos.y,
        jtacUnitName = jtacUnitName or DMS.JTAC.Config.jtacUnitName,
    }

    DMS.JTAC.MarkedTargets[groupName] = mark
    DMS.JTAC.CurrentTarget = mark

    local jtac = getJtacUnit(mark.jtacUnitName)
    if jtac then
        createSpots(mark, jtac, pos)
    elseif mark.jtacUnitName then
        debugLog("JTAC unit '%s' not found, smoke only", tostring(mark.jtacUnitName))
    end

    if DMS.JTAC.Config.smokeTargets then
        trigger.action.smoke(pos, DMS.JTAC.Config.smokeColor)
    end

    ensureTracker()
    debugLog("Marked '%s' (%s) laser %d", groupName, mark.description, laserCode)
    return mark
end

--- Re-pop smoke on the current target
function DMS.JTAC.smokeTarget(mark)
    mark = mark or DMS.JTAC.CurrentTarget
    if not mark then return false end
    local u = getFirstAliveUnit(mark.groupName)
    local pos = u and u:getPoint() or mark.position
    trigger.action.smoke(pos, DMS.JTAC.Config.smokeColor)
    return true
end

--- Stop lasing a target
function DMS.JTAC.laserOff(groupName)
    groupName = groupName or (DMS.JTAC.CurrentTarget and DMS.JTAC.CurrentTarget.groupName)
    local mark = groupName and DMS.JTAC.MarkedTargets[groupName]
    if mark then destroySpots(mark) end
end

--- Generate 9-line brief
-- @param mark table Mark data
-- @param playerGroupName string|nil Player group for heading/distance
-- @return string 9-line brief text
function DMS.JTAC.generate9Line(mark, playerGroupName)
    if not mark then
        return DMS.JTAC.Config.callsign .. ": No target marked."
    end

    local playerPos = nil
    if playerGroupName then
        local u = getFirstAliveUnit(playerGroupName)
        if u then playerPos = u:getPoint() end
    end

    local lines = {
        DMS.JTAC.Config.callsign .. ": 9-LINE follows.",
        "1. IP/BP: Player discretion",
    }

    if playerPos then
        local bearing = getBearing(playerPos, mark.position)
        local distance = getDistance(playerPos, mark.position) / 1852  -- to NM
        table.insert(lines, string.format("2. Heading: %03d (true)", math.floor(bearing)))
        table.insert(lines, string.format("3. Distance: %.1f NM", distance))
    else
        table.insert(lines, "2. Heading: N/A")
        table.insert(lines, "3. Distance: N/A")
    end

    local markType = "Smoke"
    if mark.laserSpot then markType = string.format("Laser %d", mark.laserCode) end
    if mark.laserSpot and DMS.JTAC.Config.smokeTargets then
        markType = string.format("Smoke, Laser %d", mark.laserCode)
    end

    table.insert(lines, string.format("4. Elevation: %d ft", math.floor((mark.elevation or 0) * 3.28084)))
    table.insert(lines, string.format("5. Target: %s", tostring(mark.description)))
    table.insert(lines, string.format("6. Position: X:%.0f Z:%.0f", mark.position.x, mark.position.z))
    table.insert(lines, string.format("7. Mark: %s", markType))
    table.insert(lines, "8. Friendlies: None in immediate area")
    table.insert(lines, "9. Egress: Pilot's discretion")
    table.insert(lines, "READBACK.")

    return table.concat(lines, "\n")
end

--- Output helper: to a group if groupId given, else coalition
local function say(msg, duration, groupId)
    if groupId then
        trigger.action.outTextForGroup(groupId, msg, duration, true)
    else
        trigger.action.outTextForCoalition(DMS.JTAC.Config.playerCoalition, msg, duration, true)
    end
end

--- Send 9-line to players
-- @param mark table|nil Mark data (uses current if nil)
-- @param playerGroupName string|nil Requesting group (for heading/distance)
-- @param groupId number|nil Send only to this group
function DMS.JTAC.send9Line(mark, playerGroupName, groupId)
    mark = mark or DMS.JTAC.CurrentTarget
    say(DMS.JTAC.generate9Line(mark, playerGroupName), DMS.JTAC.Config.displayDuration, groupId)
end

--- Send abbreviated "sparkle" call
function DMS.JTAC.sendSparkle(mark, groupId)
    mark = mark or DMS.JTAC.CurrentTarget
    if not mark then return end
    local msg
    if mark.laserSpot then
        msg = string.format("%s: Sparkle, Laser %d on %s.", DMS.JTAC.Config.callsign, mark.laserCode, mark.description)
    else
        msg = string.format("%s: Unable laser. Target %s marked with smoke.", DMS.JTAC.Config.callsign, mark.description)
    end
    say(msg, 10, groupId)
end

--- Check-in message
function DMS.JTAC.checkIn(playerCallsign, groupId)
    playerCallsign = playerCallsign or "Flight"
    say(string.format("%s: %s, this is %s. I hold you Lima Charlie. Standing by for tasking.",
        DMS.JTAC.Config.callsign, playerCallsign, DMS.JTAC.Config.callsign), 10, groupId)
end

--- Cleared hot call
function DMS.JTAC.clearedHot(playerCallsign, groupId)
    playerCallsign = playerCallsign or "Flight"
    say(string.format("%s: %s, you are CLEARED HOT.", DMS.JTAC.Config.callsign, playerCallsign), 5, groupId)
end

--- Good hits / BDA call
function DMS.JTAC.goodHits(playerCallsign, result, groupId)
    playerCallsign = playerCallsign or "Flight"
    result = result or "Target destroyed"
    say(string.format("%s: %s, good hits. %s.", DMS.JTAC.Config.callsign, playerCallsign, result), 10, groupId)
end

--- Request situation update
function DMS.JTAC.sitRep(groupId)
    local markedCount = 0
    for _ in pairs(DMS.JTAC.MarkedTargets) do
        markedCount = markedCount + 1
    end

    local msg
    if markedCount == 0 then
        msg = DMS.JTAC.Config.callsign .. ": No targets currently marked. Standing by."
    else
        msg = string.format("%s: I have %d target(s) marked.", DMS.JTAC.Config.callsign, markedCount)
        local cur = DMS.JTAC.CurrentTarget
        if cur then
            msg = msg .. string.format(" Current target: %s, %s.", tostring(cur.description),
                cur.laserSpot and ("Laser " .. cur.laserCode) or "smoke only")
        end
    end
    say(msg, 10, groupId)
end

--- Clear all marks (destroys all laser/IR spots)
function DMS.JTAC.clearMarks()
    for groupName in pairs(DMS.JTAC.MarkedTargets) do
        removeMark(groupName, "cleared")
    end
    DMS.JTAC.MarkedTargets = {}
    DMS.JTAC.CurrentTarget = nil
    say(DMS.JTAC.Config.callsign .. ": All marks cleared.", 5)
end

--- Start JTAC system
function DMS.JTAC.start()
    DMS.JTAC.Active = true
    debugLog("Started (callsign: %s, jtac unit: %s)", DMS.JTAC.Config.callsign,
        tostring(DMS.JTAC.Config.jtacUnitName))
end

--- Stop JTAC system (lasers off)
function DMS.JTAC.stop()
    DMS.JTAC.Active = false
    for _, mark in pairs(DMS.JTAC.MarkedTargets) do
        destroySpots(mark)
    end
    debugLog("Stopped")
end

--------------------------------------------------------------------------------
-- Per-group F10 menus
--------------------------------------------------------------------------------

local function wrapMenu(fn, name)
    return function(args)
        local ok, err = pcall(fn, args or {})
        if not ok then
            env.error("[JTAC] menu '" .. name .. "' failed: " .. tostring(err))
        end
    end
end

local function playerCallsign(args)
    local u = args.unitName and Unit.getByName(args.unitName)
    if u and u:isExist() then
        local grp = u:getGroup()
        return (grp and grp:getName()) or u:getPlayerName() or "Flight"
    end
    return "Flight"
end

local function buildMenuForGroup(group, unitName)
    if not group then return end
    local groupId = group:getID()
    if DMS.JTAC.MenuGroups[groupId] then return end
    DMS.JTAC.MenuGroups[groupId] = true

    local args = {groupId = groupId, groupName = group:getName(), unitName = unitName}
    local root = missionCommands.addSubMenuForGroup(groupId, DMS.JTAC.Config.menuName)

    missionCommands.addCommandForGroup(groupId, "Check In", root, wrapMenu(function(a)
        DMS.JTAC.checkIn(playerCallsign(a), a.groupId)
    end, "checkIn"), args)
    missionCommands.addCommandForGroup(groupId, "Request 9-Line", root, wrapMenu(function(a)
        DMS.JTAC.send9Line(nil, a.groupName, a.groupId)
    end, "9line"), args)
    missionCommands.addCommandForGroup(groupId, "Request Sparkle", root, wrapMenu(function(a)
        DMS.JTAC.sendSparkle(nil, a.groupId)
    end, "sparkle"), args)
    missionCommands.addCommandForGroup(groupId, "Request Smoke", root, wrapMenu(function(a)
        if DMS.JTAC.smokeTarget() then
            say(DMS.JTAC.Config.callsign .. ": Smoke out on target.", 8, a.groupId)
        else
            say(DMS.JTAC.Config.callsign .. ": No target marked.", 8, a.groupId)
        end
    end, "smoke"), args)
    missionCommands.addCommandForGroup(groupId, "SITREP", root, wrapMenu(function(a)
        DMS.JTAC.sitRep(a.groupId)
    end, "sitrep"), args)

    debugLog("Menu built for group '%s' (id %d)", group:getName(), groupId)
end

local function tryBuildForUnit(unit)
    if not unit or not unit.getPlayerName then return end
    if not unit:isExist() then return end
    local ok, pname = pcall(unit.getPlayerName, unit)
    if not ok or not pname then return end
    if unit:getCoalition() ~= DMS.JTAC.Config.playerCoalition then return end
    buildMenuForGroup(unit:getGroup(), unit:getName())
end

--- Register per-group JTAC F10 menus for player units (call once from mission init)
function DMS.JTAC.setupMenus()
    if DMS.JTAC.MenuEventHandler then return end
    local handler = {}
    function handler:onEvent(event)
        if not event then return end
        if event.id ~= world.event.S_EVENT_BIRTH and event.id ~= world.event.S_EVENT_PLAYER_ENTER_UNIT then
            return
        end
        local ok, err = pcall(tryBuildForUnit, event.initiator)
        if not ok then env.error("[JTAC] menu event error: " .. tostring(err)) end
    end
    DMS.JTAC.MenuEventHandler = handler
    world.addEventHandler(handler)

    -- Players already in slots when this is called
    local players = coalition.getPlayers(DMS.JTAC.Config.playerCoalition) or {}
    for _, u in ipairs(players) do
        pcall(tryBuildForUnit, u)
    end
    debugLog("Per-group menus enabled")
end

--[==[
USAGE EXAMPLE:

DMS.JTAC.configure({
    callsign = "Hammer",
    jtacUnitName = "JTAC-Humvee-1",   -- lasing unit
    smokeTargets = true,
    laserCodeStart = 1688,
})
DMS.JTAC.start()
DMS.JTAC.setupMenus()                -- per-group F10 "JTAC" menu for players

DMS.JTAC.markTarget("Enemy-Armor-1", "T-72 platoon")   -- laser + IR + smoke
DMS.JTAC.send9Line()
DMS.JTAC.clearedHot("Viper 1-1")
DMS.JTAC.goodHits("Viper 1-1", "3 vehicles destroyed")
]==]

-- Export
_G.DMS = DMS
