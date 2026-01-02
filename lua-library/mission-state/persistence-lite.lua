-- Persistence Lite System for DCS Missions
-- Save mission state to file for later resumption
-- Note: Requires lfs (LuaFileSystem) - may have permission restrictions
-- Place in mission via DO SCRIPT FILE

DMS = DMS or {}
DMS.Persistence = {}

-- State storage
DMS.Persistence.State = {}
DMS.Persistence.Active = false
DMS.Persistence.TimerId = nil
DMS.Persistence.LastSaveTime = 0

-- Configuration
DMS.Persistence.Config = {
    saveFileName = "dms_persistence.lua",
    savePath = nil,  -- Will try to auto-detect
    autoSaveInterval = 300,  -- 5 minutes
    saveOnEvent = true,      -- Save on significant events
    maxBackups = 3,
    playerCoalition = coalition.side.BLUE,
}

--- Configure persistence system
-- @param settings table Configuration overrides
function DMS.Persistence.configure(settings)
    for key, value in pairs(settings) do
        DMS.Persistence.Config[key] = value
    end
end

--- Serialize a value to string
-- @param val any Value to serialize
-- @param indent string Current indentation
-- @return string Serialized string
local function serialize(val, indent)
    indent = indent or ""
    local nextIndent = indent .. "  "

    local t = type(val)

    if t == "nil" then
        return "nil"
    elseif t == "boolean" then
        return val and "true" or "false"
    elseif t == "number" then
        return tostring(val)
    elseif t == "string" then
        return string.format("%q", val)
    elseif t == "table" then
        local parts = {}
        table.insert(parts, "{\n")

        for k, v in pairs(val) do
            local keyStr
            if type(k) == "number" then
                keyStr = "[" .. k .. "]"
            elseif type(k) == "string" then
                if k:match("^[%a_][%w_]*$") then
                    keyStr = k
                else
                    keyStr = "[" .. string.format("%q", k) .. "]"
                end
            else
                keyStr = "[" .. tostring(k) .. "]"
            end

            table.insert(parts, nextIndent .. keyStr .. " = " .. serialize(v, nextIndent) .. ",\n")
        end

        table.insert(parts, indent .. "}")
        return table.concat(parts)
    else
        return "nil"  -- Skip functions, userdata, etc.
    end
end

--- Deserialize a string to value
-- @param str string Serialized string
-- @return any Deserialized value
local function deserialize(str)
    local func, err = loadstring("return " .. str)
    if func then
        return func()
    end
    return nil
end

--- Get save file path
-- @return string|nil Path or nil if not available
local function getSavePath()
    if DMS.Persistence.Config.savePath then
        return DMS.Persistence.Config.savePath
    end

    -- Try to use lfs if available
    if lfs then
        local path = lfs.writedir()
        if path then
            DMS.Persistence.Config.savePath = path .. "Missions/"
            return DMS.Persistence.Config.savePath
        end
    end

    return nil
end

--- Save state to file
-- @return boolean Success
function DMS.Persistence.save()
    local path = getSavePath()
    if not path then
        trigger.action.outTextForCoalition(
            DMS.Persistence.Config.playerCoalition,
            "Persistence: Unable to determine save path",
            5,
            true
        )
        return false
    end

    -- Add timestamp
    DMS.Persistence.State._timestamp = timer.getTime()
    DMS.Persistence.State._missionTime = timer.getAbsTime()

    local content = "return " .. serialize(DMS.Persistence.State)
    local fullPath = path .. DMS.Persistence.Config.saveFileName

    -- Try to save
    local file, err = io.open(fullPath, "w")
    if file then
        file:write(content)
        file:close()
        DMS.Persistence.LastSaveTime = timer.getTime()

        trigger.action.outTextForCoalition(
            DMS.Persistence.Config.playerCoalition,
            "Mission state saved.",
            5,
            true
        )
        return true
    else
        trigger.action.outTextForCoalition(
            DMS.Persistence.Config.playerCoalition,
            "Persistence: Save failed - " .. (err or "unknown error"),
            10,
            true
        )
        return false
    end
end

