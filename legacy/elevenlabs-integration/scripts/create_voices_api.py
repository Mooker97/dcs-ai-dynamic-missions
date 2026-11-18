"""
Automated Voice Creation using ElevenLabs Voice Design API

Creates custom voices from text prompts and saves them to your ElevenLabs account.
Uses the Voice Design v3 API to generate and save voices programmatically.

Usage:
    python create_voices_api.py
    python create_voices_api.py --prompt "description of voice"
    python create_voices_api.py --from-file VOICE-PROMPTS-QUICK.md

Requirements:
    pip install elevenlabs python-dotenv
"""

import os
import sys
import json
import base64
from pathlib import Path
from elevenlabs.client import ElevenLabs

try:
    from dotenv import load_dotenv
    load_dotenv()
except ImportError:
    pass

# ============================================================================
# Voice Design Configuration
# ============================================================================

# Voices to create (name: prompt)
VOICES_TO_CREATE = {
    "AWACS - Magic": """Professional male AWACS controller, age 35-45, American accent with neutral/Midwest tone, highly trained military radio voice with perfect clarity and measured cadence. Calm and composed even during emergencies, technical vocabulary delivered naturally, authoritative presence without aggression. Clear diction for critical radio communications, steady breathing, confident tone from years of air battle management experience.""",

    "JTAC - Hawkeye": """Male JTAC (forward air controller), age 28-38, American accent with slight Southern or Western undertone, professional military radio voice that shifts from calm professionalism to controlled urgency under contact. Quick, precise speech patterns using brevity codes naturally, combat-experienced delivery that's direct and unambiguous. Clear radio voice even under stress, confident targeting calls, slightly elevated heart rate audible during hot situations.""",

    "Fighter - Viper (F)": """Female fighter pilot, age 26-35, American accent with confident and sharp tone, highly trained military aviator voice with quick reaction times and zero hesitation. Professional combat communications under high g-forces and stress, athletic breathing patterns, crisp and commanding delivery. Slightly elevated pitch during emergency callouts but always maintaining control, sharp tactical awareness in voice, decisive and direct communication style.""",

    "Ground - Anvil 6": """Male ground commander (senior NCO or officer), age 40-55, American accent with neutral tone, deeply experienced military voice that remains calm and measured even under heavy fire. Combat veteran delivery with professional military bearing, controlled breathing during contact, authoritative without shouting. Voice of experience and confidence from 20+ years service, steady cadence that provides reassurance to subordinates, clear tactical communications under any stress level.""",
}

# Test phrases for preview generation (must be 100-1000 characters)
TEST_PHRASES = [
    "All callsigns, mission is a go. Good hunting out there. We have clear skies and weapons free. Stay sharp and maintain radio discipline. Contact will be vectored as needed. Good luck.",
    "We need air support at our position immediately! Taking heavy fire from multiple directions! Request immediate close air support on our coordinates!",
    "Target destroyed. Good kill, good kill. Splash one hostile armor. Battle damage assessment shows complete destruction. Excellent work on that strike package.",
    "SAM launch detected! Missile in the air inbound from the north! All aircraft take defensive maneuvers immediately and deploy countermeasures!",
]

# ============================================================================
# Helper Functions
# ============================================================================

def save_audio_preview(audio_base64: str, filename: str) -> str:
    """Save base64 encoded audio to file."""
    audio_bytes = base64.b64decode(audio_base64)
    output_path = Path(filename)
    with open(output_path, 'wb') as f:
        f.write(audio_bytes)
    return str(output_path)


def design_voice(client: ElevenLabs, description: str, preview_text: str = None) -> dict:
    """
    Generate voice previews using Voice Design API.

    Returns:
        Dict with 'previews' array containing generated_voice_id and audio_base_64
    """
    print(f"\n  Generating previews...")
    print(f"  Description: {description[:80]}...")

    try:
        # Use the Voice Design endpoint
        response = client.text_to_voice.design(
            voice_description=description,
            text=preview_text,
            model_id="eleven_multilingual_ttv_v2",  # or "eleven_ttv_v3"
        )

        print(f"  [OK] Generated {len(response.previews)} preview(s)")
        return response

    except Exception as e:
        print(f"  [ERROR] Error generating voice: {e}")
        return None


