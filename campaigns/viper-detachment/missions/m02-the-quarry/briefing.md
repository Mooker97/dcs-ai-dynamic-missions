# THE QUARRY

**Classification:** fictional training material · **Date/Time:** 05 NOV, 1030L · **Callsign:** PYTHON 1-1 (Pike 1-2, AI wingman) · **Two start options, see para 4**

## Intelligence narrative (S2)

The Northern Border Brigade has now confirmed what we only suspected: the Northern Plains Front
moved the Garrison stocks into a disused limestone quarry 4 NM north-east of Al Bab. NBB observers
report trucks in and out of the pit every night this week and a guard force living on site. A
walled command compound sits on the west lip. A farm hamlet, about a dozen occupied houses, stands
some 300 m east of the quarry wall.

Assessed: five storage bunkers or cuts in the pit, of which two are in use. Active sites will show
vehicles at the entrance (cargo trucks, a fuel bowser) and guards nearby. Empty sites show
nothing. We cannot tell you which two. Expect the NPF to try to move stock out once it hears jets.

Unknown: whether the short-range SAMs that survived the last week have moved to cover the Quarry.
ELINT is watching east of Al Bab.

## 1. Situation

- **Enemy (known).** ZU-23 emplacements and a ZU-23 technical on the Quarry rim (light AAA,
  effective below ~5,000 ft AGL). Command building and its vehicles on the west lip.
- **Enemy (reported, not located).** DShK technicals on the tracks around the Quarry; a guard
  section in the pit; Igla MANPADS teams on likely attack headings; possibly one short-range SAM
  3-4 NM beyond the target. *Most likely:* guns fire barrage, a truck runs for Al Bab. *Most
  dangerous:* a MANPADS team under a repeated attack heading while a SAM emits late from the east.
- **Friendly.** Magic (E-3) controls the area. Jackal Two-Three (TSgt Ortiz, USAF JTAC) is with the
  NBB north of Tell Rifaat and relays NBB ground reporting; he is not controlling this strike.
  Shell (KC-135) on the AR track over southern Turkey.
- **Civilians.** Families in the hamlet east of the Quarry; farm traffic on the Quarry road to Al Bab.
  Their pickups look like technicals.

## 2. Mission

At 1030L PYTHON 1 strikes the NPF weapons depot and command compound at the Quarry, north-east of
Al Bab, with laser-guided bombs to destroy the insurgents' stocks without harming the hamlet.

## 3. Execution

- **Commander's intent.** Bomb the right concrete. Purpose: take the Garrison stocks away from the
  NPF before its next push on the Brigade. Key tasks: find the active sites on the pod, destroy
  them, destroy the command building, no civilian harm. End state: two sites with secondaries, the
  command building down, PYTHON home with both jets.
- **Concept.** (1) Ramp start: depart Incirlik, transit ESE. Air start: begin 20 NM short of IP SHALE, then step 2.
  (2) Check in with Magic inside 10 NM of IP SHALE (12 NM NW of the target). (3) Rook Ops clears
  you to engage inside 10 NM of the Quarry. (4) TGP search, self-lase LGB runs. (5) Egress north
  to GATE (11 NM N of the target), call Rook Ops, RTB Incirlik.
- **Steerpoints (loaded in both files, flown at 20,000 ft).** STPT 1 start (Incirlik ramp, or the
  air-start point) · STPT 2 **IP** SHALE · STPT 3 **TGT1** the Quarry pit (storage sites) ·
  STPT 4 **TGT2** command compound, west lip · STPT 5 **EGRESS** GATE · STPT 6 **HOME** Incirlik.
  IP to TGT1 about 12 NM run-in from the north-west; TGT to GATE about 11 NM north.
- **Tasks.** PYTHON 1-1: GBU-12 on the active sites, then the command building. PYTHON 1-2:
  wingman, buddy-lase backup, BDA calls.
- **Coordinating instructions.**
  - ROE: PID every aimpoint on the TGP. **No weapons east of the Quarry's east wall** (hamlet is
    no-strike). Vehicles on the road: PID required; Rook Ops clearance before any release near it.
  - Run-ins from the west or north-west keep the hamlet beyond the target, not under the fall line.
    Do not repeat an attack heading.
  - Altitude: medium, release 15,000-20,000 ft MSL; stay above the AAA.
  - Laser codes: 1688 lead, 1687 wing.
  - Abort: SAM launch, MANPADS launch on the run-in, civilian vehicles inside 300 m of the aimpoint,
    or check fire from Rook Ops. Joker 5,000 lb, bingo 3,500 lb (from the IP).

## 4. Administration & logistics

- **Two start options, same sortie, same callsign (PYTHON 1-1, Pike 1-2 as AI wingman).** Pick the file:
  - copy **m02-the-quarry-ramp.miz** for a cold start on the Incirlik ramp. Full transit (about
    100 NM), Shell available.
  - copy **m02-the-quarry-air.miz** for an air start: 20,000 ft, 420 kts, 20 NM before IP SHALE
    on the line from Incirlik, heading for the IP, master arm safe, full internal fuel.
- **Loadout (both, generator preset `lgb_strike`).** 4x GBU-12 (2x TER-9/A on stations 3/7),
  2x AIM-120C, 2x AIM-9X, 2x 370 gal tanks, ALQ-184, AN/AAQ-28 LITENING.
- **Divert:** Gaziantep, Adana Sakirpasa, Hatay. **CSAR:** none dedicated; NBB lines west of Al Bab.

## 5. Command & signal

| Agency | Callsign | Frequency |
|---|---|---|
| Squadron / ops | Rook Ops (PYTHON 1 flight freq) | 305.0 AM |
| AWACS (E-3A) | Magic 1-1 | 251.0 AM |
| JTAC (with NBB, CJTF Blue) | Jackal Two-Three | 41.5 FM |
| Tanker (KC-135, boom) | Shell 1-1 | 276.1 AM, TACAN 51Y |
| Incirlik Ground/Tower | Incirlik | 360.0 AM / 122.0 AM |

- Frequencies, callsigns and TACAN are set on the aircraft in the mission (out/plan.json: flight 305.0, Magic 251.0, Shell 276.1 / 51Y, Jackal 41.5 FM). Incirlik from the airfield data. The cockpit callsign is PYTHON 1-1 in both files.
- Bullseye: Minakh. Codeword for stocks destroyed: none; call BDA in plain text on egress.
- Lost comms: complete the attack only with PID, egress via GATE, recover Incirlik.
