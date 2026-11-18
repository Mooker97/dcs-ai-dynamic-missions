-- Kill Chain Reaction System for DCS Missions
-- Triggers events when specific targets are destroyed
-- Optional: utils/error-handler.lua, utils/mission-settings.lua
-- Place in mission via DO SCRIPT FILE


DMS = DMS or {}
DMS.KillChain = DMS.KillChain or {}

-- Tracked targets and their reactions
DMS.KillChain.Targets = DMS.KillChain.Targets or {}
DMS.KillChain.Active = DMS.KillChain.Active or false

-- Configuration
DMS.KillChain.Config = DMS.KillChain.Config or {
    playerCoalition = coalition.side.BLUE,
    announceReactions = true,
    displayDuration = 10,
    pollInterval = 10,      -- Seconds between fallback liveness polls (0 = disabled)
}

local LOG_PREFIX = "[KillChain]"

local function isDebug()
    return DMS.Settings and DMS.Settings.isDebug and DMS.Settings.isDebug()
end

local function debugLog(fmt, ...)
    if isDebug() then
        env.info(string.format(LOG_PREFIX .. " " .. fmt, ...))
    end
end

local function logError(context, err)
    if DMS.Error and DMS.Error.log then
        DMS.Error.log(context, err)
    else
        env.error(string.format("%s %s: %s", LOG_PREFIX, tostring(context), tostring(err)))
    end
end

--- Safely call obj:method(...) returning nil on error
local function safeMethod(obj, method, ...)
    if obj == nil or type(obj) ~= "table" or type(obj[method]) ~= "function" then
        return nil
    end
    local ok, res = pcall(obj[method], obj, ...)
    if ok then return res end
    return nil
end

local function objectExists(obj)
    return safeMethod(obj, "isExist") == true
end

--- Count alive units in a group (excluding an optional unit name that is dying)
local function countAliveUnits(group, excludeName)
    if not objectExists(group) then return 0 end
    local units = safeMethod(group, "getUnits")
    if type(units) ~= "table" then return 0 end
    local alive = 0
    for _, unit in ipairs(units) do
        if objectExists(unit) and (excludeName == nil or safeMethod(unit, "getName") ~= excludeName) then
            local life = safeMethod(unit, "getLife")
            if life == nil or life >= 1 then
                alive = alive + 1
            end
        end
    end
    return alive
end

--- Check whether a registered target is currently alive
-- @return boolean|nil alive (nil = target not found in world)
local function isTargetAlive(targetName)
    local group = Group.getByName(targetName)
    if group and objectExists(group) then
        return countAliveUnits(group) > 0
    end
    local unit = Unit.getByName(targetName)
    if unit and objectExists(unit) then
        local life = safeMethod(unit, "getLife")
        return life == nil or life >= 1
    end
    if StaticObject and StaticObject.getByName then
        local static = StaticObject.getByName(targetName)
        if static and objectExists(static) then
            local life = safeMethod(static, "getLife")
            return life == nil or life > 0
        end
    end
    return nil
end

--- Configure kill chain system
-- @param settings table Configuration overrides
function DMS.KillChain.configure(settings)
    if type(settings) ~= "table" then return end
    for key, value in pairs(settings) do
        DMS.KillChain.Config[key] = value
    end
end

