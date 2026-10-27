-- Score Tracker System for DCS Missions
-- Track player scores and statistics during mission
-- Optional: utils/error-handler.lua (falls back to pcall if absent)
-- Place in mission via DO SCRIPT FILE

DMS = DMS or {}
DMS.Score = DMS.Score or {}

-- Player scores (preserved if the script is loaded twice)
DMS.Score.Players = DMS.Score.Players or {}
DMS.Score.Active = DMS.Score.Active or false

-- Score values by category
DMS.Score.Values = DMS.Score.Values or {
    -- Air targets
    air_kill = 100,
    helicopter_kill = 75,
    -- Ground targets
    armor_kill = 50,
    vehicle_kill = 25,
    infantry_kill = 10,
    sam_kill = 150,
    radar_kill = 200,
    -- Naval targets
    ship_kill = 200,
    boat_kill = 75,
    -- Special
    hvt_kill = 500,
    building_kill = 30,
    -- Penalties
    friendly_fire = -500,
    civilian_kill = -1000,
    aircraft_lost = -200,
}

-- Configuration
DMS.Score.Config = DMS.Score.Config or {
    playerCoalition = coalition.side.BLUE,
    showKillScore = true,
    showTotalScore = true,
    displayDuration = 5,
    trackFriendlyFire = true,
    multiplierEnabled = true,
    baseMultiplier = 1.0,
}

-- Unit type -> score category (exact match first, then plain substring match)
DMS.Score._categoryMap = DMS.Score._categoryMap or {
    -- Aircraft
    ["F-16"] = "air_kill", ["F-15"] = "air_kill", ["F-14"] = "air_kill",
    ["MiG-29"] = "air_kill", ["Su-27"] = "air_kill", ["Su-33"] = "air_kill",
    ["MiG-21"] = "air_kill", ["MiG-23"] = "air_kill", ["Su-25"] = "air_kill",
    -- Helicopters
    ["Mi-8"] = "helicopter_kill", ["Mi-24"] = "helicopter_kill",
    ["UH-60"] = "helicopter_kill", ["Ka-50"] = "helicopter_kill",
    -- Armor
    ["T-72"] = "armor_kill", ["T-80"] = "armor_kill", ["T-90"] = "armor_kill",
    ["M1"] = "armor_kill", ["Leopard"] = "armor_kill", ["BMP"] = "armor_kill",
    -- SAMs
    ["SA-6"] = "sam_kill", ["SA-10"] = "sam_kill", ["SA-11"] = "sam_kill",
    ["SA-2"] = "sam_kill", ["SA-3"] = "sam_kill", ["Patriot"] = "sam_kill",
    ["Hawk"] = "sam_kill", ["Roland"] = "sam_kill",
    -- Radars
    ["EWR"] = "radar_kill", ["1L13"] = "radar_kill", ["55G6"] = "radar_kill",
    -- Ships
    ["CVN"] = "ship_kill", ["CG"] = "ship_kill", ["FFG"] = "ship_kill",
}
local categoryMap = DMS.Score._categoryMap

-- ============================================================
-- SAFE HELPERS
-- ============================================================

local function isDebug()
    return DMS.Settings and DMS.Settings.isDebug and DMS.Settings.isDebug()
end

local function debugLog(fmt, ...)
    if isDebug() then
        env.info(string.format("[Score] " .. fmt, ...))
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

--- Configure score tracker
-- @param settings table Configuration overrides
function DMS.Score.configure(settings)
    if type(settings) ~= "table" then return end
    for key, value in pairs(settings) do
        DMS.Score.Config[key] = value
    end
end

--- Set score value for category
-- @param category string Category name
-- @param value number Score value
function DMS.Score.setValue(category, value)
    DMS.Score.Values[category] = value
end

--- Map unit type to score category
-- @param unitType string Unit type name (exact or substring)
-- @param category string Score category
function DMS.Score.setUnitCategory(unitType, category)
    categoryMap[unitType] = category
end

--- Get or create player record
-- @param playerName string Player name
-- @return table Player record
local function getPlayerRecord(playerName)
    if not DMS.Score.Players[playerName] then
        DMS.Score.Players[playerName] = {
            name = playerName,
            score = 0,
            kills = {
                air = 0,
                ground = 0,
                ship = 0,
                total = 0,
            },
            friendlyFire = 0,
            deaths = 0,
            multiplier = DMS.Score.Config.baseMultiplier,
            streak = 0,
            maxStreak = 0,
            groupId = nil,      -- last known group ID (for messages)
            lastDeathTime = nil,
        }
    end
    return DMS.Score.Players[playerName]
end

--- Remember the player's current group so messages go to the right cockpit
local function rememberPlayerUnit(record, unit)
    local group = safeMethod(unit, "getGroup")
    local gid = group and safeMethod(group, "getID")
    if gid then record.groupId = gid end
end

