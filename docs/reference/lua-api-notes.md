# Lua API notes (addendum to CONTRACTS)

This file documents two runtime pieces in more detail than [CONTRACTS](../CONTRACTS.md) does:
the `DMS.Test` module and the `cap` encounter kind. CONTRACTS stays the shared interface. Where the
two disagree, CONTRACTS wins and this file is out of date.

Status: implemented, not flown. Both are covered by mock specs only (`lua/spec/test_spec.lua`,
`lua/spec/cap_spec.lua`). Nothing here has been checked in DCS yet.

## DMS.Test (`lua/src/dms/test.lua`)

In-mission assertions plus a player proxy, for headless DCS runs driven by `tools/dcs_harness`.
The module does nothing unless `DMS_CONFIG.test` is a table and `enabled ~= false`. Calling the
`DMS.Test.*` functions directly works either way.

### Config

```lua
DMS_CONFIG.test = {
  enabled = true,
  playerProxy = "Proxy-1",  -- AI group treated as the player by every player-dependent module
  minutes = 40,             -- model minutes; open checks fail and DONE is logged at minutes*60 - 15 s
  checks = {
    { kind = "booted" },
    { kind = "spawns", min = 3 },
    { kind = "beats_in_order", beats = { "a", "b" }, deadlineSec = 600 },
    { kind = "beat", id = "a" },
    { kind = "comms", min = 2 },
    { kind = "encounter", id = "popup_aa" },
    { kind = "convoy_halt" },
    { kind = "outcome", result = "success" },
  },
}
```

Every check accepts an optional `name` (default `<kind>[_<id>]_<index>`) and `deadlineSec`
(default: until the end of the run).

| Kind | Passes when | Fails early when |
|---|---|---|
| `booted` | `DMS._booted` at start (checked once) | - |
| `spawns` | at least `min` (default 1) `spawner.spawned` events | a non-air, non-ship spawn has a unit on WATER or SHALLOW_WATER |
| `beats_in_order` | every listed beat fired, in that order | a listed beat fired out of order |
| `beat` | beat `id` fired | - |
| `comms` | `#DMS.Comms.history() >= min` | - |
| `encounter` | `encounter.spawned` seen for `id` | - |
| `convoy_halt` | resolved last: every convoy group that took a `unit.hit` emitted `convoy.halted` within 5 s (vacuous pass if none was hit) | - |
| `outcome` | a `DMS.Log.outcome{kind = "end"}` line, with `result` if given | - |

### Log protocol (parsed by `tools/dcs_harness/run_mission.py`)

```
[DMS.TEST] PASS|FAIL|SKIP|INFO <name> <detail>
[DMS.TEST] DONE <passed>/<total>
```

Whitespace in `<name>` is replaced by `_`. The harness exits DCS a few seconds after `DONE`. An
`INFO summary` line (beats, spawns, encounters, comms count, proxy takeoff and landing) is written
every 120 s and once more just before `DONE`.

### Lifecycle

- `DMS.Test` subscribes to `mission.start`, which `DMS.boot` emits after every module has started.
  When test mode is enabled it calls `DMS.Test.start()` under `pcall`.
- `start()` observes the bus (`spawner.spawned`, `beat.fired`, `encounter.spawned`, `unit.hit`,
  `convoy.halted`, `unit.takeoff`, `unit.landed`, `zone.entered`). It also wraps
  `DMS.Log.outcome`, so the `outcome` check sees exactly what reached `dcs.log`.
- It runs the checks. Every 5 s it tests whether all polled checks have resolved or the end time
  has been reached. When either is true it resolves the open checks, runs the final checks
  (`convoy_halt`), writes the summary and logs `DONE`.
- All scheduling goes through `DMS.Clock`. The `timer.scheduleFunction` fallback in `schedule()`
  is used only when `DMS.Clock` is missing, which happens in standalone use.

### Player proxy

