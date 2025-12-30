-- core/event_handler.lua
-- Dynamic Mission System - Event Handler

DynamicMission = DynamicMission or {}
DynamicMission.EventHandler = {}

---
-- Main event dispatcher
-- Called by DCS when mission events occur
-- @param event DCS event data
---
function DynamicMission.EventHandler:onEvent(event)
    if not DynamicMission.state.initialized then
        return
    end

    if event.id == world.event.S_EVENT_BIRTH then
        self:handleBirth(event)
    elseif event.id == world.event.S_EVENT_DEAD then
        self:handleDeath(event)
    elseif event.id == world.event.S_EVENT_TAKEOFF then
        self:handleTakeoff(event)
    elseif event.id == world.event.S_EVENT_CRASH then
        self:handleCrash(event)
    elseif event.id == world.event.S_EVENT_EJECTION then
        self:handleEjection(event)
    elseif event.id == world.event.S_EVENT_PLAYER_ENTER_UNIT then
        self:handlePlayerEnterUnit(event)
    end
end

---
-- Handle unit birth (spawn) events
-- @param event Event data
---
function DynamicMission.EventHandler:handleBirth(event)
    local unit = event.initiator
    if not unit then return end

    -- Track player aircraft
    if unit:getPlayerName() then
        DynamicMission.state.player_stats.current_aircraft = unit
        DynamicMission.log(string.format("Player entered: %s", unit:getTypeName()), "INFO")
    end
end

---
-- Handle unit death events
-- @param event Event data
---
function DynamicMission.EventHandler:handleDeath(event)
    local unit = event.initiator
    if not unit then return end

    local unit_name = unit:getName()
    local coalition_id = unit:getCoalition()

    -- Check if player died
    if unit:getPlayerName() then
        DynamicMission.state.player_stats.deaths = DynamicMission.state.player_stats.deaths + 1
        DynamicMission.log("Player died", "INFO")

        -- Update adaptive difficulty
        if DynamicMission.config.adaptive and DynamicMission.config.adaptive.enabled then
            DynamicMission.AdaptiveDifficulty.update()
        end
    end

    -- Check if enemy died (player kill)
    if coalition_id ~= coalition.side.BLUE then
        DynamicMission.state.player_stats.kills = DynamicMission.state.player_stats.kills + 1
        DynamicMission.log(string.format("Enemy destroyed: %s (Total kills: %d)",
            unit_name, DynamicMission.state.player_stats.kills), "INFO")

        -- Update adaptive difficulty
        if DynamicMission.config.adaptive and DynamicMission.config.adaptive.enabled then
            DynamicMission.AdaptiveDifficulty.update()
        end
    end

    -- Check for reinforcement triggers
    if DynamicMission.config.events then
        DynamicMission.Reinforcements.checkTriggers(event)
    end
end

---
-- Handle aircraft takeoff events
-- @param event Event data
---
function DynamicMission.EventHandler:handleTakeoff(event)
    local unit = event.initiator
    if not unit then return end

    -- Log player takeoff
    if unit:getPlayerName() then
        DynamicMission.log("Player airborne", "INFO")
    end
end

---
-- Handle crash events
-- @param event Event data
---
function DynamicMission.EventHandler:handleCrash(event)
    local unit = event.initiator
    if not unit then return end

    -- Log player crash
    if unit:getPlayerName() then
        DynamicMission.log("Player crashed", "WARNING")
    end
end

---
-- Handle ejection events
-- @param event Event data
---
function DynamicMission.EventHandler:handleEjection(event)
    local unit = event.initiator
    if not unit then return end

    -- Log player ejection
    if unit:getPlayerName() then
        DynamicMission.log("Player ejected", "INFO")

        -- Trigger rescue mission if configured
        -- (Future implementation)
    end
end

---
-- Handle player entering unit
-- @param event Event data
---
function DynamicMission.EventHandler:handlePlayerEnterUnit(event)
    local unit = event.initiator
    if not unit then return end

    DynamicMission.state.player_stats.current_aircraft = unit
    DynamicMission.log(string.format("Player entered: %s", unit:getTypeName()), "INFO")
end
