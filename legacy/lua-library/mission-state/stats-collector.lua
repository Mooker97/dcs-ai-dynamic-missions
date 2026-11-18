-- Stats Collector System for DCS Missions
-- Comprehensive mission statistics tracking
-- Optional: utils/error-handler.lua (falls back to pcall if absent)
-- Place in mission via DO SCRIPT FILE

DMS = DMS or {}
DMS.Stats = DMS.Stats or {}

-- Statistics storage (preserved if the script is loaded twice)
DMS.Stats.Data = DMS.Stats.Data or {
    mission = {
        startTime = 0,
        endTime = 0,
        duration = 0,
    },
    players = {},
    coalition = {
        [0] = {kills = 0, losses = 0, score = 0},  -- NEUTRAL
        [1] = {kills = 0, losses = 0, score = 0},  -- RED
        [2] = {kills = 0, losses = 0, score = 0},  -- BLUE
    },
    units = {
        spawned = 0,
        destroyed = 0,
        byType = {},
    },
    weapons = {
        fired = 0,
        hits = 0,
        byType = {},
    },
    events = {
        takeoffs = 0,
        landings = 0,
        ejections = 0,
        crashes = 0,
    },
}

DMS.Stats.Active = DMS.Stats.Active or false

-- Configuration
DMS.Stats.Config = DMS.Stats.Config or {
    playerCoalition = coalition.side.BLUE,
    trackWeapons = true,
    trackMovement = false,  -- Can be performance intensive
    displayDuration = 30,
}

-- ============================================================
-- SAFE HELPERS
-- ============================================================

local function isDebug()
    return DMS.Settings and DMS.Settings.isDebug and DMS.Settings.isDebug()
end

local function debugLog(fmt, ...)
    if isDebug() then
        env.info(string.format("[Stats] " .. fmt, ...))
    end
end

local function logError(context, msg)
    if DMS.Error and DMS.Error.log then
        DMS.Error.log(context, msg)
    else
        env.error("[DMS LUA ERROR] " .. tostring(context) .. ": " .. tostring(msg))
    end
end

local function safeMethod(obj, method, ...)
    if type(obj) ~= "table" or type(obj[method]) ~= "function" then return nil end
    local ok, result = pcall(obj[method], obj, ...)
    if ok then return result end
    return nil
end

local function isUnitObject(obj)
    return safeMethod(obj, "getCategory") == Object.Category.UNIT
end

local function getPlayerNameOf(obj)
    if not isUnitObject(obj) then return nil end
    return safeMethod(obj, "getPlayerName")
end

--- Unit.Category (AIRPLANE/HELICOPTER/GROUND_UNIT/SHIP/STRUCTURE) via getDesc
local function getUnitTypeCategory(obj)
    local desc = safeMethod(obj, "getDesc")
    if type(desc) == "table" then return desc.category end
    return nil
end

--- Configure stats collector
-- @param settings table Configuration overrides
function DMS.Stats.configure(settings)
    if type(settings) ~= "table" then return end
    for key, value in pairs(settings) do
        DMS.Stats.Config[key] = value
    end
end

--- Get or create player stats
-- @param playerName string Player name
-- @return table Player stats
local function getPlayerStats(playerName)
    if not DMS.Stats.Data.players[playerName] then
        DMS.Stats.Data.players[playerName] = {
            name = playerName,
            kills = {
                air = 0,
                ground = 0,
                ship = 0,
                total = 0,
            },
            deaths = 0,
            ejections = 0,
            landings = 0,
            takeoffs = 0,
            friendlyFire = 0,
            flightTime = 0,
            weaponsFired = 0,
            weaponsHit = 0,
            damageDealt = 0,
            damageTaken = 0,
            firstSpawn = timer.getTime(),
            lastActivity = timer.getTime(),
        }
    end
    return DMS.Stats.Data.players[playerName]
end

--- Increment a per-player counter if obj is a player-controlled unit
local function bumpPlayer(obj, field)
    local playerName = getPlayerNameOf(obj)
    if playerName then
        local stats = getPlayerStats(playerName)
        stats[field] = (stats[field] or 0) + 1
        stats.lastActivity = timer.getTime()
    end
end

