# 0007. Randomness split: Python decides the space, Lua picks the instance

Status: Accepted · 2026-10-27

## Context

Missions need to be inspectable and reproducible, for debugging and validation. They also need to
play differently every time, for replayability.

## Decision

- **Python** is seeded, and the seed is stored in the `.miz`. It decides:
  - theater, time and weather
  - objectives, templates and loadouts
  - validated spawn zones
  - pool contents and weights
  - beats, the voice map and budgets
- **Lua** (`DMS.Rng`) is re-seeded at runtime by mixing the sub-second fraction of
  `timer.getTime()` with `DMS_CONFIG.seed`. It decides:
  - which pool members appear, and where
  - timing jitter and director pacing
  - pop-up SAMs and waves
  - which optional beats fire
  - hidden difficulty adaptation
- Randomise *which* and *where*. Never randomise *whether the mission is winnable*.

## Consequences

- The `.miz` alone fully determines the space of possible outcomes, and `dms check` can validate it.
- The runtime needs its own RNG module, because `os` is sanitized and `math.random` seeding is weak.
- Lua scenario tests run across many seeds (target: 1000).
