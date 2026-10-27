# Voice Catalog & Prompts

Catalog of DMS voices, generic voice lines, and ElevenLabs voice-design prompts.
Adapted from `legacy/elevenlabs-integration/docs/VOICE-CATALOG.md`.

| File | Purpose |
|------|---------|
| `data/voice/voices.json` | Voice registry: voice key -> `voice_id`, name, description, categories, settings |
| `data/voice/voices.template.json` | Same shape with placeholder IDs, for a fresh ElevenLabs account |
| `data/voice/lines/generic.yaml` | The generic line set below, in `VoiceLineSet` shape (the source of truth) |
| `assets/audio/generic/...` | Rendered takes that already exist (referenced from `audio:` in the YAML) |
| `examples/dustoff-corridor/voice_lines.yaml` | Mission-specific lines for the reference mission |

API keys never go in any of these files. Set `ELEVENLABS_API_KEY` in the environment.

---

## Voices

| Key | Name | Use for |
|-----|------|---------|
| `ground_troops` (default) | Sgt Butterfield - Combat Ground | Requesting Support, Good Strike, Keep Going, Taking Fire, Tally |
| `mission_control` | Twr Marcus - Military Controller | Mission Start, Mission Complete, Abort / Waveoff |
| `briefing_officer` | Capt Lockyer - Australian Briefing Officer | Mission Start (briefing opener) |
| `warning_system` | Capt Willis - Fighter Pilot | SAM Warning, Enemy Aircraft, Friendly Fire, Weather |
| `jtac` | Sgt Brown - Combat Ground | Negative Results / Miss, Winchester / Bingo |
| `awacs_magic` | AWACS - Magic | AWACS calls (made from the AWACS Controller prompt below) |

---

## Generic Voice Lines (54 total)

The legacy catalog header said 47 lines. Its tables actually contain 54, and all 54 are kept.
Line text lives in `lines/generic.yaml`. This table tracks which ones have been rendered.

