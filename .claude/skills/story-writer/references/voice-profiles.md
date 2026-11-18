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
  notes: "Understated. Humour is bone dry and rare. Habit: closes every tasking with 'Ops out.'"
```

## Library voices (assign up front)

`data/voice/voices.json` holds voices that already exist, so using one costs nothing. Set the
character's `eleven_voice_id` to the `voice_id` of the closest fit. Several speakers may share a
library voice only if they never talk in the same mission.

| key | `eleven_voice_id` | fits |
|---|---|---|
| `mission_control` | `IqaWsJgCV6ihH2Uh6Jb2` | calm male controller: tower, ops |
| `awacs_magic` | `2qVLKOamXa29yju9mqTK` | AWACS / GCI |
| `ops_lindqvist` | `XrExE9yKIg1WjnnlVkGX` | female, even American: ops officer |
| `briefing_officer` | `T3RkkRObzq7rCMQT4zhL` | Australian officer: ops, briefings |
| `warning_system` | `vIuLMrDs3Mbl0w5kvuKe` | American fighter pilot, Southern hint: wingman, other aircrew |
| `jtac` | `PtGjyQZ7kCARwCuiOKQL` | American soldier, high energy: JTAC |
| `ground_troops` | `KgoKSoe0uSDQXTd5sh94` | soldier under fire: ground commander, team in contact |

Read the file for the current list (keys can be added). No good fit: leave `eleven_voice_id:
null`, write the `design_prompt`, and the voice-director designs it (with the user's approval).

## Verbal habits

Give each recurring speaker one habit and one procedural tell in `notes`, e.g. "Always says
'welcome back' on the recovery call", "Counts impacts down: 'splash in three... two...'",
"Reads grids twice when tired". Mission lines reuse them, so character survives brevity.

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
