# Dustoff Corridor - Minimal Input Mission Setup

## Philosophy

**User places only essential creative elements. Lua handles all randomization and behavior.**

The DMS Lua library is designed so that mission creators place LATE ACTIVATION groups in the Mission Editor, and the scripts handle when/if they activate. This means:
- **User work**: Place groups, name them correctly, set LATE ACTIVATION
- **Lua work**: Random selection, proximity triggers, AI behavior, reinforcements

---

## What User Must Do (Mission Editor)

### Required Elements (5 items)

| Element | Name | Notes |
|---------|------|-------|
| Player Aircraft | `Player` | AH-64D, Client slot |
| Convoy Group | `Convoy-Main` | Trucks + escorts with route |
| Zone | `Alpha-Ambush-Zone` | Trigger zone ~500m radius |
| Zone | `Bravo-Ambush-Zone` | Trigger zone ~600m radius |
| Zone | `Charlie-Ambush-Zone` | Trigger zone ~500m radius |

### Enemy Groups (LATE ACTIVATION)

User places these groups at desired positions. **Naming convention is critical** - the Lua scripts find groups by name.

#### Alpha Zone (~9 groups)
```
Alpha-ZU23-Hill          # ZU-23 on elevated position
Alpha-ZU23-Road          # ZU-23 roadside
Alpha-MANPADS-Compound   # Igla team in compound
Alpha-MANPADS-Wadi       # Igla team in wadi
Alpha-Technical-Road     # Technicals on road
Alpha-Technical-Ridge    # Technicals behind ridge
Alpha-Infantry-Compound  # Infantry squad
Alpha-Infantry-Treeline  # Infantry in trees
Ambush-Alpha-Hidden      # Proximity-activated ambush
```

#### Bravo Zone (~10 groups)
```
Bravo-Shilka-Village     # ZSU-23-4 at village
Bravo-Shilka-Treeline    # ZSU-23-4 in treeline
Bravo-Shilka-Hill        # ZSU-23-4 on hill
Bravo-Tunguska-Road      # 2S6 covering road
Bravo-ZU23-Bridge        # ZU-23 at chokepoint
Bravo-BMP-Wadi           # BMPs hidden in wadi
Bravo-BMP-Village        # BMPs in village
Bravo-BTR-Road           # BTRs on road
Bravo-BTR-Treeline       # BTRs in treeline
Ambush-Bravo-Hidden      # Proximity-activated ambush
```

#### Charlie Zone (~8 groups)
```
Charlie-Shilka-Crossroads   # ZSU-23-4 at crossroads
Charlie-Tunguska-Urban      # 2S6 in urban area
Charlie-ZU23-Bridge         # ZU-23 at final bridge
Charlie-MANPADS-Rooftop     # MANPADS elevated
Charlie-Infantry-Urban      # Infantry in buildings
Charlie-Technical-Road      # Technicals blocking road
Charlie-RPG-Overwatch       # RPG teams elevated
Ambush-Charlie-Hidden       # Proximity-activated ambush
```

#### QRF Groups (~5 groups)
```
QRF-Technicals-1         # Light QRF
QRF-Technicals-2         # Light QRF alt
QRF-Armor-1              # BMP response
QRF-Infantry-1           # Infantry with armor
QRF-Heavy-1              # T-72 heavy response
```

**Total: ~32 LATE ACTIVATION groups**

---

## What Lua Handles Automatically

### Layer 1: Random Selection (SpawnPool)

```lua
-- From init.lua - picks random subset of placed groups
DMS.SpawnPool.create("alpha-aa", { chance = 60, count = 1 })
DMS.SpawnPool.addGroups("alpha-aa", {
    "Alpha-ZU23-Hill", "Alpha-ZU23-Road",
    "Alpha-MANPADS-Compound", "Alpha-MANPADS-Wadi",
})
```

**What this does**: 60% chance to activate exactly 1 random AA group from the 4 options.

### Layer 2: Proximity Activation

