-- DMS.Comms: voice + subtitle queue (never overlaps), per-speaker shuffle-bags,
-- per-group F10 menus under a "DMS" root.
-- Depends on: DMS.Log, DMS.Clock, DMS.Bus, DMS.Rng, DMS.safeCall (contract v0.3).
DMS = DMS or {}
DMS.Comms = DMS.Comms or {}

local Comms = DMS.Comms
local P = "Comms"

Comms.SOUND_PREFIX = "l10n/DEFAULT/"
Comms.GAP_SEC = 0.75          -- silence between queued transmissions
Comms.MAX_QUEUE = 12          -- oldest low-priority items dropped beyond this
Comms.ROOT_MENU = "DMS"

-- ---------------------------------------------------------------------------
-- helpers
-- ---------------------------------------------------------------------------

local function cfg() return DMS_CONFIG or {} end

local function now()
  if DMS.Clock and DMS.Clock.now then return DMS.Clock.now() end
  return 0
end

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

local function estimateDur(text)
  local words = 0
  for _ in string.gmatch(text or "", "%S+") do words = words + 1 end
  local d = words * 0.4 + 1
  if d < 2 then d = 2 end
  return d
end

local function speakerCfg(speaker)
  local sp = cfg().speakers
  if type(sp) == "table" and speaker ~= nil and type(sp[speaker]) == "table" then return sp[speaker] end
  return nil
end

local function speakerCallsign(speaker, opts)
  if opts and opts.callsign then return opts.callsign end
  local sc = speakerCfg(speaker)
  if sc and sc.callsign then return sc.callsign end
  return speaker
end

