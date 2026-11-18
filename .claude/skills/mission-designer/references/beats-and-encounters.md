# Beats and encounters

Beats (`beats.py` `Beat`) compile verbatim into `DMS_CONFIG.beats`. Encounters (`mission.py`
`EncounterIntent`) compile into `DMS_CONFIG.encounters` (docs/CONTRACTS.md). On each event, the
Lua narrative engine fires the highest-`priority` eligible beat, respecting `once`,
`cooldown_sec` and `requires`. Per-role spines (SEAD, strike, CAS, CAP, CSAR, air assault) with
T+ offsets and outcome keys are in the guide §1
(`docs/reference/mission-design-guide.md`); start from the matching one.

## Beat shape

```yaml
mission_id: m01-first-light
beats:
  - id: mission_start
    when: {event: timer, after_sec: 10}
    requires: {}                 # flags, flags_not, qualities[{quality,op,value}], beats_fired, beats_not_fired, chance
    priority: 90
    once: true
    guaranteed: true             # story spine: must play every run (chance ignored, line never dropped)
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
| `unit.takeoff` / `unit.landed` | `group`, `players_only`, `zone` (position at the event), `place` (airbase/FARP/ship name) | departure, recovery and debrief (never guaranteed on takeoff if an air variant exists) |
| `zone.entered` | **zone** (an area id), `group` | on-station, RTB approach, staging area seen |
| `unit.shot` | `group_prefix`, `coalition`, `type_name` | AAA opens up, SAM launch |
| `unit.hit` | `group`/`unit`, `coalition`, `players_only` | player hit, friendly taking fire, civilian hit |
| `unit.dead` | `coalition` (0 neutral, 1 red, 2 blue), `group_prefix`, `type_name` | first kill, civilian casualty |
| `group.dead` | **group** or **group_prefix** | objective destroyed |
| `mark.added` | none | player marks a target on F10 |
| `beat.fired` | **beat** (+ `delay_sec` on the beat) | chains: telegraph → threat, call → reply, timeouts |
| `encounter.spawned` | **encounter** | warning that a pop-up exists |
| `director.state` | **state** BUILD_UP / PEAK / RELAX | character lines in RELAX |

`dms plan` derives group names from spec ids (threats, pools, support), and `group_prefix` matches
them. If a beat needs an exact group name, use the spec id and check the plan output.

## Guaranteed vs optional

- **Guaranteed** beats set `guaranteed: true` (a `# GUARANTEED` comment is optional): mission
  start / check-in, objective payoff, check-out, RTB call, landed/debrief, and a mission-end record
  on death. Together they cover the arc mission's `key_beats`. Never hang one on an optional
  encounter, on `unit.takeoff`, or on a ramp-only zone when an air variant exists.
- **Optional** beats react: first kill, taking fire, pop-up telegraph, civilians nearby, player hit.
- Priorities: guaranteed 80–95, reactions 40–70, ambience 10–30. Repeatable reactions
  (`once: false`) get `cooldown_sec ≥ 30` and ≥3 variants.
- Chain state with `effects.set_flag` and then `requires: {flags: [...]}`, or with
  `requires.beats_fired`.

## Timeout fallback (no single point of failure)

A guaranteed beat that waits on a kill, a landing or a flag can stall the mission. Give it a
sibling that fires on time if the event never comes, sets the **same flag**, and is suppressed if
the event happened. This is what the `spine_no_fallback` lint looks for. From viper m03:

```yaml
  - id: mill_good_effects          # the payoff, if the player kills the target
    when: {event: group.dead, group_prefix: mill}
    priority: 85
    once: true
    speaker: jtac
    lines: [mill_good_effects_v1, mill_good_effects_v2, mill_good_effects_v3]
    effects: {set_flag: next_target, outcome: {mill_destroyed: true}}
  - id: jtac_retask                # the timeout: 8 min after the talk-on, move on anyway
    when: {event: beat.fired, beat: talk_on_1}
    delay_sec: 480
    requires: {flags_not: [next_target]}
    priority: 70
    once: true
    speaker: jtac
    lines: [jtac_retask_v1, jtac_retask_v2, jtac_retask_v3]
    effects: {set_flag: next_target}
```

The next spine beat waits on `flag: next_target`, so check-out and RTB always fire. A `timer` beat
with `requires: {beats_not_fired: [<payoff>]}` works the same way. Landing beats are never
guaranteed without such a fallback ("go around, alternate LZ", or RTB on a timer). Add one
"Ops: say status" nudge after ~4 min without progress.

