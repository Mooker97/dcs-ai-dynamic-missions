-- Flanking Maneuver System for DCS Missions
-- AI groups execute flanking movements around targets
-- Place in mission via DO SCRIPT FILE

DMS = DMS or {}
DMS.Flanking = {}

-- Active flanking maneuvers
DMS.Flanking.Maneuvers = {}

-- Configuration
DMS.Flanking.Config = {
    defaultFlankDistance = 500,     -- Distance to flank (meters)
    defaultFlankAngle = 90,         -- Angle of flank (degrees)
    defaultApproachSpeed = 30,      -- Speed during flank (kph)
    executionTime = 30,             -- Time to reach flank position (seconds)
    announceManeuvers = false,      -- Debug output
}

--- Configure flanking system
-- @param settings table Configuration overrides
function DMS.Flanking.configure(settings)
    for key, value in pairs(settings) do
        DMS.Flanking.Config[key] = value
    end
end

--- Calculate flank position
-- @param originPos table Origin position (flanking unit)
-- @param targetPos table Target position
-- @param distance number Flank distance
-- @param angle number Flank angle in degrees (90 = perpendicular)
-- @param side string "left" or "right"
-- @return table Flank position {x, z}
local function calculateFlankPosition(originPos, targetPos, distance, angle, side)
    -- Calculate bearing from origin to target
    local dx = targetPos.x - originPos.x
    local dz = targetPos.z - originPos.z
    local bearing = math.atan2(dz, dx)

    -- Calculate flank angle
    local flankAngleRad = math.rad(angle)
    if side == "left" then
        flankAngleRad = -flankAngleRad
    end

    -- Calculate flank position
    local flankBearing = bearing + flankAngleRad
    local flankX = targetPos.x + distance * math.cos(flankBearing)
    local flankZ = targetPos.z + distance * math.sin(flankBearing)

    return {x = flankX, z = flankZ}
end

--- Get group position
-- @param groupName string Group name
-- @return table|nil Position
local function getGroupPosition(groupName)
    local group = Group.getByName(groupName)
    if group and group:isExist() then
        local units = group:getUnits()
        if units and #units > 0 and units[1]:isExist() then
            return units[1]:getPoint()
        end
    end
    return nil
end

--- Execute flanking maneuver
-- @param groupName string Group to flank
-- @param targetPos table Target position to flank
-- @param options table|nil Flank options
function DMS.Flanking.executeFlank(groupName, targetPos, options)
    options = options or {}

    local group = Group.getByName(groupName)
    if not group or not group:isExist() then return false end

    local originPos = getGroupPosition(groupName)
    if not originPos then return false end

    local distance = options.distance or DMS.Flanking.Config.defaultFlankDistance
    local angle = options.angle or DMS.Flanking.Config.defaultFlankAngle
    local side = options.side or (math.random() > 0.5 and "left" or "right")
    local speed = options.speed or DMS.Flanking.Config.defaultApproachSpeed

    -- Calculate flank position
    local flankPos = calculateFlankPosition(originPos, targetPos, distance, angle, side)

    -- Store maneuver info
    DMS.Flanking.Maneuvers[groupName] = {
        targetPos = targetPos,
        flankPos = flankPos,
        side = side,
        startTime = timer.getTime(),
        phase = "moving", -- moving, flanking, attacking
    }

    -- Set group to move to flank position
    local controller = group:getController()
    if controller then
        -- Set alert but hold fire during movement
        controller:setOption(AI.Option.Ground.id.ALARM_STATE, AI.Option.Ground.val.ALARM_STATE.RED)
        controller:setOption(AI.Option.Ground.id.ROE, AI.Option.Ground.val.ROE.RETURN_FIRE)

        -- Move to flank position
        local mission = {
            id = 'Mission',
            params = {
                route = {
                    points = {
                        [1] = {
                            x = flankPos.x,
                            y = flankPos.z,
                            type = "Turning Point",
                            action = "Off Road",
                            speed = speed / 3.6,  -- Convert to m/s
                        }
                    }
                }
            }
        }
        controller:setTask(mission)
    end

    -- Schedule attack phase
    timer.scheduleFunction(function()
        DMS.Flanking.executeAttack(groupName, targetPos)
        return nil
    end, nil, timer.getTime() + DMS.Flanking.Config.executionTime)

    if DMS.Flanking.Config.announceManeuvers then
        trigger.action.outText(string.format(
            "[Flanking] %s executing %s flank",
            groupName, side
        ), 10)
    end

    return true
