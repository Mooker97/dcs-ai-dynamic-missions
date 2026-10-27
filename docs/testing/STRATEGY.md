# DMS testing strategy

How DMS missions are tested, from cheap and fast to expensive and real, and how Claude uses each tier.
Status as of 2026-10-27, on DCS 2.9.30 Steam Edition.

## Test pyramid

| Tier | What | Tool | Cost per run | Who runs it |
|---|---|---|---|---|
| 1. Lua unit specs | Runtime modules against a mocked DCS API (timer, env, Group, coalition, world events) | busted / lupa under `lua/` | ms | CI and Claude, on every change |
| 2. Python + structural .miz checks | Schemas, the planner, and the generated `mission`/`dictionary`/`mapResource` tables, plus a `luac -p` of every embedded script | pytest, `dms check <miz>` | s | CI and Claude, on every build |
| 3. Headless DCS run | The real DCS sim loads the .miz as a private local server. In-mission assertions log `[DMS.TEST]` lines and the harness parses dcs.log | `tools/dcs_harness/run_mission.py` | 1.5–3 min of boot plus mission time, and the machine's GPU/CPU | Claude locally, before handing a mission to the user |
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
- **Time.** The server runs in multiplayer mode, so time acceleration is not available. Mission time equals wall time.
  `--accel` is wired in (`Export.LoSetCommand(53)` steps) but is expected to be ignored in MP. Design test missions so
  everything interesting happens in the first 2–5 minutes. Use `DMS_CONFIG` overrides with short delays and
  `chance = 100`, or a test-only seed.
- **Run cost.** About 35–50 s to boot to idle on this machine (i7-10700KF), then mission load and mission time. It uses
  the GPU/CPU and cannot run while the user is playing DCS (one instance at a time; the harness refuses if DCS is running).
- **Multiplayer mode.** DMS runs inside a server session (`DCS.isMultiplayer()` is true). A single-player code path that differs
  (for example, assuming `world.getPlayer()` exists) is not exercised.

**Tier 4, manual.** This is the only tier for feel, pacing, voice, menus and difficulty. Use the debriefer skill afterwards. The
`[DMS.OUTCOME]` lines are the same ones tier 3 parses.

## The harness (tier 3)

```
uv run python tools/dcs_harness/run_mission.py path/to/test.miz --minutes 5 [--report out.json]
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
3. It launches `DCS.exe -w DCS.dms_test --server --norender` with `SteamAppId=223750` in the environment. Without that variable the
   Steam build asks Steam to relaunch it ("Steam asked for app restart") and the arguments are lost. `--server` also
   skips the 2.9 launcher window. Plain client mode (`--mode client`) stalls on that window, so don't use it.
4. The hook, running in the GameGUI state, uses `onSimulationFrame` as a ticker. This callback also ticks while idle. About 20 s after the hook loads, it calls
   `net.start_server()` for a private, LAN-bound, password-protected server with `resume_mode = 1` and only the test mission.
   It keeps the sim unpaused and watches `DCS.getLogHistory()` for `[DMS.TEST] DONE`. It calls `DCS.exitProcess()`
   3 s after DONE, at `--minutes` of model time, at mission end, or at its own wall limit.
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

## Current status and the one-time user step

What has been verified on this machine with a pydcs smoke mission (Caucasus, one blue AI vehicle, DO SCRIPT logging
PASS then DONE after 30 s):
- DCS 2.9.30 Steam launches unattended with `--server --norender` and an isolated write dir in about 35–50 s. It loads all modules,
  and the harness hook loads and ticks. There are no modal dialogs in this mode.
- **Blocker:** `net.start_server` fails with `ASYNCNET: server_start failed: login is required` (preceded by
  `Login failed with code 400`). A server needs an Eagle Dynamics account login, and Steam auth alone is not enough. The test
  write dir has no saved login.

**One-time fix (user). Pick one:**
- **A (easiest).** Run once with `--copy-login`. It copies your saved ED login (`Saved Games\DCS\Config\network.vault`, already present
  because you have logged into multiplayer before) into `Saved Games\DCS.dms_test\Config\`. This is opt-in because it duplicates a
  credential file. It is unverified whether the vault is portable between write dirs. If the next run still logs `Login failed`, use B.
- **B.** Start DCS once with the test profile: in a terminal,
  `set SteamAppId=223750 && "E:\SteamLibrary\steamapps\common\DCSWorld\bin\DCS.exe" -w DCS.dms_test`.
  Get through the launcher, open **Multiplayer**, log in with your ED account and tick **Save password / auto login**, then quit. If your ED account is
  not linked to Steam yet, link it at digitalcombatsimulator.com first.
- **C.** Install the free **DCS dedicated server** (digitalcombatsimulator.com → Downloads → Dedicated Server) and log in once with
  "remember me". The harness prefers `DCS_server.exe` automatically.

After that, re-run the smoke test:
`uv run python tools/dcs_harness/run_mission.py <smoke.miz> --minutes 3`. The expected result is verdict `pass`, 2 PASS lines, and `done: true`.

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
- **Single-player autostart** (no login needed, time acceleration possible): the GUI starts single-player missions by setting
  `START_PARAMS.command = '--mission'` / `missionPath` and calling `Gui.doQuit()` (`MissionEditor/modules/me_mission.lua`).
  Driving that from a hook is unproven, and there would be a briefing screen to dismiss. It is worth a spike if
  the login route stays blocked or acceleration becomes important.