| Category | Line ids | Count | Rendered audio (`assets/audio/generic/`) |
|----------|----------|-------|------------------------------------------|
| Requesting Support | `support_request_01..07` | 7 | none (legacy marked #1 recorded, but no file exists) |
| Reacting to Good Strike | `good_kill_01..05` | 5 | `ground-troops/good-kill.wav` (01) |
| Good But Keep Going | `keep_going_01..02` | 2 | `ground-troops/good-kill-keep-em-coming.wav`, `keep-em-coming.wav` (01) |
| Taking Fire / Under Attack | `taking_fire_01..05` | 5 | none |
| Target Spotted / Tally | `tally_01..05` | 5 | none |
| Negative Results / Miss | `miss_01..03` | 3 | none |
| Winchester / Bingo | `winchester_bingo_01..04` | 4 | none |
| Friendly Fire Warning | `friendly_fire_01..03` | 3 | none |
| Mission Start | `mission_start_01..05` | 5 | `mission-start/mission-is-a-go.wav` + `good-hunting.wav` (02), `weapons-free.wav` (03), `stay-sharp.wav` (04); legacy marked 05 recorded, but no file exists |
| Mission Complete | `mission_complete_01..05` | 5 | `mission-complete/obj-complete.wav` (01), `mission-success.wav` (02) |
| Abort / Waveoff | `abort_01..03` | 3 | none |
| SAM Warning | `sam_warning_01..03` | 3 | none |
| Enemy Aircraft | `bandit_01..02` | 2 | none |
| Weather / Visibility | `weather_01..02` | 2 | none |

Suggested categories that have no lines yet: **Extraction / CSAR** (rescue coordination).

Mission-specific rendered audio: `assets/audio/missions/dawn-scout/` (`mission-start.wav`, `clear-to-land.wav`).

---

## Voice Creation Prompts

Copy/paste these into ElevenLabs Voice Design to create voices.

### AWACS Controller
```
Professional male AWACS controller, age 35-45, American accent with neutral/Midwest tone, highly trained military radio voice with perfect clarity and measured cadence. Calm and composed even during emergencies, technical vocabulary delivered naturally, authoritative presence without aggression. Clear diction for critical radio communications, steady breathing, confident tone from years of air battle management experience.
```

### JTAC (Forward Air Controller)
```
Male JTAC (forward air controller), age 28-38, American accent with slight Southern or Western undertone, professional military radio voice that shifts from calm professionalism to controlled urgency under contact. Quick, precise speech patterns using brevity codes naturally, combat-experienced delivery that's direct and unambiguous. Clear radio voice even under stress, confident targeting calls, slightly elevated heart rate audible during hot situations.
```

### Female Fighter Pilot
```
Female fighter pilot, age 26-35, American accent with confident and sharp tone, highly trained military aviator voice with quick reaction times and zero hesitation. Professional combat communications under high g-forces and stress, athletic breathing patterns, crisp and commanding delivery. Slightly elevated pitch during emergency callouts but always maintaining control, sharp tactical awareness in voice, decisive and direct communication style.
```

### Calm Ground Commander
```
Male ground commander (senior NCO or officer), age 40-55, American accent with neutral tone, deeply experienced military voice that remains calm and measured even under heavy fire. Combat veteran delivery with professional military bearing, controlled breathing during contact, authoritative without shouting. Voice of experience and confidence from 20+ years service, steady cadence that provides reassurance to subordinates, clear tactical communications under any stress level.
```

### British Ground Troops
```
Male British ground soldier, age 24-32, British accent (regional - Yorkshire, Cockney, or Scottish options), professional British Army voice with characteristic composure and dry wit even under fire. Quick tactical communications with British military terminology, controlled urgency that never quite breaks into panic, brief and efficient radio calls. Clear accent for international operations, combat-ready delivery, slight breathlessness during contact but always maintaining British professionalism.
```

### Navy Carrier Controller
```
Male naval air traffic controller (carrier tower), age 35-50, American accent with neutral tone, professional Navy aviation voice trained for aircraft carrier operations. Calm and methodical delivery of technical launch and recovery instructions, clear enunciation over deck noise and wind, carrier-specific terminology delivered naturally. Authoritative tone for critical safety calls, steady pacing for deck operations, confident voice from years of carrier aviation experience.
```

### Female AWACS/Controller
```
Professional female military controller, age 30-42, American or British accent with neutral professional tone, highly trained in air battle management with exceptional radio communication skills. Warm but authoritative presence, calm and composed during high-threat situations, technical vocabulary delivered with confidence and clarity. Clear enunciation for long-range communications, measured cadence that conveys control of the situation, professional detachment with underlying competence and years of training.
```

### Close Air Support Pilot
```
Male close air support pilot (A-10 or Apache), age 30-42, American accent with focused and intense tone, ground attack specialist with calm aggressive mindset during target engagement. Professional delivery with predator-like focus on ground targets, controlled intensity during gun runs, clear and precise targeting calls. Voice of controlled aggression, confident in weapons employment, tactical patience mixed with lethal capability, years of CAS experience evident in calm but deadly tone.
```

---

## Voice Assignment Recommendations

| Voice Type | Best For Categories |
|------------|-------------------|
| **Ground Troops (Excited)** | Requesting Support, Good Strike, Taking Fire |
| **Ground Commander (Calm)** | Target Spotted, Status Reports |
| **AWACS/Controller** | Mission Start/Complete, SAM Warning, Weather |
| **JTAC** | Good Strike reactions, Negative Results, Target Spotted |
| **Fighter Pilot** | Enemy Aircraft, SAM Warning, Winchester/Bingo |
| **Warning System** | All Warnings (automated tone) |

---

## Usage

### Create a voice
1. Go to https://elevenlabs.io/app/voice-lab
2. Click "Add Voice" -> "Voice Design"
3. Copy a prompt from above, paste it, and generate
4. Save the voice and copy its Voice ID into `data/voice/voices.json` under a new or existing key

### Generate voice lines
```bash
dms voice data/voice/lines/generic.yaml      # see docs/CONTRACTS.md
```
Rendered takes are cached at `~/.dms/tts-cache/<sha256>.ogg`, keyed by
`sha256(voice_id|model|text|fx_preset)`. The legacy generator
(`legacy/elevenlabs-integration/scripts/generate_with_custom_voices.py`) is kept for reference only.
