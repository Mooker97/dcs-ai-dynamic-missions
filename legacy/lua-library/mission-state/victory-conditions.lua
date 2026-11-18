-- Victory Conditions System for DCS Missions
-- Define and track win/lose conditions
-- Requires: utils/messaging.lua
-- Place in mission via DO SCRIPT FILE

DMS = DMS or {}
DMS.Victory = DMS.Victory or {}

-- Condition definitions
DMS.Victory.WinConditions = DMS.Victory.WinConditions or {}
DMS.Victory.LoseConditions = DMS.Victory.LoseConditions or {}
DMS.Victory.Active = DMS.Victory.Active or false
-- DMS.Victory.TimerId: DCS timer id while running
-- DMS.Victory.Result: nil = ongoing, "win", "lose"
DMS.Victory._seenGroups = DMS.Victory._seenGroups or {}

-- Configuration
DMS.Victory.Config = DMS.Victory.Config or {
    playerCoalition = coalition.side.BLUE,
    checkInterval = 5,
    showProgress = true,
    endMissionOnResult = false,  -- Set flag to end mission
    victoryFlag = "mission_victory",
    defeatFlag = "mission_defeat",
    displayDuration = 30,
}

--- Configure victory system
-- @param settings table Configuration overrides
local function isDebug()
    return DMS.Settings and DMS.Settings.isDebug and DMS.Settings.isDebug()
end

local function debugLog(fmt, ...)
    if isDebug() then
        env.info(string.format("[Victory] " .. fmt, ...))
    end
end

local function logError(context, msg)
    if DMS.Error and DMS.Error.log then
        DMS.Error.log(context, msg)
    else
        env.error("[DMS LUA ERROR] " .. tostring(context) .. ": " .. tostring(msg))
    end
end

--- Run a user callback under pcall; returns its result or nil on error
local function safeInvoke(func, context, ...)
    if type(func) ~= "function" then return nil end
    local ok, result = pcall(func, ...)
    if not ok then
        logError(context, result)
        return nil
    end
    return result
end

function DMS.Victory.configure(settings)
    if type(settings) ~= "table" then return end
    for key, value in pairs(settings) do
        DMS.Victory.Config[key] = value
    end
end

--- Register a win condition
-- @param id string Condition ID
-- @param checkFunc function Function returning true when condition met
-- @param options table|nil Condition options
function DMS.Victory.addWinCondition(id, checkFunc, options)
    options = options or {}

    DMS.Victory.WinConditions[id] = {
        id = id,
        check = checkFunc,
        description = options.description or id,
        required = options.required ~= false,  -- Required by default
        met = false,
        weight = options.weight or 1,  -- For partial victory calculation
        onMet = options.onMet,
    }
end

--- Register a lose condition
-- @param id string Condition ID
-- @param checkFunc function Function returning true when condition met
-- @param options table|nil Condition options
function DMS.Victory.addLoseCondition(id, checkFunc, options)
    options = options or {}

    DMS.Victory.LoseConditions[id] = {
        id = id,
        check = checkFunc,
        description = options.description or id,
        instant = options.instant or false,  -- Instant loss if true
        met = false,
        onMet = options.onMet,
    }
end

--- Check if group is destroyed
-- @param groupName string Group name
-- @return boolean True if destroyed or doesn't exist
local function countAliveUnits(groupName)
    local group = Group.getByName(groupName)
    if not group or not group:isExist() then
        return nil  -- group does not exist (never spawned, or fully removed)
    end
    local count = 0
    for _, unit in ipairs(group:getUnits() or {}) do
        if unit and unit:isExist() and unit:getLife() >= 1 then
            count = count + 1
        end
    end
    return count
end

--- A group counts as destroyed only after it has been seen alive at least
-- once. This stops dynamically-spawned (not yet spawned) groups from
-- completing "destroy" objectives instantly.
local function isGroupDestroyed(groupName)
    local alive = countAliveUnits(groupName)
    if alive and alive > 0 then
        DMS.Victory._seenGroups[groupName] = true
        return false
    end
    if not DMS.Victory._seenGroups[groupName] then
        debugLog("Group '%s' not seen alive yet - not counted as destroyed", tostring(groupName))
        return false
    end
    return true
