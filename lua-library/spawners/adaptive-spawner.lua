-- Adaptive Spawner System for DCS Missions
-- Dynamically adjusts spawn density based on player performance
-- Place in mission via DO SCRIPT FILE

DMS = DMS or {}
DMS.AdaptiveSpawner = {}

-- Spawn pools
DMS.AdaptiveSpawner.Pools = {}
DMS.AdaptiveSpawner.Active = false
DMS.AdaptiveSpawner.TimerId = nil

-- Tracking
DMS.AdaptiveSpawner.Stats = {
    totalSpawned = 0,
    currentDifficulty = "normal",
    spawnsSinceAdjust = 0,
    lastSpawnTime = 0,
}

-- Difficulty levels
DMS.AdaptiveSpawner.DIFFICULTY = {
    EASY = "easy",
    NORMAL = "normal",
    HARD = "hard",
    NIGHTMARE = "nightmare",
}

-- Configuration
DMS.AdaptiveSpawner.Config = {
    -- Timing
    baseSpawnInterval = 120,      -- Base spawn interval in seconds
    minSpawnInterval = 45,        -- Minimum interval (hard mode)
    maxSpawnInterval = 300,       -- Maximum interval (easy mode)
    checkInterval = 30,           -- How often to check for spawning

    -- Difficulty adjustments
    intervalMultipliers = {
        easy = 2.0,
        normal = 1.0,
        hard = 0.6,
        nightmare = 0.4,
    },

    -- Resource limits
    maxSpawns = -1,               -- Total spawns allowed (-1 = unlimited)
    maxActiveGroups = 10,         -- Max groups active at once
    maxActiveUnits = 50,          -- Max units active at once

    -- Rubber-banding (prevent wild swings)
    maxDifficultyChange = 1,      -- Max levels to change per adjustment
    adjustmentCooldown = 120,     -- Seconds between difficulty changes

    -- Integration
    useSkillScaling = true,       -- Link to DMS.SkillScaling if available

    -- Coalition
    spawnCoalition = coalition.side.RED,
    playerCoalition = coalition.side.BLUE,

    announceSpawns = false,
}

-- Unit compositions by difficulty
DMS.AdaptiveSpawner.Compositions = {
    easy = {
        {type = "infantry", weight = 0.6, groups = {}},
        {type = "technical", weight = 0.3, groups = {}},
        {type = "aaa_light", weight = 0.1, groups = {}},
    },
    normal = {
        {type = "infantry", weight = 0.3, groups = {}},
        {type = "ifv", weight = 0.3, groups = {}},
        {type = "tank_light", weight = 0.2, groups = {}},
        {type = "aaa", weight = 0.2, groups = {}},
    },
    hard = {
        {type = "ifv", weight = 0.2, groups = {}},
        {type = "tank", weight = 0.3, groups = {}},
        {type = "aaa_heavy", weight = 0.2, groups = {}},
        {type = "sam_short", weight = 0.3, groups = {}},
    },
    nightmare = {
        {type = "tank_heavy", weight = 0.3, groups = {}},
        {type = "sam_medium", weight = 0.3, groups = {}},
        {type = "attack_helo", weight = 0.2, groups = {}},
        {type = "combined", weight = 0.2, groups = {}},
    },
}

--- Configure adaptive spawner
-- @param settings table Configuration overrides
function DMS.AdaptiveSpawner.configure(settings)
    for key, value in pairs(settings) do
        DMS.AdaptiveSpawner.Config[key] = value
    end
end

--- Set unit compositions
-- @param compositions table Composition definitions by difficulty
function DMS.AdaptiveSpawner.setCompositions(compositions)
    for difficulty, types in pairs(compositions) do
        DMS.AdaptiveSpawner.Compositions[difficulty] = types
    end
end

