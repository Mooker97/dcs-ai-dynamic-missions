-- Objective Tracker System for DCS Missions
-- Track and display mission objectives with completion status
-- Requires: utils/messaging.lua
-- Place in mission via DO SCRIPT FILE

DMS = DMS or {}
DMS.Objectives = DMS.Objectives or {}

-- Objective definitions
DMS.Objectives.List = DMS.Objectives.List or {}
DMS.Objectives.Active = DMS.Objectives.Active or false

-- Objective status
DMS.Objectives.Status = {
    PENDING = 1,
    ACTIVE = 2,
    COMPLETED = 3,
    FAILED = 4,
    OPTIONAL = 5,
}

-- Configuration
DMS.Objectives.Config = DMS.Objectives.Config or {
    playerCoalition = coalition.side.BLUE,
    checkInterval = 10,
    showNotifications = true,
    displayDuration = 10,
    trackOnHUD = true,           -- Show current objective on HUD
    hudRefreshInterval = 60,     -- Refresh HUD display interval
}

-- Status display text
local statusText = {
    [1] = "[  ]",      -- PENDING
    [2] = "[>>]",      -- ACTIVE
    [3] = "[OK]",      -- COMPLETED
    [4] = "[XX]",      -- FAILED
    [5] = "[  ]",      -- OPTIONAL
}

local function isDebug()
    return DMS.Settings and DMS.Settings.isDebug and DMS.Settings.isDebug()
end

local function logError(context, err)
    if DMS.Error and DMS.Error.log then
        DMS.Error.log(context, err)
    else
        env.error("[DMS LUA ERROR] " .. tostring(context) .. ": " .. tostring(err))
    end
end

--- Run a user callback/condition safely
-- @return boolean ok, any result
local function safeRun(func, context)
    if type(func) ~= "function" then return false, nil end
    local ok, result = pcall(func)
    if not ok then
        logError(context, result)
        return false, nil
    end
    return true, result
end

--- Configure objective tracker
-- @param settings table Configuration overrides
function DMS.Objectives.configure(settings)
    if type(settings) ~= "table" then return end
    for key, value in pairs(settings) do
        DMS.Objectives.Config[key] = value
    end
end

--- Register an objective
-- @param id string Unique objective ID
-- @param description string Objective description
-- @param options table|nil Objective options
function DMS.Objectives.register(id, description, options)
    options = options or {}
    if id == nil then
        logError("Objectives.register", "objective id is nil")
        return
    end
    description = description or tostring(id)

    DMS.Objectives.List[id] = {
        id = id,
        description = description,
        status = options.status or DMS.Objectives.Status.PENDING,
        priority = options.priority or 1,              -- Lower = more important
        isOptional = options.isOptional or false,
        isHidden = options.isHidden or false,          -- Don't show until revealed
        condition = options.condition or nil,           -- Auto-complete condition
        failCondition = options.failCondition or nil,   -- Auto-fail condition
        onComplete = options.onComplete or nil,
        onFail = options.onFail or nil,
        parentId = options.parentId or nil,            -- For sub-objectives
        completionMessage = options.completionMessage,
        failMessage = options.failMessage,
    }

    if options.isOptional then
        DMS.Objectives.List[id].status = DMS.Objectives.Status.OPTIONAL
    end

    if isDebug() then
        env.info(string.format("[Objectives] Registered: '%s' - %s (optional: %s, hidden: %s)",
            tostring(id), description, tostring(options.isOptional or false), tostring(options.isHidden or false)))
    end
end

--- Activate an objective (make it current)
-- @param id string Objective ID
function DMS.Objectives.activate(id)
    local obj = DMS.Objectives.List[id]
    if not obj then return end

    if obj.status == DMS.Objectives.Status.PENDING or
       obj.status == DMS.Objectives.Status.OPTIONAL then
        obj.status = DMS.Objectives.Status.ACTIVE
        obj.isHidden = false

        if isDebug() then
            env.info(string.format("[Objectives] Activated: '%s' - %s", tostring(id), obj.description))
        end

        if DMS.Objectives.Config.showNotifications then
            trigger.action.outTextForCoalition(
                DMS.Objectives.Config.playerCoalition,
                "NEW OBJECTIVE: " .. obj.description,
                DMS.Objectives.Config.displayDuration,
                true
            )
        end
    end
