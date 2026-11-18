"""
ElevenLabs Voice Line Generator for DCS Missions

Reads VOICE-LINES.md and generates audio files for all lines marked with ⏳
Saves files in organized folder structure matching DCS mission requirements.

Requirements:
    pip install elevenlabs python-dotenv

Usage:
    python generate_voice_lines.py [--voice-id VOICE_ID] [--model MODEL] [--dry-run]

Environment:
    ELEVENLABS_API_KEY must be set in environment or .env file
"""

import os
import re
import sys
from pathlib import Path
from typing import List, Dict, Tuple
from elevenlabs.client import ElevenLabs
from elevenlabs import VoiceSettings

# Try to load .env file if available
try:
    from dotenv import load_dotenv
    load_dotenv()
except ImportError:
    pass

# ============================================================================
# Configuration
# ============================================================================

DEFAULT_VOICE_ID = "pNInz6obpgDQGcFmaJgB"  # Adam - deep, authoritative
DEFAULT_MODEL = "eleven_multilingual_v2"
OUTPUT_FORMAT = "mp3_44100_128"  # Can also use: "pcm_44100" for WAV

# Voice settings for military/tactical communications
VOICE_SETTINGS = VoiceSettings(
    stability=0.5,          # Medium stability for natural emotion
    similarity_boost=0.75,  # High similarity for consistency
    style=0.5,              # Moderate style
    use_speaker_boost=True  # Enhanced clarity for radio comms
)

# Category-specific voice settings
CATEGORY_VOICE_SETTINGS = {
    "Taking Fire / Under Attack": VoiceSettings(
        stability=0.3,  # More expressive/urgent
        similarity_boost=0.75,
        style=0.6,
        use_speaker_boost=True
    ),
    "SAM Warning": VoiceSettings(
        stability=0.3,  # Urgent
        similarity_boost=0.75,
        style=0.6,
        use_speaker_boost=True
    ),
    "Friendly Fire Warning": VoiceSettings(
        stability=0.3,  # Very urgent
        similarity_boost=0.75,
        style=0.7,
        use_speaker_boost=True
    ),
    "Mission Start": VoiceSettings(
        stability=0.7,  # Calm and steady
        similarity_boost=0.75,
        style=0.3,
        use_speaker_boost=True
    ),
    "Mission Complete": VoiceSettings(
        stability=0.7,  # Calm and professional
        similarity_boost=0.75,
        style=0.3,
        use_speaker_boost=True
    ),
}

# Folder mapping for categories
CATEGORY_FOLDERS = {
    "Requesting Support": "generic/ground-troops/requesting-support",
    "Reacting to Good Strike": "generic/ground-troops/good-strike",
    "Good But Keep Going": "generic/ground-troops/keep-going",
    "Taking Fire / Under Attack": "generic/ground-troops/taking-fire",
    "Target Spotted / Tally": "generic/ground-troops/target-spotted",
    "Negative Results / Miss": "generic/ground-troops/negative-results",
    "Winchester / Bingo": "generic/ground-troops/winchester-bingo",
    "Mission Start": "generic/mission/mission-start",
    "Mission Complete": "generic/mission/mission-complete",
    "Abort / Waveoff": "generic/mission/abort-waveoff",
    "Friendly Fire Warning": "generic/ground-troops/friendly-fire-warning",
    "SAM Warning": "generic/threats/sam-warning",
    "Enemy Aircraft": "generic/threats/enemy-aircraft",
    "Weather / Visibility": "generic/threats/weather-visibility",
}

# ============================================================================
# Helper Functions
# ============================================================================

def sanitize_filename(text: str) -> str:
    """Convert text to safe filename."""
    # Remove quotes and special characters
    text = text.strip('"\'')
    # Replace spaces and special chars with hyphens
    text = re.sub(r'[^\w\s-]', '', text)
    text = re.sub(r'[-\s]+', '-', text)
    # Lowercase and limit length
    text = text.lower()[:80]
    return text


