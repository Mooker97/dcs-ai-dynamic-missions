# Ambient module classes

Every class in `functions/fn_ambientPresets.sqf` is listed here with how it was checked. At
runtime `DMSA_fnc_ambientAdd` also runs `isClass (configFile >> "CfgVehicles" >> _x)` on every
class. It drops missing classes and logs them as
`[DMS] WARN: Ambient [id] classes missing in this game config, dropped: [...]`. A preset whose
infantry is all missing falls back to `vanilla_nato`. The first harness run therefore settles
every TO VERIFY below.

Legend:
- **kb**: in `docs/arma/kb/classes-verified.md`, which was `isClass`-checked on a dedicated server on 2026-10-27.
- **PBO**: the class name was found as a config string in the mod's PBOs on 2026-10-28, with
  `E:\SteamLibrary\steamapps\workshop\content\107410\843577117\addons\*.pbo` for RHS USAF 0.5.6.
  It has not been loaded in game yet.
- **game PBO**: found as a config string in the installed Arma 3 PBOs (`E:\SteamLibrary\steamapps\common\Arma 3`) on 2026-10-28. Not `isClass`-checked yet.
- **TO VERIFY**: from memory, not checked anywhere yet.

## vanilla_nato (side west)

| List | Class | Source |
|---|---|---|
| infantry | `B_Soldier_F`, `B_Soldier_GL_F`, `B_soldier_AR_F`, `B_Soldier_TL_F`, `B_medic_F`, `B_soldier_M_F` | kb |
| sentry | `B_Soldier_F`, `B_Soldier_GL_F` | kb |
| worker | `B_engineer_F` | game PBO (`characters_f.pbo`) |
| worker | `B_Soldier_F` | kb |
| driver | `B_Soldier_F` | kb |
| traffic | `B_Truck_01_transport_F`, `B_Truck_01_covered_F`, `B_MRAP_01_F` | game PBO (`soft_f_beta.pbo`, `data_f.pbo`, `baseconfig_f.pbo`) |
| parked | `B_Truck_01_transport_F`, `B_MRAP_01_F` | game PBO |
| heli | `B_Heli_Transport_01_F` | kb |
| heli | `B_Heli_Transport_03_unarmed_F` | game PBO (`Heliddonsir_f_heli.pbo`, Helicopters DLC content) |

## rhs_usarmy (side west; desert vehicles for Altis/Malden)

| List | Class | Source |
|---|---|---|
| infantry | `rhsusf_army_ocp_rifleman`, `rhsusf_army_ocp_rifleman_m4`, `rhsusf_army_ocp_autorifleman`, `rhsusf_army_ocp_grenadier`, `rhsusf_army_ocp_teamleader`, `rhsusf_army_ocp_machinegunner`, `rhsusf_army_ocp_medic`, `rhsusf_army_ocp_squadleader` | PBO (`rhsusf_c_troops.pbo`) |
| sentry | `rhsusf_army_ocp_rifleman`, `rhsusf_army_ocp_rifleman_m4` | PBO |
| worker | `rhsusf_army_ocp_engineer`, `rhsusf_army_ocp_driver` | PBO |
| driver | `rhsusf_army_ocp_driver` | PBO |
| traffic | `rhsusf_m1025_d`, `rhsusf_m998_d_2dr_halftop`, `rhsusf_m1151_usarmy_d` | PBO (`rhsusf_c_hmmwv.pbo` / `rhsusf_c_m11xx.pbo`, which hold the HMMWV classes) |
| traffic, parked | `rhsusf_M1078A1P2_D_fmtv_usarmy` | PBO (`rhsusf_c_fmtv.pbo`) |
| parked | `rhsusf_m998_d_4dr` | PBO |
| heli | `RHS_UH60M_d`, `RHS_UH60M` | PBO (`rhsusf_c_a2port_air.pbo`) |

## rhs_usmc (side west)

| List | Class | Source |
|---|---|---|
| infantry | `rhsusf_usmc_marpat_wd_rifleman`, `_rifleman_m4`, `_autorifleman`, `_grenadier`, `_teamleader`, `_machinegunner`, `_squadleader`, `_rifleman_light` (all prefixed `rhsusf_usmc_marpat_wd`) | PBO (`rhsusf_c_troops.pbo`) |
| sentry | `rhsusf_usmc_marpat_wd_rifleman`, `rhsusf_usmc_marpat_wd_rifleman_m4` | PBO |
| worker | `rhsusf_usmc_marpat_wd_engineer`, `rhsusf_usmc_marpat_wd_driver` | PBO |
| driver | `rhsusf_usmc_marpat_wd_driver` | PBO |
| traffic | `rhsusf_m1025_d_s`, `rhsusf_m998_d_s_2dr_halftop`, `rhsusf_m1043_d_s`, `rhsusf_m1151_usmc_d` | PBO |
| parked | `rhsusf_m998_d_s_4dr`, `rhsusf_m1043_d_s` | PBO |
| heli | `RHS_UH1Y_UNARMED_d`, `RHS_UH1Y_UNARMED` | PBO (`rhsusf_c_a2port_air.pbo`) |

Woodland MARPAT infantry is used because only the `_wd` USMC infantry names were checked. Pass
`classes` to override, for example on Enoch with woodland vehicles.

## Other classes and names used by the module

| Name | Used for | Source |
|---|---|---|
| `Land_HelipadEmpty_F` | Invisible pad under the helicopter landing spot | kb |
| `Land_BarGate_F` | Finds sentry posts (`nearestObjects`). If none are found, the road fallback is used | game PBO (`structures_f.pbo`). Whether Altis bases have them is TO VERIFY (see the survey line) |
| `HeliH` | Base class used to find existing helipads (`nearestObjects`), with flat ground as the fallback | game PBO (`structures_f_mil.pbo`). That it is the helipad base class is TO VERIFY |
| `House` | Base class used to find buildings for the idle spots | TO VERIFY (standard A3 base class) |
| `rhsusf_army_ocp_rifleman` | Detects RHS USAF for `faction = "auto"` | PBO |
| `lambs_danger_disableAI` (unit), `lambs_danger_disableGroupAI` (group) | Opts out of LAMBS Danger | PBO (`lambs_danger.pbo` 2.6.2: 3DEN attributes and `fnc_isForcedExit`; also read in `lambs_main.pbo` and `lambs_wp.pbo`) |
| `BIS_fnc_ambientAnim` | Idle and work animations | `docs/arma/kb/functions.txt`. Set names read from `A3\Functions_F\Ambient\fn_ambientAnimGetParams.sqf` |
| unit variable `BIS_fnc_ambientAnim` + `__logic` | Deletes the helper logic on despawn | Read from `A3\Functions_F\Ambient\fn_ambientAnim.sqf` (`_unit setVariable [..., _logic]`) and `fn_ambientAnim__terminate.sqf` |
