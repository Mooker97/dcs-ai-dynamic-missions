-- DMS PedalRudder: the DCS half of the pedal rudder bridge.
--
-- Installed to Saved Games\DCS\Scripts\DMS\PedalRudder.lua and loaded by one line at the end of
-- Export.lua (see tools/pedal_rudder/README.md). tools/pedal_rudder/pedal_rudder.py reads the
-- racing pedals, mixes them into one rudder value in -1..1 and sends it here over localhost UDP
-- as plain text. Every frame this file feeds the latest value to DCS with
-- LoSetCommand(2003, value) (the generic rudder axis). No virtual device exists in Windows.
--
-- This runs in the Export environment, not the mission environment, so require/socket/lfs are
-- available here (they are banned in lua/src/dms). Lua 5.1.
--
-- Safety:
--   * It wraps the existing LuaExportStart/BeforeNextFrame/Stop and always calls them first,
--     so DCS-BIOS and other exports keep working.
--   * Every DMS step runs under pcall, so a bug here can never break those other exports.
--   * If no packet arrives for STALE_SEC, it sends 0 once and then stops touching the rudder.
--   * Every ACK_SEC it replies "DMS-ACK" to the sender so the terminal readout can show "linked".

local DMSPR = {
  PORT = 47801,
  STALE_SEC = 0.5,
  ACK_SEC = 0.5,
  RUDDER_CMD = 2003,
  MAX_PACKETS_PER_FRAME = 256,
}

local socketLib = nil
local udp = nil
local value = 0
local lastRecv = -1000
local lastAck = -1000
local feeding = false
local peerIp = nil
local peerPort = nil

local function say(level, msg)
  if log and log.write then
    log.write("DMS.PedalRudder", level, msg)
  end
end

local function info(msg)
  say(log and log.INFO or 0, msg)
end

local function warn(msg)
  say(log and log.WARNING or 0, msg)
end

local function now()
  if socketLib then
    return socketLib.gettime()
  end
  return 0
end

local function clamp(v)
  if v ~= v then
    return 0
  end
  if v > 1 then
    return 1
  end
  if v < -1 then
    return -1
  end
  return v
end

local function openSocket()
  if udp then
    return
  end
  if not socketLib then
    local base = "."
    if lfs and lfs.currentdir then
      base = lfs.currentdir()
    end
    package.path = package.path .. ";" .. base .. "/LuaSocket/?.lua"
    package.cpath = package.cpath .. ";" .. base .. "/LuaSocket/?.dll"
    socketLib = require("socket")
  end
  local s = socketLib.udp()
  local ok, err = s:setsockname("127.0.0.1", DMSPR.PORT)
  if not ok then
    warn("cannot bind 127.0.0.1:" .. DMSPR.PORT .. ": " .. tostring(err))
    s:close()
    return
  end
  s:settimeout(0)
  udp = s
  info("listening on 127.0.0.1:" .. DMSPR.PORT .. ", rudder command " .. DMSPR.RUDDER_CMD)
end

local function closeSocket()
  if feeding then
    LoSetCommand(DMSPR.RUDDER_CMD, 0)
    feeding = false
  end
  if udp then
    udp:close()
    udp = nil
    info("stopped")
  end
end

local function frame()
  if not udp then
    return
  end
  local t = now()
  local got = false
  for _ = 1, DMSPR.MAX_PACKETS_PER_FRAME do
    local data, ip, port = udp:receivefrom()
    if not data then
      break
    end
    local v = tonumber(data)
    if v then
      value = clamp(v)
      got = true
      peerIp = ip
      peerPort = port
    end
  end
  if got then
    lastRecv = t
    if not feeding then
      feeding = true
      info("pedals linked, feeding rudder")
    end
  end
  if feeding then
    if t - lastRecv > DMSPR.STALE_SEC then
      LoSetCommand(DMSPR.RUDDER_CMD, 0)
      feeding = false
      info("no pedal data for " .. DMSPR.STALE_SEC .. " s, rudder released")
      return
    end
    LoSetCommand(DMSPR.RUDDER_CMD, value)
    if peerIp and t - lastAck >= DMSPR.ACK_SEC then
      udp:sendto("DMS-ACK", peerIp, peerPort)
      lastAck = t
    end
  end
end

local function guarded(name, fn)
  local ok, err = pcall(fn)
  if not ok then
    warn(name .. " failed: " .. tostring(err))
  end
end

local prevStart = LuaExportStart
local prevBefore = LuaExportBeforeNextFrame
local prevStop = LuaExportStop

function LuaExportStart()
  if prevStart then
    prevStart()
  end
  guarded("start", openSocket)
end

function LuaExportBeforeNextFrame()
  if prevBefore then
    prevBefore()
  end
  guarded("frame", frame)
end

function LuaExportStop()
  guarded("stop", closeSocket)
  if prevStop then
    prevStop()
  end
end

DMS_PEDAL_RUDDER = DMSPR
