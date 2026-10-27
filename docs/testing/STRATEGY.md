# DMS testing strategy

How DMS missions are tested, from cheap and fast to expensive and real, and how Claude uses each tier.
Status as of 2026-10-27, on DCS 2.9.30 Steam Edition.

## Test pyramid

| Tier | What | Tool | Cost per run | Who runs it |
|---|---|---|---|---|
| 1. Lua unit specs | Runtime modules against a mocked DCS API (timer, env, Group, coalition, world events) | busted / lupa under `lua/` | ms | CI and Claude, on every change |
| 2. Python + structural .miz checks | Schemas, the planner, and the generated `mission`/`dictionary`/`mapResource` tables, plus a `luac -p` of every embedded script | pytest, `dms check <miz>` | s | CI and Claude, on every build |
| 3. Headless DCS run | The real DCS sim loads the .miz as a single-player mission (no login, time-accelerated). In-mission assertions log `[DMS.TEST]` lines and the harness parses dcs.log | `tools/dcs_harness/run_mission.py` | about 50 s of boot plus mission time divided by `--accel` | Claude locally, before handing a mission to the user |
| 4. Manual cockpit | A human flies it | DCS + the debriefer skill | 30+ min | The user |

Promote a bug down the pyramid. When a tier-3 or tier-4 run finds a bug, add a tier-1 spec that reproduces it whenever you can.

## Fidelity and limitations per tier

**Tier 1, mock specs.** These are fast and deterministic, with a seeded RNG. They check logic only. The mocks encode
*our assumptions* about the DCS API, and that is where real bugs hide: nil returns for dead groups, `Group.getByName`
on late-activated groups, event ordering, and Lua 5.1-only syntax. Keep the mocks honest by copying observed behaviour
from tier-3 logs.

**Tier 2, structural checks.** These catch broken IDs, missing dictionary keys, bad CLSIDs, unknown unit types,
and script syntax errors. They cannot catch runtime errors or wrong behaviour.

**Tier 3, headless DCS.** This is the real engine: real `coalition.addGroup`, AI, pathing, events, timers, and the sanitized
mission environment. Limitations:
- **No human player.** The F10 radio menus, `trigger.action.outTextForGroup`/`outSoundForGroup` delivery, the cockpit,
  kneeboard, briefing UI, and voice playback quality cannot be checked. We can only assert that the call was made without error.
- **Player proxy.** Set `DMS_CONFIG.test.playerProxy = "<AI group name>"`, and the runtime treats that AI group as "the
  player" for proximity, director and intel logic (`DMS.Test.playerGroups()` and `DMS.Test.emitProxySpawn()` in
  `tools/dcs_harness/test_mode.lua`). The proxy differs from a human in several ways: there are no `player.spawned` events from BIRTH
  (we synthesize them), `getPlayerName()` is nil, the AI flies its route rather than reacting, it never crashes or ejects,
  and there are no `S_EVENT_PLAYER_*` events. Encounters that depend on player behaviour need scripted proxy routes.
- **Time.** Single-player mode (the default) supports time acceleration. `--accel 16` ramps to x16 in about
  3.5 s, and 300 s of model time then runs in about 21 s of wall time. Server mode (`--mode server`) has no acceleration, so model
  time equals wall time there. Higher factors make AI and physics step coarsely. Use x16 or less for behaviour tests, and keep x1
  for anything timing-sensitive (missile shots, close formation).
- **Run cost.** About 30 s to load modules, 15 s of idle menu, and 4–5 s of mission load, then mission time divided by the
  accel factor. A 300 s mission at x16 takes **about 78 s end to end** with `--norender`. It cannot run while the user is
  playing DCS (one instance at a time; the harness refuses if DCS is running). Every run visibly opens and closes a DCS process,
  so batch your checks into one test mission instead of launching many runs.
- **Single-player mode.** DMS runs as an SP mission (`DCS.isMultiplayer()` is false), the same way the user flies it.
  MP-only code paths (slots, `net.*` player lists) are exercised only by `--mode server`, which needs a login.

**Tier 4, manual.** This is the only tier for feel, pacing, voice, menus and difficulty. Use the debriefer skill afterwards. The
`[DMS.OUTCOME]` lines are the same ones tier 3 parses.

## The harness (tier 3)

```
uv run python tools/dcs_harness/run_mission.py path/to/test.miz --minutes 5 --accel 16 [--report out.json]
    [--mode sp|server] [--render] [--probe]
```

What it does:
1. It finds DCS: `DCS_server.exe` is preferred, then the newest `DCS.exe`. The search covers the registry, common paths, and
   Steam libraries. You can override it with `--exe` or `DCS_INSTALL`.
