-- Hunt Pack Coordination for DCS Missions
-- Enemy ground groups detect players, share intel and converge on the
-- (predicted) player position. Routes are re-issued periodically.
-- Place in mission via DO SCRIPT FILE
-- Optional: utils/mission-settings.lua (debug logging), utils/error-handler.lua

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
    detectionRange = 15000,      -- Max range at which a group can detect a player
    shareRange = 50000,          -- Packs with a member this close to the target receive shared intel
    respondRange = 30000,        -- Members within this range of the target are routed toward it
    trackingCoalition = coalition.side.BLUE,
    announceDetection = false,
    -- Movement
    moveSpeed = 15,              -- m/s (~54 kph)
    moveAction = "Off Road",     -- Route action: "Off Road", "On Road", "Cone", "Rank", "Vee", ...
    reissueInterval = 30,        -- Seconds between route refreshes toward a moving target
    repathDistance = 500,        -- Re-route early if the aim point moved more than this (m)
    -- Prediction (lead the target using its last observed velocity)
    usePrediction = true,
    predictLeadTime = 30,        -- Extra seconds of lead beyond intel age
    maxPredictDistance = 3000,   -- Clamp prediction offset (m)
    -- Detection
    useLineOfSight = true,       -- land.isVisible check counts as a visual detection
}

-- ============================================================
-- INTERNAL HELPERS
-- ============================================================

local function logDebug(fmt, ...)
    if DMS.Settings and DMS.Settings.isDebug and DMS.Settings.isDebug() then
        env.info(string.format("[HuntPack] " .. fmt, ...))
    end
end

local function logError(context, err)
    local msg = tostring(err)
    if DMS.Error and DMS.Error.log then
        if pcall(DMS.Error.log, "HuntPack." .. context, msg) then return end
    end
    env.error(string.format("[DMS LUA ERROR] HuntPack.%s: %s", context, msg))
end

local function getLeadUnit(group)
    if not group or not group:isExist() then return nil end
    local units = group:getUnits()
    if not units then return nil end
    for _, u in ipairs(units) do
        if u and u:isExist() then return u end
    end
    return nil
end

local function isGroundGroup(group)
    local ok, cat = pcall(group.getCategory, group)
    return ok and cat == Group.Category.GROUND
end

local function getDistance(pos1, pos2)
    local dx = pos2.x - pos1.x
    local dz = pos2.z - pos1.z
    return math.sqrt(dx * dx + dz * dz)
end

local function makeGroundPoint(x, z, speed, action)
    return {
        x = x, y = z,   -- route y = Vec3.z
        alt = land.getHeight({x = x, y = z}), alt_type = "BARO",
        type = "Turning Point", action = action or "Off Road",
        speed = speed, speed_locked = true,
        ETA = 0, ETA_locked = false,
        formation_template = "",
        task = {id = "ComboTask", params = {tasks = {}}},
    }
end

