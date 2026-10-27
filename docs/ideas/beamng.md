# BeamNG.drive backend

Status: idea, liked by the user 2026-10-27 · next backend candidate after Arma (see
[ADR 0012](../adr/0012-multiple-game-backends.md)) · not scheduled

## Why it fits DMS

- **Scriptable:**
  - scenarios and missions in Lua, plus the Flowgraph visual editor used by career-mode missions [?]
  - driving AI (chase, flee, follow, traffic, scripted waypoints) [?]
  - ambient traffic and a police pursuit system [?]
- **BeamNGpy:** an official Python API that can build scenarios, spawn and control vehicles, read
  sensors and damage, and drive AI from code [? it targets BeamNG.tech; compatibility with
  BeamNG.drive still to check]. With it, Claude could build *and test* missions with no human,
  using an AI driver as the player. That's the same loop as the DCS and Arma harnesses.
- **Soft-body damage:** missions can score *how much* damage you took (fragile cargo, careful
  driving), which suits the user's preference for realism.

## What carries over from DMS

- Director/pacing (traffic density, police aggression, roadblocks)
- Seeded randomness
- Voice (dispatcher, co-driver, scanner via ElevenLabs + radio FX)
- Later, the story pillar (jobs chaining into a campaign)
- The headless-testing approach

## Mission ideas

1. **Tow Truck Shift:** dispatch calls, drive through live traffic, hook the wreck, return to the
   yard. Location, wreck, weather and traffic change each run. Realistic, simple, little fragile AI.
2. **Courier Run:** fragile cargo against the clock. Damage cuts your pay. The Director adds road
   closures, crashes ahead and jams.
3. **The Getaway:** reach the safe house while police pursuit escalates (more units → roadblocks).
   Lose them and lie low. Same "win before you're swamped" feel as Arma's The Hill.
4. **Rally Stage Generator:** a random stage on real roads, with generated pace notes read by an
   ElevenLabs co-driver. A showcase for the voice pillar.
5. **Ambulance / Police Patrol:** shift-based calls, priority levels, response-time scoring.

**Recommended MVP:** Tow Truck Shift (simplest, most realistic) or The Getaway (most exciting,
reuses Director escalation, depends more on police AI).

## First steps when picked up

1. Check the installed BeamNG.drive version (Steam, `E:\SteamLibrary`) and whether BeamNGpy can
   connect to and control it. If not, check what a Lua-only harness could do instead.
2. Research the mission/scenario format (career missions, Flowgraph, plain scenario JSON + Lua)
   and pick the simplest one we can generate.
3. Build a smoke test: generate a scenario, spawn a car, AI drives A→B, read the log/state back.
4. Write a `docs/beamng/PLAN.md` in the same style as `docs/arma/PLAN.md`.
