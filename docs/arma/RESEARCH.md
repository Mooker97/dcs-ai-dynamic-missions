# Arma 3 MVP: research and build plan

Status: research draft, 2026-10-27. Scope was cut by the user (see below). **[U]** marks something not verified
against a live install or a primary source. The BI wiki returned 403 to automated fetches, so confirm class names
with the M1 `isClass` sweep or the in-game Config Viewer.

**MVP flow (vanilla, Altis, daytime, solo + AI squad 4–8):**
1. The squad starts on foot about 1 km from a small CSAT-held compound (one of 2–3 candidates).
2. Assault the compound, then hold-action "retrieve intel" (laptop or documents).
3. A QRF of 1–2 waves (trucks + infantry, optionally one APC) triggers on detection or on intel pickup.
4. Limited artillery is available through the comm menu.
5. Call the extraction Ghost Hawk to an LZ near the compound and board. Success.

Fail: the player dies (or the squad is wiped), or the extraction heli is destroyed.

## 1. Mission structure

Folder `DMS_Raid.Altis/`:

- `mission.sqm`: **minimal**. Only the playable `B_Soldier_SL_F` player. Save it from Eden with Attributes >
  General > *Binarize* unticked, which gives a text `class Mission` that git can diff. Do not hand-write the header
  (`version`, `addons[]`, `ItemIDProvider`) **[U]**. The squad is spawned by script and `joinSilent`ed to
  `group player`. The sqm could also hold the squad, but that is not needed.
- `description.ext`:
  - `onLoadName`, `respawn = 0`
  - `class Header { gameType = Coop; minPlayers = 1; maxPlayers = 1; };`
  - `class CfgFunctions` (folder `fn/`)
  - `class CfgCommunicationMenu` (artillery, extract)
  - `class CfgDebriefing` (Win / Dead / HeliLost)
  - `class Params` (`DMS_test`, `DMS_seed`, `DMS_site`)
