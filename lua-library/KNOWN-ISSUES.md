# Known Bugs & Possible Improvements

**Date Started**: 2026-01-03
**Purpose**: Track bugs discovered during testing and ideas for future improvements

---

## Known Bugs

### 1. Fog of War Not Working
**Date Reported**: 2026-01-03
**Status**: Not Fixed
**Description**: FOW system still not functioning correctly despite code fix. Enemy units remain visible on F10 map at spawn.

**Notes**:
- Line 696 fix removed invalid `trigger.action.groupKnown()` call
- FOW registration appears to run but groups stay visible
- Need to investigate DCS API for proper F10 map hiding

---

### 2. Convoy AI: Doesn't Slow/Stop to Engage
**Date Reported**: 2026-01-03
**Status**: Not Fixed
**Description**: Convoy keeps rolling through ambush zones. Only some units engage while moving - convoy doesn't slow down or stop to fight.

**Expected Behavior**: Convoy should:
- Slow down when taking fire
- Stop or take defensive positions
- All units should engage threats

**Current Behavior**:
- Convoy maintains speed through combat
- Partial engagement only
- Feels unrealistic

---

### 3. Enemy AI: No Active Convoy Seeking
**Date Reported**: 2026-01-03
**Status**: Not Fixed
**Description**: Enemy units do not actively hunt or seek the convoy. If they don't have initial LOS, they never attempt to engage it.

**Expected Behavior**:
- Enemies should patrol/search for convoy
- Move to intercept when convoy nearby
- Pursue if convoy spotted then lost

**Current Behavior**:
- Enemies stationary unless direct LOS
- No pursuit or hunting behavior
- Passive defense only

---

## Possible Improvements

### 1. DCS Mission Architecture: Reduce Giant Init Scripts
**Date Suggested**: 2026-01-03
**Date Researched**: 2026-01-03
**Priority**: Low
**Status**: Deferred - Nice to Have

**Description**: Current approach uses massive single-file init scripts (dustoff-master-init.lua). Feels inefficient given we have a modular lua-library structure.

**Current Problem**:
- 1300+ line init files
- All dependencies concatenated into one file
- Hard to maintain and debug
- Doesn't leverage library structure

---

## Research Findings

### Loading Multiple Files in DCS

**✅ SUPPORTED - Multiple DO SCRIPT FILE Actions**

DCS natively supports loading multiple Lua files using sequential DO SCRIPT FILE trigger actions:

```
Trigger: ONCE > Time More (1)
Actions:
  - Do Script File (1-settings.lua)
  - Do Script File (2-fog-of-war.lua)
  - Do Script File (3-dynamic-spawn.lua)
  - Do Script File (4-mission-init.lua)
```

**Key Points**:
- Scripts execute in order within same trigger
- Dependencies work correctly: if C needs B and B needs A, load as A→B→C
- Once loaded, scripts share the global mission scripting environment
- All functions/tables become accessible to subsequent scripts

