-- HVT Supply Convoy Spawner for Dawn Scout
-- 15% chance, spawns around 13 min, triggers flag for radio callout

local hvtGroup = "hvt-1"
local spawnChance = 15
local minTime = 720   -- 12 min
local maxTime = 840   -- 14 min
local hvtFlag = "100" -- Flag must be STRING for Mission Editor triggers

-- Roll once at mission start
if math.random(1, 100) <= spawnChance then
    local spawnTime = math.random(minTime, maxTime)

    timer.scheduleFunction(function()
        local group = Group.getByName(hvtGroup)
        if group then
            trigger.action.activateGroup(group)
            trigger.action.setUserFlag(hvtFlag, true)
        end
        return nil
    end, nil, timer.getTime() + spawnTime)
end
