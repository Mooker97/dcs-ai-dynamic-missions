# DMS Rebuild — Architecture Proposal

Status: **proposal, awaiting approval** · 2026-10-27

## Vision

Start from a story (historical, adapted, fictional, fantasy). Get a campaign of playable,
**replayable** DCS missions with briefings, kneeboards and voiced radio chatter that react to what
actually happens in the cockpit.

## Four pillars

| Pillar | What it is | Who does it |
|---|---|---|
| 1. Story | premise → story bible → campaign arc → mission beats | Claude agents/skills, writing schema-validated YAML |
| 2. Generator | MissionSpec → validated plan → `.miz` | Deterministic Python (pydcs builds, lupa edits) |
| 3. Runtime | dynamic, unpredictable, replayable behaviour in DCS | DMS Lua core (ours), driven by a generated config table |
| 4. Voice | beat lines → ElevenLabs → radio FX → `.ogg` in the `.miz` | Python stage, cached, plus Claude voice-director skill |

**Rule:** LLMs write *structured files*, and code compiles them. No step ever interprets prose.

## End-to-end pipeline

```
premise.md
  └─[story-writer]──────▶ bible.yaml        (setting, factions→DCS mapping, characters+voices, sources)
      └─[campaign-planner]▶ arc.yaml          (acts, missions, dramatic questions, qualities, branches)
          └─[mission-designer]▶ missions/mNN/{mission-spec.yaml, beats.yaml, briefing.md, lines.yaml}
              ├─ dms validate   → errors with suggested fixes (Claude repairs, ≤3 loops)
              ├─ dms plan       → plan.json (exact positions/types/IDs; seeded, reproducible)
              ├─ dms voice      → voice/radio/*.ogg (ElevenLabs v3/Dialogue + ffmpeg radio FX, cached)
              ├─ dms build      → out/mNN.miz  (pydcs + dms.lua bundle + DMS_CONFIG + audio + kneeboard)
              └─ dms check      → structural report (IDs, slots, resources, config schema, luac -p)
  fly it ─▶ dcs.log contains [DMS.OUTCOME] {json}
      └─[debriefer]──────▶ state/outcomes/mNN.yaml + qualities + continuity.md ─▶ next mission is written to fit
```

Each mission is generated **after** the previous one is flown. Branching costs nothing, and the
campaign reacts to what really happened.

## Randomness split

**Python decides the space of possibilities. Lua picks the instance each time you play.**

- **Python (seeded, inspectable, reproducible):** theater, time, weather, objectives, unit
  templates, loadouts, validated spawn zones (land, road-reachable), pool contents and weights, beat
  definitions, voice map, budgets. The seed is stored in the `.miz`.
- **Lua (unpredictable every play):** which pool members appear and where, timing jitter, director
  pacing, pop-up SAMs, reinforcement waves, which optional beats fire, hidden difficulty adaptation.

## Pillar 3: DMS Lua runtime (rebuilt, ours, tested)

The bundle is one `dms.lua` (concatenated in manifest order, version-stamped) plus a generated
`dms_config.lua` (`DMS_CONFIG = {...}`). It runs on the raw DCS API, and everything goes through
safe wrappers.

| # | Module | Responsibility |
|---|---|---|
| 1 | core | logger (`[Prefix]`, debug flag), `safeCall` (xpcall plus traceback), version banner |
| 2 | clock | the only scheduler: every callback is pcall-guarded and always re-arms; fake clock in tests |
| 3 | rng | entropy seeding, weighted pick, pickN, shuffle-bag (no repeats), jitter |
| 4 | bus | DCS events → typed events (`unit.dead` deduplicated across DEAD/UNIT_LOST/KILL, `player.spawned` via BIRTH, `zone.entered`) |
| 5 | registry | central name/ID allocation, live-group tracking, unit budgets |
| 6 | spawner | template + zone → `coalition.addGroup`; surface/LOS/distance-from-player checks; 1 s delay before tasking |
| 7 | ground | correct routes (≥2 points), StopRoute/resume, FireAtPoint, ROE/alarm by domain, hunt/intercept, stuck watchdog |
| 8 | director | per-flight intensity, BUILD_UP → PEAK → RELAX, spawn budget per minute, hidden difficulty |
| 9 | encounters | pool, ambush_sam, waves, hunt, convoy, cap; triggered by proximity, beat, director or time |
| 10 | narrative | storylet/beat engine: preconditions on qualities/flags/events, priority, cooldowns, effects, `[DMS.OUTCOME]` |
| 11 | comms | voice + subtitle queue (no overlap), per-group sound, radioTransmission, F10 per-group menus |
| 12 | intel | fog of war = spawn-time `hidden` + F10 marks on detection (stale/refresh), BDA |

**Fog of war, honestly.** DCS can't hide or reveal units at runtime. Enemies spawn with `hidden`
and become visible as F10 marks when they are detected. The mission map option is set to "Fog of War".

**Optional plugins** (loaded before `dms.lua` when the spec asks for them): Skynet-IADS (needs
MIST), MOOSE (for CTLD/CSAR/ATIS/EasyGCICAP), each a pinned version. The core never depends on them.

