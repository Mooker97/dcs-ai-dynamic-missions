--[[
  DMS Voice Line & Flag System
  Trigger DCS flags with optional text messages or audio playback

  Features:
    - Set mission flags with descriptive logging
    - Display text messages when flags trigger
    - Optional audio playback (integrates with DMS.Audio)
    - Pre-mapped voice line libraries

  Requires:
    - None (standalone)
    - Optional: comms/audio-player.lua (for audio playback)

  Usage:
    -- Simple flag with text
    DMS.VoiceFlags.set(100, "Mission Start", "Convoy rolling out now")

    -- Register voice line library
    DMS.VoiceFlags.registerLibrary("convoy", {
        [100] = {text = "Convoy rolling out", audio = "convoy_start.wav"},
        [101] = {text = "Mission complete", audio = "convoy_victory.wav"},
    })

    -- Trigger from library
    DMS.VoiceFlags.trigger("convoy", 100)
]]

DMS = DMS or {}
DMS.VoiceFlags = {}

--------------------------------------------------------------------------------
-- State
--------------------------------------------------------------------------------

local state = {
    libraries = {},              -- Registered voice line libraries
    triggered = {},              -- Flags that have been triggered (for once-only)
}

--------------------------------------------------------------------------------
-- Configuration
--------------------------------------------------------------------------------

DMS.VoiceFlags.Config = {
    debug = false,               -- Local debug fallback (DMS.Settings.isDebug() takes priority)
    textDuration = 10,           -- Seconds to display text messages
    coalition = coalition.side.BLUE,  -- Default coalition for messages
    useAudio = false,            -- Use audio playback (requires DMS.Audio)
    textPrefix = "",             -- Prefix for text messages
}

--------------------------------------------------------------------------------
-- Utility Functions
--------------------------------------------------------------------------------

local function isDebugEnabled()
    if DMS.Settings and DMS.Settings.isDebug then
        return DMS.Settings.isDebug()
    end
    return DMS.VoiceFlags.Config.debug
end

local function tableLength(t)
    local count = 0
    if type(t) == "table" then
        for _ in pairs(t) do count = count + 1 end
    end
    return count
end

local function log(msg, level)
    level = level or "info"
    -- Warnings always logged; info only in debug mode
    if level == "warning" or isDebugEnabled() then
        local timestamp = timer.getTime and timer.getTime() or 0
        if level == "warning" then
            env.warning(string.format("[DMS.VoiceFlags %.1f] %s", timestamp, msg))
        else
            env.info(string.format("[DMS.VoiceFlags %.1f] %s", timestamp, msg))
        end
    end
end

--------------------------------------------------------------------------------
-- Core Functions
--------------------------------------------------------------------------------

--- Set a flag with optional text message and audio
-- @param flagNumber number Flag number to set
-- @param description string Description for logging
-- @param text string|nil Optional text to display to players
-- @param audioFile string|nil Optional audio file to play
-- @param options table|nil Optional: {coalition, duration, useAudio}
function DMS.VoiceFlags.set(flagNumber, description, text, audioFile, options)
    options = options or {}
    local coalition_target = options.coalition or DMS.VoiceFlags.Config.coalition
    local duration = options.duration or DMS.VoiceFlags.Config.textDuration
    local useAudio = DMS.VoiceFlags.Config.useAudio
    if options.useAudio ~= nil then useAudio = options.useAudio end

    -- Set the flag
    trigger.action.setUserFlag(flagNumber, 1)

    -- Display text message
    if text then
        local fullText = DMS.VoiceFlags.Config.textPrefix .. text
        trigger.action.outTextForCoalition(coalition_target, fullText, duration)
    end

    -- Play audio (if available)
    if audioFile and useAudio and DMS.Audio and DMS.Audio.playForCoalition then
        local ok, err = pcall(DMS.Audio.playForCoalition, coalition_target, audioFile)
        if not ok then
            log("Audio playback failed for " .. tostring(audioFile) .. ": " .. tostring(err), "warning")
        end
    end

    -- Log
    log(string.format("Flag %s set: %s", tostring(flagNumber), tostring(description)))

    -- Mark as triggered
    state.triggered[flagNumber] = true

    return true
end

--- Set flag only if not already triggered (once-only)
-- @param flagNumber number Flag number
-- @param description string Description
-- @param text string|nil Text message
-- @param audioFile string|nil Audio file
-- @param options table|nil Options
-- @return boolean True if triggered, false if already triggered
function DMS.VoiceFlags.setOnce(flagNumber, description, text, audioFile, options)
    if state.triggered[flagNumber] then
        return false
    end
    return DMS.VoiceFlags.set(flagNumber, description, text, audioFile, options)
