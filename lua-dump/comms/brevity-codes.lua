-- Brevity Code System for DCS Missions
-- Proper military brevity code generation
-- Place in mission via DO SCRIPT FILE

DMS = DMS or {}
DMS.Brevity = {}

-- Bullseye reference point
DMS.Brevity.Bullseye = nil

-- Configuration
DMS.Brevity.Config = {
    playerCoalition = coalition.side.BLUE,
    useMetric = false,          -- false = nautical miles/feet, true = km/meters
    includeMagnetic = true,     -- Include magnetic variation
    magneticVariation = 0,      -- Degrees (positive = east)
    defaultAltitudeFormat = "angels",  -- "angels" or "cherubs" or "meters"
}

--- Configure brevity system
-- @param settings table Configuration overrides
function DMS.Brevity.configure(settings)
    for key, value in pairs(settings) do
        DMS.Brevity.Config[key] = value
    end
end

--- Set bullseye reference point
-- @param pos table Position {x, y, z} or {x, z}
function DMS.Brevity.setBullseye(pos)
    DMS.Brevity.Bullseye = {
        x = pos.x,
        z = pos.z or pos.y,  -- Handle both formats
    }
end

--- Calculate bearing between two points
-- @param fromPos table From position
-- @param toPos table To position
-- @return number Bearing in degrees (0-360)
local function calculateBearing(fromPos, toPos)
    local dx = toPos.x - fromPos.x
    local dz = toPos.z - fromPos.z

    local bearing = math.deg(math.atan2(dz, dx))
    bearing = 90 - bearing  -- Convert from math angle to compass

    if bearing < 0 then bearing = bearing + 360 end
    if bearing >= 360 then bearing = bearing - 360 end

    -- Apply magnetic variation if configured
    if DMS.Brevity.Config.includeMagnetic then
        bearing = bearing + DMS.Brevity.Config.magneticVariation
        if bearing < 0 then bearing = bearing + 360 end
        if bearing >= 360 then bearing = bearing - 360 end
    end

    return bearing
end

--- Calculate distance between two points
-- @param pos1 table First position
-- @param pos2 table Second position
-- @return number Distance in meters
local function calculateDistance(pos1, pos2)
    local dx = pos2.x - pos1.x
    local dz = pos2.z - pos1.z
    return math.sqrt(dx * dx + dz * dz)
end

--- Convert meters to nautical miles
-- @param meters number Distance in meters
-- @return number Distance in nautical miles
local function metersToNM(meters)
    return meters / 1852
end

--- Convert meters to feet
-- @param meters number Altitude in meters
-- @return number Altitude in feet
local function metersToFeet(meters)
    return meters * 3.28084
end

--- Format altitude using brevity
-- @param altitudeMeters number Altitude in meters
-- @param format string|nil Format type (angels/cherubs/meters)
-- @return string Formatted altitude
function DMS.Brevity.formatAltitude(altitudeMeters, format)
    format = format or DMS.Brevity.Config.defaultAltitudeFormat

    if format == "meters" then
        return string.format("%.0f meters", altitudeMeters)
    end

    local altFeet = metersToFeet(altitudeMeters)

    if format == "cherubs" or altFeet < 1000 then
        -- CHERUBS = hundreds of feet (for low altitude)
        local cherubs = math.floor(altFeet / 100)
        return string.format("CHERUBS %d", cherubs)
    else
        -- ANGELS = thousands of feet
        local angels = math.floor(altFeet / 1000)
        return string.format("ANGELS %d", angels)
    end
end

