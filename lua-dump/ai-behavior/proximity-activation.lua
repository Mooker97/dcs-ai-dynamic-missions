-- Proximity-Based Activation for DCS Missions
-- Activates LATE ACTIVATION groups when player approaches
-- Requires: utils/coordinates.lua, utils/group-utils.lua
-- Place in mission via DO SCRIPT FILE

DMS = DMS or {}
DMS.Proximity = {}

-- Tracked groups
DMS.Proximity.Groups = {}
DMS.Proximity.TimerId = nil
DMS.Proximity.Active = false

-- Configuration
DMS.Proximity.Config = {
    checkInterval = 5,           -- Seconds between checks
    defaultRadius = 20000,       -- Default activation radius (20km)
    defaultCoalition = coalition.side.BLUE,  -- Which coalition to track
    announceActivations = false, -- Show activation messages
    deactivateOnDistance = false, -- Deactivate when player leaves
    deactivateRadius = 50000,    -- Distance to deactivate (if enabled)
}

--- Configure proximity system
-- @param settings table Configuration overrides
function DMS.Proximity.configure(settings)
    for key, value in pairs(settings) do
        DMS.Proximity.Config[key] = value
    end
end

--- Register a group for proximity activation
-- @param groupName string Group name (must be LATE ACTIVATION)
-- @param centerX number|nil Activation center X (or group's ME position)
-- @param centerZ number|nil Activation center Z
-- @param radius number|nil Activation radius in meters
-- @param spawnChance number|nil Chance to spawn when triggered (0-100)
function DMS.Proximity.register(groupName, centerX, centerZ, radius, spawnChance)
    -- If no position given, we'll check against the group's actual position
    DMS.Proximity.Groups[groupName] = {
        name = groupName,
        centerX = centerX,
        centerZ = centerZ,
        radius = radius or DMS.Proximity.Config.defaultRadius,
        spawnChance = spawnChance or 100,
        activated = false,
        checked = false,
    }
end

--- Register multiple groups with same settings
-- @param groupNames table Array of group names
-- @param centerX number Activation center X
-- @param centerZ number Activation center Z
-- @param radius number|nil Activation radius
-- @param spawnChance number|nil Spawn chance
function DMS.Proximity.registerBulk(groupNames, centerX, centerZ, radius, spawnChance)
    for _, name in ipairs(groupNames) do
        DMS.Proximity.register(name, centerX, centerZ, radius, spawnChance)
    end
end

--- Register from trigger zone
-- @param groupName string Group name
-- @param triggerZoneName string Trigger zone name in ME
-- @param spawnChance number|nil Spawn chance
function DMS.Proximity.registerWithZone(groupName, triggerZoneName, spawnChance)
    local zone = trigger.misc.getZone(triggerZoneName)
    if zone then
        DMS.Proximity.register(
            groupName,
            zone.point.x,
            zone.point.z,
            zone.radius,
            spawnChance
        )
    end
end

--- Get player positions to check against
-- @return table Array of player Vec3 positions
local function getPlayerPositions()
    local positions = {}
    local coalitions = {coalition.side.BLUE, coalition.side.RED}

    for _, side in ipairs(coalitions) do
        local players = coalition.getPlayers(side)
        if players then
            for _, unit in ipairs(players) do
                if unit and unit:isExist() then
                    table.insert(positions, unit:getPoint())
                end
            end
        end
    end

    return positions
end

--- Check distance between point and player
-- @param centerX number Center X
-- @param centerZ number Center Z
-- @param playerPos table Player Vec3 position
-- @return number Distance in meters
local function getDistanceToPlayer(centerX, centerZ, playerPos)
    local dx = playerPos.x - centerX
    local dz = playerPos.z - centerZ
    return math.sqrt(dx * dx + dz * dz)
end

--- Process proximity checks
local function processProximityCheck(_, time)
    if not DMS.Proximity.Active then
        return nil
    end

    local playerPositions = getPlayerPositions()
    if #playerPositions == 0 then
        return time + DMS.Proximity.Config.checkInterval
    end

    for groupName, config in pairs(DMS.Proximity.Groups) do
        if not config.activated then
            local checkX = config.centerX
            local checkZ = config.centerZ

            -- If no position set, try to get from group
            if not checkX or not checkZ then
                local group = Group.getByName(groupName)
                if group then
                    local units = group:getUnits()
                    if units and #units > 0 then
                        local pos = units[1]:getPoint()
                        checkX = pos.x
                        checkZ = pos.z
                    end
                end
            end

            if checkX and checkZ then
                -- Check against all players
                for _, playerPos in ipairs(playerPositions) do
                    local dist = getDistanceToPlayer(checkX, checkZ, playerPos)

                    if dist <= config.radius then
                        -- Player in range, try to activate
                        config.checked = true

                        local roll = math.random(1, 100)
                        if roll <= config.spawnChance then
                            local group = Group.getByName(groupName)
                            if group then
                                trigger.action.activateGroup(group)
                                config.activated = true

                                if DMS.Settings and DMS.Settings.isDebug() then
                                    env.info(string.format("[Proximity] Activated '%s' (dist: %.0fm, rolled %d <= %d)",
                                        groupName, dist, roll, config.spawnChance))
                                end

                                if DMS.Proximity.Config.announceActivations then
                                    trigger.action.outText(
                                        "Contact! Enemy detected nearby.",
                                        5, true
                                    )
                                end
                            end
                        else
                            -- Failed spawn roll, mark as processed
                            config.activated = true
                            if DMS.Settings and DMS.Settings.isDebug() then
                                env.info(string.format("[Proximity] Skipped '%s' (rolled %d > %d)",
                                    groupName, roll, config.spawnChance))
                            end
                        end
                        break
                    end
                end
            end
        end

        -- Optional: Deactivate when player leaves (if enabled)
        if config.activated and DMS.Proximity.Config.deactivateOnDistance then
            local shouldDeactivate = true
            local checkX = config.centerX
            local checkZ = config.centerZ

            if checkX and checkZ then
                for _, playerPos in ipairs(playerPositions) do
                    local dist = getDistanceToPlayer(checkX, checkZ, playerPos)
                    if dist <= DMS.Proximity.Config.deactivateRadius then
                        shouldDeactivate = false
                        break
                    end
                end

                if shouldDeactivate then
                    local group = Group.getByName(groupName)
                    if group and group:isExist() then
                        trigger.action.deactivateGroup(group)
                        config.activated = false
                    end
                end
            end
        end
    end

    return time + DMS.Proximity.Config.checkInterval
end

--- Start proximity monitoring
function DMS.Proximity.start()
    if DMS.Proximity.Active then
        return
    end

    DMS.Proximity.Active = true
    DMS.Proximity.TimerId = timer.scheduleFunction(
        processProximityCheck,
        nil,
        timer.getTime() + DMS.Proximity.Config.checkInterval
    )

    if DMS.Settings and DMS.Settings.isDebug() then
        local count = 0
        for _ in pairs(DMS.Proximity.Groups) do count = count + 1 end
        env.info(string.format("[Proximity] Started monitoring %d groups (radius: %dm, interval: %ds)",
            count, DMS.Proximity.Config.defaultRadius, DMS.Proximity.Config.checkInterval))
    end
end

--- Stop proximity monitoring
function DMS.Proximity.stop()
    DMS.Proximity.Active = false
    if DMS.Proximity.TimerId then
        timer.removeFunction(DMS.Proximity.TimerId)
        DMS.Proximity.TimerId = nil
    end
end

--- Get statistics
-- @return table {registered, activated, pending}
function DMS.Proximity.getStats()
    local activated, pending = 0, 0
    for _, config in pairs(DMS.Proximity.Groups) do
        if config.activated then
            activated = activated + 1
        else
            pending = pending + 1
        end
    end

    local total = 0
    for _ in pairs(DMS.Proximity.Groups) do
        total = total + 1
    end

    return {
        registered = total,
        activated = activated,
        pending = pending
    }
end

--- Force activate a specific group
-- @param groupName string Group name
function DMS.Proximity.forceActivate(groupName)
    local config = DMS.Proximity.Groups[groupName]
    if config and not config.activated then
        local group = Group.getByName(groupName)
        if group then
            trigger.action.activateGroup(group)
            config.activated = true
        end
    end
end

--- Reset a group for re-activation
-- @param groupName string Group name
function DMS.Proximity.reset(groupName)
    local config = DMS.Proximity.Groups[groupName]
    if config then
        config.activated = false
        config.checked = false
    end
end

--[[
USAGE EXAMPLE:

-- Configure
DMS.Proximity.configure({
    checkInterval = 3,
    defaultRadius = 15000,  -- 15km
    announceActivations = true
})

-- Register groups
DMS.Proximity.register("Enemy-1", -50000, 40000, 10000, 75)  -- 10km radius, 75% chance
DMS.Proximity.register("Enemy-2", -55000, 45000)  -- Default radius and 100% chance

-- Register with trigger zone
DMS.Proximity.registerWithZone("Ambush-1", "Ambush Zone", 80)

-- Bulk register
DMS.Proximity.registerBulk(
    {"SAM-1", "SAM-2", "SAM-3"},
    -60000, 50000,
    20000,
    50
)

-- Start monitoring
DMS.Proximity.start()

-- Check stats
local stats = DMS.Proximity.getStats()
trigger.action.outText("Pending threats: " .. stats.pending, 10)
]]

-- Export
_G.DMS = DMS
