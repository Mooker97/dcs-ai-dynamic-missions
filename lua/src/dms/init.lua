-- DMS init: last in the manifest. Boots the runtime when DMS_CONFIG is present.
-- Specs (where DMS_CONFIG is nil at load time) call DMS.boot() themselves.

DMS = DMS or {}

DMS.START_ORDER = { "Spawner", "Ground", "Director", "Encounters", "Narrative", "Comms", "Intel", "Ambient", "Flights" }

local function count(t)
  if type(t) ~= "table" then
    return 0
  end
  local n = 0
  for _ in pairs(t) do
    n = n + 1
  end
  return n
end

function DMS.boot()
  if DMS._booted then
    return false
  end
  DMS._booted = true
  local cfg = DMS_CONFIG
  if type(cfg) ~= "table" then
    cfg = {}
  end

  if cfg.debug ~= nil then
    DMS.Log.setDebug(cfg.debug == true)
  end
  local seed = DMS.Rng and DMS.Rng.seed and DMS.Rng.seed() or nil

  local started, failed = {}, {}
  for _, name in ipairs(DMS.START_ORDER) do
    local mod = DMS[name]
    if type(mod) == "table" and type(mod.start) == "function" then
      local ok = DMS.safeCall(mod.start, mod)
      if ok then
        started[#started + 1] = name
      else
        failed[#failed + 1] = name
      end
    end
  end

  local b = type(cfg.budgets) == "table" and cfg.budgets or {}
  DMS.Log.info(
    "Init",
    "DMS %s started: mission=%s seed=%s debug=%s budgets(ground=%s air=%s spm=%s) "
      .. "templates=%d pools=%d zones=%d encounters=%d beats=%d modules=[%s]%s",
    tostring(DMS.VERSION),
    tostring(cfg.missionId),
    tostring(seed),
    tostring(DMS.Log.isDebug()),
    tostring(b.maxActiveGround),
    tostring(b.maxActiveAir),
    tostring(b.spawnsPerMin),
    count(cfg.templates),
    count(cfg.pools),
    count(cfg.zones),
    count(cfg.encounters),
    count(cfg.beats),
    table.concat(started, ","),
    #failed > 0 and (" FAILED=[" .. table.concat(failed, ",") .. "]") or ""
  )
  if DMS.Bus and DMS.Bus.emit then
    DMS.Bus.emit("mission.start", { missionId = cfg.missionId })
  end
  return true
end

-- Order-independent boot: canonical embed order is dms_config.lua before dms.lua, but if the
-- config is loaded after the bundle we re-check a few times and boot once it appears.
DMS.BOOT_RETRIES = DMS.BOOT_RETRIES or 5
DMS.BOOT_RETRY_SEC = DMS.BOOT_RETRY_SEC or 1

function DMS._deferBoot()
  if not (DMS.Clock and DMS.Clock.after) then
    DMS.Log.warn("Init", "DMS_CONFIG missing and DMS.Clock unavailable; runtime modules not started")
    return false
  end
  local tries = 0
  -- a module already started by hand (tests, custom scripts) means someone else owns the lifecycle
  local function startedByHand()
    for _, name in ipairs(DMS.START_ORDER) do
      local m = DMS[name]
      if type(m) == "table" and (m._started == true or (type(m._s) == "table" and m._s.started == true)) then
        return name
      end
    end
    return nil
  end
  local function check()
    if DMS._booted then
      return
    end
    local manual = startedByHand()
    if manual then
      DMS.Log.debug("Init", "deferred boot skipped: %s was started manually", manual)
      return
    end
    if DMS_CONFIG ~= nil then
      DMS.Log.info(
        "Init",
        "DMS_CONFIG appeared after load (%.0fs); booting",
        tries * DMS.BOOT_RETRY_SEC + DMS.BOOT_RETRY_SEC
      )
      DMS.safeCall(DMS.boot)
      return
    end
    tries = tries + 1
    if tries >= DMS.BOOT_RETRIES then
      DMS.Log.warn(
        "Init",
        "DMS_CONFIG never appeared after %ds; runtime modules not started " .. "(embed dms_config.lua before dms.lua)",
        tries * DMS.BOOT_RETRY_SEC
      )
      return
    end
    DMS.Clock.after(DMS.BOOT_RETRY_SEC, check)
  end
  DMS.Clock.after(DMS.BOOT_RETRY_SEC, check)
  return true
end

if DMS_CONFIG ~= nil then
  DMS.safeCall(DMS.boot)
else
  DMS.Log.info(
    "Init",
    "DMS %s loaded; DMS_CONFIG missing, runtime modules not started yet (waiting for config)",
    tostring(DMS.VERSION)
  )
  DMS._deferBoot()
end
