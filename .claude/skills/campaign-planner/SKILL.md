---
name: campaign-planner
description: Plan a DMS campaign arc from an existing story bible. Use when campaigns/<slug>/bible.yaml exists and the user wants the mission list, acts, branches or story qualities ("plan the campaign", "outline the missions", "add a branch", "rework act 2"), or when the debriefer needs the arc extended. Produces campaigns/<slug>/arc.yaml and initialises state/qualities.yaml.
---

# campaign-planner

Turn a story bible into a playable **campaign arc**: acts, missions, the dramatic question each one
answers, the qualities that carry state between missions, and the branches that let outcomes
matter. This skill only plans missions. The mission-designer fills each one in later, right before
it's flown.

## Inputs

- `campaigns/<slug>/bible.yaml` (required), `premise.md` (scope, session length), `continuity.md`.
- When re-planning: `state/qualities.yaml` and `state/outcomes/*.yaml`. Never re-plan flown missions.

## Outputs

- `campaigns/<slug>/arc.yaml` (`CampaignArc`). Skeleton: `campaigns/_template/arc.yaml`. Example:
  `campaigns/dustoff-valley/arc.yaml`.
- `campaigns/<slug>/state/qualities.yaml` (`Qualities`), only if it doesn't exist yet:
  `{values: {<quality id>: <initial>}, flags: {}, outcomes: {}, updated_after: null}`.
- Schemas: `schemas/campaign-arc.schema.json`, `schemas/qualities.schema.json`. The source of truth
  is `packages/dms-core/src/dms_core/schemas/campaign.py` (`CampaignArc`, `Act`, `ArcMission`,
  `Branch`, `QualityDef`, `Qualities`) and `_common.py` (`Requires`, `QualityCheck`, `MissionType`).

## arc.yaml shape

```yaml
schema_version: 1
title: "..."                       # matches the bible
logline: "One-sentence pitch."
qualities:                         # list of QualityDef
  - {id: intel, description: "...", initial: 0, min: 0, max: 5}
acts:
  - id: act1
    title: "..."
    summary: "..."
    missions:                      # ArcMission, in play order
      - id: m01-first-light        # 'mNN-slug' = the folder name under missions/
        title: "..."
        mission_type: RECON        # CAS|SEAD|DEAD|CAP|STRIKE|ESCORT|CSAR|RECON|TRANSPORT|CONVOY_ESCORT
        dramatic_question: "..."
        synopsis: "2-5 sentences, including what the runtime randomises (replayability)."
        player_aircraft: AH-64D_BLK_II
        characters: [ops_hatay, kestrel]          # bible character ids
        key_beats: ["Ops clears Dusty", "RTB call from tower"]   # guaranteed moments
        quality_effects: {intel: "+1 if aa_sites_found >= 1; +1 more if aa_sites_found >= 2 (max +2 via QualityDef)"}
        branches:                  # first match wins; [] = next mission in order
          - when: {flags: [m01_player_lost]}
            goto: m01b-second-look
            description: "Recovery mission if Dusty went down."
        optional: false            # true = only reachable through a branch
        status: planned            # planned|designed|built|flown
ending_notes: "How endings depend on qualities."
```

## Branch conditions are data, not expressions

`when` is a `Requires` block, and all of its parts must hold:
`flags`, `flags_not`, `qualities: [{quality, op, value}]` (op: `== != > >= < <=`), `chance`.
Campaign flags are written by the debriefer from mission outcomes using the convention
**`<mNN>_<outcome_key>`**, e.g. the outcome `player_lost: true` from m01 becomes flag
`m01_player_lost`. So:
- Decide each mission's outcome keys now and name them in `synopsis` or `quality_effects`. The
  mission-designer emits them as beat `effects.outcome`.
- A branch on an outcome uses the derived flag: `when: {flags: [m02_aaa_destroyed]}`.
- Every `goto` must be an existing mission id. Every quality in a condition must be declared.
- Put the specific branches first and leave the fallthrough implicit (empty branches or no match →
  next in order). Use `optional: true` for missions reached only by a branch.

## quality_effects are machine-applied

`dms debrief` applies `quality_effects` itself (`dms_core.outcomes.parse_quality_effect`; see
CONTRACTS "Debrief" → "Arc quality_effects"), so every clause must be machine-readable:
- A value is clauses split on `;`. Parentheticals `(...)` are dropped, so use them for human notes.
- A clause is `+N if <cond>`, `-N if <cond>`, `+N more if <cond>` or `set to N if <cond>`.
- `<cond>` is terms joined by `and` / `or` (`and` binds tighter; no parentheses). A term is
  `[not] <outcome_key>` (truthy) or `<outcome_key> <op> <number>` (op: `>= <= > < == !=`).
