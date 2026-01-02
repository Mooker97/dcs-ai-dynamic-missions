# MCP Light JSON Schemas

This directory contains JSON Schema definitions for all DCS mission operation types.

## Purpose

These schemas define the structure and validation rules for:
- **Groups** - Complete group definitions with units and routes
- **Units** - Individual unit configurations
- **Waypoints** - Route waypoint definitions
- **Coordinates** - Position and coordinate system formats
- **Loadouts** - Weapon, fuel, and countermeasure configurations
- **Triggers** - Trigger zones and trigger rule definitions

## Schema Files

| File | Description |
|------|-------------|
| `group-schema.json` | Group structure with units, routes, and metadata |
| `unit-schema.json` | Unit properties, position, skill, and loadout |
| `waypoint-schema.json` | Waypoint position, altitude, speed, and actions |
| `coordinate-schema.json` | Cartesian, geographic, and MGRS coordinate formats |
| `loadout-schema.json` | Pylons, weapons, fuel, chaff/flare, gun ammo |
| `trigger-schema.json` | Trigger zones, rules, conditions, and actions |

## Usage

### Validation

Use these schemas to validate operation parameters before calling miz-modification functions:

```python
import json
import jsonschema

# Load schema
with open("schemas/group-schema.json") as f:
    schema = json.load(f)

# Validate group data
group_data = {
    "name": "Fighter-1",
    "coalition": "blue",
    "category": "plane",
    "units": [...]
}

try:
    jsonschema.validate(instance=group_data, schema=schema)
    print("Valid group data")
except jsonschema.ValidationError as e:
    print(f"Invalid group data: {e.message}")
```

### IDE Integration

Many IDEs support JSON Schema for autocomplete and validation:

**VS Code** (`settings.json`):
```json
{
  "json.schemas": [
    {
      "fileMatch": ["**/missions/**/groups/*.json"],
      "url": "./schemas/group-schema.json"
    },
    {
      "fileMatch": ["**/missions/**/loadouts/*.json"],
      "url": "./schemas/loadout-schema.json"
    }
  ]
}
```

## Schema Conventions

### Required vs Optional

- **Required fields**: Minimum fields needed for operation to succeed
- **Optional fields**: Additional configuration with sensible defaults

### Enum Values

String fields with limited valid values use `enum`:

```json
{
  "coalition": {
    "type": "string",
    "enum": ["blue", "red", "neutrals"]
  }
}
```

### Numeric Ranges

Numeric fields specify valid ranges:

```json
{
  "altitude": {
    "type": "number",
    "minimum": 0,
    "maximum": 20000
  }
}
```

### Referenced Definitions

Complex nested structures use `$ref` to reference definitions:

```json
{
  "units": {
    "type": "array",
    "items": {
      "$ref": "#/definitions/unit"
    }
  }
}
```

## Examples

### Valid Group

```json
{
  "name": "Fighter-1",
  "coalition": "blue",
  "category": "plane",
  "country": 2,
  "units": [
    {
      "name": "Pilot #001",
      "type": "F-16C_50",
      "skill": "High",
      "x": -50000,
      "y": 30000,
      "alt": 2000,
      "speed": 250,
      "heading": 0
    }
  ]
}
```

### Valid Waypoint

```json
{
  "position": {
    "x": -50000,
    "y": 30000
  },
  "alt": 3000,
  "alt_type": "BARO",
  "speed": 250,
  "action": "Turning Point"
}
```

### Valid Loadout

```json
{
  "fuel": 5000,
  "chaff": 120,
  "flare": 60,
  "gun": 511,
  "pylons": {
    "1": {
      "CLSID": "{5CE2FF2A-645A-4197-B48D-8720AC69394F}",
      "num": 1
    },
    "3": {
      "CLSID": "{8D399DDA-FF81-4F14-904D-099B34FE7918}",
      "num": 3
    }
  }
}
```

### Valid Trigger Zone

```json
{
  "name": "Target Area",
  "zoneId": 1,
  "x": 150000,
  "y": 55000,
  "radius": 5000,
  "type": 0,
  "hidden": false
}
```

### Valid DO SCRIPT Trigger

```json
{
  "comment": "Mission Start",
  "script": "trigger.action.outText('Mission begins!', 10)",
  "time_after": 5,
  "trigger_type": "triggerOnce"
}
```

## Validation Tools

### Python

```bash
pip install jsonschema
```

```python
import json
import jsonschema

def validate_operation_data(data, schema_file):
    with open(schema_file) as f:
        schema = json.load(f)
    jsonschema.validate(instance=data, schema=schema)
```

### Online Validators

- [JSONSchema Validator](https://www.jsonschemavalidator.net/)
- [JSON Schema Lint](https://jsonschemalint.com/)

## Schema Versioning

These schemas follow the [JSON Schema Draft-07](https://json-schema.org/draft-07/json-schema-release-notes.html) specification.

## Contributing

When modifying schemas:
1. Update schema file
2. Update examples in this README
3. Validate examples against updated schema
4. Update relevant operation documentation

## See Also

- [Group Operations](../operations/groups.md)
- [Unit Operations](../operations/units.md)
- [Waypoint Operations](../operations/waypoints.md)
- [Coordinate Operations](../operations/coordinates.md)
- [Loadout Operations](../operations/loadouts.md)
- [Trigger Operations](../operations/triggers.md)
- [JSON Schema Documentation](https://json-schema.org/)