The proxy is an AI group named by `playerProxy`. It is found by retrying every 2 s, 15 times. Each
of its units is then registered in `DMS.Bus._players`, and a synthetic
`player.spawned {unit, group, groupId, playerName = "PROXY", coalition, typeName, proxy = true}` is
emitted for it. After that, Narrative, Intel, Director, Comms, `DMS.Spawner.playerUnits()`,
encounter proximity triggers, hunts and spawn-distance checks all treat the proxy as the player.

`setupProxy()` runs once after registration and again 5 s later. It sends `SetImmortal`, sets ROE
to WEAPON_HOLD and, for air groups, sets REACTION_ON_THREAT to NO_REACTION. Each step is `pcall`ed.

### Functions

| Function | Purpose |
|---|---|
| `pass(name, detail)` / `fail(...)` / `skip(...)` / `info(...)` | write one protocol line (pass/fail are counted) |
| `check(name, cond, detail) -> bool` | pass or fail on `cond` |
| `expect(name, fn, deadlineSec, opts) -> resolve` | poll `fn(atEnd) -> ok, detail, fatal` every `opts.interval` (2 s); `opts.negate` passes if `fn` never became true |
| `done()` / `autoDone(graceSec)` | log `DONE` (once); `autoDone` logs it when no expectation is pending (disabled under `start()`, which owns `DONE`) |
| `resolveOpen()` | force a final evaluation of every open expectation |
| `config()` / `isEnabled()` / `proxyName()` / `isProxyRun()` | config accessors |
| `playerGroups(realList)` | `{proxyGroup}` when a proxy exists, else `realList` (for scripts written against the old `test_mode.lua`) |
| `setupProxy()` / `emitProxySpawn()` | proxy setup and registration (see above) |
| `runChecks(checks, defaultDeadline)` | run check specs; an unknown kind fails immediately |
| `CHECKS` | the check registry. Add new kinds here as `fn(check, deadline)` |
| `summary()` / `start()` / `_reset()` | summary line, lifecycle, test reset |

## CAP encounter (`kind = "cap"`)

An enemy air group flies to a station, orbits there and engages air targets inside the station
zone. It can leave after a time on station, fly home and despawn once it is out of sight. Lost or
departing groups can be replaced, up to a limit.

### Config

```lua
{ id = "north_cap", kind = "cap",
  template = "mig29",               -- or pool = "fighters" (each pool group is its own launch)
  spawnZone = "north_airfield",     -- where it spawns (pool zones if omitted; template falls back to `zone`)
  zone = "cap_box",                 -- station = zone centre ... or point = {x =, y =}
  engageRadiusM = nil,              -- default max(40000, zone radius)
  targetTypes = { "Air" },
  orbit = { pattern = "Race-Track", -- "Race-Track" | "Circle"
            legM = 30000,           -- Range; race-track leg, centred on the station
            headingDeg = nil,       -- leg heading; random (seeded) if nil
            altM = 7000,            -- Range, BARO
            speed = 220 },          -- Range, m/s
  roe = "OPEN_FIRE",                -- AI.Option.Air.val.ROE key
  reaction = "EVADE_FIRE",          -- AI.Option.Air.val.REACTION_ON_THREAT key
  radar = nil,                      -- optional AI.Option.Air.val.RADAR_USING key
  timeOnStationSec = nil,           -- Range; nil = stay until dead
  maxSpawns = nil,                  -- total groups ever spawned by this encounter; nil = no replacements
  replaceOnDead = true, replaceOnRtb = true, replaceDelaySec = { 60, 180 },
  arriveM = 10000, stationTimeoutSec = 1200, rtbDespawnSec = 600, despawnMinPlayerM = 37000,
  checkSec = 10, cost = 1, maxDeferSec = 900, gated = true,
  trigger = { type = "time", afterSec = 30 }, chance = nil, once = true }
```

Unknown enum keys fall back to the default and log a warning. An unknown `orbit.pattern` falls
back to Race-Track. A CAP with no resolvable station, or with no pool and no template, logs a
warning and does nothing.

### DCS tasking

The tasks follow the Hoggit SSE docs. They have the same shape as
`legacy/lua-library/ai-behavior/fire-support.lua`, which puts an en-route EngageTargetsInZone task
on WP1 and an Orbit task on WP2.

About 1 s after the spawn (`Spawner` `onReady`), the group is set up as follows:

