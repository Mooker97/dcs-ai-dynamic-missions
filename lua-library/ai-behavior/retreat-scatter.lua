-- Retreat and Scatter Behavior for DCS Missions
-- Damaged units flee instead of fighting to death
-- Requires: utils/coordinates.lua, utils/group-utils.lua
-- Place in mission via DO SCRIPT FILE

DMS = DMS or {}
DMS.Retreat = {}

-- Tracked groups
DMS.Retreat.Groups = {}
DMS.Retreat.TimerId = nil
DMS.Retreat.Active = false

-- Configuration
DMS.Retreat.Config = {
    checkInterval = 5,           -- Seconds between health checks
    defaultRetreatThreshold = 50, -- Health % to trigger retreat
    defaultScatterRadius = 2000,  -- Meters to scatter from current position
    retreatSpeed = 20,           -- Speed in m/s for retreating
    announceRetreats = false,    -- Show retreat messages
}

-- Retreat destinations
DMS.Retreat.Destinations = {}

--- Configure retreat system
-- @param settings table Configuration overrides
function DMS.Retreat.configure(settings)
    for key, value in pairs(settings) do
        DMS.Retreat.Config[key] = value
    end
end

--- Add a retreat destination point
-- @param name string Destination name
-- @param x number X coordinate
-- @param z number Z coordinate
function DMS.Retreat.addDestination(name, x, z)
    DMS.Retreat.Destinations[name] = {x = x, z = z}
end

--- Register a group for retreat behavior
-- @param groupName string Group name
-- @param retreatThreshold number|nil Health % to trigger retreat
-- @param destination string|nil Named destination or "scatter"
function DMS.Retreat.register(groupName, retreatThreshold, destination)
    -- Record initial size for percentage calculation
    local group = Group.getByName(groupName)
    local initialSize = 0
    if group then
        local units = group:getUnits()
        if units then
            initialSize = #units
        end
    end

    DMS.Retreat.Groups[groupName] = {
        name = groupName,
        threshold = retreatThreshold or DMS.Retreat.Config.defaultRetreatThreshold,
        destination = destination or "scatter",
        initialSize = initialSize,
        retreating = false,
        destroyed = false,
    }
end

--- Register multiple groups
-- @param groupNames table Array of group names
-- @param retreatThreshold number|nil Shared threshold
-- @param destination string|nil Shared destination
function DMS.Retreat.registerBulk(groupNames, retreatThreshold, destination)
    for _, name in ipairs(groupNames) do
        DMS.Retreat.register(name, retreatThreshold, destination)
    end
end

--- Get group health percentage
-- @param groupName string Group name
-- @param initialSize number Original unit count
-- @return number Health percentage (0-100)
local function getGroupHealth(groupName, initialSize)
    local group = Group.getByName(groupName)
    if not group or not group:isExist() then
        return 0
    end

    local units = group:getUnits()
    if not units then
        return 0
    end

    local aliveCount = 0
    for _, unit in ipairs(units) do
        if unit:isExist() and unit:getLife() >= 1 then
            aliveCount = aliveCount + 1
        end
    end

    if initialSize > 0 then
        return (aliveCount / initialSize) * 100
    end
    return 0
end

--- Get scatter position from current location
-- @param currentX number Current X
-- @param currentZ number Current Z
-- @return number, number New X, Z
local function getScatterPosition(currentX, currentZ)
    local angle = math.random() * 2 * math.pi
    local dist = DMS.Retreat.Config.defaultScatterRadius * (0.5 + math.random() * 0.5)

    local newX = currentX + dist * math.cos(angle)
    local newZ = currentZ + dist * math.sin(angle)

    return newX, newZ
end

local function debugLog(fmt, ...)
    if DMS.Settings and DMS.Settings.isDebug() then
        env.info(string.format("[Retreat] " .. fmt, ...))
    end
end

