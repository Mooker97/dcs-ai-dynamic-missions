# Dustoff Corridor - Mission Setup

Player AH-64D escorts the `Convoy-Main` ground convoy Alpha -> Bravo -> Charlie -> FOB-Victory
(Syria). Enemies are created by `dustoff-master-init.lua` from code-built templates; nothing
enemy needs placing in the ME. Reference build: `Saved Games\DCS\Missions\Syria AH64\Dustoff Corridor.miz`.

## 1. Triggers

| # | Type | Condition | Action |
|---|------|-----------|--------|
| 1 | ONCE | TIME MORE (5) | DO SCRIPT FILE -> `dustoff-master-init.lua` |
| 2 | ONCE | TIME MORE (10) | SOUND TO ALL -> `mission start.wav` (optional) |

- Load the script only once; do not also add MIST/MOOSE or the separate DMS module files.
- DCS embeds a **copy** of the script in the .miz. After editing the .lua, open trigger 1 and
  re-select the file (the current .miz still embeds `dustoff-master-init-v8.lua`), then save.
- Timing after load: spawns at +2 s, zone/win-loss monitoring at +10 s.

## 2. Required group names (case-sensitive)

| Name | Coalition | Notes |
|------|-----------|-------|
| `Convoy-Main` | BLUE ground | Route runs through all four zones and ends inside FOB-Victory. Any vehicle count (reference: 8). |
| `Player Group` | BLUE helicopter | Player AH-64D. Crash/eject/pilot dead = mission failed. |
| `A-10 CAS` | BLUE plane | **Late Activation** ticked. Give it a CAS/CAP route over the corridor. |

## 3. Required trigger zones

| Zone | Shape | Use |
|------|-------|-----|
| `Alpha-Zone` | quad or circle | Alpha spawns (SAM + infantry), enter/exit flags 110/111 |
| `Bravo-Zone` | quad or circle | Bravo armor (hunts convoy) + infantry, flags 112/113 |
| `Charlie-Zone` | quad or circle | Charlie defense, flags 114/115; entering launches the QRF |
| `FOB-Victory` | circle | Any convoy vehicle inside = victory (flags 116 + 101) |
| `QRF-Staging` | circle | QRF spawn point (reference: east of Charlie) |

Quad zones are tested with point-in-polygon from the zone's vertices; circles use the radius.
Spawns are placed by distance from the zone centre (pool min/max distance), not inside the quad.

## 4. Mission options (important)

- **F10 View Options: `Fog of War`** (or `Allies Only`). Enemy groups spawn with
  *hidden on map*; they appear only as BLUE F10 marks (text + red circle) once detected. With
  `All` the marks still work but the setting contradicts the design.
- Optional: hide enemy units from the external/labels view via `Labels: Off` or `Dot only`.

## 5. Flags set by the script

| Flag | Event |
|------|-------|
| 100 | Mission start |
| 101 / 102 | Victory / defeat |
| 110 / 111 | Convoy enters / exits Alpha |
| 112 / 113 | Convoy enters / exits Bravo |
| 114 / 115 | Convoy enters / exits Charlie |
| 116 | Convoy reaches FOB-Victory |
| 117 | Convoy first hit (once) |
| 118 | Convoy vehicle destroyed (each loss) |
| 119 | A-10 CAS checked in (fires on activation) |

Each flag also shows a placeholder text line to BLUE. Hook voice lines with
`FLAG IS TRUE (n)` -> `SOUND TO COALITION` triggers (see `VOICE-LINES.md`).

## 6. What the script does

- **Spawns** (on load): `sam-site` 10%, `alpha-ground` 80% x4, `bravo-armor` 80% x6,
  `bravo-infantry` 60% x2, `charlie-defense` 80% x5. Pool `count` is always honoured
  (templates cycle). All enemies are RED (country Russia).
- **Ambush posture**: Alpha/Bravo infantry and Charlie defense hold position, ROE open fire, alarm red.
- **Hunting**: `bravo-armor` groups route off-road to an intercept point ahead of the convoy
  lead when it is within 4 km; route re-issued every 30 s while alive.
- **QRF**: when the convoy enters Charlie **or** loses 2 vehicles, the QRF pools roll
  (light 50%, medium 25%, heavy 10%), spawn at `QRF-Staging` and hunt the convoy.
- **Convoy halt**: any hit on a convoy vehicle stops its route (alarm red, open fire). It
  resumes after 50 s without hits. Zone progression is unaffected.
- **SAM ambush**: SAM sites stay dark until a BLUE player is within 8 km, then 80% chance to
  go hot (re-rolls every 30 s); back to dark 30 s after the player leaves.
- **Fog of war**: an enemy group is "detected" when a BLUE unit is within 5 km with line of
  sight, or when it shoots/is hit. Marks refresh every 15 s and are removed when the group dies.
- **A-10**: testing mode activates `A-10 CAS` 60-120 s after start (100%). For release set
  `A10Config.testing = false` (25% chance, 5-10 min).

## 7. Tuning (top of the mission section in the .lua)

| Setting | Where |
|---------|-------|
| Debug log (`[FOW]`, `[Hunt]`, `[SAMAmbush]`, `[DUSTOFF-*]`) | `DMS.Settings.configure({ debug = ... })` |
| Detection range / mark refresh | `fogOfWarRevealRange`, `DMS.FogOfWar.Config.markRefresh` |
| Hunt radius / speed | `huntRadius`, `huntSpeed` on each pool |
| QRF loss threshold | `DMS.DustoffCorridor.QRFConfig.lossThreshold` |
| Convoy resume delay | `DMS.DustoffCorridor.ConvoyHalt.resumeAfter` |

Logs: `Saved Games\DCS\Logs\dcs.log` (search `[DMS ERROR]` for caught script errors).

## 8. Test checklist

1. Start mission; `dcs.log` shows `Dustoff Corridor master init script loaded`, no `[DMS ERROR]`.
2. F10 map shows no enemy icons until marks appear near the convoy/player.
3. Convoy stops when hit and moves again ~50 s later.
4. Bravo armor drives toward the convoy (`[Hunt] ... routed to intercept`).
5. A-10 appears at 1-2 min and flag 119 text shows.
6. Victory message when the convoy reaches FOB-Victory.
