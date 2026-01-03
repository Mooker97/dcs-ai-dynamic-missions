"""Quick test of ElevenLabs setup - generates sample audio"""
from elevenlabs.client import ElevenLabs
from elevenlabs import VoiceSettings
import os

try:
    from dotenv import load_dotenv
    load_dotenv()
except ImportError:
    pass

# Test with Sgt Butterfield (high-energy ground soldier)
VOICE_ID = "KgoKSoe0uSDQXTd5sh94"
TEST_LINE = "Good kill, GOOD kill!"

print("Testing ElevenLabs setup...")
print(f"Voice: Sgt Butterfield (Combat Ground)")
print(f"Line: {TEST_LINE}")
print()

api_key = os.getenv("ELEVENLABS_API_KEY")
if not api_key:
    print("ERROR: ELEVENLABS_API_KEY not found!")
    exit(1)

client = ElevenLabs(api_key=api_key)

print("Generating audio...")
audio = client.text_to_speech.convert(
    text=TEST_LINE,
    voice_id=VOICE_ID,
    model_id="eleven_multilingual_v2",
    output_format="mp3_44100_128",
    voice_settings=VoiceSettings(
        stability=0.5,
        similarity_boost=0.75,
        style=0.5,
        use_speaker_boost=True
    )
)

# Save to file in test_files folder
from pathlib import Path
test_dir = Path("test_files")
test_dir.mkdir(exist_ok=True)

output_file = test_dir / "test_sgt_butterfield.mp3"
with open(output_file, "wb") as f:
    for chunk in audio:
        f.write(chunk)

print(f"SUCCESS! Audio saved to: {output_file}")
print("\nPlay the file to verify quality!")
print("\nSetup is complete. Ready to generate all voice lines!")
