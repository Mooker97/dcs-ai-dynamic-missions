-- Support Request System for DCS Missions
-- Player can call in various support assets through F10 menu
-- Place in mission via DO SCRIPT FILE
--
-- F10 menus are built PER PLAYER GROUP (so each request uses the position of
-- the player who pressed it). If DMS.CommandMenu is loaded, the menu is added
-- under its root; otherwise a standalone per-group "Support Requests" menu is
-- built on S_EVENT_BIRTH / S_EVENT_PLAYER_ENTER_UNIT.
--
-- Asset groups (MEDEVAC/SEAD/CAS) are normally LATE ACTIVATION groups placed
-- in the ME. CAS/SEAD assets may instead provide `spawnData` (a coalition.addGroup
-- group table) and `country` to be spawned on demand.

DMS = DMS or {}
DMS.SupportRequests = {}

-- Registered support assets
DMS.SupportRequests.Assets = {}
DMS.SupportRequests.Active = false
DMS.SupportRequests.Cooldowns = {}
DMS.SupportRequests.MenuGroups = {}  -- groupId -> true (standalone menu dedupe)

-- Asset types
DMS.SupportRequests.TYPES = {
    ARTILLERY = "ARTILLERY",
    MORTAR = "MORTAR",
    SMOKE = "SMOKE",
    ILLUMINATION = "ILLUMINATION",
    MEDEVAC = "MEDEVAC",
    SEAD = "SEAD",
    CAS = "CAS",
    RESUPPLY = "RESUPPLY",
}

-- Configuration
DMS.SupportRequests.Config = {
    playerCoalition = coalition.side.BLUE,
    defaultCooldown = 120,
    artilleryDelay = 45,        -- Seconds until artillery arrives
    artilleryRounds = 6,        -- Rounds per fire mission
    artillerySpread = 50,       -- Meters spread
    artilleryPower = 100,       -- trigger.action.explosion power per round
    smokeColors = {
        red = trigger.smokeColor.Red,
        green = trigger.smokeColor.Green,
        blue = trigger.smokeColor.Blue,
        white = trigger.smokeColor.White,
        orange = trigger.smokeColor.Orange,
    },
    illuminationAltitude = 500,
    illuminationPower = 100000,
    medevacGroupPrefix = "MEDEVAC",
    announceRequests = true,
    -- CAS tasking
    casZoneRadius = 3000,       -- EngageTargetsInZone radius (m)
    casAltitude = 2500,         -- Orbit altitude (m MSL)
    casSpeed = 150,             -- m/s
    casTargetTypes = {"Ground Units"},
    -- Resupply
    resupplyDelay = 600,
    resupplyCargoType = "container_cargo",
    defaultCountry = nil,       -- country.id for statics; nil = derive from requester / coalition
}

local SMOKE_ORDER = {"red", "green", "blue", "white", "orange"}
local staticCounter = 0

-- ============================================================================
-- Local helpers
-- ============================================================================

local function debugLog(fmt, ...)
    if DMS.Settings and DMS.Settings.isDebug and DMS.Settings.isDebug() then
        env.info(string.format("[SupportRequests] " .. fmt, ...))
    end
end

local function logError(context, err)
    env.error(string.format("[SupportRequests] %s: %s", context, tostring(err)))
    if DMS.Error and DMS.Error.log then
        pcall(DMS.Error.log, "SupportRequests", context, err)
    end
end

--- Schedule a pcall-guarded one-shot function
local function schedule(delay, context, fn)
    timer.scheduleFunction(function()
        local ok, err = pcall(fn)
        if not ok then logError(context, err) end
        return nil
    end, nil, timer.getTime() + delay)
end

--- Announce to the requesting group if known, else to the coalition
local function announce(text, duration, options)
    if not DMS.SupportRequests.Config.announceRequests then return end
    if options and options.groupId then
        trigger.action.outTextForGroup(options.groupId, text, duration or 10)
    else
        trigger.action.outTextForCoalition(DMS.SupportRequests.Config.playerCoalition, text, duration or 10)
    end
end

local function groundPoint(pos)
    return {x = pos.x, y = land.getHeight({x = pos.x, y = pos.z}), z = pos.z}
end