--- Determine score category for a target object (unit or static)
-- @param target Object Target object
-- @return string Score category
local function getScoreCategory(target)
    local objCat = safeMethod(target, "getCategory")
    if objCat == Object.Category.STATIC or objCat == Object.Category.SCENERY then
        return "building_kill"
    end

    local typeName = safeMethod(target, "getTypeName") or ""

    -- Exact match
    if categoryMap[typeName] then
        return categoryMap[typeName]
    end

    -- Plain substring match ("-" is a pattern char, so use plain find)
    for pattern, category in pairs(categoryMap) do
        if string.find(typeName, pattern, 1, true) then
            return category
        end
    end

    -- Fall back to unit type category
    local category = getUnitTypeCategory(target)
    if category == Unit.Category.AIRPLANE then
        return "air_kill"
    elseif category == Unit.Category.HELICOPTER then
        return "helicopter_kill"
    elseif category == Unit.Category.SHIP then
        return "ship_kill"
    elseif category == Unit.Category.STRUCTURE then
        return "building_kill"
    end

    return "vehicle_kill"  -- Default
end

--- Add score to player
-- @param playerName string Player name
-- @param amount number Points to add
-- @param category string|nil Score category (counts as a kill when set)
-- @param showMessage boolean|nil Show score popup
function DMS.Score.addScore(playerName, amount, category, showMessage)
    if not playerName then return end
    amount = tonumber(amount) or 0
    local record = getPlayerRecord(playerName)

    -- Apply multiplier
    local multiplier = DMS.Score.Config.multiplierEnabled and record.multiplier or 1.0
    local finalAmount = math.floor(amount * multiplier)

    record.score = record.score + finalAmount

    -- Track kills by type
    if category then
        if string.find(category, "air", 1, true) or string.find(category, "helicopter", 1, true) then
            record.kills.air = record.kills.air + 1
        elseif string.find(category, "ship", 1, true) or string.find(category, "boat", 1, true) then
            record.kills.ship = record.kills.ship + 1
        else
            record.kills.ground = record.kills.ground + 1
        end
        record.kills.total = record.kills.total + 1

        -- Update streak
        if amount > 0 then
            record.streak = record.streak + 1
            if record.streak > record.maxStreak then
                record.maxStreak = record.streak
            end
            if DMS.Score.Config.multiplierEnabled and record.streak >= 3 then
                record.multiplier = math.min(2.0, 1.0 + (record.streak - 2) * 0.1)
            end
        end
    end

    debugLog("%s %+d pts (%s) total=%d", tostring(playerName), finalAmount, tostring(category or "adjust"), record.score)

    -- Show message
    if showMessage ~= false and DMS.Score.Config.showKillScore and finalAmount ~= 0 then
        local msg
        if finalAmount > 0 then
            msg = string.format("+%d", finalAmount)
            if multiplier > 1.0 then
                msg = msg .. string.format(" (x%.1f)", multiplier)
            end
        else
            msg = string.format("%d", finalAmount)
        end
        if DMS.Score.Config.showTotalScore then
            msg = msg .. string.format("  [Total: %d]", record.score)
        end

        if record.groupId then
            trigger.action.outTextForGroup(record.groupId, msg, DMS.Score.Config.displayDuration)
        end
    end
end

--- Event handler (raw; wrapped with pcall in start())
DMS.Score._EventHandlerInternal = {
    onEvent = function(self, event)
        if not DMS.Score.Active or type(event) ~= "table" then
            return
        end

        -- Kill events
        if event.id == world.event.S_EVENT_KILL then
            local initiator = event.initiator
            local target = event.target
            local playerName = getPlayerNameOf(initiator)
            if playerName and target then
                local record = getPlayerRecord(playerName)
                rememberPlayerUnit(record, initiator)

                local initiatorCoalition = safeMethod(initiator, "getCoalition")
                local targetCoalition = safeMethod(target, "getCoalition")

                if initiatorCoalition and targetCoalition and initiatorCoalition == targetCoalition then
                    if DMS.Score.Config.trackFriendlyFire then
                        record.friendlyFire = record.friendlyFire + 1
                        record.streak = 0
                        record.multiplier = DMS.Score.Config.baseMultiplier
                        DMS.Score.addScore(playerName, DMS.Score.Values.friendly_fire or -500, nil, true)
                    end
                else
                    local category = getScoreCategory(target)
                    local points = DMS.Score.Values[category] or 25
                    DMS.Score.addScore(playerName, points, category, true)
                end
            end
            return
        end

        -- Player deaths (ejection + pilot dead can both fire: count once per 30s)
        if event.id == world.event.S_EVENT_PILOT_DEAD or
           event.id == world.event.S_EVENT_EJECTION then
            local playerName = getPlayerNameOf(event.initiator)
            if playerName then
                local record = getPlayerRecord(playerName)
                rememberPlayerUnit(record, event.initiator)
                local now = timer.getTime()
                if record.lastDeathTime and (now - record.lastDeathTime) < 30 then
                    return
                end
                record.lastDeathTime = now
                record.deaths = record.deaths + 1
                record.streak = 0
                record.multiplier = DMS.Score.Config.baseMultiplier
                DMS.Score.addScore(playerName, DMS.Score.Values.aircraft_lost or -200, nil, true)
            end
        end
    end
}

