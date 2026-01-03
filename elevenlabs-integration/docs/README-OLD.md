# DCS Mission Voice Lines

Automated voice line generation system for DCS World missions using ElevenLabs AI Text-to-Speech.

> **💡 Have custom ElevenLabs voices?** See [QUICK-START-CUSTOM-VOICES.md](QUICK-START-CUSTOM-VOICES.md) for 5-minute setup!

---

## Quick Start

### 1. Setup (First Time Only)

```bash
# Install dependencies
pip install elevenlabs python-dotenv

# Get API key from https://elevenlabs.io/app/settings/api-keys
# Set environment variable
setx ELEVENLABS_API_KEY "your-api-key-here"  # Windows
export ELEVENLABS_API_KEY="your-api-key-here"  # Linux/Mac

# Restart terminal after setting environment variable
```

📚 **Detailed setup guide:** See [ELEVENLABS-SETUP.md](ELEVENLABS-SETUP.md)

---

### 2. Generate Voice Lines

```bash
# Generate all pending voice lines
python generate_voice_lines.py

# Preview what would be generated (no API calls)
python generate_voice_lines.py --dry-run

# Use a different voice
python generate_voice_lines.py --voice-id 21m00Tcm4TlvDq8ikWAM

# List all available voices
python generate_voice_lines.py --list-voices
```

---

### 3. Use in DCS Missions

1. Generated audio files are saved in organized folders under `generic/`
2. Copy desired audio files to your `.miz` mission file's `l10n/DEFAULT/` folder
3. Use DMS.Audio to play them in-mission:

```lua
-- Play a voice line
DMS.Audio.play("generic/ground-troops/good-strike/good-kill-good-kill.mp3")

-- Play for blue coalition only
DMS.Audio.playForCoalition(
    coalition.side.BLUE,
    "generic/ground-troops/requesting-support/we-need-air-support-now.mp3"
)
```

---

## Files Overview

| File | Purpose |
|------|---------|
| `VOICE-LINES.md` | Master list of all voice lines with generation status |
| `ELEVENLABS-SETUP.md` | Detailed setup instructions for ElevenLabs API |
| `generate_voice_lines.py` | Python script to generate audio files |
| `README.md` | This file - quick reference guide |
| `generic/` | Generated audio files organized by category |
| `missions/` | Mission-specific custom voice lines |

---

## Folder Structure

```
mission assets/audio/
├── README.md                    # Quick reference (you are here)
├── ELEVENLABS-SETUP.md          # Detailed setup guide
├── VOICE-LINES.md               # Voice line catalog
├── generate_voice_lines.py      # Generation script
├── generic/                     # Generic voice lines for all missions
│   ├── ground-troops/
│   │   ├── requesting-support/
│   │   ├── good-strike/
│   │   ├── keep-going/
│   │   ├── taking-fire/
│   │   ├── target-spotted/
│   │   ├── negative-results/
│   │   ├── winchester-bingo/
│   │   └── friendly-fire-warning/
│   ├── mission/
│   │   ├── mission-start/
│   │   ├── mission-complete/
│   │   └── abort-waveoff/
│   └── threats/
│       ├── sam-warning/
│       ├── enemy-aircraft/
│       └── weather-visibility/
└── missions/                    # Mission-specific voice lines
    └── Dawn Scout/
        ├── Mission Start.wav
        └── Clear To Land.wav
```

---

## Voice Lines Categories

Current categories in VOICE-LINES.md:

### Ground Troops (13 categories)
- **Requesting Support** (7 lines) - "We need air support, NOW!"
- **Reacting to Good Strike** (5 lines) - "Good kill, GOOD kill!"
- **Good But Keep Going** (2 lines) - "Keep it coming!"
- **Taking Fire / Under Attack** (5 lines) - "We're taking fire!"
- **Target Spotted / Tally** (5 lines) - "Visual on hostile armor!"
- **Negative Results / Miss** (3 lines) - "You missed the target!"
- **Winchester / Bingo** (4 lines) - "Winchester! Out of ammo!"
- **Friendly Fire Warning** (3 lines) - "Check fire! Friendlies!"

