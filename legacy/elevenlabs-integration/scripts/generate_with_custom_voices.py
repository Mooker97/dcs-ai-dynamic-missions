"""
Generate voice lines using custom voice profiles from voice_config.json

This script allows you to assign different custom voices to different
categories of voice lines, creating a more diverse and realistic audio
experience for your DCS missions.

Requirements:
    - voice_config.json configured with your voice IDs
    - Run list_my_voices.py first to get your voice IDs

Usage:
    python generate_with_custom_voices.py
    python generate_with_custom_voices.py --dry-run
    python generate_with_custom_voices.py --config my_custom_config.json
"""

import json
import os
import sys
from pathlib import Path
from elevenlabs.client import ElevenLabs
from elevenlabs import VoiceSettings

# Try to load .env
try:
    from dotenv import load_dotenv
    load_dotenv()
except ImportError:
    pass

# Import from generate_voice_lines
import generate_voice_lines as gvl

# ============================================================================
# Configuration Loading
# ============================================================================

def load_voice_config(config_path=None):
    """Load voice configuration from JSON file."""
    if config_path is None:
        config_path = Path(__file__).parent / "voice_config.json"
    else:
        config_path = Path(config_path)

    if not config_path.exists():
        print("ERROR: voice_config.json not found!")
        print(f"Expected location: {config_path}")
        print("\nSetup instructions:")
        print("1. Run: python list_my_voices.py")
        print("2. Copy voice_config.template.json to voice_config.json")
        print("3. Fill in your voice IDs from step 1")
        print("4. Run this script again")
        return None

    try:
        with open(config_path, 'r', encoding='utf-8') as f:
            config = json.load(f)

        # Validate configuration
        if 'voices' not in config:
            print("ERROR: Configuration missing 'voices' section!")
            return None

        if 'default_voice' not in config:
            print("ERROR: Configuration missing 'default_voice'!")
            return None

        # Check that default voice exists
        if config['default_voice'] not in config['voices']:
            print(f"ERROR: Default voice '{config['default_voice']}' not found in voices!")
            return None

        # Validate voice entries
        for voice_name, voice_data in config['voices'].items():
            if 'voice_id' not in voice_data:
                print(f"ERROR: Voice '{voice_name}' missing 'voice_id'!")
                return None
            if voice_data['voice_id'] == "YOUR_VOICE_ID_HERE":
                print(f"ERROR: Voice '{voice_name}' still has placeholder ID!")
                print("Please update voice_config.json with your actual voice IDs")
                return None

        return config

    except json.JSONDecodeError as e:
        print(f"ERROR: Invalid JSON in config file: {e}")
        return None
    except Exception as e:
        print(f"ERROR: Failed to load config: {e}")
        return None


def get_voice_for_category(config, category):
    """
    Get the appropriate voice ID and name for a category.

    Returns:
        Tuple of (voice_id, voice_name, voice_description)
    """
    # Check each voice profile to see if it handles this category
    for voice_name, voice_data in config['voices'].items():
        if 'categories' in voice_data and category in voice_data['categories']:
            return (
                voice_data['voice_id'],
                voice_data.get('name', voice_name),
                voice_data.get('description', '')
            )

    # Fall back to default voice
    default_name = config['default_voice']
    default_data = config['voices'][default_name]
    return (
        default_data['voice_id'],
        default_data.get('name', default_name),
        default_data.get('description', 'Default voice')
    )


def display_voice_assignment(config, lines_to_generate):
    """Display which voice will be used for each category."""
    print("\n" + "=" * 80)
    print("VOICE ASSIGNMENT")
    print("=" * 80)

    voice_usage = {}  # Track how many lines each voice will generate

    for category, lines in lines_to_generate.items():
        voice_id, voice_name, description = get_voice_for_category(config, category)

        if voice_name not in voice_usage:
            voice_usage[voice_name] = 0
        voice_usage[voice_name] += len(lines)

        print(f"\n📁 {category}")
        print(f"   Voice: {voice_name}")
        print(f"   Lines: {len(lines)}")
        if description:
            print(f"   Description: {description}")

    print("\n" + "=" * 80)
    print("VOICE USAGE SUMMARY")
    print("=" * 80)
    for voice_name, count in sorted(voice_usage.items(), key=lambda x: x[1], reverse=True):
        print(f"  {voice_name}: {count} lines")


# ============================================================================
# Main Generation Logic
# ============================================================================

