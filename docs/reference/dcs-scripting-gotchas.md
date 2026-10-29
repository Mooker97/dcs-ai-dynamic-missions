# DCS scripting gotchas

These are practical rules for writing Lua that runs inside the DCS mission scripting environment.
They were checked against the Hoggit wiki, the ED forums and the MOOSE source in October 2026.
Items marked **[?]** have not been verified in DCS yet. Confirm them in a flight test before you
rely on them, then remove the marker.

Related: [miz-format.md](miz-format.md) · [ADR 0003](../adr/0003-own-lua-core-optional-moose.md) ·
[CONTRACTS](../CONTRACTS.md)

## Language and sandbox

- DCS runs **Lua 5.1**, which means:
  - There is no `goto`, no `::label::`, no `//` and no bitwise operators.
  - Use `unpack`, not `table.unpack`.
- The following are sanitized and unavailable: `os`, `io`, `lfs`, `require`, `loadlib` and the
  whole `package` table (verified in the installed `Scripts/MissionScripting.lua`, 2026-10-29).
  This is why we use a concatenation bundler ([ADR 0004](../adr/0004-concatenation-bundler.md)).
- For time, use `timer.getTime()` (mission seconds), `timer.getAbsTime()` (seconds since midnight)
  and `env.mission.date`.
- To skip the rest of a loop iteration without `goto`, wrap the loop body in a helper function and
  `return` from it.

## Timers and error handling

- If a callback passed to `timer.scheduleFunction` raises an error, that loop stops permanently and
  never fires again. Always `pcall` the callback body and return the next fire time anyway.
  `DMS.Clock` is the only module that calls the scheduler, and it handles this.
- Never schedule for exactly `timer.getTime()` during mission start. In the m03 headless run
  (2026-10-28), two encounters with `afterSec = 0` never ran while a 30 s one did. `DMS.Clock`
  now schedules every first run at least 0.05 s ahead. With that, m03's two `after_min: 0`
  encounters (fort_positions, armor_line) spawned at t=0 (headless DCS 2026-10-29). Not proven in
  isolation that the exact-now schedule was the cause.
- Wrap `onEvent` handlers in `pcall` as well. `DMS.Bus` is the only module that calls
  `world.addEventHandler`.

## Ground AI

- **ROE values for ground units** are OPEN_FIRE (2), RETURN_FIRE (3) and WEAPON_HOLD (4).
  `WEAPON_FREE` applies to air units only.
