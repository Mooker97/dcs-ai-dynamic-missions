# Waypoint Extraction Scripts

Two approaches for extracting waypoints from DCS mission files (.miz).

## Scripts

### 1. `get_waypoints.py` - pydcs-based (Preferred when working)

**Approach**: Uses the pydcs library for full mission parsing

**Pros**:
- Complete mission understanding
- Type-safe access to all mission properties
- Structured data extraction

**Cons**:
- Requires DCS World installation (or at least DCS_HOME set)
- Fails on missions with unknown task IDs
- Currently non-functional with test missions due to KeyError: 35 (unknown task ID in mission file)

**Usage**:
```bash
python get_waypoints.py mission.miz
python get_waypoints.py mission.miz --coalition blue
python get_waypoints.py mission.miz --group "Enfield"
python get_waypoints.py mission.miz --json output.json
```

### 2. `get_waypoints_lite.py` - Direct Lua parsing (Work in Progress)

**Approach**: Directly parses the mission Lua file without pydcs

**Pros**:
- No DCS installation required
- Works with any mission file structure
- Bypasses pydcs limitations

**Cons**:
- Complex regex patterns for nested Lua structures
- Currently incomplete - regex patterns need refinement
- Less robust than pydcs approach

**Status**: 🚧 Under development - regex patterns for extracting groups/waypoints need work

**Usage** (same as get_waypoints.py):
```bash
python get_waypoints_lite.py mission.miz
python get_waypoints_lite.py mission.miz --coalition blue --json output.json
```

## Current Issue

The test missions contain tasks with ID=35 that pydcs doesn't recognize, causing the pydcs approach to fail. The lightweight parser is being developed as a workaround but needs additional work on Lua parsing patterns.

## Output Format

Both scripts output waypoint data in the same format:

```json
{
  "mission_name": "Mission Name",
  "terrain": "PersianGulf",
  "groups": {
    "blue": {
      "aircraft": [
        {
          "name": "Group Name",
          "country": "USA",
          "units": 2,
          "waypoint_count": 6,
          "waypoints": [
            {
              "index": 1,
              "position": {"x": 18880.87, "y": -130.40},
              "alt": 7473.70,
              "alt_type": "BARO",
              "speed": 220.97,
              "type": "Turning Point",
              "action": "Turning Point"
            }
          ]
        }
      ],
      "helicopters": [],
      "vehicles": [],
      "ships": []
    },
    "red": { ... }
  }
}
```

## Next Steps for Completion

To finish the lightweight parser:

1. **Fix Coalition Extraction**: The regex pattern for finding the coalition->blue->country path needs refinement
2. **Fix Group Extraction**: The nested Lua structure parsing needs better handling
3. **Test with Mission Files**: Validate against multiple mission files

### Debugging

Use `debug_parse.py` to test regex patterns:
```bash
python debug_parse.py mission.miz
```

This shows which sections are being found and helps debug pattern matching.

## Alternative Approach

If regex proves too complex, consider:
- Using a Lua parser library (e.g., `slpp`, `lupa`)
- Writing a simple Lua table parser
- Using pydcs with patches for unknown task IDs

## Mission File Structure Reference

```
mission = {
  ["coalition"] = {
    ["blue"] = {
      ["country"] = {
        [1] = {
          ["name"] = "USA",
          ["plane"] = {
            ["group"] = {
              [1] = {
                ["name"] = "Group Name",
                ["route"] = {
                  ["points"] = {
                    [1] = {
                      ["x"] = 18880.87,
                      ["y"] = -130.40,
                      ["alt"] = 7473.70,
                      ["alt_type"] = "BARO",
                      ["speed"] = 220.97,
                      ["action"] = "Turning Point",
                      ["type"] = "Turning Point"
                    }
                  }
                }
              }
            }
          }
        }
      }
    }
  }
}
```
