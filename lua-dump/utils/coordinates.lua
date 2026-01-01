-- Coordinate Utilities for DCS Missions
-- Shared coordinate conversion and distance calculations
-- IMPORTANT: DCS uses x=North/South, z=East/West, y=Altitude (counterintuitive!)
-- Place in mission via DO SCRIPT FILE or embed in mission

DMS = DMS or {}
DMS.Coords = {}

--[[
DCS COORDINATE SYSTEM:
  - Vec3.x = North/South axis (positive = North)
  - Vec3.z = East/West axis (positive = East)
  - Vec3.y = Altitude (height above sea level)

This is DIFFERENT from typical x/y conventions!
Functions in this module use DCS conventions (x, z for ground position).
]]

--- Convert degrees to radians
-- @param deg number Degrees
-- @return number Radians
function DMS.Coords.degToRad(deg)
    return deg * math.pi / 180
end

--- Convert radians to degrees
-- @param rad number Radians
-- @return number Degrees
function DMS.Coords.radToDeg(rad)
    return rad * 180 / math.pi
end

--- Calculate distance between two points (2D ground distance)
-- @param x1 number First point X (North/South)
-- @param z1 number First point Z (East/West)
-- @param x2 number Second point X
-- @param z2 number Second point Z
-- @return number Distance in meters
function DMS.Coords.distance2D(x1, z1, x2, z2)
    local dx = x2 - x1
    local dz = z2 - z1
    return math.sqrt(dx * dx + dz * dz)
end

--- Calculate distance between two Vec3 points (3D)
-- @param pos1 table Vec3 {x, y, z}
-- @param pos2 table Vec3 {x, y, z}
-- @return number Distance in meters
function DMS.Coords.distance3D(pos1, pos2)
    local dx = pos2.x - pos1.x
    local dy = pos2.y - pos1.y
    local dz = pos2.z - pos1.z
    return math.sqrt(dx * dx + dy * dy + dz * dz)
end

--- Calculate distance from Vec3 (convenience wrapper)
-- @param pos1 table Vec3 from getPoint()
-- @param pos2 table Vec3 from getPoint()
-- @return number Ground distance in meters (ignores altitude)
function DMS.Coords.distanceVec3(pos1, pos2)
    return DMS.Coords.distance2D(pos1.x, pos1.z, pos2.x, pos2.z)
end

--- Calculate bearing from point 1 to point 2
-- @param x1 number First point X (North/South)
-- @param z1 number First point Z (East/West)
-- @param x2 number Second point X
-- @param z2 number Second point Z
-- @return number Bearing in degrees (0-360, 0 = North)
function DMS.Coords.bearing(x1, z1, x2, z2)
    local dx = x2 - x1
    local dz = z2 - z1
    -- atan2(east, north) for bearing from north
    local bearing = math.atan2(dz, dx)
    bearing = DMS.Coords.radToDeg(bearing)
    if bearing < 0 then
        bearing = bearing + 360
    end
    return bearing
end

--- Calculate bearing between two Vec3 positions
-- @param from table Vec3 from position
-- @param to table Vec3 to position
-- @return number Bearing in degrees
function DMS.Coords.bearingVec3(from, to)
    return DMS.Coords.bearing(from.x, from.z, to.x, to.z)
end

--- Calculate new position given start, distance, and bearing
-- @param x number Start X (North/South)
-- @param z number Start Z (East/West)
-- @param distance number Distance in meters
-- @param bearingDeg number Bearing in degrees (0 = North)
-- @return number, number New X, Z coordinates
function DMS.Coords.offsetPosition(x, z, distance, bearingDeg)
    local bearingRad = DMS.Coords.degToRad(bearingDeg)
    -- North component goes to X, East component goes to Z
    local newX = x + distance * math.cos(bearingRad)
    local newZ = z + distance * math.sin(bearingRad)
    return newX, newZ
end

--- Generate random position within radius of center point
-- @param centerX number Center X coordinate
-- @param centerZ number Center Z coordinate
-- @param minRadius number Minimum radius in meters
-- @param maxRadius number Maximum radius in meters
-- @return number, number Random X, Z coordinates
function DMS.Coords.randomInRadius(centerX, centerZ, minRadius, maxRadius)
    local angle = math.random() * 2 * math.pi
    local radius = minRadius + math.random() * (maxRadius - minRadius)
    local x = centerX + radius * math.cos(angle)
    local z = centerZ + radius * math.sin(angle)
    return x, z
end

--- Generate random position within rectangular zone
-- @param minX number Minimum X (South boundary)
-- @param maxX number Maximum X (North boundary)
-- @param minZ number Minimum Z (West boundary)
-- @param maxZ number Maximum Z (East boundary)
-- @return number, number Random X, Z coordinates
function DMS.Coords.randomInRect(minX, maxX, minZ, maxZ)
    local x = minX + math.random() * (maxX - minX)
    local z = minZ + math.random() * (maxZ - minZ)
    return x, z
