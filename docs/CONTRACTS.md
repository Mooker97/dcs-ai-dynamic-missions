# Interface contracts (v0.3.1)

These are the shared interfaces that parallel work builds against. Change them only by editing
this file first. Background: `docs/rebuild/ARCHITECTURE-PROPOSAL.md`, `docs/rebuild/RESEARCH-NOTES.md`.
The end-to-end check that Python and Lua agree is `tests/integration/test_config_roundtrip.py`
(m01 config -> `dms_config.lua` -> `dist/dms.lua` in the DCS mock, 50 seeds).

## Naming rules (Python <-> Lua)

- Python model **field names** are snake_case. `RuntimeConfig.to_lua_table()` converts them to
  camelCase (`max_active_ground` -> `maxActiveGround`, `flags_not` -> `flagsNot`).
- **User keys are never converted**: template / zone / pool / voice-line / speaker ids, outcome
  keys (`{patrol_complete = true}`), quality ids and flag names keep their authored spelling.
- `None` values are dropped; tuples become Lua arrays.
- Python schemas only grow additively: new optional fields, widened literals/unions, and
  `mode="before"` validators that normalise the Lua-style aliases listed below into the canonical
  shape. The Lua runtime accepts the canonical camelCase keys **and** those aliases.

## Lua runtime: core API (lua/src/dms/)

Target: DCS mission scripting, **Lua 5.1** (no goto; os/io/lfs/require unavailable). Each module is a
global table on `DMS` with the guard `DMS = DMS or {}; DMS.X = DMS.X or {}`. Load order is
`lua/manifest.txt`; `tools/bundle_lua.py` concatenates it into `dist/dms.lua`.

**Embed order in the .miz:** plugins -> `dms_config.lua` -> `dms.lua` -> plugin adapters (config
first; see "Optional plugins" below). The runtime
tolerates either order: `init.lua` boots immediately when `DMS_CONFIG` exists at load, otherwise
it re-checks for a few seconds via `DMS.Clock.after` and then logs a warning. `DMS.boot()` is
idempotent.

```lua
DMS.VERSION                       -- string stamped by bundler
DMS_CONFIG                        -- global table emitted by the generator (see below); may be nil in tests
DMS.boot() -> bool                -- start modules in DMS.START_ORDER, then emit "mission.start"; once only
DMS.START_ORDER = { "Spawner", "Ground", "Director", "Encounters", "Narrative", "Comms", "Intel", "Ambient" }
-- boot calls mod.start(mod) under safeCall; start functions ignore their arguments.
DMS.BOOT_RETRIES = 5  DMS.BOOT_RETRY_SEC = 1   -- deferred-boot polling when DMS_CONFIG loads late
DMS._deferBoot()                  -- internal (init.lua); skipped if a module was started by hand

-- core.lua
DMS.Log.debug(prefix, fmt, ...)   -- only when DMS.Log.isDebug(); "[DMS][prefix] msg" via env.info
DMS.Log.info / warn / error(prefix, fmt, ...)
DMS.Log.setDebug(bool)            DMS.Log.isDebug() -> bool        -- default: DMS_CONFIG.debug
DMS.safeCall(fn, ...) -> ok, ...  -- xpcall + traceback; logs errors with prefix "safeCall"
DMS.Json.encode(v) -> string      -- deterministic (sorted keys), {} for empty tables, errors on cycles
DMS.Log.outcome(tbl)              -- env.info("[DMS.OUTCOME] " .. DMS.Json.encode(tbl))

-- clock.lua: the only module allowed to call timer.scheduleFunction
DMS.Clock.now()                   DMS.Clock.after(delaySec, fn, ...) -> id
DMS.Clock.every(intervalSec, fn, opts) -> id   -- opts.jitter, opts.firstDelay; return false to stop
DMS.Clock.cancel(id)              DMS.Clock.isActive(id) -> bool

-- rng.lua
DMS.Rng.seed(n)                   -- n nil: DMS_CONFIG.seed mixed with timer entropy
DMS.Rng.random() DMS.Rng.int(a,b) DMS.Rng.chance(pct) DMS.Rng.weighted(items) DMS.Rng.pickN(list,n)
DMS.Rng.shuffle(list)             DMS.Rng.shuffleBag(list) -> bag (bag:next())
DMS.Rng.jitter(base, spread)      DMS.Rng.range(t) DMS.Rng.rangeInt(t)   -- t = number | {min, max}

-- bus.lua: the only module allowed to call world.addEventHandler
DMS.Bus.on(name, fn(payload, name)) -> token   -- name "*" receives everything
DMS.Bus.off(token)                DMS.Bus.emit(name, payload)
DMS.Bus.learnGroup(groupOrName)   DMS.Bus.rescan()   DMS.Bus.unitInfo(unitName)
DMS.Bus._players[unitName]        -- live player units (set at BIRTH, cleared after their unit.dead)
DMS.Bus.install() / uninstall()   -- add/remove the world event handler (install also rescans); called by init

-- registry.lua
DMS.Registry.allocName(prefix) -> "DMS_<prefix>_<n>"   -- runtime spawns are named DMS_<poolOrTemplateId>_<n>
DMS.Registry.track(groupName, meta)  -- meta {category="ground"|"air"|"ship", coalition, encounter, units, template}
DMS.Registry.untrack(g)  DMS.Registry.get(g)  DMS.Registry.isAlive(g)  DMS.Registry.count(category, coalition)
DMS.Registry.budgetAvailable(category, coalition, nUnits)   -- DMS_CONFIG.budgets
DMS.Registry.spawnRateAvailable()  -- informational; the director owns the spawn-rate window
DMS.Registry.list(filterFn(name, meta)) -> sorted names
```

### Runtime modules

