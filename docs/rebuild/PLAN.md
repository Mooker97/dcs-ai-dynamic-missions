# Plan: what is left (2026-10-29)

This file merges five read-only planning passes into one plan. Nothing here is done: every item
stays "implemented, not flown" until it meets the [DoD](../adr/0009-definition-of-done-requires-flight.md).
Tracks A–E are independent and can run in parallel. **DCS and Arma runs are strictly one at a
time** on the shared PC, with the T0 pre-flight check before each.

| Track | What | Needs the user? |
|---|---|---|
| [A](#a-headless-dcs-backlog) | Headless DCS backlog: m03/m04/w01 re-runs, missing test checks, plugins | No (DCS runs serialize) |
| [B](#b-mcp-docs-dedicated-server) | MCP in Claude Code, docs staleness, dedicated server | MCP enable, ED login |
| [C](#c-arma-the-hill) | Arma: The Hill across 3 seeds, CI, playtest, backend | Playtest |
| [D](#d-cockpit-sessions) | Cockpit sessions that tick most v0.3–v0.7 boxes | Yes (flying) |
| [E](#e-v09-and-v10) | v0.9/v1.0 in five waves | Real flights at the end |

## Findings that change things

These came out of the planning passes and should be fixed first:

1. **The MCP server is switched off.** `.claude/settings.local.json` has
   `"disabledMcpjsonServers": ["dms"]`. Turn it back on in `/mcp`; this is a user step.
2. **The Skynet adapter will register nothing.** Its default prefix is `DMS_`, but the planner
   names SAM groups `sa6_site_1`, `sa8_popup_1`, ... When `skynet` is enabled, the planner should
   emit `DMS_SKYNET = {prefixes = {...sam threat ids}}`.
3. **The m03 and w01 test builds are stale.** They predate a0c1679, 3603721, facf2cc and 176251e,
   so rebuild both before re-running.
4. **There is no DMS F10 menu in Viper m01 or m02.** The specs don't turn on the `comms` menu
   option, so turn it on before cockpit session 1, or the Comms box can't be ticked.
5. **m02 has no voice manifest.** A plain `dms run` would pay for ElevenLabs, so use
   `--skip-voice` (or render it on purpose).
6. **Arma doc drift.** `exfilHotRadius` is 200 in `fn_config.sqf:132` but 300 in `arma/README.md`.
7. **`tools/dcs_harness/run_mission.py` has uncommitted edits from another session.** Exactly one
   work package may touch it at a time.

---

## A. Headless DCS backlog

**T0, the pre-flight check before every run** (the PC is shared, and the lock allows one run per
write dir and one DCS at a time):
```powershell
Get-Process DCS,DCS_server,arma3_x64,arma3 -EA SilentlyContinue     # must print nothing
[math]::Round((Get-CimInstance Win32_OperatingSystem).FreePhysicalMemory/1MB,1)  # >= 12
Test-Path "$env:USERPROFILE\Saved Games\DCS.dms_test\dms_harness.lock"  # False or holder dead
```
Exit code 2 is an infrastructure problem. Never "fix" mission code because of it.

| # | Task | DCS? | Effort |
|---|---|---|---|
| A1 | **Re-run Viper m03.** Rebuild with `--test` (test.minutes should be about 87, up from 67), then run the harness `--accel 16 --minutes <t+2>`. Pass = verdict `pass` with all 17 checks: the spine through `rook_rtb`, the 6 required encounters, and `outcome_end` `result=success`. Likely failures: the proxy never lands (loiter or popTask resume), `jtac_checkout` never fires, or an encounter requirement is wrong (fix it in `testmode.py encounter_requirements`, not in the mission). | yes | 10 min |
| A2 | **Viper m04.** Rebuild, then run. Pass = the spine through `on_deck` and `outcome_end`, with the 14 optional encounters INFO only. Watch the fuel divert and the go-around. | yes | 10 min |
| A3 | **Missing test-mode checks.** Write them in CONTRACTS first, then `lua/src/dms/test.lua`, then `dms_gen/planner/testmode.py`, then the specs. The kinds are listed below. | no | ~4 h |
| A4 | **Dustoff w01, test build.** Pass = the spine through `mission_end`, plus `flight_orders`, `flight_strike`, `camera_cues`, `voice_files` and `watch_mode`. The PLAY lines show `via=all tx=0`, with `file=-` on the `voiced:false` lines. Likely failures: the column stalls (tune the screen orders), or no strike release (check the `weapon` → `weaponType` mapping). | yes, after A3 | 5 min |
| A5 | **w01 plain build** (the real stand-in path; `flights.lua:1104` never runs in test mode). Run `--minutes 20`. Judge from the log: the line `watch focus 'Dusty_dusty' stands in`, `started with K flight(s) (watch mission)`, `[DMS.OUTCOME] kind=end`, and no ERROR. | yes | 4 min |
| A6 | **Plugin smoke.** First fix finding 2, with a test in `dms-gen/tests/test_plugins.py`. Then make `campaigns/plugin-smoke/`: `p01-skynet` is m01 plus `plugins: [skynet]`, `p02-moose` is m02 plus `plugins: [moose]`. Skynet pass = the version line, `SAM site sa6_site_1 added`, `skip DMS_sa6_ambush_1` and `skip DMS_sa8_popup_1` (runtime spawn names), and `IADS activated (N>=1)`. MOOSE pass = the include banner, and **all of m02's normal checks still pass** (that proves MOOSE doesn't starve `DMS.Bus`). | yes | 2 h + 10 min |
| A7 | **Record the results** in ROADMAP and CHANGELOG as "headless DCS <date>". | no | 20 min |

**New check kinds for A3:**

| Kind | Added when | Pass |
|---|---|---|
| `flight_strike` | any `strike` order | Every started strike order has at least one `flight.weapon` release. FAIL if it ended on `maxSec` with no release. INFO if the target died first. |
| `camera_cues` | `watch.cues` | Every fired beat with a `cue` produced exactly one `CAMERA: ...` text with `all=true`. |
| `voice_files` | always | A `voiced:false` line plays with `file=nil` and the text shown. Every other line plays its own file. |
| `watch_mode` | `watch` | The focus units are registered in `DMS.Bus._players`, there were 0 `radioTransmission` calls, and Intel marks use coalition -1. |
| `plugins` | spec `plugins` non-empty | mist: `mist.majorVersion==4`. moose: `BASE` and `_DATABASE` exist. skynet: `DMS.SkynetAdapter.active` and the sites count is at least the minimum. |

**Order:** A3 and the A6 authoring can start now. The DCS runs go strictly in series:
A1 → A2 → A4 → A5 → p01 → p02, about 45 min of DCS in total.

---

## B. MCP, docs, dedicated server

### B1. MCP server in a real Claude Code session
1. **User:** take `dms` out of `disabledMcpjsonServers`, or approve it in `/mcp`.
2. Run `claude mcp list` from the repo root. Pass = `dms ... ✓ Connected`. `.mcp.json` is fine on
   Windows (`uv` is a real exe on PATH, and `find_root()` handles any cwd).
3. Run a non-interactive session on a scratch copy of the campaign:
   `claude -p "...schema, campaign_status, validate, plan, build, check..." --allowedTools "mcp__dms__*" --output-format json`.
   Pass = all 6 tools are called and each returns `ok: true`, `build` returns a miz path, and
   `out/check.json` exists. Add a negative case: `validate` on a missing path returns
   `{ok:false}`, not a protocol error.
4. Add read-only tools: `catalog`, `outcome`, `doctor` and `voice_estimate` (a dry run, so no
   cost). Maybe `install(dry_run=True)`. Don't add `run` (it pays for voice) or `bundle-lua`.
5. **ADR 0005 conflict:** `check.json` is MCP-only (CONTRACTS:1106). Either have the CLI write it
   too, or record the exception in the ADR.

### B2. Docs staleness (fix, then hand the checklist to the user)
| Where | Problem |
|---|---|
| CLAUDE.md:24-25, README.md:43 | The CLI lists are missing `debrief`, `install` and `doctor`. README is also missing run, catalog, outcome and new-campaign. |
| README.md:56 | "Some commands are still being built" is stale. |
| CLAUDE.md:69, README.md:74, ARCHITECTURE.md:118-125 | The skills lists leave out `dms-quickstart` and `.claude/commands/dms.md`. |
| CLAUDE.md:6, README.md:13 | "Nothing flown" should become "headless-verified through v0.8; cockpit pending". |
| README.md:60-77, CLAUDE.md:58-71 | The repo maps are missing dms-arma, dms-tacview, dms-beamng, `tools/dcs_harness` and `arma/` (README is also missing dms-mcp). |
| ARCHITECTURE.md:85-101 | The module table leaves out the `flights`, `test` and `init` modules from the manifest. |
| ARCHITECTURE.md:182 | Says 1000 seeds; the specs use 50–200. |
| ARCHITECTURE.md:186, ADR 0009:17 | The smoke test is the single-player harness, not a dedicated-server scrape. |
| ADR 0005:16 | Says "pydantic return types", but the tools return `dict[str, Any]`. |
| packages/dms-mcp/README.md | "Approve it when asked", but it was rejected (finding 1). |

### B3. Headless dedicated server (blocked on the ED login)
`run_mission.py --mode server` already writes `serverSettings.lua` and calls
`net.start_server`. The missing piece is a login on the test profile.
1. **User, choose one:**
   - Run the harness with `--copy-login` yourself.
   - Start `DCS.exe -w DCS.dms_test` once and log in with "save password" ticked.
   - Install DCS_server and log in once.

   The credential stays in `Saved Games\...\network.vault`, never in the repo. Add
   `network.vault` to `.gitignore`.
2. **Harness:**
   - Server-mode write dir `DCS.dms_server`.
   - WebGUI off. Check the keys against DCS_server's defaults first.
   - A `PHASE server_running` check that fails fast on "login is required" with exit 2.
   - No accel in server mode.
   - Assert that `log_path` points at the server write dir.
3. **Tests:** dry-run and parser tests (the cmd line has `--server`, the `missionList` path is
   right, no secrets in the report).
4. **Verify:** one server run of viper m01. Pass = `reached_simulation`, `[DMS.TEST] DONE`,
   0 script errors and verdict `pass`. Then update ROADMAP v0.8.

---

## C. Arma: The Hill

**Why seeds 1–2 lose** (from the 2026-10-28 reports):
- Test-time compression stacks every enemy wave at once: 19–22 East against 7.
- Seed 1: the squad never moved to the LZ. LAMBS probably kept it in cover.
- Seed 2: an RCWS APC parked at 580 m shot the heli down. That is outside
  `exfilHotVehicleRadius` = 600 measured from the LZ, but inside its weapon range.

| # | Change | Effort |
|---|---|---|
| C1a | Fight-time floors in `fn_qrf.sqf:50/56/66`: 240 / 600 / 90 s. Normal play is unchanged. | S |
| C1b | Test-squad extraction: disable LAMBS on `DMS_squad` in the extraction phase (check the variable names in the kb), plus YELLOW, `doFollow` and a `move DMS_lz` fallback if the leader moves less than 30 m in 60 s. Add `currentWaypoint`, behaviour and destination to STATUS (`fn_testMode.sqf:62`). | S–M |
| C1c | `exfilHotVehicleRadius` 600 → 1200 (`fn_config.sqf:133`). Fix the README radii. | S |
| C1d | Only if still failing: remove one STATIC row (`fn_config.sqf:33`). | S |
| C1e | Refresh `packages/dms-arma/examples/the_hill.yaml` with `dms-arma import`. | S |

**Test gates** (run once the DCS queue is idle):

| Gate | Runs | Pass |
|---|---|---|
| A, vanilla, assist 180 | sites 1–3 × seeds {1,2}, 6 runs | at least 5/6 wins, 0 script errors |
| B, forced endings | `DMS_testForce=1/2` | both PASS |
| C, modded (`--mods core`) | 3 runs | at least 2/3 wins (report-only until C1b is proven) |
| D, realism | `--assist 0 --time-scale 100`, one run per site | report-only |

**C2. CI:** `rebuild` is already green, so the "waiting on CI" note is stale. Add these tests:
- `run_mission.py` argparse/params
- the batch-JSON verdict
- the kb class check across all 6 missions
- README ↔ `fn_config` radii, and that the `DMS_fnc_t` floors are present

Launching Arma stays local.

**C3. Playtest card** (after Gate A): Veteran, no crosshair, seeds 3 then 1. Check:
- feel: finding the outpost from the fuzzed marker, first contact
- mortars on `0-8`: about 85 s delay, danger-close refused inside 150 m
- the 8 s laptop hold action
- extraction: refused before intel, hot-LZ hold-off, boarding
- balance

Capture the `.rpt` `[DMS]` lines, 1–5 ratings and one immersion-breaker, and save them in
`docs/arma/playtests/YYYY-MM-DD.md`.

**C4. Generalise into a DMS backend** (gated on the playtest sign-off):

| WP | What | Depends on |
|---|---|---|
| WP0 | CONTRACTS Arma section and ADR 0012 update | — |
| WP1 | `backend: dcs\|arma` and neutral intent in `dms_core` schemas | WP0 |
| WP2 | `dms_arma/intent.py` mapping plus a `--strict` kb gate | WP1 |
| WP3 | `dms build` and `dms debrief` routing to Arma (`.rpt` outcomes) | WP2 |
| WP4 | The Hill rebuilt from intent is byte-equal to the hand config, then Gate A | WP3 |

---

## D. Cockpit sessions

Order: **S3 → S1 → S2**. w01 is the cheapest proof that the `.ogg` files play on a real sound
driver. Copy `dcs.log` before relaunching DCS, because DCS keeps only one old log.

### S3: Watch Dustoff w01 (~15 min, spectator)
`uv run dms run campaigns/dustoff-valley/missions/w01-dustoff-under-fire --install`.
Use F2/F6/F10/F11 and follow the `CAMERA:` hints.

| T+ | Expect |
|---|---|
| 0:08 | Ops clears Kestrel in, plus the LZ mark |
| ~2:00 | Technicals on the canal road, and a mark |
| ~3:45 | Venom strike, then BDA |
| 5–7 | "LZ is cold", Dustoff inbound |
| 8–10 | Dustoff on the ground for about 90 s |
| 12–14:30 | Ops: "clear of the valley", then the mission ends |

Ticks: voice heard on a real driver (v0.6), marks (v0.4), outcome (v0.5).

### S1: Viper m01 (ramp, voiced), debrief, m02 (air), debrief (~2 h)
**Before you start:** turn on the m01/m02 comms menu (finding 4), and tune UHF **251.0** for
Magic. Magic is the only voice on a set frequency; the others play to the whole coalition.
```
uv run dms doctor
uv run dms run campaigns/viper-detachment/missions/m01-broken-umbrella --install
# fly m01-broken-umbrella-ramp.miz, slot Python 1-1
uv run dms debrief campaigns/viper-detachment --mission m01
uv run dms run campaigns/viper-detachment/missions/m02-the-quarry --skip-voice --install
# predict first: intel>=2 -> ACTIVE SITE mark; sam_threat>=2 -> SAM warning
uv run dms debrief campaigns/viper-detachment --mission m02
```

**m01, what to expect:**
- T+0:10: the Ops radio check and the IP ARROW mark.
- Only the ZU-23s are visible on F10.
- Base traffic on the apron, with the C-130 departing and then arriving.
- Kneeboard page: 305.0 / 251.0 / 276.1, TCN 51Y.
- Magic at ARROW, then the window opens with the CYCLOPS circle.
- 80% chance of the pop-up SAM, and an ELINT warning before the SA-6.
- Red contact circles that go grey after 2 min.
- The window closes, then "Vul time. RTB", then the mission ends at "Copy on deck".

**Ticks:**
- v0.3: the core bundle loads.
- v0.4: plan, build, runtime F10 view, slice mission, `dms check`.
- v0.5: narrative, comms (menu only if turned on), briefing and kneeboard.
- v0.6: voice, embedded audio, shuffle-bag (partial), voiced mission.
- v0.7: director, difficulty, debriefer, and the next mission fitting the outcome.

### S2: Quickstart (~1 h)
In Claude Code, type
`/dms make me a mission: <airframe> <task> over <map>, voice on, $3 cap`, then fly the variant on
the fly card. Ticks: the v0.5 skills and premise → m01 flown, v0.6 voice-director, `install` and
`doctor`, and the quickstart skill.

### dcs.log checks after each session
```powershell
$L="$env:USERPROFILE\Saved Games\DCS\Logs\dcs.log"
Select-String $L '\[DMS\]\[Init\].*started: mission='
Select-String $L 'ERROR.*\[DMS|WARNING.*\[DMS|stack traceback|file not found|queue full'
Select-String $L '\[DMS\]\[Narrative\] (beat|mission finished)'
Select-String $L 'PLAY n='
Select-String $L '\[DMS\.OUTCOME\]'
```

**On failure, send back:**
- the miz and slot you flew, and the seed
- the first ERROR line plus 30 lines after it
- every `[DMS.OUTCOME]` line
- the PLAY lines around the problem
- the `[DMS][Comms] started` line
- the `[DMS][Intel]` lines, with an F10 screenshot if a mark was wrong

---

## E. v0.9 and v1.0

Everything below extends [NEXT.md](NEXT.md). These rules apply to every package:
- Write it in CONTRACTS first.
- Lua 5.1, `DMS.Clock` and `DMS.Bus` only.
- Every CLI feature goes in `dms_cli/cmd_<name>.py`, and only the lead edits `main.py`
  registration and `lua/manifest.txt`, at the end of each wave.

### Wave 1: contracts and ground truth (parallel)
- **C1 Contracts** (`docs/CONTRACTS.md` and the beats/mission/runtime/outcome schemas):
  - MP: beat `scope`, encounter `per_flight`, `comms.maxAgeSec`, `outcome.players[]`,
    `TestSettings.proxies[]`, `player.joined_late`.
  - State: `[DMS.STATE]` chunked lines, `DMS_CONFIG.resume`, and `snapshot()`/`restore()` on
    each module.
  - Variety: `Encounters.registerKind`, with kinds artillery, csar and ground_war, and a troops
    objective.
  - Tooling: `[DMS.PROBE]`, the nightly JSON, `dms status --json`, `dms debrief --acmi`.
- **Q1/Q2 CI:** pin StyLua and make luacheck blocking. Do this first, or rebase after the rest.
- **Q7 Probes** (`tools/dcs_harness/probes/**`): K1–K10. K9 is the longest `env.info` line
  that comes through intact. K10 is whether `net.get_player_list` works in the mission
  environment.
- **Q3 Nightly** (`tools/nightly.py`): a free-RAM gate, a lock shared with the Arma harness,
  and Tacview enable. This is the one package allowed to touch `run_mission.py`.

### Wave 2: parallel implementations (after C1)

| Package | Owns | What |
|---|---|---|
| MP-A | `narrative.lua` | per-flight fired sets, flight-aware coalition, late joiners |
| MP-B | `encounters.lua`, `spawner.lua` | per-flight encounters within budget, staggered MP spawns, `registerKind` |
| MP-C | `comms.lua`, new `players.lua`, `outcomes.py` | `players[]` in outcomes |
| MP-D | `test.lua`, new `test_proxies.py` | N proxies, check `mp_two_proxies` |
| P1-py | `dms_core/state.py`, `cmd_resume.py` | rebuild the resume config from the last `[DMS.STATE]`, through the lupa round-trip |
| U1 | `campaign_status.py`, `cmd_status.py`, `dms_mcp/ops.py` | `dms status` |
| G1 | `packages/dms-tacview/**`, `cmd_debrief_acmi.py` | ACMI facts into outcomes |
| U3 | `kneeboard_map.py` | deterministic map page drawn from `plan.json` |

### Wave 3
- **P1-lua:** `state.lua` plus snapshot/restore. Headless checks `resume_no_dup_beats` and
  `resume_no_dead_respawn`.
- **V5:** helo ops (`enc_csar.lua`, troops objective, dustoff missions).
- **V1:** artillery (`enc_artillery.lua`; killing the spotter stops the fire).
- **U5:** a last-sortie kneeboard page.
- **MP6:** dedicated-server smoke (needs B3).

### Wave 4: v1.0
- **V2:** ground war (`front_moves`, `no_stuck_groups`).
- **Viper m03 rework** onto V1/V2.
- **G4:** backend seam (`dms_core/backend.py`).
- **Q4:** the `DMS_SEEDS` env.
- **Q6:** eval scoring.

### Wave 5: the done gate
- Fly viper m01→m05+ with real debriefs and at least one branch taken.
- (flown) CHANGELOG entries.
- 7 green nightlies in a row.
- The CONTRACTS v1 freeze.

### DCS risks and what to do

**Persistence.** The mission environment has no `io` or `lfs`, so state goes out as
`[DMS.STATE]` log checkpoints and Python rebuilds the resume config.
- `dcs.log` rotates at every launch, so run `dms resume` before relaunching.
- Respawn survivors from the snapshot and pin `resume.seed`.
- Unit health is approximate, which is a known limitation.

**Multiplayer.**
- Key per-flight state by group name, not groupId (DCS reuses IDs), and read `getID()` fresh
  at every BIRTH.
- Dynamic slots create group names that aren't in the miz; treat them as new flights.
- Multicrew means 2 players per unit, so count facts by player name.
- On a server `world.getPlayer()` is nil, so use `coalition.getPlayers`.

**Needs a real flight to count as done:**
- MP: two clients, then two flights on a server.
- P1: one cockpit resume.
- V5: a helo landing in the cockpit.
- The kneeboard pages.
- K2–K4.
- The full campaign.
