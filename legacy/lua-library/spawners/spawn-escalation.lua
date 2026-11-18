-- Escalation Wave Spawning for DCS Missions
-- Progressive difficulty with timed waves
-- Requires: spawners/spawn-core.lua
-- Place in mission via DO SCRIPT FILE

DMS = DMS or {}
DMS.Escalation = {}

-- Wave definitions
DMS.Escalation.Waves = {}
DMS.Escalation.CurrentWave = 0
DMS.Escalation.Active = false
DMS.Escalation.TimerId = nil

-- Configuration
DMS.Escalation.Config = {
    timeBetweenWaves = 300,     -- 5 minutes default
    announceWaves = true,       -- Show wave messages
    autoStart = false,          -- Start automatically
    startDelay = 60,            -- Delay before first wave
    loopWaves = false,          -- Restart from wave 1 after last
}

--- Define a wave of enemies
-- @param waveNumber number Wave number (1, 2, 3...)
-- @param groups table Array of group names to spawn
-- @param spawnChances table|nil Per-group spawn chances {group=chance}
-- @param message string|nil Announcement message
-- @param hidden boolean|nil Fog of war override for this wave (nil = settings default)
function DMS.Escalation.defineWave(waveNumber, groups, spawnChances, message, hidden)
    DMS.Escalation.Waves[waveNumber] = {
        hidden = hidden,
        number = waveNumber,
        groups = groups,
        spawnChances = spawnChances or {},
        message = message,
        spawned = false
    }
end

--- Configure escalation settings
-- @param settings table Configuration overrides
function DMS.Escalation.configure(settings)
    for key, value in pairs(settings) do
        DMS.Escalation.Config[key] = value
    end
end

--- Spawn a specific wave
-- @param waveNumber number Wave to spawn
-- @return number Count of groups spawned
function DMS.Escalation.spawnWave(waveNumber)
    local wave = DMS.Escalation.Waves[waveNumber]
    if not wave then
        return 0
    end

    local spawned = 0

    local Core = DMS.SpawnCore
    if not Core then
        env.error("[Escalation] spawners/spawn-core.lua is not loaded")
        return 0
    end

    for _, groupName in ipairs(wave.groups) do
        local chance = wave.spawnChances[groupName] or 100
        if Core.rollAndActivate(groupName, chance, {hidden = wave.hidden, prefix = "Escalation"}) then
            spawned = spawned + 1
        end
    end

    Core.log("Escalation", "Wave %d spawned %d of %d groups", waveNumber, spawned, #wave.groups)

    wave.spawned = true
    DMS.Escalation.CurrentWave = waveNumber

    -- Announce wave
    if DMS.Escalation.Config.announceWaves then
        local msg = wave.message or string.format("Wave %d incoming!", waveNumber)
        trigger.action.outText(msg, 10, true)
    end

    return spawned
end

--- Internal: Process next wave (internal, wrapped with error handler)
local function processNextWaveInternal(_, time)
    if not DMS.Escalation.Active then
        DMS.Escalation.TimerId = nil
        return nil
    end
    local nextWave = DMS.Escalation.CurrentWave + 1

    -- Check if wave exists
    if not DMS.Escalation.Waves[nextWave] then
        if DMS.Escalation.Config.loopWaves and DMS.Escalation.Waves[1] then
            -- Reset for looping
            nextWave = 1
            for _, wave in pairs(DMS.Escalation.Waves) do
                wave.spawned = false
            end
        else
            -- End escalation
            DMS.Escalation.Active = false
            if DMS.Escalation.Config.announceWaves then
                trigger.action.outText("All waves complete.", 10, true)
            end
            return nil
        end
    end

    DMS.Escalation.spawnWave(nextWave)

    -- Schedule next wave
    return time + DMS.Escalation.Config.timeBetweenWaves
end

--- Process next wave with error handling
local function processNextWave(args, time)
    local success, result = pcall(processNextWaveInternal, args, time)
    if not success then
        local logged = DMS.Error and DMS.Error.log and pcall(DMS.Error.log, "Escalation.processNextWave", result)
        if not logged then
            env.error("[DMS LUA ERROR] Escalation.processNextWave: " .. tostring(result))
        end
        -- Continue running despite error (unless stopped)
        if not DMS.Escalation.Active then return nil end
        return time + (DMS.Escalation.Config.timeBetweenWaves or 300)
    end
    return result
end

--- Start the escalation sequence
function DMS.Escalation.start()
    if DMS.Escalation.Active then
        return
    end

    DMS.Escalation.Active = true
    DMS.Escalation.CurrentWave = 0

    -- Schedule first wave
    DMS.Escalation.TimerId = timer.scheduleFunction(
        processNextWave,
        nil,
        timer.getTime() + DMS.Escalation.Config.startDelay
    )
end

--- Stop the escalation
function DMS.Escalation.stop()
    DMS.Escalation.Active = false
    if DMS.Escalation.TimerId then
        timer.removeFunction(DMS.Escalation.TimerId)
        DMS.Escalation.TimerId = nil
    end
end

--- Skip to specific wave
-- @param waveNumber number Wave to jump to
function DMS.Escalation.skipTo(waveNumber)
    DMS.Escalation.CurrentWave = waveNumber - 1
    DMS.Escalation.spawnWave(waveNumber)
end

--- Trigger next wave immediately
function DMS.Escalation.triggerNext()
    local nextWave = DMS.Escalation.CurrentWave + 1
    if DMS.Escalation.Waves[nextWave] then
        DMS.Escalation.spawnWave(nextWave)
    end
end

--- Get current wave info
-- @return table {current, total, active}
function DMS.Escalation.getStatus()
    local totalWaves = 0
    for _ in pairs(DMS.Escalation.Waves) do
        totalWaves = totalWaves + 1
    end

    return {
        current = DMS.Escalation.CurrentWave,
        total = totalWaves,
        active = DMS.Escalation.Active
    }
end

--- Reset escalation state
function DMS.Escalation.reset()
    DMS.Escalation.stop()
    DMS.Escalation.CurrentWave = 0
    for _, wave in pairs(DMS.Escalation.Waves) do
        wave.spawned = false
    end
end

--[[
USAGE EXAMPLE:

-- Configure timing
DMS.Escalation.configure({
    timeBetweenWaves = 180,  -- 3 minutes
    announceWaves = true,
    startDelay = 30
})

-- Define waves (easy to hard)
DMS.Escalation.defineWave(1,
    {"Light-1", "Light-2"},
    {["Light-1"] = 100, ["Light-2"] = 75},
    "Light enemy patrol spotted!"
)

DMS.Escalation.defineWave(2,
    {"Medium-1", "Medium-2", "AAA-1"},
    {["AAA-1"] = 50},
    "Enemy reinforcements arriving!"
)

DMS.Escalation.defineWave(3,
    {"Heavy-1", "SAM-1", "Armor-1"},
    nil,
    "WARNING: Heavy enemy forces inbound!"
)

-- Start escalation
DMS.Escalation.start()

-- Or trigger waves manually
-- DMS.Escalation.triggerNext()
]]

-- Export
_G.DMS = DMS