--- Record a kill
-- @param killer Object Killing object (may be nil / non-unit)
-- @param target Object Killed object (unit, static or scenery)
local function recordKill(killer, target)
    if not target then return end

    local killerCoalition = safeMethod(killer, "getCoalition")
    local targetCoalition = safeMethod(target, "getCoalition")

    -- Update coalition stats
    local coal = DMS.Stats.Data.coalition
    if killerCoalition and coal[killerCoalition] then
        coal[killerCoalition].kills = coal[killerCoalition].kills + 1
    end
    if targetCoalition and coal[targetCoalition] then
        coal[targetCoalition].losses = coal[targetCoalition].losses + 1
    end

    -- Update unit type stats
    local typeName = safeMethod(target, "getTypeName") or "Unknown"
    DMS.Stats.Data.units.byType[typeName] = (DMS.Stats.Data.units.byType[typeName] or 0) + 1
    DMS.Stats.Data.units.destroyed = DMS.Stats.Data.units.destroyed + 1

    -- Update player stats
    local playerName = getPlayerNameOf(killer)
    if playerName then
        local stats = getPlayerStats(playerName)
        stats.lastActivity = timer.getTime()

        if killerCoalition and killerCoalition == targetCoalition then
            stats.friendlyFire = stats.friendlyFire + 1
        else
            stats.kills.total = stats.kills.total + 1

            local targetCategory = getUnitTypeCategory(target)
            if targetCategory == Unit.Category.AIRPLANE or
               targetCategory == Unit.Category.HELICOPTER then
                stats.kills.air = stats.kills.air + 1
            elseif targetCategory == Unit.Category.SHIP then
                stats.kills.ship = stats.kills.ship + 1
            else
                stats.kills.ground = stats.kills.ground + 1
            end
        end
        debugLog("%s killed %s", tostring(playerName), typeName)
    end
end

--- Event handler (raw; wrapped with pcall in start())
DMS.Stats._EventHandlerInternal = {
    onEvent = function(self, event)
        if not DMS.Stats.Active or type(event) ~= "table" then
            return
        end

        local id = event.id

        if id == world.event.S_EVENT_KILL then
            recordKill(event.initiator, event.target)

        elseif id == world.event.S_EVENT_TAKEOFF then
            DMS.Stats.Data.events.takeoffs = DMS.Stats.Data.events.takeoffs + 1
            bumpPlayer(event.initiator, "takeoffs")

        elseif id == world.event.S_EVENT_LAND then
            DMS.Stats.Data.events.landings = DMS.Stats.Data.events.landings + 1
            bumpPlayer(event.initiator, "landings")

        elseif id == world.event.S_EVENT_EJECTION then
            DMS.Stats.Data.events.ejections = DMS.Stats.Data.events.ejections + 1
            bumpPlayer(event.initiator, "ejections")

        elseif id == world.event.S_EVENT_CRASH then
            DMS.Stats.Data.events.crashes = DMS.Stats.Data.events.crashes + 1

        elseif id == world.event.S_EVENT_PILOT_DEAD then
            bumpPlayer(event.initiator, "deaths")

        elseif id == world.event.S_EVENT_SHOT and DMS.Stats.Config.trackWeapons then
            DMS.Stats.Data.weapons.fired = DMS.Stats.Data.weapons.fired + 1
            local weaponName = safeMethod(event.weapon, "getTypeName")
            if weaponName then
                DMS.Stats.Data.weapons.byType[weaponName] = (DMS.Stats.Data.weapons.byType[weaponName] or 0) + 1
            end
            bumpPlayer(event.initiator, "weaponsFired")

        elseif id == world.event.S_EVENT_HIT and DMS.Stats.Config.trackWeapons then
            DMS.Stats.Data.weapons.hits = DMS.Stats.Data.weapons.hits + 1
            bumpPlayer(event.initiator, "weaponsHit")

        elseif id == world.event.S_EVENT_BIRTH then
            if isUnitObject(event.initiator) then
                DMS.Stats.Data.units.spawned = DMS.Stats.Data.units.spawned + 1
            end
        end
    end
}

--- Format duration as HH:MM:SS
-- @param seconds number Duration in seconds
-- @return string Formatted duration
local function formatDuration(seconds)
    seconds = math.max(0, tonumber(seconds) or 0)
    local hours = math.floor(seconds / 3600)
    local mins = math.floor((seconds % 3600) / 60)
    local secs = math.floor(seconds % 60)
    return string.format("%02d:%02d:%02d", hours, mins, secs)