### Mission Control (5 categories)
- **Mission Start** (5 lines) - "Weapons free, good hunting"
- **Mission Complete** (5 lines) - "All objectives complete, RTB"
- **Abort / Waveoff** (3 lines) - "Wave off, abort!"

### Threats (3 categories)
- **SAM Warning** (3 lines) - "SAM launch! Missile in the air!"
- **Enemy Aircraft** (2 lines) - "Bandit! Enemy fighter inbound!"
- **Weather / Visibility** (2 lines) - "Visibility dropping!"

**Total:** 47 voice lines

---

## Usage Examples

### Example 1: Basic Generation

```bash
# Generate all pending lines with default voice (Adam - deep male voice)
python generate_voice_lines.py
```

Output:
```
Found 30 lines to generate across 14 categories
Estimated character count: 1,245
Voice: pNInz6obpgDQGcFmaJgB
Model: eleven_multilingual_v2

📁 Requesting Support (7 lines)
   Output: generic/ground-troops/requesting-support/
  Generating: Taking HEAVY fire, requesting CAS immediately!...
  ✅ Saved: generic/ground-troops/requesting-support/taking-heavy-fire-requesting-cas-immediately.mp3
  ...
```

### Example 2: Preview Generation (Dry Run)

```bash
# See what would be generated without using API credits
python generate_voice_lines.py --dry-run
```

### Example 3: Different Voice

```bash
# List available voices
python generate_voice_lines.py --list-voices

# Use Rachel (female voice) instead of Adam
python generate_voice_lines.py --voice-id 21m00Tcm4TlvDq8ikWAM
```

### Example 4: Integration with DMS.Audio

```lua
-- In mission script
DMS.Audio.configure({ basePath = "generic/" })

-- Register voice line library
DMS.Audio.registerLibrary("ground_troops", {
    need_support = "ground-troops/requesting-support/we-need-air-support-now.mp3",
    good_kill = "ground-troops/good-strike/good-kill-good-kill.mp3",
    taking_fire = "ground-troops/taking-fire/were-taking-fire-from-the-north.mp3",
})

-- Play random voice line from category
DMS.Audio.playRandomFromLibrary("ground_troops")

-- Play specific line
DMS.Audio.playFromLibrary("ground_troops", "good_kill")

-- Play with delay
DMS.Audio.play("ground-troops/good-strike/good-kill-good-kill.mp3", 2.0)
```

---

## Recommended Voices

### Military/Tactical Male Voices
- **Adam** (`pNInz6obpgDQGcFmaJgB`) - Deep, authoritative ⭐ DEFAULT
- **Antoni** (`ErXwobaYiN019PkySvjV`) - Well-rounded, professional
- **Clyde** (`2EiwWnXFnvU5JabPnv8n`) - War veteran style

### Professional Female Voices
- **Rachel** (`21m00Tcm4TlvDq8ikWAM`) - Calm, clear, commonly used
- **Bella** (`EXAVITQu4vr4xnSDxMaL`) - Soft but clear

### How to Choose
- **Ground troops (urgent/combat):** Lower stability voices with more emotion
- **Mission control (calm/professional):** Higher stability, steady delivery
- **Listen to samples:** https://elevenlabs.io/voice-library

---

## Voice Settings Tuning

The script automatically adjusts voice settings per category:

| Category | Stability | Use Case |
|----------|-----------|----------|
| Taking Fire / Under Attack | 0.3 (Low) | More expressive/urgent |
| SAM Warning | 0.3 (Low) | High urgency |
| Friendly Fire Warning | 0.3 (Low) | Critical urgency |
| Mission Start | 0.7 (High) | Calm, professional |
| Mission Complete | 0.7 (High) | Steady, composed |
| Default | 0.5 (Medium) | Balanced |

All categories use:
- **similarity_boost:** 0.75 (consistent voice)
- **speaker_boost:** Enabled (enhanced clarity)

---

## API Quota Management

### Free Tier
- **10,000 characters/month**
- All voice lines ≈ 2,000 characters
- Can generate complete set **5 times per month**

### Character Count by Category