```lua
-- spawner.lua
DMS.Spawner.spawn(templateId, zoneId|point|{zone=}|{x,y,radiusM}, opts) -> groupName|nil, reason
--   opts: country, heading (DEGREES), hidden, encounter, minPlayerDistM (default 5 km ground / 37 km air),
--         outOfLOS, buildingRadius, tries, prefix, skill, lateActivation, ignoreBudget, onReady(name),
--         radiusM, cost, altM / speed (air), losHeightM (outOfLOS eye height, default 3),
--         readyDelaySec (before onReady).
--         Ground points must be land (no water / shallow water) for every unit.
DMS.Spawner.spawnPool(poolId, opts) -> {groupName...}   -- count = poolCount(poolId) unless opts.count
--   opts as spawn, plus count (fixed, not scaled) and zone | point (where; default a random pool.zones entry)
--   opts.cost is PER GROUP: every spawned group emits spawner.spawned{cost}, so a launch notes count x cost.
DMS.Spawner.poolCount(poolId) -> n   -- one roll of Rng.range(pool.pick), rounded, then Director.scaleCount
DMS.Spawner.getZone(id) zoneCenter(z) zoneRadius(z) inZone(z, p) randomPointInZone(z) playerUnits()
DMS.Spawner.isLand(p) isWater(p) validPoint(p, opts, players) -> ok, reason
--   validPoint opts: category (ship = water, air = anywhere, else land), buildingRadius, outOfLOS,
--                    losHeightM, minPlayerDistM
DMS.Spawner.buildGroupData(name, tpl, pos, headingRad, opts) -> DCS group table   -- used by spawn
-- ground.lua
DMS.Ground.routeTo(name, point, opts) halt resume holdFire openFire returnFire alarm(name, "GREEN"|"RED"|"AUTO")
DMS.Ground.hunt(name, target, opts) stopHunt watch(name, opts) haltOnHit(convoy, resumeAfterSec) leadPos
DMS.Ground.fireAtPoint(name, point, {radius=100, expendQty}) -> bool
-- director.lua
DMS.Director.canSpawn(cost, flight?) -> ok, reason   noteSpawn(cost)   state(flight?) intensity(flight?)
DMS.Director.skillFor(skill) scaleCount(n) scaleDelay(sec) adapt(delta, why) level()
DMS.Director.addIntensity(flight, amount, why) addPlayer(unit, group?) removePlayer(unit) flights() -> sorted names
DMS.Director.spawnBudget() -> spawns/min   tick(dt)   -- tick is driven by start(); call directly only in specs
--   removePlayer(unit, keepFlight?): last unit gone -> flight deleted, or kept as an orphan
--     (keepFlight) so the breather (PEAK -> RELAX) still applies; tick prunes orphans once back in
--     BUILD_UP; a respawn into the same group resumes its state.
--   player.left keeps the flight as an orphan and remembers the unit for Director.LEFT_GRACE_SEC
--     (10 s): a unit.dead / unit.ejected / unit.pilot_dead for it inside the window still counts as
--     a player death (counted once per life); with no death the flight is deleted when it expires.
--     unit.ejected / unit.pilot_dead while the unit is still mapped also count as the death.
--   spawn budget: rolling 60 s window of noted costs, max(1, spawnsPerMin * (1 + 0.25 * level));
--     an empty window always admits one spawn (oversized costs are throttled, never starved).
--   state() with no flight: state of the most intense flight; ties -> PEAK > RELAX > BUILD_UP, then name.
--   adapt clamp: DMS_CONFIG.director.adapt {min<=0, max>=0} (default -1/+1); skill tier = rounded level.
--   enabled=false: passthrough. Only the spawn budget applies (no flights, no states, level stays 0).
-- encounters.lua
DMS.Encounters.trigger(id, opts) -> bool   -- opts: boolean force | {force=bool, beat=id}; ignores chance,
                                           --       respects once unless force
DMS.Encounters.get(id) groups(id) add(def)
DMS.Encounters.capStation(def) capOrbitTask(station, n?) capEngageTask(station, targetTypes?, n?)  -- cap task tables
--   event trigger: {type="event", event=<bus event>}; `name` is accepted as an alias for `event`
-- narrative.lua
DMS.Narrative.trigger(id, source) setFlag(name, value) getFlag(name) isFlagSet(name)
DMS.Narrative.getQuality(q) addQuality(q, d) setOutcome(tbl) finish(result) firedList() firedCount(id)
DMS.Narrative.outcome() qualities() qualityDeltas()   -- live tables (read-only by convention)
DMS.Narrative.pump()                       -- internal: run beat selection now (trigger/events call it)
-- comms.lua
DMS.Comms.say(speaker, lineIds, text, opts) -> lineId|true|false
--   opts: coalition, groupId, frequency (MHz|Hz), modulation (0 AM, 1 FM), pos, power, priority,
--         cooldownSec, key, callsign, durSec, keep (never dropped from a full queue)
--   frequency/modulation default to DMS_CONFIG.speakers[speaker]; callsign likewise.
--   Queue: one line at a time, GAP_SEC (0.75) between, priority then FIFO, never interrupts.
--   lineIds list = variants: shuffle-bag per (speaker, list), no immediate repeat across refills.
--   With a frequency, radioTransmission at opts.power or Comms.TX_POWER_W (10000 W, the ME max)
--   from near each listener (DCS fades by range/LOS per listener; ~1 nm at 10000 W stays clear):
--   opts.pos -> one transmitter there; a group line (groupId) -> one, Comms.TX_ABOVE_M (150 m)
--   above that group's first player unit (none if the group has no player); a coalition-wide line
--   -> one per player group, de-duplicated by group, TX_ABOVE_M above each group's first player
--   unit, and a group within Comms.TX_MERGE_M (2 nm) of an earlier transmitter shares it. Every
--   radioTransmission gets its own name (DMS_TX_<seq>). The line still plays once: one subtitle,
--   one queue slot, one PLAY line. With no player position, outSoundForGroup/ForCoalition (never
--   a map-origin transmitter). In a DMS.Test proxy run with no human player, the proxy group's
--   units stand in for the players (so headless runs exercise radioTransmission).
--   Each play logs info `PLAY n=<seq> line=<id|-> speaker=<id> via=radio|group|coalition|text
--   file=<f|-> start=<t> end=<t+durSec> tx=<n>` (n = radioTransmission calls, 0 unless via=radio);
--   start logs `started (.. N voice lines, M with audio)`.
DMS.Comms.text(msg, opts) repeatLast(groupId, coalition) history() addMenuCommand(path, label, fn)
--   history(): played lines {t, dur, line, speaker, file, text}, oldest first; capped at
--   Comms.historyCap() = HISTORY_CAP (200), or HISTORY_CAP_TEST (100000) when DMS_CONFIG.test is
--   enabled so the end-of-run comms checks see every line.
DMS.Comms.isBusy() -> bool   statusText() -> string   menuFor(groupId) -> menu record|nil
DMS.Comms.addStatusProvider(fn() -> string|{string...})   -- extra lines in the status menu text
-- intel.lua
DMS.Intel.reveal(groupName, reason, opts) forget(g) contacts() contact(g) report(groupId) kills()
DMS.Intel.mark(spec) -> handle            -- see "mark" below
DMS.Intel.removeMarkHandle(handle) -> bool     -- true once the handle is removed (false if unknown)
--   Group marks: one stable handle per group (marking the same group again returns it). Removing
--   it forgets the contact only if the mark created it; an independently detected contact stays
--   and gets its label/radius back.
DMS.Intel.resolveGroup(name) -> groupName|nil   -- "group:<name>": exact live group, else first live
                                                --  prefix match (with or without "DMS_")
DMS.Intel.liveMarks() -> {id -> {kind="circle"|"text", text, pos, coalition, radius, owner, t}}
DMS.Intel.markStats() -> {added, removed, failed, live}   -- mission-wide (survive stop/start)
--   Mark ids start at FIRST_MARK_ID (50000) and only grow; they are never reused, even after
--   removeMark (a reused id fires MARK_ADDED but never renders: ED bug). Intel.start() raises the
--   next id past panels in our band [FIRST_MARK_ID, FIRST_MARK_ID + MARK_ID_BAND (10^7)) or
--   script-made ones (initiator nil) below PLAYER_MARK_FLOOR (2.5e8), never past player marks
--   (ids ~251,000,000+), so our next id cannot land on the player's next mark. Intel.stop() removes every mark it drew; Intel.start() calls stop() only
--   on a restart, so marks beats drew before the first start survive. A mark DCS rejected (pcall
--   error) is not tracked. Each F10 change logs one debug line (test builds set debug = true):
--     [DMS][Intel] MARK add id=<n> kind=circle|text coal=<-1|1|2> x=<x> z=<z> r=<m|-> t=<model s> owner=<contact:G|mark:label> text=<label>
--     [DMS][Intel] MARK remove id=<n> kind=<kind> t=<model s> why=<redraw|destroyed|contact lost|...>
--   (newlines in text become " | "; owner has no spaces). A failed call logs ERROR "MARK add failed id=<n>".
-- ambient.lua: DMS.Ambient (friendly base traffic around player airbases; own budget, never
--   tracked in DMS.Registry, never emits spawner.spawned, so Director/Intel/Test spawn counts ignore it)
DMS.Ambient.start()                 -- in START_ORDER after Intel; inert unless DMS_CONFIG.ambient.enabled
DMS.Ambient.tick()                  -- one activation/maintenance pass (driven by Clock.every(checkSec))
DMS.Ambient.activate(siteId) -> bool   deactivate(siteId, reason) -> nGroupsRemoved
DMS.Ambient.isActive(siteId) -> bool   sites() -> sorted ids   owned(siteId) -> {groups={...}, statics={...}}
DMS.Ambient.isAmbient(groupOrStaticName) -> bool   -- Director ignores unit.dead/unit.shot of these
DMS.Ambient.counts(siteId?) -> groups, units      -- live ambient groups/units (site or all)
-- test.lua: DMS.Test (headless-DCS assertions; inert unless DMS_CONFIG.test.enabled)
--   Starts itself on mission.start (not in START_ORDER). Logs "[DMS.TEST] PASS|FAIL|SKIP|INFO <name> <detail>"
--   and "[DMS.TEST] DONE <passed>/<total>" (parsed by tools/dcs_harness).
DMS.Test.pass(name, detail) fail skip info   check(name, cond, detail) -> bool   done() autoDone(graceSec)
DMS.Test.expect(name, fn(atEnd) -> ok, detail, fatal, deadlineSec, {interval=2, negate})
DMS.Test.config() isEnabled() proxyName() isProxyRun() runChecks(checks, deadlineSec)
--   DMS_CONFIG.test = {enabled, playerProxy=<AI group treated as the player>, minutes, checks={...},
--                      loiter={zone, x, y, radiusM, altM, altType, speedMps, startBeat?, untilBeat, returnSec}?}
--   check kinds: booted | spawns{min} | beats_in_order{beats} | beat{id} | comms{min} |
--                encounter{id, optional?, group?} | convoy_halt | outcome{requireResult?} |
--                ambient_cycle{site?} | marks{min?} | fog_hidden | comms_no_overlap{toleranceSec?} |
--                comms_beats{beats?}; optional name, deadlineSec
--   marks / fog_hidden / comms_no_overlap / comms_beats are end-of-run checks (resolved with DONE,
--     never hold the run open). testmode adds all four (f10_marks, fog_hidden, radio_no_overlap,
--     spine_lines_played; f10_marks min = 1 when a spine beat has a mark, else 0).
--   marks: PASS when Intel drew >= min marks, none failed, and (sampled every 10 s and at the end)
--     every live text mark id is in world.getMarkPanels() and no removed id in our range is still
--     listed. DCS lists drawn shapes there too ({idx, time, initiator, coalition, groupID, text,
--     pos}; all-coalition shapes report coalition 255, pos = average of points), so circles are
--     verified: a missing one fails once getMarkPanels lists any of our circles; if it lists none,
--     the detail says circles are unverified (no FAIL). No getMarkPanels -> PASS "unverified".
--   fog_hidden: with intel.fogOfWar ~= false, every enemy vehicle/ship/plane/helicopter group in
--     env.mission (minus intel.knownGroups) and every enemy group passed to coalition.addGroup
--     after mission.start (test mode wraps it) has hidden = true.
--   comms_no_overlap: no DMS.Comms.history() line starts before the previous t + dur - 0.05 s.
--     SKIP when history entries carry no numeric t/dur.
--   comms_beats: every guaranteed beat (or `beats`) with speech (lines/text, or effects.speak) that
--     fired has a history entry at/after its fire time whose `line` is one of its lines or whose
--     text contains its text. Still queued at the end -> INFO, not FAIL.
--   Comms log line the harness reads (info): [DMS][Comms] PLAY n=<seq> line=<id|-> speaker=<id>
--     via=<..> file=<f|-> start=<model s> end=<model s> (see comms.lua above); tools/dcs_harness
--     log_comms_overlap SKIPs PLAY lines without start=/end=. The debug `TX '<text>'` line is text only.
--   Harness-side checks (tools/dcs_harness/run_mission.py, report `log_checks`, on unless
--     --no-log-checks; a FAIL fails the run): log_marks (replays the debug MARK add/remove lines:
--     FAIL on an add of a live id, a remove of a never-added id, a failed call, or replay counts
--     at the Lua marks check line ("added=A removed=R live=L failed=F") that differ from it;
--     without that Lua line it is informational; no MARK lines -> SKIP if the Lua check counted
--     marks (debug off), else INFO) and log_comms_overlap (sorted by start, every PLAY start >= previous
--     end + Comms.GAP_SEC (0.75) - 0.05 s; dur = end - start).
--   encounter optional=true: never FAILs and never holds the run open; PASS if it spawned, else
--     INFO "optional encounter X not spawned" (plus "group G: Y spawned" when a sibling of the same
--     mutually exclusive `group` spawned). testmode makes a check required only when its trigger is
--     unconditional for the proxy (time / director, proximity on the proxy route, or a guaranteed
--     beat; spec chance 100); everything else is optional.
--   outcome: PASS on any `kind=end` outcome, detail reports its result; `requireResult`
--     (success|failure) also demands that result (legacy `result` is the same). testmode sets it
--     only from mission-spec `test.require_result`.
--   loiter: once `startBeat` (the loiter zone's spine beat) fired or the proxy is within radiusM
--     of (x, y) (circle zone radius, else a small floor) it gets a pushed Orbit task (circle,
--     altM BARO or RADIO = AGL, speedMps) until beat `untilBeat` fired or model time
--     minutes*60 - returnSec, then popTask resumes the route home. Logs INFO loiter start/stop
--     (and skip when untilBeat fired before the zone). Set by testmode when the spine beat before
--     the first landing beat is not position-driven (e.g. an RTB call on a flag/timer).
--   ambient_cycle: PASS once a site (any, or `site`) emitted ambient.activated and later
--   ambient.deactivated (proxy left the area); detail lists activations/deactivations per site.
```

### Events

All payload names are strings; `pos` is vec3; coalition is 0 neutral / 1 red / 2 blue.