end

--- Register a voice line library
-- @param libraryName string Library name
-- @param voiceLines table Map of flag numbers to {text, audio, description}
function DMS.VoiceFlags.registerLibrary(libraryName, voiceLines)
    state.libraries[libraryName] = voiceLines or {}
    log(string.format("Registered library '%s' with %d voice lines", tostring(libraryName), tableLength(voiceLines)))
end

--- Trigger a voice line from a library
-- @param libraryName string Library name
-- @param flagNumber number Flag number
-- @param options table|nil Optional settings
-- @return boolean True if triggered
function DMS.VoiceFlags.trigger(libraryName, flagNumber, options)
    local lib = state.libraries[libraryName]
    if not lib then
        log("ERROR: Unknown library: " .. tostring(libraryName), "warning")
        return false
    end

    local voiceLine = lib[flagNumber]
    if not voiceLine then
        log("ERROR: Unknown flag " .. tostring(flagNumber) .. " in library: " .. tostring(libraryName), "warning")
        return false
    end

    return DMS.VoiceFlags.set(
        flagNumber,
        voiceLine.description or ("Flag " .. flagNumber),
        voiceLine.text,
        voiceLine.audio,
        options
    )
end

--- Trigger once from library (prevents duplicates)
-- @param libraryName string Library name
-- @param flagNumber number Flag number
-- @param options table|nil Options
-- @return boolean True if triggered
function DMS.VoiceFlags.triggerOnce(libraryName, flagNumber, options)
    if state.triggered[flagNumber] then
        return false
    end
    return DMS.VoiceFlags.trigger(libraryName, flagNumber, options)
end

--- Check if a flag has been triggered
-- @param flagNumber number Flag number
-- @return boolean True if triggered
function DMS.VoiceFlags.hasTriggered(flagNumber)
    return state.triggered[flagNumber] == true
end

--- Reset a flag's triggered state (allow re-triggering)
-- @param flagNumber number Flag number
function DMS.VoiceFlags.reset(flagNumber)
    state.triggered[flagNumber] = nil
    log("Reset flag " .. tostring(flagNumber))
end

--- Reset all flags
function DMS.VoiceFlags.resetAll()
    state.triggered = {}
    log("Reset all flags")
end

--- Get list of all triggered flags
-- @return table Array of flag numbers
function DMS.VoiceFlags.getTriggeredFlags()
    local flags = {}
    for flagNumber, _ in pairs(state.triggered) do
        table.insert(flags, flagNumber)
    end
    table.sort(flags)
    return flags
end

--- Get statistics
-- @return table Stats
function DMS.VoiceFlags.getStats()
    local libraryCount = 0
    local voiceLineCount = 0

    for _, lib in pairs(state.libraries) do
        libraryCount = libraryCount + 1
        for _ in pairs(lib) do
            voiceLineCount = voiceLineCount + 1
        end
    end

    return {
        libraries = libraryCount,
        voiceLines = voiceLineCount,
        triggeredFlags = #DMS.VoiceFlags.getTriggeredFlags(),
        audioEnabled = (DMS.VoiceFlags.Config.useAudio and DMS.Audio ~= nil) and true or false,
    }
end

--------------------------------------------------------------------------------
-- Configuration
--------------------------------------------------------------------------------

--- Configure the system
-- @param settings table Configuration overrides
function DMS.VoiceFlags.configure(settings)
    for key, value in pairs(settings) do
        DMS.VoiceFlags.Config[key] = value
    end
end

--------------------------------------------------------------------------------
-- Preset Libraries
--------------------------------------------------------------------------------

--- Standard mission state flags
DMS.VoiceFlags.Presets = {
    MISSION_START = 100,
    MISSION_VICTORY = 101,
    MISSION_DEFEAT = 102,
}

--- Create a standard mission state library
-- @param texts table Optional custom texts {start, victory, defeat}
function DMS.VoiceFlags.createMissionStateLibrary(texts)
    texts = texts or {}

    DMS.VoiceFlags.registerLibrary("mission_state", {
        [100] = {
            description = "Mission Start",
            text = texts.start or "Mission is a go. Good hunting.",
            audio = texts.startAudio or "mission_start.wav",
        },
        [101] = {
            description = "Mission Victory",
            text = texts.victory or "Mission complete. Excellent work.",
            audio = texts.victoryAudio or "mission_victory.wav",
        },
        [102] = {
            description = "Mission Defeat",
            text = texts.defeat or "Mission failed.",
            audio = texts.defeatAudio or "mission_defeat.wav",
        },
    })
end

log("DMS.VoiceFlags loaded")

return DMS.VoiceFlags
