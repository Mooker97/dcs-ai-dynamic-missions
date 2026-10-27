# 0012. Support multiple game backends (DCS first, Arma 3 second)

Status: Accepted · 2026-10-27

## Context

DMS was built for DCS World. The user also wants Arma 3 missions with the same qualities:
replayable, seeded, tested headlessly, and later story-driven and voiced. Much of DMS doesn't depend
on any game:
- the story pillar (bible, arc, beats, skills)
- voice rendering
- the director and encounter design
- the testing approach

The runtime language (Lua vs SQF), the mission file format (`.miz` vs `mission.sqm` + scripts) and
the unit catalogs are game-specific.

## Decision

- Treat each game as a **backend**: its own builder, runtime scripts, catalog and headless harness.
- Keep story, voice and mission intent free of game-specific fields where practical.
- Arma 3 starts as a hand-built MVP (`arma/`, plan in `docs/arma/PLAN.md`). It is generalised into
  a backend only once it plays well.
- DCS remains the primary backend. Arma work must not block the DCS roadmap.

## Consequences

- New schema fields should be checked for DCS-only assumptions before being added to the story or
  mission-intent layers.
- Each backend needs its own verified knowledge base (`docs/reference/` for DCS, `docs/arma/kb/`
  for Arma) and its own harness (`tools/dcs_harness/`, `tools/arma_harness/`).
