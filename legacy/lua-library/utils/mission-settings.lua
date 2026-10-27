-- Mission Settings for DCS Missions
-- Central configuration with sensible defaults
-- Override only what you need per mission
-- Place in mission via DO SCRIPT FILE (load early, before other DMS scripts)

DMS = DMS or {}
DMS.Settings = DMS.Settings or {}

-- ============================================================
-- DEFAULT SETTINGS
-- ============================================================
-- These are the baseline defaults. Missions override via DMS.Settings.configure()

DMS.Settings.Defaults = {
    -- Coalitions
    playerCoalition = (coalition and coalition.side and coalition.side.BLUE) or 2,
    enemyCoalition = (coalition and coalition.side and coalition.side.RED) or 1,

    -- Fog of War
    fogOfWar = false,                   -- Hide enemy units from F10 map until detected
    fogOfWarRevealRange = 5000,         -- Meters - proximity reveal distance
    fogOfWarRevealOnRadar = true,       -- Reveal when radar detects
    fogOfWarRevealOnVisual = true,      -- Reveal when visual contact
    fogOfWarRevealOnDamage = true,      -- Reveal when unit takes/deals damage

    -- Spawning
    spawnHiddenByDefault = false,       -- If true, spawns use hidden when fogOfWar is on
    spawnAnnouncementsEnabled = true,   -- Show spawn notifications (debug)

    -- Difficulty
    difficultyMultiplier = 1.0,         -- 0.5 = easier, 1.5 = harder
    adaptiveDifficulty = false,         -- Adjust based on player performance

    -- Timing
    missionTimeLimit = 0,               -- 0 = no limit, otherwise seconds
    reinforcementDelay = 60,            -- Default delay for reinforcement waves

    -- Debug
    debug = false,                      -- Enable debug messages
    debugVerbose = false,               -- Extra verbose logging
    showErrorAlerts = true,             -- Show on-screen alerts when Lua errors occur
}

-- Active settings (initialized from defaults; preserved across reloads)
local _existingCurrent = DMS.Settings.Current

-- ============================================================
-- INITIALIZATION
-- ============================================================

--- Initialize settings with defaults
-- Called automatically, but can be called to reset
function DMS.Settings.init()
    DMS.Settings.Current = {}
    for key, value in pairs(DMS.Settings.Defaults) do
        DMS.Settings.Current[key] = value
    end
end

-- Initialize on load (keep any values already configured if this file is reloaded)
if type(_existingCurrent) == "table" then
    DMS.Settings.Current = _existingCurrent
    for key, value in pairs(DMS.Settings.Defaults) do
        if DMS.Settings.Current[key] == nil then
            DMS.Settings.Current[key] = value
        end
    end
else
    DMS.Settings.init()
end

-- ============================================================
-- CONFIGURATION API
-- ============================================================

--- Configure mission settings (merge with defaults)
-- Only specify settings you want to override
-- @param overrides table Settings to override
-- @usage DMS.Settings.configure({ fogOfWar = true, debug = true })
function DMS.Settings.configure(overrides)
    if type(overrides) ~= "table" then return end
    if type(DMS.Settings.Current) ~= "table" then DMS.Settings.init() end

    for key, value in pairs(overrides) do
        if DMS.Settings.Defaults[key] ~= nil then
            DMS.Settings.Current[key] = value
        else
            -- Unknown setting - log warning but still set it
            if DMS.Settings.Current.debug then
                env.info(string.format("[DMS.Settings] Warning: Unknown setting '%s'", key))
            end
            DMS.Settings.Current[key] = value
        end
    end

    -- Auto-enable spawnHiddenByDefault when fogOfWar is enabled
    if overrides.fogOfWar == true and overrides.spawnHiddenByDefault == nil then
        DMS.Settings.Current.spawnHiddenByDefault = true
    end

    if DMS.Settings.Current.debug then
        env.info("[DMS.Settings] Configuration updated")
    end
end

--- Get a setting value
-- @param key string Setting name
-- @return any Setting value (from Current, falls back to Default)
function DMS.Settings.get(key)
    local current = DMS.Settings.Current
    if type(current) == "table" and current[key] ~= nil then
        return current[key]
    end
    local defaults = DMS.Settings.Defaults
    if type(defaults) == "table" then
        return defaults[key]
    end
    return nil
end

--- Set a single setting
-- @param key string Setting name
-- @param value any Setting value
function DMS.Settings.set(key, value)
    if type(DMS.Settings.Current) ~= "table" then DMS.Settings.init() end
    DMS.Settings.Current[key] = value
end

--- Check if fog of war is enabled
-- @return boolean
function DMS.Settings.isFogOfWarEnabled()
    return DMS.Settings.get("fogOfWar") == true
end

--- Check if spawns should be hidden by default
-- @return boolean
function DMS.Settings.shouldSpawnHidden()
    return DMS.Settings.get("fogOfWar") and DMS.Settings.get("spawnHiddenByDefault")
end

--- Get effective hidden state for a spawn
-- @param explicitHidden boolean|nil Explicit hidden parameter (nil = use default)
-- @return boolean Whether to spawn hidden
function DMS.Settings.getSpawnHidden(explicitHidden)
    if explicitHidden ~= nil then
        return explicitHidden
    end
    return DMS.Settings.shouldSpawnHidden()
end

--- Reset to defaults
function DMS.Settings.reset()
    DMS.Settings.init()
end

--- Get all current settings (for debugging)
-- @return table Copy of current settings
function DMS.Settings.getAll()
    local copy = {}
    for key, value in pairs(DMS.Settings.Current or {}) do
        copy[key] = value
    end
    return copy
end

--- Print current settings (debug)
function DMS.Settings.dump()
    env.info("=== DMS Settings ===")
    for key, value in pairs(DMS.Settings.Current or {}) do
        local default = DMS.Settings.Defaults[key]
        local marker = (value ~= default) and " *" or ""
        env.info(string.format("  %s: %s%s", key, tostring(value), marker))
    end
    env.info("(* = overridden from default)")
end

-- ============================================================
-- CONVENIENCE ACCESSORS
-- ============================================================

--- Get player coalition
-- @return number Coalition side
function DMS.Settings.getPlayerCoalition()
    return DMS.Settings.get("playerCoalition")
end

--- Get enemy coalition
-- @return number Coalition side
function DMS.Settings.getEnemyCoalition()
    return DMS.Settings.get("enemyCoalition")
end

--- Check if debug mode is enabled
-- @return boolean
function DMS.Settings.isDebug()
    local ok, v = pcall(DMS.Settings.get, "debug")
    return ok and v == true
end

--[[
USAGE EXAMPLES:

-- Example 1: Simple fog of war mission
DMS.Settings.configure({
    fogOfWar = true,
})

-- Example 2: Hard difficulty with fog of war
DMS.Settings.configure({
    fogOfWar = true,
    difficultyMultiplier = 1.5,
    adaptiveDifficulty = true,
})

-- Example 3: Debug mode
DMS.Settings.configure({
    debug = true,
    debugVerbose = true,
})

-- Example 4: Red vs Blue swap
DMS.Settings.configure({
    playerCoalition = coalition.side.RED,
    enemyCoalition = coalition.side.BLUE,
})

-- Checking settings in other scripts:
if DMS.Settings.isFogOfWarEnabled() then
    -- Enable fog of war features
end

local hidden = DMS.Settings.getSpawnHidden(options.hidden)
-- Returns: explicit value if provided, otherwise default based on fogOfWar setting
]]

-- Export
_G.DMS = DMS
