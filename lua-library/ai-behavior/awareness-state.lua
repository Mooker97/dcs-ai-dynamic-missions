-- Enemy Awareness State System for DCS Missions
-- Realistic detection → alert → hunt state machine
-- Place in mission via DO SCRIPT FILE

DMS = DMS or {}
DMS.Awareness = {}

-- Awareness states
DMS.Awareness.STATES = {
    UNAWARE = "UNAWARE",       -- Normal peacetime behavior
    SUSPICIOUS = "SUSPICIOUS", -- Heard/saw something, investigating
    ALERT = "ALERT",          -- Confirmed contact, combat ready
    HUNTING = "HUNTING",      -- Lost contact, actively searching
    ENGAGED = "ENGAGED",      -- In active combat
}

-- Tracked groups and their awareness
DMS.Awareness.Groups = {}
DMS.Awareness.Active = false
DMS.Awareness.TimerId = nil

-- Configuration
DMS.Awareness.Config = {
    checkInterval = 3,
    spreadRadius = 5000,           -- Alert spreads to groups within this range
    suspiciousDecayTime = 60,      -- Seconds to return to UNAWARE from SUSPICIOUS
    alertDecayTime = 180,          -- Seconds to return to SUSPICIOUS from ALERT
    huntingDuration = 120,         -- Seconds to hunt before giving up
    detectionRange = 3000,         -- Range at which groups detect players
    playerCoalition = coalition.side.BLUE,
    enemyCoalition = coalition.side.RED,
    announceStateChanges = false,  -- Debug output
}

--- Configure awareness system
-- @param settings table Configuration overrides
function DMS.Awareness.configure(settings)
    for key, value in pairs(settings) do
        DMS.Awareness.Config[key] = value
    end
end

--- Register a group for awareness tracking
-- @param groupName string Group name
-- @param options table|nil Initial options
function DMS.Awareness.register(groupName, options)
    options = options or {}

    DMS.Awareness.Groups[groupName] = {
        name = groupName,
        state = options.initialState or DMS.Awareness.STATES.UNAWARE,
        lastStateChange = timer.getTime(),
        lastContactPos = nil,
        lastContactTime = 0,
        searchPattern = nil,
        detectionRange = options.detectionRange or DMS.Awareness.Config.detectionRange,
    }

    -- Set initial AI state
    DMS.Awareness.applyState(groupName)
end

--- Register multiple groups
-- @param groupNames table Array of group names
-- @param options table|nil Options for all
function DMS.Awareness.registerBatch(groupNames, options)
    for _, name in ipairs(groupNames) do
        DMS.Awareness.register(name, options)
    end
end

--- Apply AI settings based on awareness state
-- @param groupName string Group name
function DMS.Awareness.applyState(groupName)
    local awareness = DMS.Awareness.Groups[groupName]
    if not awareness then return end

    local group = Group.getByName(groupName)
    if not group or not group:isExist() then return end

    local controller = group:getController()
    if not controller then return end

    local state = awareness.state

    if state == DMS.Awareness.STATES.UNAWARE then
        controller:setOption(AI.Option.Ground.id.ALARM_STATE, AI.Option.Ground.val.ALARM_STATE.GREEN)
        controller:setOption(AI.Option.Ground.id.ROE, AI.Option.Ground.val.ROE.WEAPON_HOLD)

    elseif state == DMS.Awareness.STATES.SUSPICIOUS then
        controller:setOption(AI.Option.Ground.id.ALARM_STATE, AI.Option.Ground.val.ALARM_STATE.YELLOW)
        controller:setOption(AI.Option.Ground.id.ROE, AI.Option.Ground.val.ROE.RETURN_FIRE)

    elseif state == DMS.Awareness.STATES.ALERT then
        controller:setOption(AI.Option.Ground.id.ALARM_STATE, AI.Option.Ground.val.ALARM_STATE.RED)
        controller:setOption(AI.Option.Ground.id.ROE, AI.Option.Ground.val.ROE.WEAPON_FREE)

    elseif state == DMS.Awareness.STATES.HUNTING then
        controller:setOption(AI.Option.Ground.id.ALARM_STATE, AI.Option.Ground.val.ALARM_STATE.RED)
        controller:setOption(AI.Option.Ground.id.ROE, AI.Option.Ground.val.ROE.WEAPON_FREE)
        -- Search pattern handled separately

    elseif state == DMS.Awareness.STATES.ENGAGED then
        controller:setOption(AI.Option.Ground.id.ALARM_STATE, AI.Option.Ground.val.ALARM_STATE.RED)
        controller:setOption(AI.Option.Ground.id.ROE, AI.Option.Ground.val.ROE.WEAPON_FREE)
    end
end

