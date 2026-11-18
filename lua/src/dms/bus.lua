-- DMS bus: pub/sub plus translation of DCS world events into DMS events.
-- The only module allowed to call world.addEventHandler.
--
-- Death handling: DEAD / UNIT_LOST / KILL / CRASH for the same unit within DEDUPE_SEC
-- produce a single "unit.dead". Unit -> group/coalition/category is cached at BIRTH, at
-- registration (DMS.Bus.learnGroup, called by Registry.track) and at load (scan of all
-- groups), because dead units can no longer be queried. "group.dead" fires when the last
-- known unit of a group dies.
--
-- Payload "category" values: "air" | "ground" | "ship" | "static".

DMS = DMS or {}
DMS.Bus = DMS.Bus or {}

local Bus = DMS.Bus
local DEDUPE_SEC = 5

Bus._handlers = Bus._handlers or {} -- name -> list of {token, fn}
Bus._tokens = Bus._tokens or {} -- token -> name
Bus._nextToken = Bus._nextToken or 1
Bus._units = Bus._units or {} -- unitName -> {group, groupId, coalition, category, typeName, pos, player}
Bus._groups = Bus._groups or {} -- groupName -> {alive = {unitName=true}, coalition, deadSent}
Bus._deadAt = Bus._deadAt or {} -- unitName -> time of last unit.dead
Bus._players = Bus._players or {} -- unitName -> payload of player.spawned (+ objId)
-- DCS object id (unit.id_) -> unit name, filled at player BIRTH and cleared on leave/death: in
-- PLAYER_LEAVE_UNIT / death handlers the initiator may already be destroyed, so getName fails.
Bus._objNames = Bus._objNames or {}

local function log()
  return DMS.Log
end

-- ---------------------------------------------------------------------------
-- pub/sub
-- ---------------------------------------------------------------------------

