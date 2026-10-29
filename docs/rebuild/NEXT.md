# Beyond v0.8: a proposal for v0.9 and v1.0

Status: **proposal**, 2026-10-29. Not approved. Nothing here is scheduled until it is moved onto
[ROADMAP.md](../../ROADMAP.md). It reflects the `rebuild` branch as of today, including this
session's uncommitted work: director hardening, the real ElevenLabs render, intel marks and test
checks, the campaign loop with arc `quality_effects`, campaign flags and conditional briefings, the
MCP stdio test, and pinned MIST/MOOSE/Skynet.

Legend. **Effort:** S is under a day, M is 1–3 days, L is a week or more. **Test tier** (per the
headless-testing rule): *mock* (Lua specs on `lua/mocks/dcs.lua` with the fake clock), *structural*
(pytest on a built `.miz` or plan), *headless* (`tools/dcs_harness/run_mission.py` in real DCS, no
human), *manual* (cockpit). A claim is only as strong as its tier.

## 1. What "v1.0 done" should mean

v1.0 is not "every feature exists". It is **one campaign that a person can play from premise to
finale without a developer at the keyboard**, with every runtime feature it uses meeting the
[DoD](../adr/0009-definition-of-done-requires-flight.md). Concretely:

1. **A full campaign is flown.** `viper-detachment` (m01–m04 exist under
   `campaigns/viper-detachment/missions/`), or a successor, goes through 5+ missions. Each mission is
   designed after the previous debrief (`dms debrief`, `dms_core/outcomes.py`). At least one arc
   branch is taken for real, and the qualities visibly change a later briefing (via
   `dms_gen/builder/conditional.py`).
2. **Every runtime module is (flown).** All 13 modules in `lua/src/dms/` have a CHANGELOG entry
   tagged (flown). Every **[?]** in `docs/reference/dcs-scripting-gotchas.md` is either resolved or
   recorded as a known limitation (section 8).
3. **Two-player co-op works.** Two clients in one flight, and two flights on a dedicated server, each
   get their own menus, comms and director pacing (section 2).
4. **One-command reproducibility.** `uv sync` → `dms run <mission>` → a flyable `.miz`, on a clean
   machine, with voice either cached or `--offline`. CI is fully blocking, and a nightly headless
   soak is green for 7 consecutive nights (section 6).
5. **The contracts are frozen.** `docs/CONTRACTS.md` gets a v1 tag, schema `schema_version: 1` is
   promised stable, and further breaking changes need a migration in `dms validate`.

Explicitly **not** v1.0: Arma and BeamNG backends, PvP, and cross-session persistence beyond
checkpoint/resume. Those are v1.x.

## 2. Multiplayer

**What already works (code, mostly mock tier):**

| Area | Where | Tier |
|---|---|---|
| Director state per flight (keyed by player group), orphan flights, `player.left` grace | `lua/src/dms/director.lua:67-178` | mock (200 seeds) |
| F10 menus per group, rebuilt on BIRTH, removed via `removeItemForGroup` | `lua/src/dms/comms.lua:535-609` | mock, headless SP |
| Text and sound per group (`outTextForGroup`, `outSoundForGroup`), group transmitter 50 m above the player | `lua/src/dms/comms.lua:136-231` | mock |
| Intel marks per group, with a stable handle | `lua/src/dms/intel.lua:345-430`, CONTRACTS l.150 | mock, headless SP |
| `slot: client` flights | `dms_core/schemas/mission.py:157`, CONTRACTS l.631 | structural |
| Server harness mode (`--mode server`, `net.start_server`) | `tools/dcs_harness/run_mission.py:20,605,758` | blocked: needs an ED login in the write dir |

**Gaps:**

