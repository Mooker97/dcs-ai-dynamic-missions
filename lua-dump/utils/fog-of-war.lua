-- Fog of War System for DCS Missions
-- Hides enemy units from F10 map until detected
-- Requires: utils/mission-settings.lua
-- Place in mission via DO SCRIPT FILE (after mission-settings.lua)

DMS = DMS or {}
DMS.FogOfWar = {}

-- ============================================================
-- STATE TRACKING
-- ============================================================

-- Units that have been revealed to each coalition
-- Key: coalition side, Value: table of unit names
DMS.FogOfWar.RevealedUnits = {
    [coalition.side.RED] = {},
    [coalition.side.BLUE] = {},
    [coalition.side.NEUTRAL] = {},
}

-- Groups spawned as hidden (need tracking for reveal)
DMS.FogOfWar.HiddenGroups = {}

-- Running state
DMS.FogOfWar.Running = false
DMS.FogOfWar.CheckScheduleID = nil

-- ============================================================
-- CONFIGURATION
-- ============================================================

DMS.FogOfWar.Config = {
    checkInterval = 3,          -- Seconds between proximity checks
    revealRange = 5000,         -- Default detection range (meters)
    revealOnRadar = true,       -- Reveal when detected by radar
    revealOnVisual = true,      -- Reveal on visual contact
    revealOnDamage = true,      -- Reveal when dealing/taking damage
    announceReveals = false,    -- Notify player when units revealed
}

--- Configure fog of war system
-- @param settings table Configuration overrides
function DMS.FogOfWar.configure(settings)
    for key, value in pairs(settings or {}) do
        DMS.FogOfWar.Config[key] = value
    end

    -- Sync with mission settings if available
    if DMS.Settings then
        DMS.FogOfWar.Config.revealRange = DMS.Settings.get("fogOfWarRevealRange") or DMS.FogOfWar.Config.revealRange
        DMS.FogOfWar.Config.revealOnRadar = DMS.Settings.get("fogOfWarRevealOnRadar")
        DMS.FogOfWar.Config.revealOnVisual = DMS.Settings.get("fogOfWarRevealOnVisual")
        DMS.FogOfWar.Config.revealOnDamage = DMS.Settings.get("fogOfWarRevealOnDamage")
    end
end

-- ============================================================
-- CORE FUNCTIONS
-- ============================================================

--- Register a group as hidden (called by spawn functions)
-- @param groupName string Group name
-- @param ownerCoalition number Coalition that owns this group
function DMS.FogOfWar.registerHiddenGroup(groupName, ownerCoalition)
    DMS.FogOfWar.HiddenGroups[groupName] = {
        name = groupName,
        owner = ownerCoalition,
        revealed = false,
        revealedTo = {},
    }

    if DMS.Settings and DMS.Settings.isDebug() then
        env.info(string.format("[FOW] Registered hidden group: %s", groupName))
    end
end

--- Reveal a group to a coalition
-- @param groupName string Group to reveal
-- @param toCoalition number Coalition to reveal to
-- @param reason string|nil Reason for reveal (for logging)
function DMS.FogOfWar.revealGroup(groupName, toCoalition, reason)
    local hidden = DMS.FogOfWar.HiddenGroups[groupName]
    if not hidden then
        return false
    end

    -- Already revealed to this coalition?
    if hidden.revealedTo[toCoalition] then
        return false
    end

    -- Mark as revealed
    hidden.revealedTo[toCoalition] = true
    hidden.revealed = true

    -- Get the group and reveal it
    local group = Group.getByName(groupName)
    if group then
        -- Use DCS controller to make group known
        local controller = group:getController()
        if controller then
            -- This makes the group visible on the F10 map
            trigger.action.groupKnown(groupName, toCoalition, true)
        end

        -- Mark all units as revealed
        for _, unit in ipairs(group:getUnits() or {}) do
            local unitName = unit:getName()
            DMS.FogOfWar.RevealedUnits[toCoalition][unitName] = true
        end
    end

    -- Announce if configured
    if DMS.FogOfWar.Config.announceReveals then
        local msg = string.format("Contact! Enemy forces detected%s",
            reason and (" - " .. reason) or "")
        trigger.action.outTextForCoalition(toCoalition, msg, 5)
    end

    if DMS.Settings and DMS.Settings.isDebug() then
        env.info(string.format("[FOW] Revealed %s to coalition %d (%s)",
            groupName, toCoalition, reason or "unknown"))
    end

    return true
end

--- Reveal a unit to a coalition
-- @param unitName string Unit to reveal
-- @param toCoalition number Coalition to reveal to
function DMS.FogOfWar.revealUnit(unitName, toCoalition)
    local unit = Unit.getByName(unitName)
    if not unit then return false end

    local group = unit:getGroup()
    if group then
        return DMS.FogOfWar.revealGroup(group:getName(), toCoalition, "unit detected")
    end

    return false
