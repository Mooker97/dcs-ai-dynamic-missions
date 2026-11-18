# DCS-unknowns probes (Q7)

Small generated missions that each answer one DCS unknown from
[NEXT.md section 8](../../../docs/rebuild/NEXT.md) (K1–K8), plus K9 and K10 from
[PLAN.md wave 1](../../../docs/rebuild/PLAN.md). Each probe logs `[DMS.PROBE] probe=kN key=value`
lines. `parse_probes.py` turns a `dcs.log` into one JSON answer per probe.

Status: implemented, not run. No probe has been run in DCS yet.

| File | What |
|---|---|
| `build_probes.py` | Generates `probe_kN_<slug>.miz` with pydcs through `dms_gen`'s `MissionBuilder` (ADR 0001: generate only) |
| `parse_probes.py` | The catalog (`PROBES`) and the dcs.log → JSON parser. Stdlib only |
| `lua/common.lua` | `DMS_PROBE` helpers: `log`, `after`, `start`, `finish`, value quoting |
| `lua/kN_*.lua` | One probe script per unknown (Lua 5.1) |
| `../../tests/test_probes.py` | Structural miz checks, Lua runs against a DCS stub, parser fixtures |

Every mission puts one blue AI Hummer ("Probe Anchor") 4 km south-west of Vaziani on Caucasus.
It has one MISSION START trigger with a DO SCRIPT FILE (`dms_probe_kN.lua` = `common.lua` + any
runtime module + the probe). When a probe finishes it logs `probe=kN done=1` and then
`[DMS.TEST] DONE`, so the harness hook exits DCS straight away. Probes call
`timer.scheduleFunction` and `world.addEventHandler` directly. That is allowed here only. Hard
rule 3 still covers everything in `lua/src`.

## Running

Before a run, check that no game is running and that enough RAM is free. The harness waits for
`--min-free-gb`, which defaults to 12. Run one probe at a time, because the harness locks its
write dir.

```bash
# 1. generate (default output dist/probes/, which git ignores)
uv run python tools/dcs_harness/probes/build_probes.py            # all, or: ... k1 k6
# 2. run (build_probes.py prints the exact command for each probe)
uv run python tools/dcs_harness/run_mission.py dist/probes/probe_k6_timers.miz --minutes 1 --report probe_k6_report.json
# 3. parse (the harness write dir defaults to %USERPROFILE%\Saved Games\DCS.dms_test)
uv run python tools/dcs_harness/probes/parse_probes.py "%USERPROFILE%/Saved Games/DCS.dms_test/Logs/dcs.log" --probe k6 --out k6.json
```

The harness replaces `dcs.log` on every run and keeps the previous one as `dcs.log.prev`. Copy
the log away after each run if you want to keep it, which K5 needs.

`parse_probes.py` exits with 0 when every requested probe has data. Each answer's `status` is one
of `answered`, `partial` (the headless half is settled, the rest is manual), `manual`, `no_data` or
`error`.

## The probes

| # | Question | Run | Answer keys | Headless? |
|---|---|---|---|---|
| K1 | Does a ground route need ≥ 2 points with the current position first? | `--minutes 3 --accel 8` | `one_point_moves`, `two_points_no_current_moves`, `two_points_current_first_moves`, `on_road_moves`, `control_moves` | yes |
| K2 | Does `world.getMarkPanels()` list markup shapes, and is a script mark's `initiator` nil? | `--minutes 1` | `shapes_listed`, `lines_quads_listed`, `script_initiator_nil`, `our_panels`, `removed_mark_still_listed` | script half |
| K3 | Does `radioTransmission` accept the subtitle/duration arguments? | `--minutes 1` | `arity7_ok` … `arity9_swapped_ok`, `validates_arguments`, `events_seen` | arity only |
| K4 | Range, power and LOS model of `radioTransmission` | `--minutes 1` | `transmissions` (call ok + terrain LOS per case), `all_calls_ok` | manual |
| K5 | Does `DMS.Rng.seed()` differ per launch of the same miz? | `--minutes 1`, **5 runs** | `seeds_all_distinct`, `picks_all_distinct`, `time_identical_across_runs`, `launch_entropy_all_distinct`, `per_run` | yes |
| K6 | Does a timer scheduled for exactly `timer.getTime()` at mission start fire? | `--minutes 1` | `start_now_fires`, `start_plus_0_05_fires`, `start_past_fires`, `callback_now_fires`, `labels` | yes |
| K7 | Does `net.dostring_in('mission', ...)` from a hook still work? | `--minutes 1 --inject "<K7 snippet>"` | `errorbox_dostring_ok`, `inject_dostring_ok`, `inject_ran_in_mission`, `global_visible_to_mission_script`, `works` | yes |
| K8 | Does Tacview write an ACMI from the isolated write dir? | `--minutes 2`, then parse with `--tacview-dir` | `tacview_loaded`, `new_acmi_files`, `acmi_written` | yes, after setup |
| K9 | What is the longest `env.info` line that arrives intact in dcs.log? | `--minutes 1` | `max_intact_len`, `first_broken_len`, `lengths[]` (found, logged_len, intact, split) | yes |
| K10 | Do `net.get_player_list` / `net.get_player_info` work in the mission env? | `--minutes 1` | `net_type`, `net_keys`, `get_player_list_ok`, `player_ids`, `get_player_info_ok`, `player_info_keys` | SP yes; also run `--mode server` |

