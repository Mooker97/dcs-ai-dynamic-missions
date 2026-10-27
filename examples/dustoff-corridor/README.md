# Dustoff Corridor (reference mission, v0.4 vertical slice)

Syria, AH-64D. The player escorts the BLUE ground convoy `Convoy-Main` along the corridor
Alpha -> Bravo -> Charlie -> FOB-Victory. The Mission Editor holds only the player, the convoy,
a late-activated `A-10 CAS` flight, and five trigger zones. A single Lua file creates every
enemy at runtime from code-built templates. This is the mission the v0.4 vertical slice has to
reproduce from a `MissionSpec` with the new `lua/src/dms/` runtime and a generated `DMS_CONFIG`.

- **Win:** any convoy vehicle reaches `FOB-Victory` (flags 116 + 101).
- **Lose:** the convoy is destroyed, or the player crashes, ejects or dies (flag 102).

## Files

| File | What it is |
|------|------------|
| `dustoff-master-init.lua` | Legacy single-file build (~1950 lines): settings, error handling, utils, fog of war, unit templates, dynamic spawn + hunting, SAM ambush, reinforcements, and the mission config. Loaded by one `DO SCRIPT FILE` trigger (ONCE, TIME MORE 5). |
| `MISSION-SETUP.md` | ME requirements: group and zone names, flags, mission options, tuning knobs, test checklist |
| `VOICE-LINES.md` | Original voice script: Convoy Actual + Hawg One-One, flags 100-127, ElevenLabs voice prompts |
| `voice_lines.yaml` | `VOICE-LINES.md` converted to the `VoiceLineSet` shape (21 lines and their variants) |
| `AUTOMATION-PLAN.md` | Earlier design notes for the zone-only, script-spawned setup |

**Fixture:** `tests/fixtures/miz/dustoff-corridor.miz`. Like the reference build, it still embeds
`dustoff-master-init-v8.lua`, so it may lag behind the `.lua` here.

## Runtime modules it exercises

Each behaviour in the master-init maps to a DMS runtime module (see `docs/CONTRACTS.md`):

| DMS module | Behaviour in this mission (legacy code) |
|------------|------------------------------------------|
| **spawner** | `DMS.UnitTemplates` (about 25 RED group templates: Tunguska, Shilka, ZU-23, MANPADS, T-72, BMP-2, BTR-80, technicals, infantry, QRF). `DMS.DynamicSpawn.createPool/executePool` places groups at a min/max distance from each zone centre, with a per-pool `chance` and a `count` that is always honoured. Initial pools: `sam-site` (Alpha, 10% x1), `alpha-ground` (80% x4), `bravo-armor` (80% x6), `bravo-infantry` (60% x2), `charlie-defense` (80% x5). Spawned groups are hidden on the map. |
| **ground** | Ambush posture for the Alpha/Bravo infantry and Charlie defense pools (hold, ROE open fire, alarm red). Hunting: `bravo-armor` and all QRF groups route off-road to an intercept point ahead of the convoy lead (start within 4 km, re-routed every 30 s). Convoy halt-under-fire: any hit stops the convoy route, which resumes after 50 s with no hits. |
| **encounters** | SAM ambush: `sam-site` groups stay dark until a BLUE player is within 8 km, then have an 80% chance to go hot (re-rolled every 30 s), and go dark again 30 s after the player leaves. QRF: when the convoy enters Charlie or loses 2 vehicles, `qrf-light` (50%), `qrf-medium` (25%) and `qrf-heavy` (10%) roll at `QRF-Staging` and hunt the convoy. A-10 CAS: the late-activated group activates 60-120 s after start in testing mode (25% at 5-10 min for release) and sets flag 119. |
| **intel** | Fog of war: an enemy group counts as detected when a BLUE unit is within 5 km with line of sight, or when the group shoots or is hit. Detected groups get BLUE F10 marks (text + red circle) that refresh every 15 s and are removed when the group dies. Intended for F10 view option "Fog of War". |

Narrative beats come from zone enter/exit tracking (point-in-polygon for quad zones), first
convoy hit, each convoy loss, A-10 check-in and win/loss. In the legacy build each beat sets a
user flag (100-102, 110-119) and shows a placeholder text line. In v0.4 these become `beats` with
lines from `voice_lines.yaml`.
