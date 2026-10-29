# Tacview-powered debriefs (DCS)

Status: groundwork implemented 2026-10-29 (`packages/dms-tacview`: parser, summary, facts adapter,
`dms-tacview summarize`), tested against hand-written fixtures only. **Not yet run on a real DCS
ACMI file, not wired into `dms debrief`.** Implemented, not flown.

## What

Tacview (installed on the user's machine, Steam) records DCS flights as **ACMI** files. ACMI is a
text-based, time-stamped log of every object: positions, attitude, type, coalition, weapons fired,
hits and destruction [? confirm what the DCS exporter records]. Parse that after a flight, and the
debriefer knows what actually happened, instead of relying only on our `[DMS.OUTCOME]` lines.

## Why it's valuable

- **A smarter debriefer** (v0.7 campaign loop):
  - who killed what, with which weapon, and from where
  - which SAMs engaged you, and how close you came
  - what the convoy did, and how long you spent in the threat area
- **Better outcomes:** richer facts become campaign qualities. For example, "flew low through the
  valley and was never painted by radar" could raise a stealth reputation quality.
- **A tuning tool for us:** compare what the Director *intended* (log) with what *happened* (ACMI).
  It can show encounters that never engaged, AI stuck on terrain, or spawns nobody saw.
- **A headless-harness bonus:** headless DCS runs could also record ACMI, so tests can assert on
  geometry. For example, "the hunt group got within 2 km of the convoy".

## Sketch

- A new package/module `dms-tacview` (or `dms_core.acmi`) that streams and parses `.acmi` / `.zip.acmi`
  into typed events: spawn, destroy, shot, hit, and per-object tracks sampled at N Hz.
- `dms debrief <acmi> [--log dcs.log]` merges the ACMI events with the `[DMS.OUTCOME]` lines and
  writes `state/outcomes/mNN.yaml` with extra facts. The debriefer skill gets a richer summary.
- Optional: render a debrief map, i.e. a kneeboard-style PNG of the flight path, threats and kills.

## Open questions

- Recording location and naming. Does Tacview need to be enabled in DCS Special options? [?]
- Which ACMI fields DCS fills in for ground units, weapons and hits.
- Whether any of this needs Tacview Advanced/Enterprise, or just the free recording. [?]
- File sizes and parsing speed for 1–2 hour flights. (The parser is a single pass and keeps every
  transform sample; `--sample-dt` thins tracks while parsing. Not measured on a real file yet.)

## ACMI 2.2 format: verified vs assumed

Source: Tacview "ACMI flight recordings 2.2" page (`tacview.net/documentation/acmi/en/`, which now
redirects to `raia-software-inc.gitbook.io/tacview/technical-documentation/acmi-telemetry-file-format`),
read 2026-10-29.

**Verified from the spec**

- The first two lines are `FileType=text/acmi/tacview` and `FileVersion=2.2`. The text is UTF-8,
  a BOM is recommended, and lines end in LF. The text can be wrapped in a zip or 7z container.
- Comments are `//` at the start of a line.
- `#<seconds>` starts a frame. The time is in seconds (decimals allowed) relative to `ReferenceTime`.
- `<hexid>,<Prop>=<value>,...` sets properties on an object. Ids are 64-bit hex with no prefix or
  leading zeros. Object `0` is global (`ReferenceTime`, `RecordingTime`, `Title`, `DataSource`,
  `DataRecorder`, `Author`, `Briefing`, `Comments`, `Theater`, `ReferenceLongitude`, `ReferenceLatitude`, ...).
- `-<hexid>` removes an object.
- A comma inside a text value is written `\,`.
- `T=` has 3 components (`Lon|Lat|Alt`), 5 (`+ U|V`, flat-world metres), 6
  (`+ Roll|Pitch|Yaw`) or 9 (`Lon|Lat|Alt|Roll|Pitch|Yaw|U|V|Heading`). Angles are in degrees,
  altitude in metres MSL, and yaw is clockwise from true north. Omitted components keep their
  previous value (`T=41.626||`). An object should keep the same notation for its whole life.
- `ReferenceLongitude` / `ReferenceLatitude` are added to every object's lon/lat.
- Properties only need writing when they change.
- Events are `0,Event=<Type>|<ObjectId>|...|<Text>`. Several can share a frame. Types: `Message`,
  `Bookmark`, `Debug`, `LeftArea` ("removed cleanly, not destroyed"), `Destroyed`, `TakenOff`,
  `Landed`, `Timeout` (weapon result:
  `Timeout|SourceId:507|AmmoType:FOX2|AmmoCount:1|Bullseye:50/15000/2500|TargetId:201|IntendedTarget:Leader|Outcome:Kill`).
- Object text properties include `Name`, `Type`, `Parent`, `Next`, `Pilot`, `Group`, `Country`
  (ISO 3166-1 alpha-2), `Coalition`, `Color`, `CallSign`, `Registration`, `Squawk` and
  `LockedTarget`. `Type` is `+`-joined tags. The class tags are
  `Air|Ground|Sea|Weapon|Sensor|Navaid|Misc`. Other tags include `FixedWing`, `Rotorcraft`,
  `AntiAircraft`, `Vehicle`, `Missile`, `Bomb`, `Shell`, `Bullet`, `Static` and `Building`.

**Assumed [?] (the parser handles these, but they are not confirmed against a real DCS file)**

- [?] **Line continuation:** a backslash at the end of a line continues a multi-line text value,
  and the line break is kept. The spec only says to "escape" end-of-line characters.
- [?] **File names:** `Tacview-<date>-DCS-<mission>.txt.acmi` / `.zip.acmi` under
  `Documents\Tacview`. The parser detects zip by its magic bytes and ignores the extension. It
  does not support 7z.
- [?] **DCS exporter coverage:**
  - whether DCS writes `Destroyed` events, or only `-id` removals
  - whether weapons carry a `Parent` (the `tacview-duckdb` package "enriches" DCS weapon→launcher
    links, which suggests DCS does not)
  - whether `Timeout` events appear at all
  - whether shells and bullets are recorded
  - what `Coalition` looks like (`Allies` / `Enemies` in our fixture)
  - whether AI aircraft carry a `Pilot` property
- [?] DCS uses the 9-component `T` (with U/V = DCS x/z [?]) for all objects.
- [?] Whether recording needs Tacview to be enabled in DCS Special options, and whether it needs a
  paid edition. Basic recording is believed to work in the free edition.

## Package `dms-tacview` (implemented, not flown)

- `dms_tacview.acmi`: `parse_acmi(text)` / `parse_acmi_file(path)` -> `Recording` (header + globals,
  objects with props, latest transform, absolute-lon/lat track, `first_seen`/`last_seen`/`removed_at`,
  events). Malformed lines are counted and skipped, never fatal. An id re-used after removal starts
  a new object.
- `dms_tacview.summary.summarize(rec, player=, points=, heuristics=)` -> `FlightSummary` (Pydantic,
  `extra="forbid"`): object fates, shots, kills, player track, closest approach to named points and
  zones, and closest hostile `AntiAircraft` object.
- `dms_tacview.facts`: `outcome_facts(summary)` -> flat `tv_*` facts.
  `enrich_outcome(outcome, summary, merge_into_outcomes=False)` -> a copy of `MissionOutcome`.
- CLI: `dms-tacview summarize <file> [--player X] [--points pts.yaml] [--facts] [--json] [--full]`.

### Heuristics (all labelled in the output; thresholds in `Heuristics`)

| What | Stated by the file | Heuristic fallback |
|---|---|---|
| Object destroyed | `Destroyed` event -> `fate_source: destroyed_event` | A combatant (no Weapon/Decoy/Misc/Static/... tag, no `Landed` event) removed before the last frame with no `LeftArea` -> `removal_inferred` (turn off with `infer_destroyed_from_removal=False`) |
| Weapon launcher | `Parent` -> `launcher_method: parent_property` | The nearest combatant alive at the weapon's first sample, within `launch_radius_m` (500 m), same `Coalition` preferred -> `launch_proximity` |
| Weapon hit | `Timeout` event / kill attribution | A combatant within `hit_radius_m` (150 m) of the weapon's last sample -> `impact_proximity` |
| Kill credit | `Timeout` event with `TargetId` = victim and `Outcome` Kill/Hit -> `method: timeout_event`, `confidence: high` | The **nearest weapon** whose end time falls in [kill − 15 s, kill + 1 s], within `hit_radius_m` of the victim, is credited to its launcher -> `nearest_weapon`. Confidence is `medium` if the launcher came from `Parent`, else `low` |
| Player | `--player` matching id/Pilot/Name/CallSign/Group -> `explicit` | The aircraft with a `Pilot` property that appears first (longest-lived on ties) -> `heuristic_first_piloted_aircraft`. With AI pilots also named, this may pick the wrong aircraft, so pass `--player` |
| Zone time inside | n/a | Per track segment: (number of endpoints inside / 2) × segment duration |

Closest approach to a point uses point-to-segment distance on a local flat projection. Threat
distance is 3-D, measured at the player's samples against the threat's interpolated position.
Projectiles (`Shell`/`Bullet`/...) are left out of shots unless `count_projectiles`.

### Facts (`outcome_facts`)

Every key matches the arc condition grammar `[a-z][a-z0-9_]*` and has the `tv_` prefix, so it
cannot collide with keys reported by Lua:

- Always: `tv_player_found`, `tv_duration_s`.
- When a player is found:
  - `tv_flight_time_s`, `tv_distance_km`, `tv_max_alt_m`, `tv_min_alt_m`
  - `tv_player_destroyed`, `tv_player_landed`
  - `tv_player_shots`, `tv_player_hits`
  - `tv_player_kills` and `tv_player_kills_{air,ground,sea}`
  - `tv_player_kills_confident` (high/medium confidence only)
  - `tv_friendly_losses`, `tv_enemy_losses` (by the player's `Coalition`)
  - `tv_closest_threat_m`
- Per named point: `tv_<slug>_min_m`, plus `tv_<slug>_entered` and `tv_<slug>_time_inside_s`
  for zones that have a `radius_m`.

## Proposed integration (not done; `dms_core.outcomes` is unchanged)

1. `dms debrief --acmi <file|auto>`. `auto` picks the newest `*.acmi` in the Tacview folder whose
   `RecordingTime` falls inside the dcs.log session window [?]. After `build_outcome(...)`, call
   `dms_tacview.enrich_outcome(outcome, summarize(parse_acmi_file(p), player=..., points=...))`.
2. Named points come from the plan: `DMS_CONFIG` zones/targets (lon/lat computed by `dms_gen`) are
   turned into `NamedPoint`s. The player comes from `MissionOutcome.players[0]`, if present.
3. Facts land in `extra.tacview` by default. They are merged into `outcomes` (so arc
   `quality_effects` can use them, e.g. `+1 if tv_convoy_route_time_inside_s < 60`) only with
   `--acmi-facts`, so that a heuristic never changes campaign state unless asked to.
4. The debriefer skill reads `extra.tacview.kills` (with `method` and `confidence`) for the
   narrative. It must not state a `low`-confidence kill as fact.

### Draft CONTRACTS.md addition (for "Debrief"; not applied)

> - **Tacview facts** (`dms_tacview`, optional, `--acmi PATH|auto`): the ACMI recording is parsed
>   and summarized. `extra.tacview = {source, facts, player, player_selected_by, kills[{victim,
>   killer, weapon, t, method, confidence}], warnings}`. Facts are `tv_*` keys (see
>   docs/ideas/tacview.md). With `--acmi-facts`, they are also merged into `outcomes` without
>   overwriting Lua-reported keys, so they are visible to arc `quality_effects` and `<mNN>_tv_*`
>   flags. A missing or unparseable ACMI is a warning, never fatal. `session_hash` is computed
>   from the dcs.log records only, so adding or removing the ACMI does not change the re-debrief
>   guard.
