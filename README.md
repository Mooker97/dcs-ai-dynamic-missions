# DCS Dynamic Mission System

An AI-powered DCS mission generation system that transforms natural language prompts into complete, playable mission files.

## Vision

Transform DCS mission creation from a multi-hour technical process into a 30-second conversation.

**Example:**
```
"Create a co-op SEAD mission for F-16 and F-15C on Persian Gulf"
→ Complete .miz file, ready to fly
```

## Project Status

**Phase 1: Local Development System (IN PROGRESS)**
- Building MCP server for mission generation
- Target: Working prototype

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│                     USER INTERFACE                       │
│  Phase 1: Claude Desktop (MCP)                          │
│  Phase 2: Standalone Web App + API                      │
└────────────────┬────────────────────────────────────────┘
                 │
                 ↓
┌─────────────────────────────────────────────────────────┐
│              CLAUDE AI (Orchestration)                   │
│  • Understands user intent                              │
│  • Designs mission structure                            │
│  • Calls appropriate tools                              │
└────────────────┬────────────────────────────────────────┘
                 │
                 ↓
┌─────────────────────────────────────────────────────────┐
│                  MCP SERVER LAYER                        │
│  • Mission Generator MCP (creates .miz files)           │
│  • Lua Scripting Library (dynamic content)              │
│  • File management & validation                         │
└────────────────┬────────────────────────────────────────┘
                 │
                 ↓
┌─────────────────────────────────────────────────────────┐
│                   OUTPUT LAYER                           │
│  Phase 1: Local filesystem                              │
│  Phase 2: S3 bucket + CDN delivery                      │
└─────────────────────────────────────────────────────────┘
```

## Project Structure

```
dcs-dynamic-missions/
├── mcp-server/           # Mission generator MCP
│   ├── src/             # Source code
│   ├── tests/           # Unit tests
│   └── requirements.txt
├── lua-library/         # Dynamic scripting system
│   ├── core/           # Core functionality
│   ├── spawners/       # Unit spawning
│   ├── randomizers/    # Randomization
│   └── config/         # Configuration
├── missions/            # Generated missions output
├── docs/               # Documentation
└── README.md
```

## Installation (Phase 1)

```bash
# 1. Clone repository
git clone https://github.com/yourusername/dcs-dynamic-missions.git
cd dcs-dynamic-missions

# 2. Set up MCP server
cd mcp-server
python -m venv venv
venv\Scripts\activate  # Windows
pip install -r requirements.txt

# 3. Configure Claude Desktop
# Edit: %APPDATA%\Claude\claude_desktop_config.json
{
  "mcpServers": {
    "dcs-mission-generator": {
      "command": "python",
      "args": ["C:/path/to/dcs-dynamic-missions/mcp-server/src/server.py"]
    }
  }
}

# 4. Restart Claude Desktop

# 5. Test in Claude
"Create a test mission for F-16 on Caucasus"
```

## Features

### Phase 1: Local MCP System
- ✅ Architecture design
- ⏳ MCP server implementation
- ⏳ Basic mission generation
- ⏳ Unit templates
- ⏳ Lua scripting integration
- ⏳ Mission validation

### Phase 2: Web Application (Future)
- Web-based mission builder
- User accounts and authentication
- Mission marketplace
- API access
- Cloud storage

## Usage Examples

**Simple SEAD Mission:**
```
User: "Create a SEAD mission for F-16 on Caucasus, medium difficulty"

Result:
✅ Mission created: missions/sead_caucasus_20241208.miz
- Player: F-16C at Kutaisi
- Targets: 3x SAM sites (SA-6, SA-2, SA-11)
- Threats: 2x MiG-29 (spawn at 15 min)
- Difficulty: Medium
```

**Co-op Mission:**
```
User: "Make a co-op escort mission. F-16 and F-15C protecting B-1B bombers on Persian Gulf"

Result:
✅ Mission created: missions/escort_persian_gulf_20241208.miz
- Player 1: F-16C (close escort)
- Player 2: F-15C (high CAP)
- Protected: 2x B-1B bombers
- Threats: 3 waves of MiG-29s and Su-27s
```

## Development Roadmap

### Phase 1.0: MVP - **Current**
- Implement MCP server
- Basic mission generation
- Unit templates
- Test with Claude Desktop

### Phase 1.1: Enhanced Local System
- Complete all mission types
- Lua library integration
- Dynamic spawning
- Mission modification tools

### Phase 2.0: Web Application
- Web interface
- User authentication
- Cloud storage
- Payment system

## Technology Stack

**Phase 1:**
- Python 3.10+
- MCP protocol
- Lua scripting
- DCS World integration

**Phase 2:**
- Frontend: React + Next.js + TailwindCSS
- Backend: FastAPI + PostgreSQL + Redis
- AI: Anthropic Claude API
- Infrastructure: AWS + S3 + CloudFront

## Contributing

This is currently in active development. Contributions welcome once Phase 1 is complete.

## License

TBD

## Support

- GitHub Issues for bug reports
- Discord community (coming soon)

## Roadmap

See [SpecSheet.md](./SpecSheet.md) for complete product specification and roadmap.

---

**Let's transform DCS mission creation!** 🚀
