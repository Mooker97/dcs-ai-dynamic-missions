#!/usr/bin/env python3
"""
Compile Lua modules into single dynamic_mission_lib.lua file.

Usage:
    python build.py

Output:
    dynamic_mission_lib.lua - Single compiled library file
"""

from pathlib import Path
from datetime import datetime


def load_module(module_path):
    """Load Lua module file."""
    with open(module_path, 'r', encoding='utf-8') as f:
        return f.read()


def compile_library():
    """Compile all modules into single file."""

    # Module load order (dependencies first)
    modules = [
        # Core modules (order matters - init first, event handler last)
        "core/init.lua",
        "core/utils.lua",

        # Randomizers (used by spawners)
        "randomizers/location.lua",
        "randomizers/timing.lua",
        "randomizers/loadout.lua",

        # Spawners (use randomizers)
        "spawners/air_spawner.lua",
        "spawners/ground_spawner.lua",
        "spawners/naval_spawner.lua",

        # Behaviors (use spawners and randomizers)
        "behaviors/adaptive_difficulty.lua",
        "behaviors/reinforcements.lua",

        # Utils
        "utils/templates.lua",
        "utils/zones.lua",
        "utils/validation.lua",

        # Event handler (last - uses all other modules)
        "core/event_handler.lua"
    ]

    # Header
    compiled = f"""-- Dynamic Mission Library
-- Generated: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}
-- DO NOT EDIT - Generated from modules
-- Source: lua-library/ modules

"""

    # Compile modules
    library_path = Path(__file__).parent
    loaded_modules = []

    for module_path in modules:
        full_path = library_path / module_path

        # Check if module exists
        if not full_path.exists():
            print(f"[WARNING] Module not found (skipping): {module_path}")
            continue

        print(f"[LOAD] {module_path}")

        compiled += f"\n-- ============================================\n"
        compiled += f"-- Module: {module_path}\n"
        compiled += f"-- ============================================\n\n"
        compiled += load_module(full_path)
        compiled += "\n"

        loaded_modules.append(module_path)

    # Write compiled file
    output_path = library_path / "dynamic_mission_lib.lua"
    with open(output_path, 'w', encoding='utf-8') as f:
        f.write(compiled)

    # Report
    print(f"\n[OK] Library compiled successfully!")
    print(f"Output: {output_path}")
    print(f"Modules: {len(loaded_modules)} / {len(modules)}")
    print(f"Size: {len(compiled):,} characters")

    # List loaded modules
    print(f"\nLoaded modules:")
    for module in loaded_modules:
        print(f"  [OK] {module}")

    # List missing modules
    missing = set(modules) - set(loaded_modules)
    if missing:
        print(f"\n[WARNING] Missing modules (not yet implemented):")
        for module in missing:
            print(f"  [SKIP] {module}")

    return output_path


if __name__ == "__main__":
    try:
        compile_library()
    except Exception as e:
        print(f"\n[ERROR] Compilation failed: {e}")
        import traceback
        traceback.print_exc()
        exit(1)