- **Options** (via `AI.Option.Air`):
  - `ROE = roe`
  - `REACTION_ON_THREAT = reaction`
  - `RTB_ON_BINGO = true`
  - `PROHIBIT_AG = true`
  - `RADAR_USING`, only if `radar` is set
- **Route**: `setTask({id = "Mission", params = {route = {points = {wp1, wp2}}}})`.
  - Both points use `type = action = "Turning Point"`, `alt_type = "BARO"` and `speed_locked`.
  - wp1 is the current lead position. Its `ComboTask` holds
    `{id = "EngageTargetsInZone", params = {point = {x, y}, zoneRadius, targetTypes, priority = 0}}`.
  - wp2 is the orbit start. Its `ComboTask` holds
    `{id = "Orbit", params = {pattern = AI.Task.OrbitPattern.RACE_TRACK|CIRCLE, point, point2?, speed, altitude}}`.
    `point2` is set for Race-Track only.
- **RTB**: ROE is set to RETURN_FIRE, and a new 2-point `Mission` route runs from the current
  position to the recorded spawn position.

### State machine (one monitor per encounter, every `checkSec`)

`transit` -> `station` -> `rtb` -> `gone`. Any state can also end in `dead`.

| Transition | When |
|---|---|
| transit -> station | the lead is within `legM/2 + arriveM` of the station centre, or `stationTimeoutSec` has passed since tasking |
| station -> rtb | `timeOnStationSec` has elapsed (if set). A relief is queued when `replaceOnRtb` |
| rtb -> gone | the lead is within 5 km of home or `rtbDespawnSec` has passed, **and** no enemy player is within `despawnMinPlayerM`. The group is then destroyed |
| any -> dead | `DMS.Registry.isAlive` is false. A replacement is queued when `replaceOnDead` |

Losses are also processed at `group.dead`, before the encounter tests whether it is cleared, so a
queued replacement keeps `encounter.cleared` from firing too early.

### Spawn limits and the director

- Each launch spawns exactly one group (pools use `count = 1`). The initial number of groups is
  `pool.pick`, scaled by `Director.scaleCount` and clamped to `maxSpawns`. A template gives 1.
- Replacements stop once `spawned + queued >= maxSpawns`. With no `maxSpawns`, there are no
  replacements.
- Every launch is **strictly** director-gated with `Director.canSpawn(cost)`, retried every
  `gateRetrySec`. Other kinds force their spawn once `maxDeferSec` has passed. A CAP launch
  instead drops after `maxDeferSec` (default 900 s) and logs
  `spawn skipped: director refused ...`. This means CAP never pushes the spawns-per-minute budget
  over its limit, which the 200-seed spec checks.
- `DMS.Spawner` still applies `budgets.maxActiveAir` and the 37 km minimum spawn distance from
  players.

### Bus events (new)

| Event | Payload |
|---|---|
| `encounter.cap_on_station` | `{id, encounter, group}` |
| `encounter.cap_rtb` | `{id, encounter, group}` |
| `encounter.cap_despawned` | `{id, encounter, group}` |
| `encounter.cap_lost` | `{id, encounter, group}` |

`encounter.spawned` (with `kind = "cap"`) and `encounter.cleared` behave as they do for the other
kinds.

### Helpers (exported for specs and tools)

- `DMS.Encounters.capStation(def) -> {center, pattern, point, point2?, altM, speed, radius, legM} | nil`
- `DMS.Encounters.capOrbitTask(station, number?)`
- `DMS.Encounters.capEngageTask(station, targetTypes?, number?)`

### Unverified in DCS **[?]**

- Whether OPEN_FIRE (rather than WEAPON_FREE) together with EngageTargetsInZone gives the intended
  "engage only inside the zone" behaviour.
- Whether AI aircraft hold the race-track until re-tasked.
- Whether `RTB_ON_BINGO` sends them to the nearest friendly airbase rather than along our RTB
  route. The state machine does not model a bingo RTB: such a group stays in `station` until it
  dies or its station time runs out.

## Ambient base traffic (`lua/src/dms/ambient.lua`)

