-- Fire Support Request System for DCS Missions
-- AI groups call for help from nearby friendly units
-- Place in mission via DO SCRIPT FILE
-- Optional: utils/mission-settings.lua (debug logging), utils/error-handler.lua

DMS = DMS or {}
DMS.FireSupport = {}

-- Registered support assets
DMS.FireSupport.Assets = {}
DMS.FireSupport.Requests = {}
DMS.FireSupport.Active = false
DMS.FireSupport.HandlerAdded = false

-- Configuration
DMS.FireSupport.Config = {
    checkInterval = 5,
    defaultSupportRadius = 10000,   -- Units within this range can support
    responseTime = 10,               -- Seconds before support arrives
    maxConcurrentSupport = 3,        -- Max units responding to one call
    cooldownTime = 60,               -- Seconds before unit can request again
    announceSupport = true,          -- Show support messages
    enemyCoalition = coalition.side.RED,
    artilleryRadius = 150,           -- FireAtPoint dispersion radius (m)
    artilleryRounds = 10,            -- FireAtPoint expendQty
    airEngageRadius = 3000,          -- EngageTargetsInZone radius for air assets (m)
    armorSpeed = 12,                 -- m/s when armor moves to support
    infantrySpeed = 5,               -- m/s when infantry moves to support
}

-- ============================================================
-- INTERNAL HELPERS (logging, safety, tasking)
-- ============================================================

local function logDebug(fmt, ...)
    if DMS.Settings and DMS.Settings.isDebug and DMS.Settings.isDebug() then
        env.info(string.format("[FireSupport] " .. fmt, ...))
    end
end

local function logError(context, err)
    local msg = tostring(err)
    if DMS.Error and DMS.Error.log then
        if pcall(DMS.Error.log, "FireSupport." .. context, msg) then return end
    end
    env.error(string.format("[DMS LUA ERROR] FireSupport.%s: %s", context, msg))
end

--- Schedule a one-shot callback, pcall-guarded
local function safeScheduleOnce(context, func, delay)
    return timer.scheduleFunction(function(_, time)
        local ok, err = pcall(func, time)
        if not ok then logError(context, err) end
        return nil
    end, nil, timer.getTime() + delay)
end

--- First living unit of a group (nil if group is dead / missing)
local function getLeadUnit(group)
    if not group or not group:isExist() then return nil end
    local units = group:getUnits()
    if not units then return nil end
    for _, u in ipairs(units) do
        if u and u:isExist() then return u end
    end
    return nil
end

local function getGroupCategory(group)
    local ok, cat = pcall(group.getCategory, group)
    if ok then return cat end
    return nil
end

--- Get position of a group
-- @param groupName string Group name
-- @return table|nil Position
local function getGroupPosition(groupName)
    local lead = getLeadUnit(Group.getByName(groupName))
    if lead then return lead:getPoint() end
    return nil
end

--- Calculate distance
local function getDistance(pos1, pos2)
    local dx = pos1.x - pos2.x
    local dz = pos1.z - pos2.z
    return math.sqrt(dx * dx + dz * dz)
end

--- Build a ground route point (route x/y are map coords: y = Vec3.z)
local function makeGroundPoint(x, z, speed, action)
    return {
        x = x, y = z,
        alt = land.getHeight({x = x, y = z}), alt_type = "BARO",
        type = "Turning Point", action = action or "Off Road",
        speed = speed, speed_locked = true,
        ETA = 0, ETA_locked = false,
        formation_template = "",
        task = {id = "ComboTask", params = {tasks = {}}},
    }
end

