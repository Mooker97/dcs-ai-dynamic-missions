-- Dynamic Zone-Based Spawner for DCS Missions
-- Spawns groups from templates at random positions around trigger zones
-- Requires: utils/mission-settings.lua, spawners/unit-templates.lua
-- Optional: utils/fog-of-war.lua (for hidden spawns)
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
}

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

--- Generate unique unit ID
-- @return number Unique unit ID
local function generateUnitId()
    DMS.DynamicSpawn.UnitCounter = DMS.DynamicSpawn.UnitCounter + 1
    return 10000 + DMS.DynamicSpawn.UnitCounter  -- Start high to avoid conflicts
end

--- Build groupData table for coalition.addGroup()
-- @param template table Group template from UnitTemplates
-- @param groupName string Name for the group
-- @param centerX number Spawn X position
-- @param centerY number Spawn Y position
-- @param heading number Group heading in radians
-- @param options table Additional options {formation, spacing, hidden}
-- @return table groupData for coalition.addGroup()
local function buildGroupData(template, groupName, centerX, centerY, heading, options)
    options = options or {}
    local spacing = options.spacing or DMS.DynamicSpawn.Config.defaultSpacing
    local formation = options.formation or "line"
    local hidden = options.hidden
    if hidden == nil then
        hidden = DMS.DynamicSpawn.Config.defaultHidden
    end

    -- Calculate unit positions
    local positions = calculateFormationPositions(
        centerX, centerY, heading,
        #template.units, spacing, formation
    )

    -- Build units table
    local units = {}
    for i, unitDef in ipairs(template.units) do
        local pos = positions[i] or positions[1]
        local unitId = generateUnitId()

        table.insert(units, {
            ["type"] = unitDef.type,
            ["name"] = string.format("%s-%d", groupName, i),
            ["unitId"] = unitId,
            ["x"] = pos.x,
            ["y"] = pos.y,
            ["heading"] = heading,
            ["skill"] = unitDef.skill or "Average",
            ["playerCanDrive"] = false,
        })
    end

    -- Build group data
    local groupData = {
        ["name"] = groupName,
        ["task"] = template.task or DMS.DynamicSpawn.Config.defaultTask,
        ["visible"] = not hidden,
        ["hidden"] = hidden,
        ["units"] = units,
        ["x"] = centerX,
        ["y"] = centerY,
        ["route"] = {
            ["spans"] = {},
            ["points"] = {
                [1] = {
                    ["alt"] = 0,
                    ["type"] = "Turning Point",
                    ["action"] = "Off Road",
                    ["alt_type"] = "BARO",
                    ["x"] = centerX,
                    ["y"] = centerY,
                    ["speed"] = 0,
                    ["speed_locked"] = true,
                    ["ETA_locked"] = true,
                    ["ETA"] = 0,
                    ["task"] = {
                        ["id"] = "ComboTask",
                        ["params"] = {["tasks"] = {}},
                    },
                },
            },
        },
    }

    return groupData
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
            -- Calculate position
            local spawnX, spawnY, angle = calculateSpawnPosition(
                zone.point.x, zone.point.z,  -- Note: DCS uses z for "y" in ground coords
                pool.minDistance, pool.maxDistance
            )

            -- Calculate heading
            local heading = calculateHeading(
                pool.heading,
                spawnX, spawnY,
                zone.point.x, zone.point.z
            )

            -- Generate group name
            local groupName = generateGroupName(poolId)

            -- Determine country
            local countryId = pool.country or template.country or DMS.DynamicSpawn.Config.defaultCountry

            -- Build group data
            local groupData = buildGroupData(template, groupName, spawnX, spawnY, heading, {
                formation = pool.formation,
                spacing = pool.spacing,
                hidden = pool.hidden,
            })

            -- Spawn the group
            local group
            if DMS.FogOfWar and (pool.hidden ~= false) then
                -- Use FogOfWar spawn for hidden tracking
                group = DMS.FogOfWar.spawnGroup(countryId, Group.Category.GROUND, groupData, pool.hidden)
            else
                -- Direct spawn
                group = coalition.addGroup(countryId, Group.Category.GROUND, groupData)
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
        hidden = options.hidden,
    })

    -- Spawn the group
    local group
    if DMS.FogOfWar and (options.hidden ~= false) then
        group = DMS.FogOfWar.spawnGroup(countryId, Group.Category.GROUND, groupData, options.hidden)
    else
        group = coalition.addGroup(countryId, Group.Category.GROUND, groupData)
    end

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
        hidden = options.hidden,
    })

    local group
    if DMS.FogOfWar and (options.hidden ~= false) then
        group = DMS.FogOfWar.spawnGroup(countryId, Group.Category.GROUND, groupData, options.hidden)
    else
        group = coalition.addGroup(countryId, Group.Category.GROUND, groupData)
    end

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

