-- ============================================
-- DUSTOFF CORRIDOR - MASTER INIT SCRIPT
-- Combined all dependencies with debug enabled
-- Load as single DO SCRIPT FILE at mission start
-- ============================================

--[[
This master init script combines all required Lua modules into a single file.
Place in Mission Editor as: DO SCRIPT FILE → dustoff-master-init.lua
Set to: Once + At mission start
]]

DMS = DMS or {}

-- ============================================
-- 1. MISSION SETTINGS (utils/mission-settings.lua)
-- ============================================

DMS.Settings = {}

DMS.Settings.Defaults = {
    playerCoalition = coalition.side.BLUE,
    enemyCoalition = coalition.side.RED,
    fogOfWar = true,  -- ENABLED: FOW now active for spawned enemies
    fogOfWarRevealRange = 5000,
    fogOfWarRevealOnRadar = true,
    fogOfWarRevealOnVisual = true,
    fogOfWarRevealOnDamage = true,
    spawnHiddenByDefault = false,
    spawnAnnouncementsEnabled = true,
    difficultyMultiplier = 1.0,
    adaptiveDifficulty = false,
    missionTimeLimit = 0,
    reinforcementDelay = 60,
    debug = true,  -- ENABLED
    debugVerbose = false,
    showErrorAlerts = true,
}

DMS.Settings.Current = {}

function DMS.Settings.init()
    DMS.Settings.Current = {}
    for key, value in pairs(DMS.Settings.Defaults) do
        DMS.Settings.Current[key] = value
    end
end

DMS.Settings.init()

function DMS.Settings.configure(overrides)
    if not overrides then return end
    for key, value in pairs(overrides) do
        if DMS.Settings.Defaults[key] ~= nil then
            DMS.Settings.Current[key] = value
        else
            if DMS.Settings.Current.debug then
                env.info(string.format("[DMS.Settings] Warning: Unknown setting '%s'", key))
            end
            DMS.Settings.Current[key] = value
        end
    end
    if overrides.fogOfWar == true and overrides.spawnHiddenByDefault == nil then
        DMS.Settings.Current.spawnHiddenByDefault = true
    end
    if DMS.Settings.Current.debug then
        env.info("[DMS.Settings] Configuration updated")
    end
end

function DMS.Settings.get(key)
    if DMS.Settings.Current[key] ~= nil then
        return DMS.Settings.Current[key]
    end
    return DMS.Settings.Defaults[key]
end

function DMS.Settings.set(key, value)
    DMS.Settings.Current[key] = value
end

function DMS.Settings.isFogOfWarEnabled()
    return DMS.Settings.get("fogOfWar") == true
end

function DMS.Settings.shouldSpawnHidden()
    return DMS.Settings.get("fogOfWar") and DMS.Settings.get("spawnHiddenByDefault")
end

function DMS.Settings.getSpawnHidden(explicitHidden)
    if explicitHidden ~= nil then
        return explicitHidden
    end
    return DMS.Settings.shouldSpawnHidden()
end

function DMS.Settings.reset()
    DMS.Settings.init()
end

function DMS.Settings.getAll()
    local copy = {}
    for key, value in pairs(DMS.Settings.Current) do
        copy[key] = value
    end
    return copy
end

function DMS.Settings.dump()
    env.info("=== DMS Settings ===")
    for key, value in pairs(DMS.Settings.Current) do
        local default = DMS.Settings.Defaults[key]
        local marker = (value ~= default) and " *" or ""
        env.info(string.format("  %s: %s%s", key, tostring(value), marker))
    end
    env.info("(* = overridden from default)")
end

function DMS.Settings.getPlayerCoalition()
    return DMS.Settings.get("playerCoalition")
end

function DMS.Settings.getEnemyCoalition()
    return DMS.Settings.get("enemyCoalition")
end

function DMS.Settings.isDebug()
    return DMS.Settings.get("debug") == true
end

env.info("[DMS] Mission Settings module loaded")

-- ============================================
-- 2. ERROR HANDLER (for other modules)
-- ============================================

DMS.Error = {}
DMS.Error.Errors = {}

function DMS.Error.log(context, errorMsg)
    local entry = {
        timestamp = timer.getTime(),
        context = context,
        message = tostring(errorMsg),
    }
    table.insert(DMS.Error.Errors, entry)
    env.error(string.format("[DMS ERROR] %s: %s", context, tostring(errorMsg)))
end

function DMS.Error.safeCall(func, context)
    local success, result = pcall(func)
    if not success then
        DMS.Error.log(context or "unknown", result)
        return nil
    end
    return result
end

function DMS.Error.safeSchedule(func, delay, context)
    local wrappedFunc = function()
        DMS.Error.safeCall(func, context)
        return nil
    end
    return timer.scheduleFunction(wrappedFunc, nil, timer.getTime() + (delay or 0))
end

function DMS.Error.safeHandler(handlerTable, context)
    local wrappedHandler = {
        onEvent = function(self, event)
            DMS.Error.safeCall(function()
                handlerTable:onEvent(event)
            end, context)
        end
    }
    return wrappedHandler
end

env.info("[DMS] Error Handler module loaded")

-- ============================================
-- 3. FOG OF WAR (utils/fog-of-war.lua)
-- ============================================

DMS.FogOfWar = {}
DMS.FogOfWar.RevealedUnits = {
    [coalition.side.RED] = {},
    [coalition.side.BLUE] = {},
    [coalition.side.NEUTRAL] = {},
}
DMS.FogOfWar.HiddenGroups = {}
DMS.FogOfWar.Running = false
DMS.FogOfWar.CheckScheduleID = nil

DMS.FogOfWar.Config = {
    checkInterval = 3,
    revealRange = 5000,
    revealOnRadar = true,
    revealOnVisual = true,
    revealOnDamage = true,
    announceReveals = false,
}

function DMS.FogOfWar.configure(settings)
    for key, value in pairs(settings or {}) do
        DMS.FogOfWar.Config[key] = value
    end
    if DMS.Settings then
        DMS.FogOfWar.Config.revealRange = DMS.Settings.get("fogOfWarRevealRange") or DMS.FogOfWar.Config.revealRange
        DMS.FogOfWar.Config.revealOnRadar = DMS.Settings.get("fogOfWarRevealOnRadar")
        DMS.FogOfWar.Config.revealOnVisual = DMS.Settings.get("fogOfWarRevealOnVisual")
        DMS.FogOfWar.Config.revealOnDamage = DMS.Settings.get("fogOfWarRevealOnDamage")
    end