| Event | Payload | Emitted by |
|---|---|---|
| `unit.hit` | `{target, targetGroup, targetCoalition, initiator?, initiatorGroup?, weapon}` | bus (HIT) |
| `unit.shot` | `{initiator, initiatorGroup, coalition, weapon}` | bus (SHOT) |
| `unit.dead` | `{unit, group, coalition, category="air"\|"ground"\|"ship"\|"static", typeName, pos, killer?}` | bus (DEAD/UNIT_LOST/KILL/CRASH, de-duplicated) |
| `group.dead` | `{group, coalition}` | bus (last known unit died) |
| `player.spawned` | `{unit, group, groupId, playerName, coalition, typeName}` | bus (BIRTH with player) |
| `player.left` | `{unit, group, groupId, playerName}` | bus (PLAYER_LEAVE_UNIT, or after a player's unit.dead; a destroyed initiator is resolved through an object-id -> unit-name map filled at BIRTH) |
| `unit.ejected` / `unit.pilot_dead` | `{unit, group, coalition, groupId, player?}` (player = name while still in the slot) | bus (EJECTION / PILOT_DEAD, initiator = the aircraft; for EJECTION `target` is the seat, or the pilot without an ejection seat) |
| `unit.takeoff` / `unit.landed` | `{unit, group, coalition, place}` | bus |
| `mark.added` / `mark.changed` / `mark.removed` | `{idx, text, pos, coalition, groupId}` | bus |
| `mission.start` | `{missionId}` | init, after all modules started |
| `mission.end` | `{}` | bus (S_EVENT_MISSION_END); narrative finishes on it |
| `mission.result` | `{result}` | narrative.finish |
| `zone.entered` | `{zone, group, unit}` | narrative zone poll (player units only) |
| `beat.fired` | `{id, beat}` | narrative |
| `beat.request` | `{id, encounter}` | encounters telegraph `"beat:<id>"`; narrative triggers the beat (normal eligibility) |
| `spawner.spawned` | `{group, template, coalition, category, units, encounter, pos, cost}` | spawner |
| `encounter.spawned` | `{id, encounter, groups, kind}` | encounters |
| `encounter.telegraph` | `{id, encounter, telegraph, groups}` | encounters |
| `encounter.sam_hot` | `{id, encounter, group}` | encounters |
| `encounter.wave` | `{id, encounter, wave, of, groups}` | encounters |
| `encounter.cleared` | `{id, encounter}` | encounters |
| `encounter.cap_on_station` / `cap_rtb` / `cap_despawned` / `cap_lost` | `{id, encounter, group}` | encounters (cap) |
| `encounter.proximity` | `{id, encounter, zone, group, unit}` | encounters proximity trigger (NOT `zone.entered`) |
| `convoy.halted` / `convoy.resumed` | `{group, by?}` | ground.haltOnHit |
| `ground.stuck` | `{group}` | ground.watch |
| `director.state` | `{flight, state, intensity}` | director |
| `intel.revealed` | `{group, reason}` | intel |
| `ambient.activated` | `{site, groups, statics}` (groups/statics = number queued for spawn) | ambient |
| `ambient.deactivated` | `{site, groups, statics, reason}` (number removed; reason `"left"` \| `"manual"`) | ambient |

DCS event-order facts the bus relies on (research 2026-10-29, Hoggit + ED forum):

- Slot or coalition change: the new unit's BIRTH fires **before** the old unit's PLAYER_LEAVE_UNIT,
  so subscribers see `player.spawned` (new) then `player.left` (old). `Bus._players` is keyed by
  unit name and each entry remembers its object id; a PLAYER_LEAVE_UNIT or death for an older
  object with the same unit name (re-slot into the same slot) is ignored.
- In PLAYER_LEAVE_UNIT and death handlers the initiator may already be destroyed (`getName` fails).
  The bus falls back to `Bus._objNames` (object id `id_` -> unit name, filled at BIRTH, cleared on
  leave/death), so `Bus._players` never leaks.
- PILOT_DEAD can come **before** EJECTION (a mortally wounded player ejects), and removing a
  parachute unit can raise PILOT_DEAD for the aircraft minutes after ejection (none if the player
  re-slotted first). The Director's `LEFT_GRACE_SEC` window is deliberately short; don't lengthen it.
- The order of EJECTION / PILOT_DEAD relative to PLAYER_LEAVE_UNIT is still unknown [? cockpit test].

## DMS_CONFIG (generated by Python, consumed by Lua)

Python model: `dms_core.schemas.runtime.RuntimeConfig`, serialized as `DMS_CONFIG = {...}` in
`dms_config.lua`. Every key below is optional except `missionId`; every Lua module tolerates any
key being absent (including `DMS_CONFIG = {}`). `Range` = number or `{min, max}`.

```lua
DMS_CONFIG = {
  version = 1, seed = 12345, debug = false, missionId = "m01-first-light",
  budgets  = { maxActiveGround = 150, maxActiveAir = 16, maxActiveShip = nil, spawnsPerMin = 3 },  -- spawnsPerMin >= 1
  director = { enabled = true, peak = 70, relaxSec = {40, 90}, decayPerSec = 1.5, adapt = {min = -1, max = 1},
               peakHoldSec = 15, maxIntensity = 100, nearM = 10000, calmSec = 300,
               gain = { hit = 25, nearShot = 5, samLaunch = 15, nearKill = 8, playerDead = 40 } },
  templates = { zu23 = { country = "INSURGENTS", category = "ground",  -- ground|air|airplane|helicopter|ship
                         skill = "Average", task = nil, altM = nil,
                         units = { {type = "ZU-23 Emplacement", dx = 0, dy = 0, heading = 0,  -- heading DEGREES
                                    skill = nil, payload = nil, livery = nil} } } },
  zones = { ridge = { kind = "polygon", points = { {x = 0, y = 0}, ... } },
            town  = { kind = "circle", x = 0, y = 0, radius = 1500 } },
  pools = { aaa = { members = { {tpl = "zu23", w = 3} }, pick = {1, 2} --[[or a number]], zones = {"ridge"} } },
  encounters = {
    { id = "popup_aa", kind = "ambush_sam",            -- ambush_sam|waves|hunt|convoy|cap|pool
      pool = "hidden_aa",                              -- or template = "zu23" (+ zone/spawnZone), or group = "Convoy1" (convoy)
      trigger = { type = "proximity",                  -- proximity|beat|director|time|event|manual
                  zone = "patrol_box", radiusM = 8334, point = nil, coalition = nil, checkSec = 5,
                  beat = nil, state = nil, afterSec = nil --[[Range]], event = nil, group = nil },
      chance = 70, once = true, telegraph = "beat:popup_aa_warning",  -- "beat:<id>" | "event:<name>" | "<name>"; fires: ambush_sam when a player enters range (goes hot telegraphSec later), waves before each wave (spawns telegraphSec later), cap at each launch
      hunt = false --[[or group name]], engageRadiusM = 15000, hotChance = nil, telegraphSec = {30, 60},
      reactSec = {2, 8}, checkSec = 2, gated = true, cost = 1, maxDeferSec = 300, gateRetrySec = 15,
      huntIntervalSec = 30, huntSpeed = 8, huntRadiusM = nil, target = nil, spawnZone = nil,
      waves = nil --[[number or {min,max}]], gapSec = {120, 240},
      destination = "kirikhan_road" --[[zone id or {x,y}]], resumeAfterSec = {60, 120}, escortRadiusM = 500,
      speed = 10, action = "On Road" },
    -- kind = "cap": one air group per launch on station over zone|point (details: reference/lua-api-notes.md)
    { id = "mig_cap", kind = "cap", pool = "migs" --[[or template]], spawnZone = "north_af",
      zone = "cap_box" --[[or point = {x,y}]], engageRadiusM = 40000, targetTypes = {"Air"},
      orbit = { pattern = "Race-Track" --[[|Circle]], legM = 30000, headingDeg = nil, altM = {6000, 8000}, speed = {200, 230} },
      roe = "OPEN_FIRE", reaction = "EVADE_FIRE", radar = nil, timeOnStationSec = nil --[[Range]],
      maxSpawns = 1, replaceOnDead = true, replaceOnRtb = true, replaceDelaySec = {60, 180}, arriveM = 10000,
      stationTimeoutSec = 1200, rtbDespawnSec = 600, despawnMinPlayerM = 37000, checkSec = 10, maxDeferSec = 900 },
    -- cap launches are strictly director-gated: still refused after maxDeferSec -> dropped (logged), never forced.
    -- director gate (gated ~= false): a pool launch rolls its count first (Spawner.poolCount, once per launch,
    --   kept across retries) and asks canSpawn(cost * count, flight) before spawnPool(..., {count = count});
    --   template launches ask cost * 1. flight = the triggering unit's group (proximity) if the director tracks
    --   it, else the tracked player flight nearest the encounter anchor (spawnZone, trigger zone/point, zone,
    --   point, first pool zone), else nil (busiest flight).
  },
  beats = { --[[ see "Beats" ]] },
  voice = { ops_cleared_v1 = { file = "ops_cleared_v1.ogg" --[[optional: nil/"" = subtitle only]], text = "Dusty, Hatay Ops...", durSec = 7.5,
                               speaker = "ops_walsh", turns = nil --[[ { {speaker=, text=}, ... } ]] } },
  speakers = { ops_walsh = { callsign = "Hatay Ops", frequency = nil --[[MHz]], modulation = nil --[[0 AM|1 FM]] } },
  qualities = { intel = 0, enemy_aa = 2 },            -- campaign values at plan time; seeds `requires.qualities`
  flags = { m01_sa6_radar_destroyed = true, m01_success = true, m01_failure = false },
                                                      -- campaign flags at plan time (state/qualities.yaml `flags`)
  narrative = { minGapSec = 8, pendingTtlSec = 45, zonePollSec = 3 },
  intel = { fogOfWar = true --[[on unless false: nil = on in intel/spawner/test and `dms check`]], revealRadiusM = 5000, markRefreshSec = 15, staleSec = 120,
            removeSec = nil --[[default 3 * staleSec]], scanSec = 5, markRadiusM = 600, sensors = true,
            knownGroups = { "aaa_reyhanli_1" } --[[enemy groups shown on F10 by design (spec hidden_on_map: false);
                                                   `dms check` does not flag them]] },
  players = { coalition = 2 },
  -- Friendly base traffic around player airbases (lua/src/dms/ambient.lua). Defaults shown.
  ambient = { enabled = true, checkSec = 5, graceSec = 30, staggerSec = 3,
              departureDelaySec = 600,   -- departures/arrivals wait for the first player takeoff OR this
              maxGroups = 12, maxUnits = 24,   -- global ambient budget (statics count as units only)
              sites = {
                { id = "hatay", airbase = "Hatay" --[[DCS airbase name; nil = point only]],
                  point = {x = 0, y = 0},       -- site centre (default: airbase position)
                  coalition = 2, country = "USA",
                  activeRadiusM = 8000, despawnRadiusM = 12000,   -- despawn > active (hysteresis)
                  maxGroups = 8, maxUnits = 16,
                  avoid = { {x = 0, y = 0, radiusM = 60} },  -- player parking spots etc.: nothing spawns or parks here
                  layers = {   -- every layer optional; types are DCS type names, templates DMS template ids
                    departures = { count = 1, types = {"C-130"}, templates = nil, category = "airplane",
                                   intervalSec = {240, 480}, distanceM = 40000, altM = 1500, speed = 120 },
                    arrivals   = { count = 1, types = {"C-130"}, category = "airplane",
                                   intervalSec = {300, 600}, distanceM = 25000, altM = 1000, speed = 110 },
                    ground     = { count = 3, types = {"M978 HEMTT Tanker"}, radiusM = 500, speed = 4 },
                    helo       = { count = 1, types = {"UH-60A"}, radiusM = 3000, altM = 150, speed = 45 },
                    statics    = { count = 3, types = {"FARP Fuel Depot"}, category = nil --[[static category]],
                                   radiusM = 400 },
                  } } } },
  test = { enabled = true, playerProxy = "Dustoff 1" --[[AI group treated as the player]], minutes = 40,
           checks = { {kind = "booted", name = nil, deadlineSec = nil}, {kind = "spawns", min = 1},
                      {kind = "beats_in_order", beats = {"a", "b"}}, {kind = "beat", id = "a"},
                      {kind = "comms", min = 2}, {kind = "encounter", id = "popup_aa"},
                      {kind = "convoy_halt"}, {kind = "outcome", result = "success"},
                      {kind = "ambient_cycle", site = nil} } },
}
```

- `ambient` (see `DMS.Ambient`): a site activates when a player unit of its `coalition` (incl. the
  DMS.Test proxy) is within `activeRadiusM` of `point`, spawning its layers staggered by
  `staggerSec`; it deactivates (everything it owns destroyed) once no such player has been within
  `despawnRadiusM` for `graceSec`, and re-activates on return. Layer semantics: `departures` park
  uncontrolled on free airbase parking (`Airbase.getParking(true)`, spots inside `avoid` skipped),
  get a `Start` command after the runway gate, fly `distanceM` out and are destroyed beyond
  `despawnRadiusM + distanceM/2`, then replaced after `intervalSec`; `arrivals` spawn airborne
  `distanceM` out and land (route `Land`), destroyed ~90 s after `unit.landed`; `ground` vehicles
  loop between parking/apron points at `speed` m/s; `helo` orbits the site at `radiusM`/`altM`;
  `statics` stay while the site is active. All ambient groups get SetImmortal, SetInvisible and
  weapons hold; `count` is per layer, and `maxGroups`/`maxUnits` (site and global) are hard caps.
  Mission spec: `ambient: {enabled: true, density: off|low|medium|high}` (default enabled, low);
  the planner generates sites for the player flights' departure and recovery airbases.
  `dms check` validates every ambient `types` entry against the unit catalog (`ambient_bad_type`)
  and every `templates` entry against `templates` (`ambient_bad_template`).
- `test` is only present in `dms build --test` builds (headless DCS runs): `dms_test.lua`, loaded
  between `dms_config.lua` and `dms.lua`, sets `DMS_CONFIG.test` and `debug = true`; read by
  `lua/src/dms/test.lua`. Python model: `RuntimeConfig.test` (`TestSettings`, `TestCheck`).
  Mission spec: optional `test: {require_result: success|failure}` (headless test hints; default
  unset = any mission end passes `outcome_end`, since an AI proxy cannot attack).
- Spec-level `convoy` encounters (`mission-spec.yaml` `dynamic.encounters`, which only name a
  pool) compile to `spawnZone` = the pool's first area and `destination` = the pool's last area
  (pool with 2+ areas), else the proximity trigger area when it differs, else the nearest
  `terrain: road` area outside the spawn area, else the nearest other area outside it. The runtime
  spawns the convoy from the pool there and routes it to `destination` (`speed`/`action` defaults).

### Beats (`beats.yaml` -> `DMS_CONFIG.beats`, compiled verbatim)

```lua
{ id = "patrol_complete", guaranteed = true, priority = 80, once = true, cooldownSec = 0, delaySec = 0,
  when = { event = "zone.entered", zone = "gate_west", playersOnly = true },
  requires = { flags = {"on_station"}, flagsNot = {"patrol_complete"},
               qualities = { {quality = "trust", op = ">=", value = 2} },
               beatsFired = {}, beatsNotFired = {}, chance = 100 },
  speaker = "ops_walsh", lines = {"ops_rtb_v1", "ops_rtb_v2"}, text = "Dusty, Ops. Good picture. RTB.",
  mark = { type = "text", at = "zone:patrol_box", text = "PATROL BOX", radiusM = nil, coalition = nil },
  effects = { setFlag = "patrol_complete" --[[or list]], flagValue = nil, clearFlag = nil --[[or list]],
              outcome = { patrol_complete = true }, startEncounter = nil --[[or list]], spawnPool = nil,
              qualityDeltas = { trust = 1 }, endMission = nil --[["success"|"failure"]],
              speak = nil --[[ {speaker=, lines={...}, text=} overrides the beat's speaker/lines/text ]],
              mark = nil --[[ same shape as beat mark; used when the beat has no mark ]] } }
```

**when** - canonical form is `event` plus filters:
`timer` (`afterSec` since start) | `flag` (`flag`, optional `value`: number => `==`, `">=2"`, bool) |
`zone.entered` (`zone`) | `beat.fired` (`beat`) | `encounter.spawned` (`encounter`) |
`director.state` (`state`, optional `flight`) | `mission.start` | any event in the table above.
`timer` and `flag` are state triggers (edge: fire when the condition becomes true); the rest are
event triggers. Optional `delaySec` on `when` (used only when the beat-level `delaySec` is 0).
Filter semantics:
- `group` / `groupPrefix`: subject group = `payload.group` or `targetGroup` or `initiatorGroup`;
  a prefix matches the name or the name with a leading `DMS_` stripped (so `hidden_aa` matches the
  runtime spawn `DMS_hidden_aa_1`).
- `unit` / `unitPrefix`: `payload.unit` or `target` or `initiator`.
- `coalition` (0/1/2): `payload.coalition` or `targetCoalition`. `typeName`: `payload.typeName`.
- `playersOnly`: the subject unit (unit.hit -> target, unit.shot -> initiator, else unit) is a
  player; always true for `player.spawned`.
- `beat`: `payload.beat` or `payload.id`; `encounter`: `payload.encounter` or `payload.id`;
  `zone` / `state` / `flight`: equal; any other key: `payload[key] == value`.
- `unit.landed` / `unit.takeoff` only: `zone` is a **position** filter (the unit's position at the
  event, via `Unit.getByName(payload.unit):getPoint()`, is inside the config zone, else the ME
  trigger zone); `place` (alias `airbase`) matches `payload.place` (airbase/FARP/ship name)
  case-insensitively. Both may be set (both must hold). A non-matching landing is logged at debug
  (`[DMS][Narrative] landed ... not in zone ...`). So "land at X" is one beat:
  `when = { event = "unit.landed", zone = "fob_pad", playersOnly = true }`.
- Aliases (Lua and Python normaliser): no `event` with `afterSec`/`timer` -> timer, `flag` -> flag,
  `zone` -> zone.entered, `director`/`directorState` -> director.state, `beat` -> beat.fired.

**requires** - all must hold: `flags`, `flagsNot`, `qualities` (list of `{quality, op, value}`),
`beatsFired`, `beatsNotFired`, `chance` (rolled once when the beat is triggered). Aliases: `flags` as
a map `{f = true|false}`, `flagsSet`, `notFlags` / `flagsNotSet`, `qualities` as a map
`{q = 2 (>=) | ">=2" | {min=, max=} | {op=, value=}}`.
Flag lookups (`flags`, `flagsNot`, `when: {flag=}`) see mission flags first (set by `setFlag` /
`clearFlag` or an ME trigger), then **campaign flags** (`DMS_CONFIG.flags`, e.g.
`requires = { flags = { m01_sa6_radar_destroyed = true, m01_player_lost = false } }`), else not set.
A mission-set value (including a cleared 0) wins over the campaign value. Campaign flags are never
echoed in the outcome `flags` (those are this flight's flags only). Accessors:
`DMS.Narrative.getCampaignFlag(name) -> bool`, `DMS.Narrative.campaignFlags() -> {name = bool}`.

**effects** - `qualityDeltas` are applied live (later beats in the same mission see them) and
reported cumulatively in the outcome; the debriefer applies them to `state/qualities.yaml`.
`endMission` finishes the narrative (writes the `end` outcome line). Aliases: `finish` / `end` /
`result` (victory -> success, defeat -> failure), `qualities` -> `qualityDeltas`.
`speak` (`{speaker, lines, text}`, each optional) replaces the beat's own speaker / lines / text
for the radio call; `mark` (beat-mark shape) is dropped when the beat has no top-level `mark`.

**mark** - `at` is `group:<name>` (exact, else first group whose name or `DMS_`-stripped name
starts with it), `unit:<name>`, `zone:<id>` or `point:<x>,<y>` (DCS map meters). `type`
`circle` draws a circle (`radiusM`, default zone radius / 1000 m) plus label; `text` / `point` draw
the label only. Aliases: a bare string (= `at`), `{x, y}`, `radius`.

**guaranteed** - spine beats: chance ignored; once queued, a guaranteed beat is exempt from the
pending TTL while its requires still hold (it can be delayed by traffic, never lost to it); Comms
never drops its line from a full queue. `guaranteed` is also a design-time promise checked by
`dms check`: the beat must be reachable in every playthrough.

**selection** - when a beat's `when` occurs, its `requires` must already hold (else it is not
queued) and `chance` is rolled; queued beats wait in a pending queue (TTL
`narrative.pendingTtlSec`, `delaySec` honoured) and `requires` are re-checked when they fire. Among
ready beats the highest priority fires (ties random), at most one radio beat per
`narrative.minGapSec`. Silent beats (no speaker, lines or text) bypass the gap and fire at once.
Chains are expressed with `when: {event: beat.fired, beat: <id>}`, not with same-event flags.

### Optional plugins (`lua/plugins/`, `dms_gen.plugins`, ADR 0003/0013)

Opt-in per mission with `MissionSpec.plugins: list["mist" | "skynet" | "moose"]` (default `[]`,
no duplicates). The planner expands dependencies and adapters (`skynet` -> `mist`, `skynet`,
`skynet_adapter`) and emits repo-relative script resources in a fixed order, each its own
`DO SCRIPT FILE` action in the "DMS: load scripts" trigger:

`mist` -> `moose` -> `skynet` -> (explicit `plan_mission(plugins=[paths])`) -> `dms_config.lua`
(-> `dms_test.lua`) -> `dms.lua` -> adapters.

Pins (tag, URL, sha256) live in `dms_gen.plugins.PLUGINS` and `lua/plugins/PINS.md`; files are
vendored as LF text (not LFS) under `lua/plugins/<name>/<version>/`. Current: MIST 4.5.126,
MOOSE 2.9.19 (`Moose_.lua`), Skynet-IADS 3.3.0 (`skynet-iads-compiled.lua`).

Adapters (`lua/plugins/adapters/*.lua`) are DMS-owned glue, not core modules: they load after
`dms.lua`, use only `DMS.Log/Clock/Bus/safeCall`, and no-op with one log line when their plugin
(or DMS) is absent. The core never references a plugin global.

```lua
-- lua/plugins/adapters/skynet_adapter.lua  (log prefix "SkynetAdapter")
DMS_SKYNET = { enabled = true, prefixes = { "DMS_" }, coalition = nil, name = "DMS IADS",
               activateDelaySec = 2, radioMenu = false }   -- optional global, all keys optional
--   coalition "red"|"blue"; nil -> the enemy of DMS_CONFIG.players.coalition (red when unset)
DMS.SkynetAdapter.iads            -- the SkynetIADS instance (nil when skipped)
DMS.SkynetAdapter.sites / .ewrs   -- group / unit names added
DMS.SkynetAdapter.active          -- true after iads:activate() ran (DMS.Clock.after(activateDelaySec))
-- At load: groups of that coalition whose name starts with a prefix and contain a unit type from
-- Skynet's samTypesDB join as SAM sites; units with the EWR attribute join as EW radars.
-- Later: every DMS.Bus "spawner.spawned" with a matching group name is considered the same way,
-- DMS.Clock.after(1.5) after the event (controller not ready on a fresh group).
-- Groups of an `ambush_sam` encounter (spawner.spawned.encounter, or DMS.Registry meta.encounter
-- for existing groups, whose DMS.Encounters.get(id).def.kind is ambush_sam) are skipped and logged:
-- the encounter owns their emission control.
```

### `dms check` (dms_gen.check.check_miz)

Structural checks on a built `.miz` (lupa round-trip, never pydcs). Errors fail the check:
- ids/names unique, at least one Client/Player slot (warning in test builds), units on the map;
- `mapResource` files present; compiled trigger strings present; `DO SCRIPT FILE` order is
  plugins -> `dms_config.lua` (-> `dms_test.lua`) -> `dms.lua` (`script_order`, `test_script_order`);
- optional plugins (recognised by file name from `dms_gen.plugins.PLUGINS`): a plugin after
  `dms_config.lua`/`dms.lua` or an adapter before `dms.lua` is `plugin_order` (error); a missing
  prerequisite is `plugin_dependency` (error; warning for an adapter, which no-ops); bytes that
  differ from the pinned sha256 are `plugin_unpinned` (warning); `plugins` (info) lists them;
- `dms_config.lua` evaluates and validates against `RuntimeConfig` (`config_schema`; Lua camelCase
  field names map back to snake_case, user keys untouched); required keys present;
- references: pool members/zones exist; each encounter has a source (`pool` that exists, or
  `template` that exists, or `group`) (`config_bad_pool` / `config_bad_template` /
  `config_no_source`); trigger zones/beats exist; beat lines are in `voice`; voice files embedded;
- **beat reachability**: a beat's trigger must be able to fire. A `zone` must be a config zone or
  an ME trigger zone; `group`/`groupPrefix` an ME group or a possible runtime spawn
  (`DMS_<poolOrTemplate>_<n>`); `unit` an ME unit or a runtime spawn; `event` a known event;
  `encounter` a config encounter; `beat` a reachable beat; `flag` (event or `requires.flags`)
  set by a reachable beat's `setFlag`, an ME trigger action or a true `DMS_CONFIG.flags` campaign
  flag; `requires.beatsFired` reachable
  beats; `director.state` needs the director enabled. Unreachable `guaranteed` beats are errors
  (`guaranteed_unreachable`), others warnings (`beat_unreachable`). A beat that is reachable
  once missing **campaign flags** arrive is info (`beat_campaign_gated`, any severity of beat): a
  flag `<mNN>_<fact>` (outcomes `derive_flags` naming) whose `mNN` is an earlier mission (arc
  play order when `arc.yaml` is found above the .miz, else any other `mNN` key) that has no
  flags at all in `DMS_CONFIG.flags` yet (not flown/debriefed). Once that mission's flags are
  present, a still-missing one is a real `beat_unreachable`/`guaranteed_unreachable`;
- Lua 5.1 syntax of every embedded `.lua`; fog of war on -> enemy groups hidden (warning).

### Outcome lines

`[DMS.OUTCOME] {json}` in dcs.log, written on every outcome change (`kind = "update"`) and once
when the mission ends (`kind = "end"`, from `endMission`, `mission.end` or `DMS.Narrative.finish`):

```json
{"missionId": "m01-first-light", "kind": "end", "t": 1834.5, "result": "success",
 "outcome": {"patrol_complete": true, "landed": true}, "qualityDeltas": {"trust": 1},
 "qualities": {"intel": 0, "trust": 1}, "beats": ["mission_start", "..."], "flags": {"landed": true}}
```

Parsed by `dms_core.schemas.outcome.parse_dcs_log` into `MissionOutcome` (`outcome` -> `outcomes`,
`t` -> `time`, `event` -> `kind` for older lines).

### Debrief (`dms_core.outcomes`, `dms debrief`)

Deterministic dcs.log -> campaign state. No schema changes: debrief metadata lives in
`MissionOutcome.extra`.

- **Logs searched** (no `--log`): `<home>/Saved Games/DCS/Logs/dcs.log` and
  `.../DCS.openbeta/Logs/dcs.log`, newest mtime first, each followed by its rotated `dcs.log.old`.
  `--log PATH` (file or Logs dir) searches PATH then its sibling `.old`. First file with a matching
  session wins.
- **Sessions**: a new session starts at each `=== Log opened` line, at each Init banner
  `[DMS][Init] DMS <ver> started: mission=<id> ...`, and when an outcome line for the same mission
  has a smaller `t` than the previous one (restart without a banner). The **latest** session for the
  mission wins. Mission match: exact id, else the same `mNN` prefix (`m01` matches `m01-first-light`).
- **Issues**: `[DMS]` lines at WARNING/ERROR level (or `[DMS][safeCall]`) in that session go to
  `extra.log_warnings` / `extra.log_errors`. Malformed `[DMS.OUTCOME]` JSON is skipped and counted
  (`extra.malformed_lines`), never fatal. No outcome line for the mission -> error (exit 1).
- **state/outcomes/<mNN>.yaml**: merged `MissionOutcome` with `kind: summary`; `extra` holds
  `source: dcs_log`, `log_file`, `session_start` (log timestamp), `session_hash`, `ended` (an `end` line exists),
  `beats_fired`, `quality_changes [{quality, from, to, delta, reason}]`, `flags_set`,
  `next_mission`, `next_reason`, log issues. `mNN` = first `-` segment of the mission id.
- **state/qualities.yaml** (pure `apply_outcome(state, outcome, arc)`): `qualityDeltas` (cumulative,
  last record wins) are rounded to int, added, and clamped to the arc `QualityDef` min/max; a quality
  missing from `values` starts at its `initial`; deltas for qualities the arc does not declare are
  skipped with a warning. Flags: each outcome key becomes `<mNN>_<key>` (bool as-is, number `> 0`,
  string `true`), plus `<mNN>_<result>`; other result flags of the same mission
  (`success|failure|partial|aborted|ended`) are set false. `outcomes[<mission id>]` = outcome
  facts, `updated_after` = mission id, `next_mission` = branch choice.
- **Arc `quality_effects`** (v0.7, on by default, `--no-arc-effects` turns it off): each value is
  split on `;` into clauses; parentheticals (`(min 0)`) are dropped (a warning when the dropped
  text contains `min` / `max` / `only` / `or` / `and`, i.e. a limit or condition the debriefer must
  judge by hand). A clause applies when it is
  `<+N|-N> [more] if <cond>` or `set to <N> if <cond>`; `<cond>` = terms joined by `and` / `or`
  (`and` binds tighter), a term = `[not] <outcome_key>` (truthy: bool true, number `> 0`, non-empty
  string; a missing key is false) or `<outcome_key> <op> <number>` (`>= <= > < == !=`; bool = 0/1).
  `and` / `or` / `not` are reserved, never keys. Keys are this flight's merged `outcome` keys plus
  `result` (the end result string), `success` and `failure` (`result == ...`) when the log has a
  result. Every condition key absent from those facts is a warning (it still counts as false / 0).
  **Unended flights**: if the flight did not end (`extra.ended` false or no `result`), arc effects
  are skipped with a warning (beat `qualityDeltas` still apply) unless `--force-arc-effects`. Clauses are applied in order, then clamped to the
  `QualityDef` min/max; each applied clause is a `quality_changes` entry with reason
  `arc quality_effects: "<clause>"`. Anything else (e.g. `-1 if only one of them`) is not applied
  and is listed in `warnings` for the debriefer skill. If the beats already reported a non-zero
  `qualityDeltas` for that quality, its arc effects are skipped (warning) so nothing counts twice.
- **continuity.md**: unless `--dry-run` / `--no-continuity`, `dms debrief` appends one factual entry
  `### <date> — dms debrief — <mission id> flown (<result|unknown>)` followed by a marker line
  `<!-- dms-debrief: <mNN> <session_hash> -->` (result, outcome facts, quality changes with reasons,
  flags, unapplied effects, log errors, next mission). An entry for the same flight (same marker,
  or a legacy entry with the same heading mission + `session <session_start>`) is replaced in place,
  never duplicated. The file's line endings (LF or CRLF) are kept. The debriefer skill adds
  the narrative entry (canon, threads, player account) after it.
- **Next flight reflects the outcome** through `state/qualities.yaml`: `dms plan`/`run` of a mission
  in `campaigns/<slug>/missions/` copy its `values` into `DMS_CONFIG.qualities`, which seeds beat
  `requires.qualities` (e.g. `intel >= 2` -> the intel mark beat, `sam_threat >= 2` -> the pop-up SAM
  encounter) and `DMS.Narrative.getQuality`. Its `flags` are copied likewise into
  `DMS_CONFIG.flags` (campaign flags for beat `requires.flags`, see "Beats"; `dms check` counts the
  ones that are true as set), and both seed the conditional briefing blocks below.
- **Conditional briefing** (`dms_gen.builder.conditional`, applied by `dms build` to `briefing.md`
  and `kneeboard.md`): a directive is a whole line `<!-- if <cond> -->`, `<!-- elif <cond> -->`,
  `<!-- else -->` or `<!-- endif -->` (blocks nest). `<cond>` is the arc `quality_effects`
  condition grammar (`and` / `or` / `not`, `<key> <op> <number>`), evaluated against the plan's
  `DMS_CONFIG.qualities` and `DMS_CONFIG.flags` (campaign state at plan time; a flag and a quality
  with the same name: the quality wins). Unknown keys are false / 0. Only the taken branch's lines
  are kept; directive lines are removed. An unparseable condition or unbalanced block fails the
  build (`ValueError`). Other HTML comments are left alone.
- **Next mission**: the flown mission's `branches` in order; `when` (`Requires`) is checked against
  campaign `flags`/`values` (`beats_fired`/`beats_not_fired` against this flight's beats; `chance`
  rolled with `--seed`). First match wins, else the next non-optional arc mission, else none (end).
- **Re-debrief guard**: `extra.session_hash` = first 16 hex of the SHA-256 of the session's
  records for the mission (canonical JSON). If `state/outcomes/<mNN>.yaml` already records the same
  `session_start` + `session_hash` (the log file path is not compared, so `dcs.log` -> `dcs.log.old`
  rotation or another spelling of the path is still caught; files without `session_hash` fall back
  to `session_start`), `dms debrief` refuses (exit 1) unless `--force`. With `--force` on the same
  flight, the previous file's `quality_changes` are rolled back first (each `to - from` subtracted,
  newest first, clamped) and its `flags_set` keys removed, then the flight is re-applied; its
  continuity entry is replaced.
