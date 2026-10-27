-- Persistence Lite System for DCS Missions
-- Save mission state to file for later resumption
-- Note: Requires io (and lfs for automatic save path). Both are sanitized by
-- default in DCS/Scripts/MissionScripting.lua. Without them this module
-- degrades to in-memory state only and logs a single env.warning.
-- Place in mission via DO SCRIPT FILE

DMS = DMS or {}
DMS.Persistence = DMS.Persistence or {}

-- State storage (preserved if the script is loaded twice)
DMS.Persistence.State = DMS.Persistence.State or {}
DMS.Persistence.Active = DMS.Persistence.Active or false
DMS.Persistence.LastSaveTime = DMS.Persistence.LastSaveTime or 0
DMS.Persistence.Available = DMS.Persistence.Available or false  -- io + save path usable
DMS.Persistence._warned = DMS.Persistence._warned or false

-- Configuration
DMS.Persistence.Config = DMS.Persistence.Config or {
    saveFileName = "dms_persistence.lua",
    savePath = nil,          -- Auto-detected via lfs.writedir() if available
    autoSaveInterval = 300,  -- 5 minutes
    saveOnEvent = true,      -- Track destroyed groups via S_EVENT_DEAD
    maxBackups = 3,
    playerCoalition = coalition.side.BLUE,
    notifyPlayers = true,    -- Show save/load messages to players
}

local function isDebug()
    return DMS.Settings and DMS.Settings.isDebug and DMS.Settings.isDebug()
end

local function debugLog(fmt, ...)
    if isDebug() then
        env.info(string.format("[Persistence] " .. fmt, ...))
    end
end

local function logError(context, msg)
    if DMS.Error and DMS.Error.log then
        DMS.Error.log(context, msg)
    else
        env.error("[DMS LUA ERROR] " .. tostring(context) .. ": " .. tostring(msg))
    end
end

local function notify(text, duration)
    if DMS.Persistence.Config.notifyPlayers then
        trigger.action.outTextForCoalition(DMS.Persistence.Config.playerCoalition, text, duration or 5, true)
    end
end

--- Configure persistence system
-- @param settings table Configuration overrides
function DMS.Persistence.configure(settings)
    if type(settings) ~= "table" then return end
    for key, value in pairs(settings) do
        DMS.Persistence.Config[key] = value
    end
end

--- Serialize a value to string (functions/userdata/threads are skipped)
-- @param val any Value to serialize
-- @param indent string Current indentation
-- @param seen table Cycle guard
-- @return string Serialized string
local function serialize(val, indent, seen)
    indent = indent or ""
    seen = seen or {}
    local nextIndent = indent .. "  "

    local t = type(val)

    if t == "nil" then
        return "nil"
    elseif t == "boolean" then
        return val and "true" or "false"
    elseif t == "number" then
        if val ~= val then return "0" end  -- NaN
        if val == math.huge then return "1e999" end
        if val == -math.huge then return "-1e999" end
        return string.format("%.17g", val)
    elseif t == "string" then
        return string.format("%q", val)
    elseif t == "table" then
        if seen[val] then return "nil" end  -- cycle
        seen[val] = true
        local parts = { "{\n" }

        for k, v in pairs(val) do
            local vt = type(v)
            if vt ~= "function" and vt ~= "userdata" and vt ~= "thread" then
                local keyStr
                if type(k) == "number" then
                    keyStr = "[" .. serialize(k) .. "]"
                elseif type(k) == "string" then
                    if k:match("^[%a_][%w_]*$") then
                        keyStr = k
                    else
                        keyStr = "[" .. string.format("%q", k) .. "]"
                    end
                elseif type(k) == "boolean" then
                    keyStr = "[" .. tostring(k) .. "]"
                end
                if keyStr then
                    table.insert(parts, nextIndent .. keyStr .. " = " .. serialize(v, nextIndent, seen) .. ",\n")
                end
            end
        end

        seen[val] = nil
        table.insert(parts, indent .. "}")
        return table.concat(parts)
    end
    return "nil"  -- Skip functions, userdata, etc.
end

