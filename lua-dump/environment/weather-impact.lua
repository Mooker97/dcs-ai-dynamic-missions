-- Weather Impact System for DCS Missions
-- Adjusts gameplay based on weather conditions
-- Requires: utils/messaging.lua
-- Place in mission via DO SCRIPT FILE

DMS = DMS or {}
DMS.Weather = {}

-- Weather state
DMS.Weather.Current = {}
DMS.Weather.Active = false
DMS.Weather.TimerId = nil
DMS.Weather.ChangeHandlers = {}

-- Configuration
DMS.Weather.Config = {
    playerCoalition = coalition.side.BLUE,
    checkInterval = 120,          -- Check weather every 2 minutes
    announceChanges = true,
    enableOperationalImpact = true,
    displayDuration = 15,
}

-- Weather condition thresholds
DMS.Weather.Thresholds = {
    visibility = {
        good = 10000,             -- > 10km
        moderate = 5000,          -- 5-10km
        poor = 2000,              -- 2-5km
        minimal = 0,              -- < 2km
    },
    ceiling = {
        high = 3000,              -- > 3000m
        medium = 1500,            -- 1500-3000m
        low = 500,                -- 500-1500m
        veryLow = 0,              -- < 500m
    },
    wind = {
        calm = 5,                 -- < 5 m/s
        light = 10,               -- 5-10 m/s
        moderate = 15,            -- 10-15 m/s
        strong = 25,              -- 15-25 m/s
        severe = 100,             -- > 25 m/s
    },
}

--- Configure weather system
-- @param settings table Configuration overrides
function DMS.Weather.configure(settings)
    for key, value in pairs(settings) do
        DMS.Weather.Config[key] = value
    end
end

