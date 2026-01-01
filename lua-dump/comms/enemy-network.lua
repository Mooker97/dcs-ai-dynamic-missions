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
local function getTemplate(language, messageType)
    local templates = DMS.EnemyNetwork.Templates[language]
    if not templates then
        templates = DMS.EnemyNetwork.Templates.english
    end

    local typeTemplates = templates[messageType]
    if not typeTemplates then
        return "Unknown transmission."
    end

    return typeTemplates[math.random(#typeTemplates)]
end

--- Format bearing
-- @param fromPos table From position
-- @param toPos table To position
-- @return string Formatted bearing
local function formatBearing(fromPos, toPos)
    local dx = toPos.x - fromPos.x
    local dz = toPos.z - fromPos.z
    local bearing = math.deg(math.atan2(dz, dx))
    bearing = 90 - bearing
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

    -- Get template
    local template = getTemplate(node.language, messageType)

    -- Format message based on type
    local message = template
    if messageType == "CONTACT" and data.targetPos then
        local bearing = formatBearing(nodePos, data.targetPos)
        local distance = formatDistance(nodePos, data.targetPos)
        message = string.format(template, bearing, distance)
    elseif messageType == "STATUS" or messageType == "REINFORCEMENT" then
        message = string.format(template, node.callsign)
    end

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
            local englishTemplate = getTemplate("english", messageType)
            if messageType == "CONTACT" and data.targetPos then
                local bearing = formatBearing(nodePos, data.targetPos)
                local distance = formatDistance(nodePos, data.targetPos)
                intercepted.translation = string.format(englishTemplate, bearing, distance)
            else
                intercepted.translation = string.format(englishTemplate, node.callsign)
            end
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
                local garbled = message:gsub("%a", function(c)
                    if math.random() < 0.3 then
                        return DMS.EnemyNetwork.Config.staticNoise
                    end
                    return c
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

        -- Fire callback
        if DMS.EnemyNetwork.OnIntercept then
            DMS.EnemyNetwork.OnIntercept(intercepted)
        end
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
        for _, nodeId in ipairs(affectedNodes) do
            local node = DMS.EnemyNetwork.Nodes[nodeId]
            if node then
                node.active = true
            end
        end
        return nil
    end, nil, timer.getTime() + duration)

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
    if not DMS.Awareness then return end

    -- Store original setState
    local originalSetState = DMS.Awareness.setState

    DMS.Awareness.setState = function(groupName, newState, contactPos)
        -- Call original
        originalSetState(groupName, newState, contactPos)

        -- Find node for this group
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
    end
end

--- Start enemy network system
function DMS.EnemyNetwork.start()
    if DMS.EnemyNetwork.Active then return end
    DMS.EnemyNetwork.Active = true

    -- Hook awareness if available
    DMS.EnemyNetwork.hookAwareness()
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
