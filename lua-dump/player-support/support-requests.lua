-- Support Request System for DCS Missions
-- Player can call in various support assets through F10 menu
-- Place in mission via DO SCRIPT FILE

DMS = DMS or {}
DMS.SupportRequests = {}

-- Registered support assets
DMS.SupportRequests.Assets = {}
DMS.SupportRequests.Active = false
DMS.SupportRequests.Cooldowns = {}

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
}

--- Configure support request system
-- @param settings table Configuration overrides
function DMS.SupportRequests.configure(settings)
    for key, value in pairs(settings) do
        DMS.SupportRequests.Config[key] = value
    end
end

--- Register a support asset
-- @param assetId string Unique asset ID
-- @param assetType string Asset type from TYPES
-- @param groupName string|nil Group name (for mobile assets)
-- @param options table|nil Asset options
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
    }
end

--- Check if asset is available
-- @param assetId string Asset ID
-- @return boolean Available
local function isAssetAvailable(assetId)
    local asset = DMS.SupportRequests.Assets[assetId]
    if not asset then return false end

    -- Check uses
    if asset.maxUses > 0 and asset.uses >= asset.maxUses then
        return false
    end

    -- Check cooldown
    local cooldownEnd = DMS.SupportRequests.Cooldowns[assetId] or 0
    if timer.getTime() < cooldownEnd then
        return false
    end

    return asset.available
end

--- Start cooldown for asset
-- @param assetId string Asset ID
local function startCooldown(assetId)
    local asset = DMS.SupportRequests.Assets[assetId]
    if asset then
        DMS.SupportRequests.Cooldowns[assetId] = timer.getTime() + asset.cooldown
        asset.uses = asset.uses + 1
    end
end

--- Get player position
-- @return table|nil Player position
local function getPlayerPosition()
    local players = coalition.getPlayers(DMS.SupportRequests.Config.playerCoalition)
    if players and #players > 0 then
        return players[1]:getPoint()
    end
    return nil
end

--- Request artillery strike
-- @param targetPos table Target position {x, y, z}
-- @param options table|nil Strike options
function DMS.SupportRequests.requestArtillery(targetPos, options)
    options = options or {}

    local assetId = options.assetId or "default_arty"
    if not isAssetAvailable(assetId) then
        if DMS.SupportRequests.Config.announceRequests then
            trigger.action.outTextForCoalition(
                DMS.SupportRequests.Config.playerCoalition,
                "ARTILLERY: Asset unavailable or on cooldown.",
                10
            )
        end
        return false
    end

    local delay = options.delay or DMS.SupportRequests.Config.artilleryDelay
    local rounds = options.rounds or DMS.SupportRequests.Config.artilleryRounds
    local spread = options.spread or DMS.SupportRequests.Config.artillerySpread

    if DMS.SupportRequests.Config.announceRequests then
        trigger.action.outTextForCoalition(
            DMS.SupportRequests.Config.playerCoalition,
            string.format("ARTILLERY: Fire mission received. Rounds inbound in %d seconds.", delay),
            10
        )
    end

    -- Schedule artillery impact
    timer.scheduleFunction(function()
        for i = 1, rounds do
            timer.scheduleFunction(function()
                local impactPos = {
                    x = targetPos.x + (math.random() - 0.5) * spread * 2,
                    y = targetPos.y,
                    z = targetPos.z + (math.random() - 0.5) * spread * 2,
                }
                trigger.action.explosion(impactPos, 100)
            end, nil, timer.getTime() + (i - 1) * 2)  -- 2 seconds between rounds
        end

        if DMS.SupportRequests.Config.announceRequests then
            trigger.action.outTextForCoalition(
                DMS.SupportRequests.Config.playerCoalition,
                "ARTILLERY: Splash! Rounds complete.",
                5
            )
        end
    end, nil, timer.getTime() + delay)

    startCooldown(assetId)
    return true
end

--- Request smoke marker
-- @param pos table Position for smoke
-- @param color string Color name (red, green, blue, white, orange)
function DMS.SupportRequests.requestSmoke(pos, color)
    color = color or "red"
    local smokeColor = DMS.SupportRequests.Config.smokeColors[color]

    if not smokeColor then
        smokeColor = trigger.smokeColor.Red
    end

    trigger.action.smoke(pos, smokeColor)

    if DMS.SupportRequests.Config.announceRequests then
        trigger.action.outTextForCoalition(
            DMS.SupportRequests.Config.playerCoalition,
            string.format("SMOKE: %s smoke deployed at marked position.", color:upper()),
            5
        )
    end

    return true
end

