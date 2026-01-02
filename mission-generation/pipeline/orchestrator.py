"""
Mission Generation Orchestrator

Main entry point for mission generation pipeline.
Coordinates: Intent Parser → Mission Designer → Mission Builder
"""

from typing import Dict, Any
from pathlib import Path
from . import parse, design
from .mission_builder import build


def generate_mission(prompt: str, output_dir: str = None) -> Dict[str, Any]:
    """
    Generate a complete DCS mission from natural language prompt.

    Args:
        prompt: Natural language mission description
            Example: "Create a 4-ship F-16 SEAD mission in Persian Gulf at dawn"
        output_dir: Directory to save output .miz file
            Default: ../miz-files/output/

    Returns:
        {
            "success": bool,
            "miz_path": str (if success),
            "briefing": str (if success),
            "error": str (if failure),
            "intent": dict,
            "structure": dict
        }

    Example:
        >>> result = generate_mission(
        ...     "Create a 4-ship F-16 SEAD mission in Persian Gulf at dawn",
        ...     output_dir="miz-files/output/"
        ... )
        >>> if result["success"]:
        ...     print(f"Mission created: {result['miz_path']}")
        ... else:
        ...     print(f"Error: {result['error']}")
    """

    # Set default output directory
    if output_dir is None:
        output_dir = str(Path(__file__).parent.parent.parent / "miz-files" / "output")

    try:
        # Step 1: Parse intent from natural language
        print(f"[Orchestrator] Parsing prompt: {prompt}")
        intent = parse(prompt)
        print(f"[Orchestrator] Intent: {intent.to_dict()}")

        # Step 2: Design mission structure
        print(f"[Orchestrator] Designing mission...")
        structure = design(intent)
        print(f"[Orchestrator] Mission structure created")

        # Step 3: Build .miz file
        print(f"[Orchestrator] Building .miz file...")
        miz_path = build(structure, output_dir)
        print(f"[Orchestrator] Mission built: {miz_path}")

        # Step 4: Validate (TODO: implement validator)
        # validation = validator.validate(miz_path)
        # if not validation["valid"]:
        #     return {
        #         "success": False,
        #         "error": "Validation failed",
        #         "details": validation["errors"]
        #     }

        # Success
        return {
            "success": True,
            "miz_path": miz_path,
            "briefing": structure["briefing"],
            "intent": intent.to_dict(),
            "structure": structure,
            "warnings": []
        }

    except Exception as e:
        # Error handling
        return {
            "success": False,
            "error": str(e),
            "intent": intent.to_dict() if 'intent' in locals() else None,
            "structure": structure if 'structure' in locals() else None
        }


def generate_mission_from_intent(intent, output_dir: str = None) -> Dict[str, Any]:
    """
    Generate mission from pre-parsed MissionIntent object.

    Useful for programmatic mission generation without natural language parsing.

    Args:
        intent: MissionIntent object
        output_dir: Directory to save output .miz file

    Returns:
        Same as generate_mission()
    """

    if output_dir is None:
        output_dir = str(Path(__file__).parent.parent.parent / "miz-files" / "output")

    try:
        # Skip parsing, go straight to design
        print(f"[Orchestrator] Using provided intent: {intent.to_dict()}")
        structure = design(intent)

        miz_path = build(structure, output_dir)

        return {
            "success": True,
            "miz_path": miz_path,
            "briefing": structure["briefing"],
            "intent": intent.to_dict(),
            "structure": structure,
            "warnings": []
        }

    except Exception as e:
        return {
            "success": False,
            "error": str(e),
            "intent": intent.to_dict(),
            "structure": structure if 'structure' in locals() else None
        }


# Command-line interface for testing
if __name__ == "__main__":
    import sys

    if len(sys.argv) < 2:
        print("Usage: python orchestrator.py <mission prompt>")
        print("\nExample:")
        print('  python orchestrator.py "Create a 4-ship F-16 SEAD mission in Persian Gulf at dawn with heavy SAMs"')
        sys.exit(1)

    prompt = " ".join(sys.argv[1:])
    result = generate_mission(prompt)

    print("\n" + "="*80)
    if result["success"]:
        print("SUCCESS!")
        print(f"Mission file: {result['miz_path']}")
        print(f"\nBriefing:\n{result['briefing']}")
    else:
        print("FAILED!")
        print(f"Error: {result['error']}")
    print("="*80)
