# Roadmap

The architecture is described in [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md). A box is ticked
only when it meets the **Definition of Done** below. "Implemented" isn't the same as "done".

## Definition of Done ([ADR 0009](docs/adr/0009-definition-of-done-requires-flight.md))

A feature is done when all of the following are true:

1. CI is green: ruff, ruff format, mypy, pytest (including the Lua specs via lupa), `luac -p`
   (Lua 5.1) and StyLua.
2. Tests cover the feature. For Lua, that means fake-clock scenarios across many seeds. For the
   generator, it means structural assertions on the built `.miz`.
3. **For runtime features:** a DCS smoke test passes (the mission loads, `dcs.log` shows no DMS
   errors, and the expected `[DMS]` lines appear), **and** a manual in-cockpit check passes.
4. The feature is recorded in [CHANGELOG.md](CHANGELOG.md) with **(flown)** where applicable.

## v0.3: Skeleton (in progress)
- [x] Restructure in place on `rebuild`: uv workspace, `legacy/`, Git LFS
- [x] Interface contracts (`docs/CONTRACTS.md`)
- [x] CI green on `rebuild` (Python job and Lua job) *(first run 2026-10-28; StyLua advisory)*
- [ ] Docs reset: README, CLAUDE.md, ARCHITECTURE, ADRs and references *(written; awaiting review)*
- [ ] `dms_core` schemas (story, campaign, mission, beats, voice, plan, runtime, outcome) and JSON Schema export *(implemented + tested)*
- [ ] lupa miz I/O with byte-exact round-trip tests on all fixtures *(implemented + tested)*
- [ ] Lua core: core, clock, rng, bus and registry, with mocks and a fake clock *(implemented + tested)*
- [ ] Bundler `tools/bundle_lua.py` → `dist/dms.lua` (version-stamped, `luac -p` clean) *(implemented + tested)*
- [ ] `dms` CLI scaffold: `validate`, `schema`, `bundle-lua`, `check` *(implemented + tested)*
- [ ] Core bundle loads in DCS with no errors in `dcs.log` (flown) *(headless DCS 2026-10-28: m01 test build passes end to end, 0 errors; cockpit check pending)*

## v0.4: Vertical slice
- [ ] Hand-written `mission-spec.yaml` → `dms plan` → `plan.json`
- [ ] `dms build` (pydcs) → `.miz` with `dms.lua` and `DMS_CONFIG` injected
- [ ] Runtime modules: spawner, ground, encounters and intel (fog of war via `hidden` + marks) *(tested on mocks; headless DCS 2026-10-29: f10_marks, fog_hidden, log_marks PASS on viper m01 x3, m02, m03 (circleToAll shapes listed by getMarkPanels); cockpit check of the F10 view pending)*
- [ ] `dms check`: IDs, slots, resources, config schema and `luac -p` *(implemented + tested, incl. config schema and beat reachability)*
- [ ] Slice mission flown in DCS: spawns, routes, an ambush and marks all verified (flown) *(headless DCS 2026-10-29: viper m01 and m02 pass every check, incl. marks; m03 failed outcome_end until the CAS proxy route fix (80f4266), re-run pending; cockpit unchecked)*

## v0.5: Story pillar
- [ ] Skills: story-writer, campaign-planner and mission-designer
- [ ] Narrative module (storylets/beats, qualities, `[DMS.OUTCOME]`) *(+ campaign flags, landed zone/place filters; tested on mocks)*
- [ ] Comms module (subtitle queue, F10 per-group menus)
- [ ] Briefing (5-paragraph order) and kneeboard generation *(embedded in the miz; conditional blocks + generated COMMS page; not viewed in DCS)*
- [ ] A campaign authored end to end from a premise; mission 1 flown (flown)

