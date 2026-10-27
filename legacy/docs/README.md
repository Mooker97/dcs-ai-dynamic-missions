# DCS Dynamic Mission System

An AI-powered mission generation system that transforms simple DCS mission templates and natural language prompts into complete, playable dynamic missions.

## Vision

Transform DCS mission creation from a multi-hour technical process into a 30-second conversation.

**Example:**
```
User: "I have a template with a CAP zone and player spawn.
       Generate a dynamic CAP mission with random enemy fighters and SAM threats"

→ Complete playable .miz file with randomized enemies, dynamic behaviors, ready to fly
```

## How It Works

### 1. You Provide a Simple Template
- Place player spawn point(s)
- Define trigger zones (CAP_ZONE, STRIKE_AREA, etc.)
- Add template units (example aircraft/SAMs to duplicate)
- Set basic mission parameters (time, weather)

### 2. Describe Your Mission
```
"Generate a CAP mission with 6-10 random enemy fighters
and 2-3 SAM sites that ambush when players get close"
```

### 3. Get a Playable Dynamic Mission
- Units spawn randomly in defined zones
- Dynamic Lua scripts create unpredictable gameplay
- Each playthrough is different
- Ready to load in DCS World

## Project Status

**Phase 1: Foundation (IN PROGRESS)**
- ✅ Architecture designed (MizParser-based)
- ✅ Project structure established
- ⏳ Core library implementation (`miz-modifier/`)
- ⏳ MCP server development
- 📍 **Current Focus**: Completing groups and coordinates modules

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│              USER PROVIDES TEMPLATE                      │
│  • .miz file with zones, player spawn, template units   │
│  • Natural language mission prompt                      │
└────────────────┬────────────────────────────────────────┘
                 │
                 ↓
┌─────────────────────────────────────────────────────────┐
│              CLAUDE AI (via MCP)                         │
│  • Analyzes template structure                          │
│  • Interprets mission prompt                            │
│  • Designs mission (unit count, behaviors, objectives)  │
│  • Orchestrates generation pipeline                     │
└────────────────┬────────────────────────────────────────┘
                 │
                 ↓
┌─────────────────────────────────────────────────────────┐
│              MCP SERVER TOOLS                            │
│  • read_template_mission() - Parse template             │
│  • add_dynamic_units() - Spawn randomized units         │
│  • inject_lua_scripts() - Add dynamic behaviors         │
│  • configure_triggers() - Mission logic                 │
│  • validate_mission() - Quality checks                  │
└────────────────┬────────────────────────────────────────┘
                 │
                 ↓
┌─────────────────────────────────────────────────────────┐
│          MIZ-FILE-MODIFICATION LIBRARY                   │
│  • MizParser (Extract → Modify → Repackage)            │
│  • Regex-based Lua manipulation                         │
│  • No DCS installation required                         │
│  • Groups, Units, Waypoints, Coordinates modules        │
└────────────────┬────────────────────────────────────────┘
                 │
                 ↓
┌─────────────────────────────────────────────────────────┐
│            PLAYABLE DYNAMIC MISSION                      │
│  • Complete .miz file ready for DCS World              │
│  • Randomized unit spawns                               │
│  • Dynamic Lua scripts embedded                         │
│  • No two playthroughs identical                        │
└─────────────────────────────────────────────────────────┘
```

## Project Structure

```
DMS/
├── miz-modifier/      # Core library (MizParser-based)
│   ├── parsing/               # MizParser (extract/repackage)
│   ├── groups/                # Group operations (add/remove/modify)
│   ├── units/                 # Unit operations
│   ├── waypoints/             # Waypoint operations
│   ├── coordinates/           # Coordinate transformations
│   └── utils/                 # ID manager, patterns, validation
├── mcp_server/                # MCP server implementation (planned)
│   ├── server.py             # MCP server main
│   ├── tools/                # MCP tool implementations
│   └── config.py             # Server configuration
├── lua-library/              # DMS dynamic scripting system (planned)
│   ├── DMS.Settings.lua      # Debug configuration
│   ├── DMS.SpawnPool.lua     # Random spawning
│   ├── DMS.FogOfWar.lua      # Hidden unit activation
│   ├── DMS.SAMAmbush.lua     # SAM behavior
│   └── ...                   # Additional modules
├── miz-files/                # Mission files
│   ├── templates/            # Template .miz files
│   ├── input/                # User-provided templates
│   └── output/               # Generated missions
├── knowledge/                # Documentation
│   ├── miz-file-manipulation.md  # Complete .miz reference
│   └── ...
├── claudedocs/               # Technical analysis
├── CLAUDE.md                 # Developer guidance
├── MVP-Plan.md               # MVP specification
└── README.md                 # This file
```

## Installation (Phase 1)

### Prerequisites

```bash
# Python 3.10+
python --version

