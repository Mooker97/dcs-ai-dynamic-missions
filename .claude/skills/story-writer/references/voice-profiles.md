# Voice profiles

Each speaking character gets a `voice` block (`VoiceProfile`). The voice-director turns it into an
ElevenLabs voice.

```yaml
voice:
  eleven_voice_id: null        # set once a library/designed voice exists; reuse it across missions
  design_prompt: >-
    Female Australian army operations officer, early 40s, low-mid pitch, slightly husky. Dry,
    economical delivery with a flat General Australian accent. Speaks in short radio phrases,
    never rushes, and her voice tightens rather than rises under pressure. Recorded close on a
    headset microphone in a quiet operations room.
  accent: General Australian
  age: 42
  gender: female
  cadence: measured            # slow | measured | brisk | rapid
  brevity: terse               # terse | normal | chatty
  radio_fx: uhf_clean          # uhf_clean | vhf_noisy | intercom | none
  notes: "Understated. Humour is bone dry and rare."
```

## Writing a Voice Design prompt (60–120 words)

Cover, in this order:
1. **Who:** role, rank feel, age, gender.
2. **Sound:** pitch, timbre (gravelly, bright, husky), accent with region.
3. **Delivery:** pace, cadence, how stress shows (tightens, speeds up, gets quieter).
4. **Context:** where they speak from (cockpit under g, ops room, vehicle on the move).

Avoid celebrity names, real people, "radio filter" (FX are added later; a clean recording is better)
and contradictory adjectives.

Starting points (adapted from `legacy/elevenlabs-integration/docs/VOICE-CATALOG.md`):

| Role | Core of the prompt | cadence / radio_fx |
|---|---|---|
| AWACS / GCI | 35–45, neutral Midwest American, perfectly measured, technical, unflappable | measured / uhf_clean |
| JTAC | 28–38, slight Southern/Western American, crisp brevity, controlled urgency in contact | brisk / vhf_noisy |
| Ground commander | 40–55, calm senior NCO, steady under fire, authority without shouting | measured / vhf_noisy |
| CAS / attack pilot | 30–42, cool and clipped, relaxed confidence, short weapon calls | brisk / uhf_clean |
| Tower / ATC | 30–50, neutral, methodical, slightly bored, precise numbers | measured / uhf_clean |
| British soldier | 24–32, regional British (Yorkshire, Scottish), dry wit, brisk | brisk / vhf_noisy |
| Front-seater / CPG | crew voice inside the player's aircraft | brisk / intercom |

## Distinctness on the radio

Band-passed audio flattens voices. Separate recurring speakers by at least two of: gender, age band,
accent, cadence, timbre. Two recurring speakers never share both accent and age band.

## Brevity

- `terse` (the default for military speakers): 3–12 words per transmission, callsign first, no filler.
- `normal`: up to about 20 words. Use it for ops briefings and ground commanders explaining a situation.
- `chatty`: civilians, journalists and rare characters only.

## radio_fx presets (`RadioFxPreset`)

| Preset | Use for | Sound |
|---|---|---|
| `uhf_clean` | aircraft, ATC, ops on UHF | 300–3400 Hz band-pass, light compression, squelch tail |
| `vhf_noisy` | ground units, FM squad and vehicle nets | band-pass, noise bed, peak distortion |
| `intercom` | cockpit crew (front-seater) | wider band, no squelch, slight engine bed |
| `none` | narrator / briefing audio | no processing |

Individual lines may override the preset with `radio_fx` in lines.yaml.
