# Waypoint Extraction Development: Lessons Learned

**Date**: December 2024
**Status**: Failed attempts documented for future reference
**Knowledge Base Updated**: Yes - `knowledge/miz-file-manipulation.md`

## Summary

Attempted to create waypoint extraction scripts for DCS mission files using two approaches:
1. **pydcs-based** (`get_waypoints.py`) - Failed due to unknown task IDs in real missions
2. **Direct Lua parsing** (`get_waypoints_lite.py`) - Failed due to regex complexity for nested structures

Both scripts are **non-functional** but preserved as learning examples in `modifications/` with documentation in `modifications/README_waypoints.md`.

## What Was Created

### Files
- `modifications/get_waypoints.py` - pydcs approach (328 lines, non-functional)
- `modifications/get_waypoints_lite.py` - Direct Lua parsing (419 lines, incomplete)
- `modifications/README_waypoints.md` - Documentation of both approaches
- `knowledge/miz-file-manipulation.md` - Updated with comprehensive lessons learned

### What Works
- ✅ Complete CLI interface design
- ✅ Filtering by coalition and group name
- ✅ JSON export structure
- ✅ Output formatting
- ✅ Error handling patterns
- ✅ Project integration

### What Doesn't Work
- ❌ pydcs fails on `KeyError: 35` (unknown task ID)
- ❌ Regex patterns can't reliably parse nested Lua structures
- ❌ Cannot extract waypoints from test mission files

## Critical Mistakes

### 1. Started Coding Before Understanding Structure
**Wrong**: Wrote regex patterns based on assumptions
**Right**: Extract mission file first, inspect actual structure

```bash
# Should have done this FIRST:
python parsing/miz_parser.py extract "mission.miz" "inspect"
cat inspect/mission | grep -A 20 "route"
```

### 2. Used Windows-Incompatible Output
**Wrong**: Unicode emojis in print statements (✅, ❌, 📍)
**Error**: `UnicodeEncodeError: 'charmap' codec can't encode character`
**Right**: ASCII only - `[OK]`, `[ERROR]`, `>`

### 3. Trusted pydcs for Parsing
**Wrong**: Assumed pydcs could parse any mission file
**Reality**: pydcs designed for missions IT generates, not real-world missions
**Crashes on**: Unknown task IDs, options, or custom configurations
**Lesson**: **pydcs is for GENERATION, not PARSING**

### 4. Complex Nested Regex
**Wrong**: Attempted to match 10+ levels of nested Lua tables with regex
**Reality**: Regex cannot reliably handle arbitrary nesting depth
**Right**: Use Lua parser library OR hybrid string-finding approach

## The Right Solution (Not Implemented)

### Option 1: slpp Lua Parser (BEST)
```python
import slpp

mission_dict = slpp.slpp.decode(mission_content)

for country in mission_dict['coalition']['blue']['country']:
    for group in country['plane']['group']:
        waypoints = group['route']['points']
        # Direct dict access, no regex needed
```

**Pros**: Handles any Lua structure, clean code
**Cons**: Additional dependency

### Option 2: Hybrid String Finding + Simple Regex (PRACTICAL)
```python
# Use string finding for sections
coalition_start = content.find('["blue"] =')
coalition_end = content.find('}, -- end of ["blue"]', coalition_start)
blue_section = content[coalition_start:coalition_end]

# Simple regex only for leaf data
for match in re.finditer(r'\["x"\]\s*=\s*([-\d.]+)', blue_section):
    x = float(match.group(1))
```

**Pros**: No dependencies, follows existing patterns
**Cons**: More code than Lua parser

## Development Process Lessons

### Before Writing Code:
1. **Extract and inspect** actual mission file structure
2. **Identify all nesting levels** (10+ for waypoints)
3. **Build patterns incrementally** - test each level
4. **Create debug scripts** to validate patterns
5. **Only then** write full implementation

### Windows Compatibility:
- ✅ ASCII output only (no emojis)
- ✅ Use `Path` objects for file paths
- ✅ Test on Windows cmd (not just bash)

### Testing Strategy:
- ✅ Test with actual mission files (not synthetic examples)
- ✅ Validate structure at each step
- ✅ Check for specific data presence, not just structure

## What This Taught Us

### pydcs Limitations (Updated Knowledge Base)
- **Use Case**: Mission GENERATION from scratch
- **Not For**: Parsing existing real-world missions
- **Reason**: Fails on unknown task IDs, options, custom configs
- **Alternative**: MizParser + string finding/regex for parsing

### Regex Limitations
- **Good For**: Simple patterns, leaf-level data extraction
- **Bad For**: Nested structures beyond 2-3 levels
- **Alternative**: Lua parser libraries (slpp, lupa)

### Development Approach
- **Inspect First**: Always examine actual file before coding
- **Incremental**: Build and test one level at a time
- **Debug Tools**: Create small test scripts
- **Follow Patterns**: Use existing `methods/groups/list_groups.py` as reference

## Impact on Project

### Knowledge Base Updated
Added comprehensive section: "Lessons Learned from Waypoint Extraction (December 2024)"

**Location**: `knowledge/miz-file-manipulation.md`

**Covers**:
- Critical mistakes and solutions
- Three alternative approaches (with code examples)
- Development process best practices
- Windows compatibility considerations
- Testing strategies
- Recommended pattern for future scripts

### Future Script Development
All future scripts should:
1. Extract and inspect mission files FIRST
2. Use MizParser + hybrid string finding approach
3. Reserve pydcs for mission generation only
4. Use ASCII output for Windows compatibility
5. Build patterns incrementally with debug scripts

## Files to Reference

### For Future Development:
- `knowledge/miz-file-manipulation.md` - Complete patterns and lessons
- `methods/groups/list_groups.py` - Working example of string finding + regex
- `parsing/miz_parser.py` - Extract/repackage workflow

### For Understanding Mistakes:
- `modifications/get_waypoints.py` - pydcs limitations example
- `modifications/get_waypoints_lite.py` - Complex regex problems example
- `modifications/README_waypoints.md` - Detailed explanation of both approaches

## Conclusion

Two approaches were attempted and both failed, but **valuable lessons were learned**:

1. ✅ pydcs limitations now well-documented
2. ✅ Regex nesting limits understood
3. ✅ Alternative approaches identified (slpp, hybrid)
4. ✅ Development process refined
5. ✅ Knowledge base significantly enhanced

The non-functional scripts remain as **reference examples** of what NOT to do, and the knowledge base now contains clear guidance for future development.

**Next time**: Extract first, use slpp OR string finding + simple regex, test incrementally.