--- Calculate aspect (HOT/COLD/FLANKING)
-- @param fromPos table Observer position
-- @param toPos table Target position
-- @param targetHeading number Target heading in degrees
-- @return string Aspect (HOT/COLD/BEAM/DRAG)
local function calculateAspect(fromPos, toPos, targetHeading)
    local bearingToTarget = calculateBearing(fromPos, toPos)
    local reciprocal = (bearingToTarget + 180) % 360

    -- Calculate angle off (how far target is from pointing at observer)
    local angleOff = math.abs(targetHeading - reciprocal)
    if angleOff > 180 then angleOff = 360 - angleOff end

    if angleOff <= 30 then
        return "HOT"      -- Target heading toward observer
    elseif angleOff >= 150 then
        return "COLD"     -- Target heading away
    elseif angleOff >= 70 and angleOff <= 110 then
        return "BEAM"     -- Target crossing
    else
        return "FLANK"    -- Oblique angle
    end
end

--- Format BRAA call (Bearing, Range, Altitude, Aspect)
-- @param fromPos table Observer position
-- @param toPos table Target position
-- @param targetAltitude number|nil Target altitude in meters
-- @param targetHeading number|nil Target heading for aspect
-- @return string BRAA call
function DMS.Brevity.formatBRAA(fromPos, toPos, targetAltitude, targetHeading)
    local bearing = calculateBearing(fromPos, toPos)
    local distanceM = calculateDistance(fromPos, toPos)
    local distanceNM = metersToNM(distanceM)

    local braaStr = string.format("BRAA %03.0f/%d", bearing, math.floor(distanceNM))

    if targetAltitude then
        local altFeet = metersToFeet(targetAltitude)
        braaStr = braaStr .. string.format("/%d", math.floor(altFeet / 1000) * 1000)
    end

    if targetHeading then
        local aspect = calculateAspect(fromPos, toPos, targetHeading)
        braaStr = braaStr .. "/" .. aspect
    end

    return braaStr
end

--- Format Bullseye reference
-- @param pos table Target position
-- @return string Bullseye call
function DMS.Brevity.formatBullseye(pos)
    if not DMS.Brevity.Bullseye then
        return "BULLSEYE NOT SET"
    end

    local bearing = calculateBearing(DMS.Brevity.Bullseye, pos)
    local distanceM = calculateDistance(DMS.Brevity.Bullseye, pos)
    local distanceNM = metersToNM(distanceM)

    return string.format("BULLSEYE %03.0f/%d", bearing, math.floor(distanceNM))
end

--- Format 9-line CAS brief
-- @param data table 9-line data
-- @return string Formatted 9-line
function DMS.Brevity.format9Line(data)
    local lines = {}

    -- Line 1: IP/BP
    table.insert(lines, string.format("1. IP/BP: %s", data.ip or "N/A"))

    -- Line 2: Heading (IP to target)
    table.insert(lines, string.format("2. HEADING: %03d", data.heading or 0))

    -- Line 3: Distance (IP to target in NM)
    table.insert(lines, string.format("3. DISTANCE: %d NM", data.distance or 0))

    -- Line 4: Target elevation (feet MSL)
    local elevation = data.elevation or 0
    if not DMS.Brevity.Config.useMetric then
        elevation = metersToFeet(elevation)
    end
    table.insert(lines, string.format("4. ELEVATION: %d FT", math.floor(elevation)))

    -- Line 5: Target description
    table.insert(lines, string.format("5. TARGET: %s", data.targetDesc or "UNKNOWN"))

    -- Line 6: Target location (grid or lat/long)
    if data.grid then
        table.insert(lines, string.format("6. LOCATION: %s", data.grid))
    elseif data.location then
        local bullseye = DMS.Brevity.formatBullseye(data.location)
        table.insert(lines, string.format("6. LOCATION: %s", bullseye))
    else
        table.insert(lines, "6. LOCATION: N/A")
    end

    -- Line 7: Mark type
    table.insert(lines, string.format("7. MARK: %s", data.mark or "NONE"))

    -- Line 8: Friendlies
    table.insert(lines, string.format("8. FRIENDLIES: %s", data.friendlies or "NONE"))

    -- Line 9: Egress
    table.insert(lines, string.format("9. EGRESS: %s", data.egress or "EGRESS ON ATTACK HEADING"))

    -- Optional: Remarks
    if data.remarks then
        table.insert(lines, string.format("REMARKS: %s", data.remarks))
    end

    return table.concat(lines, "\n")
