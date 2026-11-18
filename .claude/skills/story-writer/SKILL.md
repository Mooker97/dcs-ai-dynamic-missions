---
name: story-writer
description: Turn a DCS campaign premise or story idea into a DMS story bible. Use when the user wants to start a new DCS campaign or mission series from a story (historical, adapted, fictional or fantasy), says things like "I have an idea for a campaign", "write the story bible", "set up campaigns/<slug>", or asks to add or change factions, characters or voices in an existing bible.yaml. Produces campaigns/<slug>/premise.md, bible.yaml and a seeded continuity.md.
---

# story-writer

Turn a premise into the canonical **story bible** for a DMS campaign. Later agents (campaign-planner,
mission-designer, voice-director, debriefer) read your files instead of remembering, so the bible
must be complete, consistent and schema-valid.

## Inputs

- The user's premise (free text, a file in `supporting Files/`, or a short pitch).
- Answers to a brief interview (step 1).
- For `historical` / `adapted` modes: web research (step 3).

## Outputs (all under `campaigns/<slug>/`)

| File | Skeleton | Notes |
|---|---|---|
| `premise.md` | `campaigns/_template/premise.md` | pitch + interview answers |
| `bible.yaml` | `campaigns/_template/bible.yaml` | `StoryBible`, must validate (step 7) |
| `continuity.md` | `campaigns/_template/continuity.md` | canon at start + open threads + first log entry |

Worked example: `campaigns/dustoff-valley/` (premise.md, bible.yaml).
Schema: `schemas/story-bible.schema.json`. The source of truth is
`packages/dms-core/src/dms_core/schemas/story.py` (`StoryBible`, `Setting`, `Tone`, `Faction`,
`FactionDCS`, `Character`, `VoiceProfile`, `TimelineEvent`, `Source`). Its `Field(description=...)`
texts are authoritative guidance. Unknown keys are rejected.

## bible.yaml shape (top level)