--- Request illumination flare
-- @param pos table Position for illumination
function DMS.SupportRequests.requestIllumination(pos)
    local altitude = DMS.SupportRequests.Config.illuminationAltitude
    local power = DMS.SupportRequests.Config.illuminationPower

    local flarePos = {
        x = pos.x,
        y = pos.y + altitude,
        z = pos.z,
    }

    trigger.action.illuminationBomb(flarePos, power)

    if DMS.SupportRequests.Config.announceRequests then
        trigger.action.outTextForCoalition(
            DMS.SupportRequests.Config.playerCoalition,
            "ILLUMINATION: Flare deployed.",
            5
        )
    end

    return true
end

--- Request MEDEVAC
-- @param pos table Pickup position
-- @param options table|nil Options
function DMS.SupportRequests.requestMEDEVAC(pos, options)
    options = options or {}

    -- Find available MEDEVAC group
    local medevacGroup = nil
    for assetId, asset in pairs(DMS.SupportRequests.Assets) do
        if asset.type == DMS.SupportRequests.TYPES.MEDEVAC and isAssetAvailable(assetId) then
            medevacGroup = asset.groupName
            startCooldown(assetId)
            break
        end
    end

    if not medevacGroup then
        if DMS.SupportRequests.Config.announceRequests then
            trigger.action.outTextForCoalition(
                DMS.SupportRequests.Config.playerCoalition,
                "MEDEVAC: No available assets at this time.",
                10
            )
        end
        return false
    end

    -- Activate MEDEVAC group if LATE ACTIVATION
    local group = Group.getByName(medevacGroup)
    if group then
        trigger.action.activateGroup(group)

        -- Set destination waypoint to pickup pos
        local controller = group:getController()
        if controller then
            local mission = {
                id = 'Mission',
                params = {
                    route = {
                        points = {
                            {
                                x = pos.x,
                                y = pos.z,
                                type = "Turning Point",
                                action = "Fly Over Point",
                                speed = 50,
                            }
                        }
                    }
                }
            }
            controller:setTask(mission)
        end
    end

    if DMS.SupportRequests.Config.announceRequests then
        trigger.action.outTextForCoalition(
            DMS.SupportRequests.Config.playerCoalition,
            "MEDEVAC: Dustoff inbound to marked position. ETA 5 minutes.",
            10
        )
    end

    -- Mark pickup zone with smoke
    timer.scheduleFunction(function()
        trigger.action.smoke(pos, trigger.smokeColor.Green)
    end, nil, timer.getTime() + 2)

    return true
end

