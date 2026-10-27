-- Formation-Based Spawning for DCS Missions
-- Spawn multiple groups in military formations
-- Each LATE ACTIVATION group is respawned (same name) with its lead unit on its
-- formation slot, so the computed positions are actually applied.
-- Requires: spawners/spawn-core.lua
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

--- Resolve formation centre/heading: explicit placement, else the ME position
-- and heading of the first group's lead unit
local function resolvePlacement(groupNames, placement)
    placement = placement or {}
    local cx, cz, hdg = placement.x, placement.z or placement.y, placement.heading
    if (cx == nil or hdg == nil) and DMS.SpawnCore then
        local tmpl = DMS.SpawnCore.getGroupTemplate(groupNames[1])
        local lead = tmpl and tmpl.data.units and tmpl.data.units[1]
        if lead then
            if cx == nil then cx, cz = lead.x, lead.y end
            if hdg == nil then hdg = math.deg(lead.heading or 0) end
        end
    end
    return cx, cz, hdg or 0
end

--- Spawn groups in formation (activates LATE ACTIVATION groups)
-- @param groupNames table Array of group names (index 1 = formation leader)
-- @param spawnChance number|nil Overall spawn chance (default 100)
-- @param staggerDelay number|nil Delay between spawns in seconds
-- @param options table|nil {pattern="wedge", x=, z=, heading=deg, spacing=1.0, hidden=bool}
--        Without x/z the leader group's ME position is the formation centre.
--        Without options.pattern every group spawns at its ME position.
-- @return number Count spawned (or scheduled)
function DMS.Formations.spawnGroups(groupNames, spawnChance, staggerDelay, options)
    options = options or {}
    spawnChance = spawnChance or 100

    local Core = DMS.SpawnCore
    if not Core then
        env.error("[Formations] spawners/spawn-core.lua is not loaded")
        return 0
    end

    -- Roll for formation spawn
    local ok, roll = Core.roll(spawnChance)
    if not ok then
        Core.log("Formations", "Formation skipped (rolled %d > %d)", roll, spawnChance)
        return 0
    end

    -- Compute and apply slot positions
    local positions = {}
    local pattern = options.pattern
    if pattern then
        local cx, cz, hdg = resolvePlacement(groupNames, options)
        if cx then
            positions = DMS.Formations.getPositions(cx, cz, hdg, pattern, options.spacing, #groupNames)
        end
    end

    local count = 0
    for i, groupName in ipairs(groupNames) do
        if Group.getByName(groupName) then
            local slot = positions[i]
            local opts = {hidden = options.hidden, prefix = "Formations"}
            if slot then
                opts.x, opts.y = slot.x, slot.z
            end
            local ctx = "Formations.activate(" .. groupName .. ")"
            if staggerDelay and staggerDelay > 0 and i > 1 then
                Core.schedule(function()
                    Core.activate(groupName, opts)
                end, (i - 1) * staggerDelay, ctx)
            else
                Core.safeCall(Core.activate, ctx, groupName, opts)
            end
            count = count + 1
            Core.log("Formations", "'%s' slot %d at (%.0f, %.0f)", groupName, i,
                slot and slot.x or 0, slot and slot.z or 0)
        end
    end

    return count
end

--- Create a formation spawn configuration
-- @param name string Formation set name
-- @param groupNames table Array of group names
-- @param pattern string Formation pattern name
-- @param spawnChance number Spawn probability
-- @param placement table|nil {x=, z=, heading=deg, spacing=, hidden=, staggerDelay=}
-- @return table Formation configuration
function DMS.Formations.createConfig(name, groupNames, pattern, spawnChance, placement)
    return {
        name = name,
        groups = groupNames,
        pattern = pattern,
        spawnChance = spawnChance or 100,
        placement = placement or {},
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

    local p = config.placement or {}
    local count = DMS.Formations.spawnGroups(config.groups, config.spawnChance, p.staggerDelay, {
        pattern = config.pattern,
        x = p.x, z = p.z, heading = p.heading,
        spacing = p.spacing, hidden = p.hidden,
    })
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

-- Spawn LATE ACTIVATION groups in a wedge centred on Tank-1's ME position
DMS.Formations.spawnGroups(
    {"Tank-1", "Tank-2", "Tank-3", "Tank-4"},
    75,   -- 75% spawn chance
    2,    -- 2 second stagger between spawns
    {pattern = "wedge", spacing = 1.5}  -- or x=, z=, heading= for explicit placement
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