`schema_version: 1` · `title` · `mode` (historical|adapted|fictional) ·
`setting {era: int year, theater: <DCS map enum>, region, premise_summary}` ·
`tone {style, themes: []}` · `player_role` (string, e.g. "AH-64D crew, Australian Army aviation
detachment, callsign Dusty") · `factions[]` · `characters[]` · `timeline[]` · `sources[]` ·
`canon_rules[]`.
There is no `id`, `player` or `glossary` key. Put the mode rationale, recurring callsigns and
codewords in `canon_rules` or `premise.md`.

Theater enum: Caucasus, Syria, PersianGulf, Nevada, MarianaIslands, Sinai, Kola, Afghanistan,
Normandy, TheChannel, Falklands, GermanyCW.

## Steps

1. **Interview briefly** (one message, at most 8 questions, with defaults offered so the user can
   answer "defaults are fine"). Cover tone, era (year), realism (grounded / stylised / fantasy),
   mode, player aircraft + callsign, theater + home base, scope, mission length, failure
   tolerance and hard no's. Skip anything the premise already answers. Defaults:
   - **Scope:** 4–5 main-line missions. Optional branch (recovery) missions are extra and don't
     count toward the number.
   - **Length:** 45–60 min per mission, an air start offered, transit 20 min or less.
   - **Failure:** fail forward (a loss branches to a different mission); permadeath only on request.
   Record the answers in premise.md; campaign-planner holds to the scope number.
2. **Pick the slug** (short kebab-case) and run `uv run dms new-campaign <slug>` (copies
   `campaigns/_template/`). Then delete `missions/m01-example/` and
   `state/outcomes/mNN-example.yaml`.
3. **Decide the mode and research if needed.** Read `references/modes-and-sourcing.md`.
   - `historical` / `adapted`: launch 1–3 research subagents in parallel (Agent tool,
     general-purpose, WebSearch/WebFetch) with narrow questions. Each returns
     `{claim, source_url, confidence, note}`. Every claim you use goes in `sources` or in a
     timeline event's `source`.
   - `fictional`: real geography and real equipment are still claims, so cite them where they
     carry weight.
   - Explain the choice of mode in the first `canon_rules` entry ("Mode fictional: ...") and in
     premise.md.
4. **Map factions to DCS.** Read `references/faction-mapping.md`. Each faction is
   `{id, name, description, doctrine, dcs: {country, coalition, units[], tech_veneer}}`. Note that
   `country` is a **single** DCS country (make a second faction for a second country), and
   `units` lists era-correct DCS type ids. `tech_veneer` is a free-text string explaining which
   real gear stands in for fictional gear.
   - **Player coalition rule.** The player's DCS coalition is the coalition the catalog gives the
     player airframe, whatever the politics: `uv run dms catalog units --era <year> --category
     plane|helicopter` (e.g. Mi-8MT, Mi-24P, Ka-50 are red; F-16C_50, A-10C_2, AH-64D_BLK_II,
     UH-1H are blue). Put the player's faction on that side and every enemy faction on the other,
     even if that puts, say, Abkhazia on blue. Record it in `canon_rules`
     (`"Coalition: player flies Mi-8MT, so Georgian forces are DCS red and Abkhaz forces blue."`).
5. **Write characters.** 3–7 speaking roles is enough: ops/command, tower/ATC, a ground voice, a
   supporting flight, and optionally an antagonist heard only through intel. Each character has
   `{id, name, callsign, role, faction, real_person, description, arc, voice}`, with
   `real_person: false` for anyone invented. Every radio speaker needs a `voice` (see
   `references/voice-profiles.md`):
   `{eleven_voice_id, design_prompt, accent, age, gender, cadence, brevity, radio_fx, notes}`.
   - **Enums are strict** (free text fails validation): `cadence` slow|measured|brisk|rapid,
     `brevity` terse|normal|chatty, `radio_fx` uhf_clean|vhf_noisy|intercom|none.
   - **Assign `eleven_voice_id` now** from the library (`data/voice/voices.json`, table in
     `references/voice-profiles.md`) when one fits. It's free, and `dms voice --dry-run` fails
     for a speaker with no id. Leave it `null` only for a voice you intend to design.
   - Give each recurring speaker a **verbal habit and a procedural tell** in `notes` (a tower
     controller who always says "welcome back", a JTAC who counts down impacts), so character
     lives inside procedure.
6. **Fill the rest.**
   - `setting`, `tone` (2–4 themes), `player_role`.
   - `timeline`: each event is `{date, event, fictional, source}`. Mark invented events
     `fictional: true`. A real event takes `source: {claim, source_url, confidence}`.
   - `canon_rules`: hard rules, the mode rationale, the coalition rule (step 4), callsign
     conventions, and the campaign's **stakes vocabulary**: what losing looks like in this world
     ("villages on the ridge fall", "the partner force withdraws"), so the planner and designer
     state stakes consistently.

   Then write `premise.md`. Seed `continuity.md` with canon at start, 2–4 open threads, and the log
   entry `### <date> — story-writer — campaign created`.
7. **Validate.** Fix all errors, max 3 loops; report the error verbatim if it still fails.
   (`dms validate` takes mission folders and `arc.yaml`, not the bible, so use the model directly.)
   ```
   uv run python -c "import yaml; from dms_core.schemas import StoryBible; StoryBible.model_validate(yaml.safe_load(open('campaigns/<slug>/bible.yaml', encoding='utf-8'))); print('OK')"
   ```
8. **Hand off.** Summarise the bible in ≤10 lines and suggest the next step: the campaign-planner skill.

## Quality bar

- A stranger can read `premise_summary` and know who, where, why now, and what the player is for.
- Every faction resolves to a real DCS country and era-correct units. Nothing is hand-waved.
- Real people get `real_person: true` and no invented quotes or private actions. Prefer a
  fictional stand-in, which is the default when in doubt.
- Voices are distinct on the radio. Each `design_prompt` is a usable 60–120-word ElevenLabs prompt,
  not a list of adjectives.
- Tone is military-professional by default: the story lives in the gaps around procedure, not in speeches.
- At least one character's fate can become a quality outcome (alive, wounded or captured by
  mission N), so qualities have faces.
- The player coalition follows the catalog rule, not the politics.

## Checklist

- [ ] Interview done (or defaults explicitly accepted)
- [ ] `mode` set and the rationale recorded; every real-world claim has a `Source` with confidence
- [ ] Factions: one `country`, `coalition`, era-correct `units`; `tech_veneer` text only where gear is fictional
- [ ] Player coalition = the catalog coalition of the player airframe; enemies on the other side; recorded in `canon_rules`
- [ ] Characters: unique ids, `real_person` correct, complete `voice` for every speaker (exact enums, library `eleven_voice_id` where one fits, verbal habit in `notes`)
- [ ] `canon_rules` has the mode rationale, coalition rule and stakes vocabulary
- [ ] Scope (main-line mission count), length and failure tolerance recorded in premise.md
- [ ] `player_role` matches the interview (aircraft, unit, callsign, home base)
- [ ] premise.md, bible.yaml, continuity.md written; bible validates (fix all errors, max 3 loops)
- [ ] Nothing written outside `campaigns/<slug>/`
