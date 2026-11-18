-- AWACS/GCI Simulation for DCS Missions
-- Provides radar picture calls to players
-- Requires: utils/coordinates.lua, utils/messaging.lua
-- Place in mission via DO SCRIPT FILE

DMS = DMS or {}
DMS.AWACS = {}

-- State
DMS.AWACS.Contacts = {}
DMS.AWACS.TimerId = nil
DMS.AWACS.Active = false
DMS.AWACS.ContactIdCounter = 0

-- Configuration
DMS.AWACS.Config = {
    checkInterval = 30,          -- Seconds between radar sweeps
    callsign = "Overlord",       -- AWACS callsign
    detectionRange = 200000,     -- 200km detection range
    trackingCoalition = coalition.side.BLUE,  -- Coalition to provide calls for
    enemyCoalition = coalition.side.RED,
    announceNewContacts = true,
    announceMerges = true,
    announceKills = true,
    useBullseye = false,         -- Use bullseye calls (requires bullseye setup)
    bullseyeX = 0,               -- Bullseye position
    bullseyeZ = 0,
    minAltitudeForCall = 100,    -- Minimum altitude to report (meters)
}

-- Per-group F10 menu state (groupId -> true)
DMS.AWACS.GroupMenus = {}
DMS.AWACS.MenuHandler = nil

local function logDebug(fmt, ...)
    if DMS.Settings and DMS.Settings.isDebug and DMS.Settings.isDebug() then
        env.info(string.format("[AWACS] " .. fmt, ...))
    end
end

-- Contact tracking structure
-- {id, groupName, lastPos, lastAlt, firstSeen, lastSeen, reported}

--- Configure AWACS
-- @param settings table Configuration overrides
function DMS.AWACS.configure(settings)
    for key, value in pairs(settings) do
        DMS.AWACS.Config[key] = value
    end
end

--- Set bullseye position
-- @param x number Bullseye X coordinate
-- @param z number Bullseye Z coordinate
function DMS.AWACS.setBullseye(x, z)
    DMS.AWACS.Config.bullseyeX = x
    DMS.AWACS.Config.bullseyeZ = z
    DMS.AWACS.Config.useBullseye = true
end

--- Get player position (average of all players)
-- @return table|nil Average Vec3 or nil
local function getPlayerPosition()
    local players = coalition.getPlayers(DMS.AWACS.Config.trackingCoalition)
    if not players or #players == 0 then
        return nil
    end

    local sumX, sumY, sumZ = 0, 0, 0
    local count = 0

    for _, unit in ipairs(players) do
        if unit and unit:isExist() then
            local pos = unit:getPoint()
            sumX = sumX + pos.x
            sumY = sumY + pos.y
            sumZ = sumZ + pos.z
            count = count + 1
        end
    end

    if count > 0 then
        return {x = sumX / count, y = sumY / count, z = sumZ / count}
    end
    return nil
end

--- Calculate bearing between two positions
-- @param fromX number From X
-- @param fromZ number From Z
-- @param toX number To X
-- @param toZ number To Z
-- @return number Bearing in degrees
local function getBearing(fromX, fromZ, toX, toZ)
    local dx = toX - fromX
    local dz = toZ - fromZ
    local bearing = math.deg(math.atan2(dz, dx))
    if bearing < 0 then
        bearing = bearing + 360
    end
    return bearing
end

--- Calculate distance between two positions
-- @param x1 number First X
-- @param z1 number First Z
-- @param x2 number Second X
-- @param z2 number Second Z
-- @return number Distance in meters
local function getDistance(x1, z1, x2, z2)
    local dx = x2 - x1
    local dz = z2 - z1
    return math.sqrt(dx * dx + dz * dz)
end

--- Get aspect (hot/cold/flanking) based on track vs player
-- @param contactHeading number Contact heading in degrees
-- @param bearingToPlayer number Bearing from contact to player
-- @return string Aspect string
local function getAspect(contactHeading, bearingToPlayer)
    local angleDiff = math.abs(contactHeading - bearingToPlayer)
    if angleDiff > 180 then
        angleDiff = 360 - angleDiff
    end

    if angleDiff < 30 then
        return "hot"
    elseif angleDiff > 150 then
        return "cold"
    elseif angleDiff < 90 then
        return "flanking"
    else
        return "beaming"
    end
end

--- Get cardinal direction from heading
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