end

--- Format SITREP
-- @param data table SITREP data
-- @return string Formatted SITREP
function DMS.Brevity.formatSITREP(data)
    local lines = {}

    table.insert(lines, "===== SITREP =====")

    if data.callsign then
        table.insert(lines, string.format("FROM: %s", data.callsign))
    end

    if data.position then
        local bullseye = DMS.Brevity.formatBullseye(data.position)
        table.insert(lines, string.format("POSITION: %s", bullseye))
    end

    if data.altitude then
        table.insert(lines, string.format("ALTITUDE: %s", DMS.Brevity.formatAltitude(data.altitude)))
    end

    if data.status then
        table.insert(lines, string.format("STATUS: %s", data.status))
    end

    if data.fuel then
        table.insert(lines, string.format("FUEL: %d%% / %d MIN PLAYTIME", data.fuel, data.playtime or 0))
    end

    if data.weapons then
        table.insert(lines, string.format("WEAPONS: %s", data.weapons))
    end

    if data.contacts then
        table.insert(lines, string.format("CONTACTS: %s", data.contacts))
    end

    if data.intentions then
        table.insert(lines, string.format("INTENTIONS: %s", data.intentions))
    end

    if data.requests then
        table.insert(lines, string.format("REQUEST: %s", data.requests))
    end

    return table.concat(lines, "\n")
end

--- Get contact classification based on unit type
-- @param unitType string DCS unit type name
-- @return string Brevity classification
function DMS.Brevity.getContactCall(unitType)
    -- Air contacts
    local airContacts = {
        -- Fighters
        ["F-15C"] = "FIGHTER",
        ["F-15E"] = "STRIKE EAGLE",
        ["F-16C"] = "VIPER",
        ["F-16C_50"] = "VIPER",
        ["F-14A"] = "TOMCAT",
        ["F-14B"] = "TOMCAT",
        ["F/A-18C"] = "HORNET",
        ["FA-18C_hornet"] = "HORNET",
        ["MiG-29A"] = "FULCRUM",
        ["MiG-29S"] = "FULCRUM",
        ["MiG-21Bis"] = "FISHBED",
        ["Su-27"] = "FLANKER",
        ["Su-33"] = "FLANKER",
        ["Su-30"] = "FLANKER",
        ["J-11A"] = "FLANKER",

        -- Attack
        ["A-10C"] = "HAWG",
        ["A-10C_2"] = "HAWG",
        ["Su-25"] = "FROGFOOT",
        ["Su-25T"] = "FROGFOOT",

        -- Helicopters
        ["AH-64D"] = "APACHE",
        ["AH-64D_BLK_II"] = "APACHE",
        ["Ka-50"] = "HOKUM",
        ["Ka-50_3"] = "HOKUM",
        ["Mi-24P"] = "HIND",
        ["Mi-24V"] = "HIND",
        ["Mi-8MT"] = "HIP",
        ["UH-60A"] = "BLACKHAWK",
        ["UH-1H"] = "HUEY",

        -- Transport/Support
        ["C-130"] = "HERC",
        ["IL-76MD"] = "CANDID",
        ["E-3A"] = "AWACS",
        ["A-50"] = "MAINSTAY",
        ["KC-135"] = "TANKER",
        ["IL-78M"] = "TANKER",
    }

    -- Ground contacts
    local groundContacts = {
        ["T-72B"] = "TANK",
        ["T-72B3"] = "TANK",
        ["T-80UD"] = "TANK",
        ["T-90"] = "TANK",
        ["M1A2"] = "TANK",
        ["Leopard-2"] = "TANK",
        ["BMP-1"] = "IFV",
        ["BMP-2"] = "IFV",
        ["BMP-3"] = "IFV",
        ["M2A2"] = "BRADLEY",
        ["BTR-80"] = "APC",
        ["BRDM-2"] = "SCOUT",
        ["Infantry"] = "TROOPS",
        ["Soldier"] = "TROOPS",
        ["ZU-23"] = "AAA",
        ["ZSU-23-4"] = "SHILKA",
        ["2S6 Tunguska"] = "TUNGUSKA",
        ["SA-6 Kub Str"] = "GAINFUL",
        ["SA-8 Osa"] = "GECKO",
        ["SA-9 Strela 1"] = "GASKIN",
        ["SA-11 Buk SR"] = "GADFLY",
        ["SA-15 Tor"] = "GAUNTLET",
        ["SA-19 Grisom 2S6M"] = "GRISON",
        ["S-300PS"] = "GRUMBLE",
        ["Patriot"] = "PATRIOT",
        ["Hawk"] = "HAWK",
    }

    return airContacts[unitType] or groundContacts[unitType] or "UNKNOWN"