def create_voice_from_preview(
    client: ElevenLabs,
    generated_voice_id: str,
    name: str,
    description: str
) -> str:
    """
    Create permanent voice from a preview.

    Returns:
        Voice ID of created voice
    """
    print(f"\n  Creating permanent voice: {name}")

    try:
        response = client.text_to_voice.create(
            voice_name=name,
            voice_description=description,
            generated_voice_id=generated_voice_id
        )

        print(f"  [OK] Voice created successfully!")
        print(f"  Voice ID: {response.voice_id}")
        return response.voice_id

    except Exception as e:
        print(f"  [ERROR] Error creating voice: {e}")
        return None


def list_existing_voices(client: ElevenLabs) -> dict:
    """Get list of existing voices to avoid duplicates."""
    response = client.voices.get_all()
    return {voice.name: voice.voice_id for voice in response.voices}


# ============================================================================
# Main Creation Workflow
# ============================================================================

def create_voices_interactive(client: ElevenLabs, voices_dict: dict):
    """
    Interactive voice creation workflow.
    Generates previews, lets user listen, then creates permanent voices.
    """
    print("=" * 80)
    print("ElevenLabs Voice Creation - Interactive Mode")
    print("=" * 80)

    # Check existing voices
    print("\nChecking existing voices...")
    existing_voices = list_existing_voices(client)
    print(f"Found {len(existing_voices)} existing voices in your account")

    # Track created voices
    created_voices = {}
    previews_dir = Path("voice_previews")
    previews_dir.mkdir(exist_ok=True)

    for voice_name, voice_description in voices_dict.items():
        print("\n" + "=" * 80)
        print(f"Creating: {voice_name}")
        print("=" * 80)

        # Skip if already exists
        if voice_name in existing_voices:
            print(f"[SKIP] Voice '{voice_name}' already exists with ID: {existing_voices[voice_name]}")
            response = input("  Create anyway? (y/N): ").strip().lower()
            if response != 'y':
                created_voices[voice_name] = existing_voices[voice_name]
                continue

        # Generate previews
        preview_text = TEST_PHRASES[0]  # Use first test phrase
        result = design_voice(client, voice_description, preview_text)

        if not result or not result.previews:
            print(f"  [ERROR] Failed to generate previews for {voice_name}")
            continue

        # Save preview audio files
        print(f"\n  Saving {len(result.previews)} preview(s) to {previews_dir}/")
        preview_files = []
        for i, preview in enumerate(result.previews):
            filename = previews_dir / f"{voice_name.replace(' ', '_')}_preview_{i+1}.mp3"
            save_audio_preview(preview.audio_base_64, str(filename))
            preview_files.append({
                'file': filename,
                'generated_voice_id': preview.generated_voice_id,
                'preview_obj': preview
            })
            print(f"    {i+1}. {filename}")

        # Let user choose
        print(f"\n  Generated {len(preview_files)} preview(s)")
        print(f"  Listen to files in: {previews_dir}/")
        print(f"  Preview text: \"{result.text}\"")

        while True:
            choice = input(f"\n  Select preview to save (1-{len(preview_files)}, or 's' to skip): ").strip()

            if choice.lower() == 's':
                print(f"  [SKIP] Skipping {voice_name}")
                break

            try:
                choice_idx = int(choice) - 1
                if 0 <= choice_idx < len(preview_files):
                    selected = preview_files[choice_idx]

                    # Create permanent voice
                    voice_id = create_voice_from_preview(
                        client,
                        selected['generated_voice_id'],
                        voice_name,
                        voice_description
                    )

                    if voice_id:
                        created_voices[voice_name] = voice_id
                        print(f"  [OK] {voice_name} saved to your account!")
                    break
                else:
                    print(f"  Invalid choice. Enter 1-{len(preview_files)}")
            except ValueError:
                print(f"  Invalid input. Enter a number or 's' to skip")

    # Summary
    print("\n" + "=" * 80)
    print("VOICE CREATION COMPLETE")
    print("=" * 80)
    print(f"\n[OK] Created {len(created_voices)} voice(s):")
    for name, voice_id in created_voices.items():
        print(f"  - {name}")
        print(f"    ID: {voice_id}")

    # Save to JSON
    output_file = "created_voices.json"
    with open(output_file, 'w') as f:
        json.dump(created_voices, f, indent=2)
    print(f"\n📄 Voice IDs saved to: {output_file}")

    # Update voice_config.json
    print("\n💡 Next steps:")
    print("1. Run: python list_my_voices.py")
    print("2. Update voice_config.json with new voice IDs")
    print("3. Run: python generate_with_custom_voices.py")