local function getAliveGroup(groupName)
    if not groupName then return nil end
    local group = Group.getByName(groupName)
    if group and group:isExist() and group:getSize() > 0 then
        return group
    end
    return nil
end

local function groupLeadPoint(group)
    local unit = group and group:getUnit(1)
    if unit and unit:isExist() then
        return unit:getPoint()
    end
    return nil
end

local function defaultCountryFor(side)
    if DMS.SupportRequests.Config.defaultCountry then
        return DMS.SupportRequests.Config.defaultCountry
    end
    if side == coalition.side.RED then
        return country.id.RUSSIA
    end
    return country.id.USA
end

--- Configure support request system
-- @param settings table Configuration overrides
function DMS.SupportRequests.configure(settings)
    for key, value in pairs(settings or {}) do
        DMS.SupportRequests.Config[key] = value
    end
end

--- Register a support asset
-- @param assetId string Unique asset ID
-- @param assetType string Asset type from TYPES
-- @param groupName string|nil Group name (for mobile assets)
-- @param options table|nil {cooldown, maxUses, position, range, spawnData, country}
function DMS.SupportRequests.registerAsset(assetId, assetType, groupName, options)
    options = options or {}

    DMS.SupportRequests.Assets[assetId] = {
        id = assetId,
        type = assetType,
        groupName = groupName,
        available = true,
        cooldown = options.cooldown or DMS.SupportRequests.Config.defaultCooldown,
        maxUses = options.maxUses or -1,  -- -1 = unlimited
        uses = 0,
        position = options.position,  -- Fixed position for static assets
        range = options.range or 20000,  -- Max range in meters
        spawnData = options.spawnData,   -- coalition.addGroup table (optional)
        country = options.country,       -- country.id for spawnData
        category = options.category or Group.Category.AIRPLANE,
    }
    debugLog("Registered asset '%s' (%s)", assetId, tostring(assetType))
end

--- Check if asset is available
local function isAssetAvailable(assetId)
    local asset = DMS.SupportRequests.Assets[assetId]
    if not asset then return false end

    if asset.maxUses > 0 and asset.uses >= asset.maxUses then
        return false
    end

    local cooldownEnd = DMS.SupportRequests.Cooldowns[assetId] or 0
    if timer.getTime() < cooldownEnd then
        return false
    end

    return asset.available
end

--- Start cooldown for asset
local function startCooldown(assetId)
    local asset = DMS.SupportRequests.Assets[assetId]
    if asset then
        DMS.SupportRequests.Cooldowns[assetId] = timer.getTime() + asset.cooldown
        asset.uses = asset.uses + 1
    end
end

--- Find first available asset of a type
local function findAsset(assetType)
    for assetId, asset in pairs(DMS.SupportRequests.Assets) do
        if asset.type == assetType and isAssetAvailable(assetId) then
            return assetId, asset
        end
    end
    return nil, nil
end

--- Activate (late activation) or spawn the asset's group
-- @return Group|nil
local function activateAssetGroup(asset)
    local group = getAliveGroup(asset.groupName)
    if group then
        trigger.action.activateGroup(group)
        return group
    end
    if asset.spawnData and asset.country then
        local data = asset.spawnData
        local ok, spawned = pcall(coalition.addGroup, asset.country, asset.category, data)
        if ok and spawned then
            asset.groupName = spawned:getName()
            debugLog("Spawned asset group '%s'", asset.groupName)
            return spawned
        end
        logError("spawn asset " .. tostring(asset.id), spawned)
    end
    return nil
end

--- Build a two-point air route: current position -> target with a task
local function buildAirRoute(group, target, alt, speed, task)
    local start = groupLeadPoint(group) or target
    return {
        id = "Mission",
        params = {
            airborne = true,
            route = {
                points = {
                    {
                        x = start.x, y = start.z,
                        alt = alt, alt_type = "BARO",
                        speed = speed,
                        type = "Turning Point", action = "Turning Point",
                    },
                    {
                        x = target.x, y = target.z,
                        alt = alt, alt_type = "BARO",
                        speed = speed,
                        type = "Turning Point", action = "Turning Point",
                        task = task,
                    },
                },
            },
        },
    }
end

