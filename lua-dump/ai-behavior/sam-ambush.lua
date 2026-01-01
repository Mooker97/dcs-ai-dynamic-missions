-- SAM Ambush System for DCS Missions
-- SAMs stay radar-dark until player enters engagement envelope
-- Requires: utils/coordinates.lua, utils/group-utils.lua
-- Place in mission via DO SCRIPT FILE

DMS = DMS or {}
DMS.SAMAmbush = {}

-- Tracked SAM sites
DMS.SAMAmbush.Sites = {}
DMS.SAMAmbush.TimerId = nil
DMS.SAMAmbush.Active = false

-- Configuration
DMS.SAMAmbush.Config = {
    checkInterval = 2,           -- Fast checks for responsiveness
    defaultEngageRadius = 30000, -- 30km default engagement envelope
    defaultMinAltitude = 100,    -- Minimum altitude to engage (meters)
    defaultMaxAltitude = 25000,  -- Maximum altitude (meters)
    holdFireTime = 10,           -- Seconds to wait before firing after activation
    announceThreats = false,     -- "Mud spike!" warnings
    trackingCoalition = coalition.side.BLUE,
}

--- Configure the SAM ambush system
-- @param settings table Configuration overrides
function DMS.SAMAmbush.configure(settings)
    for key, value in pairs(settings) do
        DMS.SAMAmbush.Config[key] = value
    end
end

--- Register a SAM site for ambush behavior
-- @param groupName string SAM group name
-- @param centerX number SAM position X
-- @param centerZ number SAM position Z
-- @param engageRadius number|nil Engagement radius in meters
-- @param minAlt number|nil Minimum engagement altitude
-- @param maxAlt number|nil Maximum engagement altitude
function DMS.SAMAmbush.register(groupName, centerX, centerZ, engageRadius, minAlt, maxAlt)
    DMS.SAMAmbush.Sites[groupName] = {
        name = groupName,
        x = centerX,
        z = centerZ,
        engageRadius = engageRadius or DMS.SAMAmbush.Config.defaultEngageRadius,
        minAlt = minAlt or DMS.SAMAmbush.Config.defaultMinAltitude,
        maxAlt = maxAlt or DMS.SAMAmbush.Config.defaultMaxAltitude,
        radarOn = false,
        activateTime = 0,
        trackingTarget = nil,
    }

    -- Ensure SAM starts with radar off
    DMS.SAMAmbush.setRadar(groupName, false)
end

--- Register SAM at its current position
-- @param groupName string SAM group name
-- @param engageRadius number|nil Engagement radius
function DMS.SAMAmbush.registerAtPosition(groupName, engageRadius)
    local group = Group.getByName(groupName)
    if group then
        local units = group:getUnits()
        if units and #units > 0 then
            local pos = units[1]:getPoint()
            DMS.SAMAmbush.register(groupName, pos.x, pos.z, engageRadius)
        end
    end
end

--- Set radar emission state for a SAM
-- @param groupName string SAM group name
-- @param state boolean True = radar on, False = radar off
function DMS.SAMAmbush.setRadar(groupName, state)
    local group = Group.getByName(groupName)
    if group and group:isExist() then
        local controller = group:getController()
        if controller then
            -- setOption for radar emission
            -- Option 9 = RADAR_USE (0=Never, 1=For Attack, 2=For Search, 3=For Continuous Search)
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

--- Get all player aircraft positions and altitudes
-- @return table Array of {pos, alt, unit} tables
local function getPlayerAircraft()
    local aircraft = {}

    local players = coalition.getPlayers(DMS.SAMAmbush.Config.trackingCoalition)
    if players then
        for _, unit in ipairs(players) do
            if unit and unit:isExist() then
                local pos = unit:getPoint()
                table.insert(aircraft, {
                    pos = pos,
                    alt = pos.y,
                    unit = unit
                })
            end
        end
    end

    return aircraft
end

--- Check if aircraft is in SAM engagement envelope
-- @param site table SAM site data
-- @param aircraft table Aircraft data
-- @return boolean True if in envelope
local function isInEnvelope(site, aircraft)
    -- Check altitude
    if aircraft.alt < site.minAlt or aircraft.alt > site.maxAlt then
        return false
    end

    -- Check range
    local dx = aircraft.pos.x - site.x
    local dz = aircraft.pos.z - site.z
    local range = math.sqrt(dx * dx + dz * dz)

    return range <= site.engageRadius
end

