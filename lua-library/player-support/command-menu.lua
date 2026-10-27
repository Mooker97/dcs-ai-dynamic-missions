-- F10 Command Menu System for DCS Missions
-- Dynamic radio menu builder for player interactions
-- Place in mission via DO SCRIPT FILE
--
-- Menus are built PER PLAYER GROUP (missionCommands.*ForGroup) so that every
-- command knows exactly which player/group pressed it. Menu/command definitions
-- are registered with addMenu/addCommand and are materialised for each player
-- group when it spawns (S_EVENT_BIRTH / S_EVENT_PLAYER_ENTER_UNIT). Definitions
-- added after players have spawned are also pushed to existing player groups.
--
-- Command callbacks receive a context table:
--   ctx = { groupId, groupName, unitName, playerName, coalition }
-- Use DMS.CommandMenu.getUnit(ctx) to fetch the live Unit (may be nil if dead).

DMS = DMS or {}
DMS.CommandMenu = {}

-- Definitions (shared by all groups)
DMS.CommandMenu.Menus = {}         -- menuId -> {id, name, parent}
DMS.CommandMenu.MenuOrder = {}     -- ordered list of menuIds
DMS.CommandMenu.Commands = {}      -- commandId -> {id, name, menu, callback, options, cooldown}
DMS.CommandMenu.CommandOrder = {}  -- ordered list of commandIds

-- Per-group state
DMS.CommandMenu.Groups = {}        -- groupId -> {ctx, root, menus = {menuId=path}, commands = {commandId=path}, lastUsed = {}}
DMS.CommandMenu.MenuHandles = {}   -- kept for backwards compat (unused)

DMS.CommandMenu.Initialized = false

-- Configuration
DMS.CommandMenu.Config = {
    playerCoalition = coalition.side.BLUE,  -- nil = all coalitions
    rootMenuName = "Mission Commands",
    showConfirmations = true,
    confirmationDuration = 5,
}

-- ============================================================================
-- Local helpers
-- ============================================================================

local function isDebug()
    return DMS.Settings and DMS.Settings.isDebug and DMS.Settings.isDebug()
end

local function debugLog(fmt, ...)
    if isDebug() then
        env.info(string.format("[CommandMenu] " .. fmt, ...))
    end
end

local function logError(context, err)
    env.error(string.format("[CommandMenu] %s: %s", context, tostring(err)))
    if DMS.Error and DMS.Error.log then
        pcall(DMS.Error.log, "CommandMenu", context, err)
    end
end

local function msgToGroup(ctx, text, duration)
    if ctx and ctx.groupId then
        trigger.action.outTextForGroup(ctx.groupId, text, duration or 10)
    end
end

local function coalitionAllowed(side)
    local wanted = DMS.CommandMenu.Config.playerCoalition
    return wanted == nil or wanted == side
end

--- Get the live unit that owns a menu context
-- @param ctx table Callback context
-- @return Unit|nil
function DMS.CommandMenu.getUnit(ctx)
    if not ctx then return nil end
    if ctx.unitName then
        local unit = Unit.getByName(ctx.unitName)
        if unit and unit:isExist() then return unit end
    end
    if ctx.groupName then
        local group = Group.getByName(ctx.groupName)
        if group and group:isExist() then
            for _, u in ipairs(group:getUnits() or {}) do
                if u and u:isExist() then return u end
            end
        end
    end
    return nil
end

--- Configure command menu system
-- @param settings table Configuration overrides
function DMS.CommandMenu.configure(settings)
    for key, value in pairs(settings or {}) do
        DMS.CommandMenu.Config[key] = value
    end
end

-- ============================================================================
-- Per-group materialisation
-- ============================================================================

local function ensureRoot(gs)
    if not gs.root then
        gs.root = missionCommands.addSubMenuForGroup(gs.ctx.groupId, DMS.CommandMenu.Config.rootMenuName)
    end
    return gs.root
end

