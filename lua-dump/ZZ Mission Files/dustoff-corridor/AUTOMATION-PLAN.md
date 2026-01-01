# Dustoff Corridor - Mission Automation Plan

## Overview

Automate the creation of ~32 enemy groups, triggers, and zones from a base mission file where the user has manually placed only the essential creative elements.

---

## Phase 1: User Manual Setup (DCS Mission Editor)

### What User Places Manually

| Element | Name Convention | Purpose |
|---------|-----------------|---------|
| **Player Aircraft** | `Player` | AH-64D Apache, Client slot |
| **Convoy Group** | `Convoy-Main` | 4x trucks + 2x Humvees with full route |
| **Alpha Zone** | `Alpha-Ambush-Zone` | ~500m radius trigger zone |
| **Bravo Zone** | `Bravo-Ambush-Zone` | ~600m radius trigger zone |
| **Charlie Zone** | `Charlie-Ambush-Zone` | ~500m radius trigger zone |

### Optional Additional Zones (for positioning reference)

| Element | Name Convention | Purpose |
|---------|-----------------|---------|
| `Alpha-Center` | Zone marking Alpha area center | Enemy spawn reference |
| `Bravo-Center` | Zone marking Bravo area center | Enemy spawn reference |
| `Charlie-Center` | Zone marking Charlie area center | Enemy spawn reference |
| `QRF-Staging` | Zone for QRF spawn point | Behind enemy lines |

### User Deliverable

- Save as: `miz-files/input/dustoff-corridor-base.miz`
- Map: Syria or Caucasus
- Coalitions: Blue (USA) and Red (Russia) must exist
- Time/Weather: User's choice

---

## Phase 2: Script Extraction

### Data to Extract from Base Mission

```python
extract_data = {
    # Trigger Zones
    "zones": {
        "Alpha-Ambush-Zone": {"x": float, "y": float, "radius": float},
        "Bravo-Ambush-Zone": {"x": float, "y": float, "radius": float},
        "Charlie-Ambush-Zone": {"x": float, "y": float, "radius": float},
        # Optional positioning zones
        "Alpha-Center": {"x": float, "y": float, "radius": float},
        "Bravo-Center": {"x": float, "y": float, "radius": float},
        "Charlie-Center": {"x": float, "y": float, "radius": float},
    },

    # Convoy route for threat positioning
    "convoy_route": [
        {"x": float, "y": float, "name": "waypoint_1"},
        {"x": float, "y": float, "name": "waypoint_2"},
        # ...
    ],

    # Existing groups (to avoid ID conflicts)
    "existing_groups": ["Player", "Convoy-Main"],
    "max_group_id": int,
    "max_unit_id": int,
}
```

### Extraction Functions Needed

| Function | Source | Status |
|----------|--------|--------|
| `list_trigger_zones()` | `triggers/list.py` | Verify exists |
| `extract_convoy_waypoints()` | `waypoints/` | May need to create |
| `list_all_groups()` | `groups/list.py` | Exists |
| `get_max_ids()` | `utils/id_manager.py` | Exists |

---

## Phase 3: Group Generation

### Enemy Groups to Generate (~35 total)

#### Alpha Zone Groups (9 groups)

| Group Name | Unit Type | Count | Position Logic |
|------------|-----------|-------|----------------|
| `Alpha-ZU23-Hill` | ZU-23 Technical | 1 | Elevated, 500m from route |
| `Alpha-ZU23-Road` | ZU-23 Technical | 1 | Roadside, 300m from route |
| `Alpha-MANPADS-Compound` | Infantry w/Igla | 2 | Near buildings/compound |
| `Alpha-MANPADS-Wadi` | Infantry w/Igla | 2 | Low terrain feature |
| `Alpha-Technical-Road` | Technical | 3 | On/near road |
| `Alpha-Technical-Ridge` | Technical | 3 | Behind terrain |
| `Alpha-Infantry-Compound` | Infantry Squad | 6 | In compound |
| `Alpha-Infantry-Treeline` | Infantry Squad | 6 | In treeline |
| `Ambush-Alpha-Hidden` | Infantry + Technical | 4 | 300m off road, surprise |

#### Bravo Zone Groups (10 groups)

