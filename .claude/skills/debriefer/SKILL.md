---
name: debriefer
description: Debrief a flown DMS mission and advance the campaign. Use after the player has flown a DMS mission in DCS ("I just flew m01", "debrief", "what happened last flight", "update the campaign", "pick the next mission"). Reads [DMS.OUTCOME] lines from dcs.log (or interviews the player), writes state/outcomes/mNN.yaml, updates state/qualities.yaml and continuity.md, and picks the next mission via arc branches.
---

# debriefer

Turn what actually happened in the cockpit into campaign state, so the next mission is written to fit.

## Inputs

- `dcs.log`, whichever was modified most recently:
  - Stable: `C:\Users\mook\Saved Games\DCS\Logs\dcs.log`
  - Open Beta: `C:\Users\mook\Saved Games\DCS.openbeta\Logs\dcs.log`

  DCS overwrites the log at every launch, so debrief before relaunching. Otherwise ask for
  `dcs.log.old`.
- `campaigns/<slug>/arc.yaml`: the mission entry (`quality_effects`, `branches`, `key_beats`) and
  the `qualities` list (min/max).
- `campaigns/<slug>/missions/<id>/beats.yaml`, for `effects.quality_deltas` and `effects.outcome`
  per beat.
- `campaigns/<slug>/state/qualities.yaml` and `continuity.md`.
- The player, for anything the log can't tell you.

## Outputs

- `state/outcomes/<mNN>.yaml`: one merged `MissionOutcome`
  `{mission_id, kind: summary, result, flags, outcomes, kills, losses, players, extra}`. Put
  `source` (dcs_log|questionnaire|mixed), `beats_fired`, `quality_changes` and `player_notes`
  under `extra`. Schema: `schemas/mission-outcome.schema.json`; model:
  `packages/dms-core/src/dms_core/schemas/outcome.py`.
- `state/qualities.yaml` (`Qualities`): `values`, `flags`, `outcomes[<mission id>]`, `updated_after`.
  There is no next-mission field; the next mission is recorded in continuity.md.
- An appended `continuity.md` entry. The arc mission's `status` becomes `flown`.

## Steps

1. **Find the run.** Locate the log and confirm it is this mission: the `[DMS]` banner shows the
   version and `missionId` (e.g. `m01-first-light`). If the id doesn't match, stop and ask.
2. **Extract outcomes** with the schema helpers:
   ```
   uv run python -c "import sys; from dms_core.schemas import parse_dcs_log, summarize_outcomes; recs=parse_dcs_log(open(sys.argv[1], encoding='utf-8', errors='replace').read()); print(len(recs), 'records'); [print(r.beat, r.kind, r.outcomes) for r in recs]; [print(k, v.model_dump_json(indent=1)) for k, v in summarize_outcomes(recs).items()]" "C:\Users\mook\Saved Games\DCS\Logs\dcs.log"
   ```
   Collect `beats_fired` from records that have a `beat`. Note any `[DMS][...]` ERROR or
   `safeCall` lines, since they can explain missing beats.
3. **Fill gaps with a short questionnaire.** Ask only about what's missing: at most 6 questions,
   multiple-choice where possible. Did you complete the objective? Were you hit or shot down? What
   did you find? Did anything hit civilians? Too easy, about right, or too hard? With no log at
   all, `extra.source: questionnaire`; with both, `mixed`.
4. **Judge the result**: `success`, `partial`, `failure` or `aborted`, measured against the
   dramatic question and the primary objectives. One sentence of reasoning.
5. **Compute quality changes.**
   - Sum `effects.quality_deltas` of every fired beat.
   - Apply the arc's `quality_effects` rules where outcomes satisfy them.
   - Clamp each value to its QualityDef `min`/`max`.
   - Record `{quality, from, to, reason}` in `extra.quality_changes`.
   - Never invent changes the arc and beats don't define. Propose them to the user instead.
6. **Derive campaign flags.** For each outcome key, write the flag `<mNN>_<key>`, where `mNN` is
   the mission id prefix (e.g. `m01`). Booleans copy as-is; a number sets the flag to `value > 0`;
   a string sets `true`. Also set `<mNN>_<result>` (e.g. `m01_success`). Carry over existing flags
   unchanged.
7. **Write the files.**
   - `state/outcomes/<mNN>.yaml`.
   - `state/qualities.yaml`: update `values` and `flags`, set `outcomes[<mission id>]` to the
     merged outcome dict, and set `updated_after: <mission id>`.
   - Validate both:
     ```
     uv run python -c "import yaml,sys; from dms_core.schemas import Qualities, MissionOutcome; L=lambda f: yaml.safe_load(open(f, encoding='utf-8')); Qualities.model_validate(L(sys.argv[1])); MissionOutcome.model_validate(L(sys.argv[2])); print('OK')" campaigns/<slug>/state/qualities.yaml campaigns/<slug>/state/outcomes/<mNN>.yaml
     ```
8. **Choose the next mission.** Evaluate the flown mission's `branches` in order. A branch matches
   when every part of its `when` (`Requires`) holds against the campaign `flags` and `values`:
   `flags`, `flags_not`, `qualities [{quality, op, value}]`, and `chance` (roll once and report the
   roll). The first match wins. If none match, or the list is empty, take the next mission in arc
   order, skipping missions marked `optional: true`. At the end of the arc, read `ending_notes`.
9. **Append to continuity.md.** Never edit earlier entries.
   ```
   ### <date> — debriefer — <mission id> flown (<result>)
   - 3–6 bullet facts: kills, losses, discoveries, civilian harm.
   - Canon changes: now destroyed / dead / known.
   - Flags set: m01_..., qualities: intel 0→2 (reason).
   - Threads: opened / advanced / closed.
   - Next: <mission id> (<which branch or "next in order">).
   ```
10. **Debrief the player** in character as the ops officer: 4–8 terse lines of BDA and
    consequences. Then, out of character, suggest the mission-designer skill for the next mission.

## Quality bar

- Facts come from the log first and the player second, with nothing invented. Ask when they
  contradict each other.
- Qualities stay within bounds, and every change has a stated reason.
- Flags follow `<mNN>_<key>` exactly, because arc branches depend on it.
- continuity.md stays append-only and readable by the next agent without other context.
- Failure still moves the story forward (the arc's recovery branch).

## Checklist

- [ ] Correct log and mission id confirmed
- [ ] Every `[DMS.OUTCOME]` record parsed and merged; script errors noted
- [ ] Questionnaire used only for gaps
- [ ] outcomes/<mNN>.yaml written; qualities clamped with reasons; `<mNN>_<key>` flags derived
- [ ] Both files validate
- [ ] Branches evaluated in order (fallthrough = next non-optional); next mission written in continuity.md
- [ ] continuity.md appended; arc status `flown`; in-character debrief delivered