```lua
-- Groups that only activate when player gets close
DMS.Proximity.registerWithZone("Ambush-Alpha-Hidden", "Alpha-Ambush-Zone", 70)
```

**What this does**: When player enters zone, 70% chance to activate the hidden ambush.

### Layer 3: SAM Ambush Behavior

```lua
-- SAMs stay radar-dark until player in engagement envelope
DMS.SAMAmbush.registerAtPosition("Bravo-Shilka-Village", 10000)
```

**What this does**: Shilka keeps radar off. When player within 10km, goes HOT.

### Layer 4: Reinforcement Waves

```lua
-- QRF responds to convoy taking fire
DMS.Reinforcements.waveOnFlag(1, {"QRF-Technicals-1"}, "convoy_under_fire", 1)
```

**What this does**: When convoy hit (flag set by event handler), QRF spawns.

### Layer 5: Kill Tracking & Adaptive Response

```lua
-- Heavy QRF only if player is doing well
DMS.Reinforcements.registerWave(3, {"QRF-Heavy-1"}, {
    condition = function()
        return DMS.DustoffCorridor.State.playerKills >= 12
    end,
})
```

---

## Script Load Order (DO SCRIPT FILE triggers)

Create these triggers in Mission Editor with "MISSION START" condition:

| # | Script Path | Delay |
|---|-------------|-------|
| 1 | `lua-dump/utils/coordinates.lua` | 0s |
| 2 | `lua-dump/utils/group-utils.lua` | 0s |
| 3 | `lua-dump/utils/timer-utils.lua` | 0s |
| 4 | `lua-dump/utils/messaging.lua` | 0s |
| 5 | `lua-dump/utils/mission-settings.lua` | 0s |
| 6 | `lua-dump/spawners/random-spawn-pool.lua` | 0s |
| 7 | `lua-dump/ai-behavior/proximity-activation.lua` | 0s |
| 8 | `lua-dump/ai-behavior/sam-ambush.lua` | 0s |
| 9 | `lua-dump/events/reinforcement-waves.lua` | 0s |
| 10 | `lua-dump/comms/bda-reporter.lua` | 0s |
| 11 | `ZZ Mission Files/dustoff-corridor/init.lua` | 0s |
| 12 | DO SCRIPT: `DMS.DustoffCorridor.start()` | 2s |

---

## Enhanced Features to Add

### 1. Objective Tracking

Add `objective-tracker.lua` to track convoy progress:

```lua
-- In init.lua
DMS.Objectives.register("escort_convoy", {
    description = "Escort convoy to FOB Victory",
    type = "arrival",
    targetGroup = "Convoy-Main",
    targetZone = "FOB-Victory-Zone",
})

DMS.Objectives.register("protect_convoy", {
    description = "Keep at least 2 convoy vehicles alive",
    type = "survival",
    targetGroup = "Convoy-Main",
    minUnits = 2,
})
```

### 2. Phase Manager

Add mission phases for structured flow:

```lua
DMS.PhaseManager.definePhase("ALPHA", {
    name = "Alpha Sector",
    briefing = "Clear Alpha sector for convoy passage.",
    onEnter = function()
        DMS.SpawnPool.executePool("alpha-aa")
        DMS.SpawnPool.executePool("alpha-ground")
    end,
})

DMS.PhaseManager.addTransition("ALPHA", "BRAVO", {
    type = "zone",
    zone = "Bravo-Ambush-Zone",
    unit = "Convoy-Main",
})
```

### 3. Support Requests (F10 Menu)

Add player-callable support:

```lua
-- Add support request menu
DMS.CommandMenu.configure({ rootMenuName = "Dustoff Support" })

DMS.SupportRequests.registerAsset("arty", DMS.SupportRequests.TYPES.ARTILLERY, nil, {
    cooldown = 300,
    uses = 2,
})

DMS.SupportRequests.registerAsset("resupply", DMS.SupportRequests.TYPES.RESUPPLY, "FARP-1", {
    cooldown = 600,
})
```

### 4. BDA Reporter

Already integrated - reports kills to player:

