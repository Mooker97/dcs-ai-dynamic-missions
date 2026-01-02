-- Conditional Trigger System for DCS Missions
-- Complex if/then/else logic for mission events
-- Place in mission via DO SCRIPT FILE

DMS = DMS or {}
DMS.ConditionalTrigger = {}

-- Trigger definitions
DMS.ConditionalTrigger.Triggers = {}
DMS.ConditionalTrigger.Variables = {}
DMS.ConditionalTrigger.Active = false
DMS.ConditionalTrigger.TimerId = nil

-- Configuration
DMS.ConditionalTrigger.Config = {
    checkInterval = 2,
    playerCoalition = coalition.side.BLUE,
    announceEvaluations = false,
}

--- Configure conditional trigger system
-- @param settings table Configuration overrides
function DMS.ConditionalTrigger.configure(settings)
    for key, value in pairs(settings) do
        DMS.ConditionalTrigger.Config[key] = value
    end
end

--- Set a variable
-- @param name string Variable name
-- @param value any Variable value
function DMS.ConditionalTrigger.setVariable(name, value)
    DMS.ConditionalTrigger.Variables[name] = value
end

--- Get a variable
-- @param name string Variable name
-- @return any Variable value
function DMS.ConditionalTrigger.getVariable(name)
    return DMS.ConditionalTrigger.Variables[name]
end

--- Increment a variable
-- @param name string Variable name
-- @param amount number Amount to add (default 1)
function DMS.ConditionalTrigger.incrementVariable(name, amount)
    amount = amount or 1
    local current = DMS.ConditionalTrigger.Variables[name] or 0
    DMS.ConditionalTrigger.Variables[name] = current + amount
end