- **Write order**: every file is written atomically (temp file + rename) in the order
  continuity.md -> state/qualities.yaml -> state/outcomes/<mNN>.yaml. The outcome file is the guard,
  so it lands last: a failure before it leaves the flight un-guarded and a rerun redoes it (the
  continuity entry is replaced, not duplicated).

## AI flights and watch missions (v0.9)

A **watch mission** has no client slots. The viewer is a spectator (F2/F7/F10/F11) and every
actor is AI. **AI flights** are aircraft that follow a list of orders. They work in any mission; a
watch mission just has nothing else in the air. A beat can carry a **camera cue** that tells the
viewer where to look, because a mission script cannot move the camera.

Mission spec (`mission-spec.yaml`):

```yaml
watch:                        # optional; when set, this is a spectator mission and player_flights may be empty
  focus: dusty                # id of the flight that stands in for "the player" (narrative
                              # zone.entered, director, ambient sites, comms listener position)
  cues: true                  # show beat `cue` text (default true)
flights:                      # optional, any mission
  - id: dustoff               # Ident. The planner picks the DCS group name; read it from
                              #   plan.json or DMS_CONFIG.flights[].group
    callsign: "Dustoff 3-1"
    aircraft: UH-60A          # DCS type (checked against the catalog)
    count: 1                  # 1-4
    coalition: blue           # blue | red
    country: USA
    skill: High               # Average|Good|High|Excellent
    start_area: hatay         # area id; an airbase area with parking_hot/runway starts there, else airborne
    start_type: air           # air | parking_hot | runway
    start_alt_ft: 500         # air start altitude (AGL for helicopters, MSL for planes)
    start_speed_kts: 100
    heading_toward: lz_ridge  # air start: initial heading toward this area (optional)
    loadout: medevac          # loadout keyword (same as player flights); omit for the default
    speaker: dustoff_pilot    # bible character id for comms; frequency/modulation as for Support
    frequency_mhz: 40.5
    modulation: FM
    immortal: false
    invisible: false
    orders:                   # run in order; each starts when the previous one is done
      - {do: fly, to: gate_west, alt_ft: 300, speed_kts: 110}
      - {do: hold, at: gate_west, until: {beat: lz_cold}, max_min: 6}
      - {do: land, at: lz_ridge, ground_min: 1.5, pickup: kestrel}
      - {do: fly, to: hatay}
      - {do: land, at: hatay}
```