- Keys are **this mission's outcome keys** (beat `effects.outcome`), not the `mNN_` flags.
- Clamping comes from the QualityDef `min` / `max`; don't encode it in the clause.
- Spell out exclusive-or: `-1 if a and not b or b and not a`.

Example: `sam_threat: "-1 if sa6_radar_destroyed; -1 more if sa8_destroyed and sa6_launchers_destroyed >= 2 (min 0)"`.
Anything else ("+1 per site found", "-1 if only one of them", "+1 if any civilian is hit") is not
applied, only warned. Every key you use is an outcome key the mission-designer must set in beats:
a number for `>= N` terms, a boolean for truthy terms. List those keys in `synopsis` too.

- **Numbers are constants unless the runtime counts them.** A beat emits a fixed value (a
  boarding beat sets `refugees_carried: 24`), so `refugees_carried >= 20` is really a boolean.
  Prefer booleans, or counts the designer can tie to real kills (one beat per `group.dead`:
  `launchers_destroyed: 1`, then `2`, ...). Use counts for multi-target objectives so the arc can
  branch on degree, plus a partial-success key.
- **Cap the swing:** no mission's clauses may move one quality by more than ±2 (lint
  `quality_swing`).

## Single sortie: the one-act, one-mission arc

A one-off mission (dms-quickstart) still gets an arc, so `dms debrief` works and the arc can grow
later. One act, one mission, `branches: []`, one quality:

```yaml
schema_version: 1
title: "Hawg Morning"
logline: "Two A-10s break an armoured column before it reaches the valley town."
qualities:
  - {id: trust, description: "How much the ground force trusts Hawg flight.", initial: 0, min: -3, max: 3}
acts:
  - id: act1
    title: "The column"
    summary: "One sortie; extend the arc after the flight."
    missions:
      - id: m01-hawg-morning
        title: "Hawg Morning"
        mission_type: CAS
        dramatic_question: "Can Hawg stop the column without hitting the town?"
        synopsis: >-
          CAS north of the valley town against a column the JTAC talks on. The column's route,
          its AAA escort and a pop-up MANPADS team vary each play. Outcome keys:
          column_destroyed, civilians_hit. Director: moderate.
        player_aircraft: A-10C_2
        characters: [ops_main, jtac_bulldog]
        key_beats: ["Ops tasks Hawg to the JTAC", "JTAC checks Hawg out", "RTB call"]
        quality_effects:
          trust: "+1 if column_destroyed and not civilians_hit; -1 if civilians_hit"
        branches: []
        optional: false
        status: planned
ending_notes: "Single sortie. Extend the arc after the flight."
```

This validates; its one `quality_unread` warning for `trust` is expected until a later mission
reads it.

## Steps

1. **Read the bible end to end.** Note the themes, what the player aircraft can really do, the
   home base, faction units and the open threads in continuity.md.
2. **Write the spine:** `logline`, then 1–3 acts, each with a turn that changes the situation, and
   `ending_notes`.
3. **Define 3–6 qualities** (integers): intel picture, trust of ground forces, enemy AA strength,
   supply, civilian harm, losses. Cut any quality nobody reads.
   Frame them as **one progress quality plus 1–2 menace qualities** (`intel` vs `sam_threat`,
   `collateral`); the rest are optional. **Never gate on grind**: each step of a quality comes
   from distinct content.
4. **Lay out the missions.** The count is the premise's or user's number (default 4–5), and it
   counts **main-line missions only** (`optional: false`). Optional branch missions are recovery
   content on top of it. Longer campaigns: 5–8 per act. For each:
   - `dramatic_question`: a yes/no question where *both* answers lead somewhere interesting
     ("Can Dusty map the valley without getting shot at?", not "Will Dusty succeed?").
   - `mission_type` that the aircraft can actually fly (no CAP in an Apache).
   - `synopsis` with the area (real map names near the home base, at a realistic radius of
     action), what happens, and what Lua randomises each play.
   - `key_beats` (the guaranteed moments), `characters`, `quality_effects` in the machine grammar
     above, and `branches`.
   - Branch patterns (guide §5, `docs/reference/mission-design-guide.md`): **branch and
     bottleneck** is the default (a failure mission `mNNb` rejoins the main line within 2 hops),
     **menace threshold** (`collateral >= 3` forces an inquiry or ROE mission), **Midnight
     Staircase** (optional prep sorties versus a clock quality), at most one **sorting hat**, and
     never a time cave. **Diverge in state, converge in structure**: branch per act rather than
     per mission, and let qualities carry the difference.
   - **Waypoints:** a `key_beats` entry may be a story event that must happen by mission N via
     any branch; say so in the synopsis so the debriefer can check it was reached.
   - Persisted world damage (a destroyed SAM site) becomes a flag that later briefings mention.