--- Evaluate a single condition
-- @param condition table Condition definition
-- @return boolean Condition met
local function evaluateCondition(condition)
    local condType = condition.type

    -- Boolean operators
    if condType == "AND" then
        for _, subCond in ipairs(condition.conditions or condition) do
            if not evaluateCondition(subCond) then
                return false
            end
        end
        return true

    elseif condType == "OR" then
        for _, subCond in ipairs(condition.conditions or condition) do
            if evaluateCondition(subCond) then
                return true
            end
        end
        return false

    elseif condType == "NOT" then
        return not evaluateCondition(condition.condition)

    elseif condType == "XOR" then
        local trueCount = 0
        for _, subCond in ipairs(condition.conditions) do
            if evaluateCondition(subCond) then
                trueCount = trueCount + 1
            end
        end
        return trueCount == 1

    -- Variable comparisons
    elseif condType == "variable" then
        local value = DMS.ConditionalTrigger.Variables[condition.name]
        local target = condition.value
        local op = condition.operator or "=="

        if value == nil then
            return condition.nilValue or false
        end

        if op == "==" or op == "eq" then
            return value == target
        elseif op == "!=" or op == "neq" then
            return value ~= target
        elseif op == ">" or op == "gt" then
            return value > target
        elseif op == ">=" or op == "gte" then
            return value >= target
        elseif op == "<" or op == "lt" then
            return value < target
        elseif op == "<=" or op == "lte" then
            return value <= target
        elseif op == "between" then
            return value >= target and value <= condition.max
        elseif op == "contains" then
            return string.find(tostring(value), tostring(target)) ~= nil
        end

    -- Flag checks
    elseif condType == "flag" then
        local flagValue = trigger.misc.getUserFlag(condition.flag)
        local target = condition.value
        local op = condition.operator or "=="

        if target == true then
            return flagValue > 0
        elseif target == false then
            return flagValue == 0
        end

        if op == "==" then
            return flagValue == target
        elseif op == "!=" then
            return flagValue ~= target
        elseif op == ">" then
            return flagValue > target
        elseif op == ">=" then
            return flagValue >= target
        elseif op == "<" then
            return flagValue < target
        elseif op == "<=" then
            return flagValue <= target
        end

    -- Time checks
    elseif condType == "mission_time" then
        local missionTime = timer.getTime()
        local target = condition.seconds
        local op = condition.operator or ">="

        if op == ">" then return missionTime > target
        elseif op == ">=" then return missionTime >= target
        elseif op == "<" then return missionTime < target
        elseif op == "<=" then return missionTime <= target
        elseif op == "==" then return math.abs(missionTime - target) < 1
        end

    elseif condType == "time_of_day" then
        local absTime = timer.getAbsTime()
        local hours = math.floor(absTime / 3600) % 24
        local minutes = math.floor((absTime % 3600) / 60)
        local currentMinutes = hours * 60 + minutes

        local afterMinutes = (condition.after_hour or 0) * 60 + (condition.after_minute or 0)
        local beforeMinutes = (condition.before_hour or 24) * 60 + (condition.before_minute or 0)

        return currentMinutes >= afterMinutes and currentMinutes < beforeMinutes

    -- Group/Unit checks
    elseif condType == "group_alive" then
        local group = Group.getByName(condition.group)
        if not group or not group:isExist() then return false end
        local units = group:getUnits()
        for _, unit in ipairs(units or {}) do
            if unit and unit:isExist() and unit:getLife() > 1 then
                return true
            end
        end
        return false

    elseif condType == "group_dead" then
        local group = Group.getByName(condition.group)
        if not group or not group:isExist() then return true end
        local units = group:getUnits()
        for _, unit in ipairs(units or {}) do
            if unit and unit:isExist() and unit:getLife() > 1 then
                return false
            end
        end
        return true

    elseif condType == "group_size" then
        local group = Group.getByName(condition.group)
        if not group or not group:isExist() then return false end
        local count = 0
        local units = group:getUnits()
        for _, unit in ipairs(units or {}) do
            if unit and unit:isExist() and unit:getLife() > 1 then
                count = count + 1
            end
        end
        local op = condition.operator or ">="
        local target = condition.count

        if op == "==" then return count == target
        elseif op == ">" then return count > target
        elseif op == ">=" then return count >= target
        elseif op == "<" then return count < target
        elseif op == "<=" then return count <= target
        end

    elseif condType == "groups_alive_count" then
        local count = 0
        for _, groupName in ipairs(condition.groups) do
            local group = Group.getByName(groupName)
            if group and group:isExist() then
                local units = group:getUnits()
                for _, unit in ipairs(units or {}) do
                    if unit and unit:isExist() and unit:getLife() > 1 then
                        count = count + 1
                        break
                    end
                end
            end
        end
        local op = condition.operator or ">="
        local target = condition.count

        if op == "==" then return count == target
        elseif op == ">" then return count > target
        elseif op == ">=" then return count >= target
        elseif op == "<" then return count < target
        elseif op == "<=" then return count <= target
        end

    -- Zone checks
    elseif condType == "zone" then
        local zone = trigger.misc.getZone(condition.zone)
        if not zone then return false end

        local coalitionSide = condition.coalition or DMS.ConditionalTrigger.Config.playerCoalition
        local players = coalition.getPlayers(coalitionSide)

        for _, unit in ipairs(players or {}) do
            if unit and unit:isExist() then
                local pos = unit:getPoint()
                local dx = pos.x - zone.point.x
                local dz = pos.z - zone.point.z
                local dist = math.sqrt(dx * dx + dz * dz)
                if dist <= zone.radius then
                    return condition.occupied ~= false
                end
            end
        end
        return condition.occupied == false

    elseif condType == "zone_empty" then
        local zone = trigger.misc.getZone(condition.zone)
        if not zone then return true end

        -- Check both coalitions
        for _, side in ipairs({coalition.side.RED, coalition.side.BLUE}) do
            local groups = coalition.getGroups(side)
            for _, group in ipairs(groups or {}) do
                if group:isExist() then
                    local units = group:getUnits()
                    for _, unit in ipairs(units or {}) do
                        if unit and unit:isExist() then
                            local pos = unit:getPoint()
                            local dx = pos.x - zone.point.x
                            local dz = pos.z - zone.point.z
                            local dist = math.sqrt(dx * dx + dz * dz)
                            if dist <= zone.radius then
                                return false
                            end
                        end
                    end
                end
            end
        end
        return true

    -- Player state checks
    elseif condType == "player_alive" then
        local players = coalition.getPlayers(DMS.ConditionalTrigger.Config.playerCoalition)
        return players and #players > 0

    elseif condType == "player_count" then
        local players = coalition.getPlayers(DMS.ConditionalTrigger.Config.playerCoalition)
        local count = players and #players or 0
        local op = condition.operator or ">="
        local target = condition.count

        if op == "==" then return count == target
        elseif op == ">" then return count > target
        elseif op == ">=" then return count >= target
        elseif op == "<" then return count < target
        elseif op == "<=" then return count <= target
        end

    elseif condType == "player_altitude" then
        local players = coalition.getPlayers(DMS.ConditionalTrigger.Config.playerCoalition)
        if not players or #players == 0 then return false end

        local pos = players[1]:getPoint()
        local altitude = pos.y
        if condition.agl then
            local terrain = land.getHeight({x = pos.x, y = pos.z})
            altitude = pos.y - terrain
        end

        local op = condition.operator or "<="
        local target = condition.altitude

        if op == ">" then return altitude > target
        elseif op == ">=" then return altitude >= target
        elseif op == "<" then return altitude < target
        elseif op == "<=" then return altitude <= target
        elseif op == "between" then
            return altitude >= target and altitude <= condition.max
        end

    -- Random
    elseif condType == "random" then
        return math.random() < condition.chance

    -- Custom function
    elseif condType == "custom" then
        return condition.check()

    -- DMS system integration
    elseif condType == "phase" then
        if DMS.PhaseManager then
            return DMS.PhaseManager.getCurrentPhase() == condition.phase
        end
        return false

    elseif condType == "awareness_state" then
        if DMS.Awareness then
            local status = DMS.Awareness.getStatus(condition.group)
            return status and status.state == condition.state
        end
        return false

    elseif condType == "skill_level" then
        if DMS.SkillScaling then
            local skill = DMS.SkillScaling.getCurrentSkill()
            local skillLevels = {"Rookie", "Average", "Good", "High", "Excellent"}
            local currentIdx, targetIdx

            for i, s in ipairs(skillLevels) do
                if s == skill then currentIdx = i end
                if s == condition.skill then targetIdx = i end
            end

            if not currentIdx or not targetIdx then return false end

            local op = condition.operator or "=="
            if op == "==" then return currentIdx == targetIdx
            elseif op == ">=" then return currentIdx >= targetIdx
            elseif op == "<=" then return currentIdx <= targetIdx
            elseif op == ">" then return currentIdx > targetIdx
            elseif op == "<" then return currentIdx < targetIdx
            end
        end
        return false
    end

    return false