--- Generate BRA call
-- @param contact table Contact data
-- @param playerPos table Player Vec3
-- @return string BRA call message
local function generateBRACall(contact, playerPos)
    local bearing = getBearing(playerPos.x, playerPos.z, contact.lastPos.x, contact.lastPos.z)
    local range = getDistance(playerPos.x, playerPos.z, contact.lastPos.x, contact.lastPos.z) / 1852  -- to NM
    local angels = math.floor(contact.lastAlt / 304.8)  -- to thousands of feet

    local msg = string.format("%s: Contact, BRA %03d/%d, angels %d",
        DMS.AWACS.Config.callsign,
        math.floor(bearing),
        math.floor(range),
        angels
    )

    if contact.aspect then
        msg = msg .. ", " .. contact.aspect
    end

    return msg
end

--- Generate Bullseye call
-- @param contact table Contact data
-- @return string Bullseye call message
local function generateBullseyeCall(contact)
    local bearing = getBearing(
        DMS.AWACS.Config.bullseyeX, DMS.AWACS.Config.bullseyeZ,
        contact.lastPos.x, contact.lastPos.z
    )
    local range = getDistance(
        DMS.AWACS.Config.bullseyeX, DMS.AWACS.Config.bullseyeZ,
        contact.lastPos.x, contact.lastPos.z
    ) / 1852

    local angels = math.floor(contact.lastAlt / 304.8)
    local track = contact.track or "unknown"

    return string.format("%s: Group, Bullseye %03d/%d, %d thousand, tracking %s",
        DMS.AWACS.Config.callsign,
        math.floor(bearing),
        math.floor(range),
        angels,
        track
    )
end

--- Scan for enemy aircraft
-- @return table Array of detected contacts
local function scanForContacts(refPos)
    local contacts = {}
    local maxRange = DMS.AWACS.Config.detectionRange
    local groups = coalition.getGroups(DMS.AWACS.Config.enemyCoalition, Group.Category.AIRPLANE)

    if groups then
        for _, group in ipairs(groups) do
            if group and group:isExist() then
                local units = group:getUnits()
                if units and #units > 0 then
                    local leader = units[1]
                    if leader and leader:isExist() then
                        local pos = leader:getPoint()

                        -- Check altitude threshold and detection range
                        local inRange = (not refPos or not maxRange)
                            or getDistance(refPos.x, refPos.z, pos.x, pos.z) <= maxRange
                        if inRange and pos.y >= DMS.AWACS.Config.minAltitudeForCall then
                            -- Get velocity for track
                            local velocity = leader:getVelocity()
                            local heading = math.deg(math.atan2(velocity.z, velocity.x))
                            if heading < 0 then heading = heading + 360 end

                            table.insert(contacts, {
                                groupName = group:getName(),
                                pos = pos,
                                alt = pos.y,
                                heading = heading,
                                track = getCardinal(heading),
                                unitCount = #units
                            })
                        end
                    end
                end
            end
        end
    end

    -- Also check helicopters
    local helis = coalition.getGroups(DMS.AWACS.Config.enemyCoalition, Group.Category.HELICOPTER)
    if helis then
        for _, group in ipairs(helis) do
            if group and group:isExist() then
                local units = group:getUnits()
                if units and #units > 0 then
                    local leader = units[1]
                    if leader and leader:isExist() then
                        local pos = leader:getPoint()
                        local inRange = (not refPos or not maxRange)
                            or getDistance(refPos.x, refPos.z, pos.x, pos.z) <= maxRange
                        if inRange and pos.y >= DMS.AWACS.Config.minAltitudeForCall then
                            table.insert(contacts, {
                                groupName = group:getName(),
                                pos = pos,
                                alt = pos.y,
                                heading = 0,
                                track = "unknown",
                                unitCount = #units,
                                isHeli = true
                            })
                        end
                    end
                end
            end
        end
    end

    return contacts
end