-- fn(payload, name). name "*" receives every event.
function Bus.on(name, fn)
  if type(name) ~= "string" or type(fn) ~= "function" then
    log().error("Bus", "on(): bad arguments (%s, %s)", type(name), type(fn))
    return nil
  end
  local token = Bus._nextToken
  Bus._nextToken = token + 1
  local list = Bus._handlers[name]
  if not list then
    list = {}
    Bus._handlers[name] = list
  end
  list[#list + 1] = { token = token, fn = fn }
  Bus._tokens[token] = name
  return token
end

function Bus.off(token)
  local name = token and Bus._tokens[token]
  if not name then
    return false
  end
  Bus._tokens[token] = nil
  local list = Bus._handlers[name] or {}
  for i = #list, 1, -1 do
    if list[i].token == token then
      table.remove(list, i)
    end
  end
  return true
end

local function deliver(list, name, payload)
  if not list then
    return
  end
  local snapshot = {}
  for i, h in ipairs(list) do
    snapshot[i] = h
  end
  for _, h in ipairs(snapshot) do
    if Bus._tokens[h.token] then
      local ok, err = pcall(h.fn, payload, name)
      if not ok then
        log().error("Bus", "handler for '%s' failed: %s", name, err)
      end
    end
  end
end

function Bus.emit(name, payload)
  local ok, err = pcall(function()
    if log().isDebug() and name ~= "unit.hit" and name ~= "unit.shot" then
      log().debug("Bus", "emit %s", name)
    end
    deliver(Bus._handlers[name], name, payload)
    deliver(Bus._handlers["*"], name, payload)
  end)
  if not ok then
    log().error("Bus", "emit('%s') failed: %s", tostring(name), err)
  end
end

-- ---------------------------------------------------------------------------
-- object helpers (everything pcall'd: initiators can be nil/static/scenery/weapon/dead)
-- ---------------------------------------------------------------------------

local function call(obj, method, ...)
  if obj == nil then
    return nil
  end
  local f = obj[method]
  if type(f) ~= "function" then
    return nil
  end
  local ok, a, b = pcall(f, obj, ...)
  if ok then
    return a, b
  end
  return nil
end
Bus._call = call

local function objCategory(obj)
  if type(obj) ~= "table" then
    return nil
  end
  return call(obj, "getCategory")
end

local function isUnit(obj)
  return objCategory(obj) == Object.Category.UNIT
end
local function isStatic(obj)
  return objCategory(obj) == Object.Category.STATIC
end

local function unitKind(obj)
  local desc = call(obj, "getDesc")
  local c = type(desc) == "table" and desc.category or nil
  if c == nil then
    c = call(obj, "getCategoryEx")
  end
  if c == 0 or c == 1 then
    return "air"
  end
  if c == 3 then
    return "ship"
  end
  return "ground"
end

local function groupKind(cat)
  if cat == 0 or cat == 1 then
    return "air"
  end
  if cat == 3 then
    return "ship"
  end
  return "ground"
end

-- Cache everything we may need after the unit dies.
local function learnUnit(obj)
  local name = call(obj, "getName")
  if not name then
    return nil
  end
  local info = Bus._units[name] or {}
  local grp = call(obj, "getGroup")
  if grp then
    info.group = call(grp, "getName") or info.group
    info.groupId = call(grp, "getID") or info.groupId
  end
  info.coalition = call(obj, "getCoalition") or info.coalition
  info.category = unitKind(obj)
  info.typeName = call(obj, "getTypeName") or info.typeName
  info.pos = call(obj, "getPoint") or info.pos
  Bus._units[name] = info
  if info.group then
    local g = Bus._groups[info.group]
    if not g or g.deadSent then
      g = { alive = {}, coalition = info.coalition }
      Bus._groups[info.group] = g
    end
    g.alive[name] = true
    g.coalition = g.coalition or info.coalition
  end
  return name, info
end

-- Cache a group's current units (call after spawning / when tracking).
function Bus.learnGroup(groupOrName)
  local ok, err = pcall(function()
    local grp = groupOrName
    if type(groupOrName) == "string" then
      grp = Group.getByName(groupOrName)
    end
    if not grp or not call(grp, "isExist") then
      return
    end
    local gname = call(grp, "getName")
    local units = call(grp, "getUnits") or {}
    local fresh = { alive = {}, coalition = call(grp, "getCoalition") }
    Bus._groups[gname] = fresh
    for _, u in ipairs(units) do
      learnUnit(u)
    end
    Bus._groups[gname] = Bus._groups[gname] or fresh
  end)
  if not ok then
    log().error("Bus", "learnGroup failed: %s", err)
  end
end

-- Scan every existing group (done once at load; cheap enough to repeat).
function Bus.rescan()
  for _, side in ipairs({ 0, 1, 2 }) do
    local ok, groups = pcall(coalition.getGroups, side)
    if ok and type(groups) == "table" then
      for _, g in ipairs(groups) do
        Bus.learnGroup(g)
      end
    end
  end
end

function Bus.unitInfo(unitName)
  return Bus._units[unitName]
end

local function nameOf(obj)
  return call(obj, "getName")
end

local function objIdOf(obj)
  if type(obj) ~= "table" then
    return nil
  end
  local ok, id = pcall(function()
    return obj.id_
  end)
  if ok and id ~= nil then
    return id
  end
  return nil
end

-- Name of a possibly-destroyed object: getName, else the BIRTH-time object id map.
local function nameOrCached(obj)
  local n = nameOf(obj)
  if n then
    return n
  end
  local id = objIdOf(obj)
  return id ~= nil and Bus._objNames[id] or nil
end

-- Remove a player entry and emit player.left once.
local function dropPlayer(name, why)
  local p = Bus._players[name]
  if not p then
    return
  end
  Bus._players[name] = nil
  if p.objId ~= nil and Bus._objNames[p.objId] == name then
    Bus._objNames[p.objId] = nil
  end
  log().debug("Bus", "player.left %s from %s (%s)", tostring(p.playerName), name, why)
  Bus.emit("player.left", { unit = name, group = p.group, groupId = p.groupId, playerName = p.playerName })
end

local function weaponName(e)
  if e.weapon then
    local n = call(e.weapon, "getTypeName")
    if n then
      return n
    end
  end
  return e.weapon_name
end

-- ---------------------------------------------------------------------------
-- DCS event translation
-- ---------------------------------------------------------------------------

local function now()
  return timer.getTime()
end

local function handleDeath(victim, killer)
  local cat = objCategory(victim)
  -- dead units may fail getCategory: fall back to cache by name
  local name = nameOrCached(victim)
  if not name then
    return
  end
  if cat ~= nil and cat ~= Object.Category.UNIT and cat ~= Object.Category.STATIC then
    return
  end
  local last = Bus._deadAt[name]
  if last and now() - last < DEDUPE_SEC then
    return
  end
  local info = Bus._units[name]
  if cat == Object.Category.UNIT or (cat == nil and info) then
    if not info or not info.group then
      local _, learned = learnUnit(victim)
      info = learned or info
    end
  end
  Bus._deadAt[name] = now()
  local payload
  if cat == Object.Category.STATIC or (cat == nil and not info) then
    payload = {
      unit = name,
      group = nil,
      coalition = call(victim, "getCoalition"),
      category = "static",
      typeName = call(victim, "getTypeName"),
      pos = call(victim, "getPoint"),
    }
  else
    info = info or {}
    payload = {
      unit = name,
      group = info.group,
      coalition = info.coalition,
      category = info.category or "ground",
      typeName = info.typeName or call(victim, "getTypeName"),
      pos = call(victim, "getPoint") or info.pos,
    }
  end
  if killer then
    payload.killer = nameOf(killer)
  end
  log().debug("Bus", "unit.dead %s (group %s)", name, tostring(payload.group))
  Bus.emit("unit.dead", payload)

  local pl = Bus._players[name]
  local vid = objIdOf(victim)
  if pl and not (vid ~= nil and pl.objId ~= nil and vid ~= pl.objId) then
    dropPlayer(name, "dead") -- a stale death of an older object with this name keeps the new player
  end

  local gname = payload.group
  local g = gname and Bus._groups[gname]
  if g then
    g.alive[name] = nil
    if not g.deadSent and next(g.alive) == nil then
      g.deadSent = true
      log().debug("Bus", "group.dead %s", gname)
      Bus.emit("group.dead", { group = gname, coalition = g.coalition or payload.coalition })
    end
  end
end

local function unitPayload(obj)
  local name = nameOf(obj)
  if not name then
    return nil
  end
  local info = Bus._units[name]
  if not info then
    local _, learned = learnUnit(obj)
    info = learned or {}
  end
  return { unit = name, group = info.group, coalition = info.coalition or call(obj, "getCoalition") }, info
end

local H = {}
local EV = world.event

H[EV.S_EVENT_BIRTH] = function(e)
  if not isUnit(e.initiator) then
    return
  end
  local name, info = learnUnit(e.initiator)
  if not name then
    return
  end
  Bus._deadAt[name] = nil
  local player = call(e.initiator, "getPlayerName")
  if player ~= nil then
    -- Slot / coalition change: DCS fires the new unit's BIRTH before the old unit's
    -- PLAYER_LEAVE_UNIT, so subscribers see player.spawned(new) then player.left(old). Entries are
    -- keyed by unit name and the leave is checked against the object id, so the late leave only
    -- closes the old unit (or is ignored when it belongs to an older object with this name).
    local objId = objIdOf(e.initiator)
    local prev = Bus._players[name]
    if prev and prev.objId ~= nil and Bus._objNames[prev.objId] == name then
      Bus._objNames[prev.objId] = nil
    end
    if objId ~= nil then
      Bus._objNames[objId] = name
    end
    local payload = {
      unit = name,
      group = info.group,
      groupId = info.groupId,
      playerName = player,
      coalition = info.coalition,
      typeName = info.typeName,
    }
    Bus._players[name] = payload
    log().debug("Bus", "player.spawned %s in %s", tostring(player), name)
    Bus.emit("player.spawned", payload)
    payload.objId = objId -- after emit: subscribers see the documented payload only
  end
end

-- The initiator may already be destroyed (getName fails): fall back to the object id map. A leave
-- whose object id differs from the current entry's is a stale leave of an older object with the
-- same unit name (re-slot into the same slot; BIRTH comes first) and is ignored.
H[EV.S_EVENT_PLAYER_LEAVE_UNIT] = function(e)
  local name = nameOrCached(e.initiator)
  local p = name and Bus._players[name]
  if not p then
    local id = objIdOf(e.initiator)
    if id ~= nil then
      Bus._objNames[id] = nil
    end
    return
  end
  local id = objIdOf(e.initiator)
  if id ~= nil and p.objId ~= nil and id ~= p.objId then
    Bus._objNames[id] = nil
    log().debug(
      "Bus",
      "stale PLAYER_LEAVE_UNIT for %s (object %s, current %s): ignored",
      name,
      tostring(id),
      tostring(p.objId)
    )
    return
  end
  dropPlayer(name, "leave")
end

H[EV.S_EVENT_HIT] = function(e)
  if not isUnit(e.target) then
    return
  end
  local tp = unitPayload(e.target)
  if not tp then
    return
  end
  local payload = { target = tp.unit, targetGroup = tp.group, targetCoalition = tp.coalition, weapon = weaponName(e) }
  if isUnit(e.initiator) then
    local ip = unitPayload(e.initiator)
    if ip then
      payload.initiator, payload.initiatorGroup = ip.unit, ip.group
    end
  end
  Bus.emit("unit.hit", payload)
end

H[EV.S_EVENT_SHOT] = function(e)
  if not isUnit(e.initiator) then
    return
  end
  local ip = unitPayload(e.initiator)
  if not ip then
    return
  end
  Bus.emit(
    "unit.shot",
    { initiator = ip.unit, initiatorGroup = ip.group, coalition = ip.coalition, weapon = weaponName(e) }
  )
end

local function deathFromInitiator(e)
  handleDeath(e.initiator, nil)
end
H[EV.S_EVENT_DEAD] = deathFromInitiator
H[EV.S_EVENT_UNIT_LOST] = deathFromInitiator
H[EV.S_EVENT_CRASH] = deathFromInitiator
H[EV.S_EVENT_KILL] = function(e)
  local killer = isUnit(e.initiator) and e.initiator or nil
  handleDeath(e.target, killer)
end

-- EJECTION / PILOT_DEAD: initiator is the aircraft unit (Hoggit; for EJECTION the seat or pilot
-- is e.target). Emitted for every unit (player or AI) with player=<name|nil> from the live player
-- map; the Director uses them to count a player death that arrives after player.left (slot leave
-- while going down). PILOT_DEAD can precede EJECTION (mortally wounded player ejects), and a
-- parachute removal can raise PILOT_DEAD minutes later.
local function pilotEvent(name)
  return function(e)
    if not isUnit(e.initiator) then
      return
    end
    local p, info = unitPayload(e.initiator)
    if not p then
      return
    end
    local pl = Bus._players[p.unit]
    p.groupId = info and info.groupId
    p.player = pl and pl.playerName or nil
    log().debug("Bus", "%s %s (player %s)", name, p.unit, tostring(p.player))
    Bus.emit(name, p)
  end
end
H[EV.S_EVENT_EJECTION] = pilotEvent("unit.ejected")
H[EV.S_EVENT_PILOT_DEAD] = pilotEvent("unit.pilot_dead")

local function landing(name)
  return function(e)
    if not isUnit(e.initiator) then
      return
    end
    local p = unitPayload(e.initiator)
    if not p then
      return
    end
    p.place = e.place and call(e.place, "getName") or nil
    Bus.emit(name, p)
  end
end
H[EV.S_EVENT_TAKEOFF] = landing("unit.takeoff")
H[EV.S_EVENT_LAND] = landing("unit.landed")

local function mark(name)
  return function(e)
    Bus.emit(
      name,
      { idx = e.idx, text = e.text, pos = e.pos, coalition = e.coalition, groupId = e.groupID or e.groupId }
    )
  end
end
H[EV.S_EVENT_MARK_ADDED] = mark("mark.added")
H[EV.S_EVENT_MARK_CHANGE] = mark("mark.changed")
H[EV.S_EVENT_MARK_REMOVED] = mark("mark.removed")

H[EV.S_EVENT_MISSION_END] = function()
  log().debug("Bus", "mission.end")
  Bus.emit("mission.end", {})
end

Bus._dcsHandlers = H

function Bus._onEvent(e)
  if type(e) ~= "table" then
    return
  end
  local h = H[e.id]
  if h then
    h(e)
  end
end

function Bus.install()
  if Bus._handler then
    return
  end
  Bus._handler = {
    onEvent = function(_, e)
      local ok, err = pcall(Bus._onEvent, e)
      if not ok then
        pcall(DMS.Log.error, "Bus", "onEvent(%s) failed: %s", tostring(e and e.id), err)
      end
    end,
  }
  world.addEventHandler(Bus._handler)
  Bus.rescan()
end

function Bus.uninstall()
  if not Bus._handler then
    return
  end
  world.removeEventHandler(Bus._handler)
  Bus._handler = nil
end

Bus.install()
