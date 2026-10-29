# Blind run findings — p09 Air Bridge to Sukhumi (2026-10-29)

**Campaign:** `campaigns/eval-p09-sukhumi-air-bridge/` (not committed) · **Premise:**
`p09-sukhumi-air-bridge` (adapted, Mi-8, Caucasus 1993) · **Score:** 62/63 = 98% · **Status:**
implemented, not flown.

Claude Code followed story-writer → campaign-planner → mission-designer (m01 and m02), taking only
the premise `prompt` as input. It read the `expect` block only after scoring. One research subagent
covered the adapted-mode sourcing. Voice was skipped (no ElevenLabs credits). DCS was not launched.

## What happened

| Step | File | Validation result | Repair loops |
|---|---|---|---|
| story-writer | bible.yaml | `StoryBible` OK first time | 0 |
| campaign-planner | arc.yaml, state/qualities.yaml | `CampaignArc` / `Qualities` OK first time; all 14 `quality_effects` clauses parse with no warnings | 0 |
| mission-designer | m01-first-run | 0 errors from the start. Loop 1: 5 warnings. Fixed the `composition` free text and the ignored helicopter `air_start`, leaving 3 warnings. Loop 2: pinned ZU-23 templates after `plan.json` showed a Shilka (not a validate issue) | 2 (warnings only) |
| mission-designer | m02-sister-ship | 0 errors, 3 warnings (the same accepted ones) first time | 0 |
| plan / build / check | m01, m02 | Both plan, build `-ramp`/`-air`/default `.miz` and pass `dms check` | n/a |

Score: files 6/6, schema 4/4, premise 19/20, arc 4/4, coverage 20/20, build 6/6, story 3/3.
**Only failure:** `mission count (6 in [3, 5])`. The arc has 5 main-path missions plus the
optional branch mission `m02b-walking-out`, and the scorer counts all of them.

Accepted warnings (per mission): `no presets for Mi-8MT; DCS default payload used` ×2 (ramp and
air) and `faction 'abkhaz' is not red`. The second is a false positive (see V2).

## Passes that are weaker than they look

- **`player coalition: red`** passed because the designer happened to look at
  `dms catalog units --era 1993`, which lists the Mi-8MT as red-only. The skill never tells
  you to do that. The politically natural reading, a Georgian government crew, is DCS-blue by
  default. Nothing in story-writer or faction-mapping would have caught a blue choice, and it would
  have failed the premise check.
- **Story element `fuel`** matched only the word "bingo" in the briefing's abort criteria. The
  campaign's actual fuel theme ("fuel is the ration", "fuel as arithmetic", Granite's drums) uses
  none of the keywords (`fuel shortage`, `short of fuel`, `low fuel`, ...). The heuristic passed
  for the wrong reason.

## Skill ambiguities

### story-writer

- **S1. Coalition for non-NATO player sides.** There is no rule for picking the player's DCS
  coalition. *Suggestion:* in step 4 (or `references/faction-mapping.md`), add: "The player's
  coalition is the catalog coalition of the player airframe (`uv run dms catalog units --era
  <year>`), whatever the politics. Record it in `canon_rules`. Enemies take the other side, even
  if that puts, e.g., Abkhazia on blue."
