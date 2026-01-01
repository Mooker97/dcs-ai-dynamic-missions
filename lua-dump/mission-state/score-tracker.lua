-- Score Tracker System for DCS Missions
-- Track player scores and statistics during mission
-- Requires: utils/messaging.lua
-- Place in mission via DO SCRIPT FILE

DMS = DMS or {}
DMS.Score = {}

-- Player scores
DMS.Score.Players = {}
DMS.Score.EventHandler = nil
DMS.Score.Active = false

-- Score values by category
DMS.Score.Values = {
    -- Air kills
    air_kill = 100,
    helicopter_kill = 75,
    -- Ground kills
    armor_kill = 50,
    vehicle_kill = 25,
    infantry_kill = 10,
    sam_kill = 150,
    radar_kill = 200,
    -- Ship kills
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
DMS.Score.Config = {
    playerCoalition = coalition.side.BLUE,
    showKillScore = true,
    showTotalScore = true,
    displayDuration = 5,
    trackFriendlyFire = true,
    multiplierEnabled = true,
    baseMultiplier = 1.0,
}

-- Category mapping for unit types
local categoryMap = {
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
    -- Radar
    ["EWR"] = "radar_kill", ["1L13"] = "radar_kill", ["55G6"] = "radar_kill",
    -- Ships
    ["CVN"] = "ship_kill", ["CG"] = "ship_kill", ["FFG"] = "ship_kill",
    -- Default handled below
}

--- Configure score system
-- @param settings table Configuration overrides
function DMS.Score.configure(settings)
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

--- Set unit type category
-- @param unitType string Unit type name (or partial)
-- @param category string Score category
function DMS.Score.setUnitCategory(unitType, category)
    categoryMap[unitType] = category
end

--- Get or create player score record
-- @param playerName string Player name
-- @return table Player score data
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
        }
    end
    return DMS.Score.Players[playerName]
end

--- Determine score category for a unit
-- @param unit table DCS unit object
-- @return string Category name
local function getScoreCategory(unit)
    local typeName = unit:getTypeName()

    -- Check exact match first
    if categoryMap[typeName] then
        return categoryMap[typeName]
    end

    -- Check partial match
    for pattern, category in pairs(categoryMap) do
        if string.find(typeName, pattern) then
            return category
        end
    end

    -- Default by DCS category
    local category = unit:getCategory()
    if category == Unit.Category.AIRPLANE then
        return "air_kill"
    elseif category == Unit.Category.HELICOPTER then
        return "helicopter_kill"
    elseif category == Unit.Category.SHIP then
        return "ship_kill"
    elseif category == Unit.Category.GROUND_UNIT then
        return "vehicle_kill"
    end

    return "vehicle_kill"  -- Default
end

--- Add score to player
-- @param playerName string Player name
-- @param amount number Score amount
-- @param category string|nil Category for tracking
-- @param showMessage boolean|nil Show score popup
function DMS.Score.addScore(playerName, amount, category, showMessage)
    local record = getPlayerRecord(playerName)

    -- Apply multiplier
    local multiplier = DMS.Score.Config.multiplierEnabled and record.multiplier or 1.0
    local finalAmount = math.floor(amount * multiplier)

    record.score = record.score + finalAmount

    -- Track kills by category
    if category then
        if string.find(category, "air") or string.find(category, "helicopter") then
            record.kills.air = record.kills.air + 1
        elseif string.find(category, "ship") or string.find(category, "boat") then
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
            -- Increase multiplier with streak
            if DMS.Score.Config.multiplierEnabled and record.streak >= 3 then
                record.multiplier = math.min(2.0, 1.0 + (record.streak - 2) * 0.1)
            end
        end
    end

    -- Show score message
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

        trigger.action.outTextForGroup(
            Unit.getByName(playerName) and Unit.getByName(playerName):getGroup():getID() or 0,
            msg,
            DMS.Score.Config.displayDuration
        )
    end
end

--- Create event handler
local function createEventHandler()
    local handler = {}

    function handler:onEvent(event)
        if not DMS.Score.Active then
            return
        end

        -- Handle kills
        if event.id == world.event.S_EVENT_KILL then
            local initiator = event.initiator
            local target = event.target

            if initiator and target and initiator.getPlayerName then
                local playerName = initiator:getPlayerName()
                if playerName then
                    local initiatorCoalition = initiator:getCoalition()
                    local targetCoalition = target:getCoalition()

                    -- Check friendly fire
                    if initiatorCoalition == targetCoalition then
                        if DMS.Score.Config.trackFriendlyFire then
                            local record = getPlayerRecord(playerName)
                            record.friendlyFire = record.friendlyFire + 1
                            record.streak = 0  -- Reset streak
                            record.multiplier = DMS.Score.Config.baseMultiplier
                            DMS.Score.addScore(playerName, DMS.Score.Values.friendly_fire, nil, true)
                        end
                    else
                        -- Enemy kill
                        local category = getScoreCategory(target)
                        local points = DMS.Score.Values[category] or 25
                        DMS.Score.addScore(playerName, points, category, true)
                    end
                end
            end
        end

        -- Handle player death
        if event.id == world.event.S_EVENT_PILOT_DEAD or
           event.id == world.event.S_EVENT_EJECTION then
            local unit = event.initiator
            if unit and unit.getPlayerName then
                local playerName = unit:getPlayerName()
                if playerName then
                    local record = getPlayerRecord(playerName)
                    record.deaths = record.deaths + 1
                    record.streak = 0  -- Reset streak
                    record.multiplier = DMS.Score.Config.baseMultiplier
                    DMS.Score.addScore(playerName, DMS.Score.Values.aircraft_lost or -200, nil, true)
                end
            end
        end
    end

    return handler
end

--- Start score tracking
function DMS.Score.start()
    if DMS.Score.Active then
        return
    end

    DMS.Score.Active = true
    DMS.Score.EventHandler = createEventHandler()
    world.addEventHandler(DMS.Score.EventHandler)
end

--- Stop score tracking
function DMS.Score.stop()
    DMS.Score.Active = false
end

--- Get player score
-- @param playerName string Player name
-- @return table Score data
function DMS.Score.getPlayerScore(playerName)
    return getPlayerRecord(playerName)
end

--- Get all player scores sorted by total
-- @return table Sorted array of player scores
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

--- Display leaderboard
function DMS.Score.showLeaderboard()
    local scores = DMS.Score.getLeaderboard()
    local lines = {"=== MISSION SCORES ===", ""}

    for i, record in ipairs(scores) do
        local line = string.format("%d. %s: %d pts (K:%d D:%d)",
            i, record.name, record.score, record.kills.total, record.deaths)
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

--- Display player stats
-- @param playerName string Player name
function DMS.Score.showPlayerStats(playerName)
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

    -- Try to show to specific player
    local unit = Unit.getByName(playerName)
    if unit and unit:isExist() then
        trigger.action.outTextForGroup(
            unit:getGroup():getID(),
            table.concat(lines, "\n"),
            15
        )
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

-- Customize score values
DMS.Score.setValue("sam_kill", 200)
DMS.Score.setValue("hvt_kill", 1000)

-- Add custom unit categories
DMS.Score.setUnitCategory("SA-15", "sam_kill")
DMS.Score.setUnitCategory("General", "hvt_kill")

-- Start tracking
DMS.Score.start()

-- Add F10 menu commands
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
