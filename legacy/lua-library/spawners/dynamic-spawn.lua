-- Dynamic Zone-Based Spawner for DCS Missions
-- Spawns groups from templates at random positions around trigger zones
-- Requires: utils/mission-settings.lua, spawners/unit-templates.lua
-- Optional: utils/fog-of-war.lua (hidden spawns + F10 contact marks),
--           spawners/spawn-core.lua (terrain/building checks, guarded timers)
--
-- Notes:
--   * Unit/group IDs are omitted from spawn tables so DCS assigns unique IDs.
--   * Spawn positions are rerolled when they land on water/shallow water (and,
--     with spawn-core loaded, near buildings).
--   * Spawned groups get a valid 2-point "hold" route so later setTask() works.
--   * Ground tasking uses routes (AttackGroup is aircraft-only).
-- Place in mission via DO SCRIPT FILE

DMS = DMS or {}
DMS.DynamicSpawn = {}

-- ============================================================
-- STATE
-- ============================================================

DMS.DynamicSpawn.Pools = {}          -- Registered spawn pools
DMS.DynamicSpawn.SpawnedGroups = {}  -- Track all spawned groups
DMS.DynamicSpawn.GroupCounter = 0    -- For unique group names
DMS.DynamicSpawn.UnitCounter = 0     -- For unique unit IDs

-- ============================================================
-- CONFIGURATION
-- ============================================================

DMS.DynamicSpawn.Config = {
    defaultMinDistance = 100,    -- Min distance from zone center (m)
    defaultMaxDistance = 500,    -- Max distance from zone center (m)
    defaultSpacing = 20,         -- Unit spacing in formations (m)
    defaultHeading = "center",   -- "center" = face zone center, "random", or angle in radians
    defaultHidden = true,        -- Hidden from F10 map by default
    defaultCountry = country.id.RUSSIA,
    defaultTask = "Ground Nothing",
    maxPositionAttempts = 20,    -- Rerolls for a valid (dry land) spawn position
    defaultHuntSpeed = 10,       -- m/s (~36 km/h) for hunt/attack routes
    huntUpdateInterval = 60,     -- Seconds between hunt re-routes toward a moving target
}

-- ============================================================
-- INTERNAL HELPERS
-- ============================================================

local function logError(context, err)
    if DMS.SpawnCore and DMS.SpawnCore.logError then
        DMS.SpawnCore.logError(context, err)
        return
    end
    local logged = DMS.Error and DMS.Error.log and pcall(DMS.Error.log, context, tostring(err))
    if not logged then
        env.error(string.format("[DMS LUA ERROR] %s: %s", context, tostring(err)))
    end
end

--- One-shot pcall-guarded timer; returns timer id
local function safeSchedule(func, delay, context)
    return timer.scheduleFunction(function()
        local ok, err = pcall(func)
        if not ok then logError(context, err) end
        return nil
    end, nil, timer.getTime() + math.max(0, delay or 0))
end

--- Is (x, y) map point usable for ground units (not water; no buildings with spawn-core)?
local function isValidGroundPoint(x, y)
    if DMS.SpawnCore and DMS.SpawnCore.isValidGroundPoint then
        return (DMS.SpawnCore.isValidGroundPoint(x, y))
    end
    if land and land.getSurfaceType and land.SurfaceType then
        local ok, st = pcall(land.getSurfaceType, {x = x, y = y})
        if ok and (st == land.SurfaceType.WATER or st == land.SurfaceType.SHALLOW_WATER) then
            return false
        end
    end
    return true
end
DMS.DynamicSpawn.isValidGroundPoint = isValidGroundPoint

--- Are all positions in an array of {x, y} valid ground?
local function allValid(positions)
    for _, p in ipairs(positions) do
        if not isValidGroundPoint(p.x, p.y) then return false end
    end
    return true
end

--- Configure dynamic spawn system
-- @param settings table Configuration overrides
function DMS.DynamicSpawn.configure(settings)
    for key, value in pairs(settings or {}) do
        DMS.DynamicSpawn.Config[key] = value
    end
end

-- ============================================================
-- POSITION CALCULATION
-- ============================================================

--- Calculate a random position around a zone center
-- @param zoneX number Zone center X coordinate
-- @param zoneY number Zone center Y coordinate (actually Z in DCS)
-- @param minDist number Minimum distance from center
-- @param maxDist number Maximum distance from center
-- @return number, number, number X, Y coordinates and angle from center
local function calculateSpawnPosition(zoneX, zoneY, minDist, maxDist)
    local angle = math.random() * 2 * math.pi
    local distance = minDist + math.random() * (maxDist - minDist)

    local x = zoneX + distance * math.cos(angle)
    local y = zoneY + distance * math.sin(angle)

    return x, y, angle
end