end

--- Start stats collection
function DMS.Stats.start()
    if DMS.Stats.Active then
        return
    end

    DMS.Stats.Active = true
    DMS.Stats.Data.mission.startTime = timer.getTime()
    DMS.Stats.Data.mission.endTime = 0

    if not DMS.Stats.EventHandler then
        if DMS.Error and DMS.Error.safeHandler then
            DMS.Stats.EventHandler = DMS.Error.safeHandler(DMS.Stats._EventHandlerInternal, "Stats.EventHandler")
        else
            DMS.Stats.EventHandler = {
                onEvent = function(self, event)
                    local ok, err = pcall(DMS.Stats._EventHandlerInternal.onEvent, DMS.Stats._EventHandlerInternal, event)
                    if not ok then logError("Stats.EventHandler", err) end
                end
            }
        end
        world.addEventHandler(DMS.Stats.EventHandler)
    end
    debugLog("Started (trackWeapons=%s)", tostring(DMS.Stats.Config.trackWeapons))
end

--- Stop stats collection
function DMS.Stats.stop()
    DMS.Stats.Active = false
    DMS.Stats.Data.mission.endTime = timer.getTime()
    DMS.Stats.Data.mission.duration = DMS.Stats.Data.mission.endTime - DMS.Stats.Data.mission.startTime
    if DMS.Stats.EventHandler then
        pcall(world.removeEventHandler, DMS.Stats.EventHandler)
        DMS.Stats.EventHandler = nil
    end
    debugLog("Stopped (duration %s)", formatDuration(DMS.Stats.Data.mission.duration))
end

--- Get mission summary
-- @return table Mission summary data
function DMS.Stats.getSummary()
    local endTime = DMS.Stats.Active and timer.getTime() or DMS.Stats.Data.mission.endTime
    if not endTime or endTime == 0 then endTime = timer.getTime() end
    local duration = endTime - DMS.Stats.Data.mission.startTime

    return {
        duration = duration,
        durationFormatted = formatDuration(duration),
        unitsSpawned = DMS.Stats.Data.units.spawned,
        unitsDestroyed = DMS.Stats.Data.units.destroyed,
        weaponsFired = DMS.Stats.Data.weapons.fired,
        weaponHitRate = DMS.Stats.Data.weapons.fired > 0 and
            (DMS.Stats.Data.weapons.hits / DMS.Stats.Data.weapons.fired * 100) or 0,
        takeoffs = DMS.Stats.Data.events.takeoffs,
        landings = DMS.Stats.Data.events.landings,
        ejections = DMS.Stats.Data.events.ejections,
        crashes = DMS.Stats.Data.events.crashes,
        blueKills = DMS.Stats.Data.coalition[2].kills,
        blueLosses = DMS.Stats.Data.coalition[2].losses,
        redKills = DMS.Stats.Data.coalition[1].kills,
        redLosses = DMS.Stats.Data.coalition[1].losses,
    }
end

--- Get player stats
-- @param playerName string Player name
-- @return table|nil Player stats
function DMS.Stats.getPlayerStats(playerName)
    return DMS.Stats.Data.players[playerName]
end

--- Get all player stats sorted by kills
-- @return table Sorted player stats
function DMS.Stats.getPlayerRankings()
    local rankings = {}
    for _, stats in pairs(DMS.Stats.Data.players) do
        table.insert(rankings, stats)
    end

    table.sort(rankings, function(a, b)
        return a.kills.total > b.kills.total
    end)

    return rankings
end

