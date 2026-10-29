# Test fixtures

Inputs for tests and golden checks. Binary files (`*.miz`, `*.wav`, `*.ogg`, `*.mp3`, `*.png`)
are stored with **Git LFS** (see `.gitattributes`); run `git lfs install` before cloning.
Names are sanitized to lowercase-hyphen. Treat every file as read-only: tests copy before writing.

## `miz/` — DCS mission files

| File | Origin | Notes |
|---|---|---|
| `dustoff-corridor.miz` | `Saved Games\DCS\Missions\Syria AH64\Dustoff Corridor.miz` (user's DCS folder) | Syria, AH-64D. Reference mission for the v0.4 vertical slice; scripts in `examples/dustoff-corridor/` |
| `dawn-scout.miz` | `miz-files/input/Dawn Scout.miz` | Syria AH-64 scout mission with embedded audio; scripts in `examples/dawn-scout/` |
| `desert-scout.miz` | `miz-files/input/Desert Scout.miz` | Syria scout mission; scripts in `examples/desert-scout/` |
| `unit-reference.miz` | `miz-files/input/unit-reference.miz` | Small mission with reference units (type strings / unit table layout) |
| `verbose.miz` | `miz-files/input/Verbose.miz` | Small mission. Byte-identical to legacy `legacy/miz-modification/tests/test.miz` (so that one was not copied again) |
| `syria-blank.miz` | `miz-files/Blanks/Syria Blank.miz` | Empty Syria mission, base for generated missions |
| `caucus-empty.miz` | `legacy/miz-modification/tests/integration_tests/miz-files/caucus-empty.miz` | Caucasus, no groups |
| `caucus-single-flight.miz` | `legacy/miz-modification/tests/integration_tests/miz-files/caucus-single-flight.miz` | Caucasus, one flight |
| `caucus-multi-unit.miz` | `legacy/miz-modification/tests/integration_tests/miz-files/caucus-multi-unit.miz` | Caucasus, multiple groups/units |

Not copied: `miz-files/input/temp_unit_ref/` (extraction temp dir) and `miz-files/output/` (generated).

## `prompts/` — story / mission prompts (golden prompt suite seeds)

| File | Origin |
|---|---|
| `story-prompt.txt` | `supporting Files/Story Prompt.txt` (base template: Syria, single-player Apache, CAS/Recon) |
| `story-prompt-artillery-hunt.txt` | `supporting Files/Story Prompt - Artillery Hunt.txt` |
| `story-prompt-cracking-kirkhan.txt` | `supporting Files/Story Prompt - Cracking Kirkhan.txt` |
| `story-prompt-valley-patrol.txt` | `supporting Files/Story Prompt - Valley Patrol.txt` |

## Related assets (not fixtures)

`assets/audio/` and `assets/images/` hold the rendered voice lines and briefing images copied from
the local `mission assets/` folder (also LFS). The original untracked folders (`miz-files/`,
`mission assets/`, `supporting Files/`) were left in place.

## `dcs-logs/` — dcs.log excerpts for `dms outcome` / `dms debrief`

| File | Origin |
|---|---|
| `multi-session-dcs.log.txt` | Hand-written, several sessions (banner, restart, malformed lines) |
| `headless-m03-dms-test.log.txt` | Real lines from a headless DCS run of viper m03 (`Saved Games\DCS.dms_test\Logs\dcs.log`, 2026-10-28): banner, two `[DMS]` warnings, one `update` `[DMS.OUTCOME]` (no `end`) |
| `synthetic-m01-{win,window-lost,player-lost}.log.txt` | Synthetic viper m01 flights in the real line format (m01 not flown yet); used by `tests/integration/test_campaign_loop.py` |
