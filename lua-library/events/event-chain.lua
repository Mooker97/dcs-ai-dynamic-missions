-- Event Chain System for DCS Missions
-- Linked event sequences that create cause-and-effect chains
-- Place in mission via DO SCRIPT FILE

DMS = DMS or {}
DMS.EventChain = {}

-- Chain definitions
DMS.EventChain.Chains = {}
DMS.EventChain.ActiveChains = {}
DMS.EventChain.Active = false

-- Configuration
DMS.EventChain.Config = {
    checkInterval = 1,
    announceChains = false,
    playerCoalition = coalition.side.BLUE,
}

--- Configure event chain system
-- @param settings table Configuration overrides
function DMS.EventChain.configure(settings)
    for key, value in pairs(settings) do
        DMS.EventChain.Config[key] = value
    end
end

--- Define an event chain
-- @param chainId string Unique chain ID
-- @param steps table Array of chain steps
function DMS.EventChain.defineChain(chainId, steps)
    DMS.EventChain.Chains[chainId] = {
        id = chainId,
        steps = steps,
        onComplete = nil,
        onCancel = nil,
    }
end

--- Check if trigger condition is met
-- @param trigger table Trigger definition
-- @param chainState table Current chain state
-- @return boolean Trigger met
local function checkTrigger(triggerDef, chainState)
    local triggerType = triggerDef.type

    if triggerType == "immediate" then
        return true

    elseif triggerType == "delay" then
        local elapsed = timer.getTime() - chainState.stepStartTime
        return elapsed >= triggerDef.seconds

    elseif triggerType == "kill" then
        local group = Group.getByName(triggerDef.target)
        if not group or not group:isExist() then
            return true  -- Group dead
        end
        local units = group:getUnits()
        for _, unit in ipairs(units or {}) do
            if unit and unit:isExist() and unit:getLife() > 1 then
                return false  -- Still alive
            end
        end
        return true

    elseif triggerType == "unit_dead" then
        local unit = Unit.getByName(triggerDef.target)
        return not unit or not unit:isExist() or unit:getLife() <= 1

    elseif triggerType == "flag" then
        local flagValue = trigger.misc.getUserFlag(triggerDef.flag)
        if triggerDef.value == true then
            return flagValue > 0
        elseif triggerDef.value == false then
            return flagValue == 0
        else
            return flagValue == triggerDef.value
        end

    elseif triggerType == "zone" then
        local zone = trigger.misc.getZone(triggerDef.zone)
        if not zone then return false end

        local players = coalition.getPlayers(DMS.EventChain.Config.playerCoalition)
        for _, unit in ipairs(players or {}) do
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

    elseif triggerType == "zone_exit" then
        local zone = trigger.misc.getZone(triggerDef.zone)
        if not zone then return true end

        local players = coalition.getPlayers(DMS.EventChain.Config.playerCoalition)
        for _, unit in ipairs(players or {}) do
            if unit and unit:isExist() then
                local pos = unit:getPoint()
                local dx = pos.x - zone.point.x
                local dz = pos.z - zone.point.z
                local dist = math.sqrt(dx * dx + dz * dz)
                if dist <= zone.radius then
                    return false  -- Still in zone
                end
            end
        end
        return true

    elseif triggerType == "time_of_day" then
        local absTime = timer.getAbsTime()
        local hours = math.floor(absTime / 3600) % 24
        return hours >= triggerDef.after and hours < triggerDef.before

    elseif triggerType == "random" then
        if chainState.randomChecked then
            return chainState.randomResult
        end
        chainState.randomChecked = true
        chainState.randomResult = math.random() < triggerDef.chance
        return chainState.randomResult

    elseif triggerType == "custom" then
        return triggerDef.check(chainState)

    elseif triggerType == "chain_complete" then
        local targetChain = DMS.EventChain.ActiveChains[triggerDef.chain]
        return targetChain and targetChain.completed

    elseif triggerType == "AND" then
        for _, subTrigger in ipairs(triggerDef.triggers) do
            if not checkTrigger(subTrigger, chainState) then
                return false
            end
        end
        return true

    elseif triggerType == "OR" then
        for _, subTrigger in ipairs(triggerDef.triggers) do
            if checkTrigger(subTrigger, chainState) then
                return true
            end
        end
        return false
    end

    return false