end

--- Get weapon brevity call
-- @param weaponType string Weapon type or category
-- @return string Weapon call
function DMS.Brevity.getWeaponCall(weaponType)
    local weaponCalls = {
        -- Air-to-Air
        ["AIM-120"] = "FOX THREE",
        ["AIM-7"] = "FOX ONE",
        ["AIM-9"] = "FOX TWO",
        ["R-77"] = "FOX THREE",
        ["R-27ER"] = "FOX ONE",
        ["R-27ET"] = "FOX TWO",
        ["R-73"] = "FOX TWO",

        -- Air-to-Ground
        ["AGM-65"] = "RIFLE",
        ["AGM-88"] = "MAGNUM",
        ["GBU"] = "LASER",
        ["CBU"] = "PICKLE",
        ["Mk-82"] = "PICKLE",
        ["Mk-83"] = "PICKLE",
        ["Mk-84"] = "PICKLE",
        ["FAB"] = "PICKLE",

        -- Guns
        ["GAU-8"] = "GUNS GUNS GUNS",
        ["M61"] = "GUNS",
        ["GSh-30"] = "GUNS",

        -- Missiles generic
        ["SARH"] = "FOX ONE",
        ["ARH"] = "FOX THREE",
        ["IR"] = "FOX TWO",
        ["HARM"] = "MAGNUM",
        ["MAVERICK"] = "RIFLE",

        -- Defensive
        ["CHAFF"] = "CHAFF CHAFF",
        ["FLARE"] = "FLARES",
    }

    -- Check for partial matches
    for key, call in pairs(weaponCalls) do
        if string.find(weaponType:upper(), key:upper()) then
            return call
        end
    end

    return "WEAPON"
end

--- Format threat warning
-- @param threatType string Threat type
-- @param bearing number Bearing to threat
-- @param range number|nil Range in meters
-- @return string Threat warning
function DMS.Brevity.formatThreatWarning(threatType, bearing, range)
    local threatCall = DMS.Brevity.getContactCall(threatType)
    local clock = math.floor(((bearing + 15) % 360) / 30) + 1
    if clock == 0 then clock = 12 end

    local warning = string.format("THREAT! %s, %d O'CLOCK", threatCall, clock)

    if range then
        local rangeNM = metersToNM(range)
        if rangeNM < 5 then
            warning = warning .. ", CLOSE"
        elseif rangeNM < 15 then
            warning = warning .. string.format(", %d MILES", math.floor(rangeNM))
        else
            warning = warning .. ", FAR"
        end
    end

    return warning
end

--- Format defensive call
-- @param action string Defensive action (BREAK/DEFENDING/NOTCH)
-- @param direction string Direction (LEFT/RIGHT)
-- @param threat string|nil Threat description
-- @return string Defensive call
function DMS.Brevity.formatDefensive(action, direction, threat)
    local call = string.format("%s %s!", action:upper(), direction:upper())
    if threat then
        call = call .. " " .. threat
    end
    return call
