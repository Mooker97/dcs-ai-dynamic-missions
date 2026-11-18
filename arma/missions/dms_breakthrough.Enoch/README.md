# Breakthrough (Livonia)

**Status: implemented, not flown by a human.** The static checks pass (`uv run pytest arma/tools`). The
headless results are in "Test results" below. Test tier: headless AI on a dedicated server, never played.

## Premise

You command one M1A2 SEP Abrams (RHS, woodland) with an AI driver and gunner. A section of two M2A3
Bradleys with an 8-man rifle squad follows you. Advance about 3 km along a farm road on Livonia, break a
Russian armour screen and take a crossroads village. Two A-10 strikes are on call, and a pre-planned strike
hits the village defences when you cross the phase line. There is no voice and no dialogue. You get short
text hints only.

Grounded and simple:
- There are no exact enemy markers. The objective is a 300 m area, offset 50–120 m from the crossroads.
- There is no respawn.
- Assume Veteran difficulty.

## Flow

1. **Start.** The seed (or the `DMS_site` param) picks one of three verified approaches. Each is a 3 km road
   route, taken offline from the terrain's road shapefile and checked in-engine for open ground and
   treelines (see CLASSES.md):
   - Bielawa from the Lukow road
   - Topolin from the Radacz road
   - Grabin from the Zapadlisko road

   The script then works out the rest:
   - **The crossroads:** the road segment with 3 or more connections nearest the village point.
   - **The phase line, PL BLUE:** 1 km out by road.
   - **The treeline ambush:** 1.0–1.7 km out by road and 250–700 m off it. The spot needs a treeline
     behind it, clear ground at it and line of sight to the road. The seed picks the side and the spot.
   - **The ATGM spot:** 0.5–1.1 km out, usually on the other flank.
   - **The BMP's spot:** at the village edge, 150–260 m short of the crossroads, beside the road.

   All of it is logged.
2. **Your tank.** It starts on the road with the gun forward. You sit in the commander's seat. The driver
   and gunner are AI in your group, so order them as usual or switch seats from the action menu.
3. **The section.**
   - Bradley 1 keeps 150–250 m behind you along the road, and Bradley 2 another 100 m behind it.
   - They stop when you stop and never pass you. They fight on their own (combat mode YELLOW).
   - When the village armour is dead and you or they are within 800 m of the crossroads, they move up,
     stop 300 m short and dismount the squad. The squad then clears house by house within 150 m of the
     crossroads (LAMBS taskCQB).
   - Losing a Bradley or the squad is logged with a short hint. It does not fail the mission.
4. **The enemy (RHS AFRF):**
   - 2 T-72B3 dug in at a treeline (no driving, turret free).
   - A Metis-M ATGM with a 2-man team on a flank.
   - A dug-in BMP-2 with an RPG team at the village edge.
   - A 7-man rifle squad garrisoned round the crossroads (LAMBS taskGarrison).
   - **Counter-attack, maybe (60 %, seeded):** if the village has not fallen 10 minutes after you cross
     PL BLUE, a T-72B3 and a BMP-3 come in from 1.5 km beyond the village, and you get a spot report.
5. **Phase line.** Crossing PL BLUE gives the hint "Phase line crossed. Pre-planned strike inbound on the
   village defences." An A-10 pass then drops 4 x Mk82 (35 m CEP) on the village defences about 30 s
   plus the run-in later.
6. **Win (either):**
   - **Cleared:** no village armour left (the BMP, plus the counter-attack if it came), at most 2 enemy men
     alive within 250 m of the crossroads, and your tank or a dismount within 200 m of it.
   - **Held:** your tank within 75 m of the crossroads for 2 minutes with no enemy armour alive within 3 km.
7. **Fail:** your tank is destroyed, or you are killed.
   - **Immobilised (alive) is not a fail.** After 20 s you get the hint "Keep fighting from the hull, or bail
     out and fall back to the Bradleys." After 10 minutes immobilised without a win, the mission ends as a
     draw (`DMS_Draw`, "Attack stalled", `result=DRAW`).

Every ending goes through `DMS_fnc_end`, which writes one `[DMS.OUTCOME] result=WIN|FAIL|DRAW end=... reason=...
seed=... site=... t=...` line.

## Air support