local function buildMenuForGroup(gs, menuId)
    if gs.menus[menuId] then return gs.menus[menuId] end
    local def = DMS.CommandMenu.Menus[menuId]
    if not def then return nil end
    local parentPath
    if def.parent then
        parentPath = buildMenuForGroup(gs, def.parent)
    else
        parentPath = ensureRoot(gs)
    end
    if not parentPath then return nil end
    gs.menus[menuId] = missionCommands.addSubMenuForGroup(gs.ctx.groupId, def.name, parentPath)
    return gs.menus[menuId]
end

local function runCommand(args)
    local ok, err = pcall(function()
        local gs = DMS.CommandMenu.Groups[args.groupId]
        local def = DMS.CommandMenu.Commands[args.commandId]
        if not gs or not def then return end
        local ctx = gs.ctx

        -- Per-group cooldown
        local now = timer.getTime()
        local last = gs.lastUsed[def.id] or -math.huge
        if def.cooldown > 0 and now - last < def.cooldown then
            msgToGroup(ctx, string.format("%s unavailable for %d more seconds.", def.name, math.ceil(def.cooldown - (now - last))), 5)
            return
        end
        gs.lastUsed[def.id] = now

        debugLog("'%s' pressed by group %s (%s)", def.name, tostring(ctx.groupName), tostring(ctx.playerName))

        -- Confirmation first so the callback's own output appears below it
        if DMS.CommandMenu.Config.showConfirmations then
            local msg = def.options.confirmation or string.format("%s executed", def.name)
            msgToGroup(ctx, msg, DMS.CommandMenu.Config.confirmationDuration)
        end

        if def.callback then
            def.callback(ctx)
        end
    end)
    if not ok then logError("command " .. tostring(args.commandId), err) end
end

local function buildCommandForGroup(gs, commandId)
    if gs.commands[commandId] then return end
    local def = DMS.CommandMenu.Commands[commandId]
    if not def then return end
    local parentPath
    if def.menu then
        parentPath = buildMenuForGroup(gs, def.menu)
    else
        parentPath = ensureRoot(gs)
    end
    if not parentPath then return end
    gs.commands[commandId] = missionCommands.addCommandForGroup(
        gs.ctx.groupId, def.name, parentPath, runCommand,
        {groupId = gs.ctx.groupId, commandId = commandId}
    )
end

local function buildAllForGroup(gs)
    for _, menuId in ipairs(DMS.CommandMenu.MenuOrder) do
        if DMS.CommandMenu.Menus[menuId] then buildMenuForGroup(gs, menuId) end
    end
    for _, commandId in ipairs(DMS.CommandMenu.CommandOrder) do
        if DMS.CommandMenu.Commands[commandId] then buildCommandForGroup(gs, commandId) end
    end
end

--- Register a player unit (builds menus for its group once)
-- @param unit Unit Player unit
function DMS.CommandMenu.registerPlayerUnit(unit)
    if not unit or not unit:isExist() then return end
    local playerName = unit.getPlayerName and unit:getPlayerName()
    if not playerName then return end
    if not coalitionAllowed(unit:getCoalition()) then return end
    local group = unit:getGroup()
    if not group then return end
    local groupId = group:getID()

    local gs = DMS.CommandMenu.Groups[groupId]
    if gs then
        -- Already built: just refresh who is flying it
        gs.ctx.unitName = unit:getName()
        gs.ctx.playerName = playerName
        return
    end

    gs = {
        ctx = {
            groupId = groupId,
            groupName = group:getName(),
            unitName = unit:getName(),
            playerName = playerName,
            coalition = unit:getCoalition(),
        },
        menus = {},
        commands = {},
        lastUsed = {},
    }
    DMS.CommandMenu.Groups[groupId] = gs
    buildAllForGroup(gs)
    debugLog("Built menus for group %s (player %s)", gs.ctx.groupName, playerName)
end

