# Ambush (Livonia)

**Status: implemented, not run.** It passes the static checks (`uv run pytest arma`) but has not been
loaded in Arma yet. The site coordinates and the road trace still need checking in-engine (see "To
verify" below).

## Premise

You lead a USMC rifle squad (RHS) on foot in Livonia. A Russian motor-rifle convoy is coming down a
forest road: a GAZ Tigr in the lead, a BTR-80, then one or two Ural trucks with a dismount squad in
each. Walk about 800 m to an ambush position above the road, wait, spring the ambush in the kill zone
and destroy the convoy before it gets past the kill line. Then break contact and walk about 1 km to the
rally point, where two HMMWVs are waiting.

Grounded and simple: no respawn, no scripted heroics, one convoy, one optional mortar section. The
enemy uses LAMBS Danger, so expect the dismounts to get out, take cover, suppress, flank and then come
looking for you.

## Flow

1. **Start.** The mission picks one of three sites by seed (or the `DMS_site` param). It snaps to the
   nearest real road segment, traces the road about 2.2 km each way and lays out the kill zone, the
   convoy's entry road and exit, a kill line 500 m past the kill zone, the ambush position (170-240 m
   from the road, on the side with the better view of the kill zone and then the higher ground), the
   squad start (800 m behind it) and the rally point (1 km away, on a track if there is one, at least
   700 m from the convoy's road).
2. **Approach.** The squad starts on hold fire (combat mode GREEN). The briefing gives the direction
   the convoy will come from and a 10-minute arrival window.
3. **The convoy** sets off 10-16 minutes after the start (seeded). An observation post calls it when it
   is about 2 km out. It drives in column at limited speed, staying on the road.
4. **Contact.** The ambush is sprung by the player's first shot, by any BLUFOR hit on the convoy, or by
   the convoy spotting the squad first ("compromised"). The squad is released to fire at will. The
   trucks stop and the dismounts get out. After 45 s each dismount group runs LAMBS `taskHunt` around
   the kill zone. The Tigr and BTR keep their column orders. They fight from the road and may try to push
   through.
5. **Win condition, part 1.** The convoy is combat ineffective when no vehicle can still move or fire,
   and at most 2 of its men are left within 900 m of the kill zone. A BTR that is immobilised but still
   has a working gun still counts.
6. **Win condition, part 2.** Break contact and get to the RP. The mission is won when the player
   reaches it (with no player, any squad member).
7. **Fail** if the player is killed, the squad is wiped out, or 2 convoy vehicles get past the kill
   line. A single escaped vehicle drives off and is removed. That is acceptable.

**Mortars** work as in The Hill: an 81 mm section through the comm menu (0-8). It has 2 fire missions
of 4 rounds and 2 spotting rounds. Expect about 85 s from request to splash. Requests within 150 m of
friendlies are refused as danger close. The section is too slow to hit a moving convoy, so use it on
dismounts and halted vehicles.

## How to play

Load these mods: **CBA_A3, ACE (the SP repack), LAMBS Danger, RHS AFRF and RHS USAF**. RHS GREF is
optional. If a required mod is missing, the mission logs `Missing required mods: ...`, shows a hint and
ends straight away with "Required mods missing".

Copy the folder `dms_ambush.Enoch` to `Documents\Arma 3\missions\` (or `mpmissions\`) and start it
from the editor or the scenario list. Recommended difficulty: Veteran, no crosshair. Livonia (the
Contact DLC terrain) must be installed.

Tips: put the Javelin and the M136 on the BTR first. Let the convoy get well into the kill zone before
you open fire. Once the vehicles are burning, don't stay to fight the dismounts. Break contact.

## Testing

Static: `uv run pytest arma -q` (this mission's tests are in `arma/tools/test_dms_ambush.py`).

Headless (main session; requires the mods):

```
uv run python tools/arma_harness/run_mission.py arma/missions/dms_ambush.Enoch --mods core,843425103,843577117,843593391 --seed 1 --minutes 30 --param DMS_testAssist=180
# each site
... --param DMS_site=1|2|3
# forced failures: 1 = convoy escapes (squad holds fire and is captive), 2 = squad wiped after contact
... --param DMS_testForce=1
```

In test mode an AI squad (the team leader plus six) plays the mission. It walks to the ambush position,
waits on hold fire and springs the ambush when the lead vehicle is 150 m from the kill zone. It calls
one mortar fire mission on the kill zone and keeps its AT men pointed at the nearest working vehicle.
Once the convoy is finished it moves to the RP. `DMS_testAssist` removes what is left of the convoy that
many seconds after contact, because AI-vs-AI fights in the trees can drag on. The convoy's departure
delay is scaled with `DMS_testTimeScale`, with a floor of 240 s so the squad has time to get into
position. Plan on 20-30 minutes of mission time per run.

Expected `[DMS.TEST]` checks: `spawn_route`, `spawn_squad`, `spawn_rp`, `squad_in_position`,
`convoy_spawned`, `contact`, `artillery`, `convoy_ineffective`, `rp_reached`, `outcome_win`. A forced
failure replaces `outcome_win` with `outcome_forced`. Outcome line:
`[DMS.OUTCOME] result=WIN|FAIL end=DMS_Win|DMS_FailDead|DMS_FailEscape|DMS_FailMods|DMS_FailSetup|DMS_TestEnd reason=... seed=... site=... t=...`.

Useful log lines: `Mods: ...`, `Route: snapped N m from the site point, road '<type>', convoy from the
<dir> ...`, `Route: side ±1 ... visible n/m height h m in-map ...`, `Convoy spawned: ...`,
`CONTACT (...)`, `Convoy vehicle ... escaped past the kill line`, `Convoy combat ineffective ...`,
`Rally point reached ...`. Set `DMS_debug=1` to get route waypoint and convoy markers on the map.

## To verify in-engine

- **Site coordinates (TO VERIFY).** These were picked offline from Livonia's own road shapefile and
  town list (see `CLASSES.md`, "Terrain data"):
  1. [9765, 2666] forest road between Gieraltow and Dolnik (shapefile type 2 "road")
  2. [3339, 4449] main road between Polana and Huta (type 1)
  3. [12062, 6532] main road south of Karlin (type 1, 740 m from the east map edge)

  For each one, check the `Route:` lines: snap distance, road type, in/out lengths of at least 2250 and
  1500 m, and that both ambush sides are scored with one chosen. Then look at the map with
  `DMS_debug=1`: are the waypoints on one road, is the ambush position in sensible cover above the
  road, is the RP reachable on foot?
- **Classes** were verified offline from the PBO configs, not with `isClass` in-engine. The diag sweep
  (`tools/arma_harness/make_diag.py`) could be pointed at this mission's `fn_config.sqf`.
- **Behaviour to watch**
  - Does the convoy hold the column on the road (`forceFollowRoad`)?
  - Do the Urals stop and dismount (`doStop` + `forceSpeed 0`, `leaveVehicle`, then `moveOut` after 4 s)?
  - Do the dismounts actually hunt (LAMBS `taskHunt` with `onlyPlayers = false`)?
  - Does a collision inside the column ever fire a false "convoy hit" contact (hits from an EAST source
    are ignored)?
  - Does the player's squad hold fire on GREEN until contact?
- **Player loadout.** The vanilla slot gets the RHS team leader's loadout through `setUnitLoadout`.
  Check it in a hosted or SP start, which the harness does not cover.