--- Register a spawn pool
-- @param poolId string Unique pool ID
-- @param groups table Array of group names
-- @param options table|nil Pool options
function DMS.AdaptiveSpawner.registerPool(poolId, groups, options)
    options = options or {}

    DMS.AdaptiveSpawner.Pools[poolId] = {
        id = poolId,
        groups = groups,
        unitType = options.unitType or "generic",
        spawnZone = options.spawnZone,
        weight = options.weight or 1.0,
        maxSpawns = options.maxSpawns or -1,
        spawned = 0,
        cooldown = options.cooldown or 0,
        lastSpawned = 0,
        enabled = true,
    }

    -- Add to composition if type specified
    if options.unitType and options.difficulty then
        local diff = options.difficulty
        if DMS.AdaptiveSpawner.Compositions[diff] then
            for _, comp in ipairs(DMS.AdaptiveSpawner.Compositions[diff]) do
                if comp.type == options.unitType then
                    table.insert(comp.groups, poolId)
                    break
                end
            end
        end
    end
end

--- Add groups to a unit type for a difficulty
-- @param difficulty string Difficulty level
-- @param unitType string Unit type
-- @param poolIds table Array of pool IDs
function DMS.AdaptiveSpawner.addToComposition(difficulty, unitType, poolIds)
    local comp = DMS.AdaptiveSpawner.Compositions[difficulty]
    if not comp then return end

    for _, entry in ipairs(comp) do
        if entry.type == unitType then
            for _, poolId in ipairs(poolIds) do
                table.insert(entry.groups, poolId)
            end
            return
        end
    end

    -- Add new type if not found
    table.insert(comp, {
        type = unitType,
        weight = 0.25,
        groups = poolIds,
    })
end

--- Get current spawn interval
-- @return number Spawn interval in seconds
function DMS.AdaptiveSpawner.getSpawnInterval()
    local difficulty = DMS.AdaptiveSpawner.Stats.currentDifficulty
    local multiplier = DMS.AdaptiveSpawner.Config.intervalMultipliers[difficulty] or 1.0
    local interval = DMS.AdaptiveSpawner.Config.baseSpawnInterval * multiplier

    return math.max(
        DMS.AdaptiveSpawner.Config.minSpawnInterval,
        math.min(DMS.AdaptiveSpawner.Config.maxSpawnInterval, interval)
    )
end

--- Get current unit composition
-- @return table Composition for current difficulty
function DMS.AdaptiveSpawner.getUnitComposition()
    local difficulty = DMS.AdaptiveSpawner.Stats.currentDifficulty
    return DMS.AdaptiveSpawner.Compositions[difficulty] or
           DMS.AdaptiveSpawner.Compositions.normal
end

--- Count active groups
-- @return number Active group count
local function countActiveGroups()
    local count = 0
    local groups = coalition.getGroups(DMS.AdaptiveSpawner.Config.spawnCoalition)
    if groups then
        for _, group in ipairs(groups) do
            if group:isExist() then
                local units = group:getUnits()
                for _, unit in ipairs(units or {}) do
                    if unit and unit:isExist() and unit:getLife() > 1 then
                        count = count + 1
                        break
                    end
                end
            end
        end
    end
    return count
end

--- Count active units
-- @return number Active unit count
local function countActiveUnits()
    local count = 0
    local groups = coalition.getGroups(DMS.AdaptiveSpawner.Config.spawnCoalition)
    if groups then
        for _, group in ipairs(groups) do
            if group:isExist() then
                local units = group:getUnits()
                for _, unit in ipairs(units or {}) do
                    if unit and unit:isExist() and unit:getLife() > 1 then
                        count = count + 1
                    end
                end
            end
        end
    end
    return count
end

