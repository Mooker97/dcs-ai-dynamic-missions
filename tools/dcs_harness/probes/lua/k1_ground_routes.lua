-- K1: does a ground route need >= 2 points with the current position first?
-- Five identical groups (built by build_probes.py) each get one route variant at t=2.
-- Distance moved and controller:hasTask() are logged at +60 s and +120 s.
local P = DMS_PROBE
local PROBE = "k1"
local SPEED = 8 -- m/s
local DIST = 2000 -- m, route legs run north (+x)
local VARIANTS = {
  { group = "K1 one_point", variant = "one_point" },
  { group = "K1 two_no_current", variant = "two_points_no_current" },
  { group = "K1 two_current_first", variant = "two_points_current_first" },
  { group = "K1 two_current_first_road", variant = "two_points_current_first_on_road" },
  { group = "K1 control", variant = "control_no_task" },
}
local start = {}

local function wp(x, z, action)
  return {
    x = x,
    y = z,
    type = "Turning Point",
    action = action,
    speed = SPEED,
    speed_locked = true,
    ETA = 0,
    ETA_locked = false,
    formation_template = "",
  }
end

local function routeFor(variant, p)
  local a = "Off Road"
  if variant == "two_points_current_first_on_road" then
    a = "On Road"
  end
  if variant == "one_point" then
    return { wp(p.x + DIST, p.z, a) }
  elseif variant == "two_points_no_current" then
    return { wp(p.x + DIST / 2, p.z, a), wp(p.x + DIST, p.z, a) }
  elseif variant == "control_no_task" then
    return nil
  end
  return { wp(p.x, p.z, a), wp(p.x + DIST, p.z, a) }
end

local function setRoutes()
  for _, v in ipairs(VARIANTS) do
    local p = P.groupPoint(v.group)
    if not p then
      P.log(PROBE, "phase", "route_set", "variant", v.variant, "error", "group_missing")
    else
      start[v.variant] = p
      local pts = routeFor(v.variant, p)
      local ok, err = true, nil
      if pts then
        ok, err = pcall(function()
          local ctrl = Group.getByName(v.group):getController()
          ctrl:setTask({ id = "Mission", params = { route = { points = pts } } })
        end)
      end
      P.log(
        PROBE,
        "phase",
        "route_set",
        "variant",
        v.variant,
        "points",
        pts and #pts or 0,
        "ok",
        tostring(ok),
        "err",
        tostring(err),
        "t",
        P.fmt(P.now())
      )
    end
  end
end

local function report(phase)
  for _, v in ipairs(VARIANTS) do
    local p = P.groupPoint(v.group)
    local s = start[v.variant]
    local moved = -1
    if p and s then
      moved = math.sqrt((p.x - s.x) ^ 2 + (p.z - s.z) ^ 2)
    end
    local okT, has = pcall(function()
      return Group.getByName(v.group):getController():hasTask()
    end)
    P.log(
      PROBE,
      "phase",
      phase,
      "variant",
      v.variant,
      "moved_m",
      string.format("%.1f", moved),
      "has_task",
      okT and tostring(has) or "error",
      "t",
      P.fmt(P.now())
    )
  end
end

P.start(PROBE)
P.after(PROBE, 2, setRoutes)
P.after(PROBE, 62, function()
  report("mid")
end)
P.after(PROBE, 122, function()
  report("final")
  P.finish(PROBE)
end)
