-- Group Utilities for DCS Missions
-- Common group operations, health checks, position queries
-- Requires: utils/coordinates.lua
-- Place in mission via DO SCRIPT FILE or embed in mission

DMS = DMS or {}
DMS.Groups = {}

--- Get group by name safely
-- @param groupName string Group name
-- @return Group|nil Group object or nil
function DMS.Groups.get(groupName)
    local group = Group.getByName(groupName)
    if group and group:isExist() then
        return group
    end
    return nil
end

--- Check if group exists and has living units
-- @param groupName string Group name
-- @return boolean True if group is alive
function DMS.Groups.isAlive(groupName)
    local group = DMS.Groups.get(groupName)
    if group then
        local units = group:getUnits()
        if units then
            for _, unit in ipairs(units) do
                if unit:isExist() and unit:getLife() >= 1 then
                    return true
                end
            end
        end
    end
    return false
end

--- Get number of alive units in group
-- @param groupName string Group name
-- @return number Count of alive units
function DMS.Groups.getAliveCount(groupName)
    local count = 0
    local group = DMS.Groups.get(groupName)
    if group then
        local units = group:getUnits()
        if units then
            for _, unit in ipairs(units) do
                if unit:isExist() and unit:getLife() >= 1 then
                    count = count + 1
                end
            end
        end
    end
    return count
end

--- Get group health percentage
-- @param groupName string Group name
-- @param initialCount number|nil Initial unit count for comparison
-- @return number Health percentage (0-100)
function DMS.Groups.getHealthPercent(groupName, initialCount)
    local aliveCount = DMS.Groups.getAliveCount(groupName)
    initialCount = initialCount or DMS.Groups.getInitialSize(groupName) or aliveCount
    if initialCount > 0 then
        return (aliveCount / initialCount) * 100
    end
    return 0
end

--- Get group leader position (Vec3)
-- @param groupName string Group name
-- @return table|nil Vec3 position {x, y, z} or nil
function DMS.Groups.getPosition(groupName)
    local group = DMS.Groups.get(groupName)
    if group then
        local units = group:getUnits()
        if units and #units > 0 and units[1]:isExist() then
            return units[1]:getPoint()
        end
    end
    return nil
end

--- Get all unit positions in group
-- @param groupName string Group name
-- @return table Array of Vec3 positions
function DMS.Groups.getAllPositions(groupName)
    local positions = {}
    local group = DMS.Groups.get(groupName)
    if group then
        local units = group:getUnits()
        if units then
            for _, unit in ipairs(units) do
                if unit:isExist() then
                    table.insert(positions, unit:getPoint())
                end
            end
        end
    end
    return positions
end

--- Get center position of group (average of all units)
-- @param groupName string Group name
-- @return table|nil Average Vec3 position or nil
function DMS.Groups.getCenterPosition(groupName)
    local positions = DMS.Groups.getAllPositions(groupName)
    if #positions == 0 then
        return nil
    end

    local sumX, sumY, sumZ = 0, 0, 0
    for _, pos in ipairs(positions) do
        sumX = sumX + pos.x
        sumY = sumY + pos.y
        sumZ = sumZ + pos.z
    end

    return {
        x = sumX / #positions,
        y = sumY / #positions,
        z = sumZ / #positions
    }
end

--- Activate group (must be LATE ACTIVATION in mission editor)
-- @param groupName string Group name
-- @return boolean True if activated
function DMS.Groups.activate(groupName)
    local group = Group.getByName(groupName)
    if group then
        trigger.action.activateGroup(group)
        return true
    end
    return false
end

--- Deactivate group
-- @param groupName string Group name
-- @return boolean True if deactivated
function DMS.Groups.deactivate(groupName)
    local group = DMS.Groups.get(groupName)
    if group then
        trigger.action.deactivateGroup(group)
        return true
    end
    return false
end

--- Destroy group completely
-- @param groupName string Group name
-- @return boolean True if destroyed
function DMS.Groups.destroy(groupName)
    local group = DMS.Groups.get(groupName)
    if group then
        group:destroy()
        return true
    end
    return false
end

--- Get group coalition
-- @param groupName string Group name
-- @return number|nil Coalition ID (0=neutral, 1=red, 2=blue) or nil
function DMS.Groups.getCoalition(groupName)
    local group = DMS.Groups.get(groupName)
    if group then
        return group:getCoalition()
    end
    return nil
end

--- Get group category
-- @param groupName string Group name
-- @return number|nil Category (0=airplane, 1=helicopter, 2=ground, 3=ship, 4=train)
function DMS.Groups.getCategory(groupName)
    local group = DMS.Groups.get(groupName)
    if group then
        return group:getCategory()
    end
    return nil
end

--- Check if group is aircraft (plane or helicopter)
-- @param groupName string Group name
-- @return boolean True if aircraft
function DMS.Groups.isAircraft(groupName)
    local category = DMS.Groups.getCategory(groupName)
    return category == Group.Category.AIRPLANE or category == Group.Category.HELICOPTER
