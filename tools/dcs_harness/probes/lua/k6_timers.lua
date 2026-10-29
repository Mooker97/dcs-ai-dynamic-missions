-- K6: do callbacks scheduled for exactly timer.getTime() during mission start fire?
-- Schedules at -1, +0, +0.01, +0.05 and +1 s from the mission-start DO SCRIPT (labels "start_*")
-- and again from inside a timer callback at t~3 (labels "cb_*"). Raw timer.scheduleFunction is
-- allowed in probes only, never in lua/src (hard rule 3).
local P = DMS_PROBE
local PROBE = "k6"
local OFFSETS = {
  { "past_1", -1 },
  { "now_0", 0 },
  { "plus_0_01", 0.01 },
  { "plus_0_05", 0.05 },
  { "plus_1", 1 },
}

local function scheduleAll(prefix)
  local t0 = timer.getTime()
  for _, o in ipairs(OFFSETS) do
    local label = prefix .. o[1]
    local ok, err = pcall(timer.scheduleFunction, function(_, time)
      P.log(PROBE, "phase", "fired", "label", label, "at", P.fmt(P.now()), "time_arg", P.fmt(time))
      return nil
    end, nil, t0 + o[2])
    P.log(
      PROBE,
      "phase",
      "scheduled",
      "label",
      label,
      "t0",
      P.fmt(t0),
      "for",
      P.fmt(t0 + o[2]),
      "ok",
      tostring(ok),
      "err",
      tostring(err)
    )
  end
end

P.start(PROBE)
scheduleAll("start_")
P.after(PROBE, 3, function()
  scheduleAll("cb_")
end)
P.after(PROBE, 9, function()
  P.finish(PROBE)
end)
