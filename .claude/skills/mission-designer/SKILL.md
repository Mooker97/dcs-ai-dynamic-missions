---
name: mission-designer
description: Design the next playable DMS mission from a campaign arc entry and the current campaign state. Use when the user wants to write, detail or redesign a specific mission ("design m03", "write the next mission", "make the briefing and radio lines for this mission"), after campaign-planner has produced arc.yaml or after the debriefer has chosen the next mission. Produces missions/mNN-<slug>/{mission-spec.yaml, beats.yaml, lines.yaml, briefing.md, kneeboard.md} and runs `uv run dms validate`.
---

# mission-designer

Turn one arc entry into a complete, validated mission package: a declarative spec the generator
compiles, beats the Lua narrative engine fires, voice-line variants, a 5-paragraph briefing and a
kneeboard. Design the mission **just before it's flown**, so it reflects what actually happened
in earlier missions.

## Inputs (read all of them, every time)

1. `campaigns/<slug>/bible.yaml`: mode, factions (country, units), characters and voices, canon rules.
2. `campaigns/<slug>/arc.yaml`: the mission entry (`synopsis`, `key_beats`, `characters`,
   `quality_effects`, branches). If no mission is named, use the latest "Next:" entry in
   continuity.md, or else the first `planned` mission.
3. `campaigns/<slug>/state/qualities.yaml` (values, flags, outcomes) and every `state/outcomes/*.yaml`.
4. `campaigns/<slug>/continuity.md`, the whole file: who is alive, what is destroyed, open threads.

## Outputs: `campaigns/<slug>/missions/<mission id>/`

| File | Model (`packages/dms-core/src/dms_core/schemas/`) | JSON Schema |
|---|---|---|
| `mission-spec.yaml` | `mission.py` `MissionSpec` | `schemas/mission-spec.schema.json` |
| `beats.yaml` | `beats.py` `BeatSheet` / `Beat` | `schemas/beats.schema.json` |
| `lines.yaml` | `voice.py` `VoiceLineSet` / `VoiceLine` | `schemas/voice-lines.schema.json` |
| `briefing.md`, `kneeboard.md` | n/a; see `references/briefing-format.md` | n/a |

Skeletons: `campaigns/_template/missions/`. Worked example:
`campaigns/dustoff-valley/missions/m01-first-light/`. The field descriptions in the models are
authoritative. Unknown keys are rejected.

## Steps

1. **State digest.** Write yourself 5–10 lines: the dramatic question, which qualities and flags
   change this mission and how, continuity facts to honour, threads to touch or pay off, and the
   outcome keys the arc expects.
2. **Shape the flight.** Plan departure → transit → on-station → complication → egress → recovery.
   Decide where tension peaks, where the player breathes, and what is guaranteed versus random.
   Record this in `notes` (designer intent, not compiled) and set
   `dynamic.director {enabled, intensity: calm|moderate|intense, adaptive}`.
3. **Write `mission-spec.yaml`.** Areas and roles only; never coordinates, unit ids or CLSIDs.
   - Header: `id` (= folder), `title`, `campaign`, `content_mode` (= bible mode), `theater`,
     `era`, `date` (YYYY-MM-DD), `start_time` (HH:MM), `weather_preset`
     (clear|scattered|broken|overcast|rain|storm|dust|fog|night_clear), `mission_type`,
     `duration_min`, `blue_countries`, `red_countries`, `cast` (every speaker id).
   - `areas[]`: `{id, description, where, terrain}`. `where.kind` is one of `near_airbase`
     `{airbase, radius_nm, bearing_deg, distance_nm}`, `near_named_place`
     `{place, radius_nm, bearing_deg, ...}`, `latlon`, or `zone` (polygon points).
   - `player_flights[]`: `{callsign, aircraft, count, coalition, country, start_area, start_type,
     loadout, frequency_mhz, tasking}`.
   - `objectives[]`: kind destroy|protect|escort|reach|recon|rescue|survive|land, with `area`,
     `target`, and `success_flag` / `failure_flag` that beats set.
   - `threats[]`: `{role, area, strength light|medium|heavy, faction, skill, hidden_on_map}`.
     Threats named in the briefing as known get `hidden_on_map: false`. Scale threats by
     qualities (low intel means more hidden threats; high enemy AA means `heavy`).
   - `support[]`: `{role, callsign, area, route, composition, speaker}`.
   - `dynamic`: `pools[] {id, roles, areas, pick: [min,max], faction, notes}`, and
     `encounters[] {id, kind, pool, trigger {type proximity|beat|director|time, area, radius_nm,
     beat, after_min}, chance, telegraph_beat, waves, gap_min, hunt}`, plus `fog_of_war`.
     See `references/beats-and-encounters.md`.
