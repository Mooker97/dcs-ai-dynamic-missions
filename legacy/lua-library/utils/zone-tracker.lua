--[[
  DMS Zone Tracker
  Track when groups enter/exit trigger zones

  Features:
    - Monitor group position relative to zones
    - Trigger callbacks on entry/exit
    - Prevent duplicate triggers
    - Zone priority system for overlapping zones
    - Historical tracking (which zones group has visited)

  Requires:
    - utils/coordinates.lua (optional, for distance calculations)

  Usage:
    -- Monitor convoy through zones
    DMS.ZoneTracker.track({
        groupName = "Convoy-Main",
        zones = {"Alpha-Zone", "Bravo-Zone", "Charlie-Zone"},
        onEnter = function(groupName, zoneName)
            env.info(groupName .. " entered " .. zoneName)
        end,
        onExit = function(groupName, zoneName)
            env.info(groupName .. " exited " .. zoneName)
        end
    })

    -- Start tracking
    DMS.ZoneTracker.start()
]]

DMS = DMS or {}
DMS.ZoneTracker = DMS.ZoneTracker or {}

--------------------------------------------------------------------------------
-- State (kept on the module table so a reload does not orphan a running loop)
--------------------------------------------------------------------------------

DMS.ZoneTracker._state = DMS.ZoneTracker._state or {
    trackedGroups = {},          -- Groups being tracked
    timerId = nil,               -- Timer ID
    active = false,              -- System running
}
local state = DMS.ZoneTracker._state

--------------------------------------------------------------------------------
-- Configuration
--------------------------------------------------------------------------------

DMS.ZoneTracker.Config = DMS.ZoneTracker.Config or {
    checkInterval = 7,           -- Seconds between position checks
    debug = false,               -- Local debug logging (DMS.Settings debug also enables)
}

--------------------------------------------------------------------------------
-- Utility Functions
--------------------------------------------------------------------------------

local function isDebugEnabled()
    if DMS.Settings and DMS.Settings.isDebug and DMS.Settings.isDebug() then
        return true
    end
    return DMS.ZoneTracker.Config.debug == true
end

local function log(msg, level)
    level = level or "info"
    local timestamp = (timer and timer.getTime) and timer.getTime() or 0
    if level == "warning" then
        -- Warnings are always logged
        env.warning(string.format("[ZoneTracker %.1f] %s", timestamp, tostring(msg)))
    elseif isDebugEnabled() then
        env.info(string.format("[ZoneTracker %.1f] %s", timestamp, tostring(msg)))
    end
end

local function exists(obj)
    if obj == nil or type(obj) ~= "table" or type(obj.isExist) ~= "function" then
        return false
    end
    local ok, e = pcall(obj.isExist, obj)
    return ok and e and true or false
end

--- Check if group is in zone
-- @param groupName string Group name
-- @param zone table Zone object from trigger.misc.getZone()
-- @return boolean True if in zone
local function isGroupInZone(groupName, zone)
    if not zone or not zone.point or not zone.radius then return false end

    local okG, group = pcall(Group.getByName, groupName)
    if not okG or not exists(group) then return false end

    local okU, units = pcall(group.getUnits, group)
    if not okU or type(units) ~= "table" then return false end

    -- Check lead unit position (first surviving unit; original lead may be dead)
    local leadUnit = nil
    for _, u in ipairs(units) do
        if exists(u) then
            leadUnit = u
            break
        end
    end
    if not leadUnit then return false end

    local okP, pos = pcall(leadUnit.getPoint, leadUnit)
    if not okP or not pos then return false end
    local dx = pos.x - zone.point.x
    local dz = pos.z - zone.point.z
    local dist = math.sqrt(dx * dx + dz * dz)

    return dist <= zone.radius
end

--------------------------------------------------------------------------------
-- Core Functions
--------------------------------------------------------------------------------

