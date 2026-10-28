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

**Embed order in the .miz:** plugins -> `dms_config.lua` -> `dms.lua` (config first). The runtime
tolerates either order: `init.lua` boots immediately when `DMS_CONFIG` exists at load, otherwise
it re-checks for a few seconds via `DMS.Clock.after` and then logs a warning. `DMS.boot()` is
idempotent.

```lua
DMS.VERSION                       -- string stamped by bundler
DMS_CONFIG                        -- global table emitted by the generator (see below); may be nil in tests
DMS.boot() -> bool                -- start modules in DMS.START_ORDER, then emit "mission.start"; once only
DMS.START_ORDER = { "Spawner", "Ground", "Director", "Encounters", "Narrative", "Comms", "Intel" }
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
DMS.Spawner.spawnPool(poolId, opts) -> {groupName...}   -- count = Rng.range(pool.pick), scaled by director
--   opts as spawn, plus count (fixed, not scaled) and zone | point (where; default a random pool.zones entry)
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
-- encounters.lua
DMS.Encounters.trigger(id, opts) -> bool   -- opts: boolean force | {force=bool, beat=id}; ignores chance,
                                           --       respects once unless force
DMS.Encounters.get(id) groups(id) add(def)
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
DMS.Comms.text(msg, opts) repeatLast(groupId, coalition) history() addMenuCommand(path, label, fn)
DMS.Comms.isBusy() -> bool   statusText() -> string   menuFor(groupId) -> menu record|nil
DMS.Comms.addStatusProvider(fn() -> string|{string...})   -- extra lines in the status menu text
-- intel.lua
DMS.Intel.reveal(groupName, reason, opts) forget(g) contacts() contact(g) report(groupId) kills()
DMS.Intel.mark(spec) -> handle            -- see "mark" below
DMS.Intel.removeMarkHandle(handle) -> bool
DMS.Intel.resolveGroup(name) -> groupName|nil   -- "group:<name>": exact live group, else first live
                                                --  prefix match (with or without "DMS_")
-- test.lua: DMS.Test (headless-DCS assertions; inert unless DMS_CONFIG.test.enabled)
--   Starts itself on mission.start (not in START_ORDER). Logs "[DMS.TEST] PASS|FAIL|SKIP|INFO <name> <detail>"
--   and "[DMS.TEST] DONE <passed>/<total>" (parsed by tools/dcs_harness).
DMS.Test.pass(name, detail) fail skip info   check(name, cond, detail) -> bool   done() autoDone(graceSec)
DMS.Test.expect(name, fn(atEnd) -> ok, detail, fatal, deadlineSec, {interval=2, negate})
DMS.Test.config() isEnabled() proxyName() isProxyRun() runChecks(checks, deadlineSec)
--   DMS_CONFIG.test = {enabled, playerProxy=<AI group treated as the player>, minutes, checks={...}}
--   check kinds: booted | spawns{min} | beats_in_order{beats} | beat{id} | comms{min} |
--                encounter{id} | convoy_halt | outcome{result}; optional name, deadlineSec
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
| `player.left` | `{unit, group, groupId, playerName}` | bus |
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
| `encounter.proximity` | `{id, encounter, zone, group, unit}` | encounters proximity trigger (NOT `zone.entered`) |
| `convoy.halted` / `convoy.resumed` | `{group, by?}` | ground.haltOnHit |
| `ground.stuck` | `{group}` | ground.watch |
| `director.state` | `{flight, state, intensity}` | director |
| `intel.revealed` | `{group, reason}` | intel |

## DMS_CONFIG (generated by Python, consumed by Lua)

Python model: `dms_core.schemas.runtime.RuntimeConfig`, serialized as `DMS_CONFIG = {...}` in
`dms_config.lua`. Every key below is optional except `missionId`; every Lua module tolerates any
key being absent (including `DMS_CONFIG = {}`). `Range` = number or `{min, max}`.

```lua
DMS_CONFIG = {
  version = 1, seed = 12345, debug = false, missionId = "m01-first-light",
  budgets  = { maxActiveGround = 150, maxActiveAir = 16, maxActiveShip = nil, spawnsPerMin = 3 },
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
      chance = 70, once = true, telegraph = "beat:popup_aa_warning",  -- "beat:<id>" | "event:<name>" | "<name>"
      hunt = false --[[or group name]], engageRadiusM = 15000, hotChance = nil, telegraphSec = {30, 60},
      reactSec = {2, 8}, checkSec = 2, gated = true, cost = 1, maxDeferSec = 300, gateRetrySec = 15,
      huntIntervalSec = 30, huntSpeed = 8, huntRadiusM = nil, target = nil, spawnZone = nil,
      waves = nil --[[number or {min,max}]], gapSec = {120, 240},
      destination = "kirikhan_road" --[[zone id or {x,y}]], resumeAfterSec = {60, 120}, escortRadiusM = 500,
      speed = 10, action = "On Road" },
  },
  beats = { --[[ see "Beats" ]] },
  voice = { ops_cleared_v1 = { file = "ops_cleared_v1.ogg" --[[optional: nil/"" = subtitle only]], text = "Dusty, Hatay Ops...", durSec = 7.5,
                               speaker = "ops_walsh", turns = nil --[[ { {speaker=, text=}, ... } ]] } },
  speakers = { ops_walsh = { callsign = "Hatay Ops", frequency = nil --[[MHz]], modulation = nil --[[0 AM|1 FM]] } },
  qualities = { intel = 0, enemy_aa = 2 },            -- campaign values at plan time; seeds `requires.qualities`
  narrative = { minGapSec = 8, pendingTtlSec = 45, zonePollSec = 3 },
  intel = { fogOfWar = true, revealRadiusM = 5000, markRefreshSec = 15, staleSec = 120,
            removeSec = nil --[[default 3 * staleSec]], scanSec = 5, markRadiusM = 600, sensors = true },
  players = { coalition = 2 },
}
```

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
              qualityDeltas = { trust = 1 }, endMission = nil --[["success"|"failure"]] } }
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
- Aliases (Lua and Python normaliser): no `event` with `afterSec`/`timer` -> timer, `flag` -> flag,
  `zone` -> zone.entered, `director`/`directorState` -> director.state, `beat` -> beat.fired.

**requires** - all must hold: `flags`, `flagsNot`, `qualities` (list of `{quality, op, value}`),
`beatsFired`, `beatsNotFired`, `chance` (rolled once when the beat is triggered). Aliases: `flags` as
a map `{f = true|false}`, `flagsSet`, `notFlags` / `flagsNotSet`, `qualities` as a map
`{q = 2 (>=) | ">=2" | {min=, max=} | {op=, value=}}`.

**effects** - `qualityDeltas` are applied live (later beats in the same mission see them) and
reported cumulatively in the outcome; the debriefer applies them to `state/qualities.yaml`.
`endMission` finishes the narrative (writes the `end` outcome line). Aliases: `finish` / `end` /
`result` (victory -> success, defeat -> failure), `qualities` -> `qualityDeltas`.

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
  `source: dcs_log`, `log_file`, `session_start` (log timestamp), `ended` (an `end` line exists),
  `beats_fired`, `quality_changes [{quality, from, to, delta, reason}]`, `flags_set`,
  `next_mission`, `next_reason`, log issues. `mNN` = first `-` segment of the mission id.
- **state/qualities.yaml** (pure `apply_outcome(state, outcome, arc)`): `qualityDeltas` (cumulative,
  last record wins) are rounded to int, added, and clamped to the arc `QualityDef` min/max; a quality
  missing from `values` starts at its `initial`; deltas for qualities the arc does not declare are
  skipped with a warning. Flags: each outcome key becomes `<mNN>_<key>` (bool as-is, number `> 0`,
  string `true`), plus `<mNN>_<result>`; other result flags of the same mission
  (`success|failure|partial|aborted|ended`) are set false. `outcomes[<mission id>]` = outcome
  facts, `updated_after` = mission id, `next_mission` = branch choice. Arc free-text
  `quality_effects` are **not** applied by code (the debriefer skill proposes them).
- **Next mission**: the flown mission's `branches` in order; `when` (`Requires`) is checked against
  campaign `flags`/`values` (`beats_fired`/`beats_not_fired` against this flight's beats; `chance`
  rolled with `--seed`). First match wins, else the next non-optional arc mission, else none (end).
- **Re-debrief guard**: if `state/outcomes/<mNN>.yaml` already records the same `log_file` +
  `session_start`, `dms debrief` refuses (exit 1) unless `--force`, so deltas are not applied twice.

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
| `validation.py` | `Issue` (path, problem, suggestions, severity); `validate_mission_bundle` cross-file checks | `dms validate` |

Vocabulary notes: threat role `civilian` = unarmed civilian vehicles only (pair with a neutral
faction; the planner must never pick armed types for it, and lists that faction's country in
`BuildPlan.neutral_countries` so the builder creates it in the neutral coalition). Beat `coalition` filters accept 0
(neutral), 1 (red), 2 (blue).

Every model gets `model_config = ConfigDict(extra="forbid")` and `Field(description=...)` on
fields; the descriptions double as LLM guidance. `dms_core.schemas.export_json_schemas(out_dir)`
writes JSON Schema files to `schemas/` at the repo root for skills and editors.

## File formats

- **Campaign folder:** `campaigns/<slug>/premise.md, bible.yaml, arc.yaml, continuity.md, state/qualities.yaml, state/outcomes/<mNN>.yaml, missions/mNN-<slug>/{mission-spec.yaml, beats.yaml, briefing.md, kneeboard.md, lines.yaml, voice/, out/}`
- **YAML** for authored files. **JSON** for machine intermediates (`plan.json`).
- **Voice cache:** `~/.dms/tts-cache/<sha256>.ogg`, where the key is `sha256(voice_id|model|text|fx_preset)`;
  a Text-to-Dialogue line (with `turns`) uses sha256 of the canonical JSON
  `{"kind":"dialogue","model","fx","inputs":[{voice_id,text}]}`. Voice ids come from the bible's
  `VoiceProfile.eleven_voice_id` first, `data/voice/voices.json` (or `--voices`) second; `--model`
  overrides the lines.yaml `model`. `dms voice` writes `voice/manifest.json` and never edits lines.yaml.
- **CLI** (`packages/dms-cli`, typer; global `--root <repo>`, default: walk up to the uv workspace).
  `<mission>` is a mission folder or its `mission-spec.yaml`.
  - `dms validate <mission> [--beats --lines --bible] [--json]`: schema + cross-file + planner checks.
  - `dms plan <mission> [-o plan.json] [--seed N] [--voice-manifest]`: default output
    `<mission>/out/plan.json`; the voice manifest defaults to `<mission>/voice/manifest.json` if present.
  - `dms voice <lines.yaml|mission> [--out --dry-run --fx --voices --model]`: output `<mission>/voice`.
  - `dms build <plan.json|mission> [-o out.miz] [--lua]`: a folder reads `<mission>/out/plan.json` and
    writes `<mission>/out/<id>.miz`, then runs check.
  - `dms run <mission> [--seed --skip-voice -o]`: validate -> voice -> plan -> build -> check.
  - `--test [--test-minutes M]` on `plan`, `build` (plus `--seed`) and `run`: headless-DCS test variant
    (AI player proxy + `DMS.Test` checks) in `out/test/<id>-test.miz`; normal outputs are untouched.
  - `dms check <miz> [--json]`, `dms schema [--out]`, `dms bundle-lua [--out]`.
  - `dms catalog units|templates [--era --coalition --role --category]`,
    `dms catalog airbases --theater T [--near name|x,y --limit]`, `dms catalog mission-types`; all take `--json`.
  - `dms outcome <dcs.log> [--mission-id] [--json]`: parse `[DMS.OUTCOME]` lines and summarise.
  - `dms new-campaign <slug>`: copy `campaigns/_template` to `campaigns/<slug>`.
  - `dms debrief <campaign_dir> --mission mNN [--log PATH] [--dry-run] [--force] [--seed N] [--json]`:
    latest session's `[DMS.OUTCOME]` lines -> `state/outcomes/<mNN>.yaml`, qualities, next mission.
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
| `validate` | `path` | Like `dms validate`. `path` is a mission folder or `mission-spec.yaml`, or a `bible.yaml` / `arc.yaml` / `qualities.yaml` (schema only) | `kind`, `path`, `files`, `errors`, `warnings`, `issues` |
| `plan` | `mission_dir`, `seed?` | Like `dms plan`: writes `<mission>/out/plan.json` (uses `voice/manifest.json` when present) | `plan`, `voice_manifest`, `mission_id`, `seed`, `theater`, `players[]`, `stats` |
| `build` | `mission_dir`, `test=false` | `dms build` + check. Plans first when `out/plan.json` is missing. `test=true` is `dms build --test` (seed from `out/plan.json`, writes `out/test/`, `out/<id>-test.miz`) | `miz`, `test`, `mission_id`, `seed`, `stats`, `notes[]`, `check`, `harness` (test only) |
| `check` | `miz_path` | `dms check` | `CheckReport` fields: `path`, `issues`, `stats` |
| `schema` | `name` | JSON Schema of one document model. `name` is a `DOCUMENT_MODELS` stem (`mission-spec`, ...), a class name (`MissionSpec`) or `bible` / `arc` / `lines` | `name`, `model`, `schema` |
| `campaign_status` | `campaign_slug` | Read-only overview of `campaigns/<slug>` | `title`, `files`, `qualities`, `flags`, `next_mission`, `outcomes[]`, `missions[]` (`id`, `title`, `designed`, `files`, `voiced`, `planned`, `built[]`, `out[]`, `last_check`, `debriefed`), `arc_missions_not_designed[]` |

- **`out/check.json`:** `build` and `check` record the last check result next to the `.miz` as
  `{"<file>.miz": CheckReport + "checked_at" (UTC ISO)}`, and `campaign_status` reports it as
  `last_check`. This file is generated output (git-ignored with `out/`). The CLI does not write it yet.
- Voice rendering (paid ElevenLabs calls) and campaign writes (debrief, `new-campaign`) are not
  exposed over MCP. Use the CLI and skills for those.
- **Entry point:** `dms-mcp` (console script). An example `.mcp.json` is in `packages/dms-mcp/README.md`.