| Category | Lines | Est. Chars |
|----------|-------|------------|
| Requesting Support | 7 | ~350 |
| Good Strike | 5 | ~200 |
| Taking Fire | 5 | ~225 |
| Mission Start | 5 | ~225 |
| SAM Warning | 3 | ~135 |
| Others | 22 | ~865 |
| **TOTAL** | **47** | **~2,000** |

### Tips
- Use `--dry-run` to preview before generating
- Script skips existing files automatically
- Only pending lines (⏳) are generated
- Mark completed lines as ✅ in VOICE-LINES.md

---

## Troubleshooting

### "API key not found"
```bash
# Check if set
echo $ELEVENLABS_API_KEY  # Linux/Mac
echo %ELEVENLABS_API_KEY%  # Windows

# Set it
setx ELEVENLABS_API_KEY "your-key"  # Windows (restart terminal)
export ELEVENLABS_API_KEY="your-key"  # Linux/Mac
```

### "Rate limit exceeded"
- Free tier: 10,000 chars/month
- Wait until next billing cycle
- Or upgrade plan at https://elevenlabs.io/pricing

### Audio sounds wrong
- Try different voice ID (`--voice-id`)
- Adjust voice settings in script
- Use different model (`--model eleven_flash_v2_5`)

### Script crashes
```bash
# Reinstall dependencies
pip install --upgrade elevenlabs python-dotenv

# Check Python version (3.8+)
python --version
```

---

## Adding New Voice Lines

1. **Edit VOICE-LINES.md:**
   - Add new category or add to existing category
   - Use markdown table format
   - Mark status as ⏳ (needs generation)

2. **Update Script (if needed):**
   - Add category to `CATEGORY_FOLDERS` in `generate_voice_lines.py`
   - Optionally add custom voice settings to `CATEGORY_VOICE_SETTINGS`

3. **Generate:**
   ```bash
   python generate_voice_lines.py
   ```

4. **Verify:**
   - Listen to generated files
   - Test in DCS mission
   - Update VOICE-LINES.md status to ✅

---

## Advanced Usage

### Custom Voice Settings

Edit `generate_voice_lines.py` to customize:

```python
# Add category-specific settings
CATEGORY_VOICE_SETTINGS = {
    "Your New Category": VoiceSettings(
        stability=0.4,          # 0-1: Lower = more expressive
        similarity_boost=0.8,   # 0-1: Higher = more consistent
        style=0.5,              # 0-1: Exaggeration level
        use_speaker_boost=True  # Enhanced clarity
    ),
}
```

### Batch Processing

```bash
# Generate with multiple voices for comparison
python generate_voice_lines.py --voice-id pNInz6obpgDQGcFmaJgB  # Adam
python generate_voice_lines.py --voice-id ErXwobaYiN019PkySvjV  # Antoni
python generate_voice_lines.py --voice-id 21m00Tcm4TlvDq8ikWAM  # Rachel
```

### Output Format

Change format in script:

```python
# For WAV instead of MP3
OUTPUT_FORMAT = "pcm_44100"  # Uncompressed WAV (larger files)

# For higher quality MP3
OUTPUT_FORMAT = "mp3_44100_192"  # 192 kbps
```

---

## Resources

### Documentation
- [ElevenLabs API Docs](https://elevenlabs.io/docs/api-reference/authentication)
- [Python SDK GitHub](https://github.com/elevenlabs/elevenlabs-python)
- [Voice Library](https://elevenlabs.io/voice-library)
- [DMS.Audio Reference](../../lua-library/comms/audio-player.lua)

### Support
- ElevenLabs Help: https://help.elevenlabs.io
- DCS Scripting: https://wiki.hoggitworld.com/view/Simulator_Scripting_Engine
- Project Issues: [GitHub Issues](https://github.com/your-repo/issues)

---

## License & Credits

Voice synthesis powered by [ElevenLabs AI](https://elevenlabs.io)

**Important:** Review ElevenLabs' terms of service regarding:
- Commercial use rights
- Attribution requirements
- Content policy
- Usage limits

Generated audio files are for use in DCS World missions only.

---

**Happy mission building! 🎮✈️**