2. It prepares an **isolated write dir**, `%USERPROFILE%\Saved Games\DCS.dms_test`. The user's `Saved Games\DCS` profile is
   only read: `options.lua` is copied once and then forced windowed at 1280x720 with no VR and muted. Nothing in the
   install dir is touched, and `MissionScripting.lua` stays sanitized. The harness writes:
   `Config/serverSettings.lua`, `Config/autoexec.cfg` (`net.allow_dostring_in = {"mission"}`, so the hook can run
   `env.setErrorMessageBoxEnabled(false)` and optional `--inject` Lua in the mission env), `Config/nicknames.lua`,
   and `Scripts/Hooks/dms_harness_hook.lua`, generated from `hook_template.lua`.
3. It launches `DCS.exe -w DCS.dms_test --norender` with `SteamAppId=223750` in the environment. Without that variable the
   Steam build asks Steam to relaunch it ("Steam asked for app restart") and the arguments are lost. The 2.9 launcher window is
   suppressed by `["miscellaneous"]["launcher"] = false` in the test profile's `options.lua`, which the harness forces on every run.
   This is the `misc('launcher')` option in `MissionEditor/modules/Options/optionsDb.lua`. With that setting, plain client mode
   boots straight to an idle main menu with no dialogs. `--mode server` adds `--server`.
4. The hook, running in the GameGUI state, uses `onSimulationFrame` as a ticker. This callback also ticks while idle. About
   15 s after the hook loads:
   - **`--mode sp` (default)** does exactly what the GUI's **Fly** button does (`me_mission.runMission` then `Gui.doQuit`).
     Through `net.dostring_in('gui', ...)` it sets `START_PARAMS.command = '--mission'`, `missionPath`, and
     `returnScreen = 'quit'`, then calls `__EMBEDDED__.doAction()`. Hooks run in a sandboxed env, so `START_PARAMS` and
     `__EMBEDDED__` are only reachable through `dostring_in('gui')`, which `autoexec.cfg` allows. The `dxgui` `Gui` table is
     not a global there, and `DCS.startMission` is "NOT IMPLEMENTED YET" (`MissionEditor/GameGUI.lua`).
     SP missions start paused on the briefing. The hook calls `DCS.setPause(false)` every second, which fires
     `onSimulationResume` and hides the briefing. No click is needed.
   - **`--mode server`** calls `net.start_server()` for a private, LAN-bound, password-protected server with
     `resume_mode = 1`. This needs an ED login.

   The hook watches `DCS.getLogHistory()` for `[DMS.TEST] DONE`. It calls `DCS.exitProcess()` 3 s after DONE, at
   `--minutes` of model time, at mission end, or at its own wall limit.

   **Time acceleration** (`--accel N`, SP only): the hook sends `Export.LoSetCommand(53)` ("Accelerate model time", Ctrl+Z)
   at most once per 0.15 s and reads `Export.LoGetModelTimeAcceleration()` back until it equals N. Each press adds 1 (x1, x2,
   x3 and so on), and command 191 steps down. Do not send several presses in one frame: they compound unpredictably (63 presses
   in one frame gave x3700). Neither the hook env nor the GUI state has a `timer.setAcc` in 2.9.30. The console's
   `acceleration` command uses one, but that object is not reachable. `--probe` logs the hook-visible `DCS.*`/`Export.*`
   inventory and the GUI-state globals.
5. Python kills our DCS process on a hard wall timeout. It matches the process by the write-dir name in the command line, so the user's own DCS is never
   killed. It then parses `DCS.dms_test\Logs\dcs.log` into JSON with these fields: `phases`, `tests` (PASS/FAIL/SKIP/INFO),
   `done`, `outcomes` (`[DMS.OUTCOME]` JSON), `script_errors` (SCRIPTING ERROR / "Mission script error"),
   `dms_errors` (`[DMS]` ERROR lines), `other_errors`, `notes`, and `verdict`.
   Exit codes: `0` passed (or ran with no assertions), `1` FAIL or script/DMS errors, `2` infrastructure problem.

### In-mission assertions (`tools/dcs_harness/test_mode.lua`)

The Lua owner bundles this file, or a test mission loads it with a separate DO SCRIPT FILE. It is inert unless called.

```lua
DMS.Test.check("config_loaded", DMS_CONFIG ~= nil)
DMS.Test.expect("sam_spawned", function()
  return DMS.Registry.count("ground", 1) > 0, "red ground active"
end, 120)                                         -- model seconds; FAIL "timeout" otherwise
DMS.Test.expect("no_early_qrf", function() return Group.getByName("DMS_qrf_1") ~= nil end, 60, {negate = true})
-- DONE is logged automatically once every expect() resolves (DMS.Test.manualDone = true to call DMS.Test.done() yourself)
```

Log protocol: `[DMS.TEST] PASS|FAIL|SKIP|INFO <name_without_spaces> <detail>` and `[DMS.TEST] DONE <passed>/<total>`.
Test-mode `DMS_CONFIG` additions: `test = { playerProxy = "Blue Proxy" }`.

