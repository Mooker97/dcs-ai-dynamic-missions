-- luacheck config for the DMS Lua runtime. Target: DCS mission scripting environment (Lua 5.1).
std = "lua51"
max_line_length = 120
codes = true

exclude_files = {
    "legacy/**",
    "lua/plugins/**", -- pinned third-party (MOOSE, MIST, Skynet)
    "dist/**",
    ".venv/**",
}

-- Our globals: the runtime namespace and the generated config table.
globals = {
    "DMS",
    "DMS_CONFIG",
}

-- DCS Simulator Scripting Engine globals (read-only).
read_globals = {
    -- singletons
    "env", "timer", "trigger", "world", "coalition", "country", "land", "atmosphere",
    "missionCommands", "coord", "radio", "net", "AI", "VoiceChat",
    -- classes
    "Object", "CoalitionObject", "Unit", "Group", "StaticObject", "Airbase", "Weapon",
    "SceneryObject", "Controller", "Spot",
    -- optional plugins (only referenced behind nil checks)
    "mist", "SkynetIADS", "SKYNET", "BASE", "SPAWN", "ZONE",
}

files["lua/spec/**"] = {
    std = "+busted",
    globals = { "env", "timer", "trigger", "world", "coalition", "country", "land",
                "missionCommands", "coord", "AI", "Unit", "Group", "StaticObject", "Object" },
}

files["lua/mocks/**"] = {
    -- mocks define the DCS globals
    globals = { "env", "timer", "trigger", "world", "coalition", "country", "land", "atmosphere",
                "missionCommands", "coord", "radio", "net", "AI", "Object", "Unit", "Group",
                "StaticObject", "Airbase", "Weapon", "SceneryObject", "Controller", "Spot" },
}
