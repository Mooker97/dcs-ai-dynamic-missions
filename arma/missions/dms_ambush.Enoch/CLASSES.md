# Classes and functions used by "Ambush"

**Checked 2026-10-28 offline** against the installed mod PBOs (Steam workshop folder
`E:\SteamLibrary\steamapps\workshop\content\107410\<id>\addons`). Not yet checked in-engine with `isClass`.

**How:** every PBO of the six mods was unpacked (header parse, uncompressed entries only) and each
rapified `config.bin` was parsed into a class tree. A class counts as verified only when it is a real
`class` entry under `CfgVehicles` (or `CfgPatches`), not just a string somewhere. Scope and side were
resolved through the inheritance chain: every unit and vehicle below is `scope = 2` (public). Side 0 =
EAST, 1 = WEST. LAMBS ships its functions as plain SQF compiled by CBA (`PREP(...)` in `XEH_PREP.hpp`),
so its function names and parameters were read from the source in `lambs_wp.pbo`.

Mods: CBA_A3 `450814997`, ACE (SP repack) `1744095754`, LAMBS Danger `1858075458`, RHSAFRF `843425103`,
RHSUSAF `843577117`, RHSGREF `843593391` (optional, not used by any class here).

## Required mods (CfgPatches, checked by `fn_mods.sqf` at start)

| Label | CfgPatches | Mod id / PBO |
|---|---|---|
| CBA | `cba_main` | 450814997 / cba_main.pbo |
| ACE | `ace_main` | 1744095754 / ace_main.pbo |
| LAMBS Danger | `lambs_danger` | 1858075458 / lambs_danger.pbo |
| LAMBS Waypoints | `lambs_wp` | 1858075458 / lambs_wp.pbo |
| RHS AFRF | `rhs_main` | 843425103 / rhs_main.pbo |
| RHS USAF | `rhsusf_main` | 843577117 / rhsusf_main.pbo |
| RHS GREF (optional, logged only) | `rhsgref_main` | 843593391 / rhsgref_main.pbo |

## Player squad (RHS USAF, USMC woodland MARPAT, side WEST)

| Role | Class | Mod id / PBO |
|---|---|---|
| Team leader (player loadout, test-mode leader) | `rhsusf_usmc_marpat_wd_teamleader` | 843577117 / rhsusf_c_troops.pbo |
| Automatic rifleman (M249) | `rhsusf_usmc_marpat_wd_autorifleman_m249` | 843577117 / rhsusf_c_troops.pbo |
| Grenadier (M203) | `rhsusf_usmc_marpat_wd_grenadier` | 843577117 / rhsusf_c_troops.pbo |
| Rifleman AT (M136) | `rhsusf_usmc_marpat_wd_riflemanat` | 843577117 / rhsusf_c_troops.pbo |
| Javelin gunner | `rhsusf_usmc_marpat_wd_javelin` | 843577117 / rhsusf_c_troops.pbo |
| Rifleman | `rhsusf_usmc_marpat_wd_rifleman` | 843577117 / rhsusf_c_troops.pbo |
| Corpsman | `rhsusf_navy_marpat_wd_medic` | 843577117 / rhsusf_c_troops.pbo |

The `mission.sqm` slot stays vanilla `B_Soldier_TL_F` (verified, `docs/arma/kb/classes-verified.md`), so
the mission loads without RHS and can end itself with a clear message. The player gets the team
leader's loadout through `getUnitLoadout`/`setUnitLoadout` at start.

## Convoy (RHS AFRF, motor rifles in EMR, side EAST)

