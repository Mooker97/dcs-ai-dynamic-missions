# Arma 3 MVP plan

Status: in progress · decided with the user 2026-10-27

## Goal

One mission that feels like real soldiering: lead a squad, shoot bad guys, call support, get out.
Story, dialogue and voice are deliberately **out of scope** for now ("I don't want to focus on the
talking side of things just yet").

## Decisions

| Decision | Choice | Why |
|---|---|---|
| Game | Arma 3 (not Reforger) | Mature SQF scripting, built-in squad command, free bundled dedicated server for headless tests |
| Players | Solo, leading an AI squad | Simplest to build and test |
| Mods | Vanilla, base game only | Easy to run, test and share |
| Feel | **Grounded realism over "fun"** | User: "it doesn't need to be that fun, I want it to feel kinda realistic" |
| Scope | Small and simple | The user rejected two richer versions as too complex (see history) |

## The mission: "The Hill" (`arma/missions/dms_the_hill.Altis`)

1. Squad (6 AI + player as team leader) starts on foot about 1 km from the objective.
2. Assault a small CSAT-held compound (one of 2–3 sites, chosen by seed).
3. Retrieve intel (laptop/documents) with a hold action.
4. QRF: triggered by detection or intel pickup. Wave 1 (truck + infantry) arrives 5–8 min later,
   dismounts short and flanks. Wave 2 (APC) only if the fight drags on.
5. Limited artillery through the comm menu: processing delay, time of flight, dispersion,
   spotting round, refuses danger-close.
6. Call extraction. The heli holds off while the LZ is hot, lands, waits a limited time, then
   takes the squad out → success. Fail if the player dies or the heli is destroyed.

Realism tuning: realistic squad composition, no respawn, AI with good spotting but low aim
accuracy, garrison that holds positions, approximate area markers only. Recommended difficulty is
Veteran with no crosshair.

## Milestones

| | Milestone | Verified by |
|---|---|---|
| M1 | Spawns + assault | Headless run: spawns logged, no script errors |
| M2 | Intel + QRF | Test mode: intel PASS, QRF waves PASS |
| M3 | Artillery + exfil + end states | Test mode: fire missions, heli lands/departs, outcome success; forced-failure run |
| M4 | Multi-seed soak + **user playtest** | 3+ seeds pass headless; user plays it (comm menu/hold action/feel) |

The harness lives in `tools/arma_harness/` and is documented in `docs/arma/TESTING.md`. Verified
reference data is in `docs/arma/kb/`.

## How it was decided

1. Story-first pitches (Ferryman, Dead Ground, Signal Fire, Bounty) were rejected as too much story.
2. Combat pitches: Hammer and Anvil, The Bridge, Lights Out, Downed Bird, Convoy Breaker. The user
   picked **Lights Out**, made it daytime, and swapped the waking garrison for a QRF clock.
3. Variants: The Hill (chosen), The Compound, Three Launchers. The AA objective was then swapped for
   a HVT with an intel pickup.
4. **Cut to the current design.** The user found the HVT, tank and escalation version too complex:
   "just assaulting somewhere with a QRF, retrieve the intel, call in help, get out".

The rejected ideas are good candidates for later missions built from the same parts:
- Downed Bird (CSAR hold)
- Convoy Breaker (ambush)
- The Bridge (seize and hold, with a tank reinforcement)
- Three Launchers (multi-objective with escalation)
- The tank and heli insertion

## Later: generalise into DMS

Keep The Hill hand-tuned until it plays well. After that, an Arma backend would take a generic
mission spec and write `fn_config.sqf` (every tunable already lives there). That reuses the DMS
ideas: seeded randomness, pacing/director, the headless test harness, and later story and voice.
See [ADR 0012](../adr/0012-multiple-game-backends.md).
