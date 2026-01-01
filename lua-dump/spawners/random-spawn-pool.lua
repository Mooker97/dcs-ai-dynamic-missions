-- Random Spawn Pool System for DCS Missions
-- Pick N random groups from a pool with overall spawn chance
-- Place in mission via DO SCRIPT FILE

DMS = DMS or {}
DMS.SpawnPool = {}

-- Registered pools
DMS.SpawnPool.Pools = {}

-- Configuration
DMS.SpawnPool.Config = {
    defaultChance = 100,     -- Default overall spawn chance
    defaultCount = 1,        -- Default number to pick from pool
}

--- Configure spawn pool system
-- @param settings table Configuration overrides
function DMS.SpawnPool.configure(settings)
    for key, value in pairs(settings) do
        DMS.SpawnPool.Config[key] = value
    end
end

--- Create a new spawn pool
-- @param poolId string Unique pool identifier
-- @param options table|nil Pool options {chance, count, delay, hidden}
-- @return table Pool reference
function DMS.SpawnPool.create(poolId, options)
    options = options or {}

    DMS.SpawnPool.Pools[poolId] = {
        id = poolId,
        groups = {},
        chance = options.chance or DMS.SpawnPool.Config.defaultChance,
        count = options.count or DMS.SpawnPool.Config.defaultCount,
        delay = options.delay or 0,
        minDelay = options.minDelay,
        maxDelay = options.maxDelay,
        hidden = options.hidden,  -- nil = use settings default, true/false = override
        executed = false,
        spawnedGroups = {},
    }

    return DMS.SpawnPool.Pools[poolId]
end

--- Add group to a pool
-- @param poolId string Pool identifier
-- @param groupName string Group name to add
function DMS.SpawnPool.addGroup(poolId, groupName)
    local pool = DMS.SpawnPool.Pools[poolId]
    if pool then
        table.insert(pool.groups, groupName)
    end
end

--- Add multiple groups to a pool
-- @param poolId string Pool identifier
-- @param groupNames table Array of group names
function DMS.SpawnPool.addGroups(poolId, groupNames)
    for _, name in ipairs(groupNames) do
        DMS.SpawnPool.addGroup(poolId, name)
    end
end

--- Add groups by pattern to a pool
-- Groups named "Prefix-1", "Prefix-2", etc.
-- @param poolId string Pool identifier
-- @param prefix string Group name prefix
-- @param count number Number of groups
function DMS.SpawnPool.addPattern(poolId, prefix, count)
    for i = 1, count do
        DMS.SpawnPool.addGroup(poolId, prefix .. "-" .. i)
    end
end

--- Shuffle array (Fisher-Yates)
-- @param arr table Array to shuffle
-- @return table Shuffled array
local function shuffle(arr)
    local shuffled = {}
    for i, v in ipairs(arr) do
        shuffled[i] = v
    end

    for i = #shuffled, 2, -1 do
        local j = math.random(1, i)
        shuffled[i], shuffled[j] = shuffled[j], shuffled[i]
    end

    return shuffled
end