Order fields (all optional except `do`):

- `do`, one of:
  - `fly`: route to area `to`.
  - `hold`: orbit area `at`.
  - `land`: land in area `at` (an airbase area means that airfield).
  - `escort`: follow flight `flight` and engage threats to it within `radius_nm`.
  - `engage`: orbit `at` and attack `targets` within `radius_nm`.
  - `strike`: attack a target in area `at` in up to 3 passes, then the next order. The target is
    the first live group whose name starts with `group`, a threat/pool id (`DMS_` prefix allowed).
    Each aircraft of the flight gets a different live unit of that group per pass, and survivors
    are re-attacked while the flight has ammo of the `weapon` kind. With no `group`, or no live
    match, it is a single Bombing run on the area centre.
  - `rtb`: fly to the start airbase and land.
- `alt_ft`: AGL for helicopters, MSL for planes.
- `speed_kts`.
- `radius_nm`: default 1.5.
- `targets`: a list of `ground` | `armor` | `aaa` | `infantry` | `air`; default `[ground]`.
- `weapon` (strike): `guided_bomb` | `bomb` | `missile` | `rockets` | `gun` | `any`; default
  `guided_bomb`.
- `ground_min` (land): time on the ground before the next order; default 1.
- `pickup` (land): support/flight id of a friendly ground group that boards. Its units are
  removed when the ground time ends, if they are within 300 m.
- `until`: a beat `when` form, such as `{beat: x}`, `{flag: x}` or
  `{event: flight.lifted, flight: dustoff}`; for hold/escort/engage.
- `max_min`: the order ends after this many minutes even if `until` never happens. Default 15
  for hold/escort/engage and 6 for strike.
- `when`: start condition, in the same `when` form. Default: immediately after the previous
  order.

`ground_min` and `max_min` take a number or `[min, max]`.

Beats gain an optional `cue: "<text>"`. When the mission has `watch` with `cues: true`, it is
shown to everyone as `CAMERA: <text>` for 10 s; otherwise it is ignored. Voice lines gain
`voiced: false`, meaning subtitle only: `dms voice` never sends the line to ElevenLabs, and
`--dry-run` counts only voiced characters.

`DMS_CONFIG` (meters, seconds, m/s; the Lua side is `lua/src/dms/flights.lua`):

```lua
DMS_CONFIG.watch = { enabled = true, focus = "Dusty_dusty" --[[DCS group name]], cues = true }
DMS_CONFIG.flights = {
  { id = "dustoff", group = "Dustoff_dustoff", category = "helicopter", coalition = 2,
    speaker = "dustoff_pilot", startAirbase = "Hatay" --[[nil if airborne start]],
    orders = {
      { kind = "fly", to = "gate_west", altM = 90, altType = "RADIO", speedMps = 56.6 },
      { kind = "hold", at = "gate_west", until = { event = "beat.fired", beat = "lz_cold" }, maxSec = 360 },
      { kind = "land", at = "lz_ridge", groundSec = 90, pickup = "Kestrel_kestrel" --[[DCS group name]] },
      { kind = "escort", flight = "dustoff", radiusM = 2778, targets = { "Ground Units" } },
      { kind = "engage", at = "lz_ridge", radiusM = 2778, targets = { "Ground Units" }, altM = 90,
        altType = "RADIO", until = { event = "flight.lifted", flight = "dustoff" }, maxSec = 900 },
      { kind = "strike", at = "canal_east", group = "technicals", weapon = "guided_bomb",
        altM = 4572, altType = "BARO", maxSec = 360 },
      { kind = "rtb" },
    } } }
```

`targets` are DCS attribute names: `ground` -> "Ground Units", `armor` -> "Armored vehicles",
`aaa` -> "Air Defence", `infantry` -> "Infantry", `air` -> "Air". `weapon` maps to the DCS
`weaponType` flags: `guided_bomb` = GuidedBomb, `bomb` = AnyBomb, `missile` = AnyASM, `rockets` =
Rockets, `gun` = Cannons, `any` = Auto. `to` and `at` are zone ids in `DMS_CONFIG.zones`, or an
airbase name for `land`/`rtb`. Range values (`{min,max}`) roll once per order via
`DMS.Rng.range`.

```lua
-- flights.lua: DMS.Flights (START_ORDER after Ambient; inert without DMS_CONFIG.flights)
DMS.Flights.start() stop()
DMS.Flights.state(id) -> { index, kind, status = "running"|"done"|"lost", since } | nil
DMS.Flights.advance(id, why) -> bool       -- end the current order now
DMS.Flights.groupName(id) -> string|nil   ids() -> sorted ids
-- Watch / stand-in player (core.lua)
DMS.standInGroups() -> { groupName... }   -- DMS.Test proxy group (test runs), else watch.focus, else {}
DMS.isWatch() -> bool                     -- DMS_CONFIG.watch.enabled
```

Order semantics:

- `fly`: a Mission task to the zone centre at altM and speed. Done within max(300 m, zone
  radius).
