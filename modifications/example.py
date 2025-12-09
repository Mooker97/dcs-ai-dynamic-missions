"""
Example script demonstrating MIZ file manipulation with pydcs
"""

from miz_utils import MizHandler
from pathlib import Path


def example_inspect_mission():
    """Example: Inspect a mission file"""
    print("\n=== EXAMPLE 1: Inspect Mission ===")

    # Find first .miz file in miz-files directory
    miz_dir = Path("../miz-files")
    miz_files = list(miz_dir.glob("*.miz"))

    if not miz_files:
        print("No .miz files found in ../miz-files/")
        return

    # Load and inspect first mission
    handler = MizHandler(str(miz_files[0]))

    # Get basic info
    info = handler.get_mission_info()
    print(f"\nMission Name: {info['mission_name']}")
    print(f"Terrain: {info['terrain']}")
    print(f"Date: {info['date']}")

    # List aircraft
    groups = handler.list_aircraft_groups()
    print(f"\nBlue Coalition: {len(groups['blue'])} aircraft groups")
    print(f"Red Coalition: {len(groups['red'])} aircraft groups")


def example_export_to_json():
    """Example: Export mission data to JSON"""
    print("\n=== EXAMPLE 2: Export to JSON ===")

    miz_dir = Path("../miz-files")
    miz_files = list(miz_dir.glob("*.miz"))

    if not miz_files:
        print("No .miz files found in ../miz-files/")
        return

    handler = MizHandler(str(miz_files[0]))
    output_path = "mission_export.json"
    handler.export_to_json(output_path)
    print(f"Exported to: {output_path}")


def example_modify_mission():
    """Example: Load, modify, and save a mission"""
    print("\n=== EXAMPLE 3: Modify Mission (Template) ===")
    print("This is a template - add your specific modifications here")

    miz_dir = Path("../miz-files")
    miz_files = list(miz_dir.glob("*.miz"))

    if not miz_files:
        print("No .miz files found in ../miz-files/")
        return

    # Load mission
    handler = MizHandler(str(miz_files[0]))

    # Make modifications to handler.mission here
    # Example: Change mission start time, add/remove groups, etc.

    # Save to new file
    output_path = miz_dir / "modified_mission.miz"
    # handler.save(str(output_path))
    print(f"Would save to: {output_path}")
    print("(Commented out to prevent accidental modifications)")


if __name__ == "__main__":
    print("DCS MIZ File Manipulation Examples")
    print("=" * 50)

    # Run examples
    example_inspect_mission()
    example_export_to_json()
    example_modify_mission()

    print("\n" + "=" * 50)
    print("Examples complete!")
