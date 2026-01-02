-- Decoy System for DCS Missions
-- Creates fake targets and defensive positions
-- Requires: utils/group-utils.lua
-- Place in mission via DO SCRIPT FILE

DMS = DMS or {}
DMS.Decoys = {}

-- Decoy definitions
DMS.Decoys.Sites = {}
DMS.Decoys.Active = false
DMS.Decoys.TimerId = nil

-- Decoy types
DMS.Decoys.Types = {
    INFLATABLE = "inflatable",     -- Inflatable decoys (tanks, aircraft)
    HEAT = "heat",                  -- Heat emitters for IR
    RADAR = "radar",                -- Radar reflectors
    SMOKE = "smoke",                -- Smoke generators
    LIGHT = "light",                -- Light decoys (fake airfield)
}

-- Configuration
DMS.Decoys.Config = {
    playerCoalition = coalition.side.BLUE,
    enemyCoalition = coalition.side.RED,
    detectionRadius = 5000,        -- Radius to detect player attacks
    revealOnAttack = true,         -- Reveal decoy when attacked
    revealMessage = true,
    smokeInterval = 120,           -- Seconds between smoke refreshes
    displayDuration = 10,
}

--- Configure decoy system
-- @param settings table Configuration overrides
function DMS.Decoys.configure(settings)
    for key, value in pairs(settings) do
        DMS.Decoys.Config[key] = value
    end
end

--- Register a decoy site
-- @param id string Decoy identifier
-- @param position table Vec3 position
-- @param options table Decoy options
function DMS.Decoys.register(id, position, options)
    options = options or {}

    DMS.Decoys.Sites[id] = {
        id = id,
        position = {x = position.x, y = position.y or 0, z = position.z},
        type = options.type or DMS.Decoys.Types.INFLATABLE,
        disguisedAs = options.disguisedAs or "Unknown Target",
        revealed = false,
        attacked = false,
        smokeColor = options.smokeColor or trigger.smokeColor.White,
        active = true,
        groupName = options.groupName,  -- Associated late-activation group
        realTargetId = options.realTargetId, -- ID of real target this protects
        lastSmokeTime = 0,
    }

    -- Activate associated group if exists
    if options.groupName then
        local group = Group.getByName(options.groupName)
        if group then
            trigger.action.activateGroup(group)
        end
    end

    return DMS.Decoys.Sites[id]
end

--- Register decoy from zone
-- @param id string Decoy identifier
-- @param zoneName string Zone name
-- @param options table Decoy options
function DMS.Decoys.registerFromZone(id, zoneName, options)
    local zone = trigger.misc.getZone(zoneName)
    if zone then
        local position = {x = zone.point.x, y = 0, z = zone.point.z}
        return DMS.Decoys.register(id, position, options)
    end
    return nil
end

--- Calculate distance between positions
-- @param pos1 table Vec3
-- @param pos2 table Vec3
-- @return number Distance
local function getDistance(pos1, pos2)
    local dx = pos2.x - pos1.x
    local dz = pos2.z - pos1.z
    return math.sqrt(dx * dx + dz * dz)
end

--- Reveal a decoy
-- @param id string Decoy ID
-- @param reason string|nil Reason for reveal
function DMS.Decoys.reveal(id, reason)
    local decoy = DMS.Decoys.Sites[id]
    if not decoy or decoy.revealed then
        return
    end

    decoy.revealed = true

    if DMS.Decoys.Config.revealMessage then
        local msg = string.format("INTEL UPDATE: Target at grid X:%.0f Z:%.0f identified as DECOY (%s)",
            decoy.position.x / 1000,
            decoy.position.z / 1000,
            decoy.type)

        if reason then
            msg = msg .. "\n" .. reason
        end

        trigger.action.outTextForCoalition(
            DMS.Decoys.Config.playerCoalition,
            msg,
            DMS.Decoys.Config.displayDuration,
            true
        )
    end
end

--- Mark a decoy as attacked
-- @param id string Decoy ID
function DMS.Decoys.markAttacked(id)
    local decoy = DMS.Decoys.Sites[id]
    if not decoy then return end

    decoy.attacked = true

    if DMS.Decoys.Config.revealOnAttack and not decoy.revealed then
        DMS.Decoys.reveal(id, "Decoy detected - attack ineffective!")
    end
end

--- Event handler for attack detection (internal)
DMS.Decoys._EventHandlerInternal = {
    onEvent = function(self, event)
        if not DMS.Decoys.Active then
            return
        end

        -- Check for weapons hitting near decoys
        if event.id == world.event.S_EVENT_HIT or
           event.id == world.event.S_EVENT_DEAD then

            local position = nil

            if event.target then
                position = event.target:getPoint()
            end

            if position then
                -- Check if hit is near any decoy
                for id, decoy in pairs(DMS.Decoys.Sites) do
                    if decoy.active and not decoy.attacked then
                        local distance = getDistance(position, decoy.position)
                        if distance < DMS.Decoys.Config.detectionRadius then
                            DMS.Decoys.markAttacked(id)
                        end
                    end
                end
            end
        end
    end
}

--- Refresh smoke at decoy sites
local function refreshSmoke()
    local currentTime = timer.getTime()

    for _, decoy in pairs(DMS.Decoys.Sites) do
        if decoy.active and decoy.type == DMS.Decoys.Types.SMOKE then
            if currentTime - decoy.lastSmokeTime >= DMS.Decoys.Config.smokeInterval then
                trigger.action.smoke(decoy.position, decoy.smokeColor)
                decoy.lastSmokeTime = currentTime
            end
        end
    end
end

--- Process decoy system (internal)
local function processDecoysInternal(_, time)
    if not DMS.Decoys.Active then
        return nil
    end

    -- Refresh smoke decoys
    refreshSmoke()

    return time + 30  -- Check every 30 seconds
