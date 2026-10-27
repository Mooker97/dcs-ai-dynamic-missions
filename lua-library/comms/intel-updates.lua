-- Intel Updates System for DCS Missions
-- Dynamic intelligence reports tied to mission events
-- Requires: utils/messaging.lua
-- Place in mission via DO SCRIPT FILE

DMS = DMS or {}
DMS.Intel = {}

-- Queued intel reports
DMS.Intel.Queue = {}
DMS.Intel.History = {}   -- Sent reports (most recent last), used by broadcastUpdate
DMS.Intel.Active = false

local function debugLog(fmt, ...)
    if DMS.Settings and DMS.Settings.isDebug and DMS.Settings.isDebug() then
        env.info(string.format("[Intel] " .. fmt, ...))
    end
end

local function logError(context, err)
    env.error(string.format("[Intel] %s: %s", context, tostring(err)))
    if DMS.Error and DMS.Error.log then
        pcall(DMS.Error.log, "Intel", context, err)
    end
end

local function recordHistory(report)
    table.insert(DMS.Intel.History, {
        content = report.content,
        source = report.source,
        priority = report.priority,
        time = timer.getTime(),
    })
    local maxHistory = DMS.Intel.Config.maxHistory or 20
    while #DMS.Intel.History > maxHistory do
        table.remove(DMS.Intel.History, 1)
    end
end

-- Configuration
DMS.Intel.Config = {
    defaultSource = "SIGINT",
    defaultPriority = "ROUTINE",
    displayDuration = 15,
    playerCoalition = coalition.side.BLUE,
    minTimeBetweenReports = 30,  -- Minimum seconds between reports
    lastReportTime = 0,
    maxHistory = 20,             -- Reports kept for broadcastUpdate
    updateReportCount = 3,       -- Reports included in a requested update
}

-- Priority levels
DMS.Intel.Priority = {
    ROUTINE = 1,
    PRIORITY = 2,
    IMMEDIATE = 3,
    FLASH = 4,
}

--- Configure intel system
-- @param settings table Configuration overrides
function DMS.Intel.configure(settings)
    for key, value in pairs(settings) do
        DMS.Intel.Config[key] = value
    end
end

--- Queue an intel report
-- @param content string Intel content
-- @param source string|nil Source (SIGINT, HUMINT, IMINT, etc)
-- @param priority string|nil Priority level
-- @param delay number|nil Delay before showing (seconds)
function DMS.Intel.report(content, source, priority, delay)
    source = source or DMS.Intel.Config.defaultSource
    priority = priority or DMS.Intel.Config.defaultPriority
    delay = delay or 0

    local report = {
        content = content,
        source = source,
        priority = priority,
        scheduledTime = timer.getTime() + delay,
        sent = false,
    }

    table.insert(DMS.Intel.Queue, report)

    -- Sort queue by scheduled time
    table.sort(DMS.Intel.Queue, function(a, b)
        return a.scheduledTime < b.scheduledTime
    end)

    -- Process queue if active
    if DMS.Intel.Active then
        DMS.Intel.processQueue()
    end
end

--- Format intel message
-- @param report table Report data
-- @return string Formatted message
local function formatIntelMessage(report)
    return string.format("INTEL [%s] - %s:\n%s",
        report.priority,
        report.source,
        report.content
    )
end

--- Process the intel queue
function DMS.Intel.processQueue()
    local currentTime = timer.getTime()

    for _, report in ipairs(DMS.Intel.Queue) do
        if not report.sent and report.scheduledTime <= currentTime then
            -- Check minimum time between reports
            if currentTime - DMS.Intel.Config.lastReportTime >= DMS.Intel.Config.minTimeBetweenReports then
                local msg = formatIntelMessage(report)

                trigger.action.outTextForCoalition(
                    DMS.Intel.Config.playerCoalition,
                    msg,
                    DMS.Intel.Config.displayDuration,
                    true
                )

                report.sent = true
                recordHistory(report)
                DMS.Intel.Config.lastReportTime = currentTime
                debugLog("Sent report [%s/%s]", tostring(report.priority), tostring(report.source))
            end
        end
    end

    -- Clean up sent reports
    local newQueue = {}
    for _, report in ipairs(DMS.Intel.Queue) do
        if not report.sent then
            table.insert(newQueue, report)
        end
    end
    DMS.Intel.Queue = newQueue
end

--- Start intel system
function DMS.Intel.start()
    if DMS.Intel.Active then
        return
    end

    DMS.Intel.Active = true

    -- Start queue processor
    timer.scheduleFunction(function(_, time)
        if not DMS.Intel.Active then
            return nil
        end
        local ok, err = pcall(DMS.Intel.processQueue)
        if not ok then logError("processQueue", err) end
        return time + 5  -- Check every 5 seconds
    end, nil, timer.getTime() + 1)
    debugLog("Started (min %ds between reports)", DMS.Intel.Config.minTimeBetweenReports)
end

--- Stop intel system
function DMS.Intel.stop()
    DMS.Intel.Active = false
end

--- Send immediate intel (bypasses queue)
-- @param content string Intel content
-- @param source string|nil Source
-- @param priority string|nil Priority
function DMS.Intel.immediate(content, source, priority)
    source = source or DMS.Intel.Config.defaultSource
    priority = priority or "FLASH"

    local msg = string.format("INTEL [%s] - %s:\n%s", priority, source, content)

    trigger.action.outTextForCoalition(
        DMS.Intel.Config.playerCoalition,
        msg,
        DMS.Intel.Config.displayDuration,
        true
    )

    DMS.Intel.Config.lastReportTime = timer.getTime()
    recordHistory({content = content, source = source, priority = priority})