end

--- Check if any group in list is alive
-- @param groupNames table Array of group names
-- @return boolean True if at least one unit alive
local function anyGroupAlive(groupNames)
    for _, name in ipairs(groupNames) do
        if not isGroupDestroyed(name) then
            return true
        end
    end
    return false
end

--- Check if all groups destroyed
-- @param groupNames table Array of group names
-- @return boolean True if all destroyed
local function allGroupsDestroyed(groupNames)
    for _, name in ipairs(groupNames) do
        if not isGroupDestroyed(name) then
            return false
        end
    end
    return true
end

-- Convenience condition creators
DMS.Victory.Conditions = {}

--- Create "destroy all" condition
-- @param groupNames table Groups to destroy
-- @return function Condition check function
function DMS.Victory.Conditions.destroyAll(groupNames)
    return function()
        return allGroupsDestroyed(groupNames)
    end
end

--- Create "destroy any" condition
-- @param groupNames table Groups (destroy at least one)
-- @return function Condition check function
function DMS.Victory.Conditions.destroyAny(groupNames)
    return function()
        for _, name in ipairs(groupNames) do
            if isGroupDestroyed(name) then
                return true
            end
        end
        return false
    end
end

--- Create "protect" condition (group must survive)
-- @param groupNames table Groups to protect
-- @param minSurvivors number|nil Minimum units that must survive
-- @return function Condition check function (returns true if FAILED to protect)
function DMS.Victory.Conditions.protect(groupNames, minSurvivors)
    minSurvivors = minSurvivors or 1

    return function()
        local survivors = 0
        for _, name in ipairs(groupNames) do
            survivors = survivors + (countAliveUnits(name) or 0)
        end
        return survivors < minSurvivors  -- True = failed to protect
    end
end

--- Create flag condition
-- @param flagName string Flag to check
-- @param flagValue number|nil Value to check (default 1)
-- @return function Condition check function
function DMS.Victory.Conditions.flag(flagName, flagValue)
    flagValue = flagValue or 1
    return function()
        return trigger.misc.getUserFlag(flagName) == flagValue
    end
end

--- Create time elapsed condition
-- @param seconds number Seconds that must elapse
-- @return function Condition check function
function DMS.Victory.Conditions.timeElapsed(seconds)
    local startTime = timer.getTime()
    return function()
        return timer.getTime() - startTime >= seconds
    end
end

--- Create player in zone condition
-- @param zoneName string Zone name
-- @return function Condition check function
function DMS.Victory.Conditions.playerInZone(zoneName)
    return function()
        local zone = trigger.misc.getZone(zoneName)
        if not zone then return false end

        local players = coalition.getPlayers(DMS.Victory.Config.playerCoalition)
        if not players then return false end

        for _, player in ipairs(players) do
            if player and player:isExist() then
                local pos = player:getPoint()
                local dx = pos.x - zone.point.x
                local dz = pos.z - zone.point.z
                local dist = math.sqrt(dx * dx + dz * dz)
                if dist <= zone.radius then
                    return true
                end
            end
        end
        return false
    end
end

--- Create no players alive condition
-- @return function Condition check function
function DMS.Victory.Conditions.allPlayersDead()
    return function()
        local players = coalition.getPlayers(DMS.Victory.Config.playerCoalition)
        return not players or #players == 0
    end
end

