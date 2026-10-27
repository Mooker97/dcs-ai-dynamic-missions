# Class names verified in Arma 3 (vanilla)

**Verified 2026-10-27** on Arma 3 Stable 2.22.154089 (`productVersion`), dedicated server
(`arma3server_x64.exe`), base game only, no mods or `-mod` lines. CDLC folders are installed, but
nothing here needs them.

**How:** `tools/arma_harness/make_diag.py` generates `tools/arma_harness/diag/dms_diag.Altis`. Its
`initServer.sqf` loads the real `functions/fn_config.sqf`, collects every class-like string, adds the
alternatives listed in `EXTRA_CLASSES`, and logs
`isClass (configFile >> "CfgVehicles"|"CfgWeapons"|"CfgMagazines"|"CfgAmmo" >> _x)` for each one.
Run it with `uv run python tools/arma_harness/run_mission.py tools/arma_harness/diag/dms_diag.Altis --diag`.
It takes about 40 s of wall time.

**Result:** every class the mission uses exists. None were missing.

## Used by `dms_the_hill.Altis`

| Role | Class | Config |
|---|---|---|
| Player squad | `B_Soldier_TL_F`, `B_soldier_AR_F`, `B_Soldier_GL_F`, `B_medic_F`, `B_soldier_LAT_F`, `B_soldier_M_F`, `B_Soldier_F` | CfgVehicles |
| CSAT infantry | `O_Soldier_F`, `O_Soldier_AR_F`, `O_Soldier_GL_F`, `O_Soldier_LAT_F`, `O_soldier_M_F`, `O_Soldier_TL_F`, `O_medic_F` | CfgVehicles |
| QRF vehicles | `O_Truck_02_transport_F`, `O_Truck_03_transport_F`, `O_APC_Wheeled_02_rcws_v2_F`, `O_APC_Wheeled_02_rcws_F` | CfgVehicles |
| Static weapon | `O_HMG_01_high_F` | CfgVehicles |
| Extraction | `B_Heli_Transport_01_F` (UH-80 Ghost Hawk) | CfgVehicles |
| Props | `Land_CampingTable_F`, `Land_Laptop_unfolded_F`, `CamoNet_OPFOR_open_F`, `Box_East_Ammo_F`, `Land_HelipadEmpty_F` | CfgVehicles |
| Built compound (BUILD mode) | `Land_Cargo_HQ_V1_F`, `Land_Cargo_House_V1_F`, `Land_Cargo_Patrol_V1_F`, `Land_BagBunker_Small_F`, `Land_BagFence_Round_F`, `Land_BagFence_Long_F`, `Land_HBarrier_5_F`, `Land_Razorwire_F` | CfgVehicles |
| Mortar shell | `Sh_82mm_AMOS` | **CfgAmmo only**. `createVehicle` on it works and the round detonates on impact (see `docs/arma/TESTING.md`) |

## Also present (checked as alternatives)

`O_Truck_02_covered_F`, `O_Truck_03_covered_F`, `O_MRAP_02_hmg_F`, `O_MRAP_02_F`,
`O_APC_Tracked_02_cannon_F`, `Land_Cargo_Tower_V1_F`, `Land_Cargo_House_V3_F`,
`Land_Cargo_Patrol_V3_F`, `CamoNet_OPFOR_F`, `CamoNet_OPFOR_big_F`, `Land_CampingTable_small_F`,
`Land_WoodenTable_large_F`, `Land_Laptop_device_F`, `Land_Laptop_F`, `Land_File1_F`, `Land_Map_F`,
`Box_East_Wps_F`, `O_supplyCrate_F`, `Land_HBarrier_3_F`, `O_HMG_01_F`, `O_GMG_01_high_F`,
`B_Mortar_01_F`, `B_Heli_Transport_01_camo_F`, `B_Soldier_SL_F`, `O_Soldier_SL_F` (all CfgVehicles).
`Sh_155mm_AMOS` and `R_80mm_HE` (CfgAmmo). `8Rnd_82mm_Mo_shells` (CfgMagazines).

## Building positions (`count (_bld buildingPos -1)`)

| Class | Positions |
|---|---|
| `Land_Cargo_House_V1_F` / `_V3_F` | 1 |
| `Land_Cargo_Patrol_V1_F` / `_V3_F` | 2 |
| `Land_Cargo_HQ_V1_F` | 13 |
| `Land_Cargo_Tower_V1_F` (terrain object) | 18 |

The original BUILD composition had two cargo houses and one patrol tower, which give 4 positions for
5 garrison riflemen. One house is now a `Land_Cargo_HQ_V1_F`.

## Log noise that is not an error

On spawn the server logs `soldier[O_Soldier_LAT_F]:Some of magazines weren't stored in soldier Vest
or Uniform?` and `Duplicate HitPoint name 'HitGun' in 'O_HMG_01_high_F'`. Both come from vanilla
config and are harmless. The harness does not count them as script errors.