end

--- Complete an objective
-- @param id string Objective ID
function DMS.Objectives.complete(id)
    local obj = DMS.Objectives.List[id]
    if not obj then return end

    if obj.status ~= DMS.Objectives.Status.COMPLETED then
        obj.status = DMS.Objectives.Status.COMPLETED

        if isDebug() then
            env.info(string.format("[Objectives] Completed: '%s' - %s", tostring(id), obj.description))
        end

        if DMS.Objectives.Config.showNotifications then
            local msg = obj.completionMessage or ("OBJECTIVE COMPLETE: " .. obj.description)
            trigger.action.outTextForCoalition(
                DMS.Objectives.Config.playerCoalition,
                msg,
                DMS.Objectives.Config.displayDuration,
                true
            )
        end

        if obj.onComplete then
            safeRun(obj.onComplete, "Objectives.onComplete(" .. tostring(id) .. ")")
        end
    end
end

--- Fail an objective
-- @param id string Objective ID
function DMS.Objectives.fail(id)
    local obj = DMS.Objectives.List[id]
    if not obj then return end

    if obj.status ~= DMS.Objectives.Status.FAILED and
       obj.status ~= DMS.Objectives.Status.COMPLETED then
        obj.status = DMS.Objectives.Status.FAILED

        if isDebug() then
            env.info(string.format("[Objectives] Failed: '%s' - %s", tostring(id), obj.description))
        end

        if DMS.Objectives.Config.showNotifications then
            local msg = obj.failMessage or ("OBJECTIVE FAILED: " .. obj.description)
            trigger.action.outTextForCoalition(
                DMS.Objectives.Config.playerCoalition,
                msg,
                DMS.Objectives.Config.displayDuration,
                true
            )
        end

        if obj.onFail then
            safeRun(obj.onFail, "Objectives.onFail(" .. tostring(id) .. ")")
        end
    end
end

--- Reveal a hidden objective
-- @param id string Objective ID
function DMS.Objectives.reveal(id)
    local obj = DMS.Objectives.List[id]
    if obj then
        obj.isHidden = false
    end
end

--- Get formatted objective list for display
-- @param includeCompleted boolean|nil Include completed objectives
-- @return string Formatted objective list
function DMS.Objectives.getFormattedList(includeCompleted)
    local lines = {"=== MISSION OBJECTIVES ===", ""}
    local objectives = {}

    -- Sort by priority
    for _, obj in pairs(DMS.Objectives.List) do
        if not obj.isHidden then
            table.insert(objectives, obj)
        end
    end

    table.sort(objectives, function(a, b)
        local pa, pb = tonumber(a.priority) or 999, tonumber(b.priority) or 999
        if pa == pb then return tostring(a.id) < tostring(b.id) end
        return pa < pb
    end)

    -- Format each objective
    for _, obj in ipairs(objectives) do
        if includeCompleted or
           (obj.status ~= DMS.Objectives.Status.COMPLETED and
            obj.status ~= DMS.Objectives.Status.FAILED) then

            local prefix = statusText[obj.status] or "[  ]"
            local suffix = ""

            if obj.isOptional and obj.status ~= DMS.Objectives.Status.COMPLETED then
                suffix = " (Optional)"
            elseif obj.status == DMS.Objectives.Status.COMPLETED then
                suffix = " - COMPLETE"
            elseif obj.status == DMS.Objectives.Status.FAILED then
                suffix = " - FAILED"
            end

            table.insert(lines, prefix .. " " .. tostring(obj.description) .. suffix)
        end
    end

    return table.concat(lines, "\n")
end

--- Get a status report string (used by player-support/command-menu.lua)
-- Includes a progress summary plus all visible objectives with status.
-- @return string Status report
function DMS.Objectives.getStatusReport()
    local total, completed, failed, active, optional = 0, 0, 0, 0, 0
    for _, obj in pairs(DMS.Objectives.List) do
        if not obj.isHidden then
            if obj.isOptional then
                optional = optional + 1
            else
                total = total + 1
            end
            if obj.status == DMS.Objectives.Status.COMPLETED then
                if not obj.isOptional then completed = completed + 1 end
            elseif obj.status == DMS.Objectives.Status.FAILED then
                if not obj.isOptional then failed = failed + 1 end
            elseif obj.status == DMS.Objectives.Status.ACTIVE then
                active = active + 1
            end
        end
    end

    if total == 0 and optional == 0 then
        return "=== MISSION OBJECTIVES ===\n\nNo objectives assigned."
    end

    local summary = string.format("Progress: %d/%d complete, %d active, %d failed", completed, total, active, failed)
    if optional > 0 then
        summary = summary .. string.format(" (+%d optional)", optional)
    end

    return DMS.Objectives.getFormattedList(true) .. "\n\n" .. summary