--- Calculate heading based on mode
-- @param mode string|number "center", "random", or angle in radians
-- @param unitX number Unit X position
-- @param unitY number Unit Y position
-- @param zoneX number Zone center X
-- @param zoneY number Zone center Y
-- @return number Heading in radians
local function calculateHeading(mode, unitX, unitY, zoneX, zoneY)
    if mode == "center" then
        -- Face toward zone center
        return math.atan2(zoneY - unitY, zoneX - unitX)
    elseif mode == "random" then
        return math.random() * 2 * math.pi
    elseif type(mode) == "number" then
        return mode
    else
        return 0
    end
end

--- Calculate unit positions in formation
-- @param centerX number Group center X
-- @param centerY number Group center Y
-- @param heading number Group heading in radians
-- @param unitCount number Number of units
-- @param spacing number Distance between units
-- @param formation string "line", "column", "vee", "circle"
-- @return table Array of {x, y} positions
local function calculateFormationPositions(centerX, centerY, heading, unitCount, spacing, formation)
    local positions = {}
    formation = formation or "line"

    if unitCount == 1 then
        table.insert(positions, {x = centerX, y = centerY})
        return positions
    end

    if formation == "line" then
        -- Perpendicular to heading
        local perpAngle = heading + math.pi / 2
        local startOffset = -((unitCount - 1) * spacing) / 2

        for i = 1, unitCount do
            local offset = startOffset + (i - 1) * spacing
            table.insert(positions, {
                x = centerX + offset * math.cos(perpAngle),
                y = centerY + offset * math.sin(perpAngle),
            })
        end

    elseif formation == "column" then
        -- Along heading direction
        local startOffset = -((unitCount - 1) * spacing) / 2

        for i = 1, unitCount do
            local offset = startOffset + (i - 1) * spacing
            table.insert(positions, {
                x = centerX + offset * math.cos(heading),
                y = centerY + offset * math.sin(heading),
            })
        end

    elseif formation == "vee" then
        -- V formation
        table.insert(positions, {x = centerX, y = centerY})  -- Leader

        for i = 2, unitCount do
            local side = ((i - 1) % 2 == 0) and 1 or -1
            local row = math.ceil((i - 1) / 2)
            local perpAngle = heading + math.pi / 2

            table.insert(positions, {
                x = centerX - row * spacing * math.cos(heading) + side * row * spacing * math.cos(perpAngle),
                y = centerY - row * spacing * math.sin(heading) + side * row * spacing * math.sin(perpAngle),
            })
        end

    elseif formation == "circle" then
        -- Circle around center
        for i = 1, unitCount do
            local angle = (i - 1) * (2 * math.pi / unitCount)
            local radius = spacing * unitCount / (2 * math.pi)
            table.insert(positions, {
                x = centerX + radius * math.cos(angle),
                y = centerY + radius * math.sin(angle),
            })
        end

    else
        -- Default: line
        return calculateFormationPositions(centerX, centerY, heading, unitCount, spacing, "line")
    end

    return positions
end

-- ============================================================
-- GROUP DATA BUILDING
-- ============================================================

--- Generate unique group name
-- @param poolId string Pool identifier
-- @return string Unique group name
local function generateGroupName(poolId)
    DMS.DynamicSpawn.GroupCounter = DMS.DynamicSpawn.GroupCounter + 1
    return string.format("%s-%d", poolId, DMS.DynamicSpawn.GroupCounter)
end

--- Build a ground route that holds at (x, y): 2 points (DCS needs >= 2 for later
-- setTask/route changes to behave), both at the spawn position, speed 0.
local function buildHoldRoute(x, y, heading)
    local function point(px, py)
        return {
            ["alt"] = 0,
            ["type"] = "Turning Point",
            ["action"] = "Off Road",
            ["alt_type"] = "BARO",
            ["x"] = px,
            ["y"] = py,
            ["speed"] = 0,
            ["speed_locked"] = true,
            ["ETA"] = 0,
            ["ETA_locked"] = false,
            ["formation_template"] = "",
            ["task"] = {
                ["id"] = "ComboTask",
                ["params"] = {["tasks"] = {}},
            },
        }
    end
    -- Second point 1 m ahead along heading so the segment has a direction
    return {
        ["spans"] = {},
        ["points"] = {
            [1] = point(x, y),
            [2] = point(x + math.cos(heading or 0), y + math.sin(heading or 0)),
        },
    }
end
DMS.DynamicSpawn.buildHoldRoute = buildHoldRoute