5. **Vary the rhythm.** Alternate pressure and breathing room, mix mission types, start with a
   "routine" mission so the player learns the area, escalate, and pay off threads at the end. Each
   act needs at least one mission whose outcome changes another.
   - **Director cadence.** `ArcMission` has no intensity field, so end each synopsis with the
     intended director intensity (`Director: calm.`). The first mission is `calm`, no more than
     2 `intense` in a row, at least one `calm` per act, and the act climax `intense`. The designer
     sets it in the spec (lint `intensity_streak`).
   - Vary length like a golf course: 30 / 45 / 60-minute missions.
6. **Validate.** Run `uv run dms validate`; fix all errors and the lint warnings you can, max 3
   loops:
   ```
   uv run dms validate campaigns/<slug>/arc.yaml
   ```
   It runs the schema plus the arc lint (`failure_dead_end`, `branch_never_rejoins`,
   `intensity_streak`, `quality_unmoved` / `quality_unread`, `quality_swing`). Fix
   `failure_dead_end` with a branch on the failure flag, or by naming the flag in the next
   mission's synopsis (the lint reads it), e.g. "If m02_player_lost, the briefing opens with the
   crew's recovery." Then initialise `state/qualities.yaml` and
   validate it (`dms validate` doesn't take it):
   ```
   uv run python -c "import yaml; from dms_core.schemas import Qualities; Qualities.model_validate(yaml.safe_load(open('campaigns/<slug>/state/qualities.yaml', encoding='utf-8'))); print('OK')"
   ```
7. **Append to continuity.md:** `### <date> — campaign-planner — arc planned`, with the mission
   list, outcome keys per mission, and which open thread each mission is meant to pay off.
8. **Hand off.** Show a compact table (id, title, type, dramatic question, branches) and suggest
   running the mission-designer for the first mission.

## Quality bar

- Every mission can be flown with the player aircraft from the home base or a named FARP or divert.
- Every quality is moved by at least one mission (`quality_effects`) and **read** by at least
  one later mission. A read is a branch `when`, a beat `requires.qualities` / `requires.flags`, a
  briefing `<!-- if ... -->` condition, or a threat/pool scaling note in the synopsis that the
  designer turns into one of those. Prose alone doesn't count.
- Every mission's failure flag (`mNN_player_lost`, objective `failure_flag`s) is read by a branch
  or by the next mission (its synopsis says how its briefing or beats use it). Each failure branch
  is a different mission type or situation, not a replay at higher difficulty. No "game over"
  unless the user asked for permadeath.
- The player's coalition follows the bible's coalition rule in `canon_rules` (the catalog
  coalition of the player airframe), whatever the politics.
- The mission count matches the requested scope, counting `optional: false` missions only.
- Dramatic questions are concrete and different from each other.
- Missions run 30–60 minutes of flight unless the premise says otherwise.

## Checklist

- [ ] logline, acts, ending_notes
- [ ] Main-line (non-optional) mission count matches the scope; optional branches are extra
- [ ] 3–6 qualities (one progress, 1–2 menace), each moved and read (branch, beat `requires` or briefing `<!-- if -->`); no mission swings one by more than ±2
- [ ] Each mission has an `mNN-slug` id, a MissionType enum value, a dramatic question, a synopsis with replayability, key_beats, quality_effects, and branches using `Requires` with `<mNN>_<key>` flags
- [ ] Every quality_effects clause is in the machine grammar (no "per", "only one", "any"), and each key in it is an outcome key of that mission
- [ ] Every goto exists; optional missions are flagged and rejoin within 2 hops; every failure flag is read
- [ ] Each synopsis ends with `Director: calm|moderate|intense` (first calm, ≤2 intense in a row, a calm per act)
- [ ] `uv run dms validate .../arc.yaml`: all errors fixed, lint warnings fixed where possible (max 3 loops)
- [ ] state/qualities.yaml initialised (if new) and validates; continuity.md appended
