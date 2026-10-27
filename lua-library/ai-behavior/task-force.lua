-- Task Force Coordination System for DCS Missions
-- Multiple ground groups working together as a coordinated unit
-- Place in mission via DO SCRIPT FILE
-- Optional: ai-behavior/flanking.lua, utils/mission-settings.lua, utils/error-handler.lua

DMS = DMS or {}
DMS.TaskForce = {}

-- Registered task forces
DMS.TaskForce.Forces = {}
DMS.TaskForce.GroupToForce = {}  -- Map group names to their task force
DMS.TaskForce.Active = false
DMS.TaskForce.HandlerAdded = false
DMS.TaskForce.TimerId = nil

-- Configuration
DMS.TaskForce.Config = {
    checkInterval = 3,
    defaultCoordRadius = 3000,      -- Coordination radius
    defaultResponseDelay = 5,        -- Seconds before coordinated response
    announceCoordination = false,    -- On-screen coordination messages
    playerCoalition = coalition.side.BLUE,
    assaultSpeed = 10,               -- m/s
    assaultAction = "Off Road",      -- Route action for assault ("Off Road", "Rank", "Vee", ...)
    artilleryRounds = 10,            -- FireAtPoint expendQty for support groups with artillery
    artilleryRadius = 150,           -- FireAtPoint radius
}

-- ============================================================
-- INTERNAL HELPERS
-- ============================================================

local function logDebug(fmt, ...)
    if DMS.Settings and DMS.Settings.isDebug and DMS.Settings.isDebug() then
        env.info(string.format("[TaskForce] " .. fmt, ...))
    end
end

local function logError(context, err)
    local msg = tostring(err)
    if DMS.Error and DMS.Error.log then
        if pcall(DMS.Error.log, "TaskForce." .. context, msg) then return end
    end
    env.error(string.format("[DMS LUA ERROR] TaskForce.%s: %s", context, msg))
end

local function safeScheduleOnce(context, func, delay)
    return timer.scheduleFunction(function(_, time)
        local ok, err = pcall(func, time)
        if not ok then logError(context, err) end
        return nil
    end, nil, timer.getTime() + delay)
end

local function getLeadUnit(group)
    if not group or not group:isExist() then return nil end
    local units = group:getUnits()
    if not units then return nil end
    for _, u in ipairs(units) do
        if u and u:isExist() then return u end
    end
    return nil
end

local function isGroundGroup(group)
    local ok, cat = pcall(group.getCategory, group)
    return ok and cat == Group.Category.GROUND
end

local function makeGroundPoint(x, z, speed, action)
    return {
        x = x, y = z,   -- route y = Vec3.z
        alt = land.getHeight({x = x, y = z}), alt_type = "BARO",
        type = "Turning Point", action = action or "Off Road",
        speed = speed, speed_locked = true,
        ETA = 0, ETA_locked = false,
        formation_template = "",
        task = {id = "ComboTask", params = {tasks = {}}},
    }
end