--- Deserialize file content. Accepts content with or without a leading
-- "return" (save() writes "return {...}"; older files may be a bare table).
-- @param str string Serialized string
-- @return any Deserialized value
local function deserialize(str)
    if type(str) ~= "string" or str == "" then return nil end
    local chunk = str
    if not chunk:match("^%s*return[%s{]") then
        chunk = "return " .. chunk
    end
    local func, err = loadstring(chunk)
    if not func then
        logError("Persistence.deserialize", err)
        return nil
    end
    -- Data only: run in an empty environment
    if setfenv then setfenv(func, {}) end
    local ok, result = pcall(func)
    if ok then return result end
    logError("Persistence.deserialize", result)
    return nil
end

-- Exposed for testing
DMS.Persistence._serialize = serialize
DMS.Persistence._deserialize = deserialize

--- Get save file path
-- @return string|nil Path or nil if not available
local function getSavePath()
    if DMS.Persistence.Config.savePath then
        return DMS.Persistence.Config.savePath
    end

    -- lfs is removed by MissionScripting.lua sanitization by default
    if type(lfs) == "table" and type(lfs.writedir) == "function" then
        local ok, path = pcall(lfs.writedir)
        if ok and type(path) == "string" then
            DMS.Persistence.Config.savePath = path .. "Missions/"
            return DMS.Persistence.Config.savePath
        end
    end

    return nil
end

--- Check whether file persistence can work in this environment.
-- @return boolean available, string|nil reason
function DMS.Persistence.isAvailable()
    if type(io) ~= "table" or type(io.open) ~= "function" then
        return false, "'io' library is not available (sanitized in MissionScripting.lua)"
    end
    if not getSavePath() then
        return false, "no save path ('lfs' is not available and Config.savePath is not set)"
    end
    return true, nil
end

local function checkAvailable()
    local ok, reason = DMS.Persistence.isAvailable()
    DMS.Persistence.Available = ok
    if not ok and not DMS.Persistence._warned then
        DMS.Persistence._warned = true
        env.warning("[Persistence] File persistence disabled: " .. tostring(reason) ..
            ". State is kept in memory for this session only. To enable, de-sanitize io/lfs in " ..
            "DCS/Scripts/MissionScripting.lua (or provide Config.savePath with io available).")
    end
    return ok, reason
end

