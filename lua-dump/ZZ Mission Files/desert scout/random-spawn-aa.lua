-- Random AA Spawner for Desert Scout
-- Place this in a DO SCRIPT trigger at mission start
-- 35% chance for exactly 1 AA to spawn, selected randomly from pool

-- AA group pool
local aaGroups = {
    "AA-1", "AA-2", "AA-3", "AA-4", "AA-5", "AA-6", "AA-7", "AA-8",
    "AA-9", "AA-10", "AA-11", "AA-12", "AA-13", "AA-14", "AA-15", "AA-16",
}

-- 35% chance for AA to spawn
local spawnChance = 35
local roll = math.random(1, 100)

if roll <= spawnChance then
    -- Pick one random AA group
    local selectedIndex = math.random(1, #aaGroups)
    local selectedGroup = aaGroups[selectedIndex]

    local group = Group.getByName(selectedGroup)
    if group then
        trigger.action.activateGroup(group)
    end
end
