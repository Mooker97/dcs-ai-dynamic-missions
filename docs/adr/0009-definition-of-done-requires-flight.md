# 0009. Definition of Done requires a DCS flight test

Status: Accepted · 2026-10-27

## Context

Earlier versions marked features ✅ on the strength of the code alone. On review, that code
contained `goto` (invalid in Lua 5.1), calls to APIs that don't exist, and timer loops that died
silently. Mock tests can't prove how something behaves in DCS.

## Decision

A runtime feature is **done** only when all four of these hold:

1. CI is green: ruff, mypy, pytest (including the Lua specs via lupa), `luac -p` and StyLua.
2. A DCS smoke test passes. The mission loads, `dcs.log` has no DMS errors, and the expected
   `[DMS]` lines appear. Use a headless dedicated server where possible.
3. A manual check in the cockpit confirms the behaviour.
4. The result is recorded in `CHANGELOG.md`.

Until then, the feature is described as "implemented, not flown".

## Consequences

- Progress reports stay honest. DCS is needed for sign-off, but not for development.
- The roadmap tracks "flown" separately from "implemented".

## Update (2026-10-29)

The smoke test in step 2 is in practice the single-player harness, not a dedicated-server log
scrape: `dms run --test` builds a test variant (AI player proxy plus in-mission `[DMS.TEST]`
checks), and `tools/dcs_harness/run_mission.py` runs it unattended in single-player DCS and parses
`dcs.log` into a report. Dedicated-server mode needs a saved ED login and is not automated yet.
Passing the harness makes a feature "headless-verified"; it is still not done until the cockpit
check (step 3) passes.