## v0.6: Voice pillar
- [ ] `dms voice`: ElevenLabs v3 and Text-to-Dialogue, ffmpeg radio FX, sha256 cache *(implemented + tested; viper m01 rendered for real, 101 clips; headless DCS 2026-10-29: all 20 played lines `file=*.ogg`, via=radio, no script errors; headless uses a dummy sound driver and a missing .ogg logs nothing, so not heard in DCS)*
- [ ] Audio embedded in `l10n/DEFAULT/` with mapResource and a keeper trigger *(structural tests on a built miz)*
- [ ] Beat-driven playback with shuffle-bag variants *(tested on mocks, 200 seeds; headless DCS 2026-10-29: radio_no_overlap, log_comms_overlap, spine_lines_played PASS on viper m01/m02/m03)*
- [ ] voice-director skill with a cost estimate *(implemented)*
- [ ] Voiced mission flown with no overlapping or missing lines (flown)

## v0.7: Director and the campaign loop
- [ ] Director: per-flight intensity, BUILD_UP → PEAK → RELAX, spawn budget *(hardened 2026-10-29; 37 specs × 50 seeds)*
- [ ] Hidden difficulty adaptation, clamped to ±1 tier *(tested on mocks)*
- [ ] Debriefer skill: `dcs.log` → outcomes, qualities and `continuity.md` *(`dms debrief` verified on a real headless DCS log, dry run; arc quality_effects applied by code; integration-tested)*
- [ ] Next mission generated to fit the previous outcome (flown, 2 consecutive missions) *(plan changes with outcome via qualities, flags and conditional briefings; integration-tested; not flown)*

## v0.8: Reach and evals
- [ ] MCP server (FastMCP, ~6 coarse tools) wrapping the CLI library *(stdio-tested with the mcp client; `.mcp.json` added; not yet loaded in a Claude Code session)*
- [ ] Golden prompt eval suite (~30 premises/specs) *(31 premises, 8 goldens green; first blind run p09 scored 63/63; viper 107/107 on a retro premise)*
- [ ] Optional plugins: Skynet-IADS (+ MIST) and MOOSE, pinned *(implemented + tested: MIST 4.5.126, Skynet 3.3.0, MOOSE 2.9.19 vendored, `plugins: [skynet]` spec field, Skynet adapter; not flown)*
- [ ] Headless dedicated-server smoke test automation *(single-player headless works end to end; server mode needs an ED login)*

## Few-prompt quickstart (north star: one-line premise → installed .miz)
- [ ] `dms-quickstart` skill: one batched question, then story → arc → mission → `dms run --install` → fly card *(dry-run end to end on an A-10C CAS premise; not flown)*
- [ ] `dms install` / `dms doctor` *(implemented + tested; doctor 14/14 OK on the dev machine)*
- [ ] Mission-quality lint in `dms validate` (26 rules, `dms_core.lint`) *(implemented + tested; all campaigns 0 errors)*

## Next (proposal)
What is left is planned in [docs/rebuild/PLAN.md](docs/rebuild/PLAN.md). See
[docs/rebuild/NEXT.md](docs/rebuild/NEXT.md) for v0.9/v1.0, and the groundwork packages
`dms-tacview`, `dms-beamng`, `dms-arma` (fixture/fake-tested only).

## Arma 3 track ([plan](docs/arma/PLAN.md), [ADR 0012](docs/adr/0012-multiple-game-backends.md))
- [x] Research, knowledge base (`docs/arma/kb/`), MVP mission "The Hill" written
- [ ] Headless harness (`tools/arma_harness/`) + class/site verification in real Arma *(works in engine; CI green on `rebuild`)*
- [ ] The Hill passes unattended test mode across 3+ seeds *(full win seen on seed 3, vanilla and modded; forced endings pass; seeds 1–2 lose real AI fights)*
- [ ] User playtest of The Hill (feel, comm menu, hold action, balance)
- [ ] Generalise into a DMS backend (spec → `fn_config.sqf`), only after The Hill plays well

## Ideas backlog (not scheduled) — see [docs/ideas/](docs/ideas/README.md)
- [ ] Tacview ACMI debriefs for DCS: richer outcomes and Director tuning ([idea](docs/ideas/tacview.md))
- [ ] BeamNG.drive backend: Tow Truck Shift or The Getaway MVP, BeamNGpy test loop ([idea](docs/ideas/beamng.md))