--- Set group awareness state
-- @param groupName string Group name
-- @param newState string New state
-- @param contactPos table|nil Contact position
function DMS.Awareness.setState(groupName, newState, contactPos)
    local awareness = DMS.Awareness.Groups[groupName]
    if not awareness then return end

    local oldState = awareness.state

    -- Only change if different
    if oldState == newState then return end

    awareness.state = newState
    awareness.lastStateChange = timer.getTime()

    if contactPos then
        awareness.lastContactPos = contactPos
        awareness.lastContactTime = timer.getTime()
    end

    -- Apply AI settings
    DMS.Awareness.applyState(groupName)

    -- Start search pattern if hunting
    if newState == DMS.Awareness.STATES.HUNTING and contactPos then
        if DMS.SearchPattern then
            DMS.SearchPattern.start(groupName, contactPos)
        end
    end

    if DMS.Awareness.Config.announceStateChanges then
        trigger.action.outText(string.format(
            "[Awareness] %s: %s → %s",
            groupName, oldState, newState
        ), 5)
    end
end

--- Spread alert to nearby groups
-- @param sourcePos table Source position
-- @param newState string State to spread
-- @param contactPos table|nil Contact position
function DMS.Awareness.spreadAlert(sourcePos, newState, contactPos)
    for groupName, awareness in pairs(DMS.Awareness.Groups) do
        local group = Group.getByName(groupName)
        if group and group:isExist() then
            local units = group:getUnits()
            if units and #units > 0 then
                local groupPos = units[1]:getPoint()
                local dx = groupPos.x - sourcePos.x
                local dz = groupPos.z - sourcePos.z
                local dist = math.sqrt(dx * dx + dz * dz)

                if dist <= DMS.Awareness.Config.spreadRadius then
                    -- Spread alert (don't downgrade)
                    local stateOrder = {
                        [DMS.Awareness.STATES.UNAWARE] = 1,
                        [DMS.Awareness.STATES.SUSPICIOUS] = 2,
                        [DMS.Awareness.STATES.ALERT] = 3,
                        [DMS.Awareness.STATES.HUNTING] = 3,
                        [DMS.Awareness.STATES.ENGAGED] = 4,
                    }

                    local currentOrder = stateOrder[awareness.state] or 1
                    local newOrder = stateOrder[newState] or 1

                    if newOrder > currentOrder then
                        -- Nearby groups get one level lower alert
                        local spreadState = newState
                        if newState == DMS.Awareness.STATES.ENGAGED then
                            spreadState = DMS.Awareness.STATES.ALERT
                        elseif newState == DMS.Awareness.STATES.ALERT then
                            spreadState = DMS.Awareness.STATES.SUSPICIOUS
                        end

                        DMS.Awareness.setState(groupName, spreadState, contactPos)
                    end
                end
            end
        end
    end
end

--- Get player positions
-- @return table Array of player positions
local function getPlayerPositions()
    local positions = {}
    local players = coalition.getPlayers(DMS.Awareness.Config.playerCoalition)
    if players then
        for _, unit in ipairs(players) do
            if unit and unit:isExist() then
                table.insert(positions, unit:getPoint())
            end
        end
    end
    return positions
end

--- Process awareness state decay and detection
local function processAwareness(_, time)
    if not DMS.Awareness.Active then return nil end

    local currentTime = timer.getTime()
    local playerPositions = getPlayerPositions()

    for groupName, awareness in pairs(DMS.Awareness.Groups) do
        local group = Group.getByName(groupName)
        if not group or not group:isExist() then
            goto continue
        end

        local units = group:getUnits()
        if not units or #units == 0 then
            goto continue
        end

        local groupPos = units[1]:getPoint()
        local timeSinceChange = currentTime - awareness.lastStateChange

        -- Check for player detection
        local playerDetected = false
        local detectedPos = nil

        for _, playerPos in ipairs(playerPositions) do
            local dx = playerPos.x - groupPos.x
            local dz = playerPos.z - groupPos.z
            local dist = math.sqrt(dx * dx + dz * dz)

            if dist <= awareness.detectionRange then
                playerDetected = true
                detectedPos = playerPos
                break
            end
        end

        if playerDetected then
            -- Player detected - escalate
            if awareness.state == DMS.Awareness.STATES.UNAWARE then
                DMS.Awareness.setState(groupName, DMS.Awareness.STATES.SUSPICIOUS, detectedPos)
            elseif awareness.state == DMS.Awareness.STATES.SUSPICIOUS then
                DMS.Awareness.setState(groupName, DMS.Awareness.STATES.ALERT, detectedPos)
            elseif awareness.state == DMS.Awareness.STATES.HUNTING then
                DMS.Awareness.setState(groupName, DMS.Awareness.STATES.ALERT, detectedPos)
            end
            -- Spread alert
            DMS.Awareness.spreadAlert(groupPos, DMS.Awareness.STATES.SUSPICIOUS, detectedPos)
        else
            -- No player - decay states
            if awareness.state == DMS.Awareness.STATES.SUSPICIOUS then
                if timeSinceChange > DMS.Awareness.Config.suspiciousDecayTime then
                    DMS.Awareness.setState(groupName, DMS.Awareness.STATES.UNAWARE)
                end

            elseif awareness.state == DMS.Awareness.STATES.ALERT then
                if timeSinceChange > DMS.Awareness.Config.alertDecayTime then
                    if awareness.lastContactPos then
                        DMS.Awareness.setState(groupName, DMS.Awareness.STATES.HUNTING, awareness.lastContactPos)
                    else
                        DMS.Awareness.setState(groupName, DMS.Awareness.STATES.SUSPICIOUS)
                    end
                end

            elseif awareness.state == DMS.Awareness.STATES.HUNTING then
                if timeSinceChange > DMS.Awareness.Config.huntingDuration then
                    DMS.Awareness.setState(groupName, DMS.Awareness.STATES.SUSPICIOUS)
                end

            elseif awareness.state == DMS.Awareness.STATES.ENGAGED then
                -- Engaged decays to hunting if no contact
                if timeSinceChange > 30 then
                    if awareness.lastContactPos then
                        DMS.Awareness.setState(groupName, DMS.Awareness.STATES.HUNTING, awareness.lastContactPos)
                    else
                        DMS.Awareness.setState(groupName, DMS.Awareness.STATES.ALERT)
                    end
                end
            end
        end

        ::continue::
    end

    return time + DMS.Awareness.Config.checkInterval
end

--- Event handler for combat detection
DMS.Awareness.EventHandler = {
    onEvent = function(self, event)
        if not DMS.Awareness.Active then return end

        -- Combat events trigger immediate ENGAGED state
        if event.id == world.event.S_EVENT_SHOT or
           event.id == world.event.S_EVENT_HIT then

            local initiator = event.initiator
            if not initiator then return end

            local group = initiator:getGroup()
            if not group then return end

            local groupName = group:getName()
            local awareness = DMS.Awareness.Groups[groupName]

            if awareness then
                local targetPos = nil
                if event.target then
                    targetPos = event.target:getPoint()
                end

                DMS.Awareness.setState(groupName, DMS.Awareness.STATES.ENGAGED, targetPos)

                -- Spread alert from this position
                local sourcePos = initiator:getPoint()
                DMS.Awareness.spreadAlert(sourcePos, DMS.Awareness.STATES.ALERT, targetPos)
            end
        end
    end
}

--- Start awareness system
function DMS.Awareness.start()
    if DMS.Awareness.Active then return end

    DMS.Awareness.Active = true
    world.addEventHandler(DMS.Awareness.EventHandler)

    DMS.Awareness.TimerId = timer.scheduleFunction(
        processAwareness,
        nil,
        timer.getTime() + DMS.Awareness.Config.checkInterval
    )
end

--- Stop awareness system
function DMS.Awareness.stop()
    DMS.Awareness.Active = false
    if DMS.Awareness.TimerId then
        timer.removeFunction(DMS.Awareness.TimerId)
        DMS.Awareness.TimerId = nil
    end
end

--- Get group awareness status
-- @param groupName string Group name
-- @return table|nil Awareness info
function DMS.Awareness.getStatus(groupName)
    local awareness = DMS.Awareness.Groups[groupName]
    if awareness then
        return {
            state = awareness.state,
            timeSinceChange = timer.getTime() - awareness.lastStateChange,
            lastContactPos = awareness.lastContactPos,
        }
    end
    return nil
end

--- Get all groups in a specific state
-- @param state string State to filter by
-- @return table Array of group names
function DMS.Awareness.getGroupsInState(state)
    local groups = {}
    for groupName, awareness in pairs(DMS.Awareness.Groups) do
        if awareness.state == state then
            table.insert(groups, groupName)
        end
    end
    return groups
end

--- Force all groups to a state
-- @param state string State to set
function DMS.Awareness.setAllState(state)
    for groupName, _ in pairs(DMS.Awareness.Groups) do
        DMS.Awareness.setState(groupName, state)
    end
end

--[[
USAGE EXAMPLE:

-- Configure
DMS.Awareness.configure({
    spreadRadius = 8000,
    detectionRange = 4000,
    announceStateChanges = true,
})

-- Register groups
DMS.Awareness.register("Patrol-1", {detectionRange = 5000})
DMS.Awareness.register("Guard-Post", {
    initialState = DMS.Awareness.STATES.ALERT,  -- Already alert
    detectionRange = 3000,
})

DMS.Awareness.registerBatch({
    "Infantry-1", "Infantry-2", "Infantry-3"
})

-- Start system
DMS.Awareness.start()

-- Flow example:
-- 1. Player approaches at 5km → Patrol-1 goes SUSPICIOUS
-- 2. Player gets closer at 3km → Patrol-1 goes ALERT
-- 3. Alert spreads to nearby groups (they go SUSPICIOUS)
-- 4. Patrol-1 engages → goes ENGAGED, nearby groups go ALERT
-- 5. Player leaves area → groups decay to HUNTING
-- 6. After 2 minutes of hunting → decay to SUSPICIOUS
-- 7. After 1 minute suspicious → return to UNAWARE

-- Manual control
DMS.Awareness.setState("Patrol-1", DMS.Awareness.STATES.ALERT)
DMS.Awareness.setAllState(DMS.Awareness.STATES.ALERT)  -- Full alarm

-- Check status
local status = DMS.Awareness.getStatus("Patrol-1")
local alertGroups = DMS.Awareness.getGroupsInState(DMS.Awareness.STATES.ALERT)
]]

-- Export
_G.DMS = DMS
