---
name: debriefer
description: Debrief a flown DMS mission and advance the campaign. Use after the player has flown a DMS mission in DCS ("I just flew m01", "debrief", "what happened last flight", "update the campaign", "pick the next mission"). Runs `uv run dms debrief` to turn dcs.log [DMS.OUTCOME] lines into state/outcomes/mNN.yaml, state/qualities.yaml and the next mission via arc branches, then interviews the player only for what the log can't tell and appends continuity.md.
---

# debriefer

Turn what actually happened in the cockpit into campaign state, so the next mission is written to fit.
Code reads the log; you handle what code can't: the player's account, judgement calls and story.

## Inputs

- `dcs.log`. `uv run dms debrief` finds it itself: the newest of
  `C:\Users\mook\Saved Games\DCS\Logs\dcs.log` and `C:\Users\mook\Saved Games\DCS.openbeta\Logs\dcs.log`,
  then each one's rotated `dcs.log.old` (DCS rotates the log at every launch). Pass `--log PATH` for
  any other file. One log can hold several runs of the same mission; the latest run is used.
- `campaigns/<slug>/arc.yaml`: the mission entry (`quality_effects`, `branches`, `key_beats`) and
  the `qualities` list (min/max).
- `campaigns/<slug>/missions/<id>/beats.yaml`, to explain which beats produced which facts.
- `campaigns/<slug>/state/qualities.yaml` and `continuity.md`.
- The player, only for what the log can't tell you.

## Outputs

- `state/outcomes/<mNN>.yaml` (written by `dms debrief`): one merged `MissionOutcome` with
  `kind: summary`. `extra` holds `source`, `log_file`, `session_start`, `ended`, `beats_fired`,
  `quality_changes`, `flags_set`, `next_mission`, `next_reason`, `log_errors`, `log_warnings`,
  `malformed_lines`. You add `player_notes` (and set `source: mixed` if you interviewed).
- `state/qualities.yaml` (written by `dms debrief`): `values`, `flags`, `outcomes[<mission id>]`,
  `updated_after`, `next_mission`.
- `continuity.md`: `dms debrief` appends a factual `### <date> — dms debrief — <id> flown (<result>)`
  entry (outcome facts, quality changes with reasons, flags, items to check, next mission). You
  append the narrative `debriefer` entry after it, and set the arc mission's `status` to `flown`.

## Steps

1. **Run the deterministic debrief first**, dry run then for real:
   ```
   uv run dms debrief campaigns/<slug> --mission mNN --dry-run
   uv run dms debrief campaigns/<slug> --mission mNN
   ```
   It picks the log, finds the latest session for the mission, merges every `[DMS.OUTCOME]` line,
   applies beat `qualityDeltas`, then the arc's machine-readable `quality_effects` clauses
   (`-1 if key`, `+1 more if a and b >= 2`, `set to 0 if a and not b`; clamped to the arc
   min/max), derives `<mNN>_<key>` and `<mNN>_<result>` flags, evaluates the arc branches, appends
   the factual continuity.md entry and prints the next mission. The rules are in
   docs/CONTRACTS.md "Debrief". Add `--json` for machine-readable output, and `--seed N` if a
   branch uses `chance`.
   - **Exit 1, "no [DMS.OUTCOME] lines"**: wrong log, or the mission never ran. Ask for the right
     `dcs.log` / `dcs.log.old` (`--log`), or fall back to the questionnaire (step 3) and write the
     files by hand (step 6).
   - **Exit 1, "already in state/outcomes"**: this flight was already debriefed (matched on its
     session start + a hash of its records, so a rotated `dcs.log.old` is caught too). Rerun with
     `--force` only if the user wants it re-applied: the previous run's `quality_changes` and flags
     are rolled back first and its continuity entry is replaced, so nothing doubles.
   - Read the printed `LOG ERROR` and `skipped malformed` lines: they explain missing beats.
2. **Check what the log could not say.** `ended: NO` / `result: unknown` means there was no `end`
   line (crash, quit, or no `endMission` beat). For such a flight `dms debrief` does **not** apply
   the arc `quality_effects` (warning `arc quality_effects not applied: the flight did not end`);
   beat `qualityDeltas` still apply. Ask how it ended, then either judge the effects by hand (step
   5) or rerun with `--force --force-arc-effects` once you know the outcome facts are complete. Kills and losses appear only if the runtime reported
   them. Civilian harm, what the player saw, and how hard it felt are usually not in the log.
3. **Fill gaps with a short questionnaire.** Ask only about what step 2 found missing: at most 6
   questions, multiple-choice where possible. If the result is unknown, ask how it ended.