end

--- Broadcast a situation update built from the most recent intel reports.
-- Called by the F10 "Request Intel Update" command (player-support/command-menu.lua).
-- @param side number|nil Coalition to send to (default Config.playerCoalition)
-- @param groupId number|nil If given, send only to this group
function DMS.Intel.broadcastUpdate(side, groupId)
    side = side or DMS.Intel.Config.playerCoalition
    local count = DMS.Intel.Config.updateReportCount or 3
    local now = timer.getTime()

    local lines = {}
    for i = #DMS.Intel.History, math.max(1, #DMS.Intel.History - count + 1), -1 do
        local r = DMS.Intel.History[i]
        local ago = math.floor((now - r.time) / 60)
        table.insert(lines, string.format("[%s/%s, %d min ago] %s", r.priority, r.source, ago, r.content))
    end

    local pending = 0
    for _, r in ipairs(DMS.Intel.Queue) do
        if not r.sent then pending = pending + 1 end
    end

    local msg
    if #lines == 0 then
        msg = "INTEL SITREP:\nNo active contacts at this time."
    else
        msg = "INTEL SITREP:\n" .. table.concat(lines, "\n")
    end
    if pending > 0 then
        msg = msg .. string.format("\n(%d further report(s) being processed)", pending)
    end

    if groupId then
        trigger.action.outTextForGroup(groupId, msg, DMS.Intel.Config.displayDuration)
    else
        trigger.action.outTextForCoalition(side, msg, DMS.Intel.Config.displayDuration)
    end
    debugLog("Broadcast update (%d reports, %d pending)", #lines, pending)
end

-- Pre-defined intel report templates
DMS.Intel.Templates = {}

--- Register an intel template
-- @param name string Template name
-- @param content string Template content (can use %s for variables)
-- @param source string|nil Default source
-- @param priority string|nil Default priority
function DMS.Intel.registerTemplate(name, content, source, priority)
    DMS.Intel.Templates[name] = {
        content = content,
        source = source or DMS.Intel.Config.defaultSource,
        priority = priority or DMS.Intel.Config.defaultPriority,
    }
end

--- Send intel from template
-- @param templateName string Template name
-- @param ... any Variables to insert into template
function DMS.Intel.fromTemplate(templateName, ...)
    local template = DMS.Intel.Templates[templateName]
    if not template then
        return
    end

    local ok, content = pcall(string.format, template.content, ...)
    if not ok then
        logError("fromTemplate " .. tostring(templateName), content)
        return
    end
    DMS.Intel.report(content, template.source, template.priority)
end

--- Create spawn-linked intel report
-- When a group spawns, send intel about it
-- @param groupName string Group to watch for
-- @param intelContent string Intel to report
-- @param delay number|nil Delay after spawn
function DMS.Intel.onSpawn(groupName, intelContent, delay)
    delay = delay or 5

    -- Check periodically if group has spawned
    timer.scheduleFunction(function(_, time)
        local ok, result = pcall(function()
            local group = Group.getByName(groupName)
            if not group or not group:isExist() then return false end
            -- Late-activated groups exist before activation: require an active unit
            local unit = group:getUnit(1)
            if not unit or not unit:isExist() or not unit:isActive() then return false end
            DMS.Intel.report(intelContent, "HUMINT", "PRIORITY", delay)
            debugLog("Group '%s' spawned, intel queued", groupName)
            return true
        end)
        if not ok then
            logError("onSpawn " .. tostring(groupName), result)
            return nil
        end
        if result then return nil end  -- Stop checking
        return time + 5  -- Keep checking
    end, nil, timer.getTime() + 5)
end

--[[
USAGE EXAMPLE:

-- Configure
DMS.Intel.configure({
    defaultSource = "SIGINT",
    displayDuration = 15,
    minTimeBetweenReports = 20
})

-- Start system
DMS.Intel.start()

-- Register templates
DMS.Intel.registerTemplate("convoy_spotted",
    "Enemy supply convoy spotted moving through sector %s. Estimated %d vehicles.",
    "HUMINT", "PRIORITY")

DMS.Intel.registerTemplate("sam_active",
    "SA-%d radar emissions detected at grid %s. Recommend caution.",
    "SIGINT", "IMMEDIATE")

DMS.Intel.registerTemplate("reinforcements",
    "Enemy reinforcements arriving from the %s. ETA %d minutes.",
    "IMINT", "PRIORITY")

-- Send intel reports
DMS.Intel.report("Enemy patrol activity detected in northern sector.", "SIGINT")

DMS.Intel.fromTemplate("convoy_spotted", "Alpha", 6)
DMS.Intel.fromTemplate("sam_active", 11, "XY1234")

-- Immediate flash report
DMS.Intel.immediate("Enemy aircraft scrambling from hostile airfield!", "SIGINT", "FLASH")

-- Link intel to spawn
DMS.Intel.onSpawn("HVT-Convoy",
    "High Value Target convoy has departed enemy base. Intercept opportunity!",
    10)
]]

-- Export
_G.DMS = DMS
