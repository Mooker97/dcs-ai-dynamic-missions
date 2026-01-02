-- F10 Command Menu System for DCS Missions
-- Dynamic radio menu builder for player interactions
-- Place in mission via DO SCRIPT FILE

DMS = DMS or {}
DMS.CommandMenu = {}

-- Menu structure
DMS.CommandMenu.Menus = {}
DMS.CommandMenu.Commands = {}
DMS.CommandMenu.MenuHandles = {}

-- Configuration
DMS.CommandMenu.Config = {
    playerCoalition = coalition.side.BLUE,
    rootMenuName = "Mission Commands",
    showConfirmations = true,
    confirmationDuration = 5,
}

--- Configure command menu system
-- @param settings table Configuration overrides
function DMS.CommandMenu.configure(settings)
    for key, value in pairs(settings) do
        DMS.CommandMenu.Config[key] = value
    end
end

--- Create the root menu
function DMS.CommandMenu.createRootMenu()
    if DMS.CommandMenu.MenuHandles.root then return end

    DMS.CommandMenu.MenuHandles.root = missionCommands.addSubMenuForCoalition(
        DMS.CommandMenu.Config.playerCoalition,
        DMS.CommandMenu.Config.rootMenuName
    )
end

--- Add a submenu
-- @param menuId string Unique menu ID
-- @param menuName string Display name
-- @param parentId string|nil Parent menu ID (nil = root)
-- @return table Menu handle
function DMS.CommandMenu.addMenu(menuId, menuName, parentId)
    DMS.CommandMenu.createRootMenu()

    local parentHandle = nil
    if parentId then
        parentHandle = DMS.CommandMenu.MenuHandles[parentId]
    else
        parentHandle = DMS.CommandMenu.MenuHandles.root
    end

    local handle = missionCommands.addSubMenuForCoalition(
        DMS.CommandMenu.Config.playerCoalition,
        menuName,
        parentHandle
    )

    DMS.CommandMenu.MenuHandles[menuId] = handle
    DMS.CommandMenu.Menus[menuId] = {
        id = menuId,
        name = menuName,
        parent = parentId,
        handle = handle,
    }

    return handle
end

--- Add a command to a menu
-- @param commandId string Unique command ID
-- @param commandName string Display name
-- @param menuId string|nil Menu ID (nil = root)
-- @param callback function Function to call when selected
-- @param options table|nil Command options
function DMS.CommandMenu.addCommand(commandId, commandName, menuId, callback, options)
    options = options or {}
    DMS.CommandMenu.createRootMenu()

    local parentHandle = nil
    if menuId then
        parentHandle = DMS.CommandMenu.MenuHandles[menuId]
    else
        parentHandle = DMS.CommandMenu.MenuHandles.root
    end

    -- Wrap callback with confirmation
    local wrappedCallback = function()
        -- Execute callback
        local result = callback()

        -- Show confirmation
        if DMS.CommandMenu.Config.showConfirmations then
            local msg = options.confirmation or string.format("%s executed", commandName)
            trigger.action.outTextForCoalition(
                DMS.CommandMenu.Config.playerCoalition,
                msg,
                DMS.CommandMenu.Config.confirmationDuration
            )
        end

        return result
    end

    local handle = missionCommands.addCommandForCoalition(
        DMS.CommandMenu.Config.playerCoalition,
        commandName,
        parentHandle,
        wrappedCallback
    )

    DMS.CommandMenu.Commands[commandId] = {
        id = commandId,
        name = commandName,
        menu = menuId,
        handle = handle,
        callback = callback,
        enabled = true,
        cooldown = options.cooldown or 0,
        lastUsed = 0,
    }

    return handle
end

--- Remove a command
-- @param commandId string Command ID
function DMS.CommandMenu.removeCommand(commandId)
    local command = DMS.CommandMenu.Commands[commandId]
    if command and command.handle then
        missionCommands.removeItemForCoalition(
            DMS.CommandMenu.Config.playerCoalition,
            command.handle
        )
        DMS.CommandMenu.Commands[commandId] = nil
    end
end