end

--- Execute actions
-- @param actions table Action definitions
local function executeActions(actions)
    for _, action in ipairs(actions) do
        local actionType = action.type

        if actionType == "message" then
            trigger.action.outTextForCoalition(
                DMS.ConditionalTrigger.Config.playerCoalition,
                action.text,
                action.duration or 10
            )

        elseif actionType == "setVariable" then
            DMS.ConditionalTrigger.setVariable(action.name, action.value)

        elseif actionType == "incrementVariable" then
            DMS.ConditionalTrigger.incrementVariable(action.name, action.amount)

        elseif actionType == "setFlag" then
            trigger.action.setUserFlag(action.flag, action.value)

        elseif actionType == "spawn" then
            if action.pool and DMS.SpawnPool then
                DMS.SpawnPool.forceSpawn(action.pool)
            elseif action.group then
                local group = Group.getByName(action.group)
                if group then
                    trigger.action.activateGroup(group)
                end
            end

        elseif actionType == "activate" then
            local group = Group.getByName(action.group)
            if group then
                trigger.action.activateGroup(group)
            end

        elseif actionType == "explosion" then
            trigger.action.explosion(action.position, action.power or 100)

        elseif actionType == "smoke" then
            trigger.action.smoke(action.position, action.color or trigger.smokeColor.Red)

        elseif actionType == "sound" then
            trigger.action.outSound(action.file)

        elseif actionType == "transition" then
            if DMS.PhaseManager then
                DMS.PhaseManager.forceTransition(action.phase)
            end

        elseif actionType == "start_chain" then
            if DMS.EventChain then
                DMS.EventChain.start(action.chain)
            end

        elseif actionType == "enable_trigger" then
            DMS.ConditionalTrigger.enable(action.trigger)

        elseif actionType == "disable_trigger" then
            DMS.ConditionalTrigger.disable(action.trigger)

        elseif actionType == "custom" then
            action.execute()
        end
    end
