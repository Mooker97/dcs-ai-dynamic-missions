-- Random Enemy Spawner for Dawn Scout
-- Place this in a DO SCRIPT trigger at mission start
-- NOTE: AA and HVT have separate scripts (random-spawn-aa.lua, random-spawn-hvt.lua)

-- Configuration (matches Dawn Scout.miz)
local spawnGroups = {
    -- AAA groups (65% chance) - 4 groups
    {name = "AAA-1", spawnChance = 65},
    {name = "AAA-2", spawnChance = 65},
    {name = "AAA-3", spawnChance = 65},
    {name = "AAA-4", spawnChance = 65},

    -- Infantry groups (33% chance) - 6 groups
    {name = "Infantry-1", spawnChance = 33},
    {name = "Infantry-2", spawnChance = 33},
    {name = "Infantry-5", spawnChance = 33},
    {name = "Infantry-6", spawnChance = 33},
    {name = "Infantry-7", spawnChance = 33},
    {name = "Infantry-8", spawnChance = 33},

    -- Tech groups (25% chance) - 11 groups
    {name = "Tech-1", spawnChance = 25},
    {name = "Tech-6", spawnChance = 25},
    {name = "Tech-11", spawnChance = 25},
    {name = "Tech-12", spawnChance = 25},
    {name = "Tech-13", spawnChance = 25},
    {name = "Tech-14", spawnChance = 25},
    {name = "Tech-15", spawnChance = 25},
    {name = "Tech-16", spawnChance = 25},
    {name = "Tech-17", spawnChance = 25},
    {name = "Tech-18", spawnChance = 25},
    {name = "Tech-19", spawnChance = 25},
}

-- Function to attempt spawn
local function trySpawn(groupConfig)
    local roll = math.random(1, 100)

    if roll <= groupConfig.spawnChance then
        local group = Group.getByName(groupConfig.name)
        if group then
            trigger.action.activateGroup(group)
            return true
        end
    end
    return false
end

-- Spawn immediately at mission start
for i, groupConfig in ipairs(spawnGroups) do
    trySpawn(groupConfig)
end
