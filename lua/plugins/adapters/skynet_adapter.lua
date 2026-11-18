-- lua/plugins/adapters/skynet_adapter.lua
-- Optional DMS adapter for Skynet-IADS (lua/plugins/skynet, pinned; see lua/plugins/PINS.md).
--
-- Loaded after dms.lua when a mission spec lists `plugins: [skynet]` (the planner embeds
-- mist -> skynet -> dms_config.lua -> dms.lua -> this file). It builds one Skynet IADS from SAM
-- groups whose names start with a prefix (default "DMS_", i.e. DMS runtime spawns
-- DMS_<poolOrTemplate>_<n>), adds units with the EWR attribute in those groups as early-warning
-- radars, then keeps adding matching SAM groups as DMS spawns them (DMS.Bus "spawner.spawned",
-- added SPAWN_DELAY_SEC later: a new group's controller is not safe to touch for ~1 s).
-- Groups spawned by an `ambush_sam` encounter are skipped: that encounter already drives their
-- emission state (dark until players are close), and two controllers would fight.
--
-- It never fails the mission: without Skynet (SkynetIADS / samTypesDB), MIST or DMS it logs
-- one line and does nothing. The DMS core never depends on it (ADR 0003).
--
-- Options: an optional global table set before this file loads (e.g. in a DO SCRIPT):
--   DMS_SKYNET = {
--     enabled = true,              -- false: do nothing
--     prefixes = { "DMS_" },       -- group name prefixes (add ME threat ids to include them)
--     coalition = nil,             -- "red" | "blue": only groups of this side join; default is the
--                                  -- enemy of DMS_CONFIG.players.coalition (red when unset)
--     name = "DMS IADS",           -- Skynet IADS name
--     activateDelaySec = 2,        -- delay before iads:activate()
--     radioMenu = false,           -- Skynet's F10 debug radio menu
--   }
--
-- Lua 5.1 only. Scheduling goes through DMS.Clock and events through DMS.Bus.

do
  local PREFIX = "SkynetAdapter"

  local function g(name)
    return rawget(_G, name) -- strict-globals safe
  end

  local function plainLog(msg)
    local e = g("env")
    if e and e.info then
      e.info("[DMS][" .. PREFIX .. "] " .. msg)
    end
  end

  local DMS = g("DMS")
  if type(DMS) ~= "table" or type(DMS.Log) ~= "table" then
    plainLog("DMS runtime not loaded; adapter disabled (load it after dms.lua)")
    return
  end

  local A = DMS.SkynetAdapter or {}
  DMS.SkynetAdapter = A
  A.sites = A.sites or {}
  A.ewrs = A.ewrs or {}
  A.active = false

  local opts = g("DMS_SKYNET")
  if type(opts) ~= "table" then
    opts = {}
  end

  if opts.enabled == false then
    DMS.Log.info(PREFIX, "disabled by DMS_SKYNET.enabled = false")
    return
  end

  local Skynet = g("SkynetIADS")
  local samDB = g("samTypesDB")
  if type(Skynet) ~= "table" or type(Skynet.create) ~= "function" then
    DMS.Log.info(PREFIX, "Skynet-IADS not loaded; skipping (no IADS)")
    return
  end
  if type(g("mist")) ~= "table" then
    DMS.Log.warn(PREFIX, "Skynet-IADS loaded without MIST; skipping (load mist before skynet)")
    return
  end
  if type(samDB) ~= "table" then
    DMS.Log.warn(PREFIX, "Skynet samTypesDB missing; skipping")
    return
  end

  local prefixes = {}
  if type(opts.prefixes) == "table" then
    for i = 1, #opts.prefixes do
      if type(opts.prefixes[i]) == "string" then
        prefixes[#prefixes + 1] = opts.prefixes[i]
      end
    end
  else
    prefixes[1] = "DMS_"
  end
  local side
  if opts.coalition == "blue" then
    side = 2
  elseif opts.coalition == "red" then
    side = 1
  else
    local cfg = g("DMS_CONFIG")
    local pc = type(cfg) == "table" and type(cfg.players) == "table" and cfg.players.coalition or nil
    side = (pc == 1) and 2 or 1
  end
  local SPAWN_DELAY_SEC = 1.5
  A.SPAWN_DELAY_SEC = SPAWN_DELAY_SEC
  local delay = tonumber(opts.activateDelaySec) or 2

  -- unit type name -> true for every element Skynet knows (search/track radars, launchers, ...)
  local samTypes = {}
  for _, site in pairs(samDB) do
    if type(site) == "table" then
      for role, units in pairs(site) do
        if role ~= "type" and role ~= "name" and type(units) == "table" then
          for typeName in pairs(units) do
            if type(typeName) == "string" then
              samTypes[typeName] = true
            end
          end
        end
      end
    end
  end
  A.samTypes = samTypes

  local function hasPrefix(name)
    for i = 1, #prefixes do
      local p = prefixes[i]
      if string.sub(name, 1, string.len(p)) == p then
        return true
      end
    end
    return false
  end
  A.hasPrefix = hasPrefix

  -- returns isSam, {ewrUnitName...}
  local function inspect(group)
    local isSam, ewrs = false, {}
    local units = group:getUnits() or {}
    for i = 1, #units do
      local u = units[i]
      local okT, typeName = pcall(u.getTypeName, u)
      if okT and samTypes[typeName] then
        isSam = true
      end
      local okE, isEwr = pcall(u.hasAttribute, u, "EWR")
      if okE and isEwr then
        local okN, uname = pcall(u.getName, u)
        if okN and uname then
          ewrs[#ewrs + 1] = uname
        end
      end
    end
    return isSam, ewrs
  end

  -- kind of the DMS encounter with this id ("ambush_sam", "pool", ...), or nil
  local function encounterKind(id)
    if id == nil then
      return nil
    end
    local E = DMS.Encounters
    if type(E) == "table" and type(E.get) == "function" then
      local okS, st = pcall(E.get, id)
      if okS and type(st) == "table" and type(st.def) == "table" and st.def.kind then
        return st.def.kind
      end
    end
    local cfg = g("DMS_CONFIG")
    local list = type(cfg) == "table" and cfg.encounters or nil
    if type(list) == "table" then
      for i = 1, #list do
        if type(list[i]) == "table" and list[i].id == id then
          return list[i].kind
        end
      end
    end
    return nil
  end
  A.encounterKind = encounterKind

  -- encounter id of a DMS-tracked group (DMS.Registry meta), or nil
  local function encounterOf(groupName)
    local R = DMS.Registry
    if type(R) == "table" and type(R.get) == "function" then
      local okM, meta = pcall(R.get, groupName)
      if okM and type(meta) == "table" then
        return meta.encounter
      end
    end
    return nil
  end

  local function consider(groupName, why, encounter)
    if type(groupName) ~= "string" or not hasPrefix(groupName) then
      return false
    end
    if A.sites[groupName] then
      return false
    end
    local enc = encounter
    if enc == nil then
      enc = encounterOf(groupName)
    end
    if encounterKind(enc) == "ambush_sam" then
      DMS.Log.info(PREFIX, "skip %s: ambush_sam encounter %s controls it", groupName, tostring(enc))
      return false
    end
    local group = Group.getByName(groupName)
    if not group or not group:isExist() then
      DMS.Log.debug(PREFIX, "skip %s: group not found", groupName)
      return false
    end
    if group:getCoalition() ~= side then
      DMS.Log.debug(PREFIX, "skip %s: wrong coalition", groupName)
      return false
    end
    local isSam, ewrs = inspect(group)
    local added = false
    for i = 1, #ewrs do
      if not A.ewrs[ewrs[i]] then
        local ok, err = DMS.safeCall(function()
          return A.iads:addEarlyWarningRadar(ewrs[i])
        end)
        if ok then
          A.ewrs[ewrs[i]] = true
          added = true
          DMS.Log.info(PREFIX, "EW radar %s added (%s)", ewrs[i], why)
        else
          DMS.Log.warn(PREFIX, "EW radar %s not added: %s", ewrs[i], tostring(err))
        end
      end
    end
    if isSam then
      local ok, site = DMS.safeCall(function()
        return A.iads:addSAMSite(groupName)
      end)
      if ok and site then
        A.sites[groupName] = true
        added = true
        DMS.Log.info(PREFIX, "SAM site %s added (%s)", groupName, why)
      else
        DMS.Log.warn(PREFIX, "SAM site %s not added (Skynet cannot handle it)", groupName)
      end
    elseif #ewrs == 0 then
      DMS.Log.debug(PREFIX, "skip %s: no SAM or EWR units", groupName)
    end
    return added
  end
  A.consider = consider

  local okC, iads = DMS.safeCall(function()
    return Skynet:create(opts.name or "DMS IADS")
  end)
  if not okC or type(iads) ~= "table" then
    DMS.Log.error(PREFIX, "SkynetIADS:create failed; no IADS")
    return
  end
  A.iads = iads

  -- groups that already exist (ME threats with a matching prefix, early spawns)
  local okG, groups = pcall(coalition.getGroups, side, Group.Category.GROUND)
  local n = 0
  if okG and type(groups) == "table" then
    for i = 1, #groups do
      local okN, gname = pcall(groups[i].getName, groups[i])
      if okN and consider(gname, "existing") then
        n = n + 1
      end
    end
  end

  A.token = DMS.Bus.on("spawner.spawned", function(p)
    if type(p) ~= "table" or type(p.group) ~= "string" or not hasPrefix(p.group) then
      return
    end
    local name, enc = p.group, p.encounter
    if encounterKind(enc) == "ambush_sam" then
      DMS.Log.info(PREFIX, "skip %s: ambush_sam encounter %s controls it", name, tostring(enc))
      return
    end
    -- the controller of a fresh group is not ready yet (gotchas: wait ~1 s)
    DMS.Clock.after(SPAWN_DELAY_SEC, function()
      consider(name, "spawned", enc)
    end)
  end)

  DMS.Clock.after(delay, function()
    local ok = DMS.safeCall(function()
      if opts.radioMenu then
        A.iads:addRadioMenu()
      end
      A.iads:activate()
    end)
    A.active = ok and true or false
    DMS.Log.info(PREFIX, "IADS %s (%d existing site/radar groups)", ok and "activated" or "activation failed", n)
  end)

  DMS.Log.info(PREFIX, "started: prefixes %s, coalition %s", table.concat(prefixes, ","), side == 2 and "blue" or "red")
end
