# MIZ File Modifier - Next Steps

**Current Status**: Phase 1 Complete, Phase 2 In Progress (~40% overall completion)

---

## 🎯 Immediate Priority (Wave 1)

### Step 1: Fix Test Infrastructure ✅ COMPLETE
**File**: `tests/run_tests.py`
**Issue**: Syntax error with null bytes
**Action**: Fixed - rewrote file, updated tests to use correct group names
**Result**: 25/25 tests passing

### Step 2: Implement Coordinate Extraction ✅ COMPLETE
**File**: `coordinates/extract.py`
**Functions Implemented**:
- `get_group_coordinates(mission_content, group_name)` → `{"x": float, "y": float, "alt": float}`
- `get_unit_coordinates(mission_content, unit_name)` → `{"x": float, "y": float, "alt": float}`
- `get_all_positions(mission_content, coalition=None, unit_type=None)` → `{"GroupName": {...}, ...}`
- `get_waypoint_coordinates(mission_content, group_name, waypoint_index)` → `{"x": float, "y": float, "alt": float, "speed": float}`
- Convenience wrappers: `*_file()` versions for all functions
**Result**: All functions tested and working

### Step 3: Test Phase 2 Modules
**Files**:
- Create `tests/test_groups_list.py`
- Create `tests/test_groups_remove.py`
- Create `tests/test_groups_duplicate.py`
- Create `tests/test_coordinates.py`

**Time**: 45 minutes

**Wave 1 Total**: ~1.5 hours → Gets to 50% completion

---

## 🚀 High Value Features (Wave 2)

### Step 4: Implement Group Addition
**File**: `groups/add.py`
**Functions Needed**:
- `add_group(mission_content, group_name, unit_type_category, unit_type, coalition, country, position, num_units=1, route=None, skill="Good")` → modified content
- `add_group_file()` wrapper

**Time**: 1 hour

### Step 5: Implement Group Modification
**File**: `groups/modify.py`
**Functions Needed**:
- `rename_group(mission_content, old_name, new_name)` → modified content
- `move_group(mission_content, group_name, new_position)` → modified content
- `change_group_coalition(mission_content, group_name, new_coalition, new_country)` → modified content
- `modify_group_skill(mission_content, group_name, skill)` → modified content
- Convenience wrappers for each

**Time**: 1 hour

**Wave 2 Total**: ~2 hours → Gets to 65% completion

---

## 🎖️ Unit Operations (Wave 3)

### Step 6: Implement Unit Addition
**File**: `units/add.py`
**Functions Needed**:
- `add_unit_to_group(mission_content, group_name, unit_type, position_offset=None, skill=None)` → modified content
- `add_unit_to_group_file()` wrapper

**Time**: 45 minutes

### Step 7: Implement Unit Removal
**File**: `units/remove.py`
**Functions Needed**:
- `remove_unit_from_group(mission_content, group_name, unit_index)` → modified content
- `remove_unit_by_name(mission_content, unit_name)` → modified content
- Convenience wrappers

**Time**: 30 minutes

### Step 8: Implement Unit Modification
**File**: `units/modify.py`
**Functions Needed**:
- `modify_unit_loadout(mission_content, unit_name, loadout)` → modified content
- `modify_unit_skill(mission_content, unit_name, skill)` → modified content
- `modify_unit_position(mission_content, unit_name, new_position)` → modified content
- `rename_unit(mission_content, old_name, new_name)` → modified content
- Convenience wrappers

**Time**: 1 hour

**Wave 3 Total**: ~2 hours → Gets to 80% completion

---

## 🗺️ Waypoint Operations (Wave 4)

### Step 9: Implement Waypoint Inspection
**File**: `waypoints/list.py`
**Functions Needed**:
- `list_waypoints(mission_content, group_name)` → list of waypoint dicts
- `get_waypoint_count(mission_content, group_name)` → int
- `get_waypoint_info(mission_content, group_name, waypoint_index)` → dict

**Time**: 30 minutes

### Step 10: Implement Waypoint Addition
**File**: `waypoints/add.py`
**Functions Needed**:
- `add_waypoint(mission_content, group_name, position, speed=150, alt=2000, action="Turning Point", index=None)` → modified content
- `add_waypoint_file()` wrapper

**Time**: 45 minutes

### Step 11: Implement Waypoint Removal
**File**: `waypoints/remove.py`
**Functions Needed**:
- `remove_waypoint(mission_content, group_name, waypoint_index)` → modified content
- `clear_route(mission_content, group_name, keep_first=True)` → modified content
- Convenience wrappers

**Time**: 30 minutes

### Step 12: Implement Waypoint Modification
**File**: `waypoints/modify.py`
**Functions Needed**:
- `modify_waypoint(mission_content, group_name, waypoint_index, position=None, speed=None, alt=None, action=None)` → modified content
- `modify_waypoint_file()` wrapper

**Time**: 45 minutes

**Wave 4 Total**: ~2.5 hours → Gets to 95% completion

---

## ✨ Polish & Production (Wave 5)

### Step 13: Integration Testing
**Files**: Create comprehensive integration tests
- Test multi-step operations
- Test error handling
- Test edge cases

**Time**: 1 hour

### Step 14: Documentation
**Tasks**:
- Document test.miz structure
- Update README with usage examples
- Add troubleshooting guide

**Time**: 30 minutes

**Wave 5 Total**: ~1.5 hours → Gets to 100% completion

---

## 📊 Summary

| Wave | Focus | Time | Completion |
|------|-------|------|------------|
| Current | - | - | 40% |
| Wave 1 | Fix & Complete Phase 2 | 1.5 hrs | 50% |
| Wave 2 | Group Operations | 2 hrs | 65% |
| Wave 3 | Unit Operations | 2 hrs | 80% |
| Wave 4 | Waypoint Operations | 2.5 hrs | 95% |
| Wave 5 | Polish & Testing | 1.5 hrs | 100% |
| **Total** | **Full Implementation** | **~10 hrs** | **100%** |

---

## 🎯 Recommended Execution

### Fast Track (Recommended)
**Execute**: Waves 1-2 only
**Time**: ~3.5 hours
**Result**: 65% complete with all core group operations working
**Usability**: High - can list, add, remove, modify, duplicate groups

### Complete Build
**Execute**: All 5 waves
**Time**: ~10 hours
**Result**: 100% complete library
**Usability**: Maximum - full mission manipulation capabilities

---

## 🚦 Let's Start

**Ready to begin Wave 1, Step 1?**

Say "go" or "start" and we'll fix the test infrastructure immediately.

Alternative: Tell me which wave you want to focus on and we'll execute it.
