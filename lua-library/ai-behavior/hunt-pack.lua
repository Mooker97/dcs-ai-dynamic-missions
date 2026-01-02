-- Hunt Pack Coordination for DCS Missions
-- Enemy groups share player position and coordinate attacks
-- Requires: utils/coordinates.lua, utils/group-utils.lua
-- Place in mission via DO SCRIPT FILE

DMS = DMS or {}
DMS.HuntPack = {}

-- Pack state
DMS.HuntPack.Packs = {}
DMS.HuntPack.TimerId = nil
DMS.HuntPack.Active = false

-- Last known player position (shared intel)
DMS.HuntPack.LastKnownPlayerPos = nil
DMS.HuntPack.LastUpdateTime = 0

-- Configuration
DMS.HuntPack.Config = {
    checkInterval = 10,          -- Seconds between coordination checks
    intelDecayTime = 120,        -- Seconds before intel becomes stale
    detectionRange = 15000,      -- Range at which groups detect player
    shareRange = 50000,          -- Range at which groups share intel
    respondRange = 30000,        -- Range at which groups respond to shared intel
    trackingCoalition = coalition.side.BLUE,
    announceDetection = false,
}

--- Configure hunt pack system
-- @param settings table Configuration overrides
function DMS.HuntPack.configure(settings)
    for key, value in pairs(settings) do
        DMS.HuntPack.Config[key] = value
    end
end

--- Create a new hunt pack
-- @param packName string Unique pack identifier
-- @param groupNames table Array of group names in this pack
-- @param behavior string|nil "aggressive", "defensive", or "patrol"
function DMS.HuntPack.createPack(packName, groupNames, behavior)
    DMS.HuntPack.Packs[packName] = {
        name = packName,
        groups = groupNames,
        behavior = behavior or "aggressive",
        lastKnownTarget = nil,
        intelTime = 0,
        active = true,
    }
end

--- Add group to existing pack
-- @param packName string Pack name
-- @param groupName string Group to add
function DMS.HuntPack.addToPack(packName, groupName)
    local pack = DMS.HuntPack.Packs[packName]
    if pack then
        table.insert(pack.groups, groupName)
    end
end

--- Get player positions
-- @return table Array of Vec3 positions
local function getPlayerPositions()
    local positions = {}
    local players = coalition.getPlayers(DMS.HuntPack.Config.trackingCoalition)

    if players then
        for _, unit in ipairs(players) do
            if unit and unit:isExist() then
                table.insert(positions, unit:getPoint())
            end
        end
    end

    return positions
end

--- Get group position
-- @param groupName string Group name
-- @return table|nil Vec3 position
local function getGroupPosition(groupName)
    local group = Group.getByName(groupName)
    if group and group:isExist() then
        local units = group:getUnits()
        if units and #units > 0 and units[1]:isExist() then
            return units[1]:getPoint()
        end
    end
    return nil
end

--- Calculate distance between two Vec3 points
-- @param pos1 table Vec3
-- @param pos2 table Vec3
-- @return number Distance in meters
local function getDistance(pos1, pos2)
    local dx = pos2.x - pos1.x
    local dz = pos2.z - pos1.z
    return math.sqrt(dx * dx + dz * dz)
end

--- Check if any group in pack detects player
-- @param pack table Pack data
-- @param playerPositions table Array of player Vec3
-- @return table|nil Detected player position
local function checkPackDetection(pack, playerPositions)
    for _, groupName in ipairs(pack.groups) do
        local groupPos = getGroupPosition(groupName)
        if groupPos then
            for _, playerPos in ipairs(playerPositions) do
                local dist = getDistance(groupPos, playerPos)
                if dist <= DMS.HuntPack.Config.detectionRange then
                    return playerPos
                end
            end
        end
    end
    return nil
end

--- Share intel with pack members
-- @param pack table Pack data
-- @param targetPos table Target Vec3 position
local function shareIntel(pack, targetPos)
    pack.lastKnownTarget = targetPos
    pack.intelTime = timer.getTime()

    -- Also update global last known
    DMS.HuntPack.LastKnownPlayerPos = targetPos
    DMS.HuntPack.LastUpdateTime = timer.getTime()
end

--- Check if pack has valid intel
-- @param pack table Pack data
-- @return boolean True if intel is still valid
local function hasValidIntel(pack)
    if not pack.lastKnownTarget then
        return false
    end

    local age = timer.getTime() - pack.intelTime
    return age < DMS.HuntPack.Config.intelDecayTime
end

