# Lessons learned

These are dated lessons from earlier phases. Each one has been turned into a rule or an ADR. The
lessons are kept here so the reasoning isn't lost.

## 2025-12-08: check existing project patterns before choosing a tool

**Context:** We were writing a script to pull group coordinates out of `.miz` files.

**Mistake:** I started with pydcs without checking how existing scripts did it, and hit four
problems:

- `KeyError: 35`, an unknown task ID.
- Livery scanner errors that required a DCS install.
- Awkward environment-variable setup.
- A need for a `pydcs_patch.py`.

**Lesson:** Look at how the repo already solves a problem before picking an approach.

**Current rule:** The answer then was MizParser. That has since been superseded: use lupa miz I/O
for reading and editing ([ADR 0002](../adr/0002-lupa-dict-round-trip-for-editing.md)), and use
pydcs only for generation ([ADR 0001](../adr/0001-pydcs-for-generation-only.md)).

## 2025-12-08: set environment variables before imports that read them

**Context:** pydcs scans for DCS liveries while it is being imported.

**Mistake:** `DCS_INSTALLATION` and `DCS_SAVED_GAMES` were set after importing a helper that
imported pydcs itself, so the scan had already run.

**Lesson:** If a library reads environment variables or config at import time, set them at the
very top of the entry point, before any import that could pull the library in transitively. A
traceback that runs through module `__init__` or class bodies is the giveaway.

## 2024-12: regex on nested Lua tables doesn't scale

Extracting waypoints with regex over the `mission` text failed in two different ways. The lessons:

- Inspect the real structure before writing parsers.
- Regex can't match balanced nested tables reliably.
- Don't trust pydcs round-trips.

A real Lua parser fixes all three ([ADR 0002](../adr/0002-lupa-dict-round-trip-for-editing.md)).

## Windows: keep console output ASCII

The Windows console (cp1252) raises `UnicodeEncodeError` on emoji or check marks. CLI output should
use plain ASCII markers such as `[OK]` and `[FAIL]`, or force UTF-8 through `rich`/typer. Use
`pathlib.Path` for paths.

## 2026-10-27: "complete" isn't the same as "works in DCS"

A review of the 72-module legacy Lua library found four problems:

- `goto` in 7 modules (a syntax error in Lua 5.1).
- `WEAPON_FREE` used as a ground ROE.
- A call to `trigger.action.groupKnown`, which doesn't exist.
- Timer loops that died on their first error.

All 72 had been marked ✅. This led to [ADR 0009](../adr/0009-definition-of-done-requires-flight.md):
nothing is done until it has been flown.
