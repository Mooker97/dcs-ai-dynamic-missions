"""
Test script for miz-file-modification library.

Demonstrates all current modification capabilities with file outputs.
"""

from pathlib import Path
from miz_modifier.groups.list import list_all_groups_file, get_group_info_file
from miz_modifier.groups.remove import (
    remove_groups_by_type_file,
    remove_group_file,
    remove_groups_by_coalition_file,
    remove_empty_groups_file
)
from miz_modifier.groups.duplicate import duplicate_group_file


def print_separator(title):
    """Print a formatted section separator."""
    print(f"\n{'='*60}")
    print(f"  {title}")
    print('='*60)


def inspect_mission(input_miz):
    """Inspect and display mission contents."""
    print_separator("MISSION INSPECTION")

    # List all groups
    groups = list_all_groups_file(input_miz)

    print(f"\nInput: {input_miz}")
    print(f"\nCoalition Summary:")
    print(f"  Blue:     {len(groups['blue'])} groups")
    print(f"  Red:      {len(groups['red'])} groups")
    print(f"  Neutrals: {len(groups['neutrals'])} groups")
    print(f"  TOTAL:    {sum(len(g) for g in groups.values())} groups")

    # Show details for each coalition
    for coalition, group_list in groups.items():
        if group_list:
            print(f"\n{coalition.upper()} Groups:")
            for group_name in group_list:
                try:
                    info = get_group_info_file(input_miz, group_name)
                    unit_types = set(u.get('type', 'Unknown') for u in info['units'])
                    print(f"  - {group_name}: {info['unit_count']} units ({', '.join(unit_types)})")
                except Exception as e:
                    print(f"  - {group_name}: Error reading info ({e})")

    return groups


def test_remove_by_type(input_miz, output_dir, groups):
    """Test removing groups by unit type."""
    print_separator("TEST 1: Remove Groups by Type")

    # Determine what types exist
    print("\nAvailable unit types to test:")
    test_types = ["ship", "helicopter", "vehicle", "plane"]

    for unit_type in test_types:
        output_miz = output_dir / f"test1_no_{unit_type}s.miz"

        try:
            print(f"\nRemoving all {unit_type}s...")
            remove_groups_by_type_file(
                str(input_miz),
                str(output_miz),
                [unit_type]
            )

            # Check results
            new_groups = list_all_groups_file(str(output_miz))
            total_removed = sum(len(g) for g in groups.values()) - sum(len(g) for g in new_groups.values())

            print(f"  Output: {output_miz.name}")
            print(f"  Removed: {total_removed} groups")
            print(f"  Remaining: {sum(len(g) for g in new_groups.values())} groups")

        except Exception as e:
            print(f"  Skipped ({e})")


def test_duplicate_groups(input_miz, output_dir, groups):
    """Test duplicating groups with position offsets."""
    print_separator("TEST 2: Duplicate Groups with Position Offsets")

    # Find first group from each coalition to duplicate
    test_cases = []

    if groups['blue']:
        test_cases.append(('blue', groups['blue'][0]))
    if groups['red']:
        test_cases.append(('red', groups['red'][0]))

    if not test_cases:
        print("\nNo groups found to duplicate!")
        return

    output_miz = output_dir / "test2_duplicated_groups.miz"

    print(f"\nDuplicating groups to: {output_miz.name}")

    # Start with original mission
    current_miz = input_miz
    temp_outputs = []

    for i, (coalition, group_name) in enumerate(test_cases):
        temp_output = output_dir / f"temp_duplicate_{i}.miz"
        temp_outputs.append(temp_output)

        try:
            print(f"\n  Duplicating: {group_name} ({coalition})")

            # Duplicate with position offset
            duplicate_group_file(
                str(current_miz),
                str(temp_output),
                group_name=group_name,
                new_group_name=f"{group_name}-Clone",
                position_offset={"x": 5000, "y": 5000}  # 5km east, 5km north
            )

            print(f"    New name: {group_name}-Clone")
            print(f"    Offset: +5km east, +5km north")

            current_miz = temp_output

        except Exception as e:
            print(f"    Error: {e}")

    # Final output
    if temp_outputs:
        import shutil
        shutil.copy(str(temp_outputs[-1]), str(output_miz))

        # Cleanup temp files
        for temp in temp_outputs:
            if temp.exists():
                temp.unlink()

        # Show final result
        final_groups = list_all_groups_file(str(output_miz))
        print(f"\n  Final result:")
        print(f"    Original groups: {sum(len(g) for g in groups.values())}")
        print(f"    New total: {sum(len(g) for g in final_groups.values())}")
        print(f"    Added: {sum(len(g) for g in final_groups.values()) - sum(len(g) for g in groups.values())} groups")


