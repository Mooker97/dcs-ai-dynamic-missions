-- Messaging Utilities for DCS Missions
-- Standardized radio message formatting and display
-- Place in mission via DO SCRIPT FILE or embed in mission

DMS = DMS or {}
DMS.Msg = {}

-- Message display durations (seconds)
DMS.Msg.Duration = {
    BRIEF = 5,
    NORMAL = 10,
    LONG = 15,
    PERSISTENT = 30,
}

-- Callsigns for radio messages
DMS.Msg.Callsigns = {
    awacs = {"Overlord", "Magic", "Darkstar", "Wizard", "Focus"},
    jtac = {"Warrior", "Reaper", "Anvil", "Hammer", "Spark"},
    tanker = {"Texaco", "Shell", "Arco"},
    player = {"Viper", "Falcon", "Hornet", "Hawg", "Rifle"},
    fac = {"Misty", "Nail", "Covey", "Wolf"},
}

--- Send message to all players
-- @param text string Message text
-- @param duration number|nil Display duration in seconds (default: 10)
-- @param clearView boolean|nil Use new stacking format (default: true)
function DMS.Msg.toAll(text, duration, clearView)
    duration = duration or DMS.Msg.Duration.NORMAL
    if clearView == nil then clearView = true end
    trigger.action.outText(text, duration, clearView)
end

--- Send message to specific coalition
-- @param coalitionId number Coalition ID (coalition.side.BLUE, etc)
-- @param text string Message text
-- @param duration number|nil Display duration in seconds
-- @param clearView boolean|nil Use stacking format
function DMS.Msg.toCoalition(coalitionId, text, duration, clearView)
    duration = duration or DMS.Msg.Duration.NORMAL
    if clearView == nil then clearView = true end
    trigger.action.outTextForCoalition(coalitionId, text, duration, clearView)
end

--- Send message to blue coalition
-- @param text string Message text
-- @param duration number|nil Display duration
function DMS.Msg.toBlue(text, duration)
    DMS.Msg.toCoalition(coalition.side.BLUE, text, duration)
end

--- Send message to red coalition
-- @param text string Message text
-- @param duration number|nil Display duration
function DMS.Msg.toRed(text, duration)
    DMS.Msg.toCoalition(coalition.side.RED, text, duration)
end

--- Send message to specific group
-- @param groupId number Group ID (from group:getID())
-- @param text string Message text
-- @param duration number|nil Display duration
function DMS.Msg.toGroup(groupId, text, duration)
    duration = duration or DMS.Msg.Duration.NORMAL
    trigger.action.outTextForGroup(groupId, text, duration)
end

--- Send message to group by name
-- @param groupName string Group name
-- @param text string Message text
-- @param duration number|nil Display duration
function DMS.Msg.toGroupByName(groupName, text, duration)
    local group = Group.getByName(groupName)
    if group then
        DMS.Msg.toGroup(group:getID(), text, duration)
    end
end

--- Format a radio transmission
-- @param callsign string Sender callsign
-- @param message string Message content
-- @param frequency string|nil Optional frequency display
-- @return string Formatted radio message
function DMS.Msg.formatRadio(callsign, message, frequency)
    if frequency then
        return string.format("[%s] %s: \"%s\"", frequency, callsign, message)
    else
        return string.format("%s: \"%s\"", callsign, message)
    end
end

--- Format AWACS-style BRA (Bearing, Range, Altitude) call
-- @param callsign string AWACS callsign
-- @param targetDesc string Target description (e.g., "Single group")
-- @param bearing number Bearing in degrees
-- @param rangeNm number Range in nautical miles
-- @param altitudeFt number Altitude in feet
-- @param aspect string|nil Aspect (hot, cold, flanking, beaming)
-- @return string Formatted BRA call
function DMS.Msg.formatBRA(callsign, targetDesc, bearing, rangeNm, altitudeFt, aspect)
    local angels = math.floor(altitudeFt / 1000)
    local msg = string.format("%s: %s, BRA %03d/%d, angels %d",
        callsign, targetDesc, math.floor(bearing), math.floor(rangeNm), angels)
    if aspect then
        msg = msg .. ", " .. aspect
    end
    return msg
end

