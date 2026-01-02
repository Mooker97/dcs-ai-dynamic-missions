-- Formation-Based Spawning for DCS Missions
-- Spawn multiple groups in military formations
-- Requires: utils/coordinates.lua
-- Place in mission via DO SCRIPT FILE

DMS = DMS or {}
DMS.Formations = {}

-- Formation patterns (offsets from leader position)
-- Each pattern is array of {xOffset, zOffset} relative to formation heading
DMS.Formations.Patterns = {
    -- Line abreast (side by side)
    line = {
        {0, 0},      -- Leader
        {0, 50},     -- Right
        {0, -50},    -- Left
        {0, 100},    -- Far right
        {0, -100},   -- Far left
    },

    -- Column (one behind another)
    column = {
        {0, 0},
        {-50, 0},
        {-100, 0},
        {-150, 0},
        {-200, 0},
    },

    -- Wedge/V formation
    wedge = {
        {0, 0},       -- Point
        {-30, 30},    -- Right rear
        {-30, -30},   -- Left rear
        {-60, 60},    -- Far right rear
        {-60, -60},   -- Far left rear
    },

    -- Echelon right
    echelon_right = {
        {0, 0},
        {-30, 30},
        {-60, 60},
        {-90, 90},
        {-120, 120},
    },

    -- Echelon left
    echelon_left = {
        {0, 0},
        {-30, -30},
        {-60, -60},
        {-90, -90},
        {-120, -120},
    },

    -- Box formation
    box = {
        {0, 0},
        {0, 50},
        {-50, 0},
        {-50, 50},
    },

    -- Diamond
    diamond = {
        {0, 0},       -- Point
        {-30, 30},    -- Right
        {-30, -30},   -- Left
        {-60, 0},     -- Trail
    },

    -- Scattered (random within area)
    scattered = "random",  -- Special handling
}

--- Calculate formation positions
-- @param centerX number Formation center X
-- @param centerZ number Formation center Z
-- @param headingDeg number Formation heading in degrees
-- @param pattern string|table Pattern name or custom offsets
-- @param spacing number|nil Spacing multiplier (default 1.0)
-- @param count number|nil Number of positions needed
-- @return table Array of {x, z} positions
function DMS.Formations.getPositions(centerX, centerZ, headingDeg, pattern, spacing, count)
    spacing = spacing or 1.0
    local positions = {}

    -- Get pattern definition
    local offsets = DMS.Formations.Patterns[pattern]
    if type(offsets) == "string" and offsets == "random" then
        -- Scattered formation
        count = count or 5
        local radius = 100 * spacing
        for i = 1, count do
            local angle = math.random() * 2 * math.pi
            local dist = math.random() * radius
            table.insert(positions, {
                x = centerX + dist * math.cos(angle),
                z = centerZ + dist * math.sin(angle)
            })
        end
        return positions
    end

    if not offsets then
        offsets = DMS.Formations.Patterns.line  -- Default
    end

    -- Convert heading to radians
    local headingRad = math.rad(headingDeg)
    local cosH = math.cos(headingRad)
    local sinH = math.sin(headingRad)

    -- Calculate positions
    count = count or #offsets
    for i = 1, math.min(count, #offsets) do
        local offset = offsets[i]
        local xOff = offset[1] * spacing
        local zOff = offset[2] * spacing

        -- Rotate offset by heading
        local rotX = xOff * cosH - zOff * sinH
        local rotZ = xOff * sinH + zOff * cosH

        table.insert(positions, {
            x = centerX + rotX,
            z = centerZ + rotZ
        })
    end

    return positions
end

--- Spawn groups in formation (activates LATE ACTIVATION groups)
-- Note: Groups spawn at their ME positions, not formation positions
-- This function is for coordinating spawn timing of pre-placed groups
-- @param groupNames table Array of group names
-- @param spawnChance number|nil Overall spawn chance (default 100)
-- @param staggerDelay number|nil Delay between spawns in seconds
-- @return number Count spawned
function DMS.Formations.spawnGroups(groupNames, spawnChance, staggerDelay)
    spawnChance = spawnChance or 100

    -- Roll for formation spawn
    if math.random(1, 100) > spawnChance then
        return 0
    end

    local count = 0
    for i, groupName in ipairs(groupNames) do
        local group = Group.getByName(groupName)
        if group then
            if staggerDelay and staggerDelay > 0 then
                local delay = (i - 1) * staggerDelay
                local grp = group  -- Capture for closure
                DMS.Error.safeSchedule(function()
                    trigger.action.activateGroup(grp)
                end, delay, "Formations.activateGroup(" .. groupName .. ")")
            else
                DMS.Error.safeCall(function()
                    trigger.action.activateGroup(group)
                end, "Formations.activateGroup(" .. groupName .. ")")
            end
            count = count + 1
        end
    end

    return count
end

--- Create a formation spawn configuration
-- @param name string Formation set name
-- @param groupNames table Array of group names
-- @param pattern string Formation pattern name
-- @param spawnChance number Spawn probability
-- @return table Formation configuration
function DMS.Formations.createConfig(name, groupNames, pattern, spawnChance)
    return {
        name = name,
        groups = groupNames,
        pattern = pattern,
        spawnChance = spawnChance or 100,
        spawned = false
    }
end

-- Store formation configurations
DMS.Formations.Configs = {}

--- Register a formation for later spawning
-- @param config table From createConfig()
function DMS.Formations.register(config)
    DMS.Formations.Configs[config.name] = config
end

--- Spawn a registered formation by name
-- @param name string Formation name
-- @return number Count spawned
function DMS.Formations.spawn(name)
    local config = DMS.Formations.Configs[name]
    if not config or config.spawned then
        return 0
    end

    local count = DMS.Formations.spawnGroups(config.groups, config.spawnChance)
    if count > 0 then
        config.spawned = true
    end
    return count
end

--- Spawn all registered formations
-- @return number Total spawned
function DMS.Formations.spawnAll()
    local total = 0
    for name, _ in pairs(DMS.Formations.Configs) do
        total = total + DMS.Formations.spawn(name)
    end
    return total
end

--[[
USAGE EXAMPLE:

-- Get formation positions for mission planning
local positions = DMS.Formations.getPositions(
    -50000,  -- centerX
    40000,   -- centerZ
    90,      -- heading (East)
    "wedge", -- pattern
    1.5      -- spacing multiplier
)

-- Spawn a group of LATE ACTIVATION units
DMS.Formations.spawnGroups(
    {"Tank-1", "Tank-2", "Tank-3", "Tank-4"},
    75,   -- 75% spawn chance
    2     -- 2 second stagger between spawns
)

-- Register and spawn formations
DMS.Formations.register(DMS.Formations.createConfig(
    "Alpha Squad",
    {"Alpha-1", "Alpha-2", "Alpha-3"},
    "wedge",
    80
))

DMS.Formations.spawn("Alpha Squad")
-- Or spawn all: DMS.Formations.spawnAll()
]]

-- Export
_G.DMS = DMS
