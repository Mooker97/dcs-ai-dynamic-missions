-- Enemy Network Communications for DCS Missions
-- AI-to-AI communications that players can intercept
-- Place in mission via DO SCRIPT FILE

DMS = DMS or {}
DMS.EnemyNetwork = {}

-- Network nodes
DMS.EnemyNetwork.Nodes = {}
DMS.EnemyNetwork.Active = false
DMS.EnemyNetwork.MessageQueue = {}
DMS.EnemyNetwork.InterceptedMessages = {}

-- Message templates by language
DMS.EnemyNetwork.Templates = {
    russian = {
        CONTACT = {
            "Внимание! Воздушный контакт, пеленг %s, дальность %s.",
            "Обнаружена цель! Направление %s.",
            "Контакт с противником! Азимут %s, расстояние %s километров.",
        },
        REINFORCEMENT = {
            "Запрашиваю подкрепление! Координаты %s.",
            "Нужна поддержка! Противник превосходит нас числом!",
            "Срочно требуется помощь! Позиция под огнем!",
        },
        RETREAT = {
            "Всем подразделениям - отступаем к запасным позициям!",
            "Отход! Повторяю - отход к точке сбора!",
            "Приказ на отступление! Организованный отход!",
        },
        CASUALTY = {
            "Потери личного состава! Нужна эвакуация!",
            "Раненые! Требуется медицинская помощь!",
            "Тяжелые потери. Боеспособность снижена.",
        },
        AMMO = {
            "Боеприпасы на исходе! Срочно нужно пополнение!",
            "Критический уровень боекомплекта!",
            "Запрашиваю снабжение - боеприпасы заканчиваются.",
        },
        SPOTTED = {
            "Нас засекли! Противник знает нашу позицию!",
            "Обнаружены! Меняем позицию!",
            "Враг ведет огонь по нашим координатам!",
        },
        STATUS = {
            "Докладываю: позиция %s, состояние - боеготовность.",
            "Статус: все системы в норме, ожидаем приказов.",
            "Пост %s - без происшествий.",
        },
        DESTROYED = {
            "Цель уничтожена! Подтверждаю поражение.",
            "Попадание! Враг уничтожен!",
            "Ликвидация подтверждена.",
        },
    },
    english = {
        CONTACT = {
            "Contact! Bearing %s, range %s.",
            "Target acquired! Direction %s.",
            "Enemy contact! Azimuth %s, distance %s klicks.",
        },
        REINFORCEMENT = {
            "Requesting reinforcements! Grid %s.",
            "Need support! We're outnumbered!",
            "Urgent assistance required! Position under fire!",
        },
        RETREAT = {
            "All units - fall back to secondary positions!",
            "Retreat! Repeat - retreat to rally point!",
            "Order to withdraw! Organized fallback!",
        },
        CASUALTY = {
            "Casualties! Need CASEVAC!",
            "Wounded! Medical assistance required!",
            "Heavy losses. Combat effectiveness reduced.",
        },
        AMMO = {
            "Running low on ammo! Need resupply urgent!",
            "Critical ammunition level!",
            "Requesting supply run - ammo depleted.",
        },
        SPOTTED = {
            "We've been spotted! Enemy knows our position!",
            "Compromised! Displacing!",
            "Taking fire at our coordinates!",
        },
        STATUS = {
            "Report: Position %s, status - ready.",
            "Status: All systems normal, awaiting orders.",
            "Post %s - all quiet.",
        },
        DESTROYED = {
            "Target destroyed! Confirmed kill.",
            "Hit! Enemy down!",
            "Elimination confirmed.",
        },
    },
}

-- Configuration
DMS.EnemyNetwork.Config = {
    playerCoalition = coalition.side.BLUE,
    enemyCoalition = coalition.side.RED,
    defaultLanguage = "russian",
    interceptRange = 15000,        -- Meters - range to intercept messages
    decryptionChance = 0.7,        -- Chance to understand message
    showOriginal = true,           -- Show original language
    showTranslation = true,        -- Show English translation
    messageDisplayTime = 8,
    checkInterval = 5,
    enableInterception = true,
    staticNoise = "[STATIC]",
    interceptPrefix = "INTERCEPT",
}