- `hold`: Orbit (Circle) over the zone. Done on `until` or `maxSec`.
- `land`: a `Land` task at the zone centre for helicopters; planes land at the airbase. A
  helicopter more than 2 km from the point first gets a `fly`-style route there at cruise (the
  order's `altM`/`speedMps`, else the latest earlier order's, else the defaults), and the `Land`
  task when it is within 2 km, so the transit is not flown at the Land task's approach speed. Done
  after `groundSec` on the ground (S_EVENT_LAND for the lead, or AGL < 3 m and speed < 2 m/s);
  then the group lifts off. `flight.lifted` is emitted when the ground time ends and the next order
  is issued (not on the actual liftoff). The last order keeps the group on the ground
  (`durationFlag = false`).
- `escort`: an Escort task on the other flight's group; its `engagementDistMax` (radiusM) and
  `targetTypes` do the engaging (a fixed EngageTargetsInZone cannot follow a moving group). Done on
  `until`, `maxSec`, or when the escorted group is gone.
- `engage`: Orbit plus EngageTargetsInZone.
- `strike` with a live target group: passes. Each pass is one group task, a `ComboTask` of one
  `AttackUnit` per aircraft (as many as the flight has live aircraft, on the target group's live
  units in unit order, each a different unit), with `groupAttack = false`, `attackQtyLimit =
  true`, `attackQty = 1`, weaponType per `weapon`, `expend = "Two"` (`"One"` when the target
  group has no more live units than the flight has aircraft), and the attack altitude when the
  order has `altM`. A pass is over 45 s after its last release (`unit.shot`) or when all of its
  targeted units are dead. Then, if target units survive, it is re-tasked on the survivors
  (at most 3 passes), as long as a flight unit still carries ammo of the `weapon` kind
  (`Unit.getAmmo`, best effort: AAMs and SAMs never count; no answer from DCS counts as ammo).
  Done when the target group is dead (`target dead`), after pass 3 (`passes exhausted`), with no
  ammo left (`no ammo`), or at `maxSec`. Every pass logs
  `[DMS][Flights] flight '<id>' strike pass <n>: targets <unit>,<unit>`. (DCS cannot task the
  units of an AI aircraft group separately, so the split is per AttackUnit in one ComboTask
  [? headless check that each aircraft takes a different AttackUnit].)
- `strike` with no live target group: a `Bombing` task on the area centre with expend "All".
  Done 60 s after the first release, or at `maxSec`. Both forms emit `flight.weapon` per
  release.
- `rtb`: route to startAirbase with a Land waypoint (airborne starts use the nearest friendly
  airbase).

Python compile rules (`packages/dms-gen/src/dms_gen/planner/flights.py`):