- **S2. Scope default.** The interview offers "defaults" but never says what the default mission
  count is, so later skills have no number to hold to. *Suggestion:* state a default ("4-5 missions,
  45-60 min") and tell the user that optional branch missions are extra.
- **S3. Sourcing the central invention.** Research found no source for helicopter flights into
  Babushara in Sept 1993, or for Senaki/Kutaisi supporting them. The adapted-mode rules handled
  this well: it went into `canon_rules` as an explicit invention. *Suggestion:* add that pattern
  to `modes-and-sourcing.md` as an example ("If research can't source the premise's core activity,
  say so in canon_rules and keep it out of `sources`").

### campaign-planner

- **P1. Do optional missions count toward the scope?** The skill says "5–8 per act, or fewer for
  short campaigns" and "use `optional: true` for missions reached only by a branch", but never
  says whether optional missions count toward the user's or premise's mission count. The scorer
  counts all of them. *Suggestion:* decide on one rule and write it in both places. Either the
  scorer counts `optional: false` missions only (preferred: branch missions are recovery content,
  not scope), or the skill says "the requested count includes optional branch missions".
- **P2. "Read by a later mission" is not machine-checkable.** Qualities such as `garrison_supply`
  and `airframes` are "read" only in m05's synopsis prose. *Suggestion:* say what counts as a read:
  a branch `when`, a beat `requires.qualities`, a briefing `<!-- if -->` condition, or a pool/threat
  scaling note, listed in the designer's state digest.
- **P3. Outcome numbers are constants.** `refugees_carried >= 20` reads like a measured count, but
  beats can only emit fixed values (the boarding beat sets 24). *Suggestion:* note in the
  quality_effects section that numeric outcomes are designer-set per beat unless the mission
  counts kills. Prefer booleans, or counts the runtime really produces (kills, groups dead).

### mission-designer

- **D1. Contradiction about `guaranteed`.** The SKILL.md step 4 says "There is no schema field for
  this: put a `# GUARANTEED` comment", and `references/beats-and-encounters.md` repeats it. But
  `Beat.guaranteed: bool` exists (it rejects `chance < 100`), and the worked example uses
  `guaranteed: true`. I used both. *Suggestion:* say "set `guaranteed: true` (the runtime ignores
  chance for it); the `# GUARANTEED` comment is optional".
- **D2. `dms catalog templates --role <ThreatRole>` returns nothing for `aaa`, `manpads`,
  `technicals` and `civilian`.** Catalog templates use `air_defense` / `technical` as their role,
  while the spec uses ThreatRole values. The skill points to this exact command
  (`--role sam_short`) for choosing `templates`. *Suggestion:* make the CLI accept ThreatRole
  names (map through `forces.ROLE_TEMPLATES`), or show the role→template table in the skill.
- **D3. Unpinned roles drift from the briefing.** `aaa` for a faction listing both ZU-23 and
  ZSU-23-4 planned a Shilka, a radar gun, while the briefing said ZU-23. *Suggestion:* add a rule:
  "If the briefing names a type, pin `templates`, then read `out/plan.json` groups after
  `dms plan` to confirm."
- **D4. Helicopter air starts.** `references/player-flights.md` documents `air_start`
  (altitude, speed, distance), but validate says "air_start is ignored for helicopters (low air
  start)". *Suggestion:* state that in the reference, together with what a helicopter air start
  actually does.
- **D5. Landing at a specific place.** `unit.landed` has no `zone` filter, so every "land at X" beat
  needs a silent `zone.entered` beat that sets a flag, then a `unit.landed` beat that requires it
  (used three times here). *Suggestion:* add `zone` to the `unit.landed` trigger (preferred), or
  document the pattern in `beats-and-encounters.md`. As written, the pattern can be fooled by
  flying through the zone and landing elsewhere.
- **D6. Transport has no cargo model.** No spec field covers internal cargo, troops or passengers,
  and the Mi-8MT has no loadout presets, so "2,000 kg ammunition" and "24 refugees" are fiction
  only. *Suggestion (schema gap):* add a `cargo` intent to TRANSPORT/CSAR (`internal_kg`,
  `passengers`) that the builder maps to aircraft weight or the DCS cargo/troop system. At minimum,
  add Mi-8MT, UH-1H and CH-47 transport/rocket presets so `loadout` resolves.
- **D7. Frequencies for agencies that are not units.** The briefing format says to write `TBD
  (plan)`, but `plan.json` only assigns the player flight's frequency. Ops and tower characters
  never get one. I used `dms catalog airbases` UHF/VHF values. *Suggestion:* either have the
  planner assign a frequency to each cast speaker (the radio net), or tell the skill to use the
  airbase catalog frequencies for towers and the flight frequency for ops.
- **D8. `composition` format.** Free text in `support[].composition` warns ("unknown unit ...");
  only `"4x Soldier AK, 1x Ural-375"` parses. The worked example also uses free prose.
  *Suggestion:* document the `Nx <type id>` list form in the skill.

## Validation and CLI gaps

- **V1.** `dms check <mission folder>` fails with `not found`, but `dms plan`/`dms build` accept a
  folder. Check needs the `.miz` path. Make the three consistent.
- **V2.** `faction '<x>' is not red` is a false positive when the player flies red: the check
  assumes enemies are red. Compare against the side opposite `player_flights[0].coalition`.
- **V3.** `dms check` warns "beat ... can never fire: flag 'm01_player_lost' is never set" for
  continuity beats before the earlier mission is flown. That is expected for a campaign flag.
  Downgrade it to info, or reword it as "campaign flag not set at plan time".
- **V4.** The score counts no validate warnings, so a mission with a false "not red" faction
  warning and unresolved loadouts still scores 100% on schema. That's fine for scoring, but it
  hides the loadout gap (D6).

## Suggestions for the eval itself

- Count `optional: false` missions in the `mission count` check (see P1), or record in
  `--lint-premises`/the README that optional missions count.
- Widen p09's `fuel` keywords ("fuel ration", "rationed", "fuel is short", "kilos of fuel"), or
  score story elements against the bible's `tone.themes` too, so passing means the theme is
  there and not a stray "bingo".
- Add a check that the player coalition was chosen by a rule. Today a correct red is
  indistinguishable from a lucky one.