# Optional: Coordinate transformation library
pip install pyproj>=3.7.0
```

### Setup

```bash
# 1. Clone repository
git clone https://github.com/yourusername/DMS.git
cd DMS

# 2. Install dependencies (optional)
pip install pyproj>=3.7.0

# 3. Create mission directories
mkdir -p miz-files/{templates,input,output}

# 4. Test core library
python -c "from miz-modifier.parsing.miz_parser import MizParser; print('✅ Library ready')"
```

### MCP Server Setup (When Available)

```bash
# Configure Claude Desktop
# Edit: %APPDATA%\Claude\claude_desktop_config.json
{
  "mcpServers": {
    "dcs-mission-generator": {
      "command": "python",
      "args": ["C:/path/to/DMS/mcp_server/server.py"]
    }
  }
}

# Restart Claude Desktop
```

## Features

### Phase 1: Foundation (Current)
- ✅ MizParser-based architecture (no DCS installation required)
- ✅ Project structure and documentation
- ⏳ Groups module (add/remove/duplicate/modify)
- ⏳ Coordinates module (extract/transform/randomize)
- ⏳ Units module
- ⏳ Waypoints module

### Phase 2: MCP Server
- [ ] MCP server implementation
- [ ] Template analysis tool
- [ ] Unit spawning tool
- [ ] Lua script injection tool
- [ ] Mission validation tool
- [ ] Claude integration

### Phase 3: Unit Spawning
- [ ] Template extraction system
- [ ] Position randomization in zones
- [ ] Unit duplication with variation
- [ ] ID management
- [ ] Coordinate transformations

### Phase 4: Dynamic Scripts
- [ ] DMS Lua library integration
- [ ] SpawnPool system
- [ ] Fog of War mechanics
- [ ] SAM ambush behaviors
- [ ] Dynamic reinforcements
- [ ] Debug logging system

### Phase 5: Mission Types
- [ ] CAP mission generator
- [ ] SEAD mission generator
- [ ] Strike mission generator
- [ ] Mission briefing generation
- [ ] Objective system

### Phase 6: Polish & Testing
- [ ] Comprehensive validation
- [ ] DCS.log integration
- [ ] Mission testing suite
- [ ] Error recovery
- [ ] Documentation

## Usage Examples

### Current (Library Development)

```python
from miz-modifier.parsing.miz_parser import MizParser
from miz-modifier.groups.remove import remove_groups_by_type

# Extract and modify mission
parser = MizParser("miz-files/input/mission.miz")
parser.extract()

# Get and modify content
content = parser.get_mission_content()
modified = remove_groups_by_type(content, ["ship"])

# Save changes
parser.write_mission_content(modified)
parser.repackage("miz-files/output/modified.miz")
```

### Future (MCP Server)

```
User: "Create a CAP mission using carrier_template.miz with 8 random
       enemy fighters and 2 SAM sites that ambush players"

Claude (via MCP):
1. Analyzes carrier_template.miz
   → Found: CAP_ZONE, TEMPLATE_MIG29, TEMPLATE_SA10, player spawn

