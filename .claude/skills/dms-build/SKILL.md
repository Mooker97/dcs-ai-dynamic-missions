---
name: dms-build
description: Build a designed DMS mission into a flyable DCS .miz end to end. Use when a mission folder has mission-spec.yaml/beats.yaml/lines.yaml and the user wants the .miz ("build m01", "make the miz", "compile the mission", "why won't it build", "how do I fly this"). Runs uv run dms validate → plan → voice → build → check, explains each output, says where the .miz lands, how to load it in DCS and what to look for in dcs.log.
---

# dms-build

Compile a designed mission into `out/mNN.miz` with the `dms` CLI, stopping at the first failing
stage, repairing, and explaining what each stage produced.

## Inputs

- `campaigns/<slug>/missions/mNN-<slug>/` containing `mission-spec.yaml`, `beats.yaml`,
  `lines.yaml`, `briefing.md`, `kneeboard.md` (written by the mission-designer skill).
- Optional: `ELEVENLABS_API_KEY` for voice. Without it, build with subtitles only.

## Outputs (inside the mission folder)

| Stage | Command | Produces |
|---|---|---|
| validate | `uv run dms validate <mission folder>` | schema + cross-file + planner errors and mission-quality lint (`[code] ... Fix: ...`), or OK |
| plan | `uv run dms plan <mission folder>` | `out/plan.json`: exact positions, unit types, payload CLSIDs, frequencies, group names, triggers, seed, `DMS_CONFIG` |
| voice | `uv run dms voice lines.yaml --dry-run`, then `uv run dms voice lines.yaml` | cost estimate, then `voice/*.ogg` (radio FX applied, cached) |
| build | `uv run dms build <mission folder>` (`--variant air` for one variant) | the `.miz`: pydcs mission + `dms.lua` bundle + `dms_config.lua` + audio + briefing text from `briefing.md` + kneeboard pages rendered from `kneeboard.md`. With start variants: one `out/<id>-<variant>.miz` per variant (each checked) plus `out/<id>.miz` = copy of the first |
| check | `uv run dms check <mission folder>` (every built variant) or one `.miz` | structural report: IDs, slots, resources, config schema, `luac -p` |

Run all commands from the repo root with full paths, e.g.
`uv run dms validate campaigns/dustoff-valley/missions/m01-first-light`. `uv run dms run <mission
folder>` chains validate -> voice -> plan -> build -> check (`--skip-voice`, `--install`).
`uv run dms schema` regenerates `schemas/<stem>.schema.json` (mission-spec, beats, voice-lines,
build-plan, runtime-config, ...) from the pydantic models in `packages/dms-core/src/dms_core/schemas/`.
`plan.json` is a `BuildPlan` and the embedded `DMS_CONFIG` is a `RuntimeConfig`.

## Steps

1. **Pre-flight.** Confirm the files exist and run `uv run dms doctor` (deps, Lua 5.1, ffmpeg,
   ElevenLabs key present, DCS folders, `dist/dms.lua` freshness, git-lfs; fix any FAIL). Don't
   fake outputs: if a stage fails, stop there.
2. **Validate.** `uv run dms validate <mission folder>` runs the schema, cross-file and planner
   checks plus the mission-quality lint (`dms_core.lint`; rules in the mission design guide §6 and
   CONTRACTS "Mission-quality lint"). Fix all errors and every lint warning you can, at most 3
   loops, keeping the designer's intent (fix the field, never delete the beat). Then report the
   rest verbatim. `--strict` fails on warnings too; use it when the user asks for a clean bill.
3. **Plan.** Summarise `out/plan.json` for the user: seed, player slot, spawn zones resolved,
   threat types chosen, frequencies. Frequencies are authored in the spec and already written in
   `briefing.md`/`kneeboard.md` by the designer: confirm the plan's values match them (fix the
   Markdown or the spec, not `plan.json`). If the briefing names a threat type, confirm the plan
   picked it (else pin `templates` in the spec). Re-run `dms validate` now: `transit_too_long`
   only runs once `out/plan.json` exists. The plan is seeded, so the same seed reproduces it.
4. **Voice.** Run the dry-run and report the cost. Render only after the user approves new cost.
   For voice/tag work, use the voice-director skill. No API key: skip and note that beats will
   show subtitles only.
