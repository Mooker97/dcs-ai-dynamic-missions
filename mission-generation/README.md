# Mission Generation Pipeline

Transform natural language mission requests into playable DCS .miz files in seconds.

## Vision

```
"Create a 4-ship F-16 SEAD mission in the Persian Gulf at dawn with heavy SAM threats"
                                    ↓
                        30 seconds of processing
                                    ↓
            PlayableSEADMission_PersianGulf_20260103.miz
```

## What is the Mission Generation Pipeline?

The **Mission Generation Pipeline** is a system that:

1. **Understands** natural language mission requests
2. **Designs** balanced, realistic mission structures
3. **Builds** complete .miz files using the miz-modifier library
4. **Injects** dynamic Lua scripts for replayability
5. **Validates** mission integrity before delivery

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────┐
│                     User Input (Natural Language)            │
│   "Create a SEAD mission in Syria with F/A-18Cs at dusk"    │
└──────────────────────────┬──────────────────────────────────┘
                           ↓
┌──────────────────────────────────────────────────────────────┐
│                    1. Intent Parser                          │
│  Extracts: mission type, theater, aircraft, time, threats    │
└──────────────────────────┬───────────────────────────────────┘
                           ↓
                  Structured Parameters
                           ↓
┌──────────────────────────────────────────────────────────────┐
│                   2. Mission Designer                         │
│  Selects: template, unit compositions, Lua scripts, balance  │
└──────────────────────────┬───────────────────────────────────┘
                           ↓
                  Mission Structure
                           ↓
┌──────────────────────────────────────────────────────────────┐
│                   3. Mission Builder                          │
│  Uses miz-modifier: add groups, waypoints, modify mission    │
└──────────────────────────┬───────────────────────────────────┘
                           ↓
                  Modified .miz File
                           ↓
┌──────────────────────────────────────────────────────────────┐
│                    4. Lua Injector                           │
│  Injects: spawn pools, SAM ambush, objectives, BDA, etc.    │
└──────────────────────────┬───────────────────────────────────┘
                           ↓
                  Dynamic .miz File
                           ↓
┌──────────────────────────────────────────────────────────────┐
│                     5. Validator                             │
│  Checks: IDs unique, coordinates valid, Lua syntax correct   │
└──────────────────────────┬───────────────────────────────────┘
                           ↓
                  Playable .miz File ✅
