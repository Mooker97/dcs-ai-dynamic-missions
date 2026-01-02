# DMS MCP Server - MVP Plan

## Vision

Transform simple .miz template files into complete, playable dynamic missions through natural language prompts. The user provides a basic mission shell with foundational elements (trigger zones, player spawn, template units), describes their desired mission in natural language, and receives a fully functional dynamic mission ready to fly.

**Target Experience**: "I have a template with a CAP zone and player spawn. Generate a dynamic CAP mission with random enemy fighters and SAM threats" → Complete playable mission in 30 seconds.

---

## Core Functionality

### Input Requirements

**Template .miz File Must Include**:
- ✅ Player spawn point(s) - Aircraft with player slots configured
- ✅ Trigger zones - Named zones defining operational areas (e.g., "CAP_ZONE", "STRIKE_AREA", "SAM_BELT")
- ✅ Template units - Example units that define spawn templates (e.g., "TEMPLATE_MIG29", "TEMPLATE_SA10")
- ✅ Basic mission parameters - Time, weather, coalitions configured

**Mission Prompt Examples**:
- "Generate a CAP mission with 4-8 random enemy fighters and ground SAM threats"
- "Create a SEAD mission with SA-10 and SA-15 SAM sites that go cold when attacked"
- "Build a strike mission with random ground targets and CAP escorts"

### MCP Server Operations

**Core MCP Tools** (exposed to Claude):

1. **`generate_dynamic_mission()`**
   - **Input**: Template .miz path, mission prompt (natural language)
   - **Output**: Complete playable .miz file path
   - **Function**: Orchestrates entire mission generation pipeline

2. **`read_template_mission()`**
   - **Input**: Template .miz path
   - **Output**: JSON with trigger zones, template units, player spawns
   - **Function**: Analyzes template to understand available elements

3. **`add_dynamic_units()`**
   - **Input**: Mission file, unit templates, spawn zones, spawn parameters
   - **Output**: Modified mission with spawned units
   - **Function**: Adds randomized units based on templates and zones

4. **`inject_lua_scripts()`**
   - **Input**: Mission file, script modules to inject, configuration
   - **Output**: Modified mission with DMS Lua scripts embedded
   - **Function**: Adds dynamic scripting system to mission

5. **`configure_triggers()`**
   - **Input**: Mission file, trigger configurations
   - **Output**: Modified mission with mission logic triggers
   - **Function**: Sets up mission start, objectives, end conditions

6. **`validate_mission()`**
   - **Input**: Generated .miz path
   - **Output**: Validation report (structural errors, missing elements)
   - **Function**: Checks mission integrity before delivery

---

## Mission Generation Pipeline

### Phase 1: Template Analysis
1. Extract and parse template .miz file using `MizParser`
2. Identify trigger zones and their purposes
3. Extract template unit configurations
4. Identify player spawn locations
5. Return structured data to Claude for decision-making

### Phase 2: Mission Design (Claude Orchestration)
1. Parse user's mission prompt
2. Determine mission type (CAP, SEAD, Strike, etc.)
3. Select appropriate unit templates
4. Calculate spawn quantities and locations
5. Choose dynamic behaviors (SAM ambush, reinforcements, etc.)
6. Design mission objectives and win conditions

### Phase 3: Mission Construction
1. Duplicate template units to create spawn pool
2. Randomize positions within trigger zones
3. Inject DMS Lua library modules
4. Configure dynamic behaviors (FOW, SAM ambush, spawning)
5. Add mission triggers (start, objectives, end)
6. Generate mission briefing text

### Phase 4: Validation & Delivery
1. Validate mission structure
2. Check for ID conflicts
3. Verify all zones and units exist
4. Package final .miz file
5. Return path to playable mission

---

## Technical Architecture

### MizParser Operations (Python)

**Uses**: `miz-modifier/` library with MizParser-based approach

**Key Operations**:
- Extract → Modify → Repackage workflow
- Regex-based Lua table manipulation
- No DCS installation required
- Pure Python, lightweight