| # | Gap | Value | Effort | Deps | Test tier |
|---|---|---|---|---|---|
| MP1 | Narrative is **mission-global**. `N._s.fired` (`narrative.lua:62`) and `playerCoalition()` (`narrative.lua:37`, defaulting to blue) mean the first flight to trip a beat consumes it for everyone. Add beat `scope: mission\|flight`, with per-flight fired sets and the flight carried in the payload. | High | M | CONTRACTS beats section | mock: two flights through the same zone, each gets the beat once |
| MP2 | Encounters trigger once per mission (`encounters.lua:1040-1046`, `st.done`). Add `per_flight: true` so a late joiner gets their own ambush, within the director budget. | Med | M | MP1 | mock, 200 seeds |
| MP3 | Spawns aren't staggered. The gotchas say "stagger 1–3 s in MP". Add a `DMS.Clock` spawn queue in `spawner.lua` when `#players > 1`. | Med | S | – | mock: assert spacing |
| MP4 | The outcome is per mission, with no per-player facts. Add `players[]` (name, flight, kills, death or eject) to the final `[DMS.OUTCOME]`, and `dms debrief` keeps it. | Med | S | – | mock, plus a structural parse test |
| MP5 | `DMS.Test` has a single proxy (`test.lua:214-280`). Allow N proxies (one per client flight) so MP logic runs headless in SP mode without an ED login. | **High** (unlocks MP testing) | M | – | headless SP with 2 AI proxies |
| MP6 | Dedicated-server smoke. Do the one-time ED login into `DCS.dms_test/Config/network.vault` (user action), then run `--mode server`. Proves hooks, `net.*` and slot behaviour. | Med | S (+ user) | user login | headless server |
| MP7 | Join in progress. A client that spawns at T+30 min should get the menus and the current briefing state, and no backlog of stale comms. Comms needs a "drop if older than N s" rule for per-group queues. | Med | S | MP1 | mock |
| MP8 | SRS awareness. Many MP groups use SRS rather than in-game radio, and `radioTransmission` is not heard on SRS [?]. Option: an opt-in MOOSE `MSRS` adapter in `lua/plugins/adapters/`. | Low–Med | M | MOOSE pin | manual |

PvP (two player coalitions with mirrored directors) is out of scope until v1.x. Today
`playerCoalition()` in narrative, intel and comms assumes one coalition.

## 3. Persistence within a mission, across sessions

The problem: a 2-hour server mission restarts, and everything is lost. Under sanitisation the
mission environment has no `io`, `os` or `lfs` (gotchas, "Language and sandbox").

| Option | How | Value | Effort | Risk |
|---|---|---|---|---|
| **P1. Log checkpoints plus rebuild (recommended first)** | A new `DMS.State` module emits `[DMS.STATE] {json}` every N min and at every beat: fired beats, qualities, flags, dead group names, encounter `st`, director tiers. `dms resume <mission> [--log]` (in `dms_core/outcomes.py`, which already parses sessions) bakes the last snapshot into `DMS_CONFIG.resume`. On start, the modules skip fired beats and don't respawn dead groups. | High | M | Needs a rebuild between sessions. Positions of moving units are approximate. |
| P2. Server hook bridge | `Saved Games/DCS/Scripts/Hooks/dms_hook.lua` (GUI env, which has `io`) polls `net.dostring_in('mission', 'return DMS.State.json()')` and writes `~/.dms/state/<mission>.json`. On load it pushes the state back in. Builds on `tools/dcs_harness/hook_template.lua`. | High for servers | M | Whether `net.dostring_in` into `mission` is still allowed in 2.9 [?]. Needs an install step. |
| P3. Opt-in de-sanitised `io` | `DMS_CONFIG.persist.io = true`: the module writes directly if `io` exists, and otherwise falls back to P1. | Low | S | Security. Never required (gotchas, "Persistence" item 4). |
| P4. DCS-gRPC | External state queries (RESEARCH-NOTES l.155). | Low | L | Adds a dependency. |

Order: **P1** (pure DMS, works SP and MP, testable on mocks), then **P2** for the dedicated
server. Test: mock (snapshot → resume round-trip, 200 seeds), then headless (run m02 for 10 min,
kill DCS, `dms resume`, rerun, and assert no duplicate beats or spawns of dead groups via
`[DMS]` lines).