```

## Pipeline Components

### 1. Intent Parser (`pipeline/intent_parser.py`)

**Purpose**: Convert natural language to structured mission parameters

**Input**:
```
"Create a 4-ship F-16 SEAD mission in the Persian Gulf at dawn with heavy SAM threats"
```

**Output**:
```python
{
    "mission_type": "SEAD",
    "theater": "PersianGulf",
    "time_of_day": "dawn",
    "weather": "clear",
    "player": {
        "aircraft": "F-16C_50",
        "count": 4,
        "loadout": "SEAD",
        "skill": "Player",
        "airbase": "auto"
    },
    "threats": {
        "level": "heavy",
        "types": ["SAM"],
        "specific": []
    },
    "objectives": {
        "primary": "Suppress enemy air defenses",
        "secondary": [],
        "count": "auto"
    },
    "support": {
        "awacs": "auto",
        "tanker": "auto",
        "jtac": False
    }
}
```

**Methods**:
- Regex patterns for common mission types
- Aircraft type matching against known types
- Theater keyword detection
- Time/weather parsing
- Threat level classification

---

### 2. Mission Designer (`pipeline/mission_designer.py`)

**Purpose**: Transform parameters into concrete mission structure with balanced threats and objectives

**Input**: Parsed intent parameters (from Intent Parser)

**Output**:
```python
{
    "template": "pg_clean.miz",
    "blue_forces": {
        "player_flight": {
            "template": "F16_SEAD_4ship",
            "customizations": {...}
        },
        "awacs": {...},
        "tanker": {...}
    },
    "red_forces": {
        "sam_sites": [
            {"template": "SA10_battalion", "position": (x1, y1)},
            {"template": "SA6_battery", "position": (x2, y2)},
            ...
        ],
        "cap_flights": [...]
    },
    "objectives": [...],
    "randomization": {...},
    "lua_scripts": [
        "spawning/random-spawn-pools.lua",
        "ai-behavior/sam-ambush.lua",
        ...
    ],
    "briefing": "..."
}
```

**Responsibilities**:
- Select appropriate template mission for theater
- Choose unit templates based on mission type
- Balance difficulty (threat count, types, positioning)
- Select Lua scripts for dynamics
- Generate briefing text
- Configure randomization parameters

**Mission Design Doctrines** (see `templates/missions/*.yaml`):
- **SEAD**: Multiple SAM sites, limited CAP, tanker required
- **CAP**: Enemy fighters, interceptor role, fuel management critical
- **Strike**: Ground targets, heavy AAA, escort fighters optional
- **Escort**: Protect bombers/transports, threat variety

---

### 3. Mission Builder (`pipeline/mission_builder.py`)

**Purpose**: Transform mission structure into actual .miz file using miz-modifier operations

**Input**: Mission structure (from Mission Designer)

**Output**: Modified .miz file with all groups, waypoints, and settings applied

**Process**:
```python
def build_mission(mission_structure, output_path):
    # 1. Load template
    parser = MizParser(get_template_path(mission_structure["template"]))
    parser.extract()
    content = parser.get_mission_content()

    # 2. Add blue forces
    for group_name, group_config in mission_structure["blue_forces"].items():
        template = load_unit_template(group_config["template"])
        group_data = apply_customizations(template, group_config["customizations"])
        content = add_group(content, "blue", group_data)

    # 3. Add red forces
    for threat_category, threats in mission_structure["red_forces"].items():
        for threat in threats:
            template = load_unit_template(threat["template"])
            # Add positional randomization if enabled
            group_data = create_group_from_template(threat)
            content = add_group(content, "red", group_data)

    # 4. Set mission parameters
    content = set_mission_time(content, mission_structure["time"])
    content = set_weather(content, mission_structure["weather"])
    content = set_briefing(content, mission_structure["briefing"])

    # 5. Package and return
    parser.write_mission_content(content)
    parser.repackage(output_path)

    return output_path
```

**Dependencies**:
- `miz_modifier.groups.add` - Add groups
- `miz_modifier.waypoints.add` - Add waypoints
- `miz_modifier.units.modify` - Set loadouts, positions
- Template system (unit templates, mission templates)

---

### 4. Lua Injector (`lua_injector.py`)

**Purpose**: Inject dynamic Lua scripts from `lua-library/` into the mission file

**Input**:
- Mission structure (specifies which scripts to inject)
- Path to modified .miz file

**Output**: .miz file with Lua scripts injected as triggers

**Process**:
```python
def inject_lua_scripts(miz_path, script_list, config):
    parser = MizParser(miz_path)
    parser.extract()
    content = parser.get_mission_content()

    for script_path in script_list:
        # Read Lua script
        script_content = read_lua_script(f"lua-library/{script_path}")

        # Configure script with mission-specific parameters
        configured_script = configure_script(script_content, config)

        # Inject as DO SCRIPT or trigger
        content = add_trigger_script(content, configured_script)

    parser.write_mission_content(content)
    parser.repackage(miz_path)
```

**Common Scripts Injected**:
- `spawning/random-spawn-pools.lua` - Randomize enemy positions
- `ai-behavior/sam-ambush.lua` - SAMs go HOT/DARK dynamically
- `communications/bda-reporting.lua` - Bomb damage assessment messages
- `objectives/objective-tracker.lua` - Track objective completion
- `mission-state/phase-manager.lua` - Multi-phase missions
- `support/fuel-monitor.lua` - Low fuel warnings

---

### 5. Validator (`pipeline/validator.py`)

**Purpose**: Verify mission integrity before delivery to user

**Checks**:

1. **Unique IDs**: All group and unit IDs are unique
2. **Valid Coordinates**: All positions are within map bounds
3. **No Overlapping Spawns**: Units don't spawn on top of each other
4. **Valid Types**: All aircraft/vehicle types exist in DCS
5. **Lua Syntax**: Injected scripts are syntactically valid
6. **Coalition Balance**: Mission has both blue and red forces
7. **Spawn Locations**: Aircraft spawn at valid airbases/coordinates

**Process**:
```python
def validate_mission(miz_path):
    parser = MizParser(miz_path)
    parser.extract()
    content = parser.get_mission_content()

    errors = []
    warnings = []

    # Run all validation checks
    errors.extend(check_unique_ids(content))
    errors.extend(check_valid_coordinates(content))
    errors.extend(check_lua_syntax(content))
    warnings.extend(check_spawn_locations(content))
    warnings.extend(check_coalition_balance(content))

    return {
        "valid": len(errors) == 0,
        "errors": errors,
        "warnings": warnings
    }
```

---

### 6. Orchestrator (`pipeline/orchestrator.py`)

**Purpose**: Main entry point that coordinates all pipeline components

**Usage**:
```python
from mission_generation.pipeline.orchestrator import generate_mission

result = generate_mission(
    prompt="Create a 4-ship F-16 SEAD mission in the Persian Gulf at dawn",
    output_dir="miz-files/output/"
)

if result["success"]:
    print(f"Mission created: {result['miz_path']}")
    print(f"Briefing: {result['briefing']}")
else:
    print(f"Error: {result['error']}")
```

**Process**:
```python
def generate_mission(prompt, output_dir):
    # 1. Parse intent
    intent = intent_parser.parse(prompt)

    # 2. Design mission
    structure = mission_designer.design(intent)

    # 3. Build .miz file
    miz_path = mission_builder.build(structure, output_dir)

    # 4. Inject Lua scripts
    lua_injector.inject(miz_path, structure["lua_scripts"], structure["randomization"])

    # 5. Validate
    validation = validator.validate(miz_path)

    if not validation["valid"]:
        return {
            "success": False,
            "error": "Validation failed",
            "details": validation["errors"]
        }

    return {
        "success": True,
        "miz_path": miz_path,
        "briefing": structure["briefing"],
        "warnings": validation["warnings"]
    }
```

---

## Unit Templates (`templates/units/`)

Unit templates define reusable group compositions in YAML format.

### Example: F-16 SEAD Flight

`templates/units/blue_air.yaml`:

```yaml
F16_SEAD_4ship:
  name: "Viper {id}"
  country: "USA"
  category: "plane"
  units:
    - type: "F-16C_50"
      callsign: "Viper 1-1"
      position: {offset: [0, 0]}        # Leader
      loadout: "SEAD_Standard"
      fuel: 1.0
    - type: "F-16C_50"
      callsign: "Viper 1-2"
      position: {offset: [50, -50]}     # Wingman
      loadout: "SEAD_Standard"
      fuel: 1.0
    - type: "F-16C_50"
      callsign: "Viper 2-1"
      position: {offset: [100, 0]}      # Element lead
      loadout: "SEAD_Standard"
      fuel: 1.0
    - type: "F-16C_50"
      callsign: "Viper 2-2"
      position: {offset: [150, -50]}    # Element wing
      loadout: "SEAD_Standard"
      fuel: 1.0
  waypoints:
    - action: "From Runway"
      position: {airbase: "auto"}
    - action: "Turning Point"
      position: {offset: [50000, 0]}
      altitude: 8000
      speed: 250
    - action: "Turning Point"
      position: {offset: [100000, 50000]}
      altitude: 8000
      speed: 250
  frequency: 251.0
  modulation: 0  # AM
```

**Template Variables**:
- `{id}` - Auto-incremented group number
- `{callsign}` - Generated callsign
- `offset` - Relative position (resolved at build time)
- `airbase: "auto"` - Choose appropriate airbase for theater

---

## Mission Type Definitions (`templates/missions/`)

Mission type definitions specify doctrine, typical threats, and objectives for each mission type.

### Example: SEAD Mission

`templates/missions/sead.yaml`:

```yaml
mission_type: "SEAD"
full_name: "Suppression of Enemy Air Defenses"

description: |
  Suppress enemy air defense systems to enable follow-on strikes.
  Primary targets are radar-guided SAM sites.

typical_aircraft:
  - "F-16C_50"
  - "F/A-18C_hornet"
  - "F-15E"
  - "AV8BNA"

loadouts:
  F-16C_50: "SEAD_Standard"  # HARMs, AIM-120s, AIM-9s
  F/A-18C_hornet: "SEAD_Standard"
  F-15E: "SEAD_AGM88"
  AV8BNA: "SEAD_Light"

threat_composition:
  light:
    sam_sites: 2-3
    types: ["SA-3", "SA-6"]
    cap_flights: 0
  moderate:
    sam_sites: 4-6
    types: ["SA-6", "SA-10", "SA-15"]
    cap_flights: 1
  heavy:
    sam_sites: 8-12
    types: ["SA-10", "SA-20", "SA-11", "SA-15"]
    cap_flights: 2-3
  overwhelming:
    sam_sites: 15+
    types: ["SA-20", "SA-21", "SA-10", "SA-11", "SA-15"]
    cap_flights: 4+

support_assets:
  awacs: required
  tanker: recommended
  jtac: optional
  escort: optional

objectives:
  primary: "Destroy or suppress {count} SAM sites"
  secondary: "Return safely to base"
  bonus: "Destroy additional threats of opportunity"

lua_scripts:
  - "spawning/random-spawn-pools.lua"
  - "ai-behavior/sam-ambush.lua"
  - "communications/bda-reporting.lua"
  - "objectives/objective-tracker.lua"

briefing_template: |
  MISSION: SEAD - Suppression of Enemy Air Defenses
  THEATER: {theater}
  TIME: {time}
  WEATHER: {weather}

  SITUATION:
  Enemy air defenses in the {theater} are preventing coalition air operations.
  Intelligence has identified {threat_count} active SAM sites in the target area.

  MISSION:
  You are tasked with suppressing enemy air defenses using anti-radiation missiles.
  Primary targets: {primary_targets}

  THREATS:
  - {threat_level} SAM presence ({threat_types})
  - Possible fighter CAP

  SUPPORT:
  - AWACS: {awacs_callsign} on {awacs_freq}
  - Tanker: {tanker_callsign} at {tanker_location}

  WEATHER: {weather_description}

  COMMUNICATIONS:
  - Tower: {tower_freq}
  - Flight: {flight_freq}
  - AWACS: {awacs_freq}
```

---

## Template Mission Files (`miz-files/templates/`)

Clean template .miz files for each theater, used as starting points for mission generation.

**Requirements**:
- Minimal content (just airbases and geography)
- No pre-placed units (except maybe an AWACS reference)
- Correct coalition setup
- Default weather and time (will be overridden)

**Theaters**:
- `pg_clean.miz` - Persian Gulf
- `syria_clean.miz` - Syria
- `caucasus_clean.miz` - Caucasus
- `nevada_clean.miz` - Nevada Test and Training Range
- `marianas_clean.miz` - Marianas

**Future**: Auto-generate templates using DCS Mission Editor headless mode or pydcs

---

## Example Usage

### Simple SEAD Mission

```python
from mission_generation.pipeline.orchestrator import generate_mission

result = generate_mission(
    prompt="Create a SEAD mission in Syria with 2 F/A-18s at dusk",
    output_dir="miz-files/output/"
)

print(result["miz_path"])  # Path to generated .miz
```

### Custom Mission Parameters

```python
from mission_generation.pipeline.intent_parser import MissionIntent
from mission_generation.pipeline.orchestrator import generate_mission_from_intent

intent = MissionIntent(
    mission_type="CAP",
    theater="PersianGulf",
    player={
        "aircraft": "F-14B",
        "count": 2,
        "loadout": "CAP_Heavy",
        "airbase": "Carrier"
    },
    threats={
        "level": "heavy",
        "types": ["CAP", "INTERCEPT"]
    },
    time_of_day="dawn",
    weather="cloudy"
)

result = generate_mission_from_intent(intent, "miz-files/output/")
```

---

## Development Roadmap

### Phase 1: Foundation (Current)

- [x] Directory structure
- [ ] README and architecture documentation
- [ ] Unit template YAML format and examples
- [ ] Mission type definition YAML format

### Phase 2: Core Components

- [ ] Intent parser implementation
- [ ] Mission designer implementation
- [ ] Mission builder implementation
- [ ] Basic template loading system

### Phase 3: Advanced Features

- [ ] Lua injector implementation
- [ ] Validator implementation
- [ ] Orchestrator with error handling
- [ ] Template mission files for all theaters

### Phase 4: Polish and Testing

- [ ] End-to-end testing
- [ ] Balance tuning (threat counts, positions)
- [ ] Briefing generation
- [ ] User feedback and iteration

### Phase 5: MCP Server Integration

- [ ] Expose pipeline through MCP server
- [ ] Natural language interface via Claude
- [ ] Web UI for mission generation (optional)

---

## Testing

### Unit Tests

```bash
cd mission-generation
python -m pytest tests/
```

### Integration Tests

```python
# Test full pipeline
from mission_generation.pipeline.orchestrator import generate_mission

result = generate_mission(
    prompt="Create a test mission in Caucasus",
    output_dir="miz-files/test/"
)

assert result["success"]
assert os.path.exists(result["miz_path"])

# Load in DCS and verify
# Manual testing required
```

### DCS Testing

1. Generate mission using pipeline
2. Load `.miz` file in DCS Mission Editor
3. Check for errors in Mission Editor
4. Start mission and fly
5. Check `dcs.log` for Lua errors
6. Verify objectives, briefing, and dynamics work correctly

---

## Troubleshooting

### Mission Won't Load in DCS

- Check validation errors: `validator.validate(miz_path)`
- Verify Lua syntax: check `dcs.log` for script errors
- Ensure all unit types are valid for installed DCS modules

### Unbalanced Difficulty

- Adjust threat counts in mission type YAML
- Modify threat positioning in mission designer
- Tune adaptive AI settings in Lua scripts

### Missing Support Assets

- Check support asset templates exist
- Verify airbase has correct coalition
- Check tanker/AWACS waypoints are valid

---

## See Also

- [MCP Light Documentation](../knowledge/mcp-light/README.md) - Available modification operations
- [miz-modifier Library](../miz-modifier/architecture.md) - Low-level .miz manipulation
- [Lua Library](../lua-library/README.md) - Dynamic mission scripts
- [MIZ File Structure](../knowledge/miz-file-manipulation.md) - Understanding .miz files