end

--- Check if a group is revealed to a coalition
-- @param groupName string Group name
-- @param toCoalition number Coalition to check
-- @return boolean
function DMS.FogOfWar.isRevealed(groupName, toCoalition)
    local hidden = DMS.FogOfWar.HiddenGroups[groupName]
    if not hidden then
        return true  -- Not tracked = visible
    end
    return hidden.revealedTo[toCoalition] == true
end

-- ============================================================
-- DETECTION CHECKS
-- ============================================================

--- Check proximity-based detection
local function checkProximityDetection()
    local playerCoalition = DMS.Settings and DMS.Settings.getPlayerCoalition() or coalition.side.BLUE
    local revealRange = DMS.FogOfWar.Config.revealRange

    -- Get all player units
    local playerUnits = {}
    for _, groupData in pairs(coalition.getGroups(playerCoalition) or {}) do
        local group = Group.getByName(groupData:getName())
        if group then
            for _, unit in ipairs(group:getUnits() or {}) do
                if unit:isExist() then
                    table.insert(playerUnits, unit)
                end
            end
        end
    end

    -- Check each hidden group
    for groupName, hidden in pairs(DMS.FogOfWar.HiddenGroups) do
        if not hidden.revealedTo[playerCoalition] then
            local group = Group.getByName(groupName)
            if group and group:isExist() then
                local groupUnits = group:getUnits() or {}

                for _, enemyUnit in ipairs(groupUnits) do
                    if enemyUnit:isExist() then
                        local enemyPos = enemyUnit:getPoint()

                        for _, playerUnit in ipairs(playerUnits) do
                            local playerPos = playerUnit:getPoint()
                            local dist = math.sqrt(
                                (enemyPos.x - playerPos.x)^2 +
                                (enemyPos.y - playerPos.y)^2 +
                                (enemyPos.z - playerPos.z)^2
                            )

                            if dist <= revealRange then
                                DMS.FogOfWar.revealGroup(groupName, playerCoalition, "proximity")
                                break
                            end
                        end
                    end
                end
            end
        end
    end
end

--- Schedule periodic proximity checks
local function scheduleProximityCheck()
    if not DMS.FogOfWar.Running then return end

    checkProximityDetection()

    DMS.FogOfWar.CheckScheduleID = timer.scheduleFunction(function()
        scheduleProximityCheck()
        return nil
    end, nil, timer.getTime() + DMS.FogOfWar.Config.checkInterval)
end

-- ============================================================
-- EVENT HANDLERS
-- ============================================================

DMS.FogOfWar.EventHandler = {
    onEvent = function(self, event)
        if not DMS.FogOfWar.Running then return end

        local playerCoalition = DMS.Settings and DMS.Settings.getPlayerCoalition() or coalition.side.BLUE

        -- Reveal on damage
        if DMS.FogOfWar.Config.revealOnDamage then
            if event.id == world.event.S_EVENT_HIT or
               event.id == world.event.S_EVENT_DEAD or
               event.id == world.event.S_EVENT_KILL then

                -- Reveal the target
                if event.target then
                    local group = event.target:getGroup()
                    if group then
                        local targetCoalition = event.target:getCoalition()
                        if targetCoalition ~= playerCoalition then
                            DMS.FogOfWar.revealGroup(group:getName(), playerCoalition, "combat")
                        end
                    end
                end

                -- Reveal the attacker
                if event.initiator then
                    local group = event.initiator:getGroup()
                    if group then
                        local initiatorCoalition = event.initiator:getCoalition()
                        if initiatorCoalition ~= playerCoalition then
                            DMS.FogOfWar.revealGroup(group:getName(), playerCoalition, "engaged")
                        end
                    end
                end
            end
        end

        -- Reveal on shooting (even if miss)
        if event.id == world.event.S_EVENT_SHOT then
            if event.initiator and DMS.FogOfWar.Config.revealOnDamage then
                local group = event.initiator:getGroup()
                if group then
                    local shooterCoalition = event.initiator:getCoalition()
                    if shooterCoalition ~= playerCoalition then
                        DMS.FogOfWar.revealGroup(group:getName(), playerCoalition, "firing")
                    end
                end
            end
        end
    end
}

-- ============================================================
-- SPAWN INTEGRATION
-- ============================================================