--- Select pool based on composition
-- @return string|nil Selected pool ID
local function selectPool()
    local composition = DMS.AdaptiveSpawner.getUnitComposition()

    -- Build weighted selection
    local totalWeight = 0
    local options = {}

    for _, entry in ipairs(composition) do
        if #entry.groups > 0 then
            for _, poolId in ipairs(entry.groups) do
                local pool = DMS.AdaptiveSpawner.Pools[poolId]
                if pool and pool.enabled then
                    -- Check pool limits
                    if pool.maxSpawns < 0 or pool.spawned < pool.maxSpawns then
                        -- Check cooldown
                        local currentTime = timer.getTime()
                        if currentTime - pool.lastSpawned >= pool.cooldown then
                            local weight = entry.weight * pool.weight
                            totalWeight = totalWeight + weight
                            table.insert(options, {
                                poolId = poolId,
                                weight = weight,
                                cumWeight = totalWeight,
                            })
                        end
                    end
                end
            end
        end
    end

    if totalWeight == 0 or #options == 0 then
        return nil
    end

    -- Weighted random selection
    local roll = math.random() * totalWeight
    for _, option in ipairs(options) do
        if roll <= option.cumWeight then
            return option.poolId
        end
    end

    return options[#options].poolId
end

--- Spawn from a pool
-- @param poolId string Pool ID
-- @return boolean Success
local function spawnFromPool(poolId)
    local pool = DMS.AdaptiveSpawner.Pools[poolId]
    if not pool or #pool.groups == 0 then return false end

    -- Select random group from pool
    local groupName = pool.groups[math.random(#pool.groups)]
    local group = Group.getByName(groupName)

    if group then
        trigger.action.activateGroup(group)
        pool.spawned = pool.spawned + 1
        pool.lastSpawned = timer.getTime()
        DMS.AdaptiveSpawner.Stats.totalSpawned = DMS.AdaptiveSpawner.Stats.totalSpawned + 1
        DMS.AdaptiveSpawner.Stats.spawnsSinceAdjust = DMS.AdaptiveSpawner.Stats.spawnsSinceAdjust + 1
        DMS.AdaptiveSpawner.Stats.lastSpawnTime = timer.getTime()

        if DMS.AdaptiveSpawner.Config.announceSpawns then
            trigger.action.outText(string.format(
                "[AdaptiveSpawner] Spawned: %s (Pool: %s, Difficulty: %s)",
                groupName, poolId, DMS.AdaptiveSpawner.Stats.currentDifficulty
            ), 5)
        end

        return true
    end

    return false
end

--- Set difficulty level
-- @param difficulty string Difficulty level
function DMS.AdaptiveSpawner.setDifficulty(difficulty)
    if not DMS.AdaptiveSpawner.Compositions[difficulty] then
        return
    end

    local oldDifficulty = DMS.AdaptiveSpawner.Stats.currentDifficulty
    DMS.AdaptiveSpawner.Stats.currentDifficulty = difficulty
    DMS.AdaptiveSpawner.Stats.spawnsSinceAdjust = 0

    if oldDifficulty ~= difficulty then
        if DMS.AdaptiveSpawner.Config.announceSpawns then
            trigger.action.outText(string.format(
                "[AdaptiveSpawner] Difficulty changed: %s -> %s",
                oldDifficulty, difficulty
            ), 10)
        end
    end
end

--- Get difficulty from skill level
-- @param skillLevel string Skill level from SkillScaling
-- @return string Difficulty level
local function skillToDifficulty(skillLevel)
    local mapping = {
        ["Rookie"] = "easy",
        ["Average"] = "easy",
        ["Good"] = "normal",
        ["High"] = "hard",
        ["Excellent"] = "nightmare",
    }
    return mapping[skillLevel] or "normal"
end

--- Update difficulty from SkillScaling
local function updateFromSkillScaling()
    if not DMS.AdaptiveSpawner.Config.useSkillScaling then return end
    if not DMS.SkillScaling then return end

    local skill = DMS.SkillScaling.getCurrentSkill()
    if skill then
        local newDifficulty = skillToDifficulty(skill)

        -- Apply rubber-banding
        local difficulties = {"easy", "normal", "hard", "nightmare"}
        local currentIdx, newIdx

        for i, d in ipairs(difficulties) do
            if d == DMS.AdaptiveSpawner.Stats.currentDifficulty then
                currentIdx = i
            end
            if d == newDifficulty then
                newIdx = i
            end
        end

        if currentIdx and newIdx then
            local maxChange = DMS.AdaptiveSpawner.Config.maxDifficultyChange
            local change = math.max(-maxChange, math.min(maxChange, newIdx - currentIdx))
            local clampedIdx = math.max(1, math.min(#difficulties, currentIdx + change))
            newDifficulty = difficulties[clampedIdx]
        end

        DMS.AdaptiveSpawner.setDifficulty(newDifficulty)
    end
end

--- Process spawn cycle (internal, wrapped with error handler)
local function processSpawningInternal(_, time)
    if not DMS.AdaptiveSpawner.Active then return nil end

    -- Update difficulty from skill scaling
    updateFromSkillScaling()

    -- Check global limits
    local config = DMS.AdaptiveSpawner.Config
    if config.maxSpawns > 0 and DMS.AdaptiveSpawner.Stats.totalSpawned >= config.maxSpawns then
        return time + config.checkInterval
    end

    if countActiveGroups() >= config.maxActiveGroups then
        return time + config.checkInterval
    end

    if countActiveUnits() >= config.maxActiveUnits then
        return time + config.checkInterval
    end

    -- Check spawn interval
    local interval = DMS.AdaptiveSpawner.getSpawnInterval()
    local timeSinceSpawn = time - DMS.AdaptiveSpawner.Stats.lastSpawnTime

    if timeSinceSpawn < interval then
        return time + config.checkInterval
    end

    -- Select and spawn
    local poolId = selectPool()
    if poolId then
        spawnFromPool(poolId)
    end

    return time + config.checkInterval
end

--- Process spawn cycle with error handling
local function processSpawning(args, time)
    local success, result = pcall(processSpawningInternal, args, time)
    if not success then
        if DMS.Error then
            DMS.Error.log("AdaptiveSpawner.processSpawning", result)
        else
            env.error("[DMS LUA ERROR] AdaptiveSpawner.processSpawning: " .. tostring(result))
        end
        -- Continue running despite error
        return time + (DMS.AdaptiveSpawner.Config.checkInterval or 30)
    end
    return result
end

--- Start adaptive spawner
function DMS.AdaptiveSpawner.start()
    if DMS.AdaptiveSpawner.Active then return end

    DMS.AdaptiveSpawner.Active = true
    DMS.AdaptiveSpawner.Stats.lastSpawnTime = timer.getTime()

    DMS.AdaptiveSpawner.TimerId = timer.scheduleFunction(
        processSpawning,
        nil,
        timer.getTime() + DMS.AdaptiveSpawner.Config.checkInterval
    )
end

--- Stop adaptive spawner
function DMS.AdaptiveSpawner.stop()
    DMS.AdaptiveSpawner.Active = false
    if DMS.AdaptiveSpawner.TimerId then
        timer.removeFunction(DMS.AdaptiveSpawner.TimerId)
        DMS.AdaptiveSpawner.TimerId = nil
    end
end

--- Force a spawn
-- @param poolId string|nil Specific pool (nil = auto-select)
function DMS.AdaptiveSpawner.forceSpawn(poolId)
    if poolId then
        spawnFromPool(poolId)
    else
        local selected = selectPool()
        if selected then
            spawnFromPool(selected)
        end
    end
end

--- Get spawner stats
-- @return table Current stats
function DMS.AdaptiveSpawner.getStats()
    return {
        totalSpawned = DMS.AdaptiveSpawner.Stats.totalSpawned,
        currentDifficulty = DMS.AdaptiveSpawner.Stats.currentDifficulty,
        spawnInterval = DMS.AdaptiveSpawner.getSpawnInterval(),
        activeGroups = countActiveGroups(),
        activeUnits = countActiveUnits(),
        remainingSpawns = DMS.AdaptiveSpawner.Config.maxSpawns > 0
            and (DMS.AdaptiveSpawner.Config.maxSpawns - DMS.AdaptiveSpawner.Stats.totalSpawned)
            or "unlimited",
    }
end

--- Get remaining resources (for finite pool)
-- @return number|nil Remaining spawns (nil if unlimited)
function DMS.AdaptiveSpawner.getRemainingResources()
    if DMS.AdaptiveSpawner.Config.maxSpawns < 0 then
        return nil
    end
    return DMS.AdaptiveSpawner.Config.maxSpawns - DMS.AdaptiveSpawner.Stats.totalSpawned
end

--- Enable/disable a pool
-- @param poolId string Pool ID
-- @param enabled boolean Enable state
function DMS.AdaptiveSpawner.setPoolEnabled(poolId, enabled)
    local pool = DMS.AdaptiveSpawner.Pools[poolId]
    if pool then
        pool.enabled = enabled
    end
end

--[[
USAGE EXAMPLE:

-- Configure
DMS.AdaptiveSpawner.configure({
    baseSpawnInterval = 90,
    minSpawnInterval = 30,
    maxSpawnInterval = 180,
    maxSpawns = 50,           -- Finite enemy pool
    maxActiveGroups = 8,
    maxActiveUnits = 40,
    useSkillScaling = true,
    announceSpawns = true,
})

-- Register spawn pools
DMS.AdaptiveSpawner.registerPool("infantry_squad_1", {"INF-1", "INF-2", "INF-3"}, {
    unitType = "infantry",
    difficulty = "easy",
    weight = 1.0,
})

DMS.AdaptiveSpawner.registerPool("technical_patrol", {"TECH-1", "TECH-2"}, {
    unitType = "technical",
    difficulty = "easy",
    weight = 0.8,
})

DMS.AdaptiveSpawner.registerPool("bmp_section", {"BMP-1", "BMP-2"}, {
    unitType = "ifv",
    difficulty = "normal",
    weight = 1.0,
})

DMS.AdaptiveSpawner.registerPool("t72_platoon", {"T72-1", "T72-2"}, {
    unitType = "tank",
    difficulty = "hard",
    weight = 1.2,
    cooldown = 180,  -- 3 minute cooldown between spawns
})

DMS.AdaptiveSpawner.registerPool("sa15_battery", {"SA15-1"}, {
    unitType = "sam_short",
    difficulty = "hard",
    weight = 0.8,
    maxSpawns = 2,  -- Only 2 of these in mission
})

-- Or set compositions manually
DMS.AdaptiveSpawner.setCompositions({
    easy = {
        {type = "infantry", weight = 0.7, groups = {"infantry_squad_1"}},
        {type = "technical", weight = 0.3, groups = {"technical_patrol"}},
    },
    normal = {
        {type = "infantry", weight = 0.3, groups = {"infantry_squad_1"}},
        {type = "ifv", weight = 0.4, groups = {"bmp_section"}},
        {type = "tank", weight = 0.3, groups = {"t72_platoon"}},
    },
    hard = {
        {type = "tank", weight = 0.5, groups = {"t72_platoon"}},
        {type = "sam", weight = 0.5, groups = {"sa15_battery"}},
    },
})

-- Start spawner
DMS.AdaptiveSpawner.start()

-- Manual difficulty control
DMS.AdaptiveSpawner.setDifficulty("hard")

-- Check stats
local stats = DMS.AdaptiveSpawner.getStats()
trigger.action.outText(string.format(
    "Spawns: %d, Difficulty: %s, Interval: %ds, Active: %d groups",
    stats.totalSpawned, stats.currentDifficulty,
    stats.spawnInterval, stats.activeGroups
), 10)

-- Integration with SkillScaling (automatic)
-- When player does well -> difficulty increases -> harder units spawn faster
-- When player struggles -> difficulty decreases -> easier units spawn slower

-- Force spawn for scripted events
DMS.AdaptiveSpawner.forceSpawn("t72_platoon")
]]

-- Export
_G.DMS = DMS