- **CAS: A-10 bomb run on marked position** (comm menu `0-8`, 2 uses). Aim the cursor at a spot, or open
  the map and click. An RHS A-10A flies a real pass from behind you and drops 2 x Mk82 (25 m CEP). Expect
  about 90 s of tasking plus about 50 s of run-in. Requests within 200 m of friendlies are refused and the
  strike is not used up.
- **How it is kept reliable:** the jet is for the look and sound. The bombs are spawned by script just
  above the aim point along the jet's heading, with a seeded CEP. They drop when the jet is within 700 m,
  or when its transit times out. The jet crew is captive, so enemy air defence never decides whether the
  strike happens.

## How to play

1. Load these mods: **CBA_A3, ACE (the SP repack), LAMBS Danger, RHS AFRF and RHS USAF**. RHS GREF is
   optional. Livonia (Contact DLC terrain) must be installed. If a mod is missing, the mission says which
   one and ends.
2. Copy the folder `dms_breakthrough.Enoch` to `Documents\Arma 3\missions\` and open it in Eden (Livonia),
   or start it from the scenario list. Play on Veteran.
3. You spawn in the tank. Open the map: the LD is your start, PL BLUE is the flag 1 km out, and the red
   hatched circle is the objective area.

**Tips:**
- Stop short of the treelines and scan before you cross open ground.
- Spend the first A-10 on whatever stopped you, not on a guess.
- Hull-down behind a rise beats a duel in the open.
- Let the pre-planned strike land before you drive into the village.

## Parameters

| Param | Values | Meaning |
|---|---|---|
| `DMS_seed` | 0 (random, logged), 1, 2, 3, 7, 42, 1337, 4242 | Seeds the site, the treeline/ATGM/BMP spots, the counter-attack roll and the bomb dispersion |
| `DMS_site` | 0 (from seed), 1–3 | Forces a site |
| `DMS_debug` | 0/1 | Shows log lines in `systemChat` and puts markers on enemy positions and the route |
| `DMS_testMode` | 0/1 | Runs the mission unattended with an AI-crewed tank |
| `DMS_testMinutes` | 15–90 | Hard stop for test mode |
| `DMS_testTimeScale` | 100/50/25/15/10 | Scales the mission-logic delays (`DMS_fnc_t`) in test mode only |
| `DMS_testStartDist` | 0, 1500, 2000 | Test-mode start distance by road. Values below 1500 (the harness default 300) mean normal, so the treeline is always on the route |
| `DMS_testAssist` | 0/120/180/300 | Test only. This many seconds into each stage (treeline fight, village armour, village clearance), the stage's remaining enemies are removed and counted (`assisted N` in the checks) |
| `DMS_testForce` | 0/1 | 1 = the tank is destroyed at first contact. Expects `DMS_FailTank` |

## Test mode

In test mode an AI-crewed M1A2 (its own group) runs the route with the same section and support. AI can't use
the comm menu, so the harness calls `DMS_fnc_air` `REQUEST` directly. The AI commander is told about
enemies within 2.2 km, standing in for the player's eyes. The tank:
1. drives to about 2.2 km out, halts, calls CAS 1 on the treeline tanks and fights them
2. advances to 450 m short of the crossroads (CAS 2 goes on the ATGM, or on the BMP if the ATGM is dead)
3. waits for the village armour
4. drives onto the crossroads once the squad is out

The section, phase line, pre-planned strike, counter-attack and win logic are the normal mission code.

Checks: `spawn_tank`, `spawn_section`, `spawn_enemy`, `contact`, `cas_strike`, `treeline_killed`,
`section_follow`, `preplanned_strike`, `section_dismount`, `village_cleared`, `outcome_win` (forced:
`outcome_forced`).

```
uv run python tools/arma_harness/run_mission.py arma/missions/dms_breakthrough.Enoch --mods rhs --seeds 1,2 --parallel 2 --minutes 45 --time-scale 25 --start-dist 0
uv run python tools/arma_harness/run_mission.py arma/missions/dms_breakthrough.Enoch --mods rhs --seed 1 --param DMS_testForce=1
```

## Test results

See the bottom of this file. It is updated after each harness iteration.

## To verify with a human player

- The player lands in the commander's seat with the crewman kit, and the driver and gunner obey orders.
- Seat switching works with AI crew in the seats.
- The comm-menu cursor position (3D aim and map click) reaches the server as the aim point.
- The bombs look right coming off the A-10's pass.
- Balance: T-72B3 accuracy against a moving M1A2 on Veteran, the Metis on the flank, the 10-minute
  counter-attack delay and the 2-minute hold.