--- Remove a menu (and all its contents)
-- @param menuId string Menu ID
function DMS.CommandMenu.removeMenu(menuId)
    local menu = DMS.CommandMenu.Menus[menuId]
    if menu and menu.handle then
        missionCommands.removeItemForCoalition(
            DMS.CommandMenu.Config.playerCoalition,
            menu.handle
        )
        DMS.CommandMenu.Menus[menuId] = nil
        DMS.CommandMenu.MenuHandles[menuId] = nil
    end
end

--- Add standard support menu
function DMS.CommandMenu.addSupportMenu()
    DMS.CommandMenu.addMenu("support", "Request Support")

    DMS.CommandMenu.addCommand("intel_update", "Request Intel Update", "support", function()
        if DMS.Intel then
            DMS.Intel.broadcastUpdate()
        else
            trigger.action.outTextForCoalition(
                DMS.CommandMenu.Config.playerCoalition,
                "INTEL: No active contacts at this time.",
                10
            )
        end
    end, {confirmation = "INTEL: Compiling situation report..."})

    DMS.CommandMenu.addCommand("request_arty", "Request Artillery Strike", "support", function()
        -- Placeholder - missions can override
        trigger.action.outTextForCoalition(
            DMS.CommandMenu.Config.playerCoalition,
            "ARTILLERY: Mark target with smoke. Strike inbound in 60 seconds.",
            10
        )
    end, {confirmation = "ARTILLERY: Request acknowledged.", cooldown = 120})

    DMS.CommandMenu.addCommand("request_cas", "Request CAS Support", "support", function()
        trigger.action.outTextForCoalition(
            DMS.CommandMenu.Config.playerCoalition,
            "CAS: No additional air assets available at this time.",
            10
        )
    end, {confirmation = "CAS: Checking availability..."})
end

--- Add mission status menu
function DMS.CommandMenu.addStatusMenu()
    DMS.CommandMenu.addMenu("status", "Mission Status")

    DMS.CommandMenu.addCommand("obj_status", "Objective Status", "status", function()
        if DMS.Objectives then
            local status = DMS.Objectives.getStatusReport()
            trigger.action.outTextForCoalition(
                DMS.CommandMenu.Config.playerCoalition,
                status,
                15
            )
        else
            trigger.action.outTextForCoalition(
                DMS.CommandMenu.Config.playerCoalition,
                "No objectives tracking active.",
                5
            )
        end
    end)

    DMS.CommandMenu.addCommand("threat_status", "Threat Status", "status", function()
        local msg = "THREAT STATUS:\n"

        -- Check various systems
        if DMS.Awareness then
            local alert = #DMS.Awareness.getGroupsInState("ALERT")
            local hunting = #DMS.Awareness.getGroupsInState("HUNTING")
            msg = msg .. string.format("Alert groups: %d\nHunting groups: %d\n", alert, hunting)
        end

        if DMS.SkillScaling then
            local skill = DMS.SkillScaling.getCurrentSkill()
            msg = msg .. string.format("Enemy skill: %s\n", skill)
        end

        trigger.action.outTextForCoalition(
            DMS.CommandMenu.Config.playerCoalition,
            msg,
            10
        )
    end)

    DMS.CommandMenu.addCommand("time_status", "Mission Time", "status", function()
        local missionTime = timer.getTime()
        local minutes = math.floor(missionTime / 60)
        local seconds = math.floor(missionTime % 60)

        trigger.action.outTextForCoalition(
            DMS.CommandMenu.Config.playerCoalition,
            string.format("Mission Time: %02d:%02d", minutes, seconds),
            5
        )
    end)
end

