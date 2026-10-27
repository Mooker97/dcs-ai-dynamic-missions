-- DMS.Narrative: storylet / beat engine over DMS_CONFIG.beats.
-- A beat is *triggered* by its `when` (edge), rolls `chance` once per trigger, then waits in a short
-- pending queue until `requires`, `once`, `cooldownSec` and the global min gap allow it to fire.
-- Among ready beats the highest priority fires first (ties random).
-- Depends on: DMS.Log, DMS.Clock, DMS.Bus, DMS.Rng; optional DMS.Comms, DMS.Intel, DMS.Encounters.
DMS = DMS or {}
DMS.Narrative = DMS.Narrative or {}

local N = DMS.Narrative
local P = "Narrative"

N.TICK_SEC = 1
N.MIN_GAP_SEC = 8          -- override: DMS_CONFIG.narrative.minGapSec
N.PENDING_TTL_SEC = 45     -- override: DMS_CONFIG.narrative.pendingTtlSec
N.ZONE_POLL_SEC = 3        -- override: DMS_CONFIG.narrative.zonePollSec

local function cfg() return DMS_CONFIG or {} end
local function ncfg() return cfg().narrative or {} end
local function now() return (DMS.Clock and DMS.Clock.now()) or 0 end
local function log(level, fmt, ...)
  if DMS.Log and DMS.Log[level] then DMS.Log[level](P, fmt, ...) end
end
local function call(fn, ...)
  if DMS.safeCall then return DMS.safeCall(fn, ...) end
  return pcall(fn, ...)
end
local function playerCoalition()
  local p = cfg().players
  return (p and p.coalition) or 2
end

local function copy(t)
  if type(t) ~= "table" then return t end
  local o = {}
  for k, v in pairs(t) do o[k] = copy(v) end
  return o
end

local function freshState()
  return {
    beats = {}, byId = {}, order = {},
    flags = {}, qualities = {}, outcome = {},
    fired = {},          -- id -> {count, lastAt}
    firedList = {},
    pending = {},        -- id -> {at, expires, source}
    stateWas = {},       -- id -> bool (edge detection for state triggers)
    directorStates = {}, -- flight -> state
    zoneInside = {},     -- zone|unit -> bool
    players = {},
    lastFireAt = nil, startedAt = 0,
    finished = false, result = nil,
    tokens = {}, clocks = {}, started = false, pumping = false,
  }
end
N._s = N._s or freshState()

-- ---------------------------------------------------------------------------
-- flags & qualities
-- ---------------------------------------------------------------------------

local function userFlag(name)
  if trigger and trigger.misc and trigger.misc.getUserFlag then
    local ok, v = pcall(trigger.misc.getUserFlag, name)
    if ok and v ~= nil then return tonumber(v) or (v and 1 or 0) end
  end
  return 0
end

function N.getFlag(name)
  local v = N._s.flags[name]
  if v ~= nil then
    if v == true then return 1 end
    if v == false then return 0 end
    return tonumber(v) or 0
  end
  return userFlag(name)
end

function N.isFlagSet(name) return N.getFlag(name) ~= 0 end

function N.setFlag(name, value)
  if value == nil or value == true then value = 1 end
  if value == false then value = 0 end
  N._s.flags[name] = value
  if trigger and trigger.action and trigger.action.setUserFlag then
    pcall(trigger.action.setUserFlag, name, value)
  end
  log("debug", "flag %s = %s", tostring(name), tostring(value))
end

function N.getQuality(name) return N._s.qualities[name] or 0 end
function N.qualities() return N._s.qualities end

function N.addQuality(name, delta)
  local q = N._s.qualities
  q[name] = (q[name] or 0) + (tonumber(delta) or 0)
  log("debug", "quality %s %+g -> %g", name, tonumber(delta) or 0, q[name])
end