--- Build groupData table for coalition.addGroup()
-- Unit/group IDs are intentionally omitted: DCS assigns unique ones.
-- @param template table Group template from UnitTemplates
-- @param groupName string Name for the group
-- @param centerX number Spawn X position
-- @param centerY number Spawn Y position (map y = vec3.z)
-- @param heading number Group heading in radians
-- @param options table Additional options {formation, spacing, positions}
-- @return table groupData for coalition.addGroup()
local function buildGroupData(template, groupName, centerX, centerY, heading, options)
    options = options or {}
    local spacing = options.spacing or DMS.DynamicSpawn.Config.defaultSpacing
    local formation = options.formation or "line"

    -- Calculate unit positions (or use precomputed/validated ones)
    local positions = options.positions or calculateFormationPositions(
        centerX, centerY, heading,
        #template.units, spacing, formation
    )

    -- Build units table
    local units = {}
    for i, unitDef in ipairs(template.units) do
        local pos = positions[i] or positions[1]
        table.insert(units, {
            ["type"] = unitDef.type,
            ["name"] = string.format("%s-%d", groupName, i),
            ["x"] = pos.x,
            ["y"] = pos.y,
            ["heading"] = heading,
            ["skill"] = unitDef.skill or "Average",
            ["playerCanDrive"] = false,
        })
    end

    return {
        ["name"] = groupName,
        ["task"] = template.task or DMS.DynamicSpawn.Config.defaultTask,
        ["units"] = units,
        ["x"] = centerX,
        ["y"] = centerY,
        ["route"] = buildHoldRoute(centerX, centerY, heading),
    }
end

--- Apply hidden flags to the spawn table, spawn, register with FOW
-- @param countryId number
-- @param groupData table
-- @param hidden boolean|nil explicit override (nil = FogOfWar enabled / Config.defaultHidden)
-- @return Group|nil, boolean hidden
local function spawnGroupTable(countryId, groupData, hidden)
    local isHidden
    if DMS.FogOfWar and DMS.FogOfWar.applyToSpawnTable then
        local _, h = DMS.FogOfWar.applyToSpawnTable(groupData, hidden)
        isHidden = h
    else
        if hidden == nil then hidden = DMS.DynamicSpawn.Config.defaultHidden end
        isHidden = hidden and true or false
        if isHidden then
            groupData.hidden = true
            groupData.hiddenOnMFD = true
            groupData.hiddenOnPlanner = true
        end
    end

    local group = coalition.addGroup(countryId, Group.Category.GROUND, groupData)
    if group and isHidden and DMS.FogOfWar and DMS.FogOfWar.registerHiddenGroup then
        DMS.FogOfWar.registerHiddenGroup(groupData.name, group:getCoalition())
    end
    return group, isHidden
end

-- ============================================================
-- POOL MANAGEMENT
-- ============================================================