--- Get current weather data
-- @return table Weather data
local function getWeatherData()
    local weather = {}

    -- Get weather from environment
    local windAtGround = atmosphere.getWind({x = 0, y = 10, z = 0})
    weather.windSpeed = math.sqrt(windAtGround.x^2 + windAtGround.z^2)
    weather.windDirection = math.deg(math.atan2(windAtGround.z, windAtGround.x))
    if weather.windDirection < 0 then
        weather.windDirection = weather.windDirection + 360
    end

    -- Fog and visibility (simplified - DCS doesn't expose all weather directly)
    -- In practice, you'd set these via mission parameters
    local fogData = env.mission.weather.fog
    if fogData then
        weather.fogEnabled = fogData.enable
        weather.fogVisibility = fogData.visibility or 10000
        weather.fogThickness = fogData.thickness or 0
    else
        weather.fogEnabled = false
        weather.fogVisibility = 10000
    end

    -- Clouds
    local clouds = env.mission.weather.clouds
    if clouds then
        weather.cloudBase = clouds.base or 5000
        weather.cloudDensity = clouds.density or 0
        weather.cloudPreset = clouds.preset
    else
        weather.cloudBase = 5000
        weather.cloudDensity = 0
    end

    -- Precipitation (from clouds preset typically)
    weather.precipitation = false
    if clouds and clouds.preset then
        -- Common precipitation presets contain "Rain" or "Storm"
        if string.find(clouds.preset, "Rain") or string.find(clouds.preset, "Storm") then
            weather.precipitation = true
        end
    end

    return weather
end

--- Classify visibility
-- @param visibility number Visibility in meters
-- @return string Classification
local function classifyVisibility(visibility)
    if visibility > DMS.Weather.Thresholds.visibility.good then
        return "good"
    elseif visibility > DMS.Weather.Thresholds.visibility.moderate then
        return "moderate"
    elseif visibility > DMS.Weather.Thresholds.visibility.poor then
        return "poor"
    else
        return "minimal"
    end
end

--- Classify ceiling
-- @param ceiling number Cloud base in meters
-- @return string Classification
local function classifyCeiling(ceiling)
    if ceiling > DMS.Weather.Thresholds.ceiling.high then
        return "high"
    elseif ceiling > DMS.Weather.Thresholds.ceiling.medium then
        return "medium"
    elseif ceiling > DMS.Weather.Thresholds.ceiling.low then
        return "low"
    else
        return "veryLow"
    end
end

--- Classify wind
-- @param speed number Wind speed in m/s
-- @return string Classification
local function classifyWind(speed)
    if speed < DMS.Weather.Thresholds.wind.calm then
        return "calm"
    elseif speed < DMS.Weather.Thresholds.wind.light then
        return "light"
    elseif speed < DMS.Weather.Thresholds.wind.moderate then
        return "moderate"
    elseif speed < DMS.Weather.Thresholds.wind.strong then
        return "strong"
    else
        return "severe"
    end
end

--- Analyze weather impact on operations
-- @param weather table Weather data
-- @return table Impact analysis
local function analyzeImpact(weather)
    local impact = {
        visualOps = true,        -- Visual flight rules possible
        lowLevelOps = true,      -- Low level operations safe
        carrierOps = true,       -- Carrier operations safe
        heloOps = true,          -- Helicopter operations safe
        tankerAvailable = true,  -- AAR operations feasible
        laserGuided = true,      -- Laser guided weapons effective
        warnings = {},
    }

    -- Visibility impact
    local visClass = classifyVisibility(weather.fogVisibility)
    if visClass == "poor" then
        impact.laserGuided = false
        table.insert(impact.warnings, "Poor visibility - Laser guidance degraded")
    elseif visClass == "minimal" then
        impact.visualOps = false
        impact.laserGuided = false
        table.insert(impact.warnings, "Minimal visibility - IFR only, no visual weapons")
    end

    -- Ceiling impact
    local ceilClass = classifyCeiling(weather.cloudBase)
    if ceilClass == "low" then
        impact.lowLevelOps = false
        table.insert(impact.warnings, "Low ceiling - Avoid low level operations")
    elseif ceilClass == "veryLow" then
        impact.visualOps = false
        impact.lowLevelOps = false
        table.insert(impact.warnings, "Very low ceiling - IFR required")
    end

    -- Wind impact
    local windClass = classifyWind(weather.windSpeed)
    if windClass == "strong" then
        impact.heloOps = false
        impact.carrierOps = false
        table.insert(impact.warnings, "Strong winds - No carrier/helo ops")
    elseif windClass == "severe" then
        impact.heloOps = false
        impact.carrierOps = false
        impact.tankerAvailable = false
        table.insert(impact.warnings, "SEVERE WINDS - Limited operations")
    end

    -- Precipitation
    if weather.precipitation then
        impact.laserGuided = false
        table.insert(impact.warnings, "Precipitation - Laser guidance ineffective")
    end

    return impact
end

--- Register handler for weather changes
-- @param handler function Handler(oldWeather, newWeather, impact)
function DMS.Weather.onChange(handler)
    table.insert(DMS.Weather.ChangeHandlers, handler)
end

--- Check weather and apply effects (internal)
local function checkWeatherInternal(_, time)
    if not DMS.Weather.Active then
        return nil
    end

    local weather = getWeatherData()
    local impact = analyzeImpact(weather)

    -- Store current
    local oldWeather = DMS.Weather.Current
    DMS.Weather.Current = weather
    DMS.Weather.Current.impact = impact
    DMS.Weather.Current.visibilityClass = classifyVisibility(weather.fogVisibility)
    DMS.Weather.Current.ceilingClass = classifyCeiling(weather.cloudBase)
    DMS.Weather.Current.windClass = classifyWind(weather.windSpeed)

    -- Check for significant changes
    local changed = false
    if oldWeather.visibilityClass ~= weather.visibilityClass or
       oldWeather.ceilingClass ~= weather.ceilingClass or
       oldWeather.windClass ~= weather.windClass then
        changed = true
    end

    if changed then
        -- Announce changes
        if DMS.Weather.Config.announceChanges then
            DMS.Weather.showBrief()
        end

        -- Trigger handlers
        for _, handler in ipairs(DMS.Weather.ChangeHandlers) do
            handler(oldWeather, weather, impact)
        end

        -- Set flags for operational impacts
        if DMS.Weather.Config.enableOperationalImpact then
            trigger.action.setUserFlag("wx_visual_ops", impact.visualOps and 1 or 0)
            trigger.action.setUserFlag("wx_laser_guided", impact.laserGuided and 1 or 0)
            trigger.action.setUserFlag("wx_carrier_ops", impact.carrierOps and 1 or 0)
            trigger.action.setUserFlag("wx_helo_ops", impact.heloOps and 1 or 0)
        end
    end

    return time + DMS.Weather.Config.checkInterval
end

--- Check weather with error handling
local function checkWeather(args, time)
    local success, result = pcall(checkWeatherInternal, args, time)
    if not success then
        if DMS.Error then
            DMS.Error.log("Weather.checkWeather", result)
        else
            env.error("[DMS LUA ERROR] Weather.checkWeather: " .. tostring(result))
        end
        return time + (DMS.Weather.Config.checkInterval or 120)
    end
    return result
end

--- Start weather system
function DMS.Weather.start()
    if DMS.Weather.Active then
        return
    end

    DMS.Weather.Active = true

    -- Initialize
    DMS.Weather.Current = getWeatherData()
    DMS.Weather.Current.impact = analyzeImpact(DMS.Weather.Current)

    DMS.Weather.TimerId = timer.scheduleFunction(
        checkWeather,
        nil,
        timer.getTime() + 10  -- Initial check after 10 seconds
    )
end

--- Stop weather system
function DMS.Weather.stop()
    DMS.Weather.Active = false
    if DMS.Weather.TimerId then
        timer.removeFunction(DMS.Weather.TimerId)
        DMS.Weather.TimerId = nil
    end
end

--- Display weather brief
function DMS.Weather.showBrief()
    local wx = DMS.Weather.Current
    if not wx then
        wx = getWeatherData()
        wx.impact = analyzeImpact(wx)
    end

    local lines = {
        "=== WEATHER BRIEF ===",
        "",
        string.format("Visibility: %s (%.0f km)", wx.visibilityClass or "N/A", (wx.fogVisibility or 10000) / 1000),
        string.format("Ceiling: %s (%.0f m)", wx.ceilingClass or "N/A", wx.cloudBase or 5000),
        string.format("Wind: %s (%.0f m/s from %03d)", wx.windClass or "N/A",
            wx.windSpeed or 0, wx.windDirection or 0),
    }

    if wx.precipitation then
        table.insert(lines, "Precipitation: Active")
    end

    -- Warnings
    if wx.impact and #wx.impact.warnings > 0 then
        table.insert(lines, "")
        table.insert(lines, "-- OPERATIONAL IMPACTS --")
        for _, warning in ipairs(wx.impact.warnings) do
            table.insert(lines, "! " .. warning)
        end
    else
        table.insert(lines, "")
        table.insert(lines, "No significant operational impacts.")
    end

    trigger.action.outTextForCoalition(
        DMS.Weather.Config.playerCoalition,
        table.concat(lines, "\n"),
        DMS.Weather.Config.displayDuration,
        true
    )
end

--- Get weather data for other scripts
-- @return table Current weather
function DMS.Weather.getCurrent()
    return DMS.Weather.Current
end

--- Check if laser weapons are effective
-- @return boolean True if laser guidance works
function DMS.Weather.isLaserEffective()
    return DMS.Weather.Current.impact and DMS.Weather.Current.impact.laserGuided
end

--- Check if visual operations possible
-- @return boolean True if visual ops OK
function DMS.Weather.isVisualOps()
    return DMS.Weather.Current.impact and DMS.Weather.Current.impact.visualOps
end

--[[
USAGE EXAMPLE:

-- Configure
DMS.Weather.configure({
    announceChanges = true,
    enableOperationalImpact = true
})

-- Register change handler
DMS.Weather.onChange(function(oldWx, newWx, impact)
    if not impact.carrierOps then
        trigger.action.outText("NOTICE: Carrier operations suspended due to weather", 15)
    end

    if not impact.laserGuided and oldWx.impact.laserGuided then
        trigger.action.outText("WARNING: Weather degrading laser guidance capability", 10)
    end
end)

-- Start system
DMS.Weather.start()

-- Add F10 menu
missionCommands.addCommandForCoalition(coalition.side.BLUE, "Weather Brief", nil,
    function() DMS.Weather.showBrief() end)

-- In other scripts, check weather conditions
if DMS.Weather.isLaserEffective() then
    -- Use laser guided weapons
else
    -- Switch to GPS/INS guided weapons
end
]]

-- Export
_G.DMS = DMS