local function logDebug(fmt, ...)
    if DMS.Settings and DMS.Settings.isDebug and DMS.Settings.isDebug() then
        env.info(string.format("[EnemyNetwork] " .. fmt, ...))
    end
end

--- string.format that never throws (templates may have fewer/more %s than args)
local function safeFormat(template, ...)
    local ok, result = pcall(string.format, template, ...)
    if ok then return result end
    return (template:gsub("%%s", "?"))
end

--- Configure enemy network
-- @param settings table Configuration overrides
function DMS.EnemyNetwork.configure(settings)
    for key, value in pairs(settings) do
        DMS.EnemyNetwork.Config[key] = value
    end
end

--- Register a network node (communication-capable unit/group)
-- @param nodeId string Unique node ID
-- @param groupName string DCS group name
-- @param options table|nil Node options
function DMS.EnemyNetwork.registerNode(nodeId, groupName, options)
    options = options or {}

    DMS.EnemyNetwork.Nodes[nodeId] = {
        id = nodeId,
        groupName = groupName,
        callsign = options.callsign or nodeId,
        language = options.language or DMS.EnemyNetwork.Config.defaultLanguage,
        range = options.range or DMS.EnemyNetwork.Config.interceptRange,
        encrypted = options.encrypted or false,
        lastTransmission = 0,
        transmissionCooldown = options.cooldown or 30,
        active = true,
    }
end

--- Get position of a network node
-- @param nodeId string Node ID
-- @return table|nil Position
local function getNodePosition(nodeId)
    local node = DMS.EnemyNetwork.Nodes[nodeId]
    if not node then return nil end

    local group = Group.getByName(node.groupName)
    if not group or not group:isExist() then
        node.active = false
        return nil
    end

    local units = group:getUnits()
    if units and #units > 0 then
        local unit = units[1]
        if unit and unit:isExist() then
            return unit:getPoint()
        end
    end

    return nil
end

--- Get player positions
-- @return table Array of player positions
local function getPlayerPositions()
    local positions = {}
    local players = coalition.getPlayers(DMS.EnemyNetwork.Config.playerCoalition)
    if players then
        for _, unit in ipairs(players) do
            if unit and unit:isExist() then
                table.insert(positions, unit:getPoint())
            end
        end
    end
    return positions
end

--- Check if message can be intercepted
-- @param nodePos table Node position
-- @param range number Interception range
-- @return boolean Can intercept
local function canIntercept(nodePos, range)
    if not DMS.EnemyNetwork.Config.enableInterception then
        return false
    end

    local playerPositions = getPlayerPositions()
    for _, playerPos in ipairs(playerPositions) do
        local dx = playerPos.x - nodePos.x
        local dz = playerPos.z - nodePos.z
        local dist = math.sqrt(dx * dx + dz * dz)
        if dist <= range then
            return true
        end
    end
    return false
end

