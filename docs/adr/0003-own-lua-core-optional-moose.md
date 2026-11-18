# 0003. Own Lua core on the raw DCS API; MOOSE and Skynet are optional plugins

Status: Accepted · 2026-10-27

## Context

MOOSE (GPL-3, ~2.9.x) is large, active and capable. Skynet-IADS needs MIST.

The legacy `lua-library/` had 72 modules with real bugs, fixed in commit 7744bb4:

- `goto` statements under Lua 5.1
- ground ROE set to `WEAPON_FREE`
- timer loops that died on the first error
- calls to a `trigger.action.groupKnown` that doesn't exist

We need a small, testable runtime driven by a generated config table, and we need to understand all
of it.

## Decision

- Build 12 modules under `lua/src/dms/`: core, clock, rng, bus, registry, spawner, ground,
  director, encounters, narrative, comms and intel.
- The modules use only the raw DCS scripting API. They are tested with mocks and a fake clock, and
  their API is defined in `docs/CONTRACTS.md`.
- MOOSE, MIST and Skynet are **optional, pinned plugins** under `lua/plugins/`. When a spec asks
  for one, it loads before `dms.lua`.
- The core never depends on a plugin.
- `legacy/lua-library/` stays as read-only reference. Its behaviours are ported over with tests.

## Consequences

- We own correctness, so DCS quirks have to be documented
  ([`../reference/dcs-scripting-gotchas.md`](../reference/dcs-scripting-gotchas.md)).
- The bundle stays small, and no GPL code goes into the core.
- Features MOOSE already provides (CTLD, CSAR, ATIS) are used through plugins, not re-implemented.