end

--- Execute attack after flanking
-- @param groupName string Group name
-- @param targetPos table Target position
function DMS.Flanking.executeAttack(groupName, targetPos)
    local group = Group.getByName(groupName)
    if not group or not group:isExist() then return end

    local maneuver = DMS.Flanking.Maneuvers[groupName]
    if maneuver then
        maneuver.phase = "attacking"
    end

    local controller = group:getController()
    if controller then
        -- Go weapons free
        controller:setOption(AI.Option.Ground.id.ROE, AI.Option.Ground.val.ROE.WEAPON_FREE)

        -- Attack toward target
        local mission = {
            id = 'Mission',
            params = {
                route = {
                    points = {
                        [1] = {
                            x = targetPos.x,
                            y = targetPos.z,
                            type = "Turning Point",
                            action = "Off Road",
                            speed = 15,
                        }
                    }
                }
            }
        }
        controller:setTask(mission)
    end

    if DMS.Flanking.Config.announceManeuvers then
        trigger.action.outText(string.format(
            "[Flanking] %s attacking from flank!",
            groupName
        ), 10)
    end
end

--- Execute pincer movement (two groups flank from opposite sides)
-- @param group1 string First flanking group
-- @param group2 string Second flanking group
-- @param targetPos table Target position
-- @param options table|nil Options
function DMS.Flanking.executePincer(group1, group2, targetPos, options)
    options = options or {}

    DMS.Flanking.executeFlank(group1, targetPos, {
        side = "left",
        distance = options.distance,
        angle = options.angle,
    })

    DMS.Flanking.executeFlank(group2, targetPos, {
        side = "right",
        distance = options.distance,
        angle = options.angle,
    })
end

--- Execute envelopment (multiple groups surround target)
-- @param groupNames table Array of group names
-- @param targetPos table Target position
-- @param options table|nil Options
function DMS.Flanking.executeEnvelopment(groupNames, targetPos, options)
    options = options or {}
    local distance = options.distance or DMS.Flanking.Config.defaultFlankDistance

    local numGroups = #groupNames
    local angleStep = 360 / numGroups

    for i, groupName in ipairs(groupNames) do
        local angle = (i - 1) * angleStep
        DMS.Flanking.executeFlank(groupName, targetPos, {
            angle = angle,
            distance = distance,
            side = "right",  -- Angle determines position
        })
    end
end

--- Cancel flanking maneuver
-- @param groupName string Group name
function DMS.Flanking.cancel(groupName)
    DMS.Flanking.Maneuvers[groupName] = nil

    local group = Group.getByName(groupName)
    if group and group:isExist() then
        local controller = group:getController()
        if controller then
            controller:resetTask()
        end
    end
end

--- Get maneuver status
-- @param groupName string Group name
-- @return table|nil Maneuver status
function DMS.Flanking.getStatus(groupName)
    return DMS.Flanking.Maneuvers[groupName]
end

--[[
USAGE EXAMPLE:

-- Configure
DMS.Flanking.configure({
    defaultFlankDistance = 600,
    defaultFlankAngle = 90,
    announceManeuvers = true,
})

-- Single flank maneuver
local targetPos = {x = -50000, z = 40000}
DMS.Flanking.executeFlank("Infantry-1", targetPos, {
    side = "left",
    distance = 500,
})

-- Pincer movement (two groups)
DMS.Flanking.executePincer("Infantry-1", "Infantry-2", targetPos)

-- Full envelopment (surround target)
DMS.Flanking.executeEnvelopment(
    {"Squad-1", "Squad-2", "Squad-3", "Squad-4"},
    targetPos,
    {distance = 400}
)

-- Integrate with TaskForce system
-- When TaskForce assigns "flanker" role, it calls:
-- DMS.Flanking.executeFlank(groupName, contactPos)
]]

-- Export
_G.DMS = DMS
