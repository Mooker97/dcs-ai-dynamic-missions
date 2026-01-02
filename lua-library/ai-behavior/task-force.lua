-- Task Force Coordination System for DCS Missions
-- Multiple groups working together as a coordinated unit
-- Place in mission via DO SCRIPT FILE

DMS = DMS or {}
DMS.TaskForce = {}

-- Registered task forces
DMS.TaskForce.Forces = {}
DMS.TaskForce.GroupToForce = {}  -- Map group names to their task force
DMS.TaskForce.Active = false
DMS.TaskForce.TimerId = nil

-- Configuration
DMS.TaskForce.Config = {
    checkInterval = 3,
    defaultCoordRadius = 3000,      -- Coordination radius
    defaultResponseDelay = 5,        -- Seconds before coordinated response
    announceCoordination = false,    -- Debug: show coordination messages
    playerCoalition = coalition.side.BLUE,
}

--- Configure task force system
-- @param settings table Configuration overrides
function DMS.TaskForce.configure(settings)
    for key, value in pairs(settings) do
        DMS.TaskForce.Config[key] = value
    end
end

--- Create a new task force
-- @param forceId string Unique task force identifier
-- @param groupNames table Array of group names in this force
-- @param options table|nil Task force options
function DMS.TaskForce.create(forceId, groupNames, options)
    options = options or {}

    local force = {
        id = forceId,
        groups = {},
        coordRadius = options.coordRadius or DMS.TaskForce.Config.defaultCoordRadius,
        responseDelay = options.responseDelay or DMS.TaskForce.Config.defaultResponseDelay,
        alertState = "IDLE",        -- IDLE, ALERT, ENGAGED, PURSUING
        lastContactPos = nil,
        lastContactTime = 0,
        roles = options.roles or {}, -- {groupName = "assault"|"support"|"flanker"|"reserve"}
        tactics = options.tactics or "standard", -- standard, ambush, defensive
    }

    -- Register groups
    for _, groupName in ipairs(groupNames) do
        force.groups[groupName] = {
            name = groupName,
            role = options.roles and options.roles[groupName] or "assault",
            engaged = false,
            alive = true,
        }
        DMS.TaskForce.GroupToForce[groupName] = forceId
    end

    DMS.TaskForce.Forces[forceId] = force
    return force
end

--- Add group to existing task force
-- @param forceId string Task force ID
-- @param groupName string Group to add
-- @param role string|nil Role assignment
function DMS.TaskForce.addGroup(forceId, groupName, role)
    local force = DMS.TaskForce.Forces[forceId]
    if force then
        force.groups[groupName] = {
            name = groupName,
            role = role or "assault",
            engaged = false,
            alive = true,
        }
        DMS.TaskForce.GroupToForce[groupName] = forceId
    end
end

--- Get group position
-- @param groupName string Group name
-- @return table|nil Position {x, y, z}
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

--- Calculate distance between two points
-- @param pos1 table First position
-- @param pos2 table Second position
-- @return number Distance in meters
local function getDistance(pos1, pos2)
    local dx = pos1.x - pos2.x
    local dz = pos1.z - pos2.z
    return math.sqrt(dx * dx + dz * dz)
end

--- Issue attack command to group
-- @param groupName string Group name
-- @param targetPos table Target position
local function orderAttack(groupName, targetPos)
    local group = Group.getByName(groupName)
    if group and group:isExist() then
        local controller = group:getController()
        if controller then
            -- Set aggressive ROE
            controller:setOption(AI.Option.Ground.id.ROE, AI.Option.Ground.val.ROE.WEAPON_FREE)
            controller:setOption(AI.Option.Ground.id.ALARM_STATE, AI.Option.Ground.val.ALARM_STATE.RED)

            -- Create attack task toward position
            local task = {
                id = 'GoToWaypoint',
                params = {
                    x = targetPos.x,
                    y = targetPos.z,
                    speed = 20,
                }
            }
            -- Alternative: just set aggressive and let AI handle it
        end
    end
end

--- Issue support/cover command
-- @param groupName string Group name
-- @param targetPos table Position to support
local function orderSupport(groupName, targetPos)
    local group = Group.getByName(groupName)
    if group and group:isExist() then
        local controller = group:getController()
        if controller then
            controller:setOption(AI.Option.Ground.id.ROE, AI.Option.Ground.val.ROE.WEAPON_FREE)
            controller:setOption(AI.Option.Ground.id.ALARM_STATE, AI.Option.Ground.val.ALARM_STATE.RED)
        end
    end
end

--- Execute coordinated response for task force
-- @param forceId string Task force ID
-- @param contactPos table Contact position
function DMS.TaskForce.coordinatedResponse(forceId, contactPos)
    local force = DMS.TaskForce.Forces[forceId]
    if not force then return end

    force.alertState = "ENGAGED"
    force.lastContactPos = contactPos
    force.lastContactTime = timer.getTime()

    local responseCount = 0

    for groupName, groupInfo in pairs(force.groups) do
        if groupInfo.alive then
            local role = groupInfo.role

            if role == "assault" then
                -- Assault groups attack directly
                timer.scheduleFunction(function()
                    orderAttack(groupName, contactPos)
                    return nil
                end, nil, timer.getTime() + force.responseDelay)
                responseCount = responseCount + 1

            elseif role == "support" or role == "overwatch" then
                -- Support groups provide fire support from position
                timer.scheduleFunction(function()
                    orderSupport(groupName, contactPos)
                    return nil
                end, nil, timer.getTime() + force.responseDelay + 2)
                responseCount = responseCount + 1

            elseif role == "flanker" then
                -- Flankers move to flank position (handled by flanking.lua if loaded)
                timer.scheduleFunction(function()
                    if DMS.Flanking then
                        DMS.Flanking.executeFlank(groupName, contactPos)
                    else
                        orderAttack(groupName, contactPos)
                    end
                    return nil
                end, nil, timer.getTime() + force.responseDelay + 5)
                responseCount = responseCount + 1

            elseif role == "reserve" then
                -- Reserve waits longer before committing
                timer.scheduleFunction(function()
                    orderAttack(groupName, contactPos)
                    return nil
                end, nil, timer.getTime() + force.responseDelay + 15)
            end
        end
    end

    if DMS.TaskForce.Config.announceCoordination then
        trigger.action.outText(string.format(
            "[TaskForce] %s: Coordinated response - %d groups engaging",
            forceId, responseCount
        ), 10)
    end