def test_remove_specific_groups(input_miz, output_dir, groups):
    """Test removing specific groups by name."""
    print_separator("TEST 3: Remove Specific Groups by Name")

    # Take first group from blue and red if they exist
    groups_to_remove = []
    if groups['blue']:
        groups_to_remove.append(groups['blue'][0])
    if groups['red']:
        groups_to_remove.append(groups['red'][0])

    if not groups_to_remove:
        print("\nNo groups found to remove!")
        return

    output_miz = output_dir / "test3_removed_specific.miz"

    print(f"\nRemoving specific groups...")
    print(f"  Groups to remove: {', '.join(groups_to_remove)}")

    # Remove first group
    current_miz = input_miz
    for i, group_name in enumerate(groups_to_remove):
        if i == 0:
            remove_group_file(str(current_miz), str(output_miz), group_name)
            current_miz = output_miz
        else:
            temp = output_dir / "temp_remove.miz"
            remove_group_file(str(current_miz), str(temp), group_name)
            import shutil
            shutil.copy(str(temp), str(output_miz))
            temp.unlink()

    # Show results
    new_groups = list_all_groups_file(str(output_miz))
    print(f"\n  Output: {output_miz.name}")
    print(f"  Original: {sum(len(g) for g in groups.values())} groups")
    print(f"  Remaining: {sum(len(g) for g in new_groups.values())} groups")


def test_remove_coalition(input_miz, output_dir, groups):
    """Test removing entire coalition."""
    print_separator("TEST 4: Remove Entire Coalition")

    # Remove red coalition if it exists
    if not groups['red']:
        print("\nNo red coalition found to remove!")
        return

    output_miz = output_dir / "test4_blue_only.miz"

    print(f"\nRemoving RED coalition...")
    print(f"  Red groups: {len(groups['red'])}")

    remove_groups_by_coalition_file(
        str(input_miz),
        str(output_miz),
        "red"
    )

    # Show results
    new_groups = list_all_groups_file(str(output_miz))
    print(f"\n  Output: {output_miz.name}")
    print(f"  Remaining blue: {len(new_groups['blue'])} groups")
    print(f"  Remaining red: {len(new_groups['red'])} groups")


def test_complex_modification(input_miz, output_dir, groups):
    """Test complex multi-step modification."""
    print_separator("TEST 5: Complex Multi-Step Modification")

    print("\nCreating complex modified mission...")
    print("  Step 1: Remove all ships")
    print("  Step 2: Remove all helicopters")
    print("  Step 3: Duplicate first blue aircraft group")

    output_miz = output_dir / "test5_complex_modification.miz"

    # Step 1: Remove ships
    temp1 = output_dir / "temp_step1.miz"
    try:
        remove_groups_by_type_file(str(input_miz), str(temp1), ["ship"])
        current = temp1
    except:
        current = input_miz

    # Step 2: Remove helicopters
    temp2 = output_dir / "temp_step2.miz"
    try:
        remove_groups_by_type_file(str(current), str(temp2), ["helicopter"])
        current = temp2
    except:
        pass

    # Step 3: Duplicate blue group if exists
    if groups['blue']:
        try:
            duplicate_group_file(
                str(current),
                str(output_miz),
                group_name=groups['blue'][0],
                new_group_name=f"{groups['blue'][0]}-Reinforcement",
                position_offset={"x": 10000, "y": 0}  # 10km east
            )
        except Exception as e:
            print(f"\n  Error in step 3: {e}")
            import shutil
            shutil.copy(str(current), str(output_miz))
    else:
        import shutil
        shutil.copy(str(current), str(output_miz))

    # Cleanup temp files
    if temp1.exists():
        temp1.unlink()
    if temp2.exists():
        temp2.unlink()

    # Show results
    new_groups = list_all_groups_file(str(output_miz))
    print(f"\n  Output: {output_miz.name}")
    print(f"  Original: {sum(len(g) for g in groups.values())} groups")
    print(f"  Final: {sum(len(g) for g in new_groups.values())} groups")


def main():
    """Run all modification tests."""
    print("="*60)
    print("  MIZ FILE MODIFICATION LIBRARY - TEST SUITE")
    print("="*60)

    # Setup paths
    input_miz = Path("miz-files/input/your-mission.miz")
    output_dir = Path("miz-files/output")

    # Check for mission files
    if not input_miz.exists():
        # Try to find any .miz file in input directory
        input_dir = Path("miz-files/input")
        if input_dir.exists():
            miz_files = list(input_dir.glob("*.miz"))
            if miz_files:
                input_miz = miz_files[0]
                print(f"\nUsing found mission: {input_miz.name}")
            else:
                print(f"\nERROR: No .miz files found in {input_dir}")
                print("Please place a .miz file in miz-files/input/")
                return
        else:
            print(f"\nERROR: Input directory not found: {input_dir}")
            return

    # Create output directory
    output_dir.mkdir(parents=True, exist_ok=True)

    # Inspect mission
    groups = inspect_mission(input_miz)

    # Run tests
    test_remove_by_type(input_miz, output_dir, groups)
    test_duplicate_groups(input_miz, output_dir, groups)
    test_remove_specific_groups(input_miz, output_dir, groups)
    test_remove_coalition(input_miz, output_dir, groups)
    test_complex_modification(input_miz, output_dir, groups)

    # Final summary
    print_separator("TEST COMPLETE")
    print(f"\nAll output files saved to: {output_dir}")
    print("\nGenerated files:")
    for output_file in sorted(output_dir.glob("test*.miz")):
        print(f"  - {output_file.name}")

    print("\nNext steps:")
    print("  1. Load output .miz files in DCS World")
    print("  2. Verify modifications are correct")
    print("  3. Check DCS.log for any errors")


if __name__ == "__main__":
    main()