--- Load state from file
-- @return boolean Success
function DMS.Persistence.load()
    local path = getSavePath()
    if not path then
        return false
    end

    local fullPath = path .. DMS.Persistence.Config.saveFileName

    local file, err = io.open(fullPath, "r")
    if file then
        local content = file:read("*all")
        file:close()

        local data = deserialize(content)
        if data then
            DMS.Persistence.State = data

            trigger.action.outTextForCoalition(
                DMS.Persistence.Config.playerCoalition,
                "Mission state loaded from previous session.",
                10,
                true
            )
            return true
        end
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
    if not DMS.Persistence.State._trackedGroups then
        DMS.Persistence.State._trackedGroups = {}
    end

    for _, name in ipairs(groupNames) do
        DMS.Persistence.State._trackedGroups[name] = true
    end
end

--- Restore destroyed groups (remove from mission)
function DMS.Persistence.restoreGroupState()
    local destroyed = DMS.Persistence.get("_destroyedGroups", {})

    for groupName, _ in pairs(destroyed) do
        local group = Group.getByName(groupName)
        if group and group:isExist() then
            group:destroy()
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
end

--- Auto-save timer (internal)
local function autoSaveInternal(_, time)
    if not DMS.Persistence.Active then
        return nil
    end

    DMS.Persistence.save()

    return time + DMS.Persistence.Config.autoSaveInterval
end

--- Auto-save timer with error handling
local function autoSave(args, time)
    local success, result = pcall(autoSaveInternal, args, time)
    if not success then
        if DMS.Error then
            DMS.Error.log("Persistence.autoSave", result)
        else
            env.error("[DMS LUA ERROR] Persistence.autoSave: " .. tostring(result))
        end
        return time + (DMS.Persistence.Config.autoSaveInterval or 300)
    end
    return result
end

--- Start persistence system
function DMS.Persistence.start()
    if DMS.Persistence.Active then
        return
    end

    DMS.Persistence.Active = true

    -- Try to load existing state
    DMS.Persistence.load()

    -- Restore group states
    DMS.Persistence.restoreGroupState()

    -- Start auto-save
    if DMS.Persistence.Config.autoSaveInterval > 0 then
        DMS.Persistence.TimerId = timer.scheduleFunction(
            autoSave,
            nil,
            timer.getTime() + DMS.Persistence.Config.autoSaveInterval
        )
    end

    -- Add event handler for tracking destructions
    if DMS.Persistence.Config.saveOnEvent then
        DMS.Persistence._EventHandlerInternal = {
            onEvent = function(self, event)
                if event.id == world.event.S_EVENT_DEAD then
                    local unit = event.initiator
                    if unit then
                        local group = unit:getGroup()
                        if group then
                            local groupName = group:getName()
                            if DMS.Persistence.State._trackedGroups and
                               DMS.Persistence.State._trackedGroups[groupName] then
                                -- Check if group is fully destroyed
                                local units = group:getUnits()
                                local allDead = true
                                if units then
                                    for _, u in ipairs(units) do
                                        if u:isExist() and u:getLife() >= 1 then
                                            allDead = false
                                            break
                                        end
                                    end
                                end
                                if allDead then
                                    DMS.Persistence.recordDestroyed(groupName)
                                end
                            end
                        end
                    end
                end
            end
        }
        -- Wrap event handler with error protection
        DMS.Persistence.EventHandler = DMS.Error.safeHandler(
            DMS.Persistence._EventHandlerInternal,
            "Persistence.EventHandler"
        )
        world.addEventHandler(DMS.Persistence.EventHandler)
    end
end

--- Stop persistence system
function DMS.Persistence.stop()
    DMS.Persistence.Active = false
    if DMS.Persistence.TimerId then
        timer.removeFunction(DMS.Persistence.TimerId)
        DMS.Persistence.TimerId = nil
    end
end

--- Manual save trigger
function DMS.Persistence.quickSave()
    DMS.Persistence.save()
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

-- At mission end or critical points
-- DMS.Persistence.save()

-- NOTE: This requires proper file permissions.
-- DCS's Lua sandbox may restrict file operations.
-- This works best with missions that allow lfs access
-- or when run from the Mission Editor.
]]

-- Export
_G.DMS = DMS