end

function DMS.FogOfWar.registerHiddenGroup(groupName, ownerCoalition)
    DMS.FogOfWar.HiddenGroups[groupName] = {
        name = groupName,
        owner = ownerCoalition,
        revealed = false,
        revealedTo = {},
    }
    if DMS.Settings and DMS.Settings.isDebug() then
        env.info(string.format("[FOW] Registered hidden group: %s", groupName))
    end
end

function DMS.FogOfWar.revealGroup(groupName, toCoalition, reason)
    local hidden = DMS.FogOfWar.HiddenGroups[groupName]
    if not hidden then return false end
    if hidden.revealedTo[toCoalition] then return false end

    hidden.revealedTo[toCoalition] = true
    hidden.revealed = true

    local group = Group.getByName(groupName)
    if group then
        local controller = group:getController()
        if controller then
            trigger.action.groupKnown(groupName, toCoalition, true)
        end
        for _, unit in ipairs(group:getUnits() or {}) do
            DMS.FogOfWar.RevealedUnits[toCoalition][unit:getName()] = true
        end
    end

    if DMS.FogOfWar.Config.announceReveals then
        local msg = string.format("Contact! Enemy forces detected%s", reason and (" - " .. reason) or "")
        trigger.action.outTextForCoalition(toCoalition, msg, 5)
    end

    if DMS.Settings and DMS.Settings.isDebug() then
        env.info(string.format("[FOW] Revealed %s to coalition %d (%s)", groupName, toCoalition, reason or "unknown"))
    end

    return true
end

function DMS.FogOfWar.revealUnit(unitName, toCoalition)
    local unit = Unit.getByName(unitName)
    if not unit then return false end
    local group = unit:getGroup()
    if group then
        return DMS.FogOfWar.revealGroup(group:getName(), toCoalition, "unit detected")
    end
    return false
end

function DMS.FogOfWar.isRevealed(groupName, toCoalition)
    local hidden = DMS.FogOfWar.HiddenGroups[groupName]
    if not hidden then return true end
    return hidden.revealedTo[toCoalition] == true
end

local function checkProximityDetection()
    local playerCoalition = DMS.Settings and DMS.Settings.getPlayerCoalition() or coalition.side.BLUE
    local revealRange = DMS.FogOfWar.Config.revealRange

    local playerUnits = {}
    for _, groupData in pairs(coalition.getGroups(playerCoalition) or {}) do
        local group = Group.getByName(groupData:getName())
        if group then
            for _, unit in ipairs(group:getUnits() or {}) do
                if unit:isExist() then
                    table.insert(playerUnits, unit)
                end
            end
        end
    end

    for groupName, hidden in pairs(DMS.FogOfWar.HiddenGroups) do
        if not hidden.revealedTo[playerCoalition] then
            local group = Group.getByName(groupName)
            if group and group:isExist() then
                local groupUnits = group:getUnits() or {}
                for _, enemyUnit in ipairs(groupUnits) do
                    if enemyUnit:isExist() then
                        local enemyPos = enemyUnit:getPoint()
                        for _, playerUnit in ipairs(playerUnits) do
                            local playerPos = playerUnit:getPoint()
                            local dist = math.sqrt(
                                (enemyPos.x - playerPos.x)^2 +
                                (enemyPos.y - playerPos.y)^2 +
                                (enemyPos.z - playerPos.z)^2
                            )
                            if dist <= revealRange then
                                DMS.FogOfWar.revealGroup(groupName, playerCoalition, "proximity")
                                break
                            end
                        end
                    end
                end
            end
        end
    end
end

local function scheduleProximityCheck()
    if not DMS.FogOfWar.Running then return end
    DMS.Error.safeCall(checkProximityDetection, "FogOfWar.checkProximityDetection")
    DMS.FogOfWar.CheckScheduleID = timer.scheduleFunction(function()
        scheduleProximityCheck()
        return nil
    end, nil, timer.getTime() + DMS.FogOfWar.Config.checkInterval)
end

DMS.FogOfWar._EventHandlerInternal = {
    onEvent = function(self, event)
        if not DMS.FogOfWar.Running then return end
        local playerCoalition = DMS.Settings and DMS.Settings.getPlayerCoalition() or coalition.side.BLUE

        if DMS.FogOfWar.Config.revealOnDamage then
            if event.id == world.event.S_EVENT_HIT or
               event.id == world.event.S_EVENT_DEAD or
               event.id == world.event.S_EVENT_KILL then
                if event.target then
                    local group = event.target:getGroup()
                    if group then
                        local targetCoalition = event.target:getCoalition()
                        if targetCoalition ~= playerCoalition then
                            DMS.FogOfWar.revealGroup(group:getName(), playerCoalition, "combat")
                        end
                    end
                end
                if event.initiator then
                    local group = event.initiator:getGroup()
                    if group then
                        local initiatorCoalition = event.initiator:getCoalition()
                        if initiatorCoalition ~= playerCoalition then
                            DMS.FogOfWar.revealGroup(group:getName(), playerCoalition, "engaged")
                        end
                    end
                end
            end
        end

        if event.id == world.event.S_EVENT_SHOT then
            if event.initiator and DMS.FogOfWar.Config.revealOnDamage then
                local group = event.initiator:getGroup()
                if group then
                    local shooterCoalition = event.initiator:getCoalition()
                    if shooterCoalition ~= playerCoalition then
                        DMS.FogOfWar.revealGroup(group:getName(), playerCoalition, "firing")
                    end
                end
            end
        end
    end
}

function DMS.FogOfWar.spawnGroup(countryId, category, groupData, hidden)
    local shouldHide = hidden
    if shouldHide == nil then
        shouldHide = DMS.Settings and DMS.Settings.getSpawnHidden() or false
    end
    groupData.hidden = shouldHide
    local group = coalition.addGroup(countryId, category, groupData)
    if shouldHide and group then
        local ownerCoalition = group:getCoalition()
        DMS.FogOfWar.registerHiddenGroup(groupData.name, ownerCoalition)
    end
    return group
end

