--[[
  DMS Audio Player
  Play WAV/OGG audio files from mission assets

  Audio files must be embedded in the .miz and live in l10n/DEFAULT/ (flat,
  no sub-folders). They are played with:
    trigger.action.outSound("l10n/DEFAULT/<file>.ogg")
    trigger.action.outSoundForCoalition(side, "l10n/DEFAULT/<file>.ogg")
    trigger.action.outSoundForGroup(groupId, "l10n/DEFAULT/<file>.ogg")

  IMPORTANT: DCS only packs a sound file into the .miz (and keeps it in the
  mission resource list / mapResource) if the Mission Editor references it.
  Add every sound file ONCE via the ME, e.g. a dummy trigger
  (TIME MORE 99999 -> SOUND TO ALL <file>) so it is kept in l10n/DEFAULT/.
  File names passed to this module are resolved to "l10n/DEFAULT/<file>";
  any path components (e.g. "radio_click.wav") are stripped because the ME
  stores resources flat. Prefer .ogg; .wav also works.

  Supports queuing, delays, and targeted playback (coalition/group/unit)

  SOURCE AUDIO FILES:
    Project audio assets are located in:
    DMS/mission assets/audio/

    Available files:
      generic/mission start/
        - mission is a go.wav
        - stay sharp.wav
        - Weapos free.wav
        - good hunting.wav
      generic/mission complete/
        - Obj complete.wav
        - Mission Success.wav
      generic/ground troops/
        - Good Kill.wav
        - Good Kill Keep em coming.wav
        - Keep em coming.wav
      missions/Dawn Scout/
        - Mission Start.wav
        - Clear To Land.wav

    Add these to the mission via the ME (see note above) so they end up in
    the .miz file's l10n/DEFAULT/ folder.

  Usage:
    DMS.Audio.configure({ basePath = "l10n/DEFAULT/" })
    DMS.Audio.play("warning_siren.wav")
    DMS.Audio.playForCoalition(coalition.side.BLUE, "briefing.ogg")
    DMS.Audio.queue("sound1.wav", "sound2.wav", "sound3.wav")
]]

DMS = DMS or {}
DMS.Audio = {}

--------------------------------------------------------------------------------
-- Configuration
--------------------------------------------------------------------------------

local config = {
  basePath = "l10n/DEFAULT/",    -- Resource path inside the .miz (DCS default)
  defaultDelay = 0,              -- Default delay before playing (seconds)
  queueGap = 0.5,                -- Gap between queued sounds (seconds)
  logPlayback = true,            -- Log audio playback events
  enabled = true,                -- Master enable/disable
}

local state = {
  queue = {},                    -- Sound queue
  queueIndex = 1,                -- Current position in queue
  isProcessingQueue = false,     -- Queue processing flag
  playCount = 0,                 -- Total sounds played
  lastPlayed = nil,              -- Last sound filename
  lastPlayTime = 0,              -- Time of last playback
}

-- Registered sound libraries (named collections)
local libraries = {}

--------------------------------------------------------------------------------
-- Utility Functions
--------------------------------------------------------------------------------

local function log(msg)
  if config.logPlayback then
    local timestamp = timer.getTime and timer.getTime() or 0
    env.info(string.format("[DMS.Audio %.1f] %s", timestamp, msg))
  end
end

local function debugLog(fmt, ...)
  if DMS.Settings and DMS.Settings.isDebug and DMS.Settings.isDebug() then
    env.info(string.format("[DMS.Audio] " .. fmt, ...))
  end
end

local function tableLength(t)
  local n = 0
  if type(t) == "table" then
    for _ in pairs(t) do n = n + 1 end
  end
  return n
end

--- Schedule a function safely (pcall-guarded, one-shot)
local function safeSchedule(fn, delay, name)
  return timer.scheduleFunction(function()
    local ok, err = pcall(fn)
    if not ok then
      env.error("[DMS.Audio] " .. (name or "scheduled") .. " failed: " .. tostring(err))
    end
    return nil
  end, nil, timer.getTime() + (delay or 0))
