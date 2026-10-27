---
name: voice-director
description: Plan and render voiced radio chatter for a DMS mission with ElevenLabs. Use when a mission's lines.yaml exists and the user wants voices assigned or designed, audio tags added, a cost estimate, or audio rendered ("voice this mission", "generate the radio lines", "how much will the voices cost", "re-record Kestrel's lines"). Drives `uv run dms voice --dry-run` then `uv run dms voice`.
---

# voice-director

Turn `lines.yaml` into rendered, radio-processed `.ogg` files. Assign or design voices, add Eleven v3
audio tags sparingly, render beat chains with Text-to-Dialogue where it helps, **estimate the cost
before spending anything**, and listen-check the result.

## Inputs

- `campaigns/<slug>/missions/<id>/lines.yaml`: a `VoiceLineSet` `{mission_id, model, lines[]}`.
  Each entry is one variant: `{id, speaker, text, subtitle, beat, delivery, radio_fx, file, dur_sec}`.
  Schema: `schemas/voice-lines.schema.json`; model: `packages/dms-core/src/dms_core/schemas/voice.py`.
- `campaigns/<slug>/missions/<id>/beats.yaml`, to find exchanges (beats chained with
  `when: {event: beat.fired}` and a short `delay_sec`).
- `campaigns/<slug>/bible.yaml` → `characters[].voice` (`VoiceProfile`: eleven_voice_id,
  design_prompt, accent, age, gender, cadence, brevity, radio_fx, notes).
- `ELEVENLABS_API_KEY` in the environment. Never print it or write it to a file.

## Outputs

- Edited `lines.yaml`: audio tags inline in `text` where they help, `subtitle` set whenever the
  spoken text differs from the on-screen text (tags are stripped automatically otherwise), and
  optional per-line `radio_fx` overrides. `file` and `dur_sec` are filled in by `dms voice`.
- Updated `bible.yaml`: `eleven_voice_id` for newly created voices, logged in continuity.md.
- Rendered audio in `missions/<id>/voice/`, cached at `~/.dms/tts-cache/<sha256>.ogg` with the key
  `sha256(voice_id|model|text|fx_preset)`, so unchanged lines cost nothing to re-run.

## Steps

1. **Inventory.** Count lines (variants) and characters per speaker. List speakers without an
   `eleven_voice_id` and the beat chains that form exchanges.
2. **Assign voices.** For each speaker without an id, reuse a library voice that fits the profile,
   or design one from `design_prompt` with Voice Design. Designing costs credits, so ask the user
   first. Check distinctness: no two recurring speakers share accent and age band. Write the ids
   back into bible.yaml.
3. **Direct the lines.** Read `references/elevenlabs-v3.md`.
   - Add tags only where delivery needs help: one leading tag (`[calm]`, `[tense]`, `[urgent]`,
     `[tired]`), and a second one only for a mid-line change.
   - Don't change the wording beyond tags and punctuation. If wording must change, agree it with
     the mission-designer, and keep the line inside the speaker's `brevity`.
   - Use `delivery` notes and the speaker's `cadence` and `notes` as direction.
   - Set the set-level `model`. Use `eleven_v3` for finals. Use `eleven_flash_v2_5` for cheap
     drafts; it has no tags, so strip them or expect them to be ignored.
4. **Estimate first. Always.**
   ```
   uv run dms voice campaigns/<slug>/missions/<id>/lines.yaml --dry-run
   ```
   Report the character count, cached vs. new lines, estimated credits and cost, and any voices
   that would be created. **Stop and get the user's go-ahead** before any new cost.
5. **Draft pass (optional).** For large sets or new voices, render one variant per speaker with
   `model: eleven_flash_v2_5` (or the CLI's model flag) and listen before the full v3 render.
6. **Render.**
   ```
   uv run dms voice campaigns/<slug>/missions/<id>/lines.yaml
   ```
   The radio FX preset per speaker (`uhf_clean`, `vhf_noisy`, `intercom`, `none`) is applied
   after TTS.
7. **Listen-check** against the checklist below. Fix failures by editing the tags or punctuation
   in `text`, then re-run. Only changed lines miss the cache.
8. **Report:** files rendered, credits spent, lines flagged, and the next step (`dms build`, via
   the dms-build skill).

## If the CLI is not ready

If `uv run dms voice` isn't implemented yet, say so plainly. Still do steps 1–3 and give a manual
character-count estimate (sum of `len(text)` over the lines × the model's per-character price). Do
not call the ElevenLabs API ad hoc without the user's explicit request.

## Quality bar (listening checklist)

- [ ] Callsigns and numbers pronounced right ("one-one", "niner", place names)
- [ ] Each speaker is recognisable after FX; no two sound alike
- [ ] Delivery fits the situation: routine calls flat, contact calls tight, never theatrical
- [ ] No artefacts: clipped starts, mid-word breaths, robotic pitch, tag words read aloud
- [ ] Loudness consistent across lines (flag outliers)
- [ ] Duration fits: terse lines ≤4 s, normal lines ≤8 s; overlong lines get rewritten, not sped up
- [ ] Exchanges (chained beats) have natural gaps and don't overlap
- [ ] Subtitles match what is said

## Checklist

- [ ] Every speaker has a voice id (or an approved design); distinctness checked
- [ ] Tags added sparingly; wording untouched; subtitles correct
- [ ] Dry-run cost reported and approved before any paid render
- [ ] Render complete; listening checklist passed, or failures listed
- [ ] bible.yaml voice ids and continuity.md updated