--- Spawn a group with fog of war handling
-- Use this instead of coalition.addGroup() when fog of war may be active
-- @param countryId number Country ID
-- @param category number Group category (Group.Category.GROUND, etc)
-- @param groupData table Group spawn data
-- @param hidden boolean|nil Override hidden state (nil = use settings)
-- @return Group|nil Spawned group
function DMS.FogOfWar.spawnGroup(countryId, category, groupData, hidden)
    -- Determine if should be hidden
    local shouldHide = hidden
    if shouldHide == nil then
        shouldHide = DMS.Settings and DMS.Settings.getSpawnHidden() or false
    end

    -- Set hidden flag in group data
    groupData.hidden = shouldHide

    -- Spawn the group
    local group = coalition.addGroup(countryId, category, groupData)

    -- Register for tracking if hidden
    if shouldHide and group then
        local ownerCoalition = group:getCoalition()
        DMS.FogOfWar.registerHiddenGroup(groupData.name, ownerCoalition)
    end

    return group
end

--- Activate a Late Activation group with fog of war handling
-- @param groupName string Group name (must be Late Activation in ME)
-- @param hidden boolean|nil Override hidden state
-- @return boolean Success
function DMS.FogOfWar.activateGroup(groupName, hidden)
    local group = Group.getByName(groupName)
    if not group then
        return false
    end

    -- Determine if should be hidden
    local shouldHide = hidden
    if shouldHide == nil then
        shouldHide = DMS.Settings and DMS.Settings.getSpawnHidden() or false
    end

    -- Activate the group
    trigger.action.activateGroup(group)

    -- If should be hidden, mark as unknown to enemy coalition
    if shouldHide then
        local ownerCoalition = group:getCoalition()
        local enemyCoalition = DMS.Settings and DMS.Settings.getEnemyCoalition() or coalition.side.RED

        -- Determine who to hide from
        local hideFrom = (ownerCoalition == enemyCoalition)
            and (DMS.Settings and DMS.Settings.getPlayerCoalition() or coalition.side.BLUE)
            or enemyCoalition

        -- Register as hidden
        DMS.FogOfWar.registerHiddenGroup(groupName, ownerCoalition)

        -- Make group unknown (hidden on F10 map)
        -- Note: This is the key DCS function for fog of war
        trigger.action.groupKnown(groupName, hideFrom, false)
    end

    return true
end

-- ============================================================
-- CONTROL FUNCTIONS
-- ============================================================

--- Start the fog of war system
function DMS.FogOfWar.start()
    if DMS.FogOfWar.Running then return end

    DMS.FogOfWar.Running = true

    -- Sync config with settings
    DMS.FogOfWar.configure({})

    -- Register event handler
    world.addEventHandler(DMS.FogOfWar.EventHandler)

    -- Start proximity checks
    scheduleProximityCheck()

    if DMS.Settings and DMS.Settings.isDebug() then
        env.info("[FOW] Fog of War system started")
    end
end

--- Stop the fog of war system
function DMS.FogOfWar.stop()
    DMS.FogOfWar.Running = false

    if DMS.FogOfWar.CheckScheduleID then
        timer.removeFunction(DMS.FogOfWar.CheckScheduleID)
        DMS.FogOfWar.CheckScheduleID = nil
    end

    if DMS.Settings and DMS.Settings.isDebug() then
        env.info("[FOW] Fog of War system stopped")
    end
end

--- Reveal all hidden groups (end of mission, etc)
function DMS.FogOfWar.revealAll()
    local playerCoalition = DMS.Settings and DMS.Settings.getPlayerCoalition() or coalition.side.BLUE

    for groupName, _ in pairs(DMS.FogOfWar.HiddenGroups) do
        DMS.FogOfWar.revealGroup(groupName, playerCoalition, "mission end")
    end
end

--- Get statistics
-- @return table {totalHidden, revealed, stillHidden}
function DMS.FogOfWar.getStats()
    local total = 0
    local revealed = 0
    local playerCoalition = DMS.Settings and DMS.Settings.getPlayerCoalition() or coalition.side.BLUE

    for _, hidden in pairs(DMS.FogOfWar.HiddenGroups) do
        total = total + 1
        if hidden.revealedTo[playerCoalition] then
            revealed = revealed + 1
        end
    end

    return {
        totalHidden = total,
        revealed = revealed,
        stillHidden = total - revealed,
    }
end

--[[
USAGE EXAMPLES:

-- Basic setup (in mission init)
DMS.Settings.configure({
    fogOfWar = true,
})
DMS.FogOfWar.start()

-- Spawn a group hidden from F10 map
DMS.FogOfWar.activateGroup("Enemy-AA-1")  -- Uses settings default
DMS.FogOfWar.activateGroup("Enemy-AA-2", true)  -- Force hidden
DMS.FogOfWar.activateGroup("Friendly-Convoy", false)  -- Force visible

-- Manual reveal
DMS.FogOfWar.revealGroup("Enemy-AA-1", coalition.side.BLUE, "intel report")

-- Check stats
local stats = DMS.FogOfWar.getStats()
trigger.action.outText(string.format("Hidden: %d, Revealed: %d", stats.stillHidden, stats.revealed), 10)
]]

-- Export
_G.DMS = DMS