end

local function getFullPath(filename)
  filename = tostring(filename)
  -- Already a full resource path
  if filename:match("^l10n/") then
    return filename
  end
  -- ME stores resources flat in l10n/DEFAULT/: strip any folder prefix
  local base = filename:match("([^/\\]+)$") or filename
  return config.basePath .. base
end

local function validateFile(filename)
  -- Check file extension
  local ext = filename:match("%.(%w+)$")
  if ext then
    ext = ext:lower()
    if ext ~= "wav" and ext ~= "ogg" then
      log("WARNING: Unsupported audio format: " .. ext .. " (use .wav or .ogg)")
      return false
    end
  else
    log("WARNING: No file extension on: " .. filename)
    return false
  end
  return true
end

--------------------------------------------------------------------------------
-- Core Playback Functions
--------------------------------------------------------------------------------

--- Play sound for all players
-- @param filename Sound file name (relative to basePath)
-- @param delay Optional delay in seconds before playing
function DMS.Audio.play(filename, delay)
  if not config.enabled then return false end
  if not filename then
    log("ERROR: No filename provided")
    return false
  end

  local fullPath = getFullPath(filename)
  validateFile(fullPath)

  local function doPlay()
    trigger.action.outSound(fullPath)
    state.playCount = state.playCount + 1
    state.lastPlayed = fullPath
    state.lastPlayTime = timer.getTime()
    log("Playing: " .. fullPath)
  end

  if delay and delay > 0 then
    safeSchedule(doPlay, delay, "play")
  else
    local ok, err = pcall(doPlay)
    if not ok then log("ERROR: playback failed: " .. tostring(err)) return false end
  end

  return true
end

--- Play sound for a specific coalition
-- @param side Coalition side (coalition.side.BLUE/RED/NEUTRAL)
-- @param filename Sound file name
-- @param delay Optional delay in seconds
function DMS.Audio.playForCoalition(side, filename, delay)
  if not config.enabled then return false end
  if not filename or not side then
    log("ERROR: Missing coalition or filename")
    return false
  end

  local fullPath = getFullPath(filename)
  validateFile(fullPath)

  local function doPlay()
    trigger.action.outSoundForCoalition(side, fullPath)
    state.playCount = state.playCount + 1
    state.lastPlayed = fullPath
    state.lastPlayTime = timer.getTime()
    local sideName = side == coalition.side.BLUE and "BLUE" or
                     side == coalition.side.RED and "RED" or "NEUTRAL"
    log("Playing for " .. sideName .. ": " .. fullPath)
  end

  if delay and delay > 0 then
    safeSchedule(doPlay, delay, "play")
  else
    local ok, err = pcall(doPlay)
    if not ok then log("ERROR: playback failed: " .. tostring(err)) return false end
  end

  return true
end

--- Play sound for a specific group
-- @param groupId Group ID number
-- @param filename Sound file name
-- @param delay Optional delay in seconds
function DMS.Audio.playForGroup(groupId, filename, delay)
  if not config.enabled then return false end
  if not filename or not groupId then
    log("ERROR: Missing groupId or filename")
    return false
  end

  local fullPath = getFullPath(filename)
  validateFile(fullPath)

  local function doPlay()
    trigger.action.outSoundForGroup(groupId, fullPath)
    state.playCount = state.playCount + 1
    state.lastPlayed = fullPath
    state.lastPlayTime = timer.getTime()
    log("Playing for group " .. groupId .. ": " .. fullPath)
  end

  if delay and delay > 0 then
    safeSchedule(doPlay, delay, "play")
  else
    local ok, err = pcall(doPlay)
    if not ok then log("ERROR: playback failed: " .. tostring(err)) return false end
  end

  return true
end