--- Command group to retreat
-- Builds a real two-point ground route: current position -> destination.
-- @param groupName string Group name
-- @param destX number Destination X (DCS map x)
-- @param destZ number Destination Z (DCS vec3.z, route y)
local function commandRetreat(groupName, destX, destZ)
    local group = Group.getByName(groupName)
    if not group or not group:isExist() then
        return false
    end

    local units = group:getUnits()
    if not units or #units == 0 then
        return false
    end
    local startPos = units[1]:getPoint()

    local controller = group:getController()
    if not controller then
        return false
    end

    -- Hold fire and retreat
    controller:setOption(AI.Option.Ground.id.ROE, AI.Option.Ground.val.ROE.WEAPON_HOLD)
    controller:setOption(AI.Option.Ground.id.ALARM_STATE, AI.Option.Ground.val.ALARM_STATE.GREEN)

    local speed = DMS.Retreat.Config.retreatSpeed
    local retreatTask = {
        id = 'Mission',
        params = {
            route = {
                points = {
                    [1] = {
                        type = "Turning Point",
                        action = "Off Road",
                        x = startPos.x,
                        y = startPos.z,
                        speed = speed,
                        ETA = 0,
                        ETA_locked = false,
                        speed_locked = true,
                    },
                    [2] = {
                        type = "Turning Point",
                        action = "Off Road",
                        x = destX,
                        y = destZ,
                        speed = speed,
                        ETA = 0,
                        ETA_locked = false,
                        speed_locked = true,
                    },
                }
            }
        }
    }

    controller:setTask(retreatTask)
    debugLog("Group '%s' retreating to (%.0f, %.0f)", groupName, destX, destZ)
    return true
end

--- Check one registered group and trigger retreat if needed
local function checkGroup(groupName, config)
    if config.destroyed or config.retreating then
        return
    end

    local health = getGroupHealth(groupName, config.initialSize)

    if health <= 0 then
        config.destroyed = true
        debugLog("Group '%s' destroyed", groupName)
        return
    end

    if health <= config.threshold then
        -- Trigger retreat!
        config.retreating = true

        local destX, destZ

        if config.destination == "scatter" then
            local group = Group.getByName(groupName)
            if group and group:isExist() then
                local units = group:getUnits()
                if units and #units > 0 then
                    local pos = units[1]:getPoint()
                    destX, destZ = getScatterPosition(pos.x, pos.z)
                end
            end
        else
            local dest = DMS.Retreat.Destinations[config.destination]
            if dest then
                destX, destZ = dest.x, dest.z
            else
                debugLog("Group '%s' has unknown destination '%s'", groupName, tostring(config.destination))
            end
        end

        if destX and destZ then
            debugLog("Group '%s' health %.0f%% <= %d%%, retreating", groupName, health, config.threshold)
            commandRetreat(groupName, destX, destZ)

            if DMS.Retreat.Config.announceRetreats then
                trigger.action.outText("Enemy forces are retreating!", 5, true)
            end
        end
    end
end

--- Process retreat checks
local function processRetreatCheck(_, time)
    if not DMS.Retreat.Active then
        return nil
    end

    local ok, err = pcall(function()
        for groupName, config in pairs(DMS.Retreat.Groups) do
            checkGroup(groupName, config)
        end
    end)
    if not ok then
        env.error(string.format("[Retreat] processRetreatCheck error: %s", tostring(err)))
    end

    return time + DMS.Retreat.Config.checkInterval
end

--- Start retreat monitoring
function DMS.Retreat.start()
    if DMS.Retreat.Active then
        return
    end

    DMS.Retreat.Active = true
    DMS.Retreat.TimerId = timer.scheduleFunction(
        processRetreatCheck,
        nil,
        timer.getTime() + DMS.Retreat.Config.checkInterval
    )
    debugLog("Started monitoring (interval: %ds)", DMS.Retreat.Config.checkInterval)
end

--- Stop retreat monitoring
function DMS.Retreat.stop()
    DMS.Retreat.Active = false
    if DMS.Retreat.TimerId then
        timer.removeFunction(DMS.Retreat.TimerId)
        DMS.Retreat.TimerId = nil
    end
end

--- Force a group to retreat
-- @param groupName string Group name
function DMS.Retreat.forceRetreat(groupName)
    local config = DMS.Retreat.Groups[groupName]
    if config and not config.retreating then
        config.retreating = true

        local group = Group.getByName(groupName)
        if group and group:isExist() then
            local units = group:getUnits()
            if units and #units > 0 then
                local pos = units[1]:getPoint()
                local destX, destZ = getScatterPosition(pos.x, pos.z)
                commandRetreat(groupName, destX, destZ)
            end
        end
    end