--- Start score tracking
function DMS.Score.start()
    if DMS.Score.Active then
        return
    end

    DMS.Score.Active = true

    if not DMS.Score.EventHandler then
        if DMS.Error and DMS.Error.safeHandler then
            DMS.Score.EventHandler = DMS.Error.safeHandler(DMS.Score._EventHandlerInternal, "Score.EventHandler")
        else
            DMS.Score.EventHandler = {
                onEvent = function(self, event)
                    local ok, err = pcall(DMS.Score._EventHandlerInternal.onEvent, DMS.Score._EventHandlerInternal, event)
                    if not ok then logError("Score.EventHandler", err) end
                end
            }
        end
        world.addEventHandler(DMS.Score.EventHandler)
    end
    debugLog("Started")
end

--- Stop score tracking
function DMS.Score.stop()
    DMS.Score.Active = false
    if DMS.Score.EventHandler then
        pcall(world.removeEventHandler, DMS.Score.EventHandler)
        DMS.Score.EventHandler = nil
    end
    debugLog("Stopped")
end

--- Get player score
-- @param playerName string Player name
-- @return table Player record
function DMS.Score.getPlayerScore(playerName)
    return getPlayerRecord(playerName)
end

--- Get leaderboard
-- @return table Sorted array of player records
function DMS.Score.getLeaderboard()
    local scores = {}
    for _, record in pairs(DMS.Score.Players) do
        table.insert(scores, record)
    end

    table.sort(scores, function(a, b)
        return a.score > b.score
    end)

    return scores
end

--- Show leaderboard to coalition
function DMS.Score.showLeaderboard()
    local scores = DMS.Score.getLeaderboard()
    local lines = {"=== MISSION SCORES ===", ""}

    for i, record in ipairs(scores) do
        local line = string.format("%d. %s: %d pts (K:%d D:%d)",
            i, tostring(record.name), record.score, record.kills.total, record.deaths)
        table.insert(lines, line)
    end

    if #scores == 0 then
        table.insert(lines, "No scores recorded yet.")
    end

    trigger.action.outTextForCoalition(
        DMS.Score.Config.playerCoalition,
        table.concat(lines, "\n"),
        20,
        true
    )
end

--- Show player stats
-- @param playerName string Player name
function DMS.Score.showPlayerStats(playerName)
    if not playerName then return end
    local record = getPlayerRecord(playerName)

    local lines = {
        "=== YOUR STATS ===",
        "",
        string.format("Score: %d", record.score),
        string.format("Multiplier: x%.1f", record.multiplier),
        string.format("Current Streak: %d (Max: %d)", record.streak, record.maxStreak),
        "",
        string.format("Air Kills: %d", record.kills.air),
        string.format("Ground Kills: %d", record.kills.ground),
        string.format("Ship Kills: %d", record.kills.ship),
        string.format("Total Kills: %d", record.kills.total),
        "",
        string.format("Deaths: %d", record.deaths),
        string.format("Friendly Fire: %d", record.friendlyFire),
    }

    if record.groupId then
        trigger.action.outTextForGroup(record.groupId, table.concat(lines, "\n"), 15)
    else
        trigger.action.outTextForCoalition(
            DMS.Score.Config.playerCoalition,
            table.concat(lines, "\n"),
            15,
            true
        )
    end
end

--- Reset all scores
function DMS.Score.reset()
    DMS.Score.Players = {}
end

--[[
USAGE EXAMPLE:

-- Configure
DMS.Score.configure({
    showKillScore = true,
    showTotalScore = true,
    multiplierEnabled = true,
    baseMultiplier = 1.0
})

-- Custom score values
DMS.Score.setValue("sam_kill", 200)
DMS.Score.setValue("hvt_kill", 1000)

-- Map custom unit types
DMS.Score.setUnitCategory("SA-15", "sam_kill")
DMS.Score.setUnitCategory("General", "hvt_kill")

-- Start tracking
DMS.Score.start()

-- Add F10 menu
missionCommands.addCommandForCoalition(coalition.side.BLUE, "Show Leaderboard", nil,
    function() DMS.Score.showLeaderboard() end)

missionCommands.addCommandForCoalition(coalition.side.BLUE, "Show My Stats", nil,
    function()
        local players = coalition.getPlayers(coalition.side.BLUE)
        if players and #players > 0 then
            local name = players[1]:getPlayerName()
            if name then DMS.Score.showPlayerStats(name) end
        end
    end)

-- Manual score adjustment
-- DMS.Score.addScore("PlayerName", 500, "hvt_kill", true)
]]

-- Export
_G.DMS = DMS