end

--- Check if group is ground unit
-- @param groupName string Group name
-- @return boolean True if ground
function DMS.Groups.isGround(groupName)
    return DMS.Groups.getCategory(groupName) == Group.Category.GROUND
end

--- Check if group is ship
-- @param groupName string Group name
-- @return boolean True if ship
function DMS.Groups.isShip(groupName)
    return DMS.Groups.getCategory(groupName) == Group.Category.SHIP
end

--- Get all groups by coalition
-- @param coalitionId number Coalition ID (coalition.side.BLUE, etc)
-- @return table Array of group objects
function DMS.Groups.getByCoalition(coalitionId)
    local groups = {}
    local allGroups = coalition.getGroups(coalitionId)
    if allGroups then
        for _, group in ipairs(allGroups) do
            if group:isExist() then
                table.insert(groups, group)
            end
        end
    end
    return groups
end

--- Get all groups by coalition and category
-- @param coalitionId number Coalition ID
-- @param category number Group.Category value
-- @return table Array of group objects
function DMS.Groups.getByCoalitionAndCategory(coalitionId, category)
    local groups = {}
    local allGroups = coalition.getGroups(coalitionId, category)
    if allGroups then
        for _, group in ipairs(allGroups) do
            if group:isExist() then
                table.insert(groups, group)
            end
        end
    end
    return groups
end

--- Find closest group to position from list
-- @param pos table Vec3 position
-- @param groupNames table Array of group names to check
-- @return string|nil, number Closest group name and distance (or nil)
function DMS.Groups.findClosest(pos, groupNames)
    local closest = nil
    local minDist = math.huge

    for _, groupName in ipairs(groupNames) do
        local groupPos = DMS.Groups.getPosition(groupName)
        if groupPos then
            local dist = DMS.Coords.distanceVec3(pos, groupPos)
            if dist < minDist then
                minDist = dist
                closest = groupName
            end
        end
    end

    return closest, minDist
end

--- Find groups within radius of position
-- @param pos table Vec3 center position
-- @param radius number Radius in meters
-- @param groupNames table Array of group names to check
-- @return table Array of group names within radius
function DMS.Groups.findInRadius(pos, radius, groupNames)
    local found = {}

    for _, groupName in ipairs(groupNames) do
        local groupPos = DMS.Groups.getPosition(groupName)
        if groupPos then
            if DMS.Coords.isVec3InRadius(groupPos, pos, radius) then
                table.insert(found, groupName)
            end
        end
    end

    return found
end

--- Get group speed (leader unit) in m/s
-- @param groupName string Group name
-- @return number Speed in m/s or 0
function DMS.Groups.getSpeed(groupName)
    local group = DMS.Groups.get(groupName)
    if group then
        local units = group:getUnits()
        if units and #units > 0 and units[1]:isExist() then
            local velocity = units[1]:getVelocity()
            if velocity then
                return DMS.Coords.getSpeed(velocity)
            end
        end
    end
    return 0
end

--- Get group heading (leader unit) in degrees
-- @param groupName string Group name
-- @return number Heading in degrees (0-360) or 0
function DMS.Groups.getHeading(groupName)
    local group = DMS.Groups.get(groupName)
    if group then
        local units = group:getUnits()
        if units and #units > 0 and units[1]:isExist() then
            local pos = units[1]:getPosition()
            if pos and pos.x then
                -- pos.x is the orientation vector
                local heading = math.atan2(pos.x.z, pos.x.x)
                heading = math.deg(heading)
                if heading < 0 then
                    heading = heading + 360
                end
                return heading
            end
        end
    end
    return 0
end

--- Get group altitude (leader unit) in meters
-- @param groupName string Group name
-- @return number Altitude in meters or 0
function DMS.Groups.getAltitude(groupName)
    local pos = DMS.Groups.getPosition(groupName)
    if pos then
        return pos.y
    end
    return 0
end

-- Store initial group sizes for health tracking
DMS.Groups._initialSizes = {}

--- Record initial group size for health tracking
-- @param groupName string Group name
function DMS.Groups.recordInitialSize(groupName)
    DMS.Groups._initialSizes[groupName] = DMS.Groups.getAliveCount(groupName)
end

--- Get initial size (or current if not recorded)
-- @param groupName string Group name
-- @return number Initial unit count
function DMS.Groups.getInitialSize(groupName)
    return DMS.Groups._initialSizes[groupName]
end

--- Record initial sizes for multiple groups
-- @param groupNames table Array of group names
function DMS.Groups.recordAllInitialSizes(groupNames)
    for _, name in ipairs(groupNames) do
        DMS.Groups.recordInitialSize(name)
    end
end

--- Get group controller for AI commands
-- @param groupName string Group name
-- @return Controller|nil Controller object or nil
function DMS.Groups.getController(groupName)
    local group = DMS.Groups.get(groupName)
    if group then
        return group:getController()
    end
    return nil
end

-- Export for global access
_G.DMS = DMS