--- Get player position from a menu context
local function getPlayerPosition(ctx)
    if not ctx then return nil end
    local unit = ctx.unitName and Unit.getByName(ctx.unitName)
    if unit and unit:isExist() then
        return unit:getPoint(), unit
    end
    local group = getAliveGroup(ctx.groupName)
    local lead = group and group:getUnit(1)
    if lead and lead:isExist() then
        return lead:getPoint(), lead
    end
    return nil
end

-- ============================================================================
-- Requests
-- ============================================================================

--- Request artillery strike
-- @param targetPos table Target position {x, y, z}
-- @param options table|nil {assetId, delay, rounds, spread, groupId}
function DMS.SupportRequests.requestArtillery(targetPos, options)
    options = options or {}
    if not targetPos then return false end

    local assetId = options.assetId
    if not assetId then
        assetId = findAsset(DMS.SupportRequests.TYPES.ARTILLERY) or "default_arty"
    end
    if not isAssetAvailable(assetId) then
        announce("ARTILLERY: Asset unavailable or on cooldown.", 10, options)
        return false
    end

    local delay = options.delay or DMS.SupportRequests.Config.artilleryDelay
    local rounds = options.rounds or DMS.SupportRequests.Config.artilleryRounds
    local spread = options.spread or DMS.SupportRequests.Config.artillerySpread
    local power = DMS.SupportRequests.Config.artilleryPower

    announce(string.format("ARTILLERY: Fire mission received. Rounds inbound in %d seconds.", delay), 10, options)
    debugLog("Artillery fire mission (%d rounds, %ds delay)", rounds, delay)

    schedule(delay, "artillery", function()
        for i = 1, rounds do
            schedule((i - 1) * 2, "artillery round", function()  -- 2 seconds between rounds
                local impact = groundPoint({
                    x = targetPos.x + (math.random() - 0.5) * spread * 2,
                    z = targetPos.z + (math.random() - 0.5) * spread * 2,
                })
                trigger.action.explosion(impact, power)
            end)
        end
        schedule(rounds * 2, "artillery complete", function()
            announce("ARTILLERY: Splash! Rounds complete.", 5, options)
        end)
    end)

    startCooldown(assetId)
    return true
end

--- Request smoke marker
-- @param pos table Position for smoke
-- @param color string Color name (red, green, blue, white, orange)
-- @param options table|nil {groupId}
function DMS.SupportRequests.requestSmoke(pos, color, options)
    if not pos then return false end
    color = color or "red"
    local smokeColor = DMS.SupportRequests.Config.smokeColors[color] or trigger.smokeColor.Red

    trigger.action.smoke(groundPoint(pos), smokeColor)
    announce(string.format("SMOKE: %s smoke deployed at marked position.", color:upper()), 5, options)
    return true
end

--- Request illumination flare
-- @param pos table Position for illumination
-- @param options table|nil {groupId}
function DMS.SupportRequests.requestIllumination(pos, options)
    if not pos then return false end
    local ground = groundPoint(pos)
    trigger.action.illuminationBomb({
        x = ground.x,
        y = ground.y + DMS.SupportRequests.Config.illuminationAltitude,
        z = ground.z,
    }, DMS.SupportRequests.Config.illuminationPower)

    announce("ILLUMINATION: Flare deployed.", 5, options)
    return true
end

--- Request MEDEVAC
-- @param pos table Pickup position
-- @param options table|nil {groupId}
function DMS.SupportRequests.requestMEDEVAC(pos, options)
    options = options or {}
    if not pos then return false end

    local assetId, asset = findAsset(DMS.SupportRequests.TYPES.MEDEVAC)
    local group = asset and getAliveGroup(asset.groupName)
    if not group then
        announce("MEDEVAC: No available assets at this time.", 10, options)
        return false
    end
    startCooldown(assetId)
    trigger.action.activateGroup(group)

    local groupName = asset.groupName
    -- Give the controller a moment after activation before tasking
    schedule(1, "medevac task", function()
        local g = getAliveGroup(groupName)
        if not g then return end
        local controller = g:getController()
        if not controller then return end
        local start = groupLeadPoint(g) or pos
        local alt = land.getHeight({x = pos.x, y = pos.z}) + 150
        controller:setTask({
            id = "Mission",
            params = {
                route = {
                    points = {
                        {x = start.x, y = start.z, alt = 150, alt_type = "RADIO", speed = 50,
                         type = "Turning Point", action = "Turning Point"},
                        {x = pos.x, y = pos.z, alt = alt, alt_type = "BARO", speed = 50,
                         type = "Turning Point", action = "Fly Over Point"},
                    },
                },
            },
        })
    end)

    announce("MEDEVAC: Dustoff inbound to marked position. ETA 5 minutes.", 10, options)
    debugLog("MEDEVAC '%s' tasked", groupName)

    schedule(2, "medevac smoke", function()
        trigger.action.smoke(groundPoint(pos), trigger.smokeColor.Green)
    end)

    return true
