-- Ambient Traffic System for DCS Missions
-- Spawns non-combat AI for immersion
-- Requires: utils/group-utils.lua
-- Place in mission via DO SCRIPT FILE

DMS = DMS or {}
DMS.Ambient = {}

-- Traffic definitions
DMS.Ambient.Traffic = {}
DMS.Ambient.Active = false
DMS.Ambient.TimerId = nil
DMS.Ambient.SpawnedGroups = {}

-- Configuration
DMS.Ambient.Config = {
    enabled = true,
    checkInterval = 60,           -- Check/spawn every minute
    maxActiveTraffic = 10,        -- Maximum concurrent ambient units
    despawnDistance = 100000,     -- Despawn when this far from all players (100km)
    playerCoalition = coalition.side.BLUE,
    neutralCoalition = coalition.side.NEUTRAL,
}

-- Traffic types
DMS.Ambient.Types = {
    AIRLINER = "airliner",
    CARGO = "cargo",
    HELICOPTER = "helicopter",
    SHIP = "ship",
    VEHICLE = "vehicle",
}

--- Configure ambient traffic
-- @param settings table Configuration overrides
function DMS.Ambient.configure(settings)
    for key, value in pairs(settings) do
        DMS.Ambient.Config[key] = value
    end
end

--- Register a traffic route
-- @param id string Route identifier
-- @param trafficType string Type of traffic
-- @param options table Route options
function DMS.Ambient.registerRoute(id, trafficType, options)
    DMS.Ambient.Traffic[id] = {
        id = id,
        type = trafficType,
        groupName = options.groupName,           -- Late activation group template
        spawnChance = options.spawnChance or 50, -- % chance per check
        maxActive = options.maxActive or 1,      -- Max of this type active
        activeCount = 0,
        cooldown = options.cooldown or 300,      -- Seconds between spawns
        lastSpawn = 0,
        conditions = options.conditions or nil,   -- Function returning true to allow spawn
        timeRestriction = options.timeRestriction or nil, -- {start, end} in hours
        spawnZone = options.spawnZone or nil,    -- Zone to spawn in
    }
end

--- Get player positions
-- @return table Array of Vec3 positions
local function getPlayerPositions()
    local positions = {}
    local players = coalition.getPlayers(DMS.Ambient.Config.playerCoalition)

    if players then
        for _, unit in ipairs(players) do
            if unit:isExist() then
                table.insert(positions, unit:getPoint())
            end
        end
    end

    return positions
end

--- Calculate distance to nearest player
-- @param position table Vec3 position
-- @param playerPositions table Array of player Vec3
-- @return number Distance in meters
local function distanceToNearestPlayer(position, playerPositions)
    local minDist = math.huge

    for _, playerPos in ipairs(playerPositions) do
        local dx = position.x - playerPos.x
        local dz = position.z - playerPos.z
        local dist = math.sqrt(dx * dx + dz * dz)
        if dist < minDist then
            minDist = dist
        end
    end

    return minDist
end

--- Check time restriction
-- @param restriction table {start, end} in hours
-- @return boolean True if within time window
local function checkTimeRestriction(restriction)
    if not restriction then return true end

    local tod = timer.getAbsTime() % 86400
    local currentHour = tod / 3600

    if restriction.start <= restriction.finish then
        return currentHour >= restriction.start and currentHour <= restriction.finish
    else
        -- Wraps around midnight
        return currentHour >= restriction.start or currentHour <= restriction.finish
    end
end

--- Spawn traffic
-- @param route table Route definition
local function spawnTraffic(route)
    local group = Group.getByName(route.groupName)
    if group then
        trigger.action.activateGroup(group)
        route.activeCount = route.activeCount + 1
        route.lastSpawn = timer.getTime()

        table.insert(DMS.Ambient.SpawnedGroups, {
            groupName = route.groupName,
            routeId = route.id,
            spawnTime = timer.getTime(),
        })

        return true
    end
    return false
end

--- Count total active traffic
-- @return number Active traffic count
local function countActiveTraffic()
    local count = 0

    for i = #DMS.Ambient.SpawnedGroups, 1, -1 do
        local spawned = DMS.Ambient.SpawnedGroups[i]
        local group = Group.getByName(spawned.groupName)

        if group and group:isExist() then
            count = count + 1
        else
            -- Group no longer exists, update route count
            local route = DMS.Ambient.Traffic[spawned.routeId]
            if route then
                route.activeCount = math.max(0, route.activeCount - 1)
            end
            table.remove(DMS.Ambient.SpawnedGroups, i)
        end
    end

    return count
end

--- Check and despawn distant traffic
-- @param playerPositions table Player positions
local function checkDespawn(playerPositions)
    if #playerPositions == 0 then return end

    for i = #DMS.Ambient.SpawnedGroups, 1, -1 do
        local spawned = DMS.Ambient.SpawnedGroups[i]
        local group = Group.getByName(spawned.groupName)

        if group and group:isExist() then
            local units = group:getUnits()
            if units and #units > 0 then
                local position = units[1]:getPoint()
                local distance = distanceToNearestPlayer(position, playerPositions)

                if distance > DMS.Ambient.Config.despawnDistance then
                    group:destroy()

                    local route = DMS.Ambient.Traffic[spawned.routeId]
                    if route then
                        route.activeCount = math.max(0, route.activeCount - 1)
                    end

                    table.remove(DMS.Ambient.SpawnedGroups, i)
                end
            end
        end
    end
end