local eventHandler = {}
function eventHandler:onEvent(event)
    if not event or (event.id ~= world.event.S_EVENT_BIRTH and event.id ~= world.event.S_EVENT_PLAYER_ENTER_UNIT) then
        return
    end
    local ok, err = pcall(function()
        local unit = event.initiator
        if not unit or Object.getCategory(unit) ~= Object.Category.UNIT then return end
        DMS.CommandMenu.registerPlayerUnit(unit)
    end)
    if not ok then logError("onEvent", err) end
end

--- Initialise per-group menu building (idempotent). Called automatically by
-- addMenu/addCommand, but can be called directly.
function DMS.CommandMenu.init()
    if DMS.CommandMenu.Initialized then return end
    DMS.CommandMenu.Initialized = true
    world.addEventHandler(eventHandler)

    -- Catch players already in the mission
    for _, side in ipairs({coalition.side.RED, coalition.side.BLUE}) do
        if coalitionAllowed(side) then
            for _, unit in ipairs(coalition.getPlayers(side) or {}) do
                pcall(DMS.CommandMenu.registerPlayerUnit, unit)
            end
        end
    end
    debugLog("Initialised (root menu '%s')", DMS.CommandMenu.Config.rootMenuName)
end

-- Backwards-compatible alias
function DMS.CommandMenu.createRootMenu()
    DMS.CommandMenu.init()
end

-- ============================================================================
-- Definition API
-- ============================================================================

--- Add a submenu
-- @param menuId string Unique menu ID
-- @param menuName string Display name
-- @param parentId string|nil Parent menu ID (nil = root)
function DMS.CommandMenu.addMenu(menuId, menuName, parentId)
    DMS.CommandMenu.init()
    if not DMS.CommandMenu.Menus[menuId] then
        table.insert(DMS.CommandMenu.MenuOrder, menuId)
    end
    DMS.CommandMenu.Menus[menuId] = {id = menuId, name = menuName, parent = parentId}

    for _, gs in pairs(DMS.CommandMenu.Groups) do
        local ok, err = pcall(buildMenuForGroup, gs, menuId)
        if not ok then logError("addMenu", err) end
    end
    return menuId
end

--- Add a command to a menu
-- @param commandId string Unique command ID
-- @param commandName string Display name
-- @param menuId string|nil Menu ID (nil = root)
-- @param callback function function(ctx) called when selected
-- @param options table|nil {confirmation = string, cooldown = seconds}
function DMS.CommandMenu.addCommand(commandId, commandName, menuId, callback, options)
    DMS.CommandMenu.init()
    options = options or {}
    if not DMS.CommandMenu.Commands[commandId] then
        table.insert(DMS.CommandMenu.CommandOrder, commandId)
    end
    DMS.CommandMenu.Commands[commandId] = {
        id = commandId,
        name = commandName,
        menu = menuId,
        callback = callback,
        options = options,
        cooldown = options.cooldown or 0,
        enabled = true,
    }

    for _, gs in pairs(DMS.CommandMenu.Groups) do
        local ok, err = pcall(buildCommandForGroup, gs, commandId)
        if not ok then logError("addCommand", err) end
    end
    return commandId
end

--- Remove a command
-- @param commandId string Command ID
function DMS.CommandMenu.removeCommand(commandId)
    for _, gs in pairs(DMS.CommandMenu.Groups) do
        local path = gs.commands[commandId]
        if path then
            pcall(missionCommands.removeItemForGroup, gs.ctx.groupId, path)
            gs.commands[commandId] = nil
        end
    end
    DMS.CommandMenu.Commands[commandId] = nil
end

