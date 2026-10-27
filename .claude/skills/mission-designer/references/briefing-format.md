# Briefing and kneeboard format

The briefing (`briefing.md`) becomes the DCS briefing text. The kneeboard (`kneeboard.md`) is
rendered onto a kneeboard page. Target 350–600 words for the briefing and ≤25 lines for the kneeboard.

## Header

`**Classification:** fictional training material · **Date/Time:** 14 MAR, 0615L · **Callsign:** Dusty 1-1`

The classification line always says fictional unless the mode is historical and the text is sourced.

## Intelligence narrative (before paragraph 1)

Two or three short paragraphs in the S2's voice, plain and declarative:
1. What changed since last mission (from continuity.md and outcomes). Name consequences.
2. What the enemy is probably doing and why. Separate assessment from fact ("assessed", "reported",
   "confirmed").
3. What we don't know: the gap this mission fills.

This is where story lives in the briefing. Keep it in the register of a staff officer, not a novelist.

## The five paragraphs

1. **Situation**
   - Enemy: disposition, strength, capabilities, most likely and most dangerous course of action.
     List every known threat (`hidden_on_map: false` in the spec) with location and type; hint at hidden ones only as uncertainty.
   - Friendly: adjacent units, support (tower, ops, ground teams, other flights), and who is on the net.
   - Civilians / attachments: anything that constrains fires.
2. **Mission:** one sentence: who, what, when, where, why.
3. **Execution**
   - Commander's intent: purpose, key tasks, end state. One short paragraph.
   - Concept of operations: phases (departure, ingress, on-station, egress, recovery).
   - Tasks for each flight.
   - Coordinating instructions: ROE, altitude blocks, no-fire areas, abort criteria, bingo, time on station.
4. **Administration & logistics:** loadout, fuel, start type, divert field, CSAR/medevac.
5. **Command & signal:** table of agency, callsign and frequency (`TBD (plan)` before `dms plan`),
   codewords, authentication, lost-comms procedure.

## Kneeboard

Repeats paragraphs 3–5 in shorthand: a phase table, ROE, bingo/abort, the comms table and codewords.
Nothing in the kneeboard may contradict the briefing.

## Style

- Short sentences, active voice, military shorthand where it is standard (AO, FOB, RTB, ROE, BDA).
- Times local with `L` suffix, distances in NM for air and km/m for ground, altitudes in feet.
- No invented precision: if `dms plan` sets it, write `see kneeboard` or `TBD (plan)`.
