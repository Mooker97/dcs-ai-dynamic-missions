-- Random Enemy Spawner for Operation Outback Shepherd
-- Place this in a DO SCRIPT trigger at mission start

-- Configuration
local spawnGroups = {
    -- Tech groups (25% chance, 1-3 min spawn)
    {name = "tech-1", spawnChance = 25, minTime = 60, maxTime = 180},
    {name = "tech-2", spawnChance = 25, minTime = 60, maxTime = 180},
    {name = "tech-3", spawnChance = 25, minTime = 60, maxTime = 180},
    {name = "tech-4", spawnChance = 25, minTime = 60, maxTime = 180},
    {name = "tech-5", spawnChance = 25, minTime = 60, maxTime = 180},
    {name = "tech-6", spawnChance = 25, minTime = 60, maxTime = 180},
    {name = "tech-7", spawnChance = 25, minTime = 60, maxTime = 180},
    {name = "tech-8", spawnChance = 25, minTime = 60, maxTime = 180},
    {name = "tech-9", spawnChance = 25, minTime = 60, maxTime = 180},
    {name = "tech-10", spawnChance = 25, minTime = 60, maxTime = 180},
    -- Inf groups (33% chance, 1-3 min spawn)
    {name = "inf-1", spawnChance = 33, minTime = 60, maxTime = 180},
    {name = "inf-2", spawnChance = 33, minTime = 60, maxTime = 180},
    {name = "inf-3", spawnChance = 33, minTime = 60, maxTime = 180},
    {name = "inf-4", spawnChance = 33, minTime = 60, maxTime = 180},
}

-- Function to attempt spawn
local function trySpawn(groupConfig)
    local roll = math.random(1, 100)
    
    if roll <= groupConfig.spawnChance then
        local group = Group.getByName(groupConfig.name)
        if group then
            trigger.action.activateGroup(group)
            trigger.action.outText("Enemy contact detected in area!", 10)
            env.info("Spawned group: " .. groupConfig.name)
        else
            env.info("ERROR: Group not found: " .. groupConfig.name)
        end
    else
        env.info("Spawn roll failed for: " .. groupConfig.name .. " (rolled " .. roll .. ", needed <=" .. groupConfig.spawnChance .. ")")
    end
end

-- Schedule spawns
for i, groupConfig in ipairs(spawnGroups) do
    local spawnTime = math.random(groupConfig.minTime, groupConfig.maxTime)
    
    timer.scheduleFunction(
        function()
            trySpawn(groupConfig)
        end,
        nil,
        timer.getTime() + spawnTime
    )
    
    env.info("Scheduled " .. groupConfig.name .. " for spawn check at " .. spawnTime .. " seconds")
end

env.info("Random spawner script initialized with " .. #spawnGroups .. " groups")