# Classes, functions and data used by "Breakthrough"

**Checked 2026-10-29 offline and in-engine.**

- **Offline:** every config PBO of RHS USAF (`843577117`) and RHS AFRF (`843425103`) in
  `E:\SteamLibrary\steamapps\workshop\content\107410\<id>\addons` was unpacked and each rapified
  `config.bin` parsed into a class tree (the same scratch PBO reader the Ambush check used). A class counts
  only when it is a real `class` under `CfgVehicles`/`CfgAmmo`. Scope, side, faction and crew were resolved
  through the inheritance chain. Display names come from `rhs_main.pbo`'s stringtable.
- **In-engine:** a diag mission on a dedicated server with `--mods rhs` (2026-10-29) ran `isClass` on every
  class below. All returned true. It also spawned the M1A2 and the M2A3 to read their seats.
- **At start**, the mission checks every class again with `isClass` and logs
  `Missing classes (fallbacks used where listed): ...` as a WARN.

Mods: CBA_A3 `450814997`, ACE (SP repack) `1744095754`, LAMBS Danger `1858075458`, RHSAFRF `843425103`,
RHSUSAF `843577117`, RHSGREF `843593391` (optional, logged only).

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

## Player tank (RHS USAF, US Army woodland, side WEST)

| Role | Class | Mod id / PBO | Config |
|---|---|---|---|
| M1A2 SEP (woodland) | `rhsusf_m1a2sep1wd_usarmy` | 843577117 / rhsusf_c_m1a2.pbo | parent `rhsusf_m1a2tank_base`, scope 2, side 1, faction `rhs_faction_usarmy_wd`, crew `rhsusf_army_ucp_combatcrewman`, display "M1A2SEP (Woodland)" (`$STR_M1A2SEPWD_Name`) |
| Fallback: M1A2 SEP (desert) | `rhsusf_m1a2sep1d_usarmy` | same | scope 2, faction `rhs_faction_usarmy_d` |
| Player loadout | `rhsusf_army_ucp_combatcrewman` | 843577117 / rhsusf_c_troops.pbo | parent `rhsusf_army_ocp_combatcrewman`, scope 2, faction `rhs_faction_usarmy_wd` |

Seats as read in-engine: `driver`, `gunner` [0], `commander` [0, 0], `turret` [0, 1], `commander` [0, 2],
`turret` [0, 3]. The player is moved into turret **[0, 0]** with `moveInTurret`. `createVehicleCrew` fills
the seats, then every crew member except the driver and gunner is removed with `deleteVehicleCrew`.

The `mission.sqm` slot stays vanilla `B_Soldier_TL_F` (in-engine verified, `docs/arma/kb/classes-verified.md`),
so the mission loads without RHS and can end itself with a clear message. The player gets the crewman kit
with `setUnitLoadout (configFile >> "CfgVehicles" >> "rhsusf_army_ucp_combatcrewman")`.

## Friendly section (RHS USAF, side WEST)

| Role | Class | Mod id / PBO | Config |
|---|---|---|---|
| Bradley (x2) | `RHS_M2A3_wd` | 843577117 / rhsusf_c_a2port_armor.pbo | parent `RHS_M2A3`, scope 2, faction `rhs_faction_usarmy_wd`, crew `rhsusf_army_ucp_crewman`; 6 cargo seats (in-engine `emptyPositions "cargo"`) |
| Fallback Bradley | `RHS_M2A3` | same | the desert one, used by dms_village.Malden |
| Squad leader | `rhsusf_army_ucp_squadleader` | 843577117 / rhsusf_c_troops.pbo | scope 2, side 1 (inherited), faction `rhs_faction_usarmy_wd` |
| Team leader | `rhsusf_army_ucp_teamleader` | same | same |
| Automatic rifleman | `rhsusf_army_ucp_autorifleman` | same | same |
| Rifleman (AT) | `rhsusf_army_ucp_riflemanat` | same | same |
| Grenadier | `rhsusf_army_ucp_grenadier` | same | same |
| Machine gunner | `rhsusf_army_ucp_machinegunner` | same | same |
| Rifleman | `rhsusf_army_ucp_rifleman` | same | same |
| Medic | `rhsusf_army_ucp_medic` | same | same |