--- Play sound for a specific unit
-- @param unitId Unit ID number
-- @param filename Sound file name
-- @param delay Optional delay in seconds
function DMS.Audio.playForUnit(unitId, filename, delay)
  if not config.enabled then return false end
  if not filename or not unitId then
    log("ERROR: Missing unitId or filename")
    return false
  end

  local fullPath = getFullPath(filename)
  validateFile(fullPath)

  local function doPlay()
    trigger.action.outSoundForUnit(unitId, fullPath)
    state.playCount = state.playCount + 1
    state.lastPlayed = fullPath
    state.lastPlayTime = timer.getTime()
    log("Playing for unit " .. unitId .. ": " .. fullPath)
  end

  if delay and delay > 0 then
    safeSchedule(doPlay, delay, "play")
  else
    local ok, err = pcall(doPlay)
    if not ok then log("ERROR: playback failed: " .. tostring(err)) return false end
  end

  return true
end

--- Play sound for a specific country
-- @param countryId Country ID (country.id.USA, country.id.RUSSIA, etc.)
-- @param filename Sound file name
-- @param delay Optional delay in seconds
function DMS.Audio.playForCountry(countryId, filename, delay)
  if not config.enabled then return false end
  if not filename or not countryId then
    log("ERROR: Missing countryId or filename")
    return false
  end

  local fullPath = getFullPath(filename)
  validateFile(fullPath)

  local function doPlay()
    trigger.action.outSoundForCountry(countryId, fullPath)
    state.playCount = state.playCount + 1
    state.lastPlayed = fullPath
    state.lastPlayTime = timer.getTime()
    log("Playing for country " .. countryId .. ": " .. fullPath)
  end

  if delay and delay > 0 then
    safeSchedule(doPlay, delay, "play")
  else
    local ok, err = pcall(doPlay)
    if not ok then log("ERROR: playback failed: " .. tostring(err)) return false end
  end

  return true
end

--------------------------------------------------------------------------------
-- Queue System
--------------------------------------------------------------------------------

