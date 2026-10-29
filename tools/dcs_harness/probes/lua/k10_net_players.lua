-- K10: do net.get_player_list / net.get_player_info work in the mission scripting env?
-- Logs what the net table exposes and what each call returns at t=2 and t=10. The player's
-- ucid is never logged, only whether the field exists.
local P = DMS_PROBE
local PROBE = "k10"
local CHUNK = 400

local function logKeys(phase)
  local netT = rawget(_G, "net")
  local keys = P.keys(netT)
  local parts = math.max(1, math.ceil(string.len(keys) / CHUNK))
  for i = 1, parts do
    local slice = string.sub(keys, (i - 1) * CHUNK + 1, i * CHUNK)
    P.log(PROBE, "phase", phase, "net_type", type(netT), "keys_part", i, "keys_parts", parts, "net_keys", slice)
  end
end

local function call(name, ...)
  local netT = rawget(_G, "net")
  local f = type(netT) == "table" and netT[name] or nil
  if type(f) ~= "function" then
    return false, "missing"
  end
  return pcall(f, ...)
end

local function probeOnce(phase)
  logKeys(phase)
  local okL, list = call("get_player_list")
  local ids = {}
  if okL and type(list) == "table" then
    for i, id in ipairs(list) do
      ids[i] = tostring(id)
    end
  end
  P.log(
    PROBE,
    "phase",
    phase,
    "call",
    "get_player_list",
    "ok",
    tostring(okL),
    "type",
    type(list),
    "count",
    (okL and type(list) == "table") and #list or -1,
    "ids",
    table.concat(ids, ","),
    "err",
    okL and "nil" or tostring(list)
  )
  local okM, me = call("get_my_player_id")
  P.log(PROBE, "phase", phase, "call", "get_my_player_id", "ok", tostring(okM), "value", tostring(me))
  local tryIds = {}
  for i = 1, math.min(#ids, 8) do
    tryIds[#tryIds + 1] = tonumber(ids[i])
  end
  if #tryIds == 0 then
    tryIds = { 1 }
  end
  for _, id in ipairs(tryIds) do
    local okI, info = call("get_player_info", id)
    local fields = {}
    if okI and type(info) == "table" then
      fields = info
    end
    P.log(
      PROBE,
      "phase",
      phase,
      "call",
      "get_player_info",
      "id",
      tostring(id),
      "ok",
      tostring(okI),
      "type",
      type(info),
      "keys",
      P.keys(fields),
      "name",
      tostring(fields.name),
      "side",
      tostring(fields.side),
      "slot",
      tostring(fields.slot),
      "has_ucid",
      tostring(fields.ucid ~= nil),
      "err",
      okI and "nil" or tostring(info)
    )
    local okN, nameAttr = call("get_player_info", id, "name")
    local v = tostring(nameAttr)
    P.log(PROBE, "phase", phase, "call", "get_player_info_attr", "id", tostring(id), "ok", tostring(okN), "value", v)
  end
end

P.start(PROBE)
P.after(PROBE, 2, function()
  probeOnce("t2")
end)
P.after(PROBE, 10, function()
  probeOnce("t10")
  P.finish(PROBE)
end)
