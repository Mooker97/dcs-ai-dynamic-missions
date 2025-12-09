"""
MIZ File Utilities
Utility functions for reading, parsing, and modifying DCS World .miz files using pydcs
"""

import os
import sys
from pathlib import Path
from typing import Optional, Dict, Any
import json

# Suppress liveries scanner errors by setting a mock DCS path
os.environ.setdefault('DCS_HOME', str(Path.home() / '.dcs'))

try:
    import dcs
except Exception as e:
    print(f"Warning: Error initializing pydcs: {e}")
    print("This may be due to missing DCS installation or liveries issues.")
    print("Attempting to continue with limited functionality...")
    import dcs


class MizHandler:
    """Handler class for DCS mission (.miz) files"""

    def __init__(self, miz_path: Optional[str] = None):
        """
        Initialize MizHandler

        Args:
            miz_path: Path to .miz file to load (optional)
        """
        self.mission: Optional[dcs.Mission] = None
        self.miz_path: Optional[Path] = None

        if miz_path:
            self.load(miz_path)

    def load(self, miz_path: str) -> None:
        """
        Load a .miz file

        Args:
            miz_path: Path to .miz file
        """
        self.miz_path = Path(miz_path)
        if not self.miz_path.exists():
            raise FileNotFoundError(f"MIZ file not found: {miz_path}")

        self.mission = dcs.Mission()
        self.mission.load_file(str(self.miz_path))
        print(f"✅ Loaded mission: {self.miz_path.name}")

    def save(self, output_path: Optional[str] = None) -> None:
        """
        Save the mission to a .miz file

        Args:
            output_path: Path to save .miz file (defaults to original path)
        """
        if not self.mission:
            raise ValueError("No mission loaded")

        save_path = Path(output_path) if output_path else self.miz_path
        self.mission.save(str(save_path))
        print(f"✅ Saved mission: {save_path.name}")

    def get_mission_info(self) -> Dict[str, Any]:
        """
        Get basic mission information

        Returns:
            Dictionary with mission metadata
        """
        if not self.mission:
            raise ValueError("No mission loaded")

        info = {
            "mission_name": self.mission.description_text or "Unnamed",
            "terrain": self.mission.terrain.name if self.mission.terrain else "Unknown",
            "date": str(self.mission.start_time),
            "weather": self.mission.weather.dict() if hasattr(self.mission.weather, 'dict') else "N/A",
            "coalition_blue_countries": len(self.mission.country(dcs.countries.USA.name).plane_group) if self.mission.country(dcs.countries.USA.name) else 0,
            "coalition_red_countries": len(self.mission.country(dcs.countries.Russia.name).plane_group) if self.mission.country(dcs.countries.Russia.name) else 0,
        }

        return info

    def list_aircraft_groups(self) -> Dict[str, list]:
        """
        List all aircraft groups in the mission

        Returns:
            Dictionary with blue and red aircraft groups
        """
        if not self.mission:
            raise ValueError("No mission loaded")

        groups = {
            "blue": [],
            "red": []
        }

        # Iterate through countries and their aircraft groups
        for country in self.mission.coalition["blue"].countries.values():
            for group in country.plane_group:
                groups["blue"].append({
                    "name": group.name,
                    "units": len(group.units),
                    "country": country.name
                })

        for country in self.mission.coalition["red"].countries.values():
            for group in country.plane_group:
                groups["red"].append({
                    "name": group.name,
                    "units": len(group.units),
                    "country": country.name
                })

        return groups

    def export_to_json(self, output_path: str) -> None:
        """
        Export mission information to JSON

        Args:
            output_path: Path to save JSON file
        """
        if not self.mission:
            raise ValueError("No mission loaded")

        info = self.get_mission_info()
        groups = self.list_aircraft_groups()

        data = {
            "mission_info": info,
            "aircraft_groups": groups
        }

        with open(output_path, 'w', encoding='utf-8') as f:
            json.dump(data, f, indent=2, default=str)

        print(f"✅ Exported mission data to: {output_path}")


def quick_inspect(miz_path: str) -> None:
    """
    Quick inspection of a .miz file - prints basic info

    Args:
        miz_path: Path to .miz file
    """
    handler = MizHandler(miz_path)
    info = handler.get_mission_info()
    groups = handler.list_aircraft_groups()

    print("\n" + "="*50)
    print(f"MISSION: {info['mission_name']}")
    print("="*50)
    print(f"Terrain: {info['terrain']}")
    print(f"Date: {info['date']}")
    print(f"\nBlue Aircraft Groups: {len(groups['blue'])}")
    for group in groups['blue']:
        print(f"  - {group['name']} ({group['units']} units, {group['country']})")
    print(f"\nRed Aircraft Groups: {len(groups['red'])}")
    for group in groups['red']:
        print(f"  - {group['name']} ({group['units']} units, {group['country']})")
    print("="*50 + "\n")


if __name__ == "__main__":
    import sys

    if len(sys.argv) < 2:
        print("Usage: python miz_utils.py <path_to_miz_file>")
        sys.exit(1)

    quick_inspect(sys.argv[1])
