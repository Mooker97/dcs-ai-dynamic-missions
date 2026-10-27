-- Weather Impact System for DCS Missions
-- Reads mission weather and adjusts gameplay (flags, warnings, handlers) based on it.
-- Requires: nothing (utils/messaging.lua, utils/error-handler.lua optional)
-- Place in mission via DO SCRIPT FILE
--
-- IMPORTANT LIMITATION:
--   DCS World cannot change clouds, precipitation, visibility, wind or temperature at
--   runtime from the mission scripting environment. Those values are fixed by the
--   mission editor (env.mission.weather). This module only READS weather and reacts
--   to it. The only runtime-adjustable element is fog (world.weather.* fog functions,
--   DCS 2.9.10+); DMS.Weather.setFog() uses those when available. Any other "set"
--   call logs a warning and does nothing.
--
--   What CAN change during a mission and is re-sampled each check:
--     - Wind (atmosphere.getWind, sampled at a reference point)
--     - Fog (world.weather.getFogVisibilityDistance / getFogThickness, if available)

DMS = DMS or {}
DMS.Weather = DMS.Weather or {}

-- Weather state (preserved on reload)
DMS.Weather.Current = DMS.Weather.Current or {}
DMS.Weather.Active = DMS.Weather.Active or false
DMS.Weather.ChangeHandlers = DMS.Weather.ChangeHandlers or {}

-- Configuration
DMS.Weather.Config = DMS.Weather.Config or {
    playerCoalition = (coalition and coalition.side and coalition.side.BLUE) or 2,
    checkInterval = 120,          -- Re-sample wind/fog every 2 minutes
    announceChanges = true,
    enableOperationalImpact = true,
    displayDuration = 15,
    referencePoint = nil,         -- Vec3 {x, y, z} for wind sampling (nil = map origin)
    sampleHeightAGL = 10,         -- Wind sample height above ground (m)
}

