#!/usr/bin/env python3
"""
Remove ship groups from DCS mission files.

This is a convenience wrapper for remove_groups.py with 'ship' type.
For more flexibility, use remove_groups.py directly.
"""

import sys
import os

# Import the generic remove_groups functionality
from remove_groups import remove_groups, parse_unit_types


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Remove Ship Groups - DCS Mission Modifier")
        print("\nUsage: python remove_ship.py <input.miz> [output.miz]")
        print('\nExample: python remove_ship.py "../../miz-files/input/f16 A-G.miz" "../../miz-files/output/f16 A-G no ship.miz"')
        print("\nNote: For removing multiple unit types, use remove_groups.py instead")
        sys.exit(1)

    input_file = sys.argv[1]
    output_file = sys.argv[2] if len(sys.argv) > 2 else input_file.replace('.miz', '_no_ship.miz')

    if not os.path.exists(input_file):
        print(f"Error: Input file not found: {input_file}")
        sys.exit(1)

    # Use the generic remove_groups function with 'ship' type
    remove_groups(input_file, output_file, ['ship'])
