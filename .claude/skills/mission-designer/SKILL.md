---
name: mission-designer
description: Design the next playable DMS mission from a campaign arc entry and the current campaign state. Use when the user wants to write, detail or redesign a specific mission ("design m03", "write the next mission", "make the briefing and radio lines for this mission"), after campaign-planner has produced arc.yaml or after the debriefer has chosen the next mission. Produces missions/mNN-<slug>/{mission-spec.yaml, beats.yaml, lines.yaml, briefing.md, kneeboard.md} and runs `uv run dms validate`.
---

# mission-designer

Turn one arc entry into a complete, validated mission package: a declarative spec the generator
compiles, beats the Lua narrative engine fires, voice-line variants, a 5-paragraph briefing and a
kneeboard. Design the mission **just before it's flown**, so it reflects what actually happened
in earlier missions.

**Read [`docs/reference/mission-design-guide.md`](../../../docs/reference/mission-design-guide.md)
first** (the "guide"; §0 is the seven rules). It holds the per-role spines (§1), radio cheat-sheet
(§2), briefing/kneeboard checklists (§3), pacing and director table (§4) and the lint list (§6).
Where it is stricter than this skill, it wins.

## Inputs (read all of them, every time)

1. `campaigns/<slug>/bible.yaml`: mode, factions (country, units), characters and voices, canon rules
   (including which DCS coalition the player is on).
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

Skeletons: `campaigns/_template/missions/`. Worked examples:
`campaigns/dustoff-valley/missions/m01-first-light/` and
`campaigns/viper-detachment/missions/m03-troops-in-contact/` (CAS spine; `jtac_retask` is the 8-min timeout fallback). The field
descriptions in the models are authoritative (`uv run dms schema`). Unknown keys are rejected.

## Steps

1. **State digest.** Write yourself 5–10 lines: the dramatic question, which qualities and flags
   change this mission and how, continuity facts to honour, threads to touch or pay off, and the
   outcome keys the arc expects.
2. **Shape the flight.** Pick the per-role spine from guide §1 and write the timeline in the spec
   `notes` as `T+min: event` lines, **measured from the first guaranteed beat** (the same in ramp
   and air variants), not from mission start:
   - hook within 3 min; first engagement by T+5–10; 2–3 rising peaks with the scripted climax last;
   - on-station time stated; expected total flight time stated for each variant.

   Set `dynamic.director {enabled, intensity: calm|moderate|intense, adaptive}` from guide §4
   (calm for first/recon/transport, moderate default, intense for TIC/climax and at most 1 in 3).
