-- Template-Based Spawning for DCS Missions
-- Spawn predefined unit compositions by template name
-- Requires: utils/group-utils.lua
-- Place in mission via DO SCRIPT FILE

DMS = DMS or {}
DMS.Templates = {}

-- Template definitions
-- Each template maps to group names in the mission editor
DMS.Templates.Library = {}

--- Define a spawn template
-- @param templateName string Template identifier
-- @param groupNames table Array of group names that make up this template
-- @param description string|nil Human-readable description
-- @param defaultChance number|nil Default spawn chance (0-100)
-- @param defaultHidden boolean|nil Default hidden state (nil = use settings)
function DMS.Templates.define(templateName, groupNames, description, defaultChance, defaultHidden)
    DMS.Templates.Library[templateName] = {
        name = templateName,
        groups = groupNames,
        description = description or templateName,
        defaultChance = defaultChance or 100,
        defaultHidden = defaultHidden,  -- nil = use settings default
        spawnCount = 0
    }
end

--- Spawn a template
-- @param templateName string Template to spawn
-- @param spawnChance number|nil Override spawn chance
-- @param hidden boolean|nil Override hidden state (nil = use template/settings default)
-- @return boolean, number Success and count of groups spawned
function DMS.Templates.spawn(templateName, spawnChance, hidden)
    local template = DMS.Templates.Library[templateName]
    if not template then
        return false, 0
    end

    spawnChance = spawnChance or template.defaultChance

    -- Roll for spawn
    local roll = math.random(1, 100)
    if roll > spawnChance then
        if DMS.Settings and DMS.Settings.isDebug() then
            env.info(string.format("[Templates] '%s' skipped (rolled %d, needed <= %d)",
                templateName, roll, spawnChance))
        end
        return false, 0
    end

    -- Determine hidden state: param > template default > settings default
    if hidden == nil then
        hidden = template.defaultHidden
    end
    if hidden == nil and DMS.Settings then
        hidden = DMS.Settings.getSpawnHidden()
    end

    local spawned = 0
    for _, groupName in ipairs(template.groups) do
        local group = Group.getByName(groupName)
        if group then
            -- Use fog of war system if available and hidden is needed
            if hidden and DMS.FogOfWar then
                DMS.FogOfWar.activateGroup(groupName, true)
            else
                trigger.action.activateGroup(group)
            end
            spawned = spawned + 1
        end
    end

    template.spawnCount = template.spawnCount + 1

    if DMS.Settings and DMS.Settings.isDebug() then
        env.info(string.format("[Templates] Spawned '%s': %d groups (hidden: %s)",
            templateName, spawned, tostring(hidden or false)))
    end

    return true, spawned
end

--- Spawn template with delay
-- @param templateName string Template name
-- @param delay number Delay in seconds
-- @param spawnChance number|nil Override spawn chance
-- @param hidden boolean|nil Override hidden state
function DMS.Templates.spawnDelayed(templateName, delay, spawnChance, hidden)
    timer.scheduleFunction(function()
        DMS.Templates.spawn(templateName, spawnChance, hidden)
        return nil
    end, nil, timer.getTime() + delay)
end

--- Spawn one random template from a list
-- @param templateNames table Array of template names
-- @param spawnChance number|nil Chance to spawn anything
-- @param hidden boolean|nil Override hidden state
-- @return string|nil Template that was spawned
function DMS.Templates.spawnRandom(templateNames, spawnChance, hidden)
    spawnChance = spawnChance or 100

    if math.random(1, 100) > spawnChance then
        return nil
    end

    local selected = templateNames[math.random(#templateNames)]
    local success = DMS.Templates.spawn(selected, 100, hidden)  -- Already rolled

    if success then
        return selected
    end
    return nil
end

--- Spawn multiple random templates
-- @param templateNames table Array of template names
-- @param count number How many to spawn
-- @param allowDuplicates boolean|nil Allow same template multiple times
-- @param hidden boolean|nil Override hidden state
-- @return table Array of spawned template names
function DMS.Templates.spawnRandomMultiple(templateNames, count, allowDuplicates, hidden)
    local spawned = {}
    local available = {}

    -- Copy available templates
    for _, name in ipairs(templateNames) do
        table.insert(available, name)
    end

    for i = 1, count do
        if #available == 0 then
            break
        end

        local idx = math.random(#available)
        local selected = available[idx]

        local success = DMS.Templates.spawn(selected, 100, hidden)
        if success then
            table.insert(spawned, selected)
        end

        if not allowDuplicates then
            table.remove(available, idx)
        end
    end

    return spawned
end

--- Get template info
-- @param templateName string Template name
-- @return table|nil Template definition
function DMS.Templates.getInfo(templateName)
    return DMS.Templates.Library[templateName]
end

--- List all defined templates
-- @return table Array of template names
function DMS.Templates.list()
    local names = {}
    for name, _ in pairs(DMS.Templates.Library) do
        table.insert(names, name)
    end
    return names
end

--- Check if all groups in template are alive
-- @param templateName string Template name
-- @return boolean True if all groups have alive units
function DMS.Templates.isAlive(templateName)
    local template = DMS.Templates.Library[templateName]
    if not template then
        return false
    end

    for _, groupName in ipairs(template.groups) do
        if DMS.Groups and not DMS.Groups.isAlive(groupName) then
            return false
        end
    end
    return true
end

--- Get template health percentage
-- @param templateName string Template name
-- @return number Average health of all groups (0-100)
function DMS.Templates.getHealth(templateName)
    local template = DMS.Templates.Library[templateName]
    if not template or not DMS.Groups then
        return 0
    end

    local totalHealth = 0
    local groupCount = 0

    for _, groupName in ipairs(template.groups) do
        local health = DMS.Groups.getHealthPercent(groupName)
        totalHealth = totalHealth + health
        groupCount = groupCount + 1
    end

    if groupCount > 0 then
        return totalHealth / groupCount
    end
    return 0
end

--[[
USAGE EXAMPLE:

-- Define templates (groups must be LATE ACTIVATION in ME)
DMS.Templates.define("light_patrol",
    {"Patrol-Vehicle-1", "Patrol-Vehicle-2"},
    "Two-vehicle patrol",
    75
)

DMS.Templates.define("heavy_armor",
    {"Tank-1", "Tank-2", "Tank-3", "APC-1"},
    "Armored column with tanks and APC",
    50
)

DMS.Templates.define("sam_site",
    {"SAM-Radar", "SAM-Launcher-1", "SAM-Launcher-2", "SAM-Support"},
    "Complete SAM battery",
    30
)

DMS.Templates.define("convoy",
    {"Truck-1", "Truck-2", "Truck-3", "Escort-1"},
    "Supply convoy with escort",
    60
)

-- Spawn specific template
DMS.Templates.spawn("heavy_armor", 75)

-- Spawn random from list
local spawned = DMS.Templates.spawnRandom(
    {"light_patrol", "heavy_armor", "convoy"},
    80
)

-- Spawn 2 random templates without duplicates
local spawnedList = DMS.Templates.spawnRandomMultiple(
    {"light_patrol", "heavy_armor", "convoy", "sam_site"},
    2,
    false
)

-- Delayed spawn
DMS.Templates.spawnDelayed("sam_site", 120)  -- After 2 minutes
]]

-- Export
_G.DMS = DMS
