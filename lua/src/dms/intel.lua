-- DMS.Intel: fog-of-war contact marks (detection -> F10 marks, refresh, stale, removal) and BDA.
-- Spawn-time `hidden` is applied by the spawner; this module only reveals via marks.
-- Depends on: DMS.Log, DMS.Clock, DMS.Bus, DMS.Registry (optional), DMS.Comms (optional).
DMS = DMS or {}
DMS.Intel = DMS.Intel or {}

local Intel = DMS.Intel
local P = "Intel"

Intel.FIRST_MARK_ID = 50000
-- Our id band is [FIRST_MARK_ID, FIRST_MARK_ID + MARK_ID_BAND). Player-made marks get ids around
-- 251,000,000+ (ED forum), so bumpPastExisting never follows a panel at or above PLAYER_MARK_FLOOR.
Intel.MARK_ID_BAND = 10000000
Intel.PLAYER_MARK_FLOOR = 250000000
Intel.COLOR_LIVE = { 1, 0.1, 0.1, 1 }
Intel.FILL_LIVE = { 1, 0.1, 0.1, 0.15 }
Intel.COLOR_STALE = { 0.6, 0.6, 0.6, 0.8 }
Intel.FILL_STALE = { 0.6, 0.6, 0.6, 0.08 }
Intel.MOVE_REDRAW_M = 75

local function cfg()
  return DMS_CONFIG or {}
end
local function icfg()
  local c = cfg().intel or {}
  return {
    fogOfWar = c.fogOfWar ~= false,
    revealRadiusM = c.revealRadiusM or 5000,
    markRefreshSec = c.markRefreshSec or 15,
    staleSec = c.staleSec or 120,
    removeSec = c.removeSec or ((c.staleSec or 120) * 3),
    scanSec = c.scanSec or 5,
    markRadiusM = c.markRadiusM or 600,
    sensors = c.sensors ~= false,
  }
end

local function now()
  return (DMS.Clock and DMS.Clock.now()) or 0
end
local function log(level, fmt, ...)
  if DMS.Log and DMS.Log[level] then
    DMS.Log[level](P, fmt, ...)
  end
end
local function call(fn, ...)
  if DMS.safeCall then
    return DMS.safeCall(fn, ...)
  end
  return pcall(fn, ...)
end

local function playerCoalition()
  local p = cfg().players
  return (p and p.coalition) or 2
end
local function enemyCoalition()
  return playerCoalition() == 1 and 2 or 1
end

-- Mark ids are monotonic for the whole mission (they survive Intel.stop/start) and are never
-- reused, not even after removeMark: DCS mark ids share one namespace with player marks and
-- shapes, and a reused id fires MARK_ADDED but never renders (ED bug, see dcs-scripting-gotchas).
Intel._nextId = Intel._nextId or (Intel.FIRST_MARK_ID - 1)
-- Every mark we put on the F10 map: id -> {kind, text, pos, coalition, radius, owner, t}.
Intel._marks = Intel._marks or { live = {}, added = 0, removed = 0, failed = 0 }

local function freshState()
  return {
    contacts = {}, -- groupName -> contact
    statics = {}, -- handle -> {ids} | {group, created, prevLabel, prevRadius}
    groupHandles = {}, -- groupName -> handle (one stable handle per marked group)
    kills = {}, -- typeName -> n (enemy losses)
    killsByGroup = {}, -- groupName -> {typeName -> n}
    killTotal = 0,
    players = {}, -- unitName -> true (from player.spawned)
    tokens = {},
    clocks = {},
    started = false,
  }
end
Intel._s = Intel._s or freshState()

-- ---------------------------------------------------------------------------
-- geometry / DCS helpers
-- ---------------------------------------------------------------------------

local function newId()
  Intel._nextId = Intel._nextId + 1
  return Intel._nextId
end

-- One line per F10 map change, parsed by DMS.Test / tools/dcs_harness (CONTRACTS "Test mode"):
--   [DMS][Intel] MARK add id=<n> kind=<circle|text> coal=<-1|0|1|2> x=<x> z=<z> r=<m|-> t=<s> owner=<o> text=<text>
--   [DMS][Intel] MARK remove id=<n> kind=<kind> t=<s> why=<reason>
local function oneLine(v)
  return (string.gsub(tostring(v or ""), "[\r\n]+", " | "))