--- Process SAM ambush checks
local function processAmbushCheck(_, time)
    if not DMS.SAMAmbush.Active then
        return nil
    end

    local playerAircraft = getPlayerAircraft()

    for groupName, site in pairs(DMS.SAMAmbush.Sites) do
        -- Check if SAM group still exists
        local group = Group.getByName(groupName)
        if not group or not group:isExist() then
            site.radarOn = false
            goto continue
        end

        local targetInEnvelope = false
        local closestTarget = nil
        local closestDist = math.huge

        -- Check each player aircraft
        for _, aircraft in ipairs(playerAircraft) do
            if isInEnvelope(site, aircraft) then
                targetInEnvelope = true

                local dx = aircraft.pos.x - site.x
                local dz = aircraft.pos.z - site.z
                local dist = math.sqrt(dx * dx + dz * dz)

                if dist < closestDist then
                    closestDist = dist
                    closestTarget = aircraft.unit
                end
            end
        end

        if targetInEnvelope and not site.radarOn then
            -- Target entered envelope - activate!
            DMS.SAMAmbush.setRadar(groupName, true)
            site.trackingTarget = closestTarget

            if DMS.Settings and DMS.Settings.isDebug() then
                env.info(string.format("[SAMAmbush] '%s' going HOT (target at %.0fm)",
                    groupName, closestDist))
            end

            if DMS.SAMAmbush.Config.announceThreats then
                trigger.action.outText("WARNING: Mud spike!", 5, true)
            end

        elseif not targetInEnvelope and site.radarOn then
            -- All targets left envelope - go dark again
            -- Add some delay before going dark to simulate realistic behavior
            if time - site.activateTime > 30 then  -- Stay on for at least 30 seconds
                DMS.SAMAmbush.setRadar(groupName, false)
                site.trackingTarget = nil

                if DMS.Settings and DMS.Settings.isDebug() then
                    env.info(string.format("[SAMAmbush] '%s' going DARK (no targets in envelope)",
                        groupName))
                end
            end
        end

        ::continue::
    end

    return time + DMS.SAMAmbush.Config.checkInterval
end

--- Start the SAM ambush system
function DMS.SAMAmbush.start()
    if DMS.SAMAmbush.Active then
        return
    end

    DMS.SAMAmbush.Active = true
    DMS.SAMAmbush.TimerId = timer.scheduleFunction(
        processAmbushCheck,
        nil,
        timer.getTime() + DMS.SAMAmbush.Config.checkInterval
    )

    if DMS.Settings and DMS.Settings.isDebug() then
        local count = 0
        for _ in pairs(DMS.SAMAmbush.Sites) do count = count + 1 end
        env.info(string.format("[SAMAmbush] Started monitoring %d SAM sites (default radius: %dm)",
            count, DMS.SAMAmbush.Config.defaultEngageRadius))
    end
end

--- Stop the SAM ambush system
function DMS.SAMAmbush.stop()
    DMS.SAMAmbush.Active = false
    if DMS.SAMAmbush.TimerId then
        timer.removeFunction(DMS.SAMAmbush.TimerId)
        DMS.SAMAmbush.TimerId = nil
    end
end

--- Force a SAM to go hot
-- @param groupName string SAM group name
function DMS.SAMAmbush.forceHot(groupName)
    DMS.SAMAmbush.setRadar(groupName, true)
end

--- Force a SAM to go dark
-- @param groupName string SAM group name
function DMS.SAMAmbush.forceDark(groupName)
    DMS.SAMAmbush.setRadar(groupName, false)
end

--- Get SAM site status
-- @param groupName string SAM group name
-- @return table|nil Site status
function DMS.SAMAmbush.getStatus(groupName)
    local site = DMS.SAMAmbush.Sites[groupName]
    if site then
        return {
            name = site.name,
            radarOn = site.radarOn,
            tracking = site.trackingTarget ~= nil,
            engageRadius = site.engageRadius
        }
    end
    return nil
end

--- Get all SAM statuses
-- @return table Status summary
function DMS.SAMAmbush.getAllStatus()
    local hot, dark = 0, 0
    for _, site in pairs(DMS.SAMAmbush.Sites) do
        if site.radarOn then
            hot = hot + 1
        else
            dark = dark + 1
        end
    end
    return {hot = hot, dark = dark, total = hot + dark}
end

--[[
USAGE EXAMPLE:

-- Configure
DMS.SAMAmbush.configure({
    checkInterval = 2,
    defaultEngageRadius = 25000,  -- 25km
    announceThreats = true
})

-- Register SAM sites
DMS.SAMAmbush.register("SA-6-1", -50000, 40000, 20000)  -- Custom radius
DMS.SAMAmbush.register("SA-11-1", -55000, 45000, 35000, 500, 20000)  -- With altitude limits

-- Or register at current ME position
DMS.SAMAmbush.registerAtPosition("SA-10-1", 40000)

-- Start monitoring
DMS.SAMAmbush.start()

-- Manual control
DMS.SAMAmbush.forceHot("SA-6-1")   -- Force radar on
DMS.SAMAmbush.forceDark("SA-6-1")  -- Force radar off

-- Check status
local status = DMS.SAMAmbush.getAllStatus()
trigger.action.outText("SAMs: " .. status.hot .. " hot, " .. status.dark .. " dark", 10)
]]

-- Export
_G.DMS = DMS