`DMS_CONFIG.ambient` (see CONTRACTS) lists sites, normally one per player departure/recovery
airbase. `DMS.Ambient.start()` (last in `START_ORDER`) runs one `Clock.every(checkSec)` tick.

### Lifecycle per site

- **Inactive -> active**: a player unit of the site's coalition (`DMS.Spawner.playerUnits()`, so the
  DMS.Test proxy counts) within `activeRadiusM` of the site point. Emits `ambient.activated`,
  then fills layers one spawn per `staggerSec` in the order statics, ground, departures, helo,
  arrivals (never several in one frame).
- **Active**: every tick refreshes `lastNear` while a player is within `despawnRadiusM`, starts
  parked departures, removes departed/landed aircraft and re-fills layers below `count` (after
  `intervalSec` for departures/arrivals). A failed spawn logs its reason once
  (`[DMS][Ambient] Site 'x': skipped <layer> spawn (<reason>)`) and retries after 60 s.
- **Active -> inactive**: no player within `despawnRadiusM` for `graceSec`. Every group is
  `destroy()`ed and every static removed; emits `ambient.deactivated {reason = "left"}`. Pending
  staggered spawns are dropped (epoch counter). Returning within `activeRadiusM` re-activates.

### Layers and DCS tasking

| Layer | Spawn | Lifetime |
|---|---|---|
| departures | `uncontrolled = true`, first waypoint `TakeOffParking` / `From Parking Area` with `airdromeId`, unit `parking = Term_Index` on a free spot from `Airbase:getParking(true)` (Term_Type 68/72/100/104, plus 40 for helicopters), never inside `avoid` | `setCommand{id = "Start"}` once the runway gate is open and a random 60-240 s has passed; destroyed beyond `min(despawnRadiusM + distanceM/2, 0.9 distanceM)` from the site; replaced after `intervalSec` |
| arrivals | airborne `distanceM` out on a random bearing, route -> `Land` / `Landing` waypoint with `airdromeId` | destroyed 90 s after its `unit.landed`, or after 40 min |
| ground | 4 loop points: 30-55 m off random parking spots (or random land points within `radiusM`), never water/shallow water/runway, `avoid`, or within 25 m of a spot | re-routed (reversed) when the lead reaches the last point |
| helo | airborne on a 6-point circle (`radiusM`, `altM` RADIO), starting opposite the nearest player | route re-issued each lap |
| statics | `coalition.addStaticObject` (layer `category` passed through) on the same ground-point rules | until deactivation |

All groups get `SetImmortal`, `SetInvisible`, ROE weapon hold (air: reaction NO_REACTION;
ground: alarm GREEN) 1 s after spawn. Aircraft get `payload.fuel = 0.6 * Unit.getDescByName(type).fuelMassMax`
when that API answers, else no payload table.

**Runway gate**: departures are not started and arrivals are not spawned until a player of any
coalition registered in `DMS.Bus._players` has a `unit.takeoff`, or `departureDelaySec` has passed
since start. This keeps the runway free while the player starts up and taxis.

**Budgets**: `maxGroups`/`maxUnits` per site and globally (statics count as units only). Ambient
groups are not tracked in `DMS.Registry` and never emit `spawner.spawned`, so the Director's spawn
budget, `budgets.maxActive*` and `DMS.Test` spawn checks are unaffected; the Director ignores
`unit.dead`/`unit.shot` from ambient groups (`DMS.Ambient.isAmbient`). They are on the player's
coalition, so Intel never marks them.

### Unverified in DCS **[?]**

- `Airbase:getParking(true)` returning only free spots on every map, and `Term_Type` filtering
  keeping large transports (C-130) out of spots that are too small.
- Uncontrolled parked aircraft obeying `{id = "Start"}` after `SetImmortal`/`SetInvisible`.
- `Unit.getDescByName(type).fuelMassMax` (fallback: no payload; DCS may then spawn with 0 fuel).
- `Group:destroy()` of ambient groups not producing `unit.dead` (guarded anyway via `isAmbient`).
- Ground AI driving between apron points without blocking taxiways the player uses.
