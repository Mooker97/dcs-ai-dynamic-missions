# DMS for Arma 3: "The Hill" (vanilla MVP)

This is a small, grounded solo mission for Altis. You lead a NATO squad on foot against a CSAT-held
compound, retrieve the intel, survive the reaction force and extract by helicopter. It uses no mods,
no dialogue and no voice.

**Status 2026-10-27 (real Arma 3 2.22, dedicated server, `tools/arma_harness`, see `docs/arma/TESTING.md`):**
- **Verified:** all class names (`docs/arma/kb/classes-verified.md`); the sites are now real terrain outposts
  (`docs/arma/kb/sites-verified.md`); there were no script errors in 3 runs. These steps PASS in real
  runs: spawns, alarm, artillery (5/5 rounds detonate within 150 m), QRF waves 1 and 2, intel, exfil
  request and heli spawn.
- **Not yet passing:** the AI test squad does not clear the outpost within 10 min (`compound_cleared`
  FAIL), so the exfil landing, boarding and win were never observed. A test-only `DMS_testAssist`
  param (harness `--assist 180`) was added but has not been run yet.
- **Needs a human playtest:** the comm menu and hold-action UI, feel and balance.
The TO VERIFY list below predates these runs. Items 1, 2 and 8 are now verified.

## Layout

```
arma/
  missions/dms_the_hill.Altis/
    mission.sqm           minimal text-format scenario: one playable team leader
    description.ext       params, CfgFunctions, comm menu, debriefings
    initServer.sqf        all setup, server-authoritative; fail monitor
    initPlayerLocal.sqf   briefing diary entries
    functions/
      fn_config.sqf       ALL tunables (sites, composition, skills, QRF, artillery, exfil, test)
      fn_log.sqf          [DMS] / [DMS.TEST] logging
      fn_rng.sqf          seeded Wichmann-Hill RNG (exact in SQF floats)
      fn_findPos.sqf      flat/clear ground and nearest-road snapping
      fn_spawnCompound.sqf  compound, garrison, statics, patrol, intel item
      fn_qrf.sqf          detection, alarm, QRF waves 1-2
      fn_support.sqf      virtual 82 mm mortar, comm-menu helper
      fn_intel.sqf        "Retrieve intel" hold action
      fn_exfil.sqf        extraction Ghost Hawk
      fn_end.sqf          single mission end + [DMS.OUTCOME] line
      fn_testMode.sqf     unattended AI run with PASS/FAIL checks
  tools/
    sqf_check.py          static checker (stdlib only)
    test_mission_files.py pytest suite
```

## Install