4. **Write `beats.yaml` (≥10 beats)** as `{mission_id, beats: [...]}`. Read
   `references/beats-and-encounters.md`.
   - **Guaranteed** beats (mission start, objective payoff, RTB call, landed/debrief, mission end
     on death) must be reachable in every playthrough. There is no schema field for this: put a
     `# GUARANTEED` comment above each one, and make them cover the arc's `key_beats`.
   - **Optional** beats react to what happens.
   - `lines` lists the **variant ids** (e.g. `[ops_cleared_v1, ops_cleared_v2, ops_cleared_v3]`),
     and a beat with lines needs a `speaker`.
   - Outcome keys go in `effects.outcome`, using the arc's keys exactly. Quality changes go in
     `effects.quality_deltas`, the result in `effects.end_mission`, and objective flags in
     `effects.set_flag`.
   - Telegraph every punishment 30–60 s ahead.
   - Exchanges between two speakers are **chained beats**: beat B has
     `when: {event: beat.fired, beat: A}` with `delay_sec`.
5. **Write `lines.yaml`** as `{mission_id, model: eleven_v3, lines: [...]}`. This is a **flat
   list, one entry per variant**: `{id: <beat>_vN, speaker, text, subtitle, beat, delivery,
   radio_fx}`. Write **3–5 variants** per voiced beat. Read `references/radio-realism.md` before
   writing a word: callsign first, real brevity, within the speaker's `brevity`. Variants should
   differ in wording and information, not just swap synonyms. Keep `text` free of audio tags
   (the voice-director adds them) and leave `file` / `dur_sec` empty for `dms voice` to fill.
6. **Write `briefing.md` and `kneeboard.md`** (`references/briefing-format.md`): an intel
   narrative followed by the 5-paragraph order, with the kneeboard repeating paragraphs 3–5. Every
   known threat and objective must appear. Write `TBD (plan)` for frequencies until `dms plan`
   assigns them.
7. **Validate and repair (≤3 loops).**
   ```
   uv run dms validate campaigns/<slug>/missions/<id>/mission-spec.yaml
   ```
   If the CLI isn't available yet, run the same checks directly:
   ```
   uv run python -c "import yaml,sys; from dms_core.schemas import MissionSpec,BeatSheet,VoiceLineSet,StoryBible,validate_mission_bundle as v; d=sys.argv[1]; L=lambda f: yaml.safe_load(open(f, encoding='utf-8')); i=v(MissionSpec.model_validate(L(d+'/mission-spec.yaml')), BeatSheet.model_validate(L(d+'/beats.yaml')), VoiceLineSet.model_validate(L(d+'/lines.yaml')), StoryBible.model_validate(L(sys.argv[2]))); [print(x.severity, x.path, x.problem, x.suggestions) for x in i]; print(len(i), 'issues')" campaigns/<slug>/missions/<id> campaigns/<slug>/bible.yaml
   ```
   Fix every error and decide on each warning. After 3 failed loops, stop and report the remaining
   errors verbatim with a diagnosis. Never weaken the design just to pass (for example by deleting a
   beat); fix the field instead.
8. **Cross-check by reading:** every `requires.flags` entry is set by some beat or objective flag,
   every outcome key matches the arc, the spec's known threats match the briefing, and the beat
   speakers are all in `cast`.
9. **Record.** Set the arc mission's `status: designed` and append to continuity.md:
   `### <date> — mission-designer — <id> designed`, plus anything newly canon (named NPCs, places).
10. **Hand off.** Summarise in ≤10 lines and suggest the dms-build skill.

## Quality bar

- **Pilots don't talk nonsense.** No movie lines, no "Hell yeah", no exposition dumps on the radio.
  The story lives in the gaps around procedure.
- The mission is winnable every time: randomise *which* and *where*, never *whether*. No
  unavoidable kills. Nothing spawns in line of sight or inside about 5 km (ground) or 20 nm (air)
  of the player.
- Each playthrough differs in at least 3 ways: pool picks, positions, optional encounters, timing.
- The briefing alone is enough to fly the mission: threats, ROE, route intent, abort criteria and
  recovery.
- Consistent with the bible and continuity. Dead characters stay dead.

## Checklist

- [ ] All four inputs read; state digest written
- [ ] mission-spec.yaml: areas by reference, roles not types, `cast` complete, pools and encounters with telegraph beats, director set
- [ ] beats.yaml: ≥10 beats; `# GUARANTEED` start, payoff, RTB, landed and end beats cover the arc's key_beats; outcome keys match the arc
- [ ] lines.yaml: flat variants, 3–5 per voiced beat, radio-realism rules followed
- [ ] briefing.md (intel narrative + 5 paragraphs) and kneeboard.md (≤25 lines)
- [ ] Validation passes (≤3 repair loops); cross-check clean
- [ ] Arc status updated; continuity.md appended