3. **Write `mission-spec.yaml`.** Areas and roles only; never coordinates, unit ids or CLSIDs.
   - Header: `id` (= folder), `title`, `campaign`, `content_mode` (= bible mode), `theater`,
     `era`, `date` (YYYY-MM-DD), `start_time` (HH:MM), `weather_preset`
     (clear|scattered|broken|overcast|rain|storm|dust|fog|night_clear), `mission_type`,
     `duration_min`, `blue_countries`, `red_countries`, `cast` (every speaker id).
   - **Countries are full DCS names** (`Combined Joint Task Forces Blue`, not `CJTF Blue`;
     `Combined Joint Task Forces Red`, `Insurgents`, `Russia`, `Georgia`, ...), matching the bible.
   - **Coalition:** the player flight's `coalition` is the side the catalog gives the player
     aircraft (`uv run dms catalog units --era <year>`, e.g. Mi-8MT and Ka-50 are red), as recorded
     in the bible's `canon_rules`, whatever the politics. Enemy factions go on the other side.
   - `areas[]`: `{id, description, where, terrain}`. `where.kind` is one of `near_airbase`
     `{airbase, radius_nm, bearing_deg, distance_nm}`, `near_named_place`
     `{place, radius_nm, bearing_deg, ...}`, `latlon`, or `zone` (polygon points). Make gating
     zones wide (guide §0.2); name an `ip_*` and an `egress*` area if you want those steerpoints.
   - `player_flights[]`: `{callsign, aircraft, count, coalition, country, start_area, start_type,
     loadout, frequency_mhz, tasking, variant, slot, air_start}`. Offer a ramp **and** an air
     start (same flight twice, `variant: ramp` / `variant: air`), use a DCS callsign for the type,
     and check the loadout preset table. All in `references/player-flights.md`.
   - `objectives[]`: kind destroy|protect|escort|reach|recon|rescue|survive|land, with `area`,
     `target`, and `success_flag` / `failure_flag` that beats set.
   - `threats[]`: `{role, area, strength light|medium|heavy, faction, skill, hidden_on_map,
     templates}`. Before pinning `templates`, list what fits with
     `uv run dms catalog templates --role <ThreatRole> --era <year>` (ThreatRole names such as
     `sam_short`, `aaa`, `manpads`, `technicals` work); a template that doesn't fit the role or
     era is only warned and then ignored. **If the briefing names a type** (ZU-23, SA-8), pin it,
     and after `dms plan` read the groups in `out/plan.json` to confirm. Threats named in the
     briefing as known get `hidden_on_map: false`. Scale threats by qualities. Civilians: role
     `civilian` with a neutral bible faction.
   - `support[]`: `{role, callsign, area, route, composition, faction, speaker, frequency_mhz,
     modulation, tacan}`. `composition` must be a list in the form `"4x Soldier AK, 1x Ural-375"`
     (`Nx <DCS type id>`); free prose warns "unknown unit". `faction` sets the units' DCS country.
     AWACS/tankers fly on `frequency_mhz` with the spec `callsign` when it is a DCS name (AWACS:
     Overlord, Magic, Wizard, Focus, Darkstar; tankers: Texaco, Arco, Shell; `"Texaco 6"` =
     flight 6). Tankers take `tacan` (e.g. `51Y`). `modulation` is automatic (FM below 88 MHz).
   - **Frequencies:** give every flight and support agency a `frequency_mhz` in the spec. Towers
     use `uv run dms catalog airbases` values; agencies with no unit (Ops) share the flight
     frequency or a spec value you choose. These numbers go straight into the briefing.
   - `dynamic`: `pools[]` and `encounters[]` (shapes in `references/beats-and-encounters.md`),
     plus `fog_of_war`. **Set pieces bypass the director**: the pinned objective and the arc's
     guaranteed threat are `threats` or `chance: 100` encounters; only filler (`waves`, `hunt`,
     `cap`) is director-gated. At most 6 encounters with `chance > 0` (`vul_overload`). Every
     `ambush_sam` / `cap` / `waves` has a `telegraph_beat` (`popup_no_telegraph`).