function DMS.FogOfWar.activateGroup(groupName, hidden)
    local group = Group.getByName(groupName)
    if not group then return false end
    local shouldHide = hidden
    if shouldHide == nil then
        shouldHide = DMS.Settings and DMS.Settings.getSpawnHidden() or false
    end
    trigger.action.activateGroup(group)
    if shouldHide then
        local ownerCoalition = group:getCoalition()
        local enemyCoalition = DMS.Settings and DMS.Settings.getEnemyCoalition() or coalition.side.RED
        local hideFrom = (ownerCoalition == enemyCoalition)
            and (DMS.Settings and DMS.Settings.getPlayerCoalition() or coalition.side.BLUE)
            or enemyCoalition
        DMS.FogOfWar.registerHiddenGroup(groupName, ownerCoalition)
        trigger.action.groupKnown(groupName, hideFrom, false)
    end
    return true
end

function DMS.FogOfWar.start()
    if DMS.FogOfWar.Running then return end
    DMS.FogOfWar.Running = true
    DMS.FogOfWar.configure({})
    DMS.FogOfWar.EventHandler = DMS.Error.safeHandler(
        DMS.FogOfWar._EventHandlerInternal,
        "FogOfWar.EventHandler"
    )
    world.addEventHandler(DMS.FogOfWar.EventHandler)
    scheduleProximityCheck()
    if DMS.Settings and DMS.Settings.isDebug() then
        env.info("[FOW] Fog of War system started")
    end
end

function DMS.FogOfWar.stop()
    DMS.FogOfWar.Running = false
    if DMS.FogOfWar.CheckScheduleID then
        timer.removeFunction(DMS.FogOfWar.CheckScheduleID)
        DMS.FogOfWar.CheckScheduleID = nil
    end
end

function DMS.FogOfWar.revealAll()
    local playerCoalition = DMS.Settings and DMS.Settings.getPlayerCoalition() or coalition.side.BLUE
    for groupName, _ in pairs(DMS.FogOfWar.HiddenGroups) do
        DMS.FogOfWar.revealGroup(groupName, playerCoalition, "mission end")
    end
end

function DMS.FogOfWar.getStats()
    local total = 0
    local revealed = 0
    local playerCoalition = DMS.Settings and DMS.Settings.getPlayerCoalition() or coalition.side.BLUE
    for _, hidden in pairs(DMS.FogOfWar.HiddenGroups) do
        total = total + 1
        if hidden.revealedTo[playerCoalition] then
            revealed = revealed + 1
        end
    end
    return {totalHidden = total, revealed = revealed, stillHidden = total - revealed}
end

env.info("[DMS] Fog of War module loaded")

-- ============================================
-- 4. UNIT TEMPLATES (spawners/unit-templates.lua)
-- ============================================

DMS.UnitTemplates = {}
DMS.UnitTemplates.Units = {
    ["2S6 Tunguska"] = {type = "2S6 Tunguska", category = "AA", threat = "HIGH", country = "RUSSIA"},
    ["ZSU-23-4 Shilka"] = {type = "ZSU-23-4 Shilka", category = "AA", threat = "MEDIUM", country = "RUSSIA"},
    ["Strela-10M3"] = {type = "Strela-10M3", category = "AA", threat = "MEDIUM", country = "RUSSIA"},
    ["Ural-375 ZU-23"] = {type = "Ural-375 ZU-23", category = "AA", threat = "MEDIUM", country = "RUSSIA"},
    ["tt_ZU-23"] = {type = "tt_ZU-23", category = "AA", threat = "MEDIUM", country = "INSURGENT"},
    ["SA-18 Igla-S manpad"] = {type = "SA-18 Igla-S manpad", category = "AA", threat = "HIGH", country = "RUSSIA"},
    ["T-72B3"] = {type = "T-72B3", category = "ARMOR", threat = "HIGH", country = "RUSSIA"},
    ["BMP-2"] = {type = "BMP-2", category = "ARMOR", threat = "MEDIUM", country = "RUSSIA"},
    ["BMP-3"] = {type = "BMP-3", category = "ARMOR", threat = "HIGH", country = "RUSSIA"},
    ["BTR-80"] = {type = "BTR-80", category = "ARMOR", threat = "LOW", country = "RUSSIA"},
    ["BRDM-2"] = {type = "BRDM-2", category = "ARMOR", threat = "LOW", country = "RUSSIA"},
    ["tt_KORD"] = {type = "tt_KORD", category = "TECHNICAL", threat = "LOW", country = "INSURGENT"},
    ["HL_KORD"] = {type = "HL_KORD", category = "EMPLACEMENT", threat = "LOW", country = "RUSSIA"},
    ["Soldier AK"] = {type = "Soldier AK", category = "INFANTRY", threat = "LOW", country = "RUSSIA"},
    ["Soldier RPG"] = {type = "Soldier RPG", category = "INFANTRY", threat = "MEDIUM", country = "RUSSIA"},
}