| Role | Class | Mod id / PBO |
|---|---|---|
| Lead vehicle (GAZ Tigr) | `rhs_tigr_msv` | 843425103 / rhs_c_cars.pbo |
| APC (BTR-80) | `rhs_btr80_msv` | 843425103 / rhs_c_btr.pbo (also patched by ACE compat and GREF) |
| Truck 1 (Ural-4320, covered) | `RHS_Ural_MSV_01` | 843425103 / rhs_c_a2port_car.pbo |
| Truck 2 (Ural-4320, open; rolled 50 %) | `RHS_Ural_Open_MSV_01` | 843425103 / rhs_c_a2port_car.pbo |
| Dismount leader | `rhs_msv_emr_sergeant` | 843425103 / rhs_c_troops.pbo |
| Dismounts | `rhs_msv_emr_rifleman`, `rhs_msv_emr_machinegunner`, `rhs_msv_emr_grenadier`, `rhs_msv_emr_LAT`, `rhs_msv_emr_RShG2`, `rhs_msv_emr_at`, `rhs_msv_emr_medic`, `rhs_msv_emr_efreitor` | 843425103 / rhs_c_troops.pbo |

Vehicle crews come from each vehicle's own config through `createVehicleCrew`.

## Rally point pickup (RHS USAF, side WEST)

| Role | Class | Mod id / PBO |
|---|---|---|
| HMMWV with M2 (crewed) | `rhsusf_m1025_w_m2` | 843577117 / rhsusf_c_hmmwv.pbo |
| HMMWV 4-door (driver) | `rhsusf_m998_w_4dr` | 843577117 / rhsusf_c_hmmwv.pbo |

## LAMBS functions

| Function | Source | Signature used |
|---|---|---|
| `lambs_wp_fnc_taskHunt` | 1858075458 / lambs_wp.pbo `functions\fnc_taskHunt.sqf`, `PREP(taskHunt)` | `[group, radius, cycle, area, centre, onlyPlayers, enableReinforcement, flares] spawn lambs_wp_fnc_taskHunt` (`onlyPlayers` defaults to true; the mission passes false so the AI test squad is hunted too) |

LAMBS Danger itself needs no calls: with the mod loaded every AI group (convoy dismounts and the
player's squad) uses its danger FSM.

## Vanilla (no mod)

| What | Name | Where verified |
|---|---|---|
| Player slot | `B_Soldier_TL_F` | `docs/arma/kb/classes-verified.md` (in-engine) |
| Mortar round | `Sh_82mm_AMOS` (CfgAmmo) | `docs/arma/kb/classes-verified.md` (in-engine) |
| Markers | `hd_ambush`, `hd_objective`, `hd_end`, `hd_pickup`, `mil_dot` | CfgMarkers in `Arma 3\Addons\ui_f.pbo` config.bin (offline) |
| Marker colours | `ColorOPFOR`, `ColorBLUFOR`, `ColorRed` | CfgMarkerColors in ui_f.pbo (offline) |
| Task types | `destroy`, `move` | CfgTaskTypes in ui_f.pbo (offline) |
| BIS functions | `BIS_fnc_getParamValue`, `BIS_fnc_taskCreate`, `BIS_fnc_taskSetState`, `BIS_fnc_taskExists`, `BIS_fnc_taskCompleted`, `BIS_fnc_addCommMenuItem`, `BIS_fnc_endMission` | `docs/arma/kb/functions.txt` (enforced by `arma/tools/test_kb_functions.py`) |

## Engine commands worth a look in-engine

These are standard SQF commands, but this is the first DMS mission that uses them:
`getRoadInfo` (2.00+, `mapType` compared upper-case), `roadsConnectedTo`, `nearRoads`,
`terrainIntersectASL`, `forceFollowRoad`, `forceSpeed`, `setUnitLoadout`/`getUnitLoadout`, `canFire`.

## Terrain data (Livonia)

The site centres in `fn_config.sqf` come from the terrain's own data in
`Arma 3\Enoch\Addons\map_enoch_data.pbo` (`roads\roads.shp`, UTM with false easting 200000, so world
x = easting - 200000) and the town list in `map_enoch.pbo` (`CfgWorlds >> Enoch >> Names`). Road types
there: 1 = main road, 2 = road, 3 = track (`roads\RoadsLib.cfg`).
