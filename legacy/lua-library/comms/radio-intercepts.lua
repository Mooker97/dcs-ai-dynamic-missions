-- Enemy Radio Intercepts for DCS Missions
-- Intercepted enemy communications for intel and atmosphere
-- Requires: utils/messaging.lua
-- Place in mission via DO SCRIPT FILE

DMS = DMS or {}
DMS.Intercepts = {}

-- Queue of intercepts
DMS.Intercepts.Queue = {}
DMS.Intercepts.Active = false
DMS.Intercepts.TimerId = nil

-- Configuration
DMS.Intercepts.Config = {
    displayDuration = 12,
    minInterval = 45,            -- Minimum seconds between intercepts
    maxInterval = 120,           -- Maximum seconds between intercepts
    lastInterceptTime = 0,
    playerCoalition = coalition.side.BLUE,
    interceptChance = 70,        -- % chance to intercept when triggered
    showStatic = true,           -- Add radio static effect to messages
}

-- Pre-defined intercept messages by category
DMS.Intercepts.Messages = {
    -- General chatter
    chatter = {
        "...confirmed, moving to position...",
        "...radar contact, bearing...[static]...",
        "...request reinforcements at grid...",
        "...ammunition running low...",
        "...enemy aircraft spotted overhead...",
        "...maintaining radio silence from now...",
        "...understood, holding position...",
        "...patrol reports all clear in sector...",
    },

    -- Air defense related
    air_defense = {
        "...SAM battery reports ready status...",
        "...tracking aircraft, awaiting weapons free...",
        "...radar contact, multiple bogeys inbound...",
        "...switching to backup frequency...",
        "...lost radar lock, reacquiring...",
        "...air defense on high alert...",
    },

    -- Ground forces
    ground = {
        "...convoy has departed, ETA thirty minutes...",
        "...armor column moving through checkpoint...",
        "...infantry taking defensive positions...",
        "...supply truck disabled, requesting recovery...",
        "...enemy ground forces spotted, engage...",
    },

    -- Command communications
    command = {
        "...headquarters confirms mission proceed...",
        "...new orders received, stand by...",
        "...priority target designated at...[static]...",
        "...operation commencing at dawn...",
        "...all units report status immediately...",
    },

    -- Distress/Combat
    distress = {
        "...we are under attack! Request...[static]...",
        "...mayday, mayday, position is...",
        "...taking heavy fire, need support...",
        "...casualties reported, medical...[static]...",
        "...aircraft down! Search and rescue...",
    },

    -- Reinforcement/Movement
    movement = {
        "...reinforcements en route, ETA...",
        "...relocating to secondary position...",
        "...transport aircraft departing...",
        "...withdrawal ordered, fall back...",
        "...flanking maneuver in progress...",
    },
}

local function isDebug()
    return DMS.Settings and DMS.Settings.isDebug and DMS.Settings.isDebug()
end

local function logDebug(fmt, ...)
    if isDebug() then
        env.info(string.format("[Intercepts] " .. fmt, ...))
    end
end

--- Run a timer callback inside pcall so a script error cannot kill the scheduler
local function safeCall(name, fn, ...)
    local ok, result = pcall(fn, ...)
    if not ok then
        env.error(string.format("[Intercepts] %s error: %s", name, tostring(result)))
        return nil
    end
    return result
end

--- Configure intercepts system
-- @param settings table Configuration overrides
function DMS.Intercepts.configure(settings)
    for key, value in pairs(settings) do
        DMS.Intercepts.Config[key] = value
    end
end

