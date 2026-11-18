-- Mission Phase Manager for DCS Missions
-- Mission phase state machine with automatic transitions
-- Place in mission via DO SCRIPT FILE

DMS = DMS or {}
DMS.PhaseManager = DMS.PhaseManager or {}

-- Phase definitions (preserved if the script is loaded twice)
DMS.PhaseManager.Phases = DMS.PhaseManager.Phases or {}
DMS.PhaseManager.Transitions = DMS.PhaseManager.Transitions or {}
-- DMS.PhaseManager.CurrentPhase: current phase id (nil until started)
DMS.PhaseManager.PhaseStartTime = DMS.PhaseManager.PhaseStartTime or 0
DMS.PhaseManager.Active = DMS.PhaseManager.Active or false

-- Callbacks
DMS.PhaseManager.OnEnterCallbacks = DMS.PhaseManager.OnEnterCallbacks or {}
DMS.PhaseManager.OnExitCallbacks = DMS.PhaseManager.OnExitCallbacks or {}

-- Configuration
DMS.PhaseManager.Config = DMS.PhaseManager.Config or {
    checkInterval = 5,
    playerCoalition = coalition.side.BLUE,
    announcePhaseChanges = true,
    briefingDuration = 15,
}

--- Configure phase manager
-- @param settings table Configuration overrides
local function isDebug()
    return DMS.Settings and DMS.Settings.isDebug and DMS.Settings.isDebug()
end

local function debugLog(fmt, ...)
    if isDebug() then
        env.info(string.format("[PhaseManager] " .. fmt, ...))
    end
end

local function logError(context, msg)
    if DMS.Error and DMS.Error.log then
        DMS.Error.log(context, msg)
    else
        env.error("[DMS LUA ERROR] " .. tostring(context) .. ": " .. tostring(msg))
    end
end

--- Run a user callback under pcall; returns its result or nil on error
local function safeInvoke(func, context, ...)
    if type(func) ~= "function" then return nil end
    local ok, result = pcall(func, ...)
    if not ok then
        logError(context, result)
        return nil
    end
    return result
end

--- Call an optional method on an optional module (e.g. DMS.RandomSpawn.start)
local function callOptional(module, method, ...)
    if type(module) == "table" and type(module[method]) == "function" then
        return safeInvoke(module[method], "PhaseManager." .. tostring(method), ...)
    end
    debugLog("Optional call skipped: %s not available", tostring(method))
    return nil
end

function DMS.PhaseManager.configure(settings)
    if type(settings) ~= "table" then return end
    for key, value in pairs(settings) do
        DMS.PhaseManager.Config[key] = value
    end
end

--- Define a mission phase
-- @param phaseId string Unique phase ID
-- @param options table Phase options
function DMS.PhaseManager.definePhase(phaseId, options)
    options = options or {}

    DMS.PhaseManager.Phases[phaseId] = {
        id = phaseId,
        name = options.name or phaseId,
        briefing = options.briefing or "",
        duration = options.duration,  -- Max duration before timeout
        timeoutPhase = options.timeoutPhase,  -- Phase to transition to on timeout
        onEnter = options.onEnter,  -- Function called when entering phase
        onExit = options.onExit,    -- Function called when exiting phase
        onUpdate = options.onUpdate,  -- Function called each check interval
        flags = options.flags or {},  -- Flags to set on enter
        success = options.success,  -- Success condition function
        failure = options.failure,  -- Failure condition function
    }
end

--- Add a transition between phases
-- @param fromPhase string Source phase ID
-- @param toPhase string Target phase ID
-- @param conditions table Transition conditions
function DMS.PhaseManager.addTransition(fromPhase, toPhase, conditions)
    conditions = conditions or {}
    if not DMS.PhaseManager.Transitions[fromPhase] then
        DMS.PhaseManager.Transitions[fromPhase] = {}
    end

    table.insert(DMS.PhaseManager.Transitions[fromPhase], {
        from = fromPhase,
        to = toPhase,
        conditions = conditions,
        priority = conditions.priority or 0,
    })

    -- Sort by priority (higher first)
    table.sort(DMS.PhaseManager.Transitions[fromPhase], function(a, b)
        return a.priority > b.priority
    end)
end