## Current status (2026-10-27, DCS 2.9.30.28738 Steam, i7-10700KF + RTX 4070 Ti)

**Single-player mode works end to end with no login and no user step.** Verified runs of the pydcs smoke missions
(Caucasus, one blue AI vehicle, DO SCRIPT logging PASS, then PASS + DONE after N model seconds):

| Run | Result | Model time | Wall time (in sim) | Wall time (total) |
|---|---|---|---|---|
| `smoke.miz` (DONE at t=30), early ramp that reached about x3 | pass, 2 PASS + DONE | 40 s | 14 s | about 70 s |
| `smoke_long.miz` (DONE at t=300), `--accel 16`, `--norender` | pass, 2 PASS + DONE | 355 s | 24 s (x16 reached after 3.4 s) | **78 s** |
| same, `--render` | pass, 2 PASS + DONE | 349 s | 25 s | 156 s |

Phases in a typical `--norender` run: modules and hooks load at about 29 s, the menu is idle and `sp_start_called` fires at about 42 s,
the mission is loaded at about 47 s, then `sim_start`, DONE, and `EXIT reason=done`.

### `--norender` vs `--render`

Measured during the x16 `smoke_long` runs (sampled every 2 s). GPU numbers are for the whole GPU, and the desktop was already using
20–30% at idle.

| | `--norender` (default) | `--render` (1280x720 window) |
|---|---|---|
| Total wall time | 78 s | 156 s (boot to hook about 64 s vs 29 s) |
| DCS CPU, % of the whole machine | avg 4, peak 15 | avg 16, peak 57 |
| DCS working set | avg 1.7 GB, peak 3.4 GB | avg 4.0 GB, peak 8.9 GB |
| VRAM, whole GPU | no increase (2.2 GB, desktop only) | +4.6 GB (peak 6.9 GB) |
| GPU utilisation | no measurable increase | peaks of 72% |
| Can a human watch | no | yes |
| Sim, AI and scripting fidelity | same | same |

Use `--norender` for every automated run. Use `--render` only when a human wants to watch the run. The harness never asserts
anything visual.

### Server mode and the optional user step

`--mode server` still fails with `ASYNCNET: server_start failed: login is required`, because the test profile has no ED login.
You only need it to exercise MP-specific code. To enable it, do one of the following:
- Run once with `--copy-login`. It copies `Saved Games\DCS\Config\network.vault` into the test profile only.
  **The user has to run this command themselves**: Claude's auto-mode permission classifier blocks Claude from copying the
  credential. It is unverified whether the vault is portable between write dirs.
- Start `DCS.exe -w DCS.dms_test` once (with `SteamAppId=223750` set), open Multiplayer, log in with "Save password" ticked,
  and quit.
- Install the free DCS dedicated server and log in once. The harness prefers `DCS_server.exe`.

## How Claude uses this in the dev loop

1. Change Lua or the generator, then run tier 1 and 2 (`uv run pytest`, busted, `dms check`). This always happens, and it is fast.
2. Before telling the user a mission is ready, or after touching spawn, director or encounter code, build a **test variant**
   of the mission: the same plan plus `test_mode.lua`, `test.playerProxy`, short timers, `chance = 100`, and a few
   `DMS.Test.expect` calls for the beats or encounters under test. Run the harness with `--minutes` just past the last
   deadline. Never run it while the user has DCS open; the harness refuses if DCS is running.
3. Read the JSON report. `script_errors` and `dms_errors` are bugs. A `FAIL` comes with its detail. Exit code 2 means infrastructure:
   check `phases` and `notes` (login, wall timeout) and do not "fix" mission code for it.
4. Fix the bug, add a tier-1 regression spec, and re-run.
5. Hand the real (non-test) .miz to the user for tier 4, with notes on what tier 3 could not cover (menus, sounds, feel).

## Rejected or deferred options

- **Editing `MissionScripting.lua`** to desanitize: rejected because we never modify the install. Hooks already have `io`, `os` and `lfs`, and
  the mission env is reachable through `net.dostring_in('mission', 'a_do_script(...)')` when allowed by the write-dir `autoexec.cfg`.
- **DCS-gRPC**: deferred, because it requires a `dofile` line added to the install's `MissionScripting.lua`. Hooks plus dcs.log cover our needs.
- **`DCS.startMission(path)`**: listed in `MissionEditor/GameGUI.lua` as "NOT IMPLEMENTED YET". **`net.load_mission`**
  is server-only. The SP path uses `START_PARAMS` and `__EMBEDDED__.doAction()` instead (see above).
- **Server mode as the default**: it boots fine, but `net.start_server` needs an ED login and gets no time acceleration.
  SP mode replaced it as the default.