--- Request SEAD support
-- @param targetArea table Center of target area
-- @param options table|nil Options
function DMS.SupportRequests.requestSEAD(targetArea, options)
    options = options or {}

    -- Find available SEAD asset
    local seadGroup = nil
    local seadAssetId = nil
    for assetId, asset in pairs(DMS.SupportRequests.Assets) do
        if asset.type == DMS.SupportRequests.TYPES.SEAD and isAssetAvailable(assetId) then
            seadGroup = asset.groupName
            seadAssetId = assetId
            break
        end
    end

    if not seadGroup then
        if DMS.SupportRequests.Config.announceRequests then
            trigger.action.outTextForCoalition(
                DMS.SupportRequests.Config.playerCoalition,
                "SEAD: No available assets at this time.",
                10
            )
        end
        return false
    end

    -- Activate and task SEAD group
    local group = Group.getByName(seadGroup)
    if group then
        trigger.action.activateGroup(group)

        local controller = group:getController()
        if controller then
            -- SEAD task
            controller:setOption(AI.Option.Air.id.ROE, AI.Option.Air.val.ROE.WEAPON_FREE)

            local mission = {
                id = 'Mission',
                params = {
                    route = {
                        points = {
                            {
                                x = targetArea.x,
                                y = targetArea.z,
                                type = "Turning Point",
                                action = "Fly Over Point",
                                speed = 200,
                                task = {
                                    id = "ComboTask",
                                    params = {
                                        tasks = {
                                            {
                                                id = "EngageTargets",
                                                params = {
                                                    targetTypes = {"Air Defence"},
                                                    priority = 0,
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
            controller:setTask(mission)
        end
    end

    startCooldown(seadAssetId)

    if DMS.SupportRequests.Config.announceRequests then
        trigger.action.outTextForCoalition(
            DMS.SupportRequests.Config.playerCoalition,
            "SEAD: Wild Weasel flight tasked to suppress air defenses in target area.",
            10
        )
    end

    return true
end

--- Request CAS support
-- @param targetArea table Target area
-- @param options table|nil Options
function DMS.SupportRequests.requestCAS(targetArea, options)
    options = options or {}

    -- Find available CAS asset
    local casGroup = nil
    local casAssetId = nil
    for assetId, asset in pairs(DMS.SupportRequests.Assets) do
        if asset.type == DMS.SupportRequests.TYPES.CAS and isAssetAvailable(assetId) then
            casGroup = asset.groupName
            casAssetId = assetId
            break
        end
    end

    if not casGroup then
        if DMS.SupportRequests.Config.announceRequests then
            trigger.action.outTextForCoalition(
                DMS.SupportRequests.Config.playerCoalition,
                "CAS: No available assets at this time.",
                10
            )
        end
        return false
    end

    local group = Group.getByName(casGroup)
    if group then
        trigger.action.activateGroup(group)

        local controller = group:getController()
        if controller then
            controller:setOption(AI.Option.Air.id.ROE, AI.Option.Air.val.ROE.WEAPON_FREE)

            local mission = {
                id = 'Mission',
                params = {
                    route = {
                        points = {
                            {
                                x = targetArea.x,
                                y = targetArea.z,
                                type = "Turning Point",
                                action = "Fly Over Point",
                                speed = 150,
                                task = {
                                    id = "ComboTask",
                                    params = {
                                        tasks = {
                                            {
                                                id = "CAS",
                                                params = {
                                                    attackGroup = true,
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
            controller:setTask(mission)
        end
    end

    startCooldown(casAssetId)

    if DMS.SupportRequests.Config.announceRequests then
        trigger.action.outTextForCoalition(
            DMS.SupportRequests.Config.playerCoalition,
            "CAS: Close air support inbound. Mark targets with smoke.",
            10
        )
    end

    return true
end

--- Request resupply drop
-- @param pos table Drop position
-- @param options table|nil Options
function DMS.SupportRequests.requestResupply(pos, options)
    options = options or {}

    if DMS.SupportRequests.Config.announceRequests then
        trigger.action.outTextForCoalition(
            DMS.SupportRequests.Config.playerCoalition,
            "RESUPPLY: Request acknowledged. C-130 will be overhead in 10 minutes.",
            10
        )
    end

    -- Simulate cargo drop after delay
    timer.scheduleFunction(function()
        -- Create cargo static object at position
        local cargoData = {
            name = "Resupply-" .. timer.getTime(),
            type = "container_cargo",
            x = pos.x,
            y = pos.z,
            heading = 0,
        }

        coalition.addStaticObject(DMS.SupportRequests.Config.playerCoalition, cargoData)

        -- Mark with smoke
        trigger.action.smoke(pos, trigger.smokeColor.Blue)

        if DMS.SupportRequests.Config.announceRequests then
            trigger.action.outTextForCoalition(
                DMS.SupportRequests.Config.playerCoalition,
                "RESUPPLY: Cargo on the ground. Marked with blue smoke.",
                10
            )
        end
    end, nil, timer.getTime() + 600)  -- 10 minutes

    return true
end

--- Build F10 menu for support requests
function DMS.SupportRequests.buildMenu()
    if not DMS.CommandMenu then
        -- Create standalone menu if CommandMenu not available
        local rootMenu = missionCommands.addSubMenuForCoalition(
            DMS.SupportRequests.Config.playerCoalition,
            "Support Requests"
        )

        -- Artillery submenu
        local artyMenu = missionCommands.addSubMenuForCoalition(
            DMS.SupportRequests.Config.playerCoalition,
            "Artillery",
            rootMenu
        )

        missionCommands.addCommandForCoalition(
            DMS.SupportRequests.Config.playerCoalition,
            "Fire at My Position",
            artyMenu,
            function()
                local pos = getPlayerPosition()
                if pos then
                    DMS.SupportRequests.requestArtillery(pos)
                end
            end
        )

        -- Smoke submenu
        local smokeMenu = missionCommands.addSubMenuForCoalition(
            DMS.SupportRequests.Config.playerCoalition,
            "Smoke Marker",
            rootMenu
        )

        for color, _ in pairs(DMS.SupportRequests.Config.smokeColors) do
            missionCommands.addCommandForCoalition(
                DMS.SupportRequests.Config.playerCoalition,
                color:upper() .. " Smoke",
                smokeMenu,
                function()
                    local pos = getPlayerPosition()
                    if pos then
                        DMS.SupportRequests.requestSmoke(pos, color)
                    end
                end
            )
        end

        -- Other support options
        missionCommands.addCommandForCoalition(
            DMS.SupportRequests.Config.playerCoalition,
            "Request Illumination",
            rootMenu,
            function()
                local pos = getPlayerPosition()
                if pos then
                    DMS.SupportRequests.requestIllumination(pos)
                end
            end
        )

        missionCommands.addCommandForCoalition(
            DMS.SupportRequests.Config.playerCoalition,
            "Request MEDEVAC",
            rootMenu,
            function()
                local pos = getPlayerPosition()
                if pos then
                    DMS.SupportRequests.requestMEDEVAC(pos)
                end
            end
        )

        missionCommands.addCommandForCoalition(
            DMS.SupportRequests.Config.playerCoalition,
            "Request SEAD",
            rootMenu,
            function()
                local pos = getPlayerPosition()
                if pos then
                    DMS.SupportRequests.requestSEAD(pos)
                end
            end
        )

        missionCommands.addCommandForCoalition(
            DMS.SupportRequests.Config.playerCoalition,
            "Request CAS",
            rootMenu,
            function()
                local pos = getPlayerPosition()
                if pos then
                    DMS.SupportRequests.requestCAS(pos)
                end
            end
        )

    else
        -- Use CommandMenu system
        DMS.CommandMenu.addMenu("support_req", "Support Requests")

        DMS.CommandMenu.addCommand("arty_here", "Artillery at My Position", "support_req", function()
            local pos = getPlayerPosition()
            if pos then
                DMS.SupportRequests.requestArtillery(pos)
            end
        end)

        -- Add smoke submenu
        DMS.CommandMenu.addMenu("smoke_menu", "Smoke Markers", "support_req")
        for color, _ in pairs(DMS.SupportRequests.Config.smokeColors) do
            DMS.CommandMenu.addCommand("smoke_" .. color, color:upper() .. " Smoke", "smoke_menu", function()
                local pos = getPlayerPosition()
                if pos then
                    DMS.SupportRequests.requestSmoke(pos, color)
                end
            end)
        end

        DMS.CommandMenu.addCommand("illum", "Request Illumination", "support_req", function()
            local pos = getPlayerPosition()
            if pos then
                DMS.SupportRequests.requestIllumination(pos)
            end
        end)

        DMS.CommandMenu.addCommand("medevac", "Request MEDEVAC", "support_req", function()
            local pos = getPlayerPosition()
            if pos then
                DMS.SupportRequests.requestMEDEVAC(pos)
            end
        end)

        DMS.CommandMenu.addCommand("sead", "Request SEAD", "support_req", function()
            local pos = getPlayerPosition()
            if pos then
                DMS.SupportRequests.requestSEAD(pos)
            end
        end)

        DMS.CommandMenu.addCommand("cas", "Request CAS", "support_req", function()
            local pos = getPlayerPosition()
            if pos then
                DMS.SupportRequests.requestCAS(pos)
            end
        end)
    end
end

--- Get asset status
-- @param assetId string Asset ID
-- @return table|nil Status info
function DMS.SupportRequests.getAssetStatus(assetId)
    local asset = DMS.SupportRequests.Assets[assetId]
    if not asset then return nil end

    local cooldownEnd = DMS.SupportRequests.Cooldowns[assetId] or 0
    local cooldownRemaining = math.max(0, cooldownEnd - timer.getTime())

    return {
        id = assetId,
        type = asset.type,
        available = isAssetAvailable(assetId),
        uses = asset.uses,
        maxUses = asset.maxUses,
        cooldownRemaining = cooldownRemaining,
    }
end

--- Initialize support request system
function DMS.SupportRequests.start()
    if DMS.SupportRequests.Active then return end

    DMS.SupportRequests.Active = true
    DMS.SupportRequests.buildMenu()

    -- Register default artillery asset if none registered
    if not next(DMS.SupportRequests.Assets) then
        DMS.SupportRequests.registerAsset("default_arty", DMS.SupportRequests.TYPES.ARTILLERY, nil, {
            cooldown = 120,
        })
    end
end

--[[
USAGE EXAMPLE:

-- Configure
DMS.SupportRequests.configure({
    artilleryDelay = 30,
    artilleryRounds = 8,
})

-- Register assets
DMS.SupportRequests.registerAsset("battery_alpha", DMS.SupportRequests.TYPES.ARTILLERY, nil, {
    cooldown = 180,
    maxUses = 5,
})

DMS.SupportRequests.registerAsset("dustoff_1", DMS.SupportRequests.TYPES.MEDEVAC, "MEDEVAC-1", {
    cooldown = 300,
})

DMS.SupportRequests.registerAsset("weasel_flight", DMS.SupportRequests.TYPES.SEAD, "F-16-SEAD", {
    cooldown = 600,
    maxUses = 2,
})

DMS.SupportRequests.registerAsset("hawg_1", DMS.SupportRequests.TYPES.CAS, "A-10-CAS", {
    cooldown = 300,
})

-- Start system (builds F10 menu)
DMS.SupportRequests.start()

-- F10 Menu structure:
-- Support Requests
--   +-- Artillery at My Position
--   +-- Smoke Markers
--   |     +-- RED Smoke
--   |     +-- GREEN Smoke
--   |     +-- BLUE Smoke
--   |     +-- WHITE Smoke
--   |     +-- ORANGE Smoke
--   +-- Request Illumination
--   +-- Request MEDEVAC
--   +-- Request SEAD
--   +-- Request CAS
]]

-- Export
_G.DMS = DMS