end

--- Execute step action
-- @param step table Step definition
-- @param chainState table Chain state
local function executeAction(step, chainState)
    if step.action then
        step.action(chainState)
    end

    -- Handle action types
    if step.actions then
        for _, actionDef in ipairs(step.actions) do
            local actionType = actionDef.type

            if actionType == "message" then
                trigger.action.outTextForCoalition(
                    DMS.EventChain.Config.playerCoalition,
                    actionDef.text,
                    actionDef.duration or 10
                )

            elseif actionType == "spawn" then
                if actionDef.pool and DMS.SpawnPool then
                    DMS.SpawnPool.forceSpawn(actionDef.pool)
                elseif actionDef.group then
                    local group = Group.getByName(actionDef.group)
                    if group then
                        trigger.action.activateGroup(group)
                    end
                end

            elseif actionType == "flag" then
                trigger.action.setUserFlag(actionDef.flag, actionDef.value)

            elseif actionType == "explosion" then
                trigger.action.explosion(actionDef.position, actionDef.power or 100)

            elseif actionType == "smoke" then
                trigger.action.smoke(actionDef.position, actionDef.color or trigger.smokeColor.Red)

            elseif actionType == "flare" then
                trigger.action.illuminationBomb(actionDef.position, actionDef.power or 100000)

            elseif actionType == "sound" then
                trigger.action.outSound(actionDef.file)

            elseif actionType == "activate" then
                local group = Group.getByName(actionDef.group)
                if group then
                    trigger.action.activateGroup(group)
                end

            elseif actionType == "deactivate" then
                local group = Group.getByName(actionDef.group)
                if group then
                    trigger.action.deactivateGroup(group)
                end

            elseif actionType == "start_chain" then
                DMS.EventChain.start(actionDef.chain)

            elseif actionType == "cancel_chain" then
                DMS.EventChain.cancel(actionDef.chain)

            elseif actionType == "awareness" then
                if DMS.Awareness then
                    if actionDef.group then
                        DMS.Awareness.setState(actionDef.group, actionDef.state)
                    else
                        DMS.Awareness.setAllState(actionDef.state)
                    end
                end

            elseif actionType == "custom" then
                actionDef.execute(chainState)
            end
        end
    end
end

--- Process active chains (internal)
local function processChainsInternal(_, time)
    if not DMS.EventChain.Active then return nil end

    for chainId, chainState in pairs(DMS.EventChain.ActiveChains) do
        if chainState.paused or chainState.completed or chainState.cancelled then
            goto continue
        end

        local chain = DMS.EventChain.Chains[chainId]
        if not chain then goto continue end

        local currentStep = chain.steps[chainState.currentStep]
        if not currentStep then
            -- Chain complete
            chainState.completed = true
            if chain.onComplete then
                chain.onComplete(chainState)
            end
            if DMS.EventChain.Config.announceChains then
                trigger.action.outText(string.format("[EventChain] %s completed", chainId), 5)
            end
            goto continue
        end

        -- Check trigger
        if checkTrigger(currentStep.trigger, chainState) then
            -- Execute action
            executeAction(currentStep, chainState)

            if DMS.EventChain.Config.announceChains then
                trigger.action.outText(string.format(
                    "[EventChain] %s step %d executed",
                    chainId, chainState.currentStep
                ), 5)
            end

            -- Check for branch
            if currentStep.branch then
                local branchCondition = currentStep.branch.condition
                if branchCondition and checkTrigger(branchCondition, chainState) then
                    -- Take branch
                    if currentStep.branch.goto then
                        chainState.currentStep = currentStep.branch.goto
                    elseif currentStep.branch.chain then
                        DMS.EventChain.start(currentStep.branch.chain)
                        chainState.completed = true
                    end
                else
                    chainState.currentStep = chainState.currentStep + 1
                end
            else
                -- Move to next step
                chainState.currentStep = chainState.currentStep + 1
            end

            chainState.stepStartTime = timer.getTime()
            chainState.randomChecked = false
        end

        ::continue::
    end

    return time + DMS.EventChain.Config.checkInterval