--- Get message template
-- @param language string Language code
-- @param messageType string Message type
-- @return string Message template
local function getTemplate(language, messageType, index)
    local templates = DMS.EnemyNetwork.Templates[language]
    if not templates then
        templates = DMS.EnemyNetwork.Templates.english
    end

    local typeTemplates = templates[messageType]
    if not typeTemplates or #typeTemplates == 0 then
        return "Unknown transmission.", 1
    end

    if not index or not typeTemplates[index] then
        index = math.random(#typeTemplates)
    end
    return typeTemplates[index], index
end

--- Format bearing
-- @param fromPos table From position
-- @param toPos table To position
-- @return string Formatted bearing
local function formatBearing(fromPos, toPos)
    local dx = toPos.x - fromPos.x
    local dz = toPos.z - fromPos.z
    -- DCS: +x = north, +z = east, so atan2(dz, dx) is already a compass bearing
    local bearing = math.deg(math.atan2(dz, dx))
    if bearing < 0 then bearing = bearing + 360 end
    return string.format("%03d", math.floor(bearing))
end

--- Format distance
-- @param fromPos table From position
-- @param toPos table To position
-- @return string Formatted distance
local function formatDistance(fromPos, toPos)
    local dx = toPos.x - fromPos.x
    local dz = toPos.z - fromPos.z
    local dist = math.sqrt(dx * dx + dz * dz) / 1000  -- km
    return string.format("%.1f", dist)
end

--- Broadcast a message from a node
-- @param nodeId string Node ID
-- @param messageType string Message type (CONTACT, REINFORCEMENT, etc.)
-- @param data table|nil Message data
function DMS.EnemyNetwork.broadcast(nodeId, messageType, data)
    data = data or {}

    local node = DMS.EnemyNetwork.Nodes[nodeId]
    if not node or not node.active then return end

    -- Check cooldown
    local currentTime = timer.getTime()
    if currentTime - node.lastTransmission < node.transmissionCooldown then
        return
    end
    node.lastTransmission = currentTime

    local nodePos = getNodePosition(nodeId)
    if not nodePos then return end

    -- Get template (remember index so the translation matches the original line)
    local template, templateIndex = getTemplate(node.language, messageType)

    local function fill(tpl)
        if messageType == "CONTACT" and data.targetPos and data.targetPos.x and data.targetPos.z then
            return safeFormat(tpl, formatBearing(nodePos, data.targetPos), formatDistance(nodePos, data.targetPos))
        elseif messageType == "STATUS" or messageType == "REINFORCEMENT" then
            return safeFormat(tpl, node.callsign)
        end
        return safeFormat(tpl)
    end

    -- Format message based on type
    local message = fill(template)

    -- Check if can be intercepted
    if canIntercept(nodePos, node.range) then
        local intercepted = {
            nodeId = nodeId,
            callsign = node.callsign,
            messageType = messageType,
            originalMessage = message,
            language = node.language,
            encrypted = node.encrypted,
            timestamp = currentTime,
            position = nodePos,
        }

        -- Attempt decryption
        local decrypted = false
        if node.encrypted then
            decrypted = math.random() < (DMS.EnemyNetwork.Config.decryptionChance * 0.5)
        else
            decrypted = math.random() < DMS.EnemyNetwork.Config.decryptionChance
        end

        -- Get translation if decrypted
        if decrypted and node.language ~= "english" then
            local englishTemplate = getTemplate("english", messageType, templateIndex)
            intercepted.translation = fill(englishTemplate)
        end

        -- Store intercepted message
        table.insert(DMS.EnemyNetwork.InterceptedMessages, intercepted)

        -- Display to player
        local displayMsg = string.format("[%s] %s:\n",
            DMS.EnemyNetwork.Config.interceptPrefix,
            node.callsign
        )

        if DMS.EnemyNetwork.Config.showOriginal then
            if node.encrypted and not decrypted then
                -- Show garbled message
                -- Garble whole words (byte-wise replacement would corrupt UTF-8 Cyrillic)
                local garbled = message:gsub("%S+", function(word)
                    if math.random() < 0.3 then
                        return DMS.EnemyNetwork.Config.staticNoise
                    end
                    return word
                end)
                displayMsg = displayMsg .. garbled
            else
                displayMsg = displayMsg .. message
            end
        end

        if DMS.EnemyNetwork.Config.showTranslation and intercepted.translation then
            displayMsg = displayMsg .. "\n[TRANSLATION]: " .. intercepted.translation
        elseif node.encrypted and not decrypted then
            displayMsg = displayMsg .. "\n[ENCRYPTED - UNABLE TO DECODE]"
        end

        trigger.action.outTextForCoalition(
            DMS.EnemyNetwork.Config.playerCoalition,
            displayMsg,
            DMS.EnemyNetwork.Config.messageDisplayTime
        )

        logDebug("Intercepted %s from '%s' (decrypted: %s)", messageType, node.callsign, tostring(decrypted))

        -- Fire callback
        if DMS.EnemyNetwork.OnIntercept then
            local ok, err = pcall(DMS.EnemyNetwork.OnIntercept, intercepted)
            if not ok then
                env.error(string.format("[EnemyNetwork] OnIntercept callback error: %s", tostring(err)))
            end
        end
    else
        logDebug("%s from '%s' not intercepted (no player within %dm)", messageType, node.callsign, node.range)
    end
end

--- Register interception callback
-- @param callback function Callback(interceptedMessage)
function DMS.EnemyNetwork.onIntercept(callback)
    DMS.EnemyNetwork.OnIntercept = callback
end

--- Get network status
-- @return table Network status
function DMS.EnemyNetwork.getNetworkStatus()
    local activeNodes = 0
    local totalNodes = 0

    for _, node in pairs(DMS.EnemyNetwork.Nodes) do
        totalNodes = totalNodes + 1
        if node.active then
            activeNodes = activeNodes + 1
        end
    end

    return {
        activeNodes = activeNodes,
        totalNodes = totalNodes,
        interceptedMessages = #DMS.EnemyNetwork.InterceptedMessages,
    }
end

--- Disrupt network in an area (EW/jamming effect)
-- @param centerPos table Center of disruption
-- @param radius number Radius in meters
-- @param duration number Duration in seconds
function DMS.EnemyNetwork.disruptNetwork(centerPos, radius, duration)
    local affectedNodes = {}
    if type(centerPos) ~= "table" or not centerPos.x or not centerPos.z then return 0 end

    for nodeId, node in pairs(DMS.EnemyNetwork.Nodes) do
        local nodePos = getNodePosition(nodeId)
        if nodePos then
            local dx = nodePos.x - centerPos.x
            local dz = nodePos.z - centerPos.z
            local dist = math.sqrt(dx * dx + dz * dz)
            if dist <= radius then
                node.active = false
                table.insert(affectedNodes, nodeId)
            end
        end
    end

    -- Restore after duration
    timer.scheduleFunction(function()
        local ok, err = pcall(function()
            for _, nodeId in ipairs(affectedNodes) do
                local node = DMS.EnemyNetwork.Nodes[nodeId]
                if node then
                    -- getNodePosition() re-flags dead groups inactive on next broadcast
                    node.active = true
                end
            end
            logDebug("Network disruption ended, %d nodes restored", #affectedNodes)
        end)
        if not ok then
            env.error(string.format("[EnemyNetwork] disrupt restore error: %s", tostring(err)))
        end
        return nil
    end, nil, timer.getTime() + (tonumber(duration) or 60))

    logDebug("Disrupted %d nodes (radius %dm, %ds)", #affectedNodes, radius or 0, duration or 0)
    return #affectedNodes
end

--- Set interception enabled/disabled
-- @param enabled boolean Enable interception
function DMS.EnemyNetwork.setInterceptable(enabled)
    DMS.EnemyNetwork.Config.enableInterception = enabled
end

--- Get intercepted messages
-- @param since number|nil Timestamp to filter from
-- @return table Array of intercepted messages
function DMS.EnemyNetwork.getIntercepted(since)
    if not since then
        return DMS.EnemyNetwork.InterceptedMessages
    end

    local filtered = {}
    for _, msg in ipairs(DMS.EnemyNetwork.InterceptedMessages) do
        if msg.timestamp >= since then
            table.insert(filtered, msg)
        end
    end
    return filtered
end

--- Hook into Awareness system for automatic broadcasts
function DMS.EnemyNetwork.hookAwareness()
    if not DMS.Awareness or type(DMS.Awareness.setState) ~= "function" or not DMS.Awareness.STATES then return end
    if DMS.EnemyNetwork._awarenessHooked then return end  -- avoid double-wrapping on restart
    DMS.EnemyNetwork._awarenessHooked = true

    -- Store original setState
    local originalSetState = DMS.Awareness.setState

    DMS.Awareness.setState = function(groupName, newState, contactPos)
        -- Call original
        local result = originalSetState(groupName, newState, contactPos)

        if not DMS.EnemyNetwork.Active then return result end

        -- Find node for this group (never let a broadcast error break Awareness)
        local ok, err = pcall(function()
        for nodeId, node in pairs(DMS.EnemyNetwork.Nodes) do
            if node.groupName == groupName then
                if newState == DMS.Awareness.STATES.ALERT then
                    DMS.EnemyNetwork.broadcast(nodeId, "CONTACT", {
                        targetPos = contactPos,
                    })
                elseif newState == DMS.Awareness.STATES.HUNTING then
                    DMS.EnemyNetwork.broadcast(nodeId, "SPOTTED", {})
                end
                break
            end
        end
        end)
        if not ok then
            env.error(string.format("[EnemyNetwork] awareness hook error: %s", tostring(err)))
        end
        return result
    end
    logDebug("Hooked DMS.Awareness.setState")
end

--- Start enemy network system
function DMS.EnemyNetwork.start()
    if DMS.EnemyNetwork.Active then return end
    DMS.EnemyNetwork.Active = true

    -- Hook awareness if available
    DMS.EnemyNetwork.hookAwareness()
    logDebug("Started")
end

--- Stop enemy network system
function DMS.EnemyNetwork.stop()
    DMS.EnemyNetwork.Active = false
end

--[[
USAGE EXAMPLE:

-- Configure
DMS.EnemyNetwork.configure({
    defaultLanguage = "russian",
    interceptRange = 20000,
    decryptionChance = 0.8,
    showOriginal = true,
    showTranslation = true,
})

-- Register network nodes
DMS.EnemyNetwork.registerNode("post_alpha", "Guard-Post-1", {
    callsign = "POST ALPHA",
    language = "russian",
    encrypted = false,
})

DMS.EnemyNetwork.registerNode("command", "HQ-Group", {
    callsign = "COMMAND",
    language = "russian",
    encrypted = true,  -- Harder to intercept
    range = 30000,
})

DMS.EnemyNetwork.registerNode("patrol_1", "Patrol-Group-1", {
    callsign = "PATROL ONE",
    language = "russian",
})

-- Start system
DMS.EnemyNetwork.start()

-- Manual broadcasts
DMS.EnemyNetwork.broadcast("post_alpha", "CONTACT", {
    targetPos = {x = 100000, z = 50000},
})

DMS.EnemyNetwork.broadcast("command", "REINFORCEMENT", {})

-- Register intercept callback
DMS.EnemyNetwork.onIntercept(function(msg)
    -- Intel gathering - track enemy communications
    trigger.action.setUserFlag("INTEL_GATHERED",
        trigger.misc.getUserFlag("INTEL_GATHERED") + 1)

    -- Could trigger events based on message type
    if msg.messageType == "REINFORCEMENT" then
        trigger.action.outTextForCoalition(
            coalition.side.BLUE,
            "INTEL: Enemy requesting reinforcements!",
            10
        )
    end
end)

-- EW/Jamming effect
local jammingRadius = 5000
local jammingDuration = 60
local nodesAffected = DMS.EnemyNetwork.disruptNetwork(
    {x = 100000, z = 50000},
    jammingRadius,
    jammingDuration
)
trigger.action.outText(string.format(
    "EW: Jammed %d enemy communication nodes for %d seconds",
    nodesAffected, jammingDuration
), 10)

-- Example intercepted message display:
-- [INTERCEPT] POST ALPHA:
-- Внимание! Воздушный контакт, пеленг 045, дальность 15.2.
-- [TRANSLATION]: Contact! Bearing 045, range 15.2.
]]

-- Export
_G.DMS = DMS