--- Process victory check (internal)
local function checkVictoryInternal(_, time)
    if not DMS.Victory.Active or DMS.Victory.Result then
        return nil
    end

    -- Check lose conditions first (priority)
    for id, cond in pairs(DMS.Victory.LoseConditions) do
        if not cond.met and safeInvoke(cond.check, "Victory.loseCondition." .. tostring(id)) then
            cond.met = true
            debugLog("Lose condition met: %s (instant=%s)", tostring(cond.description), tostring(cond.instant))
            safeInvoke(cond.onMet, "Victory.loseCondition.onMet." .. tostring(id))

            if cond.instant then
                DMS.Victory.triggerDefeat("Condition failed: " .. cond.description)
                return nil
            end
        end
    end

    -- Check win conditions
    local allRequiredMet = true
    local requiredCount = 0

    for id, cond in pairs(DMS.Victory.WinConditions) do
        if not cond.met and safeInvoke(cond.check, "Victory.winCondition." .. tostring(id)) then
            cond.met = true
            debugLog("Win condition met: %s", tostring(cond.description))
            safeInvoke(cond.onMet, "Victory.winCondition.onMet." .. tostring(id))

            if DMS.Victory.Config.showProgress then
                trigger.action.outTextForCoalition(
                    DMS.Victory.Config.playerCoalition,
                    "OBJECTIVE COMPLETE: " .. cond.description,
                    10,
                    true
                )
            end
        end

        if cond.required then
            requiredCount = requiredCount + 1
            if not cond.met then
                allRequiredMet = false
            end
        end
    end

    -- Check for victory
    if requiredCount > 0 and allRequiredMet then
        DMS.Victory.triggerVictory()
        return nil
    end

    return time + DMS.Victory.Config.checkInterval
end

--- Process victory check with error handling
local function checkVictory(args, time)
    local success, result = pcall(checkVictoryInternal, args, time)
    if not success then
        logError("Victory.checkVictory", result)
        if not DMS.Victory.Active or DMS.Victory.Result then return nil end
        return time + (tonumber(DMS.Victory.Config.checkInterval) or 5)
    end
    if result == nil then
        DMS.Victory.TimerId = nil
    end
    return result
end

--- Trigger victory
-- @param message string|nil Custom message
function DMS.Victory.triggerVictory(message)
    if DMS.Victory.Result then
        return
    end

    DMS.Victory.Result = "win"
    DMS.Victory.Active = false
    debugLog("VICTORY")

    message = message or "=== MISSION SUCCESSFUL ==="

    trigger.action.outTextForCoalition(
        DMS.Victory.Config.playerCoalition,
        message,
        DMS.Victory.Config.displayDuration,
        true
    )

    if DMS.Victory.Config.endMissionOnResult then
        trigger.action.setUserFlag(DMS.Victory.Config.victoryFlag, 1)
    end
end

--- Trigger defeat
-- @param message string|nil Custom message
function DMS.Victory.triggerDefeat(message)
    if DMS.Victory.Result then
        return
    end

    DMS.Victory.Result = "lose"
    DMS.Victory.Active = false
    debugLog("DEFEAT: %s", tostring(message))

    message = message or "=== MISSION FAILED ==="

    trigger.action.outTextForCoalition(
        DMS.Victory.Config.playerCoalition,
        message,
        DMS.Victory.Config.displayDuration,
        true
    )

    if DMS.Victory.Config.endMissionOnResult then
        trigger.action.setUserFlag(DMS.Victory.Config.defeatFlag, 1)
    end
end

--- Start victory tracking
function DMS.Victory.start()
    if DMS.Victory.Active then
        return
    end

    DMS.Victory.Active = true
    DMS.Victory.Result = nil

    DMS.Victory.TimerId = timer.scheduleFunction(
        checkVictory,
        nil,
        timer.getTime() + (tonumber(DMS.Victory.Config.checkInterval) or 5)
    )
    debugLog("Started (%d win, %d lose conditions)",
        (function() local n = 0 for _ in pairs(DMS.Victory.WinConditions) do n = n + 1 end return n end)(),
        (function() local n = 0 for _ in pairs(DMS.Victory.LoseConditions) do n = n + 1 end return n end)())
end

--- Stop victory tracking
function DMS.Victory.stop()
    DMS.Victory.Active = false
    if DMS.Victory.TimerId then
        pcall(timer.removeFunction, DMS.Victory.TimerId)
        DMS.Victory.TimerId = nil
    end
end