2. Designs mission
   → 8x MiG-29s random positions in CAP_ZONE
   → 2x SA-10 sites with ambush behavior
   → Proximity triggers for SAM activation

3. Generates mission
   → Spawns units with randomization
   → Injects DMS.SAMAmbush + DMS.Proximity scripts
   → Configures mission triggers

Result: ✅ missions/output/cap_carrier_20260101.miz
Ready to fly! Each playthrough will be different.
```

## Technical Details

### MizParser Architecture

**Key Concept**: .miz files are ZIP archives containing Lua tables

**Workflow**:
1. **Extract**: Unzip .miz file
2. **Read**: Load mission file (Lua table as text)
3. **Modify**: Use regex patterns to manipulate Lua structures
4. **Write**: Save modified content
5. **Repackage**: Zip back to .miz

**Advantages**:
- ✅ No DCS installation required
- ✅ Pure Python (standard library only)
- ✅ Fast and lightweight
- ✅ Direct Lua manipulation
- ✅ Regex-based pattern matching

### Dynamic Lua Scripting

**DMS Library Modules** (Planned):
- `DMS.Settings` - Debug configuration
- `DMS.SpawnPool` - Random unit spawning at mission start
- `DMS.FogOfWar` - Progressive unit activation
- `DMS.SAMAmbush` - SAM sites going HOT when players approach
- `DMS.Reinforcements` - Triggered reinforcement waves
- `DMS.Objectives` - Dynamic objective system
- `DMS.BDA` - Battle Damage Assessment
- `DMS.Proximity` - Player proximity detection

**Debug Logging**:
```lua
DMS.Settings.configure({ debug = true })
-- Logs appear in: %USERPROFILE%\Saved Games\DCS\Logs\dcs.log
```

## Development Roadmap

See [MVP-Plan.md](./MVP-Plan.md) for complete implementation plan.

### Milestones

- **Week 1-2**: ✅ Foundation (MizParser, project structure)
- **Week 3-4**: ⏳ Core library (groups, coordinates, units)
- **Week 5-6**: MCP server implementation
- **Week 7-8**: Unit spawning system
- **Week 9-10**: Dynamic Lua scripts
- **Week 11-12**: Mission types and testing

## Technology Stack

**Core**:
- Python 3.10+ (standard library)
- pyproj 3.7.0+ (optional, for coordinates)
- MCP protocol (Claude integration)
- Lua scripting (DCS dynamic behaviors)

**Development**:
- Git (version control)
- DCS World (mission testing)
- Visual Studio Code (recommended)

## Resources

### Documentation
- [CLAUDE.md](./CLAUDE.md) - Developer guidance and architecture
- [MVP-Plan.md](./MVP-Plan.md) - Complete MVP specification
- [knowledge/miz-file-manipulation.md](./knowledge/miz-file-manipulation.md) - .miz file structure reference

### DCS Resources
- [DCS Stores/Weapons List](https://www.airgoons.com/w/DCS_Reference/Stores_List) - Complete weapon reference
- [DCS Mission Structure Wiki](https://wiki.hoggitworld.com/view/Miz_mission_structure) - Mission file format

### DCS Log Files
- Stable: `%USERPROFILE%\Saved Games\DCS\Logs\dcs.log`
- Open Beta: `%USERPROFILE%\Saved Games\DCS.openbeta\Logs\dcs.log`

## Contributing

This project is currently in active development (Phase 1). Contributions welcome once core library is stable.

**Development Process**:
1. Read [CLAUDE.md](./CLAUDE.md) for project guidelines
2. Check current phase in [MVP-Plan.md](./MVP-Plan.md)
3. Follow MizParser patterns from existing modules
4. Test modifications in DCS World before committing

## Support

- **Issues**: GitHub Issues for bug reports
- **Discussions**: GitHub Discussions for feature requests
- **Discord**: Coming after MVP completion

## License

TBD

---

**Let's transform DCS mission creation!** 🚀

*Current Status: Phase 1 (Foundation) - Building core library*
*Last Updated: 2026-01-01*
