# Village Sweep: classes, functions and data used

**How this was checked (2026-10-28, no game running).** Mod PBOs in
`E:\SteamLibrary\steamapps\workshop\content\107410\<id>\addons` were read with a small PBO reader and
rapified-config parser (scratch tool, not committed). Each class below was found as a `CfgVehicles` class
in the named PBO's `config.bin`, with its parent, `scope`, `side` and `faction` read from the config.
`side` and `scope` are inherited where the class itself does not set them (parent shown).
The mission checks every class again at start with `isClass` and logs `Missing classes ...` as a WARN.
**Not yet confirmed in-engine.**

Mod versions on disk: CBA 3.19.0, ACE 3.21.2 (SP repack, medical and advanced fatigue disabled),
LAMBS 2.6.2.1, RHS AFRF/USAF/GREF 0.5.6.

## Required mods (CfgPatches checked at start)

| Label | CfgPatches | Workshop id | PBO |
|---|---|---|---|
| CBA_A3 | `cba_main` | 450814997 | `cba_main.pbo` |
| ACE3 | `ace_main` | 1744095754 | `ace_main.pbo` |
| LAMBS Danger | `lambs_danger` | 1858075458 | `lambs_danger.pbo` |
| LAMBS Waypoints | `lambs_wp` | 1858075458 | `lambs_wp.pbo` |
| RHS AFRF | `rhs_main` | 843425103 | `rhs_main.pbo` |
| RHS USAF | `rhsusf_main` | 843577117 | `rhsusf_main.pbo` |
| RHS GREF | `rhsgref_main` | 843593391 | `rhsgref_main.pbo` |

RHS GREF's `rhsgref_main` requires `rhs_main_loadorder` (AFRF) and `rhsusf_main_loadorder` (USAF), so
GREF cannot load without AFRF. The harness command must include 843425103.

## US Army (RHS USAF, 843577117)

| Role | Class | PBO | Config |
|---|---|---|---|
| Squad leader (player loadout, test-mode AI leader) | `rhsusf_army_ocp_squadleader` | `rhsusf_c_troops.pbo` | parent `rhsusf_infantry_army_base` (side 1 = WEST, faction `rhs_faction_usarmy_d`), scope 2 |
| Team leader | `rhsusf_army_ocp_teamleader` | `rhsusf_c_troops.pbo` | same base, scope 2 |
| Automatic rifleman | `rhsusf_army_ocp_autorifleman` | `rhsusf_c_troops.pbo` | same base, scope 2 |
| Grenadier | `rhsusf_army_ocp_grenadier` | `rhsusf_c_troops.pbo` | same base, scope 2 |
| Rifleman (AT) | `rhsusf_army_ocp_riflemanat` | `rhsusf_c_troops.pbo` | parent `rhsusf_army_ocp_rifleman`, scope 2 |
| Medic | `rhsusf_army_ocp_medic` | `rhsusf_c_troops.pbo` | parent `rhsusf_army_ocp_rifleman` (scope 2 inherited) |
| Bradley | `RHS_M2A3` | `rhsusf_c_a2port_armor.pbo` (CfgPatches `RHS_US_A2Port_Armor`) | parent `RHS_M2A2` (scope 2, side 1), `crew = rhsusf_army_ocp_crewman` |

## ChDKZ insurgents (RHS GREF, 843593391)

All infantry inherit `rhsgref_ins_base` (side 0 = EAST, faction `rhsgref_faction_chdkz`). The
`rhsgref_ins_g_*` classes are the independent ChDKZ and are not used. The mission reads the side from
config at runtime (`["SIDE", ...] call DMS_fnc_village`), so a side change would still work.

| Role | Class | PBO | Config |
|---|---|---|---|
| Leader | `rhsgref_ins_squadleader` | `rhsgref_c_troops.pbo` | scope 2 |
| Rifleman AKM | `rhsgref_ins_rifleman_akm` | `rhsgref_c_troops.pbo` | scope 2 |
| Machine gunner | `rhsgref_ins_machinegunner` | `rhsgref_c_troops.pbo` | scope 2 |
| Rifleman | `rhsgref_ins_rifleman` | `rhsgref_c_troops.pbo` | scope 2 |
| Rifleman AKS-74 | `rhsgref_ins_rifleman_aks74` | `rhsgref_c_troops.pbo` | scope 2 |
| Automatic rifleman RPK | `rhsgref_ins_arifleman_rpk` | `rhsgref_c_troops.pbo` | scope 2 |
| Grenadier | `rhsgref_ins_grenadier` | `rhsgref_c_troops.pbo` | scope 2 |
| RPG gunner | `rhsgref_ins_grenadier_rpg` | `rhsgref_c_troops.pbo` | scope 2 |
| Rifleman RPG-26 | `rhsgref_ins_rifleman_RPG26` | `rhsgref_c_troops.pbo` | scope 2 |
| Medic | `rhsgref_ins_medic` | `rhsgref_c_troops.pbo` | scope 2 |
| Technical (UAZ DShKM) | `rhsgref_ins_uaz_dshkm` | `rhsgref_c_vehicles_ret.pbo` | scope 2, side 0, crew `rhsgref_ins_rifleman` |
| Counterattack truck | `rhsgref_ins_ural` | `rhsgref_c_vehicles_ret.pbo` | scope 2, side 0 |
| Counterattack truck (fallback) | `rhsgref_ins_gaz66` | `rhsgref_c_vehicles_ret.pbo` | scope 2, side 0 |

