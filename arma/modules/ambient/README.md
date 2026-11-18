# Ambient "base life" module (DMSA)

Status: implemented, not flown. Static checks pass (`uv run pytest arma`). The headless run is
`arma/missions/dms_baselife.Altis`.

When a player is at a friendly base, at the start or the end of a mission, this module adds some
activity around them: sentries at the entrances, soldiers idling by the buildings, a work party on
a parked vehicle, 1–3 vehicles driving round the base roads and a transport helicopter that comes in,
lands, waits and leaves. Everything is spawned only while someone is near, and it is deleted once
everyone has left, to save CPU.

## Drop it into a mission

1. Copy this folder to `<mission>/modules/ambient/`. You need `cfgFunctions.hpp` and `functions/`.
   The README and CLASSES files are optional.
2. Include the functions inside the mission's `class CfgFunctions` in `description.ext`. The module
   has its own tag, `DMSA`, so it never clashes with the mission's `DMS` functions:
   ```cpp
   class CfgFunctions
   {
       class DMS { /* the mission's own functions */ };
       #include "modules\ambient\cfgFunctions.hpp"
   };
   ```
   If you put the folder somewhere else, change the `file = "modules\ambient\functions";` line in
   `cfgFunctions.hpp`.
3. Add a site on the server, for example in `initServer.sqf`:
   ```sqf
   ["main_base", [16001, 17042, 0], createHashMapFromArray [["faction", "auto"]]] call DMSA_fnc_ambientAdd;
   ```

`arma/missions/dms_baselife.Altis/modules/ambient/` is a byte-identical copy of this folder. Edit
the copy here first, then copy it there. `arma/tools/test_dms_baselife.py` fails if the two differ.

## API (server only)

| Call | Does |
|---|---|
| `[_siteId, _centerPos, _opts] call DMSA_fnc_ambientAdd` | Surveys the site and starts its monitor. Returns `_siteId`, or `""` on error |
| `[_siteId] call DMSA_fnc_ambientRemove` | Despawns and unregisters the site. Run it scheduled (it sleeps briefly while deleting groups) |
| `[_siteId, _deep] call DMSA_fnc_ambientCount` | Counts tagged objects in the world: `[units, vehicles, groups, objects]`. `""` counts every site. `objects` is `-1` unless `_deep` is true |
| `DMSA_sites get _siteId` | The site state hashmap: `active`, `activations`, `units`, `vehicles`, `groups`, `lastSpawn`, `heliSpawned`, `heliLanded`, survey results, ... |
| `DMSA_watchers = [obj, ...]` | Extra objects that activate sites, for example an AI test squad |
| `DMSA_debug = true` | DEBUG log lines and systemChat. `DMS_debug` also works |

### `_opts` (hashmap, every key optional)

| Key | Default | Meaning |
|---|---|---|
| `activeRadius` | 600 | A watcher within this range spawns the site, staggered |
| `despawnRadius` | 900 | Once every watcher is beyond this range for `despawnDelay` s, everything is deleted. This is the hysteresis band. It is forced to at least `activeRadius + 50` |
| `despawnDelay` | 30 | Seconds |
| `maxUnits` / `maxVehicles` | 24 / 4 | Hard caps, crews included. Each layer checks them before it spawns |
| `faction` | `"auto"` | `"auto"` (`rhs_usarmy` when RHS USAF is loaded, else `vanilla_nato`), `"vanilla_nato"`, `"rhs_usarmy"` or `"rhs_usmc"` |
| `side` | preset | The ambient groups' side |
| `classes` | — | Hashmap that overrides preset lists: `infantry`, `sentry`, `worker`, `driver`, `traffic`, `parked`, `heli` |
| `idleGroups` | 3 | Groups of 2–3 men on `BIS_fnc_ambientAnim` next to buildings that have building positions |
| `sentries` | 2 | Posts at vanilla bar gates (`Land_BarGate_F`), or else at the outermost road points. `disableAI "PATH"`, standing, watching outwards |
| `workParty` | true | A parked vehicle with up to 3 men on the `REPAIR_VEH_STAND` / `REPAIR_VEH_KNEEL` / `KNEEL` animations |
| `traffic` | 2 | 0–3 vehicles, driver only, on a `CYCLE` loop of road points at least 120 m apart (from `nearRoads`), `LIMITED` speed with `limitSpeed 30`, `CARELESS`, combat mode `BLUE` |
| `heli` | true | Transport helicopter visits, which need a pad (see Survey) |
| `heliFirstDelay` / `heliInterval` / `heliWait` | [60,180] / [300,600] / [40,90] | Seconds, seeded range |
| `heliSpawnDist` | 3500 | The helicopter appears at this distance, and leaves to it on the far side before it is deleted |
| `invulnerable` | false | `allowDamage false` on every ambient unit and vehicle. The default is that they can die |
| `watchPlayers` | true | Players activate the site. Test missions set this false and use `DMSA_watchers` |
| `watchers` | [] | Per-site extra watchers |
| `pollInterval` | 5 | Seconds between monitor checks |
| `seed` | `DMS_seed` or 1 | Seeds the module's own RNG, `DMSA_fnc_ambientRng`. It never shifts the mission's `DMS_fnc_rng` draws |

