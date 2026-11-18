# ElevenLabs API Setup Guide

Complete guide to setting up ElevenLabs Text-to-Speech API for generating DCS voice lines.

> **💡 Already have an ElevenLabs account?** Skip to [Step 2: Get Your API Key](#step-2-get-your-api-key)
>
> **💡 Have custom voices?** See [CUSTOM-VOICES.md](CUSTOM-VOICES.md) for using your cloned voices

---

## Step 1: Create ElevenLabs Account (Skip if you have one)

1. Go to [ElevenLabs](https://elevenlabs.io)
2. Sign up for a free account
3. Verify your email address

**Free Tier Info:**
- 10,000 characters per month
- Access to default voices
- Commercial license included

---

## Step 2: Get Your API Key

1. Log in to your ElevenLabs account
2. Click **"Developers"** in the left sidebar
3. Select the **"API Keys"** tab
   - Or go directly to: https://elevenlabs.io/app/settings/api-keys
4. Click **"Create API Key"**
5. Give it a name (e.g., "DCS Voice Lines")
6. Click **"Create"**
7. **COPY THE KEY IMMEDIATELY** - it won't be shown again!

---

## Step 3: Store Your API Key Securely

### Option A: Environment Variable (Recommended)

**Windows (PowerShell):**
```powershell
# Set for current session
$env:ELEVENLABS_API_KEY = "your-api-key-here"

# Set permanently (user level)
[System.Environment]::SetEnvironmentVariable('ELEVENLABS_API_KEY', 'your-api-key-here', 'User')
```

**Windows (Command Prompt):**
```cmd
setx ELEVENLABS_API_KEY "your-api-key-here"
```

**Linux/Mac:**
```bash
# Add to ~/.bashrc or ~/.zshrc
export ELEVENLABS_API_KEY="your-api-key-here"

# Reload shell
source ~/.bashrc  # or ~/.zshrc
```

### Option B: .env File

Create `.env` file in project root:
```
ELEVENLABS_API_KEY=your-api-key-here
```

**IMPORTANT:** Add `.env` to `.gitignore` to avoid committing your API key!

---

## Step 4: Install Python Dependencies

```bash
# Install ElevenLabs SDK
pip install elevenlabs

# Optional: Install python-dotenv if using .env file
pip install python-dotenv
```

---

## Step 5: Find Voice IDs

### Method A: List Voices via Script

Run this Python script to see all available voices:

```python
from elevenlabs.client import ElevenLabs
import os

client = ElevenLabs(api_key=os.getenv("ELEVENLABS_API_KEY"))

# Get all voices
response = client.voices.get_all()

print("Available Voices:")
print("-" * 60)
for voice in response.voices:
    print(f"Name: {voice.name}")
    print(f"ID: {voice.voice_id}")
    print(f"Description: {voice.description}")
    print(f"Labels: {voice.labels}")
    print("-" * 60)
```

### Method B: Via ElevenLabs Website

1. Go to **Voice Library**: https://elevenlabs.io/voice-library
2. Browse available voices
3. Click on a voice → Click **"More Actions"** (three dots) → **"Copy Voice ID"**

### Recommended Voices for Military/Tactical Communications

**Male Voices (Authoritative/Military):**
- **Adam** (ID: `pNInz6obpgDQGcFmaJgB`) - Deep, authoritative
- **Antoni** (ID: `ErXwobaYiN019PkySvjV`) - Well-rounded
- **Clyde** (ID: `2EiwWnXFnvU5JabPnv8n`) - War veteran style

**Female Voices:**
- **Rachel** (ID: `21m00Tcm4TlvDq8ikWAM`) - Calm, clear (commonly used)
- **Bella** (ID: `EXAVITQu4vr4xnSDxMaL`) - Soft but clear

**For Ground Troops (stressed/urgent):**
- Consider voices with higher energy and emotion capability
- Test with urgent text to find the best match

---

## Step 6: Test Your Setup

Create `test_elevenlabs.py`:

```python
from elevenlabs.client import ElevenLabs
import os

# Initialize client
client = ElevenLabs(api_key=os.getenv("ELEVENLABS_API_KEY"))

# Generate test audio
print("Generating test audio...")
audio = client.text_to_speech.convert(
    text="Good kill, GOOD kill!",
    voice_id="pNInz6obpgDQGcFmaJgB",  # Adam
    model_id="eleven_multilingual_v2",
    output_format="mp3_44100_128"
)

# Save to file
with open("test_audio.mp3", "wb") as f:
    for chunk in audio:
        f.write(chunk)

print("Test audio saved as test_audio.mp3")
print("If you hear audio, setup is complete!")
```

Run the test:
```bash
python test_elevenlabs.py
```

---

## Step 7: Generate Voice Lines

Use the provided script to generate all voice lines from `VOICE-LINES.md`:

```bash
python generate_voice_lines.py
```

See `generate_voice_lines.py` for full documentation.

---

## Troubleshooting

### Error: "API key not found"
- Check environment variable is set: `echo $ELEVENLABS_API_KEY` (Linux/Mac) or `echo %ELEVENLABS_API_KEY%` (Windows)
- Restart terminal/IDE after setting environment variable
- Verify API key is valid at https://elevenlabs.io/app/settings/api-keys

### Error: "Invalid voice_id"
- Run the voice listing script above to get valid voice IDs
- Voice IDs are case-sensitive
- Some voices may not be available on free tier

### Error: "Rate limit exceeded"
- Free tier: 10,000 characters/month
- Wait until next billing cycle or upgrade plan
- Consider batching voice generation to stay within limits

### Audio Quality Issues
- Try different models: `eleven_multilingual_v2`, `eleven_flash_v2_5`
- Adjust voice settings (stability, similarity_boost)
- Use higher output quality: `mp3_44100_192` or `pcm_44100` (WAV)

---

## Voice Settings (Advanced)

Customize voice characteristics:

```python
from elevenlabs import VoiceSettings

audio = client.text_to_speech.convert(
    text="We need air support, NOW!",
    voice_id="pNInz6obpgDQGcFmaJgB",
    model_id="eleven_multilingual_v2",
    voice_settings=VoiceSettings(
        stability=0.5,          # 0-1: Lower = more expressive
        similarity_boost=0.75,  # 0-1: Higher = closer to original
        style=0.5,              # 0-1: Exaggeration of style
        use_speaker_boost=True  # Enhance clarity
    )
)
```

**For Urgent/Combat Lines:**
- Lower stability (0.3-0.5) for more emotion
- Higher similarity_boost (0.7-0.8) for consistency
- Enable speaker_boost for clarity in combat comms

**For Calm/Professional Lines:**
- Higher stability (0.6-0.8) for steadiness
- Medium similarity_boost (0.5-0.7)

---

## API Reference Links

- [ElevenLabs API Authentication](https://elevenlabs.io/docs/api-reference/authentication)
- [Text-to-Speech API Reference](https://elevenlabs.io/docs/api-reference/text-to-speech/convert)
- [Python SDK GitHub](https://github.com/elevenlabs/elevenlabs-python)
- [Developer Quickstart Guide](https://elevenlabs.io/docs/developers/quickstart)
- [Voice Library](https://elevenlabs.io/voice-library)

---

## Character Count Estimation

Estimate how many lines you can generate with free tier:

| Category | Lines | Avg Chars | Total |
|----------|-------|-----------|-------|
| Requesting Support | 7 | 50 | 350 |
| Good Strike | 5 | 40 | 200 |
| Mission Start | 5 | 45 | 225 |
| Mission Complete | 5 | 40 | 200 |
| Taking Fire | 5 | 45 | 225 |
| Target Spotted | 5 | 50 | 250 |
| Warnings | 11 | 45 | 495 |
| **TOTAL** | **43** | - | **~1,945** |

**All voice lines in VOICE-LINES.md ≈ 2,000 characters**

Free tier (10,000 chars) can generate ALL lines **5 times** with room to spare!

---

## Next Steps

1. ✅ API Key configured
2. ✅ Dependencies installed
3. ✅ Voice IDs selected
4. ⏳ Run `generate_voice_lines.py` to create all voice lines
5. ⏳ Copy generated WAV files to `.miz` mission file's `l10n/DEFAULT/` folder
6. ⏳ Test in DCS World

Happy voice line generation!