4. **Judge the result** only if the log had none, or if the player's account contradicts it:
   `success`, `partial`, `failure` or `aborted`, measured against the dramatic question and the
   primary objectives. One sentence of reasoning. Ask when log and player disagree.
5. **Arc `quality_effects` that code could not apply.** `dms debrief` applies every clause of the
   form `<+N|-N> [more] if <cond>` / `set to N if <cond>` over this flight's outcome keys, and lists
   the rest as `warning: arc quality_effects '<q>' not machine-readable, judge by hand: ...` (also
   when the beats already moved that quality, so nothing is counted twice). Conditions can also
   read `result`, `success` and `failure`. Two more warnings need a look: `key(s) X not in this
   flight's outcome facts` (the runtime never reported X, so it counted as false/0: ask the player
   if it matters), and `dropped parenthetical (...)` (a `(min ...)`, `(max ...)`, `(only ...)` or
   `(... or ...)` note the code ignored: apply that limit or condition by hand). Judge only those
   against the outcomes and the player's account; where one clearly applies, propose the change
   with its reason. Never invent changes the arc and beats don't define. When writing a new arc,
   prefer the machine-readable form (campaign-planner).
   - **Cap the swing:** one flight should not move a quality by more than ±2 (lint
     `quality_swing`). If beats plus arc effects did, say so and propose the capped value.
   - **Waypoints:** check the mission's `key_beats` against `beats_fired`. A key beat the arc
     needs by this point that never fired (the flight stalled or ended early) goes into
     continuity.md as an open item, so the next mission's designer can stage it again.
6. **Edit the written files only for what you learned in steps 3-5**: player answers into
   `extra.player_notes` (and `source: mixed`); a judged `result` plus its `<mNN>_<result>` flag;
   accepted `quality_effects` (clamp to min/max, append `{quality, from, to, reason}` to
   `extra.quality_changes`). If the result or flags changed, re-check the branches in order by hand
   (first match wins, else next non-optional mission) and update `next_mission`. With no log at
   all, write both files by hand in the same shape with `extra.source: questionnaire`. Validate:
   ```
   uv run python -c "import yaml,sys; from dms_core.schemas import Qualities, MissionOutcome; L=lambda f: yaml.safe_load(open(f, encoding='utf-8')); Qualities.model_validate(L(sys.argv[1])); MissionOutcome.model_validate(L(sys.argv[2])); print('OK')" campaigns/<slug>/state/qualities.yaml campaigns/<slug>/state/outcomes/<mNN>.yaml
   ```
7. **Mark the arc mission `status: flown`** in arc.yaml (a one-line edit; keep the comments).
8. **Append to continuity.md** after the `dms debrief` entry (facts are already there; add what
   only you know). Never edit earlier entries.
   ```
   ### <date> — debriefer — <mission id> flown (<result>)
   - 3–6 bullet facts: kills, losses, discoveries, civilian harm.
   - Canon changes: now destroyed / dead / known.
   - Flags set: m01_..., qualities: intel 0→2 (reason).
   - Threads: opened / advanced / closed.
   - Next: <mission id> (<next_reason from dms debrief>).
   ```
   At the end of the arc (`next mission: (none)`), read `ending_notes`.
   The next mission reads this flight through campaign flags `<mNN>_<key>` (and `<mNN>_<result>`)
   and qualities: beat `requires`, and `<!-- if ... -->` blocks in its briefing/kneeboard, rendered
   at plan time (CONTRACTS "Debrief" → "Conditional briefing"). Persisted world damage (a destroyed
   site) stays a flag that later briefings must mention; list such flags under "Canon changes".
9. **Debrief the player** in character as the ops officer: 4–8 terse lines of BDA and
   consequences. Then, out of character, suggest the mission-designer skill for the next mission.

## Quality bar

- Facts come from the log first and the player second, with nothing invented. Ask when they
  contradict each other.
- Qualities stay within bounds, and every change has a stated reason.
- Flags follow `<mNN>_<key>` exactly, because arc branches depend on it.
- continuity.md stays append-only and readable by the next agent without other context.
- Failure still moves the story forward (the arc's recovery branch).

## Checklist

- [ ] `uv run dms debrief` run (dry run first); log file and session confirmed
- [ ] LOG ERROR / malformed lines read and noted
- [ ] Questionnaire used only for gaps the log left
- [ ] Manual edits (player notes, judged result, accepted quality_effects) made and validated
- [ ] Next mission (from `dms debrief`, or re-checked by hand after edits) written in continuity.md
- [ ] Unapplied arc `quality_effects` warnings judged; no quality moved more than ±2; unfired `key_beats` noted
- [ ] continuity.md appended (after the `dms debrief` entry); arc status `flown`; in-character debrief delivered
