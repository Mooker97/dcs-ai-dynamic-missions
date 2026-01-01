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
local function scanForContacts()
    local contacts = {}
    local groups = coalition.getGroups(DMS.AWACS.Config.enemyCoalition, Group.Category.AIRPLANE)

    if groups then
        for _, group in ipairs(groups) do
            if group:isExist() then
                local units = group:getUnits()
                if units and #units > 0 then
                    local leader = units[1]
                    if leader:isExist() then
                        local pos = leader:getPoint()

                        -- Check altitude threshold
                        if pos.y >= DMS.AWACS.Config.minAltitudeForCall then
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
            if group:isExist() then
                local units = group:getUnits()
                if units and #units > 0 then
                    local leader = units[1]
                    if leader:isExist() then
                        local pos = leader:getPoint()
                        if pos.y >= DMS.AWACS.Config.minAltitudeForCall then
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

--- Process radar sweep
local function processRadarSweep(_, time)
    if not DMS.AWACS.Active then
        return nil
    end

    local playerPos = getPlayerPosition()
    if not playerPos then
        return time + DMS.AWACS.Config.checkInterval
    end

    local currentContacts = scanForContacts()
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
            trigger.action.outTextForCoalition(
                DMS.AWACS.Config.trackingCoalition,
                msg,
                15,
                true
            )
            return nil
        end, nil, time + (i - 1) * 3)
    end

    return time + DMS.AWACS.Config.checkInterval
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
end

--- Stop AWACS system
function DMS.AWACS.stop()
    DMS.AWACS.Active = false
    if DMS.AWACS.TimerId then
        timer.removeFunction(DMS.AWACS.TimerId)
        DMS.AWACS.TimerId = nil
    end
end

--- Request picture (manual call)
function DMS.AWACS.requestPicture()
    local playerPos = getPlayerPosition()
    if not playerPos then
        trigger.action.outTextForCoalition(
            DMS.AWACS.Config.trackingCoalition,
            DMS.AWACS.Config.callsign .. ": Picture clean.",
            10, true
        )
        return
    end

    local contacts = scanForContacts()
    if #contacts == 0 then
        trigger.action.outTextForCoalition(
            DMS.AWACS.Config.trackingCoalition,
            DMS.AWACS.Config.callsign .. ": Picture clean.",
            10, true
        )
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

    trigger.action.outTextForCoalition(
        DMS.AWACS.Config.trackingCoalition,
        msg,
        20, true
    )
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

-- Manual picture request (could be on F10 menu)
missionCommands.addCommandForCoalition(
    coalition.side.BLUE,
    "Request Picture",
    nil,
    DMS.AWACS.requestPicture
)
]]

-- Export
_G.DMS = DMS