| Group Name | Unit Type | Count | Position Logic |
|------------|-----------|-------|----------------|
| `Bravo-Shilka-Village` | ZSU-23-4 | 1 | Village edge |
| `Bravo-Shilka-Treeline` | ZSU-23-4 | 1 | In treeline |
| `Bravo-Shilka-Hill` | ZSU-23-4 | 1 | Hilltop |
| `Bravo-Tunguska-Road` | 2S6 Tunguska | 1 | Covering road |
| `Bravo-ZU23-Bridge` | ZU-23 Emplaced | 1 | At chokepoint |
| `Bravo-BMP-Wadi` | BMP-2 + Infantry | 2+4 | Hidden in wadi |
| `Bravo-BMP-Village` | BMP-2 + Infantry | 2+4 | In village |
| `Bravo-BTR-Road` | BTR-80 | 3 | Roadblock |
| `Bravo-BTR-Treeline` | BTR-80 | 3 | Flanking position |
| `Ambush-Bravo-Hidden` | BMP + Infantry | 1+4 | Heavy ambush |

#### Charlie Zone Groups (8 groups)

| Group Name | Unit Type | Count | Position Logic |
|------------|-----------|-------|----------------|
| `Charlie-Shilka-Crossroads` | ZSU-23-4 | 1 | At crossroads |
| `Charlie-Tunguska-Urban` | 2S6 Tunguska | 1 | Urban area |
| `Charlie-ZU23-Bridge` | ZU-23 Emplaced | 1 | Final bridge |
| `Charlie-MANPADS-Rooftop` | Infantry w/Igla | 2 | Elevated |
| `Charlie-Infantry-Urban` | Infantry Squad | 6 | In buildings |
| `Charlie-Technical-Road` | Technical | 4 | Roadblock |
| `Charlie-RPG-Overwatch` | Infantry w/RPG | 3 | Elevated |
| `Ambush-Charlie-Hidden` | Mixed | 4 | Near destination |

#### QRF Groups (5 groups)

| Group Name | Unit Type | Count | Position Logic |
|------------|-----------|-------|----------------|
| `QRF-Technicals-1` | Technical | 3 | Staging area |
| `QRF-Technicals-2` | Technical | 3 | Alt staging |
| `QRF-Armor-1` | BMP-2 | 2 | Far staging |
| `QRF-Infantry-1` | Infantry Squad | 6 | With armor |
| `QRF-Heavy-1` | T-72 + BMP | 2 | Far rear |

### Position Generation Algorithm

```python
def generate_group_positions(zone_center, zone_radius, convoy_route):
    """
    Generate positions for groups around a zone center.

    Strategy:
    - AA groups: 500-1500m from zone center, varied angles
    - Ground groups: 200-800m from zone center
    - Ambush groups: 200-500m off convoy route
    - Use convoy route to determine "road direction"
    """
    positions = {}

    # Calculate road bearing from convoy waypoints
    road_bearing = calculate_bearing(convoy_route)

    # AA positions: offset perpendicular to road
    for i, aa_group in enumerate(aa_groups):
        angle = road_bearing + (90 if i % 2 == 0 else -90) + random_offset(-30, 30)
        distance = random_range(500, 1500)
        positions[aa_group] = offset_position(zone_center, angle, distance)

    # Ground positions: closer to road
    for i, ground_group in enumerate(ground_groups):
        angle = road_bearing + (45 * i) + random_offset(-20, 20)
        distance = random_range(200, 800)
        positions[ground_group] = offset_position(zone_center, angle, distance)

    return positions
```

### Unit Type Mappings (DCS Internal Names)

```python
UNIT_TYPES = {
    # AA
    "ZU-23 Technical": "Ural-375 ZU-23",
    "ZSU-23-4": "ZSU-23-4 Shilka",
    "2S6 Tunguska": "2S6 Tunguska",
    "SA-8 Gecko": "Osa 9A33 ln",
    "Infantry Igla": "Infantry AK Ins",  # + Igla in loadout?

    # Armor
    "BMP-2": "BMP-2",
    "BTR-80": "BTR-80",
    "T-72": "T-72B",

    # Vehicles
    "Technical": "UAZ-469",  # Or armed variant
    "UAZ Command": "UAZ-469",
    "Truck": "Ural-375",

    # Infantry
    "Infantry Squad": "Infantry AK Ins",
    "Infantry RPG": "Infantry AK Ins",  # Need RPG variant
}
```

---

## Phase 4: Trigger Generation

### Script Loading Triggers (11 triggers)

