"""
Lightweight MIZ File Inspector
Inspects DCS mission files without requiring full DCS installation
"""

import zipfile
import json
from pathlib import Path
from typing import Dict, Any, Optional


def parse_lua_table(lua_content: str) -> Dict[str, Any]:
    """
    Basic Lua table parser for mission files
    Note: This is a simplified parser for basic mission data
    """
    # This is a very basic parser - real Lua parsing is complex
    # For now, we'll extract key information using string parsing
    data = {}

    # Extract mission name
    if 'descriptionText' in lua_content:
        start = lua_content.find('descriptionText')
        if start != -1:
            start = lua_content.find('"', start) + 1
            end = lua_content.find('"', start)
            if end != -1:
                data['mission_name'] = lua_content[start:end]

    # Extract date
    if 'start_time' in lua_content:
        start = lua_content.find('start_time')
        if start != -1:
            start = lua_content.find('=', start) + 1
            end = lua_content.find(',', start)
            if end == -1:
                end = lua_content.find('\n', start)
            if end != -1:
                data['start_time'] = lua_content[start:end].strip()

    return data


class LightweightMizInspector:
    """Lightweight inspector for MIZ files that works without DCS installation"""

    def __init__(self, miz_path: str):
        """
        Initialize inspector

        Args:
            miz_path: Path to .miz file
        """
        self.miz_path = Path(miz_path)
        if not self.miz_path.exists():
            raise FileNotFoundError(f"MIZ file not found: {miz_path}")

        self.mission_data: Optional[Dict[str, Any]] = None
        self.raw_mission: Optional[str] = None

    def extract_files(self) -> Dict[str, bytes]:
        """
        Extract files from MIZ archive

        Returns:
            Dictionary of filename -> file content
        """
        files = {}
        with zipfile.ZipFile(self.miz_path, 'r') as zip_file:
            for filename in zip_file.namelist():
                files[filename] = zip_file.read(filename)
        return files

    def inspect(self) -> Dict[str, Any]:
        """
        Inspect the MIZ file and extract information

        Returns:
            Dictionary with mission information
        """
        files = self.extract_files()

        # Read mission file (Lua format)
        if 'mission' in files:
            self.raw_mission = files['mission'].decode('utf-8', errors='ignore')
            self.mission_data = parse_lua_table(self.raw_mission)

        # Build file list
        file_list = list(files.keys())

        # Count groups (basic string search)
        blue_groups = self.raw_mission.count('[1] =') if self.raw_mission else 0
        red_groups = self.raw_mission.count('[2] =') if self.raw_mission else 0

        info = {
            'file_name': self.miz_path.name,
            'file_size_kb': self.miz_path.stat().st_size / 1024,
            'files_in_archive': file_list,
            'mission_name': self.mission_data.get('mission_name', 'Unknown') if self.mission_data else 'Unknown',
            'estimated_blue_entries': blue_groups,
            'estimated_red_entries': red_groups,
        }

        return info

    def extract_raw_mission_text(self) -> str:
        """Get raw mission file content"""
        if not self.raw_mission:
            self.inspect()
        return self.raw_mission or ""

    def export_to_json(self, output_path: str) -> None:
        """
        Export mission info to JSON

        Args:
            output_path: Path to save JSON file
        """
        info = self.inspect()

        with open(output_path, 'w', encoding='utf-8') as f:
            json.dump(info, f, indent=2, default=str)

        print(f"✅ Exported mission info to: {output_path}")


def quick_inspect(miz_path: str) -> None:
    """
    Quick inspection of a .miz file - prints basic info

    Args:
        miz_path: Path to .miz file
    """
    inspector = LightweightMizInspector(miz_path)
    info = inspector.inspect()

    print("\n" + "="*60)
    print(f"MIZ FILE INSPECTION")
    print("="*60)
    print(f"File: {info['file_name']}")
    print(f"Size: {info['file_size_kb']:.2f} KB")
    print(f"\nMission Name: {info['mission_name']}")
    print(f"\nArchive Contents:")
    for filename in info['files_in_archive']:
        print(f"  - {filename}")
    print(f"\nEstimated Coalition Entries:")
    print(f"  Blue (Coalition 1): ~{info['estimated_blue_entries']} entries")
    print(f"  Red (Coalition 2): ~{info['estimated_red_entries']} entries")
    print("\nNote: This is a lightweight inspection without full DCS parsing.")
    print("For detailed analysis, use miz_utils.py with DCS installation.")
    print("="*60 + "\n")


if __name__ == "__main__":
    import sys

    if len(sys.argv) < 2:
        print("Usage: python miz_inspector.py <path_to_miz_file>")
        sys.exit(1)

    quick_inspect(sys.argv[1])