## 4. Mission variety

The current encounter kinds are `pool, hunt, waves, ambush_sam, convoy, cap`
(`encounters.lua:386-1033`; schema `mission.py:338`). The spawner already maps SHIP and HELICOPTER
categories (`spawner.lua:23-35`).

| # | Item | Value | Effort | Deps | Test tier |
|---|---|---|---|---|---|
| V1 | `artillery` encounter: red tubes `FireAtPoint` (already in `ground.lua`) near friendlies or the player's FARP, with a spotter that can be killed to stop it. | Med | S | – | mock, headless |
| V2 | `ground_war` encounter: two-sided frontline. Blue and red groups route at each other (`ground.lua` hunt/intercept), the director feeds reinforcements, and the "front" position becomes an outcome fact. Gives CAS missions (viper m03 "troops in contact") real stakes. | High | L | budgets, the stuck watchdog in ground.lua | mock, headless (front moves, no stuck groups) |
| V3 | `intercept` encounter: bombers or cruise missiles inbound on a target, with a time-to-impact the comms announce. | Med | M | cap code paths | mock, headless |
| V4 | Naval: `ship` templates in `data/catalog/`, ship routes, and an `anti_ship` objective. Later, a Supercarrier recovery beat. | Med | M | catalog, planner `terrain: water` (mission.py:97) | structural, headless |
| V5 | Helo ops: LZ objectives (`land` already exists in objective kinds, mission.py:272), troop pickup/drop as a beat on a landed-in-zone event, and `csar` (a downed pilot spawned on an ejection or a beat). `campaigns/dustoff-valley` is the test bed. Sling-load and CTLD go through a MOOSE adapter (none exists in `lua/plugins/adapters/` yet, only `skynet_adapter.lua`). | High (second campaign) | M (native), L (CTLD) | MOOSE adapter for CTLD | mock, headless with a helo proxy, manual |
| V6 | SEAD package: friendly AI escorts and strikers whose fate the player influences, as outcome facts. | Med | M | – | headless |

Recommended: V5 native (unblocks dustoff-valley), then V2, V1, V3, V4.

## 5. Campaign UX