**Functions**:
```python
from miz-modifier.groups.add import add_group_from_template
from miz-modifier.groups.duplicate import duplicate_group
from miz-modifier.coordinates.transform import randomize_position_in_zone
```

### Dynamic Lua Scripting System

**Modules Available**:
- `DMS.Settings` - Debug configuration
- `DMS.SpawnPool` - Random unit spawning
- `DMS.FogOfWar` - Hidden unit activation
- `DMS.SAMAmbush` - SAM sites going HOT/COLD
- `DMS.Reinforcements` - Triggered reinforcement waves
- `DMS.Objectives` - Dynamic objective system
- `DMS.BDA` - Battle Damage Assessment
- `DMS.Proximity` - Player proximity detection

**Script Injection**:
- Scripts embedded in mission file's `mapResource` section
- DO SCRIPT FILE injected via mission start triggers
- Configuration applied based on mission prompt

---

## MVP Implementation Phases

### Phase 1: Foundation (Week 1-2) ✅ IN PROGRESS
**Goal**: Core library operations functional

- ✅ MizParser implementation
- ✅ Project structure (`miz-modifier/`)
- ⏳ Core utilities (ID manager, patterns, validation)
- ⏳ Groups module (add, remove, duplicate, list)
- ⏳ Coordinates module (extract, transform, randomize)

**Deliverable**: Python library can read/modify .miz files reliably

### Phase 2: MCP Server (Week 3-4)
**Goal**: MCP server exposes tools to Claude

- [ ] MCP server implementation
- [ ] Tool definitions and schemas
- [ ] Template analysis function
- [ ] Mission validation function
- [ ] Basic mission generation pipeline

**Deliverable**: Claude can call MCP tools to analyze templates

### Phase 3: Unit Spawning (Week 5-6)
**Goal**: Generate units from templates in zones

- [ ] Template extraction system
- [ ] Unit duplication with randomization
- [ ] Position randomization within trigger zones
- [ ] Coordinate transformation utilities
- [ ] ID management for new units

**Deliverable**: Can spawn random units in defined zones

### Phase 4: Dynamic Scripts (Week 7-8)
**Goal**: Inject Lua scripts for mission dynamics

- [ ] Lua script injection system
- [ ] DMS library integration
- [ ] Configuration generation from mission prompt
- [ ] Debug logging setup
- [ ] Script validation

**Deliverable**: Missions include dynamic behaviors

### Phase 5: Mission Types (Week 9-10)
**Goal**: Support common mission types

- [ ] CAP mission generator
- [ ] SEAD mission generator
- [ ] Strike mission generator
- [ ] Mission-specific templates
- [ ] Briefing generation

**Deliverable**: Can generate 3+ mission types from prompts

### Phase 6: Polish & Testing (Week 11-12)
**Goal**: Production-ready MVP

- [ ] Comprehensive validation
- [ ] Error handling and recovery
- [ ] DCS.log integration for debugging
- [ ] Mission testing in DCS World
- [ ] Documentation and examples

**Deliverable**: Reliable mission generation for real gameplay

---

## Success Criteria

### Minimum Viable Product Must:

1. ✅ **Accept Simple Template**: User provides .miz with zones, player spawn, template units
2. ✅ **Parse Natural Language**: Claude understands mission prompts like "CAP with random enemies"
3. ✅ **Generate Playable Mission**: Output .miz loads in DCS without errors
4. ✅ **Include Dynamic Elements**: Missions use randomization, not static spawns
5. ✅ **Support Core Mission Types**: CAP, SEAD, Strike missions work reliably
6. ✅ **Validate Output**: Catches structural errors before delivery
7. ✅ **Debuggable**: Errors traceable via DCS.log and debug logging

### Quality Gates:

- **Reliability**: 90%+ generated missions load without errors
- **Playability**: Generated missions provide 15-30 min gameplay
- **Variety**: No two generations of same mission are identical
- **Performance**: Generation completes in <30 seconds
- **Debuggability**: All dynamic systems include debug logging

---

## Example Workflow

### User Interaction:

```
User: "I have a template at miz-files/input/carrier_template.miz.
       Generate a CAP mission with 6-10 enemy fighters spawning randomly
       and 2-3 SAM sites that ambush when players get close."

Claude (via MCP):
1. Call read_template_mission() → Identifies CAP_ZONE, TEMPLATE_MIG29, TEMPLATE_SA10
2. Analyze prompt → CAP mission, 6-10 fighters, 2-3 SAMs, ambush behavior
3. Call add_dynamic_units() → Spawn 8 MiG-29s in CAP_ZONE (random positions)
4. Call add_dynamic_units() → Spawn 2 SA-10 sites near CAP_ZONE
5. Call inject_lua_scripts() → Add SpawnPool, SAMAmbush, Proximity modules
6. Call configure_triggers() → Mission start, objective (destroy fighters), end conditions
7. Call validate_mission() → Check structure
8. Return complete .miz path

User: *Loads mission in DCS, flies CAP, encounters random enemies,
       SAM goes hot when approaching, completes mission*
```

---

## Technical Requirements

### Python Dependencies:
- Python 3.10+
- `pyproj>=3.7.0` (coordinate transformations)
- Standard library (zipfile, os, shutil, pathlib, re)

### DCS Requirements:
- DCS World (Stable or Open Beta)
- Write access to Saved Games mission folder
- DCS.log access for debugging

### Project Structure:
```
DMS/
├── mcp_server/              # MCP server implementation
│   ├── server.py           # MCP server main
│   ├── tools/              # MCP tool implementations
│   └── config.py           # Server configuration
├── miz-modifier/  # Core library (MizParser-based)
├── lua-library/            # Dynamic Lua scripts (DMS.*)
├── miz-files/
│   ├── templates/          # Template .miz files
│   ├── input/              # User-provided templates
│   └── output/             # Generated missions
└── tests/                  # Test suite
```

---

## Risk Mitigation

### Known Risks:

1. **Complex Mission Files**: Templates with custom scripts may break
   - **Mitigation**: Start with clean templates, validate before modification

2. **ID Conflicts**: Generated units may conflict with existing IDs
   - **Mitigation**: Robust ID manager, validation before save

3. **Coordinate Issues**: Units spawning in invalid locations (water, mountains)
   - **Mitigation**: Validate spawn zones, use zone-based randomization

4. **Lua Script Errors**: Injected scripts may have syntax errors
   - **Mitigation**: Test scripts separately, validate before injection

5. **DCS Version Changes**: DCS updates may break mission structure
   - **Mitigation**: Version-specific templates, validation checks

---

## Post-MVP Enhancements

### Phase 2 Features (Beyond MVP):
- Weather/time randomization
- AI skill level customization
- Custom loadout generation
- Waypoint generation for dynamic routing
- Voice-over briefing generation
- Multi-phase missions (sequential objectives)
- Adaptive difficulty based on player performance
- Mission rating and replay analysis

### Enterprise Features:
- Web interface for mission generation
- Mission sharing/marketplace
- AI-powered mission balancing
- Real-time mission modification during gameplay
- Multiplayer mission coordination

---

## Getting Started

### For Development:

1. **Complete Phase 1**: Finish `miz-modifier/` library
2. **Test Core Operations**: Verify groups, units, waypoints modules work
3. **Build MCP Server**: Implement tool exposure to Claude
4. **Create Test Templates**: Build 3-5 simple templates for testing
5. **Iterate**: Test generation → identify issues → fix → repeat

### For Testing:

1. Place template .miz in `miz-files/templates/`
2. Run MCP server: `python mcp_server/server.py`
3. Prompt Claude: "Generate [mission type] using [template name]"
4. Load output mission in DCS World
5. Check DCS.log for errors (enable debug logging)
6. Validate mission playability

---

## Contact & Resources

- **Architecture**: See `CLAUDE.md` for technical details
- **Documentation**: See `knowledge/miz-file-manipulation.md` for .miz structure
- **Lua Scripts**: See `lua-library/` for dynamic scripting examples
- **DCS Logs**: `%USERPROFILE%\Saved Games\DCS\Logs\dcs.log`

---

*Last Updated: 2026-01-01*
*Status: Phase 1 (Foundation) - In Progress*