def parse_voice_lines_md(file_path: str) -> Dict[str, List[Tuple[str, str]]]:
    """
    Parse VOICE-LINES.md and extract lines needing generation.

    Returns:
        Dict mapping category names to list of (line_text, status) tuples
    """
    with open(file_path, 'r', encoding='utf-8') as f:
        content = f.read()

    categories = {}
    current_category = None

    # Pattern to match category headers like "## Requesting Support"
    category_pattern = r'^## (.+?)$'
    # Pattern to match table rows: | # | Line | Status |
    row_pattern = r'^\|\s*\d+\s*\|\s*"?(.+?)"?\s*\|\s*(.+?)\s*\|$'

    for line in content.split('\n'):
        # Check for category header
        cat_match = re.match(category_pattern, line)
        if cat_match:
            current_category = cat_match.group(1).strip()
            categories[current_category] = []
            continue

        # Check for table row
        if current_category:
            row_match = re.match(row_pattern, line)
            if row_match:
                voice_line = row_match.group(1).strip()
                status = row_match.group(2).strip()
                categories[current_category].append((voice_line, status))

    return categories


def get_lines_to_generate(categories: Dict[str, List[Tuple[str, str]]]) -> Dict[str, List[str]]:
    """
    Filter to only lines marked with ⏳ (needs generation).

    Returns:
        Dict mapping category names to list of line texts
    """
    to_generate = {}
    for category, lines in categories.items():
        pending_lines = [line for line, status in lines if '⏳' in status]
        if pending_lines:
            to_generate[category] = pending_lines
    return to_generate


def estimate_character_count(lines_by_category: Dict[str, List[str]]) -> int:
    """Estimate total characters for API quota calculation."""
    total = 0
    for lines in lines_by_category.values():
        for line in lines:
            total += len(line)
    return total


# ============================================================================
# Audio Generation
# ============================================================================

def generate_audio(
    client: ElevenLabs,
    text: str,
    voice_id: str,
    model_id: str,
    voice_settings: VoiceSettings
) -> bytes:
    """Generate audio using ElevenLabs API."""
    print(f"  Generating: {text[:60]}...")

    audio_generator = client.text_to_speech.convert(
        text=text,
        voice_id=voice_id,
        model_id=model_id,
        output_format=OUTPUT_FORMAT,
        voice_settings=voice_settings
    )

    # Collect all audio chunks
    audio_bytes = b""
    for chunk in audio_generator:
        audio_bytes += chunk

    return audio_bytes


def save_audio_file(audio_bytes: bytes, file_path: Path) -> None:
    """Save audio bytes to file."""
    file_path.parent.mkdir(parents=True, exist_ok=True)
    with open(file_path, 'wb') as f:
        f.write(audio_bytes)
    print(f"  ✅ Saved: {file_path}")


# ============================================================================
# Main Generation Logic
# ============================================================================