local function compare(actual, spec)
  if type(spec) == "number" then return actual >= spec end
  if type(spec) == "boolean" then return (actual ~= 0) == spec end
  if type(spec) == "string" then
    local op, num = string.match(spec, "^%s*([<>=!~]=?)%s*(-?[%d%.]+)%s*$")
    num = tonumber(num)
    if not op or not num then return false end
    if op == ">=" then return actual >= num
    elseif op == ">" then return actual > num
    elseif op == "<=" then return actual <= num
    elseif op == "<" then return actual < num
    elseif op == "=" or op == "==" then return actual == num
    elseif op == "!=" or op == "~=" then return actual ~= num end
    return false
  end
  if type(spec) == "table" then
    if spec.op then return compare(actual, spec.op .. tostring(spec.value)) end
    if spec.min and actual < spec.min then return false end
    if spec.max and actual > spec.max then return false end
    if spec.eq and actual ~= spec.eq then return false end
    return true
  end
  return false
end
N._compare = compare

-- ---------------------------------------------------------------------------
-- requirements
-- ---------------------------------------------------------------------------

local function requiresOk(beat)
  local r = beat.requires
  if type(r) ~= "table" then return true end
  if type(r.flags) == "table" then
    for k, v in pairs(r.flags) do
      if type(k) == "number" then
        if not N.isFlagSet(v) then return false end
      elseif v == true then
        if not N.isFlagSet(k) then return false end
      elseif v == false then
        if N.isFlagSet(k) then return false end
      elseif not compare(N.getFlag(k), v) then
        return false
      end
    end
  end
  local notSet = r.notFlags or r.flagsNotSet
  if type(notSet) == "string" then notSet = { notSet } end
  if type(notSet) == "table" then
    for _, f in ipairs(notSet) do if N.isFlagSet(f) then return false end end
  end
  local set = r.flagsSet
  if type(set) == "string" then set = { set } end
  if type(set) == "table" then
    for _, f in ipairs(set) do if not N.isFlagSet(f) then return false end end
  end
  if type(r.qualities) == "table" then
    for q, spec in pairs(r.qualities) do
      if not compare(N.getQuality(q), spec) then return false end
    end
  end
  if type(r.beatsFired) == "table" then
    for _, id in ipairs(r.beatsFired) do if not N._s.fired[id] then return false end end
  end
  if type(r.beatsNotFired) == "table" then
    for _, id in ipairs(r.beatsNotFired) do if N._s.fired[id] then return false end end
  end
  return true
end

local function chanceOf(beat)
  local c = beat.chance
  if c == nil and type(beat.requires) == "table" then c = beat.requires.chance end
  return c
end

-- ---------------------------------------------------------------------------
-- outcome
-- ---------------------------------------------------------------------------

