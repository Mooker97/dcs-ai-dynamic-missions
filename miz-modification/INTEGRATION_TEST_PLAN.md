# Integration Test Plan (Wave 5)

**Goal**: Test multi-step operations and real-world workflows across the entire library.

---

## Integration Test Workflow

```
1. [User] Creates test.miz in DCS Mission Editor
         ↓
2. [Test Script] Extracts test.miz
         ↓
3. [Test Script] Modifies (add groups, change units, adjust waypoints)
         ↓
4. [Test Script] Repackages to output.miz
         ↓
5. [Test Script] Re-extracts output.miz and verifies changes persisted
         ↓
6. [User] Loads output.miz in DCS Mission Editor to verify it works
```

**Key Principle**: Each test is a **full standalone script** that runs all needed operations and verification steps automatically.

---

## Test Missions to Create

Create these 3 test missions in DCS Mission Editor and save to `miz-files/test/`:

### 1. `empty_caucasus.miz`
- **Map**: Caucasus
- **Content**: Empty mission, no units
- **Purpose**: Test adding groups from scratch

### 2. `simple_strike.miz`
- **Map**: Caucasus
- **Content**:
  - 1 blue fighter group (2x F-16C) at Batumi
  - Simple 3-waypoint route
- **Purpose**: Test modifications to existing groups

### 3. `multi_group.miz`
- **Map**: Caucasus
- **Content**:
  - Blue fighters (2x F-16C)
  - Red fighters (2x Su-27)
  - Blue ground units (2x M1 Abrams)
- **Purpose**: Test complex multi-group operations

---

## Test Structure

```
miz-modification/tests/integration/
├── test_01_add_group_and_waypoints.py      # Add new group with route
├── test_02_modify_existing_group.py        # Change units + waypoints
├── test_03_multi_group_operations.py       # Complex cross-group ops
├── test_04_unit_loadout_changes.py         # Modify loadouts
└── test_05_waypoint_route_editing.py       # Route manipulation
```

Each test outputs to `miz-files/output/test_XX_output.miz`

---

## Test Scenarios

### Test 01: Add Group with Waypoints
**Input**: `empty_caucasus.miz`
**Operations**:
1. Add new fighter group "Test-Fighter-1" (2x F-16C)
2. Add 3 waypoints to create ingress route
3. Verify group exists with correct unit count
4. Verify route has 4 waypoints (spawn + 3 added)

**Output**: `test_01_output.miz`

---

### Test 02: Modify Existing Group
**Input**: `simple_strike.miz`
**Operations**:
1. Find existing fighter group
2. Modify unit loadouts (add weapons)
3. Adjust waypoint altitudes
4. Verify changes persisted

**Output**: `test_02_output.miz`

---

### Test 03: Multi-Group Operations
**Input**: `multi_group.miz`
**Operations**:
1. List all groups (blue, red, ground)
2. Remove red fighters
3. Duplicate blue fighters to create second flight
4. Modify routes for both blue flights
5. Verify red removed, 2 blue flights exist

**Output**: `test_03_output.miz`

---

### Test 04: Unit Loadout Changes
**Input**: `simple_strike.miz`
**Operations**:
1. Get existing fighter group
2. Add 2 more units (expand to 4-ship)
3. Modify loadouts for all 4 units (CAP loadout)
4. Verify 4 units with correct pylons

**Output**: `test_04_output.miz`

---

### Test 05: Waypoint Route Editing
**Input**: `simple_strike.miz`
**Operations**:
1. Clear existing route (keep spawn point)
2. Build new 5-waypoint route
3. Modify waypoint 3 position (reroute)
4. Remove last waypoint (shorten route)
5. Verify 4 waypoints remain with correct positions

**Output**: `test_05_output.miz`

---

## Test Script Structure

Each test follows this pattern:

