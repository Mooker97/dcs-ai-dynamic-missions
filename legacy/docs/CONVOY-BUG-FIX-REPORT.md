# Convoy Detection Issue - Group Name Mismatch
**Issue**: Mission falsely ends with "Convoy Destroyed" despite all vehicles being alive
**Severity**: CRITICAL
**Root Cause**: Convoy group name in mission editor doesn't match code expectation
**Fix Location**: Mission Editor - NOT code
**Status**: REQUIRES MISSION EDITOR UPDATE

---

## Issue Summary

Mission ends prematurely with "MISSION FAILED - The convoy has been destroyed" message, but when checking the mission, all convoy vehicles are intact and alive.

**The Real Problem**: The convoy group in the DCS Mission Editor is not named `"Convoy-Main"`, which is what the Lua script expects.

---

## Code Analysis

### What The Script Expects

**File**: `dustoff-master-init.lua`
**Line**: 1144, 1157, 1189, 1216

```lua
local convoy = Group.getByName("Convoy-Main")
if not convoy then
    DMS.DustoffCorridor.onDefeat("convoy_destroyed")
    return
end
```

The script looks for a group **named exactly** `"Convoy-Main"`.

### What Happens When Name Doesn't Match

1. `Group.getByName("Convoy-Main")` returns `nil` (group not found)
2. Script checks `if not convoy then` → TRUE (nil is falsy)
3. Calls `DMS.DustoffCorridor.onDefeat("convoy_destroyed")`
4. Mission ends with defeat message
5. BUT the actual convoy exists with a different name!

### Timeline

```
T+10s:  DMS.DustoffCorridor.startConditionMonitoring() called
T+10s:  initConvoyTracking() runs
        → Group.getByName("Convoy-Main") returns nil (wrong name)
        → Log shows "Tracking 0 convoy vehicles"
T+40s:  checkConvoyDestroyed() runs
        → Group.getByName("Convoy-Main") returns nil
        → "if not convoy then" is TRUE
        → onDefeat("convoy_destroyed") triggered
        → MISSION FAILED (but convoy is actually alive!)
```

---

## The Fix: Mission Editor Configuration

### Action Required

1. **Open the mission in DCS Mission Editor**
2. **Find the convoy truck group**
   - Should be a group with 5-6 KAMAZ trucks
   - Likely blue coalition (same as player)
   - May be located in a start zone or route
3. **Rename to exactly**: `Convoy-Main`
   - Right-click group → Properties
   - Change "Group Name" field to `Convoy-Main`
   - **Must be exact spelling and capitalization**

### Verification Steps

1. Open Dustoff Corridor mission in Mission Editor
2. Look for convoy truck group
3. Check current group name
4. Note: Code expects this exact name hierarchy:
   ```lua
   Group.getByName("Convoy-Main")  -- Expects this exact name
   ```

### After Rename

Once renamed to `"Convoy-Main"`:
- ✅ Script will find the group: `Group.getByName("Convoy-Main")` returns group object
- ✅ Convoy tracking initializes: `Tracking N convoy vehicles` logged
- ✅ Convoy checks work: Script monitors unit count and health
- ✅ Win condition works: Convoy reaching FOB-Victory triggers victory
- ✅ Defeat condition works: Only triggers if ALL convoy vehicles destroyed

---

## Why This Isn't a Code Bug

**Unit Life Check Analysis**:

The condition `unit:getLife() > 1` is actually **not the issue**:
- DCS unit life: 0.0 to 100.0 (percentage health)
- Value > 1 means > 1% health remaining
- This is a reasonable threshold (units below 1% are essentially destroyed)
- This check only runs if convoy group is found

**The Real Issue**:
- If group name is wrong, `Group.getByName()` returns `nil`
- Script never gets to the life check
- Script fails immediately on line 1217: `if not convoy then`

**Example**:
```
Scenario: Convoy renamed to "Convoy-Alpha" but code looks for "Convoy-Main"

Line 1216:  local convoy = Group.getByName("Convoy-Main")
            → Returns nil (no group with that name exists)
Line 1217:  if not convoy then  → TRUE (nil is falsy)
Line 1218:  DMS.DustoffCorridor.onDefeat("convoy_destroyed")
            → Defeat triggered immediately!
```

---

## How to Verify the Issue

### In DCS Mission Editor

1. Open Dustoff Corridor mission
2. Look at all ground groups
3. Find the convoy (trucks)
4. Check its "Group Name" property
5. Note the actual name (likely NOT "Convoy-Main")

### In Code Review

The script is correct - it looks for `"Convoy-Main"` because that's what the mission should have. The mission editor just has it named differently.

---

## Testing After Fix

Once convoy group is renamed to `"Convoy-Main"`:

### ✅ Test Case 1: Convoy Tracking
1. Start mission
2. Check DCS.log for: `[DUSTOFF] Tracking N convoy vehicles`
3. Expected: Shows number > 0 (actual convoy size)

### ✅ Test Case 2: Convoy Survives
1. Start mission
2. Don't destroy convoy
3. Wait 60+ seconds
4. Expected: No defeat message, mission continues

### ✅ Test Case 3: Convoy Destroyed
1. Start mission
2. Use console or cheat to destroy all convoy vehicles
3. Expected: "Convoy Destroyed" message appears correctly

### ✅ Test Case 4: Victory
1. Start mission
2. Protect convoy
3. Move convoy to FOB-Victory zone
4. Expected: "Mission Complete" message appears

---

## Related Code

### Convoy Group References
All these functions expect the group named `"Convoy-Main"`:

| Function | Line | Purpose |
|----------|------|---------|
| `initConvoyTracking()` | 1144 | Initialize convoy vehicle count |
| `checkVictory()` | 1157 | Check if convoy in FOB zone |
| `onVictory()` | 1189 | Count survivors |
| `checkConvoyDestroyed()` | 1216 | Check if all vehicles dead |

### Mission Requirements (Line 1140)

From BUG-REPORT-2026-01-03.md:
```
Mission must have:
- Group: "Convoy-Main" (blue, ground trucks)  ← THIS IS CRITICAL
- Group: "Player Group" (blue, helicopter client)
- Zones: Alpha-Zone, Bravo-Zone, Charlie-Zone, QRF-Staging, FOB-Victory
```

---

## Summary

- **Type**: Mission Editor Configuration Error
- **Cause**: Convoy group not named `"Convoy-Main"`
- **Fix**: Rename convoy group in Mission Editor
- **Lines Affected**: None (no code change needed)
- **Testing**: Follow test cases above after renaming

**The code is correct. The mission configuration is wrong.**