--- Route a ground group from its current position through {x, z} waypoints
local function routeGroundGroup(group, waypoints, speed, action)
    if not isGroundGroup(group) then return false end
    local lead = getLeadUnit(group)
    if not lead then return false end
    local cur = lead:getPoint()
    local points = {makeGroundPoint(cur.x, cur.z, speed, action)}
    for _, wp in ipairs(waypoints) do
        points[#points + 1] = makeGroundPoint(wp.x, wp.z, speed, action)
    end
    local controller = group:getController()
    if not controller or #points < 2 then return false end
    local ok, err = pcall(controller.setTask, controller,
        {id = "Mission", params = {route = {points = points}}})
    if not ok then
        logError("routeGroundGroup", err)
        return false
    end
    return true
end

local function setGroundEngage(controller)
    controller:setOption(AI.Option.Ground.id.ROE, AI.Option.Ground.val.ROE.OPEN_FIRE)
    controller:setOption(AI.Option.Ground.id.ALARM_STATE, AI.Option.Ground.val.ALARM_STATE.RED)
end

local function safeName(obj)
    if not obj then return nil end
    local ok, name = pcall(obj.getName, obj)
    if ok then return name end
    return nil
end

--- Get living player units of the tracked coalition
local function getPlayerUnits()
    local result = {}
    local players = coalition.getPlayers(DMS.HuntPack.Config.trackingCoalition)
    if players then
        for _, unit in ipairs(players) do
            if unit and unit:isExist() then
                table.insert(result, unit)
            end
        end
    end
    return result
end

--- Does a group detect a player unit?
-- Range gate first, then the group's own sensors (controller:getDetectedTargets),
-- then optional eyeball line-of-sight (land.isVisible, +2m / +2m heights).
local function groupDetectsUnit(group, lead, playerUnit)
    local gp = lead:getPoint()
    local pp = playerUnit:getPoint()
    if getDistance(gp, pp) > DMS.HuntPack.Config.detectionRange then
        return false
    end

    local controller = group:getController()
    if controller then
        local ok, detected = pcall(controller.getDetectedTargets, controller)
        if ok and type(detected) == "table" then
            local targetName = safeName(playerUnit)
            for _, det in ipairs(detected) do
                if det.object and targetName and safeName(det.object) == targetName then
                    return true, "sensors"
                end
            end
        end
    end

    if DMS.HuntPack.Config.useLineOfSight then
        local ok, visible = pcall(land.isVisible,
            {x = gp.x, y = gp.y + 2, z = gp.z},
            {x = pp.x, y = pp.y + 2, z = pp.z})
        if ok and visible then
            return true, "line of sight"
        end
    end

    return false
end

--- Check if any group in pack detects a player
-- @return table|nil Detected player unit, string method, string detecting group
local function checkPackDetection(pack, playerUnits)
    for _, groupName in ipairs(pack.groups) do
        local group = Group.getByName(groupName)
        local lead = getLeadUnit(group)
        if lead then
            for _, playerUnit in ipairs(playerUnits) do
                local detected, method = groupDetectsUnit(group, lead, playerUnit)
                if detected then
                    return playerUnit, method, groupName
                end
            end
        end
    end
    return nil
end

--- Record intel on a pack
local function shareIntel(pack, targetPos, targetVel)
    pack.lastKnownTarget = {x = targetPos.x, y = targetPos.y or 0, z = targetPos.z}
    pack.targetVelocity = targetVel
    pack.intelTime = timer.getTime()

    DMS.HuntPack.LastKnownPlayerPos = pack.lastKnownTarget
    DMS.HuntPack.LastUpdateTime = pack.intelTime
end

local function hasValidIntel(pack)
    if not pack.lastKnownTarget then
        return false
    end
    return (timer.getTime() - pack.intelTime) < DMS.HuntPack.Config.intelDecayTime
end

--- Nearest living member distance from a pack to a point
local function packDistanceTo(pack, pos)
    local best = nil
    for _, groupName in ipairs(pack.groups) do
        local lead = getLeadUnit(Group.getByName(groupName))
        if lead then
            local d = getDistance(lead:getPoint(), pos)
            if not best or d < best then best = d end
        end
    end
    return best
end

--- Predicted target position from last intel + velocity
local function getAimPoint(pack)
    local pos = pack.lastKnownTarget
    local vel = pack.targetVelocity
    local cfg = DMS.HuntPack.Config
    if not cfg.usePrediction or not vel then
        return pos
    end
    local lead = (timer.getTime() - pack.intelTime) + cfg.predictLeadTime
    local ox, oz = vel.x * lead, vel.z * lead
    local off = math.sqrt(ox * ox + oz * oz)
    if off > cfg.maxPredictDistance and off > 0 then
        local k = cfg.maxPredictDistance / off
        ox, oz = ox * k, oz * k
    end
    return {x = pos.x + ox, y = pos.y, z = pos.z + oz}
end

--- Route pack members toward the aim point (throttled re-issue)
-- @param force boolean Ignore the re-issue throttle
local function commandPackToTarget(pack, aimPos, force)
    local cfg = DMS.HuntPack.Config
    local now = timer.getTime()

    if not force and pack.lastOrderTime and pack.lastOrderPos then
        local recent = (now - pack.lastOrderTime) < cfg.reissueInterval
        local moved = getDistance(pack.lastOrderPos, aimPos) > cfg.repathDistance
        if recent and not moved then
            return
        end
    end

    local routed = 0
    for _, groupName in ipairs(pack.groups) do
        local group = Group.getByName(groupName)
        local lead = getLeadUnit(group)
        if lead and getDistance(lead:getPoint(), aimPos) <= cfg.respondRange then
            if isGroundGroup(group) then
                local controller = group:getController()
                if controller then
                    setGroundEngage(controller)
                end
                if routeGroundGroup(group, {aimPos}, cfg.moveSpeed, cfg.moveAction) then
                    routed = routed + 1
                end
            else
                logDebug("'%s' in pack '%s' is not a ground group - not routed", groupName, pack.name)
            end
        end
    end

    pack.lastOrderTime = now
    pack.lastOrderPos = aimPos

    logDebug("Pack '%s' routed %d group(s) toward (%.0f, %.0f)", pack.name, routed, aimPos.x, aimPos.z)
end

--- Put pack on alert without moving it (defensive / patrol packs)
local function alertPack(pack)
    for _, groupName in ipairs(pack.groups) do
        local group = Group.getByName(groupName)
        if getLeadUnit(group) and isGroundGroup(group) then
            local controller = group:getController()
            if controller then setGroundEngage(controller) end
        end
    end
end

--- Process hunt pack coordination (internal)
local function processHuntPackInternal()
    local playerUnits = getPlayerUnits()

    for packName, pack in pairs(DMS.HuntPack.Packs) do
        if pack.active then
            local playerUnit, method, spotter = nil, nil, nil
            if #playerUnits > 0 then
                playerUnit, method, spotter = checkPackDetection(pack, playerUnits)
            end

            if playerUnit then
                local pos = playerUnit:getPoint()
                local vel = playerUnit:getVelocity()
                local fresh = not hasValidIntel(pack)
                shareIntel(pack, pos, vel)

                logDebug("Pack '%s': '%s' detected %s via %s", packName, tostring(spotter),
                    tostring(safeName(playerUnit)), tostring(method))

                if fresh and DMS.HuntPack.Config.announceDetection then
                    trigger.action.outText("Enemy has detected you!", 5, true)
                end

                -- Share with other packs in range that don't have fresher intel
                for otherName, other in pairs(DMS.HuntPack.Packs) do
                    if other ~= pack and other.active then
                        local d = packDistanceTo(other, pos)
                        if d and d <= DMS.HuntPack.Config.shareRange and
                           (not other.intelTime or other.intelTime < pack.intelTime) then
                            shareIntel(other, pos, vel)
                            logDebug("Pack '%s' shared intel with '%s'", packName, otherName)
                        end
                    end
                end

                if pack.behavior == "aggressive" then
                    commandPackToTarget(pack, getAimPoint(pack), fresh)
                else
                    alertPack(pack)
                end

            elseif hasValidIntel(pack) then
                if pack.behavior == "aggressive" then
                    commandPackToTarget(pack, getAimPoint(pack), false)
                else
                    alertPack(pack)
                end
            end
        end
    end
end

local function processHuntPack(_, time)
    if not DMS.HuntPack.Active then
        return nil
    end
    local ok, err = pcall(processHuntPackInternal)
    if not ok then
        logError("processHuntPack", err)
    end
    return time + (DMS.HuntPack.Config.checkInterval or 10)
end

-- ============================================================
-- PUBLIC API
-- ============================================================

--- Configure hunt pack system
function DMS.HuntPack.configure(settings)
    for key, value in pairs(settings) do
        DMS.HuntPack.Config[key] = value
    end
end

--- Create a new hunt pack
-- @param packName string Unique pack identifier
-- @param groupNames table Array of group names in this pack
-- @param behavior string|nil "aggressive" (hunts), "defensive" or "patrol" (alert only)
function DMS.HuntPack.createPack(packName, groupNames, behavior)
    DMS.HuntPack.Packs[packName] = {
        name = packName,
        groups = groupNames or {},
        behavior = behavior or "aggressive",
        lastKnownTarget = nil,
        targetVelocity = nil,
        intelTime = 0,
        lastOrderTime = nil,
        lastOrderPos = nil,
        active = true,
    }
    logDebug("Created pack '%s' (%d groups, %s)", packName, #(groupNames or {}), behavior or "aggressive")
end

--- Add group to existing pack
function DMS.HuntPack.addToPack(packName, groupName)
    local pack = DMS.HuntPack.Packs[packName]
    if pack then
        table.insert(pack.groups, groupName)
    end
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

    local count = 0
    for _ in pairs(DMS.HuntPack.Packs) do count = count + 1 end
    logDebug("Started monitoring %d packs (interval: %ds, detection: %dm)",
        count, DMS.HuntPack.Config.checkInterval, DMS.HuntPack.Config.detectionRange)
end

--- Stop hunt pack system
function DMS.HuntPack.stop()
    DMS.HuntPack.Active = false
    if DMS.HuntPack.TimerId then
        pcall(timer.removeFunction, DMS.HuntPack.TimerId)
        DMS.HuntPack.TimerId = nil
    end
    logDebug("Stopped")
end

--- Manually report player position to all packs (e.g. from AWACS / EWR)
-- @param pos table Vec3 position
-- @param vel table|nil Vec3 velocity (enables prediction)
function DMS.HuntPack.reportPosition(pos, vel)
    for _, pack in pairs(DMS.HuntPack.Packs) do
        shareIntel(pack, pos, vel)
        pack.lastOrderTime = nil  -- force a fresh route next cycle
    end
    logDebug("Position reported to all packs (%.0f, %.0f)", pos.x, pos.z)
end

function DMS.HuntPack.deactivatePack(packName)
    local pack = DMS.HuntPack.Packs[packName]
    if pack then pack.active = false end
end

function DMS.HuntPack.activatePack(packName)
    local pack = DMS.HuntPack.Packs[packName]
    if pack then pack.active = true end
end

--- Get pack status
function DMS.HuntPack.getStatus(packName)
    local pack = DMS.HuntPack.Packs[packName]
    if pack then
        return {
            name = pack.name,
            groupCount = #pack.groups,
            hasIntel = hasValidIntel(pack),
            behavior = pack.behavior,
            active = pack.active,
            lastKnownTarget = pack.lastKnownTarget,
        }
    end
    return nil
end

--[[
USAGE EXAMPLE:

DMS.HuntPack.configure({
    detectionRange = 10000,
    shareRange = 40000,
    respondRange = 25000,
    announceDetection = true,
})

DMS.HuntPack.createPack("Alpha Pack", {"Patrol-1", "Patrol-2", "Patrol-3"}, "aggressive")
DMS.HuntPack.createPack("Bravo Pack", {"Guard-1", "Guard-2"}, "defensive")

DMS.HuntPack.start()

-- Manual intel report (e.g. from AWACS detection)
DMS.HuntPack.reportPosition({x = -50000, y = 0, z = 40000})

DMS.HuntPack.deactivatePack("Alpha Pack")
]]

-- Export
_G.DMS = DMS
