# Classes and functions used by "Hold the OP"

**Verified 2026-10-28 offline** by searching the installed workshop PBOs
(`E:\SteamLibrary\steamapps\workshop\content\107410\<id>\addons\*.pbo`) for each name. The configs
are rapified, but class-name strings survive. RHSUSAF's `rhsusf_c_a2port_air.pbo` and the LAMBS
PBOs also contain readable source. **Not yet checked in-engine.** At start the mission itself runs
`isClass (configFile >> "CfgVehicles" >> _x)` on every class below and `!isNil` on every LAMBS
function. If one is missing it ends with `DMS_FailMods` and logs `Mod check: ...`.

Mod ids: CBA_A3 `450814997`, ace Singleplayer `1744095754` (ACE 3.21.2 repack), LAMBS_Danger
`1858075458` (2.6.2.1), RHSAFRF `843425103`, RHSUSAF `843577117` (0.5.6).

## Required mods (CfgPatches, logged as `Mods: ...`)

| Mod | CfgPatches | Found in |
|---|---|---|
| CBA_A3 | `cba_main` | 450814997 `cba_main.pbo` (prefix `x\cba\addons\main`) |
| ACE | `ace_main` | 1744095754 `ace_main.pbo` (prefix `z\ace\addons\main`) |
| LAMBS_Danger | `lambs_danger` | 1858075458 `lambs_danger.pbo` (prefix `z\lambs\addons\danger`) |
| LAMBS waypoints | `lambs_wp` | 1858075458 `lambs_wp.pbo` (prefix `z\lambs\addons\wp`) |
| RHSAFRF | `rhs_main` | 843425103 `rhs_main.pbo` (prefix `rhsafrf\addons\rhs_main`) |
| RHSUSAF | `rhsusf_main` | 843577117 `rhsusf_main.pbo` (prefix `rhsusf\addons\rhsusf_main`) |

The patch names follow the CBA/ACE/LAMBS `PREFIX_COMPONENT` convention and the RHS main PBO names.
They are only logged. The class and function checks are what gate the mission.

## Player squad: RHSUSAF, US Army OCP (843577117 `rhsusf_c_troops.pbo`)

| Role | Class |
|---|---|
| Player loadout / test-mode leader | `rhsusf_army_ocp_squadleader` |
| Team leader | `rhsusf_army_ocp_teamleader` |
| Automatic rifleman (M249) | `rhsusf_army_ocp_autorifleman` |
| Grenadier (M203) | `rhsusf_army_ocp_grenadier` |
| Rifleman (starts on the static gun) | `rhsusf_army_ocp_rifleman` |
| Rifleman AT (M136) | `rhsusf_army_ocp_riflemanat` |
| Machine gunner (M240) | `rhsusf_army_ocp_machinegunner` |
| Medic | `rhsusf_army_ocp_medic` |

The mission.sqm slot is vanilla `B_Soldier_SL_F` (in-engine verified, `docs/arma/kb/classes-verified.md`),
so the mission loads without RHS. The player's kit comes from
`setUnitLoadout (configFile >> "CfgVehicles" >> "rhsusf_army_ocp_squadleader")`. **TO VERIFY in-engine.**

## Static weapon (843577117 `rhsusf_c_statics.pbo`)

| Class | Use |
|---|---|
| `RHS_M2StaticMG_D` | M2 .50 cal on a high tripod (desert). First choice |
| `RHS_MK19_TriPod_D` | Mk19 GMG on a tripod (desert). Fallback if the M2 class is missing |

## Enemy: RHSAFRF, motor rifles (MSV) in EMR summer (843425103 `rhs_c_troops.pbo`)

| Role | Class |
|---|---|
| Group leader | `rhs_msv_emr_sergeant` |
| Rifleman (x2 weight) | `rhs_msv_emr_rifleman` |
| Machine gunner (PKP) | `rhs_msv_emr_machinegunner` |
| Light AT | `rhs_msv_emr_LAT` |
| Grenadier | `rhs_msv_emr_grenadier` |
| Automatic rifleman | `rhs_msv_emr_arifleman` |
| RShG-2 | `rhs_msv_emr_RShG2` |
| Medic | `rhs_msv_emr_medic` |

AA soldiers (`rhs_msv_emr_aa`) are deliberately left out so the single AH-64D sortie is not lost to
an Igla every time.

## Support-by-fire vehicle (843425103)

| Class | PBO | Use |
|---|---|---|
| `rhs_btr80_msv` | `rhs_c_btr.pbo` | BTR-80 (KPVT 14.5 mm). First choice |
| `rhs_bmp2_msv` | `rhs_c_bmp.pbo` | BMP-2. Fallback only |

## Air support (843577117)

| Class | PBO | Use |
|---|---|---|
| `RHS_AH64D_CS` | `rhsusf_c_a2port_air.pbo` (`class RHS_AH64D_CS : RHS_AH64D`) | AH-64D close-support loadout. First choice |
| `RHS_AH64D` | same | Base AH-64D. Fallback |

The crew comes from `createVehicleCrew` (the config crew `rhsusf_army_ocp_ah64_pilot` exists in
`rhsusf_c_troops.pbo`).

## LAMBS functions (1858075458 `lambs_wp.pbo`, readable source)

| Function | Signature used (from the function header and `params`) |
|---|---|
| `lambs_wp_fnc_taskAssault` | `[group, pos, retreat=false, threshold=15, cycle=2, useWaypoint=false] spawn` (rushing assault: units ignore fire until they arrive) |
| `lambs_wp_fnc_taskCreep` | `[group, radius, cycle, area=[], centre, onlyPlayers=false] spawn` |
| `lambs_wp_fnc_taskRush` | `[group, radius, cycle, area=[], centre, onlyPlayers=false] spawn` |

`onlyPlayers` defaults to **true** in LAMBS. It is passed as `false` so the tasks also go after the AI
squad in test mode, and against AI squad members in normal play. Targets come from
`lambs_main_fnc_findClosestTarget`, which picks any enemy-side unit within `radius` of `centre`.

`taskAssault` keeps the group variable `lambs_wp_taskAssaultMembers` (`QGVAR(taskAssaultMembers)`,
PREFIX `lambs`, COMPONENT `wp`). Units are removed from it as they arrive. The mission switches a
group to `taskRush` once that list is empty, or after 7 minutes.

## Vanilla (already verified in-engine, `docs/arma/kb/classes-verified.md`)

| Class | Use |
|---|---|
| `B_Soldier_SL_F` | mission.sqm player slot |
| `Sh_82mm_AMOS` (CfgAmmo) | Virtual mortar round (standing in for the 81 mm M821; RHS's own M252 ammo is not used) |
| `Land_Cargo_HQ_V1_F`, `Land_Cargo_House_V1_F`, `Land_Cargo_Patrol_V1_F`, `Land_Cargo_Tower_V1_F` | Outpost structures searched for fighting positions |

Marker type `b_recon`, task type `defend` and the comm-menu icon `attack_ca.paa` (also used by LAMBS'
own config) are vanilla UI assets. **TO VERIFY** visually.

## BIS functions

Only functions in `docs/arma/kb/functions.txt` are used: `BIS_fnc_getParamValue`,
`BIS_fnc_taskCreate`, `BIS_fnc_taskExists`, `BIS_fnc_taskCompleted`, `BIS_fnc_taskSetState`,
`BIS_fnc_addCommMenuItem` and `BIS_fnc_endMission`.
