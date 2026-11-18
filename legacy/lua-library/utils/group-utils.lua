-- Group Utilities for DCS Missions
-- Common group operations, health checks, position queries
-- Requires: utils/coordinates.lua (optional; falls back to internal math)
-- Place in mission via DO SCRIPT FILE or embed in mission

DMS = DMS or {}
DMS.Groups = DMS.Groups or {}

-- ============================================================
-- INTERNAL HELPERS
-- ============================================================

-- Does a DCS object handle still exist?
local function exists(obj)
    if obj == nil or type(obj) ~= "table" or type(obj.isExist) ~= "function" then
        return false
    end
    local ok, e = pcall(obj.isExist, obj)
    return ok and e and true or false
end

-- Unit alive check (life >= 1; optionally must be activated)
local function unitAlive(unit, requireActive)
    if not exists(unit) then return false end
    local ok, life = pcall(unit.getLife, unit)
    if not ok or type(life) ~= "number" or life < 1 then return false end
    if requireActive and type(unit.isActive) == "function" then
        local okA, active = pcall(unit.isActive, unit)
        if okA and not active then return false end
    end
    return true
end

-- Safe getUnits (always returns a table)
local function getUnits(group)
    if not exists(group) then return {} end
    local ok, units = pcall(group.getUnits, group)
    if ok and type(units) == "table" then return units end
    return {}
end

-- First existing unit of a group (original leader may be dead)
local function firstUnit(group)
    for _, unit in ipairs(getUnits(group)) do
        if exists(unit) then return unit end
    end
    return nil
end

local function dist3(a, b)
    if DMS.Coords and DMS.Coords.distanceVec3 then
        return DMS.Coords.distanceVec3(a, b)
    end
    local dx, dz = a.x - b.x, a.z - b.z
    return math.sqrt(dx * dx + dz * dz)
end

-- ============================================================
-- LOOKUP / LIVENESS
-- ============================================================

--- Get group by name safely
-- @param groupName string Group name
-- @return Group|nil Group object or nil
function DMS.Groups.get(groupName)
    if type(groupName) ~= "string" or not Group or not Group.getByName then
        return nil
    end
    local ok, group = pcall(Group.getByName, groupName)
    if ok and exists(group) then
        return group
    end
    return nil
end

--- Check if group exists and has living units
-- Late-activated (not yet activated) groups count as alive by default, matching
-- DMS.Utils.isGroupAlive; pass requireActive=true to treat them as not alive.
-- @param groupName string Group name
-- @param requireActive boolean|nil
-- @return boolean True if group is alive
function DMS.Groups.isAlive(groupName, requireActive)
    for _, unit in ipairs(getUnits(DMS.Groups.get(groupName))) do
        if unitAlive(unit, requireActive) then
            return true
        end
    end
    return false
end

--- Check if group has been activated (any unit active)
-- @param groupName string Group name
-- @return boolean
function DMS.Groups.isActive(groupName)
    for _, unit in ipairs(getUnits(DMS.Groups.get(groupName))) do
        if exists(unit) and type(unit.isActive) == "function" then
            local ok, active = pcall(unit.isActive, unit)
            if ok and active then return true end
        end
    end
    return false
end

--- Get number of alive units in group
-- @param groupName string Group name
-- @param requireActive boolean|nil
-- @return number Count of alive units
function DMS.Groups.getAliveCount(groupName, requireActive)
    local count = 0
    for _, unit in ipairs(getUnits(DMS.Groups.get(groupName))) do
        if unitAlive(unit, requireActive) then
            count = count + 1
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
    if initialCount and initialCount > 0 then
        return (aliveCount / initialCount) * 100
    end
    return 0
end

-- ============================================================
-- POSITION
-- ============================================================

--- Get group leader position (Vec3) - first surviving unit
-- @param groupName string Group name
-- @return table|nil Vec3 position {x, y, z} or nil
function DMS.Groups.getPosition(groupName)
    local unit = firstUnit(DMS.Groups.get(groupName))
    if unit then
        local ok, p = pcall(unit.getPoint, unit)
        if ok then return p end
    end
    return nil
end

--- Get all unit positions in group
-- @param groupName string Group name
-- @return table Array of Vec3 positions
function DMS.Groups.getAllPositions(groupName)
    local positions = {}
    for _, unit in ipairs(getUnits(DMS.Groups.get(groupName))) do
        if exists(unit) then
            local ok, p = pcall(unit.getPoint, unit)
            if ok and p then
                table.insert(positions, p)
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

-- ============================================================
-- ACTIVATION / DESTRUCTION
-- ============================================================

--- Activate group (must be LATE ACTIVATION in mission editor)
-- @param groupName string Group name
-- @return boolean True if activated
function DMS.Groups.activate(groupName)
    local group = DMS.Groups.get(groupName)
    if group then
        local ok, err = pcall(trigger.action.activateGroup, group)
        if not ok then
            env.warning(string.format("[Groups] activate('%s') failed: %s", tostring(groupName), tostring(err)))
        elseif DMS.Settings and DMS.Settings.isDebug() then
            env.info(string.format("[Groups] Activated '%s'", groupName))
        end
        return ok
    end
    return false
