# Mission Generation Pipeline - Quick Start

## For Users (When Complete)

### Generate a Mission

```python
from mission_generation.pipeline import generate_mission

result = generate_mission(
    "Create a 4-ship F-16 SEAD mission in Persian Gulf at dawn with heavy SAM threats"
)

if result["success"]:
    print(f"Mission file: {result['miz_path']}")
    print(f"\n{result['briefing']}")
else:
    print(f"Error: {result['error']}")
```

### Supported Prompts (SEAD Only - MVP)

```
"Create a 4-ship F-16 SEAD mission in Persian Gulf at dawn with heavy SAM threats"
"2 F/A-18s SEAD in Syria at night, light threats"
"SEAD mission with 2 Vipers in Caucasus, moderate SAMs, need tanker"
```

**Keywords Recognized:**
- **Aircraft**: F-16/Viper, F/A-18/Hornet, F-15E
- **Count**: "2-ship", "4-ship", "2 aircraft"
- **Theater**: Persian Gulf/PG, Syria, Caucasus, Nevada, Marianas
- **Time**: dawn/sunrise, dusk/sunset, night, day/noon
- **Threat**: light, moderate, heavy, overwhelming
- **Support**: awacs, tanker, jtac, escort

## For Developers

### Project Structure

```
mission-generation/
├── pipeline/               # Core pipeline components
│   ├── intent_parser.py   # Natural language → structured intent
│   ├── mission_designer.py # Intent → mission structure
│   ├── mission_builder.py # Structure → .miz file
│   └── orchestrator.py    # Main API entry point
├── templates/             # Content templates
│   ├── missions/          # Mission type definitions (YAML)
│   └── units/             # Unit templates (YAML)
├── test_mvp.py           # Test suite
└── README.md             # Full documentation
```

### Component Overview

#### 1. Intent Parser
Converts natural language to structured parameters.

```python
from pipeline import parse

intent = parse("4-ship F-16 SEAD in PG at dawn, heavy threats")
# Returns: MissionIntent object
```

#### 2. Mission Designer
Transforms intent into concrete mission structure.

```python
from pipeline import design

structure = design(intent)
# Returns: Dict with templates, positions, briefing, etc.
```

#### 3. Mission Builder
Generates actual .miz file using miz-modifier.

```python
from pipeline import build

miz_path = build(structure, output_dir="miz-files/output/")
# Returns: Path to generated .miz file
```

#### 4. Orchestrator
Chains everything together.

```python
from pipeline import generate_mission

result = generate_mission(prompt, output_dir)
# Returns: {"success": bool, "miz_path": str, "briefing": str, ...}
```

### Testing

```bash
# Run full test suite
python test_mvp.py

# Test individual components
python -c "from pipeline import parse; print(parse('SEAD in PG').to_dict())"
```

### Adding New Content

#### Add New Aircraft

Edit `templates/units/blue_air.yaml`:

```yaml
F14_SEAD_2ship:
  name: "Tomcat {id}"
  country: "USA"
  category: "plane"
  units:
    - type: "F-14B"
      callsign: "Tomcat {id}-1"
      position: {offset: [0, 0]}
      loadout: "SEAD_Standard"
      fuel: 1.0
      skill: "Player"
    # ... more units
  waypoints:
    - action: "From Runway"
      position: {airbase: "auto"}
    # ... more waypoints
```

Update `mission_designer.py` to recognize new aircraft.

#### Add New SAM Sites

Edit `templates/units/sam_sites.yaml`:

```yaml
SA21_Growler_Battalion:
  name: "SA-21 {id}"
  country: "Russia"
  category: "vehicle"
  threat_level: "Extreme"
  max_range: "120 NM"
  units:
    # ... unit definitions
```

Reference in `templates/missions/sead.yaml` threat compositions.

#### Add New Mission Type

1. Create `templates/missions/cap.yaml`
2. Implement parser support in `intent_parser.py`
3. Update `mission_designer.py` to handle CAP-specific logic
4. Add CAP unit templates to `templates/units/`

### Key Files to Understand

1. **README.md** - Complete architecture documentation
2. **MVP-STATUS.md** - Current status and what's missing
3. **templates/missions/sead.yaml** - Mission type definition example
4. **pipeline/orchestrator.py** - API entry point

### Dependencies

**Current:**
- Python 3.10+
- PyYAML

**Required for Full Functionality:**
- miz-modifier library (in development)
- Template .miz files
- DCS World (for testing generated missions)

### Common Tasks

**Run the orchestrator from command line:**
```bash
cd mission-generation/pipeline
python orchestrator.py "Create a 4-ship F-16 SEAD mission in PG"
```

**Debug intent parsing:**
```python
from pipeline import parse
intent = parse("Your prompt here")
print(intent.to_dict())
```

**Debug mission design:**
```python
from pipeline import parse, design
intent = parse("Your prompt here")
structure = design(intent)

print(f"SAMs: {len(structure['red_forces']['sam_sites'])}")
print(f"Briefing:\n{structure['briefing']}")
```

**Load a template:**
```python
import yaml
with open("templates/missions/sead.yaml") as f:
    mission_def = yaml.safe_load(f)
print(mission_def['threat_composition']['heavy'])
```

## Integration with MCP Server

When ready, expose through MCP:

```python
# In MCP server
@mcp.tool()
def create_mission(prompt: str) -> str:
    """Generate DCS mission from natural language"""
    result = generate_mission(prompt)
    if result["success"]:
        return f"Mission created: {result['miz_path']}"
    else:
        return f"Error: {result['error']}"
```

## Troubleshooting

**Import errors:**
- Ensure you're in the correct directory
- Check Python path includes DMS root
- Verify all `__init__.py` files exist

**YAML errors:**
- Validate YAML syntax (use online validator)
- Check indentation (use spaces, not tabs)
- Ensure all required fields are present

**Template not found:**
- Verify file exists in `templates/units/` or `templates/missions/`
- Check file name matches exactly (case-sensitive)

## Next Steps

1. Read **README.md** for full architecture
2. Check **MVP-STATUS.md** for implementation status
3. Run **test_mvp.py** to see pipeline in action
4. Review template files to understand content structure
5. Read **knowledge/miz-file-manipulation.md** for .miz internals

## Questions?

- Check **README.md** for comprehensive documentation
- Review **MVP-STATUS.md** for current status
- Look at test examples in **test_mvp.py**
- Examine template files for content examples
