-- DMS core: logging, safeCall, tiny JSON encoder, outcome lines.
-- Lua 5.1 (DCS mission scripting). See docs/CONTRACTS.md.

DMS = DMS or {}
DMS.VERSION = DMS.VERSION or "dev"
DMS.Log = DMS.Log or {}
DMS.Json = DMS.Json or {}

local Log = DMS.Log
local Json = DMS.Json

-- nil = follow DMS_CONFIG.debug
Log._debug = Log._debug

function Log.setDebug(on)
  Log._debug = on and true or false
end

function Log.isDebug()
  if Log._debug ~= nil then
    return Log._debug
  end
  local cfg = DMS_CONFIG
  return type(cfg) == "table" and cfg.debug == true
end

-- string.format that never throws: non-number args are tostring'd; on failure falls back to concatenation.
local function format(fmt, ...)
  local n = select("#", ...)
  if n == 0 then
    return tostring(fmt)
  end
  local args = { ... }
  for i = 1, n do
    local v = args[i]
    if type(v) ~= "number" and type(v) ~= "string" then
      args[i] = tostring(v)
    end
  end
  local ok, msg = pcall(string.format, tostring(fmt), unpack(args, 1, n))
  if ok then
    return msg
  end
  local parts = { tostring(fmt) }
  for i = 1, n do
    parts[#parts + 1] = tostring(args[i])
  end
  return table.concat(parts, " ")
end
Log.format = format

local function emit(sink, prefix, fmt, ...)
  local line = "[DMS][" .. tostring(prefix) .. "] " .. format(fmt, ...)
  if env and env[sink] then
    env[sink](line)
  end
  return line
end

function Log.debug(prefix, fmt, ...)
  if not Log.isDebug() then
    return
  end
  return emit("info", prefix, fmt, ...)
end
function Log.info(prefix, fmt, ...)
  return emit("info", prefix, fmt, ...)
end
function Log.warn(prefix, fmt, ...)
  return emit("warning", prefix, fmt, ...)
end
function Log.error(prefix, fmt, ...)
  return emit("error", prefix, fmt, ...)
end

-- ---------------------------------------------------------------------------
-- safeCall
-- ---------------------------------------------------------------------------

local function traceback(err)
  if debug and debug.traceback then
    return debug.traceback(tostring(err), 2)
  end
  return tostring(err)
end

-- DMS.safeCall(fn, ...) -> true, results... | false, errWithTraceback
function DMS.safeCall(fn, ...)
  if type(fn) ~= "function" then
    local t = type(fn)
    if t == "table" or t == "userdata" then
      local mt = getmetatable(fn)
      if not (mt and mt.__call) then
        Log.error("safeCall", "not callable: %s", t)
        return false, "not callable: " .. t
      end
    else
      Log.error("safeCall", "not callable: %s", t)
      return false, "not callable: " .. t
    end
  end
  local n = select("#", ...)
  local args = { ... }
  local res = { xpcall(function()
    return fn(unpack(args, 1, n))
  end, traceback) }
  if not res[1] then
    Log.error("safeCall", "%s", res[2])
    return false, res[2]
  end
  return unpack(res, 1, table.maxn(res))
end

-- ---------------------------------------------------------------------------
-- JSON (encode only)
-- ---------------------------------------------------------------------------

local ESC =
  { ['"'] = '\\"', ["\\"] = "\\\\", ["\b"] = "\\b", ["\f"] = "\\f", ["\n"] = "\\n", ["\r"] = "\\r", ["\t"] = "\\t" }

local function encodeString(s)
  return '"'
    .. string.gsub(s, '[%c"\\]', function(c)
      return ESC[c] or string.format("\\u%04x", string.byte(c))
    end)
    .. '"'
end

local function encodeNumber(x)
  if x ~= x or x == math.huge or x == -math.huge then
    return "null"
  end
  if x == math.floor(x) and math.abs(x) < 1e15 then
    return string.format("%d", x)
  end
  return string.format("%.14g", x)
end

local function isArray(t)
  local n = 0
  for k in pairs(t) do
    if type(k) ~= "number" or k < 1 or k ~= math.floor(k) then
      return false
    end
    n = n + 1
  end
  if n == 0 then
    return false
  end
  for i = 1, n do
    if t[i] == nil then
      return false
    end
  end
  return true, n
end

local encodeValue
encodeValue = function(v, seen)
  local t = type(v)
  if v == nil then
    return "null"
  elseif t == "boolean" then
    return v and "true" or "false"
  elseif t == "number" then
    return encodeNumber(v)
  elseif t == "string" then
    return encodeString(v)
  elseif t == "table" then
    if seen[v] then
      error("DMS.Json.encode: cycle detected")
    end
    seen[v] = true
    local out
    local arr, n = isArray(v)
    if arr then
      local parts = {}
      for i = 1, n do
        parts[i] = encodeValue(v[i], seen)
      end
      out = "[" .. table.concat(parts, ",") .. "]"
    else
      local keys = {}
      for k in pairs(v) do
        keys[#keys + 1] = k
      end
      table.sort(keys, function(a, b)
        return tostring(a) < tostring(b)
      end)
      local parts = {}
      for _, k in ipairs(keys) do
        local val = v[k]
        local vt = type(val)
        if vt ~= "function" and vt ~= "userdata" and vt ~= "thread" then
          parts[#parts + 1] = encodeString(tostring(k)) .. ":" .. encodeValue(val, seen)
        end
      end
      out = "{" .. table.concat(parts, ",") .. "}"
    end
    seen[v] = nil
    return out
  else
    return encodeString(tostring(v))
  end
end

-- Deterministic (sorted keys). Empty tables encode as {}. Errors on cycles.
function Json.encode(v)
  return encodeValue(v, {})
end

-- DMS.Log.outcome(tbl): one machine-readable line for the debriefer.
function Log.outcome(tbl)
  local ok, s = pcall(Json.encode, tbl)
  if not ok then
    Log.error("Outcome", "could not encode outcome: %s", s)
    return nil
  end
  local line = "[DMS.OUTCOME] " .. s
  if env and env.info then
    env.info(line)
  end
  return line
end
