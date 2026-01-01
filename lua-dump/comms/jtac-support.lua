-- JTAC Support System for DCS Missions
-- Provides target marking and 9-line briefs
-- Requires: utils/coordinates.lua, utils/messaging.lua
-- Place in mission via DO SCRIPT FILE

DMS = DMS or {}
DMS.JTAC = {}

-- State
DMS.JTAC.Active = false
DMS.JTAC.CurrentTarget = nil
DMS.JTAC.MarkedTargets = {}
DMS.JTAC.LaserCode = 1688

-- Configuration
DMS.JTAC.Config = {
    callsign = "Warrior",
    playerCoalition = coalition.side.BLUE,
    targetCoalition = coalition.side.RED,
    laserCodeStart = 1688,
    laserCodeEnd = 1700,
    autoMarkRange = 10000,       -- Auto-mark targets within this range of JTAC
    smokeTargets = true,
    smokeColor = trigger.smokeColor.Red,
    displayDuration = 20,
}

--- Configure JTAC
-- @param settings table Configuration overrides
function DMS.JTAC.configure(settings)
    for key, value in pairs(settings) do
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

--- Calculate cardinal direction
-- @param heading number Heading in degrees
-- @return string Cardinal direction
local function getCardinal(heading)
    if heading >= 337.5 or heading < 22.5 then return "North"
    elseif heading < 67.5 then return "Northeast"
    elseif heading < 112.5 then return "East"
    elseif heading < 157.5 then return "Southeast"
    elseif heading < 202.5 then return "South"
    elseif heading < 247.5 then return "Southwest"
    elseif heading < 292.5 then return "West"
    else return "Northwest"
    end
end

--- Get bearing from player to target
-- @param playerPos table Player Vec3
-- @param targetPos table Target Vec3
-- @return number Bearing in degrees
local function getBearing(playerPos, targetPos)
    local dx = targetPos.x - playerPos.x
    local dz = targetPos.z - playerPos.z
    local bearing = math.deg(math.atan2(dz, dx))
    if bearing < 0 then bearing = bearing + 360 end
    return bearing
end

--- Get distance between positions
-- @param pos1 table Vec3
-- @param pos2 table Vec3
-- @return number Distance in meters
local function getDistance(pos1, pos2)
    local dx = pos2.x - pos1.x
    local dz = pos2.z - pos1.z
    return math.sqrt(dx * dx + dz * dz)
end

--- Mark a target
-- @param groupName string Target group name
-- @param description string|nil Target description
-- @return table|nil Mark data or nil
function DMS.JTAC.markTarget(groupName, description)
    local group = Group.getByName(groupName)
    if not group or not group:isExist() then
        return nil
    end

    local units = group:getUnits()
    if not units or #units == 0 then
        return nil
    end

    local leader = units[1]
    if not leader:isExist() then
        return nil
    end

    local pos = leader:getPoint()
    local laserCode = getNextLaserCode()

    local mark = {
        groupName = groupName,
        description = description or leader:getTypeName(),
        position = pos,
        laserCode = laserCode,
        markTime = timer.getTime(),
        elevation = pos.y,
    }

    DMS.JTAC.MarkedTargets[groupName] = mark
    DMS.JTAC.CurrentTarget = mark

    -- Add smoke if configured
    if DMS.JTAC.Config.smokeTargets then
        trigger.action.smoke(pos, DMS.JTAC.Config.smokeColor)
    end

    return mark
end

--- Generate 9-line brief
-- @param mark table Mark data
-- @param playerGroupName string|nil Player group for IP calculation
-- @return string 9-line brief text
function DMS.JTAC.generate9Line(mark, playerGroupName)
    if not mark then
        return DMS.JTAC.Config.callsign .. ": No target marked."
    end

    -- Get player position for calculations
    local playerPos = nil
    if playerGroupName then
        local playerGroup = Group.getByName(playerGroupName)
        if playerGroup and playerGroup:isExist() then
            local units = playerGroup:getUnits()
            if units and #units > 0 then
                playerPos = units[1]:getPoint()
            end
        end
    end

    -- If no player specified, try to get any player
    if not playerPos then
        local players = coalition.getPlayers(DMS.JTAC.Config.playerCoalition)
        if players and #players > 0 then
            playerPos = players[1]:getPoint()
        end
    end

    local lines = {
        DMS.JTAC.Config.callsign .. ": 9-LINE follows.",
        "1. IP/BP: Player discretion",
    }

    if playerPos then
        local bearing = getBearing(playerPos, mark.position)
        local distance = getDistance(playerPos, mark.position) / 1852  -- to NM

        table.insert(lines, string.format("2. Heading: %03d", math.floor(bearing)))
        table.insert(lines, string.format("3. Distance: %.1f NM", distance))
    else
        table.insert(lines, "2. Heading: N/A")
        table.insert(lines, "3. Distance: N/A")
    end

    table.insert(lines, string.format("4. Elevation: %d ft", math.floor(mark.elevation * 3.28084)))
    table.insert(lines, string.format("5. Target: %s", mark.description))
    table.insert(lines, string.format("6. Position: X:%.0f Z:%.0f", mark.position.x, mark.position.z))
    table.insert(lines, string.format("7. Mark: Smoke, Laser %d", mark.laserCode))
    table.insert(lines, "8. Friendlies: None in immediate area")
    table.insert(lines, "9. Egress: Pilot's discretion")
    table.insert(lines, "READBACK.")

    return table.concat(lines, "\n")