end

--- Define a conditional trigger
-- @param triggerId string Unique trigger ID
-- @param conditions table Condition tree
-- @param actions table Actions to execute
-- @param options table|nil Trigger options
function DMS.ConditionalTrigger.define(triggerId, conditions, actions, options)
    options = options or {}

    DMS.ConditionalTrigger.Triggers[triggerId] = {
        id = triggerId,
        conditions = conditions,
        actions = actions,
        enabled = options.enabled ~= false,
        once = options.once ~= false,  -- Default: only fire once
        fired = false,
        cooldown = options.cooldown or 0,
        lastFired = 0,
        elseActions = options.elseActions,  -- Actions if condition fails
        priority = options.priority or 0,
    }
end

--- Evaluate a trigger manually
-- @param triggerId string Trigger ID
-- @return boolean Condition met
function DMS.ConditionalTrigger.evaluate(triggerId)
    local trigger = DMS.ConditionalTrigger.Triggers[triggerId]
    if not trigger then return false end

    return evaluateCondition(trigger.conditions)
end

--- Enable a trigger
-- @param triggerId string Trigger ID
function DMS.ConditionalTrigger.enable(triggerId)
    local trig = DMS.ConditionalTrigger.Triggers[triggerId]
    if trig then
        trig.enabled = true
    end
end

--- Disable a trigger
-- @param triggerId string Trigger ID
function DMS.ConditionalTrigger.disable(triggerId)
    local trig = DMS.ConditionalTrigger.Triggers[triggerId]
    if trig then
        trig.enabled = false
    end
end

--- Reset a trigger (allow it to fire again)
-- @param triggerId string Trigger ID
function DMS.ConditionalTrigger.reset(triggerId)
    local trig = DMS.ConditionalTrigger.Triggers[triggerId]
    if trig then
        trig.fired = false
    end
end

--- Process triggers
local function processTriggers(_, time)
    if not DMS.ConditionalTrigger.Active then return nil end

    local currentTime = timer.getTime()

    -- Sort by priority
    local sortedTriggers = {}
    for _, trig in pairs(DMS.ConditionalTrigger.Triggers) do
        table.insert(sortedTriggers, trig)
    end
    table.sort(sortedTriggers, function(a, b) return a.priority > b.priority end)

    for _, trig in ipairs(sortedTriggers) do
        if not trig.enabled then goto continue end
        if trig.once and trig.fired then goto continue end

        -- Check cooldown
        if trig.cooldown > 0 and (currentTime - trig.lastFired) < trig.cooldown then
            goto continue
        end

        local result = evaluateCondition(trig.conditions)

        if result then
            executeActions(trig.actions)
            trig.fired = true
            trig.lastFired = currentTime

            if DMS.ConditionalTrigger.Config.announceEvaluations then
                trigger.action.outText(string.format("[ConditionalTrigger] %s fired", trig.id), 5)
            end
        elseif trig.elseActions then
            executeActions(trig.elseActions)
        end

        ::continue::
    end

    return time + DMS.ConditionalTrigger.Config.checkInterval