--- Track a group through zones
-- @param config table Configuration:
--   - groupName (string, required): Group to track
--   - zones (table, required): Array of zone names (strings)
--   - zonePriority (table, optional): Zone priority order (zones[1] = highest)
--   - onEnter (function, optional): Callback(groupName, zoneName)
--   - onExit (function, optional): Callback(groupName, zoneName)
--   - preventDuplicateEntry (boolean, optional): Only trigger entry once per zone (default: true)
--   - allowMultipleExit (boolean, optional): Allow multiple exit triggers (default: true)
function DMS.ZoneTracker.track(config)
    if type(config) ~= "table" or not config.groupName or type(config.zones) ~= "table" then
        log("ERROR: groupName and zones required", "warning")
        return false
    end

    -- Cache zone objects
    local zoneObjects = {}
    for _, zoneName in ipairs(config.zones) do
        local okZ, zone = pcall(trigger.misc.getZone, zoneName)
        if okZ and zone then
            zoneObjects[zoneName] = zone
        else
            log("WARNING: Zone '" .. tostring(zoneName) .. "' not found in mission", "warning")
        end
    end

    local trackData = {
        groupName = config.groupName,
        zones = config.zones,
        zoneObjects = zoneObjects,
        zonePriority = config.zonePriority or config.zones,  -- Default: order given
        currentZone = nil,
        zonesEntered = {},       -- Track which zones have been entered
        onEnter = config.onEnter,
        onExit = config.onExit,
        preventDuplicateEntry = config.preventDuplicateEntry ~= false,  -- Default true
        allowMultipleExit = config.allowMultipleExit ~= false,         -- Default true
    }

    state.trackedGroups[config.groupName] = trackData
    log(string.format("Now tracking '%s' through %d zones", config.groupName, #config.zones))

    return true
end

--- Stop tracking a specific group
-- @param groupName string Group name
function DMS.ZoneTracker.untrack(groupName)
    if state.trackedGroups[groupName] then
        state.trackedGroups[groupName] = nil
        log("Stopped tracking: " .. groupName)
        return true
    end
    return false
end

--- Check zone positions for tracked group
-- @param trackData table Track data for group
local function checkZonePosition(trackData)
    local groupName = trackData.groupName
    local zoneObjects = trackData.zoneObjects
    local zonePriority = trackData.zonePriority

    -- Check which zone group is in (priority order)
    local newZone = nil
    for _, zoneName in ipairs(zonePriority) do
        if isGroupInZone(groupName, zoneObjects[zoneName]) then
            newZone = zoneName
            break
        end
    end

    -- Zone transition detected
    if newZone ~= trackData.currentZone then
        -- EXITING previous zone
        if trackData.currentZone then
            if trackData.onExit then
                local ok, err = pcall(trackData.onExit, groupName, trackData.currentZone)
                if not ok then
                    log(string.format("onExit callback error for '%s': %s", groupName, tostring(err)), "warning")
                end
            end
            log(string.format("'%s' exited '%s'", groupName, trackData.currentZone))
        end

        -- ENTERING new zone
        if newZone then
            -- Check if we should prevent duplicate entry
            local shouldTriggerEntry = true
            if trackData.preventDuplicateEntry and trackData.zonesEntered[newZone] then
                shouldTriggerEntry = false
            end

            if shouldTriggerEntry then
                if trackData.onEnter then
                    local ok, err = pcall(trackData.onEnter, groupName, newZone)
                    if not ok then
                        log(string.format("onEnter callback error for '%s': %s", groupName, tostring(err)), "warning")
                    end
                end
                trackData.zonesEntered[newZone] = true
                log(string.format("'%s' entered '%s'", groupName, newZone))
            end
        end

        trackData.currentZone = newZone
    end
end

--- Main tracking loop (DCS reschedule pattern; each group check pcall-guarded)
local function trackingLoop(_, time)
    if not state.active then
        state.timerId = nil
        return nil
    end

    -- Check all tracked groups (copy keys so callbacks may untrack safely)
    local names = {}
    for groupName in pairs(state.trackedGroups) do
        names[#names + 1] = groupName
    end
    for _, groupName in ipairs(names) do
        local trackData = state.trackedGroups[groupName]
        if trackData then
            local ok, err = pcall(checkZonePosition, trackData)
            if not ok then
                log(string.format("Check failed for '%s': %s", groupName, tostring(err)), "warning")
            end
        end
    end

    local interval = tonumber(DMS.ZoneTracker.Config.checkInterval) or 7
    if interval <= 0 then interval = 7 end
    return (time or timer.getTime()) + interval
end

--- Start the zone tracking system
function DMS.ZoneTracker.start()
    if state.active then
        log("Already started", "warning")
        return
    end

    state.active = true
    local count = 0
    for _ in pairs(state.trackedGroups) do count = count + 1 end
    log(string.format("Started - tracking %d groups (interval: %ds)",
        count, DMS.ZoneTracker.Config.checkInterval))

    state.timerId = timer.scheduleFunction(trackingLoop, nil, timer.getTime() + 1)
end

--- Stop the zone tracking system
function DMS.ZoneTracker.stop()
    state.active = false
    if state.timerId then
        pcall(timer.removeFunction, state.timerId)
        state.timerId = nil
    end
    log("Stopped")
end

--- Get current zone for a tracked group
-- @param groupName string Group name
-- @return string|nil Zone name or nil
function DMS.ZoneTracker.getCurrentZone(groupName)
    local trackData = state.trackedGroups[groupName]
    if trackData then
        return trackData.currentZone
    end
    return nil
end

--- Get zones entered by a tracked group
-- @param groupName string Group name
-- @return table Array of zone names entered
function DMS.ZoneTracker.getZonesEntered(groupName)
    local trackData = state.trackedGroups[groupName]
    if not trackData then return {} end

    local zones = {}
    for zoneName, _ in pairs(trackData.zonesEntered) do
        table.insert(zones, zoneName)
    end
    return zones
end

--- Check if group has entered a specific zone
-- @param groupName string Group name
-- @param zoneName string Zone name
-- @return boolean True if entered
function DMS.ZoneTracker.hasEnteredZone(groupName, zoneName)
    local trackData = state.trackedGroups[groupName]
    if trackData then
        return trackData.zonesEntered[zoneName] == true
    end
    return false
end

--- Get statistics
-- @return table Stats
function DMS.ZoneTracker.getStats()
    local groupCount = 0
    local activeCount = 0

    for groupName, trackData in pairs(state.trackedGroups) do
        groupCount = groupCount + 1
        if trackData.currentZone then
            activeCount = activeCount + 1
        end
    end

    return {
        trackedGroups = groupCount,
        groupsInZones = activeCount,
        active = state.active,
        checkInterval = DMS.ZoneTracker.Config.checkInterval,
    }
end

--- Clear all tracked groups
function DMS.ZoneTracker.clear()
    state.trackedGroups = {}
    log("Cleared all tracked groups")
end

--------------------------------------------------------------------------------
-- Configuration
--------------------------------------------------------------------------------

--- Configure the system
-- @param settings table Configuration overrides
function DMS.ZoneTracker.configure(settings)
    if type(settings) ~= "table" then return end
    for key, value in pairs(settings) do
        DMS.ZoneTracker.Config[key] = value
    end
end

--------------------------------------------------------------------------------
-- Utility Helper (if DMS.Utils not loaded)
--------------------------------------------------------------------------------

DMS.Utils = DMS.Utils or {}
if not DMS.Utils.tableLength then
    function DMS.Utils.tableLength(t)
        if type(t) ~= "table" then return 0 end
        local count = 0
        for _ in pairs(t) do count = count + 1 end
        return count
    end
end

log("DMS.ZoneTracker loaded")

return DMS.ZoneTracker