end

local function shapeCoal(coal)
  if coal == nil or coal == "all" then
    return -1
  end
  return coal
end

-- Draw a mark. kind: "circle" (circleToAll) | "text" (markToCoalition, or markToAll for coal -1).
-- Returns true when DCS accepted it (the id is then tracked in Intel._marks.live).
local function addMark(kind, id, coal, pos, text, radius, owner, color, fill, lineType)
  local A = trigger and trigger.action
  if not A then
    return false
  end
  local ok, err
  if kind == "circle" then
    if not A.circleToAll then
      return false
    end
    ok, err = pcall(A.circleToAll, shapeCoal(coal), id, pos, radius, color, fill, lineType or 1, true, "")
  elseif shapeCoal(coal) == -1 then
    if not A.markToAll then
      return false
    end
    ok, err = pcall(A.markToAll, id, tostring(text or ""), pos, true)
  else
    if not A.markToCoalition then
      return false
    end
    ok, err = pcall(A.markToCoalition, id, tostring(text or ""), pos, coal, true)
  end
  local M = Intel._marks
  if not ok then
    M.failed = M.failed + 1
    log("error", "MARK add failed id=%d kind=%s: %s", id, kind, tostring(err))
    return false
  end
  M.live[id] = {
    kind = kind,
    text = text,
    pos = { x = pos.x, y = pos.y, z = pos.z },
    coalition = shapeCoal(coal),
    radius = radius,
    owner = owner,
    t = now(),
  }
  M.added = M.added + 1
  log(
    "debug",
    "MARK add id=%d kind=%s coal=%s x=%.0f z=%.0f r=%s t=%.1f owner=%s text=%s",
    id,
    kind,
    tostring(shapeCoal(coal)),
    pos.x,
    pos.z,
    radius and string.format("%.0f", radius) or "-",
    now(),
    (string.gsub(oneLine(owner), "%s", "_")),
    oneLine(text)
  )
  return true
end

local function removeMark(id, why)
  if not id then
    return
  end
  local M = Intel._marks
  local rec = M.live[id]
  if trigger and trigger.action and trigger.action.removeMark then
    pcall(trigger.action.removeMark, id)
  end
  if rec then
    M.live[id] = nil
    M.removed = M.removed + 1
    log("debug", "MARK remove id=%d kind=%s t=%.1f why=%s", id, rec.kind, now(), oneLine(why))
  end
end