```lua
DMS.BDA.configure({
    playerCoalition = coalition.side.BLUE,
    announceKills = true,
    trackGroups = {"Bravo-Shilka-Village", "Bravo-Tunguska-Road", ...},
})
```

### 5. Audio Alerts

Add radio calls using audio-player:

```lua
DMS.AudioPlayer.configure({
    basePath = "l10n/DEFAULT/",
})

-- When convoy takes fire
DMS.AudioPlayer.play("convoy_under_fire.ogg", coalition.side.BLUE)
```

### 6. Skill Scaling

Adjust AI difficulty based on player performance:

```lua
DMS.SkillScaling.configure({
    initialSkill = "Good",
    announceChanges = false,
})

-- Connect to adaptive spawner
DMS.AdaptiveSpawner.registerPool("reinforcements", {"QRF-Technicals-1", "QRF-Armor-1"}, {
    difficulty = "medium",
})
```

---

## Simplified Setup Checklist

### User (Mission Editor) - ~30 minutes

- [ ] Place player aircraft (AH-64D)
- [ ] Place convoy with route (4x trucks, 2x Humvees)
- [ ] Create 3 trigger zones (Alpha, Bravo, Charlie)
- [ ] Place ~32 enemy groups at various positions
- [ ] Set ALL enemy groups to LATE ACTIVATION
- [ ] Name groups according to convention above
- [ ] Add DO SCRIPT FILE triggers for Lua scripts
- [ ] Save mission

### Automatic (Lua Runtime)

- [x] Random threat selection from pools
- [x] Proximity-based ambush activation
- [x] SAM ambush behavior (dark until engaged)
- [x] Convoy under fire detection
- [x] QRF reinforcement spawning
- [x] Kill tracking and adaptive response
- [x] Mission briefing display
- [x] Debug logging (if enabled)

---

## Replayability Matrix

Each playthrough is unique due to:

| System | Randomization |
|--------|---------------|
| SpawnPool | Different threats each time (1-2 from each pool) |
| Proximity | 50-70% chance per ambush site |
| Reinforcements | Only spawn if conditions met |
| SAM Ambush | Behavior varies by approach angle |
| Time of Day | Set randomly in ME or by user |

**Estimated unique combinations**: 1000+ different threat layouts

---

## Files Structure

```
DMS/
├── lua-dump/
│   ├── utils/                    # Core utilities
│   ├── spawners/
│   │   └── random-spawn-pool.lua # Pool selection
│   ├── ai-behavior/
│   │   ├── proximity-activation.lua
│   │   └── sam-ambush.lua
│   ├── events/
│   │   ├── reinforcement-waves.lua
│   │   └── objective-tracker.lua
│   ├── comms/
│   │   ├── bda-reporter.lua
│   │   └── audio-player.lua
│   ├── mission-state/
│   │   └── phase-manager.lua
│   └── player-support/
│       ├── command-menu.lua
│       └── support-requests.lua
│
└── ZZ Mission Files/
    └── dustoff-corridor/
        ├── AUTOMATION-PLAN.md    # This document
        ├── init.lua              # Mission configuration
        └── audio/                # Mission audio files (optional)
            ├── convoy_under_fire.ogg
            └── mission_complete.ogg
```

---

## Quick Start

1. **Copy template mission** with pre-placed groups (if available)
2. **Adjust positions** to fit your preferred map area
3. **Modify init.lua** if you want different pool chances
4. **Test in DCS** with debug mode enabled:
   ```lua
   DMS.Settings.configure({ debug = true })
   ```
5. **Check DCS.log** for `[DUSTOFF]`, `[SpawnPool]`, `[Proximity]` messages

---

## Future Automation

Python script could automate:
- Extracting zone positions from base mission
- Generating group positions around zones
- Adding groups to mission file
- Creating DO SCRIPT FILE triggers

But current approach requires only:
- User places groups manually (full control over terrain use)
- Lua handles all runtime logic

This gives mission creators artistic control while removing tedious trigger logic.
