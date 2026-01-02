# Dustoff Corridor - Mission Editor Setup Guide

Complete guide for building the "Dustoff Corridor" dynamic convoy escort mission in DCS Mission Editor.

---

## Overview

**Mission Type**: Convoy Escort / CAS
**Player Aircraft**: AH-64D Apache
**Map**: Any (designed for Syria/Caucasus)
**Duration**: 20-40 minutes
**Replayability**: High (randomized threats each playthrough)

---

## Step 1: Map Setup

### Choose Your Map and Draw the Route

1. Open DCS Mission Editor
2. Select your map (Syria recommended)
3. Plan a convoy route ~30-40km long with:
   - **Start**: FARP or friendly base
   - **Checkpoint Alpha**: ~10km from start (first contact)
   - **Checkpoint Bravo**: ~20km (main ambush area)
   - **Checkpoint Charlie**: ~30km (final push)
   - **End**: FOB/Destination

### Recommended Terrain Features

| Zone | Ideal Terrain |
|------|---------------|
| Alpha | Open with scattered cover (hills, compounds) |
| Bravo | Complex (villages, treelines, wadis) |
| Charlie | Urban/infrastructure (bridges, crossroads) |

---

## Step 2: Friendly Forces

### Player Aircraft

| Property | Value |
|----------|-------|
| Type | AH-64D Apache |
| Name | `Player` |
| Coalition | Blue |
| Start | FARP or runway |
| Skill | Client |
| Loadout | Your choice (AGM-114, rockets, gun) |

### Convoy

| Property | Value |
|----------|-------|
| Name | `Convoy-Main` |
| Coalition | Blue |
| Units | 4x M939 Trucks, 2x M1025 Humvees |
| Speed | 30-40 kph (slow!) |
| Late Activation | **NO** (starts immediately) |

**Convoy Waypoints:**
1. Start point
2. Checkpoint Alpha (pause 0-30 seconds)
3. Checkpoint Bravo (pause 0-30 seconds)
4. Checkpoint Charlie (pause 0-30 seconds)
5. Destination (end)

---

## Step 3: Alpha Zone Groups (Light Resistance)

All groups set to **LATE ACTIVATION = YES**

### AA Options (Place all 4, script picks 1)

| Group Name | Units | Position Description |
|------------|-------|---------------------|
| `Alpha-ZU23-Hill` | ZU-23 Technical | Hilltop overlooking route |
| `Alpha-ZU23-Road` | ZU-23 Technical | Roadside, 500m from route |
| `Alpha-MANPADS-Compound` | 2x Infantry w/Igla | Inside compound/buildings |
| `Alpha-MANPADS-Wadi` | 2x Infantry w/Igla | Hidden in dry riverbed |

### Ground Options (Place all 4, script picks 0-1)

| Group Name | Units | Position Description |
|------------|-------|---------------------|
| `Alpha-Technical-Road` | 3x Technical | On road, blocking position |
| `Alpha-Technical-Ridge` | 3x Technical | Behind ridge, flanking |
| `Alpha-Infantry-Compound` | Infantry squad | In compound buildings |
| `Alpha-Infantry-Treeline` | Infantry squad | Treeline ambush position |

### Hidden Ambush (Proximity Triggered)

| Group Name | Units | Position | Notes |
|------------|-------|----------|-------|
| `Ambush-Alpha-Hidden` | Infantry + Technical | 300m off road | Surprise ambush |

### Alpha Trigger Zone

| Zone Name | Radius | Center |
|-----------|--------|--------|
| `Alpha-Ambush-Zone` | 500m | Near `Ambush-Alpha-Hidden` |

---

## Step 4: Bravo Zone Groups (Heavy Resistance)

All groups set to **LATE ACTIVATION = YES**

### AA Options (Place all 5, script picks 1-2)

| Group Name | Units | Position Description |
|------------|-------|---------------------|
| `Bravo-Shilka-Village` | ZSU-23-4 Shilka | Village edge, concealed |
| `Bravo-Shilka-Treeline` | ZSU-23-4 Shilka | In treeline |
| `Bravo-Shilka-Hill` | ZSU-23-4 Shilka | Hilltop overwatch |
| `Bravo-Tunguska-Road` | 2S6 Tunguska | Covering road approach |
| `Bravo-ZU23-Bridge` | ZU-23 Emplaced | At bridge/chokepoint |

### Armor Options (Place all 4, script picks 0-1)

| Group Name | Units | Position Description |
|------------|-------|---------------------|
| `Bravo-BMP-Wadi` | 2x BMP-2, Infantry | Hidden in wadi/ditch |
| `Bravo-BMP-Village` | 2x BMP-2, Infantry | In village |
| `Bravo-BTR-Road` | 3x BTR-80 | On road, roadblock |
| `Bravo-BTR-Treeline` | 3x BTR-80 | Treeline flanking |