end

--- Process active chains with error handling
local function processChains(args, time)
    local success, result = pcall(processChainsInternal, args, time)
    if not success then
        if DMS.Error then
            DMS.Error.log("EventChain.processChains", result)
        else
            env.error("[DMS LUA ERROR] EventChain.processChains: " .. tostring(result))
        end
        return time + (DMS.EventChain.Config.checkInterval or 1)
    end
    return result
end

--- Start an event chain
-- @param chainId string Chain ID
-- @param options table|nil Start options
function DMS.EventChain.start(chainId, options)
    options = options or {}

    local chain = DMS.EventChain.Chains[chainId]
    if not chain then
        trigger.action.outText(string.format("[EventChain] Unknown chain: %s", chainId), 10)
        return false
    end

    DMS.EventChain.ActiveChains[chainId] = {
        chainId = chainId,
        currentStep = options.startStep or 1,
        stepStartTime = timer.getTime(),
        startTime = timer.getTime(),
        paused = false,
        completed = false,
        cancelled = false,
        randomChecked = false,
        randomResult = false,
        data = options.data or {},  -- Custom data storage
    }

    if DMS.EventChain.Config.announceChains then
        trigger.action.outText(string.format("[EventChain] %s started", chainId), 5)
    end

    -- Start processing if not already active
    if not DMS.EventChain.Active then
        DMS.EventChain.Active = true
        timer.scheduleFunction(
            processChains,
            nil,
            timer.getTime() + DMS.EventChain.Config.checkInterval
        )
    end

    return true
end

--- Pause a chain
-- @param chainId string Chain ID
function DMS.EventChain.pause(chainId)
    local chainState = DMS.EventChain.ActiveChains[chainId]
    if chainState then
        chainState.paused = true
        chainState.pauseTime = timer.getTime()
    end
end

--- Resume a chain
-- @param chainId string Chain ID
function DMS.EventChain.resume(chainId)
    local chainState = DMS.EventChain.ActiveChains[chainId]
    if chainState and chainState.paused then
        -- Adjust step start time for pause duration
        local pauseDuration = timer.getTime() - chainState.pauseTime
        chainState.stepStartTime = chainState.stepStartTime + pauseDuration
        chainState.paused = false
    end
end

--- Cancel a chain
-- @param chainId string Chain ID
function DMS.EventChain.cancel(chainId)
    local chainState = DMS.EventChain.ActiveChains[chainId]
    if chainState then
        chainState.cancelled = true
        local chain = DMS.EventChain.Chains[chainId]
        if chain and chain.onCancel then
            chain.onCancel(chainState)
        end
    end
end

--- Get chain status
-- @param chainId string Chain ID
-- @return table|nil Status info
function DMS.EventChain.getStatus(chainId)
    local chainState = DMS.EventChain.ActiveChains[chainId]
    if not chainState then return nil end

    local chain = DMS.EventChain.Chains[chainId]

    return {
        chainId = chainId,
        currentStep = chainState.currentStep,
        totalSteps = chain and #chain.steps or 0,
        elapsed = timer.getTime() - chainState.startTime,
        paused = chainState.paused,
        completed = chainState.completed,
        cancelled = chainState.cancelled,
    }
end

--- Check if chain is active
-- @param chainId string Chain ID
-- @return boolean Active
function DMS.EventChain.isActive(chainId)
    local chainState = DMS.EventChain.ActiveChains[chainId]
    return chainState and not chainState.completed and not chainState.cancelled
end

--- Register completion callback
-- @param chainId string Chain ID
-- @param callback function Callback(chainState)
function DMS.EventChain.onComplete(chainId, callback)
    local chain = DMS.EventChain.Chains[chainId]
    if chain then
        chain.onComplete = callback
    end
end

--- Register cancellation callback
-- @param chainId string Chain ID
-- @param callback function Callback(chainState)
function DMS.EventChain.onCancel(chainId, callback)
    local chain = DMS.EventChain.Chains[chainId]
    if chain then
        chain.onCancel = callback
    end
end