4. **Write `beats.yaml`** as `{mission_id, beats: [...]}`: ≥10 beats; for a quickstart single
   mission aim at ~15–20 beats with 3 variants each. Read `references/beats-and-encounters.md`.
   - **Guaranteed** beats (start/check-in, objective payoff, check-out, RTB, landed/debrief, end on
     death) get `guaranteed: true` (the runtime ignores chance for them and never drops their
     line); a `# GUARANTEED` comment is optional. They cover the arc's `key_beats` and are
     reachable from every variant: never on `unit.takeoff` or a ramp-only zone when an air variant
     exists (`guaranteed_on_takeoff`).
   - **No single point of failure** (guide §0.1). Every guaranteed beat that waits on a kill, a
     landing or a flag needs a timeout path: a `timer` beat with
     `requires: {beats_not_fired: [<it>]}` that sets the same flag or retasks, so check-out and RTB
     always fire (`spine_no_fallback`). Never make a landing beat guaranteed without one. Add an
     "Ops: say status" nudge after ~4 min of no progress. Pattern: viper m03's 8-min retask.
   - **Generic fallback plus specific variants** (guide §5): for each reactive event (player hit,
     SAM launch, first kill) write one ungated low-priority beat, then state-gated beats at higher
     priority (`no_generic_fallback`). Reactions with `once: false` need `cooldown_sec ≥ 30` and
     ≥3 variants.
   - **Story in RELAX, brevity in PEAK** (guide §4.2): character and continuity lines get
     `when: {event: director.state, state: RELAX}` or chain off a kill/BDA beat. Anything that can
     fire mid-fight is ≤12 words (`peak_chatter`). Max 3 radio beats on one trigger
     (`radio_density`).
   - `lines` lists the **variant ids** (`[ops_cleared_v1, ops_cleared_v2, ops_cleared_v3]`), and a
     beat with lines needs a `speaker` in `cast`.
   - **Outcome keys** go in `effects.outcome`, using the arc's keys exactly; every key in the arc
     entry's `quality_effects` must be set by some beat (a number for `>= N` terms, a boolean for
     truthy terms), or `dms debrief` silently moves nothing. Multi-target objectives emit a count
     (`targets_destroyed: 2`) plus a partial-success key, not just a boolean (guide §0.7).
     Quality changes go in `effects.quality_deltas` (≤ ±2 per quality, `quality_swing`), the
     result in `effects.end_mission`, objective flags in `effects.set_flag`.
   - **Continuity beats.** `dms plan` copies `state/qualities.yaml` `values` and `flags` (e.g.
     `m01_sa6_radar_destroyed`, `m01_success`, `m01_player_lost`) into `DMS_CONFIG.qualities` /
     `DMS_CONFIG.flags`. Gate on them with `requires.flags` / `requires.flags_not` /
     `requires.qualities`, or the map form `requires: {flags: {m01_sa6_radar_destroyed: true}}`.
     A flag set during the mission wins; unknown means not set. Read the previous mission's
     failure flag somewhere (beat, briefing block) so it isn't a dead end (`failure_dead_end`).
   - **Land at a place:** one beat. `when: {event: unit.landed, zone: <lz>, players_only: true}`
     fires only when the unit is inside the zone as it lands (position checked at the event);
     `place: <airbase/FARP/ship name>` (alias `airbase`) matches the DCS landing place instead.
     Both work for `unit.takeoff` too. No silent `zone.entered` + flag pair is needed.
   - Telegraph every punishment 30–60 s ahead with an ungated, undelayed telegraph beat
     (`telegraph_too_short`).
   - Exchanges are **chained beats**: beat B has `when: {event: beat.fired, beat: A}` with
     `delay_sec: 2-4`.
5. **Write `lines.yaml`** as `{mission_id, model: eleven_v3, lines: [...]}`: a **flat list, one
   entry per variant** `{id: <beat>_vN, speaker, text, subtitle, beat, delivery, radio_fx}`.
   3–5 variants per voiced beat that differ in information or rhythm (`variants_too_similar`).
   Read `references/radio-realism.md` and guide §2 first: callsign first (`callsign_first`),
   real brevity, within the speaker's `brevity` limit (terse 12 / normal 20 words, ≤8 s;
   `line_too_long`). No audio tags in `text`; leave `file` / `dur_sec` empty.
6. **Write `briefing.md` and `kneeboard.md`** (`references/briefing-format.md`, guide §3): intel
   narrative, then the 5-paragraph order with `## 1.`–`## 5.` headings, a **Duration** line per
   variant, a **Stakes** line (what happens if we fail), abort and bingo, and for each known threat
   its location and **the cue the player gets** (RWR symbol / none / JTAC report). Every visible or
   telegraphed threat must be named (`briefing_threat_mismatch`). Write the spec frequencies
   directly; for agencies without one use the `dms plan` comms or `TBD (plan)` (the build fills
   it, see `references/briefing-format.md`). The kneeboard is ≤25 lines with a comms table and the same
   frequencies and laser code (`kneeboard_contradiction`, `kneeboard_too_long`). For
   state-dependent text use `<!-- if ... -->` / `<!-- elif -->` / `<!-- else -->` /
   `<!-- endif -->` blocks keyed on qualities and `mNN_` campaign flags.