end

--- Start conditional trigger system
function DMS.ConditionalTrigger.start()
    if DMS.ConditionalTrigger.Active then return end

    DMS.ConditionalTrigger.Active = true
    DMS.ConditionalTrigger.TimerId = timer.scheduleFunction(
        processTriggers,
        nil,
        timer.getTime() + DMS.ConditionalTrigger.Config.checkInterval
    )
end

--- Stop conditional trigger system
function DMS.ConditionalTrigger.stop()
    DMS.ConditionalTrigger.Active = false
    if DMS.ConditionalTrigger.TimerId then
        timer.removeFunction(DMS.ConditionalTrigger.TimerId)
        DMS.ConditionalTrigger.TimerId = nil
    end
end

--[[
USAGE EXAMPLE:

-- Configure
DMS.ConditionalTrigger.configure({
    announceEvaluations = true,
})

-- Initialize variables
DMS.ConditionalTrigger.setVariable("player_kills", 0)
DMS.ConditionalTrigger.setVariable("mission_time", 0)

-- Simple trigger: spawn reinforcements when player kills reach threshold
DMS.ConditionalTrigger.define("reinforcement_trigger", {
    type = "AND",
    conditions = {
        {type = "variable", name = "player_kills", operator = ">=", value = 5},
        {type = "mission_time", operator = ">=", seconds = 300},
    },
}, {
    {type = "message", text = "Enemy reinforcements inbound!", duration = 10},
    {type = "spawn", pool = "heavy_reinforcements"},
    {type = "setVariable", name = "reinforcements_called", value = true},
})

-- Complex nested condition
DMS.ConditionalTrigger.define("complex_trigger", {
    type = "AND",
    conditions = {
        -- Player is in combat zone
        {type = "zone", zone = "COMBAT_ZONE", occupied = true},

        -- AND either:
        {
            type = "OR",
            conditions = {
                -- SAM is destroyed
                {type = "group_dead", group = "SA-6-Battery"},

                -- OR player is below 100m AGL
                {type = "player_altitude", operator = "<", altitude = 100, agl = true},
            },
        },

        -- AND NOT in safe zone
        {
            type = "NOT",
            condition = {type = "zone", zone = "SAFE_ZONE", occupied = true},
        },
    },
}, {
    {type = "message", text = "Conditions met for extraction!", duration = 15},
    {type = "activate", group = "Extraction-Helo"},
    {type = "setFlag", flag = "EXTRACTION_ENABLED", value = 1},
})

-- If/else trigger
DMS.ConditionalTrigger.define("mission_outcome", {
    type = "AND",
    conditions = {
        {type = "group_dead", group = "Primary-Target"},
        {type = "player_alive"},
    },
}, {
    {type = "message", text = "Mission Success! RTB.", duration = 20},
    {type = "transition", phase = "EGRESS"},
}, {
    once = true,
    elseActions = {
        {type = "message", text = "Mission objectives not yet complete.", duration = 10},
    },
})

-- Repeating trigger with cooldown
DMS.ConditionalTrigger.define("periodic_warning", {
    type = "AND",
    conditions = {
        {type = "zone", zone = "DANGER_ZONE", occupied = true},
        {type = "skill_level", operator = "<=", skill = "Average"},
    },
}, {
    {type = "message", text = "WARNING: You are in a high-threat area!", duration = 5},
}, {
    once = false,
    cooldown = 60,  -- Only warn every 60 seconds
})

-- Track kills using event handler
world.addEventHandler({
    onEvent = function(self, event)
        if event.id == world.event.S_EVENT_KILL then
            if event.initiator then
                local coal = event.initiator:getCoalition()
                if coal == coalition.side.BLUE then
                    DMS.ConditionalTrigger.incrementVariable("player_kills")
                end
            end
        end
    end,
})

-- Start system
DMS.ConditionalTrigger.start()
]]

-- Export
_G.DMS = DMS
