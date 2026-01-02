-- Rescue Coordination System for DCS Missions
-- Track ejected pilots and coordinate CSAR
-- Requires: utils/messaging.lua, utils/coordinates.lua
-- Place in mission via DO SCRIPT FILE

DMS = DMS or {}
DMS.Rescue = {}

-- Downed pilots
DMS.Rescue.DownedPilots = {}
DMS.Rescue.EventHandler = nil
DMS.Rescue.Active = false
DMS.Rescue.TimerId = nil
DMS.Rescue.PilotIdCounter = 0

-- Configuration
DMS.Rescue.Config = {
    playerCoalition = coalition.side.BLUE,
    trackAIPilots = false,       -- Track AI pilot ejections too
    pilotSurvivalTime = 1800,    -- Seconds pilot survives (30 min)
    rescueRadius = 500,          -- Meters for successful rescue
    checkInterval = 10,
    announceEjections = true,
    announceRescues = true,
    smokeOnEjection = true,
    smokeColor = trigger.smokeColor.Orange,
    useFlares = true,
    flareInterval = 300,         -- Seconds between flares
}

--- Configure rescue system
-- @param settings table Configuration overrides
function DMS.Rescue.configure(settings)
    for key, value in pairs(settings) do
        DMS.Rescue.Config[key] = value
    end
end

--- Generate grid reference from position
-- @param pos table Vec3 position
-- @return string Grid reference
local function getGridReference(pos)
    -- Simple grid reference (in real use, would use MGRS)
    return string.format("X:%.0f Z:%.0f", pos.x / 1000, pos.z / 1000)
end

--- Calculate distance between positions
-- @param pos1 table Vec3
-- @param pos2 table Vec3
-- @return number Distance in meters
local function getDistance(pos1, pos2)
    local dx = pos2.x - pos1.x
    local dz = pos2.z - pos1.z
    return math.sqrt(dx * dx + dz * dz)
end

--- Register a downed pilot
-- @param position table Vec3 position
-- @param pilotName string Pilot name
-- @param isPlayer boolean Is player pilot
local function registerDownedPilot(position, pilotName, isPlayer)
    DMS.Rescue.PilotIdCounter = DMS.Rescue.PilotIdCounter + 1

    local pilotId = "PILOT-" .. DMS.Rescue.PilotIdCounter

    DMS.Rescue.DownedPilots[pilotId] = {
        id = pilotId,
        name = pilotName or "Unknown",
        isPlayer = isPlayer,
        position = {x = position.x, y = position.y, z = position.z},
        ejectionTime = timer.getTime(),
        expirationTime = timer.getTime() + DMS.Rescue.Config.pilotSurvivalTime,
        rescued = false,
        lastFlareTime = 0,
        status = "awaiting_rescue",
    }

    -- Add smoke marker
    if DMS.Rescue.Config.smokeOnEjection then
        trigger.action.smoke(position, DMS.Rescue.Config.smokeColor)
    end

    -- Announce ejection
    if DMS.Rescue.Config.announceEjections then
        local grid = getGridReference(position)
        local msg = string.format(
            "MAYDAY MAYDAY MAYDAY!\n%s has ejected!\nLast position: %s\nInitiate CSAR operations.",
            pilotName or "Pilot",
            grid
        )

        trigger.action.outTextForCoalition(
            DMS.Rescue.Config.playerCoalition,
            msg,
            20,
            true
        )
    end

    return pilotId
end

--- Event handler (internal)
DMS.Rescue._EventHandlerInternal = {
    onEvent = function(self, event)
        if not DMS.Rescue.Active then
            return
        end

        -- Track ejections
        if event.id == world.event.S_EVENT_EJECTION then
            local unit = event.initiator

            if unit then
                local isPlayer = false
                local pilotName = "Unknown Pilot"

                if unit.getPlayerName then
                    local pName = unit:getPlayerName()
                    if pName then
                        isPlayer = true
                        pilotName = pName
                    end
                end

                -- Only track if player or config allows AI
                if isPlayer or DMS.Rescue.Config.trackAIPilots then
                    local position = unit:getPoint()
                    registerDownedPilot(position, pilotName, isPlayer)
                end
            end
        end
    end
}