end

--- Common tactical calls
DMS.Brevity.Calls = {
    -- Engagement
    ENGAGED = "ENGAGED",                    -- Maneuvering with intent to kill
    SADDLED = "SADDLED",                   -- In position behind target
    BINGO = "BINGO",                       -- Fuel state requiring RTB
    JOKER = "JOKER",                       -- Fuel state requiring exit from combat
    WINCHESTER = "WINCHESTER",              -- No ordnance remaining
    GUNS = "GUNS GUNS GUNS",               -- Firing cannon

    -- Situational
    BLIND = "BLIND",                       -- Lost visual contact
    VISUAL = "VISUAL",                     -- Have visual contact
    TALLY = "TALLY",                       -- Target in sight
    NO_JOY = "NO JOY",                     -- No target contact
    CONTACT = "CONTACT",                   -- Radar/sensor contact
    CLEAN = "CLEAN",                       -- No radar contacts
    PICTURE = "PICTURE",                   -- Request tactical situation

    -- Maneuvering
    BREAK = "BREAK",                       -- Maximum G turn
    EXTEND = "EXTEND",                     -- Gain distance
    JINK = "JINK",                         -- Unpredictable maneuver
    NOTCH = "NOTCH",                       -- Beaming to defeat radar

    -- Support
    SPLASH = "SPLASH",                     -- Target destroyed
    SHACK = "SHACK",                       -- Direct hit on ground target
    BUDDY_SPIKE = "BUDDY SPIKE",           -- Friendly radar lock warning
    NAILS = "NAILS",                       -- RWR detection of AI radar
    MUD = "MUD",                           -- RWR detection of SAM radar
    SPIKE = "SPIKE",                       -- RWR detection of airborne radar lock
}

--[[
USAGE EXAMPLE:

-- Configure
DMS.Brevity.configure({
    useMetric = false,
    magneticVariation = 4,  -- 4 degrees east
})

-- Set bullseye
DMS.Brevity.setBullseye({x = 0, z = 0})

-- Format BRAA call
local playerPos = {x = 100000, z = 50000}
local targetPos = {x = 120000, z = 60000, y = 5000}
local braa = DMS.Brevity.formatBRAA(playerPos, targetPos, 5000, 180)
-- Returns: "BRAA 045/15/15000/HOT"

-- Format Bullseye
local bullseye = DMS.Brevity.formatBullseye(targetPos)
-- Returns: "BULLSEYE 027/73"

-- Format 9-Line CAS brief
local nineLine = DMS.Brevity.format9Line({
    ip = "IP ALPHA",
    heading = 180,
    distance = 5,
    elevation = 150,
    targetDesc = "T-72 PLATOON, 4 VEHICLES",
    location = targetPos,
    mark = "SMOKE RED",
    friendlies = "SOUTH 500M, MARKED ORANGE PANELS",
    egress = "EAST TO HOLDING POINT BRAVO",
    remarks = "TROOPS IN CONTACT, CLEARED HOT",
})

-- Format altitude
local alt = DMS.Brevity.formatAltitude(7620)
-- Returns: "ANGELS 25"

local lowAlt = DMS.Brevity.formatAltitude(150)
-- Returns: "CHERUBS 5"

-- Get contact call
local contact = DMS.Brevity.getContactCall("MiG-29A")
-- Returns: "FULCRUM"

-- Get weapon call
local weapon = DMS.Brevity.getWeaponCall("AIM-120C")
-- Returns: "FOX THREE"

-- Format threat warning
local threat = DMS.Brevity.formatThreatWarning("SA-6 Kub Str", 270, 15000)
-- Returns: "THREAT! GAINFUL, 9 O'CLOCK, 8 MILES"

-- Using common calls
trigger.action.outText(DMS.Brevity.Calls.WINCHESTER, 5)
trigger.action.outText(DMS.Brevity.Calls.BINGO, 5)
]]

-- Export
_G.DMS = DMS
