# 0001. pydcs is used to generate new missions only

Status: Accepted · 2026-10-27

## Context

pydcs 1.0.0 (Python ≥3.11) reliably *generates* missions. A hands-on probe built a Syria mission
with an AH-64 client slot, convoy waypoints, trigger zones and a DO SCRIPT FILE.

Its *load → save* path is lossy. We ran it on 5 real missions:

- 2 failed to load (`KeyError: 'enable_fog'`).
- The other 3 lost `trig.custom`, `start_delay`, passwords and inline script content.
- The mission version was downgraded from 23 to 20.

pydcs also reads environment variables at import time. Its livery scanner searches the Windows
registry for a DCS install and picks an arbitrary profile.

## Decision

- `dms build` uses pydcs, pinned to an exact version, to create new `.miz` files from a `BuildPlan`.
- pydcs never opens a user's mission for editing (see ADR 0002).
- DCS paths and env vars are set explicitly **before** `dcs` is imported.

## Consequences

- Generated missions get pydcs's unit and payload database and its grounding data.
- Editing needs a second I/O path (lupa).
- Upgrading pydcs means re-running the generation smoke tests.