--- Assign attack task to a spawned group
-- @param groupName string Group name
-- @param targetGroupName string Target group to attack
-- @param options table {immediate, weaponType}
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

--- Assign hunt task - move to area and engage enemies
-- @param groupName string Group name
-- @param targetPoint table {x, y} destination
-- @param options table {speed, formation, engageRadius}
function DMS.DynamicSpawn.assignHuntTask(groupName, targetPoint, options)
    options = options or {}

    local group = Group.getByName(groupName)
    if not group then
        env.warning(string.format("[DynamicSpawn] Cannot assign hunt - group '%s' not found", groupName))
        return false
    end

    local controller = group:getController()
    if not controller then return false end

    -- Set ROE to weapons free
    controller:setOption(AI.Option.Ground.id.ROE, AI.Option.Ground.val.ROE.OPEN_FIRE)
    controller:setOption(AI.Option.Ground.id.ALARM_STATE, AI.Option.Ground.val.ALARM_STATE.RED)

    -- Create waypoint mission to target
    local mission = {
        id = "Mission",
        params = {
            route = {
                points = {
                    [1] = {
                        type = "Turning Point",
                        action = "Off Road",
                        x = targetPoint.x,
                        y = targetPoint.y,
                        speed = options.speed or 15,  -- ~54 km/h
                        task = {
                            id = "ComboTask",
                            params = {
                                tasks = {
                                    [1] = {
                                        id = "EngageTargets",
                                        params = {
                                            maxDist = options.engageRadius or 3000,
                                            targetTypes = {"Armored vehicles", "Infantry", "Air Defence"},
                                            priority = 0,
                                        },
                                    },
                                },
                            },
                        },
                    },
                },
            },
        },
    }

    controller:setTask(mission)

    if DMS.Settings and DMS.Settings.isDebug() then
        env.info(string.format("[DynamicSpawn] Assigned hunt task: %s -> (%.0f, %.0f)", groupName, targetPoint.x, targetPoint.y))
    end

    return true
end

--- Make spawned groups hunt a convoy
-- @param poolIds table Array of pool IDs to assign hunting
-- @param convoyName string Convoy group name
-- @param options table {delay, staggerDelay}
function DMS.DynamicSpawn.huntConvoy(poolIds, convoyName, options)
    options = options or {}
    local delay = options.delay or 0
    local staggerDelay = options.staggerDelay or 30  -- Stagger attacks

    local function assignHunting()
        local convoy = Group.getByName(convoyName)
        if not convoy then
            env.warning(string.format("[DynamicSpawn] Convoy '%s' not found for hunting", convoyName))
            return
        end

        local convoyPos = convoy:getUnit(1):getPoint()
        local assignedCount = 0

        for _, poolId in ipairs(poolIds) do
            local groups = DMS.DynamicSpawn.getPoolGroups(poolId)
            for i, groupName in ipairs(groups) do
                -- Stagger the attack timing
                local groupDelay = (assignedCount * staggerDelay)

                timer.scheduleFunction(function()
                    -- Get current convoy position for interception
                    local currentConvoy = Group.getByName(convoyName)
                    if currentConvoy and currentConvoy:getUnit(1) then
                        DMS.DynamicSpawn.assignAttackTask(groupName, convoyName, {immediate = true})
                    end
                    return nil
                end, nil, timer.getTime() + groupDelay)

                assignedCount = assignedCount + 1
            end
        end

        if DMS.Settings and DMS.Settings.isDebug() then
            env.info(string.format("[DynamicSpawn] Hunt convoy: %d groups assigned to hunt '%s'", assignedCount, convoyName))
        end
    end

    if delay > 0 then
        timer.scheduleFunction(function()
            assignHunting()
            return nil
        end, nil, timer.getTime() + delay)
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

-- Initialize counters from existing groups to avoid ID conflicts
local function initializeCounters()
    -- Try to find highest existing group/unit IDs
    for _, coalitionSide in pairs({coalition.side.RED, coalition.side.BLUE}) do
        local groups = coalition.getGroups(coalitionSide, Group.Category.GROUND)
        if groups then
            for _, group in ipairs(groups) do
                local units = group:getUnits()
                if units then
                    for _, unit in ipairs(units) do
                        local id = unit:getID()
                        if id and id > DMS.DynamicSpawn.UnitCounter then
                            DMS.DynamicSpawn.UnitCounter = id
                        end
                    end
                end
            end
        end
    end

    if DMS.Settings and DMS.Settings.isDebug() then
        env.info(string.format("[DynamicSpawn] Initialized counters (unit base: %d)", DMS.DynamicSpawn.UnitCounter))
    end
end

-- Run initialization
initializeCounters()

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