end

--- Deactivate group
-- @param groupName string Group name
-- @return boolean True if deactivated
function DMS.Groups.deactivate(groupName)
    local group = DMS.Groups.get(groupName)
    if group then
        local ok = pcall(trigger.action.deactivateGroup, group)
        return ok
    end
    return false
end

--- Destroy group completely
-- @param groupName string Group name
-- @return boolean True if destroyed
function DMS.Groups.destroy(groupName)
    local group = DMS.Groups.get(groupName)
    if group then
        local ok = pcall(group.destroy, group)
        return ok
    end
    return false
end

-- ============================================================
-- PROPERTIES
-- ============================================================

--- Get group coalition
-- @param groupName string Group name
-- @return number|nil Coalition ID (0=neutral, 1=red, 2=blue) or nil
function DMS.Groups.getCoalition(groupName)
    local group = DMS.Groups.get(groupName)
    if group then
        local ok, c = pcall(group.getCoalition, group)
        if ok then return c end
    end
    return nil
end

--- Get group category
-- @param groupName string Group name
-- @return number|nil Category (0=airplane, 1=helicopter, 2=ground, 3=ship, 4=train)
function DMS.Groups.getCategory(groupName)
    local group = DMS.Groups.get(groupName)
    if group then
        local ok, c = pcall(group.getCategory, group)
        if ok then return c end
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
    local ok, allGroups = pcall(coalition.getGroups, coalitionId)
    if ok and allGroups then
        for _, group in ipairs(allGroups) do
            if exists(group) then
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
    local ok, allGroups = pcall(coalition.getGroups, coalitionId, category)
    if ok and allGroups then
        for _, group in ipairs(allGroups) do
            if exists(group) then
                table.insert(groups, group)
            end
        end
    end
    return groups
end

-- ============================================================
-- SPATIAL QUERIES
-- ============================================================

--- Find closest group to position from list
-- @param pos table Vec3 position
-- @param groupNames table Array of group names to check
-- @return string|nil, number Closest group name and distance (or nil)
function DMS.Groups.findClosest(pos, groupNames)
    local closest = nil
    local minDist = math.huge
    if not pos then return nil, minDist end

    for _, groupName in ipairs(groupNames or {}) do
        local groupPos = DMS.Groups.getPosition(groupName)
        if groupPos then
            local dist = dist3(pos, groupPos)
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
    if not pos or not radius then return found end

    for _, groupName in ipairs(groupNames or {}) do
        local groupPos = DMS.Groups.getPosition(groupName)
        if groupPos and dist3(groupPos, pos) <= radius then
            table.insert(found, groupName)
        end
    end

    return found
end

--- Get group speed (leader unit) in m/s
-- @param groupName string Group name
-- @return number Speed in m/s or 0
function DMS.Groups.getSpeed(groupName)
    local unit = firstUnit(DMS.Groups.get(groupName))
    if unit then
        local ok, v = pcall(unit.getVelocity, unit)
        if ok and v then
            return math.sqrt((v.x or 0) ^ 2 + (v.y or 0) ^ 2 + (v.z or 0) ^ 2)
        end
    end
    return 0
end

--- Get group heading (leader unit) in degrees
-- @param groupName string Group name
-- @return number Heading in degrees (0-360) or 0
function DMS.Groups.getHeading(groupName)
    local unit = firstUnit(DMS.Groups.get(groupName))
    if unit then
        local ok, pos = pcall(unit.getPosition, unit)
        if ok and pos and pos.x then
            -- pos.x is the forward orientation vector
            local heading = math.deg(math.atan2(pos.x.z, pos.x.x))
            if heading < 0 then
                heading = heading + 360
            end
            return heading
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

-- ============================================================
-- INITIAL SIZE TRACKING
-- ============================================================

-- Store initial group sizes for health tracking (preserved on reload)
DMS.Groups._initialSizes = DMS.Groups._initialSizes or {}

--- Record initial group size for health tracking
-- @param groupName string Group name
function DMS.Groups.recordInitialSize(groupName)
    if not groupName then return end
    DMS.Groups._initialSizes[groupName] = DMS.Groups.getAliveCount(groupName)
end

--- Get initial size (nil if not recorded)
-- @param groupName string Group name
-- @return number|nil Initial unit count
function DMS.Groups.getInitialSize(groupName)
    return DMS.Groups._initialSizes[groupName]
end

--- Record initial sizes for multiple groups
-- @param groupNames table Array of group names
function DMS.Groups.recordAllInitialSizes(groupNames)
    for _, name in ipairs(groupNames or {}) do
        DMS.Groups.recordInitialSize(name)
    end
end

--- Get group controller for AI commands
-- @param groupName string Group name
-- @return Controller|nil Controller object or nil
function DMS.Groups.getController(groupName)
    local group = DMS.Groups.get(groupName)
    if group then
        local ok, c = pcall(group.getController, group)
        if ok then return c end
    end
    return nil
end

-- Export for global access
_G.DMS = DMS