--- Command pack to move toward position
-- @param pack table Pack data
-- @param targetPos table Target Vec3 position
local function commandPackToTarget(pack, targetPos)
    for _, groupName in ipairs(pack.groups) do
        local group = Group.getByName(groupName)
        if group and group:isExist() then
            local groupPos = getGroupPosition(groupName)
            if groupPos then
                local dist = getDistance(groupPos, targetPos)

                -- Only command if within response range
                if dist <= DMS.HuntPack.Config.respondRange then
                    -- For ground units, we could set a waypoint
                    -- For aircraft, we could use setTask
                    -- This is simplified - in practice you'd need unit-type specific commands

                    local controller = group:getController()
                    if controller then
                        -- Set to attack anything at the target area
                        -- This is a basic implementation
                        controller:setOption(AI.Option.Ground.id.ROE, AI.Option.Ground.val.ROE.WEAPON_FREE)
                        controller:setOption(AI.Option.Ground.id.ALARM_STATE, AI.Option.Ground.val.ALARM_STATE.RED)
                    end
                end
            end
        end
    end
end

--- Process hunt pack coordination
local function processHuntPack(_, time)
    if not DMS.HuntPack.Active then
        return nil
    end

    local playerPositions = getPlayerPositions()
    if #playerPositions == 0 then
        return time + DMS.HuntPack.Config.checkInterval
    end

    for packName, pack in pairs(DMS.HuntPack.Packs) do
        if pack.active then
            -- Check if pack detects player
            local detectedPos = checkPackDetection(pack, playerPositions)

            if detectedPos then
                -- Fresh detection - share intel
                shareIntel(pack, detectedPos)

                if DMS.HuntPack.Config.announceDetection then
                    trigger.action.outText("Enemy has detected you!", 5, true)
                end

                -- Command pack to engage
                if pack.behavior == "aggressive" then
                    commandPackToTarget(pack, detectedPos)
                end

            elseif hasValidIntel(pack) then
                -- No direct detection but have intel
                if pack.behavior == "aggressive" then
                    -- Move to last known position
                    commandPackToTarget(pack, pack.lastKnownTarget)
                end
            end
        end
    end

    return time + DMS.HuntPack.Config.checkInterval
end

--- Start hunt pack system
function DMS.HuntPack.start()
    if DMS.HuntPack.Active then
        return
    end

    DMS.HuntPack.Active = true
    DMS.HuntPack.TimerId = timer.scheduleFunction(
        processHuntPack,
        nil,
        timer.getTime() + DMS.HuntPack.Config.checkInterval
    )
end

--- Stop hunt pack system
function DMS.HuntPack.stop()
    DMS.HuntPack.Active = false
    if DMS.HuntPack.TimerId then
        timer.removeFunction(DMS.HuntPack.TimerId)
        DMS.HuntPack.TimerId = nil
    end
end

--- Manually report player position to all packs
-- @param pos table Vec3 position
function DMS.HuntPack.reportPosition(pos)
    for _, pack in pairs(DMS.HuntPack.Packs) do
        shareIntel(pack, pos)
    end
end

--- Deactivate a pack (stops hunting)
-- @param packName string Pack name
function DMS.HuntPack.deactivatePack(packName)
    local pack = DMS.HuntPack.Packs[packName]
    if pack then
        pack.active = false
    end
end

--- Activate a pack
-- @param packName string Pack name
function DMS.HuntPack.activatePack(packName)
    local pack = DMS.HuntPack.Packs[packName]
    if pack then
        pack.active = true
    end
end

--- Get pack status
-- @param packName string Pack name
-- @return table|nil Pack status
function DMS.HuntPack.getStatus(packName)
    local pack = DMS.HuntPack.Packs[packName]
    if pack then
        return {
            name = pack.name,
            groupCount = #pack.groups,
            hasIntel = hasValidIntel(pack),
            behavior = pack.behavior,
            active = pack.active
        }
    end
    return nil
end

--[[
USAGE EXAMPLE:

-- Configure
DMS.HuntPack.configure({
    detectionRange = 10000,   -- 10km detection
    shareRange = 40000,       -- 40km intel sharing
    respondRange = 25000,     -- 25km response range
    announceDetection = true
})

-- Create packs
DMS.HuntPack.createPack("Alpha Pack",
    {"Patrol-1", "Patrol-2", "Patrol-3"},
    "aggressive"
)

DMS.HuntPack.createPack("Bravo Pack",
    {"Guard-1", "Guard-2"},
    "defensive"
)

-- Start system
DMS.HuntPack.start()

-- Manual intel report (e.g., from AWACS detection)
DMS.HuntPack.reportPosition({x = -50000, y = 0, z = 40000})

-- Deactivate pack
DMS.HuntPack.deactivatePack("Alpha Pack")
]]

-- Export
_G.DMS = DMS