--- Register a target with chain reactions
-- @param targetName string Unit, static or group name to track
-- @param reactions table Reaction definitions
function DMS.KillChain.registerTarget(targetName, reactions)
    if type(targetName) ~= "string" then
        logError("KillChain.registerTarget", "targetName must be a string")
        return
    end
    local ok, alive = pcall(isTargetAlive, targetName)
    DMS.KillChain.Targets[targetName] = {
        name = targetName,
        destroyed = false,
        seenAlive = ok and alive == true,
        reactions = type(reactions) == "table" and reactions or {},
    }
    debugLog("Registered target '%s' with %d reactions", targetName, #DMS.KillChain.Targets[targetName].reactions)
end

--- Create a spawn reaction
-- @param groupNames table Groups to activate
-- @param delay number|nil Delay before activation
-- @param message string|nil Message to display
-- @return table Reaction definition
function DMS.KillChain.spawnReaction(groupNames, delay, message)
    return {
        type = "spawn",
        groups = groupNames or {},
        delay = delay or 0,
        message = message,
    }
end

--- Create a flag reaction
-- @param flagName string Flag to set
-- @param flagValue number Value to set
-- @return table Reaction definition
function DMS.KillChain.flagReaction(flagName, flagValue)
    return {
        type = "flag",
        flag = flagName,
        value = flagValue or 1,
    }
end

--- Create a message reaction
-- @param text string Message text
-- @param duration number|nil Display duration
-- @return table Reaction definition
function DMS.KillChain.messageReaction(text, duration)
    return {
        type = "message",
        text = text,
        duration = duration or DMS.KillChain.Config.displayDuration,
    }
end

--- Create a cascade kill reaction (destroy other groups)
-- @param groupNames table Groups to destroy
-- @param delay number|nil Delay before destruction
-- @return table Reaction definition
function DMS.KillChain.cascadeReaction(groupNames, delay)
    return {
        type = "cascade",
        groups = groupNames or {},
        delay = delay or 0,
    }
end

--- Create a custom function reaction
-- @param func function Function to call
-- @param args any|nil Arguments to pass
-- @return table Reaction definition
function DMS.KillChain.customReaction(func, args)
    return {
        type = "custom",
        func = func,
        args = args,
    }
end

--- Execute a reaction
-- @param reaction table Reaction definition
local function executeReaction(reaction, targetName)
    if type(reaction) ~= "table" then return end

    if reaction.type == "spawn" then
        for _, groupName in ipairs(reaction.groups or {}) do
            local group = Group.getByName(groupName)
            if group and objectExists(group) then
                trigger.action.activateGroup(group)
                debugLog("'%s' destroyed -> activated group '%s'", tostring(targetName), tostring(groupName))
            else
                debugLog("'%s' destroyed -> spawn group '%s' not found", tostring(targetName), tostring(groupName))
            end
        end
        if reaction.message and DMS.KillChain.Config.announceReactions then
            trigger.action.outTextForCoalition(
                DMS.KillChain.Config.playerCoalition,
                reaction.message,
                DMS.KillChain.Config.displayDuration,
                true
            )
        end

    elseif reaction.type == "flag" then
        if reaction.flag ~= nil then
            trigger.action.setUserFlag(tostring(reaction.flag), reaction.value or 1)
            debugLog("'%s' destroyed -> flag '%s' = %s", tostring(targetName), tostring(reaction.flag), tostring(reaction.value))
        end

    elseif reaction.type == "message" then
        if reaction.text then
            trigger.action.outTextForCoalition(
                DMS.KillChain.Config.playerCoalition,
                reaction.text,
                reaction.duration or DMS.KillChain.Config.displayDuration,
                true
            )
        end

    elseif reaction.type == "cascade" then
        for _, groupName in ipairs(reaction.groups or {}) do
            local group = Group.getByName(groupName)
            if group and objectExists(group) then
                safeMethod(group, "destroy")
                debugLog("'%s' destroyed -> cascade destroyed '%s'", tostring(targetName), tostring(groupName))
            end
        end

    elseif reaction.type == "custom" then
        if type(reaction.func) == "function" then
            reaction.func(reaction.args)
        end
    end
end

local function safeExecuteReaction(reaction, targetName)
    local ok, err = pcall(executeReaction, reaction, targetName)
    if not ok then
        logError("KillChain.executeReaction(" .. tostring(targetName) .. ")", err)
    end
end

--- Process a target destruction
-- @param targetName string Name of destroyed target
local function processTargetDestruction(targetName)
    local target = DMS.KillChain.Targets[targetName]
    if not target or target.destroyed then
        return
    end

    target.destroyed = true
    target.destroyedTime = timer.getTime()
    debugLog("Target '%s' destroyed, executing %d reactions", targetName, #target.reactions)

    for _, reaction in ipairs(target.reactions) do
        local delay = tonumber(type(reaction) == "table" and reaction.delay) or 0
        if delay > 0 then
            timer.scheduleFunction(function()
                safeExecuteReaction(reaction, targetName)
                return nil
            end, nil, timer.getTime() + delay)
        else
            safeExecuteReaction(reaction, targetName)
        end
    end
end

--- Check a group target after one of its units died
local function checkGroupTarget(groupName, dyingUnitName)
    local target = DMS.KillChain.Targets[groupName]
    if not target or target.destroyed then return end
    local group = Group.getByName(groupName)
    if countAliveUnits(group, dyingUnitName) == 0 then
        processTargetDestruction(groupName)
    end
end

--- Handle a destroyed object (event initiator or target)
-- Objects may be units, statics, scenery or weapons; only units have groups.
local function handleDestroyedObject(obj)
    if obj == nil or type(obj) ~= "table" then return end

    local category = safeMethod(obj, "getCategory")
    local objName = safeMethod(obj, "getName")

    -- Unit or static tracked by name
    if type(objName) == "string" and DMS.KillChain.Targets[objName] then
        processTargetDestruction(objName)
    end

    -- Group membership only applies to units
    if category == Object.Category.UNIT then
        local group = safeMethod(obj, "getGroup")
        local groupName = group and safeMethod(group, "getName")
        local target = type(groupName) == "string" and DMS.KillChain.Targets[groupName]
        if target and not target.destroyed then
            -- Re-check shortly after; the dying unit may still report as existing
            local dyingName = objName
            timer.scheduleFunction(function()
                local ok, err = pcall(checkGroupTarget, groupName, dyingName)
                if not ok then logError("KillChain.checkGroupTarget", err) end
                return nil
            end, nil, timer.getTime() + 1)
        end
    end
end

-- event id -> event field holding the destroyed object
local function buildDeathEvents()
    local ev = world.event
    local map = {}
    if ev.S_EVENT_DEAD then map[ev.S_EVENT_DEAD] = "initiator" end
    if ev.S_EVENT_CRASH then map[ev.S_EVENT_CRASH] = "initiator" end
    if ev.S_EVENT_PILOT_DEAD then map[ev.S_EVENT_PILOT_DEAD] = "initiator" end
    if ev.S_EVENT_UNIT_LOST then map[ev.S_EVENT_UNIT_LOST] = "initiator" end
    if ev.S_EVENT_KILL then map[ev.S_EVENT_KILL] = "target" end
    return map
end

--- Create event handler (pcall-guarded)
local function createEventHandler()
    local deathEvents = buildDeathEvents()
    return {
        onEvent = function(self, event)
            if not DMS.KillChain.Active or type(event) ~= "table" then
                return
            end
            local field = deathEvents[event.id]
            if not field then return end
            local ok, err = pcall(handleDestroyedObject, event[field])
            if not ok then
                logError("KillChain.onEvent(" .. tostring(event.id) .. ")", err)
            end
        end
    }
end

--- Fallback poll: catches targets destroyed without an event (e.g. group:destroy())
local function pollTargets()
    for name, target in pairs(DMS.KillChain.Targets) do
        if not target.destroyed then
            local alive = isTargetAlive(name)
            if alive == true then
                target.seenAlive = true
            elseif target.seenAlive then
                debugLog("Poll detected '%s' destroyed", name)
                processTargetDestruction(name)
            end
        end
    end
end

local function pollTick(_, time)
    if not DMS.KillChain.Active then
        DMS.KillChain.PollTimerId = nil
        return nil
    end
    local ok, err = pcall(pollTargets)
    if not ok then logError("KillChain.poll", err) end
    local interval = tonumber(DMS.KillChain.Config.pollInterval) or 10
    if interval <= 0 then
        DMS.KillChain.PollTimerId = nil
        return nil
    end
    return time + interval
end

--- Start kill chain system
function DMS.KillChain.start()
    if DMS.KillChain.Active then
        return
    end

    DMS.KillChain.Active = true

    if DMS.KillChain.EventHandler then
        world.removeEventHandler(DMS.KillChain.EventHandler)
    end
    DMS.KillChain.EventHandler = createEventHandler()
    world.addEventHandler(DMS.KillChain.EventHandler)

    local interval = tonumber(DMS.KillChain.Config.pollInterval) or 10
    if interval > 0 then
        DMS.KillChain.PollTimerId = timer.scheduleFunction(pollTick, nil, timer.getTime() + interval)
    end

    local count = 0
    for _ in pairs(DMS.KillChain.Targets) do count = count + 1 end
    debugLog("Started tracking %d targets (poll interval: %ss)", count, tostring(interval))
end

--- Stop kill chain system
function DMS.KillChain.stop()
    DMS.KillChain.Active = false
    if DMS.KillChain.EventHandler then
        world.removeEventHandler(DMS.KillChain.EventHandler)
        DMS.KillChain.EventHandler = nil
    end
    if DMS.KillChain.PollTimerId then
        pcall(timer.removeFunction, DMS.KillChain.PollTimerId)
        DMS.KillChain.PollTimerId = nil
    end
    debugLog("Stopped")
end

--- Register command post destruction chain
-- Destroying command post disables associated units
-- @param commandPostName string Command post unit/group name
-- @param associatedGroups table Groups that depend on command post
function DMS.KillChain.registerCommandPost(commandPostName, associatedGroups)
    DMS.KillChain.registerTarget(commandPostName, {
        DMS.KillChain.messageReaction(
            "INTEL: Enemy command post destroyed. Enemy communications disrupted!",
            15
        ),
        DMS.KillChain.cascadeReaction(associatedGroups, 5),
        DMS.KillChain.flagReaction("command_post_destroyed", 1),
    })
end

--- Register ammo depot destruction chain
-- Destroying depot weakens associated air defenses
-- @param depotName string Ammo depot name
-- @param samGroups table SAM groups that lose effectiveness
function DMS.KillChain.registerAmmoDepot(depotName, samGroups)
    DMS.KillChain.registerTarget(depotName, {
        DMS.KillChain.messageReaction(
            "INTEL: Ammunition depot destroyed. Enemy air defenses weakened!",
            15
        ),
        DMS.KillChain.flagReaction("ammo_depot_destroyed", 1),
        -- Custom reaction to reduce SAM engagement range (conceptual)
        -- Weaken SAMs: force alarm state GREEN (radars dark) on associated groups
        DMS.KillChain.customReaction(function(groups)
            for _, groupName in ipairs(groups or {}) do
                local group = Group.getByName(groupName)
                if group and objectExists(group) then
                    local controller = safeMethod(group, "getController")
                    if controller and AI and AI.Option and AI.Option.Ground then
                        pcall(controller.setOption, controller,
                            AI.Option.Ground.id.ALARM_STATE, AI.Option.Ground.val.ALARM_STATE.GREEN)
                    end
                end
            end
        end, samGroups),
    })
end

--- Register HVT elimination chain
-- @param hvtName string High Value Target name
-- @param victoryFlag string|nil Flag to set for victory condition
function DMS.KillChain.registerHVT(hvtName, victoryFlag)
    local reactions = {
        DMS.KillChain.messageReaction(
            "MISSION UPDATE: High Value Target eliminated!",
            20
        ),
    }

    if victoryFlag then
        table.insert(reactions, DMS.KillChain.flagReaction(victoryFlag, 1))
    end

    DMS.KillChain.registerTarget(hvtName, reactions)
end

--- Check if target has been destroyed
-- @param targetName string Target name
-- @return boolean True if destroyed
function DMS.KillChain.isDestroyed(targetName)
    local target = DMS.KillChain.Targets[targetName]
    return (target and target.destroyed) and true or false
end

--[[
USAGE EXAMPLE:

-- Configure
DMS.KillChain.configure({
    announceReactions = true,
    displayDuration = 15
})

-- Register targets with chain reactions
DMS.KillChain.registerTarget("Enemy-Radar", {
    DMS.KillChain.messageReaction("SEAD SUCCESS: Enemy radar destroyed!", 10),
    DMS.KillChain.spawnReaction({"QRF-Response"}, 30, "Warning: Enemy QRF responding!"),
    DMS.KillChain.flagReaction("radar_down", 1)
})

-- Complex chain: destroying power plant disables SAMs
DMS.KillChain.registerTarget("Power-Plant", {
    DMS.KillChain.messageReaction("INTEL: Power grid destroyed!", 15),
    DMS.KillChain.cascadeReaction({"SAM-Site-1", "SAM-Site-2"}, 10),
    DMS.KillChain.spawnReaction({"Repair-Convoy"}, 60, "INTEL: Enemy repair convoy dispatched")
})

-- Use convenience functions
DMS.KillChain.registerCommandPost("Enemy-HQ", {"Patrol-1", "Patrol-2", "QRF-1"})
DMS.KillChain.registerAmmoDepot("Ammo-Depot-1", {"SAM-Battery-1"})
DMS.KillChain.registerHVT("Enemy-General", "mission_complete")

-- Custom reaction
DMS.KillChain.registerTarget("Fuel-Depot", {
    DMS.KillChain.customReaction(function()
        -- Custom logic when fuel depot destroyed
        trigger.action.outText("Secondary explosions reported!", 10)
        trigger.action.explosion({x = 100000, y = 0, z = 100000}, 500)
    end)
})

-- Start system
DMS.KillChain.start()
]]

-- Export
_G.DMS = DMS
