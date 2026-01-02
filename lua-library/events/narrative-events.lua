-- Narrative Events System for DCS Missions
-- Scripted story moments and cinematic events
-- Requires: utils/messaging.lua, utils/timer-utils.lua
-- Place in mission via DO SCRIPT FILE

DMS = DMS or {}
DMS.Narrative = {}

-- Story state
DMS.Narrative.Chapters = {}
DMS.Narrative.CurrentChapter = 0
DMS.Narrative.Active = false
DMS.Narrative.TimerId = nil

-- Configuration
DMS.Narrative.Config = {
    playerCoalition = coalition.side.BLUE,
    messageDisplayTime = 15,
    typingEffect = true,        -- Simulate radio typing effect
    typingDelay = 0.05,         -- Delay between characters (if typing effect)
    chapterTransitionDelay = 5, -- Delay between chapters
    autoAdvance = false,        -- Auto-advance chapters when conditions met
}

-- Voice/character definitions
DMS.Narrative.Characters = {
    AWACS = {prefix = "OVERLORD: ", color = nil},
    HQ = {prefix = "COMMAND: ", color = nil},
    WINGMAN = {prefix = "WINGMAN: ", color = nil},
    JTAC = {prefix = "JTAC: ", color = nil},
    INTEL = {prefix = "INTEL: ", color = nil},
    ENEMY = {prefix = "[INTERCEPTED] ", color = nil},
}

--- Configure narrative system
-- @param settings table Configuration overrides
function DMS.Narrative.configure(settings)
    for key, value in pairs(settings) do
        DMS.Narrative.Config[key] = value
    end
end

--- Add a custom character
-- @param id string Character ID
-- @param prefix string Message prefix
function DMS.Narrative.addCharacter(id, prefix)
    DMS.Narrative.Characters[id] = {prefix = prefix, color = nil}
end

--- Create a dialogue line
-- @param character string Character ID
-- @param text string Dialogue text
-- @param delay number|nil Delay before showing
-- @return table Dialogue definition
local function createDialogue(character, text, delay)
    local char = DMS.Narrative.Characters[character] or {prefix = ""}
    return {
        type = "dialogue",
        text = char.prefix .. text,
        delay = delay or 0,
    }
end

--- Create an action (spawn, flag, etc)
-- @param actionType string Action type
-- @param params table Action parameters
-- @param delay number|nil Delay before action
-- @return table Action definition
local function createAction(actionType, params, delay)
    return {
        type = "action",
        actionType = actionType,
        params = params,
        delay = delay or 0,
    }
end

--- Register a story chapter
-- @param chapterNum number Chapter number
-- @param events table Array of events (dialogues and actions)
-- @param options table|nil Chapter options
function DMS.Narrative.registerChapter(chapterNum, events, options)
    options = options or {}

    DMS.Narrative.Chapters[chapterNum] = {
        events = events,
        played = false,
        condition = options.condition,        -- Function that returns true to trigger
        title = options.title,
        onComplete = options.onComplete,      -- Function to call when chapter ends
    }
end

--- Execute an event
-- @param event table Event definition
local function executeEvent(event)
    if event.type == "dialogue" then
        trigger.action.outTextForCoalition(
            DMS.Narrative.Config.playerCoalition,
            event.text,
            DMS.Narrative.Config.messageDisplayTime,
            true
        )

    elseif event.type == "action" then
        if event.actionType == "spawn" then
            for _, groupName in ipairs(event.params.groups or {}) do
                local group = Group.getByName(groupName)
                if group then
                    trigger.action.activateGroup(group)
                end
            end

        elseif event.actionType == "destroy" then
            for _, groupName in ipairs(event.params.groups or {}) do
                local group = Group.getByName(groupName)
                if group and group:isExist() then
                    group:destroy()
                end
            end

        elseif event.actionType == "flag" then
            trigger.action.setUserFlag(event.params.flag, event.params.value or 1)

        elseif event.actionType == "smoke" then
            trigger.action.smoke(event.params.position, event.params.color or trigger.smokeColor.Red)

        elseif event.actionType == "flare" then
            trigger.action.signalFlare(event.params.position, event.params.color or trigger.flareColor.Red, event.params.azimuth or 0)

        elseif event.actionType == "explosion" then
            trigger.action.explosion(event.params.position, event.params.power or 100)

        elseif event.actionType == "sound" then
            -- Note: Requires sound file in mission
            trigger.action.outSound(event.params.file)

        elseif event.actionType == "custom" then
            if type(event.params.func) == "function" then
                event.params.func(event.params.args)
            end
        end
    end
end

--- Play a chapter
-- @param chapterNum number Chapter to play
function DMS.Narrative.playChapter(chapterNum)
    local chapter = DMS.Narrative.Chapters[chapterNum]
    if not chapter or chapter.played then
        return false
    end

    chapter.played = true
    DMS.Narrative.CurrentChapter = chapterNum

    -- Show chapter title if defined
    if chapter.title then
        trigger.action.outTextForCoalition(
            DMS.Narrative.Config.playerCoalition,
            "=== " .. chapter.title .. " ===",
            5,
            true
        )
    end

    -- Schedule all events
    local totalDelay = chapter.title and 3 or 0

    for _, event in ipairs(chapter.events) do
        local eventDelay = totalDelay + (event.delay or 0)

        timer.scheduleFunction(function()
            executeEvent(event)
            return nil
        end, nil, timer.getTime() + eventDelay)

        -- Add message display time for dialogues
        if event.type == "dialogue" then
            totalDelay = eventDelay + DMS.Narrative.Config.messageDisplayTime + 2
        else
            totalDelay = eventDelay + 1
        end
    end

    -- Call onComplete after all events
    if chapter.onComplete then
        timer.scheduleFunction(function()
            chapter.onComplete()
            return nil
        end, nil, timer.getTime() + totalDelay)
    end

    return true
