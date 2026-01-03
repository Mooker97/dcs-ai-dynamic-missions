# Custom Voice Management

Guide for using and creating custom voices in ElevenLabs for DCS mission voice lines.

---

## Overview

ElevenLabs allows you to create custom voices through:
1. **Voice Cloning** - Clone a voice from audio samples (requires paid plan)
2. **Voice Design** - Create synthetic voices with specific characteristics
3. **Professional Voice Cloning** - High-quality cloning from longer samples (higher tier plans)

---

## Finding Your Custom Voice IDs

### Method 1: Via ElevenLabs Website (Easiest)

1. Go to **My Voices**: https://elevenlabs.io/app/voice-lab
2. Find your custom voice in the list
3. Click the **three dots (More Actions)** next to the voice
4. Click **"Copy Voice ID"**
5. Voice ID is now in your clipboard (format: `abc123XYZ456...`)

### Method 2: Via Python Script

Create a script to list all your voices including custom ones:

```python
from elevenlabs.client import ElevenLabs
import os

client = ElevenLabs(api_key=os.getenv("ELEVENLABS_API_KEY"))

# Get all voices (includes custom and default)
response = client.voices.get_all()

print("YOUR VOICES")
print("=" * 80)

for voice in response.voices:
    # Check if custom voice
    category = getattr(voice, 'category', 'unknown')
    is_custom = 'cloned' in category.lower() or 'generated' in category.lower()

    marker = "🎤 CUSTOM" if is_custom else "📢 DEFAULT"

    print(f"\n{marker} {voice.name}")
    print(f"  ID: {voice.voice_id}")

    if hasattr(voice, 'description') and voice.description:
        print(f"  Description: {voice.description}")

    if hasattr(voice, 'labels') and voice.labels:
        labels = voice.labels
        print(f"  Gender: {labels.get('gender', 'N/A')}")
        print(f"  Age: {labels.get('age', 'N/A')}")
        print(f"  Accent: {labels.get('accent', 'N/A')}")
        print(f"  Use Case: {labels.get('use case', 'N/A')}")

    print(f"  Category: {category}")
    print("-" * 80)
```

Save as `list_my_voices.py` and run:
```bash
python list_my_voices.py
```

### Method 3: Via API Call

```python
from elevenlabs.client import ElevenLabs
import os
import json

client = ElevenLabs(api_key=os.getenv("ELEVENLABS_API_KEY"))
response = client.voices.get_all()

# Save to JSON file for reference
voices_data = []
for voice in response.voices:
    voices_data.append({
        'name': voice.name,
        'voice_id': voice.voice_id,
        'category': getattr(voice, 'category', 'unknown'),
        'labels': getattr(voice, 'labels', {}),
    })

with open('my_voices.json', 'w') as f:
    json.dump(voices_data, f, indent=2)

print("Saved to my_voices.json")
```

---

## Creating Custom Voices

### Option 1: Instant Voice Cloning

**Requirements:**
- Paid plan (Starter or above)
- 1-5 minutes of clean audio samples
- Single speaker, minimal background noise

**Steps:**

1. **Prepare Audio Samples**
   - Record 1-5 minutes of clear speech
   - Supported formats: MP3, WAV, M4A, FLAC
   - Best results: Multiple short clips (10-30 seconds each)
   - Content should be varied (different emotions, contexts)

2. **Upload to ElevenLabs**
   - Go to: https://elevenlabs.io/app/voice-lab
   - Click **"Add Voice"** → **"Instant Voice Cloning"**
   - Upload your audio samples
   - Name your voice (e.g., "Tactical Commander")
   - Add labels: gender, age, accent, use case

3. **Test the Voice**
   - Click **"Generate Sample"**
   - Type test text: "We need air support, NOW!"
   - Listen and adjust if needed

4. **Get Voice ID**
   - Click three dots → **"Copy Voice ID"**
   - Save this ID for use in scripts

### Option 2: Professional Voice Cloning

**Requirements:**
- Creator or Pro plan
- 30+ minutes of high-quality audio
- Professional studio recording recommended

**Steps:**
1. Go to: https://elevenlabs.io/app/voice-lab
2. Click **"Add Voice"** → **"Professional Voice Cloning"**
3. Upload 30+ minutes of audio
4. Processing takes 24-48 hours
5. Higher quality and more natural results

### Option 3: Voice Design (Synthetic)

**Requirements:**
- Any plan (including free)
- No audio samples needed

