-- K5: does DMS.Rng.seed() give a different seed on every launch of the same .miz?
-- build_probes.py embeds lua/src/dms/rng.lua before this script. Run the miz several times and
-- pass every dcs.log to parse_probes.py. Each sample logs the raw entropy inputs too, so a repeat
-- can be traced to the input that did not change.
local P = DMS_PROBE
local PROBE = "k5"
local birthSeen = false

local function sample(phase)
  local okA, abs = pcall(timer.getAbsTime)
  local okG, kb = pcall(collectgarbage, "count")
  local addr = tostring({})
  local r1, r2, r3 = math.random(), math.random(), math.random()
  local entropy = DMS.Rng.launchEntropy()
  local seed = DMS.Rng.seed()
  local picks = {}
  for i = 1, 5 do
    picks[i] = tostring(DMS.Rng.int(1, 1000000))
  end
  P.log(
    PROBE,
    "phase",
    phase,
    "t",
    string.format("%.6f", P.now()),
    "abs",
    okA and string.format("%.6f", abs) or "error",
    "gc_kb",
    okG and string.format("%.3f", kb) or "error",
    "table_addr",
    addr,
    "math_random",
    string.format("%.6f,%.6f,%.6f", r1, r2, r3),
    "launch_entropy",
    entropy,
    "seed",
    string.format("%.0f", seed),
    "picks",
    table.concat(picks, ",")
  )
end

world.addEventHandler({
  onEvent = function(_, e)
    if birthSeen or not e or e.id ~= world.event.S_EVENT_BIRTH then
      return
    end
    birthSeen = true
    local ok, err = pcall(sample, "first_birth")
    if not ok then
      P.log(PROBE, "error", tostring(err))
    end
  end,
})

P.start(PROBE)
sample("load")
P.after(PROBE, 1, function()
  -- a fresh group guarantees a BIRTH after the handler is registered
  local a = P.groupPoint("Probe Anchor") or { x = 0, y = 0, z = 0 }
  local unit = { name = "K5 spawn-1", type = "Hummer", x = a.x + 60, y = a.z + 60, heading = 0, skill = "Average" }
  local ok, err = pcall(coalition.addGroup, country.id.USA, Group.Category.GROUND, {
    name = "K5 spawn",
    task = "Ground Nothing",
    units = { unit },
  })
  P.log(PROBE, "phase", "spawn", "ok", tostring(ok), "err", tostring(err))
end)
P.after(PROBE, 3, function()
  sample("t3")
  P.log(PROBE, "phase", "birth_check", "birth_seen", tostring(birthSeen))
  P.finish(PROBE)
end)
