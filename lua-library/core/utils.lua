-- core/utils.lua
-- Dynamic Mission System - Utility Functions

DynamicMission = DynamicMission or {}

---
-- Calculate distance between two points
-- @param point1 First point {x, y} or {x, y, z}
-- @param point2 Second point {x, y} or {x, y, z}
-- @return number Distance in meters
---
function DynamicMission.getDistance(point1, point2)
    local dx = point2.x - point1.x
    local dy = point2.y - point1.y

    if point1.z and point2.z then
        local dz = point2.z - point1.z
        return math.sqrt(dx*dx + dy*dy + dz*dz)
    else
        return math.sqrt(dx*dx + dy*dy)
    end
end

---
-- Calculate heading from one point to another
-- @param from_point Starting point {x, y}
-- @param to_point Target point {x, y}
-- @return number Heading in radians
---
function DynamicMission.getHeading(from_point, to_point)
    local dx = to_point.x - from_point.x
    local dy = to_point.y - from_point.y
    return math.atan2(dx, dy)
end

---
-- Calculate position offset by distance and heading
-- @param point Starting point {x, y}
-- @param distance Distance in meters
-- @param heading Heading in radians
-- @return table New position {x, y}
---
function DynamicMission.offsetPosition(point, distance, heading)
    return {
        x = point.x + distance * math.sin(heading),
        y = point.y + distance * math.cos(heading)
    }
end

---
-- Convert degrees to radians
-- @param degrees Angle in degrees
-- @return number Angle in radians
---
function DynamicMission.degToRad(degrees)
    return degrees * math.pi / 180
end

---
-- Convert radians to degrees
-- @param radians Angle in radians
-- @return number Angle in degrees
---
function DynamicMission.radToDeg(radians)
    return radians * 180 / math.pi
end
