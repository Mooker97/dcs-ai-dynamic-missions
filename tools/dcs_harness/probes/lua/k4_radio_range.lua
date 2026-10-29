-- K4: radioTransmission range model and per-receiver LOS. No headless audio receiver exists, so
-- this is a proxy only: it starts transmitters 5/20/50 km south of "Probe Anchor" at 1000 W and
-- 10000 W (one frequency each), logs whether each call succeeds and the terrain line of sight
-- from each transmitter to a point 1500 m above the anchor. The audible answer needs the
-- cockpit A/B in tools/dcs_harness/probes/README.md.
local P = DMS_PROBE
local PROBE = "k4"
local FILE = "l10n/DEFAULT/dms_probe_k4_missing.ogg"
local CASES = {
  { km = 5, watts = 1000, mhz = 251.0 },
  { km = 5, watts = 10000, mhz = 251.5 },
  { km = 20, watts = 1000, mhz = 252.0 },
  { km = 20, watts = 10000, mhz = 252.5 },
  { km = 50, watts = 1000, mhz = 253.0 },
  { km = 50, watts = 10000, mhz = 253.5 },
}

local function txName(c)
  return string.format("dms_probe_k4_%dkm_%dw", c.km, c.watts)
end

P.start(PROBE)
P.after(PROBE, 1, function()
  local a = P.groupPoint("Probe Anchor") or { x = 0, y = 0, z = 0 }
  local rx = { x = a.x, y = a.y + 1500, z = a.z }
  for _, c in ipairs(CASES) do
    local sx = a.x - c.km * 1000
    local okH, h = pcall(land.getHeight, { x = sx, y = a.z })
    local ground = (okH and type(h) == "number") and h or 0
    local src = { x = sx, y = ground + 50, z = a.z }
    local hz = c.mhz * 1000000
    local ok, err = pcall(trigger.action.radioTransmission, FILE, src, 0, true, hz, c.watts, txName(c))
    local okL, los = pcall(land.isVisible, src, rx)
    P.log(
      PROBE,
      "phase",
      "tx",
      "km",
      c.km,
      "watts",
      c.watts,
      "mhz",
      string.format("%.3f", c.mhz),
      "ok",
      tostring(ok),
      "err",
      tostring(err),
      "los_to_rx",
      okL and tostring(los) or "error"
    )
  end
end)
P.after(PROBE, 10, function()
  for _, c in ipairs(CASES) do
    pcall(trigger.action.stopRadioTransmission, txName(c))
  end
  P.finish(PROBE)
end)