7. **Validate and repair (≤3 loops).**
   ```
   uv run dms validate campaigns/<slug>/missions/<id>
   ```
   This runs the schema, cross-file and planner checks and the mission-quality lint (lint codes
   appear as `[<code>] ... Fix: <hint>`; meanings in CONTRACTS "Mission-quality lint").
   **Fix all errors and every lint warning you can, max 3 loops**; `--strict` fails on warnings
   if you want to prove it clean. Accepted warnings get a one-line reason in the hand-off.
   After 3 failed loops, stop and report the remaining errors verbatim with a diagnosis. Never
   weaken the design to pass (e.g. deleting a beat); fix the field instead. Then run
   `uv run dms plan <mission dir>` and confirm pinned/briefed threat types in `out/plan.json`.
8. **Cross-check by reading:** every `requires.flags` entry is set by a beat or objective flag or
   is a campaign flag in `state/qualities.yaml`; every `quality_effects` key is set by a beat;
   briefing threats match the spec; beat speakers are all in `cast`; briefing and kneeboard
   frequencies match the spec.
9. **Record.** Set the arc mission's `status: designed` and append to continuity.md:
   `### <date> — mission-designer — <id> designed`, plus anything newly canon (named NPCs, places).
10. **Hand off.** Summarise in ≤10 lines (including accepted warnings) and suggest the dms-build skill.

## Quality bar

- **Pilots don't talk nonsense.** No movie lines, no "Hell yeah", no exposition dumps on the radio.
  The story lives in the gaps around procedure. Every transmission has a function.
- The mission is winnable every time: randomise *which* and *where*, never *whether*. No
  unavoidable kills. Nothing spawns in line of sight or inside about 5 km (ground) or 20 nm (air)
  of the player.
- No beat that progresses the mission depends on exactly one event.
- Each playthrough differs in at least 3 ways: pool picks, positions, optional encounters, timing.
- The briefing alone is enough to fly the mission: threats with their cues, ROE, route intent,
  stakes, expected flight time, abort criteria and recovery.
- Consistent with the bible and continuity. Dead characters stay dead.

## Checklist

- [ ] All four inputs and the guide read; state digest written
- [ ] Timeline in `notes` (T+ from first guaranteed beat; hook ≤3 min, peaks, climax last, flight time per variant); director intensity set
- [ ] mission-spec.yaml: areas by reference, roles not types, full DCS country names, player coalition = catalog side, `cast` complete, spec frequencies for every agency, `composition` as `Nx <type>`
- [ ] Briefed types pinned (`dms catalog templates --role ... --era ...`) and confirmed in `out/plan.json`
- [ ] Set pieces not director-gated; ≤6 encounters; every pop-up has a telegraph beat
- [ ] beats.yaml: ≥10 beats (quickstart ~15–20); `guaranteed: true` spine covers key_beats from every variant
- [ ] Every gating beat (kill, landing, flag) has a timeout path; "say status" nudge
- [ ] Generic fallback + specific variants for reactions; RELAX for story lines, ≤12 words in PEAK
- [ ] Every `quality_effects` key set by a beat; counts for multi-target objectives; previous failure flag read
- [ ] lines.yaml: flat variants, 3–5 per voiced beat, radio-realism rules followed
- [ ] briefing.md (intel + `## 1.`–`## 5.`, Duration, Stakes, threat cues, abort/bingo) and kneeboard.md (≤25 lines, comms table, same numbers)
- [ ] State-dependent text uses `<!-- if -->` blocks (balanced, parseable conditions)
- [ ] `uv run dms validate` clean: fix all errors and lint warnings you can, max 3 loops; cross-check clean
- [ ] Arc status updated; continuity.md appended