--- Check if unit is in zone
-- @param zone string Zone name
-- @param coalition number Coalition to check
-- @return boolean
local function isCoalitionInZone(zoneName, coalitionSide)
    if not zoneName then return false end
    local zone = trigger.misc.getZone(zoneName)
    if not zone or not zone.point then return false end

    local players = coalition.getPlayers(coalitionSide)
    if not players then return false end

    for _, unit in ipairs(players) do
        if unit and unit:isExist() then
            local pos = unit:getPoint()
            local dx = pos.x - zone.point.x
            local dz = pos.z - zone.point.z
            local dist = math.sqrt(dx * dx + dz * dz)
            if dist <= zone.radius then
                return true
            end
        end
    end

    return false
end

--- Check if group is alive
-- @param groupName string Group name
-- @return boolean
local function isGroupAlive(groupName)
    if not groupName then return false end
    local group = Group.getByName(groupName)
    if not group or not group:isExist() then return false end

    local units = group:getUnits()
    for _, unit in ipairs(units or {}) do
        if unit and unit:isExist() and unit:getLife() >= 1 then
            return true
        end
    end

    return false
end

--- Check if flag has value
-- @param flagName string Flag name
-- @param value any Expected value
-- @return boolean
local function checkFlag(flagName, value)
    if flagName == nil then return false end
    local flagValue = tonumber(trigger.misc.getUserFlag(flagName)) or 0
    if value == true then
        return flagValue > 0
    elseif value == false then
        return flagValue == 0
    else
        return flagValue == value
    end
end

--- Evaluate transition conditions
-- @param conditions table Conditions to check
-- @return boolean All conditions met
local function evaluateConditions(conditions)
    if type(conditions) ~= "table" then return false end
    local condType = conditions.type

    if condType == "zone" then
        return isCoalitionInZone(conditions.zone, DMS.PhaseManager.Config.playerCoalition)

    elseif condType == "zone_exit" then
        return not isCoalitionInZone(conditions.zone, DMS.PhaseManager.Config.playerCoalition)

    elseif condType == "group_dead" then
        return not isGroupAlive(conditions.group)

    elseif condType == "group_alive" then
        return isGroupAlive(conditions.group)

    elseif condType == "groups_dead" then
        for _, groupName in ipairs(conditions.groups or {}) do
            if isGroupAlive(groupName) then
                return false
            end
        end
        return true

    elseif condType == "flag" then
        return checkFlag(conditions.flag, conditions.value)

    elseif condType == "time" then
        local elapsed = timer.getTime() - DMS.PhaseManager.PhaseStartTime
        return elapsed >= (tonumber(conditions.seconds) or math.huge)

    elseif condType == "time_less" then
        local elapsed = timer.getTime() - DMS.PhaseManager.PhaseStartTime
        return elapsed < (tonumber(conditions.seconds) or 0)

    elseif condType == "objectives" then
        -- Check if all required objectives complete
        for _, objId in ipairs(conditions.required or {}) do
            if not checkFlag(objId, true) then
                return false
            end
        end
        return true

    elseif condType == "any_objective" then
        -- Check if any objective complete
        for _, objId in ipairs(conditions.objectives or {}) do
            if checkFlag(objId, true) then
                return true
            end
        end
        return false

    elseif condType == "custom" then
        return safeInvoke(conditions.check, "PhaseManager.customCondition") and true or false

    elseif condType == "AND" then
        for _, subCondition in ipairs(conditions.conditions or {}) do
            if not evaluateConditions(subCondition) then
                return false
            end
        end
        return true

    elseif condType == "OR" then
        for _, subCondition in ipairs(conditions.conditions or {}) do
            if evaluateConditions(subCondition) then
                return true
            end
        end
        return false

    elseif condType == "NOT" then
        return not evaluateConditions(conditions.condition)
    end

    return false
end

