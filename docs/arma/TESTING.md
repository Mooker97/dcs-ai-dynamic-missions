# Testing Arma 3 missions headless

`tools/arma_harness/run_mission.py` runs a mission unattended on a local Arma 3 dedicated server and
turns the `.rpt` log into a JSON report and an exit code. It uses the server that ships with the
game (`arma3server_x64.exe` in the Arma 3 folder), so no separate install or download is needed.

## Quick start

```
# 3 seeds, 2 servers at a time, compressed test timings (the default cycle)
uv run python tools/arma_harness/run_mission.py arma/missions/dms_the_hill.Altis --seeds 1,2,3 --parallel 2
# one seed, a forced site, full realistic timings and the 1 km start
uv run python tools/arma_harness/run_mission.py arma/missions/dms_the_hill.Altis --seed 42 --param DMS_site=2 --time-scale 100 --start-dist 0 --minutes 45
# forced failure: the exfil heli is destroyed on landing (1) or the squad is wiped after the intel (2)
uv run python tools/arma_harness/run_mission.py arma/missions/dms_the_hill.Altis --seed 3 --param DMS_testForce=1
```

| Option | Meaning |
|---|---|
| `--minutes N` | Mission-time budget, default 15. Sets `DMS_testMinutes = N`, the mission's own hard stop, which ends the run with a summary. The wall timeout is N min + 4 min |
| `--seed N` / `--seeds 1,2,3` | `DMS_seed`. With several seeds each one gets its own server, port (+20 each), profile subdir (`arma_test\s<N>`) and mission folder (`MPMissions\dms_<name>_s<N>.<world>`) |
| `--parallel K` | Servers at once. **Capped at 2.** Launches are serialised, and each one waits until `--min-free-gb` (default 6 GB) of RAM is free, for at most `--ram-wait` s |
| `--priority` | `belownormal` (default), `idle` or `normal`. The server process priority class, so a game in the foreground keeps the CPU |
| `--time-scale P` | `DMS_testTimeScale` in percent (default **15**). Scales the mission-logic delays through `DMS_fnc_t`: QRF delays and wave gaps, mortar processing and flight time, exfil hold-off, boarding timers and test timeouts. AI, physics and spawning are unchanged. Waits the AI needs in order to act have floors (boarding window ≥ 120 s, intel timeout ≥ 600 s). It only applies when `DMS_testMode = 1`, so normal play always uses scale 1 |
| `--start-dist M` | `DMS_testStartDist` (default **300** m). The test squad starts M m from the compound. Players always start at 1 km (`startDistance`). `0` = normal |
| `--param K=V` | Any extra mission param (repeatable): `DMS_site=1..3`, `DMS_debug=1`, `DMS_testForce=1/2` |
| `--no-fail-fast` | By default a run stops at the first script error or `[DMS.TEST] FAIL`. A run always ends 3 s after `[DMS.OUTCOME]` |
| `--no-test-mode` | Do not set the test params |
| `--diag` | Diagnostic mission: no test params, and success is a `[DMS.TEST] DONE` line |
| `--wall-timeout S`, `--port P`, `--difficulty D` | Overrides. The port defaults to the first free UDP range from 2402 |
| `--keep-mission` | Leave the copy in `MPMissions` |
| `--report F` | JSON path (single run). Default: `%LOCALAPPDATA%\dmsrma_testeports\`. A batch also writes `<name>_batch_<stamp>.json` |
| `--arma DIR` / `ARMA3_DIR` | The Arma 3 folder. Default: `E:\SteamLibrary\steamapps\common\Arma 3` |

Exit codes: **0** pass (summary reached, no FAIL, no script errors), **1** ran but failed,
**2** infrastructure problem (server missing or already running, not enough RAM, mission never
started). A batch returns the worst code.

## What it does

1. It refuses to start if any `arma3server*.exe` is already running.
2. It copies the mission to `<Arma 3>\MPMissions\dms_<name>.<world>`, the only thing it writes into the
   game folder, and deletes the copy afterwards.
3. It writes `server.cfg` and `basic.cfg` to `%LOCALAPPDATA%\dms\arma_test\`, which is also the
   `-profiles` dir, so the `.rpt` files land there. `server.cfg` sets LAN only, no password, random
   admin passwords, BattlEye 0, verifySignatures 0, `persistent = 1` and one `class Missions` entry
   with `class Params` (`DMS_testMode = 1`, `DMS_seed`, `DMS_testMinutes`, extras).
4. It launches
   `arma3server_x64.exe -config=… -cfg=… -profiles=… -name=dms -autoInit -port=… -noSound -world=empty`.
   `-autoInit` together with `persistent = 1` starts the mission with no client connected. Mission
   params come from `server.cfg`.
5. It tails the newest `.rpt` and prints `[DMS…]` and error lines live. It stops on
   `[DMS.TEST] DONE` (written after the SUMMARY), or on the wall timeout, or 300 s without
   `initServer done`. Then it kills the process tree it started.
6. It parses the log:
   - script errors (blocks starting `Error in expression`, plus `Error position:`, `Error …`,
     `File …, line N`)
   - `[DMS] WARN/ERROR` lines
   - `[DMS.TEST] PASS|FAIL <check> <detail>`
   - `[DMS.TEST] SUMMARY …`
   - `[DMS.OUTCOME] result=… end=… reason=… seed=… site=… t=…`
   - `[DMS.DIAG] …` lines

## Diagnostic sweep (class names, sites)

```
uv run python tools/arma_harness/make_diag.py
uv run python tools/arma_harness/run_mission.py tools/arma_harness/diag/dms_diag.Altis --diag
```
This checks classes with `isClass`, building positions, site, QRF and town data, all vanilla
military structures on Altis and the candidate outposts' start/LZ rings. Results are in
`docs/arma/kb/classes-verified.md` and `sites-verified.md`. A run takes about 40 s.

## Notes

- Each run starts a fresh server, which takes about 25 s to load Altis. A dedicated server cannot
  accelerate time (`setAccTime` is single-player only), which is why the test mode compresses its
  own delays instead.
- **`arma3_x64.exe -autotest=<cfg>` (SP with `setAccTime`): untested.** It would launch the game
  client, which was ruled out while the PC is in use for gaming. To try later: an autotest config
  that lists the mission, plus `setAccTime 4` in test mode (SP only).
- A dedicated server with an idle AI mission uses about 1.5–2.5 GB RAM.
- The first launch may show a **Windows Defender Firewall** prompt for `arma3server_x64.exe`. The
  harness only needs loopback, so *Cancel* is fine. The server keeps running either way.
- Harmless log noise: `Some of magazines weren't stored in soldier Vest or Uniform?`,
  `Duplicate HitPoint name …`, `Strange convex component…`.
- The test mode drives an AI squad. AI behaviour is not deterministic, so a seed reproduces the
  scripted choices but not the fight itself.