DMS.UnitTemplates.Groups = {
    ["tunguska"] = {name = "tunguska", displayName = "2S6 Tunguska", category = "AA", country = country.id.RUSSIA, task = "Ground Nothing", units = {{type = "2S6 Tunguska", skill = "Random"}}},
    ["shilka"] = {name = "shilka", displayName = "ZSU-23-4 Shilka", category = "AA", country = country.id.RUSSIA, task = "Ground Nothing", units = {{type = "ZSU-23-4 Shilka", skill = "Random"}}},
    ["strela_section"] = {name = "strela_section", displayName = "Strela-10 Section", category = "AA", country = country.id.RUSSIA, task = "Ground Nothing", units = {{type = "Strela-10M3", skill = "Random"}, {type = "Strela-10M3", skill = "Random"}}},
    ["zu23_truck"] = {name = "zu23_truck", displayName = "ZU-23 on Ural", category = "AA", country = country.id.RUSSIA, task = "Ground Nothing", units = {{type = "Ural-375 ZU-23", skill = "Random"}}},
    ["zu23_technical"] = {name = "zu23_technical", displayName = "ZU-23 Technical", category = "AA", country = country.id.INSURGENTS, task = "Ground Nothing", units = {{type = "tt_ZU-23", skill = "Random"}}},
    ["zu23_battery"] = {name = "zu23_battery", displayName = "ZU-23 Battery", category = "AA", country = country.id.RUSSIA, task = "Ground Nothing", units = {{type = "Ural-375 ZU-23", skill = "Random"}, {type = "Ural-375 ZU-23", skill = "Random"}}},
    ["manpads_team"] = {name = "manpads_team", displayName = "MANPADS Team", category = "AA", country = country.id.RUSSIA, task = "Ground Nothing", units = {{type = "SA-18 Igla-S manpad", skill = "Random"}, {type = "SA-18 Igla-S manpad", skill = "Random"}}},
    ["manpads_single"] = {name = "manpads_single", displayName = "MANPADS Gunner", category = "AA", country = country.id.RUSSIA, task = "Ground Nothing", units = {{type = "SA-18 Igla-S manpad", skill = "Random"}}},
    ["t72_platoon"] = {name = "t72_platoon", displayName = "T-72 Platoon", category = "ARMOR", country = country.id.RUSSIA, task = "Ground Nothing", units = {{type = "T-72B3", skill = "Random"}, {type = "T-72B3", skill = "Random"}}},
    ["t72_single"] = {name = "t72_single", displayName = "T-72 Tank", category = "ARMOR", country = country.id.RUSSIA, task = "Ground Nothing", units = {{type = "T-72B3", skill = "Random"}}},
    ["bmp_section"] = {name = "bmp_section", displayName = "BMP Section", category = "ARMOR", country = country.id.RUSSIA, task = "Ground Nothing", units = {{type = "BMP-2", skill = "Random"}, {type = "BMP-2", skill = "Random"}}},
    ["btr_squad"] = {name = "btr_squad", displayName = "BTR Squad", category = "ARMOR", country = country.id.RUSSIA, task = "Ground Nothing", units = {{type = "BTR-80", skill = "Random"}, {type = "BTR-80", skill = "Random"}, {type = "BTR-80", skill = "Random"}}},
    ["recon_patrol"] = {name = "recon_patrol", displayName = "Recon Patrol", category = "ARMOR", country = country.id.RUSSIA, task = "Ground Nothing", units = {{type = "BRDM-2", skill = "Random"}}},
    ["technical_mg"] = {name = "technical_mg", displayName = "Technical (MG)", category = "TECHNICAL", country = country.id.INSURGENTS, task = "Ground Nothing", units = {{type = "tt_KORD", skill = "Random"}}},
    ["technical_pair"] = {name = "technical_pair", displayName = "Technical Pair", category = "TECHNICAL", country = country.id.INSURGENTS, task = "Ground Nothing", units = {{type = "tt_KORD", skill = "Random"}, {type = "tt_KORD", skill = "Random"}}},
    ["infantry_squad"] = {name = "infantry_squad", displayName = "Infantry Squad", category = "INFANTRY", country = country.id.RUSSIA, task = "Ground Nothing", units = {{type = "Soldier AK", skill = "Random"}, {type = "Soldier AK", skill = "Random"}, {type = "Soldier AK", skill = "Random"}, {type = "Soldier RPG", skill = "Random"}}},
    ["rpg_team"] = {name = "rpg_team", displayName = "RPG Team", category = "INFANTRY", country = country.id.RUSSIA, task = "Ground Nothing", units = {{type = "Soldier RPG", skill = "Random"}, {type = "Soldier RPG", skill = "Random"}}},
    ["mg_nest"] = {name = "mg_nest", displayName = "MG Nest", category = "INFANTRY", country = country.id.RUSSIA, task = "Ground Nothing", units = {{type = "HL_KORD", skill = "Random"}, {type = "Soldier AK", skill = "Random"}}},
    ["checkpoint"] = {name = "checkpoint", displayName = "Checkpoint", category = "MIXED", country = country.id.RUSSIA, task = "Ground Nothing", units = {{type = "BTR-80", skill = "Random"}, {type = "Soldier AK", skill = "Random"}, {type = "Soldier AK", skill = "Random"}, {type = "Soldier RPG", skill = "Random"}}},
    ["ambush_team"] = {name = "ambush_team", displayName = "Ambush Team", category = "MIXED", country = country.id.RUSSIA, task = "Ground Nothing", units = {{type = "Soldier RPG", skill = "Random"}, {type = "Soldier RPG", skill = "Random"}, {type = "SA-18 Igla-S manpad", skill = "Random"}}},
    ["aa_ambush"] = {name = "aa_ambush", displayName = "AA Ambush", category = "AA", country = country.id.RUSSIA, task = "Ground Nothing", units = {{type = "Ural-375 ZU-23", skill = "Random"}, {type = "SA-18 Igla-S manpad", skill = "Random"}, {type = "SA-18 Igla-S manpad", skill = "Random"}}},
    ["convoy_escort"] = {name = "convoy_escort", displayName = "Convoy Escort", category = "MIXED", country = country.id.RUSSIA, task = "Ground Nothing", units = {{type = "BTR-80", skill = "Random"}, {type = "KAMAZ Truck", skill = "Random"}, {type = "KAMAZ Truck", skill = "Random"}, {type = "BTR-80", skill = "Random"}}},
    ["qrf_light"] = {name = "qrf_light", displayName = "Light QRF", category = "QRF", country = country.id.INSURGENTS, task = "Ground Nothing", units = {{type = "tt_KORD", skill = "Random"}, {type = "tt_KORD", skill = "Random"}}},
    ["qrf_medium"] = {name = "qrf_medium", displayName = "Medium QRF", category = "QRF", country = country.id.RUSSIA, task = "Ground Nothing", units = {{type = "BMP-2", skill = "Random"}, {type = "BTR-80", skill = "Random"}}},
    ["qrf_heavy"] = {name = "qrf_heavy", displayName = "Heavy QRF", category = "QRF", country = country.id.RUSSIA, task = "Ground Nothing", units = {{type = "T-72B3", skill = "Random"}, {type = "BMP-2", skill = "Random"}}},
}

function DMS.UnitTemplates.getTemplate(templateName)
    return DMS.UnitTemplates.Groups[templateName]
end

function DMS.UnitTemplates.listTemplates(category)
    local result = {}
    for name, template in pairs(DMS.UnitTemplates.Groups) do
        if not category or template.category == category then
            table.insert(result, name)
        end
    end
    table.sort(result)
    return result
end

env.info("[DMS] Unit Templates module loaded")

-- ============================================
-- 5. DYNAMIC SPAWN (spawners/dynamic-spawn.lua)
-- ============================================

DMS.DynamicSpawn = {}
DMS.DynamicSpawn.Pools = {}
DMS.DynamicSpawn.SpawnedGroups = {}
DMS.DynamicSpawn.GroupCounter = 0
DMS.DynamicSpawn.UnitCounter = 0

