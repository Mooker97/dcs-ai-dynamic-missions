# Briefing and kneeboard format

The briefing (`briefing.md`) becomes the DCS briefing text. The kneeboard (`kneeboard.md`) is
rendered onto a kneeboard page. Target 350–600 words for the briefing and ≤25 lines for the
kneeboard. The full must-have checklists are in the guide §3
(`docs/reference/mission-design-guide.md`); `dms validate` lints the mechanical parts
(`briefing_missing_sections`, `briefing_threat_mismatch`, `kneeboard_contradiction`,
`kneeboard_too_long`).

## Header

```
**Classification:** fictional training material · **Date/Time:** 14 MAR, 0615L · **Callsign:** Dusty 1-1
**Duration:** air start ~35 min, ramp start ~60 min
**Stakes:** if the column reaches the bridge, the partner force withdraws from the valley.
```

The classification line always says fictional unless the mode is historical and the text is
sourced. The lint looks for a duration line ("Duration", "flight time", "~N min") and a stakes
line ("Stakes", "if we fail"). Stakes use the bible's stakes vocabulary: fail forward, said aloud.

## Intelligence narrative (before paragraph 1)

Two or three short paragraphs in the S2's voice, plain and declarative:
1. What changed since last mission (from continuity.md and outcomes), as a conditional block. Name
   the outcome that caused it.
2. What the enemy is probably doing and why. Separate assessment from fact ("assessed", "reported",
   "confirmed").
3. What we don't know: the gap this mission fills (it seeds the optional encounters).

This is where story lives in the briefing. Keep it in the register of a staff officer, not a novelist.

## The five paragraphs (use `## 1. Situation` … `## 5. Command & signal` headings)

1. **Situation**
   - Enemy: disposition, strength, capabilities, most likely and most dangerous course of action.
     List every known or telegraphed threat (`hidden_on_map: false`, or with a telegraph beat) with
     location, type and **the cue the player gets** (RWR symbol / no RWR / JTAC report). Hint at
     hidden ones only as uncertainty.
   - Friendly: adjacent units, support (tower, ops, ground teams, other flights), and who is on the net.
   - Civilians / attachments: anything that constrains fires.
2. **Mission:** one sentence: who, what, when, where, why.
3. **Execution**
   - Commander's intent: purpose, key tasks, end state. One short paragraph.
   - Concept of operations: phases (departure, ingress, on-station, egress, recovery), with push,
     vul/TOT window and playtime.
   - Tasks for each flight.
   - Coordinating instructions: ROE (PID, no-fire areas, danger-close procedure), altitude blocks,
     abort criteria, joker/bingo, time on station.
4. **Administration & logistics:** loadout, fuel, start type per variant, divert field, CSAR/medevac.
5. **Command & signal:** table of agency, callsign, frequency (with AM/FM) and TACAN, codewords,
   authentication, lost-comms procedure.

## Frequencies

Write the numbers from the spec (`player_flights[].frequency_mhz`, `support[].frequency_mhz`,
`tacan`) directly. Agencies with no spec number (Ops, Tower, a JTAC or AWACS without
`frequency_mhz`) get one from `dms plan` (CONTRACTS "Planner comms plan": deterministic,
non-colliding, in a band the aircraft can tune, Tower = the airbase ATC frequency). Copy them
from `out/plan.json` `comms`, or write `TBD (plan)` on the agency's line: `dms build` fills it
with that agency's frequency, and the build adds a COMMS kneeboard page either way. FM below
88 MHz (JTAC), AM otherwise.

## Kneeboard

A lineup card plus mission data in shorthand, ≤25 non-empty lines, one page:
- callsigns and flight positions; time hacks (push / TOT / vul)
- **comms table** (agency, callsign, MHz + AM/FM, TACAN) with the same numbers as the briefing
- bullseye, joker and bingo (tied to the divert), laser code, abort codeword
- threats with their RWR symbol or "no RWR"
- CAS missions: a 9-line block with lines 4, 6 and 8 blank to copy
- CSAR: survivor callsign, authentication placeholder, word of the day

Nothing in the kneeboard may contradict the briefing (frequencies, laser code, bingo, callsigns).

## Conditional text

`dms build` renders `briefing.md` and `kneeboard.md` against the campaign state at plan time: the
plan's `DMS_CONFIG.qualities` (from `state/qualities.yaml` `values`) and `DMS_CONFIG.flags` (its
`flags`, written by `dms debrief` as `<mNN>_<outcome key>` and `<mNN>_<result>`). Put each
directive on its own line:

```
<!-- if intel >= 2 and not m01_player_lost -->
The MQ-9 mapped the Quarry; target photos are on your kneeboard.
<!-- elif m01_window_held -->
The ground team held the window; expect the site where they reported it.
<!-- else -->
No fresh imagery.
<!-- endif -->
```

- Conditions use the `quality_effects` term grammar: terms joined by `and` / `or` (`and` binds
  tighter, no parentheses), each `[not] <key>` or `<key> <op> <number>` (`>= <= > < == !=`).
- Keys are quality ids and campaign flag names (`mNN_<key>`). Unknown keys are false / 0, so
  before m01 is flown every `m01_` flag is false: make the `else` branch read sensibly. A quality
  and a flag with the same name: the quality wins.
- Blocks can nest. An unparseable condition or an unbalanced `if` / `endif` fails the build.
  Other HTML comments are left alone.
- Use this for the "what changed" paragraph, for the previous mission's failure flag, and for
  threats whose status depends on earlier outcomes. Keep every branch consistent between briefing
  and kneeboard.

## Style

- Short sentences, active voice, military shorthand where it is standard (AO, FOB, RTB, ROE, BDA).
- Times local with `L` suffix, distances in NM for air and km/m for ground, altitudes in feet.
- "Bullseye", never "bulls". No invented precision: positions the planner sets (exact steerpoint
  coordinates) are "see kneeboard / F10".