local function writeOutcome(event)
  local s = N._s
  local fired = {}
  for _, id in ipairs(s.firedList) do fired[#fired + 1] = id end
  local rec = {
    missionId = cfg().missionId, event = event, t = math.floor(now() * 10 + 0.5) / 10,
    result = s.result, outcome = copy(s.outcome), qualities = copy(s.qualities), beats = fired,
  }
  if DMS.Log and DMS.Log.outcome then DMS.Log.outcome(rec) end
  return rec
end

function N.outcome() return N._s.outcome end

--- Record outcome fields (merged) and log a [DMS.OUTCOME] line when anything changed.
function N.setOutcome(tbl)
  if type(tbl) ~= "table" then return end
  local changed = false
  for k, v in pairs(tbl) do
    if N._s.outcome[k] ~= v then N._s.outcome[k] = copy(v) changed = true end
  end
  if changed then writeOutcome("update") end
end

--- End the mission narrative: writes a final [DMS.OUTCOME] line once.
function N.finish(result)
  local s = N._s
  if s.finished then return false end
  s.finished = true
  s.result = result or s.result or "ended"
  log("info", "mission finished: %s", tostring(s.result))
  writeOutcome("end")
  if DMS.Bus then DMS.Bus.emit("mission.result", { result = s.result }) end
  return true
end

-- ---------------------------------------------------------------------------
-- effects
-- ---------------------------------------------------------------------------

local function asList(v)
  if v == nil then return {} end
  if type(v) == "table" then return v end
  return { v }
end

local function applyEffects(beat)
  local e = beat.effects or {}
  -- flags
  if e.setFlag ~= nil then
    if type(e.setFlag) == "table" then
      for k, v in pairs(e.setFlag) do
        if type(k) == "number" then N.setFlag(v, 1) else N.setFlag(k, v) end
      end
    else
      N.setFlag(e.setFlag, e.flagValue or 1)
    end
  end
  for _, f in ipairs(asList(e.clearFlag)) do N.setFlag(f, 0) end
  -- qualities
  if type(e.qualities) == "table" then
    for q, d in pairs(e.qualities) do N.addQuality(q, d) end
  end
  -- speech
  local sp = e.speak
  local speaker = (sp and sp.speaker) or beat.speaker
  local lines = (sp and sp.lines) or beat.lines
  local text = (sp and sp.text) or beat.text
  if speaker or lines or text then
    if DMS.Comms and DMS.Comms.say then
      DMS.Comms.say(speaker, lines, text, { coalition = playerCoalition(), priority = beat.priority or 0,
        frequency = sp and sp.frequency or beat.frequency })
    elseif text and trigger and trigger.action and trigger.action.outTextForCoalition then
      trigger.action.outTextForCoalition(playerCoalition(), (speaker and (speaker .. ": ") or "") .. text, 10)
    end
  end
  -- marks
  local mark = e.mark or beat.mark
  if mark ~= nil then
    if DMS.Intel and DMS.Intel.mark then DMS.Intel.mark(mark)
    else log("warn", "beat '%s' wants a mark but DMS.Intel is missing", beat.id) end
  end
  -- encounters
  for _, enc in ipairs(asList(e.startEncounter)) do
    if DMS.Encounters and DMS.Encounters.trigger then
      local ok, err = call(DMS.Encounters.trigger, enc, { beat = beat.id })
      if not ok then log("error", "startEncounter %s: %s", tostring(enc), tostring(err)) end
    else
      log("warn", "beat '%s': encounter '%s' requested but DMS.Encounters missing", beat.id, tostring(enc))
    end
  end
  -- outcome / end
  if type(e.outcome) == "table" then N.setOutcome(e.outcome) end
  local fin = e.finish or e["end"] or e.result
  if fin then N.finish(fin) end
end

-- ---------------------------------------------------------------------------
-- triggering & selection
-- ---------------------------------------------------------------------------

local function gapSec() return ncfg().minGapSec or N.MIN_GAP_SEC end
local function ttlSec() return ncfg().pendingTtlSec or N.PENDING_TTL_SEC end

local function blocked(beat, t)
  local f = N._s.fired[beat.id]
  if f and beat.once ~= false and (beat.once == true) then return "once" end
  if f and beat.cooldownSec and beat.cooldownSec > 0 and t - f.lastAt < beat.cooldownSec then
    return "cooldown"
  end
  return nil
end

local function fire(beat, t)
  local s = N._s
  local f = s.fired[beat.id] or { count = 0 }
  f.count, f.lastAt = f.count + 1, t
  s.fired[beat.id] = f
  s.firedList[#s.firedList + 1] = beat.id
  s.lastFireAt = t
  log("info", "beat '%s' fired (priority %s, #%d)", beat.id, tostring(beat.priority or 0), f.count)
  local ok, err = call(applyEffects, beat)
  if not ok then log("error", "effects of '%s' failed: %s", beat.id, tostring(err)) end
  if DMS.Bus then DMS.Bus.emit("beat.fired", { id = beat.id }) end
end

function N.pump()
  local s = N._s
  if not s.started or s.pumping then return end
  s.pumping = true
  local ok, err = call(function()
    local t = now()
    -- expire / drop
    for id, p in pairs(s.pending) do
      local beat = s.byId[id]
      local why = (not beat) and "unknown" or (t > p.expires and "expired") or (blocked(beat, t) == "once" and "once")
      if why then
        s.pending[id] = nil
        log("debug", "pending beat '%s' dropped (%s)", id, why)
      end
    end
    for _ = 1, #s.order do   -- with minGapSec = 0 several ready beats may fire in one pump
      if s.lastFireAt and t - s.lastFireAt < gapSec() then return end
      local best, bestP, ties = nil, nil, 0
      for _, id in ipairs(s.order) do
        local p = s.pending[id]
        if p and t >= p.at then
          local beat = s.byId[id]
          if not blocked(beat, t) and requiresOk(beat) then
            local pr = beat.priority or 0
            if best == nil or pr > bestP then
              best, bestP, ties = beat, pr, 1
            elseif pr == bestP then
              ties = ties + 1
              if DMS.Rng.random() < 1 / ties then best = beat end   -- reservoir pick among ties
            end
          end
        end
      end
      if not best then return end
      s.pending[best.id] = nil
      fire(best, t)
    end
  end)
  s.pumping = false
  if not ok then log("error", "pump: %s", tostring(err)) end
end

--- Trigger a beat (as if its `when` had occurred). Rolls chance once. Returns true if queued.
function N.trigger(id, source, noPump)
  local s = N._s
  local beat = s.byId[id]
  if not beat or s.finished then return false end
  local t = now()
  if blocked(beat, t) == "once" then return false end
  if s.pending[id] then return true end
  local c = chanceOf(beat)
  if c ~= nil and c < 100 then
    local roll = DMS.Rng.int(1, 100)
    if roll > c then
      log("debug", "beat '%s' skipped (rolled %d > %d)", id, roll, c)
      return false
    end
    log("debug", "beat '%s' passed chance (rolled %d <= %d)", id, roll, c)
  end
  local delay = (beat.when and beat.when.delaySec) or 0
  s.pending[id] = { at = t + delay, expires = t + delay + ttlSec(), source = source }
  log("debug", "beat '%s' triggered by %s", id, tostring(source))
  if delay > 0 and DMS.Clock then DMS.Clock.after(delay, N.pump) elseif not noPump then N.pump() end
  return true
end

local function matchesFilters(w, payload)
  for k, v in pairs(w) do
    if k ~= "event" and k ~= "delaySec" then
      if k == "groupPrefix" or k == "group_prefix" then
        local g = payload.group or payload.targetGroup or payload.initiatorGroup
        if type(g) ~= "string" or string.sub(g, 1, #v) ~= v then return false end
      elseif k == "unitPrefix" or k == "unit_prefix" then
        local u = payload.unit or payload.target or payload.initiator
        if type(u) ~= "string" or string.sub(u, 1, #v) ~= v then return false end
      elseif payload[k] ~= v then
        return false
      end
    end
  end
  return true
end

-- Normalised trigger kind for a `when` table.
local function whenKind(w)
  if type(w) ~= "table" then return nil end
  if w.event then return "event" end
  if w.beat then return "beat" end
  if w.zone then return "zone" end
  if w.director or w.directorState then return "director" end
  if w.flag then return "flag" end
  if w.afterSec or w.timer then return "timer" end
  return nil
end
N._whenKind = whenKind

local function onEvent(name, payload)
  local s = N._s
  if not s.started then return end
  payload = payload or {}
  for _, beat in ipairs(s.beats) do
    local w, k = beat.when, whenKind(beat.when)
    if k == "event" and w.event == name and matchesFilters(w, payload) then
      N.trigger(beat.id, name, true)
    elseif k == "beat" and name == "beat.fired" and payload.id == w.beat and payload.id ~= beat.id then
      N.trigger(beat.id, "beat:" .. w.beat, true)
    elseif k == "zone" and name == "zone.entered" and payload.zone == w.zone then
      if (not w.group or w.group == payload.group) then N.trigger(beat.id, "zone:" .. w.zone, true) end
    elseif k == "director" and name == "director.state" then
      local want = w.director or w.directorState
      if payload.state == want and (not w.flight or w.flight == payload.flight) then
        N.trigger(beat.id, "director:" .. tostring(want), true)
      end
    end
  end
  N.pump()   -- one selection after all beats triggered by this event are queued
end

local function stateHolds(beat, t)
  local w, k = beat.when, whenKind(beat.when)
  if k == "flag" then
    local v = N.getFlag(w.flag)
    if w.value ~= nil then return compare(v, type(w.value) == "number" and ("==" .. w.value) or w.value) end
    return v ~= 0
  elseif k == "timer" then
    return t - N._s.startedAt >= (w.afterSec or w.timer)
  end
  return nil
end

local function stateTick()
  local s = N._s
  local t = now()
  for _, beat in ipairs(s.beats) do
    local holds = stateHolds(beat, t)
    if holds ~= nil then
      if holds and not s.stateWas[beat.id] then N.trigger(beat.id, whenKind(beat.when), true) end
      s.stateWas[beat.id] = holds
    end
  end
  N.pump()
end

-- ---------------------------------------------------------------------------
-- zone polling (emits "zone.entered")
-- ---------------------------------------------------------------------------

local function inZone(z, p)
  -- p is vec3; zones use vec2 {x, y} where vec2.y == vec3.z
  local px, py = p.x, p.z
  if z.kind == "circle" or (z.radius and z.x) then
    local dx, dy = px - z.x, py - z.y
    return dx * dx + dy * dy <= z.radius * z.radius
  end
  local pts = z.points
  if type(pts) ~= "table" or #pts < 3 then return false end
  local inside, j = false, #pts
  for i = 1, #pts do
    local xi, yi, xj, yj = pts[i].x, pts[i].y, pts[j].x, pts[j].y
    if ((yi > py) ~= (yj > py)) and (px < (xj - xi) * (py - yi) / (yj - yi) + xi) then inside = not inside end
    j = i
  end
  return inside
end
N._inZone = inZone

local function playerUnits()
  local out, seen = {}, {}
  if coalition and coalition.getPlayers then
    local ok, list = pcall(coalition.getPlayers, playerCoalition())
    if ok and list then
      for _, u in ipairs(list) do
        local okN, n = pcall(u.getName, u)
        if okN and n and not seen[n] then seen[n] = true out[#out + 1] = u end
      end
    end
  end
  if Unit then
    for name in pairs(N._s.players) do
      if not seen[name] then
        local ok, u = pcall(Unit.getByName, name)
        if ok and u then seen[name] = true out[#out + 1] = u end
      end
    end
  end
  return out
end

local function zonesOfInterest()
  local zones, set = cfg().zones or {}, {}
  for _, beat in ipairs(N._s.beats) do
    local w = beat.when
    if type(w) == "table" and w.zone and zones[w.zone] then set[w.zone] = zones[w.zone] end
  end
  return set
end

local function zoneTick()
  local s = N._s
  local zones = zonesOfInterest()
  if next(zones) == nil then return end
  for _, u in ipairs(playerUnits()) do
    local okE, ex = pcall(u.isExist, u)
    local okP, p = pcall(u.getPoint, u)
    if okE and ex and okP and p then
      local uname = u:getName()
      local gname
      local okG, g = pcall(u.getGroup, u)
      if okG and g then gname = g:getName() end
      for zname, z in pairs(zones) do
        local key = zname .. "|" .. uname
        local inside = inZone(z, p)
        if inside and not s.zoneInside[key] and DMS.Bus then
          log("debug", "%s entered zone %s", uname, zname)
          DMS.Bus.emit("zone.entered", { zone = zname, group = gname, unit = uname })
        end
        s.zoneInside[key] = inside
      end
    end
  end
end

-- ---------------------------------------------------------------------------
-- status / introspection
-- ---------------------------------------------------------------------------

function N.statusLines()
  local s = N._s
  local out = {}
  local keys = {}
  for k in pairs(s.outcome) do keys[#keys + 1] = tostring(k) end
  table.sort(keys)
  if #keys > 0 then
    local parts = {}
    for _, k in ipairs(keys) do parts[#parts + 1] = k .. "=" .. tostring(s.outcome[k]) end
    out[#out + 1] = "Outcome: " .. table.concat(parts, ", ")
  end
  out[#out + 1] = string.format("Story beats: %d fired", #s.firedList)
  return out
end

function N.firedCount(id)
  local f = N._s.fired[id]
  return f and f.count or 0
end
function N.firedList() return N._s.firedList end
function N.isPending(id) return N._s.pending[id] ~= nil end

-- ---------------------------------------------------------------------------
-- lifecycle
-- ---------------------------------------------------------------------------

function N.start()
  N.stop()
  N._s = freshState()
  local s = N._s
  s.started = true
  s.startedAt = now()
  for k, v in pairs(cfg().qualities or {}) do s.qualities[k] = tonumber(v) or 0 end
  for i, b in ipairs(cfg().beats or {}) do
    if type(b) == "table" then
      if not b.id then b.id = "beat_" .. i end
      if s.byId[b.id] then
        log("warn", "duplicate beat id '%s' ignored", b.id)
      else
        s.beats[#s.beats + 1] = b
        s.byId[b.id] = b
        s.order[#s.order + 1] = b.id
        if b.when ~= nil and not whenKind(b.when) then
          log("warn", "beat '%s' has an unrecognised `when`; it fires only via DMS.Narrative.trigger", b.id)
        end
      end
    end
  end
  if DMS.Bus then
    local seen = {}
    local function sub(name)
      if seen[name] then return end
      seen[name] = true
      s.tokens[#s.tokens + 1] = DMS.Bus.on(name, function(p) onEvent(name, p) end)
    end
    for _, b in ipairs(s.beats) do
      local w = b.when
      if type(w) == "table" and w.event then sub(w.event) end
    end
    sub("beat.fired"); sub("zone.entered"); sub("director.state")
    s.tokens[#s.tokens + 1] = DMS.Bus.on("player.spawned", function(p)
      if p and p.unit then s.players[p.unit] = true end
    end)
    s.tokens[#s.tokens + 1] = DMS.Bus.on("player.left", function(p)
      if p and p.unit then s.players[p.unit] = nil end
    end)
    s.tokens[#s.tokens + 1] = DMS.Bus.on("mission.end", function(p) N.finish(p and p.result) end)
  end
  if DMS.Clock then
    s.clocks[#s.clocks + 1] = DMS.Clock.every(N.TICK_SEC, function()
      local ok, err = call(stateTick)
      if not ok then log("error", "tick: %s", tostring(err)) end
    end, { firstDelay = N.TICK_SEC })
    local zp = ncfg().zonePollSec or N.ZONE_POLL_SEC
    s.clocks[#s.clocks + 1] = DMS.Clock.every(zp, function()
      local ok, err = call(zoneTick)
      if not ok then log("error", "zone poll: %s", tostring(err)) end
    end, { firstDelay = zp, jitter = 0.5 })
  end
  log("info", "started with %d beats (minGap %ds)", #s.beats, gapSec())
end

function N.stop()
  local s = N._s
  if not s then return end
  if DMS.Bus then for _, t in ipairs(s.tokens) do DMS.Bus.off(t) end end
  if DMS.Clock then for _, id in ipairs(s.clocks) do DMS.Clock.cancel(id) end end
  s.tokens, s.clocks, s.started = {}, {}, false
end
