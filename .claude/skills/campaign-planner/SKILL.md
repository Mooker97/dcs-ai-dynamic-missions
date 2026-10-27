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
        quality_effects: {intel: "+1 per hidden AA site found (max +2)"}
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

## Steps

1. **Read the bible end to end.** Note the themes, what the player aircraft can really do, the
   home base, faction units and the open threads in continuity.md.
2. **Write the spine:** `logline`, then 1–3 acts, each with a turn that changes the situation, and
   `ending_notes`.
3. **Define 3–6 qualities** (integers): intel picture, trust of ground forces, enemy AA strength,
   supply, civilian harm, losses. Cut any quality nobody reads.
4. **Lay out the missions** (5–8 per act, or fewer for short campaigns, as the premise allows). For each:
   - `dramatic_question`: a yes/no question where *both* answers lead somewhere interesting
     ("Can Dusty map the valley without getting shot at?", not "Will Dusty succeed?").
   - `mission_type` that the aircraft can actually fly (no CAP in an Apache).
   - `synopsis` with the area (real map names near the home base, at a realistic radius of
     action), what happens, and what Lua randomises each play.
   - `key_beats` (the guaranteed moments), `characters`, `quality_effects` with concrete rules,
     and `branches`.
5. **Vary the rhythm.** Alternate pressure and breathing room, mix mission types, start with a
   "routine" mission so the player learns the area, escalate, and pay off threads at the end. Each
   act needs at least one mission whose outcome changes another.
6. **Validate** (≤3 repair loops):
   ```
   uv run python -c "import yaml; from dms_core.schemas import CampaignArc; CampaignArc.model_validate(yaml.safe_load(open('campaigns/<slug>/arc.yaml', encoding='utf-8'))); print('OK')"
   ```
   Then initialise and validate `state/qualities.yaml` the same way with `Qualities`.
7. **Append to continuity.md:** `### <date> — campaign-planner — arc planned`, with the mission
   list, outcome keys per mission, and which open thread each mission is meant to pay off.
8. **Hand off.** Show a compact table (id, title, type, dramatic question, branches) and suggest
   running the mission-designer for the first mission.

## Quality bar

- Every mission can be flown with the player aircraft from the home base or a named FARP or divert.
- Every quality is moved by at least one mission (`quality_effects`) and read by at least one later
  branch or mission.
- Failure is never a dead end: a failed mission branches to a recovery or a harder variant, never
  "game over", unless the user asked for permadeath.
- Dramatic questions are concrete and different from each other.
- Missions run 30–60 minutes of flight unless the premise says otherwise.

## Checklist

- [ ] logline, acts, ending_notes
- [ ] 3–6 qualities (QualityDef list), each moved and read
- [ ] Each mission has an `mNN-slug` id, a MissionType enum value, a dramatic question, a synopsis with replayability, key_beats, quality_effects, and branches using `Requires` with `<mNN>_<key>` flags
- [ ] Every goto exists; optional missions are flagged
- [ ] arc.yaml validates; state/qualities.yaml initialised (if new) and validates; continuity.md appended