--- Remove a menu (and all its contents)
-- @param menuId string Menu ID
function DMS.CommandMenu.removeMenu(menuId)
    -- Forget child definitions
    for id, def in pairs(DMS.CommandMenu.Commands) do
        if def.menu == menuId then
            DMS.CommandMenu.Commands[id] = nil
            for _, gs in pairs(DMS.CommandMenu.Groups) do gs.commands[id] = nil end
        end
    end
    for id, def in pairs(DMS.CommandMenu.Menus) do
        if def.parent == menuId then DMS.CommandMenu.removeMenu(id) end
    end

    for _, gs in pairs(DMS.CommandMenu.Groups) do
        local path = gs.menus[menuId]
        if path then
            pcall(missionCommands.removeItemForGroup, gs.ctx.groupId, path)
            gs.menus[menuId] = nil
        end
    end
    DMS.CommandMenu.Menus[menuId] = nil
end

-- ============================================================================
-- Standard menus
-- ============================================================================

--- Add standard support menu
function DMS.CommandMenu.addSupportMenu()
    DMS.CommandMenu.addMenu("support", "Request Support")

    DMS.CommandMenu.addCommand("intel_update", "Request Intel Update", "support", function(ctx)
        if DMS.Intel and DMS.Intel.broadcastUpdate then
            DMS.Intel.broadcastUpdate(ctx.coalition, ctx.groupId)
        else
            msgToGroup(ctx, "INTEL: No active contacts at this time.", 10)
        end
    end, {confirmation = "INTEL: Compiling situation report..."})

    DMS.CommandMenu.addCommand("request_arty", "Request Artillery Strike", "support", function(ctx)
        local unit = DMS.CommandMenu.getUnit(ctx)
        if DMS.SupportRequests and DMS.SupportRequests.requestArtillery and unit then
            DMS.SupportRequests.requestArtillery(unit:getPoint(), {groupId = ctx.groupId})
        else
            msgToGroup(ctx, "ARTILLERY: Mark target with smoke. Strike inbound in 60 seconds.", 10)
        end
    end, {confirmation = "ARTILLERY: Request acknowledged.", cooldown = 120})

    DMS.CommandMenu.addCommand("request_cas", "Request CAS Support", "support", function(ctx)
        local unit = DMS.CommandMenu.getUnit(ctx)
        if DMS.SupportRequests and DMS.SupportRequests.requestCAS and unit then
            DMS.SupportRequests.requestCAS(unit:getPoint(), {groupId = ctx.groupId})
        else
            msgToGroup(ctx, "CAS: No additional air assets available at this time.", 10)
        end
    end, {confirmation = "CAS: Checking availability..."})
end

--- Add mission status menu
function DMS.CommandMenu.addStatusMenu()
    DMS.CommandMenu.addMenu("status", "Mission Status")

    DMS.CommandMenu.addCommand("obj_status", "Objective Status", "status", function(ctx)
        local status = nil
        if DMS.Objectives then
            if type(DMS.Objectives.getStatusReport) == "function" then
                status = DMS.Objectives.getStatusReport()
            elseif type(DMS.Objectives.getFormattedList) == "function" then
                status = DMS.Objectives.getFormattedList(true)
            end
        end
        if type(status) == "string" and status ~= "" then
            msgToGroup(ctx, status, 15)
        else
            msgToGroup(ctx, "No objectives tracking active.", 5)
        end
    end)

    DMS.CommandMenu.addCommand("threat_status", "Threat Status", "status", function(ctx)
        local msg = "THREAT STATUS:\n"
        local any = false

        if DMS.Awareness and DMS.Awareness.getGroupsInState then
            local alert = #(DMS.Awareness.getGroupsInState("ALERT") or {})
            local hunting = #(DMS.Awareness.getGroupsInState("HUNTING") or {})
            msg = msg .. string.format("Alert groups: %d\nHunting groups: %d\n", alert, hunting)
            any = true
        end

        if DMS.SkillScaling and DMS.SkillScaling.getCurrentSkill then
            msg = msg .. string.format("Enemy skill: %s\n", tostring(DMS.SkillScaling.getCurrentSkill()))
            any = true
        end

        if not any then msg = msg .. "No threat data available." end
        msgToGroup(ctx, msg, 10)
    end)

    DMS.CommandMenu.addCommand("time_status", "Mission Time", "status", function(ctx)
        local missionTime = timer.getTime()
        local minutes = math.floor(missionTime / 60)
        local seconds = math.floor(missionTime % 60)
        msgToGroup(ctx, string.format("Mission Time: %02d:%02d", minutes, seconds), 5)
    end)
