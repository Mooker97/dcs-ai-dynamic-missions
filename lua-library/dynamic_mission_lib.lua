-- Dynamic Mission Library
-- Generated: 2025-12-30 17:50:03
-- DO NOT EDIT - Generated from modules
-- Source: lua-library/ modules


-- ============================================
-- Module: core/init.lua
-- ============================================

-- core/init.lua
-- Dynamic Mission System - Initialization and State Management

DynamicMission = DynamicMission or {}

-- Global state
DynamicMission.state = {
    initialized = false,
    mission_start_time = 0,
    spawned_groups = {},
    player_stats = {
        kills = 0,
        deaths = 0,
        current_aircraft = nil
    },
    spawn_counters = {},
    difficulty_modifier = 1.0,
    active_timers = {}
}

-- Configuration (set by init)
DynamicMission.config = {}

---
-- Initialize the dynamic mission system
-- @param config Mission configuration table
-- @return bool Success status
---
function DynamicMission.init(config)
    DynamicMission.log("Initializing Dynamic Mission System", "INFO")

    -- Store configuration
    DynamicMission.config = config or {}

    -- Set mission start time
    DynamicMission.state.mission_start_time = timer.getTime()

    -- Initialize seed if provided
    if config.settings and config.settings.seed then
        math.randomseed(config.settings.seed)
    else
        math.randomseed(os.time())
    end

    -- Register event handlers
    world.addEventHandler(DynamicMission.EventHandler)

    -- Schedule initial spawns
    if config.spawns then
        for _, spawn_config in ipairs(config.spawns) do
            DynamicMission.scheduleSpawn(spawn_config)
        end
    end

    DynamicMission.state.initialized = true
    DynamicMission.log("Dynamic Mission System initialized successfully", "INFO")
    DynamicMission.log(string.format("Mission: %s | Type: %s | Difficulty: %s",
        config.mission_name or "Unknown",
        config.mission_type or "Unknown",
        config.difficulty or "Unknown"), "INFO")

    return true
end

---
-- Schedule a spawn based on configuration
-- @param spawn_config Spawn configuration table
---
function DynamicMission.scheduleSpawn(spawn_config)
    if not spawn_config.enabled then
        return
    end

    local template = spawn_config.template
    local schedule = spawn_config.schedule or {}
    local conditions = spawn_config.conditions or {}

    -- Calculate initial delay
    local base_delay = template.spawn.timing.initial_delay or 0
    local random_offset = template.spawn.timing.random_offset or 0
    local delay = DynamicMission.TimingRandomizer.getSpawnDelay(base_delay, random_offset)

    -- Schedule spawn
    timer.scheduleFunction(function()
        -- Check conditions
        if conditions.player_takeoff and not DynamicMission.state.player_stats.current_aircraft then
            return timer.getTime() + 60  -- Check again in 60 seconds
        end

        -- Spawn unit
        DynamicMission.log(string.format("Spawning: %s", template.name), "INFO")

        local spawner = DynamicMission.AirSpawner
        if template.category == "ground" then
            spawner = DynamicMission.GroundSpawner
        elseif template.category == "naval" then
            spawner = DynamicMission.NavalSpawner
        end

        spawner.spawn(template)

        -- Schedule repeat if configured
        if schedule.repeat_interval then
            local count = DynamicMission.state.spawn_counters[spawn_config.id] or 0
            if not schedule.max_spawns or count < schedule.max_spawns then
                DynamicMission.state.spawn_counters[spawn_config.id] = count + 1
                return timer.getTime() + schedule.repeat_interval
            end
        end

        return nil  -- Don't reschedule
    end, nil, timer.getTime() + delay)
end

---
-- Log message to DCS.log
-- @param message Message text
-- @param level Log level ("INFO", "WARNING", "ERROR")
---
function DynamicMission.log(message, level)
    level = level or "INFO"
    local prefix = "[DynamicMission]"
    env.info(string.format("%s [%s] %s", prefix, level, message))
end

---
-- Get current mission time
-- @return number Seconds since mission start
---
function DynamicMission.getTime()
    return timer.getTime() - DynamicMission.state.mission_start_time
end

---
-- Generate random number in range
-- @param min Minimum value
-- @param max Maximum value
-- @return number Random value
---
function DynamicMission.random(min, max)
    return min + (max - min) * math.random()
end


-- ============================================
-- Module: core/utils.lua
-- ============================================

-- core/utils.lua
-- Dynamic Mission System - Utility Functions

DynamicMission = DynamicMission or {}

---
-- Calculate distance between two points
-- @param point1 First point {x, y} or {x, y, z}
-- @param point2 Second point {x, y} or {x, y, z}
-- @return number Distance in meters
---
function DynamicMission.getDistance(point1, point2)
    local dx = point2.x - point1.x
    local dy = point2.y - point1.y

    if point1.z and point2.z then
        local dz = point2.z - point1.z
        return math.sqrt(dx*dx + dy*dy + dz*dz)
    else
        return math.sqrt(dx*dx + dy*dy)
    end
end

---
-- Calculate heading from one point to another
-- @param from_point Starting point {x, y}
-- @param to_point Target point {x, y}
-- @return number Heading in radians
---
function DynamicMission.getHeading(from_point, to_point)
    local dx = to_point.x - from_point.x
    local dy = to_point.y - from_point.y
    return math.atan2(dx, dy)
end

---
-- Calculate position offset by distance and heading
-- @param point Starting point {x, y}
-- @param distance Distance in meters
-- @param heading Heading in radians
-- @return table New position {x, y}
---
function DynamicMission.offsetPosition(point, distance, heading)
    return {
        x = point.x + distance * math.sin(heading),
        y = point.y + distance * math.cos(heading)
    }
end

---
-- Convert degrees to radians
-- @param degrees Angle in degrees
-- @return number Angle in radians
---
function DynamicMission.degToRad(degrees)
    return degrees * math.pi / 180
end

---
-- Convert radians to degrees
-- @param radians Angle in radians
-- @return number Angle in degrees
---
function DynamicMission.radToDeg(radians)
    return radians * 180 / math.pi
end


-- ============================================
-- Module: core/event_handler.lua
-- ============================================

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

