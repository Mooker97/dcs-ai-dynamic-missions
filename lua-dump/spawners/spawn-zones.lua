-- Zone-Based Random Spawning for DCS Missions
-- Activates LATE ACTIVATION groups with spawn chance per zone
-- Requires: utils/coordinates.lua, utils/group-utils.lua
-- Place in mission via DO SCRIPT FILE

DMS = DMS or {}
DMS.SpawnZones = {}

-- Zone definitions: {centerX, centerZ, radius}
-- Use DCS coordinates: x = North/South, z = East/West
DMS.SpawnZones.Zones = {}

-- Spawn configurations
DMS.SpawnZones.Config = {}

--- Register a circular spawn zone
-- @param zoneName string Unique zone identifier
-- @param centerX number Center X coordinate (North/South)
-- @param centerZ number Center Z coordinate (East/West)
-- @param radius number Zone radius in meters
function DMS.SpawnZones.registerZone(zoneName, centerX, centerZ, radius)
    DMS.SpawnZones.Zones[zoneName] = {
        x = centerX,
        z = centerZ,
        radius = radius,
        type = "circle"
    }
end

--- Register a rectangular spawn zone
-- @param zoneName string Zone identifier
-- @param minX number South boundary
-- @param maxX number North boundary
-- @param minZ number West boundary
-- @param maxZ number East boundary
function DMS.SpawnZones.registerRectZone(zoneName, minX, maxX, minZ, maxZ)
    DMS.SpawnZones.Zones[zoneName] = {
        minX = minX,
        maxX = maxX,
        minZ = minZ,
        maxZ = maxZ,
        type = "rect"
    }
end

--- Register zone from DCS Mission Editor trigger zone
-- @param triggerZoneName string Name of trigger zone in ME
function DMS.SpawnZones.registerFromTriggerZone(triggerZoneName)
    local zone = trigger.misc.getZone(triggerZoneName)
    if zone then
        DMS.SpawnZones.Zones[triggerZoneName] = {
            x = zone.point.x,
            z = zone.point.z,
            radius = zone.radius,
            type = "circle"
        }
        return true
    end
    return false
end

--- Configure a group for zone spawning
-- @param groupName string Group name (must be LATE ACTIVATION)
-- @param zoneName string Zone name
-- @param spawnChance number Spawn probability (0-100)
function DMS.SpawnZones.configure(groupName, zoneName, spawnChance)
    table.insert(DMS.SpawnZones.Config, {
        groupName = groupName,
        zone = zoneName,
        spawnChance = spawnChance or 100,
        spawned = false
    })
end

--- Configure multiple groups for same zone
-- @param groupNames table Array of group names
-- @param zoneName string Zone name
-- @param spawnChance number Spawn probability for each
function DMS.SpawnZones.bulkConfigure(groupNames, zoneName, spawnChance)
    for _, name in ipairs(groupNames) do
        DMS.SpawnZones.configure(name, zoneName, spawnChance)
    end
end

--- Try to spawn a single configured group
-- @param config table Spawn configuration entry
-- @return boolean True if spawned
function DMS.SpawnZones.spawnGroup(config)
    if config.spawned then
        return false
    end

    -- Roll for spawn chance
    if math.random(1, 100) > config.spawnChance then
        config.spawned = true  -- Mark as processed
        return false
    end

    -- Verify zone exists
    local zone = DMS.SpawnZones.Zones[config.zone]
    if not zone then
        return false
    end

    -- Activate the group (spawns at original ME position)
    -- Note: DCS doesn't allow repositioning LATE ACTIVATION groups
    -- Use coalition.addGroup() for true position randomization
    local group = Group.getByName(config.groupName)
    if group then
        trigger.action.activateGroup(group)
        config.spawned = true
        return true
    end

    return false
end

--- Spawn all configured groups based on their spawn chances
-- @return number Count of groups spawned
function DMS.SpawnZones.spawnAll()
    local count = 0
    for _, config in ipairs(DMS.SpawnZones.Config) do
        if DMS.SpawnZones.spawnGroup(config) then
            count = count + 1
        end
    end
    return count
end

--- Spawn groups in a specific zone only
-- @param zoneName string Zone name
-- @return number Count spawned
function DMS.SpawnZones.spawnInZone(zoneName)
    local count = 0
    for _, config in ipairs(DMS.SpawnZones.Config) do
        if config.zone == zoneName and not config.spawned then
            if DMS.SpawnZones.spawnGroup(config) then
                count = count + 1
            end
        end
    end
    return count
end

--- Spawn all groups with random delays
-- @param minDelay number Minimum delay in seconds
-- @param maxDelay number Maximum delay in seconds
function DMS.SpawnZones.spawnAllDelayed(minDelay, maxDelay)
    for _, config in ipairs(DMS.SpawnZones.Config) do
        local delay = minDelay + math.random() * (maxDelay - minDelay)
        timer.scheduleFunction(function()
            DMS.SpawnZones.spawnGroup(config)
            return nil
        end, nil, timer.getTime() + delay)
    end
end

--- Get spawn statistics
-- @return table {total, spawned, skipped}
function DMS.SpawnZones.getStats()
    local spawned, skipped = 0, 0
    for _, config in ipairs(DMS.SpawnZones.Config) do
        if config.spawned then
            -- Check if group actually exists (was activated vs skipped)
            if DMS.Groups and DMS.Groups.isAlive(config.groupName) then
                spawned = spawned + 1
            else
                skipped = skipped + 1
            end
        end
    end
    return {
        total = #DMS.SpawnZones.Config,
        spawned = spawned,
        skipped = skipped
    }
end

--- Reset all spawn states (for mission restart)
function DMS.SpawnZones.reset()
    for _, config in ipairs(DMS.SpawnZones.Config) do
        config.spawned = false
    end
end

--[[
USAGE EXAMPLE:

-- Register zones
DMS.SpawnZones.registerZone("enemy_base", -50000, 40000, 3000)
DMS.SpawnZones.registerFromTriggerZone("Patrol Area")  -- From ME

-- Configure groups (must be LATE ACTIVATION in ME)
DMS.SpawnZones.configure("Enemy-1", "enemy_base", 75)  -- 75% chance
DMS.SpawnZones.configure("Enemy-2", "enemy_base", 50)  -- 50% chance

-- Bulk configure
DMS.SpawnZones.bulkConfigure(
    {"Patrol-1", "Patrol-2", "Patrol-3"},
    "Patrol Area",
    40
)

-- Spawn at mission start
local spawned = DMS.SpawnZones.spawnAll()
trigger.action.outText("Spawned " .. spawned .. " groups", 10)

-- Or spawn with delays
DMS.SpawnZones.spawnAllDelayed(30, 120)
]]

-- Export
_G.DMS = DMS