### Hidden Ambush (Proximity Triggered)

| Group Name | Units | Position |
|------------|-------|----------|
| `Ambush-Bravo-Hidden` | BMP + Infantry | Off-road, heavy ambush |

### Bravo Trigger Zone

| Zone Name | Radius | Center |
|-----------|--------|--------|
| `Bravo-Ambush-Zone` | 600m | Near `Ambush-Bravo-Hidden` |

---

## Step 5: Charlie Zone Groups (Final Push)

All groups set to **LATE ACTIVATION = YES**

### AA Options (Place all 4, script picks 1)

| Group Name | Units | Position Description |
|------------|-------|---------------------|
| `Charlie-Shilka-Crossroads` | ZSU-23-4 | At crossroads |
| `Charlie-Tunguska-Urban` | 2S6 Tunguska | In urban area |
| `Charlie-ZU23-Bridge` | ZU-23 Emplaced | Final bridge |
| `Charlie-MANPADS-Rooftop` | 2x Infantry w/Igla | On rooftop |

### Ground Options (Place all 3, script picks 0-1)

| Group Name | Units | Position Description |
|------------|-------|---------------------|
| `Charlie-Infantry-Urban` | Infantry squad | In buildings |
| `Charlie-Technical-Road` | 4x Technical | Roadblock |
| `Charlie-RPG-Overwatch` | Infantry w/RPG | Elevated position |

### Hidden Ambush (Proximity Triggered)

| Group Name | Units | Position |
|------------|-------|----------|
| `Ambush-Charlie-Hidden` | Mixed ambush | Near destination |

### Charlie Trigger Zone

| Zone Name | Radius | Center |
|-----------|--------|--------|
| `Charlie-Ambush-Zone` | 500m | Near `Ambush-Charlie-Hidden` |

---

## Step 7: QRF Groups (Reinforcements)

All groups set to **LATE ACTIVATION = YES**

| Group Name | Units | Position | Trigger |
|------------|-------|----------|---------|
| `QRF-Technicals-1` | 3x Technical | Off-map staging | Convoy under fire |
| `QRF-Technicals-2` | 3x Technical | Alt staging | Convoy under fire |
| `QRF-Armor-1` | 2x BMP-2 | Far staging | Player kills 5+ |
| `QRF-Infantry-1` | Infantry squad | With armor | Player kills 5+ |
| `QRF-Heavy-1` | T-72 + BMP | Far rear | Player kills 12+ |

Give QRF groups waypoints that lead them toward the convoy route.

---

## Step 8: Triggers Setup

### Script Loading Triggers (MISSION START)

Create these triggers in order:

| # | Event | Action | File |
|---|-------|--------|------|
| 1 | MISSION START | DO SCRIPT FILE | `lua-library/utils/coordinates.lua` |
| 2 | MISSION START | DO SCRIPT FILE | `lua-library/utils/group-utils.lua` |
| 3 | MISSION START | DO SCRIPT FILE | `lua-library/utils/timer-utils.lua` |
| 4 | MISSION START | DO SCRIPT FILE | `lua-library/utils/messaging.lua` |
| 5 | MISSION START | DO SCRIPT FILE | `lua-library/spawners/random-spawn-pool.lua` |
| 6 | MISSION START | DO SCRIPT FILE | `lua-library/spawners/random-spawn-hvt.lua` |
| 7 | MISSION START | DO SCRIPT FILE | `lua-library/ai-behavior/proximity-activation.lua` |
| 8 | MISSION START | DO SCRIPT FILE | `lua-library/ai-behavior/sam-ambush.lua` |
| 9 | MISSION START | DO SCRIPT FILE | `lua-library/events/reinforcement-waves.lua` |
| 10 | MISSION START | DO SCRIPT FILE | `lua-library/comms/bda-reporter.lua` |
| 11 | MISSION START | DO SCRIPT FILE | `ZZ mission files/dustoff-corridor/init.lua` |
| 12 | MISSION START (5s delay) | DO SCRIPT | `DMS.DustoffCorridor.start()` |

### Flag-Based Triggers (Radio Messages)

| Flag | Trigger | Action |
|------|---------|--------|
| `200 = 1` | HVT Commander spawned | Message: "INTEL: Enemy commander in AO!" |
| `201 = 1` | HVT Commander killed | Message: "Commander eliminated! +1000 pts" |
| `210 = 1` | Supply Convoy spawned | Sound: Radio beep |
| `211 = 1` | Supply Convoy killed | Message: "Supply convoy destroyed!" |
| `220 = 1` | Mobile SAM spawned | Message: "WARNING: SAM radar detected!" |
| `221 = 1` | Mobile SAM killed | Message: "SAM neutralized. Skies clear." |

### Victory/Failure Triggers