--- Transition to a new phase
-- @param newPhaseId string New phase ID
-- @param reason string|nil Transition reason
function DMS.PhaseManager.transitionTo(newPhaseId, reason)
    local newPhase = DMS.PhaseManager.Phases[newPhaseId]
    if not newPhase then
        env.warning(string.format("[PhaseManager] Unknown phase: %s", tostring(newPhaseId)))
        trigger.action.outText(string.format("[PhaseManager] Unknown phase: %s", tostring(newPhaseId)), 10)
        return false
    end

    local oldPhase = DMS.PhaseManager.Phases[DMS.PhaseManager.CurrentPhase]

    -- Exit current phase
    if oldPhase then
        safeInvoke(oldPhase.onExit, "PhaseManager.onExit." .. tostring(oldPhase.id), oldPhase.id, newPhaseId)

        -- Call registered exit callbacks
        local exitCallbacks = DMS.PhaseManager.OnExitCallbacks[oldPhase.id]
        if exitCallbacks then
            for _, callback in ipairs(exitCallbacks) do
                safeInvoke(callback, "PhaseManager.exitCallback." .. tostring(oldPhase.id), oldPhase.id, newPhaseId)
            end
        end
    end

    -- Update current phase
    DMS.PhaseManager.CurrentPhase = newPhaseId
    DMS.PhaseManager.PhaseStartTime = timer.getTime()
    debugLog("Phase %s -> %s (%s)", tostring(oldPhase and oldPhase.id or "none"), tostring(newPhaseId), tostring(reason or "conditions met"))

    -- Set phase flags
    for flagName, flagValue in pairs(newPhase.flags or {}) do
        if flagValue == true then flagValue = 1 elseif flagValue == false then flagValue = 0 end
        trigger.action.setUserFlag(flagName, flagValue)
    end

    -- Enter new phase
    safeInvoke(newPhase.onEnter, "PhaseManager.onEnter." .. tostring(newPhaseId), newPhaseId, oldPhase and oldPhase.id or nil)

    -- Call registered enter callbacks
    local enterCallbacks = DMS.PhaseManager.OnEnterCallbacks[newPhaseId]
    if enterCallbacks then
        for _, callback in ipairs(enterCallbacks) do
            safeInvoke(callback, "PhaseManager.enterCallback." .. tostring(newPhaseId), newPhaseId, oldPhase and oldPhase.id or nil)
        end
    end

    -- Announce phase change
    if DMS.PhaseManager.Config.announcePhaseChanges then
        local msg = string.format("=== %s ===", tostring(newPhase.name):upper())
        if newPhase.briefing and newPhase.briefing ~= "" then
            msg = msg .. "\n\n" .. newPhase.briefing
        end
        if reason then
            msg = msg .. "\n\n(" .. tostring(reason) .. ")"
        end

        trigger.action.outTextForCoalition(
            DMS.PhaseManager.Config.playerCoalition,
            msg,
            DMS.PhaseManager.Config.briefingDuration
        )
    end

    return true
end

--- Process phase checks (internal)
local function processPhaseCheckInternal(_, time)
    if not DMS.PhaseManager.Active then return nil end

    local interval = tonumber(DMS.PhaseManager.Config.checkInterval) or 5
    local currentId = DMS.PhaseManager.CurrentPhase
    local currentPhase = currentId and DMS.PhaseManager.Phases[currentId]
    if not currentPhase then
        return time + interval
    end

    local elapsed = timer.getTime() - DMS.PhaseManager.PhaseStartTime

    -- Call onUpdate if defined
    safeInvoke(currentPhase.onUpdate, "PhaseManager.onUpdate." .. tostring(currentPhase.id), currentPhase.id, elapsed)

    -- Check timeout
    if currentPhase.duration and elapsed >= currentPhase.duration then
        if currentPhase.timeoutPhase then
            DMS.PhaseManager.transitionTo(currentPhase.timeoutPhase, "Phase timeout")
            return time + interval
        end
    end

    -- Note: phase success/failure functions are informational; use
    -- addTransition(..., {type = "custom", check = fn}) to act on them.

    -- Check transitions
    local transitions = DMS.PhaseManager.Transitions[currentId]
    if transitions then
        for _, transition in ipairs(transitions) do
            if evaluateConditions(transition.conditions) then
                DMS.PhaseManager.transitionTo(transition.to)
                break
            end
        end
    end

    return time + interval
end

--- Process phase checks with error handling
local function processPhaseCheck(args, time)
    local success, result = pcall(processPhaseCheckInternal, args, time)
    if not success then
        logError("PhaseManager.processPhaseCheck", result)
        if not DMS.PhaseManager.Active then return nil end
        return time + (tonumber(DMS.PhaseManager.Config.checkInterval) or 5)
    end
    return result
