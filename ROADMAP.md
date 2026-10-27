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
- [ ] CI green on `rebuild` (Python job and Lua job)
- [ ] Docs reset: README, CLAUDE.md, ARCHITECTURE, ADRs and references *(written; awaiting review)*
- [ ] `dms_core` schemas (story, campaign, mission, beats, voice, plan, runtime, outcome) and JSON Schema export
- [ ] lupa miz I/O with byte-exact round-trip tests on all fixtures
- [ ] Lua core: core, clock, rng, bus and registry, with mocks and a fake clock
- [ ] Bundler `tools/bundle_lua.py` → `dist/dms.lua` (version-stamped, `luac -p` clean)
- [ ] `dms` CLI scaffold: `validate`, `schema`, `bundle-lua`, `check`
- [ ] Core bundle loads in DCS with no errors in `dcs.log` (flown)

## v0.4: Vertical slice
- [ ] Hand-written `mission-spec.yaml` → `dms plan` → `plan.json`
- [ ] `dms build` (pydcs) → `.miz` with `dms.lua` and `DMS_CONFIG` injected
- [ ] Runtime modules: spawner, ground, encounters and intel (fog of war via `hidden` + marks)
- [ ] `dms check`: IDs, slots, resources, config schema and `luac -p`
- [ ] Slice mission flown in DCS: spawns, routes, an ambush and marks all verified (flown)

## v0.5: Story pillar
- [ ] Skills: story-writer, campaign-planner and mission-designer
- [ ] Narrative module (storylets/beats, qualities, `[DMS.OUTCOME]`)
- [ ] Comms module (subtitle queue, F10 per-group menus)
- [ ] Briefing (5-paragraph order) and kneeboard generation
- [ ] A campaign authored end to end from a premise; mission 1 flown (flown)

## v0.6: Voice pillar
- [ ] `dms voice`: ElevenLabs v3 and Text-to-Dialogue, ffmpeg radio FX, sha256 cache
- [ ] Audio embedded in `l10n/DEFAULT/` with mapResource and a keeper trigger
- [ ] Beat-driven playback with shuffle-bag variants
- [ ] voice-director skill with a cost estimate
- [ ] Voiced mission flown with no overlapping or missing lines (flown)

## v0.7: Director and the campaign loop
- [ ] Director: per-flight intensity, BUILD_UP → PEAK → RELAX, spawn budget
- [ ] Hidden difficulty adaptation, clamped to ±1 tier
- [ ] Debriefer skill: `dcs.log` → outcomes, qualities and `continuity.md`
- [ ] Next mission generated to fit the previous outcome (flown, 2 consecutive missions)

## v0.8: Reach and evals
- [ ] MCP server (FastMCP, ~6 coarse tools) wrapping the CLI library
- [ ] Golden prompt eval suite (~30 premises/specs)
- [ ] Optional plugins: Skynet-IADS (+ MIST) and MOOSE, pinned
- [ ] Headless dedicated-server smoke test automation

## Arma 3 track ([plan](docs/arma/PLAN.md), [ADR 0012](docs/adr/0012-multiple-game-backends.md))
- [x] Research, knowledge base (`docs/arma/kb/`), MVP mission "The Hill" written
- [ ] Headless harness (`tools/arma_harness/`) + class/site verification in real Arma
- [ ] The Hill passes unattended test mode across 3+ seeds
- [ ] User playtest of The Hill (feel, comm menu, hold action, balance)
- [ ] Generalise into a DMS backend (spec → `fn_config.sqf`), only after The Hill plays well