end

--- Add tactical options menu
function DMS.CommandMenu.addTacticalMenu()
    DMS.CommandMenu.addMenu("tactical", "Tactical Options")

    DMS.CommandMenu.addCommand("mark_target", "Mark Current Position", "tactical", function(ctx)
        local unit = DMS.CommandMenu.getUnit(ctx)
        if not unit then
            msgToGroup(ctx, "Unable to mark: unit not found.", 5)
            return
        end
        local pos = unit:getPoint()
        local ground = {x = pos.x, y = land.getHeight({x = pos.x, y = pos.z}), z = pos.z}
        trigger.action.smoke(ground, trigger.smokeColor.Red)
        msgToGroup(ctx, string.format("Position marked with red smoke\nX/Z: %.0f, %.0f", pos.x, pos.z), 10)
    end, {confirmation = "Marking position..."})

    DMS.CommandMenu.addCommand("flare", "Pop Flare", "tactical", function(ctx)
        local unit = DMS.CommandMenu.getUnit(ctx)
        if not unit then return end
        local pos = unit:getPoint()
        trigger.action.illuminationBomb({x = pos.x, y = pos.y + 500, z = pos.z}, 100000)
    end, {confirmation = "Flare away!"})
end

--- Build full menu from definition table
-- @param definition table Menu structure definition
function DMS.CommandMenu.buildFromDefinition(definition)
    local function processItems(items, parentId)
        for _, item in ipairs(items or {}) do
            if item.type == "menu" then
                DMS.CommandMenu.addMenu(item.id, item.name, parentId)
                processItems(item.items, item.id)
            elseif item.type == "command" then
                DMS.CommandMenu.addCommand(item.id, item.name, parentId, item.callback, item.options)
            end
        end
    end
    processItems(definition, nil)
end

--- Clear all menus (for all groups)
function DMS.CommandMenu.clearAll()
    for _, gs in pairs(DMS.CommandMenu.Groups) do
        if gs.root then
            pcall(missionCommands.removeItemForGroup, gs.ctx.groupId, gs.root)
        end
        gs.root = nil
        gs.menus = {}
        gs.commands = {}
    end
    DMS.CommandMenu.Menus = {}
    DMS.CommandMenu.MenuOrder = {}
    DMS.CommandMenu.Commands = {}
    DMS.CommandMenu.CommandOrder = {}
end

--- Add all standard menus
function DMS.CommandMenu.addStandardMenus()
    DMS.CommandMenu.addSupportMenu()
    DMS.CommandMenu.addStatusMenu()
    DMS.CommandMenu.addTacticalMenu()
end

--- Set up the standard menus (entry point for mission scripts)
function DMS.CommandMenu.setupMenus()
    DMS.CommandMenu.init()
    DMS.CommandMenu.addStandardMenus()
end

--[==[
USAGE EXAMPLE:

DMS.CommandMenu.configure({
    rootMenuName = "Operation Thunder",
    showConfirmations = true,
})

-- Standard menus (built per player group on spawn)
DMS.CommandMenu.setupMenus()

-- Custom menu; callbacks receive ctx {groupId, groupName, unitName, playerName, coalition}
DMS.CommandMenu.addMenu("custom", "Special Commands")

DMS.CommandMenu.addCommand("call_extraction", "Call Extraction", "custom", function(ctx)
    trigger.action.outTextForGroup(ctx.groupId, "Extraction inbound!", 10)
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
                callback = function(ctx) --[[ strike logic ]] end,
                options = {cooldown = 180},
            },
        },
    },
})
]==]

-- Export
_G.DMS = DMS
