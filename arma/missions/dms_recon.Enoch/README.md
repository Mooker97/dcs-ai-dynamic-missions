# DMS "Recon and Strike" (Livonia)

**Status: implemented, not run.** Static checks pass (`uv run pytest arma`). The mission has not
been loaded in Arma yet: not headless, not played. See "To verify" below and in `CLASSES.md`.

## Premise

A 4-man USMC Force Recon team inserts on foot into the Livonian forest. Somewhere inside a 1 km search
box, a Russian motor-rifle 82 mm mortar battery (three 2B14 tubes) is dug in under the trees. A small
guard and two patrols protect it. The team has to find it without being seen, report it so a 155 mm
battery can fire on it, confirm the kill, and walk out.

Grounded, with few moving parts. There are no exact objective markers, and a strike goes exactly
where you report it. A bad report misses.

## Flow

1. **Insert.** The team starts about 1.8 km from the battery. The search box is marked; the battery
   is somewhere inside it. One of 3 seeded forest sites is used, and the exact spot is snapped at
   runtime to the densest tree cover near the site anchor.
2. **Find.** The battery fires a couple of rounds every 5–10 minutes at a far-off target, so you can
   hear it. The guard holds a LAMBS camp around the tubes, and two LAMBS patrols walk 250 m and 450 m
   rings around it.
3. **Stay unseen.** If any enemy group's `knowsAbout` on a team member reaches 1.5, or a defender is
   killed, the alarm goes up. 4–7 minutes later a 6-man QRF on foot spawns about 1.3 km out, on the
   battery's far side, and hunts the team (LAMBS `taskHunt`). A strike landing near the battery raises
   the same alarm, which puts pressure on the exfil.
4. **Report** (comm menu 0-8):
   - *Fire mission: target at my laser spot.* The leader carries a laser designator. The rounds aim at
     the laser spot, which may be a tree in front of the target.
   - *Fire mission: target at cursor / map position.* Point at the target, or click it on the map.
   Reports within 200 m of the team are refused (danger close). Each fire mission is 6 rounds of
   155 mm HE with about 30 m CEP around the reported point, landing 2–3 minutes after the report.
   You have 3 fire missions.
5. **BDA.** The battery is out once 2 of its 3 tubes are out: destroyed, damaged past 75 %, or with
   the whole crew dead. You are never told this directly. To confirm, observe it (within 60 m, or
   within 400 m with line of sight to a tube), or hit it again with a later strike. If you observe it
   while it still works, you get "battery still active, N of 3 tubes out. Re-attack."
6. **Exfil.** After BDA the pickup point is marked, 1.6 km away on a seeded side. Walk there. Win when
   you are within 40 m of it, the rest of the team is within 150 m, and no known enemy is within 250 m,
   held for 10 s.

**Fail:** you are killed or the team is wiped out; the battery is still active after 90 minutes; or
all 3 fire missions are spent and the battery is still active.

## How to play

1. Load these mods: **CBA_A3** (450814997), **ACE** (1744095754, the singleplayer repack), **LAMBS_Danger**
   (1858075458), **RHSAFRF** (843425103) and **RHSUSAF** (843577117). Livonia (Contact DLC terrain) must
   be installed. The mission logs `Mods: ...` at start. If a required mod is missing, it ends at once
   with "Required mods missing: ..." instead of half-working.