local function aliveUnits(groupName)
  local out = {}
  if not Group then
    return out
  end
  local ok, g = pcall(Group.getByName, groupName)
  if not ok or not g then
    return out
  end
  local okU, units = pcall(g.getUnits, g)
  if not okU or not units then
    return out
  end
  for _, u in ipairs(units) do
    local okE, ex = pcall(u.isExist, u)
    if okE and ex then
      local okL, life = pcall(u.getLife, u)
      if not okL or not life or life >= 1 then
        out[#out + 1] = u
      end
    end
  end
  return out
end

local function centroid(units)
  local sx, sy, sz, n = 0, 0, 0, 0
  for _, u in ipairs(units) do
    local p = u:getPoint()
    sx, sy, sz, n = sx + p.x, sy + (p.y or 0), sz + p.z, n + 1
  end
  if n == 0 then
    return nil
  end
  return { x = sx / n, y = sy / n, z = sz / n }
end

local function dist2(a, b)
  local dx, dz = a.x - b.x, a.z - b.z
  return dx * dx + dz * dz
end

local function los(a, b)
  if not (land and land.isVisible) then
    return true
  end
  local ok, v = pcall(land.isVisible, { x = a.x, y = a.y + 2, z = a.z }, { x = b.x, y = b.y + 2, z = b.z })
  if not ok then
    return true
  end
  return v and true or false
end

local function vec3From(p)
  if p.z then
    return { x = p.x, y = p.y or 0, z = p.z }
  end
  local y = 0
  if land and land.getHeight then
    local ok, h = pcall(land.getHeight, { x = p.x, y = p.y })
    if ok and h then
      y = h
    end
  end
  return { x = p.x, y = y, z = p.y } -- vec2 {x, y} -> vec3 {x, h, z=y}
end

-- Coalition our marks are drawn for: everyone (-1) on a watch mission (spectators), else the players'.
local function markCoalition()
  if DMS.isWatch and DMS.isWatch() then
    return -1
  end
  return playerCoalition()
end

local function playerUnits()
  local out, seen = {}, {}
  local pc = playerCoalition()
  if coalition and coalition.getPlayers then
    local ok, list = pcall(coalition.getPlayers, pc)
    if ok and list then
      for _, u in ipairs(list) do
        local okN, n = pcall(u.getName, u)
        if okN and n and not seen[n] then
          seen[n] = true
          out[#out + 1] = u
        end
      end
    end
  end
  if Unit then
    for name in pairs(Intel._s.players) do
      if not seen[name] then
        local ok, u = pcall(Unit.getByName, name)
        if ok and u then
          local okE, ex = pcall(u.isExist, u)
          if okE and ex then
            seen[name] = true
            out[#out + 1] = u
          end
        end
      end
    end
  end
  -- stand-in players (DMS.Test proxy / watch focus flight) see like players
  if DMS.standInUnits then
    for _, u in ipairs(DMS.standInUnits()) do
      local okN, n = pcall(u.getName, u)
      if okN and n and not seen[n] then
        seen[n] = true
        out[#out + 1] = u
      end
    end
  end
  return out
end

local function isEnemyGroup(groupName)
  if not groupName then
    return false
  end
  if DMS.Registry and DMS.Registry.get then
    local meta = DMS.Registry.get(groupName)
    if meta and meta.coalition then
      return meta.coalition == enemyCoalition()
    end
  end
  if Group then
    local ok, g = pcall(Group.getByName, groupName)
    if ok and g then
      local okC, c = pcall(g.getCoalition, g)
      if okC then
        return c == enemyCoalition()
      end
    end
  end
  return false
end

local function enemyGroups()
  local out, seen = {}, {}
  local ec = enemyCoalition()
  if DMS.Registry and DMS.Registry.list then
    local ok, names = pcall(DMS.Registry.list, function(name, meta)
      meta = meta or DMS.Registry.get(name)
      return meta ~= nil and meta.coalition == ec
    end)
    if ok and names then
      for _, n in ipairs(names) do
        if not seen[n] then
          seen[n] = true
          out[#out + 1] = n
        end
      end
    end
  end
  if coalition and coalition.getGroups then
    local ok, groups = pcall(coalition.getGroups, ec)
    if ok and groups then
      for _, g in ipairs(groups) do
        local okN, n = pcall(g.getName, g)
        if okN and n and not seen[n] then
          seen[n] = true
          out[#out + 1] = n
        end
      end
    end
  end
  return out
end

-- ---------------------------------------------------------------------------
-- contact marks
-- ---------------------------------------------------------------------------

local function contactLabel(c)
  local base = c.label or string.format("Enemy: %s x%d", c.typeName or "unknown", c.count or 0)
  if c.stale then
    return base .. " (last known)"
  end
  return base
end

local function clearMarks(c, why)
  removeMark(c.circleId, why)
  removeMark(c.textId, why)
  c.circleId, c.textId = nil, nil
end

local function drawContact(c, why)
  clearMarks(c, why or "redraw")
  if not c.pos then
    return
  end
  local cfgI = icfg()
  local coal = markCoalition()
  local owner = "contact:" .. tostring(c.group)
  local id = newId()
  if
    addMark(
      "circle",
      id,
      coal,
      c.pos,
      contactLabel(c),
      c.radius or cfgI.markRadiusM,
      owner,
      c.stale and Intel.COLOR_STALE or Intel.COLOR_LIVE,
      c.stale and Intel.FILL_STALE or Intel.FILL_LIVE,
      c.stale and 2 or 1
    )
  then
    c.circleId = id
  end
  id = newId()
  if addMark("text", id, coal, c.pos, contactLabel(c), nil, owner) then
    c.textId = id
  end
  c.drawnAt = now()
  c.drawnPos = { x = c.pos.x, y = c.pos.y, z = c.pos.z }
  c.drawnCount = c.count
  c.drawnStale = c.stale
end

local function snapshot(c, units)
  c.pos = centroid(units)
  c.count = #units
  local okT, tn = pcall(units[1].getTypeName, units[1])
  c.typeName = okT and tn or c.typeName
end

--- Reveal (or refresh contact with) an enemy group. Returns true if this was a new contact.
function Intel.reveal(groupName, reason, opts)
  local s = Intel._s
  if not s.started or not groupName then
    return false
  end
  local units = aliveUnits(groupName)
  local c = s.contacts[groupName]
  if #units == 0 then
    return false
  end
  local t = now()
  if c then
    c.lastSeen = t
    if opts and opts.label then
      c.label = opts.label
    end
    if c.stale then
      c.stale = false
      snapshot(c, units)
      drawContact(c)
      log("debug", "contact '%s' re-acquired (%s)", groupName, tostring(reason))
    end
    return false
  end
  c = {
    group = groupName,
    firstSeen = t,
    lastSeen = t,
    stale = false,
    reason = reason,
    label = opts and opts.label or nil,
  }
  snapshot(c, units)
  s.contacts[groupName] = c
  drawContact(c)
  log("info", "contact: %s (%s x%d) via %s", groupName, tostring(c.typeName), c.count, tostring(reason))
  if DMS.Bus then
    DMS.Bus.emit("intel.revealed", { group = groupName, reason = reason })
  end
  return true
end

function Intel.forget(groupName, why)
  local c = Intel._s.contacts[groupName]
  if not c then
    return false
  end
  clearMarks(c, why)
  Intel._s.contacts[groupName] = nil
  log("debug", "contact '%s' removed (%s)", groupName, tostring(why))
  return true
end

function Intel.contact(groupName)
  return Intel._s.contacts[groupName]
end

function Intel.contacts()
  return Intel._s.contacts
end

local function refreshTick()
  local s = Intel._s
  local cfgI = icfg()
  local t = now()
  for name, c in pairs(s.contacts) do
    local age = t - c.lastSeen
    if age > cfgI.removeSec then
      Intel.forget(name, "contact lost")
    elseif age > cfgI.staleSec then
      if not c.stale then
        c.stale = true
        drawContact(c) -- relabel "(last known)" at the last known position
        log("debug", "contact '%s' is stale (%.0fs)", name, age)
      end
    elseif t - (c.drawnAt or 0) >= cfgI.markRefreshSec - 0.001 then
      local units = aliveUnits(name)
      if #units == 0 then
        Intel.forget(name, "no units")
      else
        snapshot(c, units)
        local moved = (not c.drawnPos) or dist2(c.pos, c.drawnPos) > Intel.MOVE_REDRAW_M * Intel.MOVE_REDRAW_M
        if moved or c.count ~= c.drawnCount or c.stale ~= c.drawnStale then
          drawContact(c)
        end
      end
    end
  end
end

-- ---------------------------------------------------------------------------
-- detection
-- ---------------------------------------------------------------------------

local function scanTick()
  local cfgI = icfg()
  local players = playerUnits()
  if #players == 0 then
    return
  end
  local ppos = {}
  for i, u in ipairs(players) do
    local ok, p = pcall(u.getPoint, u)
    if ok and p then
      ppos[#ppos + 1] = p
    end
    players[i] = u
  end
  local r2 = cfgI.revealRadiusM * cfgI.revealRadiusM
  -- proximity + line of sight
  for _, gname in ipairs(enemyGroups()) do
    local units = aliveUnits(gname)
    local found = false
    for _, u in ipairs(units) do
      local okP, up = pcall(u.getPoint, u)
      if okP and up then
        for _, p in ipairs(ppos) do
          if dist2(p, up) <= r2 and los(p, up) then
            found = true
            break
          end
        end
      end
      if found then
        break
      end
    end
    if found then
      Intel.reveal(gname, "visual")
    end
  end
  -- sensors of player-side groups
  if cfgI.sensors then
    local done = {}
    for _, u in ipairs(players) do
      local okG, g = pcall(u.getGroup, u)
      if okG and g then
        local okN, gn = pcall(g.getName, g)
        if okN and gn and not done[gn] then
          done[gn] = true
          local okC, ctrl = pcall(g.getController, g)
          if okC and ctrl and ctrl.getDetectedTargets then
            local okD, list = pcall(ctrl.getDetectedTargets, ctrl)
            if okD and list then
              for _, d in ipairs(list) do
                local obj = d.object
                if obj and obj.getGroup then
                  local okTG, tg = pcall(obj.getGroup, obj)
                  if okTG and tg then
                    local okTN, tn = pcall(tg.getName, tg)
                    if okTN and isEnemyGroup(tn) then
                      Intel.reveal(tn, "sensor")
                    end
                  end
                end
              end
            end
          end
        end
      end
    end
  end
end

-- ---------------------------------------------------------------------------
-- event handlers
-- ---------------------------------------------------------------------------

local function onHit(e)
  if not e then
    return
  end
  if e.initiatorGroup and isEnemyGroup(e.initiatorGroup) then
    Intel.reveal(e.initiatorGroup, "fired upon")
  end
  if e.targetGroup and isEnemyGroup(e.targetGroup) and e.initiatorGroup and not isEnemyGroup(e.initiatorGroup) then
    Intel.reveal(e.targetGroup, "engaged")
  end
end

local function onShot(e)
  if e and e.initiatorGroup and e.coalition == enemyCoalition() then
    Intel.reveal(e.initiatorGroup, "launch")
  end
end

local function onUnitDead(e)
  if not e or e.coalition ~= enemyCoalition() then
    return
  end
  local s = Intel._s
  local tn = e.typeName or "unknown"
  s.kills[tn] = (s.kills[tn] or 0) + 1
  s.killTotal = s.killTotal + 1
  if e.group then
    local g = s.killsByGroup[e.group] or {}
    g[tn] = (g[tn] or 0) + 1
    s.killsByGroup[e.group] = g
  end
  log("info", "BDA: %s destroyed (%s, total %d)", tn, tostring(e.group), s.killTotal)
end

local function onGroupDead(e)
  if e and e.group then
    Intel.forget(e.group, "destroyed")
  end
end

local function onPlayerSpawned(e)
  if e and e.unit and (e.coalition == nil or e.coalition == playerCoalition()) then
    Intel._s.players[e.unit] = true
  end
end

local function onPlayerLeft(e)
  if e and e.unit then
    Intel._s.players[e.unit] = nil
  end
end

-- ---------------------------------------------------------------------------
-- BDA
-- ---------------------------------------------------------------------------

function Intel.kills()
  return Intel._s.kills, Intel._s.killTotal
end

--- BDA summary. When groupId is given the summary is also shown to that group.
function Intel.report(groupId)
  local s = Intel._s
  local types = {}
  for tn in pairs(s.kills) do
    types[#types + 1] = tn
  end
  table.sort(types)
  local lines = { string.format("BDA: %d enemy units destroyed", s.killTotal) }
  for _, tn in ipairs(types) do
    lines[#lines + 1] = string.format("  %s x%d", tn, s.kills[tn])
  end
  local text = table.concat(lines, "\n")
  if groupId and trigger and trigger.action and trigger.action.outTextForGroup then
    trigger.action.outTextForGroup(groupId, text, 15, false)
  end
  return text
end

function Intel.statusLines()
  local live, stale = 0, 0
  for _, c in pairs(Intel._s.contacts) do
    if c.stale then
      stale = stale + 1
    else
      live = live + 1
    end
  end
  return { string.format("Contacts: %d active, %d last known. Kills: %d", live, stale, Intel._s.killTotal) }
end

-- ---------------------------------------------------------------------------
-- narrative marks
-- ---------------------------------------------------------------------------

local function zoneGeometry(name)
  local z = cfg().zones and cfg().zones[name]
  if z then
    if z.kind == "circle" or (z.radius and z.x) then
      return vec3From({ x = z.x, y = z.y }), z.radius or 1000
    end
    if z.points and #z.points > 0 then
      local sx, sy = 0, 0
      for _, p in ipairs(z.points) do
        sx, sy = sx + p.x, sy + p.y
      end
      local cx, cy = sx / #z.points, sy / #z.points
      local r = 0
      for _, p in ipairs(z.points) do
        local d = math.sqrt((p.x - cx) ^ 2 + (p.y - cy) ^ 2)
        if d > r then
          r = d
        end
      end
      return vec3From({ x = cx, y = cy }), r
    end
  end
  if trigger and trigger.misc and trigger.misc.getZone then
    local ok, mz = pcall(trigger.misc.getZone, name)
    if ok and mz and mz.point then
      return mz.point, mz.radius or 1000
    end
  end
  return nil
end

local function prefixMatch(name, prefix)
  if type(name) ~= "string" then
    return false
  end
  if string.sub(name, 1, #prefix) == prefix then
    return true
  end
  return string.sub(name, 1, 4) == "DMS_" and string.sub(string.sub(name, 5), 1, #prefix) == prefix
end

-- Resolve "group:<name>": exact live group, else the first (sorted) live group whose name, or name
-- without a leading "DMS_", starts with <name> (runtime spawns are named DMS_<poolId>_<n>).
function Intel.resolveGroup(name)
  if #aliveUnits(name) > 0 then
    return name
  end
  local cands, seen = {}, {}
  local function consider(n)
    if n and not seen[n] then
      seen[n] = true
      if prefixMatch(n, name) and #aliveUnits(n) > 0 then
        cands[#cands + 1] = n
      end
    end
  end
  if DMS.Registry and DMS.Registry.list then
    local ok, names = pcall(DMS.Registry.list)
    if ok and type(names) == "table" then
      for _, n in ipairs(names) do
        consider(n)
      end
    end
  end
  if coalition and coalition.getGroups then
    for _, side in ipairs({ 0, 1, 2 }) do
      local ok, groups = pcall(coalition.getGroups, side)
      if ok and type(groups) == "table" then
        for _, g in ipairs(groups) do
          local okN, n = pcall(g.getName, g)
          if okN then
            consider(n)
          end
        end
      end
    end
  end
  table.sort(cands)
  return cands[1]
end

local function unitPoint(name)
  if not Unit then
    return nil
  end
  local ok, p = pcall(function()
    local u = Unit.getByName(name)
    return u and u:isExist() and u:getPoint() or nil
  end)
  return ok and p or nil
end

--- Draw a narrative mark. spec: "group:<name>" | "unit:<name>" | "zone:<name>" | "point:<x>,<y>" |
--- {x=,y=}/{x=,y=,z=} | {type="circle"|"text"|"point", at=<one of the above>, text=, radiusM= (or radius=)}
--- type text/point draws only a label (no circle). Returns a handle (number) or nil.
function Intel.mark(spec)
  local s = Intel._s
  if spec == nil then
    return nil
  end
  local at, text, radius, kind = spec, nil, nil, "circle"
  if type(spec) == "table" and (spec.at or spec.type) then
    at, text, radius, kind = spec.at, spec.text, spec.radiusM or spec.radius, spec.type or "circle"
  end
  if type(at) == "string" then
    local gname = string.match(at, "^group:(.+)$")
    local uname = string.match(at, "^unit:(.+)$")
    local zname = string.match(at, "^zone:(.+)$")
    local px, py = string.match(at, "^point:%s*(-?[%d%.eE+-]+)%s*,%s*(-?[%d%.eE+-]+)%s*$")
    if gname then
      local resolved = Intel.resolveGroup(gname)
      if not resolved then
        log("warn", "mark: group '%s' not found/alive", gname)
        return nil
      end
      local existing = s.contacts[resolved]
      local prevLabel, prevRadius = existing and existing.label, existing and existing.radius
      Intel.reveal(resolved, "intel", { label = text })
      local c = s.contacts[resolved]
      if c then
        local changed = false
        if radius and c.radius ~= radius then
          c.radius, changed = radius, true
        end
        if text and c.label ~= text then
          c.label, changed = text, true
        end
        if changed then
          drawContact(c, "relabel")
        end
        -- stable handle (the contact's own mark ids change on every redraw), one per group
        local h = s.groupHandles[resolved]
        if h and s.statics[h] then
          if not existing then
            s.statics[h].created = true -- contact had been lost; this mark re-created it
          end
          log("debug", "mark %d: group '%s' -> contact '%s' (handle reused)", h, gname, resolved)
          return h
        end
        h = newId()
        s.statics[h] = { group = resolved, created = not existing, prevLabel = prevLabel, prevRadius = prevRadius }
        s.groupHandles[resolved] = h
        log("debug", "mark %d: group '%s' -> contact '%s'", h, gname, resolved)
        return h
      end
      log("warn", "mark: group '%s' could not be revealed", gname)
      return nil
    elseif uname then
      local p = unitPoint(uname)
      if not p then
        log("warn", "mark: unit '%s' not found/alive", uname)
        return nil
      end
      at, text = p, text or uname
    elseif px and tonumber(px) and tonumber(py) then
      at = vec3From({ x = tonumber(px), y = tonumber(py) })
    else
      local pos, r = zoneGeometry(zname or at)
      if not pos then
        log("warn", "mark: unknown target '%s'", at)
        return nil
      end
      text = text or (zname or at)
      at, radius = pos, radius or r
    end
  elseif type(at) == "table" and at.x then
    at = vec3From(at)
  else
    log("warn", "mark: bad spec")
    return nil
  end
  local coal = markCoalition()
  if type(spec) == "table" and (spec.coalition == 1 or spec.coalition == 2 or spec.coalition == -1) then
    coal = spec.coalition
  end
  local ids = {}
  local label = tostring(text or "Objective")
  local owner = "mark:" .. label
  local withCircle = kind ~= "point" and kind ~= "text"
  if withCircle then
    local id = newId()
    if addMark("circle", id, coal, at, label, radius or 1000, owner, { 1, 0.8, 0, 1 }, { 1, 0.8, 0, 0.1 }, 1) then
      ids[#ids + 1] = id
    end
  end
  local handle = newId()
  if addMark("text", handle, coal, at, label, nil, owner) then
    ids[#ids + 1] = handle
  end
  if #ids == 0 then
    log("warn", "mark '%s' (%s) not drawn", label, tostring(kind))
    return nil
  end
  s.statics[handle] = { ids = ids }
  log("debug", "mark %d drawn '%s' (%s)", handle, label, tostring(kind))
  return handle
end

function Intel.removeMarkHandle(handle)
  local rec = Intel._s.statics[handle]
  if not rec then
    return false
  end
  local s = Intel._s
  s.statics[handle] = nil
  if rec.group then
    if s.groupHandles[rec.group] == handle then
      s.groupHandles[rec.group] = nil
    end
    local c = s.contacts[rec.group]
    if rec.created then
      -- the mark revealed this contact: removing the mark forgets it
      Intel.forget(rec.group, "mark handle removed")
    elseif c and (c.label ~= rec.prevLabel or c.radius ~= rec.prevRadius) then
      -- the contact was detected independently: keep it, undo the mark's label/radius
      c.label, c.radius = rec.prevLabel, rec.prevRadius
      drawContact(c, "relabel")
    end
    log("debug", "mark handle %d removed (group '%s', forgot=%s)", handle, rec.group, tostring(rec.created == true))
    return true
  end
  for _, id in ipairs(rec.ids or {}) do
    removeMark(id, "mark handle removed")
  end
  return true
end

--- Marks DMS put on the F10 map and has not removed: id -> {kind, text, pos, coalition, radius, owner, t}.
function Intel.liveMarks()
  return Intel._marks.live
end

--- -> {added=, removed=, failed=, live=<count>} since the mission started.
function Intel.markStats()
  local M = Intel._marks
  local n = 0
  for _ in pairs(M.live) do
    n = n + 1
  end
  return { added = M.added, removed = M.removed, failed = M.failed, live = n }
end

-- Remove every mark this module drew (stop / restart).
local function removeAllMarks(why)
  local ids = {}
  for id in pairs(Intel._marks.live) do
    ids[#ids + 1] = id
  end
  table.sort(ids)
  for _, id in ipairs(ids) do
    removeMark(id, why)
  end
end

-- Start our ids above any mark already on the map that could collide with ours: a panel inside our
-- own band (an earlier run of ours, mission-editor drawings), or a script-made panel (initiator nil)
-- below the player range. Never follow a player mark (ids ~251,000,000+): our next id would land on
-- the player's next mark. Only ever raises _nextId, so ids stay monotonic.
local function bumpPastExisting()
  if not (world and world.getMarkPanels) then
    return
  end
  local ok, panels = pcall(world.getMarkPanels)
  if not ok or type(panels) ~= "table" then
    return
  end
  local first = Intel.FIRST_MARK_ID
  local bandEnd = first + Intel.MARK_ID_BAND
  local skipped = 0
  for _, p in ipairs(panels) do
    local idx = type(p) == "table" and tonumber(p.idx) or nil
    if idx and idx > Intel._nextId and not Intel._marks.live[idx] then
      local inBand = idx >= first and idx < bandEnd
      local scriptMade = p.initiator == nil and idx < Intel.PLAYER_MARK_FLOOR
      if inBand or scriptMade then
        Intel._nextId = idx
      else
        skipped = skipped + 1
      end
    end
  end
  if skipped > 0 then
    log(
      "debug",
      "mark ids: ignored %d panel(s) outside our band (player marks); next id %d",
      skipped,
      Intel._nextId + 1
    )
  end
end

-- ---------------------------------------------------------------------------
-- lifecycle
-- ---------------------------------------------------------------------------

function Intel.start()
  -- Only a restart wipes our marks: marks a beat drew before the first start (no contacts yet)
  -- must survive, together with their handles.
  local prev = Intel._s
  local carried
  if prev and prev.started then
    Intel.stop()
  elseif prev then
    carried = prev.statics
  end
  Intel._s = freshState()
  if carried then
    for h, rec in pairs(carried) do
      if not rec.group then
        Intel._s.statics[h] = rec
      end
    end
  end
  bumpPastExisting()
  local s = Intel._s
  s.started = true
  local c = icfg()
  if DMS.Bus then
    local on = function(n, f)
      s.tokens[#s.tokens + 1] = DMS.Bus.on(n, f)
    end
    on("unit.hit", onHit)
    on("unit.shot", onShot)
    on("unit.dead", onUnitDead)
    on("group.dead", onGroupDead)
    on("player.spawned", onPlayerSpawned)
    on("player.left", onPlayerLeft)
  end
  if DMS.Clock then
    if c.fogOfWar then
      s.clocks[#s.clocks + 1] = DMS.Clock.every(c.scanSec, function()
        local ok, err = call(scanTick)
        if not ok then
          log("error", "scan: %s", tostring(err))
        end
      end, { firstDelay = c.scanSec })
    end
    s.clocks[#s.clocks + 1] = DMS.Clock.every(math.min(c.markRefreshSec, c.scanSec), function()
      local ok, err = call(refreshTick)
      if not ok then
        log("error", "refresh: %s", tostring(err))
      end
    end, { firstDelay = c.markRefreshSec })
  end
  if DMS.Comms and DMS.Comms.addMenuCommand then
    DMS.Comms.addMenuCommand("", "BDA report", function(ctx)
      Intel.report(ctx.groupId)
    end)
  end
  log(
    "info",
    "started (fogOfWar=%s reveal=%dm refresh=%ds stale=%ds)",
    tostring(c.fogOfWar),
    c.revealRadiusM,
    c.markRefreshSec,
    c.staleSec
  )
end

function Intel.stop()
  local s = Intel._s
  if not s then
    return
  end
  if DMS.Bus then
    for _, t in ipairs(s.tokens) do
      DMS.Bus.off(t)
    end
  end
  if DMS.Clock then
    for _, id in ipairs(s.clocks) do
      DMS.Clock.cancel(id)
    end
  end
  removeAllMarks("intel stopped")
  for _, c in pairs(s.contacts or {}) do
    c.circleId, c.textId = nil, nil
  end
  s.contacts, s.statics, s.groupHandles = {}, {}, {}
  s.tokens, s.clocks, s.started = {}, {}, false
end
