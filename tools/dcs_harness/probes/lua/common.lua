-- DMS probe helpers (Lua 5.1). build_probes.py puts this in front of every probe script.
--
-- Probes are throwaway measurement scripts, not runtime modules: they may call
-- timer.scheduleFunction and world.addEventHandler directly (hard rule 3 covers lua/src only).
-- Protocol (parsed by parse_probes.py):
--   [DMS.PROBE] probe=<kN> key=value key="value with spaces" ...
--   [DMS.PROBE] probe=<kN> done=1      (last line of a probe)
--   [DMS.TEST] DONE                    (tells the harness hook to exit DCS)

DMS_PROBE = DMS_PROBE or {}
local P = DMS_PROBE

local function quote(v)
  local s = tostring(v)
  if s == "" or string.find(s, '[%s"=\\]') then
    s = string.gsub(s, "\\", "\\\\")
    s = string.gsub(s, '"', '\\"')
    s = string.gsub(s, "\n", "\\n")
    s = string.gsub(s, "\r", "\\r")
    s = string.gsub(s, "\t", "\\t")
    return '"' .. s .. '"'
  end
  return s
end
P.quote = quote

-- P.log(probe, k1, v1, k2, v2, ...): one [DMS.PROBE] line, keys in the given order.
function P.log(probe, ...)
  local parts = { "[DMS.PROBE] probe=" .. tostring(probe) }
  local n = select("#", ...)
  for i = 1, n, 2 do
    local k = select(i, ...)
    local v = select(i + 1, ...)
    parts[#parts + 1] = tostring(k) .. "=" .. quote(v)
  end
  env.info(table.concat(parts, " "))
end

function P.now()
  local ok, t = pcall(timer.getTime)
  if ok and type(t) == "number" then
    return t
  end
  return -1
end

function P.fmt(x)
  if type(x) ~= "number" then
    return tostring(x)
  end
  return string.format("%.3f", x)
end

-- Sorted, comma-joined keys of a table (or tostring of a non-table).
function P.keys(t)
  if type(t) ~= "table" then
    return tostring(t)
  end
  local ks = {}
  for k in pairs(t) do
    ks[#ks + 1] = tostring(k)
  end
  table.sort(ks)
  return table.concat(ks, ",")
end

-- Run fn once, sec model seconds from now. Errors are logged, never raised into the scheduler.
function P.after(probe, sec, fn)
  timer.scheduleFunction(function()
    local ok, err = pcall(fn)
    if not ok then
      P.log(probe, "error", tostring(err), "t", P.fmt(P.now()))
    end
    return nil
  end, nil, timer.getTime() + sec)
end

-- First unit position of a group (Vec3) or nil.
function P.groupPoint(name)
  local ok, p = pcall(function()
    local g = Group.getByName(name)
    local u = g and g:getUnit(1)
    if u and u:isExist() then
      return u:getPoint()
    end
    return nil
  end)
  if ok then
    return p
  end
  return nil
end

function P.start(probe)
  local okV, ver = pcall(function()
    return rawget(_G, "_APP_VERSION")
  end)
  local okA, abs = pcall(timer.getAbsTime)
  P.log(
    probe,
    "phase",
    "start",
    "t",
    P.fmt(P.now()),
    "abs",
    okA and P.fmt(abs) or "error",
    "app_version",
    okV and tostring(ver) or "error"
  )
end

function P.finish(probe)
  P.log(probe, "done", 1, "t", P.fmt(P.now()))
  env.info("[DMS.TEST] DONE")
end