end

--- Scatter all ground groups near a point
-- Each group within radius is routed (two-point route) away from the point.
-- @param point table Position {x, z} (vec3) or {x, y} (vec2 map coords)
-- @param radius number|nil Search radius in meters (default: defaultScatterRadius)
-- @param coalitionId number|nil Coalition to scatter (default: coalition.side.RED, the enemy side)
-- @return number Number of groups scattered
function DMS.Retreat.scatterNear(point, radius, coalitionId)
    if not point or not point.x then return 0 end
    radius = radius or DMS.Retreat.Config.defaultScatterRadius
    local px = point.x
    local pz = point.z or point.y or 0
    local scattered = 0

    local sides = {coalitionId or coalition.side.RED}

    for _, side in ipairs(sides) do
        local groups = coalition.getGroups(side, Group.Category.GROUND) or {}
        for _, group in ipairs(groups) do
            if group and group:isExist() then
                local units = group:getUnits()
                if units and #units > 0 then
                    local pos = units[1]:getPoint()
                    local dx = pos.x - px
                    local dz = pos.z - pz
                    local dist = math.sqrt(dx * dx + dz * dz)
                    if dist <= radius then
                        -- Flee away from the point (random direction if on top of it)
                        local angle
                        if dist < 1 then
                            angle = math.random() * 2 * math.pi
                        else
                            angle = math.atan2(dz, dx) + (math.random() - 0.5) * (math.pi / 2)
                        end
                        local fleeDist = DMS.Retreat.Config.defaultScatterRadius * (0.5 + math.random() * 0.5)
                        local destX = pos.x + fleeDist * math.cos(angle)
                        local destZ = pos.z + fleeDist * math.sin(angle)
                        local name = group:getName()
                        if commandRetreat(name, destX, destZ) then
                            scattered = scattered + 1
                            local cfg = DMS.Retreat.Groups[name]
                            if cfg then cfg.retreating = true end
                        end
                    end
                end
            end
        end
    end

    debugLog("scatterNear (%.0f, %.0f) r=%.0f scattered %d groups", px, pz, radius, scattered)
    return scattered
end

--- Get retreat statistics
-- @return table {total, retreating, destroyed, fighting}
function DMS.Retreat.getStats()
    local retreating, destroyed, fighting = 0, 0, 0

    for _, config in pairs(DMS.Retreat.Groups) do
        if config.destroyed then
            destroyed = destroyed + 1
        elseif config.retreating then
            retreating = retreating + 1
        else
            fighting = fighting + 1
        end
    end

    local total = 0
    for _ in pairs(DMS.Retreat.Groups) do
        total = total + 1
    end

    return {
        total = total,
        retreating = retreating,
        destroyed = destroyed,
        fighting = fighting
    }
end

--[[
USAGE EXAMPLE:

-- Configure
DMS.Retreat.configure({
    checkInterval = 3,
    defaultRetreatThreshold = 40,  -- Retreat at 40% health
    defaultScatterRadius = 3000,
    announceRetreats = true
})

-- Add retreat destinations
DMS.Retreat.addDestination("enemy_base", -70000, 50000)
DMS.Retreat.addDestination("rally_point", -65000, 45000)

-- Register groups
DMS.Retreat.register("Patrol-1", 50, "scatter")  -- Scatter at 50%
DMS.Retreat.register("Garrison-1", 30, "enemy_base")  -- Retreat to base at 30%

-- Bulk register
DMS.Retreat.registerBulk(
    {"Convoy-1", "Convoy-2", "Convoy-3"},
    40,
    "rally_point"
)

-- Start monitoring
DMS.Retreat.start()

-- Force retreat
DMS.Retreat.forceRetreat("Patrol-1")

-- Check status
local stats = DMS.Retreat.getStats()
trigger.action.outText("Fighting: " .. stats.fighting .. ", Retreating: " .. stats.retreating, 10)
]]

-- Export
_G.DMS = DMS