The 8-man squad is split 4/4 between the two Bradleys (`assignAsCargo` + `moveInCargo`).

## Enemy (RHS AFRF, side EAST)

| Role | Class | Mod id / PBO | Config |
|---|---|---|---|
| Treeline tanks (x2), counter-attack tank | `rhs_t72bd_tv` | 843425103 / rhs_c_t72.pbo | "T-72B3 (obr. 2012g.)", scope 2, side 0, faction `rhs_faction_tv`, crew `rhs_msv_emr_armoredcrew` |
| Fallback tank | `rhs_t72bb_tv` | same | "T-72B (obr. 1985g.)" |
| ATGM | `rhs_Metis_9k115_2_msv` | 843425103 / rhs_c_heavyweapons.pbo | 9K115-2 Metis-M, parent `rhs_Metis_Base` (`AT_01_base_F`), scope 2, side 0, faction `rhs_faction_msv`, crew `rhs_msv_rifleman` |
| Fallback ATGM | `rhs_Kornet_9M133_2_msv` | same | 9K133 Kornet. The Metis is the first choice: the Kornet would make the flank team close to an instant kill |
| ATGM team | `rhs_msv_emr_at`, `rhs_msv_emr_rifleman` | 843425103 / rhs_c_troops.pbo | scope 2, side 0, faction `rhs_faction_msv` |
| Village IFV | `rhs_bmp2_msv` | 843425103 / rhs_c_bmp.pbo | "BMP-2 (obr. 1986g.)", parent `rhs_bmp2_vdv`, scope 2, crew `rhs_msv_crew` |
| Fallback village IFV | `rhs_bmp2d_msv` | same | BMP-2D |
| Counter-attack IFV | `rhs_bmp3_msv` | 843425103 / rhs_c_bmp3.pbo | "BMP-3 (early)", scope 2 |
| Village squad | `rhs_msv_emr_sergeant` (leader), `rhs_msv_emr_rifleman`, `rhs_msv_emr_machinegunner`, `rhs_msv_emr_grenadier`, `rhs_msv_emr_LAT`, `rhs_msv_emr_medic` | 843425103 / rhs_c_troops.pbo | scope 2, side 0 (as in dms_ambush.Enoch) |
| Village RPG team | `rhs_msv_emr_RShG2`, `rhs_msv_emr_LAT` | same | same |

There are no AA units. The A-10 crew is also captive (see below).

## Air support

| What | Class | Mod id / PBO | Config |
|---|---|---|---|
| Jet for the pass | `RHS_A10` | 843577117 / rhsusf_c_a2port_air.pbo | "A-10A", parent `Plane_CAS_01_base_F`, scope 2, side 1, faction `rhs_faction_usaf`, crew `rhsusf_airforce_jetpilot` |
| Bomb | `Bo_Mk82` (CfgAmmo) | vanilla `Addons\weapons_f.pbo` | parent `BombCore`, hit 5000, indirectHit 1100, indirectHitRange 12 |
| Fallback bomb | `rhs_ammo_mk82` (CfgAmmo) | 843577117 / rhsusf_c_airweapons.pbo | parent `Bo_Mk82`. Second choice in case RHS fuze scripting expects a real release |

RHS has no F/A-18. The other US jet is the F-22A (`rhsusf_f22`), which is not a bomb truck, so the A-10A it is.
The jet flies a real pass, but the bombs are spawned by script 120 m above the aim point. They fall along the
run-in heading at 60 m/s forward and 80 m/s down, with a seeded Rayleigh CEP. Each detonation is tracked.
This follows the virtual mortars of The Hill and Ambush and the reliability lesson from Hold's AH-64.

## LAMBS functions (1858075458 `lambs_wp.pbo`, readable source)