## Landing at a specific place

Use one `unit.landed` beat with a position filter:
`when: {event: unit.landed, zone: lz_alpha, players_only: true}`. The runtime checks the unit's
position at the landing event against the zone (config zone or ME trigger zone), so flying through
the zone and landing elsewhere does not fire it. For an airbase, FARP or ship use
`place: "FARP London"` (alias `airbase`, the DCS place name, case-insensitive); `zone` and `place`
together must both hold. The same filters work on `unit.takeoff`. The old silent
`zone.entered` + `at_lz` flag pattern is no longer needed.

## Reactions: generic fallback plus specific variants

For each reactive event (player hit, SAM launch, first kill), write one ungated beat at low
priority, then state-gated variants at higher priority (`requires.flags` / `qualities`). The
specific beat wins when it applies; the generic one guarantees coverage (`no_generic_fallback`).
Story and continuity lines go in RELAX (`when: {event: director.state, state: RELAX}`) or chain
off a kill/BDA beat; anything that can fire mid-fight stays ≤12 words (`peak_chatter`). At most 3
radio beats on one trigger (`radio_density`).

## Exchanges (two speakers)

Beats have one speaker each, so an exchange is a chain: the reply beat is
`when: {event: beat.fired, beat: <first>}` with `delay_sec: 2-4`, and `once: true`. The
voice-director may render such chains as one Text-to-Dialogue take.

## Effects

- `set_flag` / `clear_flag`: mission flags. Use them for objective `success_flag` / `failure_flag`.
- `outcome`: facts emitted via `[DMS.OUTCOME]`. Use the arc's outcome keys exactly; the debriefer
  turns them into campaign flags `<mNN>_<key>`. Emit counts for multi-target objectives
  (`targets_destroyed: 2`) alongside booleans, so the arc can branch on degree. Numbers are
  designer-set per beat (write one beat per threshold you care about).
- `quality_deltas`: campaign quality changes the debriefer applies, e.g. `{intel: 1}`; keep each
  quality within ±2 per mission (`quality_swing`).
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

Pools: `pools[] {id, roles, areas, pick: [min, max], faction, templates, notes}`; `templates`
pins catalog templates (check with `uv run dms catalog templates --role <ThreatRole> --era <year>`).

| Kind | What it does |
|---|---|
| `pool` | spawns `pick` members of a pool in its areas |
| `ambush_sam` | SAM or AAA stays dark until players are in range, then rolls to go hot |
| `waves` | N waves with a `gap_min` range, often beat-triggered |
| `hunt` | ground groups route to intercept players or a target |
| `convoy` | a moving group along roads between areas |
| `cap` | enemy air patrol (use sparingly against helicopters) |

- **Set pieces bypass the director** (guide §4.3): the pinned objective and the arc's guaranteed
  threat are `threats` or `chance: 100` encounters. Only filler (`waves`, `hunt`, `cap`) is
  director-gated.
- At most 6 encounters with `chance > 0` (`vul_overload`); about one major event per 2–4 min of
  on-station time at `moderate`.
- `ambush_sam` / `cap` / `waves` need a `telegraph_beat` (`popup_no_telegraph`, an error) unless
  the notes say `no-cue:` and the briefing warns of it. The telegraph beat itself is ungated and
  undelayed (`telegraph_too_short`).

## Replayability rules

1. **Randomise which and where, never whether the mission is winnable.** The objective always
   exists, and the route home is always survivable with sensible flying.
2. **Telegraph before punishing:** 30–60 s ahead (radio warning, ground report, RWR cue).
3. **Never spawn in sight:** at least 5 km and out of line of sight for ground, at least 20 nm
   for air.
4. **Shuffle-bag variants.** Each beat lists 3–5 line variants, and the runtime never repeats one
   until the bag is empty.
5. **Keep hidden adaptation small** (`director.adaptive`): ±1 tier at most; never adapt the climax.
6. Each play should differ in at least 3 ways: pool picks, positions, optional encounters, timing
   jitter, ambient lines.

## Director intent

Write the tension curve in the spec `notes` as `T+min: event` lines from the first guaranteed
beat (hook ≤3 min, 2–3 rising peaks, climax last), then set `dynamic.director.intensity`:
`calm` (first mission, recon, transport, night), `moderate` (default), `intense` (TIC, defend,
act climax; at most 1 in 3 missions, never 3 in a row: `intensity_streak`). Table and gains:
guide §4.