| Order | Trigger Name | Script Path | Delay |
|-------|--------------|-------------|-------|
| 1 | Load Coordinates | `lua-dump/utils/coordinates.lua` | 0s |
| 2 | Load Group Utils | `lua-dump/utils/group-utils.lua` | 0s |
| 3 | Load Timer Utils | `lua-dump/utils/timer-utils.lua` | 0s |
| 4 | Load Messaging | `lua-dump/utils/messaging.lua` | 0s |
| 5 | Load Spawn Pool | `lua-dump/spawners/random-spawn-pool.lua` | 0s |
| 6 | Load Proximity | `lua-dump/ai-behavior/proximity-activation.lua` | 0s |
| 7 | Load SAM Ambush | `lua-dump/ai-behavior/sam-ambush.lua` | 0s |
| 8 | Load Reinforcements | `lua-dump/events/reinforcement-waves.lua` | 0s |
| 9 | Load BDA Reporter | `lua-dump/comms/bda-reporter.lua` | 0s |
| 10 | Load Mission Init | `ZZ Mission Files/dustoff-corridor/init.lua` | 0s |
| 11 | Start Mission | `DMS.DustoffCorridor.start()` | 5s |

**Note**: DCS uses DO SCRIPT FILE for external files, DO SCRIPT for inline code.

### Flag Message Triggers (None - HVT Removed)

HVT system removed from this mission. No flag-based triggers needed.

### Trigger Implementation

```python
# Script loading triggers use DO SCRIPT FILE
# But our add.py uses DO SCRIPT (inline)
# May need to add DO SCRIPT FILE support

# Current capability:
add_do_script_trigger(content, "Start Mission", "DMS.DustoffCorridor.start()", time_after=5)

# Needed capability:
add_do_script_file_trigger(content, "Load Init", "path/to/init.lua", time_after=0)
```

---

## Phase 5: Implementation Tasks

### Pre-Implementation Checks

- [ ] Verify `triggers/list.py` can extract trigger zones
- [ ] Verify `groups/add.py` works with vehicle units
- [ ] Check if DO SCRIPT FILE trigger support exists
- [ ] Confirm unit type names are correct for DCS

### Implementation Order

1. **Create extraction module** (`dustoff_extractor.py`)
   - Extract trigger zones
   - Extract convoy waypoints
   - Extract existing IDs

2. **Create position generator** (`dustoff_positions.py`)
   - Algorithm to distribute groups around zones
   - Randomization with seed for reproducibility

3. **Create group generator** (`dustoff_groups.py`)
   - Generate all 35 groups with correct unit types
   - Set late activation flag
   - Apply correct headings

4. **Create trigger generator** (`dustoff_triggers.py`)
   - Add DO SCRIPT FILE triggers (may need to extend `triggers/add.py`)
   - Add flag-based message triggers

5. **Create main orchestrator** (`build_dustoff_mission.py`)
   - Load base mission
   - Run extraction
   - Generate positions
   - Add groups
   - Add triggers
   - Save output mission

---

## Phase 6: Verification

### Output Verification Checklist

- [ ] All 35 groups present with correct names
- [ ] All groups set to LATE ACTIVATION
- [ ] All groups positioned within expected zones
- [ ] Trigger zones preserved from base mission
- [ ] All 12 script triggers present
- [ ] All flag triggers present
- [ ] Player and Convoy groups unchanged
- [ ] Mission loads without errors in DCS

### Testing Process

1. Load output .miz in DCS Mission Editor
2. Verify all groups visible on map
3. Verify late activation status
4. Start mission and check:
   - Briefing appears
   - Debug mode shows spawn results
   - Random threats activate
   - No Lua errors in DCS.log

---

## File Structure

```
DMS/
├── miz-files/
│   ├── input/
│   │   └── dustoff-corridor-base.miz    # User creates this
│   └── output/
│       └── dustoff-corridor-final.miz   # Script generates this
│
├── miz_file_modification/
│   ├── triggers/
│   │   ├── add.py                       # May need DO SCRIPT FILE support
│   │   └── list.py                      # Zone extraction
│   └── groups/
│       └── add.py                       # Group creation
│
└── lua-dump/
    └── ZZ Mission Files/
        └── dustoff-corridor/
            ├── MISSION-SETUP.md          # Reference doc
            ├── AUTOMATION-PLAN.md        # This document
            ├── init.lua                  # Mission script (done)
            └── build_mission.py          # Main automation script
```

---

## Open Questions

1. **DO SCRIPT FILE vs DO SCRIPT**: Does `triggers/add.py` support loading external files, or only inline scripts?

2. **Unit Type Names**: Need to verify exact DCS internal names for all unit types (especially infantry variants with specific weapons).

3. **Late Activation**: How is late activation set? Is it a group property we can modify, or does `add_group()` need a parameter?

4. **Heading Calculation**: Should groups face toward the convoy route, or random headings?

5. **Infantry Composition**: How to create infantry squads with mixed weapons (some with Igla, some with RPG)?

---

## Next Steps

1. Review this plan and confirm approach
2. Answer open questions
3. Check existing module capabilities
4. Begin implementation in order specified

