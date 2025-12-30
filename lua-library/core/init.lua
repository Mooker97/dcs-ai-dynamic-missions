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