end

--- Send 9-line to players
-- @param mark table|nil Mark data (uses current if nil)
function DMS.JTAC.send9Line(mark)
    mark = mark or DMS.JTAC.CurrentTarget

    local msg = DMS.JTAC.generate9Line(mark)

    trigger.action.outTextForCoalition(
        DMS.JTAC.Config.playerCoalition,
        msg,
        DMS.JTAC.Config.displayDuration,
        true
    )
end

--- Send abbreviated "sparkle" call
-- @param mark table|nil Mark data
function DMS.JTAC.sendSparkle(mark)
    mark = mark or DMS.JTAC.CurrentTarget

    if not mark then
        return
    end

    local msg = string.format("%s: Sparkle, Laser %d on %s.",
        DMS.JTAC.Config.callsign,
        mark.laserCode,
        mark.description
    )

    trigger.action.outTextForCoalition(
        DMS.JTAC.Config.playerCoalition,
        msg,
        10,
        true
    )
end

--- Check-in message
-- @param playerCallsign string Player callsign
function DMS.JTAC.checkIn(playerCallsign)
    playerCallsign = playerCallsign or "Flight"

    local msg = string.format("%s: %s, this is %s. I hold you Lima Charlie. Standing by for tasking.",
        DMS.JTAC.Config.callsign,
        playerCallsign,
        DMS.JTAC.Config.callsign
    )

    trigger.action.outTextForCoalition(
        DMS.JTAC.Config.playerCoalition,
        msg,
        10,
        true
    )
end

--- Cleared hot call
-- @param playerCallsign string Player callsign
function DMS.JTAC.clearedHot(playerCallsign)
    playerCallsign = playerCallsign or "Flight"

    local msg = string.format("%s: %s, you are CLEARED HOT.",
        DMS.JTAC.Config.callsign,
        playerCallsign
    )

    trigger.action.outTextForCoalition(
        DMS.JTAC.Config.playerCoalition,
        msg,
        5,
        true
    )
end

--- Good hits / BDA call
-- @param playerCallsign string Player callsign
-- @param result string|nil Result description
function DMS.JTAC.goodHits(playerCallsign, result)
    playerCallsign = playerCallsign or "Flight"
    result = result or "Target destroyed"

    local msg = string.format("%s: %s, good hits. %s.",
        DMS.JTAC.Config.callsign,
        playerCallsign,
        result
    )

    trigger.action.outTextForCoalition(
        DMS.JTAC.Config.playerCoalition,
        msg,
        10,
        true
    )
end

--- Request situation update
function DMS.JTAC.sitRep()
    local markedCount = 0
    for _ in pairs(DMS.JTAC.MarkedTargets) do
        markedCount = markedCount + 1
    end

    local msg
    if markedCount == 0 then
        msg = DMS.JTAC.Config.callsign .. ": No targets currently marked. Standing by."
    else
        msg = string.format("%s: I have %d target(s) marked.",
            DMS.JTAC.Config.callsign,
            markedCount
        )

        if DMS.JTAC.CurrentTarget then
            msg = msg .. string.format(" Current target: %s, Laser %d.",
                DMS.JTAC.CurrentTarget.description,
                DMS.JTAC.CurrentTarget.laserCode
            )
        end
    end

    trigger.action.outTextForCoalition(
        DMS.JTAC.Config.playerCoalition,
        msg,
        10,
        true
    )
end

--- Clear all marks
function DMS.JTAC.clearMarks()
    DMS.JTAC.MarkedTargets = {}
    DMS.JTAC.CurrentTarget = nil

    trigger.action.outTextForCoalition(
        DMS.JTAC.Config.playerCoalition,
        DMS.JTAC.Config.callsign .. ": All marks cleared.",
        5,
        true
    )
end

--- Start JTAC system
function DMS.JTAC.start()
    DMS.JTAC.Active = true
end

--- Stop JTAC system
function DMS.JTAC.stop()
    DMS.JTAC.Active = false
end

--[[
USAGE EXAMPLE:

-- Configure
DMS.JTAC.configure({
    callsign = "Hammer",
    smokeTargets = true,
    smokeColor = trigger.smokeColor.Red,
    laserCodeStart = 1688
})

-- Start
DMS.JTAC.start()

-- Player check-in
DMS.JTAC.checkIn("Viper 1-1")

-- Mark target
DMS.JTAC.markTarget("Enemy-Armor-1", "T-72 platoon")

-- Send 9-line
DMS.JTAC.send9Line()

-- Or abbreviated call
DMS.JTAC.sendSparkle()

-- Clear to engage
DMS.JTAC.clearedHot("Viper 1-1")

-- BDA after strike
DMS.JTAC.goodHits("Viper 1-1", "3 vehicles destroyed")

-- Set up F10 menu commands
local jtacMenu = missionCommands.addSubMenuForCoalition(coalition.side.BLUE, "JTAC")
missionCommands.addCommandForCoalition(coalition.side.BLUE, "Check In", jtacMenu,
    function() DMS.JTAC.checkIn("Player") end)
missionCommands.addCommandForCoalition(coalition.side.BLUE, "Request 9-Line", jtacMenu,
    function() DMS.JTAC.send9Line() end)
missionCommands.addCommandForCoalition(coalition.side.BLUE, "SITREP", jtacMenu,
    function() DMS.JTAC.sitRep() end)
]]

-- Export
_G.DMS = DMS