| Function | Signature used | Source |
|---|---|---|
| `lambs_wp_fnc_taskGarrison` | `[group, position, range, [], teleport=true, sortByHeight=true, exitCondition=-2, patrol=false] call` | as used and documented in dms_village.Malden/CLASSES.md |
| `lambs_wp_fnc_taskCQB` | `[group, position, radius, cycle=21] spawn` | as used and documented in dms_village.Malden/CLASSES.md |
| `lambs_danger_disableAI` / `lambs_danger_disableGroupAI` | unit / group variables, set true on the tank and Bradley crews | as in dms_village.Malden |

## Vanilla (no mod)

| What | Name | Where verified |
|---|---|---|
| Player slot | `B_Soldier_TL_F` | `docs/arma/kb/classes-verified.md` (in-engine), and the 2026-10-29 diag |
| Markers | `hd_objective`, `hd_flag`, `hd_start`, `mil_dot` | CfgMarkers in `Arma 3\Addons\ui_f.pbo` config.bin (offline) |
| Marker colours | `ColorOPFOR`, `ColorBLUFOR`, `ColorRed`, `ColorBlue` | as in Ambush (run in-engine) |
| Task type | `attack` | CfgTaskTypes in ui_f.pbo config.bin (offline) |
| Comm-menu icon | `\a3\Ui_f\data\GUI\Cfg\CommunicationMenu\cas_ca.paa` | path string found in `ui_f.pbo` and `ui_f_data.pbo` |
| BIS functions | `BIS_fnc_getParamValue`, `BIS_fnc_taskCreate`, `BIS_fnc_taskSetState`, `BIS_fnc_taskExists`, `BIS_fnc_taskCompleted`, `BIS_fnc_addCommMenuItem`, `BIS_fnc_endMission` | `docs/arma/kb/functions.txt` (enforced by `arma/tools/test_kb_functions.py`) |

## Engine commands worth a look in-engine

This is the first DMS mission to use `moveInTurret`, `deleteVehicleCrew`, `selectLeader` (remote-executed to the
group owner), `disableAI "PATH"` on vehicle drivers (the dug-in tanks and BMP), `canMove`/`canFire` as the
armour-threat test, and `createVehicle` of bomb ammo with a set velocity.

## Terrain data (Livonia)

**Offline:**
- Village positions come from `Arma 3\Enoch\Addons\map_enoch.pbo` (`CfgWorlds >> Enoch >> Names`).
- Roads come from `map_enoch_data.pbo` `roads\roads.shp`. That file uses UTM with false easting 200000, so
  world x = easting - 200000. Its dbf `ID` field gives the type: 1 = main road, 2 = road, 3 = track.
- A scratch script built a graph of type 1 and 2 roads, sampled every 25 m. For every village it found each
  road arm that runs 3 km out with a fairly straight course and no other village close to it.

**In-engine (diag, 2026-10-29):** 19 candidate approaches were measured with these tests:

| Test | How |
|---|---|
| Trees within 60 m of the road | every 100 m along the approach |
| Open ground beside the road | trees within 40 m of points 250 m and 500 m either side, every 300 m |
| Treeline firing spots, 1.0-1.7 km out | no tree within 9 m, at least 4 trees within 35 m, flat, and line of sight to the road |
| Crossroads | road segments with 3 or more connections within 150 m of the village point |

The chosen three:

| Site | Village point | Start (route point 0) | Open beside road | Treeline spots (left/right) | Junction segments |
|---|---|---|---|---|---|
| Bielawa, from the Lukow road | 1573, 9677 | 3452, 11619 | 23/40 | 2 / 4 | 1 |
| Topolin, from the Radacz road | 1858, 7330 | 4102, 8436 | 23/40 | 0 / 7 | 5 |
| Grabin, from the Zapadlisko road | 10666, 11025 | 8316, 9671 | 20/40 | 9 / 4 | 1 |

Rejected:
- The southern approaches, Polana, Nadbor and Huta, run through continuous forest (0-1/40 open).
- Lembork is mostly wooded.
- Gliniska had good treeline spots but much more forest along the road.

The route points are the shapefile centreline resampled every ~100 m. The tank starts on route point 3 and
the Bradleys on points 1 and 0.