--- Execute spawn for a specific pool
-- @param poolId string Pool identifier
-- @return table Results {success, spawned, selected}
function DMS.SpawnPool.executePool(poolId)
    local pool = DMS.SpawnPool.Pools[poolId]
    if not pool or pool.executed then
        return {success = false, spawned = 0, selected = {}}
    end

    pool.executed = true

    -- Roll for overall spawn chance
    local roll = math.random(1, 100)
    if roll > pool.chance then
        if DMS.Settings and DMS.Settings.isDebug() then
            env.info(string.format("[SpawnPool] Pool '%s' skipped (rolled %d, needed <= %d)",
                poolId, roll, pool.chance))
        end
        return {success = false, spawned = 0, selected = {}}
    end

    -- Shuffle and pick N groups
    local shuffled = shuffle(pool.groups)
    local toSpawn = math.min(pool.count, #shuffled)
    local selected = {}

    for i = 1, toSpawn do
        table.insert(selected, shuffled[i])
    end

    -- Spawn function
    local function doSpawn()
        local spawned = 0
        -- Determine hidden state: pool override > settings default
        local hidden = pool.hidden
        if hidden == nil and DMS.Settings then
            hidden = DMS.Settings.getSpawnHidden()
        end

        for _, groupName in ipairs(selected) do
            local group = Group.getByName(groupName)
            if group then
                -- Use fog of war system if available and hidden is needed
                if hidden and DMS.FogOfWar then
                    DMS.FogOfWar.activateGroup(groupName, true)
                else
                    trigger.action.activateGroup(group)
                end
                table.insert(pool.spawnedGroups, groupName)
                spawned = spawned + 1

                -- Debug logging
                if DMS.Settings and DMS.Settings.isDebug() then
                    env.info(string.format("[SpawnPool] Activated: %s (hidden: %s)",
                        groupName, tostring(hidden or false)))
                end
            end
        end
        return spawned
    end

    -- Calculate delay
    local delay = pool.delay
    if pool.minDelay and pool.maxDelay then
        delay = math.random(pool.minDelay, pool.maxDelay)
    end

    -- Execute with or without delay
    if delay > 0 then
        DMS.Error.safeSchedule(doSpawn, delay, "SpawnPool.doSpawn(" .. poolId .. ")")
        return {success = true, spawned = toSpawn, selected = selected, delayed = true}
    else
        local success, spawned = DMS.Error.safeCall(doSpawn, "SpawnPool.doSpawn(" .. poolId .. ")")
        return {success = true, spawned = spawned or 0, selected = selected, delayed = false}
    end
end

--- Execute all registered pools
-- @return table Results by pool ID
function DMS.SpawnPool.executeAll()
    local results = {}

    for poolId, _ in pairs(DMS.SpawnPool.Pools) do
        results[poolId] = DMS.SpawnPool.executePool(poolId)
    end

    return results
end

--- Reset a pool for re-execution
-- @param poolId string Pool identifier
function DMS.SpawnPool.reset(poolId)
    local pool = DMS.SpawnPool.Pools[poolId]
    if pool then
        pool.executed = false
        pool.spawnedGroups = {}
    end
end

--- Get pool info
-- @param poolId string Pool identifier
-- @return table|nil Pool information
function DMS.SpawnPool.getInfo(poolId)
    local pool = DMS.SpawnPool.Pools[poolId]
    if pool then
        return {
            id = pool.id,
            groupCount = #pool.groups,
            chance = pool.chance,
            pickCount = pool.count,
            executed = pool.executed,
            spawnedGroups = pool.spawnedGroups,
        }
    end
    return nil
end

--[[
USAGE EXAMPLE:

-- Create AA pool: 35% chance to spawn exactly 1 random AA
DMS.SpawnPool.create("aa_threat", {
    chance = 35,    -- 35% overall chance
    count = 1,      -- Pick 1 from pool
})

-- Add AA groups to pool
DMS.SpawnPool.addPattern("aa_threat", "AA", 16)  -- AA-1 through AA-16
-- Or manually:
-- DMS.SpawnPool.addGroups("aa_threat", {"AA-1", "AA-2", "AA-3", ...})

-- Create armor pool: 50% chance to spawn 2-3 random armor groups
-- With explicit hidden override (hidden from F10 map)
DMS.SpawnPool.create("armor_threat", {
    chance = 50,
    count = 3,      -- Pick up to 3
    minDelay = 120, -- 2-5 minute delay
    maxDelay = 300,
    hidden = true,  -- Force hidden (overrides DMS.Settings.fogOfWar)
})
DMS.SpawnPool.addPattern("armor_threat", "Armor", 8)

-- Create pool that uses mission settings for hidden state
DMS.SpawnPool.create("patrol", {
    chance = 75,
    count = 1,
    -- hidden not specified = uses DMS.Settings.getSpawnHidden()
})

-- Execute single pool
local result = DMS.SpawnPool.executePool("aa_threat")
if result.success then
    env.info("Spawned AA: " .. table.concat(result.selected, ", "))
end

-- Or execute all pools at once
local allResults = DMS.SpawnPool.executeAll()
]]

-- Export
_G.DMS = DMS