end

--- Request SEAD support
-- @param targetArea table Center of target area
-- @param options table|nil {groupId}
function DMS.SupportRequests.requestSEAD(targetArea, options)
    options = options or {}
    if not targetArea then return false end

    local assetId, asset = findAsset(DMS.SupportRequests.TYPES.SEAD)
    local group = asset and activateAssetGroup(asset)
    if not group then
        announce("SEAD: No available assets at this time.", 10, options)
        return false
    end
    startCooldown(assetId)

    local groupName = group:getName()
    schedule(1, "sead task", function()
        local g = getAliveGroup(groupName)
        if not g then return end
        local controller = g:getController()
        if not controller then return end
        controller:setOption(AI.Option.Air.id.ROE, AI.Option.Air.val.ROE.WEAPON_FREE)
        controller:setTask(buildAirRoute(g, targetArea, 6000, 220, {
            id = "ComboTask",
            params = {
                tasks = {
                    {
                        number = 1, enabled = true, auto = false,
                        id = "EngageTargets",
                        params = {targetTypes = {"Air Defence"}, priority = 0, maxDist = 60000},
                    },
                },
            },
        }))
    end)

    announce("SEAD: Wild Weasel flight tasked to suppress air defenses in target area.", 10, options)
    debugLog("SEAD '%s' tasked", groupName)
    return true
end

--- Request CAS support
-- Activates (or spawns) a CAS aircraft group, routes it to the target area and
-- gives it an EngageTargetsInZone en-route task plus an Orbit over the area.
-- @param targetArea table Target area {x, y, z}
-- @param options table|nil {groupId, radius, altitude, speed, duration}
function DMS.SupportRequests.requestCAS(targetArea, options)
    options = options or {}
    if not targetArea then return false end

    local assetId, asset = findAsset(DMS.SupportRequests.TYPES.CAS)
    local group = asset and activateAssetGroup(asset)
    if not group then
        announce("CAS: No available assets at this time.", 10, options)
        return false
    end
    startCooldown(assetId)

    local cfg = DMS.SupportRequests.Config
    local radius = options.radius or cfg.casZoneRadius
    local alt = options.altitude or cfg.casAltitude
    local speed = options.speed or cfg.casSpeed
    local groupName = group:getName()

    schedule(1, "cas task", function()
        local g = getAliveGroup(groupName)
        if not g then return end
        local controller = g:getController()
        if not controller then return end
        controller:setOption(AI.Option.Air.id.ROE, AI.Option.Air.val.ROE.WEAPON_FREE)

        local orbitTask = {
            number = 2, enabled = true, auto = false,
            id = "Orbit",
            params = {
                pattern = "Circle",
                point = {x = targetArea.x, y = targetArea.z},
                altitude = alt,
                speed = speed,
            },
        }
        local combo = {
            id = "ComboTask",
            params = {
                tasks = {
                    {
                        number = 1, enabled = true, auto = false,
                        id = "EngageTargetsInZone",
                        params = {
                            point = {x = targetArea.x, y = targetArea.z},
                            zoneRadius = radius,
                            targetTypes = cfg.casTargetTypes,
                            priority = 0,
                        },
                    },
                    orbitTask,
                },
            },
        }
        controller:setTask(buildAirRoute(g, targetArea, alt, speed, combo))
    end)

    announce("CAS: Close air support inbound. Mark targets with smoke.", 10, options)
    debugLog("CAS '%s' tasked (radius %dm)", groupName, radius)
    return true
end

