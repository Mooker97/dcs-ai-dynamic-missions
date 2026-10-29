# CLAUDE.md

DMS turns a story premise into a campaign of replayable, voiced DCS World missions (`.miz`).
It has three parts: a Python generator (uv workspace), a Lua 5.1 runtime, and Claude Code skills for the story.

Status: on the `rebuild` branch, headless-verified through v0.8; cockpit checks pending. Nothing from
the rebuild has been flown in the cockpit yet, so report it as "implemented, not flown".

## Working style

- The user wants work completed as quickly as possible, so use parallel processes wherever possible.
- For big tasks, fan out subagents to work concurrently on independent paths: packages, Lua modules, docs.
  Give each one explicit owned paths so they don't collide.
- `docs/CONTRACTS.md` is the shared interface. Change it there first, then change the code.

## Commands

```bash
uv sync --all-packages              # install workspace + dev tools
uv run pytest                       # all tests (packages, tests/, lua specs)
uv run pytest lua                   # Lua specs only (Lua 5.1 via lupa + lua/mocks)
uv run ruff check . && uv run ruff format .
uv run mypy packages                # strict
uv run python tools/bundle_lua.py   # lua/src -> dist/dms.lua (manifest order)
uv run dms --help                   # validate | plan | voice | build | check | run | schema | bundle-lua
                                    # | install | doctor | outcome | debrief | new-campaign | catalog
                                    # (see CONTRACTS "File formats")
uv run dms-mcp                      # MCP server (stdio)
```

## Hard rules

1. **Write Lua 5.1 only.** That means no `goto`, no `::labels::`, no `//`, no bitwise operators and
   no `table.unpack`. Also don't use `os`, `io`, `lfs` or `require`, because DCS sanitizes them.
   A hook syntax-checks edited `lua/**` files.
2. **Never use pydcs load/save on user missions.** It is lossy. pydcs is for *generating* only.
   Edit existing missions through `dms_core`'s lupa dict round-trip.
   (ADR [0001](docs/adr/0001-pydcs-for-generation-only.md), [0002](docs/adr/0002-lupa-dict-round-trip-for-editing.md))
3. **All Lua scheduling goes through `DMS.Clock`, and all events through `DMS.Bus`.** No other module
   calls `timer.scheduleFunction` or `world.addEventHandler`.
4. **Log with `DMS.Log.debug|info|warn|error(prefix, fmt, ...)`.** The prefix is the module name
   (`"Spawner"`, `"Intel"`, ...), and output looks like `[DMS][Spawner] ...`. Debug output appears
   only when `DMS.Log.isDebug()` is true. Log starts and stops, activations, skips with their
   reason, and state changes. Outcomes go through `DMS.Log.outcome{...}`, which writes
   `[DMS.OUTCOME] {json}`.
5. **Nothing is "done" until it has been flown in DCS** ([DoD](docs/adr/0009-definition-of-done-requires-flight.md)).
   Done requires green CI, a DCS smoke test (`dcs.log` is clean) and a cockpit check. Until then,
   report the work as "implemented, not flown". Never mark it ✅ on the strength of code alone.
6. **LLM-written files must validate against the schemas** in `dms_core.schemas`. Run `dms validate`
   and repair, for at most 3 loops. LLMs write declarative YAML, and code computes coordinates,
   types and IDs.
7. **Don't edit `legacy/`.** It is read-only reference. Port behaviour into `lua/src/dms/` or
   `packages/`, and add tests when you do.
8. **Keep the Python strict.** Run ruff and mypy in strict mode. Pydantic models use
   `extra="forbid"` and give every field a `Field(description=...)`.
9. **Binaries go through Git LFS** (`*.miz`, `*.ogg`, `*.wav`, `*.mp3`, `*.png`). Never commit
   generated output (`dist/`, `campaigns/**/out/`).

## Where things live

| Path | What |
|---|---|
| `packages/dms-core` | schemas, miz I/O (lupa), catalog |
| `packages/dms-gen` | plan/build (pydcs), Lua injection, kneeboard |
| `packages/dms-voice` | ElevenLabs, ffmpeg radio FX, `~/.dms/tts-cache` |
| `packages/dms-cli` | `dms` command (typer) |
| `packages/dms-mcp` | `dms-mcp` FastMCP stdio server, 6 tools wrapping core/gen (validate, plan, build, check, schema, campaign_status) |
| `packages/dms-arma` | Arma 3 backend: mission spec -> `fn_config.sqf` (`dms-arma` command) |
| `packages/dms-tacview` | Tacview ACMI parser, flight summary and debrief facts (`dms-tacview` command) |
| `packages/dms-beamng` | BeamNG.drive backend: driving-mission spec -> seeded scenario plan |
| `lua/src/dms/` + `lua/manifest.txt` | runtime modules and their load order |
| `lua/spec/`, `lua/mocks/` | specs and the DCS mock (fake clock) |
| `lua/plugins/` | optional pinned MOOSE/MIST/Skynet (the core never depends on them) |
| `tools/` | `bundle_lua.py`, `dcs_harness/` (unattended real-DCS runs -> JSON report), `arma_harness/` |
| `.claude/skills/` | dms-quickstart, story-writer, campaign-planner, mission-designer, voice-director, debriefer, dms-build |
| `.claude/commands/dms.md` | `/dms` mode: build or edit DCS missions with the CLI and skills |
| `campaigns/<slug>/` | bible, arc, missions, state (see CONTRACTS "File formats") |
| `arma/` | Arma 3 missions (`arma/missions/`), modules and tools |
| `legacy/` | pre-rebuild code and docs (read-only) |

## DCS logs

| Version | Path |
|---|---|
| Stable | `C:\Users\mook\Saved Games\DCS\Logs\dcs.log` |
| Open Beta | `C:\Users\mook\Saved Games\DCS.openbeta\Logs\dcs.log` |

Grep for `[DMS]` and `[DMS.OUTCOME]`. To get debug output, set `debug = true` in `DMS_CONFIG` or
call `DMS.Log.setDebug(true)`.

## Docs

- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md): pillars, pipeline, modules
- [docs/CONTRACTS.md](docs/CONTRACTS.md): Lua API, `DMS_CONFIG`, schemas, file formats, CLI
- [docs/adr/](docs/adr/README.md): decisions
- [docs/reference/dcs-scripting-gotchas.md](docs/reference/dcs-scripting-gotchas.md): **read before writing runtime Lua**
- [docs/reference/miz-format.md](docs/reference/miz-format.md), [docs/reference/lessons.md](docs/reference/lessons.md)
- [ROADMAP.md](ROADMAP.md), [CHANGELOG.md](CHANGELOG.md)
- Arma 3: [docs/arma/kb/](docs/arma/kb/README.md) is the verified knowledge base (all BIS function names, wiki pages). Check it before writing SQF. Missions are in `arma/missions/`.
- Key data: [DCS Stores/CLSID list](https://www.airgoons.com/w/DCS_Reference/Stores_List),
  [Hoggit scripting wiki](https://wiki.hoggitworld.com/view/Simulator_Scripting_Engine_Documentation)
