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
- The following are sanitized and unavailable: `os`, `io`, `lfs`, `require` and `package.loadlib`.
  This is why we use a concatenation bundler ([ADR 0004](../adr/0004-concatenation-bundler.md)).
- For time, use `timer.getTime()` (mission seconds), `timer.getAbsTime()` (seconds since midnight)
  and `env.mission.date`.
- To skip the rest of a loop iteration without `goto`, wrap the loop body in a helper function and
  `return` from it.

## Timers and error handling

- If a callback passed to `timer.scheduleFunction` raises an error, that loop stops permanently and
  never fires again. Always `pcall` the callback body and return the next fire time anyway.
  `DMS.Clock` is the only module that calls the scheduler, and it handles this.
- Wrap `onEvent` handlers in `pcall` as well. `DMS.Bus` is the only module that calls
  `world.addEventHandler`.

## Ground AI

- **ROE values for ground units** are OPEN_FIRE (2), RETURN_FIRE (3) and WEAPON_HOLD (4).
  `WEAPON_FREE` applies to air units only.
- **Alarm state** is set with `AI.Option.Ground.id.ALARM_STATE` and takes AUTO, GREEN or RED.
- **`DISPERSE_ON_ATTACK`** takes a number of seconds. Set it to 0 to turn dispersal off.
- **Routes** are set with `setTask({id='Mission', params={route={points={...}}}})`.
  - Give the route at least 2 points, with the current position first **[? community lore]**.
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
- `hidden`, `hiddenOnMFD` and `hiddenOnPlanner` can only be set **at spawn time**.
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
- Mark IDs share **one global namespace with player marks**, so start our counter at about 10000.

## Events

- DEAD is unreliable.
  - Subscribe to DEAD, UNIT_LOST (30) and KILL (28) together, and deduplicate.
  - Cache unit positions, because the unit may already be invalid inside the DEAD handler.
- `initiator` and `target` may be nil, a StaticObject, scenery or a Weapon. Check `getCategory()`
  under `pcall`.
- PLAYER_ENTER_UNIT is unreliable. Detect players on BIRTH with `unit:getPlayerName() ~= nil`.

## Menus and sound

- Use `missionCommands.add*ForGroup`. Rebuild the menus on BIRTH, and pass the group ID or unit name
  through `arg`.
- Play sounds with `trigger.action.outSound('l10n/DEFAULT/x.ogg')`, or its ForCoalition, ForGroup
  and ForUnit variants. The file must meet three conditions:
  - It is in `l10n/DEFAULT/`.
  - It is listed in `mapResource` (`ResKey_*`).
  - A dummy trigger references it, so the Mission Editor doesn't strip it on save.
- The signature is `trigger.action.radioTransmission(file, vec3, modulation, loop, freqHz, power, name)`
  **[? a newer subtitle parameter]**.

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

- `os` isn't available, so seed by mixing the sub-second fraction of `timer.getTime()` at the first
  player BIRTH with `DMS_CONFIG.seed`. Burn a few values after seeding.
  **[? our recommendation, not verified]**

## Persistence

These are the options, in order of preference:

1. Native `.cmp` score-based stages.
2. `env.info("[DMS.OUTCOME] {json}")`, which the debriefer parses from `dcs.log`.
3. A manual questionnaire.
4. Opt-in de-sanitized `io`. Never require it.
