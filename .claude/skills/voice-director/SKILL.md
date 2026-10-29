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
  design_prompt, accent, age, gender, cadence, brevity, radio_fx, notes). `dms voice` reads the
  bible two levels above the mission folder and uses `eleven_voice_id` first; speakers without
  one fall back to `data/voice/voices.json` (or `--voices FILE`), keeping the bible's `radio_fx`.
- Multi-speaker lines: a line with `turns: [{speaker, text}, ...]` (2+ turns) renders to ONE
  clip with ElevenLabs Text-to-Dialogue, each turn in its speaker's voice. Every turn speaker
  needs a voice id. Credits = sum of the turn texts.
- `ELEVENLABS_API_KEY` in the environment or in `DMS/.env` (gitignored; `dms voice` loads it).
  Never print it or write it anywhere else. The key does not need the `user_read` permission.

## Outputs

- Edited `lines.yaml`: audio tags inline in `text` where they help, `subtitle` set whenever the
  spoken text differs from the on-screen text (tags are stripped automatically otherwise), and
  optional per-line `radio_fx` overrides. `dms voice` does **not** edit `lines.yaml`: leave
  `file` and `dur_sec` empty there.
- `missions/<id>/voice/manifest.json`, written by `dms voice`:
  `{line_id: {file, dur_sec, text, speaker, model}}` (offline renders add `placeholder: true`).
  `dms plan`/`dms build` read it for `DMS_CONFIG.voice` (file + durSec); lines missing from it
  play as subtitles only. `dms build` warns when any clip is a placeholder.
- Updated `bible.yaml`: `eleven_voice_id` for newly created voices, logged in continuity.md.
- Rendered audio in `missions/<id>/voice/<line_id>.ogg`, cached at
  `~/.dms/tts-cache/<sha256>.ogg` with the key `sha256(voice_id|model|text|<fx>@<fx hash>)`, where
  the fx hash covers the preset's parameters, sample rate and codec (dialogue
  lines: sha256 of the full request, i.e. model, fx and every turn's voice id + text), so
  unchanged lines cost nothing to re-run. The raw pre-FX TTS is cached as well
  (`~/.dms/tts-cache/raw/<sha256 with fx="">.bin`), so changing a speaker's `radio_fx` or tuning an
  FX preset re-runs ffmpeg only and costs **0 credits**; the dry-run counts it that way.

## Steps

1. **Inventory.** Count lines (variants) and characters per speaker. List speakers without an
   `eleven_voice_id` and the beat chains that form exchanges.
2. **Assign voices.** The story-writer normally sets each speaker's bible `eleven_voice_id` from
   the library (`data/voice/voices.json`); keep those. For a speaker without one, reuse a library
   voice that fits the profile (free), and only otherwise design one from `design_prompt` with
   Voice Design. Designing costs credits, so ask the user first. Check distinctness: no two
   recurring speakers share accent and age band. Write the ids back into bible.yaml.
   **Coverage:** every voiced beat must have all its listed variants rendered for its speaker,
   or be subtitle-only by design (no `lines`, just `text`). A half-voiced beat sounds broken.
3. **Direct the lines.** Read `references/elevenlabs-v3.md`.
   - Add tags only where delivery needs help: one leading tag (`[calm]`, `[tense]`, `[urgent]`,
     `[tired]`), and a second one only for a mid-line change.
   - Don't change the wording beyond tags and punctuation. If wording must change, agree it with
     the mission-designer, and keep the line inside the speaker's `brevity`.
   - Use `delivery` notes and the speaker's `cadence` and `notes` as direction.
   - **Stress = fewer words and faster cadence, never louder.** `[urgent]` goes only on beats
     that can fire mid-fight (`unit.hit/shot/dead`, `group.dead`, SAM/wave encounters,
     `director.state: PEAK`). A JTAC in contact may get a breathless-style tag on the check-in
     only, not on every line.
   - Set the set-level `model` (`dms voice` uses it; `--model` on the CLI overrides it). Use
     `eleven_v3` for finals. Use `eleven_flash_v2_5` for cheap
     drafts; it has no tags, so strip them or expect them to be ignored.
4. **Density and duration check** (before paying). Run `uv run dms validate <mission dir>` and
   fix `line_too_long`, `peak_chatter` and `radio_density` findings with the mission-designer
   (they use `voice/manifest.json` durations once rendered, else words / 2.5 per s). Targets:
   PEAK-eligible lines ≤4 s, normal ≤8 s, RELAX character lines ≤10 s; ≤25 s of radio in any
   60 s; no more than 3 radio beats on one trigger. Flag any beat whose longest variant is over
   2× its shortest, since it skews queue timing. Fix all errors and lint warnings you can, max 3
   loops.