end

--- Check chapter conditions and auto-play
local function checkChapterConditions(_, time)
    if not DMS.Narrative.Active or not DMS.Narrative.Config.autoAdvance then
        return nil
    end

    for chapterNum, chapter in pairs(DMS.Narrative.Chapters) do
        if not chapter.played and chapter.condition then
            if chapter.condition() then
                DMS.Narrative.playChapter(chapterNum)
            end
        end
    end

    return time + 5  -- Check every 5 seconds
end

--- Start narrative system
function DMS.Narrative.start()
    if DMS.Narrative.Active then
        return
    end

    DMS.Narrative.Active = true

    if DMS.Narrative.Config.autoAdvance then
        DMS.Narrative.TimerId = timer.scheduleFunction(
            checkChapterConditions,
            nil,
            timer.getTime() + 5
        )
    end
end

--- Stop narrative system
function DMS.Narrative.stop()
    DMS.Narrative.Active = false
    if DMS.Narrative.TimerId then
        timer.removeFunction(DMS.Narrative.TimerId)
        DMS.Narrative.TimerId = nil
    end
end

--- Helper: Create dialogue event
-- @param character string Character ID
-- @param text string Dialogue text
-- @param delay number|nil Delay
-- @return table Event definition
function DMS.Narrative.dialogue(character, text, delay)
    return createDialogue(character, text, delay)
end

--- Helper: Create spawn action
-- @param groups table Group names to spawn
-- @param delay number|nil Delay
-- @return table Event definition
function DMS.Narrative.spawn(groups, delay)
    return createAction("spawn", {groups = groups}, delay)
end

--- Helper: Create flag action
-- @param flag string Flag name
-- @param value number Flag value
-- @param delay number|nil Delay
-- @return table Event definition
function DMS.Narrative.flag(flag, value, delay)
    return createAction("flag", {flag = flag, value = value}, delay)
end

--- Helper: Create explosion action
-- @param position table Vec3 position
-- @param power number Explosion power
-- @param delay number|nil Delay
-- @return table Event definition
function DMS.Narrative.explosion(position, power, delay)
    return createAction("explosion", {position = position, power = power}, delay)
end

--- Helper: Create custom action
-- @param func function Function to execute
-- @param args any|nil Arguments
-- @param delay number|nil Delay
-- @return table Event definition
function DMS.Narrative.custom(func, args, delay)
    return createAction("custom", {func = func, args = args}, delay)
end

--[[
USAGE EXAMPLE:

-- Configure
DMS.Narrative.configure({
    messageDisplayTime = 12,
    autoAdvance = true
})

-- Add custom character
DMS.Narrative.addCharacter("FLIGHT_LEAD", "VIPER 1-1: ")

-- Register opening chapter (plays at mission start)
DMS.Narrative.registerChapter(1, {
    DMS.Narrative.dialogue("HQ", "All callsigns, mission brief follows.", 0),
    DMS.Narrative.dialogue("HQ", "Primary objective: Neutralize enemy radar installation at grid XY1234.", 5),
    DMS.Narrative.dialogue("HQ", "Secondary: Destroy any targets of opportunity.", 5),
    DMS.Narrative.dialogue("AWACS", "Overlord is online. Picture clean at this time.", 5),
    DMS.Narrative.dialogue("FLIGHT_LEAD", "Copy all. Viper flight, let's get to work.", 3),
}, {
    title = "MISSION START",
    condition = function() return timer.getTime() > 10 end  -- Plays 10 seconds after start
})

-- Register chapter triggered by flag
DMS.Narrative.registerChapter(2, {
    DMS.Narrative.dialogue("AWACS", "Viper flight, be advised - radar site destroyed!", 0),
    DMS.Narrative.dialogue("ENEMY", "...air defense is down! Request immediate..."), -- Intercepted
    DMS.Narrative.spawn({"QRF-Helicopters"}, 5),
    DMS.Narrative.dialogue("AWACS", "Warning! Enemy helicopters scrambling from the north.", 2),
    DMS.Narrative.dialogue("HQ", "Excellent work. New tasking: Eliminate the QRF before they reorganize.", 5),
}, {
    title = "ENEMY RESPONSE",
    condition = function() return trigger.misc.getUserFlag("radar_destroyed") == 1 end
})

-- Dramatic ending chapter
DMS.Narrative.registerChapter(3, {
    DMS.Narrative.dialogue("AWACS", "All hostiles neutralized. Area secure.", 0),
    DMS.Narrative.dialogue("HQ", "Outstanding work, Viper flight. RTB at your discretion.", 5),
    DMS.Narrative.dialogue("FLIGHT_LEAD", "Roger that. Viper flight, let's go home.", 3),
    DMS.Narrative.flag("mission_complete", 1, 5),
}, {
    title = "MISSION COMPLETE",
    condition = function() return trigger.misc.getUserFlag("all_targets_destroyed") == 1 end,
    onComplete = function()
        trigger.action.outText("=== MISSION SUCCESS ===", 30)
    end
})

-- Start system
DMS.Narrative.start()

-- Or trigger chapters manually
-- DMS.Narrative.playChapter(1)
]]

-- Export
_G.DMS = DMS