end

--- Process decoys with error handling
local function processDecoys(args, time)
    local success, result = pcall(processDecoysInternal, args, time)
    if not success then
        if DMS.Error then
            DMS.Error.log("Decoys.processDecoys", result)
        else
            env.error("[DMS LUA ERROR] Decoys.processDecoys: " .. tostring(result))
        end
        return time + 30
    end
    return result
end

--- Start decoy system
function DMS.Decoys.start()
    if DMS.Decoys.Active then
        return
    end

    DMS.Decoys.Active = true

    -- Wrap event handler with error protection
    DMS.Decoys.EventHandler = DMS.Error.safeHandler(
        DMS.Decoys._EventHandlerInternal,
        "Decoys.EventHandler"
    )
    world.addEventHandler(DMS.Decoys.EventHandler)

    -- Start processing
    DMS.Decoys.TimerId = timer.scheduleFunction(
        processDecoys,
        nil,
        timer.getTime() + 10
    )

    -- Initial smoke for smoke decoys
    refreshSmoke()
end

--- Stop decoy system
function DMS.Decoys.stop()
    DMS.Decoys.Active = false
    if DMS.Decoys.TimerId then
        timer.removeFunction(DMS.Decoys.TimerId)
        DMS.Decoys.TimerId = nil
    end
end

--- Deactivate a decoy
-- @param id string Decoy ID
function DMS.Decoys.deactivate(id)
    local decoy = DMS.Decoys.Sites[id]
    if decoy then
        decoy.active = false

        -- Destroy associated group
        if decoy.groupName then
            local group = Group.getByName(decoy.groupName)
            if group and group:isExist() then
                group:destroy()
            end
        end
    end
end

--- Get decoy status
-- @return table Decoy status
function DMS.Decoys.getStatus()
    local status = {
        total = 0,
        active = 0,
        revealed = 0,
        attacked = 0,
        sites = {},
    }

    for id, decoy in pairs(DMS.Decoys.Sites) do
        status.total = status.total + 1

        if decoy.active then
            status.active = status.active + 1
        end
        if decoy.revealed then
            status.revealed = status.revealed + 1
        end
        if decoy.attacked then
            status.attacked = status.attacked + 1
        end

        status.sites[id] = {
            type = decoy.type,
            disguisedAs = decoy.disguisedAs,
            active = decoy.active,
            revealed = decoy.revealed,
            attacked = decoy.attacked,
        }
    end

    return status
end

--- Check if decoy protects a real target
-- @param realTargetId string Real target ID
-- @return boolean True if decoy still active
function DMS.Decoys.isProtecting(realTargetId)
    for _, decoy in pairs(DMS.Decoys.Sites) do
        if decoy.realTargetId == realTargetId and decoy.active and not decoy.revealed then
            return true
        end
    end
    return false
end

--- Create a SAM decoy configuration
-- @param id string Decoy ID
-- @param position table Position
-- @param samType string SAM type being mimicked
-- @return table Decoy site
function DMS.Decoys.createSAMDecoy(id, position, samType)
    return DMS.Decoys.register(id, position, {
        type = DMS.Decoys.Types.RADAR,
        disguisedAs = samType .. " SAM Site",
    })
end

--- Create an airfield decoy configuration
-- @param id string Decoy ID
-- @param position table Position
-- @return table Decoy site
function DMS.Decoys.createAirfieldDecoy(id, position)
    return DMS.Decoys.register(id, position, {
        type = DMS.Decoys.Types.LIGHT,
        disguisedAs = "Airfield/Helipad",
    })
end

--- Create an armor decoy configuration
-- @param id string Decoy ID
-- @param position table Position
-- @param groupName string Decoy unit group name
-- @return table Decoy site
function DMS.Decoys.createArmorDecoy(id, position, groupName)
    return DMS.Decoys.register(id, position, {
        type = DMS.Decoys.Types.INFLATABLE,
        disguisedAs = "Armor Formation",
        groupName = groupName,
    })
end

--[[
USAGE EXAMPLE:

-- Configure
DMS.Decoys.configure({
    revealOnAttack = true,
    revealMessage = true,
    detectionRadius = 3000
})

-- Register decoy sites
DMS.Decoys.register("decoy_sam_1", {x = 50000, z = 30000}, {
    type = DMS.Decoys.Types.RADAR,
    disguisedAs = "SA-11 Battery",
    realTargetId = "real_sam_1"  -- Links to real target
})

DMS.Decoys.register("decoy_depot", {x = 60000, z = 40000}, {
    type = DMS.Decoys.Types.SMOKE,
    disguisedAs = "Fuel Depot",
    smokeColor = trigger.smokeColor.Orange,
    groupName = "Decoy-Depot-Group"  -- Late activation group with dummy vehicles
})

-- Use convenience functions
DMS.Decoys.createSAMDecoy("decoy_sam_2", {x = 70000, z = 50000}, "SA-10")
DMS.Decoys.createArmorDecoy("decoy_armor", {x = 80000, z = 60000}, "Decoy-Tanks")

-- Register from zones (zones defined in Mission Editor)
DMS.Decoys.registerFromZone("decoy_airfield", "Decoy-Airfield-Zone", {
    type = DMS.Decoys.Types.LIGHT,
    disguisedAs = "Forward Airfield"
})

-- Start system
DMS.Decoys.start()

-- Manual reveal (for intel missions)
-- DMS.Decoys.reveal("decoy_sam_1", "SIGINT analysis confirms radar emissions are simulated")

-- Check if real target is still protected
if DMS.Decoys.isProtecting("real_sam_1") then
    -- Real SAM still has active decoy protection
end
]]

-- Export
_G.DMS = DMS