5. **Estimate first. Always.**
   ```
   uv run dms voice campaigns/<slug>/missions/<id>/lines.yaml --dry-run
   ```
   The first line reads `N lines (C cached, R to render): X characters ~= Y ElevenLabs credits`.
   Credits are 1 per character for `eleven_v3` / `eleven_multilingual_v2` and 0.5 per character
   for `eleven_flash_v2_5` (the CLI applies the rate). Dialogue lines bill the sum of their turn
   texts. Turn credits into money with the user's plan rate; as a rough guide (self-serve
   plans, late 2026; check elevenlabs.io/pricing): Creator ~= $0.22 / 1k credits, Pro ~= $0.20 / 1k,
   overage ~= $0.30 / 1k. A typical mission (~100 variants, ~6-7k characters, e.g. viper m01:
   101 lines / 6350 chars) is ~6.4k v3 credits ~= $1.40-2.00. Voice Design previews cost extra.
   Report: characters, cached vs. new lines, credits, approximate $, and any voices that would be
   created. **Stop and get the user's go-ahead** before any new cost (unless the user has given
   standing approval for a budget; stay inside it).
6. **Draft pass (optional).** For large sets or new voices, render one variant per speaker with
   `model: eleven_flash_v2_5` (or the CLI's model flag) and listen before the full v3 render.
7. **Render.**
   ```
   uv run dms voice campaigns/<slug>/missions/<id>/lines.yaml
   ```
   The radio FX preset per speaker (`uhf_clean`, `vhf_noisy`, `intercom`, `none`) is applied
   after TTS.
8. **Listen-check** against the checklist below. Fix failures by editing the tags or punctuation
   in `text`, then re-run. Only changed lines miss the cache. To re-roll a take whose text is
   fine but whose delivery is bad, force a fresh take (bills that line again and replaces the
   cached take): `uv run dms voice <mission> --rerender <line_id>` (repeatable), or
   `--no-raw-cache` to re-take every line. Both also work on `python -m dms_voice.cli`.
9. **Report:** files rendered, credits spent, lines flagged, and the next step (`dms build`, via
   the dms-build skill).

## No API key (offline placeholder)

Without a key, run `uv run dms voice <mission> --offline`, or set env `DMS_VOICE_OFFLINE=1`
(only `1`/`true`/`yes`/`on` count; this also covers `dms run`). `--offline` ignores `--model`
with a warning. It renders a quiet tone clip per line, sized to the text (~14 chars/s, 0.8-12 s),
through the same radio FX, cache, `voice/manifest.json` and `.miz` embedding path, at 0 credits and
with no voice ids needed. Use it to build and headless-test audio playback. The cache key carries
model `placeholder`, so a later real render never reuses a placeholder clip; just re-run without
`--offline` (delete `voice/` first so `dms run` doesn't skip the step). Say plainly in the report
that the audio is placeholder. Do not call the ElevenLabs API ad hoc without the user's request.

## How the clips play (so you can direct for it)

`DMS.Comms` queues every line: one at a time, `GAP_SEC` (0.75 s) of silence between them, higher
beat `priority` first, never interrupting. Beats list variants (`lines: [x_v1..x_v4]`); a
per-beat shuffle-bag plays each variant once per cycle and never the same one twice in a row.
Speakers with a support `frequency` transmit on that radio (the player must be tuned in);
everyone else is heard on the coalition. Each play logs
`[DMS][Comms] PLAY n=.. line=.. speaker=.. via=radio|group|coalition|text file=.. start=.. end=..`
in dcs.log. Long clips hold the queue, so keep durations inside the quality bar below.

## Quality bar (listening checklist)

- [ ] Callsigns and numbers pronounced right ("one-one", "niner", place names)
- [ ] Each speaker is recognisable after FX; no two sound alike
- [ ] Delivery fits the situation: routine calls flat, contact calls tight, never theatrical
- [ ] No artefacts: clipped starts, mid-word breaths, robotic pitch, tag words read aloud
- [ ] Loudness consistent across lines (flag outliers)
- [ ] Duration fits: PEAK/terse lines ≤4 s, normal ≤8 s, RELAX character lines ≤10 s; overlong
      lines get rewritten, not sped up
- [ ] Subtitle no longer than the speech (DCS ties the message's screen time to its length, and
      lingering messages have hidden the F10 menu)
- [ ] Exchanges (chained beats) have natural gaps and don't overlap
- [ ] Subtitles match what is said

## Checklist

- [ ] Every speaker has a voice id (bible `eleven_voice_id` or `data/voice/voices.json`, or an
      approved design); distinctness checked
- [ ] Tags added sparingly (`[urgent]` only on PEAK-eligible beats); wording untouched; subtitles correct
- [ ] `dms validate` density/duration lint clean or accepted; every voiced beat fully rendered
- [ ] Dry-run cost reported and approved before any paid render
- [ ] Render complete; listening checklist passed, or failures listed
- [ ] bible.yaml voice ids and continuity.md updated
