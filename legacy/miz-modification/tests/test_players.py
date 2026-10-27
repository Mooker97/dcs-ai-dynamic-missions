"""
Test script for utils/players.py

Tests aircraft control type detection (Player/Client/AI).
"""

import sys
from pathlib import Path

# Add parent directory to path for imports
sys.path.insert(0, str(Path(__file__).parent.parent))

from parsing.miz_parser import MizParser
from utils.players import (
    is_player_aircraft,
    is_client_aircraft,
    is_playable_aircraft,
    is_ai_aircraft,
    get_aircraft_control_type,
    get_skill_level,
    find_all_playable_aircraft,
    find_all_ai_aircraft,
    validate_skill_level,
    AI_SKILL_LEVELS,
    PLAYER_DESIGNATIONS
)


def test_aircraft_detection():
    """Test aircraft control type detection with test.miz."""
    print("=" * 60)
    print("Aircraft Control Type Detection Test")
    print("=" * 60)

    # Test mission
    test_mission = Path(__file__).parent / "test.miz"

    if not test_mission.exists():
        print(f"Error: Test mission not found at {test_mission}")
        return False

    print(f"Test mission: {test_mission.name}\n")

    # Parse mission
    parser = MizParser(str(test_mission))
    parser.extract()
    content = parser.get_mission_content()

    # Test 1: Find playable aircraft
    print("Test 1: Find playable aircraft (Player/Client)")
    playable = find_all_playable_aircraft(content)
    print(f"  Found {len(playable)} playable slot(s)")

    if playable:
        for aircraft in playable:
            print(f"    - {aircraft['name']} ({aircraft['type']}) - {aircraft['control_type']}")
    else:
        print("    (No playable slots in mission)")

    # Test 2: Find AI aircraft
    print("\nTest 2: Find AI-controlled aircraft")
    ai_aircraft = find_all_ai_aircraft(content)
    print(f"  Found {len(ai_aircraft)} AI aircraft")

    for aircraft in ai_aircraft[:5]:  # Show first 5
        print(f"    - {aircraft['name']} ({aircraft['type']}) - Skill: {aircraft['skill']}")

    if len(ai_aircraft) > 5:
        print(f"    ... and {len(ai_aircraft) - 5} more")

    # Test 3: Check specific aircraft (F-16)
    print("\nTest 3: Check F-16 control type")
    import re
    f16_pattern = r'\[(\d+)\]\s*=\s*\{.*?\["type"\]\s*=\s*"F-16C_50".*?\},\s*--\s*end\s*of\s*\[\d+\]'
    f16_match = re.search(f16_pattern, content, re.DOTALL)

    if f16_match:
        f16_block = f16_match.group(0)
        control_type = get_aircraft_control_type(f16_block)
        skill = get_skill_level(f16_block)

        print(f"  F-16C_50 Control Type: {control_type}")
        print(f"  F-16C_50 Skill: {skill}")
        print(f"  Is Playable: {is_playable_aircraft(f16_block)}")
        print(f"  Is AI: {is_ai_aircraft(f16_block)}")
    else:
        print("  F-16 not found in mission")

    # Test 4: Skill level validation
    print("\nTest 4: Skill level validation")

    valid_skills = ['High', 'Client', 'Player', 'Average']
    invalid_skills = ['Expert', 'Novice', 'Beginner']

    print("  Valid skills:")
    for skill in valid_skills:
        result = validate_skill_level(skill)
        print(f"    {skill}: {result}")
        assert result == True, f"Expected {skill} to be valid"

    print("  Invalid skills:")
    for skill in invalid_skills:
        result = validate_skill_level(skill)
        print(f"    {skill}: {result}")
        assert result == False, f"Expected {skill} to be invalid"

    # Test 5: Constants
    print("\nTest 5: Check constants")
    print(f"  AI_SKILL_LEVELS: {AI_SKILL_LEVELS}")
    print(f"  PLAYER_DESIGNATIONS: {PLAYER_DESIGNATIONS}")
    assert len(AI_SKILL_LEVELS) == 5
    assert len(PLAYER_DESIGNATIONS) == 2

    print("\n" + "=" * 60)
    print("All aircraft detection tests passed!")
    print("=" * 60)

    # Summary
    print("\nSummary:")
    print(f"  Playable slots: {len(playable)}")
    print(f"  AI aircraft: {len(ai_aircraft)}")
    print(f"  Total aircraft: {len(playable) + len(ai_aircraft)}")

    # Cleanup
    parser.cleanup()

    return True


if __name__ == "__main__":
    success = test_aircraft_detection()
    sys.exit(0 if success else 1)