DMS.DynamicSpawn.Config = {
    defaultMinDistance = 100,
    defaultMaxDistance = 500,
    defaultSpacing = 20,
    defaultHeading = "center",
    defaultHidden = true,
    defaultCountry = country.id.RUSSIA,
    defaultTask = "Ground Nothing",
}

local function calculateSpawnPosition(zoneX, zoneY, minDist, maxDist)
    local angle = math.random() * 2 * math.pi
    local distance = minDist + math.random() * (maxDist - minDist)
    local x = zoneX + distance * math.cos(angle)
    local y = zoneY + distance * math.sin(angle)
    return x, y, angle
end

local function calculateHeading(mode, unitX, unitY, zoneX, zoneY)
    if mode == "center" then
        return math.atan2(zoneY - unitY, zoneX - unitX)
    elseif mode == "random" then
        return math.random() * 2 * math.pi
    elseif type(mode) == "number" then
        return mode
    else
        return 0
    end
end

local function generateGroupName(poolId)
    DMS.DynamicSpawn.GroupCounter = DMS.DynamicSpawn.GroupCounter + 1
    return string.format("%s-%d", poolId, DMS.DynamicSpawn.GroupCounter)
end

local function generateUnitId()
    DMS.DynamicSpawn.UnitCounter = DMS.DynamicSpawn.UnitCounter + 1
    return 10000 + DMS.DynamicSpawn.UnitCounter
end

