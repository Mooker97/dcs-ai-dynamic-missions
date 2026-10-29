# Continuity ledger — Viper Detachment

<!-- APPEND-ONLY. Every agent that changes canon or records an outcome adds a dated entry at the bottom.
     Never rewrite earlier entries; correct them with a new entry that references the old one.
     Mission designers read this whole file before writing a mission. -->

## Canon at start

- Rook detachment: six F-16CM Block 50 at Incirlik, four serviceable on a normal day. The player is PYTHON 1-1; 1st Lt. Pike is PYTHON 1-2. Maj. Lindqvist is Rook Ops.
- The Northern Border Brigade holds Minakh airstrip and the villages north of Tell Rifaat. TSgt Ortiz (Jackal Two-Three) is embedded with an NBB company there.
- The NPF holds Al Bab's outskirts, the farmland south of Tell Rifaat, and Kuweires air base (the Garrison).
- NPF radar SAMs at start: one SA-6 battery (radar + 2-3 launchers), two or three SA-8s, SA-9/SA-13 vehicles. One coalition MQ-9 was lost near Al Bab in October; ISR has pulled back.
- The Quarry (weapons depot + command compound north-east of Al Bab) is suspected, not confirmed.
- The NPF has no flying aircraft.
- Each mission offers a ramp start at Incirlik or an air start near the IP; nothing in the story depends on which.

## Open threads

- [ ] The SA-6 battery that shot down the MQ-9: where is it, and does it survive? (planted: bible; pays off: m01, finally m04)
- [ ] Which Quarry bunkers actually hold the stocks? (planted: bible; pays off: m02)
- [ ] Pike's first deployment: tense on the radio at first, steadier with each sortie. (planted: bible; pays off: m04 PID call)
- [ ] The Engineer: the man keeping the captured radars running. Does his last launcher get across the river? (planted: bible; pays off: m04)

## Log

### 2026-10-28 — story-writer — campaign created
- Seeded from premise.md (user brief: F-16C_50 on Syria, grounded, light story; updated brief: counter-insurgency, SEAD/DEAD and LGB focus, ramp-or-air start choice, subtitles only).
- Mode fictional: real terrain, invented insurgency (NPF), partner force (NBB) and calendar. Enemy on Insurgents + CJTF Red flags, partner on CJTF Blue.

### 2026-10-28 — campaign-planner — arc planned
- Act 1 "Take Away the Umbrella": m01-broken-umbrella (SEAD), m02-the-quarry (STRIKE). Act 2 "Hold the Plain": m03-troops-in-contact (CAS), m04-last-launcher (DEAD: SEAD escort + LGB interdiction of a convoy carrying the last SAM).
- Qualities: sam_threat 2, intel 1, insurgent_supply 2, partner_morale 0, collateral 0.
- Outcome keys:
  - m01: window_held, sa6_radar_destroyed, sa6_launchers_destroyed, sa8_destroyed, mq9_lost, player_lost, wingman_lost
  - m02: full_bunkers_destroyed, command_building_destroyed, secondaries, civilians_hit, player_lost
  - m03: position_held, fortified_positions_destroyed, technicals_destroyed, fratricide, civilians_hit, player_lost
  - m04: sam_carrier_destroyed, overwatch_sam_destroyed, escort_destroyed, convoy_escaped, civilians_hit, player_lost
- Thread payoffs: SA-6 → m01/m04; Quarry bunkers → m02; Pike → m04; the Engineer → m04.
- Branches: only replay-on-player_lost; otherwise linear. Outcomes act through qualities.
- Every mission: two PYTHON 1 player flights (ramp start at Incirlik, air start near the IP). No beat depends on takeoff.

### 2026-10-28 — mission-designer — m01–m04 designed
- m01-broken-umbrella (03 NOV 2016, 0700L): SEAD window over Al Bab; SA-6 battery at one of 3 sites (goes hot inside ~8 NM), pop-up SHORAD (80% at sam_threat 2), MQ-9 "Cyclops Two" is narrative only.
- m02-the-quarry (05 NOV 2016, 1030L): LGB strike on a quarry depot ~4 NM NE of Al Bab; 2 of 5 storage sites hold stocks (seeded); farm hamlet 300 m east is no-strike.
- m03-troops-in-contact (08 NOV 2016, 1500L): CAS for NBB company LANTERN with Jackal Two-Three, 6 km N of Tell Rifaat; Mill and Orchard positions; NBB hold limit set by partner_morale.
- m04-last-launcher (14 NOV 2016, 0630L): the last SA-6 element convoy on one of 3 roads to the Euphrates (north/Manbij, centre/Tishrin, south/Maskanah), with a civilian decoy convoy; success = 1S91 radar destroyed.
- All four: ramp flight at Incirlik + air-start flight before the IP, both PYTHON on the radio. Subtitles only.

### 2026-10-29 — plugin-smoke — campaign created
- Copied from viper-detachment for plugin smoke tests (PLAN A6). Canon is viper-detachment's; nothing here feeds back.
