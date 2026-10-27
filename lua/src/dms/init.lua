-- DMS init: last in the manifest. Boots the runtime when DMS_CONFIG is present.
-- Specs (where DMS_CONFIG is nil at load time) call DMS.boot() themselves.

DMS = DMS or {}

DMS.START_ORDER = { "Spawner", "Ground", "Director", "Encounters", "Narrative", "Comms", "Intel" }

local function count(t)
  if type(t) ~= "table" then return 0 end
  local n = 0
  for _ in pairs(t) do n = n + 1 end
  return n
end

function DMS.boot()
  if DMS._booted then return false end
  DMS._booted = true
  local cfg = DMS_CONFIG
  if type(cfg) ~= "table" then cfg = {} end

  if cfg.debug ~= nil then DMS.Log.setDebug(cfg.debug == true) end
  local seed = DMS.Rng and DMS.Rng.seed and DMS.Rng.seed() or nil

  local started, failed = {}, {}
  for _, name in ipairs(DMS.START_ORDER) do
    local mod = DMS[name]
    if type(mod) == "table" and type(mod.start) == "function" then
      local ok = DMS.safeCall(mod.start, mod)
      if ok then started[#started + 1] = name else failed[#failed + 1] = name end
    end
  end

  local b = type(cfg.budgets) == "table" and cfg.budgets or {}
  DMS.Log.info("Init", "DMS %s started: mission=%s seed=%s debug=%s budgets(ground=%s air=%s spm=%s) "
    .. "templates=%d pools=%d zones=%d encounters=%d beats=%d modules=[%s]%s",
    tostring(DMS.VERSION), tostring(cfg.missionId), tostring(seed), tostring(DMS.Log.isDebug()),
    tostring(b.maxActiveGround), tostring(b.maxActiveAir), tostring(b.spawnsPerMin),
    count(cfg.templates), count(cfg.pools), count(cfg.zones), count(cfg.encounters), count(cfg.beats),
    table.concat(started, ","), #failed > 0 and (" FAILED=[" .. table.concat(failed, ",") .. "]") or "")
  return true
end

if DMS_CONFIG ~= nil then
  DMS.safeCall(DMS.boot)
else
  DMS.Log.info("Init", "DMS %s loaded; DMS_CONFIG missing, runtime modules not started", tostring(DMS.VERSION))
end