1. Copy `arma/missions/dms_the_hill.Altis` into one of these folders:
   - Single player / Eden: `Documents\Arma 3\missions\` (or `Documents\Arma 3 - Other Profiles\<name>\missions\`)
   - Multiplayer / dedicated: `<Arma 3 Server>\MPMissions\` (an unpacked folder works for local testing)
2. **Recommended first step:** open it once in Eden (Editor > Altis > Open > `dms_the_hill`), then
   save it with Attributes > General > *Binarize* unticked. The `mission.sqm` was written by hand
   to the documented Eden text format. A save from Eden normalises the header and addon list. The
   player unit starts in the sea at [1000, 1000] on purpose, and the server moves the squad into
   place in the first second.
3. Play it from Eden (Play > In Singleplayer), or host it as a 1-slot coop mission.

**Difficulty:** play on **Veteran**, or a custom profile with no crosshair, no enemy map tags and
no extended HUD. The mission gives no exact markers. The objective is a fuzzed 300 m area, and you
get task notifications plus a few short text hints from the mortars and the helicopter.

## How to play

- You start as team leader with six AI: autorifleman, grenadier, medic, AT rifleman, marksman and
  rifleman. They use vanilla loadouts. There is no respawn.
- The compound is about 1 km away, inside the red area. It holds two cargo houses, a patrol
  tower, sandbags, H-barriers and 2 HMGs. The defenders are 2 sentries at fixed posts, 5 riflemen
  holding building positions, 2 HMG gunners and a 3-man patrol. When alerted they fall back and
  hold their positions rather than charging.
- **Alarm:** this fires when any defender group's `knowsAbout` reaches 1.5 for a squad member,
  when a defender is killed, or when the intel is taken.
- **QRF:**
  - Wave 1 (a truck with 8 infantry) leaves a nearby town 5–8 min after the alarm. It drives by
    road and stops 350–500 m short. The infantry dismount, flank about 70° off the road axis, then
    search and destroy.
  - Wave 2 (an APC with 6 infantry, falling back to a truck) comes only if the fight drags past
    20 min after the alarm, or if wave 1 is wiped out within 5 min of spawning.
- **Mortars (comm menu `0-8`):**
  - *Spotting round* (3 available): one HE round.
  - *Fire for effect* (3 missions): 5 HE rounds, 50 m CEP. If a spotting round landed within
    150 m in the last 10 min, the CEP tightens to 25 m (adjust fire).
  - Each mission takes about 60 s to process plus 25 s time of flight.
  - Requests within 150 m of any friendly are refused (danger close).
- **Intel:** hold the action on the laptop on the table under the camo net (8 s).
- **Extraction (comm menu `0-8`, after the intel):**
  - The Ghost Hawk comes in from your start side.
  - It holds 1.5 km out while the LZ is hot: 3 or more known enemies within 200 m of the LZ, or
    any known armed enemy vehicle within 1200 m (`exfilHotRadius` / `exfilHotVehicleRadius`).
  - It lands and waits 150 s. It leaves when you and every living squad member within 400 m are
    aboard. AI members are ordered in, and after 60 s any within 30 m are seated directly.
  - If you are not aboard in time it leaves, and you can request it again.
- **Win:** the helicopter gets 1.2 km out with you aboard.
- **Fail:** you die, the squad is wiped out, or the extraction helicopter is destroyed.

## Parameters (lobby or `server.cfg`)

| Param | Values | Meaning |
|---|---|---|
| `DMS_seed` | 0 (random, logged), 1, 2, 3, 7, 42, 1337, 4242 | Seeds the site, positions, garrison classes, QRF origin and timing, and artillery dispersion. `server.cfg` can pass any integer. |
| `DMS_site` | 0 (from seed), 1–3 | Forces a site. |
| `DMS_debug` | 0/1 | Shows log lines in `systemChat` and puts markers on defenders and QRF spawns. |
| `DMS_testMode` | 0/1 | Runs the mission unattended with an AI squad. |
| `DMS_testMinutes` | 20–90 | Hard stop for test mode. |

The seed only controls the scripted choices. AI behaviour is not deterministic.

## Test mode (unattended, dedicated server)

In test mode the AI team leader's squad stands in for the player. In SP the player is parked hidden
and invulnerable, and the camera follows the AI leader. The harness then:
1. logs spawn checks
2. fires a mortar mission on the compound at T+60 s
3. advances to a staging point 350 m out, then searches and destroys
4. forces the alarm if none happens within 20 min
5. takes the intel once a squad member is inside the compound and two or fewer defenders remain
   (AI cannot use hold actions or the comm menu, so the harness calls the same server functions)
6. requests extraction and re-requests up to 3 times. For the move to the LZ it switches LAMBS
   Danger off for the squad (`lambs_danger_disableGroupAI` / `lambs_danger_disableAI`), sets
   YELLOW and `doFollow`, and orders `move` to the LZ if the leader moved less than 30 m in 60 s

When test compression (`DMS_testTimeScale`) shortens the QRF timers, floors keep the waves apart:
wave 1 comes at least 240 s after the alarm, the wave-2 drag check waits at least 600 s, and wave 2
at least 90 s after that. Normal play is unchanged. The `STATUS` line every 60 s includes the
leader's distance to the LZ, `currentWaypoint`, `behaviour` and `expectedDestination`.

Log lines look like this:

```
[DMS] INFO: Start: seed=42 site='...' ...
[DMS.TEST] PASS alarm detected
[DMS.TEST] PASS qrf_wave1 O_Truck_02_transport_F
[DMS.TEST] FAIL exfil_boarded not reached
[DMS.TEST] SUMMARY pass=12 fail=1 seed=42 site=...
[DMS.OUTCOME] result=WIN end=DMS_Win reason=extracted seed=42 site=... t=1934
```

The expected checks are `spawn_compound`, `spawn_garrison`, `spawn_intel`, `spawn_squad`,
`artillery`, `alarm`, `compound_cleared`, `intel`, `qrf_wave1`, `exfil_requested`, `exfil_landed`,
`exfil_boarded` and `outcome_win`. Any check never reached is logged as FAIL in the summary.

Example dedicated-server setup:

```
// server.cfg
persistent = 1;
class Missions {
	class DMS { template = "dms_the_hill.Altis"; difficulty = "Veteran";
		class Params { DMS_testMode = 1; DMS_seed = 42; DMS_testMinutes = 45; DMS_debug = 1; }; };
};
```
`arma3server_x64.exe -config=server.cfg -profiles=out -autoInit`. Then grep the `.rpt` in `out\`
for `[DMS`. `-autoInit` needs `persistent = 1`. With `disabledAI = 1` the player slot stays empty,
and the script builds the AI squad.

## Design choices

- **Artillery:** a custom virtual mortar section (`Sh_82mm_AMOS` shells spawned above the impact
  point) driven from `CfgCommunicationMenu` + `BIS_fnc_addCommMenuItem`. I chose it over the
  Support modules and `BIS_fnc_fireSupportVirtual` for these reasons:
  - exact round counts
  - seeded Rayleigh dispersion from a CEP
  - adjust-fire and danger-close rules in about 100 lines
  - the test harness can call it without UI
- **Intel:** `BIS_fnc_holdActionAdd`, remote-executed to all clients with a JIP id tied to the
  object. I chose it over `BIS_fnc_initIntelObject` because the hold time is realistic and the
  server gets one callback.
- **Placement:** sites are approximate. The compound centre snaps to the flattest clear spot
  (no buildings, rocks or roads) within 250 m. Trees, bushes and walls within 32 m are hidden. QRF
  spawns and dismount points snap to the nearest road.
- **Everything is server-side.** Commands that need a local argument on player-owned units
  (`setPosATL`, `setDir`, `moveInCargo`, `assignAsCargo`, `orderGetIn`) go through
  `remoteExecCall` to the unit's owner.

## Verification

`uv run pytest arma -q` (37 tests) and `uv run python arma/tools/sqf_check.py arma/missions/dms_the_hill.Altis`.

What is checked statically:
- brackets, strings and comments
- trailing commas
- missing-semicolon heuristic
- `x call f + y` and `sleep (a) + b` precedence traps
- private-variable hygiene
- no engine `random` outside `fn_rng` (except the logged seed pick)
- every `DMS_fnc_*` is declared and has a file, and every file is declared
- every `DMS_cfg get "key"` exists in `fn_config`
- comm-menu and debriefing classes exist
- `description.ext` and `mission.sqm` parse
- `mission.sqm` structure: item counts, one player, unique ids
- comm-menu `expression` strings are checked as SQF

The checker cannot catch wrong command arguments, locality bugs or AI behaviour.

## TO VERIFY in game

1. **Site coordinates** (all approximate): Pyrgos farmland [17600, 13200], Zaros countryside
   [10600, 12800], Frini plateau [14600, 20200]. Also the QRF towns: Pyrgos [16800, 12700],
   Chalkeia [20200, 11700], Zaros [9100, 11800], Neochori [12500, 14300], Athira [14000, 18700],
   Galati [10300, 19100]. For each site, check road access for the QRF, an open LZ on the start
   side, and that the snapped compound does not sit on a slope or in a village.
2. **Class names:**
   - QRF vehicles: `O_Truck_02_transport_F`, `O_Truck_03_transport_F`,
     `O_APC_Wheeled_02_rcws_v2_F` / `_rcws_F`
   - Compound objects: `CamoNet_OPFOR_open_F`, `Land_CampingTable_F`, `Land_Laptop_unfolded_F`,
     `Box_East_Ammo_F`, `Land_Razorwire_F`
   - Shell: `Sh_82mm_AMOS`

   Missing compound classes are skipped with a WARN log. For QRF vehicles the first class that
   exists is used.
3. `mission.sqm`: it loads, the player starts in the sea and is moved at once, and no "addon
   missing" warning appears.
4. `BIS_fnc_taskCreate` with an `objNull` destination (meant as "no 3D marker").
5. Comm-menu `expression` receives `[caller, position, target, is3D, id]` as `_this`. Check the
   icon/cursor paths too.
6. `_heli land "NONE"` cancels the landing before lift-off, and `land "GET IN"` keeps the engine
   running.
7. The laptop sits on the table top (it uses `boundingBoxReal`), and `Land_Cargo_House_V1_F` /
   `Land_Cargo_Patrol_V1_F` give at least 5 building positions between them (a WARN is logged if
   not).
8. Spawned shells with downward velocity detonate on impact.
9. In MP: `createUnit` into the player's (remote) group, and the dedicated end path
   (`BIS_fnc_endMission` to all, then `endMission`/`failMission` on the server).
10. Balance: the skill values in `fn_config.sqf` (aimingAccuracy 0.18, spotDistance 0.7), the
    QRF timings and the exfil hot-LZ threshold.

## Notes vs `docs/arma/RESEARCH.md`

The research plan names the folder `DMS_Raid.Altis` with functions in `fn/`. This mission uses
`dms_the_hill.Altis` and `functions/`, as requested. The research plan spawns the squad by script
and keeps a minimal player-only `mission.sqm`, and this mission does the same. Both use the same
log contract: `[DMS.TEST]` lines plus one `[DMS.OUTCOME]` line.