def generate_with_custom_voices(config_path=None, dry_run=False, model_id=None):
    """Generate all voice lines using custom voice profiles."""

    # Load configuration
    config = load_voice_config(config_path)
    if not config:
        sys.exit(1)

    # Setup paths
    script_dir = Path(__file__).parent
    voice_lines_md = script_dir / "VOICE-LINES.md"
    output_base = script_dir

    if not voice_lines_md.exists():
        print(f"ERROR: VOICE-LINES.md not found at {voice_lines_md}")
        sys.exit(1)

    # Display header
    print("=" * 80)
    print("DCS Voice Line Generator - Custom Voice Edition")
    print("=" * 80)

    # Show loaded voice profiles
    print("\n📢 VOICE PROFILES LOADED:")
    for voice_name, voice_data in config['voices'].items():
        marker = "⭐" if voice_name == config['default_voice'] else "  "
        print(f"{marker} {voice_data.get('name', voice_name)}")
        print(f"     ID: {voice_data['voice_id']}")
        if 'description' in voice_data:
            print(f"     Description: {voice_data['description']}")
        if 'categories' in voice_data:
            print(f"     Categories: {len(voice_data['categories'])}")

    # Parse voice lines
    print(f"\nParsing {voice_lines_md}...")
    categories = gvl.parse_voice_lines_md(str(voice_lines_md))
    lines_to_generate = gvl.get_lines_to_generate(categories)

    if not lines_to_generate:
        print("\n✅ No lines to generate! All lines are already marked as EXISTS.")
        return

    # Display summary
    total_lines = sum(len(lines) for lines in lines_to_generate.values())
    total_chars = gvl.estimate_character_count(lines_to_generate)

    print(f"\nFound {total_lines} lines to generate across {len(lines_to_generate)} categories")
    print(f"Estimated character count: {total_chars:,}")

    # Show voice assignments
    display_voice_assignment(config, lines_to_generate)

    if dry_run:
        print("\n[DRY RUN MODE - No audio will be generated]")
        print("\nFiles that would be generated:")
        for category, lines in lines_to_generate.items():
            folder = gvl.CATEGORY_FOLDERS.get(category, "generic/other")
            voice_id, voice_name, _ = get_voice_for_category(config, category)
            print(f"\n{category} ({len(lines)} lines) [{voice_name}]")
            print(f"  → {folder}/")
            for i, line in enumerate(lines, 1):
                filename = gvl.sanitize_filename(line) + ".mp3"
                print(f"    {i}. {filename}")
        return

    # Initialize ElevenLabs client
    api_key = os.getenv("ELEVENLABS_API_KEY")
    if not api_key:
        print("\nERROR: ELEVENLABS_API_KEY not found in environment!")
        print("Please set it using:")
        print("  Windows: setx ELEVENLABS_API_KEY \"your-key-here\"")
        print("  Linux/Mac: export ELEVENLABS_API_KEY=\"your-key-here\"")
        sys.exit(1)

    client = ElevenLabs(api_key=api_key)

    if model_id is None:
        model_id = gvl.DEFAULT_MODEL

    # Generate audio files
    print("\n" + "=" * 80)
    print("STARTING GENERATION")
    print("=" * 80)

    generated_count = 0
    failed_count = 0
    skipped_count = 0

    for category, lines in lines_to_generate.items():
        voice_id, voice_name, description = get_voice_for_category(config, category)
        folder = gvl.CATEGORY_FOLDERS.get(category, "generic/other")
        output_dir = output_base / folder

        # Get category-specific voice settings or use default
        settings = gvl.CATEGORY_VOICE_SETTINGS.get(category, gvl.VOICE_SETTINGS)

        print(f"\n📁 {category} ({len(lines)} lines)")
        print(f"   Voice: {voice_name} ({voice_id[:8]}...)")
        print(f"   Output: {folder}/")

        for i, line in enumerate(lines, 1):
            filename = gvl.sanitize_filename(line) + ".mp3"
            output_path = output_dir / filename

            # Skip if file already exists
            if output_path.exists():
                print(f"  ⏭️  Skipping (exists): {filename}")
                skipped_count += 1
                continue

            try:
                # Generate audio
                audio_bytes = gvl.generate_audio(
                    client=client,
                    text=line,
                    voice_id=voice_id,
                    model_id=model_id,
                    voice_settings=settings
                )

                # Save to file
                gvl.save_audio_file(audio_bytes, output_path)
                generated_count += 1

            except Exception as e:
                print(f"  ❌ ERROR: {e}")
                failed_count += 1
                continue

    # Summary
    print("\n" + "=" * 80)
    print("GENERATION COMPLETE!")
    print("=" * 80)
    print(f"✅ Generated: {generated_count} files")
    if skipped_count > 0:
        print(f"⏭️  Skipped: {skipped_count} files (already exist)")
    if failed_count > 0:
        print(f"❌ Failed: {failed_count} files")

    print(f"\nOutput location: {output_base}/")
    print("\nNext steps:")
    print("1. Listen to generated files and verify quality")
    print("2. Copy files to your .miz mission's l10n/DEFAULT/ folder")
    print("3. Update VOICE-LINES.md to mark files as ✅ EXISTS")
    print("4. Test in DCS World!")


# ============================================================================
# CLI Interface
# ============================================================================

def main():
    """Main entry point."""
    import argparse

    parser = argparse.ArgumentParser(
        description="Generate DCS voice lines using custom voice profiles",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
    # Generate all pending lines using voice_config.json
    python generate_with_custom_voices.py

    # Dry run to preview what would be generated
    python generate_with_custom_voices.py --dry-run

    # Use a different config file
    python generate_with_custom_voices.py --config my_config.json

    # Use a different model
    python generate_with_custom_voices.py --model eleven_flash_v2_5

Setup:
    1. Run: python list_my_voices.py
    2. Copy voice_config.template.json to voice_config.json
    3. Fill in your voice IDs
    4. Run this script
        """
    )

    parser.add_argument(
        '--config',
        help='Path to voice configuration JSON file (default: voice_config.json)'
    )

    parser.add_argument(
        '--model',
        default=None,
        help=f'ElevenLabs model ID (default: {gvl.DEFAULT_MODEL})'
    )

    parser.add_argument(
        '--dry-run',
        action='store_true',
        help='Show what would be generated without actually generating audio'
    )

    args = parser.parse_args()

    generate_with_custom_voices(
        config_path=args.config,
        dry_run=args.dry_run,
        model_id=args.model
    )


if __name__ == "__main__":
    main()