--- Queue multiple sounds to play in sequence
-- @param ... Variable number of filenames
function DMS.Audio.queue(...)
  local sounds = {...}
  for _, filename in ipairs(sounds) do
    table.insert(state.queue, {
      filename = filename,
      target = "all",
    })
  end
  log("Queued " .. #sounds .. " sounds")

  if not state.isProcessingQueue then
    DMS.Audio.processQueue()
  end
end

--- Queue sounds for a specific coalition
-- @param side Coalition side
-- @param ... Variable number of filenames
function DMS.Audio.queueForCoalition(side, ...)
  local sounds = {...}
  for _, filename in ipairs(sounds) do
    table.insert(state.queue, {
      filename = filename,
      target = "coalition",
      side = side,
    })
  end
  log("Queued " .. #sounds .. " sounds for coalition")

  if not state.isProcessingQueue then
    DMS.Audio.processQueue()
  end
end

--- Process the sound queue
function DMS.Audio.processQueue()
  if #state.queue == 0 then
    state.isProcessingQueue = false
    log("Queue complete")
    return
  end

  state.isProcessingQueue = true
  local item = table.remove(state.queue, 1)

  -- Queued items may carry their own gap (radio effect)
  if item.target == "all" then
    DMS.Audio.play(item.filename)
  elseif item.target == "coalition" then
    DMS.Audio.playForCoalition(item.side, item.filename)
  elseif item.target == "group" then
    DMS.Audio.playForGroup(item.groupId, item.filename)
  elseif item.target == "unit" then
    DMS.Audio.playForUnit(item.unitId, item.filename)
  end

  -- Schedule next sound
  safeSchedule(function()
    DMS.Audio.processQueue()
  end, config.queueGap, "processQueue")
end

--- Clear the sound queue
function DMS.Audio.clearQueue()
  state.queue = {}
  state.isProcessingQueue = false
  log("Queue cleared")
end

--------------------------------------------------------------------------------
-- Sound Libraries
--------------------------------------------------------------------------------

--- Register a named sound library
-- @param name Library name
-- @param sounds Table of sound names to filenames
function DMS.Audio.registerLibrary(name, sounds)
  libraries[name] = sounds
  log("Registered library: " .. name .. " with " .. tableLength(sounds) .. " sounds")
end

--- Play a sound from a library
-- @param libraryName Library name
-- @param soundName Sound name within library
-- @param delay Optional delay
function DMS.Audio.playFromLibrary(libraryName, soundName, delay)
  local lib = libraries[libraryName]
  if not lib then
    log("ERROR: Unknown library: " .. tostring(libraryName))
    return false
  end

  local filename = lib[soundName]
  if not filename then
    log("ERROR: Unknown sound '" .. tostring(soundName) .. "' in library: " .. tostring(libraryName))
    return false
  end

  return DMS.Audio.play(filename, delay)
end

--- Play random sound from a library
-- @param libraryName Library name
-- @param delay Optional delay
function DMS.Audio.playRandomFromLibrary(libraryName, delay)
  local lib = libraries[libraryName]
  if not lib then
    log("ERROR: Unknown library: " .. libraryName)
    return false
  end

  -- Get all sound names
  local names = {}
  for name, _ in pairs(lib) do
    table.insert(names, name)
  end

  if #names == 0 then
    log("ERROR: Library is empty: " .. libraryName)
    return false
  end

  local randomName = names[math.random(#names)]
  return DMS.Audio.playFromLibrary(libraryName, randomName, delay)
end

--------------------------------------------------------------------------------
-- Preset Sound Categories
--------------------------------------------------------------------------------

-- Common mission sounds (override with actual filenames; each file must be
-- added to the mission via the ME so it exists in l10n/DEFAULT/)
DMS.Audio.Presets = {
  -- Alerts
  ALERT_WARNING = "alerts_warning.wav",
  ALERT_CRITICAL = "alerts_critical.wav",
  ALERT_ALARM = "alerts_alarm.wav",
  ALERT_INCOMING = "alerts_incoming.wav",

  -- Mission Events
  MISSION_START = "mission_start.wav",
  MISSION_COMPLETE = "mission_complete.wav",
  MISSION_FAILED = "mission_failed.wav",
  OBJECTIVE_COMPLETE = "mission_objective_complete.wav",

  -- Radio
  RADIO_STATIC = "radio_static.wav",
  RADIO_CLICK_ON = "radio_click_on.wav",
  RADIO_CLICK_OFF = "radio_click_off.wav",
  RADIO_BEEP = "radio_beep.wav",

  -- Ambient
  AMBIENT_WIND = "ambient_wind.ogg",
  AMBIENT_RAIN = "ambient_rain.ogg",
  AMBIENT_THUNDER = "ambient_thunder.wav",

  -- UI
  UI_SELECT = "ui_select.wav",
  UI_CONFIRM = "ui_confirm.wav",
  UI_CANCEL = "ui_cancel.wav",
}

--- Play a preset sound
-- @param presetName Name from DMS.Audio.Presets
-- @param delay Optional delay
function DMS.Audio.playPreset(presetName, delay)
  local filename = DMS.Audio.Presets[presetName]
  if not filename then
    log("ERROR: Unknown preset: " .. tostring(presetName))
    return false
  end
  return DMS.Audio.play(filename, delay)
end

--------------------------------------------------------------------------------
-- Radio Simulation
--------------------------------------------------------------------------------

--- Play sound with radio effect (click on, sound, click off)
-- @param filename Sound file
-- @param options { coalition, group, unit, delay, duration }
function DMS.Audio.playWithRadioEffect(filename, options)
  options = options or {}
  local delay = options.delay or 0

  local playFunc
  if options.coalition then
    playFunc = function(f) DMS.Audio.playForCoalition(options.coalition, f) end
  elseif options.group then
    playFunc = function(f) DMS.Audio.playForGroup(options.group, f) end
  elseif options.unit then
    playFunc = function(f) DMS.Audio.playForUnit(options.unit, f) end
  else
    playFunc = function(f) DMS.Audio.play(f) end
  end

  local duration = options.duration or 5.0

  -- Schedule: click on -> sound -> click off
  safeSchedule(function()
    playFunc(DMS.Audio.Presets.RADIO_CLICK_ON or "radio_click_on.wav")
  end, delay, "radioClickOn")

  safeSchedule(function()
    playFunc(filename)
  end, delay + 0.3, "radioSound")

  -- Note: Click off timing depends on actual sound duration (options.duration)
  safeSchedule(function()
    playFunc(DMS.Audio.Presets.RADIO_CLICK_OFF or "radio_click_off.wav")
  end, delay + 0.3 + duration, "radioClickOff")

  log("Playing with radio effect: " .. filename)
  return true
end

--------------------------------------------------------------------------------
-- Configuration and State
--------------------------------------------------------------------------------

--- Configure the audio system
-- @param settings Configuration table
function DMS.Audio.configure(settings)
  if settings.basePath then config.basePath = settings.basePath end
  if settings.defaultDelay then config.defaultDelay = settings.defaultDelay end
  if settings.queueGap then config.queueGap = settings.queueGap end
  if settings.logPlayback ~= nil then config.logPlayback = settings.logPlayback end
  if settings.enabled ~= nil then config.enabled = settings.enabled end

  log("Audio configured: basePath=" .. config.basePath)
end

--- Enable audio playback
function DMS.Audio.enable()
  config.enabled = true
  log("Audio enabled")
end

--- Disable audio playback
function DMS.Audio.disable()
  config.enabled = false
  log("Audio disabled")
end

--- Get playback statistics
function DMS.Audio.getStats()
  return {
    playCount = state.playCount,
    lastPlayed = state.lastPlayed,
    lastPlayTime = state.lastPlayTime,
    queueLength = #state.queue,
    isProcessingQueue = state.isProcessingQueue,
    enabled = config.enabled,
  }
end

--- Check if audio is enabled
function DMS.Audio.isEnabled()
  return config.enabled
end

--------------------------------------------------------------------------------
-- Integration Hooks
--------------------------------------------------------------------------------

--- Hook DCS world events for automatic sound triggers
-- @param eventSounds Table mapping world.event ids to sound file (or list of files)
function DMS.Audio.hookEvents(eventSounds)
  if type(eventSounds) ~= "table" then
    log("WARNING: hookEvents requires a table of world.event id -> sound")
    return
  end

  if state.eventHandler then
    pcall(world.removeEventHandler, state.eventHandler)
  end

  local handler = {
    onEvent = function(self, event)
      local ok, err = pcall(function()
        if not event then return end
        local sound = eventSounds[event.id]
        if sound then
          if type(sound) == "table" then
            if #sound > 0 then
              DMS.Audio.play(sound[math.random(#sound)])
            end
          else
            DMS.Audio.play(sound)
          end
        end
      end)
      if not ok then
        env.error("[DMS.Audio] event hook error: " .. tostring(err))
      end
    end
  }

  state.eventHandler = handler
  world.addEventHandler(handler)
  log("Hooked event sounds")
  debugLog("Hooked %d event sound mappings", tableLength(eventSounds))
end

--- Hook into DMS.PhaseManager for phase transition sounds
-- @param phaseSounds Table mapping phase names to sounds
function DMS.Audio.hookPhases(phaseSounds)
  if not DMS.PhaseManager then
    log("WARNING: DMS.PhaseManager not available for hooking")
    return
  end

  local originalTransition = DMS.PhaseManager.transitionTo
  if type(originalTransition) ~= "function" then
    log("WARNING: DMS.PhaseManager.transitionTo not available for hooking")
    return
  end
  DMS.PhaseManager.transitionTo = function(...)
    local phaseName = ...
    local sound = phaseSounds and phaseSounds[phaseName]
    if sound then
      pcall(DMS.Audio.play, sound)
    end
    return originalTransition(...)
  end

  log("Hooked phase transition sounds")
end

--------------------------------------------------------------------------------
-- Initialization
--------------------------------------------------------------------------------

log("DMS.Audio loaded")

return DMS.Audio
