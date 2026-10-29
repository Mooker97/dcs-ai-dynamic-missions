-- K3: does trigger.action.radioTransmission accept the extra subtitle arguments?
-- pcall the call with 7, 8 and 9 arguments, plus a bad-argument control that shows whether the
-- function validates its arguments at all. Every world event seen in the next 6 s is logged.
-- The file is deliberately not in the miz: a missing file raises nothing (gotchas, Menus and
-- sound), so this only measures the call signature. Whether a subtitle shows needs a cockpit.
local P = DMS_PROBE
local PROBE = "k3"
local FILE = "l10n/DEFAULT/dms_probe_k3_missing.ogg"
local FREQ = 251000000
local events = {}

world.addEventHandler({
  onEvent = function(_, e)
    if e and e.id then
      events[#events + 1] = tostring(e.id)
    end
  end,
})

local function tx(label, ...)
  local ok, err = pcall(trigger.action.radioTransmission, ...)
  local n = select("#", ...)
  P.log(PROBE, "phase", "call", "variant", label, "nargs", n, "ok", tostring(ok), "err", tostring(err))
  local okS, errS = pcall(trigger.action.stopRadioTransmission, "dms_probe_k3_" .. label)
  P.log(PROBE, "phase", "stop", "variant", label, "ok", tostring(okS), "err", tostring(errS))
end

P.start(PROBE)
P.after(PROBE, 1, function()
  local a = P.groupPoint("Probe Anchor") or { x = 0, y = 0, z = 0 }
  local pt = { x = a.x, y = a.y + 150, z = a.z }
  tx("arity7", FILE, pt, 0, false, FREQ, 10000, "dms_probe_k3_arity7")
  tx("arity8", FILE, pt, 0, false, FREQ, 10000, "dms_probe_k3_arity8", "K3 subtitle eight")
  tx("arity9", FILE, pt, 0, false, FREQ, 10000, "dms_probe_k3_arity9", "K3 subtitle nine", 5)
  tx("arity9_swapped", FILE, pt, 0, false, FREQ, 10000, "dms_probe_k3_arity9_swapped", 5, "K3 swapped")
  tx("bad_arg_control", FILE, "not-a-point", 0, false, "not-a-frequency", 10000, "dms_probe_k3_bad_arg_control")
end)
P.after(PROBE, 7, function()
  P.log(PROBE, "phase", "events", "count", #events, "ids", table.concat(events, ","))
  P.finish(PROBE)
end)
