# Changelog

All notable changes to this project are documented in this file.
The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project
uses [Semantic Versioning](https://semver.org/) (pre-1.0, so minor versions may break things).

Under the [Definition of Done](docs/adr/0009-definition-of-done-requires-flight.md), each entry is
tagged **(flown)** once it has been verified in DCS. Everything else is "implemented, not flown".

## [Unreleased]: v0.3 skeleton

### Added
- The architecture was approved: own Lua core, four pillars, and a story-first pipeline. See
  `docs/ARCHITECTURE.md`, `docs/CONTRACTS.md` and ADRs 0001–0011 in `docs/adr/`.
- Reference docs: `docs/reference/dcs-scripting-gotchas.md`, `miz-format.md` and `lessons.md`.
- Tooling:
  - GitHub Actions CI, with a Python job (ruff, mypy, pytest) and a Lua 5.1 job (`luac -p`,
    StyLua, luacheck).
  - `.stylua.toml`, `.luacheckrc` and `.pre-commit-config.yaml`.
  - A Claude Code hook that checks edited Lua files against Lua 5.1 syntax.
- `.env.example` for `ELEVENLABS_API_KEY`.
- `dms debrief <campaign> --mission mNN`: `dms_core.outcomes` parses dcs.log sessions
  (stable/openbeta, `dcs.log.old`, latest run wins), writes `state/outcomes/<mNN>.yaml`, applies
  quality deltas and `<mNN>_<key>` flags to `state/qualities.yaml` and picks the next mission from
  arc branches. The debriefer skill calls it first. Implemented, not flown (synthetic logs only).

### Changed
- **Restructure (da799f7):**
  - The repo is now a uv workspace with `packages/dms-{core,gen,voice,cli}`, `lua/`, `data/`,
    `campaigns/` and `examples/`.
  - All pre-rebuild code and docs moved to `legacy/`, where they are read-only.
  - `.miz`, audio and images are tracked through Git LFS.
- `CLAUDE.md` was rewritten as a short guide covering commands, hard rules and links.
- `README.md` was rewritten.
- The `/dms` command now points at the `dms` CLI and skills.

### Fixed
- **Legacy Lua library under DCS Lua 5.1 (7744bb4).** All of these are implemented and pass
  mock-DCS scenario tests, but none have been flown yet:
  - Removed `goto` from 7 modules and fixed a command-menu long-string compile error.
  - Changed ground ROE from `WEAPON_FREE` to `OPEN_FIRE`. Added real 2-point ground routes,
    `FireAtPoint` and `StopRoute`.
  - Replaced the non-existent `trigger.action.groupKnown` fog of war with spawn-time `hidden`
    plus F10 marks.
  - Guarded every timer callback and event handler with `pcall`, so loops survive errors.
  - Library fixes:
    - Per-group F10 menus.
    - JTAC laser.
    - BDA classification.
    - Audio paths.
    - A shared spawn core.
    - Fixed the `DMS.Timer` name collision.
    - Persistence degrades gracefully when `io` is unavailable.
  - Dustoff Corridor fixes:
    - A-10 activation.
    - SAM fire.
    - Enemy hunting.
    - Convoy halt.
    - QRF trigger.

### Deprecated
- The regex `MizParser` / `miz-modification` approach
  ([ADR 0011](docs/adr/0011-retire-regex-mizparser.md)).
- pydcs load/save on existing missions
  ([ADR 0001](docs/adr/0001-pydcs-for-generation-only.md)).

## Pre-rebuild history (summary)

Details are in `legacy/docs/Versions.md`. Those versions marked features ✅ without testing them in
DCS. A review in October 2026 found that many of them didn't work, which led to ADR 0009.

- **v0.3 (legacy, 2026):** ElevenLabs audio generation (needs testing).
- **v0.2.x (2025-12 to 2026-01):**
  - Dynamic spawning from trigger zones.
  - Event handling.
  - AI behaviours.
  - Fog of war.
  - Scoring and objectives.
  - Dustoff Corridor, the first scripted mission.
- **v0.1.0 (2025-12-08):** A random-spawn script library for pre-placed units.
