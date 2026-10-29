-- K9: what is the longest env.info line that arrives intact in dcs.log?
-- Logs one line per length N: the message is exactly N bytes, a fixed head, a digit pattern and
-- a "|END" tail, so parse_probes.py can rebuild the expected text and compare it byte for byte.
local P = DMS_PROBE
local PROBE = "k9"
local LENGTHS = {
  100,
  255,
  256,
  511,
  512,
  1000,
  1023,
  1024,
  1500,
  2000,
  2047,
  2048,
  3000,
  4000,
  4095,
  4096,
  4097,
  6000,
  8191,
  8192,
  12000,
  16383,
  16384,
  24000,
  32767,
  32768,
  65535,
  65536,
}

function DMS_PROBE.k9Message(n)
  local head = "[DMS.PROBE] probe=k9 len=" .. n .. " payload="
  local fill = n - string.len(head) - 4
  local body = string.sub(string.rep("0123456789", math.floor(fill / 10) + 1), 1, fill)
  return head .. body .. "|END"
end

P.start(PROBE)
P.after(PROBE, 1, function()
  local list = {}
  for i, n in ipairs(LENGTHS) do
    list[i] = tostring(n)
  end
  P.log(PROBE, "phase", "plan", "lengths", table.concat(list, ","))
  for _, n in ipairs(LENGTHS) do
    env.info(DMS_PROBE.k9Message(n))
  end
  P.log(PROBE, "phase", "sent", "count", #LENGTHS)
  P.finish(PROBE)
end)