--- Check for rescue opportunities (internal)
local function checkRescuesInternal(_, time)
    if not DMS.Rescue.Active then
        return nil
    end

    local rescuers = coalition.getPlayers(DMS.Rescue.Config.playerCoalition)

    for pilotId, pilot in pairs(DMS.Rescue.DownedPilots) do
        if pilot.status == "awaiting_rescue" then
            -- Check expiration
            if time >= pilot.expirationTime then
                pilot.status = "expired"

                trigger.action.outTextForCoalition(
                    DMS.Rescue.Config.playerCoalition,
                    string.format("CSAR UPDATE: %s is no longer responding. Rescue operation cancelled.",
                        pilot.name),
                    15,
                    true
                )
            else
                -- Fire periodic flares
                if DMS.Rescue.Config.useFlares and
                   time - pilot.lastFlareTime >= DMS.Rescue.Config.flareInterval then
                    pilot.lastFlareTime = time
                    trigger.action.signalFlare(pilot.position, trigger.flareColor.Green, 0)
                end

                -- Check for rescue by helicopters or slow aircraft
                if rescuers then
                    for _, rescuer in ipairs(rescuers) do
                        if rescuer:isExist() then
                            local rescuerPos = rescuer:getPoint()
                            local distance = getDistance(rescuerPos, pilot.position)
                            local altitude = rescuerPos.y - pilot.position.y

                            -- Must be close and low
                            if distance < DMS.Rescue.Config.rescueRadius and altitude < 50 then
                                -- Check if slow enough (hovering or landing)
                                local velocity = rescuer:getVelocity()
                                local speed = math.sqrt(velocity.x^2 + velocity.z^2)

                                if speed < 30 then  -- Less than ~60 knots
                                    -- Successful rescue!
                                    pilot.status = "rescued"
                                    pilot.rescuedBy = rescuer:getPlayerName() or "Unknown"
                                    pilot.rescueTime = time

                                    if DMS.Rescue.Config.announceRescues then
                                        local msg = string.format(
                                            "CSAR SUCCESS!\n%s has been rescued by %s!\nRTB with survivor.",
                                            pilot.name,
                                            pilot.rescuedBy
                                        )

                                        trigger.action.outTextForCoalition(
                                            DMS.Rescue.Config.playerCoalition,
                                            msg,
                                            15,
                                            true
                                        )
                                    end

                                    -- Could set flag or trigger reward here
                                    trigger.action.setUserFlag("pilot_rescued_" .. pilotId, 1)
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    return time + DMS.Rescue.Config.checkInterval
end

--- Check for rescue opportunities with error handling
local function checkRescues(args, time)
    local success, result = pcall(checkRescuesInternal, args, time)
    if not success then
        if DMS.Error then
            DMS.Error.log("Rescue.checkRescues", result)
        else
            env.error("[DMS LUA ERROR] Rescue.checkRescues: " .. tostring(result))
        end
        return time + (DMS.Rescue.Config.checkInterval or 10)
    end
    return result
end

--- Start rescue coordination
function DMS.Rescue.start()
    if DMS.Rescue.Active then
        return
    end

    DMS.Rescue.Active = true

    -- Wrap event handler with error protection
    DMS.Rescue.EventHandler = DMS.Error.safeHandler(
        DMS.Rescue._EventHandlerInternal,
        "Rescue.EventHandler"
    )
    world.addEventHandler(DMS.Rescue.EventHandler)

    DMS.Rescue.TimerId = timer.scheduleFunction(
        checkRescues,
        nil,
        timer.getTime() + DMS.Rescue.Config.checkInterval
    )
end

--- Stop rescue coordination
function DMS.Rescue.stop()
    DMS.Rescue.Active = false
    if DMS.Rescue.TimerId then
        timer.removeFunction(DMS.Rescue.TimerId)
        DMS.Rescue.TimerId = nil
    end
