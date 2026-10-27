# DMS: Dynamic Mission System for DCS World

**Start from a story and get a campaign of replayable, voiced DCS missions.**

You give DMS a premise, which can be historical, adapted, fictional or fantasy. It writes a story
bible and a campaign arc. Then it builds each mission as a `.miz` file with briefings, kneeboards,
dynamic enemy behaviour and voiced radio chatter. All of these react to what actually happens in
the cockpit, and no two plays are the same. Each mission is generated after you fly the previous
one, so the campaign follows your outcomes.

## Status

> **v0.3 (skeleton) is in progress on the `rebuild` branch. Nothing from the rebuild has been
> flown in DCS yet.**

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
uv run dms --help                   # validate | plan | voice | build | check | schema | bundle-lua
```

A typical mission build:

```bash
uv run dms validate campaigns/<slug>/missions/m01-<slug>/mission-spec.yaml
uv run dms plan     campaigns/<slug>/missions/m01-<slug>/mission-spec.yaml -o plan.json
uv run dms voice    campaigns/<slug>/missions/m01-<slug>/lines.yaml
uv run dms build    plan.json -o campaigns/<slug>/missions/m01-<slug>/out/m01.miz
uv run dms check    campaigns/<slug>/missions/m01-<slug>/out/m01.miz
```

For voice, copy `.env.example` to `.env` and set `ELEVENLABS_API_KEY`. Some commands are still
being built. See the roadmap.

## Repo map

| Path | What |
|---|---|
| `packages/dms-core` | pydantic schemas, `.miz` I/O (lupa round-trip), catalog |
| `packages/dms-gen` | `plan` and `build` (pydcs), Lua injection, kneeboard |
| `packages/dms-voice` | ElevenLabs, ffmpeg radio FX, cache |
| `packages/dms-cli` | The `dms` command |
| `lua/src/dms/` | Runtime modules (core, clock, rng, bus, registry, spawner, ...) |
| `lua/spec/`, `lua/mocks/` | Lua specs and the DCS mock with a fake clock |
| `lua/plugins/` | Optional pinned MOOSE, MIST and Skynet |
| `tools/` | `bundle_lua.py` and other dev tools |
| `data/catalog/` | Unit types, templates and mission types |
| `campaigns/` | Story-first campaign workspaces |
| `examples/`, `tests/fixtures/` | Sample missions and fixtures (`.miz` in LFS) |
| `.claude/skills/` | story-writer, campaign-planner, mission-designer, voice-director, debriefer, dms-build |
| `docs/` | Architecture, contracts, ADRs and references |
| `legacy/` | Pre-rebuild code and docs (read-only) |

## Docs

- [Architecture](docs/ARCHITECTURE.md), [interface contracts](docs/CONTRACTS.md) and
  [decision records](docs/adr/README.md)
- [DCS scripting gotchas](docs/reference/dcs-scripting-gotchas.md) and
  [.miz format](docs/reference/miz-format.md)
- [Roadmap](ROADMAP.md) and [changelog](CHANGELOG.md)
- [CLAUDE.md](CLAUDE.md), for working on this repo with Claude Code