--- Stop all chains
function DMS.EventChain.stopAll()
    for chainId, _ in pairs(DMS.EventChain.ActiveChains) do
        DMS.EventChain.cancel(chainId)
    end
    DMS.EventChain.Active = false
end

--[[
USAGE EXAMPLE:

-- Configure
DMS.EventChain.configure({
    announceChains = true,
})

-- Define a SEAD cascade chain
DMS.EventChain.defineChain("sead_cascade", {
    -- Step 1: Wait for radar to die
    {
        trigger = {type = "kill", target = "EWR-1"},
        action = function()
            trigger.action.outText("Early warning radar destroyed!", 10)
        end,
    },

    -- Step 2: After 30 seconds, SAMs go blind
    {
        trigger = {type = "delay", seconds = 30},
        actions = {
            {type = "message", text = "Enemy SAM network losing coordination...", duration = 10},
            {type = "flag", flag = "SAM_DEGRADED", value = 1},
        },
        action = function()
            if DMS.SAMAmbush then
                DMS.SAMAmbush.setDetectionMultiplier(0.3)
            end
        end,
    },

    -- Step 3: After 60 more seconds, QRF responds
    {
        trigger = {type = "delay", seconds = 60},
        actions = {
            {type = "message", text = "WARNING: Enemy QRF scrambling!", duration = 10},
            {type = "spawn", pool = "QRF-Helicopters"},
        },
    },

    -- Step 4: Random chance of reinforcements
    {
        trigger = {type = "random", chance = 0.5},
        actions = {
            {type = "message", text = "Additional enemy forces detected!", duration = 10},
            {type = "spawn", pool = "Armor-Reinforcements"},
        },
    },
})

-- Define convoy ambush chain
DMS.EventChain.defineChain("convoy_ambush", {
    -- Wait for player to enter ambush zone
    {
        trigger = {type = "zone", zone = "AMBUSH_ZONE"},
        actions = {
            {type = "activate", group = "Ambush-Infantry-1"},
            {type = "activate", group = "Ambush-Infantry-2"},
            {type = "message", text = "AMBUSH! Contact left and right!", duration = 5},
        },
    },

    -- If player stays in zone too long, reinforcements
    {
        trigger = {
            type = "AND",
            triggers = {
                {type = "delay", seconds = 120},
                {type = "zone", zone = "AMBUSH_ZONE"},
            },
        },
        actions = {
            {type = "message", text = "Enemy reinforcements arriving!", duration = 10},
            {type = "activate", group = "QRF-Technical"},
        },
    },

    -- Wait for player to exit
    {
        trigger = {type = "zone_exit", zone = "AMBUSH_ZONE"},
        actions = {
            {type = "message", text = "Ambush zone cleared.", duration = 5},
            {type = "flag", flag = "AMBUSH_SURVIVED", value = 1},
        },
    },
})

-- Branching chain example
DMS.EventChain.defineChain("mission_fork", {
    {
        trigger = {type = "zone", zone = "DECISION_POINT"},
        action = function(state)
            trigger.action.outText("Choose your path:\n- North: Heavy resistance\n- South: Longer but safer", 15)
        end,
    },
    {
        trigger = {type = "delay", seconds = 5},
        action = function() end,
        branch = {
            condition = {type = "zone", zone = "NORTH_PATH"},
            chain = "heavy_resistance_path",  -- Start different chain
        },
    },
    -- Default continues to south path
    {
        trigger = {type = "zone", zone = "SOUTH_PATH"},
        actions = {
            {type = "message", text = "Taking the southern route...", duration = 10},
            {type = "start_chain", chain = "southern_path"},
        },
    },
})

-- Start chain
DMS.EventChain.start("sead_cascade")

-- Check status
local status = DMS.EventChain.getStatus("sead_cascade")
print("Chain at step " .. status.currentStep .. " of " .. status.totalSteps)

-- Register completion callback
DMS.EventChain.onComplete("sead_cascade", function(state)
    trigger.action.outText("SEAD operation complete. Skies are clear.", 15)
    trigger.action.setUserFlag("SEAD_COMPLETE", 1)
end)
]]

-- Export
_G.DMS = DMS
