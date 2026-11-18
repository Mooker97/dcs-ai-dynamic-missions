-- K7: does net.dostring_in('mission', ...) from a GameGUI hook still work?
-- The harness hook already runs code in the mission env through net.dostring_in on mission load
-- (errorbox_disable, and --inject). Run this probe with the --inject snippet from README.md: it
-- sets DMS_PROBE_K7_INJECTED and logs "phase=inject". This script checks the global from the
-- mission side.
local P = DMS_PROBE
local PROBE = "k7"

local function injected()
  return rawget(_G, "DMS_PROBE_K7_INJECTED") ~= nil
end

P.start(PROBE)
P.log(PROBE, "phase", "script_loaded", "injected", tostring(injected()))
P.after(PROBE, 3, function()
  P.log(PROBE, "phase", "check", "injected", tostring(injected()))
  P.finish(PROBE)
end)