## Behaviour

- **Survey (once, in `ambientAdd`).** Finds the road loop points, the idle spots, the sentry posts,
  the work-party parking spot and the helicopter pad. The pad is an existing `HeliH` helipad
  within `activeRadius`, or else a flat empty spot from `isFlatEmpty`. It all goes in one log line:
  `[DMS] INFO: Ambient [id] survey: roads=… loopPoints=… idleSpots=… sentryPosts=… work=… pad=…`.
  Coordinates you hand-pick only need to be roughly right, because the module snaps to what it
  finds there.
- **Activation.** Any watcher within `activeRadius` triggers the spawn. The order is sentries, idle
  groups, work party, traffic, then the helicopter thread. It is staggered by 0.3–1 s per unit or
  vehicle.
- **Despawn.** Once every watcher has been beyond `despawnRadius` for `despawnDelay` s, the module
  deletes crews (`deleteVehicleCrew`), vehicles, units (plus the ambient-anim helper logic), the
  helipad and then the empty groups (`deleteGroup`). A vehicle with a player aboard is kept, with
  its crew, and logged. Coming back re-activates the site and spawns it fresh.
- **Ambient units never fight.** Every group is combat mode `BLUE`, relaxed (`SAFE`, or `CARELESS`
  for drivers and the helicopter), with LAMBS Danger turned off through
  `group setVariable ["lambs_danger_disableGroupAI", true]` and
  `unit setVariable ["lambs_danger_disableAI", true]`. Both names were checked in the LAMBS 2.6.2
  PBOs (`lambs_danger.pbo` 3DEN attributes and `fnc_isForcedExit`). They are harmless when LAMBS
  isn't loaded. `setCaptive false` keeps them real targets for an enemy.
- **Tagging.** Every unit, vehicle, group and helper object has `DMSA_ambient = _siteId`. Exclude
  them from mission logic, for example:
  ```sqf
  private _eastAlive = {alive _x && {side group _x == east} && {(_x getVariable ["DMSA_ambient", ""]) == ""}} count allUnits;
  ```
- **Logging.** Lines look like `[DMS] INFO: Ambient [id] ...`, the same format as `DMS_fnc_log`:
  `site added`, `survey`, `activate #n`, `spawned units=… vehicles=… groups=… (sentries idle work traffic heli)`,
  `heli … inbound/landed/departing/removed`, `despawn (reason): removed units=… vehicles=… groups=…`,
  and WARN lines for missing classes, missing roads and a heli that did not land.

## Known limits and TO VERIFY

- `BIS_fnc_ambientAnim` plays its moves with `switchMove`/`playMoveNow` where the unit is local,
  which is the server. In single player and player-hosted games that is also the player's
  machine. On a dedicated server with remote clients the idle animations may not be seen
  (TO VERIFY). The solo use case is unaffected.
- The animation set names (`STAND`, `STAND_IA`, `SIT_LOW`, `KNEEL`, `WATCH1`, `WATCH2`,
  `REPAIR_VEH_STAND`, `REPAIR_VEH_KNEEL`) were read from `A3\Functions_F\Ambient\fn_ambientAnimGetParams.sqf`
  in the installed game. How they look next to real buildings has not been checked in game.
- Gates: `Land_BarGate_F` and the `HeliH` helipad base class are not in
  `docs/arma/kb/classes-verified.md` (TO VERIFY). If either is wrong, the road-entrance and
  flat-ground fallbacks take over, and the survey line shows which one was used.
- Traffic uses whatever `nearRoads` returns. Airfield taxiways are not roads, so on an airfield
  the loop may stay on the service roads. If a vehicle gets stuck it stays stuck until the next
  activation, and the test's `ambient_traffic_moving` check reports it.
- Classes: see [CLASSES.md](CLASSES.md).