end

--- Display objective list to players
function DMS.Objectives.showList()
    local text = DMS.Objectives.getFormattedList(false)
    trigger.action.outTextForCoalition(
        DMS.Objectives.Config.playerCoalition,
        text,
        20,
        true
    )
end

--- Check objective conditions (internal)
local function checkConditionsInternal(_, time)
    if not DMS.Objectives.Active then
        return nil
    end

    for _, obj in pairs(DMS.Objectives.List) do
        -- Check completion condition
        if obj.condition and
           (obj.status == DMS.Objectives.Status.ACTIVE or
            obj.status == DMS.Objectives.Status.OPTIONAL) then
            local ok, met = safeRun(obj.condition, "Objectives.condition(" .. tostring(obj.id) .. ")")
            if ok and met then
                DMS.Objectives.complete(obj.id)
            end
        end

        -- Check fail condition
        if obj.failCondition and
           obj.status ~= DMS.Objectives.Status.COMPLETED and
           obj.status ~= DMS.Objectives.Status.FAILED then
            local ok, failed = safeRun(obj.failCondition, "Objectives.failCondition(" .. tostring(obj.id) .. ")")
            if ok and failed then
                DMS.Objectives.fail(obj.id)
            end
        end
    end

    return time + (tonumber(DMS.Objectives.Config.checkInterval) or 10)
end

--- Check objective conditions with error handling
local function checkConditions(args, time)
    local success, result = pcall(checkConditionsInternal, args, time)
    if not success then
        logError("Objectives.checkConditions", result)
        if not DMS.Objectives.Active then return nil end
        return time + (tonumber(DMS.Objectives.Config.checkInterval) or 10)
    end
    if result == nil then DMS.Objectives.CheckTimerId = nil end
    return result
end

--- HUD refresh (internal)
local function refreshHUDInternal(_, time)
    if not DMS.Objectives.Active or not DMS.Objectives.Config.trackOnHUD then
        return nil
    end

    -- Find active objective
    local activeObj = nil
    local lowestPriority = 999

    for _, obj in pairs(DMS.Objectives.List) do
        local prio = tonumber(obj.priority) or 999
        if obj.status == DMS.Objectives.Status.ACTIVE and
           not obj.isHidden and
           prio < lowestPriority then
            activeObj = obj
            lowestPriority = prio
        end
    end

    local refresh = tonumber(DMS.Objectives.Config.hudRefreshInterval) or 60
    if refresh < 10 then refresh = 10 end

    if activeObj then
        trigger.action.outTextForCoalition(
            DMS.Objectives.Config.playerCoalition,
            "OBJECTIVE: " .. tostring(activeObj.description),
            refresh - 5,
            false  -- Don't clear other messages
        )
    end

    return time + refresh
end

--- HUD refresh with error handling
local function refreshHUD(args, time)
    local success, result = pcall(refreshHUDInternal, args, time)
    if not success then
        logError("Objectives.refreshHUD", result)
        if not DMS.Objectives.Active then return nil end
        return time + (tonumber(DMS.Objectives.Config.hudRefreshInterval) or 60)
    end
    if result == nil then DMS.Objectives.TimerId = nil end
    return result
end

--- Start objective tracker
function DMS.Objectives.start()
    if DMS.Objectives.Active then
        return
    end

    DMS.Objectives.Active = true

    -- Start condition checker
    DMS.Objectives.CheckTimerId = timer.scheduleFunction(
        checkConditions,
        nil,
        timer.getTime() + (tonumber(DMS.Objectives.Config.checkInterval) or 10)
    )

    -- Start HUD refresh if enabled
    if DMS.Objectives.Config.trackOnHUD then
        DMS.Objectives.TimerId = timer.scheduleFunction(
            refreshHUD,
            nil,
            timer.getTime() + 5
        )
    end

    if isDebug() then
        local count = 0
        for _ in pairs(DMS.Objectives.List) do count = count + 1 end
        env.info(string.format("[Objectives] Started tracking %d objectives (interval: %ss)",
            count, tostring(DMS.Objectives.Config.checkInterval)))
    end