-- Multi-speaker exchange (voice entry `turns`): one subtitle line per turn, "<callsign>: text".
local function turnsText(turns)
  local out = {}
  for _, t in ipairs(turns) do
    if type(t) == "table" and t.text then
      local cs = speakerCallsign(t.speaker)
      out[#out + 1] = cs and (tostring(cs) .. ": " .. t.text) or t.text
    end
  end
  if #out == 0 then return nil end
  return table.concat(out, "\n")
end

-- ---------------------------------------------------------------------------
-- state
-- ---------------------------------------------------------------------------

local function freshState()
  return {
    queue = {}, seq = 0, busyUntil = -1, pumpId = nil,
    bags = {}, cooldowns = {},
    lastByCoalition = {}, lastByGroup = {},
    groups = {},           -- groupId -> {root, ctx, submenus = {pathKey -> handle}}
    tokens = {}, started = false,
    played = {},           -- history (bounded) for tests / debugging
  }
end

Comms._s = Comms._s or freshState()
Comms._commands = Comms._commands or {}   -- registered menu commands (persist across restarts)
Comms._statusProviders = Comms._statusProviders or {}

-- ---------------------------------------------------------------------------
-- output primitives
-- ---------------------------------------------------------------------------

local function outText(target, msg, dur)
  if not (trigger and trigger.action) then return end
  if target.groupId and trigger.action.outTextForGroup then
    trigger.action.outTextForGroup(target.groupId, msg, dur, false)
  elseif trigger.action.outTextForCoalition then
    trigger.action.outTextForCoalition(target.coalition or playerCoalition(), msg, dur, false)
  end
end

local function outSound(target, path)
  if not (trigger and trigger.action) then return end
  if target.frequency and trigger.action.radioTransmission then
    local f = target.frequency
    local hz = (f < 1000) and math.floor(f * 1000000 + 0.5) or f   -- MHz or Hz accepted
    local mod = target.modulation or 0                              -- 0 = AM, 1 = FM
    local pos = target.pos or { x = 0, y = 0, z = 0 }
    Comms._s.txSeq = (Comms._s.txSeq or 0) + 1
    trigger.action.radioTransmission(path, pos, mod, false, hz, target.power or 1000,
      "DMS_TX_" .. Comms._s.txSeq)
  elseif target.groupId and trigger.action.outSoundForGroup then
    trigger.action.outSoundForGroup(target.groupId, path)
  elseif trigger.action.outSoundForCoalition then
    trigger.action.outSoundForCoalition(target.coalition or playerCoalition(), path)
  end
end

local function remember(target, msg, dur)
  local rec = { msg = msg, dur = dur, t = now() }
  if target.groupId then
    Comms._s.lastByGroup[target.groupId] = rec
  else
    Comms._s.lastByCoalition[target.coalition or playerCoalition()] = rec
  end
end

-- ---------------------------------------------------------------------------
-- queue
-- ---------------------------------------------------------------------------

local pump

local function play(item)
  local s = Comms._s
  local t = now()
  if item.file then outSound(item, Comms.SOUND_PREFIX .. item.file) end
  local msg
  if item.turnsText then
    msg = item.turnsText
  else
    msg = item.callsign and (item.callsign .. ": " .. (item.text or "")) or (item.text or "")
  end
  if item.text and item.text ~= "" then
    local showFor = item.dur + 2
    if showFor < 5 then showFor = 5 end
    outText(item, msg, showFor)
    remember(item, msg, showFor)
  end
  s.played[#s.played + 1] = { t = t, dur = item.dur, line = item.line, speaker = item.speaker,
    file = item.file, text = msg }
  if #s.played > 200 then table.remove(s.played, 1) end
  s.busyUntil = t + item.dur
  log("debug", "TX %s line=%s dur=%.1f '%s'", tostring(item.speaker), tostring(item.line), item.dur, msg)
end

pump = function()
  local s = Comms._s
  s.pumpId = nil
  if #s.queue == 0 then return end
  local t = now()
  local readyAt = s.busyUntil + Comms.GAP_SEC
  if s.busyUntil >= 0 and t < readyAt then
    if DMS.Clock then s.pumpId = DMS.Clock.after(readyAt - t, pump) end
    return
  end
  -- highest priority first, FIFO among equals
  local bi = 1
  for i = 2, #s.queue do
    local a, b = s.queue[i], s.queue[bi]
    if a.priority > b.priority or (a.priority == b.priority and a.seq < b.seq) then bi = i end
  end
  local item = table.remove(s.queue, bi)
  local ok, err = call(play, item)
  if not ok then log("error", "playback failed: %s", tostring(err)) end
  if #s.queue > 0 and DMS.Clock then
    s.pumpId = DMS.Clock.after(item.dur + Comms.GAP_SEC, pump)
  end
end

local function enqueue(item)
  local s = Comms._s
  s.seq = s.seq + 1
  item.seq = s.seq
  item.priority = item.priority or 0
  s.queue[#s.queue + 1] = item
  while #s.queue > Comms.MAX_QUEUE do
    local wi
    for i = 1, #s.queue do
      local a = s.queue[i]
      if not a.keep then
        local b = wi and s.queue[wi]
        if not b or a.priority < b.priority or (a.priority == b.priority and a.seq < b.seq) then wi = i end
      end
    end
    if not wi then break end   -- everything queued must be kept (guaranteed beats)
    local dropped = table.remove(s.queue, wi)
    log("warn", "queue full, dropped line %s", tostring(dropped.line))
  end
  if not s.pumpId then pump() end
end

local function pickLine(speaker, lineIds)
  if type(lineIds) == "string" then return lineIds end
  if type(lineIds) ~= "table" or #lineIds == 0 then return nil end
  if #lineIds == 1 then return lineIds[1] end
  local key = tostring(speaker) .. "|" .. table.concat(lineIds, ",")
  local bag = Comms._s.bags[key]
  if not bag then
    bag = DMS.Rng.shuffleBag(lineIds)
    Comms._s.bags[key] = bag
  end
  return bag:next()
end

--- Queue a voice line (or subtitle only when no voice file exists).
-- @param speaker string speaker id (DMS_CONFIG.speakers[speaker].callsign used for subtitles if present)
-- @param lineIds string|list voice line id(s) into DMS_CONFIG.voice; variants rotate via shuffle-bag
-- @param text string fallback subtitle text when the voice entry has none
-- @param opts {coalition, groupId, frequency (MHz|Hz), modulation, pos, power, priority,
--              cooldownSec, key, callsign, durSec, keep}
--   frequency/modulation default to DMS_CONFIG.speakers[speaker].frequency/modulation;
--   keep = true: never dropped when the queue overflows (guaranteed beats).
-- @return chosen line id (or true for text-only), or false when suppressed by cooldown
function Comms.say(speaker, lineIds, text, opts)
  opts = opts or {}
  local s = Comms._s
  local t = now()
  local cdKey = opts.key or speaker or text
  if opts.cooldownSec and opts.cooldownSec > 0 and cdKey then
    local last = s.cooldowns[cdKey]
    if last and t - last < opts.cooldownSec then
      log("debug", "suppressed '%s' (cooldown %.0fs)", tostring(cdKey), opts.cooldownSec)
      return false
    end
  end
  if cdKey then s.cooldowns[cdKey] = t end

  local line = pickLine(speaker, lineIds)
  local v = line and cfg().voice and cfg().voice[line] or nil
  if line and not v then log("debug", "no voice entry for line '%s' (subtitle only)", line) end
  local who = (v and v.speaker) or speaker
  local sc = speakerCfg(who) or speakerCfg(speaker) or {}
  local item = {
    speaker = who, line = line,
    file = (v and type(v.file) == "string" and v.file ~= "") and v.file or nil,   -- no file = subtitle only
    text = (v and v.text) or text,
    coalition = opts.coalition, groupId = opts.groupId,
    frequency = opts.frequency or sc.frequency, modulation = opts.modulation or sc.modulation,
    pos = opts.pos, power = opts.power,
    priority = opts.priority, keep = opts.keep and true or nil,
  }
  item.callsign = speakerCallsign(item.speaker, opts)
  if v and type(v.turns) == "table" then item.turnsText = turnsText(v.turns) end
  item.dur = opts.durSec or (v and v.durSec) or estimateDur(item.text or item.turnsText)
  if not item.file and not item.turnsText and (not item.text or item.text == "") then return false end
  enqueue(item)
  return line or true
end

--- Immediate text message (not queued). opts: {coalition, groupId, durSec, callsign}
function Comms.text(msg, opts)
  opts = opts or {}
  if opts.callsign then msg = opts.callsign .. ": " .. msg end
  local dur = opts.durSec or 10
  local target = { coalition = opts.coalition, groupId = opts.groupId }
  outText(target, msg, dur)
  remember(target, msg, dur)
  return true
end

--- Re-display the last message heard by a group (falls back to its coalition's).
function Comms.repeatLast(groupId, coalitionId)
  local s = Comms._s
  local g = groupId and s.lastByGroup[groupId]
  local c = s.lastByCoalition[coalitionId or playerCoalition()]
  local rec = g
  if c and (not rec or c.t > rec.t) then rec = c end
  local target = { groupId = groupId, coalition = coalitionId }
  if rec then
    outText(target, rec.msg, rec.dur)
  else
    outText(target, "No messages yet.", 5)
  end
  return rec
end

function Comms.isBusy()
  local s = Comms._s
  return #s.queue > 0 or now() < s.busyUntil + Comms.GAP_SEC
end

function Comms.history() return Comms._s.played end

-- ---------------------------------------------------------------------------
-- status
-- ---------------------------------------------------------------------------

--- Register an extra provider: fn() -> string|list of strings
function Comms.addStatusProvider(fn) Comms._statusProviders[#Comms._statusProviders + 1] = fn end

function Comms.statusText()
  local lines = {}
  local mid = cfg().missionId
  lines[#lines + 1] = string.format("Mission %s  T+%d:%02d", tostring(mid or "DMS"),
    math.floor(now() / 60), math.floor(now() % 60))
  local function add(fn)
    local ok, r = call(fn)
    if ok and type(r) == "string" then lines[#lines + 1] = r end
    if ok and type(r) == "table" then for _, l in ipairs(r) do lines[#lines + 1] = l end end
  end
  for _, name in ipairs({ "Narrative", "Intel", "Director", "Encounters" }) do
    local m = DMS[name]
    if m and type(m.statusLines) == "function" then add(m.statusLines) end
  end
  for _, fn in ipairs(Comms._statusProviders) do add(fn) end
  return table.concat(lines, "\n")
end

-- ---------------------------------------------------------------------------
-- per-group F10 menus
-- ---------------------------------------------------------------------------

local function pathList(path)
  if path == nil or path == "" then return {} end
  if type(path) == "table" then return path end
  local out = {}
  for part in string.gmatch(path, "[^/]+") do out[#out + 1] = part end
  return out
end

local function ensureSubmenu(g, parts)
  local parent = g.root
  local key = ""
  for _, name in ipairs(parts) do
    key = key .. "/" .. name
    local h = g.submenus[key]
    if not h then
      h = missionCommands.addSubMenuForGroup(g.ctx.groupId, name, parent)
      g.submenus[key] = h
    end
    parent = h
  end
  return parent
end

local function runCommand(arg)
  local g = Comms._s.groups[arg.groupId]
  local cmd = Comms._commands[arg.index]
  if not g or not cmd then return end
  log("debug", "menu '%s' pressed by group %s (%s)", cmd.label, tostring(g.ctx.groupName),
    tostring(g.ctx.playerName))
  local ok, err = call(cmd.fn, g.ctx)
  if not ok then log("error", "menu command '%s' failed: %s", cmd.label, tostring(err)) end
end

local function addCommandToGroup(g, index)
  local cmd = Comms._commands[index]
  local parent = ensureSubmenu(g, cmd.path)
  missionCommands.addCommandForGroup(g.ctx.groupId, cmd.label, parent, runCommand,
    { groupId = g.ctx.groupId, index = index })
end

local function buildGroupMenu(ctx)
  if not missionCommands then return end
  local s = Comms._s
  local old = s.groups[ctx.groupId]
  if old and old.root then pcall(missionCommands.removeItemForGroup, ctx.groupId, old.root) end
  local g = { ctx = ctx, submenus = {} }
  g.root = missionCommands.addSubMenuForGroup(ctx.groupId, Comms.ROOT_MENU)
  s.groups[ctx.groupId] = g
  for i = 1, #Comms._commands do addCommandToGroup(g, i) end
  log("debug", "built menu for group %s (id %s, %d commands)", tostring(ctx.groupName),
    tostring(ctx.groupId), #Comms._commands)
end

--- Register an F10 command for every player group (existing and future).
-- @param path string "Sub/Menu" or list of submenu names under the DMS root ("" or nil = root)
-- @param label string command label
-- @param fn function(ctx) ctx = {groupId, groupName, unitName, playerName, coalition}
function Comms.addMenuCommand(path, label, fn)
  local parts = pathList(path)
  local key = table.concat(parts, "/") .. "|" .. label
  for i, c in ipairs(Comms._commands) do
    if c.key == key then
      c.fn = fn            -- re-registration replaces the handler, no duplicate entry
      return i
    end
  end
  local idx = #Comms._commands + 1
  Comms._commands[idx] = { key = key, path = parts, label = label, fn = fn }
  if missionCommands then
    for _, g in pairs(Comms._s.groups) do
      local ok, err = pcall(addCommandToGroup, g, idx)
      if not ok then log("error", "addMenuCommand: %s", tostring(err)) end
    end
  end
  return idx
end

function Comms.menuFor(groupId) return Comms._s.groups[groupId] end

local function onPlayerSpawned(e)
  if not e or e.groupId == nil then return end
  local ctx = { groupId = e.groupId, groupName = e.group, unitName = e.unit,
    playerName = e.playerName, coalition = e.coalition }
  local ok, err = call(buildGroupMenu, ctx)
  if not ok then log("error", "menu build failed for %s: %s", tostring(e.group), tostring(err)) end
end

-- ---------------------------------------------------------------------------
-- lifecycle
-- ---------------------------------------------------------------------------

local function registerBuiltins()
  Comms.addMenuCommand("", "Repeat last message", function(ctx)
    Comms.repeatLast(ctx.groupId, ctx.coalition)
  end)
  Comms.addMenuCommand("", "Mission status", function(ctx)
    outText({ groupId = ctx.groupId, coalition = ctx.coalition }, Comms.statusText(), 15)
  end)
end

function Comms.start()
  Comms.stop()
  Comms._s = freshState()
  local s = Comms._s
  s.started = true
  registerBuiltins()
  if DMS.Bus then
    s.tokens[#s.tokens + 1] = DMS.Bus.on("player.spawned", onPlayerSpawned)
  end
  log("info", "started (%d menu commands, %d voice lines)", #Comms._commands,
    (function() local n = 0 for _ in pairs(cfg().voice or {}) do n = n + 1 end return n end)())
end

function Comms.stop()
  local s = Comms._s
  if not s then return end
  if DMS.Bus then for _, t in ipairs(s.tokens) do DMS.Bus.off(t) end end
  s.tokens = {}
  if s.pumpId and DMS.Clock then DMS.Clock.cancel(s.pumpId) end
  s.pumpId = nil
  s.started = false
end

--- Test helper: forget registered menu commands / providers too.
function Comms._resetAll()
  Comms.stop()
  Comms._s = freshState()
  Comms._commands = {}
  Comms._statusProviders = {}
end
