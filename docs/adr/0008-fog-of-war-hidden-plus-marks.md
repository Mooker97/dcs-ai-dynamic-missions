# 0008. Fog of war = spawn-time `hidden` + F10 marks on detection

Status: Accepted · 2026-10-27

## Context

DCS can't hide or reveal units at runtime. `hidden`, `hiddenOnMFD` and `hiddenOnPlanner` can only
be set at spawn, and the F10 view mode can't be scripted. The legacy library called
`trigger.action.groupKnown`, which doesn't exist.

## Decision

- Enemy groups spawn with `hidden = true`.
- `DMS.Intel` polls detection (`getDetectedTargets` / `isTargetDetected`) and draws F10 marks and
  shapes for detected contacts.
- Marks refresh every `markRefreshSec` and go stale after `staleSec`.
- Mark IDs start at ~10000, because they share a namespace with player marks.
- The generator sets the mission map option to "Fog of War".

## Consequences

- Players see what has been detected, not the live truth. This works in both MP and SP.
- The generator must set `hidden` on enemy units pre-placed in the Mission Editor.
- Mark churn costs performance, which limits how often marks can refresh.