5. **Build** to `missions/mNN-<slug>/out/mNN.miz`. The build reads the mission folder's
   Markdown directly, so edit `briefing.md` and `kneeboard.md` (not `plan.json`) and then rebuild:
   - `briefing.md` becomes the DCS briefing. The first `#` heading is the sortie name.
     Everything before `## 2. Mission` is the situation (description). Paragraph 2 onward is the
     blue task, and a `## Red task` section becomes the red task. Markdown is stripped to plain
     text. If the file is missing, the build uses the planner's minimal briefing (title and
     objectives).
   - `kneeboard.md` is rendered to 768x1024 PNG pages, embedded as
     `KNEEBOARD/IMAGES/<mission_id>-kneeboard-01.png` (then `-02` and so on when it overflows), for
     every aircraft. Headings, bullets, `**bold**` and pipe tables render. Keep it to 25 lines or
     fewer so it fits on one page. The page font has no `—` or `→`, so these print as `-` and `->`.
   - The rendered pages exist only inside the `.miz`, so don't commit PNGs. To preview a page, run
     `uv run python -c "from dms_gen.builder import write_kneeboard_pages as w; print(w('<dir>/kneeboard.md', '<scratch dir>'))"`.
   - **Start variants.** When `player_flights` carry `variant:` (e.g. `ramp` and `air`), the
     build writes `out/<id>-ramp.miz` and `out/<id>-air.miz` (only that variant's player flight
     in each; shared everything else) and `out/<id>.miz` as a copy of the first variant. Each
     variant `.miz` is checked. Tell the user which file is which start.
   - `uv run dms build <mission> --test [--variant V]` makes the headless test build; its AI proxy
     replaces the ramp/runway flight by default, `--variant air` tests the air start.
6. **Check** (`uv run dms check <mission folder>` checks every variant). Every finding is either fixed (back to the stage that owns it: spec → validate/plan,
   lines → voice, generator bug → report) or explicitly accepted by the user.
7. **Explain how to fly it** (below), then point at the debriefer skill for after the flight.

## Flying it

1. Install: `uv run dms install <mission folder>` copies every variant to
   `Saved Games\DCS[.openbeta]\Missions\DMS\<campaign>\` (`--dcs stable|openbeta|auto`,
   `--dry-run` to preview; `dms run <mission> --install` does it after a clean build). Or copy
   the `.miz` for the start you want to `C:\Users\mook\Saved Games\DCS\Missions\`
   (Open Beta: `Saved Games\DCS.openbeta\Missions\`): `out/<id>-ramp.miz` for a cold start on
   the ramp, `out/<id>-air.miz` for an air start near the IP (copy both to have the choice in
   DCS). Missions without variants have just `out/<id>.miz`.
2. DCS → Mission → open it, or open it in the Mission Editor to inspect first. Don't re-save it from
   the ME unless needed, because the ME can strip unreferenced sound files.
3. Read the briefing screen (it comes from `briefing.md`). Then take the player slot (e.g. Dusty 1-1).
   In single player the lead is your aircraft and the rest of the flight are AI wingmen (comms
   menu, F1 Wingman). The cockpit callsign is the plan's `radio_callsign`.
   In the cockpit, the kneeboard (RShift+K, then `[`/`]` to page) shows the rendered `kneeboard.md`
   after the airframe's own pages. The F10 map is Fog of War by design: enemies appear as
   marks only when detected.
4. Fly. After the flight, debrief **before** relaunching DCS (it overwrites dcs.log).

## What to look for in dcs.log

`C:\Users\mook\Saved Games\DCS\Logs\dcs.log`

- **Banner:** `[DMS]` line with version and `missionId`. If it's missing, the bundle didn't load
  (check the DO SCRIPT trigger).
- **Errors:** `[DMS][...]` lines at ERROR level and `safeCall` tracebacks; `SCRIPTING:` Lua errors
  outside DMS.
- **Beats:** with `debug = true` in the plan, `[DMS][narrative]` lines show beats evaluated and fired.
- **Outcomes:** `[DMS.OUTCOME] {json}` lines. The debriefer reads these.
- Missing audio: a "file not found" for `l10n/DEFAULT/*.ogg` means a resource or mapResource
  problem (report it as a build bug).

## Quality bar

- Never skip validate or check. Never hand the user a `.miz` that check flagged without saying so.
- No paid voice render without a shown estimate.
- Every stage's result is explained in one or two plain sentences, along with where its file is.

## Checklist

- [ ] validate OK, lint warnings fixed or accepted (≤3 repair loops); re-validated after plan
- [ ] plan.json summarised; its frequencies and threat types match briefing/kneeboard
- [ ] voice dry-run shown; render approved or skipped with reason
- [ ] out/mNN.miz built; check clean or findings accepted
- [ ] briefing screen and kneeboard page(s) match briefing.md / kneeboard.md (not flown = not verified)
- [ ] Installed with `dms install` (or the copy path given); fly instructions and dcs.log pointers given; debriefer suggested