- DCS group name: `<CallsignWord>_<id>` ("Dustoff 3-1" + `dustoff` -> `Dustoff_dustoff`), made
  unique by the planner. `DMS_CONFIG.watch.focus` and `pickup` carry DCS group names (a `pickup`
  support id resolves to that support's ground group, e.g. `kestrel_1`).
- `targets` are mapped to DCS attribute names in Python; `weapon` stays a **keyword** and Lua maps
  it to `weaponType`. Defaults are filled in Python: `altM`/`altType`/`speedMps` for
  fly/hold/escort/engage/strike (order value, else the flight's start alt/speed, else 500 ft AGL /
  100 kt helicopters, 15000 ft MSL / 350 kt planes), `radiusM` 2778 and `targets {"Ground Units"}`
  for escort/engage, `maxSec` (900 / 360), `groundSec` 60, `weapon "guided_bomb"`.
- A plane's `land` at an airbase area compiles `at` to the airbase name; helicopters get the zone id.
- The .miz group is a plain route flight (start point + first leg toward `heading_toward` or the
  first order's area), never late-activated or uncontrolled. Its DCS main task comes from the
  orders (strike: Ground Attack, engage: CAS, escort: Escort, else the type default).
  `immortal`/`invisible` are SetImmortal/SetInvisible commands on the first waypoint in the .miz,
  not `DMS_CONFIG` keys. Helicopter air starts use a RADIO start point (alt = AGL feet).
- AI flights with a `speaker` or `frequency_mhz` join the comms plan like Support assets.

A dead group ends its orders (`flight.lost`). Every order start, end and skip logs
`[DMS][Flights] ...` (info).

Speed telemetry: when `DMS.Log.isDebug()` (test and debug builds) or
`DMS_CONFIG.flightsTelemetry == true`, every 10 s each running flight's lead logs (info)
`[DMS][Flights] TELEM flight=<id> order=<i>/<kind> spd=<kt> agl=<ft> msl=<ft> dist=<m|->`, where
`dist` is the 2D distance to the order's target: the strike target group's or escorted group's
lead, else the land area or order zone centre, else `-`. `flightsTelemetry` is a Lua-side key
only (the Python side does not emit it yet).

Events (add these to the table above):

| Event | Payload | When |
|---|---|---|
| `flight.order` | `{flight, group, index, kind}` | an order started |
| `flight.arrived` | `{flight, group, zone}` | a `fly` order is done |
| `flight.landed` / `flight.lifted` | `{flight, group, zone}` | |
| `flight.pickup` | `{flight, group, pickup, units}` | |
| `flight.weapon` | `{flight, group, weapon, target}` | a unit of a striking flight released a weapon (unit.shot) |
| `flight.done` | `{flight, group}` | the last order is done |
| `flight.lost` | `{flight, group, reason}` | |

The beat filters `flight` and `zone` match these payload keys (generic rule).

Watch mode in the other modules:

- Comms text and sound go to **all** players (`outText` / `outSound`), even for a speaker with a
  frequency: a spectator has no radio, so watch missions never use radioTransmission.
- Intel marks use coalition -1.
- Narrative `zone.entered`, the Director and Ambient treat `standInGroups()` units as players,
  exactly as they treat the test proxy.
- Outside a test run, `DMS.Flights` registers the focus group's units in `DMS.Bus._players` and
  emits `player.spawned {..., playerName = "WATCH", standIn = true}` (as `DMS.Test` does for its
  proxy), so every player-dependent module sees it. A beat `cue` is shown via
  `DMS.Comms.text(msg, {all = true, durSec = 10})`.

`dms build --test` on a watch mission keeps the AI flights and uses the focus flight as
`test.playerProxy`, with no proxy replacement and no loiter. The usual checks run, plus
`flight_orders`: every flight reached `flight.done` or `flight.lost` by the end (INFO for
`lost`).

## Python schemas (packages/dms-core/src/dms_core/schemas/)

| Module | Models | Written by |
|---|---|---|
| `story.py` | `StoryBible`, `Faction`, `Character`, `VoiceProfile`, `TimelineEvent`, `Source` | story-writer skill |
| `campaign.py` | `CampaignArc`, `Act`, `ArcMission`, `Branch`, `QualityDef`, `Qualities` (`next_mission` set by the debriefer) | campaign-planner / debriefer |
| `mission.py` | `MissionSpec` (LLM-facing, declarative: theater, era, date, start_time, weather_preset, player_flights, mission_type, objectives, threats, support, dynamic) | mission-designer skill |
| `beats.py` | `BeatSheet` (beats.yaml), `Beat`, `BeatTrigger`, `BeatEffects`, `BeatMark` | mission-designer skill |
| `voice.py` | `VoiceLine` (optional multi-speaker `turns` of `DialogueTurn` for Text-to-Dialogue), `VoiceLineSet` (lines.yaml) | mission-designer / voice-director |
| `plan.py` | `BuildPlan` (exact: positions x/y, unit types, payload CLSIDs, frequencies, group names, trigger list, resources; `blue_countries` / `red_countries` / `neutral_countries` coalition membership) | `dms plan` |
| `runtime.py` | `RuntimeConfig` (= DMS_CONFIG above) | `dms plan` |
| `outcome.py` | `MissionOutcome` (parsed `[DMS.OUTCOME]` lines; `parse_dcs_log`, `summarize_outcomes`) | `dms outcome` / debriefer |
| `validation.py` | `Issue` (path, problem, suggestions, severity `error`/`warning`/`info`, optional lint `code` + `hint`); `validate_mission_bundle` cross-file checks | `dms validate` |

**Mission-quality lint** (`dms_core.lint`, the guide's
[§6](reference/mission-design-guide.md#6-lint-list-quality-checks-for-dms-validate)): design
problems that make a mission bad, not invalid. `lint_mission(spec, beats, lines, bible, docs)`
(arc rules only for this mission's arc entry), `lint_mission_dir(dir, ...)` (reads the optional
`briefing.md`, `kneeboard.md`, `voice/manifest.json` durations, `out/plan.json` and the nearest
`arc.yaml` + sibling missions) and `lint_arc(arc, campaign_dir)` (campaign-wide). Each finding is
an `Issue` with `code` and `hint`, and `problem` reads `"[<code>] <message>. Fix: <hint>"` (the
CLI/MCP finding shape keeps only path/problem/suggestions/severity, so the code travels in the
text). Line durations come from the manifest, else words / 2.5 per s (v3 tags stripped). `dms
validate` and MCP `validate` run it by default (`--no-lint` / `lint=false`); `--strict` /
`strict=true` fails on warnings. `dms run`/`build` do not lint. `RULES` in the module is the
source of truth:

| code | sev | fires when |
|---|---|---|
| `spine_no_fallback` | warn | a guaranteed beat on `group.dead`/`unit.dead`/`unit.landed`/`encounter.cleared`/`flag` has no other path: no sibling setting the same flag, no timely beat with `requires.beats_not_fired: [it]`, and (flag) fewer than 2 setters and no reliable setter |
| `guaranteed_on_takeoff` | error | an air-start flight exists and a guaranteed beat depends (directly, via `beat.fired`, a flag or `requires.beats_fired`) on `unit.takeoff` or a ramp-only `start_area` zone |
| `hook_late` | warn | every radio beat has a known time (timers/chains) and the first is after 180 s |
| `popup_no_telegraph` | error | `ambush_sam`/`cap`/`waves` encounter with no `telegraph_beat` and no `encounter.telegraph` beat, unless notes contain `no-cue:` and briefing.md mentions it (warn for `waves` whose pool has no anti-air/fighter role) |
| `telegraph_too_short` | warn | the telegraph beat has a delay, is gated (`requires`/chance) or has no line/text |
| `line_too_long` | warn | a variant over the speaker's `voice.brevity` words (terse 12, normal 20, chatty 30) or over 8 s |
| `peak_chatter` | warn | a variant over 12 words on a beat that fires mid-fight (`unit.hit/shot/dead`, `group.dead`, `encounter.sam_hot/wave/proximity`, `director.state` PEAK) |
| `callsign_first` | warn | a variant's first 4 words hold no cast/flight/support callsign word or short form (`Two`, `Check fire`, ...); same-speaker `beat.fired` continuations exempt |
| `banned_phrases` | warn | "over and out", "hell yeah", "let's do this", "roger that, over", "copy that", more than one `!` |
| `brevity_misuse` | warn | "bulls" (not bullseye), BRAA with "for"/"at", "tally" on friendlies, "visual" on enemies, bingo/winchester from a non-aircrew bible role |
| `variants_too_similar` | warn | two variants of a beat with word Jaccard > 0.8 |
| `too_few_variants` | warn | `once: false` with lines and fewer than 3 variants |
| `reaction_no_cooldown` | warn | `once: false` on `unit.hit/shot/dead` with `cooldown_sec` < 30 |
| `radio_density` | warn | more than 3 radio beats with the same `when` + `requires`, or more than 25 s of radio in any 60 s window of the known (timer/chain) schedule |
| `no_generic_fallback` | info | every radio beat on a reaction event is `requires`-gated |
| `quality_swing` | warn | beats' `quality_deltas` can sum past ±2 (or repeat), or the arc entry's `quality_effects` text allows > ±2 (alternatives count once, "more" adds, "set to N" = full range, "per" unbounded unless "max N") |
| `vul_overload` | warn | more than 6 encounters with `chance` > 0 |
| `briefing_threat_mismatch` | error | a threat with `hidden_on_map: false`, or a telegraphed encounter, that briefing.md never mentions (id, role words, template names) |
| `briefing_missing_sections` | warn | briefing.md lacks `## 1.`–`## 5.`, "abort", "bingo", a duration line or a stakes line |
| `kneeboard_contradiction` | error / warn | laser codes differ between briefing.md and kneeboard.md (error); a briefed frequency is missing from the kneeboard (warn) |
| `kneeboard_too_long` | warn | kneeboard.md over 25 non-empty lines or no comms table |
| `transit_too_long` | warn | `out/plan.json` exists and a client group's route to the `IP` waypoint takes > 30 min (ramp) / 8 min (air) at the waypoint speeds |
| `failure_dead_end` | error (warn while the next mission is not designed) | the arc's next main-line mission exists and `<mNN>_player_lost` / primary objective `failure_flag`s are read by no branch of this mission and not by the next mission's files or synopsis |
| `branch_never_rejoins` | warn | an `optional` arc mission reaches no main-line mission within 2 hops |
| `intensity_streak` | warn | this mission is the third `intense` in a row; (arc) an act whose designed missions have no `calm` |
| `quality_unmoved` / `quality_unread` | warn | (arc) a quality no `quality_effects`/`quality_deltas` moves / no branch, mission file or arc synopsis reads |

Vocabulary notes: threat role `civilian` = unarmed civilian vehicles only (pair with a neutral
faction; the planner must never pick armed types for it, and lists that faction's country in
`BuildPlan.neutral_countries` so the builder creates it in the neutral coalition). Beat `coalition` filters accept 0
(neutral), 1 (red), 2 (blue).

Player flights (`PlayerFlight`), start options and slots:

- `variant: str | null`: flights with the same variant are built together; each distinct variant
  produces its own `.miz` named `<id>-<variant>.miz`; flights without a variant appear in every
  variant. No variants at all = one `<id>.miz` (unchanged). Typical single-player choice:
  `variant: ramp` (`start_type: parking_cold`) and `variant: air` (`start_type: air` + `air_start`).
- `slot: player|client` (default `player`): `player` = lead unit is the single-player `Player`,
  the other `count-1` units are AI wingmen (skill `High`) that spawn and fly in SP; `client` = all
  units `Client` (multiplayer). Only one `player` flight per variant: later ones are planned as
  `client` (validate warns). AI wingmen have no player name, so the runtime (`coalition.getPlayers`,
  `player.spawned`, `players_only` filters, `Spawner.playerUnits`) only ever treats the lead as the
  player.
- `air_start: {altitude_ft=20000, speed_kts=420, distance_nm_before_first_wp=20, toward=null}`
  (only with `start_type: air`; omitted = defaults when `start_type: air`): the planner puts the
  flight `distance_nm_before_first_wp` short of its first route point (`toward` area id, default
  the first objective area) on the line from `start_area`, heading toward it, at that altitude
  (BARO) and speed; the route continues to that point (the IP when one exists, see Route).
- Route (every player flight, from the spec's areas only): departure (parking point / air-start
  point) -> `IP` (`air_start.toward`, else the first area whose id contains an `ip`, `ingress`
  or `push` token, e.g. `ip_arrow`) -> `TGT` / `TGT1..n` (each objective's area in spec order;
  without an area, its target threat's or support asset's area, or the target pool's area when
  the pool has exactly one; `land`/`survive` objectives and the start/recovery/IP/egress areas
  are skipped) -> `EGRESS` (first area whose id contains an `egress` token) -> `HOME`
  (`Landing` at the first `land` objective's airbase area, else the start area's airbase).
  Fixed-wing: 20,000 ft BARO at 450 kts (capped at 0.8 x the type's max speed; air starts use
  their `air_start` altitude/speed). Helicopters: 150 m RADIO at 200 km/h. Waypoint names
  (`PlanWaypoint.name`) are written to the .miz. Test mode builds its own proxy route and only
  uses the flight's first route point.
- Loadout `auto` (or an unrecognised intent) picks the aircraft's preset for the mission type
  (F-16C_50: SEAD/DEAD -> `sead`, STRIKE/INTERDICTION -> `lgb_strike`, CAS -> `cas`); free text
  with HARM/SEAD, GBU/LGB/strike, CAS/Maverick maps to those presets. Fuel is always full internal.
  Player helicopters (`dms_gen.builder.payloads.PRESETS`, default in brackets): Mi-8MT and UH-1H
  [`transport`] / `rockets`; CH-47Fbl1 [`transport`]; Mi-24P [`atgm_rockets`] / `rockets` /
  `transport`; Ka-50, Ka-50_3 [`atgm_rockets`] / `rockets`; SA342M [`atgm`]; OH58D
  [`hellfire_rockets`] / `hellfire` / `rockets`. `transport` = clean racks plus door guns.
  Mi-8MT/UH-1H/Mi-24P map TRANSPORT/CSAR -> `transport`, CAS -> rockets. Free text naming
  transport/cargo/troops/CSAR/medevac/"no rockets" picks `transport`; ATGM/Vikhr/Ataka/HOT
  picks `atgm_rockets` / `atgm` when the aircraft has it.
- `dms validate` warns when a threat's bible faction is not on the side opposite the players'
  (`player_flights[0].coalition`) or neutral.
- Radio callsign: the spec `callsign` is applied to the group in DCS when it is one of the type's
  DCS callsign names for that country (F-16C_50/USA: Viper, Venom, Lobo, Cowboy, Python, Rattler,
  Panther, Wolf, Weasel, Wild, Ninja, Jedi); otherwise the closest valid name is chosen
  deterministically and `dms validate` warns. `PlanGroup.radio_callsign` records the result
  (`"Python 1-1"`, flight number counted per callsign within a variant).

Threats and support: `Threat.templates: list[str]` pins the catalog templates the planner may
pick for that threat (they must be templates of the role and era; validate errors when none
match, warns for ignored ids). `PoolIntent.templates: list[str] | null` does the same for a
dynamic pool: the runtime pool's members are only those ids that are templates of one of the
pool's roles and the era (validate errors when none fit, warns for ignored ids; null/empty = any
template for the roles/era/faction). `Support.faction` (friendly bible faction) sets the asset's DCS
country; without it the speaker character's faction is used when it is on the players' side,
else the side's first country.

Support radios: `Support.frequency_mhz` is carried into `PlanGroup.frequency_mhz` and applied by
the builder (AWACS/tanker: their tuned frequency, `SetFrequency` + group frequency; default 251.0
when null). `Support.modulation: AM|FM|null` (null = FM below 87.995 MHz, else AM) sets
`PlanGroup.modulation` and the speaker's `modulation`; player flights get the band rule too.
`Support.callsign` for AWACS/tankers becomes `PlanGroup.radio_callsign` (`"Magic 1-1"`; a number
in the spec callsign, `"Texaco 6"`, is the flight number) when it is a DCS name for the type
(AWACS: Overlord, Magic, Wizard, Focus, Darkstar; tankers: Texaco, Arco, Shell); otherwise the
closest name is used and validate warns. `Support.tacan` (tankers, e.g. `"51Y"`, null = `10X`)
becomes `PlanGroup.tacan`.

Planner comms plan (`dms_gen.planner.radios`, run by `plan_mission`): every radio agency gets a
frequency, so no briefing/kneeboard needs `TBD (plan)`. Agencies are the player flights, the
supports (AWACS/tanker/JTAC always; other roles when they have a speaker, callsign or
frequency) and every friendly speaker character (`spec.cast` + line speakers) without a support.
Characters are classified by `role` text: wingman / crew / intercom / sister ship -> the player
flight's frequency (no own entry); tower / air traffic / ATC -> the player start airbase's ATC
frequency from pydcs (UHF if the aircraft has a UHF radio, else VHF), else an assigned one;
AWACS / E-3 / weapons controller -> awacs; JTAC / FAC / observation post / convoy / outpost /
company / platoon / ground -> ground; anything else (ops, command) -> agency. Characters of a
faction not on the players' side get nothing (coalition-wide audio as before).
- Spec values (`frequency_mhz`, `modulation`) always win. Assigned values are deterministic (spec
  order), never equal to another agency's or flight's frequency or the start airbases' ATC
  frequencies, and use a band the first player flight's aircraft can tune (pydcs `panel_radio`;
  each radio's band from its channel 1: < 88 FM, < 225 VHF AM, else UHF AM):
  awacs/tanker: UHF (from 251.0 / 276.0, 1 MHz steps) else VHF; ground: FM (from 41.0, 0.5
  steps) else VHF (from 133.0) else UHF (from 280.0); agency: VHF (from 124.0, 0.5 steps) else
  UHF (from 260.0); ranges FM 30-87.975, VHF 118-151.975, UHF 225-399.975.
- Assigned support frequencies are written back to the support `PlanGroup.frequency_mhz` /
  `modulation` (so AWACS and tanker no longer share the builder default 251.0) and to
  `DMS_CONFIG.speakers[<id>].frequency/modulation` (so the runtime transmits on them).
- `BuildPlan.comms: list[PlanComm{id, kind: flight|support|agency|tower, callsign, frequency_mhz,
  modulation, band: uhf|vhf|fm, speaker?, source: spec|planner|airbase|aircraft, preset?}]` in
  that order. `preset` is the first player flight's preset, e.g. `"radio 2 ch 1"`.
- `PlanGroup.radio_presets: list[PlanRadioPreset{radio, channel, frequency_mhz, name?}]` on client
  groups: every non-flight agency on the radio of its band (agency first, so the command net
  lands on channel 1 of a second radio, then awacs, ground, tanker, tower); channel 1 of the
  radio that carries the flight frequency is left to DCS. The builder applies them with pydcs
  `set_radio_channel_preset` to every unit (a radio/channel the type lacks is skipped).
- Docs (`dms_gen.builder.docs`): in `briefing.md` / `kneeboard.md`, every `TBD (plan)` is
  replaced by `<MHz> <AM|FM>` of the agency named on that line (callsign, id or speaker id,
  case-insensitive), else by `see kneeboard COMMS`; a generated `COMMS` kneeboard page (agency,
  callsign, MHz, preset) is appended whenever `plan.comms` is non-empty; the planner's fallback
  `PlanBriefing.blue_task` ends with a `Comms:` list.

Plan fields: `PlanGroup.variant` (copied from the flight), `PlanGroup.radio_callsign`, `PlanGroup.tacan`,
`BuildPlan.neutral_countries` (countries of every neutral-coalition faction used by threats or
pools; threats of a neutral faction are planned in the neutral coalition and the builder adds the
countries to the neutral coalition).

Every model gets `model_config = ConfigDict(extra="forbid")` and `Field(description=...)` on
fields; the descriptions double as LLM guidance. `dms_core.schemas.export_json_schemas(out_dir)`
writes JSON Schema files to `schemas/` at the repo root for skills and editors.

## File formats

- **Campaign folder:** `campaigns/<slug>/premise.md, bible.yaml, arc.yaml, continuity.md, state/qualities.yaml, state/outcomes/<mNN>.yaml, missions/mNN-<slug>/{mission-spec.yaml, beats.yaml, briefing.md, kneeboard.md, lines.yaml, voice/, out/}`
- **YAML** for authored files. **JSON** for machine intermediates (`plan.json`).
- **Voice cache:** `~/.dms/tts-cache/<sha256>.ogg`, where the key is `sha256(voice_id|model|text|fx)`
  and `fx` = `<preset>@<12-hex sha256 of the preset params + output sample rate + codec args>`;
  a Text-to-Dialogue line (with `turns`) uses sha256 of the canonical JSON
  `{"kind":"dialogue","model","fx","inputs":[{voice_id,text}]}` (same `fx` form). Voice ids come from the bible's
  `VoiceProfile.eleven_voice_id` first, `data/voice/voices.json` (or `--voices`) second; `--model`
  overrides the lines.yaml `model`. `dms voice` writes `voice/manifest.json`
  (`{line_id: {file, dur_sec, text, speaker, model, placeholder?: true}}`) and never edits lines.yaml.
  `--rerender LINE_ID` (repeatable) / `--no-raw-cache` (all lines) skip both caches for a fresh,
  billed take that replaces the cached one. `dms build` warns when the manifest has placeholder clips.
  Raw pre-FX TTS is cached at `raw/<key computed with fx_preset="">.bin`, so an FX change costs 0
  credits. Credits: 1/char (v3, multilingual), 0.5/char (flash/turbo). Offline: `--offline` or env
  `DMS_VOICE_OFFLINE` = `1`/`true`/`yes`/`on` uses model `placeholder` (ignoring `--model`, with a
  warning): tone clips sized to the text, no key, no voice ids, same FX/cache/manifest/embed path.
- **Audio in the .miz:** each manifest clip is `l10n/DEFAULT/<line_id>.ogg`, registered in
  `mapResource`, and referenced by one `a_out_sound` action of the never-firing keeper trigger
  (comment `DMS: keep sound resources (never fires)`, `c_flag_equals DMS_SOUND_KEEPER_NEVER 424242`)
  so the Mission Editor keeps it; `DMS_CONFIG.voice[id].file` is the bare file name.
- **CLI** (`packages/dms-cli`, typer; global `--root <repo>`, default: walk up to the uv workspace).
  `<mission>` is a mission folder or its `mission-spec.yaml`.
  - `dms validate <mission|arc.yaml> [--beats --lines --bible] [--json] [--no-lint] [--strict]`: schema +
    cross-file + planner checks + mission-quality lint (see "Mission-quality lint"); `arc.yaml` gets the
    schema plus the campaign-wide arc lint. `--strict` exits 1 on warnings too.
  - `dms plan <mission> [-o plan.json] [--seed N] [--voice-manifest]`: default output
    `<mission>/out/plan.json`; the voice manifest defaults to `<mission>/voice/manifest.json` if present.
  - `dms voice <lines.yaml|mission> [--out --dry-run --fx --voices --model --offline --rerender ID... --no-raw-cache]`:
    output `<mission>/voice`.
  - `dms build <plan.json|mission> [-o out.miz] [--lua] [--variant V]`: a folder reads
    `<mission>/out/plan.json` and writes `<mission>/out/<id>.miz`, then runs check. With player
    flight variants it writes one `<mission>/out/<id>-<variant>.miz` per variant (plan order) and
    checks each; `<id>.miz` is a copy of the first variant's build (backward compatibility).
    `--variant V` builds only that variant (`-o` then names its file).
  - `dms run <mission> [--seed --skip-voice -o] [--install [--dcs stable|openbeta|auto]]`: validate -> voice
    -> plan -> build -> check. `--install` then runs `dms install` on the mission (non-test builds only).
  - `dms install <mission|out dir|.miz> [--dcs stable|openbeta|auto] [--test] [--dry-run] [--json]`: copy
    (overwrite) `<mission>/out/<id>.miz` and every `<id>-<variant>.miz` (`<id>-test.miz` only with
    `--test`; a `.miz` argument installs just that file) to
    `<Saved Games>/DCS[.openbeta]/Missions/DMS/<campaign>/`. `<campaign>` is the `campaigns/<slug>` folder,
    else the spec's `campaign`, else `misc`. Saved Games is `$DMS_DCS_SAVED_GAMES` (the Saved Games dir
    itself), else the Windows known folder (FOLDERID_SavedGames), else `~/Saved Games`. `auto` uses whichever
    of `DCS`/`DCS.openbeta` exists (both: newest `Logs/dcs.log`; neither: `DCS` with a warning). Exit 1 when
    nothing is built.
  - `dms doctor [--json]`: environment checks (python + dms packages + pydcs, lupa Lua 5.1, luac, ffmpeg,
    ElevenLabs key presence (never its value), DCS install + Saved Games, `dist/dms.lua` freshness, git-lfs,
    uv) as a `CHECK STATUS DETAIL` table (OK/WARN/FAIL) plus `fix:` hints; JSON is
    `{ok, checks: [{name, status, detail, fix}]}`. Exit 1 only on a FAIL.
  - `--test [--test-minutes M]` on `plan`, `build` (plus `--seed`) and `run`: headless-DCS test variant
    (AI player proxy + `DMS.Test` checks) in `out/test/<id>-test.miz`; normal outputs are untouched.
    The proxy replaces a ramp/runway player flight (start `parking_*`/`runway` preferred, so
    on-deck/landing beats are reachable); `build --test --variant V` picks the proxy from variant V.
  - `dms check <miz|mission folder> [--json]`: a folder (or its `out/`) checks every built variant
    like `dms build` (`out/<id>-<variant>.miz` per `out/plan.json` variant, else `out/<id>.miz`;
    no plan: every non-test `out/*.miz`); `--json` with several files is `{miz path: report}`.
    `dms schema [--out]`, `dms bundle-lua [--out]`.
  - `dms catalog units|templates [--era --coalition --role --category]`, (`templates --role` takes a
    template role/tag or a spec `ThreatRole`, resolved through `dms_core.catalog.THREAT_ROLE_TEMPLATES`,
    the planner's role -> template table; an unknown role prints the valid ones),
    `dms catalog airbases --theater T [--near name|x,y --limit]`, `dms catalog mission-types`; all take `--json`.
  - `dms outcome <dcs.log> [--mission-id] [--json]`: parse `[DMS.OUTCOME]` lines and summarise.
  - `dms new-campaign <slug> [--with-example]`: copy `campaigns/_template` to `campaigns/<slug>`.
    Example files (any path segment containing `example`, i.e. `missions/m01-example/` and
    `state/outcomes/mNN-example.yaml`) are skipped unless `--with-example`; `missions/` and
    `state/outcomes/` are always created (empty).
  - `dms debrief <campaign_dir> --mission mNN [--log PATH] [--dry-run] [--force] [--seed N] [--no-arc-effects] [--no-continuity] [--json]`:
    latest session's `[DMS.OUTCOME]` lines -> `state/outcomes/<mNN>.yaml`, qualities (beat deltas + arc
    `quality_effects`), a continuity.md entry, next mission.
- **Briefing and kneeboard in the miz:** `dms_gen.builder.build_from_plan(plan, out, base_dir=<mission dir>)`
  (used by `dms build` and the MCP `build`) folds the mission folder's Markdown into the build.
  `plan.json` on disk is unchanged. Both files are optional; without them the plan's `PlanBriefing` is used.
  - `briefing.md` maps to the DCS briefing fields. The first `#` heading becomes `sortie`. Everything before the
    first `## 2. …`/`## Mission` heading becomes `descriptionText`, and the rest becomes `descriptionBlueTask`.
    A heading containing `Red` (e.g. `## Red task`) becomes `descriptionRedTask` until the next heading at the
    same or a higher level. Markdown is stripped to plain text, with paragraphs unwrapped so that DCS wraps them.
    Empty fields fall back to `PlanBriefing`.
  - `kneeboard.md` renders to 768x1024 PNG pages at `KNEEBOARD/IMAGES/<mission_id>-kneeboard-NN.png`
    (all aircraft). It supports headings, paragraph lines (line breaks kept), bullets, pipe tables and `**bold**`,
    and paginates when needed. It uses Pillow's default font and no bundled font files. The bytes are
    deterministic for a given Pillow build. Glyphs that font lacks become ASCII (`—`→`-`, `→`→`->`).
  - **Map page** (`dms_gen.builder.kneeboard_map`, U3): one 768x1024 PNG at
    `KNEEBOARD/IMAGES/<mission_id>-kneeboard-map-01.png` (all aircraft; it sorts after the `kneeboard.md`
    and COMMS pages), drawn from `plan.json` alone on a plain background. There are no map tiles
    (licensing and determinism). It is on by default: `MissionSpec.kneeboard.map: bool = true`, which the
    planner copies to `PlanOptions.kneeboard_map`. It is added whenever `base_dir` is given (like COMMS)
    and the plan has a client group. Contents:
    - a lat/lon graticule (labels in degrees and minutes, from pydcs's projection for `plan.theater`), a
      north arrow (map grid north = DCS +x), a scale bar in NM;
    - the player-side bullseye (pydcs terrain default, which is what the builder writes). When it is far
      off the map it becomes an edge pointer with `BULLS <brg>/<NM>` from the map centre;
    - every client group's route (identical routes drawn once), steerpoints numbered with their
      waypoint names; `IP` as a triangle and `TGT*` as a crosshair;
    - friendly airbases: the airbases named on the player side's waypoints (catalog positions);
    - known threats as rings: enemy `vehicle`/`ship`/`static` groups that are `hidden: false` and not
      `late_activation`. When `runtime.intel.fog_of_war` is on, a group must also be listed in
      `intel.known_groups`. **Hidden threats are never drawn** (fog of war). The ring radius is the
      largest catalog template `max_range_nm` of any of its unit types, else a role default
      (`sam_long` 25, `sam_medium` 15, `sam_radar` 10, `sam_short` 5, `manpads` 2.5, `aaa` 1.5 NM).
      Groups with neither get a marker and no ring;
    - no-strike areas: plan zones whose name contains `no_strike`, `nostrike`, `no-strike`, `nsa`,
      `no_fire`, `nfa` or `restricted` (case-insensitive), drawn hatched. Other zones are not drawn,
      because area names could give away hidden threats;
    - a footer with the steerpoint list (number, name, lat/lon in DDM) and the bullseye position.
    The bytes are deterministic for a given Pillow build (Pillow's default font, no antialiasing).

## MCP server (`packages/dms-mcp`, v0.8)

`dms-mcp` is a FastMCP server (official `mcp` SDK 1.x, `mcp.server.fastmcp.FastMCP`) on **stdio**.
It is a thin wrapper ([ADR 0005](adr/0005-cli-and-skills-before-mcp.md)): the tools call
`dms_core` / `dms_gen` in-process (plus the path and issue helpers in `dms_cli.util`) and never
shell out to `dms`. The tool logic lives in `dms_mcp.ops` (plain functions returning dicts) so it
can be tested without a client; `dms_mcp.server` only registers the tools.

- **Root:** relative paths resolve against the repo root: `$DMS_ROOT` if set, else the uv workspace
  found from the working directory.
- **Results:** every tool returns a JSON object with `ok: bool`. A failure the caller can fix
  (missing file, schema errors before planning, unknown name) is returned as
  `{"ok": false, "error": "<message>"}`, not raised as a protocol error.
- **Issues** use the CLI's finding shape: `{path, problem, suggestions[], severity}`.
  Check issues use `CheckIssue`: `{severity, code, message, where}`.

| Tool | Arguments | Does | Returns (besides `ok`) |
|---|---|---|---|
| `validate` | `path`, `strict=false`, `lint=true` | Like `dms validate` (incl. the mission-quality lint). `path` is a mission folder or `mission-spec.yaml`, or a `bible.yaml` / `arc.yaml` / `qualities.yaml` (schema only; `arc.yaml` also gets the arc lint) | `kind`, `path`, `files`, `errors`, `warnings`, `issues` |
| `plan` | `mission_dir`, `seed?` | Like `dms plan`: writes `<mission>/out/plan.json` (uses `voice/manifest.json` when present) | `plan`, `voice_manifest`, `mission_id`, `seed`, `theater`, `players[]`, `stats` |
| `build` | `mission_dir`, `test=false`, `variant=null` | `dms build` + check (one `.miz` per player-flight variant + `<id>.miz` = first; `variants[]` lists `{variant, miz, ok, check}`). Plans first when `out/plan.json` is missing. `test=true` is `dms build --test` (seed from `out/plan.json`, writes `out/test/`, `out/<id>-test.miz`) | `miz`, `test`, `mission_id`, `seed`, `stats`, `notes[]`, `check`, `harness` (test only) |
| `check` | `miz_path` | `dms check` | `CheckReport` fields: `path`, `issues`, `stats` |
| `schema` | `name` | JSON Schema of one document model. `name` is a `DOCUMENT_MODELS` stem (`mission-spec`, ...), a class name (`MissionSpec`) or `bible` / `arc` / `lines` | `name`, `model`, `schema` |
| `campaign_status` | `campaign_slug` | Read-only overview of `campaigns/<slug>` | `title`, `files`, `qualities`, `flags`, `next_mission`, `outcomes[]`, `missions[]` (`id`, `title`, `designed`, `files`, `voiced`, `planned`, `built[]`, `out[]`, `last_check`, `debriefed`), `arc_missions_not_designed[]` |

- **`out/check.json`:** `build` and `check` record the last check result next to the `.miz` as
  `{"<file>.miz": CheckReport + "checked_at" (UTC ISO)}`, and `campaign_status` reports it as
  `last_check`. This file is generated output (git-ignored with `out/`). The CLI does not write it yet.
- Voice rendering (paid ElevenLabs calls) and campaign writes (debrief, `new-campaign`) are not
  exposed over MCP. Use the CLI and skills for those.
- **Entry point:** `dms-mcp` (console script). The repo root has a project-scoped `.mcp.json` that
  registers it for Claude Code as server `dms` (`uv run dms-mcp`, started in the repo root, so
  `DMS_ROOT` is not needed). `packages/dms-mcp/tests/test_stdio.py` spawns that console script
  over real stdio with the `mcp` client and calls all six tools on a temp copy of
  `campaigns/viper-detachment`.
