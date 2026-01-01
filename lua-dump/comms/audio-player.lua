--[[
  DMS Audio Player
  Play WAV/OGG audio files from mission assets

  Audio files should be located in: l10n/DEFAULT/ within the .miz file
  Supports queuing, delays, and targeted playback (coalition/group/unit)

  Usage:
    DMS.Audio.configure({ basePath = "audio/" })
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
  basePath = "audio/",           -- Path prefix within l10n/DEFAULT/
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

local function getFullPath(filename)
  -- If filename already has path or starts with audio/, use as-is
  if filename:match("^audio/") or filename:match("^l10n/") then
    return filename
  end
  return config.basePath .. filename
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
    timer.scheduleFunction(function()
      doPlay()
      return nil
    end, nil, timer.getTime() + delay)
  else
    doPlay()
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
    timer.scheduleFunction(function()
      doPlay()
      return nil
    end, nil, timer.getTime() + delay)
  else
    doPlay()
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
    timer.scheduleFunction(function()
      doPlay()
      return nil
    end, nil, timer.getTime() + delay)
  else
    doPlay()
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
    timer.scheduleFunction(function()
      doPlay()
      return nil
    end, nil, timer.getTime() + delay)
  else
    doPlay()
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
    timer.scheduleFunction(function()
      doPlay()
      return nil
    end, nil, timer.getTime() + delay)
  else
    doPlay()
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
  timer.scheduleFunction(function()
    DMS.Audio.processQueue()
    return nil
  end, nil, timer.getTime() + config.queueGap)
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
  log("Registered library: " .. name .. " with " .. DMS.Utils.tableLength(sounds) .. " sounds")
end

--- Play a sound from a library
-- @param libraryName Library name
-- @param soundName Sound name within library
-- @param delay Optional delay
function DMS.Audio.playFromLibrary(libraryName, soundName, delay)
  local lib = libraries[libraryName]
  if not lib then
    log("ERROR: Unknown library: " .. libraryName)
    return false
  end

  local filename = lib[soundName]
  if not filename then
    log("ERROR: Unknown sound '" .. soundName .. "' in library: " .. libraryName)
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

-- Common mission sounds (register these with actual filenames)
DMS.Audio.Presets = {
  -- Alerts
  ALERT_WARNING = "alerts/warning.wav",
  ALERT_CRITICAL = "alerts/critical.wav",
  ALERT_ALARM = "alerts/alarm.wav",
  ALERT_INCOMING = "alerts/incoming.wav",

  -- Mission Events
  MISSION_START = "mission/start.wav",
  MISSION_COMPLETE = "mission/complete.wav",
  MISSION_FAILED = "mission/failed.wav",
  OBJECTIVE_COMPLETE = "mission/objective_complete.wav",

  -- Radio
  RADIO_STATIC = "radio/static.wav",
  RADIO_CLICK_ON = "radio/click_on.wav",
  RADIO_CLICK_OFF = "radio/click_off.wav",
  RADIO_BEEP = "radio/beep.wav",

  -- Ambient
  AMBIENT_WIND = "ambient/wind.ogg",
  AMBIENT_RAIN = "ambient/rain.ogg",
  AMBIENT_THUNDER = "ambient/thunder.wav",

  -- UI
  UI_SELECT = "ui/select.wav",
  UI_CONFIRM = "ui/confirm.wav",
  UI_CANCEL = "ui/cancel.wav",
}

--- Play a preset sound
-- @param presetName Name from DMS.Audio.Presets
-- @param delay Optional delay
function DMS.Audio.playPreset(presetName, delay)
  local filename = DMS.Audio.Presets[presetName]
  if not filename then
    log("ERROR: Unknown preset: " .. presetName)
    return false
  end
  return DMS.Audio.play(filename, delay)
end

--------------------------------------------------------------------------------
-- Radio Simulation
--------------------------------------------------------------------------------

--- Play sound with radio effect (click on, sound, click off)
-- @param filename Sound file
-- @param options { coalition, group, unit, delay }
function DMS.Audio.playWithRadioEffect(filename, options)
  options = options or {}
  local delay = options.delay or 0
  local target = options.coalition or options.group or options.unit

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

  -- Schedule: click on -> sound -> click off
  timer.scheduleFunction(function()
    playFunc(DMS.Audio.Presets.RADIO_CLICK_ON or "radio/click_on.wav")
    return nil
  end, nil, timer.getTime() + delay)

  timer.scheduleFunction(function()
    playFunc(getFullPath(filename))
    return nil
  end, nil, timer.getTime() + delay + 0.3)

  -- Note: Click off timing depends on actual sound duration
  -- User should adjust or use actual sound duration
  timer.scheduleFunction(function()
    playFunc(DMS.Audio.Presets.RADIO_CLICK_OFF or "radio/click_off.wav")
    return nil
  end, nil, timer.getTime() + delay + 5.0)  -- Assumes ~5 second sound

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

--- Hook into DMS.Events for automatic sound triggers
-- @param eventSounds Table mapping event types to sounds
function DMS.Audio.hookEvents(eventSounds)
  if not DMS.Events then
    log("WARNING: DMS.Events not available for hooking")
    return
  end

  local handler = {
    onEvent = function(self, event)
      local sound = eventSounds[event.id]
      if sound then
        if type(sound) == "table" then
          -- Random from list
          DMS.Audio.play(sound[math.random(#sound)])
        else
          DMS.Audio.play(sound)
        end
      end
    end
  }

  world.addEventHandler(handler)
  log("Hooked event sounds")
end

--- Hook into DMS.PhaseManager for phase transition sounds
-- @param phaseSounds Table mapping phase names to sounds
function DMS.Audio.hookPhases(phaseSounds)
  if not DMS.PhaseManager then
    log("WARNING: DMS.PhaseManager not available for hooking")
    return
  end

  local originalTransition = DMS.PhaseManager.transitionTo
  DMS.PhaseManager.transitionTo = function(phaseName)
    local sound = phaseSounds[phaseName]
    if sound then
      DMS.Audio.play(sound)
    end
    return originalTransition(phaseName)
  end

  log("Hooked phase transition sounds")
end

--------------------------------------------------------------------------------
-- Initialization
--------------------------------------------------------------------------------

log("DMS.Audio loaded")

return DMS.Audio