--- Add tactical options menu
function DMS.CommandMenu.addTacticalMenu()
    DMS.CommandMenu.addMenu("tactical", "Tactical Options")

    DMS.CommandMenu.addCommand("mark_target", "Mark Current Position", "tactical", function()
        -- Get first player position
        local players = coalition.getPlayers(DMS.CommandMenu.Config.playerCoalition)
        if players and #players > 0 then
            local pos = players[1]:getPoint()
            trigger.action.smoke(pos, trigger.smokeColor.Red)
            trigger.action.outTextForCoalition(
                DMS.CommandMenu.Config.playerCoalition,
                string.format("Position marked with red smoke\nGrid: %.0f, %.0f", pos.x, pos.z),
                10
            )
        end
    end, {confirmation = "Marking position..."})

    DMS.CommandMenu.addCommand("flare", "Pop Flare", "tactical", function()
        local players = coalition.getPlayers(DMS.CommandMenu.Config.playerCoalition)
        if players and #players > 0 then
            local pos = players[1]:getPoint()
            trigger.action.illuminationBomb({x = pos.x, y = pos.y + 500, z = pos.z}, 100000)
        end
    end, {confirmation = "Flare away!"})
end

--- Build full menu from definition table
-- @param definition table Menu structure definition
function DMS.CommandMenu.buildFromDefinition(definition)
    DMS.CommandMenu.createRootMenu()

    local function processItems(items, parentId)
        for _, item in ipairs(items) do
            if item.type == "menu" then
                DMS.CommandMenu.addMenu(item.id, item.name, parentId)
                if item.items then
                    processItems(item.items, item.id)
                end
            elseif item.type == "command" then
                DMS.CommandMenu.addCommand(
                    item.id,
                    item.name,
                    parentId,
                    item.callback,
                    item.options
                )
            end
        end
    end

    processItems(definition, nil)
end

--- Clear all menus
function DMS.CommandMenu.clearAll()
    -- Remove all commands
    for commandId, _ in pairs(DMS.CommandMenu.Commands) do
        DMS.CommandMenu.removeCommand(commandId)
    end

    -- Remove all menus
    for menuId, _ in pairs(DMS.CommandMenu.Menus) do
        DMS.CommandMenu.removeMenu(menuId)
    end

    -- Remove root
    if DMS.CommandMenu.MenuHandles.root then
        missionCommands.removeItemForCoalition(
            DMS.CommandMenu.Config.playerCoalition,
            DMS.CommandMenu.MenuHandles.root
        )
        DMS.CommandMenu.MenuHandles.root = nil
    end
end

--- Add all standard menus
function DMS.CommandMenu.addStandardMenus()
    DMS.CommandMenu.addSupportMenu()
    DMS.CommandMenu.addStatusMenu()
    DMS.CommandMenu.addTacticalMenu()
end

--[[
USAGE EXAMPLE:

-- Configure
DMS.CommandMenu.configure({
    rootMenuName = "Operation Thunder",
    showConfirmations = true,
})

-- Add standard menus
DMS.CommandMenu.addStandardMenus()

-- Add custom menu
DMS.CommandMenu.addMenu("custom", "Special Commands")

DMS.CommandMenu.addCommand("call_extraction", "Call Extraction", "custom", function()
    -- Spawn extraction helicopter
    trigger.action.outTextForCoalition(coalition.side.BLUE, "Extraction inbound!", 10)
    -- ... spawn logic
end, {confirmation = "Extraction requested", cooldown = 300})

-- Or build from definition
DMS.CommandMenu.buildFromDefinition({
    {
        type = "menu",
        id = "air_support",
        name = "Air Support",
        items = {
            {
                type = "command",
                id = "call_a10",
                name = "Call A-10 Strike",
                callback = function() --[[ strike logic ]] end,
                options = {cooldown = 180},
            },
            {
                type = "command",
                id = "call_f16",
                name = "Call F-16 SEAD",
                callback = function() --[[ sead logic ]] end,
            },
        },
    },
})

-- Result in F10 menu:
-- Mission Commands
--   ├─ Request Support
--   │    ├─ Request Intel Update
--   │    ├─ Request Artillery Strike
--   │    └─ Request CAS Support
--   ├─ Mission Status
--   │    ├─ Objective Status
--   │    ├─ Threat Status
--   │    └─ Mission Time
--   ├─ Tactical Options
--   │    ├─ Mark Current Position
--   │    └─ Pop Flare
--   ├─ Special Commands
--   │    └─ Call Extraction
--   └─ Air Support
--        ├─ Call A-10 Strike
--        └─ Call F-16 SEAD
]]

-- Export
_G.DMS = DMS