| # | Item | Value | Effort | Deps | Test tier |
|---|---|---|---|---|---|
| U1 | `dms status <campaign> [--json]`. A CLI wrapper over `dms_mcp/ops.py:599 campaign_status` (move it into `dms_core` so the CLI doesn't import MCP). Shows missions, flown/next, qualities, flags, last check, and last outcome. | High | S | – | structural (pytest on `campaigns/_template`) |
| U2 | `dms status --html` → one static page (arc graph with the branch taken, quality history, per-mission outcome). Publishable as an artifact. | Med | M | U1, outcomes history | structural |
| U3 | Kneeboard **map** page. `builder/kneeboard.py` renders text only. Add a Pillow page drawn from `plan.json` (areas, route/steerpoints, known threats with ring radii, bullseye) on a plain grid. No map tiles, because of licensing and determinism. | High (cockpit usefulness) | M | – | structural (deterministic PNG hash), manual view |
| U4 | Briefing images (mission editor briefing pictures) reusing the U3 renderer. The miz keys are unverified [?]. | Med | S | U3, a check against a ME-saved fixture | structural |
| U5 | Debrief kneeboard: after `dms debrief`, the next mission's kneeboard includes "last sortie" facts. | Med | S | U3 | structural |

## 6. Quality and test infrastructure

| # | Item | Value | Effort | Test tier |
|---|---|---|---|---|
| Q1 | StyLua is already blocking (`.github/workflows/ci.yml`, "Blocking" comment); CHANGELOG line ~80 still says "advisory", so fix the doc. Pin `version:` to an exact StyLua release instead of `latest`, so a release can't redden CI overnight. | Med | S | CI |
| Q2 | Make luacheck blocking (remove `continue-on-error`) once `lua/src` is clean. | Med | S | CI |
| Q3 | **Nightly headless soak on this machine.** `tools/nightly.py` runs, for every mission under `campaigns/*/missions/`: `dms build --test --seed {1,2,3}` → `run_mission.py --accel 16` → a JSON and Markdown report in `~/.dms/nightly/<date>/`, with exit codes. Windows Task Scheduler at 03:00. Respect `--min-free-gb 12` (Syria OOM in the memory notes), one game at a time, and a lock file shared with the Arma harness. CI cannot run DCS (Windows, 100+ GB, license). A self-hosted GH runner is possible later but exposes the machine. | **High** | M | headless |
| Q4 | More seeds: lift the 200-seed specs (`director_spec`, `ambient_spec:337`, cap, ground) to 1000 as ARCHITECTURE promises, behind a `DMS_SEEDS` env so CI stays fast and the nightly runs 1000. | Med | S | mock |
| Q5 | Contract drift test: assert every `DMS_CONFIG` key the Lua reads appears in `RuntimeConfig` (`schemas/runtime.py`), by grepping `cfg().<key>` in `lua/src`. `lua/spec/contract_spec.lua` covers part of this already. | Med | S | mock, structural |
| Q6 | Eval scoring with a real LLM-generated campaign (`evals/run.py --score`; ROADMAP v0.8 says none has been scored yet). The blind eval being started now feeds this. | High | M | – | structural |
| Q7 | Probe missions for the DCS unknowns (section 8): `tools/dcs_harness/probes/` with tiny generated `.miz` files that log `[DMS.PROBE] key=value`, run by the nightly. | High | M | headless |

## 7. Game-backend track and Tacview

Other agents are starting the Tacview, BeamNG and Arma-backend packages now. These are
recommendations on **ordering**, not designs.

| # | Item | Value | Effort | Deps | Test tier |
|---|---|---|---|---|---|
| G1 | **Tacview ACMI** (`docs/ideas/tacview.md`). Feeds the DCS loop directly: richer outcomes for `dms debrief`, and geometry assertions for headless tests ("hunt got within 2 km"). Do it first. Open [?]s: whether Tacview recording must be enabled in DCS Special options, and whether the free tier is enough. Verify headless by enabling the exporter in the harness write dir. | High | M | – | structural (parse a fixture ACMI), headless (harness run produces an ACMI) |
| G2 | Arma backend. Per `docs/arma/PLAN.md`, generalise only after The Hill passes 3+ seeds **and** the user playtests it. Today seeds 1–2 lose real fights (ROADMAP Arma track). Keep it gated on that playtest. | Med | L | user playtest | headless (`tools/arma_harness`) |
| G3 | BeamNG backend. `docs/beamng/FEASIBILITY.md`: use the built-in MCP server in 0.40 (`enableMcp`, `:29292`), not BeamNGpy (techCore isn't shipped). MVP "The Getaway" on the stock `evade` type. The game needs its Steam update to 0.40.3 first. | Med | L | ADR 0012 backend seam | headless via MCP |
| G4 | Backend seam. Before G2 and G3 diverge, extract the backend-neutral parts (director tiers, seeded pools, beats, outcome schema) into a documented interface in CONTRACTS, so the three backends share `outcome.py` and the debriefer. | High | M | ADR 0012 | structural |

Order: G1 → G4 → G2 (once playtested) → G3. Tacview strengthens the core product. The other
backends spread it out.

## 8. Risks and known DCS unknowns

Every **[?]** in `docs/reference/dcs-scripting-gotchas.md`, plus one unproven suspicion, with a
headless verification. Each probe is a generated `.miz` under Q7 that logs `[DMS.PROBE]` lines, and
the nightly asserts on them.

| # | Unknown (gotchas section) | Headless probe | Can headless settle it? |
|---|---|---|---|
| K1 | Ground routes need ≥2 points with the **current position first** ("Ground AI") | Spawn 4 identical groups and give each one a route variant: 1 point, 2 points without the current position, 2 points with it, and on/off road. After 120 s, log the distance moved and `getController():hasTask()`. | Yes |
| K2 | `world.getMarkPanels()` lists only `markTo*` panels, not `circleToAll`/`textToAll` shapes; script marks have `initiator == nil` ("F10 map") | Create one of each mark type, then log `#getMarkPanels()` and each panel's `idx`, `initiator` and `text`. The player-mark half (a human's initiator) needs a client. The proxy can't place marks, so that half stays manual. | Script half yes, player half manual |
| K3 | `radioTransmission` has a newer **subtitle parameter** ("Menus and sound") | `pcall` the call with 7 args and again with extra subtitle/duration args. Log ok/err, and whether a `S_EVENT_*` or message-log entry appears. Whether the subtitle is shown needs rendering. | Partly. Arity yes, display manual |
| K4 | `radioTransmission` range model and **per-receiver LOS** ("Menus and sound") | No headless receiver of audio exists. Proxy: check whether DCS's own radio-message log entries or the AI comms menu react. Likely **manual**: two client aircraft tuned to the frequency, one behind a ridge. Mitigation: keep the 10 km / 50 m placement in `comms.lua:146-231` and fall back to `outSoundForGroup` when unsure. | No, so manual |
| K5 | RNG seeding from the sub-second fraction of `timer.getTime()` at first BIRTH ("RNG") | Run the same `.miz` 5 times headless, logging `Rng.seed()`'s effective seed and the first 5 picks. **Risk:** a scripted headless start may hit BIRTH at an identical `getTime()` each run, which would give identical seeds. If so, mix `timer.getAbsTime()` and the `os`-free entropy of `world.getAirbases()` ordering or frame count. | Yes, and it tests the risk directly |
| K6 | First runs scheduled at exactly `timer.getTime()` never fire ("Timers", suspected, not proven) | Schedule callbacks at `+0`, `+0.01`, `+0.05` and `+1` during mission start, and log which fire. Raw `timer.scheduleFunction` in a probe only, never in `lua/src` (hard rule 3). | Yes |
| K7 | `net.dostring_in('mission', ...)` from a hook still works in 2.9 (needed for P2) | The harness hook runs it and logs the result. | Yes (SP hook env) |
| K8 | Tacview exporter is on in an isolated write dir (G1) | Enable it in the harness `Config/options.lua`, and assert an ACMI appears in `Documents/Tacview` [?]. | Yes |

Other risks: **ED patches** break scripting silently, so the nightly catches regressions within a
day. **ElevenLabs cost and drift**: the cache (`dms_voice/cache.py`) pins renders, and `--offline`
keeps builds possible. **pydcs lag** behind new DCS modules: pin exactly and test the catalog
against the installed DCS in the nightly. **Memory** (Syria OOM): one game at a time, enforced by
the nightly lock.

## 9. Recommended order

**v0.9: "Prove it, then share it"** (in this order, with parallel fan-out where marked ∥)

1. Q7 probes + K1–K7 ∥ Q3 nightly ∥ Q1/Q2 CI tightening. Ground truth first.
2. MP5 multi-proxy test ∥ U1 `dms status` ∥ G1 Tacview parser.
3. MP1 per-flight narrative → MP2, MP3, MP4, MP7. Then MP6 once the user has logged in.
4. P1 checkpoint/resume.
5. U3 kneeboard map ∥ V5 helo ops (dustoff-valley m01 flown).

**v1.0: "A campaign, flown"**

6. V2 ground war ∥ V1 artillery. Viper m03 is reworked on top of them.
7. Viper-detachment flown m01→m05+ with real debriefs and one branch taken. Every module (flown).
8. G4 backend seam, CONTRACTS v1 freeze, docs pass, and 7 green nightlies. Tag `v1.0`.

**v1.x:** P2 server hook, MP8 SRS, V3/V4/V6, U2 dashboard, G2 Arma backend, G3 BeamNG, PvP.
