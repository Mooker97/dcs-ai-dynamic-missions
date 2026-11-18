-- Random Spawn Pool System for DCS Missions
-- Pick N random groups from a pool with overall spawn chance
-- Requires: spawners/spawn-core.lua
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

--- Activate the selected groups of a pool (shared by executePool / forceSpawn)
-- @param pool table
-- @param selected table Array of group names
-- @return number Count activated
local function activateSelected(pool, selected)
    local Core = DMS.SpawnCore
    if not Core then
        env.error("[SpawnPool] spawners/spawn-core.lua is not loaded")
        return 0
    end
    local spawned = 0
    for _, groupName in ipairs(selected) do
        local ok, activated = Core.safeCall(Core.activate,
            "SpawnPool.activate(" .. tostring(groupName) .. ")",
            groupName, {hidden = pool.hidden, prefix = "SpawnPool"})
        if ok and activated then
            table.insert(pool.spawnedGroups, groupName)
            spawned = spawned + 1
        end
    end
    return spawned
end

--- Pick up to pool.count groups that are not active yet
local function selectGroups(pool, count)
    local Core = DMS.SpawnCore
    local candidates = {}
    for _, name in ipairs(pool.groups) do
        if not (Core and Core.isGroupActive(name)) then
            table.insert(candidates, name)
        end
    end
    if Core then
        return Core.pickRandom(candidates, count or pool.count)
    end
    return {}
end

--- Spawn (activate) groups of a pool after an optional delay
local function spawnWithDelay(pool, selected, delay)
    if delay and delay > 0 and DMS.SpawnCore then
        pool.timerId = DMS.SpawnCore.schedule(function()
            pool.timerId = nil
            activateSelected(pool, selected)
        end, delay, "SpawnPool.doSpawn(" .. pool.id .. ")")
        return #selected, true
    end
    return activateSelected(pool, selected), false
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

    local selected = selectGroups(pool)

    -- Calculate delay
    local delay = pool.delay
    if pool.minDelay and pool.maxDelay then
        delay = math.random(pool.minDelay, pool.maxDelay)
    end

    local spawned, delayed = spawnWithDelay(pool, selected, delay)

    if DMS.Settings and DMS.Settings.isDebug() then
        env.info(string.format("[SpawnPool] Pool '%s' rolled %d <= %d: %d group(s)%s",
            poolId, roll, pool.chance, #selected, delayed and string.format(" in %ds", delay) or ""))
    end

    return {success = true, spawned = spawned, selected = selected, delayed = delayed}
end

--- Force a pool to spawn now, ignoring its chance roll and executed state.
-- Used by events/conditional-triggers.lua and events/event-chain.lua.
-- @param poolId string Pool identifier
-- @param count number|nil Override how many groups to activate
-- @return table Results {success, spawned, selected}
function DMS.SpawnPool.forceSpawn(poolId, count)
    local pool = DMS.SpawnPool.Pools[poolId]
    if not pool then
        env.warning(string.format("[SpawnPool] forceSpawn: pool '%s' not found", tostring(poolId)))
        return {success = false, spawned = 0, selected = {}}
    end

    pool.executed = true
    local selected = selectGroups(pool, count)
    local spawned = activateSelected(pool, selected)

    if DMS.Settings and DMS.Settings.isDebug() then
        env.info(string.format("[SpawnPool] Force-spawned pool '%s': %d group(s)", poolId, spawned))
    end

    return {success = spawned > 0, spawned = spawned, selected = selected}
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
        if pool.timerId then
            pcall(timer.removeFunction, pool.timerId)
            pool.timerId = nil
        end
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