end

--- Get list of active downed pilots
-- @return table Array of downed pilots awaiting rescue
function DMS.Rescue.getActivePilots()
    local active = {}
    for _, pilot in pairs(DMS.Rescue.DownedPilots) do
        if pilot.status == "awaiting_rescue" then
            table.insert(active, pilot)
        end
    end
    return active
end

--- Display CSAR status
function DMS.Rescue.showStatus()
    local active = DMS.Rescue.getActivePilots()
    local lines = {"=== CSAR STATUS ===", ""}

    if #active > 0 then
        for _, pilot in ipairs(active) do
            local timeRemaining = pilot.expirationTime - timer.getTime()
            local mins = math.floor(timeRemaining / 60)
            local grid = getGridReference(pilot.position)

            table.insert(lines, string.format("%s - Grid: %s", pilot.name, grid))
            table.insert(lines, string.format("  Time remaining: %d minutes", mins))
        end
    else
        table.insert(lines, "No active CSAR operations.")
    end

    -- Show rescued count
    local rescuedCount = 0
    for _, pilot in pairs(DMS.Rescue.DownedPilots) do
        if pilot.status == "rescued" then
            rescuedCount = rescuedCount + 1
        end
    end

    if rescuedCount > 0 then
        table.insert(lines, "")
        table.insert(lines, string.format("Pilots rescued this mission: %d", rescuedCount))
    end

    trigger.action.outTextForCoalition(
        DMS.Rescue.Config.playerCoalition,
        table.concat(lines, "\n"),
        20,
        true
    )
end

--- Mark smoke at pilot location (refresh)
-- @param pilotId string Pilot ID
function DMS.Rescue.markPilot(pilotId)
    local pilot = DMS.Rescue.DownedPilots[pilotId]
    if pilot and pilot.status == "awaiting_rescue" then
        trigger.action.smoke(pilot.position, DMS.Rescue.Config.smokeColor)

        trigger.action.outTextForCoalition(
            DMS.Rescue.Config.playerCoalition,
            string.format("Smoke marker refreshed for %s", pilot.name),
            5,
            true
        )
    end
end

--- Get rescue statistics
-- @return table Rescue stats
function DMS.Rescue.getStats()
    local stats = {
        total = 0,
        awaiting = 0,
        rescued = 0,
        expired = 0,
    }

    for _, pilot in pairs(DMS.Rescue.DownedPilots) do
        stats.total = stats.total + 1
        if pilot.status == "awaiting_rescue" then
            stats.awaiting = stats.awaiting + 1
        elseif pilot.status == "rescued" then
            stats.rescued = stats.rescued + 1
        elseif pilot.status == "expired" then
            stats.expired = stats.expired + 1
        end
    end

    return stats
end

--[[
USAGE EXAMPLE:

-- Configure
DMS.Rescue.configure({
    trackAIPilots = false,       -- Only player pilots
    pilotSurvivalTime = 2400,    -- 40 minutes
    rescueRadius = 300,          -- 300m pickup radius
    smokeOnEjection = true,
    useFlares = true,
    flareInterval = 180          -- Flare every 3 minutes
})

-- Start system
DMS.Rescue.start()

-- Add F10 menu commands
local csarMenu = missionCommands.addSubMenuForCoalition(coalition.side.BLUE, "CSAR")

missionCommands.addCommandForCoalition(coalition.side.BLUE, "CSAR Status", csarMenu,
    function() DMS.Rescue.showStatus() end)

missionCommands.addCommandForCoalition(coalition.side.BLUE, "Mark Nearest Survivor", csarMenu,
    function()
        local active = DMS.Rescue.getActivePilots()
        if #active > 0 then
            DMS.Rescue.markPilot(active[1].id)
        end
    end)

-- For helicopter CSAR missions, the rescue happens automatically
-- when the helicopter hovers low and slow near the survivor
]]

-- Export
_G.DMS = DMS