## LAMBS (1858075458)

| Name | Where | Notes |
|---|---|---|
| `lambs_wp_fnc_taskGarrison` | `lambs_wp.pbo`, `functions\fnc_taskGarrison.sqf` (CfgFunctions string `lambs_wp_fnc_taskgarrison`) | Header: `[group, position, range = 50, area = [], teleport, sortByHeight, exitCondition (-2 random, -1 all, 0 hit, 1 fired, 2 firedNear), patrol]`. Used with teleport and sort-by-height on, exit condition -2 |
| `lambs_wp_fnc_taskCQB` | `lambs_wp.pbo`, `functions\fnc_taskCQB.sqf` (`lambs_wp_fnc_taskcqb`) | Header: `[group, position, radius = 50, cycle = 21, area = [], isWaypoint = false]`; spawns itself when unscheduled. Used for the counterattack infantry |
| `lambs_danger_disableAI` | `lambs_danger.pbo` | Unit variable (`QGVAR(disableAI)`), set true on the Bradley crew |
| `lambs_danger_disableGroupAI` | `lambs_danger.pbo` | Group variable (`QGVAR(disableGroupAI)`), set true on the Bradley group |

## Vanilla

| What | Name | Where |
|---|---|---|
| mission.sqm player slot | `B_Soldier_SL_F` | `A3_Characters_F` (the only addon in `mission.sqm`); the RHS loadout is applied by script |
| Comm-menu icons | `transport_ca.paa`, `defend_ca.paa`, `attack_ca.paa` | `\a3\Ui_f\data\GUI\Cfg\CommunicationMenu\`, strings found in `Addons\ui_f.pbo` |
| Comm-menu cursor | `iconCursorSupport_ca.paa` | as used by The Hill |
| Task types | `attack`, `defend`, `armor` | icon paths `simpleTasks\types\<type>_ca.paa` found in `Addons\ui_f.pbo` (class names in CfgTaskTypes not read: TO VERIFY `armor`) |
| BIS functions | `BIS_fnc_getParamValue`, `BIS_fnc_taskCreate`, `BIS_fnc_taskSetState`, `BIS_fnc_taskExists`, `BIS_fnc_taskCompleted`, `BIS_fnc_addCommMenuItem`, `BIS_fnc_endMission` | `docs/arma/kb/functions.txt` (enforced by `arma/tools/test_kb_functions.py`) |
| Engine commands (not in the KB, from memory) | `doSuppressiveFire`, `suppressFor`, `getUnitLoadout` (config form), `terrainIntersectASL`, `doWatch`, `nearestLocations` | TO VERIFY in-engine |

## Malden village locations

From `Argo\Addons\map_malden.pbo`, `config.bin`, `CfgWorlds >> Malden >> Names` (`mapSize = 12800`).
The positions are the map's own location points, so they are exact. The house counts are not known yet:
the mission logs `Village <label>: location '<text>' ... N enterable houses` for each candidate.

| Label | Config class | Type | position |
|---|---|---|---|
| Arudy | `Malden_V_Arudy` | NameVillage | 5537.25, 6983.24 |
| Houdan | `Malden_V_Houdan` | NameVillage | 7121.48, 6074.55 |
| Goisse | `Malden_V_Goisse` | NameVillage | 3584.88, 8520.04 |

Other locations seen (not used): Larche (NameCity 6012, 8627), La Trinité (NameCityCapital 7264, 7931),
La Pessagne (NameCity 3116, 6331), Chapoi (NameCity 5836, 3530), Vigny, Sainte Marie, La Rivière, Cancon,
Le Port, Dourdan, Saint Louis, Lolisse (NameVillage), Airport, Moray.
