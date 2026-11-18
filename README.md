# DMS: Dynamic Mission System for DCS World

**Start from a story and get a campaign of replayable, voiced DCS missions.**

You give DMS a premise, which can be historical, adapted, fictional or fantasy. It writes a story
bible and a campaign arc. Then it builds each mission as a `.miz` file with briefings, kneeboards,
dynamic enemy behaviour and voiced radio chatter. All of these react to what actually happens in
the cockpit, and no two plays are the same. Each mission is generated after you fly the previous
one, so the campaign follows your outcomes.

## Status

> **The rebuild (on the `rebuild` branch) is headless-verified through v0.8; cockpit checks are
> pending.** Missions run unattended in real DCS via `tools/dcs_harness`, but nothing from the
> rebuild has been flown in the cockpit yet.

The pre-rebuild code (a Lua script library, regex `.miz` editing and ElevenLabs experiments) is in
`legacy/` for reference. Reviewing it in October 2026 showed that "complete" had not meant "works in
DCS". So under the current rules, a feature is done only after it has been flown
([ADR 0009](docs/adr/0009-definition-of-done-requires-flight.md)). [ROADMAP.md](ROADMAP.md) shows
progress.

## Four pillars

| Pillar | What it does | How |
|---|---|---|
| **Story** | premise → bible → campaign arc → mission beats | Claude Code skills write schema-validated YAML |
| **Generator** | MissionSpec → BuildPlan → `.miz` | Deterministic Python: pydcs to build, lupa to edit |
| **Runtime** | Dynamic, unpredictable, replayable behaviour in DCS | DMS Lua core on the raw DCS API, driven by a generated config |
| **Voice** | Beat lines → ElevenLabs → radio FX → `.ogg` in the mission | Cached Python stage |

**The rule:** LLMs write structured files, and code compiles them. No step interprets prose.

## Quickstart

You need Python ≥3.11, [uv](https://docs.astral.sh/uv/), Git LFS, and DCS World for flight
testing. `ffmpeg` and an ElevenLabs key are needed only for voice.

```bash
git lfs install && git lfs pull
uv sync --all-packages              # install every workspace package plus dev tools
uv run pytest                       # Python tests and Lua specs (Lua 5.1 via lupa)
uv run python tools/bundle_lua.py   # build dist/dms.lua from lua/src in manifest order
uv run dms --help                   # validate | plan | voice | build | check | run | schema | bundle-lua
                                    # | install | doctor | outcome | debrief | new-campaign | catalog
```

A typical mission build:

```bash
uv run dms validate campaigns/<slug>/missions/m01-<slug>/mission-spec.yaml
uv run dms plan     campaigns/<slug>/missions/m01-<slug>/mission-spec.yaml -o plan.json
uv run dms voice    campaigns/<slug>/missions/m01-<slug>/lines.yaml
uv run dms build    plan.json -o campaigns/<slug>/missions/m01-<slug>/out/m01.miz
uv run dms check    campaigns/<slug>/missions/m01-<slug>/out/m01.miz
```

Or do all of that in one step with `uv run dms run <mission-dir>` (add `--install` to copy the
`.miz` into Saved Games). `uv run dms doctor` checks the toolchain, and after a flight
`uv run dms debrief` turns `dcs.log` into campaign state.

For voice, copy `.env.example` to `.env` and set `ELEVENLABS_API_KEY`.

## Repo map

| Path | What |
|---|---|
| `packages/dms-core` | pydantic schemas, `.miz` I/O (lupa round-trip), catalog |
| `packages/dms-gen` | `plan` and `build` (pydcs), Lua injection, kneeboard |
| `packages/dms-voice` | ElevenLabs, ffmpeg radio FX, cache |
| `packages/dms-cli` | The `dms` command |
| `packages/dms-mcp` | `dms-mcp` FastMCP stdio server (6 tools over core/gen) |
| `packages/dms-arma` | Arma 3 backend: mission spec → `fn_config.sqf` |
| `packages/dms-tacview` | Tacview ACMI parser, flight summary and debrief facts |
| `packages/dms-beamng` | BeamNG.drive backend: driving-mission spec → scenario plan |
| `lua/src/dms/` | Runtime modules (core, clock, rng, bus, registry, spawner, ...) |
| `lua/spec/`, `lua/mocks/` | Lua specs and the DCS mock with a fake clock |
| `lua/plugins/` | Optional pinned MOOSE, MIST and Skynet |
| `tools/` | `bundle_lua.py`, `dcs_harness/` (unattended real-DCS runs), `arma_harness/` |
| `data/catalog/` | Unit types, templates and mission types |
| `campaigns/` | Story-first campaign workspaces |
| `examples/`, `tests/fixtures/` | Sample missions and fixtures (`.miz` in LFS) |
| `.claude/skills/` | dms-quickstart, story-writer, campaign-planner, mission-designer, voice-director, debriefer, dms-build |
| `.claude/commands/dms.md` | `/dms` mode for building or editing missions |
| `arma/` | Arma 3 missions, modules and tools |
| `docs/` | Architecture, contracts, ADRs and references |
| `legacy/` | Pre-rebuild code and docs (read-only) |

## Docs

- [Architecture](docs/ARCHITECTURE.md), [interface contracts](docs/CONTRACTS.md) and
  [decision records](docs/adr/README.md)
- [DCS scripting gotchas](docs/reference/dcs-scripting-gotchas.md) and
  [.miz format](docs/reference/miz-format.md)
- [Roadmap](ROADMAP.md) and [changelog](CHANGELOG.md)
- [CLAUDE.md](CLAUDE.md), for working on this repo with Claude Code