--- Request resupply drop
-- @param pos table Drop position
-- @param options table|nil {groupId, country, unitName}
function DMS.SupportRequests.requestResupply(pos, options)
    options = options or {}
    if not pos then return false end

    -- addStaticObject needs a COUNTRY id, not a coalition id
    local countryId = options.country
    if not countryId and options.unitName then
        local unit = Unit.getByName(options.unitName)
        if unit and unit:isExist() then countryId = unit:getCountry() end
    end
    countryId = countryId or defaultCountryFor(DMS.SupportRequests.Config.playerCoalition)

    local delay = options.delay or DMS.SupportRequests.Config.resupplyDelay
    announce(string.format("RESUPPLY: Request acknowledged. C-130 will be overhead in %d minutes.", math.floor(delay / 60)), 10, options)

    schedule(delay, "resupply drop", function()
        staticCounter = staticCounter + 1
        local cargoData = {
            name = string.format("Resupply-%d-%d", staticCounter, math.floor(timer.getTime())),
            type = DMS.SupportRequests.Config.resupplyCargoType,
            category = "Cargos",
            canCargo = true,
            mass = 1000,
            x = pos.x,
            y = pos.z,
            heading = 0,
        }
        coalition.addStaticObject(countryId, cargoData)
        trigger.action.smoke(groundPoint(pos), trigger.smokeColor.Blue)
        announce("RESUPPLY: Cargo on the ground. Marked with blue smoke.", 10, options)
        debugLog("Resupply '%s' dropped (country %s)", cargoData.name, tostring(countryId))
    end)

    return true
end

-- ============================================================================
-- F10 menu (per player group)
-- ============================================================================

--- Wrap a request so it runs with the pressing player's position
local function withPosition(ctx, fn)
    local ok, err = pcall(function()
        local pos, unit = getPlayerPosition(ctx)
        if not pos then
            trigger.action.outTextForGroup(ctx.groupId, "Support: unable to determine your position.", 5)
            return
        end
        fn(pos, {groupId = ctx.groupId, unitName = unit and unit:getName() or ctx.unitName})
    end)
    if not ok then logError("menu command", err) end
end

-- Menu entries: {label, submenu or nil, function(pos, opts)}
local function menuEntries()
    local entries = {
        {"Artillery at My Position", nil, function(pos, o) DMS.SupportRequests.requestArtillery(pos, o) end},
    }
    for _, color in ipairs(SMOKE_ORDER) do
        if DMS.SupportRequests.Config.smokeColors[color] then
            table.insert(entries, {color:upper() .. " Smoke", "smoke",
                function(pos, o) DMS.SupportRequests.requestSmoke(pos, color, o) end})
        end
    end
    table.insert(entries, {"Request Illumination", nil, function(pos, o) DMS.SupportRequests.requestIllumination(pos, o) end})
    table.insert(entries, {"Request MEDEVAC", nil, function(pos, o) DMS.SupportRequests.requestMEDEVAC(pos, o) end})
    table.insert(entries, {"Request SEAD", nil, function(pos, o) DMS.SupportRequests.requestSEAD(pos, o) end})
    table.insert(entries, {"Request CAS", nil, function(pos, o) DMS.SupportRequests.requestCAS(pos, o) end})
    table.insert(entries, {"Request Resupply", nil, function(pos, o) DMS.SupportRequests.requestResupply(pos, o) end})
    return entries
end

--- Build standalone menu for one player group (deduped)
local function buildGroupMenu(groupId, groupName, unitName)
    if DMS.SupportRequests.MenuGroups[groupId] then return end
    DMS.SupportRequests.MenuGroups[groupId] = true

    local root = missionCommands.addSubMenuForGroup(groupId, "Support Requests")
    local smokeMenu = missionCommands.addSubMenuForGroup(groupId, "Smoke Markers", root)
    for _, entry in ipairs(menuEntries()) do
        local fn = entry[3]
        missionCommands.addCommandForGroup(groupId, entry[1], entry[2] == "smoke" and smokeMenu or root,
            function(ctx) withPosition(ctx, fn) end,
            {groupId = groupId, groupName = groupName, unitName = unitName})
    end
    debugLog("Built support menu for group %s", tostring(groupName))
end