--- Display mission summary
function DMS.Stats.showSummary()
    local summary = DMS.Stats.getSummary()

    local lines = {
        "=== MISSION STATISTICS ===",
        "",
        string.format("Mission Duration: %s", summary.durationFormatted),
        "",
        "-- Coalition Stats --",
        string.format("BLUE: %d kills, %d losses", summary.blueKills, summary.blueLosses),
        string.format("RED:  %d kills, %d losses", summary.redKills, summary.redLosses),
        "",
        "-- Unit Stats --",
        string.format("Units Spawned: %d", summary.unitsSpawned),
        string.format("Units Destroyed: %d", summary.unitsDestroyed),
        "",
        "-- Flight Stats --",
        string.format("Takeoffs: %d", summary.takeoffs),
        string.format("Landings: %d", summary.landings),
        string.format("Ejections: %d", summary.ejections),
        string.format("Crashes: %d", summary.crashes),
    }

    if DMS.Stats.Config.trackWeapons then
        table.insert(lines, "")
        table.insert(lines, "-- Weapon Stats --")
        table.insert(lines, string.format("Weapons Fired: %d", summary.weaponsFired))
        table.insert(lines, string.format("Hit Rate: %.1f%%", summary.weaponHitRate))
    end

    trigger.action.outTextForCoalition(
        DMS.Stats.Config.playerCoalition,
        table.concat(lines, "\n"),
        DMS.Stats.Config.displayDuration,
        true
    )
end

--- Display player rankings
function DMS.Stats.showRankings()
    local rankings = DMS.Stats.getPlayerRankings()

    local lines = {"=== PLAYER RANKINGS ===", ""}

    for i, stats in ipairs(rankings) do
        local kd = stats.deaths > 0 and (stats.kills.total / stats.deaths) or stats.kills.total
        local line = string.format("%d. %s - K:%d D:%d K/D:%.2f",
            i, stats.name, stats.kills.total, stats.deaths, kd)
        table.insert(lines, line)
    end

    if #rankings == 0 then
        table.insert(lines, "No player stats recorded yet.")
    end

    trigger.action.outTextForCoalition(
        DMS.Stats.Config.playerCoalition,
        table.concat(lines, "\n"),
        20,
        true
    )
end

--- Display individual player stats
-- @param playerName string Player name
function DMS.Stats.showPlayerStats(playerName)
    local stats = DMS.Stats.Data.players[playerName]

    if not stats then
        trigger.action.outText("No stats found for " .. tostring(playerName), 5)
        return
    end

    local lines = {
        "=== " .. stats.name .. " STATS ===",
        "",
        string.format("Air Kills: %d", stats.kills.air),
        string.format("Ground Kills: %d", stats.kills.ground),
        string.format("Ship Kills: %d", stats.kills.ship),
        string.format("Total Kills: %d", stats.kills.total),
        "",
        string.format("Deaths: %d", stats.deaths),
        string.format("Ejections: %d", stats.ejections),
        string.format("Friendly Fire: %d", stats.friendlyFire),
        "",
        string.format("Takeoffs: %d", stats.takeoffs),
        string.format("Landings: %d", stats.landings),
    }

    if DMS.Stats.Config.trackWeapons then
        local hitRate = stats.weaponsFired > 0 and
            (stats.weaponsHit / stats.weaponsFired * 100) or 0
        table.insert(lines, "")
        table.insert(lines, string.format("Weapons Fired: %d", stats.weaponsFired))
        table.insert(lines, string.format("Weapons Hit: %d (%.1f%%)", stats.weaponsHit, hitRate))
    end

    trigger.action.outTextForCoalition(
        DMS.Stats.Config.playerCoalition,
        table.concat(lines, "\n"),
        20,
        true
    )
end

--- Get raw stats data
-- @return table Full stats data
function DMS.Stats.getRawData()
    return DMS.Stats.Data
end

--[[
USAGE EXAMPLE:

-- Configure
DMS.Stats.configure({
    trackWeapons = true,
    trackMovement = false
})

-- Start collecting
DMS.Stats.start()

-- Add F10 menu commands
local statsMenu = missionCommands.addSubMenuForCoalition(coalition.side.BLUE, "Statistics")

missionCommands.addCommandForCoalition(coalition.side.BLUE, "Mission Summary", statsMenu,
    function() DMS.Stats.showSummary() end)

missionCommands.addCommandForCoalition(coalition.side.BLUE, "Player Rankings", statsMenu,
    function() DMS.Stats.showRankings() end)

missionCommands.addCommandForCoalition(coalition.side.BLUE, "My Stats", statsMenu,
    function()
        local players = coalition.getPlayers(coalition.side.BLUE)
        if players and #players > 0 then
            local name = players[1]:getPlayerName()
            if name then DMS.Stats.showPlayerStats(name) end
        end
    end)

-- At mission end
-- DMS.Stats.stop()
-- local summary = DMS.Stats.getSummary()
]]

-- Export
_G.DMS = DMS
