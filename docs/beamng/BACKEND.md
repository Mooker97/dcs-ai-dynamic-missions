# BeamNG.drive backend: design

Status: groundwork, 2026-10-29. **Implemented, not run in BeamNG** (no game was launched).
Package: [`packages/dms-beamng`](../../packages/dms-beamng). See [FEASIBILITY](FEASIBILITY.md) and
[ADR 0012](../adr/0012-multiple-game-backends.md). `[?]` = not verified.

## MVP pick: The Getaway

Both the [idea doc](../ideas/beamng.md) research update and FEASIBILITY §5 pick **The Getaway** first.
The stock `evade` mission type and the `gameplay_police` API already handle pursuit, roadblocks and
arrest/evade. That leaves the Director to escalate. Tow Truck Shift's risky part is physical towing
(winch/rope). The spec still supports `tow_shift`/`courier` (`kind`, `stop_at` + `hold_sec` = the
"park at the marker for N seconds" shortcut), so it can come second without schema changes.

## Pipeline

```
b01-getaway.yaml ──load_spec──▶ DrivingMissionSpec ──plan(spec, variant)──▶ ScenarioPlan
   (LLM/human, names only)       (pydantic, extra=forbid)   (seeded, pure)      (coords, picks, hash)
                                                                                     │
                       ScenarioSink.build(plan) ◀────────────────────────────────────┘
                        ├─ BeamNGpySink   (beamngpy, lazy import; needs BeamNG.tech) ← implemented
                        └─ McpSink / ModZipSink (Steam .drive: built-in MCP + mod zip) ← next
                                                                                     │
  harness polls telemetry ──▶ OutcomeTracker.update(Telemetry) ──▶ [DMS.OUTCOME] {json} lines
                                                                   └▶ dms_core MissionOutcome / debrief
```

| Module | Role |
|---|---|
| `spec.py` | `DrivingMissionSpec`: level, player vehicle, start `Place` (`at` or `one_of`), objectives (`reach`, `stop_at`, `evade`, `survive`, `max_damage`; `after` ordering, `optional`), `Traffic`, `Pursuit` + `EscalationStep` ladder, `time_limit_sec`, `time_of_day` (value or `Range`), `beats`, `ai_driver`. Reuses `dms_core` `DMSModel`, `Ident`, `OutcomeValue`, `BeatSpeak`. |
| `locations.py` | Named points per level, so YAML has no coordinates (hard rule 6). Only `west_coast_usa/docs_spawn` is verified (BeamNGpy README). **The rest are placeholders [?]** and must be read in-game before a real run. |
| `planner.py` | `plan(spec, variant) -> ScenarioPlan`. Seed = `sha256("seed:variant:id")`, one RNG with a fixed draw order (start, tod, traffic, pursuit, objectives). Objective places avoid the start. `plan_hash` = sha256 of the plan JSON. |
| `builder.py` | `ScenarioSink` protocol + `BeamNGpySink` (module injectable for tests). |
| `outcomes.py` | `OutcomeTracker`: a pure state machine over `Telemetry(t, pos, damage, arrested, evaded)`. Evaluates objectives, pursuit level, time limit and beats, and emits payloads. |

## Outcome mapping (BeamNG -> DMS)

The payloads match the DCS runtime's `DMS.Log.outcome{...}`. `format_outcome_line` writes
`[DMS.OUTCOME] {json}`, and `dms_core.schemas.parse_dcs_log` / `MissionOutcome.from_payload` parse them
unchanged (tested).

| Payload key | MissionOutcome | BeamNG meaning |
|---|---|---|
| `missionId`, `t`, `kind` (`update`/`end`), `result` | `mission_id`, `time`, `kind`, `result` | `result` ∈ `success` (required objectives done, damage ceilings held), `partial` (done but a required `max_damage` was broken), `failure` (arrested, time limit, or a beat's `end_mission`), `aborted` (`tracker.abort`) |
| `outcome` | `outcomes` | `<objective_id>: true`, `damage` (max seen), `pursuit`, `pursuit_level`, `evaded`, `arrested`, `time_limit`, `time_taken`, plus beat `outcome` facts |
| `flags` | `flags` | `<objective_id>_done` |
| `beats`, `qualityDeltas` | `beats`, `quality_deltas` | beat ids fired, and the summed beat `quality_deltas` (the debriefer applies them as for DCS) |
| `backend`, `variant` | `extra` | `"beamng"`, variant number |

Beat triggers: `start`, `time`, `objective.complete`, `pursuit.level`, `damage.above`, `arrested`,
`evaded`, `time_limit`. Beat effects: `outcome`, `quality_deltas`, `speak` (`BeatSpeak`, for the voice
pipeline), `end_mission`.

## Verified vs [?]

**Verified** (BeamNGpy README/API docs via context7, 2026-10-29): `BeamNGpy(host, port, home=, user=)`,
`.open()`, `Scenario(level, name, description=)`, `Vehicle(vid, model=, license=)`,
`scenario.add_vehicle(vehicle, pos=, rot_quat=)`, `scenario.make(bng)`, `bng.scenario.load/start`,
`vehicle.ai.set_mode('traffic'|'span'|…)`, `ai.set_aggression`, `ai.set_waypoint`, `ai.drive_in_lane`,
`ai.set_speed`, `bng.traffic.spawn(max_amount, police_ratio, extra_amount, parked_amount)`, the
`bng.env.set_tod` method's existence, and the `Damage` sensor. The README quaternion
`(0, 0, 0.3826834, 0.9238795)` is a 45° yaw about Z.

**[?] not verified:**
- `open(launch=False)` to attach to a running instance.
- `Vehicle(part_config=)`.
- `set_tod` argument semantics (0..1, and whether 0.5 is noon).
- The heading sign convention in `heading_to_quat`.
- `set_weather_preset` (not used).
- Damage units for `max_damage` (the 2000 in the example is a guess).
- Every placeholder location.
- Whether BeamNGpy works with Steam .drive at all. It almost certainly doesn't: there is no `tech/techCore`, see FEASIBILITY.

## Next steps

1. **McpSink** for Steam .drive: JSON-RPC to `127.0.0.1:29292/mcp` (`load_level`, `spawn`, `set_ai`/`drive_to`,
   `run_lua` for `gameplay_traffic.setupTraffic` / `gameplay_police.*`). Reuse `ScenarioPlan` as-is.
2. Runtime director: escalation steps -> `gameplay_police.setPursuitVars` / `placeRoadblock` [?]. This is a GE
   Lua extension, or the Python harness through `run_lua`.
3. Read real coordinates for the `west_coast_usa` locations (MCP `get_position`) and mark them `verified`.
4. Harness: poll position, damage and `getPursuitData()` -> `Telemetry` -> `OutcomeTracker`. Write the lines
   and `dms debrief`. Hook the dispatcher/scanner `speak` into dms-voice.