**Steps:**
1. Go to: https://elevenlabs.io/app/voice-lab
2. Click **"Add Voice"** → **"Voice Design"**
3. Describe desired voice characteristics:
   - Gender, age, accent
   - Tone (authoritative, calm, urgent)
   - Example: "Deep male voice, American accent, military commander, authoritative and calm under pressure"
4. Generate and test
5. Adjust description if needed

---

## Best Practices for Military/Tactical Voices

### Recording Tips for Voice Cloning

**Equipment:**
- USB microphone (minimum)
- Pop filter to reduce plosives
- Quiet room with minimal echo

**Recording Guidelines:**
1. **Variety is Key:**
   - Record multiple emotional states (calm, urgent, stressed)
   - Use military terminology and brevity codes
   - Include radio-style communications

2. **Sample Script Ideas:**
   ```
   CALM:
   - "All callsigns, mission is a go. Good hunting out there."
   - "Package is complete. Return to base."
   - "Roger that, weapons free. Stay sharp."

   URGENT:
   - "We need air support, NOW!"
   - "Contact! Multiple hostiles engaging!"
   - "SAM launch! Missile in the air!"

   PROFESSIONAL:
   - "Target coordinates are grid november papa four-five-six, seven-eight-nine."
   - "Splash one hostile armor. BDA shows target destroyed."
   - "All stations, be advised, weather conditions deteriorating."
   ```

3. **Quality Checklist:**
   - ✅ Clear pronunciation
   - ✅ Consistent microphone distance
   - ✅ No background noise
   - ✅ Natural breathing/pacing
   - ✅ Varied intonation
   - ❌ No music or sound effects
   - ❌ No multiple speakers
   - ❌ No compression artifacts

### Voice Characteristics to Target

**Ground Troops (Front Line):**
- Higher urgency baseline
- Stressed/combat-ready tone
- Quick, clipped speech
- American/British/Australian accent (depending on faction)

**Mission Control / AWACS:**
- Calm, professional tone
- Clear enunciation
- Steady pacing
- Authoritative but not aggressive

**JTAC / Forward Air Controller:**
- Professional military bearing
- Quick but controlled speech
- Combat-aware but focused
- Brevity code proficiency

---

## Using Custom Voices in Generation Script

### Method 1: Command Line

```bash
# Use your custom voice ID directly
python generate_voice_lines.py --voice-id your-custom-voice-id-here
```

### Method 2: Voice Configuration File

Create `voice_config.json` in the audio folder:

```json
{
  "voices": {
    "ground_commander": {
      "voice_id": "abc123XYZ456",
      "name": "Ground Commander",
      "description": "Deep authoritative male, combat veteran",
      "categories": [
        "Requesting Support",
        "Taking Fire / Under Attack",
        "Target Spotted / Tally"
      ]
    },
    "mission_control": {
      "voice_id": "def789UVW012",
      "name": "Mission Control",
      "description": "Calm professional female, AWACS controller",
      "categories": [
        "Mission Start",
        "Mission Complete",
        "Abort / Waveoff"
      ]
    },
    "warning_system": {
      "voice_id": "ghi345RST678",
      "name": "Warning System",
      "description": "Alert system voice, high clarity",
      "categories": [
        "SAM Warning",
        "Enemy Aircraft",
        "Friendly Fire Warning"
      ]
    }
  },
  "default_voice": "ground_commander"
}
```

### Method 3: Enhanced Generation Script

Create `generate_with_custom_voices.py`:

```python
"""
Generate voice lines using custom voice profiles from voice_config.json
"""
import json
from pathlib import Path
from generate_voice_lines import generate_audio, save_audio_file, parse_voice_lines_md, get_lines_to_generate, CATEGORY_FOLDERS, CATEGORY_VOICE_SETTINGS, VOICE_SETTINGS
from elevenlabs.client import ElevenLabs
import os

def load_voice_config():
    """Load voice configuration from JSON file."""
    config_path = Path(__file__).parent / "voice_config.json"
    if not config_path.exists():
        print("ERROR: voice_config.json not found!")
        print("Create it using the template in CUSTOM-VOICES.md")
        return None

    with open(config_path, 'r') as f:
        return json.load(f)

def get_voice_for_category(config, category):
    """Get the appropriate voice ID for a category."""
    # Check each voice profile to see if it handles this category
    for voice_name, voice_data in config['voices'].items():
        if category in voice_data['categories']:
            return voice_data['voice_id'], voice_name

    # Fall back to default voice
    default = config['default_voice']
    return config['voices'][default]['voice_id'], default

def main():
    # Load configuration
    config = load_voice_config()
    if not config:
        return

    # Setup
    api_key = os.getenv("ELEVENLABS_API_KEY")
    if not api_key:
        print("ERROR: ELEVENLABS_API_KEY not set!")
        return

    client = ElevenLabs(api_key=api_key)
    script_dir = Path(__file__).parent
    voice_lines_md = script_dir / "VOICE-LINES.md"

    # Parse voice lines
    print("=" * 70)
    print("DCS Voice Line Generator - Custom Voice Edition")
    print("=" * 70)
    print("\nVoice Profiles Loaded:")
    for name, data in config['voices'].items():
        print(f"  - {data['name']} ({name})")
        print(f"    ID: {data['voice_id']}")
        print(f"    Categories: {len(data['categories'])}")
    print()

    categories = parse_voice_lines_md(str(voice_lines_md))
    lines_to_generate = get_lines_to_generate(categories)

    if not lines_to_generate:
        print("✅ No lines to generate!")
        return

    # Generate with appropriate voices
    output_base = script_dir
    generated_count = 0

    for category, lines in lines_to_generate.items():
        voice_id, voice_name = get_voice_for_category(config, category)
        folder = CATEGORY_FOLDERS.get(category, "generic/other")
        output_dir = output_base / folder
        settings = CATEGORY_VOICE_SETTINGS.get(category, VOICE_SETTINGS)

        print(f"\n📁 {category} ({len(lines)} lines)")
        print(f"   Voice: {voice_name}")
        print(f"   Output: {folder}/")

        for line in lines:
            filename = line.lower().replace(' ', '-').replace(',', '').replace('!', '').replace('?', '')[:80] + ".mp3"
            output_path = output_dir / filename

            if output_path.exists():
                print(f"  ⏭️  Skipping (exists): {filename}")
                continue

            try:
                audio_bytes = generate_audio(
                    client=client,
                    text=line,
                    voice_id=voice_id,
                    model_id="eleven_multilingual_v2",
                    voice_settings=settings
                )
                save_audio_file(audio_bytes, output_path)
                generated_count += 1
            except Exception as e:
                print(f"  ❌ ERROR: {e}")

    print(f"\n✅ Generated {generated_count} files using custom voices!")

if __name__ == "__main__":
    main()
```

---

## Managing Multiple Voice Profiles

### Organizing Voices by Role

Create separate voice profiles for different mission roles:

| Role | Voice Characteristics | Example Names |
|------|----------------------|---------------|
| **Ground Commander** | Authoritative, urgent capable, combat-experienced | "Iron 1", "Anvil 6" |
| **JTAC** | Professional, calm under pressure, precise | "Hawkeye", "Viper 2-1" |
| **Mission Control** | Calm, clear, professional tone | "Overlord", "Magic" |
| **AWACS** | Technical, informative, steady | "Magic 1-1", "Darkstar" |
| **Warning System** | Clear, immediate, attention-grabbing | "Betty", "Bitching Betty" |

### Voice Library Structure

```
My ElevenLabs Voices:
├── [Custom] Ground Commander - Iron 6
├── [Custom] JTAC - Hawkeye
├── [Custom] Mission Control - Overlord
├── [Custom] AWACS - Magic
├── [Custom] Warning System - Betty
└── [Default] Adam (backup)
```

### Naming Convention

Use descriptive names that indicate role and callsign:
- ✅ "Ground Commander - Iron 6"
- ✅ "JTAC - Hawkeye (Urgent)"
- ✅ "AWACS Controller - Magic"
- ❌ "Voice 1"
- ❌ "Test Voice"
- ❌ "My Voice"

---

## Testing Custom Voices

### Quick Test Script

```python
from elevenlabs.client import ElevenLabs
import os

client = ElevenLabs(api_key=os.getenv("ELEVENLABS_API_KEY"))

# Test lines for different emotions
test_lines = [
    ("CALM", "All callsigns, mission is a go. Good hunting."),
    ("URGENT", "We need air support, NOW!"),
    ("STRESSED", "We're taking HEAVY fire! Multiple contacts!"),
    ("PROFESSIONAL", "Target destroyed. Good kill, good kill."),
]

voice_id = "your-custom-voice-id-here"

print("Testing voice...")
for emotion, text in test_lines:
    print(f"\n{emotion}: {text}")

    audio = client.text_to_speech.convert(
        text=text,
        voice_id=voice_id,
        model_id="eleven_multilingual_v2"
    )

    filename = f"test_{emotion.lower()}.mp3"
    with open(filename, "wb") as f:
        for chunk in audio:
            f.write(chunk)

    print(f"  Saved: {filename}")
```