end

--- Register callback for phase entry
-- @param phaseId string Phase ID
-- @param callback function Callback(phaseId, fromPhaseId)
function DMS.PhaseManager.onPhaseEnter(phaseId, callback)
    if not DMS.PhaseManager.OnEnterCallbacks[phaseId] then
        DMS.PhaseManager.OnEnterCallbacks[phaseId] = {}
    end
    table.insert(DMS.PhaseManager.OnEnterCallbacks[phaseId], callback)
end

--- Register callback for phase exit
-- @param phaseId string Phase ID
-- @param callback function Callback(phaseId, toPhaseId)
function DMS.PhaseManager.onPhaseExit(phaseId, callback)
    if not DMS.PhaseManager.OnExitCallbacks[phaseId] then
        DMS.PhaseManager.OnExitCallbacks[phaseId] = {}
    end
    table.insert(DMS.PhaseManager.OnExitCallbacks[phaseId], callback)
end

--- Get current phase
-- @return string|nil Current phase ID
function DMS.PhaseManager.getCurrentPhase()
    return DMS.PhaseManager.CurrentPhase
end

--- Get phase info
-- @param phaseId string|nil Phase ID (nil = current)
-- @return table|nil Phase info
function DMS.PhaseManager.getPhaseInfo(phaseId)
    phaseId = phaseId or DMS.PhaseManager.CurrentPhase
    local phase = DMS.PhaseManager.Phases[phaseId]
    if not phase then return nil end

    local elapsed = 0
    local remaining = nil
    if phaseId == DMS.PhaseManager.CurrentPhase then
        elapsed = timer.getTime() - DMS.PhaseManager.PhaseStartTime
        if phase.duration then
            remaining = phase.duration - elapsed
        end
    end

    return {
        id = phase.id,
        name = phase.name,
        elapsed = elapsed,
        remaining = remaining,
        duration = phase.duration,
    }
end

--- Force transition to phase
-- @param phaseId string Target phase
function DMS.PhaseManager.forceTransition(phaseId)
    DMS.PhaseManager.transitionTo(phaseId, "Forced transition")
end

--- Start phase manager
-- @param initialPhase string Starting phase
function DMS.PhaseManager.start(initialPhase)
    if DMS.PhaseManager.Active then return end

    DMS.PhaseManager.Active = true
    local ok, err = pcall(DMS.PhaseManager.transitionTo, initialPhase, "Mission start")
    if not ok then logError("PhaseManager.start", err) end

    DMS.PhaseManager.TimerId = timer.scheduleFunction(
        processPhaseCheck,
        nil,
        timer.getTime() + (tonumber(DMS.PhaseManager.Config.checkInterval) or 5)
    )
    debugLog("Started in phase '%s' (interval %ss)", tostring(initialPhase), tostring(DMS.PhaseManager.Config.checkInterval))
end

--- Stop phase manager
function DMS.PhaseManager.stop()
    DMS.PhaseManager.Active = false
    if DMS.PhaseManager.TimerId then
        pcall(timer.removeFunction, DMS.PhaseManager.TimerId)
        DMS.PhaseManager.TimerId = nil
    end
    debugLog("Stopped")
end

