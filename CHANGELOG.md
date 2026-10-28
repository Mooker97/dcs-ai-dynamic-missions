# Changelog

All notable changes to this project are documented in this file.
The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project
uses [Semantic Versioning](https://semver.org/) (pre-1.0, so minor versions may break things).

Under the [Definition of Done](docs/adr/0009-definition-of-done-requires-flight.md), each entry is
tagged **(flown)** once it has been verified in DCS. Everything else is "implemented, not flown".

## [Unreleased]: v0.3 skeleton

### Added
- Player flights: start `variant`s (one `<id>-<variant>.miz` per variant, `<id>.miz` = first;
  `dms build --variant`, MCP `build(variant=)`), `slot: player|client` (SP Player lead + AI
  wingmen by default), `air_start` placement short of the IP, radio callsign applied in the
  cockpit (`PlanGroup.radio_callsign`, validate warns when the name is not a DCS name for the
  type), F-16C_50 payload presets `sead` / `lgb_strike` / `cas` picked by mission type, full
  internal fuel; test builds prefer a ramp proxy (`--test --variant`). `Threat.templates` pins
  threat templates; `Support.faction` sets friendly countries; neutral factions fill
  `BuildPlan.neutral_countries` (civilians spawn in the neutral coalition). Implemented, not flown.
- `DMS.Ambient`: friendly base traffic (parked departures, arrivals, apron vehicles, pattern helo,
  statics) around the player's departure/recovery airbases, spawned when a player is near and
  destroyed when they leave; mission-spec `ambient: {enabled, density}` (default on, low),
  planner sites from the catalog, `dms check` type validation, `ambient_cycle` test check.
  Implemented, not flown.
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

- **First real DCS run (headless, 2026-10-28):** m01 test build on DCS 2.9.30 via
  `tools/dcs_harness` (single-player, `--norender`, x16). The bundle booted with no script or DMS
  errors; 9 of 10 spine beats fired in order, 3 encounters spawned on land and 9 comms lines
  played. The run timed out before the final landing beat (test budget too short, now fixed).
  Rerun with the longer budget: **all 9 checks pass**, the full spine fires through `on_deck`, and
  the outcome is `success` (47 model min in 4.7 real min). `dms debrief --dry-run` parses that real
  log and picks m02.
- CI is green on `rebuild` (first push); Lua is StyLua-formatted and StyLua is blocking.
- **Base traffic (`DMS.Ambient`), headless DCS 2026-10-28:** at m01's Hatay it activated as the
  proxy spawned (2 statics, 2 ground vehicles, a parked C-130 that started up once the proxy took
  off, then an arriving C-130), despawned everything when the proxy left (`ambient_cycle` PASS), and
  re-activated on its return. 0 errors or warnings. Not yet seen in the cockpit.
- Arma: four new scenarios (Ambush, Village Sweep, Hold the OP, Recon and Strike; RHS + LAMBS + ACE)
  and a drop-in base-life ambient module with a test mission.
  - Headless Arma 2026-10-28: **Recon and Strike passed** (13/13, win) on its first run. **Base-life
    passed** (13/13) vanilla and with RHS (auto-picked US Army OCP): spawned 14 men, 3 vehicles and a
    landing heli; despawned everything beyond 900 m; re-activated on return. Ambush, Village Sweep and
    Hold the OP had first-run fixes and are being rerun.
  This is a headless smoke test, not a cockpit check.
- `dms-mcp`: FastMCP stdio server with 6 tools (validate, plan, build, check, schema,
  campaign_status). Implemented, not flown.
- `evals/`: 30 premises plus 8 golden mission specs; `evals/run.py --golden | --score`.
- `dms build` embeds `briefing.md` (sortie, description, tasks) and `kneeboard.md` (768x1024 PNG
  pages) in the miz. Implemented, not viewed in DCS.
- `dms check` validates the embedded DMS_CONFIG against `RuntimeConfig`, checks guaranteed-beat
  reachability, and accepts template/group encounter sources.
- Lua: a real `cap` encounter (race-track/circle orbit, engage in zone, RTB, director-gated
  replacements); 200-seed director, ground and CAP specs. Implemented, not flown.
- Voice: Text-to-Dialogue for multi-speaker lines, per-line `radio_fx`, the lines.yaml `model` and
  bible voice ids.
- `dms plan` feeds `state/qualities.yaml` into `DMS_CONFIG.qualities`.
- Spec convoys compile with `spawnZone` and `destination`.
- Harness: DCS crash detection (out of memory) and parser unit tests; CI runs the Arma and harness
  tests, the bundle step no longer needs lupa, and StyLua is advisory.

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