| Condition | Action |
|-----------|--------|
| Convoy reaches destination | Mission SUCCESS |
| All convoy units destroyed | Mission FAILED |
| Player destroyed | Mission FAILED (or allow respawn) |

---

## Step 9: Final Checklist

### Groups Checklist

- [ ] Player Apache at FARP
- [ ] Convoy-Main with waypoints
- [ ] 4x Alpha AA groups (Late Activation)
- [ ] 4x Alpha Ground groups (Late Activation)
- [ ] 1x Alpha Hidden Ambush (Late Activation)
- [ ] 5x Bravo AA groups (Late Activation)
- [ ] 4x Bravo Armor groups (Late Activation)
- [ ] 1x Bravo Hidden Ambush (Late Activation)
- [ ] 4x Charlie AA groups (Late Activation)
- [ ] 3x Charlie Ground groups (Late Activation)
- [ ] 1x Charlie Hidden Ambush (Late Activation)
- [ ] 3x HVT groups (Late Activation)
- [ ] 5x QRF groups (Late Activation)

**Total: ~35 groups**

### Zones Checklist

- [ ] Alpha-Ambush-Zone
- [ ] Bravo-Ambush-Zone
- [ ] Charlie-Ambush-Zone

### Triggers Checklist

- [ ] 12x Script loading triggers
- [ ] Flag message triggers
- [ ] Victory/failure conditions

---

## Step 10: Testing

### Debug Mode

In `init.lua`, set:
```lua
DMS.DustoffCorridor.Config.debug = true
```

This will print spawn results to screen at mission start.

### Quick Test

1. Start mission
2. Verify briefing appears
3. Check debug output shows which threats spawned
4. Fly route and verify:
   - Random threats appear at different positions
   - SAMs stay dark until you approach
   - Hidden ambushes trigger on proximity
   - HVTs may or may not appear
   - QRF spawns when convoy takes fire

### Multiple Playthroughs

Run the mission 3-4 times to verify different spawn combinations.

---

## Spawn Probability Summary

| Element | Chance | Count |
|---------|--------|-------|
| Alpha AA | 60% | 1 of 4 |
| Alpha Ground | 50% | 1 of 4 |
| Bravo AA | 80% | 2 of 5 |
| Bravo Armor | 70% | 1 of 4 |
| Charlie AA | 75% | 1 of 4 |
| Charlie Ground | 65% | 1 of 3 |
| Hidden Ambush (each) | 50-70% | On proximity |
| HVT Commander | 25% | At 8-12 min |
| HVT Supply | 40% | At 5-10 min |
| HVT Mobile SAM | 20% | At 10-15 min |
| QRF Wave 1 | 100% | When convoy hit |
| QRF Wave 2 | Conditional | If 5+ kills |
| QRF Wave 3 | Conditional | If 12+ kills |

---

## Customization

### Easier Version

In `init.lua`:
```lua
-- Reduce spawn chances
DMS.SpawnPool.Pools["alpha-aa"].chance = 40
DMS.SpawnPool.Pools["bravo-aa"].chance = 60
DMS.SpawnPool.Pools["bravo-aa"].count = 1
```

### Harder Version

```lua
-- Increase spawn chances and counts
DMS.SpawnPool.Pools["bravo-aa"].chance = 100
DMS.SpawnPool.Pools["bravo-aa"].count = 3
DMS.SpawnPool.Pools["charlie-aa"].count = 2
```

### Different Time of Day

Set in Mission Editor:
- Dawn (0530): Harder visibility, dramatic lighting
- Day (1200): Clear visibility
- Dusk (1800): Low sun, challenging for optics

---

## Troubleshooting

### Nothing Spawns

- Check groups are set to LATE ACTIVATION
- Check group names match exactly (case sensitive)
- Enable debug mode to see spawn results

### SAMs Not Working

- Verify SAM groups are active (check spawn pool results)
- SAMs stay dark until you enter 10km envelope
- Check console for SAMAmbush debug messages

### QRF Not Spawning

- Wave 1 requires `convoy_under_fire` flag
- Wave 2 requires 5+ player kills AND 10 min elapsed
- Wave 3 requires 12+ player kills

### Script Errors

- Load scripts in correct order (utils first)
- Check DCS log file for Lua errors
- Verify file paths are correct for your installation

---

## File Structure

```
DMS/
├── lua-library/
│   ├── utils/
│   ├── spawners/
│   ├── ai-behavior/
│   ├── events/
│   ├── comms/
│   └── ZZ mission files/
│       └── dustoff-corridor/
│           ├── init.lua          <-- Main mission script
│           └── MISSION-SETUP.md  <-- This file
└── miz-files/
    └── output/
        └── dustoff-corridor.miz  <-- Your saved mission
```

---

Good luck, and happy hunting!
