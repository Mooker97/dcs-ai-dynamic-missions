"""
List all voices available in your ElevenLabs account.
Shows custom voices, default voices, and their IDs.

Usage:
    python list_my_voices.py
    python list_my_voices.py --json  # Save to my_voices.json
"""

import os
import sys
import json
from elevenlabs.client import ElevenLabs

# Try to load .env file if available
try:
    from dotenv import load_dotenv
    load_dotenv()
except ImportError:
    pass


def format_voice_info(voice, include_details=True):
    """Format voice information for display."""
    # Check if custom voice
    category = getattr(voice, 'category', 'unknown')
    is_custom = 'cloned' in category.lower() or 'generated' in category.lower() or 'premade' not in category.lower()

    marker = "[CUSTOM]" if is_custom else "[DEFAULT]"

    lines = [f"\n{marker} {voice.name}"]
    lines.append(f"  ID: {voice.voice_id}")

    if include_details:
        if hasattr(voice, 'description') and voice.description:
            lines.append(f"  Description: {voice.description}")

        if hasattr(voice, 'labels') and voice.labels:
            labels = voice.labels
            gender = labels.get('gender', 'N/A')
            age = labels.get('age', 'N/A')
            accent = labels.get('accent', 'N/A')
            use_case = labels.get('use case', 'N/A')

            lines.append(f"  Gender: {gender}")
            lines.append(f"  Age: {age}")
            lines.append(f"  Accent: {accent}")
            lines.append(f"  Use Case: {use_case}")

        lines.append(f"  Category: {category}")

    return "\n".join(lines)


def list_voices(save_json=False):
    """List all voices in the account."""
    # Check API key
    api_key = os.getenv("ELEVENLABS_API_KEY")
    if not api_key:
        print("ERROR: ELEVENLABS_API_KEY not found in environment!")
        print("\nPlease set it using:")
        print("  Windows: setx ELEVENLABS_API_KEY \"your-key-here\"")
        print("  Linux/Mac: export ELEVENLABS_API_KEY=\"your-key-here\"")
        sys.exit(1)

    # Initialize client
    print("Connecting to ElevenLabs...")
    client = ElevenLabs(api_key=api_key)

    # Get all voices
    try:
        response = client.voices.get_all()
    except Exception as e:
        print(f"ERROR: Failed to fetch voices: {e}")
        sys.exit(1)

    voices = response.voices
    if not voices:
        print("No voices found in your account.")
        return

    # Separate custom and default voices
    custom_voices = []
    default_voices = []

    for voice in voices:
        category = getattr(voice, 'category', 'unknown').lower()
        is_custom = 'cloned' in category or 'generated' in category or 'premade' not in category

        if is_custom:
            custom_voices.append(voice)
        else:
            default_voices.append(voice)

    # Display summary
    print("\n" + "=" * 80)
    print("YOUR ELEVENLABS VOICES")
    print("=" * 80)
    print(f"\nTotal Voices: {len(voices)}")
    print(f"  Custom Voices: {len(custom_voices)}")
    print(f"  Default Voices: {len(default_voices)}")
    print("=" * 80)

    # Display custom voices first
    if custom_voices:
        print("\n" + "=" * 80)
        print("CUSTOM VOICES (Your Cloned/Designed Voices)")
        print("=" * 80)
        for voice in custom_voices:
            print(format_voice_info(voice))
            print("-" * 80)

    # Display default voices
    if default_voices:
        print("\n" + "=" * 80)
        print("DEFAULT VOICES (ElevenLabs Premade)")
        print("=" * 80)
        for voice in default_voices:
            print(format_voice_info(voice, include_details=False))
            print("-" * 80)

    # Save to JSON if requested
    if save_json:
        voices_data = []
        for voice in voices:
            category = getattr(voice, 'category', 'unknown').lower()
            is_custom = 'cloned' in category or 'generated' in category or 'premade' not in category

            voice_info = {
                'name': voice.name,
                'voice_id': voice.voice_id,
                'category': category,
                'is_custom': is_custom,
            }

            if hasattr(voice, 'labels') and voice.labels:
                voice_info['labels'] = dict(voice.labels)

            if hasattr(voice, 'description') and voice.description:
                voice_info['description'] = voice.description

            voices_data.append(voice_info)

        output_file = 'my_voices.json'
        with open(output_file, 'w', encoding='utf-8') as f:
            json.dump(voices_data, f, indent=2, ensure_ascii=False)

        print(f"\n✅ Voice data saved to: {output_file}")

    # Usage tips
    print("\n" + "=" * 80)
    print("USAGE TIPS")
    print("=" * 80)
    print("\nTo use a voice in generation:")
    print("  python generate_voice_lines.py --voice-id <VOICE_ID>")
    print("\nTo use custom voices for different categories:")
    print("  1. Copy a voice ID from above")
    print("  2. Create voice_config.json (see CUSTOM-VOICES.md)")
    print("  3. Run generate_with_custom_voices.py")
    print("\nFor custom voice management:")
    print("  See CUSTOM-VOICES.md for complete guide")


def main():
    """Main entry point."""
    import argparse

    parser = argparse.ArgumentParser(
        description="List all voices in your ElevenLabs account",
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )

    parser.add_argument(
        '--json',
        action='store_true',
        help='Save voice data to my_voices.json'
    )

    args = parser.parse_args()
    list_voices(save_json=args.json)


if __name__ == "__main__":
    main()