--- Define standard mission phases
function DMS.PhaseManager.defineStandardPhases()
    DMS.PhaseManager.definePhase("BRIEFING", {
        name = "Briefing",
        briefing = "Review mission objectives and prepare for takeoff.",
        duration = 300,  -- 5 minute max briefing
        timeoutPhase = "INGRESS",
        flags = {MISSION_STARTED = 1},
    })

    DMS.PhaseManager.definePhase("INGRESS", {
        name = "Ingress",
        briefing = "Proceed to target area. Maintain awareness of threats.",
        flags = {INGRESS_ACTIVE = 1},
        onEnter = function()
            callOptional(DMS.RandomSpawn, "start")
        end,
    })

    DMS.PhaseManager.definePhase("ATTACK", {
        name = "Attack",
        briefing = "You have reached the target area. Engage all objectives.",
        flags = {ATTACK_ACTIVE = 1},
        onEnter = function()
            if DMS.Awareness and DMS.Awareness.STATES then
                callOptional(DMS.Awareness, "setAllState", DMS.Awareness.STATES.ALERT)
            end
        end,
    })

    DMS.PhaseManager.definePhase("EGRESS", {
        name = "Egress",
        briefing = "Objectives complete. Return to base.",
        flags = {EGRESS_ACTIVE = 1},
        onEnter = function()
            callOptional(DMS.RandomSpawn, "stop")
        end,
    })

    DMS.PhaseManager.definePhase("RTB", {
        name = "Return to Base",
        briefing = "Proceed to home plate for landing.",
        flags = {RTB_ACTIVE = 1},
    })

    DMS.PhaseManager.definePhase("COMPLETE", {
        name = "Mission Complete",
        briefing = "Mission accomplished. Well done.",
        flags = {MISSION_COMPLETE = 1},
        onEnter = function()
            local report = callOptional(DMS.SkillScaling, "getReport")
            if type(report) == "table" then
                trigger.action.outTextForCoalition(
                    DMS.PhaseManager.Config.playerCoalition,
                    string.format(
                        "Mission Statistics:\nKills: %d\nDeaths: %d\nFinal Difficulty: %s",
                        tonumber(report.kills) or 0, tonumber(report.deaths) or 0, tostring(report.currentSkill)
                    ),
                    30
                )
            end
        end,
    })

    DMS.PhaseManager.definePhase("ABORT", {
        name = "Mission Abort",
        briefing = "Mission aborted. Return to base immediately.",
        flags = {MISSION_ABORTED = 1},
    })

    DMS.PhaseManager.definePhase("FAILED", {
        name = "Mission Failed",
        briefing = "Mission objectives not achieved.",
        flags = {MISSION_FAILED = 1},
    })
end

--[[
USAGE EXAMPLE:

-- Configure
DMS.PhaseManager.configure({
    announcePhaseChanges = true,
    briefingDuration = 20,
})

-- Define custom phases
DMS.PhaseManager.definePhase("STARTUP", {
    name = "Startup",
    briefing = "Start your aircraft and prepare for takeoff.",
    duration = 600,
    timeoutPhase = "INGRESS",
})

DMS.PhaseManager.definePhase("INGRESS", {
    name = "Ingress to Target",
    briefing = "Proceed to waypoint ALPHA. Stay below 500 feet to avoid radar.",
    onEnter = function()
        trigger.action.setUserFlag("MISSION_PHASE", 2)
        DMS.RandomSpawn.start()
    end,
})

DMS.PhaseManager.definePhase("ATTACK", {
    name = "Attack",
    briefing = "Engage the SAM site. Use terrain for cover.",
    onEnter = function()
        DMS.Awareness.setAllState("ALERT")
    end,
})

DMS.PhaseManager.definePhase("EGRESS", {
    name = "Egress",
    briefing = "Objectives complete. Return to FARP DELTA.",
})

-- Define transitions
DMS.PhaseManager.addTransition("STARTUP", "INGRESS", {
    type = "zone_exit",
    zone = "FARP_ZONE",
})

DMS.PhaseManager.addTransition("INGRESS", "ATTACK", {
    type = "zone",
    zone = "TARGET_ZONE",
})

DMS.PhaseManager.addTransition("ATTACK", "EGRESS", {
    type = "objectives",
    required = {"OBJ_SAM_DESTROYED", "OBJ_RADAR_DESTROYED"},
})

DMS.PhaseManager.addTransition("EGRESS", "COMPLETE", {
    type = "zone",
    zone = "FARP_ZONE",
})

-- Complex condition example
DMS.PhaseManager.addTransition("ATTACK", "FAILED", {
    type = "AND",
    conditions = {
        {type = "time", seconds = 1800},  -- 30 minutes elapsed
        {type = "NOT", condition = {
            type = "objectives",
            required = {"OBJ_SAM_DESTROYED"},
        }},
    },
    priority = -1,  -- Lower priority than success transition
})

-- Start mission
DMS.PhaseManager.start("STARTUP")

-- Register callbacks
DMS.PhaseManager.onPhaseEnter("ATTACK", function(phaseId, fromPhase)
    trigger.action.outText("Combat music starts...", 5)
end)
]]

-- Export
_G.DMS = DMS