function DMS.DynamicSpawn.createPool(poolId, options)
    if not options.zone then
        env.error(string.format("[DynamicSpawn] Pool '%s' missing 'zone'", poolId))
        return false
    end
    if not options.templates or #options.templates == 0 then
        env.error(string.format("[DynamicSpawn] Pool '%s' missing 'templates'", poolId))
        return false
    end

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
        env.info(string.format("[DynamicSpawn] Created pool '%s' (%d templates) in zone '%s'",
            poolId, #options.templates, options.zone))
    end

    return true
end

function DMS.DynamicSpawn.executePool(poolId)
    local pool = DMS.DynamicSpawn.Pools[poolId]
    if not pool then
        env.error(string.format("[DynamicSpawn] Pool '%s' not found", poolId))
        return {success = false, spawned = 0, groups = {}}
    end

    local roll = math.random(1, 100)
    if roll > pool.chance then
        if DMS.Settings and DMS.Settings.isDebug() then
            env.info(string.format("[DynamicSpawn] Pool '%s' skipped (rolled %d > %d)", poolId, roll, pool.chance))
        end
        return {success = true, spawned = 0, groups = {}, skipped = true}
    end

    local zone = trigger.misc.getZone(pool.zone)
    if not zone then
        env.error(string.format("[DynamicSpawn] Zone '%s' not found", pool.zone))
        return {success = false, spawned = 0, groups = {}}
    end

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

    local spawnedGroups = {}
    for _, templateName in ipairs(selectedTemplates) do
        local template = DMS.UnitTemplates and DMS.UnitTemplates.getTemplate(templateName)
        if template then
            local spawnX, spawnY, angle = calculateSpawnPosition(
                zone.point.x, zone.point.z,
                pool.minDistance, pool.maxDistance
            )

            local heading = calculateHeading(
                pool.heading,
                spawnX, spawnY,
                zone.point.x, zone.point.z
            )

            local groupName = generateGroupName(poolId)
            local countryId = pool.country or template.country or DMS.DynamicSpawn.Config.defaultCountry

            -- Build units
            local units = {}
            for i, unitDef in ipairs(template.units) do
                local unitId = generateUnitId()
                table.insert(units, {
                    type = unitDef.type,
                    name = string.format("%s-%d", groupName, i),
                    unitId = unitId,
                    x = spawnX + (i-1)*20*math.cos(heading),
                    y = spawnY + (i-1)*20*math.sin(heading),
                    heading = heading,
                    skill = unitDef.skill or "Average",
                    playerCanDrive = false,
                })
            end

            local groupData = {
                name = groupName,
                task = template.task or DMS.DynamicSpawn.Config.defaultTask,
                visible = true,
                hidden = pool.hidden or false,
                units = units,
                x = spawnX,
                y = spawnY,
                route = {spans = {}, points = {{alt = 0, type = "Turning Point", action = "Off Road", x = spawnX, y = spawnY, speed = 0, speed_locked = true, ETA_locked = true, ETA = 0, task = {id = "ComboTask", params = {tasks = {}}}}}},
            }

            local group = coalition.addGroup(countryId, Group.Category.GROUND, groupData)
            if group then
                table.insert(spawnedGroups, groupName)
                pool.spawned[groupName] = {template = templateName, x = spawnX, y = spawnY, heading = heading}
                DMS.DynamicSpawn.SpawnedGroups[groupName] = {poolId = poolId, template = templateName, group = group}

                -- Register with FOW if FOW is enabled
                if DMS.FogOfWar and DMS.Settings and DMS.Settings.isFogOfWarEnabled() then
                    local ownerCoalition = group:getCoalition()
                    DMS.FogOfWar.registerHiddenGroup(groupName, ownerCoalition)
                    -- Make group hidden on F10 map to enemy coalition
                    trigger.action.groupKnown(groupName, coalition.side.BLUE, false)
                end

                if DMS.Settings and DMS.Settings.isDebug() then
                    env.info(string.format("[DynamicSpawn] Spawned '%s' from '%s' at (%.0f, %.0f)", groupName, templateName, spawnX, spawnY))
                end
            end
        end
    end

    pool.executed = true
    if DMS.Settings and DMS.Settings.isDebug() then
        env.info(string.format("[DynamicSpawn] Pool '%s' executed: %d groups spawned", poolId, #spawnedGroups))
    end

    return {success = true, spawned = #spawnedGroups, groups = spawnedGroups}
end

function DMS.DynamicSpawn.getPoolGroups(poolId)
    local pool = DMS.DynamicSpawn.Pools[poolId]
    if not pool then return {} end
    local groups = {}
    for name, _ in pairs(pool.spawned) do
        table.insert(groups, name)
    end
    return groups
end

function DMS.DynamicSpawn.setAmbush(groupName)
    local group = Group.getByName(groupName)
    if not group then return false end
    local controller = group:getController()
    if not controller then return false end
    controller:setOption(AI.Option.Ground.id.ROE, AI.Option.Ground.val.ROE.OPEN_FIRE)
    controller:setOption(AI.Option.Ground.id.ALARM_STATE, AI.Option.Ground.val.ALARM_STATE.RED)
    controller:setOption(AI.Option.Ground.id.DISPERSE_ON_ATTACK, false)
    if DMS.Settings and DMS.Settings.isDebug() then
        env.info(string.format("[DynamicSpawn] Set ambush: %s", groupName))
    end
    return true
end

function DMS.DynamicSpawn.setAmbushPools(poolIds)
    for _, poolId in ipairs(poolIds) do
        local groups = DMS.DynamicSpawn.getPoolGroups(poolId)
        for _, groupName in ipairs(groups) do
            DMS.DynamicSpawn.setAmbush(groupName)
        end
    end
end

function DMS.DynamicSpawn.huntConvoy(poolIds, convoyName, options)
    options = options or {}
    local delay = options.delay or 0
    local staggerDelay = options.staggerDelay or 30

    local function assignHunting()
        local assignedCount = 0
        for _, poolId in ipairs(poolIds) do
            local groups = DMS.DynamicSpawn.getPoolGroups(poolId)
            for _, groupName in ipairs(groups) do
                local groupDelay = (assignedCount * staggerDelay)
                timer.scheduleFunction(function()
                    DMS.DynamicSpawn.assignAttackTask(groupName, convoyName, {immediate = true})
                    return nil
                end, nil, timer.getTime() + groupDelay)
                assignedCount = assignedCount + 1
            end
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

function DMS.DynamicSpawn.assignAttackTask(groupName, targetGroupName, options)
    options = options or {}
    local group = Group.getByName(groupName)
    if not group then return false end
    local targetGroup = Group.getByName(targetGroupName)
    if not targetGroup then return false end
    local controller = group:getController()
    if not controller then return false end

    local task = {
        id = "AttackGroup",
        params = {groupId = targetGroup:getID(), weaponType = 1073741822, expend = "Auto"},
    }

    if options.immediate then
        controller:setTask(task)
    else
        controller:pushTask(task)
    end

    return true
end

env.info("[DMS] Dynamic Spawn module loaded")

-- ============================================
-- 6. SAM AMBUSH (ai-behavior/sam-ambush.lua)
-- ============================================

DMS.SAMAmbush = {}
DMS.SAMAmbush.Sites = {}
DMS.SAMAmbush.TimerId = nil
DMS.SAMAmbush.Active = false

DMS.SAMAmbush.Config = {
    checkInterval = 2,
    defaultEngageRadius = 30000,
    defaultMinAltitude = 100,
    defaultMaxAltitude = 25000,
    holdFireTime = 10,
    announceThreats = false,
    trackingCoalition = coalition.side.BLUE,
}

function DMS.SAMAmbush.register(groupName, options)
    options = options or {}
    local group = Group.getByName(groupName)
    local x, z = 0, 0
    if group and group:getUnits() and #group:getUnits() > 0 then
        local pos = group:getUnits()[1]:getPoint()
        x, z = pos.x, pos.z
    end

    DMS.SAMAmbush.Sites[groupName] = {
        name = groupName,
        x = x,
        z = z,
        engageRadius = options.activationRange or DMS.SAMAmbush.Config.defaultEngageRadius,
        minAlt = DMS.SAMAmbush.Config.defaultMinAltitude,
        maxAlt = DMS.SAMAmbush.Config.defaultMaxAltitude,
        radarOn = false,
        activateTime = 0,
        trackingTarget = nil,
        fireChance = options.fireChance or 100,
    }

    DMS.SAMAmbush.setRadar(groupName, false)
end

function DMS.SAMAmbush.setRadar(groupName, state)
    local group = Group.getByName(groupName)
    if group and group:isExist() then
        local controller = group:getController()
        if controller then
            if state then
                controller:setOption(AI.Option.Ground.id.ALARM_STATE, AI.Option.Ground.val.ALARM_STATE.RED)
                controller:setOption(AI.Option.Ground.id.ROE, AI.Option.Ground.val.ROE.WEAPON_FREE)
            else
                controller:setOption(AI.Option.Ground.id.ALARM_STATE, AI.Option.Ground.val.ALARM_STATE.GREEN)
                controller:setOption(AI.Option.Ground.id.ROE, AI.Option.Ground.val.ROE.WEAPON_HOLD)
            end
        end
    end

    local site = DMS.SAMAmbush.Sites[groupName]
    if site then
        site.radarOn = state
        if state then
            site.activateTime = timer.getTime()
        end
    end
end

local function getPlayerAircraft()
    local aircraft = {}
    local players = coalition.getPlayers(DMS.SAMAmbush.Config.trackingCoalition)
    if players then
        for _, unit in ipairs(players) do
            if unit and unit:isExist() then
                local pos = unit:getPoint()
                table.insert(aircraft, {pos = pos, alt = pos.y, unit = unit})
            end
        end
    end
    return aircraft
end

local function isInEnvelope(site, aircraft)
    if aircraft.alt < site.minAlt or aircraft.alt > site.maxAlt then
        return false
    end
    local dx = aircraft.pos.x - site.x
    local dz = aircraft.pos.z - site.z
    local range = math.sqrt(dx * dx + dz * dz)
    return range <= site.engageRadius
end

local function processAmbushCheck(_, time)
    if not DMS.SAMAmbush.Active then
        return nil
    end

    local playerAircraft = getPlayerAircraft()
    for groupName, site in pairs(DMS.SAMAmbush.Sites) do
        local group = Group.getByName(groupName)
        if group and group:isExist() then
            local targetInEnvelope = false
            for _, aircraft in ipairs(playerAircraft) do
                if isInEnvelope(site, aircraft) then
                    targetInEnvelope = true
                    break
                end
            end

            if targetInEnvelope and not site.radarOn then
                DMS.SAMAmbush.setRadar(groupName, true)
                if DMS.Settings and DMS.Settings.isDebug() then
                    env.info(string.format("[SAMAmbush] '%s' going HOT", groupName))
                end
            elseif not targetInEnvelope and site.radarOn then
                if time - site.activateTime > 30 then
                    DMS.SAMAmbush.setRadar(groupName, false)
                end
            end
        else
            site.radarOn = false
        end
    end

    return time + DMS.SAMAmbush.Config.checkInterval
end

function DMS.SAMAmbush.start()
    if DMS.SAMAmbush.Active then return end
    DMS.SAMAmbush.Active = true
    DMS.SAMAmbush.TimerId = timer.scheduleFunction(processAmbushCheck, nil, timer.getTime() + DMS.SAMAmbush.Config.checkInterval)
    if DMS.Settings and DMS.Settings.isDebug() then
        env.info("[SAMAmbush] System started")
    end
end

env.info("[DMS] SAM Ambush module loaded")

-- ============================================
-- 7. REINFORCEMENT WAVES (events/reinforcement-waves.lua)
-- ============================================

DMS.Reinforcements = {}
DMS.Reinforcements.Waves = {}
DMS.Reinforcements.CurrentWave = 0
DMS.Reinforcements.Active = false
DMS.Reinforcements.TimerId = nil

DMS.Reinforcements.Config = {
    playerCoalition = coalition.side.BLUE,
    enemyCoalition = coalition.side.RED,
    announceWaves = true,
    delayBetweenWaves = 60,
    maxConcurrentEnemies = 20,
    spawnDelay = 2,
}

function DMS.Reinforcements.registerWave(waveNumber, groups, options)
    options = options or {}
    DMS.Reinforcements.Waves[waveNumber] = {
        groups = groups,
        triggered = false,
        spawned = false,
        delay = options.delay or 0,
        announcement = options.announcement or string.format("Warning: Enemy reinforcements inbound! (Wave %d)", waveNumber),
        condition = options.condition or nil,
    }
end

env.info("[DMS] Reinforcements module loaded")

-- ============================================
-- 8. DUSTOFF CORRIDOR MISSION CONFIG
-- ============================================

DMS.DustoffCorridor = {}

-- Enable all features
DMS.Settings.configure({
    debug = true,
    playerCoalition = coalition.side.BLUE,
    enemyCoalition = coalition.side.RED,
    fogOfWar = true,
})

-- ============================================
-- ALPHA ZONE - Light AA + Infantry
-- ============================================

-- SAM SITE - 20% SPAWN CHANCE
DMS.DynamicSpawn.createPool("sam-site", {
    zone = "Alpha-Zone",
    templates = {"tunguska", "shilka", "zu23_battery", "aa_ambush"},
    chance = 20,  -- 20% spawn chance
    count = 1,    -- Only 1 site
    minDistance = 200,
    maxDistance = 700,
    heading = "center",
})

-- Ground infantry (no AA)
DMS.DynamicSpawn.createPool("alpha-ground", {
    zone = "Alpha-Zone",
    templates = {"infantry_squad", "rpg_team", "technical_mg", "mg_nest"},
    chance = 80,
    count = 2,
    minDistance = 100,
    maxDistance = 500,
})

-- ============================================
-- BRAVO ZONE - Armor Only (No AA)
-- ============================================

DMS.DynamicSpawn.createPool("bravo-armor", {
    zone = "Bravo-Zone",
    templates = {"bmp_section", "btr_squad", "t72_single", "checkpoint"},
    chance = 70,
    count = 2,
    minDistance = 200,
    maxDistance = 800,
})

DMS.DynamicSpawn.createPool("bravo-infantry", {
    zone = "Bravo-Zone",
    templates = {"infantry_squad", "ambush_team", "rpg_team"},
    chance = 60,
    count = 1,
    minDistance = 100,
    maxDistance = 400,
})

-- ============================================
-- CHARLIE ZONE - Infantry Defense Only
-- ============================================

DMS.DynamicSpawn.createPool("charlie-defense", {
    zone = "Charlie-Zone",
    templates = {"checkpoint", "btr_squad", "mg_nest", "infantry_squad"},
    chance = 80,
    count = 2,
    minDistance = 100,
    maxDistance = 500,
})

-- ============================================
-- QRF REINFORCEMENTS (Independent Chances)
-- ============================================

DMS.DynamicSpawn.createPool("qrf-light", {
    zone = "QRF-Staging",
    templates = {"qrf_light", "technical_pair"},
    chance = 50,  -- 50% chance
    count = 1,
    minDistance = 50,
    maxDistance = 200,
})

DMS.DynamicSpawn.createPool("qrf-medium", {
    zone = "QRF-Staging",
    templates = {"qrf_medium", "bmp_section"},
    chance = 25,  -- 25% chance
    count = 1,
    minDistance = 50,
    maxDistance = 200,
})

DMS.DynamicSpawn.createPool("qrf-heavy", {
    zone = "QRF-Staging",
    templates = {"qrf_heavy", "t72_platoon"},
    chance = 10,  -- 10% chance
    count = 1,
    minDistance = 50,
    maxDistance = 200,
})

-- ============================================
-- START FUNCTION
-- ============================================

function DMS.DustoffCorridor.start()
    env.info("[DUSTOFF] Mission starting...")

    -- Execute initial spawn pools
    DMS.DynamicSpawn.executePool("sam-site")      -- 1 SAM, 20% chance
    DMS.DynamicSpawn.executePool("alpha-ground")
    DMS.DynamicSpawn.executePool("bravo-armor")
    DMS.DynamicSpawn.executePool("bravo-infantry")
    DMS.DynamicSpawn.executePool("charlie-defense")

    -- QRF Reinforcements (independent chances)
    DMS.DynamicSpawn.executePool("qrf-light")     -- 50% chance
    DMS.DynamicSpawn.executePool("qrf-medium")    -- 25% chance
    DMS.DynamicSpawn.executePool("qrf-heavy")     -- 10% chance

    -- AI TASKING - SAM goes to ambush posture
    DMS.DynamicSpawn.setAmbushPools({"sam-site"})

    DMS.DynamicSpawn.huntConvoy(
        {"bravo-armor"},
        "Convoy-Main",
        {delay = 120, staggerDelay = 60}
    )

    DMS.DynamicSpawn.setAmbushPools({"alpha-ground", "bravo-infantry", "charlie-defense"})

    -- Register SAM group with ambush system (if it spawned)
    local samGroups = DMS.DynamicSpawn.getPoolGroups("sam-site")
    for _, groupName in ipairs(samGroups) do
        DMS.SAMAmbush.register(groupName, {
            activationRange = 8000,
            fireChance = 80,
        })
    end

    -- Start fog of war and SAM system
    DMS.FogOfWar.start()
    DMS.SAMAmbush.start()

    -- Display briefing
    trigger.action.outTextForCoalition(coalition.side.BLUE,
        "DUSTOFF CORRIDOR\n\n" ..
        "Escort convoy through hostile territory.\n" ..
        "Expect AA threats in all sectors.\n\n" ..
        "Good hunting.",
        20
    )

    env.info("[DUSTOFF] Mission started - enemies spawned dynamically")
end

-- ============================================
-- WIN / LOSS CONDITIONS
-- ============================================

DMS.DustoffCorridor.State = {
    missionEnded = false,
    result = nil,
    convoyStartCount = 0,
}

function DMS.DustoffCorridor.initConvoyTracking()
    local convoy = Group.getByName("Convoy-Main")
    if convoy then
        local units = convoy:getUnits()
        if units then
            DMS.DustoffCorridor.State.convoyStartCount = #units
        end
    end
    env.info(string.format("[DUSTOFF] Tracking %d convoy vehicles", DMS.DustoffCorridor.State.convoyStartCount))
end

function DMS.DustoffCorridor.checkVictory()
    if DMS.DustoffCorridor.State.missionEnded then return end

    local convoy = Group.getByName("Convoy-Main")
    if not convoy then return timer.getTime() + 10 end

    local zone = trigger.misc.getZone("FOB-Victory")
    if not zone then return timer.getTime() + 10 end

    local units = convoy:getUnits()
    if not units then return timer.getTime() + 10 end

    for _, unit in ipairs(units) do
        if unit and unit:isExist() then
            local pos = unit:getPoint()
            local dx = pos.x - zone.point.x
            local dy = pos.z - zone.point.z
            local dist = math.sqrt(dx*dx + dy*dy)

            if dist < zone.radius then
                DMS.DustoffCorridor.onVictory()
                return
            end
        end
    end

    return timer.getTime() + 10
end

function DMS.DustoffCorridor.onVictory()
    if DMS.DustoffCorridor.State.missionEnded then return end
    DMS.DustoffCorridor.State.missionEnded = true
    DMS.DustoffCorridor.State.result = "victory"

    local survivors = 0
    local convoy = Group.getByName("Convoy-Main")
    if convoy then
        local units = convoy:getUnits()
        if units then
            for _, unit in ipairs(units) do
                if unit and unit:isExist() then
                    survivors = survivors + 1
                end
            end
        end
    end

    local startCount = DMS.DustoffCorridor.State.convoyStartCount
    trigger.action.outTextForCoalition(coalition.side.BLUE,
        "MISSION COMPLETE\n\n" ..
        string.format("Convoy reached FOB Victory.\n") ..
        string.format("Survivors: %d/%d vehicles\n\n", survivors, startCount) ..
        "Outstanding work, Dustoff.",
        30
    )

    env.info(string.format("[DUSTOFF] VICTORY - %d/%d survived", survivors, startCount))
end

function DMS.DustoffCorridor.checkConvoyDestroyed()
    if DMS.DustoffCorridor.State.missionEnded then return end

    local convoy = Group.getByName("Convoy-Main")
    if not convoy then
        DMS.DustoffCorridor.onDefeat("convoy_destroyed")
        return
    end

    local units = convoy:getUnits()
    if not units or #units == 0 then
        DMS.DustoffCorridor.onDefeat("convoy_destroyed")
        return
    end

    local aliveCount = 0
    for _, unit in ipairs(units) do
        if unit and unit:isExist() and unit:getLife() > 1 then
            aliveCount = aliveCount + 1
        end
    end

    if aliveCount == 0 then
        DMS.DustoffCorridor.onDefeat("convoy_destroyed")
        return
    end

    return timer.getTime() + 5
end

function DMS.DustoffCorridor.setupPlayerDeathHandler()
    world.addEventHandler({
        onEvent = function(self, event)
            if DMS.DustoffCorridor.State.missionEnded then return end

            if event.id == world.event.S_EVENT_CRASH or
               event.id == world.event.S_EVENT_EJECTION or
               event.id == world.event.S_EVENT_PILOT_DEAD then

                if event.initiator then
                    local group = event.initiator:getGroup()
                    if group then
                        if group:getName() == "Player Group" then
                            timer.scheduleFunction(function()
                                DMS.DustoffCorridor.onDefeat("player_killed")
                                return nil
                            end, nil, timer.getTime() + 3)
                        end
                    end
                end
            end
        end
    })
end

function DMS.DustoffCorridor.onDefeat(reason)
    if DMS.DustoffCorridor.State.missionEnded then return end
    DMS.DustoffCorridor.State.missionEnded = true
    DMS.DustoffCorridor.State.result = "defeat"

    local message = "MISSION FAILED\n\n"

    if reason == "convoy_destroyed" then
        message = message .. "The convoy has been destroyed.\n"
        message = message .. "All vehicles lost.\n\n"
        message = message .. "The enemy controls this corridor."
    elseif reason == "player_killed" then
        message = message .. "Dustoff is down.\n"
        message = message .. "Convoy left without air support.\n\n"
        message = message .. "Mission aborted."
    else
        message = message .. "Objective failed."
    end

    trigger.action.outTextForCoalition(coalition.side.BLUE, message, 30)
    env.info(string.format("[DUSTOFF] DEFEAT - %s", reason))
end

function DMS.DustoffCorridor.startConditionMonitoring()
    DMS.DustoffCorridor.initConvoyTracking()
    DMS.DustoffCorridor.setupPlayerDeathHandler()
    timer.scheduleFunction(DMS.DustoffCorridor.checkVictory, nil, timer.getTime() + 30)
    timer.scheduleFunction(DMS.DustoffCorridor.checkConvoyDestroyed, nil, timer.getTime() + 30)
    env.info("[DUSTOFF] Win/loss monitoring started")
end

-- ============================================
-- EXECUTION
-- ============================================

timer.scheduleFunction(function()
    DMS.DustoffCorridor.start()
    return nil
end, nil, timer.getTime() + 2)

timer.scheduleFunction(function()
    DMS.DustoffCorridor.startConditionMonitoring()
    return nil
end, nil, timer.getTime() + 10)

env.info("[DUSTOFF] Dustoff Corridor master init script loaded - DEBUG AND ERROR MODE ENABLED")
_G.DMS = DMS