--- Get victory progress
-- @return table Progress information
function DMS.Victory.getProgress()
    local progress = {
        result = DMS.Victory.Result,
        winConditions = {},
        loseConditions = {},
        requiredMet = 0,
        requiredTotal = 0,
        optionalMet = 0,
        optionalTotal = 0,
    }

    for id, cond in pairs(DMS.Victory.WinConditions) do
        table.insert(progress.winConditions, {
            id = id,
            description = cond.description,
            met = cond.met,
            required = cond.required,
        })

        if cond.required then
            progress.requiredTotal = progress.requiredTotal + 1
            if cond.met then
                progress.requiredMet = progress.requiredMet + 1
            end
        else
            progress.optionalTotal = progress.optionalTotal + 1
            if cond.met then
                progress.optionalMet = progress.optionalMet + 1
            end
        end
    end

    for id, cond in pairs(DMS.Victory.LoseConditions) do
        table.insert(progress.loseConditions, {
            id = id,
            description = cond.description,
            met = cond.met,
            instant = cond.instant,
        })
    end

    return progress
end

--- Show progress to players
function DMS.Victory.showProgress()
    local progress = DMS.Victory.getProgress()

    local lines = {
        "=== MISSION PROGRESS ===",
        "",
        string.format("Required Objectives: %d/%d", progress.requiredMet, progress.requiredTotal),
    }

    if progress.optionalTotal > 0 then
        table.insert(lines, string.format("Optional Objectives: %d/%d", progress.optionalMet, progress.optionalTotal))
    end

    table.insert(lines, "")
    table.insert(lines, "Objectives:")

    for _, cond in ipairs(progress.winConditions) do
        local status = cond.met and "[X]" or "[ ]"
        local optional = cond.required and "" or " (Optional)"
        table.insert(lines, string.format("  %s %s%s", status, tostring(cond.description), optional))
    end

    trigger.action.outTextForCoalition(
        DMS.Victory.Config.playerCoalition,
        table.concat(lines, "\n"),
        20,
        true
    )
end

--[[
USAGE EXAMPLE:

-- Configure
DMS.Victory.configure({
    showProgress = true,
    endMissionOnResult = true,
    checkInterval = 3
})

-- Add win conditions
DMS.Victory.addWinCondition("destroy_radar",
    DMS.Victory.Conditions.destroyAll({"Enemy-Radar-1", "Enemy-Radar-2"}),
    {
        description = "Destroy enemy radar installations",
        required = true,
        onMet = function()
            trigger.action.outText("Radar network eliminated!", 10)
        end
    }
)

DMS.Victory.addWinCondition("destroy_sam",
    DMS.Victory.Conditions.destroyAll({"SAM-Site-1", "SAM-Site-2"}),
    {
        description = "Destroy SAM batteries",
        required = true
    }
)

DMS.Victory.addWinCondition("destroy_convoy",
    DMS.Victory.Conditions.destroyAll({"Enemy-Convoy"}),
    {
        description = "Destroy enemy supply convoy",
        required = false  -- Optional
    }
)

DMS.Victory.addWinCondition("rtb",
    DMS.Victory.Conditions.playerInZone("RTB-Zone"),
    {
        description = "Return to base",
        required = true
    }
)

-- Add lose conditions
DMS.Victory.addLoseCondition("all_dead",
    DMS.Victory.Conditions.allPlayersDead(),
    {
        description = "All players killed",
        instant = true
    }
)

DMS.Victory.addLoseCondition("friendly_destroyed",
    DMS.Victory.Conditions.protect({"Friendly-Convoy"}, 3),
    {
        description = "Friendly convoy destroyed",
        instant = true,
        onMet = function()
            trigger.action.outText("MISSION FAILED: Friendly forces destroyed!", 30)
        end
    }
)

DMS.Victory.addLoseCondition("timeout",
    DMS.Victory.Conditions.flag("mission_timeout"),
    {
        description = "Mission time expired",
        instant = true
    }
)

-- Start tracking
DMS.Victory.start()

-- Add F10 menu
missionCommands.addCommandForCoalition(coalition.side.BLUE, "Mission Progress", nil,
    function() DMS.Victory.showProgress() end)
]]

-- Export
_G.DMS = DMS