- **Alarm state** is set with `AI.Option.Ground.id.ALARM_STATE` and takes AUTO, GREEN or RED.
- **`DISPERSE_ON_ATTACK`** takes a number of seconds. Set it to 0 to turn dispersal off.
- **Routes** are set with `setTask({id='Mission', params={route={points={...}}}})`.
  - Give the route at least 2 points, with the current position first. MOOSE `RouteGroundTo`
    builds exactly `{FromWP (current), ToWP}` ([Controllable.lua](https://github.com/FlightControl-Master/MOOSE/blob/master/Moose%20Development/Moose/Wrapper/Controllable.lua)).
    A 1-point route does nothing: a BTR-80 given `{id='Mission'}` with one point 2 km away had
    moved 0 m after 60 s and 180 s (headless DCS 2026-10-29, Syria, DCS 2.9.31).
  - A route point's `y` is the Vec3 `z`.
  - Speeds are in m/s.
  - Point actions are Off Road, On Road, Cone, Rank, Diamond, Vee and EchelonL/R.
- **Commands**:
  - `StopRoute`: `setCommand({id='StopRoute', params={value=true|false}})`.
  - `SwitchWaypoint` and `Hold`.
  - `FireAtPoint {point={x,y}, radius, expendQty, expendQtyEnabled}`.
- AttackGroup and AttackUnit tasks are **broken for ground units**. Use routes, FireAtPoint or
  proximity instead.

## Spawning

- Spawn with `coalition.addGroup(country.id.X, Group.Category.GROUND, data)`.
- Omit `groupId` and `unitId` and DCS assigns them.
- **A name clash replaces the existing group.** Allocate every name through
  `DMS.Registry.allocName`.
- Wait about 1 s before touching a new group's controller with tasks or options.
- Late activation: the group exists, but `unit:isActive()` is false until you call
  `grp:activate()`. `DMS.Registry.isAlive` accounts for this.
- `hidden`, `hiddenOnMFD` and `hiddenOnPlanner` are group-level fields of the `coalition.addGroup`
  table and can only be set **at spawn time**. There is no runtime setter
  ([Hoggit addGroup](https://wiki.hoggitworld.com/view/DCS_func_addGroup)).
- Never spawn where the player can see it. Rough minimum distances: ~20 nm for air, ~5 km for
  ground, and always outside line of sight.

## Terrain and zones

- `land.getSurfaceType({x=, y=})` returns LAND, SHALLOW_WATER, WATER, ROAD or RUNWAY.
- To check for obstacles, use `world.searchObjects(Object.Category.SCENERY, sphere, cb)`.
- `land.isVisible(p1, p2)` checks terrain line of sight only. It ignores trees and buildings.
- `trigger.misc.getZone(name)` returns only `{point, radius}`.
  - Quad zones are in `env.mission.triggers.zones[i]` with `type == 2` and a `verticies` list
    (misspelled in DCS).
  - Use a point-in-polygon test for them.

## F10 map and fog of war

- Units can't be hidden or revealed at runtime, and the map view mode can't be scripted.
  [ADR 0008](../adr/0008-fog-of-war-hidden-plus-marks.md) describes our approach.
- **Mark functions**:
  - `markToAll`, `markToCoalition`, `markToGroup`
  - `circleToAll(coal, id, center, r, color, fill, lineType, readOnly, msg)`
  - `lineToAll`, `quadToAll`, `textToAll`
  - `setMarkupText`, `setMarkupColor`, `setMarkupPositionStart`, `removeMark`
- Mark IDs share **one global namespace with player marks and markup shapes**
  ([Hoggit markupToAll](https://wiki.hoggitworld.com/view/DCS_func_markupToAll)). Player-made marks
  get IDs around 251,000,000 and up ([ED forum](https://forum.dcs.world/topic/276775-getting-next-marker-idx)).
  `DMS.Intel` starts at 50000, stays in its band (50000 to 10,050,000) and only ever grows.
  - Never raise our counter to a player mark's ID, or our next ID lands on the next player mark.
  - Never reuse an ID, even after `removeMark`. A reused ID fires MARK_ADDED but doesn't render
    ([ED bug report](https://forum.dcs.world/topic/319761-triggeraction-bug-dcs-backend-remembers-old-id-numbers-even-after-youve-done-removemark)).
- `world.getMarkPanels()` returns mark panels **and markup shapes** (`circleToAll`, `textToAll`, ...).
  Each entry has `{idx, time, initiator, coalition, groupID, text, pos}`. A shape drawn for all
  coalitions may report coalition 255, and a shape's `pos` is about the average of its points
  ([Hoggit](https://wiki.hoggitworld.com/view/DCS_func_getMarkPanels)). Verified (headless DCS
  2026-10-29, DCS 2.9.31): `circleToAll(-1, ...)` is listed with `text = ""`, coalition 255 and
  `pos` at the centre (y = terrain height); `markToAll` also reports coalition 255;
  `markToCoalition(.., 2, ..)` reports 2. The m01 runs' `f10_marks` check found circles 3/3 and
  text 4/4. The mock (`lua/mocks/dcs.lua`) matches this.
- Script-made marks have `initiator == nil` and `groupID == 4294967295` (-1 as an unsigned 32-bit
  value), whether made by `markToAll`, `markToCoalition` or `circleToAll` (headless DCS 2026-10-29).
  `DMS.Test` ghost detection relies on `initiator == nil`.

## Events

- DEAD is unreliable.
  - Subscribe to DEAD, UNIT_LOST (30) and KILL (28) together, and deduplicate.
  - Cache unit positions, because the unit may already be invalid inside the DEAD handler.
- `initiator` and `target` may be nil, a StaticObject, scenery or a Weapon. Check `getCategory()`
  under `pcall`.
- PLAYER_ENTER_UNIT is unreliable. Detect players on BIRTH with `unit:getPlayerName() ~= nil`.
- PLAYER_LEAVE_UNIT can arrive after the unit is already destroyed, so `initiator:getName()` may fail.
  On a slot change, the new aircraft's BIRTH comes **before** the old aircraft's LEAVE
  ([ED forum, 2024](https://forum.dcs.world/topic/345478-onevent-bug-eventinitiator-for-unit-on-death-or-on-leave-unit-is-broken-because-its-already-been-destroyed)).
  Keep a name for every unit from BIRTH onwards. `DMS.Bus` keeps `_objNames` (object `id_` -> unit
  name) for players and ignores a leave or death whose object id is older than the current entry.
- Ejection and pilot death:
  - In EJECTION, `initiator` is the aircraft. `target` is the seat for aircraft with ejection seats
    (DISCARD_CHAIR_AFTER_EJECTION follows with the pilot), and the pilot otherwise
    ([Hoggit](https://wiki.hoggitworld.com/view/DCS_event_ejection)). In PILOT_DEAD, `initiator` is
    the aircraft unit.
  - The order isn't fixed. A mortally wounded player can log PILOT_DEAD, then EJECTION, then CRASH
    ([ED forum, 2021](https://forum.dcs.world/topic/273075-players-can-eject-bail-out-after-death/)).
  - A player who ejects and stays in the parachute is not reported by `getPlayerName()` on the
    parachute unit. Deleting that unit later raises PILOT_DEAD for the *aircraft*, possibly minutes
    afterwards ([ED forum](https://forum.dcs.world/topic/288749-player-ejecting-the-parachute-guy-isnt-recognized-as-player-unit-but-does-create-pilot_dead-event-when-deleted)).
    LANDING_AFTER_EJECTION has the pilot as `initiator` and the aircraft as `place`.
  - **[? where PLAYER_LEAVE_UNIT falls relative to EJECTION and PILOT_DEAD for a player who ejects:
    needs a cockpit run that logs every event with `timer.getTime()`. Headless runs only cover AI.]**

## Menus and sound

- Use `missionCommands.add*ForGroup`. Rebuild the menus on BIRTH, and pass the group ID or unit name
  through `arg`.
- Play sounds with `trigger.action.outSound('l10n/DEFAULT/x.ogg')`, or its ForCoalition, ForGroup
  and ForUnit variants. The file must be inside the `.miz`
  ([Hoggit](https://wiki.hoggitworld.com/view/DCS_func_outSoundForGroup)). We also apply these rules:
  - Put it in `l10n/DEFAULT/`.
  - List it in `mapResource` (`ResKey_*`). On save, the Mission Editor re-packs `l10n/<dict>/` files
    **only if `mapResource` lists them**, while files outside `l10n/` and `l10n/*/KNEEBOARD/` are
    always kept (verified in the installed `Scripts/dictionary.lua` `packMissionResources`/`unpackFiles`).
  - Reference it from a never-firing keeper trigger. The ME drops a key from `mapResource` when
    someone edits or deletes the action that uses it, and this is also the community's standard fix
    ([ED forum](https://forum.dcs.world/topic/291580-add-a-sound-file-to-be-used-by-triggeraction-outsound)).
  - **[? whether the *sim* (not the ME) needs the `mapResource` entry to play a file]** Headless
    can't settle it: `outSoundForCoalition` and `radioTransmission` on a file that doesn't exist
    raise no Lua error and log nothing in dcs.log (headless DCS 2026-10-29, `ED_SOUND` uses the
    dummy driver with `--norender`). A clean dcs.log therefore doesn't prove a file played;
    that needs a cockpit check.
- The scripting signature is `trigger.action.radioTransmission(file, vec3, modulation, loop, freqHz, power, name)`.
  DCS 2.9.25 added subtitles to the ME **trigger action**, which the ME serializes as
  `a_radio_transmission(file, zone, mod, loop, freqKHz, power, name, delay, mic, squelch, text, subtitleSec)`
  ([changelog](https://www.digitalcombatsimulator.com/en/news/changelog/release/2.9.25.21123/)).
  MOOSE still passes 7 arguments and says trigger transmissions can't carry subtitles
  ([Radio.lua](https://github.com/FlightControl-Master/MOOSE/blob/master/Moose%20Development/Moose/Sound/Radio.lua)).
  `trigger.action.radioTransmission` accepts an 8th string and a 9th number without error (headless
  DCS 2026-10-29). Whether it *uses* them as a subtitle can't be seen headless (cockpit check).
- `radioTransmission` is a real transmitter. Reception fades and gets noisy with distance and low
  `power` (in W), and needs line of sight, so altitude matters. Reports:
  - 50 W ground emitters are inaudible beyond about 35 nm since DCS 2.9
    ([ED forum](https://forum.dcs.world/topic/372080-not-a-bug-but-a-question-comm-distance-from-ground-unit)).
  - Campaign authors place the source within about 1 nm of the player and use 10000 W, which is the
    ME maximum ([ED forum, 2025](https://forum.dcs.world/topic/381336-radio-transmission-degradation-how-to-solve);
    `me_trigrules.lua` `power` max = 10000).
  - Cloud layers between transmitter and receiver were reported to degrade audio (same thread).
  - The source position is fixed for the whole clip.
  - Don't put the source exactly on the player. Use at least `y + 1`.
- DMS.Comms transmits at 10000 W from 150 m above each listener group's first player: one
  `radioTransmission` per player group on the frequency (groups within 2 nm share one), each with
  its own name. Group lines use only that group. In a `DMS.Test` proxy run (no human player) the
  proxy group stands in, so headless runs exercise `radioTransmission` too (m01: 20/20 lines
  `via=radio tx=1`, no script errors, headless DCS 2026-10-29). **[? exact range model: headless test can't hear
  audio, so this needs a cockpit A/B at 5, 20 and 50 km, 1000 W vs 10000 W]**

## Detection, skill, weather

- Detection: `ctrl:getDetectedTargets(...)` and `ctrl:isTargetDetected(obj, ...)`.
- **Skill can't change at runtime.** Adaptive difficulty applies only to *new* spawns.
- **Weather can't change at runtime.** It's set at generation time.

## Performance

- The practical limits are about 150–300 active ground units and 20–40 AI aircraft. Enforce them
  with `DMS_CONFIG.budgets`.
- Run schedulers every 5–15 s.
- In multiplayer, stagger spawns 1–3 s apart.

## RNG

- `os` isn't available, and time gives no entropy in single player: DMS boots at t = 0 with the
  mission's fixed start time, so a time-only seed was identical on every launch of a .miz (two m01
  runs: `seed=800998044` both, same spawns; headless DCS 2026-10-29). `DMS.Rng.seed()` therefore
  also mixes `Rng.launchEntropy()`: the heap address of a fresh table and closure
  (`tostring({})`, which differs between DCS processes) plus the GC byte count. Re-run: seeds
  2715297192 vs 1588303233 with different spawn positions and line variants. Burn a few values
  after seeding. `DMS.Rng` is independent of `math.random`.
- `math.random` does *not* repeat across launches: three calls at mission load gave
  0.4029/0.8970/0.9885 and 0.2373/0.5131/0.7700 on two launches of the same .miz (headless DCS
  2026-10-29). Don't rely on it either way.

## Persistence

These are the options, in order of preference:

1. Native `.cmp` score-based stages.
2. `env.info("[DMS.OUTCOME] {json}")`, which the debriefer parses from `dcs.log`.
3. A manual questionnaire.
4. Opt-in de-sanitized `io`. Never require it.

## AI flights (DMS.Flights, v0.9) **[? all unverified: implemented, not flown]**

- Tasks used: `Mission` (2 points, current position first, `alt_type` per point), `Orbit` (Circle)
  on the second waypoint's ComboTask, `EngageTargetsInZone` on the first waypoint (CAP pattern),
  `Land {point, durationFlag, duration}` as a main task for helicopters, a `Land`/`Landing`
  waypoint with `airdromeId` for planes and RTB, `Escort {groupId, pos, engagementDistMax,
  targetTypes}`, `AttackGroup` and `Bombing` with `expend = "All"`.
- Open questions for a headless run: whether helicopters accept `Escort` (may need `Follow`);
  whether `Land` with `durationFlag = false` keeps a helicopter on the ground indefinitely;
  whether a plane landed mid-orders takes off again on a new `Mission`; the numeric
  `weaponType` for `Auto` (Hoggit 1073741822 vs MOOSE 3221225470); whether `ROE = OPEN_FIRE` is
  enough for `AttackGroup`/`EngageTargetsInZone`; whether `S_EVENT_SHOT` fires for every bomb
  release of an AI flight.
- **Strike: AttackGroup piles onto one unit.** In the w01 watch run (2026-10-29) a two-ship F-16
  given `AttackGroup` (expend All, GuidedBomb) put every bomb from both jets on the same truck,
  left one truck alive and went home. `DMS.Flights` now gives a group a `ComboTask` of one
  `AttackUnit` per aircraft on different units (`groupAttack = false`, `attackQty = 1`) and
  re-tasks on survivors for up to 3 passes. **[? headless check]** that the AI splits the
  AttackUnit tasks across wingmen rather than running them in sequence with the whole flight.
- **Helicopters at ~40 kt.** In the same run the UH-60A and AH-64D flew about 40 kt with orders
  compiled at 110-135 kt. The waypoints we hand DCS look right (`speed` in m/s, `speed_locked =
  true`, `ETA_locked = false`, `Turning Point`, current position first, Orbit speed = order
  speed). Likely causes **[? headless check]**: a bare `Land` main task flies the transit at the
  AI's own slow approach speed (now: route at cruise until 2 km, then `Land`); `Orbit` holds,
  `EngageTargetsInZone` and `Escort` (which matches the escorted helicopter) are flown slowly by
  helicopter AI. Use the `TELEM` log (`DMS_CONFIG.flightsTelemetry = true` or debug) to see
  speed per order.
- `Unit.getAmmo()` returns nil for a unit with no ammo left; entries are `{count, desc}` with
  `desc.category` (Weapon.Category) and, for missiles, `desc.missileCategory`.
  **[? `desc.guidance` present only on guided bombs]**.
