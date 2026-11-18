# BROKEN UMBRELLA

**Fictional scenario** · **03 NOV, 0700L (D+0)** · **PYTHON 1-1, F-16C Block 50, 2-ship** · **Incirlik**

## Intelligence narrative — Rook detachment intelligence

Last month a coalition MQ-9 was shot down by a radar SAM near Al Bab, and ISR pulled back from the
plain. Since then we have been blind over the town. The Northern Plains Front took an SA-6 battery
and several SA-8s from the Kuweires garrison, and the man intelligence calls the Engineer has kept
them working. This is Rook's first tasked sortie.

The SA-6 is assessed at one of three sites south-east of Al Bab, toward Kuweires. It emits late and
briefly, and it moves after it shoots. Expect the radar to come up only when you are close. An
SA-8 (a single vehicle or a pair) has been reported near the town but has not been located. ZU-23s on the north-west edge of Al Bab are confirmed. MANPADS teams are assessed
present on the approaches. The NPF has no aircraft.

What we do not know: which SA-6 site is live, and whether the SA-8 is still in town. An
MQ-9, Cyclops Two, will re-establish its orbit over Al Bab if the window holds. Its pictures are how
we find the Quarry.

## 1. Situation

- **Enemy.** SA-6 battery (Straight Flush radar plus launchers) at candidate site A (5 NM SE of Al
  Bab), B (8 NM S, toward Kuweires) or C (dispersal NW of Kuweires). ZU-23 at the NW edge of Al Bab
  (on the F10 map). Possible pop-up SA-8 and MANPADS around the town. Technicals in the farmland.
  *Most likely:* the SA-6 stays dark until you are inside about 8 NM, then fires once and shuts
  down. *Most dangerous:* the SA-6 fires on Cyclops while a pop-up SA-8 covers your attack heading.
- **Friendly.** Magic (E-3) north of Gaziantep. Shell (KC-135) on the AR track west of Gaziantep.
  Cyclops Two (MQ-9) inbound on your push. Rook Ops on squadron discrete.
- **Civilians.** Pickups, cars and buses on the road west out of Al Bab. They look like technicals.

## 2. Mission

PYTHON suppresses and destroys the NPF's captured radar SAMs around Al Bab on 03 NOV to hold a
10-minute ISR window for Cyclops Two.

## 3. Execution

**Intent.** Keep the SA-6 from engaging Cyclops during the window. Killing the radar is the best
way to do that. Killing launchers is a bonus. End state: Cyclops completes its orbit and both jets
come home.

**Concept.**
1. *Start (choose one file).* Copy **m01-broken-umbrella-ramp.miz** for a cold start on the ramp at
   Incirlik (runway 05, about 83 NM to ARROW), or **m01-broken-umbrella-air.miz** for an air start: airborne
   at 20,000 ft and 420 kts, 20 NM short of IP ARROW on the Incirlik-ARROW axis (heading about
   103), with ARROW as the next steerpoint. Either way you are **Python 1-1** in the cockpit and on
   the radio, and Pike flies **Python 1-2** as an AI wingman. Both files load the same route:
   STPT 1 **IP** (ARROW, Kilis), STPT 2 **TGT1** (Al Bab, Cyclops orbit), STPT 3 **TGT2** (SA-6
   search box between Al Bab and Kuweires, covering sites A-C), STPT 4 **EGRESS** (Turkish border
   20 NM north of Al Bab), STPT 5 **HOME** (Incirlik). All at 20,000 ft.
2. *Push.* Check in with Magic at IP ARROW (Kilis). Rook Ops opens the window about 20 s later.
3. *Window (push to +10 min).* Fence in at 16 NM from Al Bab. HTS for the SA-6, HARM on emission.
4. *Hunt (+10 to +15 min).* Cleared DEAD on anything that emitted. GBU-12 self-lase on a located
   radar or launcher.
5. *Recovery.* Rook Ops calls vul end at +15. Egress north to EGRESS (STPT 4), then HOME (STPT 5),
   Incirlik.

**Coordinating instructions.**
- ROE: weapons free on SAM, AAA and positively identified armed vehicles. No attacks inside Al Bab
  town without Rook Ops clearance.
- Altitude: 15,000 ft MSL minimum over the town (MANPADS, ZU-23).
- Abort: SA-6 launch with no HARM available, or damage. Turn north to EGRESS (STPT 4).
- Bingo: set your own for Incirlik. Tank on Shell if needed.
- Duration: air start ~40 min (ARROW in ~3 min, 15 min on station, ~20 min home); ramp start
  ~65 min (start-up and taxi ~15 min, 83 NM transit ~12 min).
- Stakes: if the window fails, Cyclops never maps the Quarry, so tomorrow's strike goes in
  without marked bunkers. Every radar we leave alive sizes the SAM threat for the rest of the
  detachment.

## 4. Administration and logistics

Both jets, both start options (generator preset `sead`): 2x AGM-88C HARM (3/7), 2x GBU-12 (4/6),
ALQ-184 (5), AN/ASQ-213 HTS, AN/AAQ-28 LITENING, 2x AIM-120C (2/8), 2x AIM-9X (1/9), full internal
fuel, gun 100 %. Set the GBU-12 laser code to 1688 in the jet. Diverts: Gaziantep, Adana Sakirpasa,
Hatay. No CSAR asset is on station.

## 5. Command and signal

| Agency | Callsign | Frequency |
|---|---|---|
| Flight / squadron discrete | Python 1-1 / Rook Ops | 305.0 AM |
| AWACS | Magic 1-1 | 251.0 AM |
| Tanker | Shell 1-1 (KC-135, boom) | 276.1 AM, TACAN 51Y |
| Ground / Tower | Incirlik | 360.1 AM |

Bullseye: Minakh. Lost comms: continue the window, egress via EGRESS (STPT 4) at vul end, RTB.

## Red task

Keep the SA-6 alive. Shoot only at what you can hit, then move.