--- Save state to file
-- @return boolean Success
function DMS.Persistence.save()
    local available, reason = checkAvailable()
    if not available then
        debugLog("Save skipped: %s", tostring(reason))
        return false
    end
    local path = getSavePath()

    -- Add timestamp
    DMS.Persistence.State._timestamp = timer.getTime()
    DMS.Persistence.State._missionTime = timer.getAbsTime()

    -- File content is a complete chunk ("return {...}"); load() handles it as-is
    local content = "return " .. serialize(DMS.Persistence.State)
    local fullPath = path .. DMS.Persistence.Config.saveFileName

    local okOpen, file, err = pcall(io.open, fullPath, "w")
    if okOpen and file then
        local okWrite, werr = pcall(function()
            file:write(content)
            file:close()
        end)
        if not okWrite then
            logError("Persistence.save", werr)
            return false
        end
        DMS.Persistence.LastSaveTime = timer.getTime()
        debugLog("Saved state to %s (%d bytes)", fullPath, #content)
        notify("Mission state saved.", 5)
        return true
    end

    local msg = okOpen and err or file
    env.warning("[Persistence] Save failed: " .. tostring(msg or "unknown error"))
    notify("Persistence: Save failed - " .. tostring(msg or "unknown error"), 10)
    return false
end

--- Load state from file
-- @return boolean Success
function DMS.Persistence.load()
    local available, reason = checkAvailable()
    if not available then
        debugLog("Load skipped: %s", tostring(reason))
        return false
    end

    local fullPath = getSavePath() .. DMS.Persistence.Config.saveFileName

    local okOpen, file = pcall(io.open, fullPath, "r")
    if okOpen and file then
        local okRead, content = pcall(function()
            local c = file:read("*all")
            file:close()
            return c
        end)
        if not okRead then
            logError("Persistence.load", content)
            return false
        end

        local data = deserialize(content)
        if type(data) == "table" then
            DMS.Persistence.State = data
            debugLog("Loaded state from %s", fullPath)
            notify("Mission state loaded from previous session.", 10)
            return true
        end
        env.warning("[Persistence] Save file is invalid, ignoring: " .. fullPath)
    else
        debugLog("No save file at %s", fullPath)
    end

    return false
end

--- Set a persistent value
-- @param key string Key name
-- @param value any Value to store
function DMS.Persistence.set(key, value)
    DMS.Persistence.State[key] = value
end

--- Get a persistent value
-- @param key string Key name
-- @param default any Default if not found
-- @return any Stored value or default
function DMS.Persistence.get(key, default)
    local val = DMS.Persistence.State[key]
    if val ~= nil then
        return val
    end
    return default
end

--- Remove a persistent value
-- @param key string Key name
function DMS.Persistence.remove(key)
    DMS.Persistence.State[key] = nil
end

--- Clear all persistent state
function DMS.Persistence.clear()
    DMS.Persistence.State = {}
end

--- Track group destruction state
-- @param groupNames table Groups to track
function DMS.Persistence.trackGroups(groupNames)
    if type(groupNames) ~= "table" then return end
    if not DMS.Persistence.State._trackedGroups then
        DMS.Persistence.State._trackedGroups = {}
    end

    for _, name in ipairs(groupNames) do
        DMS.Persistence.State._trackedGroups[name] = true
    end
    debugLog("Tracking %d groups", #groupNames)
end

--- Restore destroyed groups (remove from mission)
function DMS.Persistence.restoreGroupState()
    local destroyed = DMS.Persistence.get("_destroyedGroups", {})

    for groupName, _ in pairs(destroyed) do
        local group = Group.getByName(groupName)
        if group and group:isExist() then
            group:destroy()
            debugLog("Removed previously destroyed group '%s'", tostring(groupName))
        end
    end
end

--- Record group as destroyed
-- @param groupName string Group name
function DMS.Persistence.recordDestroyed(groupName)
    if not DMS.Persistence.State._destroyedGroups then
        DMS.Persistence.State._destroyedGroups = {}
    end
    DMS.Persistence.State._destroyedGroups[groupName] = true
    debugLog("Recorded group '%s' as destroyed", tostring(groupName))
end

--- Auto-save timer: pcall-guarded, keeps rescheduling while active
local function autoSave(_, time)
    if not DMS.Persistence.Active then
        return nil
    end
    local success, result = pcall(DMS.Persistence.save)
    if not success then
        logError("Persistence.autoSave", result)
    end
    local interval = tonumber(DMS.Persistence.Config.autoSaveInterval) or 300
    if interval <= 0 then return nil end
    return time + interval
end

--- Check (deferred) whether a tracked group is fully destroyed
local function handleDeadEvent(event)
    local unit = event.initiator
    if not unit or type(unit.getCategory) ~= "function" then return end
    local okCat, cat = pcall(unit.getCategory, unit)
    if not okCat or cat ~= Object.Category.UNIT then return end

    local okG, group = pcall(unit.getGroup, unit)
    if not okG or not group then return end
    local okN, groupName = pcall(group.getName, group)
    if not okN or not groupName then return end

    local tracked = DMS.Persistence.State._trackedGroups
    if not (tracked and tracked[groupName]) then return end

    -- Defer: the dying unit may still report as existing during this event
    timer.scheduleFunction(function()
        local ok, err = pcall(function()
            local g = Group.getByName(groupName)
            local allDead = true
            if g and g:isExist() then
                for _, u in ipairs(g:getUnits() or {}) do
                    if u and u:isExist() and u:getLife() >= 1 then
                        allDead = false
                        break
                    end
                end
            end
            if allDead then
                DMS.Persistence.recordDestroyed(groupName)
            end
        end)
        if not ok then logError("Persistence.deadCheck", err) end
        return nil
    end, nil, timer.getTime() + 1)
end

--- Start persistence system
function DMS.Persistence.start()
    if DMS.Persistence.Active then
        return
    end

    DMS.Persistence.Active = true
    checkAvailable()

    -- Try to load existing state, then restore group states
    local ok, err = pcall(DMS.Persistence.load)
    if not ok then logError("Persistence.load", err) end
    ok, err = pcall(DMS.Persistence.restoreGroupState)
    if not ok then logError("Persistence.restoreGroupState", err) end

    -- Start auto-save (only meaningful if file access is available)
    local interval = tonumber(DMS.Persistence.Config.autoSaveInterval) or 0
    if interval > 0 and DMS.Persistence.Available then
        DMS.Persistence.TimerId = timer.scheduleFunction(autoSave, nil, timer.getTime() + interval)
    end

    -- Add event handler for tracking destructions (once)
    if DMS.Persistence.Config.saveOnEvent and not DMS.Persistence.EventHandler then
        DMS.Persistence._EventHandlerInternal = {
            onEvent = function(self, event)
                if not DMS.Persistence.Active or not event then return end
                if event.id == world.event.S_EVENT_DEAD
                    or (world.event.S_EVENT_UNIT_LOST and event.id == world.event.S_EVENT_UNIT_LOST) then
                    handleDeadEvent(event)
                end
            end
        }
        if DMS.Error and DMS.Error.safeHandler then
            DMS.Persistence.EventHandler = DMS.Error.safeHandler(
                DMS.Persistence._EventHandlerInternal,
                "Persistence.EventHandler"
            )
        else
            DMS.Persistence.EventHandler = {
                onEvent = function(self, event)
                    local okE, errE = pcall(DMS.Persistence._EventHandlerInternal.onEvent,
                        DMS.Persistence._EventHandlerInternal, event)
                    if not okE then logError("Persistence.EventHandler", errE) end
                end
            }
        end
        world.addEventHandler(DMS.Persistence.EventHandler)
    end

    debugLog("Started (file persistence: %s, autosave: %ss)",
        DMS.Persistence.Available and "ON" or "OFF - memory only", tostring(interval))
end

--- Stop persistence system
function DMS.Persistence.stop()
    DMS.Persistence.Active = false
    if DMS.Persistence.TimerId then
        pcall(timer.removeFunction, DMS.Persistence.TimerId)
        DMS.Persistence.TimerId = nil
    end
    if DMS.Persistence.EventHandler then
        pcall(world.removeEventHandler, DMS.Persistence.EventHandler)
        DMS.Persistence.EventHandler = nil
    end
    debugLog("Stopped")
end

--- Manual save trigger
-- @return boolean Success
function DMS.Persistence.quickSave()
    local ok = DMS.Persistence.save()
    if not ok and not DMS.Persistence.Available then
        notify("Persistence unavailable: file access (io/lfs) is disabled in this DCS install.", 10)
    end
    return ok
end

--[[
USAGE EXAMPLE:

-- Configure
DMS.Persistence.configure({
    saveFileName = "my_mission_state.lua",
    autoSaveInterval = 180,  -- 3 minutes
    saveOnEvent = true
})

-- Track specific groups for destruction persistence
DMS.Persistence.trackGroups({
    "Enemy-SAM-1", "Enemy-SAM-2",
    "Enemy-Convoy",
    "Enemy-HQ"
})

-- Start system (will load previous state if exists)
DMS.Persistence.start()

-- Store custom values
DMS.Persistence.set("mission_phase", 2)
DMS.Persistence.set("player_score", 1500)
DMS.Persistence.set("objectives_complete", {"radar", "sam1"})

-- Retrieve values
local phase = DMS.Persistence.get("mission_phase", 1)
local score = DMS.Persistence.get("player_score", 0)

-- Add F10 commands
missionCommands.addCommandForCoalition(coalition.side.BLUE, "Quick Save", nil,
    function() DMS.Persistence.quickSave() end)

-- NOTE: io and lfs are sanitized by default in DCS/Scripts/MissionScripting.lua.
-- Check DMS.Persistence.isAvailable() - without file access the module keeps
-- state in memory only (set/get still work for the current session).
]]

-- Export
_G.DMS = DMS