### Quality Checklist

Listen for:
- ✅ Clear pronunciation of military terms
- ✅ Appropriate emotion for context
- ✅ Natural breathing and pacing
- ✅ Consistency across different lines
- ❌ Robotic or unnatural inflection
- ❌ Mispronounced technical terms
- ❌ Inappropriate emotion (laughing during urgent lines)

---

## Voice Cloning Tips for Military Communications

### What Makes Good Source Audio

**✅ GOOD:**
- Military radio communications (actual or simulated)
- Podcast/interview with consistent tone
- Audiobook narration (military fiction)
- Training video voiceovers
- Clear single-speaker recordings

**❌ AVOID:**
- Multiple speakers in same audio
- Music or heavy sound effects
- Phone call recordings (compressed)
- Video game voice lines (processed)
- Echo-heavy recordings

### Sample Recording Session Plan

**Session 1: Calm/Professional (10 minutes)**
```
- Mission briefings
- Status reports
- Acknowledgments
- Technical descriptions
```

**Session 2: Moderate Urgency (5 minutes)**
```
- Contact reports
- Target callouts
- Tactical updates
- Coordination calls
```

**Session 3: High Urgency (5 minutes)**
```
- Under fire situations
- Emergency calls
- SAM warnings
- Critical damage reports
```

---

## Cost Considerations

### ElevenLabs Plans & Voice Cloning

| Plan | Price/Month | Voice Cloning | Voices |
|------|-------------|---------------|---------|
| **Free** | $0 | ❌ No | Voice Design only |
| **Starter** | $5 | ✅ Instant (1min samples) | 10 custom voices |
| **Creator** | $22 | ✅ Instant + Professional | 30 custom voices |
| **Pro** | $99 | ✅ All features | 160 custom voices |

### Recommendations

**For Hobbyist/Single Mission Creator:**
- Free tier: Use Voice Design + default voices
- Starter ($5/mo): 1-2 cloned voices for main characters

**For Serious Campaign Creators:**
- Creator ($22/mo): Multiple professional voices for different roles
- Professional cloning for best quality

**For Community/Team Projects:**
- Pro ($99/mo): Full voice library for large campaigns
- Share voices across team members

---

## Troubleshooting Custom Voices

### Voice Sounds Unnatural

**Possible Causes:**
1. Source audio quality too low
2. Multiple speakers in training samples
3. Background noise in samples
4. Not enough variety in samples

**Solutions:**
- Re-record with better equipment
- Provide 2-3x more sample audio
- Use Professional Voice Cloning (30+ min samples)
- Adjust voice settings: lower stability for more expression

### Wrong Accent/Pronunciation

**Cause:** Source audio has different accent than desired

**Solution:**
- Use source audio with correct accent
- Use Voice Design to specify accent
- Consider using default voices with desired accent

### Voice ID Not Found

**Cause:** Voice was deleted or sharing settings changed

**Solution:**
```python
# List all voices to verify
from elevenlabs.client import ElevenLabs
import os

client = ElevenLabs(api_key=os.getenv("ELEVENLABS_API_KEY"))
voices = client.voices.get_all()

for v in voices.voices:
    print(f"{v.name}: {v.voice_id}")
```

---

## Next Steps

1. ✅ Log into ElevenLabs account
2. ✅ Find your existing custom voice IDs
3. ⏳ Create `voice_config.json` with your voices
4. ⏳ Test voices with sample lines
5. ⏳ Run generation with custom voices
6. ⏳ Integrate into DCS missions

---

## Resources

- [ElevenLabs Voice Lab](https://elevenlabs.io/app/voice-lab)
- [Voice Cloning Guide](https://elevenlabs.io/docs/product/voice-cloning)
- [Voice Design Guide](https://elevenlabs.io/docs/product/voice-design)
- [API Reference - Get Voices](https://elevenlabs.io/docs/api-reference/voices/search)
- [Pricing & Plans](https://elevenlabs.io/pricing)

---

**Ready to create professional-quality voice lines with your custom voices!** 🎤✈️
