-- K8: does the Tacview exporter write an ACMI from the isolated harness write dir?
-- The mission only has to run for a while with something moving; parse_probes.py then looks for
-- Tacview lines in dcs.log and (with --tacview-dir) for a new .acmi file. Enabling Tacview in
-- the write dir is a one-time setup step (README.md).
local P = DMS_PROBE
local PROBE = "k8"

P.start(PROBE)
P.after(PROBE, 60, function()
  local p = P.groupPoint("Probe Anchor")
  P.log(PROBE, "phase", "ran", "anchor_alive", tostring(p ~= nil))
  P.finish(PROBE)
end)