--- Process traffic spawning (internal)
local function processTrafficInternal(_, time)
    if not DMS.Ambient.Active or not DMS.Ambient.Config.enabled then
        return nil
    end

    local playerPositions = getPlayerPositions()
    if #playerPositions == 0 then
        return time + DMS.Ambient.Config.checkInterval
    end

    -- Check despawn
    checkDespawn(playerPositions)

    -- Count active
    local activeCount = countActiveTraffic()

    -- Check for new spawns
    if activeCount < DMS.Ambient.Config.maxActiveTraffic then
        for _, route in pairs(DMS.Ambient.Traffic) do
            -- Check max active for this route
            if route.activeCount >= route.maxActive then
                goto continue
            end

            -- Check cooldown
            if time - route.lastSpawn < route.cooldown then
                goto continue
            end

            -- Check time restriction
            if not checkTimeRestriction(route.timeRestriction) then
                goto continue
            end

            -- Check custom conditions
            if route.conditions and not route.conditions() then
                goto continue
            end

            -- Roll for spawn
            if math.random(100) <= route.spawnChance then
                if spawnTraffic(route) then
                    activeCount = activeCount + 1

                    if activeCount >= DMS.Ambient.Config.maxActiveTraffic then
                        break
                    end
                end
            end

            ::continue::
        end
    end

    return time + DMS.Ambient.Config.checkInterval
end

--- Process traffic with error handling
local function processTraffic(args, time)
    local success, result = pcall(processTrafficInternal, args, time)
    if not success then
        if DMS.Error then
            DMS.Error.log("Ambient.processTraffic", result)
        else
            env.error("[DMS LUA ERROR] Ambient.processTraffic: " .. tostring(result))
        end
        return time + (DMS.Ambient.Config.checkInterval or 60)
    end
    return result
end

--- Start ambient traffic
function DMS.Ambient.start()
    if DMS.Ambient.Active then
        return
    end

    DMS.Ambient.Active = true

    DMS.Ambient.TimerId = timer.scheduleFunction(
        processTraffic,
        nil,
        timer.getTime() + DMS.Ambient.Config.checkInterval
    )
end

--- Stop ambient traffic
function DMS.Ambient.stop()
    DMS.Ambient.Active = false
    if DMS.Ambient.TimerId then
        timer.removeFunction(DMS.Ambient.TimerId)
        DMS.Ambient.TimerId = nil
    end
end

--- Enable/disable traffic
-- @param enabled boolean Enable state
function DMS.Ambient.setEnabled(enabled)
    DMS.Ambient.Config.enabled = enabled
end

--- Despawn all ambient traffic
function DMS.Ambient.despawnAll()
    for _, spawned in ipairs(DMS.Ambient.SpawnedGroups) do
        local group = Group.getByName(spawned.groupName)
        if group and group:isExist() then
            group:destroy()
        end
    end

    DMS.Ambient.SpawnedGroups = {}

    for _, route in pairs(DMS.Ambient.Traffic) do
        route.activeCount = 0
    end
end

--- Get traffic status
-- @return table Traffic status
function DMS.Ambient.getStatus()
    local status = {
        enabled = DMS.Ambient.Config.enabled,
        active = DMS.Ambient.Active,
        totalActive = countActiveTraffic(),
        maxActive = DMS.Ambient.Config.maxActiveTraffic,
        routes = {},
    }

    for id, route in pairs(DMS.Ambient.Traffic) do
        status.routes[id] = {
            type = route.type,
            activeCount = route.activeCount,
            maxActive = route.maxActive,
        }
    end

    return status
end

--[[
USAGE EXAMPLE:

-- Configure
DMS.Ambient.configure({
    maxActiveTraffic = 15,
    despawnDistance = 80000  -- 80km
})

-- Register traffic routes (groups must be LATE ACTIVATION in ME)
DMS.Ambient.registerRoute("airliner_east", DMS.Ambient.Types.AIRLINER, {
    groupName = "Ambient-Airliner-East",
    spawnChance = 30,
    maxActive = 2,
    cooldown = 600,  -- 10 minutes
    timeRestriction = {start = 6, finish = 22}  -- Daytime only
})

DMS.Ambient.registerRoute("cargo_ship", DMS.Ambient.Types.SHIP, {
    groupName = "Ambient-Cargo-Ship",
    spawnChance = 20,
    maxActive = 3,
    cooldown = 900
})

DMS.Ambient.registerRoute("news_helo", DMS.Ambient.Types.HELICOPTER, {
    groupName = "Ambient-News-Helo",
    spawnChance = 15,
    maxActive = 1,
    cooldown = 1200,
    conditions = function()
        -- Only spawn if not in combat
        return trigger.misc.getUserFlag("combat_started") == 0
    end
})

DMS.Ambient.registerRoute("civilian_convoy", DMS.Ambient.Types.VEHICLE, {
    groupName = "Ambient-Civilian-Convoy",
    spawnChance = 25,
    maxActive = 2,
    cooldown = 480
})

-- Start system
DMS.Ambient.start()

-- Add F10 menu
missionCommands.addCommandForCoalition(coalition.side.BLUE, "Toggle Ambient Traffic", nil,
    function()
        DMS.Ambient.setEnabled(not DMS.Ambient.Config.enabled)
        local status = DMS.Ambient.Config.enabled and "ENABLED" or "DISABLED"
        trigger.action.outText("Ambient traffic: " .. status, 5)
    end)
]]

-- Export
_G.DMS = DMS