def create_voices_auto(client: ElevenLabs, voices_dict: dict):
    """
    Automatic voice creation - uses first preview for all voices.
    Faster but no quality control.
    """
    print("=" * 80)
    print("ElevenLabs Voice Creation - Automatic Mode")
    print("=" * 80)
    print("\n[WARNING] Auto mode: First preview will be used for each voice")
    print("Use interactive mode for quality control")

    created_voices = {}
    existing_voices = list_existing_voices(client)

    for voice_name, voice_description in voices_dict.items():
        print(f"\n[CREATE] Creating: {voice_name}")

        # Skip if exists
        if voice_name in existing_voices:
            print(f"  [SKIP] Already exists (ID: {existing_voices[voice_name]})")
            created_voices[voice_name] = existing_voices[voice_name]
            continue

        # Generate and use first preview
        result = design_voice(client, voice_description, TEST_PHRASES[0])

        if result and result.previews:
            voice_id = create_voice_from_preview(
                client,
                result.previews[0].generated_voice_id,
                voice_name,
                voice_description
            )

            if voice_id:
                created_voices[voice_name] = voice_id
        else:
            print(f"  [ERROR] Failed")

    # Summary
    print("\n" + "=" * 80)
    print(f"[OK] Created {len(created_voices)} voices")
    print("=" * 80)

    for name, voice_id in created_voices.items():
        print(f"{name}: {voice_id}")

    # Save
    with open("created_voices.json", 'w') as f:
        json.dump(created_voices, f, indent=2)


# ============================================================================
# CLI Interface
# ============================================================================

def main():
    import argparse

    parser = argparse.ArgumentParser(
        description="Create custom voices using ElevenLabs Voice Design API",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
    # Interactive mode (recommended)
    python create_voices_api.py

    # Automatic mode (faster, no quality control)
    python create_voices_api.py --auto

    # Create single voice from custom prompt
    python create_voices_api.py --prompt "Your voice description" --name "Voice Name"

    # Create voices from predefined list
    python create_voices_api.py --voices awacs,jtac,fighter
        """
    )

    parser.add_argument(
        '--auto',
        action='store_true',
        help='Automatic mode - use first preview for all voices (faster)'
    )

    parser.add_argument(
        '--prompt',
        help='Custom voice description prompt'
    )

    parser.add_argument(
        '--name',
        help='Name for custom voice (use with --prompt)'
    )

    parser.add_argument(
        '--voices',
        help='Comma-separated list of voices to create (awacs,jtac,fighter,ground)'
    )

    args = parser.parse_args()

    # Check API key
    api_key = os.getenv("ELEVENLABS_API_KEY")
    if not api_key:
        print("ERROR: ELEVENLABS_API_KEY not found in environment!")
        print("\nSet it using:")
        print("  Windows: setx ELEVENLABS_API_KEY \"your-key\"")
        print("  Linux/Mac: export ELEVENLABS_API_KEY=\"your-key\"")
        sys.exit(1)

    client = ElevenLabs(api_key=api_key)

    # Custom single voice
    if args.prompt:
        if not args.name:
            print("ERROR: --name required when using --prompt")
            sys.exit(1)

        voices_dict = {args.name: args.prompt}

        if args.auto:
            create_voices_auto(client, voices_dict)
        else:
            create_voices_interactive(client, voices_dict)
        return

    # Select specific voices
    if args.voices:
        voice_keys = {
            'awacs': 'AWACS - Magic',
            'jtac': 'JTAC - Hawkeye',
            'fighter': 'Fighter - Viper (F)',
            'ground': 'Ground - Anvil 6',
        }

        selected = args.voices.lower().split(',')
        voices_dict = {
            voice_keys[key]: VOICES_TO_CREATE[voice_keys[key]]
            for key in selected if key in voice_keys
        }

        if not voices_dict:
            print(f"ERROR: No valid voices in: {args.voices}")
            print(f"Valid options: {', '.join(voice_keys.keys())}")
            sys.exit(1)
    else:
        # Use all predefined voices
        voices_dict = VOICES_TO_CREATE

    # Create voices
    if args.auto:
        create_voices_auto(client, voices_dict)
    else:
        create_voices_interactive(client, voices_dict)


if __name__ == "__main__":
    main()
