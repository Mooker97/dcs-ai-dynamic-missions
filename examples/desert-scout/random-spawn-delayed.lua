-- Random Enemy Spawner with Delays for Desert Scout
-- Place this in a DO SCRIPT trigger at mission start

-- Configuration (matches Desert Scout.miz)
local spawnGroups = {
    -- Tech groups (25% chance, 1-3 min delay) - 10 groups, expect ~2.5 spawns
    {name = "Tech-1", spawnChance = 25, minTime = 60, maxTime = 180},
    {name = "Tech-2", spawnChance = 25, minTime = 60, maxTime = 180},
    {name = "Tech-3", spawnChance = 25, minTime = 60, maxTime = 180},
    {name = "Tech-4", spawnChance = 25, minTime = 60, maxTime = 180},
    {name = "Tech-5", spawnChance = 25, minTime = 60, maxTime = 180},
    {name = "Tech-6", spawnChance = 25, minTime = 60, maxTime = 180},
    {name = "Tech-7", spawnChance = 25, minTime = 60, maxTime = 180},
    {name = "Tech-8", spawnChance = 25, minTime = 60, maxTime = 180},
    {name = "Tech-9", spawnChance = 25, minTime = 60, maxTime = 180},
    {name = "Tech-10", spawnChance = 25, minTime = 60, maxTime = 180},
    -- Infantry groups (33% chance, 1-3 min delay) - 4 groups, expect ~1.3 spawns
    {name = "Infantry-1", spawnChance = 33, minTime = 60, maxTime = 180},
    {name = "Infantry-2", spawnChance = 33, minTime = 60, maxTime = 180},
    {name = "Infantry-3", spawnChance = 33, minTime = 60, maxTime = 180},
    {name = "Infantry-4", spawnChance = 33, minTime = 60, maxTime = 180},
}

-- Function to attempt spawn (follows DCS callback signature)
local function trySpawn(groupConfig, time)
    local roll = math.random(1, 100)

    if roll <= groupConfig.spawnChance then
        local group = Group.getByName(groupConfig.name)
        if group then
            trigger.action.activateGroup(group)
        end
    end

    return nil  -- Don't reschedule
end

-- Schedule spawns with random delays
for i, groupConfig in ipairs(spawnGroups) do
    local spawnTime = math.random(groupConfig.minTime, groupConfig.maxTime)

    timer.scheduleFunction(
        trySpawn,
        groupConfig,
        timer.getTime() + spawnTime
    )
end
