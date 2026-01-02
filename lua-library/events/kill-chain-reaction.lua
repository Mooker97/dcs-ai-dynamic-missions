-- Kill Chain Reaction System for DCS Missions
-- Triggers events when specific targets are destroyed
-- Requires: utils/messaging.lua
-- Place in mission via DO SCRIPT FILE

DMS = DMS or {}
DMS.KillChain = {}

-- Tracked targets and their reactions
DMS.KillChain.Targets = {}
DMS.KillChain.EventHandler = nil
DMS.KillChain.Active = false

-- Configuration
DMS.KillChain.Config = {
    playerCoalition = coalition.side.BLUE,
    announceReactions = true,
    displayDuration = 10,
}

--- Configure kill chain system
-- @param settings table Configuration overrides
function DMS.KillChain.configure(settings)
    for key, value in pairs(settings) do
        DMS.KillChain.Config[key] = value
    end
end

--- Register a target with chain reactions
-- @param targetName string Unit or group name to track
-- @param reactions table Reaction definitions
function DMS.KillChain.registerTarget(targetName, reactions)
    DMS.KillChain.Targets[targetName] = {
        name = targetName,
        destroyed = false,
        reactions = reactions,
    }
end

--- Create a spawn reaction
-- @param groupNames table Groups to activate
-- @param delay number|nil Delay before activation
-- @param message string|nil Message to display
-- @return table Reaction definition
function DMS.KillChain.spawnReaction(groupNames, delay, message)
    return {
        type = "spawn",
        groups = groupNames,
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
        groups = groupNames,
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
local function executeReaction(reaction)
    if reaction.type == "spawn" then
        -- Activate groups
        for _, groupName in ipairs(reaction.groups) do
            local group = Group.getByName(groupName)
            if group then
                trigger.action.activateGroup(group)
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
        trigger.action.setUserFlag(reaction.flag, reaction.value)

    elseif reaction.type == "message" then
        trigger.action.outTextForCoalition(
            DMS.KillChain.Config.playerCoalition,
            reaction.text,
            reaction.duration,
            true
        )

    elseif reaction.type == "cascade" then
        for _, groupName in ipairs(reaction.groups) do
            local group = Group.getByName(groupName)
            if group and group:isExist() then
                group:destroy()
            end
        end

    elseif reaction.type == "custom" then
        if type(reaction.func) == "function" then
            reaction.func(reaction.args)
        end
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

    -- Execute all reactions
    for _, reaction in ipairs(target.reactions) do
        if reaction.delay and reaction.delay > 0 then
            timer.scheduleFunction(function()
                executeReaction(reaction)
                return nil
            end, nil, timer.getTime() + reaction.delay)
        else
            executeReaction(reaction)
        end
    end
end

--- Create event handler
local function createEventHandler()
    local handler = {}

    function handler:onEvent(event)
        if not DMS.KillChain.Active then
            return
        end

        -- Handle death events
        if event.id == world.event.S_EVENT_DEAD or
           event.id == world.event.S_EVENT_CRASH or
           event.id == world.event.S_EVENT_PILOT_DEAD then

            local target = event.initiator
            if target then
                -- Check unit name
                local unitName = target:getName()
                if unitName and DMS.KillChain.Targets[unitName] then
                    processTargetDestruction(unitName)
                end

                -- Check group name
                local group = target:getGroup()
                if group then
                    local groupName = group:getName()
                    if groupName and DMS.KillChain.Targets[groupName] then
                        -- Check if entire group is destroyed
                        local units = group:getUnits()
                        local allDead = true
                        if units then
                            for _, unit in ipairs(units) do
                                if unit:isExist() and unit:getLife() >= 1 then
                                    allDead = false
                                    break
                                end
                            end
                        end

                        if allDead then
                            processTargetDestruction(groupName)
                        end
                    end
                end
            end
        end
    end

    return handler
end

--- Start kill chain system
function DMS.KillChain.start()
    if DMS.KillChain.Active then
        return
    end

    DMS.KillChain.Active = true
    DMS.KillChain.EventHandler = createEventHandler()
    world.addEventHandler(DMS.KillChain.EventHandler)
end

--- Stop kill chain system
function DMS.KillChain.stop()
    DMS.KillChain.Active = false
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
        DMS.KillChain.customReaction(function(groups)
            -- In reality, you'd modify SAM behavior here
            -- This is a placeholder for mission-specific logic
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
    return target and target.destroyed
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
