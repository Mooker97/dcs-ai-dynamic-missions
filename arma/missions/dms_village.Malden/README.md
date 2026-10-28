# Village Sweep (`dms_village.Malden`)

**Status: implemented, not run.** Static checks pass (`uv run pytest arma`). It has not been loaded in
Arma yet, neither headless nor by a player.

## Premise

You lead a US Army rifle squad (RHS USAF, OCP) on Malden 2035 with one attached M2A3 Bradley with an AI
crew. ChDKZ insurgents (RHS GREF) hold a small village. Clear it, then hold it against their
counterattack. It is grounded and small: one village, one vehicle, three orders.

## Flow

1. **Setup (seeded).** One of three villages is picked: Arudy, Houdan or Goisse (`DMS_village` param or
   the seed). The script counts the enterable houses there and logs them. A village outside 5–45 houses is
   skipped, and if none qualify it scans the whole map. The squad (you plus 8 AI: two fire teams with a
   medic) starts on foot about 700 m out, on the first seeded bearing with dry ground and no town. The
   Bradley sits 30 m behind you.
2. **Defenders.** Two 4-man groups and a 3-man RPG team (RPG-7 and RPG-26) garrison houses with
   `lambs_wp_fnc_taskGarrison`. Each group holds the buildings within 35 m of a seeded house. The RPG
   team holds the house nearest your side of the village. A DShKM UAZ technical is parked on a village
   road in 60% of seeds. That makes 11–13 defenders.
3. **Clear.** The village counts as clear when no more than 15% of the defenders are still alive within
   250 m *and* one of your squad is within 150 m of the centre.
4. **Counterattack.** 90–180 s later a Ural (Gaz-66 as fallback) with 8 insurgents arrives on a road
   1.3–1.7 km out, from at least 90° off your approach. A DShKM technical comes with it in 50% of seeds.
   The vehicles stop 300–450 m short and stay there as fire support; they do not hunt you. The infantry
   dismount and clear the village house by house (`lambs_wp_fnc_taskCQB`).
5. **Hold.** The counterattack is beaten when no more than 20% of its infantry are alive and no technical
   gun is still manned. The village is held once there has been no *known* insurgent inside 150 m, with
   your squad present, for 60 s. If the counterattack stalls for 25 min, the 60 s hold check starts
   anyway.

### Outcomes (`[DMS.OUTCOME]`)

| Result | End class | When |
|---|---|---|
| `WIN` | `DMS_Win` | village held, Bradley alive |
| `PARTIAL` | `DMS_WinPartial` | village held, Bradley lost (a win in Arma terms, marked partial for the debrief) |
| `FAIL` | `DMS_FailDead` | you are killed, or the whole squad is |
| `FAIL` | `DMS_FailMods` / `DMS_FailSetup` | required mod or class missing, or no usable village |

**Bradley loss is a partial success, not a failure.** Losing an IFV is serious, but the job is the village,
and a grounded mission should not end the moment the vehicle burns. The Bradley counts as lost when it is
destroyed or no crew is alive inside it (they bailed out or were killed). Its task ("Keep the Bradley")
then fails. The line also carries `ifv=alive|lost`.

## The Bradley (comm menu 0-8)

The crew runs its own engagements (combat mode YELLOW). LAMBS is switched off for its crew and group so it
does not wander between orders.

| Order | What it does |
|---|---|
| Bradley: move up to my position | Drives to 25 m short of you (on your side), stops, reports. Reports "can't get through" after 240 s |
| Bradley: hold here, overwatch | Stops where it is and covers |
| Bradley: suppress marked position | Uses the comm-menu cursor (look at a spot, or click on the map). The gunner fires about 20 s of suppressive fire on it (`doSuppressiveFire`). Refused when friendlies are within 50 m of the spot, beyond 1.5 km, without terrain line of sight from the Bradley, or within 30 s of the last one |

Answers come as hints and are logged.

## How to play

Load **CBA_A3, ACE (the SP repack is fine), LAMBS_Danger, RHSAFRF, RHSUSAF, RHSGREF**. RHS GREF does
not load without AFRF. Copy the folder to `Documents\Arma 3\missions\` (editor) or `MPMissions\`. If a
mod is missing, the mission says which and ends ("Cannot start"). Recommended: Veteran, no crosshair.

## Test mode

The params are the same as The Hill's: `DMS_testMode`, `DMS_seed`, `DMS_testMinutes`, `DMS_testTimeScale`,
`DMS_testStartDist`, `DMS_testAssist`, `DMS_testForce`, plus `DMS_village` and `DMS_debug`. With no player
an AI squad plays. Here is what the test run does:

1. It checks `mods`, `spawn_village`, `spawn_defenders`, `spawn_squad` and `spawn_bradley`.
2. The squad moves to a staging point 250 m out. After 120 m it orders the Bradley up (`ifv_move`).
3. At the staging point it orders the Bradley up again, then has it suppress a defender it has terrain
   line of sight to (`ifv_suppress`, up to 3 tries), then hold (`ifv_hold`).
4. The squad searches and destroys through the village (`village_cleared`).
5. Then `counterattack`, `village_held` and `outcome_win` (WIN or PARTIAL both pass).

`DMS_testAssist` = N removes the remaining defenders N s after the squad gets within 200 m. It also removes
what is left of the counterattack N s after it dismounts. Both are logged as `Test: ... assist`.

`DMS_testForce`: 1 destroys the Bradley after the clear (`outcome_forced` expects `DMS_WinPartial`, plus
`ifv_lost`). 2 kills the squad after the clear (expects `DMS_FailDead`).

```
uv run python tools/arma_harness/run_mission.py arma/missions/dms_village.Malden --mods core,843425103,843577117,843593391 --seeds 1,2,3 --minutes 40 --param DMS_testAssist=180
```

**The AFRF id 843425103 is needed.** `--mods core,843577117,843593391` without it would fail to load GREF.

## To verify in-engine

- The house counts of Arudy, Houdan and Goisse (the `Village ...` log lines), and that the centroid lands in
  the village. Also that LAMBS garrisons fill the houses (`Garrison N: ...` lines and debug markers).
- The start bearing gives a sensible approach: a dry line was checked, but not slope or forest.
- The counterattack road spawn and its dismount point (`Rolls:` and `Counterattack spawned ...`).
- That the Bradley obeys `doMove`/`doStop` on its commander, and that the LAMBS disable variables keep it
  in place.
- That `doSuppressiveFire` + `suppressFor` makes the M2A3 gunner fire (the `ifv_suppress` round count).
- That `getUnitLoadout (configFile >> ...)` gives the player the RHS squad leader loadout.
- That task type `armor` exists (task icon only).
- That the insurgents (side EAST) and the squad engage normally with LAMBS loaded.