### Per-probe notes

- **K1.** Five identical BTR-80 groups stand 300 m apart, 1.5 km south of the anchor. At t = 2 s
  each one gets one route variant: 1 point; 2 points without the current position; 2 points
  starting at the current position, off road; the same on road; and no task as a control. The
  probe logs distance moved and `hasTask()` at +60 s and +120 s. A group counts as moved beyond
  50 m. If the control moves, the answer gets a note.
- **K2.** The probe draws one mark of each kind (`markToAll`, `markToCoalition`, `circleToAll`,
  `textToAll`, `lineToAll`, `quadToAll`) with IDs from 7,100,001 and logs every panel. It then
  removes the `markToAll` mark and lists the panels again. The player-mark half (the initiator of
  a mark a human places) needs a client: place an F10 mark by hand in a `--watch` run and read
  the `panels` lines.
- **K3.** The sound file is deliberately missing, because a missing file raises nothing (see the
  gotchas). The `bad_arg_control` call passes a string as the point and as the frequency. If even
  that doesn't raise, then `ok=true` only means "did not raise", and the answer gets a note.
  Whether the subtitle is shown needs a cockpit.
- **K4.** This is a proxy only. Transmitters at 5, 20 and 50 km south, at 1000 W and 10000 W
  (251.0–253.5 MHz AM), log whether each call succeeds and the terrain LOS to a point 1500 m
  above the anchor. **Manual A/B:** fly a client aircraft over the anchor with a real `.ogg`
  embedded, tune each frequency, and note whether you hear it and how clean it is. Repeat behind a
  ridge and under an overcast layer.
- **K5.** `lua/src/dms/rng.lua` is embedded ahead of the probe. The probe samples at load, at the
  first BIRTH (it spawns a Hummer at t = 1 s so that a BIRTH happens) and at t = 3 s. Each sample
  logs the seed, the first 5 picks and the raw entropy inputs: `t`, `abs`, GC kB, the
  `tostring({})` address, `launchEntropy` and `math.random`. Run the miz 5 times, copy each
  `dcs.log` away, then pass them all at once:
  `parse_probes.py run1.log run2.log run3.log run4.log run5.log --probe k5`.
- **K6.** The probe schedules at −1, +0, +0.01, +0.05 and +1 s from the mission-start DO SCRIPT
  (`start_*`), and again from inside a timer callback at t ≈ 3 s (`cb_*`). It shows which ones
  fire, and whether the exact-now problem is specific to mission start.
- **K7.** Pass the inject snippet exactly as `build_probes.py` prints it. The text is
  `parse_probes.K7_INJECT`:
  `--inject "DMS_PROBE_K7_INJECTED = true env.info('[DMS.PROBE] probe=k7 phase=inject inject_ran=1')"`.
  The hook's own `[DMS.HARNESS] INFO errorbox_disable res=… err=…` line also goes through
  `net.dostring_in('mission', …)`, so the parser can answer from the hook lines even without the
  probe script.
- **K8.** One-time setup: enable Tacview recording in the harness write dir's
  `Config/options.lua` (`Saved Games/DCS.dms_test`). The plugin keys are in `["plugins"]["Tacview"]`
  in the main profile's `options.lua` [?]. Then run the probe and parse with
  `--tacview-dir "%USERPROFILE%/Documents/Tacview"`. The parser lists `.acmi` files newer than
  the first `dcs.log` timestamp, plus every log line that mentions Tacview. Q3 (the nightly) owns
  turning this on permanently in `run_mission.py`.
- **K9.** The probe logs 28 lines of exactly N bytes (100 … 65536, around the 2^k boundaries). Each
  line is a fixed head, a digit pattern and a `|END` tail. The parser rebuilds the expected text
  (`k9_message(n)`) and compares it byte for byte. A line that DCS split over several log lines
  shows `split: true`.
- **K10.** The probe calls `get_player_list`, `get_my_player_id` and `get_player_info` (whole
  table and the `"name"` attribute) at t = 2 s and t = 10 s. It logs whether the `ucid` field
  exists, never its value. Single player has no human, so for the MP answer also run it with
  `--mode server --copy-login` (this needs the saved ED login, see `docs/testing/STRATEGY.md`).

## After a run

Record each finding in `docs/reference/dcs-scripting-gotchas.md`. Remove the `[?]` or replace it
with the measured fact, and tag it "headless DCS <date>, DCS <version>". The probe output gives the
version in `app_version` on the `phase=start` line.