**Source**: [Hoggit Wiki - Scripting Engine Introduction](https://wiki.hoggitworld.com/view/Scripting_Engine_Introduction)

---

### Using dofile() / loadfile()

**⚠️ SANDBOXED - Requires MissionScripting.lua Modification**

`dofile()` and `loadfile()` work in DCS but require modification to `DCS World/Scripts/MissionScripting.lua`:

```lua
-- Must comment out sanitization:
-- sanitizeModule('os')
-- sanitizeModule('io')
-- sanitizeModule('lfs')
```

**SECURITY RISK**:
> "This will allow any mission or server you play on to access the internet and modify your files, allowing a malicious mission to download and install viruses."

**Verdict**: ❌ **NOT RECOMMENDED** for mission distribution. Only suitable for personal/trusted missions.

**Sources**:
- [DCS FAQ - Lua Environment](https://www.digitalcombatsimulator.com/en/support/faq/1253/)
- [MOOSE - De-Sanitize DCS](https://flightcontrol-master.github.io/MOOSE/advanced/desanitize-dcs.html)

---

### Community Best Practices

**Script Organization Patterns**:

1. **Single Container Pattern**: Use one global table to avoid naming collisions
   ```lua
   DMS = DMS or {}  -- Our current approach ✓
   ```

2. **Modular File Structure**: Complex missions divide initialization into logical files
   ```
   - ground_defense_init.lua
   - air_defense_init.lua
   - transport_init.lua
   - mission_config.lua
   ```

3. **Framework Pattern (MIST)**:
   - Load framework first via DO SCRIPT FILE (too large for DO SCRIPT text box)
   - Load mission scripts after framework initializes
   - Timing: Framework at T+1s, mission scripts at T+2s

**Sources**:
- [Amoeba Games - Mission.lua Structure](http://www.amoeba-games.com/FST/AGHTM_MissionLua.aspx)
- [Hoggit Wiki - Mission Scripting Tools](https://wiki.hoggitworld.com/view/Mission_Scripting_Tools_Documentation)

---

## Recommended Solution for DMS

### ✅ Use Multiple DO SCRIPT FILE Actions (Native DCS Support)

**Architecture**:
```
Mission Editor Trigger:
├─ ONCE > Mission Start
├─ Do Script File: lua-library/utils/mission-settings.lua
├─ Do Script File: lua-library/utils/fog-of-war.lua
├─ Do Script File: lua-library/spawners/dynamic-spawn.lua
├─ Do Script File: lua-library/ai-behavior/sam-ambush.lua
├─ Do Script File: lua-library/events/reinforcement-waves.lua
└─ Do Script File: missions/dustoff-corridor/mission-init.lua
```

**Benefits**:
- ✅ No security risks (native DCS functionality)
- ✅ Maintains modular library structure
- ✅ Easy to debug individual modules
- ✅ Can reuse modules across missions
- ✅ Mission-specific config in separate file
- ✅ Works on any DCS installation (no modifications needed)

**Trade-offs**:
- ⚠️ Files still packed into .miz (but organized)
- ⚠️ Need to maintain load order manually
- ⚠️ Slightly more complex mission editor setup

---

## Implementation Plan

1. **Refactor lua-library modules** to be self-contained DO SCRIPT FILE compatible
2. **Create loader script** that defines proper load order
3. **Test with Dustoff Corridor** mission as proof-of-concept
4. **Document** standard loading pattern for future missions
5. **Update CLAUDE.md** with new architecture pattern

**Estimated Effort**: 2-4 hours (refactor + test)

---

## Additional Resources

- [Mission Scripting Foundation](https://wiki.hoggitworld.com/view/Mission_Scripting_Foundation_Documentation)
- [DCS Forums - ME Script Loading](https://forum.dcs.world/topic/282920-me-script-loading/)
- [Mudspike - DCS Lua Scripting Examples](https://forums.mudspike.com/t/dcs-lua-scripting-examples/16935)

---

## Template for New Entries

### Bug Template
```markdown
### N. [Bug Title]
**Date Reported**: YYYY-MM-DD
**Status**: Not Fixed | In Progress | Fixed
**Description**: [What's broken]

**Expected Behavior**: [What should happen]
**Current Behavior**: [What actually happens]
**Notes**: [Additional context]
```

### Improvement Template
```markdown
### N. [Improvement Title]
**Date Suggested**: YYYY-MM-DD
**Priority**: High | Medium | Low
**Description**: [What could be better]

**Current Problem**: [Why current approach isn't ideal]
**Possible Solutions**: [Ideas for improvement]
**Investigation Needed**: [What needs research]
```

---

## Status Key

- **Not Fixed**: Bug exists, no work done
- **In Progress**: Actively being worked on
- **Fixed**: Resolved and tested
- **Deferred**: Acknowledged but postponed
- **Won't Fix**: Decided not to pursue

---

## Priority Key

- **High**: Critical functionality or major user impact
- **Medium**: Important but not blocking
- **Low**: Nice to have, minor impact
