# Tacview-powered debriefs (DCS)

Status: idea, liked by the user 2026-10-27 · not scheduled

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
- File sizes and parsing speed for 1–2 hour flights.
