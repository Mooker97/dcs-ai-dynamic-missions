-- K2: what does world.getMarkPanels() list (marks and markup shapes), and what initiator do
-- script-made marks have? One of each kind is drawn near "Probe Anchor", then every panel is
-- logged. The player-mark half (a human's initiator) needs a client and stays manual.
local P = DMS_PROBE
local PROBE = "k2"
local BASE = 7100001

local function off(p, dx, dz)
  return { x = p.x + dx, y = p.y, z = p.z + dz }
end

local DRAWN = {}

local function draw(p)
  local red, redFill = { 1, 0, 0, 1 }, { 1, 0, 0, 0.2 }
  local calls = {
    {
      kind = "markToAll",
      fn = function(id)
        trigger.action.markToAll(id, "k2 markToAll", off(p, 500, 0), true)
      end,
    },
    {
      kind = "markToCoalition",
      fn = function(id)
        trigger.action.markToCoalition(id, "k2 markToCoalition", off(p, 1000, 0), 2, true)
      end,
    },
    {
      kind = "circleToAll",
      fn = function(id)
        trigger.action.circleToAll(-1, id, off(p, 1500, 0), 300, red, redFill, 1, true, "k2 circle")
      end,
    },
    {
      kind = "textToAll",
      fn = function(id)
        local white, shade = { 1, 1, 1, 1 }, { 0, 0, 0, 0.3 }
        trigger.action.textToAll(-1, id, off(p, 2000, 0), white, shade, 14, true, "k2 textToAll")
      end,
    },
    {
      kind = "lineToAll",
      fn = function(id)
        local a, b = off(p, 2500, 0), off(p, 2500, 500)
        trigger.action.lineToAll(-1, id, a, b, { 0, 0, 1, 1 }, 1, true, "k2 line")
      end,
    },
    {
      kind = "quadToAll",
      fn = function(id)
        local a, b, c, d = off(p, 3000, 0), off(p, 3000, 300), off(p, 3300, 300), off(p, 3300, 0)
        trigger.action.quadToAll(-1, id, a, b, c, d, red, redFill, 1, true, "k2 quad")
      end,
    },
  }
  for i, c in ipairs(calls) do
    local id = BASE + i - 1
    local ok, err = pcall(c.fn, id)
    DRAWN[#DRAWN + 1] = { kind = c.kind, id = id, ok = ok }
    P.log(PROBE, "phase", "draw", "kind", c.kind, "id", id, "ok", tostring(ok), "err", tostring(err))
  end
end

local function listPanels(phase)
  local ok, panels = pcall(world.getMarkPanels)
  if not ok or type(panels) ~= "table" then
    P.log(PROBE, "phase", phase, "error", tostring(panels))
    return {}
  end
  P.log(PROBE, "phase", phase, "count", #panels)
  local seen = {}
  for _, m in ipairs(panels) do
    seen[tonumber(m.idx) or -1] = true
    local pos = type(m.pos) == "table" and m.pos or {}
    P.log(
      PROBE,
      "phase",
      phase,
      "panel_idx",
      tostring(m.idx),
      "initiator",
      tostring(m.initiator),
      "initiator_nil",
      tostring(m.initiator == nil),
      "coalition",
      tostring(m.coalition),
      "groupID",
      tostring(m.groupID),
      "text",
      tostring(m.text),
      "time",
      tostring(m.time),
      "pos_x",
      P.fmt(pos.x),
      "pos_y",
      P.fmt(pos.y),
      "pos_z",
      P.fmt(pos.z)
    )
  end
  return seen
end

P.start(PROBE)
P.after(PROBE, 1, function()
  local p = P.groupPoint("Probe Anchor") or { x = 0, y = 0, z = 0 }
  draw(p)
end)
P.after(PROBE, 2, function()
  local seen = listPanels("panels")
  for _, d in ipairs(DRAWN) do
    P.log(PROBE, "phase", "listed", "kind", d.kind, "id", d.id, "listed", tostring(seen[d.id] == true))
  end
  pcall(trigger.action.removeMark, BASE)
end)
P.after(PROBE, 3, function()
  local seen = listPanels("after_remove")
  P.log(PROBE, "phase", "removed", "kind", "markToAll", "id", BASE, "listed", tostring(seen[BASE] == true))
  P.finish(PROBE)
end)
