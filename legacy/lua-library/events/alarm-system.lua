-- Alarm System for DCS Missions
-- Chain reaction alerts when enemies are detected
-- Requires: utils/messaging.lua
-- Place in mission via DO SCRIPT FILE

DMS = DMS or {}
DMS.Alarm = DMS.Alarm or {}

-- Alarm zones and states
DMS.Alarm.Zones = DMS.Alarm.Zones or {}
DMS.Alarm.Active = DMS.Alarm.Active or false

-- Alert levels
DMS.Alarm.Level = {
    GREEN = 1,   -- Normal operations
    YELLOW = 2,  -- Heightened awareness
    ORANGE = 3,  -- High alert
    RED = 4,     -- Combat alert
}

-- Current global alert level
DMS.Alarm.CurrentLevel = DMS.Alarm.CurrentLevel or DMS.Alarm.Level.GREEN

-- Configuration
DMS.Alarm.Config = DMS.Alarm.Config or {
    playerCoalition = coalition.side.BLUE,
    enemyCoalition = coalition.side.RED,
    checkInterval = 10,           -- Seconds between detection checks
    alertSpreadDelay = 5,         -- Delay for alert to spread to adjacent zones
    alertDecayTime = 300,         -- Seconds before alert level decreases
    showAlertMessages = true,
    detectionRange = 5000,        -- Base detection range in meters
}

-- Alert level names for messages
local levelNames = {
    [1] = "GREEN (Normal)",
    [2] = "YELLOW (Elevated)",
    [3] = "ORANGE (High)",
    [4] = "RED (Combat)",
}

local function isDebug()
    return DMS.Settings and DMS.Settings.isDebug and DMS.Settings.isDebug()
end

local function logError(context, err)
    if DMS.Error and DMS.Error.log then
        DMS.Error.log(context, err)
    else
        env.error("[DMS LUA ERROR] " .. tostring(context) .. ": " .. tostring(err))
    end
end

--- Safely call obj:method(...) returning nil on error
local function safeMethod(obj, method, ...)
    if obj == nil or type(obj) ~= "table" or type(obj[method]) ~= "function" then
        return nil
    end
    local ok, res = pcall(obj[method], obj, ...)
    if ok then return res end
    return nil
end

--- Get positions of all alive player units
local function getPlayerPositions()
    local positions = {}
    local ok, players = pcall(coalition.getPlayers, DMS.Alarm.Config.playerCoalition)
    if not ok or type(players) ~= "table" then return positions end
    for _, player in ipairs(players) do
        if safeMethod(player, "isExist") then
            local pos = safeMethod(player, "getPoint")
            if pos then table.insert(positions, pos) end
        end
    end
    return positions
end

--- Configure alarm system
-- @param settings table Configuration overrides
function DMS.Alarm.configure(settings)
    if type(settings) ~= "table" then return end
    for key, value in pairs(settings) do
        DMS.Alarm.Config[key] = value
    end
end