end

--- Alert entire task force to contact
-- @param forceId string Task force ID
-- @param contactPos table Contact position
function DMS.TaskForce.alertForce(forceId, contactPos)
    local force = DMS.TaskForce.Forces[forceId]
    if not force or force.alertState == "ENGAGED" then return end

    force.alertState = "ALERT"
    force.lastContactPos = contactPos
    force.lastContactTime = timer.getTime()

    -- Set all groups to alert state
    for groupName, _ in pairs(force.groups) do
        local group = Group.getByName(groupName)
        if group and group:isExist() then
            local controller = group:getController()
            if controller then
                controller:setOption(AI.Option.Ground.id.ALARM_STATE, AI.Option.Ground.val.ALARM_STATE.RED)
            end
        end
    end
end

--- Event handler for detecting engagement
DMS.TaskForce.EventHandler = {
    onEvent = function(self, event)
        -- Track when task force groups are engaged
        if event.id == world.event.S_EVENT_SHOT or
           event.id == world.event.S_EVENT_HIT then

            local initiator = event.initiator
            if not initiator then return end

            local group = initiator:getGroup()
            if not group then return end

            local groupName = group:getName()
            local forceId = DMS.TaskForce.GroupToForce[groupName]

            if forceId then
                local force = DMS.TaskForce.Forces[forceId]
                local groupInfo = force.groups[groupName]

                if groupInfo and not groupInfo.engaged then
                    groupInfo.engaged = true

                    -- Get target position for coordination
                    local targetPos = nil
                    if event.target then
                        targetPos = event.target:getPoint()
                    else
                        targetPos = initiator:getPoint()
                    end

                    -- Coordinate response
                    DMS.TaskForce.coordinatedResponse(forceId, targetPos)
                end
            end
        end

        -- Track group destruction
        if event.id == world.event.S_EVENT_DEAD then
            local unit = event.initiator
            if unit then
                local group = unit:getGroup()
                if group then
                    local groupName = group:getName()
                    local forceId = DMS.TaskForce.GroupToForce[groupName]
                    if forceId then
                        local force = DMS.TaskForce.Forces[forceId]
                        if force and force.groups[groupName] then
                            -- Check if group still has units
                            local units = group:getUnits()
                            local alive = false
                            if units then
                                for _, u in ipairs(units) do
                                    if u:isExist() and u:getLife() > 1 then
                                        alive = true
                                        break
                                    end
                                end
                            end
                            force.groups[groupName].alive = alive
                        end
                    end
                end
            end
        end
    end
}

--- Start task force system
function DMS.TaskForce.start()
    if DMS.TaskForce.Active then return end

    DMS.TaskForce.Active = true
    world.addEventHandler(DMS.TaskForce.EventHandler)
end

--- Stop task force system
function DMS.TaskForce.stop()
    DMS.TaskForce.Active = false
end

--- Get task force status
-- @param forceId string Task force ID
-- @return table|nil Status info
function DMS.TaskForce.getStatus(forceId)
    local force = DMS.TaskForce.Forces[forceId]
    if not force then return nil end

    local alive, engaged = 0, 0
    for _, groupInfo in pairs(force.groups) do
        if groupInfo.alive then alive = alive + 1 end
        if groupInfo.engaged then engaged = engaged + 1 end
    end

    return {
        id = force.id,
        alertState = force.alertState,
        groupsAlive = alive,
        groupsEngaged = engaged,
        lastContact = force.lastContactPos,
    }
end

--- Reset task force state
-- @param forceId string Task force ID
function DMS.TaskForce.reset(forceId)
    local force = DMS.TaskForce.Forces[forceId]
    if force then
        force.alertState = "IDLE"
        force.lastContactPos = nil
        for _, groupInfo in pairs(force.groups) do
            groupInfo.engaged = false
        end
    end
end

--[[
USAGE EXAMPLE:

-- Create a coordinated task force
DMS.TaskForce.create("ambush-team",
    {"Armor-1", "Infantry-1", "AA-1", "Reserve-1"},
    {
        roles = {
            ["Armor-1"] = "assault",
            ["Infantry-1"] = "flanker",
            ["AA-1"] = "support",
            ["Reserve-1"] = "reserve",
        },
        tactics = "ambush",
        responseDelay = 3,
    }
)

-- Start the system
DMS.TaskForce.start()

-- When Armor-1 engages, the entire team responds:
-- - Armor-1 continues assault
-- - Infantry-1 flanks after 5 seconds
-- - AA-1 provides support fire
-- - Reserve-1 commits after 15 seconds if needed

-- Check status
local status = DMS.TaskForce.getStatus("ambush-team")
]]

-- Export
_G.DMS = DMS
