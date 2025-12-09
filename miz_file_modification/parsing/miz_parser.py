#!/usr/bin/env python3
"""
MIZ file parsing utilities - handles extraction and repackaging of .miz files.

.miz files are ZIP archives containing Lua mission files and resources.
This module provides clean extract/repackage workflow for mission modification.
"""

import zipfile
import os
import shutil
from pathlib import Path
from typing import Optional


class MizParser:
    """Handler for extracting and repackaging .miz mission files."""

    def __init__(self, miz_path: str):
        """
        Initialize parser with a .miz file path.

        Args:
            miz_path: Path to the .miz file
        """
        self.miz_path = Path(miz_path)
        self.extract_dir: Optional[Path] = None
        self.mission_file: Optional[Path] = None

    def extract(self, output_dir: Optional[str] = None) -> Path:
        """
        Extract .miz file to a directory.

        Args:
            output_dir: Optional directory path. If not provided, creates temp directory.

        Returns:
            Path to extraction directory
        """
        if output_dir:
            self.extract_dir = Path(output_dir)
        else:
            # Create temp directory based on miz filename
            self.extract_dir = Path(f"temp_{self.miz_path.stem}")

        self.extract_dir.mkdir(exist_ok=True)

        print(f"Extracting {self.miz_path}...")
        with zipfile.ZipFile(self.miz_path, 'r') as zip_ref:
            zip_ref.extractall(self.extract_dir)

        # Store path to mission file for convenience
        self.mission_file = self.extract_dir / "mission"

        print(f"Extracted to: {self.extract_dir}")
        return self.extract_dir

    def repackage(self, output_miz: str, cleanup: bool = True) -> None:
        """
        Repackage extracted files back into a .miz file.

        Args:
            output_miz: Path for the output .miz file
            cleanup: If True, removes the extraction directory after repackaging
        """
        if not self.extract_dir or not self.extract_dir.exists():
            raise ValueError("No extracted directory found. Call extract() first.")

        print(f"Repackaging to: {output_miz}...")
        with zipfile.ZipFile(output_miz, 'w', zipfile.ZIP_DEFLATED) as zip_out:
            for root, dirs, files in os.walk(self.extract_dir):
                for file in files:
                    file_path = Path(root) / file
                    arcname = file_path.relative_to(self.extract_dir)
                    zip_out.write(file_path, arcname)

        print(f"Successfully created: {output_miz}")

        if cleanup:
            self.cleanup()

    def cleanup(self) -> None:
        """Remove the extraction directory."""
        if self.extract_dir and self.extract_dir.exists():
            print(f"Cleaning up: {self.extract_dir}")
            shutil.rmtree(self.extract_dir)
            self.extract_dir = None
            self.mission_file = None

    def get_mission_content(self) -> str:
        """
        Read the mission file content.

        Returns:
            Mission file content as string
        """
        if not self.mission_file or not self.mission_file.exists():
            raise ValueError("Mission file not found. Call extract() first.")

        with open(self.mission_file, 'r', encoding='utf-8') as f:
            return f.read()

    def write_mission_content(self, content: str) -> None:
        """
        Write content to the mission file.

        Args:
            content: Mission file content to write
        """
        if not self.mission_file:
            raise ValueError("Mission file not found. Call extract() first.")

        with open(self.mission_file, 'w', encoding='utf-8') as f:
            f.write(content)

        print(f"Mission file updated: {self.mission_file}")


def quick_modify(input_miz: str, output_miz: str, modify_func, cleanup: bool = True):
    """
    Quick workflow: extract, modify, repackage in one function.

    Args:
        input_miz: Path to input .miz file
        output_miz: Path to output .miz file
        modify_func: Function that takes mission content string and returns modified content
        cleanup: Whether to cleanup temp files after repackaging

    Example:
        def remove_ships(mission_content):
            # modify mission_content
            return modified_content

        quick_modify("input.miz", "output.miz", remove_ships)
    """
    parser = MizParser(input_miz)

    try:
        # Extract
        parser.extract()

        # Read mission content
        content = parser.get_mission_content()

        # Apply modification
        modified_content = modify_func(content)

        # Write modified content
        parser.write_mission_content(modified_content)

        # Repackage
        parser.repackage(output_miz, cleanup=cleanup)

    except Exception as e:
        # Cleanup on error
        parser.cleanup()
        raise e


if __name__ == "__main__":
    import sys

    if len(sys.argv) < 2:
        print("MIZ Parser - Extract and repackage DCS mission files")
        print("\nUsage:")
        print("  Extract:   python miz_parser.py extract <input.miz> [output_dir]")
        print("  Repackage: python miz_parser.py repackage <extract_dir> <output.miz>")
        print("\nExample:")
        print('  python miz_parser.py extract "../miz-files/input/mission.miz" "temp_mission"')
        print('  # ... modify files in temp_mission/ ...')
        print('  python miz_parser.py repackage "temp_mission" "../miz-files/output/modified.miz"')
        sys.exit(1)

    command = sys.argv[1].lower()

    if command == "extract":
        if len(sys.argv) < 3:
            print("Error: Missing input .miz file")
            sys.exit(1)

        input_miz = sys.argv[2]
        output_dir = sys.argv[3] if len(sys.argv) > 3 else None

        parser = MizParser(input_miz)
        extract_path = parser.extract(output_dir)
        print(f"\nMission file: {parser.mission_file}")

    elif command == "repackage":
        if len(sys.argv) < 4:
            print("Error: Missing extract_dir or output .miz file")
            sys.exit(1)

        extract_dir = sys.argv[2]
        output_miz = sys.argv[3]

        # Create temporary parser to use repackage functionality
        parser = MizParser("dummy.miz")
        parser.extract_dir = Path(extract_dir)
        parser.repackage(output_miz, cleanup=False)

    else:
        print(f"Error: Unknown command '{command}'")
        print("Valid commands: extract, repackage")
        sys.exit(1)