--- Route a ground group from its current position through {x, z} waypoints
local function routeGroundGroup(group, waypoints, speed, action)
    if not isGroundGroup(group) then return false end
    local lead = getLeadUnit(group)
    if not lead then return false end
    local cur = lead:getPoint()
    local points = {makeGroundPoint(cur.x, cur.z, speed, action)}
    for _, wp in ipairs(waypoints) do
        points[#points + 1] = makeGroundPoint(wp.x, wp.z, speed, action)
    end
    local controller = group:getController()
    if not controller or #points < 2 then return false end
    local ok, err = pcall(controller.setTask, controller,
        {id = "Mission", params = {route = {points = points}}})
    if not ok then
        logError("routeGroundGroup", err)
        return false
    end
    return true
end

local function setGroundEngage(controller)
    controller:setOption(AI.Option.Ground.id.ROE, AI.Option.Ground.val.ROE.OPEN_FIRE)
    controller:setOption(AI.Option.Ground.id.ALARM_STATE, AI.Option.Ground.val.ALARM_STATE.RED)
end

--- True if any living unit has an indirect-fire attribute
local function hasArtillery(group)
    local units = group:getUnits() or {}
    for _, u in ipairs(units) do
        if u and u:isExist() then
            local ok1, art = pcall(u.hasAttribute, u, "Artillery")
            local ok2, mlrs = pcall(u.hasAttribute, u, "MLRS")
            if (ok1 and art) or (ok2 and mlrs) then return true end
        end
    end
    return false
end

-- ============================================================
-- PUBLIC API
-- ============================================================

--- Configure task force system
function DMS.TaskForce.configure(settings)
    for key, value in pairs(settings) do
        DMS.TaskForce.Config[key] = value
    end
end

--- Create a new task force
-- @param forceId string Unique task force identifier
-- @param groupNames table Array of group names in this force
-- @param options table|nil {coordRadius, responseDelay, roles, tactics}
function DMS.TaskForce.create(forceId, groupNames, options)
    options = options or {}

    local force = {
        id = forceId,
        groups = {},
        coordRadius = options.coordRadius or DMS.TaskForce.Config.defaultCoordRadius,
        responseDelay = options.responseDelay or DMS.TaskForce.Config.defaultResponseDelay,
        alertState = "IDLE",        -- IDLE, ALERT, ENGAGED
        lastContactPos = nil,
        lastContactTime = 0,
        roles = options.roles or {}, -- {groupName = "assault"|"support"|"flanker"|"reserve"}
        tactics = options.tactics or "standard",
    }

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
    logDebug("Created task force '%s' (%d groups)", forceId, #groupNames)
    return force
end

--- Add group to existing task force
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

--- Order a ground group to assault a position (route + ROE OPEN_FIRE + alarm RED)
local function orderAttack(groupName, targetPos)
    local group = Group.getByName(groupName)
    if not getLeadUnit(group) then return end
    if not isGroundGroup(group) then
        logDebug("'%s' is not a ground group - assault order skipped", groupName)
        return
    end

    local controller = group:getController()
    if not controller then return end
    setGroundEngage(controller)

    local cfg = DMS.TaskForce.Config
    if routeGroundGroup(group, {{x = targetPos.x, z = targetPos.z}}, cfg.assaultSpeed, cfg.assaultAction) then
        logDebug("'%s' assaulting (%.0f, %.0f)", groupName, targetPos.x, targetPos.z)
    end
end

--- Order a group to support from its current position
-- Artillery/MLRS groups get a FireAtPoint mission on the contact; others hold and engage.
local function orderSupport(groupName, targetPos)
    local group = Group.getByName(groupName)
    if not getLeadUnit(group) or not isGroundGroup(group) then return end

    local controller = group:getController()
    if not controller then return end
    setGroundEngage(controller)

    if hasArtillery(group) then
        local cfg = DMS.TaskForce.Config
        controller:pushTask({
            id = "FireAtPoint",
            params = {
                point = {x = targetPos.x, y = targetPos.z},
                radius = cfg.artilleryRadius,
                expendQty = cfg.artilleryRounds,
                expendQtyEnabled = true,
            },
        })
        logDebug("'%s' firing support at (%.0f, %.0f)", groupName, targetPos.x, targetPos.z)
    else
        logDebug("'%s' providing overwatch (OPEN_FIRE / RED)", groupName)
    end
end

--- Execute coordinated response for task force
-- @param forceId string Task force ID
-- @param contactPos table Contact position (Vec3)
function DMS.TaskForce.coordinatedResponse(forceId, contactPos)
    local force = DMS.TaskForce.Forces[forceId]
    if not force or not contactPos then return end

    force.alertState = "ENGAGED"
    force.lastContactPos = contactPos
    force.lastContactTime = timer.getTime()

    local responseCount = 0

    for groupName, groupInfo in pairs(force.groups) do
        if groupInfo.alive then
            local role = groupInfo.role

            if role == "assault" then
                safeScheduleOnce("orderAttack", function()
                    orderAttack(groupName, contactPos)
                end, force.responseDelay)
                responseCount = responseCount + 1

            elseif role == "support" or role == "overwatch" then
                safeScheduleOnce("orderSupport", function()
                    orderSupport(groupName, contactPos)
                end, force.responseDelay + 2)
                responseCount = responseCount + 1

            elseif role == "flanker" then
                safeScheduleOnce("orderFlank", function()
                    local flanked = false
                    if DMS.Flanking and DMS.Flanking.executeFlank then
                        flanked = DMS.Flanking.executeFlank(groupName, contactPos)
                    end
                    if not flanked then
                        orderAttack(groupName, contactPos)
                    end
                end, force.responseDelay + 5)
                responseCount = responseCount + 1

            elseif role == "reserve" then
                safeScheduleOnce("orderReserve", function()
                    orderAttack(groupName, contactPos)
                end, force.responseDelay + 15)
            end
        end
    end

    logDebug("'%s' coordinated response - %d groups engaging (%.0f, %.0f)",
        forceId, responseCount, contactPos.x, contactPos.z)

    if DMS.TaskForce.Config.announceCoordination then
        trigger.action.outText(string.format(
            "[TaskForce] %s: Coordinated response - %d groups engaging",
            forceId, responseCount
        ), 10)
    end
end

--- Alert entire task force to contact
function DMS.TaskForce.alertForce(forceId, contactPos)
    local force = DMS.TaskForce.Forces[forceId]
    if not force or force.alertState == "ENGAGED" then return end

    force.alertState = "ALERT"
    force.lastContactPos = contactPos
    force.lastContactTime = timer.getTime()

    for groupName, _ in pairs(force.groups) do
        local group = Group.getByName(groupName)
        if getLeadUnit(group) and isGroundGroup(group) then
            local controller = group:getController()
            if controller then
                controller:setOption(AI.Option.Ground.id.ALARM_STATE, AI.Option.Ground.val.ALARM_STATE.RED)
            end
        end
    end
    logDebug("'%s' state changed to ALERT", forceId)
end

--- Mark a force member engaged and trigger coordination (once per member)
local function onMemberContact(groupName, contactPos)
    local forceId = DMS.TaskForce.GroupToForce[groupName]
    if not forceId or not contactPos then return end
    local force = DMS.TaskForce.Forces[forceId]
    if not force then return end
    local groupInfo = force.groups[groupName]
    if groupInfo and not groupInfo.engaged then
        groupInfo.engaged = true
        logDebug("'%s' (force '%s') in contact", groupName, forceId)
        DMS.TaskForce.coordinatedResponse(forceId, contactPos)
    end
end

local function getObjectGroupName(obj)
    if not obj or not obj.getGroup then return nil end
    local ok, group = pcall(obj.getGroup, obj)
    if ok and group then
        local ok2, name = pcall(group.getName, group)
        if ok2 then return name end
    end
    return nil
end

local function getObjectPoint(obj)
    if not obj or not obj.isExist then return nil end
    local ok, exists = pcall(obj.isExist, obj)
    if ok and exists then return obj:getPoint() end
    return nil
end

--- Handle events (internal)
local function handleEvent(event)
    if not DMS.TaskForce.Active then return end

    if event.id == world.event.S_EVENT_SHOT or event.id == world.event.S_EVENT_HIT then
        -- Member fired / scored a hit: contact is the target (or the shooter if unknown)
        local initiatorGroup = getObjectGroupName(event.initiator)
        if initiatorGroup and DMS.TaskForce.GroupToForce[initiatorGroup] then
            local contactPos = getObjectPoint(event.target) or getObjectPoint(event.initiator)
            onMemberContact(initiatorGroup, contactPos)
        end

        -- Member was hit: contact is the shooter
        if event.id == world.event.S_EVENT_HIT then
            local targetGroup = getObjectGroupName(event.target)
            if targetGroup and DMS.TaskForce.GroupToForce[targetGroup] then
                local contactPos = getObjectPoint(event.initiator) or getObjectPoint(event.target)
                onMemberContact(targetGroup, contactPos)
            end
        end
    end

    if event.id == world.event.S_EVENT_DEAD or event.id == world.event.S_EVENT_UNIT_LOST then
        local groupName = getObjectGroupName(event.initiator)
        local forceId = groupName and DMS.TaskForce.GroupToForce[groupName]
        if forceId then
            local force = DMS.TaskForce.Forces[forceId]
            if force and force.groups[groupName] then
                local group = Group.getByName(groupName)
                local alive = false
                if group and group:isExist() then
                    for _, u in ipairs(group:getUnits() or {}) do
                        if u and u:isExist() and u:getLife() > 1 then
                            alive = true
                            break
                        end
                    end
                end
                if force.groups[groupName].alive and not alive then
                    logDebug("'%s' (force '%s') destroyed", groupName, forceId)
                end
                force.groups[groupName].alive = alive
            end
        end
    end
end

--- Event handler (pcall-guarded)
DMS.TaskForce.EventHandler = {
    onEvent = function(self, event)
        local ok, err = pcall(handleEvent, event)
        if not ok then logError("onEvent", err) end
    end
}

--- Start task force system
function DMS.TaskForce.start()
    if DMS.TaskForce.Active then return end

    DMS.TaskForce.Active = true
    if not DMS.TaskForce.HandlerAdded then
        world.addEventHandler(DMS.TaskForce.EventHandler)
        DMS.TaskForce.HandlerAdded = true
    end
    local count = 0
    for _ in pairs(DMS.TaskForce.Forces) do count = count + 1 end
    logDebug("Started monitoring %d task forces", count)
end

--- Stop task force system
function DMS.TaskForce.stop()
    DMS.TaskForce.Active = false
    logDebug("Stopped")
end

--- Get task force status
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

DMS.TaskForce.create("ambush-team",
    {"Armor-1", "Infantry-1", "Arty-1", "Reserve-1"},
    {
        roles = {
            ["Armor-1"] = "assault",
            ["Infantry-1"] = "flanker",
            ["Arty-1"] = "support",     -- artillery gets a FireAtPoint mission
            ["Reserve-1"] = "reserve",
        },
        tactics = "ambush",
        responseDelay = 3,
    }
)

DMS.TaskForce.start()

-- When any member shoots or is hit, the whole team responds:
-- - assault groups route onto the contact (OPEN_FIRE / RED)
-- - flankers use DMS.Flanking if loaded, else assault
-- - support groups fire (artillery) or hold and engage
-- - reserve commits after +15s
]]

-- Export
_G.DMS = DMS
