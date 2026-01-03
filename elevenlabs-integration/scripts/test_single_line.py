"""Generate single test voice line"""
from elevenlabs.client import ElevenLabs
from elevenlabs import VoiceSettings
import os

try:
    from dotenv import load_dotenv
    load_dotenv()
except ImportError:
    pass

# AWACS voice
VOICE_ID = "2qVLKOamXa29yju9mqTK"
TEST_LINE = "All callsigns, mission is a go. Good hunting out there."

print("Generating single voice line...")
print(f"Voice: AWACS - Magic")
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
        stability=0.7,  # Higher for calm professional
        similarity_boost=0.75,
        style=0.3,
        use_speaker_boost=True
    )
)

# Save to file in test_files folder
from pathlib import Path
test_dir = Path("test_files")
test_dir.mkdir(exist_ok=True)

output_file = test_dir / "test_awacs_mission_line.mp3"
with open(output_file, "wb") as f:
    for chunk in audio:
        f.write(chunk)

print(f"[OK] Audio saved to: {output_file}")
print("\nPlay the file to hear the AWACS voice!")
