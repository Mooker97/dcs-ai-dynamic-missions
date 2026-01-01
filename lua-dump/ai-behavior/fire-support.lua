-- Fire Support Request System for DCS Missions
-- AI groups call for help from nearby friendly units
-- Place in mission via DO SCRIPT FILE

DMS = DMS or {}
DMS.FireSupport = {}

-- Registered support assets
DMS.FireSupport.Assets = {}
DMS.FireSupport.Requests = {}
DMS.FireSupport.Active = false

-- Configuration
DMS.FireSupport.Config = {
    checkInterval = 5,
    defaultSupportRadius = 10000,   -- Units within this range can support
    responseTime = 10,               -- Seconds before support arrives
    maxConcurrentSupport = 3,        -- Max units responding to one call
    cooldownTime = 60,               -- Seconds before unit can request again
    announceSupport = true,          -- Show support messages
    enemyCoalition = coalition.side.RED,
}

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
-- @param options table|nil Asset options
function DMS.FireSupport.registerAsset(groupName, supportType, options)
    options = options or {}

    DMS.FireSupport.Assets[groupName] = {
        name = groupName,
        type = supportType,
        range = options.range or DMS.FireSupport.Config.defaultSupportRadius,
        available = true,
        lastSupportTime = 0,
        priority = options.priority or 5,  -- 1-10, higher = responds first
        canMove = options.canMove ~= false,
    }
end

--- Register multiple assets
-- @param assets table Array of {groupName, supportType, options}
function DMS.FireSupport.registerAssets(assets)
    for _, asset in ipairs(assets) do
        DMS.FireSupport.registerAsset(asset[1], asset[2], asset[3])
    end
end

--- Get position of a group
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

--- Calculate distance
-- @param pos1 table First position
-- @param pos2 table Second position
-- @return number Distance
local function getDistance(pos1, pos2)
    local dx = pos1.x - pos2.x
    local dz = pos1.z - pos2.z
    return math.sqrt(dx * dx + dz * dz)
end

--- Find available support assets in range
-- @param requestPos table Position requesting support
-- @param requestType string|nil Specific type requested (optional)
-- @return table Array of available assets
local function findAvailableSupport(requestPos, requestType)
    local available = {}
    local currentTime = timer.getTime()

    for assetName, asset in pairs(DMS.FireSupport.Assets) do
        if asset.available then
            -- Check cooldown
            if currentTime - asset.lastSupportTime > DMS.FireSupport.Config.cooldownTime then
                -- Check if asset still exists
                local assetPos = getGroupPosition(assetName)
                if assetPos then
                    -- Check range
                    local dist = getDistance(assetPos, requestPos)
                    if dist <= asset.range then
                        -- Check type if specified
                        if not requestType or asset.type == requestType then
                            table.insert(available, {
                                name = assetName,
                                asset = asset,
                                distance = dist,
                            })
                        end
                    end
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

--- Execute support response
-- @param assetName string Support asset name
-- @param targetPos table Target position
-- @param supportType string Type of support
local function executeSupport(assetName, targetPos, supportType)
    local group = Group.getByName(assetName)
    if not group or not group:isExist() then return end

    local asset = DMS.FireSupport.Assets[assetName]
    if not asset then return end

    local controller = group:getController()
    if not controller then return end

    -- Set aggressive
    controller:setOption(AI.Option.Ground.id.ROE, AI.Option.Ground.val.ROE.WEAPON_FREE)
    controller:setOption(AI.Option.Ground.id.ALARM_STATE, AI.Option.Ground.val.ALARM_STATE.RED)

    -- Different behavior based on support type
    if supportType == "artillery" then
        -- Artillery fires from position (if it has targets)
        -- In DCS, artillery needs actual targets - this sets them hot

    elseif supportType == "armor" or supportType == "infantry" then
        -- Move toward target if can move
        if asset.canMove then
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

    elseif supportType == "air" then
        -- Air assets engage from current position
        -- Would need actual air tasking for full implementation
    end

    asset.lastSupportTime = timer.getTime()
end