```python
# test_01_add_group_and_waypoints.py

from miz_modification.parsing.miz_parser import MizParser
from miz_modification.groups.add import add_group
from miz_modification.waypoints.add import add_waypoint
from miz_modification.groups.list import list_all_groups, get_group_info
from miz_modification.waypoints.list import list_waypoints

def test_add_group_with_waypoints():
    """Add new fighter group with custom route"""

    print("=" * 60)
    print("TEST: Add Fighter Group with Custom Route")
    print("=" * 60)

    # 1. Load test mission
    print("\n1. Loading test mission...")
    parser = MizParser("../miz-files/test/empty_caucasus.miz")
    parser.extract()
    content = parser.get_mission_content()
    print("   ✓ Loaded")

    # 2. Add new fighter group
    print("\n2. Adding new fighter group 'Test-Fighter-1'...")
    content = add_group(
        content,
        group_name="Test-Fighter-1",
        unit_type_category="plane",
        unit_type="F-16C_50",
        coalition="blue",
        country="USA",
        position={"x": -50000, "y": 30000},
        num_units=2,
        skill="Good"
    )
    print("   ✓ Group added")

    # 3. Add waypoints to route
    print("\n3. Adding waypoints to route...")
    waypoints = [
        {"position": {"x": -45000, "y": 35000}, "speed": 200, "alt": 3000},
        {"position": {"x": -40000, "y": 40000}, "speed": 250, "alt": 4000},
        {"position": {"x": -35000, "y": 45000}, "speed": 300, "alt": 5000}
    ]

    for i, wp in enumerate(waypoints, 2):
        content = add_waypoint(content, "Test-Fighter-1", **wp)
        print(f"   ✓ Waypoint {i} added")

    # 4. Save modified mission
    print("\n4. Saving modified mission...")
    parser.write_mission_content(content)
    parser.repackage("../miz-files/output/test_01_output.miz")
    print("   ✓ Saved to test_01_output.miz")

    # 5. Re-extract and verify changes persisted
    print("\n5. Verifying changes persisted...")
    parser2 = MizParser("../miz-files/output/test_01_output.miz")
    parser2.extract()
    verify_content = parser2.get_mission_content()

    # Verify group exists
    groups = list_all_groups(verify_content)
    assert "Test-Fighter-1" in groups['blue'], "Group not found!"
    print("   ✓ Group 'Test-Fighter-1' exists")

    # Verify group info
    group_info = get_group_info(verify_content, "Test-Fighter-1")
    assert group_info['num_units'] == 2, "Wrong unit count!"
    print(f"   ✓ Group has {group_info['num_units']} units")

    # Verify waypoints
    waypoints_verify = list_waypoints(verify_content, "Test-Fighter-1")
    assert len(waypoints_verify) == 4, f"Expected 4 waypoints, got {len(waypoints_verify)}"
    print(f"   ✓ Route has {len(waypoints_verify)} waypoints")

    # Print waypoint details
    print("\n   Waypoint details:")
    for wp in waypoints_verify:
        print(f"      WP{wp['index']}: ({wp['x']:.0f}, {wp['y']:.0f}) @ {wp['alt']:.0f}m, {wp['speed']:.0f}m/s")

    print("\n" + "=" * 60)
    print("✅ TEST PASSED - Ready for DCS verification")
    print("   Load: miz-files/output/test_01_output.miz")
    print("=" * 60)

if __name__ == "__main__":
    test_add_group_with_waypoints()
```

**Run**: `python test_01_add_group_and_waypoints.py`

---

## Verification Strategy

### Automated Verification (in test script)
1. ✅ **Re-extract**: Load output.miz and extract contents
2. ✅ **Data Integrity**: Verify groups/units/waypoints exist with correct values
3. ✅ **IDs**: Check all IDs are unique and valid
4. ✅ **Structure**: Ensure Lua syntax is valid (no parse errors)

### Manual Verification (by user)
1. ✅ **Load in DCS**: Open output.miz in Mission Editor
2. ✅ **Visual Check**: Verify groups appear on map at correct positions
3. ✅ **Playable**: Start mission and verify units spawn correctly

---

## Implementation Order

### Phase 1: User Creates Test Missions (30 minutes)
1. Create `empty_caucasus.miz` in DCS Mission Editor
2. Create `simple_strike.miz` with 1 fighter group
3. Create `multi_group.miz` with multiple groups
4. Save all to `miz-files/test/`

### Phase 2: Implement Test Scripts (2-3 hours)
1. `test_01_add_group_and_waypoints.py` - Add from scratch
2. `test_02_modify_existing_group.py` - Modify existing
3. `test_03_multi_group_operations.py` - Complex operations
4. (Optional) `test_04_unit_loadout_changes.py` - Loadout focus
5. (Optional) `test_05_waypoint_route_editing.py` - Route focus

### Phase 3: Run Tests & DCS Verification (1-2 hours)
1. Run each test script
2. Load each output.miz in DCS Mission Editor
3. Document any issues found
4. Fix library code if needed
5. Re-run tests until all pass

---

## Success Criteria

- ✅ All test scripts run without errors
- ✅ Re-extraction verifies changes persisted correctly
- ✅ All output.miz files load in DCS Mission Editor
- ✅ Groups appear at correct positions in Mission Editor
- ✅ Routes display correctly on map
- ✅ Missions are playable (units spawn correctly)

---

## Priority (MVP)

**If time-constrained, implement only these 3 tests:**

1. **Test 01**: Add group + waypoints (complete workflow)
2. **Test 02**: Modify existing group (real-world editing)
3. **Test 03**: Multi-group operations (complexity test)

These 3 tests cover 80% of real-world usage patterns and provide confidence the library works end-to-end.

---

## Estimated Effort

| Phase | Time |
|-------|------|
| User: Create test missions | 30 min |
| Dev: Write test scripts | 2-3 hrs |
| Both: Run tests + DCS verification | 1-2 hrs |
| **Total** | **4-6 hrs** |

**MVP (3 tests only)**: ~3 hours total
