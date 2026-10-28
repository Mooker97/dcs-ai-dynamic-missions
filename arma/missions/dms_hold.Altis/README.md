# Hold the OP

**Status: implemented, not run.** The static checks pass (`uv run pytest arma`). The mission has not
been loaded in Arma yet, either headless or by a player.

## Premise

A US Army squad (RHSUSAF, OCP) holds a small observation post on the high ground of Altis. A Russian
motor-rifle company (RHSAFRF, MSV in EMR summer) attacks it in three waves over about 20 minutes. A
BTR-80 supports the main attack by fire from stand-off range. The squad has a tripod M2, an 81 mm
mortar section on call, and one AH-64D sortie. It has to hold until the relief element arrives.

The design is grounded and simple. There is one position and three attacks. Support is limited and
slow, and danger-close requests are refused. There is no respawn and no scripted heroics.

## Flow

1. **Start.** The squad (player as squad leader plus 7 AI) is already in position. Up to 4 of them go to the
   outpost's tower and house positions, highest first. The rest go to clear ground round the OP, and
   the rifleman starts on the M2. The AI hold where they are put (`doStop`) until the player orders
   otherwise. The OP is one of two verified terrain outposts, chosen by seed or by the `DMS_site` param.
2. **Prep.** There are 2.5–4 minutes before wave 1.
3. **Wave 1 (probe).** 6 men creep in from a seeded direction (LAMBS `taskCreep`). They hold fire
   for as long as possible.
4. **Wave 2 (main attack).** It comes when wave 1 is broken, or 5–7 minutes after it at most. 7 men
   make a rushing assault (LAMBS `taskAssault`) to an assault position 180 m out, then rush the OP
   (`taskRush`). Another 6 creep in 40° off that axis. At the same time a **BTR-80** drives to a
   support-by-fire position 800–1000 m out with line of sight to the OP. Its driver is then
   locked (`disableAI "PATH"`), so it **never closes on the squad**. It has low gunnery skill, and it
   withdraws once wave 2 is broken.
5. **Wave 3 (final assault).** 8 men make a rushing assault from another direction.
6. **Relief.** The relief arrives 2 minutes after the last wave is broken, or 10 minutes after
   it spawned at the latest. That is a **win**.

Each wave's spawn point is seeded. It is snapped to dry, gentle ground 900–1150 m out and preferably
in dead ground, out of sight of the OP. No wave comes from the friendly rear. Every wait is bounded.

**Fail** if the player is killed, the squad is wiped out, or the OP is **overrun**: enemy inside
60 m of the OP centre with no (non-captive) friendlies inside it for 60 s.

## Fire support (comm menu 0-8)

| Support | Limits | Realism |
|---|---|---|
| 81 mm mortars: spotting round | 2 | 60 s processing plus 25 s time of flight. Each round is 1 HE |
| 81 mm mortars: fire for effect | 3 missions of 6 rounds | 50 m CEP. 25 m CEP within 150 m of a recent spotting round. **Refused within 200 m of friendlies** |
| AH-64D attack | 1 sortie | About 2 min tasking, then a real flight in from 7 km along the friendly rear. Enemies within 200 m of the mark are passed to the crew. 3 min on station, then return to base. **Refused within 150 m of friendlies**. A refused request does not use up the sortie. It can be shot down |

The mortar is virtual. It uses the same pattern as The Hill (`createVehicle` of the vanilla
`Sh_82mm_AMOS` shell, which is verified in-engine). The helicopter is a real AI-crewed RHS AH-64D.

## How to play

1. Load these mods: **CBA_A3** (450814997), **ace Singleplayer** (1744095754), **LAMBS_Danger**
   (1858075458), **RHSAFRF** (843425103) and **RHSUSAF** (843577117). RHSGREF and RHSSAF are not needed.
2. Copy `dms_hold.Altis` to `Documents\Arma 3\missions\` (or `mpmissions\`) and start it from the
   editor or the scenario list. Veteran difficulty, no crosshair.
3. If a mod is missing, the mission ends at once with "Required mods missing", a hint that lists
   what is missing, and `Mod check:` lines in the `.rpt`.

Params: seed, OP (from seed / Agia Triada / Agios Petros), debug (wave and SBF markers, log to
screen).

## Test notes

Test mode has the same protocol as The Hill. `DMS_testMode=1` lets an AI squad hold the OP with no
player. The harness calls the same server functions the comm menu does. Run it with:

```
uv run python tools/arma_harness/run_mission.py arma/missions/dms_hold.Altis --mods core,843425103,843577117
```

The harness defaults (15 min, 15 % time scale, start distance 300, assist 180) give the following
behaviour:
- `DMS_testStartDist > 0` brings the wave spawns in to at least 450 m (450–600 m) and the SBF
  position to at most 900 m.
- `DMS_testAssist` removes what is left of a wave once it has been within 300 m of the OP for that
  many seconds. This is logged and only happens in test mode.
- Delays are scaled with floors: wave gaps at least 120 s, relief at most 360 s after the last
  wave plus at least 60 s, air on station at least 90 s, overrun at least 20 s. The whole run should
  end in about 9–11 mission minutes.

Checks (`[DMS.TEST] PASS|FAIL`):
- `mods`, `spawn_squad`, `spawn_static`
- `mortar_danger_close` and `air_danger_close`: requests on the OP itself must be refused without
  using up a mission
- `wave1`–`wave3`, `sbf_in_position`
- `mortar` (FFE on wave 2 between 250 and 800 m; half of the detonations must land within 150 m)
- `air_requested` and `air_on_station` (on the BTR once it holds, else on a wave 2 leader)
- `outcome_win`

Forced failures: `--param DMS_testForce=1` wipes the squad after wave 1, so the expected end is
`DMS_FailDead`. `--param DMS_testForce=2` moves the squad out (captive) and wave 1 into the OP,
so the expected end is `DMS_FailOverrun`.

## To verify in-engine

- The wave bearings per site are **not measured**. They are snapped at runtime, and the
  `Plan:` lines log the distance and whether each spawn can be seen from the OP. Look for
  `Wave spot: nothing dry and gentle` warnings.
- The SBF position needs line of sight to the OP (logged in `Plan: support-by-fire ...`). The BTR
  has to actually reach it (`sbf_in_position`, `SBF: holding ...`).
- `setUnitLoadout` with a CfgVehicles config entry gives the player the RHS squad leader kit
  (`Player loadout set from ...`).
- The `RHS_M2StaticMG_D` gunner gets in, and the tower positions (`Squad: ... placed`) are usable.
- The LAMBS tasks behave as intended with `onlyPlayers = false`. `taskAssault` clears
  `lambs_wp_taskAssaultMembers` on arrival, which triggers the switch to `taskRush`. If it doesn't,
  the 7-minute timeout does.
- The AH-64D AI engages revealed targets with the SAD waypoint, survives the BTR's KPVT, and leaves.
- Balance: can 8 men with an M2 hold against 27 infantry plus a BTR? Tune `waves`, `enemySkill`
  and `sbfSkill` in `fn_config.sqf`.
- The two OPs are only moderately high (35–37 m terrain height). They are verified outposts, not
  true hilltops.