--- Format AWACS-style Bullseye call
-- @param callsign string AWACS callsign
-- @param targetDesc string Target description
-- @param bearing number Bearing from bullseye
-- @param rangeNm number Range from bullseye in NM
-- @param altitudeFt number Altitude in feet
-- @param track string|nil Track direction (North, East, etc)
-- @return string Formatted Bullseye call
function DMS.Msg.formatBullseye(callsign, targetDesc, bearing, rangeNm, altitudeFt, track)
    local angels = math.floor(altitudeFt / 1000)
    local msg = string.format("%s: %s, Bullseye %03d/%d, %d thousand",
        callsign, targetDesc, math.floor(bearing), math.floor(rangeNm), angels)
    if track then
        msg = msg .. ", tracking " .. track
    end
    return msg
end

--- Format BDA (Battle Damage Assessment) message
-- @param callsign string Observer callsign
-- @param targetCallsign string Attacker callsign
-- @param result string Result description
-- @param details string|nil Additional details
-- @return string Formatted BDA message
function DMS.Msg.formatBDA(callsign, targetCallsign, result, details)
    local msg = string.format("%s: %s, %s.", callsign, targetCallsign, result)
    if details then
        msg = msg .. " " .. details
    end
    return msg
end

--- Format intel update message
-- @param source string Intel source
-- @param content string Intel content
-- @param priority string|nil Priority level (ROUTINE, PRIORITY, FLASH)
-- @return string Formatted intel message
function DMS.Msg.formatIntel(source, content, priority)
    priority = priority or "ROUTINE"
    return string.format("INTEL [%s] - %s: %s", priority, source, content)
end

--- Format warning message
-- @param content string Warning content
-- @return string Formatted warning
function DMS.Msg.formatWarning(content)
    return string.format("*** WARNING *** %s", content)
end

--- Format alert message (critical)
-- @param content string Alert content
-- @return string Formatted alert
function DMS.Msg.formatAlert(content)
    return string.format("!!! ALERT !!! %s !!!", content)
end

--- Get random callsign from type
-- @param callsignType string Type key from DMS.Msg.Callsigns
-- @return string Random callsign
function DMS.Msg.getRandomCallsign(callsignType)
    local signs = DMS.Msg.Callsigns[callsignType]
    if signs and #signs > 0 then
        return signs[math.random(#signs)]
    end
    return "Unknown"
end

--- Play sound file to all players
-- @param filename string Sound file name (must be in mission)
function DMS.Msg.playSound(filename)
    trigger.action.outSound(filename)
end

--- Play sound file to specific coalition
-- @param coalitionId number Coalition ID
-- @param filename string Sound file name
function DMS.Msg.playSoundToCoalition(coalitionId, filename)
    trigger.action.outSoundForCoalition(coalitionId, filename)
end

--- Send radio transmission with delay
-- @param callsign string Sender callsign
-- @param message string Message content
-- @param delay number Delay in seconds
-- @param duration number|nil Display duration
function DMS.Msg.radioDelayed(callsign, message, delay, duration)
    timer.scheduleFunction(function()
        local formatted = DMS.Msg.formatRadio(callsign, message)
        DMS.Msg.toAll(formatted, duration or DMS.Msg.Duration.NORMAL)
        return nil
    end, nil, timer.getTime() + delay)
end

--- Queue multiple radio messages with spacing
-- @param messages table Array of {callsign=, message=, duration=} tables
-- @param spacing number Seconds between messages
-- @param startDelay number|nil Initial delay before first message
function DMS.Msg.queueRadio(messages, spacing, startDelay)
    spacing = spacing or 3
    startDelay = startDelay or 0

    for i, msg in ipairs(messages) do
        local delay = startDelay + (i - 1) * spacing
        DMS.Msg.radioDelayed(msg.callsign, msg.message, delay, msg.duration)
    end
end

--- Display mission time remaining
-- @param remainingSeconds number Seconds remaining
-- @param label string|nil Label for the timer
function DMS.Msg.showTimeRemaining(remainingSeconds, label)
    label = label or "Time remaining"
    local mins = math.floor(remainingSeconds / 60)
    local secs = remainingSeconds % 60
    DMS.Msg.toAll(string.format("%s: %d:%02d", label, mins, secs), DMS.Msg.Duration.BRIEF)
end

--- Set a user flag (for mission editor triggers)
-- @param flagName string Flag name or number as string
-- @param value boolean|number Flag value
function DMS.Msg.setFlag(flagName, value)
    trigger.action.setUserFlag(tostring(flagName), value)
end

--- Get a user flag value
-- @param flagName string Flag name or number as string
-- @return number Flag value
function DMS.Msg.getFlag(flagName)
    return trigger.misc.getUserFlag(tostring(flagName))
end

-- Export for global access
_G.DMS = DMS