2. Copy `arma/missions/dms_recon.Enoch` to `Documents\Arma 3\missions\` (or `MPMissions\` to host it).
   The player slot is a vanilla `B_Soldier_TL_F`, so the mission loads without mods. You get the RHS
   recon team leader's loadout plus a laser designator at start.
3. Play from Eden (Livonia > Open > `dms_recon`) or host it as a 1-slot coop mission. Veteran
   difficulty with no crosshair or map tags fits the intent.
4. Parameters: seed (0 = random, logged), site (or from seed), debug (shows the battery and the QRF
   spawn points on the map).

## Test mode (headless)

```
uv run python tools/arma_harness/run_mission.py arma/missions/dms_recon.Enoch --mods core,843425103,843577117
uv run python tools/arma_harness/run_mission.py arma/missions/dms_recon.Enoch --mods core,843425103,843577117 --seeds 1,2,3 --param DMS_site=2
uv run python tools/arma_harness/run_mission.py arma/missions/dms_recon.Enoch --mods core,843425103,843577117 --param DMS_testForce=1
```

With no player, an AI team plays the mission:

1. It moves to observation posts at 400, 250 and 120 m from the battery on the approach bearing, and
   waits at each for up to `testOpHold` s.
2. **found** passes as soon as a team member within 400 m has line of sight to a tube
   (`checkVisibility` ≥ 0.25), or the team knows about a defender near the battery (`knowsAbout` ≥ 1.5).
   With `DMS_testAssist` > 0 (harness default 180), a team that has not found the battery by the last
   OP gets it revealed, and the check passes as "assisted". With assist off, the check FAILs.
3. The team pulls back to 260 m (outside danger close) and calls the same `REPORT` the comm menu
   calls, at the battery centre plus a seeded 0–15 m error. It repeats while the battery is still
   working and missions remain.
4. The team closes to 180 m to observe for BDA. If that fails, it re-attacks to confirm.
5. It walks to the pickup.

Checks: `mods`, `spawn_site`, `spawn_enemy`, `spawn_team`, `found`, `report`, `strike`, `alarm`,
`site_neutralized`, `bda`, `exfil`, `outcome_win` (plus `qrf` when it spawns). `DMS_testForce=1`
kills the team right after the first report and expects `outcome_forced` (`DMS_FailDead`).
Logs: `[DMS] ...`, `[DMS.TEST] PASS|FAIL <check> <detail>`, `SUMMARY`, `DONE`, and one
`[DMS.OUTCOME] result=... end=... reason=... seed=... site=... t=...`.

## Files

| File | What |
|---|---|
| `functions/fn_config.sqf` | Every tunable (sites, team, battery, patrols, QRF, fire support, BDA, exfil, test) |
| `functions/fn_site.sqf` | Battery tubes and crews, props, LAMBS camp guard and patrols, tube status, the battery's own fire |
| `functions/fn_alarm.sqf` | Detection, alarm, infantry QRF with LAMBS hunt |
| `functions/fn_strike.sqf` | Comm-menu reports and the virtual 155 mm battery |
| `functions/fn_bda.sqf` | Neutralized state, BDA, exfil, time limit |
| `functions/fn_findPos.sqf` | Seeded placement: map clamp, flat ground, forest hide, nearest road |
| `functions/fn_rng.sqf`, `fn_t.sqf`, `fn_log.sqf` | Copied unchanged from The Hill (seeded RNG, test time scale, logging) |
| `functions/fn_end.sqf`, `fn_testMode.sqf` | Single end with the outcome line; the test driver |
| `CLASSES.md` | Every class, LAMBS function and engine command, and where it was verified |

## To verify (in-engine)

- The three site anchors are TO VERIFY. Read the `Start:` line for each site: the battery grid,
  `forestScore` (should be dozens of trees), and the nearest place.
- `Battery fired:` lines should show tubes firing (`doArtilleryFire` with the RHS 2B14 AI at 3 km).
- After a centred strike, look for `Tube N out:` lines. Can 6 rounds of 155 mm at 30 m CEP neutralize
  2 of 3 tubes? Tune `strikeCEP` / `strikeRounds` / `tubeDamageOut` if not.
- Player: the designator is in the binocular slot with batteries, and `laserTarget` reports work with
  ACE loaded. The cursor and map-click reports land where clicked.
- LAMBS: the guard camps, the patrols walk, and the QRF hunt finds the team (`onlyPlayers` false).