**Old library:** the 72 modules (now compile-clean after today's fixes) are kept in `legacy/` as
reference. Their behaviours are ported module by module into the 12 above, with tests.

## Pillar 1: Story (Claude Code skills/agents)

| Agent / skill | Input → output |
|---|---|
| story-writer | premise (+ interview, + web research for historical) → `bible.yaml` with `mode: historical / adapted / fictional`, cited claims, faction→DCS mapping, character voice profiles |
| campaign-planner | bible → `arc.yaml` (5–8 missions, dramatic questions, qualities, branches) |
| mission-designer | arc entry + state → `mission-spec.yaml`, `beats.yaml`, `briefing.md` (5-paragraph order + intel narrative), `lines.yaml` |
| voice-director | lines → render plan + cost estimate → `dms voice` |
| debriefer | dcs.log / questionnaire → outcomes, qualities, `continuity.md` |

Files are the memory: the bible, arc and continuity ledger are canonical, and agents read them
instead of remembering.

## Pillar 4: Voice

- Line catalog keyed by **beat**, 3–5 variants each (shuffle-bag at runtime).
- Each character has a voice profile (ElevenLabs voice id or Voice Design v3 prompt, brevity rules).
- Eleven v3 with audio tags, and Text-to-Dialogue for overheard exchanges.
- ffmpeg radio FX (300–3400 Hz band-pass, compression, squelch tail) → `.ogg`.
- Cache key `sha256(voice, model, text, fx)`. Files embedded in `l10n/DEFAULT/` + mapResource + a
  keeper trigger.

## Pillar 2: Generator

- **Build new missions:** pydcs 1.0.0, pinned exactly. Verified today: generates a Syria mission
  with an AH-64 client slot, convoy waypoints, zones and DO SCRIPT FILE.
- **Edit existing missions:** lupa (real Lua) parse → dict → deterministic serializer. Verified
  lossless on all 5 test missions. Never use pydcs load/save on user missions: it failed on 2 of 5
  and lost data on the other 3.
- **Schemas:** pydantic v2. MissionSpec (LLM-facing, declarative) → BuildPlan (exact).
- **Grounding tools:** `find_airbase`, `list_units(era, coalition, role)`, `list_loadouts` from
  pydcs data, so the LLM chooses areas and roles and Python chooses coordinates and types.
- **Interface:** `dms` CLI (typer) + Claude Code skills first. An MCP server (FastMCP, ~6 coarse
  tools) is a thin wrapper added later.

## Repo layout

```
dms/                         (own top-level repo, moved out of the Next.js folder)
  pyproject.toml             uv workspace root; ruff, mypy, pytest config
  packages/
    dms-core/   src/dms_core/    schemas (pydantic), miz io (zip + lupa dict round-trip), catalog
    dms-gen/    src/dms_gen/     plan + build (pydcs), Lua injection, kneeboard
    dms-voice/  src/dms_voice/   ElevenLabs, ffmpeg FX, cache
    dms-cli/    src/dms_cli/     `dms` command
    dms-mcp/    src/dms_mcp/     MCP wrapper (later)
  lua/
    src/dms/*.lua  manifest.txt  spec/*_spec.lua (busted)  mocks/dcs.lua (fake clock)
    plugins/ (pinned MOOSE, MIST, Skynet: optional)
  data/catalog/              unit types, group templates, mission types (migrated YAML)
  campaigns/<slug>/          story-first workspaces (bible, arc, missions, state)
  examples/                  dustoff-corridor, dawn-scout, desert-scout
  tests/fixtures/            .miz inputs (Git LFS), prompts, golden specs
  tools/bundle_lua.py
  .claude/skills/            story-writer, campaign-planner, mission-designer, voice-director, debriefer, dms-build
  docs/ARCHITECTURE.md  docs/adr/  docs/reference/dcs-scripting-gotchas.md
  README.md  CHANGELOG.md  ROADMAP.md  CLAUDE.md (short)
  legacy/                    old code, read-only reference
```

## Quality gates (Definition of Done)

- CI: ruff + mypy + pytest; luac 5.1 syntax check + busted (fake clock, 1000-seed scenario runs) + StyLua.
- Golden prompt suite: ~30 premises/specs with structural assertions on the built `.miz`.
- A runtime feature is **done** only after a DCS smoke test (headless dedicated-server log scrape
  where possible) **and** a manual in-cockpit check. Nothing is marked ✅ on the strength of code
  alone.

## Roadmap

| Version | Delivers |
|---|---|
| v0.3 | Skeleton: repo move, uv workspace, CI, lupa miz-io, Lua core (core/clock/rng/bus/registry), bundler, docs reset |
| v0.4 | Vertical slice: hand-written spec → pydcs → `.miz` with `dms.lua` (spawner, ground, encounters, intel) → flies in DCS |
| v0.5 | Story pillar: story-writer, campaign-planner and mission-designer skills; narrative + comms modules; briefing/kneeboard |
| v0.6 | Voice pillar: voice stage, radio FX, embedded audio, beat-driven playback |
| v0.7 | Director + adaptive difficulty; debriefer + outcome-driven next mission |
| v0.8 | MCP server; golden prompt evals; optional Skynet/MOOSE plugins |