--- Create a spawn pool for a zone
-- @param poolId string Unique identifier for this pool
-- @param options table Pool configuration:
--   zone: Trigger zone name (required)
--   templates: Array of template names to choose from (required)
--   chance: Spawn chance 0-100 (default 100)
--   count: How many to spawn from pool (default 1)
--   minDistance: Min distance from zone center
--   maxDistance: Max distance from zone center
--   heading: "center", "random", or angle
--   formation: "line", "column", "vee", "circle"
--   spacing: Unit spacing in meters
--   hidden: Hide from F10 map
--   country: Country ID override
function DMS.DynamicSpawn.createPool(poolId, options)
    if not options.zone then
        env.error(string.format("[DynamicSpawn] Pool '%s' missing required 'zone' option", poolId))
        return false
    end

    if not options.templates or #options.templates == 0 then
        env.error(string.format("[DynamicSpawn] Pool '%s' missing required 'templates' option", poolId))
        return false
    end

    -- Verify zone exists
    local zone = trigger.misc.getZone(options.zone)
    if not zone then
        env.warning(string.format("[DynamicSpawn] Zone '%s' not found for pool '%s'", options.zone, poolId))
    end

    DMS.DynamicSpawn.Pools[poolId] = {
        id = poolId,
        zone = options.zone,
        templates = options.templates,
        chance = options.chance or 100,
        count = options.count or 1,
        minDistance = options.minDistance or DMS.DynamicSpawn.Config.defaultMinDistance,
        maxDistance = options.maxDistance or DMS.DynamicSpawn.Config.defaultMaxDistance,
        heading = options.heading or DMS.DynamicSpawn.Config.defaultHeading,
        formation = options.formation or "line",
        spacing = options.spacing or DMS.DynamicSpawn.Config.defaultSpacing,
        hidden = options.hidden,
        country = options.country,
        executed = false,
        spawned = {},
    }

    if DMS.Settings and DMS.Settings.isDebug() then
        env.info(string.format("[DynamicSpawn] Created pool '%s' with %d templates in zone '%s'",
            poolId, #options.templates, options.zone))
    end

    return true
end

--- Execute a spawn pool
-- @param poolId string Pool identifier
-- @return table Result {success, spawned, groups, templates}
function DMS.DynamicSpawn.executePool(poolId)
    local pool = DMS.DynamicSpawn.Pools[poolId]
    if not pool then
        env.error(string.format("[DynamicSpawn] Pool '%s' not found", poolId))
        return {success = false, spawned = 0, groups = {}, templates = {}}
    end

    -- Check spawn chance
    local roll = math.random(1, 100)
    if roll > pool.chance then
        if DMS.Settings and DMS.Settings.isDebug() then
            env.info(string.format("[DynamicSpawn] Pool '%s' skipped (rolled %d > %d)",
                poolId, roll, pool.chance))
        end
        return {success = true, spawned = 0, groups = {}, templates = {}, skipped = true}
    end

    -- Get zone
    local zone = trigger.misc.getZone(pool.zone)
    if not zone then
        env.error(string.format("[DynamicSpawn] Zone '%s' not found", pool.zone))
        return {success = false, spawned = 0, groups = {}, templates = {}}
    end

    -- Select random templates
    local selectedTemplates = {}
    local availableTemplates = {}
    for _, t in ipairs(pool.templates) do
        table.insert(availableTemplates, t)
    end

    for i = 1, math.min(pool.count, #availableTemplates) do
        local idx = math.random(1, #availableTemplates)
        table.insert(selectedTemplates, availableTemplates[idx])
        table.remove(availableTemplates, idx)
    end

    -- Spawn each selected template
    local spawnedGroups = {}
    local usedTemplates = {}

    for _, templateName in ipairs(selectedTemplates) do
        local template = DMS.UnitTemplates and DMS.UnitTemplates.getTemplate(templateName)
        if not template then
            env.warning(string.format("[DynamicSpawn] Template '%s' not found", templateName))
        else
            -- Calculate a position whose every unit slot is on dry land (reroll otherwise)
            local spawnX, spawnY, heading, positions
            for _ = 1, DMS.DynamicSpawn.Config.maxPositionAttempts do
                local cx, cy = calculateSpawnPosition(
                    zone.point.x, zone.point.z,  -- Note: DCS uses z for "y" in ground coords
                    pool.minDistance, pool.maxDistance
                )
                local hdg = calculateHeading(pool.heading, cx, cy, zone.point.x, zone.point.z)
                local slots = calculateFormationPositions(cx, cy, hdg, #template.units, pool.spacing, pool.formation)
                if allValid(slots) then
                    spawnX, spawnY, heading, positions = cx, cy, hdg, slots
                    break
                end
            end

            local group, groupName
            if not spawnX then
                env.warning(string.format("[DynamicSpawn] Pool '%s': no dry-land position for '%s' after %d attempts",
                    poolId, templateName, DMS.DynamicSpawn.Config.maxPositionAttempts))
            else
                -- Generate group name
                groupName = generateGroupName(poolId)

                -- Determine country
                local countryId = pool.country or template.country or DMS.DynamicSpawn.Config.defaultCountry

                -- Build group data
                local groupData = buildGroupData(template, groupName, spawnX, spawnY, heading, {
                    positions = positions,
                })

                -- Spawn the group (hidden flags + FOW registration)
                group = spawnGroupTable(countryId, groupData, pool.hidden)
            end

            if group then
                table.insert(spawnedGroups, groupName)
                table.insert(usedTemplates, templateName)
                pool.spawned[groupName] = {
                    template = templateName,
                    x = spawnX,
                    y = spawnY,
                    heading = heading,
                }

                -- Track globally
                DMS.DynamicSpawn.SpawnedGroups[groupName] = {
                    poolId = poolId,
                    template = templateName,
                    group = group,
                }

                if DMS.Settings and DMS.Settings.isDebug() then
                    env.info(string.format("[DynamicSpawn] Spawned '%s' from template '%s' at (%.0f, %.0f)",
                        groupName, templateName, spawnX, spawnY))
                end
            end
        end
    end

    pool.executed = true

    if DMS.Settings and DMS.Settings.isDebug() then
        env.info(string.format("[DynamicSpawn] Pool '%s' executed: spawned %d groups (rolled %d <= %d)",
            poolId, #spawnedGroups, roll, pool.chance))
    end

    return {
        success = true,
        spawned = #spawnedGroups,
        groups = spawnedGroups,
        templates = usedTemplates,
    }
end

--- Execute all registered pools
-- @return table Summary {total, spawned, skipped}
function DMS.DynamicSpawn.executeAll()
    local total = 0
    local spawned = 0
    local skipped = 0

    for poolId, _ in pairs(DMS.DynamicSpawn.Pools) do
        total = total + 1
        local result = DMS.DynamicSpawn.executePool(poolId)
        spawned = spawned + result.spawned
        if result.skipped then
            skipped = skipped + 1
        end
    end

    if DMS.Settings and DMS.Settings.isDebug() then
        env.info(string.format("[DynamicSpawn] Executed %d pools: %d groups spawned, %d pools skipped",
            total, spawned, skipped))
    end

    return {total = total, spawned = spawned, skipped = skipped}
end

-- ============================================================
-- UTILITY FUNCTIONS
-- ============================================================

--- Get all spawned group names from a pool
-- @param poolId string Pool identifier
-- @return table Array of group names
function DMS.DynamicSpawn.getPoolGroups(poolId)
    local pool = DMS.DynamicSpawn.Pools[poolId]
    if not pool then return {} end

    local groups = {}
    for name, _ in pairs(pool.spawned) do
        table.insert(groups, name)
    end
    return groups
end

--- Get all spawned group names
-- @return table Array of all group names
function DMS.DynamicSpawn.getAllGroups()
    local groups = {}
    for name, _ in pairs(DMS.DynamicSpawn.SpawnedGroups) do
        table.insert(groups, name)
    end
    return groups
end

--- Check if a group was dynamically spawned
-- @param groupName string Group name to check
-- @return boolean
function DMS.DynamicSpawn.isSpawned(groupName)
    return DMS.DynamicSpawn.SpawnedGroups[groupName] ~= nil
end

--- Get spawn info for a group
-- @param groupName string Group name
-- @return table|nil Spawn info {poolId, template, group}
function DMS.DynamicSpawn.getGroupInfo(groupName)
    return DMS.DynamicSpawn.SpawnedGroups[groupName]
end

--- Reset a pool to allow re-execution
-- @param poolId string Pool identifier
function DMS.DynamicSpawn.resetPool(poolId)
    local pool = DMS.DynamicSpawn.Pools[poolId]
    if pool then
        pool.executed = false
        pool.spawned = {}
    end
end

--- Remove a pool
-- @param poolId string Pool identifier
function DMS.DynamicSpawn.removePool(poolId)
    DMS.DynamicSpawn.Pools[poolId] = nil
end

--- List all pool IDs
-- @return table Array of pool IDs
function DMS.DynamicSpawn.listPools()
    local pools = {}
    for id, _ in pairs(DMS.DynamicSpawn.Pools) do
        table.insert(pools, id)
    end
    table.sort(pools)
    return pools
end

-- ============================================================
-- CONVENIENCE FUNCTIONS
-- ============================================================

--- Quick spawn: create pool and execute immediately
-- @param zone string Trigger zone name
-- @param templates table Array of template names
-- @param options table Additional options (chance, count, etc.)
-- @return table Execution result
function DMS.DynamicSpawn.quickSpawn(zone, templates, options)
    options = options or {}
    options.zone = zone
    options.templates = templates

    local poolId = string.format("quick_%s_%d", zone, DMS.DynamicSpawn.GroupCounter)
    DMS.DynamicSpawn.createPool(poolId, options)
    return DMS.DynamicSpawn.executePool(poolId)
end

--- Spawn a group definition directly (for custom groups)
-- @param groupDef table Group definition from UnitTemplates.createGroup()
-- @param position table {x, y} spawn position
-- @param options table {heading, formation, spacing, hidden, country}
-- @return string|nil Group name if successful
function DMS.DynamicSpawn.spawnGroupDirect(groupDef, position, options)
    options = options or {}

    if not groupDef or not groupDef.units or #groupDef.units == 0 then
        env.error("[DynamicSpawn] spawnGroupDirect: Invalid group definition")
        return nil
    end

    if not position or not position.x or not position.y then
        env.error("[DynamicSpawn] spawnGroupDirect: Invalid position")
        return nil
    end

    local groupName = groupDef.name or generateGroupName("custom")
    local heading = options.heading or 0
    if type(heading) == "number" and heading > math.pi * 2 then
        -- Assume degrees, convert to radians
        heading = math.rad(heading)
    end

    local countryId = options.country or groupDef.country or DMS.DynamicSpawn.Config.defaultCountry

    -- Build group data using existing function
    local groupData = buildGroupData(groupDef, groupName, position.x, position.y, heading, {
        formation = options.formation or "line",
        spacing = options.spacing or DMS.DynamicSpawn.Config.defaultSpacing,
    })

    if not options.force and not allValid(groupData.units) then
        env.warning(string.format("[DynamicSpawn] spawnGroupDirect: '%s' rejected - water/blocked position (force=true overrides)",
            groupName))
        return nil
    end

    -- Spawn the group (hidden flags + FOW registration)
    local group = spawnGroupTable(countryId, groupData, options.hidden)

    if group then
        DMS.DynamicSpawn.SpawnedGroups[groupName] = {
            poolId = "custom",
            template = groupDef.name or "custom",
            group = group,
            isCustom = true,
        }

        if DMS.Settings and DMS.Settings.isDebug() then
            env.info(string.format("[DynamicSpawn] Spawned custom group '%s' (%d units) at (%.0f, %.0f)",
                groupName, #groupDef.units, position.x, position.y))
        end

        return groupName
    end

    return nil
end

--- Spawn a single template at a specific position
-- @param templateName string Template name
-- @param x number X coordinate
-- @param y number Y coordinate
-- @param options table {heading, formation, spacing, hidden, country}
-- @return string|nil Group name if successful
function DMS.DynamicSpawn.spawnAt(templateName, x, y, options)
    options = options or {}

    local template = DMS.UnitTemplates and DMS.UnitTemplates.getTemplate(templateName)
    if not template then
        env.error(string.format("[DynamicSpawn] Template '%s' not found", templateName))
        return nil
    end

    local groupName = generateGroupName(templateName)
    local heading = options.heading or 0
    local countryId = options.country or template.country or DMS.DynamicSpawn.Config.defaultCountry

    local groupData = buildGroupData(template, groupName, x, y, heading, {
        formation = options.formation or "line",
        spacing = options.spacing or DMS.DynamicSpawn.Config.defaultSpacing,
    })

    if not options.force and not allValid(groupData.units) then
        env.warning(string.format("[DynamicSpawn] spawnAt: '%s' rejected - water/blocked position (force=true overrides)",
            groupName))
        return nil
    end

    local group = spawnGroupTable(countryId, groupData, options.hidden)

    if group then
        DMS.DynamicSpawn.SpawnedGroups[groupName] = {
            poolId = "direct",
            template = templateName,
            group = group,
        }

        if DMS.Settings and DMS.Settings.isDebug() then
            env.info(string.format("[DynamicSpawn] Direct spawn '%s' from '%s' at (%.0f, %.0f)",
                groupName, templateName, x, y))
        end

        return groupName
    end

    return nil
end

-- ============================================================
-- AI TASKING
-- ============================================================

--- Get the lead (first alive) unit position of a group as map {x, y}
local function groupPosition(group)
    if not group then return nil end
    for _, unit in ipairs(group:getUnits() or {}) do
        if unit and unit:isExist() and unit:getLife() >= 1 then
            local p = unit:getPoint()
            return {x = p.x, y = p.z}
        end
    end
    return nil
end

local function isGroundOrShip(group)
    local cat = group:getCategory()
    return cat == Group.Category.GROUND or cat == Group.Category.SHIP
end

--- Assign attack task to a spawned group.
-- Aircraft get an AttackGroup task; ground/naval groups (AttackGroup is
-- aircraft-only) get a hunt route to the target's current position.
-- @param groupName string Group name
-- @param targetGroupName string Target group to attack
-- @param options table {immediate, weaponType, speed, engageRadius}
function DMS.DynamicSpawn.assignAttackTask(groupName, targetGroupName, options)
    options = options or {}

    local group = Group.getByName(groupName)
    if not group then
        env.warning(string.format("[DynamicSpawn] Cannot assign task - group '%s' not found", groupName))
        return false
    end

    local targetGroup = Group.getByName(targetGroupName)
    if not targetGroup then
        env.warning(string.format("[DynamicSpawn] Cannot assign task - target '%s' not found", targetGroupName))
        return false
    end

    if isGroundOrShip(group) then
        local targetPos = groupPosition(targetGroup)
        if not targetPos then return false end
        return DMS.DynamicSpawn.assignHuntTask(groupName, targetPos, options)
    end

    local controller = group:getController()
    if not controller then
        env.warning(string.format("[DynamicSpawn] Cannot assign task - no controller for '%s'", groupName))
        return false
    end

    local task = {
        id = "AttackGroup",
        params = {
            groupId = targetGroup:getID(),
            weaponType = options.weaponType or 1073741822,  -- All weapons
            expend = "Auto",
        },
    }

    if options.immediate then
        controller:setTask(task)
    else
        controller:pushTask(task)
    end

    if DMS.Settings and DMS.Settings.isDebug() then
        env.info(string.format("[DynamicSpawn] Assigned attack task: %s -> %s", groupName, targetGroupName))
    end

    return true
end

--- Assign hunt task - drive to a point (off road) with weapons open and alarm RED
-- @param groupName string Group name
-- @param targetPoint table {x, y} destination in map coords (y = vec3.z)
-- @param options table {speed (m/s), action ("Off Road"|"On Road")}
function DMS.DynamicSpawn.assignHuntTask(groupName, targetPoint, options)
    options = options or {}

    local group = Group.getByName(groupName)
    if not group then
        env.warning(string.format("[DynamicSpawn] Cannot assign hunt - group '%s' not found", groupName))
        return false
    end

    local controller = group:getController()
    if not controller then return false end

    local startPos = groupPosition(group)
    if not startPos or not targetPoint or not targetPoint.x or not targetPoint.y then
        return false
    end

    -- Ground ROE has no WEAPON_FREE: OPEN_FIRE is the most permissive
    controller:setOption(AI.Option.Ground.id.ROE, AI.Option.Ground.val.ROE.OPEN_FIRE)
    controller:setOption(AI.Option.Ground.id.ALARM_STATE, AI.Option.Ground.val.ALARM_STATE.RED)

    local speed = options.speed or DMS.DynamicSpawn.Config.defaultHuntSpeed
    local action = options.action or "Off Road"

    local function wp(x, y)
        return {
            type = "Turning Point",
            action = action,
            x = x,
            y = y,
            alt = 0,
            alt_type = "BARO",
            speed = speed,
            speed_locked = true,
            ETA = 0,
            ETA_locked = false,
            formation_template = "",
            task = {id = "ComboTask", params = {tasks = {}}},
        }
    end

    -- Route: current position first, then the target (>= 2 points)
    local mission = {
        id = "Mission",
        params = {
            route = {
                points = {
                    [1] = wp(startPos.x, startPos.y),
                    [2] = wp(targetPoint.x, targetPoint.y),
                },
            },
        },
    }

    controller:setTask(mission)

    if DMS.Settings and DMS.Settings.isDebug() then
        env.info(string.format("[DynamicSpawn] Assigned hunt task: %s (%.0f, %.0f) -> (%.0f, %.0f) at %.1f m/s",
            groupName, startPos.x, startPos.y, targetPoint.x, targetPoint.y, speed))
    end

    return true
end

--- Make spawned groups hunt a convoy (ground routes, periodically re-routed to
-- the convoy's current position while both are alive)
-- @param poolIds table Array of pool IDs to assign hunting
-- @param convoyName string Convoy group name
-- @param options table {delay, staggerDelay, speed, updateInterval (0 = no re-route)}
function DMS.DynamicSpawn.huntConvoy(poolIds, convoyName, options)
    options = options or {}
    local delay = options.delay or 0
    local staggerDelay = options.staggerDelay or 30  -- Stagger attacks
    local updateInterval = options.updateInterval or DMS.DynamicSpawn.Config.huntUpdateInterval

    local function huntStep(groupName)
        local convoyPos = groupPosition(Group.getByName(convoyName))
        local hunter = Group.getByName(groupName)
        if not convoyPos or not hunter or not groupPosition(hunter) then
            if DMS.Settings and DMS.Settings.isDebug() then
                env.info(string.format("[DynamicSpawn] Hunt '%s' -> '%s' ended (hunter or convoy gone)",
                    groupName, convoyName))
            end
            return
        end
        DMS.DynamicSpawn.assignHuntTask(groupName, convoyPos, {speed = options.speed})
        if updateInterval and updateInterval > 0 then
            safeSchedule(function() huntStep(groupName) end, updateInterval,
                "DynamicSpawn.huntConvoy(" .. groupName .. ")")
        end
    end

    local function assignHunting()
        if not Group.getByName(convoyName) then
            env.warning(string.format("[DynamicSpawn] Convoy '%s' not found for hunting", convoyName))
            return
        end

        local assignedCount = 0
        for _, poolId in ipairs(poolIds) do
            for _, groupName in ipairs(DMS.DynamicSpawn.getPoolGroups(poolId)) do
                safeSchedule(function() huntStep(groupName) end, assignedCount * staggerDelay,
                    "DynamicSpawn.huntConvoy(" .. groupName .. ")")
                assignedCount = assignedCount + 1
            end
        end

        if DMS.Settings and DMS.Settings.isDebug() then
            env.info(string.format("[DynamicSpawn] Hunt convoy: %d groups assigned to hunt '%s'", assignedCount, convoyName))
        end
    end

    if delay > 0 then
        safeSchedule(assignHunting, delay, "DynamicSpawn.huntConvoy")
    else
        assignHunting()
    end
end

--- Set group to hold position with high alert
-- @param groupName string Group name
function DMS.DynamicSpawn.setAmbush(groupName)
    local group = Group.getByName(groupName)
    if not group then return false end

    local controller = group:getController()
    if not controller then return false end

    -- Set to highest alert, weapons free
    controller:setOption(AI.Option.Ground.id.ROE, AI.Option.Ground.val.ROE.OPEN_FIRE)
    controller:setOption(AI.Option.Ground.id.ALARM_STATE, AI.Option.Ground.val.ALARM_STATE.RED)
    controller:setOption(AI.Option.Ground.id.DISPERSE_ON_ATTACK, false)

    if DMS.Settings and DMS.Settings.isDebug() then
        env.info(string.format("[DynamicSpawn] Set ambush posture: %s", groupName))
    end

    return true
end

--- Configure all AA groups for ambush (stationary, high alert)
-- @param poolIds table Array of AA pool IDs
function DMS.DynamicSpawn.setAmbushPools(poolIds)
    for _, poolId in ipairs(poolIds) do
        local groups = DMS.DynamicSpawn.getPoolGroups(poolId)
        for _, groupName in ipairs(groups) do
            DMS.DynamicSpawn.setAmbush(groupName)
        end
    end
end

-- ============================================================
-- INITIALIZATION
-- ============================================================

-- Unit/group IDs are no longer generated (DCS assigns them when unitId/groupId
-- are omitted), so no ID-seeding scan is needed. UnitCounter is kept for
-- backwards compatibility only.

if DMS.Settings and DMS.Settings.isDebug() then
    env.info("[DynamicSpawn] Dynamic spawn system loaded")
end

--[[
USAGE EXAMPLES:

-- Basic pool setup
DMS.DynamicSpawn.createPool("alpha-aa", {
    zone = "Alpha-Ambush-Zone",
    templates = {"tunguska", "shilka", "zu23_truck", "manpads_team"},
    chance = 70,           -- 70% chance to spawn
    count = 2,             -- Spawn 2 random from pool
    minDistance = 200,     -- 200-600m from zone center
    maxDistance = 600,
    heading = "center",    -- Face toward zone center
    hidden = true,         -- Hidden from F10 map
})

-- Execute single pool
local result = DMS.DynamicSpawn.executePool("alpha-aa")
-- result = {success=true, spawned=2, groups={"alpha-aa-1","alpha-aa-2"}, templates={"tunguska","manpads_team"}}

-- Execute all pools at once
DMS.DynamicSpawn.executeAll()

-- Quick spawn without pre-creating pool
DMS.DynamicSpawn.quickSpawn("Bravo-Zone", {"bmp_section", "infantry_squad"}, {
    chance = 50,
    count = 1,
})

-- Spawn specific template at exact position
DMS.DynamicSpawn.spawnAt("checkpoint", 100000, 200000, {
    heading = math.rad(90),  -- Face east
    hidden = false,
})

-- Get all groups spawned from a pool
local groups = DMS.DynamicSpawn.getPoolGroups("alpha-aa")

-- Check if group was dynamically spawned
if DMS.DynamicSpawn.isSpawned("alpha-aa-1") then
    local info = DMS.DynamicSpawn.getGroupInfo("alpha-aa-1")
    -- info = {poolId="alpha-aa", template="tunguska", group=<Group>}
end

-- ============================================
-- CUSTOM GROUP BUILDER EXAMPLES
-- ============================================

-- Create a custom group on the fly
local customAA = DMS.UnitTemplates.createGroup("my_aa_ambush", {
    {type = "2S6 Tunguska"},
    {type = "SA-18 Igla-S manpad"},
    {type = "SA-18 Igla-S manpad"},
}, {
    displayName = "Custom AA Ambush",
    description = "Tunguska with MANPADS support",
    category = "AA",
})

-- Spawn the custom group directly
DMS.DynamicSpawn.spawnGroupDirect(customAA, {x = 100000, y = 200000}, {
    heading = 180,  -- Face south
    formation = "vee",
})

-- Or use the quick spawn helper
DMS.UnitTemplates.spawnCustom("ambush_1", {
    {type = "Soldier RPG"},
    {type = "Soldier RPG"},
    {type = "SA-18 Igla-S manpad"},
}, {x = 123456, y = 654321}, {heading = 90})

-- Register a custom template for reuse
DMS.UnitTemplates.register("heavy_aa_site", {
    {type = "2S6 Tunguska"},
    {type = "2S6 Tunguska"},
    {type = "Strela-10M3"},
    {type = "SA-18 Igla-S manpad"},
    {type = "SA-18 Igla-S manpad"},
}, {
    displayName = "Heavy AA Site",
    description = "Layered air defense with radar and IR",
    category = "AA",
})

-- Now use it like any other template
DMS.DynamicSpawn.spawnAt("heavy_aa_site", 150000, 250000)

-- Combine existing templates into a mega-group
local superDefense = DMS.UnitTemplates.combineTemplates("super_defense", {
    "tunguska_pair",
    "manpads_team",
    "infantry_squad",
}, {
    displayName = "Super Defense",
    description = "Combined AA and infantry defense",
})

-- Use in a spawn pool with custom templates
DMS.UnitTemplates.register("custom_checkpoint", {
    {type = "BTR-80"},
    {type = "BTR-80"},
    {type = "Soldier AK"},
    {type = "Soldier AK"},
    {type = "Soldier RPG"},
    {type = "HL_KORD"},
}, {category = "MIXED"})

DMS.DynamicSpawn.createPool("charlie-defense", {
    zone = "Charlie-Zone",
    templates = {"custom_checkpoint", "checkpoint", "btr_squad"},
    chance = 80,
    count = 2,
})
]]

-- Export
_G.DMS = DMS