- `initServer.sqf`: all spawning and logic, server-authoritative.
- `initPlayerLocal.sqf`: comm menu and hold-action UI. Gate it with `hasInterface`.
- **Packing:** an unpacked folder in `MPMissions/` works for local/dedicated testing. For release, pack it with
  AddonBuilder or FileBank from the free *Arma 3 Tools* **[U: CLI flags]**. Packing avoids a known unpacked-mission
  client kick bug ([T160204](https://feedback.bistudio.com/T160204)). [HEMTT](https://github.com/BrettMayson/HEMTT)
  is addon-focused, and its mission support is **[U]**.

## 2. Vanilla systems

- **Squad:** native squad command for AI in the player's group. Spawn the squad with `BIS_fnc_spawnGroup` and
  `joinSilent` it.
- **Compound garrison:** use `BIS_fnc_spawnGroup` with CfgGroups paths and give the groups `"GUARD"`/`"SAD"`
  waypoints. Put static gunners in the bunkers. For idle groups, set `enableDynamicSimulationSystem true` and
  `_grp enableDynamicSimulation true`.
- **Detection:** a server loop on `(east knowsAbout player) > 1.5`, backed by a "Detected by" trigger
  (`setTriggerActivation ["WEST","EAST D",false]`) and `FiredNear` EHs on the guards. The first of these sets
  `DMS_alarm`.
- **Intel:** `BIS_fnc_holdActionAdd` on `Land_Laptop_unfolded_F` / `Land_File1_F` (about 6 s). On completion it
  calls `fn_intelTaken`, which updates the task, fires the QRF if not yet fired, and unlocks extraction.
- **QRF:** pick an origin town by weight. Spawn the truck with `createVehicle` + `createVehicleCrew`, put the
  infantry `moveInCargo`, then add waypoints `"MOVE"` → `"TR UNLOAD"` (near the compound) → `"SAD"`. Wave 2 follows
  after a jittered delay and may include one APC.
- **Artillery (recommended):** `BIS_fnc_addCommMenuItem` + `CfgCommunicationMenu` + `fn_fireMission`, which
  spawns N `Sh_82mm_AMOS` shells with dispersion and delay, or drives a hidden `B_Mortar_01_F` with
  `doArtilleryFire`. It allows an exact round count, and the logic can be tested without UI. The module route
  (`SupportRequester` + `SupportProvider_Virtual_Artillery` + `BIS_fnc_addSupportLink`) is the fallback.
- **Extraction:** a comm-menu item, enabled after the intel is taken, spawns the Ghost Hawk off-map. The heli
  `doMove`s to an invisible `Land_HelipadEmpty_F` at the LZ and runs `land "GET IN"`. Poll with
  `isTouchingGround`, then wait until `{alive _x && vehicle _x != _heli} count units group player == 0`. Then fly
  out. Win once it is about 1.5 km away. A `Killed` EH on the heli ends the mission as HeliLost.
- **Tasks/end:** `BIS_fnc_taskCreate` / `BIS_fnc_taskSetState`. End with `["Win", true] remoteExec
  ["BIS_fnc_endMission", 0]`.
- **Placement:** `BIS_fnc_findSafePos` for the start position, LZ and QRF spawn. Use `nearRoads` for truck spawns.

## 3. Class names (base game only) **[U: confirm via sweep]**

| Role | Class |
|---|---|
| NATO squad | `B_Soldier_SL_F`, `B_Soldier_TL_F`, `B_soldier_AR_F`, `B_Soldier_GL_F`, `B_soldier_LAT_F`, `B_medic_F`, `B_Soldier_F` |
| Extract heli | `B_Heli_Transport_01_F` (Ghost Hawk) |
| CSAT infantry | `O_Soldier_SL_F`, `O_Soldier_F`, `O_Soldier_AR_F`, `O_Soldier_LAT_F`, `O_soldier_M_F`. Groups: `configFile >> "CfgGroups" >> "East" >> "OPF_F" >> "Infantry" >> "OIA_InfSquad"` / `"OIA_InfTeam"` |
| QRF vehicles | `O_Truck_02_transport_F` (Zamak), `O_MRAP_02_hmg_F` (Ifrit HMG), APC `O_APC_Wheeled_02_rcws_v2_F` (Marid; older `_rcws_F`) |
| Artillery | shell `Sh_82mm_AMOS` or `B_Mortar_01_F` (Mk6) |
| Intel | `Land_Laptop_unfolded_F`, `Land_File1_F`, `Land_Map_F` **[U]** |
| Compound | `Land_Cargo_HQ_V1_F`, `Land_Cargo_Patrol_V1_F`, `Land_BagBunker_Small_F`, `Land_BagFence_Long_F`, `Land_HBarrier_5_F`, `Land_Razorwire_F`; statics `O_HMG_01_high_F`; LZ `Land_HelipadEmpty_F` |

The compound is spawned from a relative-offset array (`[class, [dx,dy,dz], dir]`) rotated to the site's direction.
Then any candidate site works, and DMS can emit that array later.

## 4. Site candidates on Altis (worldspace, **all [U]**, verify in Eden)

Coordinates are approximate, recalled from map knowledge rather than measured.

1. **Outskirts east of Pyrgos**, about [17600, 13200]. QRF from Pyrgos [16800, 12700]. Open farmland for the LZ to
   the north.
2. **Countryside near Zaros / Therisa**, about [10600, 12800]. QRF from Zaros [9100, 11800]. The valley floor gives
   the LZ.
3. **Near Athira (Frini side)**, about [14600, 20200]. QRF from Athira [14000, 18700]. Open plateau to the west.

Altis also has vanilla military outposts (the `Land_Cargo_*` sets placed on the map), which are natural targets.
In M1, `nearestObjects [center, ["Land_Cargo_HQ_V1_F","Land_Cargo_Patrol_V1_F"], 30000]` finds them **[U]**. A
filter for "town 2–4 km away, flat clear ground within 300 m, a road" then picks 2–3 sites. Log them with
`diag_log` and freeze the list.

## 5. Headless testing

- **Server:** Steam tool *Arma 3 Server* (appid 233780; SteamCMD anonymous login **[U]**).
  - `server.cfg`: `persistent = 1;` and
    `class Missions { class M { template = "DMS_Raid.Altis"; difficulty = "Regular"; class Params { DMS_test = 1; }; }; };`
  - Launch: `arma3server_x64.exe -config=server.cfg -profiles=out -autoInit`
  - `-autoInit` does nothing without `persistent=1` ([ref](https://xgamingserver.com/tools/arma-3/launch-params)).
    With both set, the mission runs with no player connected.
- **Logs:** `.rpt` files are written to the `-profiles` dir. Emit `diag_log text format ["[DMS.TEST] %1", _x]` and
  `[DMS.OUTCOME]` lines, the same contract as the DCS harness, so the parser in `tools/dcs_harness` can be reused.
- **Player proxy:** when `DMS_test == 1` and no player is present, spawn an AI `B_Soldier_SL_F` leader with a
  scripted route. It calls `fn_intelTaken`, `fn_fireMission` and `fn_callExtract` directly, because hold actions and
  comm menus need a UI. This mirrors `DMS_CONFIG.test.playerProxy`. Test params can force each end state.
- **Headless client** (`-client -connect=127.0.0.1`): not needed for the MVP.
- **Static/CI:**
  - [SQF-VM](https://github.com/SQFvm/runtime) (LGPL, active) parses and runs SQF offline, including the
    preprocessor. Use it for pure functions such as QRF wave selection and timers.
  - [sqflint](https://github.com/LordGolias/sqf) (`pip install sqflint`, archived 2023) does syntax checks.
  - `hemtt check` **[U for missions]**.

## 6. Milestones

| M | Scope | Acceptance | Test |
|---|---|---|---|
| M1 | Scaffold, minimal sqm, class sweep, site picker, compound + garrison, squad on foot about 1 km out | 0 missing classes. No RPT script errors. Proxy squad reaches and clears the compound | sqflint/SQF-VM, then a dedicated autoInit run |
| M2 | Intel hold-action, detection, QRF 1–2 waves | Intel sets the task and unlocks extract. QRF spawns on alarm OR intel, only once. Trucks unload near the compound | Dedicated run with the proxy and a forced-alarm param |
| M3 | Comm-menu artillery (N rounds), extraction heli, all end states | Rounds land within 50 m and the count blocks at 0. The heli lands and the squad boards, giving Win. Heli killed gives HeliLost. Player dead gives Dead | Dedicated run, one param per end state |
| M4 | Headless soak + polish | 5 seeds × 3 sites end with a logged outcome and no script errors. User playtest | Headless batch, then the user |

**Later DMS fit:** put every tunable in one `fn/config.sqf` hashmap, the `DMS_CONFIG` analogue: sites, compound
offsets, QRF waves, weights, delays and round counts. A future Python `MissionSpec → Arma` backend writes that
file, following ADR 0007: Python picks the space, and SQF picks the instance.

## Blockers needing the user's install

- Arma 3 and Arma 3 Server (and Tools, for packing) must be installed.
- Class names and coordinates must be verified in-game.
- The first `mission.sqm` is easiest saved once from Eden (unbinarized).