-- Weather condition thresholds
DMS.Weather.Thresholds = DMS.Weather.Thresholds or {
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

local function isDebug()
    return DMS.Settings and DMS.Settings.isDebug and DMS.Settings.isDebug()
end

local function logError(context, msg)
    if DMS.Error and DMS.Error.log then
        DMS.Error.log(context, msg)
    else
        env.error("[DMS LUA ERROR] " .. tostring(context) .. ": " .. tostring(msg))
    end
end

--- Configure weather system
-- @param settings table Configuration overrides
function DMS.Weather.configure(settings)
    if type(settings) ~= "table" then return end
    for key, value in pairs(settings) do
        DMS.Weather.Config[key] = value
    end
end

-- ============================================================
-- READING WEATHER
-- ============================================================

local function getMissionWeather()
    if env and env.mission and type(env.mission.weather) == "table" then
        return env.mission.weather
    end
    return {}
end

--- Sample wind at the reference point
local function sampleWind()
    local ref = DMS.Weather.Config.referencePoint or { x = 0, y = 0, z = 0 }
    local groundY = 0
    if land and land.getHeight then
        local ok, h = pcall(land.getHeight, { x = ref.x, y = ref.z })
        if ok and type(h) == "number" then groundY = h end
    end
    local samplePoint = { x = ref.x, y = groundY + (DMS.Weather.Config.sampleHeightAGL or 10), z = ref.z }

    local ok, wind = pcall(atmosphere.getWind, samplePoint)
    if not ok or type(wind) ~= "table" then
        return 0, 0
    end
    local speed = math.sqrt((wind.x or 0) ^ 2 + (wind.z or 0) ^ 2)
    -- getWind returns the direction the air moves TOWARD; meteorological wind is FROM
    local toDir = math.deg(math.atan2(wind.z or 0, wind.x or 0))
    local fromDir = (toDir + 180) % 360
    return speed, fromDir
end

--- Get current weather data (read-only)
-- @return table Weather data
local function getWeatherData()
    local weather = {}
    local mw = getMissionWeather()

    weather.windSpeed, weather.windDirection = sampleWind()

    -- Visibility: base visibility from mission, reduced by fog when enabled
    local baseVis = 80000
    if type(mw.visibility) == "table" and type(mw.visibility.distance) == "number" then
        baseVis = mw.visibility.distance
    end

    local fogData = mw.fog
    weather.fogEnabled = false
    weather.fogThickness = 0
    weather.fogVisibility = baseVis
    if type(fogData) == "table" and (mw.enable_fog or fogData.enable) then
        weather.fogEnabled = true
        weather.fogVisibility = math.min(baseVis, fogData.visibility or baseVis)
        weather.fogThickness = fogData.thickness or 0
    end

    -- Runtime fog (DCS 2.9.10+) overrides editor values when available
    if world and world.weather and type(world.weather.getFogVisibilityDistance) == "function" then
        local okV, vis = pcall(world.weather.getFogVisibilityDistance)
        local okT, thick = pcall(world.weather.getFogThickness)
        if okV and type(vis) == "number" and okT and type(thick) == "number" and thick > 0 and vis > 0 then
            weather.fogEnabled = true
            weather.fogVisibility = math.min(baseVis, vis)
            weather.fogThickness = thick
        end
    end

    -- Clouds (static for the whole mission)
    local clouds = mw.clouds
    if type(clouds) == "table" then
        weather.cloudBase = clouds.base or 5000
        weather.cloudDensity = clouds.density or 0
        weather.cloudPreset = clouds.preset
    else
        weather.cloudBase = 5000
        weather.cloudDensity = 0
    end

    -- Precipitation (static): legacy iprecptns (1 rain, 2 storm, 3 snow, 4 snowstorm) or preset name
    weather.precipitation = false
    if type(clouds) == "table" then
        if type(clouds.iprecptns) == "number" and clouds.iprecptns > 0 then
            weather.precipitation = true
        elseif type(clouds.preset) == "string" then
            if string.find(clouds.preset, "Rain") or string.find(clouds.preset, "Storm") then
                weather.precipitation = true
            end
        end
    end

    return weather
end

-- ============================================================
-- CLASSIFICATION
-- ============================================================

local function classifyVisibility(visibility)
    visibility = visibility or 10000
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

local function classifyCeiling(ceiling)
    ceiling = ceiling or 5000
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

local function classifyWind(speed)
    speed = speed or 0
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

    local visClass = classifyVisibility(weather.fogVisibility)
    if visClass == "poor" then
        impact.laserGuided = false
        table.insert(impact.warnings, "Poor visibility - Laser guidance degraded")
    elseif visClass == "minimal" then
        impact.visualOps = false
        impact.laserGuided = false
        table.insert(impact.warnings, "Minimal visibility - IFR only, no visual weapons")
    end

    -- Only treat cloud base as a ceiling when there is meaningful cover
    if (weather.cloudDensity or 0) >= 5 or weather.cloudPreset then
        local ceilClass = classifyCeiling(weather.cloudBase)
        if ceilClass == "low" then
            impact.lowLevelOps = false
            table.insert(impact.warnings, "Low ceiling - Avoid low level operations")
        elseif ceilClass == "veryLow" then
            impact.visualOps = false
            impact.lowLevelOps = false
            table.insert(impact.warnings, "Very low ceiling - IFR required")
        end
    end

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

    if weather.precipitation then
        impact.laserGuided = false
        table.insert(impact.warnings, "Precipitation - Laser guidance ineffective")
    end

    return impact
end

local function annotate(weather)
    weather.impact = analyzeImpact(weather)
    weather.visibilityClass = classifyVisibility(weather.fogVisibility)
    weather.ceilingClass = classifyCeiling(weather.cloudBase)
    weather.windClass = classifyWind(weather.windSpeed)
    return weather
end

local function applyFlags(impact)
    if not DMS.Weather.Config.enableOperationalImpact then return end
    trigger.action.setUserFlag("wx_visual_ops", impact.visualOps and 1 or 0)
    trigger.action.setUserFlag("wx_laser_guided", impact.laserGuided and 1 or 0)
    trigger.action.setUserFlag("wx_carrier_ops", impact.carrierOps and 1 or 0)
    trigger.action.setUserFlag("wx_helo_ops", impact.heloOps and 1 or 0)
end

--- Register handler for weather changes (wind/fog changes only; see header)
-- @param handler function Handler(oldWeather, newWeather, impact)
function DMS.Weather.onChange(handler)
    if type(handler) == "function" then
        table.insert(DMS.Weather.ChangeHandlers, handler)
    end
end

-- ============================================================
-- MONITOR LOOP
-- ============================================================

local function checkWeatherInternal()
    local weather = annotate(getWeatherData())
    local oldWeather = DMS.Weather.Current or {}
    DMS.Weather.Current = weather

    local changed = oldWeather.visibilityClass ~= weather.visibilityClass
        or oldWeather.ceilingClass ~= weather.ceilingClass
        or oldWeather.windClass ~= weather.windClass

    if changed then
        if isDebug() then
            env.info(string.format("[Weather] Conditions changed: vis=%s ceiling=%s wind=%s (%.1f m/s)",
                weather.visibilityClass, weather.ceilingClass, weather.windClass, weather.windSpeed or 0))
        end

        if DMS.Weather.Config.announceChanges then
            DMS.Weather.showBrief()
        end

        for _, handler in ipairs(DMS.Weather.ChangeHandlers) do
            local ok, err = pcall(handler, oldWeather, weather, weather.impact)
            if not ok then
                logError("Weather.onChange handler", err)
            end
        end

        applyFlags(weather.impact)
    end
end

local function checkWeather(_, time)
    if not DMS.Weather.Active then
        DMS.Weather.TimerId = nil
        return nil
    end
    local ok, err = pcall(checkWeatherInternal)
    if not ok then
        logError("Weather.checkWeather", err)
    end
    local interval = tonumber(DMS.Weather.Config.checkInterval) or 120
    if interval <= 0 then interval = 120 end
    return time + interval
end

--- Start weather system
function DMS.Weather.start()
    if DMS.Weather.Active then
        return
    end

    DMS.Weather.Active = true

    local ok, err = pcall(function()
        DMS.Weather.Current = annotate(getWeatherData())
        applyFlags(DMS.Weather.Current.impact)
    end)
    if not ok then
        logError("Weather.start", err)
        DMS.Weather.Current = DMS.Weather.Current or {}
    end

    DMS.Weather.TimerId = timer.scheduleFunction(checkWeather, nil, timer.getTime() + 10)

    if isDebug() then
        local wx = DMS.Weather.Current
        env.info(string.format("[Weather] Started (interval: %ds) vis=%s ceiling=%s wind=%s",
            DMS.Weather.Config.checkInterval or 120, tostring(wx.visibilityClass),
            tostring(wx.ceilingClass), tostring(wx.windClass)))
    end
end

--- Stop weather system
function DMS.Weather.stop()
    DMS.Weather.Active = false
    if DMS.Weather.TimerId then
        pcall(timer.removeFunction, DMS.Weather.TimerId)
        DMS.Weather.TimerId = nil
    end
    if isDebug() then
        env.info("[Weather] Stopped")
    end
end

-- ============================================================
-- (NON-)MODIFICATION API
-- ============================================================

local function cannotChange(what)
    env.warning(string.format(
        "[Weather] %s: DCS cannot change weather at runtime from mission scripts. " ..
        "Set it in the Mission Editor (or use fog via DMS.Weather.setFog). No change made.",
        tostring(what)))
    return false
end

--- Not supported by DCS - logs a warning and returns false
function DMS.Weather.setWeather() return cannotChange("setWeather") end
--- Not supported by DCS - logs a warning and returns false
function DMS.Weather.setClouds() return cannotChange("setClouds") end
--- Not supported by DCS - logs a warning and returns false
function DMS.Weather.setWind() return cannotChange("setWind") end
--- Not supported by DCS - logs a warning and returns false
function DMS.Weather.setPrecipitation() return cannotChange("setPrecipitation") end

--- Change fog at runtime (DCS 2.9.10+ only)
-- @param visibility number Fog visibility distance in meters (0 disables)
-- @param thickness number Fog thickness in meters (0 disables)
-- @return boolean True if applied
function DMS.Weather.setFog(visibility, thickness)
    if not (world and world.weather and type(world.weather.setFogVisibilityDistance) == "function"
            and type(world.weather.setFogThickness) == "function") then
        return cannotChange("setFog (world.weather fog API unavailable in this DCS version)")
    end
    local ok, err = pcall(function()
        world.weather.setFogThickness(thickness or 0)
        world.weather.setFogVisibilityDistance(visibility or 0)
    end)
    if not ok then
        logError("Weather.setFog", err)
        return false
    end
    if isDebug() then
        env.info(string.format("[Weather] Fog set: visibility=%sm thickness=%sm", tostring(visibility), tostring(thickness)))
    end
    return true
end

-- ============================================================
-- OUTPUT / QUERIES
-- ============================================================

--- Display weather brief
function DMS.Weather.showBrief()
    local wx = DMS.Weather.Current
    if not wx or not wx.impact then
        wx = annotate(getWeatherData())
    end

    local lines = {
        "=== WEATHER BRIEF ===",
        "",
        string.format("Visibility: %s (%.0f km)", wx.visibilityClass or "N/A", (wx.fogVisibility or 10000) / 1000),
        string.format("Ceiling: %s (%.0f m)", wx.ceilingClass or "N/A", wx.cloudBase or 5000),
        string.format("Wind: %s (%.0f m/s from %03d)", wx.windClass or "N/A",
            wx.windSpeed or 0, math.floor(wx.windDirection or 0)),
    }

    if wx.precipitation then
        table.insert(lines, "Precipitation: Active")
    end

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
    local cur = DMS.Weather.Current
    if cur and cur.impact then return cur.impact.laserGuided end
    return true
end

--- Check if visual operations possible
-- @return boolean True if visual ops OK
function DMS.Weather.isVisualOps()
    local cur = DMS.Weather.Current
    if cur and cur.impact then return cur.impact.visualOps end
    return true
end

--[[
USAGE EXAMPLE:

DMS.Weather.configure({ announceChanges = true, enableOperationalImpact = true })

-- Fires when sampled wind or runtime fog crosses a classification threshold
DMS.Weather.onChange(function(oldWx, newWx, impact)
    if not impact.carrierOps then
        trigger.action.outText("NOTICE: Carrier operations suspended due to weather", 15)
    end
end)

DMS.Weather.start()

missionCommands.addCommandForCoalition(coalition.side.BLUE, "Weather Brief", nil,
    function() DMS.Weather.showBrief() end)

-- Fog is the only thing that can be changed at runtime (DCS 2.9.10+)
DMS.Weather.setFog(1500, 300)
]]

-- Export
_G.DMS = DMS