--- Add static effect to message
-- @param message string Original message
-- @return string Message with static
local function addStatic(message)
    if not DMS.Intercepts.Config.showStatic then
        return message
    end

    local prefix = "[INTERCEPT - Enemy Comms]\n"
    local staticEffects = {"...", "[static]", "[garbled]", "...[break]..."}

    -- Randomly insert static
    if #message > 6 and math.random(100) < 30 then
        local pos = math.random(#message - 5)
        local static = staticEffects[math.random(#staticEffects)]
        message = message:sub(1, pos) .. static .. message:sub(pos + 1)
    end

    return prefix .. message
end

--- Get random message from category
-- @param category string Message category
-- @return string Random message
local function getRandomMessage(category)
    local messages = DMS.Intercepts.Messages[category]
    if messages and #messages > 0 then
        return messages[math.random(#messages)]
    end
    return "...[static]..."
end

--- Send an intercept
-- @param message string|nil Message (random if nil)
-- @param category string|nil Category for random selection
function DMS.Intercepts.send(message, category)
    if not DMS.Intercepts.Active then
        return
    end

    -- Check intercept chance
    local roll = math.random(100)
    if roll > DMS.Intercepts.Config.interceptChance then
        logDebug("Skipped intercept (rolled %d > %d)", roll, DMS.Intercepts.Config.interceptChance)
        return
    end

    -- Get message
    if not message then
        category = category or "chatter"
        message = getRandomMessage(category)
    end

    local formatted = addStatic(message)

    trigger.action.outTextForCoalition(
        DMS.Intercepts.Config.playerCoalition,
        formatted,
        DMS.Intercepts.Config.displayDuration,
        true
    )

    DMS.Intercepts.Config.lastInterceptTime = timer.getTime()
    logDebug("Sent intercept: %s", tostring(message))
end

--- Queue an intercept for later
-- @param message string|nil Message
-- @param category string|nil Category
-- @param delay number Delay in seconds
function DMS.Intercepts.queue(message, category, delay)
    timer.scheduleFunction(function()
        safeCall("queue", DMS.Intercepts.send, message, category)
        return nil
    end, nil, timer.getTime() + (tonumber(delay) or 0) + 0.01)
end

--- Send random intercept from any category
function DMS.Intercepts.sendRandom()
    local categories = {"chatter", "air_defense", "ground", "command", "movement"}
    local category = categories[math.random(#categories)]
    DMS.Intercepts.send(nil, category)
end

--- Start ambient intercepts (random periodic)
function DMS.Intercepts.startAmbient()
    if DMS.Intercepts.TimerId then
        return
    end

    DMS.Intercepts.Active = true

    local function nextInterval()
        local minI = DMS.Intercepts.Config.minInterval
        local maxI = math.max(minI, DMS.Intercepts.Config.maxInterval)
        return minI + math.random() * (maxI - minI)
    end

    -- Reschedule by returning the next time (keeps a single, stable timer id)
    DMS.Intercepts.TimerId = timer.scheduleFunction(function(_, time)
        if not DMS.Intercepts.TimerId then return nil end
        safeCall("ambient", DMS.Intercepts.sendRandom)
        return time + nextInterval()
    end, nil, timer.getTime() + nextInterval())
    logDebug("Ambient intercepts started (%d-%ds)", DMS.Intercepts.Config.minInterval, DMS.Intercepts.Config.maxInterval)
end

--- Stop ambient intercepts
function DMS.Intercepts.stopAmbient()
    if DMS.Intercepts.TimerId then
        timer.removeFunction(DMS.Intercepts.TimerId)
        DMS.Intercepts.TimerId = nil
    end
end

--- Add custom messages to a category
-- @param category string Category name
-- @param messages table Array of messages to add
function DMS.Intercepts.addMessages(category, messages)
    if not DMS.Intercepts.Messages[category] then
        DMS.Intercepts.Messages[category] = {}
    end

    for _, msg in ipairs(messages) do
        table.insert(DMS.Intercepts.Messages[category], msg)
    end
end

--- Create new category
-- @param category string Category name
-- @param messages table Initial messages
function DMS.Intercepts.createCategory(category, messages)
    DMS.Intercepts.Messages[category] = messages or {}
end

--- Trigger intercept on event (e.g., spawn)
-- @param groupName string Group to watch
-- @param message string Message to send
-- @param category string|nil Or category for random
function DMS.Intercepts.onSpawn(groupName, message, category)
    local function isSpawned()
        local group = Group.getByName(groupName)
        if not group or not group:isExist() then return false end
        local unit = group:getUnit(1)
        -- Late-activated groups exist but are inactive until activated
        return unit ~= nil and unit:isExist() and unit:isActive()
    end

    timer.scheduleFunction(function(_, time)
        local ok, spawned = pcall(isSpawned)
        if ok and spawned then
            -- Small delay after spawn
            DMS.Intercepts.queue(message, category, 5 + math.random() * 10)
            logDebug("Group '%s' spawned, intercept queued", tostring(groupName))
            return nil
        end
        if not ok then
            env.error(string.format("[Intercepts] onSpawn error: %s", tostring(spawned)))
        end
        return time + 5
    end, nil, timer.getTime() + 5)
end

--- Start the intercepts system
function DMS.Intercepts.start()
    DMS.Intercepts.Active = true
end

--- Stop the intercepts system
function DMS.Intercepts.stop()
    DMS.Intercepts.Active = false
    DMS.Intercepts.stopAmbient()
end

--[[
USAGE EXAMPLE:

-- Configure
DMS.Intercepts.configure({
    displayDuration = 10,
    minInterval = 60,
    maxInterval = 180,
    interceptChance = 80,
    showStatic = true
})

-- Add custom messages
DMS.Intercepts.addMessages("air_defense", {
    "...SA-11 battery reporting multiple contacts...",
    "...fighter scramble authorized..."
})

-- Create mission-specific category
DMS.Intercepts.createCategory("convoy_ops", {
    "...convoy alpha proceeding to waypoint...",
    "...escort reports clear roads ahead...",
    "...fuel truck joining at checkpoint..."
})

-- Start system
DMS.Intercepts.start()

-- Start ambient intercepts
DMS.Intercepts.startAmbient()

-- Manual intercept
DMS.Intercepts.send("...air raid warning! All units take cover...", nil)

-- Category-specific random
DMS.Intercepts.send(nil, "distress")

-- Delayed intercept
DMS.Intercepts.queue("...reinforcements scrambling from base...", nil, 30)

-- Link to spawn event
DMS.Intercepts.onSpawn("Enemy-Convoy",
    "...convoy has departed, destination is...[static]...")
]]

-- Export
_G.DMS = DMS