--- Request fire support
-- @param requesterGroup string Group requesting support
-- @param targetPos table|nil Target position (defaults to requester position)
-- @param options table|nil Request options
-- @return table Results {success, respondingUnits}
function DMS.FireSupport.request(requesterGroup, targetPos, options)
    options = options or {}

    -- Get requester position if target not specified
    if not targetPos then
        targetPos = getGroupPosition(requesterGroup)
    end

    if not targetPos then
        return {success = false, respondingUnits = {}}
    end

    -- Find available support
    local available = findAvailableSupport(targetPos, options.type)

    if #available == 0 then
        return {success = false, respondingUnits = {}}
    end

    -- Select responders (up to max)
    local maxResponders = options.maxResponders or DMS.FireSupport.Config.maxConcurrentSupport
    local responding = {}

    for i = 1, math.min(maxResponders, #available) do
        local responder = available[i]
        table.insert(responding, responder.name)

        -- Schedule response
        timer.scheduleFunction(function()
            executeSupport(responder.name, targetPos, responder.asset.type)
            return nil
        end, nil, timer.getTime() + DMS.FireSupport.Config.responseTime)
    end

    -- Store request
    DMS.FireSupport.Requests[requesterGroup] = {
        targetPos = targetPos,
        respondingUnits = responding,
        time = timer.getTime(),
    }

    if DMS.FireSupport.Config.announceSupport then
        trigger.action.outText(string.format(
            "[FireSupport] %s requesting support - %d units responding",
            requesterGroup, #responding
        ), 10)
    end

    return {success = true, respondingUnits = responding}
end

--- Event handler for automatic support requests
DMS.FireSupport.EventHandler = {
    onEvent = function(self, event)
        if not DMS.FireSupport.Active then return end

        -- When enemy unit takes significant damage, nearby units call for help
        if event.id == world.event.S_EVENT_HIT then
            local target = event.target
            if not target then return end

            -- Check if target is enemy coalition
            local targetCoalition = target:getCoalition()
            if targetCoalition ~= DMS.FireSupport.Config.enemyCoalition then return end

            local group = target:getGroup()
            if not group then return end

            local groupName = group:getName()

            -- Check if already requested recently
            local existingRequest = DMS.FireSupport.Requests[groupName]
            if existingRequest then
                if timer.getTime() - existingRequest.time < 30 then
                    return  -- Too soon for another request
                end
            end

            -- 30% chance to call for support when hit
            if math.random() < 0.3 then
                DMS.FireSupport.request(groupName)
            end
        end
    end
}

--- Start fire support system
function DMS.FireSupport.start()
    if DMS.FireSupport.Active then return end

    DMS.FireSupport.Active = true
    world.addEventHandler(DMS.FireSupport.EventHandler)
end

--- Stop fire support system
function DMS.FireSupport.stop()
    DMS.FireSupport.Active = false
end

--- Mark asset as unavailable
-- @param assetName string Asset name
function DMS.FireSupport.setUnavailable(assetName)
    if DMS.FireSupport.Assets[assetName] then
        DMS.FireSupport.Assets[assetName].available = false
    end
end

--- Mark asset as available
-- @param assetName string Asset name
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
        pendingRequests = 0,  -- Could track this
    }
end

--[[
USAGE EXAMPLE:

-- Register support assets
DMS.FireSupport.registerAsset("Artillery-1", "artillery", {
    range = 15000,
    priority = 10,
    canMove = false,
})

DMS.FireSupport.registerAsset("QRF-Armor", "armor", {
    range = 8000,
    priority = 7,
})

DMS.FireSupport.registerAssets({
    {"Infantry-Reserve-1", "infantry", {range = 5000}},
    {"Infantry-Reserve-2", "infantry", {range = 5000}},
})

-- Start system (enables automatic support calls when hit)
DMS.FireSupport.start()

-- Manual support request
local targetPos = {x = -50000, z = 40000}
local result = DMS.FireSupport.request("Frontline-1", targetPos, {
    type = "armor",  -- Request specific type
    maxResponders = 2,
})

if result.success then
    env.info("Support inbound: " .. table.concat(result.respondingUnits, ", "))
end
]]

-- Export
_G.DMS = DMS
