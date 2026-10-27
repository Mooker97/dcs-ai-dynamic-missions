"""
Mission Generation MVP Test Script

Quick test of the mission generation pipeline.

Usage:
    python test_mvp.py
"""

from pipeline import generate_mission, parse, design


def test_full_pipeline():
    """Test complete pipeline: prompt → intent → structure → (mock) .miz"""
    print("="*80)
    print("TEST: Full Mission Generation Pipeline (MVP)")
    print("="*80)

    test_prompts = [
        "Create a 4-ship F-16 SEAD mission in Persian Gulf at dawn with heavy SAM threats",
        "2 F/A-18s SEAD in Syria at night, light threats, need tanker",
        "SEAD mission with 2 Vipers in Caucasus, moderate SAMs"
    ]

    for i, prompt in enumerate(test_prompts, 1):
        print(f"\n--- Test {i}/{len(test_prompts)} ---")
        print(f"Prompt: {prompt}\n")

        result = generate_mission(prompt, output_dir="miz-files/output")

        if result["success"]:
            print(f"✓ SUCCESS")
            print(f"  Output: {result['miz_path']}")
            print(f"\n  Briefing Preview:")
            preview = result['briefing'][:300] + "..." if len(result['briefing']) > 300 else result['briefing']
            print(f"  {preview}")
        else:
            print(f"✗ FAILED")
            print(f"  Error: {result['error']}")

        print()


def test_intent_parser():
    """Test intent parser independently"""
    print("="*80)
    print("TEST: Intent Parser")
    print("="*80)

    prompt = "Create a 4-ship F-16 SEAD mission in Persian Gulf at dawn with heavy SAM threats"
    print(f"\nPrompt: {prompt}\n")

    intent = parse(prompt)
    intent_dict = intent.to_dict()

    print("Parsed Intent:")
    print(f"  Mission Type: {intent_dict['mission_type']}")
    print(f"  Theater: {intent_dict['theater']}")
    print(f"  Time of Day: {intent_dict['time_of_day']}")
    print(f"  Aircraft: {intent_dict['player']['aircraft']} x{intent_dict['player']['count']}")
    print(f"  Threat Level: {intent_dict['threats']['level']}")
    print(f"  Support: AWACS={intent_dict['support']['awacs']}, Tanker={intent_dict['support']['tanker']}")
    print()


def test_mission_designer():
    """Test mission designer independently"""
    print("="*80)
    print("TEST: Mission Designer")
    print("="*80)

    prompt = "Create a 4-ship F-16 SEAD mission in Persian Gulf at dawn with heavy SAM threats"
    print(f"\nPrompt: {prompt}\n")

    intent = parse(prompt)
    structure = design(intent)

    print("Mission Structure:")
    print(f"  Template: {structure['template']}")
    print(f"  Theater: {structure['theater']}")
    print(f"  Time: {structure['time']} seconds ({structure['time'] / 3600:.1f} hours)")
    print(f"\n  Blue Forces:")
    print(f"    Player: {structure['blue_forces']['player_flight']['template']}")
    if 'awacs' in structure['blue_forces']:
        print(f"    AWACS: {structure['blue_forces']['awacs']['template']}")
    if 'tanker' in structure['blue_forces']:
        print(f"    Tanker: {structure['blue_forces']['tanker']['template']}")
    print(f"\n  Red Forces:")
    print(f"    SAM Sites: {len(structure['red_forces']['sam_sites'])}")
    for sam in structure['red_forces']['sam_sites']:
        print(f"      - {sam['template']} at {sam['position']}")
    print(f"    CAP Flights: {len(structure['red_forces']['cap_flights'])}")
    print(f"\n  Lua Scripts:")
    for script in structure['lua_scripts']:
        print(f"    - {script}")
    print()


def main():
    """Run all tests"""
    print("\n" + "█"*80)
    print("  DCS MISSION GENERATION PIPELINE - MVP TEST SUITE")
    print("█"*80 + "\n")

    try:
        # Test individual components
        test_intent_parser()
        test_mission_designer()

        # Test full pipeline
        test_full_pipeline()

        print("="*80)
        print("TEST SUITE COMPLETE")
        print("="*80)
        print("\nNOTE: Mission Builder is currently a skeleton.")
        print("No actual .miz files are generated yet.")
        print("Next steps:")
        print("  1. Implement miz-modifier group operations")
        print("  2. Create template .miz files for each theater")
        print("  3. Implement unit template loading system")
        print("  4. Implement Lua script injection")
        print("  5. Add validator")

    except Exception as e:
        print(f"\n✗ TEST SUITE FAILED")
        print(f"Error: {e}")
        import traceback
        traceback.print_exc()


if __name__ == "__main__":
    main()
