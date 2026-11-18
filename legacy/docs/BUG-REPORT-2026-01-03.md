# Dustoff Corridor - Mission Test Bug Report
**Date**: 2026-01-03 (10:45)
**Test Status**: PARTIAL FAILURE - Script loaded, enemies spawned, but 2 critical bugs

---

## Issues Found

### 1. ❌ FOG OF WAR NOT WORKING
**Severity**: HIGH
**Description**: Fog of War system failed to hide/reveal enemies correctly
- Script loaded without errors
- Enemies spawned normally (visible)
- FOG system should have hidden them initially, then revealed on proximity/combat
- **Actual behavior**: FOG system did not engage

**Last Known Code**:
- FOG system initialized: `DMS.FogOfWar.start()` called at line 1108
- Event handler: `DMS.FogOfWar._EventHandlerInternal` defined at lines 768-804
- Proximity check: `checkProximityDetection()` at lines 764-788
- Registration: `DMS.FogOfWar.registerHiddenGroup()` at lines 353-365

**Suspected Issues**:
- FOG system may not be registering spawned groups as hidden
- Event handler may not be firing correctly
- Proximity detection logic may have bugs

**Next Steps for Investigation**:
- Check DCS.log for FOG-related errors
- Verify `DMS.FogOfWar.HiddenGroups` table is populated after spawn
- Test event handler manually (S_EVENT_HIT, S_EVENT_SHOT, etc.)
- Check if `trigger.action.groupKnown()` is working

---

### 2. ❌ MISSION FAILED - FALSE POSITIVE (CONVOY ALIVE)
**Severity**: CRITICAL
**Description**: Mission ended with "FAILED - Convoy destroyed" despite all convoy vehicles being alive
- Convoy had all vehicles intact when mission ended
- Win/loss system triggered defeat condition prematurely
- **Actual behavior**: `DMS.DustoffCorridor.onDefeat("convoy_destroyed")` was called when it shouldn't have been

**Last Known Code**:
- Convoy destroyed check: `DMS.DustoffCorridor.checkConvoyDestroyed()` at lines 1239-1259
- Defeat trigger: `DMS.DustoffCorridor.onDefeat()` at lines 1261-1283
- Convoy tracking: `DMS.DustoffCorridor.initConvoyTracking()` at lines 1220-1227
- Win/loss monitoring scheduled: Lines 1300-1301

**Suspected Issues**:
- `Group.getByName("Convoy-Main")` may be returning nil incorrectly
- Unit life check logic flawed: `unit:getLife() > 1` condition may be wrong
- Group existence check: `group:isExist()` returning false when group exists
- Timer schedule may be executing checks before convoy is properly loaded
- Convoy naming mismatch (expected `"Convoy-Main"` vs actual name in mission)

**Verification Needed**:
- Confirm convoy group name is exactly `"Convoy-Main"`
- Check if convoy units are spawned/loaded when first check runs (at T+30s)
- Verify unit life values (what's the range? 0-100? 0-1000?)
- Check if group returns nil during early mission startup

---

### 3. ❌ UNITS SPAWNING ON TOP OF BUILDINGS
**Severity**: HIGH
**Description**: Several spawned vehicles clipped into/on top of buildings instead of spawning on ground
- Affects multiple pools (likely alpha-ground, bravo-armor, charlie-defense)
- Units phase through buildings or spawn elevated
- Creates unrealistic positioning and potential pathfinding issues

**Last Known Code**:
- Spawn position calculation: `calculateSpawnPosition()` at lines 537-543
- Unit position building: Lines 659-672 (unit loop)
- GroupData building: Lines 674-683

**Root Cause Analysis**:
- Spawn system uses pure distance/angle from zone center
- **No terrain/building collision detection**
- Random positions don't check if location is occupied or elevated
- DCS zone centers may be in buildings or on elevated terrain

**Suspected Issues**:
- `calculateSpawnPosition()` picks random angle/distance without checking terrain
- No height (Y coordinate) validation - assumes flat ground
- Unit formation offsets (line 666-667) compounds the problem
- Zone point may be in middle of structure

**How to Fix**:
- Need to check terrain elevation at spawn point
- Validate that Y coordinate is at ground level
- Add collision avoidance radius check
- Potentially offset spawn zones to known clear ground

**Verification Needed**:
- Which pools affected? All of them or specific zones?
- How far off ground? (meters)
- Which buildings/terrain types problematic?

---

## Test Summary

**What Worked** ✅
- Script loaded without syntax errors
- Enemies spawned in zones (sam-site, alpha-ground, bravo-armor, etc.)
- Spawn pools executed correctly
- Mission start briefing displayed
- Debug logging active

**What Failed** ❌
- Fog of War system (enemies visible when should be hidden)
- Win/Loss condition logic (false defeat detection)
- Convoy tracking or detection logic

**Current Confidence Level**: 30% for mission working as intended

---

## Debug Logs to Check

When debugging, look in `DCS.log` for these patterns:
```
[DUSTOFF] Mission starting...
[DynamicSpawn] Spawned 'xxx-1' from 'yyy' at (x, y)
[FOW] Registered hidden group: xxx
[FOW] Revealed xxx to coalition 2
[DUSTOFF] Tracking N convoy vehicles
[DUSTOFF] DEFEAT
```

## Files Modified
- `/lua-library/ZZ Mission Files/dustoff-corridor/dustoff-master-init.lua` (1307 lines)

## Reproduction Steps
1. Open mission in DCS Mission Editor
2. Add DO SCRIPT FILE trigger: `dustoff-master-init.lua` at mission start
3. Ensure mission has:
   - Group: `"Player Group"` (blue, helicopter client)
   - Group: `"Convoy-Main"` (blue, ground trucks)
   - Zones: `Alpha-Zone`, `Bravo-Zone`, `Charlie-Zone`, `QRF-Staging`, `FOB-Victory`
4. Start mission
5. Observe:
   - Enemies spawn (✅ works)
   - Enemies should be hidden from F10 map (❌ not working)
   - Convoy status tracking should be silent while alive (❌ failing)
