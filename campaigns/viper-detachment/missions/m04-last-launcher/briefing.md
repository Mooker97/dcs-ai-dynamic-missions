# THE LAST LAUNCHER

**Classification:** fictional training material · **Date/Time:** 14 NOV, 0630L · **Callsign:** PYTHON 1-1 (2-ship, F-16C Block 50; #2 Pike = AI wingman) · Incirlik

## Intelligence narrative (Rook S2)

Two weeks into the tasking, the Garrison's air defences are thinner but not gone. What remains of
the SA-6 battery, the radar vehicle the Engineer kept running and its launchers, left Kuweires
before dawn under a technical escort. NPF radio traffic overnight talked about "the river". We
assess they are moving it east to the Euphrates crossings, out of our reach on the far bank.
The Garrison also lost track of two or three SA-8s; we assess one is already on the high ground
above the convoy's road as overwatch, radar dark until you come close.

There are three roads east: north through Manbij to the northern bridge, the centre road to the
Tishrin dam, and south past Deir Hafer to Maskanah on the lake. We do not know which one they
took. The Brigade has no observers forward this morning. Civilian lorries use all three roads at
first light, and from 15,000 ft a lorry looks like a launcher.

## 1. Situation

- **Enemy.** *Known:* ZU-23 guns on the Kuweires perimeter (marked). *Convoy:* SA-6 element (one
  1S91 Straight Flush radar, three 2P25 launchers, self-propelled) with DShK technicals,
  eastbound at about 35 km/h. Radar stowed while moving; it can still stop and emit. *Overwatch:*
  an SA-8 Gecko (one or a pair; radar, HARM target) on the high ground above the convoy's road,
  emitter silent and unlocated until you are close. Rook Ops calls it as soon as it is seen. *Possible:* Igla teams at the crossings. *Most likely:* the convoy keeps moving and
  hides in traffic. *Most dangerous:* the overwatch or the SA-6 radar comes up while you are low and
  slow on a lasing run.
- **Friendly.** Magic (E-3, 251.000) has the air picture. Rook Ops (Maj. Lindqvist) on the squadron
  discrete. Shell (KC-135, 276.100, TACAN 51Y) on the AR track over southern Turkey, west of Gaziantep. Jackal Two-Three with the Brigade
  north of Tell Rifaat; Brigade observers report only if they are out.
- **Civilians.** Traffic on all three roads; Manbij, Maskanah and the dam villages are built up.

## 2. Mission

PYTHON finds and destroys the SA-6 radar vehicle moving east from Kuweires before it reaches the
Euphrates crossings, suppressing its overwatch, to remove the NPF's last radar SAM.

## 3. Execution

- **Commander's intent.** The radar is the target: without it the launchers are scrap. Key tasks:
  check in at HAMMER, take the retask, find the convoy, suppress the overwatch, put a GBU-12 on the
  1S91. End state: radar destroyed, no civilian casualties, both jets home.
- **Stakes:** if we fail, the Engineer's last radar SAM crosses the Euphrates intact and the
  umbrella over the plain comes back wherever he sets it up next.
- **Duration:** air start ~65 min / ramp start ~90 min (the 40-minute search window is inside both).
- **Start options (choose one file).** Copy `m04-last-launcher-ramp.miz` for a cold start on the
  Incirlik ramp, or `m04-last-launcher-air.miz` for an air start at 20,000 ft, 420 kt, 20 NM
  short of HAMMER (the IP), heading east-south-east. Either way you fly PYTHON 1-1 with Pike as
  PYTHON 1-2 (AI wingman); the story starts at HAMMER.
- **Concept.** (1) Ramp: start, taxi, depart Incirlik, tank on Shell if needed. (2) Push HAMMER,
  check in with Magic. (3) Rook Ops retasks; the 40-minute window starts. Candidate roads are marked
  on F10. (4) Search with the pod, north to south unless cued. (5) HARM the SA-8 when it
  emits, then lase the radar vehicle (moving target). (6) On Rook Ops' call, egress via ANVIL, RTB.
- **Steerpoints (both files; 20,000 ft, after the departure point):**

  | STPT | Name | Position | Note |
  |---|---|---|---|
  | 1 | IP | HAMMER, N36 37.2 E037 25.2 | push point, Magic check-in |
  | 2 | TGT | search box centre, N36 16.2 E037 55.2 | the convoy is on one of the three roads, not here |
  | 3 | EGRESS | ANVIL, N36 46.8 E037 18.0 | border north of Al Bab |
  | 4 | HOME | Incirlik | landing |
- **Coordinating instructions.**
  - ROE: PID before release. Westbound traffic is not the convoy. Nothing inside towns.
  - Near buildings or civilian traffic, state the target to Rook Ops before release.
  - Minimum 10,000 ft AGL over the Garrison; stay high near the crossings (MANPADS).
  - Window: 40 min from the retask. At the 5-minute call, finish your attack; at "endex" weapons hold.
  - Abort: radar SAM lock with no HARM left, or damage affecting handling.

## 4. Administration & logistics

- **Loadout (both jets, both start options; F-16C_50 preset `sead`):** 2x AGM-88C HARM (3/7),
  2x GBU-12 (4/6), 2x AIM-120C (2/8), 2x AIM-9X (1/9), ALQ-184 ECM pod (5), AN/ASQ-213 HTS (10),
  AN/AAQ-28 LITENING (11). No external tanks; full internal fuel. Laser code 1688.
- **Fuel:** Joker 4,000 lb, Bingo 3,000 lb in the box for Incirlik. Shell on request.
- **Diverts:** Gaziantep, Adana Sakirpasa, Hatay. **CSAR:** none on alert; Magic coordinates.

## 5. Command & signal

| Agency | Callsign | Freq |
|---|---|---|
| Flight / squadron discrete | Python 1-1 / Rook Ops | 305.000 AM |
| AWACS | Magic (Magic 1-1) | 251.000 AM |
| JTAC | Jackal Two-Three | 138.500 AM |
| Tanker | Shell (Shell 1-1), TACAN 51Y | 276.100 AM |
| Incirlik Ground / Tower | Incirlik | 360.100 AM |

- Codewords: HAMMER = push point; "endex" = window closed, weapons hold on the convoy.
- Codeword ANVIL = egress point.
- Lost comms: complete the search if the window is open, then RTB via ANVIL.