end

--- Check if point is within radius of center
-- @param px number Point X
-- @param pz number Point Z
-- @param cx number Center X
-- @param cz number Center Z
-- @param radius number Radius in meters
-- @return boolean True if point is within radius
function DMS.Coords.isInRadius(px, pz, cx, cz, radius)
    return DMS.Coords.distance2D(px, pz, cx, cz) <= radius
end

--- Check if Vec3 is within radius of center Vec3
-- @param point table Vec3 point to check
-- @param center table Vec3 center point
-- @param radius number Radius in meters
-- @return boolean True if within radius
function DMS.Coords.isVec3InRadius(point, center, radius)
    return DMS.Coords.isInRadius(point.x, point.z, center.x, center.z, radius)
end

--- Get unit position safely
-- @param unit Unit object or unit name string
-- @return table|nil Vec3 position {x, y, z} or nil if not found
function DMS.Coords.getUnitPos(unit)
    if type(unit) == "string" then
        unit = Unit.getByName(unit)
    end
    if unit and unit:isExist() then
        return unit:getPoint()
    end
    return nil
end

--- Get group lead position safely
-- @param group Group object or group name string
-- @return table|nil Vec3 position {x, y, z} or nil if not found
function DMS.Coords.getGroupPos(group)
    if type(group) == "string" then
        group = Group.getByName(group)
    end
    if group and group:isExist() then
        local units = group:getUnits()
        if units and #units > 0 and units[1]:isExist() then
            return units[1]:getPoint()
        end
    end
    return nil
end

--- Get player unit position (first player found)
-- @param coalitionId number|nil Coalition ID (nil = any)
-- @return table|nil Vec3 position or nil
function DMS.Coords.getPlayerPos(coalitionId)
    local searchCoalitions = coalitionId and {coalitionId} or {coalition.side.BLUE, coalition.side.RED}

    for _, side in ipairs(searchCoalitions) do
        local players = coalition.getPlayers(side)
        if players then
            for _, unit in ipairs(players) do
                if unit and unit:isExist() then
                    return unit:getPoint()
                end
            end
        end
    end
    return nil
end

--- Format position as readable string
-- @param pos table Vec3 {x, y, z}
-- @return string Formatted position
function DMS.Coords.formatPos(pos)
    if pos.y then
        return string.format("X:%.0f Z:%.0f Alt:%.0fm", pos.x, pos.z, pos.y)
    else
        return string.format("X:%.0f Z:%.0f", pos.x, pos.z)
    end
end

--- Format bearing/range from one position to another
-- @param from table Vec3 from position
-- @param to table Vec3 to position
-- @return string Formatted "BRG/RNG" string
function DMS.Coords.formatBRA(from, to)
    local brg = DMS.Coords.bearingVec3(from, to)
    local rng = DMS.Coords.distanceVec3(from, to)
    local rngNm = DMS.Coords.metersToNM(rng)
    return string.format("%03d/%.1f", brg, rngNm)
end

--- Convert meters to nautical miles
-- @param meters number Distance in meters
-- @return number Distance in nautical miles
function DMS.Coords.metersToNM(meters)
    return meters / 1852
end

--- Convert nautical miles to meters
-- @param nm number Distance in nautical miles
-- @return number Distance in meters
function DMS.Coords.nmToMeters(nm)
    return nm * 1852
end

--- Convert meters to feet
-- @param meters number Height in meters
-- @return number Height in feet
function DMS.Coords.metersToFeet(meters)
    return meters * 3.28084
end

--- Convert feet to meters
-- @param feet number Height in feet
-- @return number Height in meters
function DMS.Coords.feetToMeters(feet)
    return feet / 3.28084
end

--- Convert m/s to knots
-- @param mps number Speed in meters per second
-- @return number Speed in knots
function DMS.Coords.mpsToKnots(mps)
    return mps * 1.94384
end

--- Convert knots to m/s
-- @param knots number Speed in knots
-- @return number Speed in meters per second
function DMS.Coords.knotsToMps(knots)
    return knots / 1.94384
end

--- Get speed from velocity Vec3
-- @param velocity table Vec3 velocity from getVelocity()
-- @return number Speed in m/s
function DMS.Coords.getSpeed(velocity)
    return math.sqrt(velocity.x^2 + velocity.y^2 + velocity.z^2)
end

--- Get ground speed from velocity Vec3 (ignores vertical)
-- @param velocity table Vec3 velocity
-- @return number Ground speed in m/s
function DMS.Coords.getGroundSpeed(velocity)
    return math.sqrt(velocity.x^2 + velocity.z^2)
end

-- Export for global access
_G.DMS = DMS