def generate_all_voice_lines(
    voice_id: str = DEFAULT_VOICE_ID,
    model_id: str = DEFAULT_MODEL,
    dry_run: bool = False
) -> None:
    """Generate all voice lines marked as pending."""

    # Setup paths
    script_dir = Path(__file__).parent
    voice_lines_md = script_dir / "VOICE-LINES.md"
    output_base = script_dir

    if not voice_lines_md.exists():
        print(f"ERROR: VOICE-LINES.md not found at {voice_lines_md}")
        sys.exit(1)

    print("=" * 70)
    print("DCS Voice Line Generator - ElevenLabs Edition")
    print("=" * 70)

    # Parse voice lines
    print(f"\nParsing {voice_lines_md}...")
    categories = parse_voice_lines_md(str(voice_lines_md))
    lines_to_generate = get_lines_to_generate(categories)

    if not lines_to_generate:
        print("\n✅ No lines to generate! All lines are already marked as EXISTS.")
        return

    # Display summary
    total_lines = sum(len(lines) for lines in lines_to_generate.values())
    total_chars = estimate_character_count(lines_to_generate)

    print(f"\nFound {total_lines} lines to generate across {len(lines_to_generate)} categories")
    print(f"Estimated character count: {total_chars:,}")
    print(f"Voice: {voice_id}")
    print(f"Model: {model_id}")

    if dry_run:
        print("\n[DRY RUN MODE - No audio will be generated]")
        for category, lines in lines_to_generate.items():
            folder = CATEGORY_FOLDERS.get(category, "generic/other")
            print(f"\n{category} ({len(lines)} lines) → {folder}/")
            for i, line in enumerate(lines, 1):
                filename = sanitize_filename(line)
                print(f"  {i}. {filename}.mp3")
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

    # Generate audio files
    print("\n" + "=" * 70)
    print("Starting generation...")
    print("=" * 70)

    generated_count = 0
    failed_count = 0

    for category, lines in lines_to_generate.items():
        folder = CATEGORY_FOLDERS.get(category, "generic/other")
        output_dir = output_base / folder

        # Get category-specific voice settings or use default
        settings = CATEGORY_VOICE_SETTINGS.get(category, VOICE_SETTINGS)

        print(f"\n📁 {category} ({len(lines)} lines)")
        print(f"   Output: {folder}/")

        for i, line in enumerate(lines, 1):
            filename = sanitize_filename(line) + ".mp3"
            output_path = output_dir / filename

            # Skip if file already exists
            if output_path.exists():
                print(f"  ⏭️  Skipping (exists): {filename}")
                continue

            try:
                # Generate audio
                audio_bytes = generate_audio(
                    client=client,
                    text=line,
                    voice_id=voice_id,
                    model_id=model_id,
                    voice_settings=settings
                )

                # Save to file
                save_audio_file(audio_bytes, output_path)
                generated_count += 1

            except Exception as e:
                print(f"  ❌ ERROR: {e}")
                failed_count += 1
                continue

    # Summary
    print("\n" + "=" * 70)
    print("Generation Complete!")
    print("=" * 70)
    print(f"✅ Generated: {generated_count} files")
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
        description="Generate DCS voice lines using ElevenLabs API",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
    # Generate all pending lines with default voice
    python generate_voice_lines.py

    # Use a different voice
    python generate_voice_lines.py --voice-id ErXwobaYiN019PkySvjV

    # Dry run to see what would be generated
    python generate_voice_lines.py --dry-run

    # Use different model
    python generate_voice_lines.py --model eleven_flash_v2_5
        """
    )

    parser.add_argument(
        '--voice-id',
        default=DEFAULT_VOICE_ID,
        help=f'ElevenLabs voice ID (default: {DEFAULT_VOICE_ID} - Adam)'
    )

    parser.add_argument(
        '--model',
        default=DEFAULT_MODEL,
        help=f'ElevenLabs model ID (default: {DEFAULT_MODEL})'
    )

    parser.add_argument(
        '--dry-run',
        action='store_true',
        help='Show what would be generated without actually generating audio'
    )

    parser.add_argument(
        '--list-voices',
        action='store_true',
        help='List all available voices and exit'
    )

    args = parser.parse_args()

    # List voices if requested
    if args.list_voices:
        api_key = os.getenv("ELEVENLABS_API_KEY")
        if not api_key:
            print("ERROR: ELEVENLABS_API_KEY not set")
            sys.exit(1)

        client = ElevenLabs(api_key=api_key)
        response = client.voices.get_all()

        print("Available Voices:")
        print("=" * 70)
        for voice in response.voices:
            print(f"\nName: {voice.name}")
            print(f"ID: {voice.voice_id}")
            if hasattr(voice, 'description') and voice.description:
                print(f"Description: {voice.description}")
            if hasattr(voice, 'labels') and voice.labels:
                print(f"Labels: {voice.labels}")
            print("-" * 70)
        sys.exit(0)

    # Generate voice lines
    generate_all_voice_lines(
        voice_id=args.voice_id,
        model_id=args.model,
        dry_run=args.dry_run
    )


if __name__ == "__main__":
    main()