local eventHandler = {}
function eventHandler:onEvent(event)
    if not event or (event.id ~= world.event.S_EVENT_BIRTH and event.id ~= world.event.S_EVENT_PLAYER_ENTER_UNIT) then
        return
    end
    local ok, err = pcall(function()
        local unit = event.initiator
        if not unit or Object.getCategory(unit) ~= Object.Category.UNIT then return end
        if not unit:isExist() or not unit:getPlayerName() then return end
        if unit:getCoalition() ~= DMS.SupportRequests.Config.playerCoalition then return end
        local group = unit:getGroup()
        if group then buildGroupMenu(group:getID(), group:getName(), unit:getName()) end
    end)
    if not ok then logError("onEvent", err) end
end

--- Build F10 menu for support requests (per player group)
function DMS.SupportRequests.buildMenu()
    if DMS.CommandMenu and DMS.CommandMenu.addCommand then
        -- CommandMenu builds per group and passes ctx {groupId, groupName, unitName, ...}
        DMS.CommandMenu.addMenu("support_req", "Support Requests")
        DMS.CommandMenu.addMenu("smoke_menu", "Smoke Markers", "support_req")
        for i, entry in ipairs(menuEntries()) do
            local fn = entry[3]
            DMS.CommandMenu.addCommand("support_req_" .. i, entry[1],
                entry[2] == "smoke" and "smoke_menu" or "support_req",
                function(ctx) withPosition(ctx, fn) end,
                {confirmation = "SUPPORT: " .. entry[1] .. " requested."})
        end
        return
    end

    world.addEventHandler(eventHandler)
    for _, unit in ipairs(coalition.getPlayers(DMS.SupportRequests.Config.playerCoalition) or {}) do
        pcall(function()
            local group = unit:getGroup()
            if group then buildGroupMenu(group:getID(), group:getName(), unit:getName()) end
        end)
    end
end

-- Alias matching other modules
DMS.SupportRequests.setupMenus = function()
    DMS.SupportRequests.start()
end

--- Get asset status
-- @param assetId string Asset ID
-- @return table|nil Status info
function DMS.SupportRequests.getAssetStatus(assetId)
    local asset = DMS.SupportRequests.Assets[assetId]
    if not asset then return nil end

    local cooldownEnd = DMS.SupportRequests.Cooldowns[assetId] or 0
    return {
        id = assetId,
        type = asset.type,
        available = isAssetAvailable(assetId),
        uses = asset.uses,
        maxUses = asset.maxUses,
        cooldownRemaining = math.max(0, cooldownEnd - timer.getTime()),
    }
end

--- Initialize support request system (registers default artillery, builds menus)
function DMS.SupportRequests.start()
    if DMS.SupportRequests.Active then return end
    DMS.SupportRequests.Active = true

    if not DMS.SupportRequests.Assets["default_arty"] then
        local hasArty = false
        for _, a in pairs(DMS.SupportRequests.Assets) do
            if a.type == DMS.SupportRequests.TYPES.ARTILLERY then hasArty = true end
        end
        if not hasArty then
            DMS.SupportRequests.registerAsset("default_arty", DMS.SupportRequests.TYPES.ARTILLERY, nil, {cooldown = 120})
        end
    end

    DMS.SupportRequests.buildMenu()
    debugLog("Started")
end

--[==[
USAGE EXAMPLE:

DMS.SupportRequests.configure({artilleryDelay = 30, artilleryRounds = 8})

DMS.SupportRequests.registerAsset("battery_alpha", DMS.SupportRequests.TYPES.ARTILLERY, nil, {cooldown = 180, maxUses = 5})
DMS.SupportRequests.registerAsset("dustoff_1", DMS.SupportRequests.TYPES.MEDEVAC, "MEDEVAC-1", {cooldown = 300})
DMS.SupportRequests.registerAsset("weasel_flight", DMS.SupportRequests.TYPES.SEAD, "F-16-SEAD", {cooldown = 600, maxUses = 2})
-- CAS: late-activation group "A-10-CAS" placed in the ME
DMS.SupportRequests.registerAsset("hawg_1", DMS.SupportRequests.TYPES.CAS, "A-10-CAS", {cooldown = 300})

-- Start system (builds per-group F10 menus)
DMS.SupportRequests.start()

-- Note: requestArtillery uses options.assetId, else the first available ARTILLERY asset.
]==]

-- Export
_G.DMS = DMS