--- Process radar sweep (unguarded body; see processRadarSweep)
local function doRadarSweep(time)
    if not DMS.AWACS.Active then
        return nil
    end

    local playerPos = getPlayerPosition()
    if not playerPos then
        return time + DMS.AWACS.Config.checkInterval
    end

    local currentContacts = scanForContacts(playerPos)
    local messages = {}

    -- Check for new contacts
    for _, contact in ipairs(currentContacts) do
        local existing = DMS.AWACS.Contacts[contact.groupName]

        if not existing then
            -- New contact!
            DMS.AWACS.ContactIdCounter = DMS.AWACS.ContactIdCounter + 1
            DMS.AWACS.Contacts[contact.groupName] = {
                id = DMS.AWACS.ContactIdCounter,
                groupName = contact.groupName,
                lastPos = contact.pos,
                lastAlt = contact.alt,
                heading = contact.heading,
                track = contact.track,
                firstSeen = time,
                lastSeen = time,
                reported = false
            }

            if DMS.AWACS.Config.announceNewContacts then
                local storedContact = DMS.AWACS.Contacts[contact.groupName]

                -- Calculate aspect
                local bearingToPlayer = getBearing(contact.pos.x, contact.pos.z, playerPos.x, playerPos.z)
                storedContact.aspect = getAspect(contact.heading, bearingToPlayer)

                local msg
                if DMS.AWACS.Config.useBullseye then
                    msg = generateBullseyeCall(storedContact)
                else
                    msg = generateBRACall(storedContact, playerPos)
                end
                table.insert(messages, msg)
                storedContact.reported = true
            end
        else
            -- Update existing contact
            existing.lastPos = contact.pos
            existing.lastAlt = contact.alt
            existing.heading = contact.heading
            existing.track = contact.track
            existing.lastSeen = time
        end
    end

    -- Check for kills (contacts that disappeared)
    for groupName, contact in pairs(DMS.AWACS.Contacts) do
        local stillExists = false
        for _, current in ipairs(currentContacts) do
            if current.groupName == groupName then
                stillExists = true
                break
            end
        end

        if not stillExists then
            if DMS.AWACS.Config.announceKills and contact.reported then
                table.insert(messages, string.format("%s: Contact faded.", DMS.AWACS.Config.callsign))
            end
            DMS.AWACS.Contacts[groupName] = nil
        end
    end

    -- Display messages with spacing
    for i, msg in ipairs(messages) do
        timer.scheduleFunction(function()
            local ok, err = pcall(trigger.action.outTextForCoalition,
                DMS.AWACS.Config.trackingCoalition, msg, 15, true)
            if not ok then
                env.error(string.format("[AWACS] message error: %s", tostring(err)))
            end
            return nil
        end, nil, time + 0.1 + (i - 1) * 3)
    end

    if #messages > 0 then
        logDebug("Sweep: %d contacts, %d calls", #currentContacts, #messages)
    end

    return time + DMS.AWACS.Config.checkInterval
end

--- Timer entry point: pcall-guarded so one bad sweep cannot stop the loop
local function processRadarSweep(_, time)
    local ok, result = pcall(doRadarSweep, time)
    if not ok then
        env.error(string.format("[AWACS] sweep error: %s", tostring(result)))
        if DMS.Error and DMS.Error.log then
            pcall(DMS.Error.log, "AWACS", tostring(result))
        end
        return DMS.AWACS.Active and (time + DMS.AWACS.Config.checkInterval) or nil
    end
    return result
end

--- Start AWACS system
function DMS.AWACS.start()
    if DMS.AWACS.Active then
        return
    end

    DMS.AWACS.Active = true
    DMS.AWACS.TimerId = timer.scheduleFunction(
        processRadarSweep,
        nil,
        timer.getTime() + 5  -- Initial delay
    )
    logDebug("Started (interval: %ds, range: %dm)", DMS.AWACS.Config.checkInterval, DMS.AWACS.Config.detectionRange)
end

--- Stop AWACS system
function DMS.AWACS.stop()
    DMS.AWACS.Active = false
    if DMS.AWACS.TimerId then
        timer.removeFunction(DMS.AWACS.TimerId)
        DMS.AWACS.TimerId = nil
    end
end

--- Get position of the first alive unit in a group
-- @param groupName string DCS group name
-- @return table|nil Vec3, number|nil groupId
local function getGroupPosition(groupName)
    if not groupName then return nil end
    local group = Group.getByName(groupName)
    if not group or not group:isExist() then return nil end
    local groupId = group:getID()
    for _, unit in ipairs(group:getUnits() or {}) do
        if unit and unit:isExist() then
            return unit:getPoint(), groupId
        end
    end
    return nil, groupId
end

--- Request picture (manual call)
-- @param groupName string|nil Requesting group name (per-group menu). nil = coalition-wide, averaged player position
function DMS.AWACS.requestPicture(groupName)
    local groupId = nil
    local function out(text, duration)
        if groupId then
            trigger.action.outTextForGroup(groupId, text, duration, true)
        else
            trigger.action.outTextForCoalition(DMS.AWACS.Config.trackingCoalition, text, duration, true)
        end
    end

    local playerPos
    if groupName then
        playerPos, groupId = getGroupPosition(groupName)
        if not groupId then return end  -- requesting group is gone
    else
        playerPos = getPlayerPosition()
    end
    if not playerPos then
        out(DMS.AWACS.Config.callsign .. ": Picture clean.", 10)
        return
    end

    local contacts = scanForContacts(playerPos)
    logDebug("Picture requested (group %s): %d contacts", tostring(groupName), #contacts)
    if #contacts == 0 then
        out(DMS.AWACS.Config.callsign .. ": Picture clean.", 10)
        return
    end

    local msg = DMS.AWACS.Config.callsign .. ": Picture, " .. #contacts .. " groups.\n"

    for i, contact in ipairs(contacts) do
        if i <= 5 then  -- Limit to 5 groups
            local bearing = getBearing(playerPos.x, playerPos.z, contact.pos.x, contact.pos.z)
            local range = getDistance(playerPos.x, playerPos.z, contact.pos.x, contact.pos.z) / 1852
            local angels = math.floor(contact.alt / 304.8)

            msg = msg .. string.format("Group %d: BRA %03d/%d, angels %d\n",
                i, math.floor(bearing), math.floor(range), angels)
        end
    end

    out(msg, 20)
end

--- Add the per-group AWACS menu for a player group (deduped)
-- @param group table DCS Group
local function addMenuForGroup(group)
    if not group or not group:isExist() then return end
    local groupId = group:getID()
    if DMS.AWACS.GroupMenus[groupId] then return end
    DMS.AWACS.GroupMenus[groupId] = true

    local root = missionCommands.addSubMenuForGroup(groupId, DMS.AWACS.Config.callsign .. " (AWACS)")
    missionCommands.addCommandForGroup(groupId, "Request Picture", root, function(gName)
        local ok, err = pcall(DMS.AWACS.requestPicture, gName)
        if not ok then
            env.error(string.format("[AWACS] requestPicture error: %s", tostring(err)))
        end
    end, group:getName())
    logDebug("Menu added for group '%s' (id %d)", group:getName(), groupId)
end

--- Register per-group F10 menus for player aircraft of the tracking coalition.
-- Built on S_EVENT_BIRTH / S_EVENT_PLAYER_ENTER_UNIT so each callback knows the requesting group.
function DMS.AWACS.setupMenus()
    if DMS.AWACS.MenuHandler then return end

    local function tryUnit(unit)
        if not unit or not unit.getPlayerName then return end
        local ok, playerName = pcall(unit.getPlayerName, unit)
        if not ok or not playerName then return end
        if unit:getCoalition() ~= DMS.AWACS.Config.trackingCoalition then return end
        addMenuForGroup(unit:getGroup())
    end

    DMS.AWACS.MenuHandler = {}
    function DMS.AWACS.MenuHandler:onEvent(event)
        if not event or not event.initiator then return end
        if event.id == world.event.S_EVENT_BIRTH or event.id == world.event.S_EVENT_PLAYER_ENTER_UNIT then
            local ok, err = pcall(tryUnit, event.initiator)
            if not ok then
                env.error(string.format("[AWACS] menu event error: %s", tostring(err)))
            end
        end
    end
    world.addEventHandler(DMS.AWACS.MenuHandler)

    -- Players already in the mission when setupMenus() is called
    for _, unit in ipairs(coalition.getPlayers(DMS.AWACS.Config.trackingCoalition) or {}) do
        pcall(tryUnit, unit)
    end
    logDebug("Per-group menus enabled")
end

--- Get contact count
-- @return number Number of tracked contacts
function DMS.AWACS.getContactCount()
    local count = 0
    for _ in pairs(DMS.AWACS.Contacts) do
        count = count + 1
    end
    return count
end

--[[
USAGE EXAMPLE:

-- Configure
DMS.AWACS.configure({
    callsign = "Magic",
    checkInterval = 20,
    detectionRange = 150000,
    announceNewContacts = true,
    announceKills = true
})

-- Optional: Set bullseye
DMS.AWACS.setBullseye(-50000, 40000)

-- Start system
DMS.AWACS.start()

-- Per-group F10 "Request Picture" menu (BRA from the requesting aircraft)
DMS.AWACS.setupMenus()
]]

-- Export
_G.DMS = DMS
