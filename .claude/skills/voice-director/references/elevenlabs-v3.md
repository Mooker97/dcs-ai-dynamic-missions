# ElevenLabs v3 for radio chatter

## Models (`VoiceLineSet.model`)

| Value | Use |
|---|---|
| `eleven_v3` | final renders, with audio tags and the best emotional range |
| `eleven_flash_v2_5` | cheap, fast drafts to audition voices and pacing; no audio tags |
| `eleven_multilingual_v2` | non-English lines (e.g. enemy intercepts) when v3 struggles |
| Text-to-Dialogue (v3) | multi-speaker exchanges: a chain of beats rendered as one take |
| Voice Design | creates a voice from a bible `design_prompt`. Costs credits; reuse the id afterwards |

## Audio tags, used sparingly

Tags go inline in `text` (`VoiceLine.text` allows them). Subtitles strip them automatically, or you
can set `subtitle` explicitly.

- One leading tag sets the state: `[calm]`, `[tired]`, `[tense]`, `[urgent]`, `[matter-of-fact]`,
  `[relieved]`, `[whispers]`, and rarely `[shouts]` (only over gunfire or rotor noise).
- A mid-line tag marks a change: `"[calm] Kestrel copies. [tense] Wait. Movement north."`
- Non-verbal tags (`[exhales]`, `[clears throat]`): at most one per mission, not one per line.
- Never stack 3+ tags or tag every line. No comic tags (`[laughs]`) on a combat net unless it's an
  established habit of the character.
- Punctuation is direction too: commas add pauses, an ellipsis adds hesitation, a full stop makes
  the delivery crisp. Avoid ALL CAPS, which v3 may shout.

## Text-to-Dialogue for exchanges

lines.yaml has no multi-speaker entries. An exchange is a chain of beats: B has
`when: {event: beat.fired, beat: A}` and a `delay_sec` of 2–4. For overheard chatter you may render
a chain as one Text-to-Dialogue take, if the CLI supports it, to get natural turn timing. Otherwise
render each line separately and let `delay_sec` space them. Keep exchanges to 2–4 turns and
under 15 s.

## Radio FX presets (`RadioFxPreset`, applied by ffmpeg after TTS)

| Preset | Chain (indicative) | Typical speakers |
|---|---|---|
| `uhf_clean` | high-pass 300 Hz, low-pass 3400 Hz, compressor ~4:1, squelch tail | aircraft, ATC, ops |
| `vhf_noisy` | same band, noise bed, peak distortion, harder squelch | ground teams, convoy, FOB |
| `intercom` | wider band (~200–5000 Hz), no squelch, faint rotor/engine bed | front-seater / crew |
| `none` | loudness normalisation only | narrator, briefing audio |

Render the TTS **clean**, then apply FX. Never ask the voice model to imitate a radio. Per-line
`radio_fx` overrides the speaker preset, e.g. a tower call relayed over a noisy link.

## Cache and cost

- Cache key: `sha256(voice_id|model|text|fx_preset)` → `~/.dms/tts-cache/<sha256>.ogg`. Editing one
  variant's `text` re-renders only that variant. Changing `model` or a speaker's preset re-renders
  everything that uses it.
- Cost scales with the characters sent, and tags count. **Always run
  `uv run dms voice <lines.yaml> --dry-run` first**, show the estimate, and get approval before
  creating voices or doing large renders.
- A typical mission is 12–20 voiced beats × 3–5 variants × ~60 chars ≈ 2–6k characters.

## Settings starting points

- Stability around 0.5 (natural variation across variants), similarity 0.75+, style 0.2–0.4. Military
  speakers sound better slightly *less* expressive.
- Use the same settings for every line of a character, so they stay consistent across missions.

## Listening checklist

Pronunciation of callsigns, numbers and places · speaker distinctness after FX · delivery matches
the situation · no artefacts or spoken tags · consistent loudness · duration within brevity ·
spacing between exchange turns · subtitles match.
