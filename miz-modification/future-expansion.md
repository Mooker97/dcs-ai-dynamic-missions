# Future Expansion - Patterns Utility

This document captures potential expansions for `utils/patterns.py` to support advanced mission manipulation and generation features.

## Current Coverage (v1.0)

✅ Groups, units, waypoints (core structure)
✅ Coordinates and positioning (x, y, alt, heading)
✅ IDs and coalitions (groupId, unitId, coalition structure)
✅ Basic unit properties (skill, speed, task, visibility, start_time)

## Potential Pattern Categories

### High Priority - Mission-Critical Patterns

**Triggers & Conditions**
- Trigger rule patterns (conditions, actions, events)
- Zone definitions (circular, quad, polygon zones)
- Flag operations (set flag, check flag conditions)
- Time-based triggers (mission time, absolute time)
- Unit-based conditions (alive, dead, in zone, damaged)
- Victory/defeat conditions
- Mission goal states

**Weather & Time**
- Weather patterns (cloud base, precipitation, visibility, fog)
- Wind conditions (at ground, at altitude, turbulence)
- Season and temperature
- Date and time of day
- Dynamic weather changes (forecast)
- QNH (barometric pressure)

**Loadout & Pylons**
- Pylon configuration patterns
- Weapon types (missiles, bombs, guns, rockets)
- Fuel tank configurations
- Pod loadouts (targeting, ECM, datalink)
- Chaff/flare quantities
- Gun ammunition types and counts

**Radio & Communications**
- Radio frequency presets
- Callsign patterns (flight callsigns, numbers)
- TACAN channels and morse codes
- ILS frequencies
- Radio modulation (AM/FM)
- Link16 settings

### Medium Priority - Enhanced Functionality

**Mission Goals & Briefing**
- Mission description text
- Objective descriptions
- Briefing images and overlays
- Task descriptions
- Success criteria text
- Pictorial representation data

**Parking & Spawns**
- Airbase parking spot IDs
- Parking type (hot, cold, runway)
- Taxiway paths
- Cargo spawn points
- Ship deck spots (carrier operations)
- FARP positions

**Formation & Tactics**
- Formation type patterns
- Formation spacing parameters
- ROE (Rules of Engagement) settings
- Alarm state (auto, green, red)
- RTB (Return to Base) settings
- Emission control (EMCON) settings
- Reaction to threat patterns

**Task Parameters**
- CAP (Combat Air Patrol) race track patterns
- SEAD (Suppression of Enemy Air Defenses) engagement zones
- Tanker track patterns and altitudes
- AWACS orbit patterns
- Ground attack target areas
- Escort formation parameters
- CAS (Close Air Support) patterns

### Advanced - Future Features

**Script Injection**
- Embedded Lua script patterns
- Trigger action script blocks
- Mission start scripts
- Do Script actions
- Do Script File references
- Custom mission logic patterns

**Failure Systems**
- Random failure probability patterns
- System failure definitions
- Damage state patterns
- Fuel leak rates
- Engine failure parameters

**Map Resources**
- Theater bounds and map center
- Map resource file references
- Custom map images
- Force display options
- Fog of war settings

**Liveries**
- Aircraft livery/skin names
- Country-specific livery mappings
- Custom livery file references

**Advanced AI Behavior**
- Combat behavior patterns
- Threat response tables
- Targeting priority rules
- Defensive maneuver patterns
- Energy management settings
- Sensor usage patterns

**Static Objects**
- Static object types
- Building patterns
- Scenery objects
- Ground fortifications
- SAM site templates

**Naval Operations**
- Ship task patterns (patrol, cargo shipping)
- Naval waypoint parameters
- Carrier operations patterns
- Landing signal officer settings
- Case I/II/III recovery patterns

**Ground Operations**
- Ground group formations
- Off-road movement patterns
- Combat behavior for ground units
- Artillery fire missions
- Convoy parameters

**Special Features**
- Smoke patterns (color, density)
- Flare patterns (illumination)
- Effects and explosions
- Beacons (strobe, IR, radio)
- Mark points and navigation points

## Pattern Design Considerations

### Complexity Levels

**Level 1 - Simple Field Extraction**
- Single field patterns (already implemented)
- Example: `["frequency"] = 251000000`

**Level 2 - Nested Structure Extraction**
- Multi-level nested tables
- Example: `["payload"]["pylons"][1]["CLSID"]`

**Level 3 - Dynamic Structure Detection**
- Variable nesting depths
- Optional fields
- Conditional structures

### Mission Type Priorities

When expanding patterns, prioritize based on mission type requirements:

**Air-to-Air Missions (CAP, Intercept)**
- Loadouts (missiles, fuel)
- Radio frequencies
- Formation patterns
- CAP race track parameters

**Air-to-Ground Missions (Strike, SEAD, CAS)**
- Ground attack loadouts
- Target zones
- Ingress/egress waypoints
- SEAD engagement rules

**Naval Operations**
- Ship spawn patterns
- Naval waypoint types
- Carrier deck operations
- Naval loadouts

**Combined Arms**
- Ground unit formations
- Convoy parameters
- JTAC coordination
- CAS patterns

## Replayability Feature Patterns

Patterns that support dynamic/randomized mission content:

1. **Weather Randomization** - Extract/modify weather parameters
2. **Loadout Variety** - Swap weapon configurations
3. **Spawn Locations** - Randomize start positions (already supported via coordinates)
4. **Trigger Conditions** - Dynamic objective conditions
5. **Time of Day** - Random mission start times
6. **Enemy Composition** - Variable threat levels

## Implementation Priority Recommendations

### Phase 1 (MVP Support)
- Triggers & Conditions (basic)
- Weather & Time
- Loadout & Pylons (basic)

### Phase 2 (Enhanced Missions)
- Mission Goals & Briefing
- Task Parameters
- Formation & Tactics

### Phase 3 (Advanced AI)
- Advanced AI Behavior
- Script Injection
- Special Features

## Usage Pattern Recommendations

For each new pattern category:

1. **Define Pattern** - Create regex pattern
2. **Add Constant** - Pre-compile with `re.compile()`
3. **Add Extractor** - Utility function in `patterns.py`
4. **Document** - Add to this file with examples
5. **Test** - Validate against real .miz files

## Notes

- Patterns should prioritize **read operations** first (extraction/listing)
- Modification patterns can be added later as needed
- Focus on patterns that support **dynamic mission generation**
- Keep patterns consistent with existing naming conventions
- All patterns should handle optional whitespace variations
- Consider DCS version compatibility (some fields may not exist in all versions)

## Questions to Answer Before Expansion

1. **Mission Type Focus**: Which mission types will be generated most?
2. **Dynamic Features**: Which elements need runtime randomization?
3. **Complexity Level**: How deep into advanced AI behavior do we need?
4. **Timeline**: What's needed for MVP vs. future enhancements?

---

*Document created: 2025-12-09*
*Last updated: 2025-12-09*
