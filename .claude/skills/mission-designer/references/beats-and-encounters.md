# Beats and encounters

Beats (`beats.py` `Beat`) compile verbatim into `DMS_CONFIG.beats`. Encounters (`mission.py`
`EncounterIntent`) compile into `DMS_CONFIG.encounters` (docs/CONTRACTS.md). On each event, the
Lua narrative engine fires the highest-`priority` eligible beat, respecting `once`,
`cooldown_sec` and `requires`.

## Beat shape

```yaml
mission_id: m01-first-light
beats:
  # GUARANTEED
  - id: mission_start
    when: {event: timer, after_sec: 10}
    requires: {}                 # flags, flags_not, qualities[{quality,op,value}], beats_fired, beats_not_fired, chance
    priority: 90
    once: true
    cooldown_sec: 0
    delay_sec: 0
    speaker: ops_hatay           # must be in mission-spec `cast`
    lines: [ops_cleared_v1, ops_cleared_v2, ops_cleared_v3]   # variant ids in lines.yaml
    text: "Dusty, Hatay Ops, cleared for patrol."             # subtitle fallback
    mark: null                   # {type: circle|text|point, at: "zone:<area>"|"group:<name>"|"unit:<name>", text, radius_m}
    effects: {set_flag: started} # set_flag, clear_flag, outcome{}, start_encounter, spawn_pool, quality_deltas{}, end_mission
```

## `when.event` values and their filter fields

| Event | Required / useful fields | Typical beat |
|---|---|---|
| `mission.start` | none | scene-setting at load |
| `timer` | **after_sec** | scheduled check-ins, the start call (`after_sec: 10`) |
| `flag` | **flag** | objective flags, chaining from other systems |
| `player.spawned` / `player.left` | `players_only` | per-player greeting |
| `unit.takeoff` / `unit.landed` | `group`, `players_only` | departure, recovery and debrief |
| `zone.entered` | **zone** (an area id), `group` | on-station, RTB approach, staging area seen |
| `unit.shot` | `group_prefix`, `coalition`, `type_name` | AAA opens up, SAM launch |
| `unit.hit` | `group`/`unit`, `coalition`, `players_only` | player hit, friendly taking fire, civilian hit |
| `unit.dead` | `coalition` (1 red, 2 blue), `group_prefix`, `type_name` | first kill, civilian casualty |
| `group.dead` | **group** or **group_prefix** | objective destroyed |
| `mark.added` | none | player marks a target on F10 |
| `beat.fired` | **beat** (+ `delay_sec` on the beat) | chains: telegraph → threat, call → reply |
| `encounter.spawned` | **encounter** | warning that a pop-up exists |
| `director.state` | **state** BUILD_UP / PEAK / RELAX | ambient chatter in RELAX |

`dms plan` derives group names from spec ids (threats, pools, support), and `group_prefix` matches
them. If a beat needs an exact group name, use the spec id and check the plan output.

## Guaranteed vs optional

- **Guaranteed** beats are reachable in every playthrough: mission start, objective payoff, RTB
  call, landed/debrief, and a mission-end record on death. Mark each one with a `# GUARANTEED`
  comment; there is no schema field. Together they cover the arc mission's `key_beats`. Never hang
  a guaranteed beat on an optional encounter.
- **Optional** beats react: first kill, taking fire, pop-up telegraph, civilians nearby, player hit.
- Priorities: guaranteed 80–95, reactions 40–70, ambience 10–30. Reactions get a `cooldown_sec`
  so they don't spam.
- Chain state with `effects.set_flag` and then `requires: {flags: [...]}`, or with
  `requires.beats_fired`.

## Exchanges (two speakers)

Beats have one speaker each, so an exchange is a chain: the reply beat is
`when: {event: beat.fired, beat: <first>}` with `delay_sec: 2-4`, and `once: true`. The
voice-director may render such chains as one Text-to-Dialogue take.

## Effects

- `set_flag` / `clear_flag`: mission flags. Use them for objective `success_flag` / `failure_flag`.
- `outcome`: facts emitted via `[DMS.OUTCOME]`. Use the arc's outcome keys exactly. The
  debriefer turns them into campaign flags `<mNN>_<key>`.
- `quality_deltas`: campaign quality changes the debriefer applies, e.g. `{intel: 1}`.
- `start_encounter` / `spawn_pool`: wake a dormant encounter (QRF, pop-up) or spawn once from a pool.
- `end_mission`: `success` or `failure`.

## Encounters (`dynamic.encounters`)

```yaml
- id: popup_aa
  kind: ambush_sam          # ambush_sam | waves | hunt | convoy | cap | pool
  pool: hidden_aa           # dynamic.pools id
  trigger: {type: proximity, area: patrol_box, radius_nm: 4}   # beat -> beat; time -> after_min; director
  chance: 50
  telegraph_beat: popup_aa_warning
  waves: null
  gap_min: null             # [min, max] minutes between waves
  hunt: false
```

| Kind | What it does |
|---|---|
| `pool` | spawns `pick` members of a pool in its areas |
| `ambush_sam` | SAM or AAA stays dark until players are in range, then rolls to go hot |
| `waves` | N waves with a `gap_min` range, often beat-triggered |
| `hunt` | ground groups route to intercept players or a target |
| `convoy` | a moving group along roads between areas |
| `cap` | enemy air patrol (use sparingly against helicopters) |

## Replayability rules

1. **Randomise which and where, never whether the mission is winnable.** The objective always
   exists, and the route home is always survivable with sensible flying.
2. **Telegraph before punishing.** Every pop-up has a `telegraph_beat` (radio warning, ground
   report, RWR cue) 30–60 s before it can engage.
3. **Never spawn in sight:** at least 5 km and out of line of sight for ground, at least 20 nm
   for air.
4. **Shuffle-bag variants.** Each beat lists 3–5 line variants, and the runtime never repeats one
   until the bag is empty.
5. **Keep hidden adaptation small** (`director.adaptive`): ±1 tier at most.
6. Each play should differ in at least 3 ways: pool picks, positions, optional encounters, timing
   jitter, ambient lines.

## Director intent

Describe the tension curve in the spec `notes`: where the player feels safe, where pressure peaks,
and how long it relaxes. Then set `dynamic.director.intensity` to match. Example: "Quiet transit;
first contact in the north half of the box; peak at the pop-up AA if it fires; long relax on egress
so the tower call lands."
