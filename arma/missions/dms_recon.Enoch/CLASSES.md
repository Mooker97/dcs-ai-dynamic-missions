# Classes, functions and engine commands used by `dms_recon.Enoch`

**Checked 2026-10-28** by reading the mod PBOs directly, not in-engine. A small reader parsed each
PBO's rapified `config.bin` (CfgPatches, CfgVehicles, CfgWeapons, CfgMagazines, CfgAmmo), and the
LAMBS function headers were read from the `.sqf` sources inside `lambs_wp.pbo`. Mod folders are
`E:\SteamLibrary\steamapps\workshop\content\107410\<id>\addons\`. An in-engine `isClass` sweep has
**not** been run for this mission yet (see "To verify in-engine" below).

## Required mods (CfgPatches checked by `initServer.sqf`)

| Mod | Workshop id | CfgPatches | Found in |
|---|---|---|---|
| CBA_A3 | 450814997 | `cba_main` | `cba_main.pbo` |
| ACE (sp repack 3.21.2) | 1744095754 | `ace_main` | `ace_main.pbo` |
| LAMBS Danger | 1858075458 | `lambs_danger` | `lambs_danger.pbo` |
| LAMBS waypoints (same mod) | 1858075458 | `lambs_wp` | `lambs_wp.pbo` (v2.6.2.1) |
| RHS AFRF | 843425103 | `rhs_main` | `rhs_main.pbo` |
| RHS USAF | 843577117 | `rhsusf_main` | `rhsusf_main.pbo` |

Optional, only logged: `ace_medical`, `rhsgref_main`, `rhssaf_main` (names not checked; nothing uses them).
The harness preset `core` is CBA + ACE + LAMBS, so run with `--mods core,843425103,843577117`.

## Recon team (RHS USAF, CfgVehicles, `rhsusf_c_troops.pbo`, mod 843577117)

| Role | Class | Notes |
|---|---|---|
| Team leader (player / test leader) | `rhsusf_usmc_recon_marpat_wd_teamleader` | scope 2, parent `rhsusf_infantry_usmc_recon_base`; ships with `rhsusf_bino_lerca_1200_black` (a `Rangefinder` child), which the mission swaps for the vanilla designator |
| Marksman | `rhsusf_usmc_recon_marpat_wd_marksman` | scope 2, SR-25, LERCA rangefinder |
| Automatic rifleman | `rhsusf_usmc_recon_marpat_wd_autorifleman` | scope 2, M27 IAR |
| Rifleman | `rhsusf_usmc_recon_marpat_wd_rifleman` | scope 2 |

The `mission.sqm` player unit is vanilla `B_Soldier_TL_F` (verified, `docs/arma/kb/classes-verified.md`)
so the mission loads without mods. `initPlayerLocal.sqf` gives the player the team leader's loadout
with `setUnitLoadout (configFile >> "CfgVehicles" >> ...)`.

## Laser designator (vanilla, `Addons\weapons_f.pbo`)

| Class | Config | Notes |
|---|---|---|
| `Laserdesignator` | CfgWeapons | parent `Binocular`, `magazines[] = {"Laserbatteries"}` |
| `Laserbatteries` | CfgMagazines | scope 2. `rhs_c_heavyweapons.pbo` also touches this class (an override, not a new class) |

## Enemy (RHS AFRF, mod 843425103)

| Role | Class | PBO | Notes |
|---|---|---|---|
| Mortar (battery tube) | `rhs_2b14_82mm_msv` | `rhs_c_heavyweapons.pbo` | scope 2, parent `rhs_2b14_82mm_Base` (`StaticMortar`), side 0 (east), crew `rhs_msv_rifleman` |
| Guard / QRF leader | `rhs_msv_emr_junior_sergeant`, `rhs_msv_emr_sergeant` | `rhs_c_troops.pbo` | |
| Riflemen | `rhs_msv_emr_rifleman` | `rhs_c_troops.pbo` | parent `rhs_msv_rifleman` (scope 2) |
| MG | `rhs_msv_emr_machinegunner` | `rhs_c_troops.pbo` | |
| Grenadier | `rhs_msv_emr_grenadier` | `rhs_c_troops.pbo` | |
| AT / LAT | `rhs_msv_emr_at`, `rhs_msv_emr_LAT` | `rhs_c_troops.pbo` | |
| Marksman | `rhs_msv_emr_marksman` | `rhs_c_troops.pbo` | |

Also present and usable for variants (not used): `rhs_D30_msv`, `RHS_ZU23_MSV`, `rhs_Igla_AA_pod_msv`,
`rhs_KORD_high_MSV`, `RHS_NSV_TriPod_MSV`, `rhs_2b14_82mm_vdv`.

## Props and ammunition (vanilla, verified in-engine for The Hill)

| Class | Config | Source |
|---|---|---|
| `CamoNet_OPFOR_open_F` | CfgVehicles | `docs/arma/kb/classes-verified.md` |
| `Box_East_Ammo_F` | CfgVehicles | `docs/arma/kb/classes-verified.md` |
| `Sh_155mm_AMOS` | CfgAmmo | `docs/arma/kb/classes-verified.md` (spawned with `createVehicle` and given a downward velocity, like The Hill's mortar shells). Found in `weapons_f.pbo`, parent `ShellBase`; `rhs_c_heavyweapons.pbo` overrides it |

## LAMBS functions (`lambs_wp.pbo`, from the function headers in the PBO)

| Function | Call used | Signature (from the header) |
|---|---|---|
| `lambs_wp_fnc_taskCamp` | `[_grp, _center, 50] call lambs_wp_fnc_taskCamp` | group, position, range (50), area, teleport, patrol, exitWP. Uses `CBA_fnc_directCall` when scheduled |
| `lambs_wp_fnc_taskPatrol` | `[_grp, _center, _radius, 4] call lambs_wp_fnc_taskPatrol` | group, position, radius (200), waypoint count (4), area, dynamic, reinforcement, teleport |
| `lambs_wp_fnc_taskHunt` | `[_grp, 2500, 45, [], [], false, false, 0] spawn lambs_wp_fnc_taskHunt` | group, radius (1000), cycle s (70), area, centre (`[]` = the group, moving), onlyPlayers (false), reinforcement, flare (0 = off). It hunts the closest enemy in range, so with onlyPlayers false it also finds the AI team in test mode |

## BIS functions

All are in `docs/arma/kb/functions.txt` and in `arma/tools/sqf_check.py` `KNOWN_BIS`:
`BIS_fnc_getParamValue`, `BIS_fnc_taskCreate`, `BIS_fnc_taskSetState`, `BIS_fnc_taskExists`,
`BIS_fnc_taskCompleted`, `BIS_fnc_addCommMenuItem`, `BIS_fnc_endMission`.

## Engine commands (verify)

Not covered by the knowledge base, which lists functions only. These are standard engine commands,
but this mission is the first DMS mission to use them:

| Command | Where | Assumption to verify |
|---|---|---|
| `laserTarget` | comm-menu expression (client) | Returns the vanilla designator's laser target object while lasing, with ACE loaded too |
| `checkVisibility` | BDA, test find | `[_obs, "VIEW", _tube] checkVisibility [eyePos, posASL]` returns 0..1; forest blocks it |
| `getArtilleryAmmo`, `inRangeOfArtillery`, `doArtilleryFire` | battery fire | The RHS 2B14 AI gunner fires at a target 3 km away (2B14 max range is about 4 km) |
| `setVehicleAmmo` | battery fire | Refills the tube between fire missions |
| `setUnitLoadout` (Config argument) | `initPlayerLocal.sqf` | Copies the RHS team leader's loadout onto the vanilla player unit |
| `binocular`, `addWeapon`, `addMagazine`, `removeWeapon` | team leader | The designator ends up in the binocular slot loaded with batteries |
| `nearRoads`, `nearestTerrainObjects`, `hideObjectGlobal`, `surfaceNormal` | site snapping | Same use as The Hill (verified there on Altis) |
| `nearestLocations` | start log | Location types `NameCity`, `NameVillage`, `NameLocal`, `Hill` exist on Enoch (`CfgWorlds >> Enoch >> Names`) |
| `selectMin` | report log | |

## Site anchors (TO VERIFY)

Livonia is 12800 m square (`CfgWorlds >> Enoch >> mapSize`). The anchors in `fn_config.sqf` were
chosen between named places read from `map_enoch.pbo` (`CfgWorlds >> Enoch >> Names`), at least about 1 km
from the nearest village:

| Site | Anchor | Nearby names (position) |
|---|---|---|
| Forest south-west of Nadbor | [4300, 3300] | Nadbor [6110, 3983], Polana [3280, 2132], Hedrykow [4513, 4796], Swarog hill [4855, 2224] |
| Forest west of Rodzanica hill | [7800, 2900] | Nadbor [6110, 3983], Rodzanica hill [8882, 2042], Roztoka [7695, 5317] |
| Forest between Lembork and Borek | [9000, 7700] | Lembork [8680, 6636], Borek [9807, 8495], Zapadlisko [8058, 8712], Karlin [10073, 6957] |

Forest cover was **not** checked offline. At runtime `fn_findPos "FOREST"` picks, within 500 m of the anchor,
the dry, gentle spot (no building within 150 m, no road within 60 m) with the most trees within 60 m,
and logs the result as `forestScore` in the `Start:` line. A score near 0 means the anchor sits in open
ground and needs moving.

## To verify in-engine

1. `isClass` for every class above on a server started with `--mods core,843425103,843577117`.
2. The `Start:` log line for each site: battery grid, `forestScore` (expect dozens of trees), nearest place.
3. `Battery fired:` lines show `fired > 0` (the 2B14 AI accepts `doArtilleryFire` at 3 km).
4. The player gets the designator in the binocular slot with batteries, and `laserTarget` works with ACE loaded.
5. The 155 mm rounds take tubes out: `Tube N out: ...` lines after a strike centred on the battery.