--- Register an alarm zone
-- @param zoneName string Zone name (from Mission Editor)
-- @param options table|nil Zone options
function DMS.Alarm.registerZone(zoneName, options)
    options = options or {}

    DMS.Alarm.Zones[zoneName] = {
        name = zoneName,
        alertLevel = DMS.Alarm.Level.GREEN,
        lastAlertTime = 0,
        adjacentZones = options.adjacentZones or {},
        detectionUnits = options.detectionUnits or {},  -- Specific units that can detect
        responseGroups = options.responseGroups or {},   -- Groups to activate on alert
        hasRadar = options.hasRadar or false,           -- Extended detection range
        detectionRange = options.detectionRange or DMS.Alarm.Config.detectionRange,
    }

    if isDebug() then
        env.info(string.format("[Alarm] Registered zone '%s' (%d adjacent, %d response groups)",
            tostring(zoneName), #DMS.Alarm.Zones[zoneName].adjacentZones, #DMS.Alarm.Zones[zoneName].responseGroups))
    end
end

--- Get zone center position
-- @param zoneName string Zone name
-- @return table|nil Vec3 position or nil
local function getZonePosition(zoneName)
    local zone = trigger.misc.getZone(zoneName)
    if zone and zone.point then
        return {x = zone.point.x, y = 0, z = zone.point.z}
    end
    return nil
end

--- Get zone radius
-- @param zoneName string Zone name
-- @return number Radius in meters
local function getZoneRadius(zoneName)
    local zone = trigger.misc.getZone(zoneName)
    if zone and zone.radius then
        return zone.radius
    end
    return 1000  -- Default
end

--- Calculate distance between positions
-- @param pos1 table Vec3
-- @param pos2 table Vec3
-- @return number Distance in meters
local function getDistance(pos1, pos2)
    local dx = pos2.x - pos1.x
    local dz = pos2.z - pos1.z
    return math.sqrt(dx * dx + dz * dz)
end

--- Check if player is detected in zone
-- @param zoneData table Zone data
-- @return boolean True if player detected
local function checkDetection(zoneData)
    local zonePos = getZonePosition(zoneData.name)
    if not zonePos then
        return false
    end

    local detectionRange = zoneData.detectionRange
    if zoneData.hasRadar then
        detectionRange = detectionRange * 3  -- Radar triples detection range
    end

    local playerPositions = getPlayerPositions()
    if #playerPositions == 0 then
        return false
    end

    -- Check detection units first
    if #zoneData.detectionUnits > 0 then
        local hasAliveDetector = false
        for _, unitName in ipairs(zoneData.detectionUnits) do
            local unit = Unit.getByName(unitName)
            local life = unit and safeMethod(unit, "getLife")
            if unit and safeMethod(unit, "isExist") and (life == nil or life >= 1) then
                hasAliveDetector = true
                local unitPos = safeMethod(unit, "getPoint")
                if unitPos then
                    for _, playerPos in ipairs(playerPositions) do
                        if getDistance(unitPos, playerPos) < detectionRange then
                            return true
                        end
                    end
                end
            end
        end
        -- If detection units defined but all dead, no detection possible
        if not hasAliveDetector then
            return false
        end
    end

    -- Default zone-based detection
    local zoneRadius = getZoneRadius(zoneData.name)
    for _, playerPos in ipairs(playerPositions) do
        if getDistance(zonePos, playerPos) < zoneRadius + detectionRange then
            return true
        end
    end

    return false
end

--- Set zone alert level
-- @param zoneName string Zone name
-- @param level number Alert level
-- @param propagate boolean|nil Propagate to adjacent zones
function DMS.Alarm.setZoneAlert(zoneName, level, propagate)
    local zone = DMS.Alarm.Zones[zoneName]
    if not zone or type(level) ~= "number" then
        return
    end
    if level < DMS.Alarm.Level.GREEN then level = DMS.Alarm.Level.GREEN end
    if level > DMS.Alarm.Level.RED then level = DMS.Alarm.Level.RED end

    local oldLevel = zone.alertLevel
    zone.alertLevel = level
    zone.lastAlertTime = timer.getTime()

    if oldLevel ~= level and isDebug() then
        env.info(string.format("[Alarm] Zone '%s' state changed to %s", tostring(zoneName), levelNames[level] or "UNKNOWN"))
    end

    -- Announce level change
    if DMS.Alarm.Config.showAlertMessages and oldLevel ~= level then
        local msg = string.format("ALERT: %s zone now at %s",
            zoneName, levelNames[level] or "UNKNOWN")
        trigger.action.outTextForCoalition(
            DMS.Alarm.Config.playerCoalition,
            msg,
            10,
            true
        )
    end

    -- Activate response groups on high alert
    if level >= DMS.Alarm.Level.ORANGE then
        for _, groupName in ipairs(zone.responseGroups) do
            local group = Group.getByName(groupName)
            if group and safeMethod(group, "isExist") then
                trigger.action.activateGroup(group)
                if isDebug() then
                    env.info(string.format("[Alarm] Activated response group '%s' for zone '%s'", tostring(groupName), tostring(zoneName)))
                end
            end
        end
    end

    -- Propagate to adjacent zones (one level lower)
    if propagate ~= false and level > DMS.Alarm.Level.GREEN then
        for _, adjZoneName in ipairs(zone.adjacentZones) do
            local adjZone = DMS.Alarm.Zones[adjZoneName]
            if adjZone and adjZone.alertLevel < level - 1 then
                local newLevel = level - 1
                timer.scheduleFunction(function()
                    local ok, err = pcall(DMS.Alarm.setZoneAlert, adjZoneName, newLevel, false)
                    if not ok then logError("Alarm.propagate(" .. tostring(adjZoneName) .. ")", err) end
                    return nil
                end, nil, timer.getTime() + (tonumber(DMS.Alarm.Config.alertSpreadDelay) or 5))
            end
        end
    end

    -- Update global alert level
    DMS.Alarm.updateGlobalLevel()
end

--- Update global alert level based on all zones
function DMS.Alarm.updateGlobalLevel()
    local maxLevel = DMS.Alarm.Level.GREEN

    for _, zone in pairs(DMS.Alarm.Zones) do
        if zone.alertLevel > maxLevel then
            maxLevel = zone.alertLevel
        end
    end

    if maxLevel ~= DMS.Alarm.CurrentLevel then
        DMS.Alarm.CurrentLevel = maxLevel

        if DMS.Alarm.Config.showAlertMessages then
            trigger.action.outTextForCoalition(
                DMS.Alarm.Config.playerCoalition,
                string.format("GLOBAL ALERT LEVEL: %s", levelNames[maxLevel] or "UNKNOWN"),
                15,
                true
            )
        end
    end
end

--- Process alarm checks
local function processZone(zoneName, zone, currentTime)
        -- Check for detection
        if checkDetection(zone) then
            -- Raise to RED on direct detection
            if zone.alertLevel < DMS.Alarm.Level.RED then
                DMS.Alarm.setZoneAlert(zoneName, DMS.Alarm.Level.RED, true)
            else
                -- Keep timer refreshed
                zone.lastAlertTime = currentTime
            end
        else
            -- Decay alert level over time
            local timeSinceAlert = currentTime - zone.lastAlertTime
            if timeSinceAlert > DMS.Alarm.Config.alertDecayTime and zone.alertLevel > DMS.Alarm.Level.GREEN then
                DMS.Alarm.setZoneAlert(zoneName, zone.alertLevel - 1, false)
            end
        end
end

local function processAlarms(_, time)
    if not DMS.Alarm.Active then
        DMS.Alarm.TimerId = nil
        return nil
    end

    local currentTime = timer.getTime()
    for zoneName, zone in pairs(DMS.Alarm.Zones) do
        local ok, err = pcall(processZone, zoneName, zone, currentTime)
        if not ok then
            logError("Alarm.processZone(" .. tostring(zoneName) .. ")", err)
        end
    end

    return time + (tonumber(DMS.Alarm.Config.checkInterval) or 10)
end

--- Start alarm system
function DMS.Alarm.start()
    if DMS.Alarm.Active then
        return
    end

    DMS.Alarm.Active = true
    DMS.Alarm.TimerId = timer.scheduleFunction(
        processAlarms,
        nil,
        timer.getTime() + (tonumber(DMS.Alarm.Config.checkInterval) or 10)
    )

    if isDebug() then
        local count = 0
        for _ in pairs(DMS.Alarm.Zones) do count = count + 1 end
        env.info(string.format("[Alarm] Started monitoring %d zones (interval: %ss)", count, tostring(DMS.Alarm.Config.checkInterval)))
    end
end

--- Stop alarm system
function DMS.Alarm.stop()
    DMS.Alarm.Active = false
    if DMS.Alarm.TimerId then
        pcall(timer.removeFunction, DMS.Alarm.TimerId)
        DMS.Alarm.TimerId = nil
    end
    if isDebug() then
        env.info("[Alarm] Stopped")
    end
end

--- Manually raise alert
-- @param zoneName string Zone name
function DMS.Alarm.raiseAlert(zoneName)
    DMS.Alarm.setZoneAlert(zoneName, DMS.Alarm.Level.RED, true)
end

--- Get zone status
-- @param zoneName string Zone name
-- @return table|nil Zone status
function DMS.Alarm.getZoneStatus(zoneName)
    local zone = DMS.Alarm.Zones[zoneName]
    if zone then
        return {
            name = zone.name,
            alertLevel = zone.alertLevel,
            alertName = levelNames[zone.alertLevel],
            timeSinceAlert = timer.getTime() - zone.lastAlertTime,
        }
    end
    return nil
end

--- Get all zones at or above alert level
-- @param minLevel number Minimum alert level
-- @return table Array of zone names
function DMS.Alarm.getZonesAtLevel(minLevel)
    local zones = {}
    for zoneName, zone in pairs(DMS.Alarm.Zones) do
        if zone.alertLevel >= minLevel then
            table.insert(zones, zoneName)
        end
    end
    return zones
end

--[[
USAGE EXAMPLE:

-- Configure
DMS.Alarm.configure({
    checkInterval = 5,
    alertSpreadDelay = 3,
    alertDecayTime = 180,
    showAlertMessages = true
})

-- Register zones (create trigger zones in Mission Editor first)
DMS.Alarm.registerZone("North-Sector", {
    adjacentZones = {"Central-Sector"},
    responseGroups = {"QRF-North"},
    detectionUnits = {"EWR-North"},
    hasRadar = true,
    detectionRange = 8000
})

DMS.Alarm.registerZone("Central-Sector", {
    adjacentZones = {"North-Sector", "South-Sector"},
    responseGroups = {"QRF-Central", "SAM-Battery-1"},
    detectionRange = 5000
})

DMS.Alarm.registerZone("South-Sector", {
    adjacentZones = {"Central-Sector"},
    responseGroups = {"QRF-South"},
    detectionRange = 5000
})

-- Start system
DMS.Alarm.start()

-- Manual alert trigger (e.g., from trigger zone in ME)
-- DMS.Alarm.raiseAlert("Central-Sector")

-- Check current status
-- local status = DMS.Alarm.getZoneStatus("North-Sector")
-- local redZones = DMS.Alarm.getZonesAtLevel(DMS.Alarm.Level.RED)
]]

-- Export
_G.DMS = DMS