end

--- Stop objective tracker
function DMS.Objectives.stop()
    DMS.Objectives.Active = false
    if DMS.Objectives.TimerId then
        pcall(timer.removeFunction, DMS.Objectives.TimerId)
        DMS.Objectives.TimerId = nil
    end
    if DMS.Objectives.CheckTimerId then
        pcall(timer.removeFunction, DMS.Objectives.CheckTimerId)
        DMS.Objectives.CheckTimerId = nil
    end
    if isDebug() then
        env.info("[Objectives] Stopped")
    end
end

--- Check if all required objectives are complete
-- @return boolean True if all non-optional objectives complete
function DMS.Objectives.allComplete()
    for _, obj in pairs(DMS.Objectives.List) do
        if not obj.isOptional and
           obj.status ~= DMS.Objectives.Status.COMPLETED then
            return false
        end
    end
    return true
end

--- Check if any required objective has failed
-- @return boolean True if any non-optional objective failed
function DMS.Objectives.anyFailed()
    for _, obj in pairs(DMS.Objectives.List) do
        if not obj.isOptional and
           obj.status == DMS.Objectives.Status.FAILED then
            return true
        end
    end
    return false
end

--- Get objective status
-- @param id string Objective ID
-- @return number|nil Status code or nil
function DMS.Objectives.getStatus(id)
    local obj = DMS.Objectives.List[id]
    return obj and obj.status or nil
end

--[[
USAGE EXAMPLE:

-- Configure
DMS.Objectives.configure({
    showNotifications = true,
    trackOnHUD = true,
    hudRefreshInterval = 45
})

-- Register objectives
DMS.Objectives.register("destroy_radar", "Destroy enemy radar installation", {
    priority = 1,
    condition = function()
        local group = Group.getByName("Enemy-Radar")
        return not group or not group:isExist()
    end,
    completionMessage = "EXCELLENT! Radar destroyed. SEAD objective complete.",
    onComplete = function()
        -- Reveal next objective
        DMS.Objectives.reveal("destroy_sam")
        DMS.Objectives.activate("destroy_sam")
    end
})

DMS.Objectives.register("destroy_sam", "Neutralize SAM battery", {
    priority = 2,
    isHidden = true,  -- Revealed after radar destroyed
    condition = function()
        local group = Group.getByName("SAM-Battery")
        return not group or not group:isExist()
    end
})

DMS.Objectives.register("rtb", "Return to base", {
    priority = 3,
    isHidden = true,
    condition = function()
        -- Check if player landed at friendly airfield
        return trigger.misc.getUserFlag("player_landed") == 1
    end
})

DMS.Objectives.register("destroy_convoy", "Destroy enemy supply convoy", {
    priority = 10,
    isOptional = true,
    condition = function()
        local group = Group.getByName("Enemy-Convoy")
        return not group or not group:isExist()
    end,
    completionMessage = "Bonus objective complete! Supply convoy destroyed."
})

-- Objective with fail condition
DMS.Objectives.register("protect_friendly", "Protect friendly ground forces", {
    priority = 1,
    failCondition = function()
        local group = Group.getByName("Friendly-Armor")
        if not group or not group:isExist() then
            return true  -- Failed if group destroyed
        end
        local units = group:getUnits()
        local alive = 0
        for _, unit in ipairs(units or {}) do
            if unit:isExist() and unit:getLife() >= 1 then
                alive = alive + 1
            end
        end
        return alive < 2  -- Fail if less than 2 units survive
    end,
    failMessage = "MISSION FAILED: Friendly forces destroyed!"
})

-- Activate initial objectives
DMS.Objectives.activate("destroy_radar")
DMS.Objectives.activate("protect_friendly")

-- Start tracker
DMS.Objectives.start()

-- Add F10 menu to show objectives
missionCommands.addCommandForCoalition(coalition.side.BLUE, "Show Objectives", nil,
    function() DMS.Objectives.showList() end)
]]

-- Export
_G.DMS = DMS
