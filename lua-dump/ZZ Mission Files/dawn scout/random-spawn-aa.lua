-- Random AA Spawner for Dawn Scout
-- Place this in a DO SCRIPT trigger at mission start
-- 35% chance for exactly 1 AA to spawn, selected randomly from pool

-- AA group pool (2S6 Tunguska units)
local aaGroups = {
    "AA-17", "AA-18", "AA-19", "AA-20", "AA-21", "AA-22", "AA-23", "AA-24",
    "AA-25", "AA-26", "AA-27", "AA-28", "AA-29", "AA-30", "AA-31", "AA-32",
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