--- Route a ground group: current position first, then the given {x, z} waypoints
-- @return boolean True if the Mission task was set
local function routeGroundGroup(group, waypoints, speed, action)
    if getGroupCategory(group) ~= Group.Category.GROUND then return false end
    local lead = getLeadUnit(group)
    if not lead then return false end
    local cur = lead:getPoint()
    local points = {makeGroundPoint(cur.x, cur.z, speed, action)}
    for _, wp in ipairs(waypoints) do
        points[#points + 1] = makeGroundPoint(wp.x, wp.z, speed, action)
    end
    if #points < 2 then return false end
    local controller = group:getController()
    if not controller then return false end
    local ok, err = pcall(controller.setTask, controller,
        {id = "Mission", params = {route = {points = points}}})
    if not ok then
        logError("routeGroundGroup", err)
        return false
    end
    return true
end

--- Ground ROE OPEN_FIRE + alarm RED (ground ROE has no WEAPON_FREE)
local function setGroundEngage(controller)
    controller:setOption(AI.Option.Ground.id.ROE, AI.Option.Ground.val.ROE.OPEN_FIRE)
    controller:setOption(AI.Option.Ground.id.ALARM_STATE, AI.Option.Ground.val.ALARM_STATE.RED)
end

-- ============================================================
-- PUBLIC API
-- ============================================================

--- Configure fire support system
-- @param settings table Configuration overrides
function DMS.FireSupport.configure(settings)
    for key, value in pairs(settings) do
        DMS.FireSupport.Config[key] = value
    end
end

--- Register a group as support asset
-- @param groupName string Group name
-- @param supportType string Type: "artillery", "air", "armor", "infantry"
-- @param options table|nil Asset options {range, priority, canMove, fireRadius, rounds}
function DMS.FireSupport.registerAsset(groupName, supportType, options)
    options = options or {}

    DMS.FireSupport.Assets[groupName] = {
        name = groupName,
        type = supportType,
        range = options.range or DMS.FireSupport.Config.defaultSupportRadius,
        available = true,
        lastSupportTime = -math.huge,
        priority = options.priority or 5,  -- 1-10, higher = responds first
        canMove = options.canMove ~= false,
        fireRadius = options.fireRadius,   -- artillery only (optional)
        rounds = options.rounds,           -- artillery only (optional)
    }
    logDebug("Registered %s asset '%s' (range %dm)", tostring(supportType), groupName,
        DMS.FireSupport.Assets[groupName].range)
end

--- Register multiple assets
-- @param assets table Array of {groupName, supportType, options}
function DMS.FireSupport.registerAssets(assets)
    for _, asset in ipairs(assets) do
        DMS.FireSupport.registerAsset(asset[1], asset[2], asset[3])
    end
end

--- Find available support assets in range
local function findAvailableSupport(requestPos, requestType)
    local available = {}
    local currentTime = timer.getTime()

    for assetName, asset in pairs(DMS.FireSupport.Assets) do
        if asset.available
            and currentTime - asset.lastSupportTime > DMS.FireSupport.Config.cooldownTime
            and (not requestType or asset.type == requestType) then
            local assetPos = getGroupPosition(assetName)  -- nil if dead
            if assetPos then
                local dist = getDistance(assetPos, requestPos)
                if dist <= asset.range then
                    table.insert(available, {name = assetName, asset = asset, distance = dist})
                end
            end
        end
    end

    -- Sort by priority then distance
    table.sort(available, function(a, b)
        if a.asset.priority ~= b.asset.priority then
            return a.asset.priority > b.asset.priority
        end
        return a.distance < b.distance
    end)

    return available
end

--- Task an air asset: en-route EngageTargetsInZone on WP1, orbit over target at WP2
local function taskAirSupport(group, controller, targetPos, isHelo)
    local lead = getLeadUnit(group)
    if not lead then return end
    local cur = lead:getPoint()
    local alt = math.max(cur.y, land.getHeight({x = targetPos.x, y = targetPos.z}) + (isHelo and 300 or 1500))
    local speed = isHelo and 50 or 200
    local function airPoint(x, z, tasks)
        return {
            x = x, y = z, alt = alt, alt_type = "BARO",
            type = "Turning Point", action = "Turning Point",
            speed = speed, speed_locked = true,
            ETA = 0, ETA_locked = false,
            task = {id = "ComboTask", params = {tasks = tasks}},
        }
    end
    local engage = {
        number = 1, auto = false, enabled = true,
        id = "EngageTargetsInZone",
        params = {
            point = {x = targetPos.x, y = targetPos.z},
            zoneRadius = DMS.FireSupport.Config.airEngageRadius,
            targetTypes = {"All"},
            priority = 0,
        },
    }
    local orbit = {
        number = 1, auto = false, enabled = true,
        id = "Orbit",
        params = {pattern = "Circle", point = {x = targetPos.x, y = targetPos.z},
                  speed = speed, altitude = alt},
    }
    controller:setTask({id = "Mission", params = {route = {points = {
        airPoint(cur.x, cur.z, {engage}),
        airPoint(targetPos.x, targetPos.z, {orbit}),
    }}}})
end

--- Execute support response
-- @param assetName string Support asset name
-- @param targetPos table Target position (Vec3)
-- @param supportType string Type of support
-- @param targetIsFriendly boolean True if targetPos is the requester's own position
local function executeSupport(assetName, targetPos, supportType, targetIsFriendly)
    local group = Group.getByName(assetName)
    if not getLeadUnit(group) then
        logDebug("Asset '%s' no longer alive - support cancelled", assetName)
        return
    end

    local asset = DMS.FireSupport.Assets[assetName]
    if not asset then return end

    local controller = group:getController()
    if not controller then return end

    local cfg = DMS.FireSupport.Config
    local cat = getGroupCategory(group)
    local isAir = (cat == Group.Category.AIRPLANE or cat == Group.Category.HELICOPTER)

    if cat == Group.Category.GROUND then
        setGroundEngage(controller)
    elseif isAir then
        controller:setOption(AI.Option.Air.id.ROE, AI.Option.Air.val.ROE.WEAPON_FREE)
    end

    if supportType == "artillery" then
        if targetIsFriendly then
            -- Never drop indirect fire on the requester's own position
            logDebug("Artillery '%s' skipped - no enemy target position supplied", assetName)
        else
            -- pushTask keeps the existing route underneath the fire mission
            controller:pushTask({
                id = "FireAtPoint",
                params = {
                    point = {x = targetPos.x, y = targetPos.z},
                    radius = asset.fireRadius or cfg.artilleryRadius,
                    expendQty = asset.rounds or cfg.artilleryRounds,
                    expendQtyEnabled = true,
                },
            })
            logDebug("Artillery '%s' firing at (%.0f, %.0f)", assetName, targetPos.x, targetPos.z)
        end

    elseif supportType == "armor" or supportType == "infantry" then
        if asset.canMove then
            local speed = (supportType == "armor") and cfg.armorSpeed or cfg.infantrySpeed
            if routeGroundGroup(group, {{x = targetPos.x, z = targetPos.z}}, speed, "Off Road") then
                logDebug("'%s' (%s) moving to (%.0f, %.0f)", assetName, supportType, targetPos.x, targetPos.z)
            end
        end

    elseif supportType == "air" then
        if isAir then
            taskAirSupport(group, controller, targetPos, cat == Group.Category.HELICOPTER)
            logDebug("Air asset '%s' tasked to engage at (%.0f, %.0f)", assetName, targetPos.x, targetPos.z)
        end
    end

    asset.lastSupportTime = timer.getTime()
end

--- Request fire support
-- @param requesterGroup string Group requesting support
-- @param targetPos table|nil Target position (Vec3). If nil, maneuver units move to the
--        requester; artillery will NOT fire (it would hit the requester).
-- @param options table|nil Request options {type, maxResponders}
-- @return table Results {success, respondingUnits}
function DMS.FireSupport.request(requesterGroup, targetPos, options)
    options = options or {}

    local targetIsFriendly = false
    if not targetPos then
        targetPos = getGroupPosition(requesterGroup)
        targetIsFriendly = true
    end

    if not targetPos then
        return {success = false, respondingUnits = {}}
    end

    local available = findAvailableSupport(targetPos, options.type)

    if #available == 0 then
        logDebug("'%s' requested support - none available", tostring(requesterGroup))
        return {success = false, respondingUnits = {}}
    end

    local maxResponders = options.maxResponders or DMS.FireSupport.Config.maxConcurrentSupport
    local responding = {}

    for i = 1, math.min(maxResponders, #available) do
        local responder = available[i]
        table.insert(responding, responder.name)
        -- Reserve now so overlapping requests don't double-book the asset
        responder.asset.lastSupportTime = timer.getTime()

        safeScheduleOnce("executeSupport", function()
            executeSupport(responder.name, targetPos, responder.asset.type, targetIsFriendly)
        end, DMS.FireSupport.Config.responseTime)
    end

    DMS.FireSupport.Requests[requesterGroup] = {
        targetPos = targetPos,
        respondingUnits = responding,
        time = timer.getTime(),
    }

    logDebug("'%s' requested support - %d responding: %s",
        tostring(requesterGroup), #responding, table.concat(responding, ", "))

    if DMS.FireSupport.Config.announceSupport then
        trigger.action.outText(string.format(
            "[FireSupport] %s requesting support - %d units responding",
            requesterGroup, #responding
        ), 10)
    end

    return {success = true, respondingUnits = responding}
end

--- Handle hit events (internal)
local function handleEvent(event)
    if not DMS.FireSupport.Active then return end
    if event.id ~= world.event.S_EVENT_HIT then return end

    local target = event.target
    if not target or not target.getGroup or not target:isExist() then return end

    if target:getCoalition() ~= DMS.FireSupport.Config.enemyCoalition then return end

    local group = target:getGroup()
    if not group then return end

    local groupName = group:getName()

    local existingRequest = DMS.FireSupport.Requests[groupName]
    if existingRequest and timer.getTime() - existingRequest.time < 30 then
        return  -- Too soon for another request
    end

    -- 30% chance to call for support when hit
    if math.random() < 0.3 then
        -- Target the shooter if known, so fire lands on the enemy, not on the requester
        local shooterPos = nil
        local shooter = event.initiator
        if shooter and shooter.isExist and shooter:isExist() then
            shooterPos = shooter:getPoint()
        end
        DMS.FireSupport.request(groupName, shooterPos)
    end
end

--- Event handler for automatic support requests (pcall-guarded)
DMS.FireSupport.EventHandler = {
    onEvent = function(self, event)
        local ok, err = pcall(handleEvent, event)
        if not ok then logError("onEvent", err) end
    end
}

--- Start fire support system
function DMS.FireSupport.start()
    if DMS.FireSupport.Active then return end

    DMS.FireSupport.Active = true
    if not DMS.FireSupport.HandlerAdded then
        world.addEventHandler(DMS.FireSupport.EventHandler)
        DMS.FireSupport.HandlerAdded = true
    end
    logDebug("Started (cooldown: %ds, response delay: %ds)",
        DMS.FireSupport.Config.cooldownTime, DMS.FireSupport.Config.responseTime)
end

--- Stop fire support system
function DMS.FireSupport.stop()
    DMS.FireSupport.Active = false
    logDebug("Stopped")
end

--- Mark asset as unavailable
function DMS.FireSupport.setUnavailable(assetName)
    if DMS.FireSupport.Assets[assetName] then
        DMS.FireSupport.Assets[assetName].available = false
    end
end

--- Mark asset as available
function DMS.FireSupport.setAvailable(assetName)
    if DMS.FireSupport.Assets[assetName] then
        DMS.FireSupport.Assets[assetName].available = true
    end
end

--- Get support network status
-- @return table Status information
function DMS.FireSupport.getStatus()
    local total, available = 0, 0

    for _, asset in pairs(DMS.FireSupport.Assets) do
        total = total + 1
        if asset.available then
            available = available + 1
        end
    end

    return {
        totalAssets = total,
        availableAssets = available,
        pendingRequests = 0,
    }
end

--[[
USAGE EXAMPLE:

DMS.FireSupport.registerAsset("Artillery-1", "artillery", {
    range = 15000,
    priority = 10,
    canMove = false,
    rounds = 20,       -- FireAtPoint expendQty
    fireRadius = 100,  -- FireAtPoint radius
})

DMS.FireSupport.registerAsset("QRF-Armor", "armor", {range = 8000, priority = 7})

DMS.FireSupport.registerAssets({
    {"Infantry-Reserve-1", "infantry", {range = 5000}},
    {"Infantry-Reserve-2", "infantry", {range = 5000}},
})

-- Start (enemy units that get hit may call support onto the shooter's position)
DMS.FireSupport.start()

-- Manual request onto a specific (enemy) position
local targetPos = {x = -50000, y = 0, z = 40000}
local result = DMS.FireSupport.request("Frontline-1", targetPos, {type = "armor", maxResponders = 2})
if result.success then
    env.info("Support inbound: " .. table.concat(result.respondingUnits, ", "))
end
]]

-- Export
_G.DMS = DMS
