---
name: dms-quickstart
description: Go from a one-line premise to a flyable DCS mission (or a whole campaign) in a few prompts. Use when the user says "make me a mission about X", "quick mission", "A-10 CAS over the Caucasus", "give me a campaign about X", "print me a mission", "just build something I can fly", or otherwise wants a .miz without driving each DMS skill by hand. Orchestrates story-writer -> campaign-planner -> mission-designer -> dms run -> dms install and ends with a how-to-fly card.
---

# dms-quickstart

Take a premise and hand back a `.miz` that is already in the DCS Missions folder, asking the user
**at most one batched round of questions**. This skill runs the other DMS skills in order. It does
not replace them: follow each skill's own steps and quality bar, but skip their interviews
because this skill already did that.

## 0. Pre-flight (5 seconds)

```
uv run dms doctor
```
- Any **FAIL**: fix it (the `fix:` hints say how) or stop and tell the user.
- WARN `elevenlabs key`: voice isn't possible, so the mission gets subtitles only. Don't ask about voice.
- WARN `dcs saved games`: the build still works, but `dms install` will create the folder. Say so.

## 1. One batched question round (or none)

Pull every answer you can out of the premise. Ask only about what's still missing, in **one message**
with the defaults shown, so the user can reply "go" / "defaults". If the premise names an aircraft
and a map, or says "just do it" or "surprise me", **skip the round** and use the defaults.

| Question | Default |
|---|---|
| Aircraft (DCS module) | from the premise, else `F-16C_50` |
| Map | from the premise, else the aircraft's usual map (A-10C II / AH-64D: Caucasus, F-16C: Syria) |
| Era (year) | 2016 for modern jets, else the aircraft's era (`uv run dms catalog units --role attack`) |
| How many missions | **1** (single-mission fast path). "campaign" means 3 |
| Design all missions now, or just m01? | m01 only (later missions get designed after you fly, from what happened) |
| Voice? | **no** (subtitles only). If yes, give a cost cap in USD, default $3 |
| Start | both a ramp and an air start (two `.miz` files) |

Always write the answers (or "defaults accepted") into `premise.md`'s interview table.

**Aircraft support.** `loadout: auto` resolves to a real preset only for the airframes in
`packages/dms-gen/src/dms_gen/builder/payloads.py`: F-16C_50, A-10C_2, AH-64D_BLK_II, Mi-8MT,
UH-1H, CH-47Fbl1, Mi-24P, Ka-50, Ka-50_3, SA342M and OH58D (preset names: mission-designer
`references/player-flights.md`). Any other airframe spawns with the **DCS default payload, often
clean pylons**. If the user picks one, say so in the question round and in the fly card ("rearm
on the ramp: ramp start only"), and default to the ramp variant.

**Coalition.** The player's DCS coalition is the one the catalog gives the airframe
(`uv run dms catalog units --era <year> --category plane|helicopter`), whatever the politics:
an Mi-8MT or Ka-50 crew is red, so its enemies go on blue. story-writer records this in
`canon_rules`.

## 2. Story (story-writer skill)

Follow `.claude/skills/story-writer/SKILL.md` steps 2-8, using the answers from section 1 for
its interview. Step 2 runs `uv run dms new-campaign <slug>`; delete `missions/m01-example/` and
`state/outcomes/mNN-example.yaml` after it.
- Mode `fictional` unless the premise is a real operation. With 1 mission, use 3-4 characters
  (ops, JTAC or controller, AWACS, tower) and skip research for fictional mode.
- The story-writer's strict voice enums and library `eleven_voice_id`s apply even with voice
  off: they cost nothing and keep a later `dms voice` working.

## 3. Arc (campaign-planner skill)

Follow `.claude/skills/campaign-planner/SKILL.md`.

**Single-mission fast path.** Use the planner's one-act, one-mission arc ("Single sortie"
section): `branches: []`, one quality, machine-grammar `quality_effects`. Still write
`state/qualities.yaml`, so `dms debrief` works afterwards and the arc can be extended later.
A requested count of N means N main-line missions; optional branch missions are extra.

For N > 1 missions, plan all N, but design only m01 unless the user asked for all of them
(section 1).

## 4. Mission (mission-designer skill)

Follow `.claude/skills/mission-designer/SKILL.md` for m01, and then for each further mission if
the user asked for all of them. Its pitfalls section covers country names, template checks,
callsigns, frequencies and the spine timeout. Quickstart budget: about **15-20 beats with 3
variants each**, which is enough for the spine, its timeout fallbacks and a few reactions.

`uv run dms validate <mission dir>`: fix all errors and the lint warnings you can, max 3 loops.
It must end `OK: 0 error(s)`, with each remaining warning accepted for a stated reason.

## 5. Voice (only if the user opted in)

Follow `.claude/skills/voice-director/SKILL.md` steps 1-4:
```
uv run dms voice <mission dir> --dry-run
```
The first line gives credits. Convert to dollars at about $0.30 per 1k credits (the worst case,
overage rate). If the cost is **under the user's cap**, render (`uv run dms voice <mission dir>`)
without asking again, since the cap counts as approval. Over the cap, skip it and say what it
would cost. A 1-mission quickstart is about 50 lines and 4k characters, which is roughly $1.20.

## 6. Build + install

```
uv run dms run <mission dir> --skip-voice --install        # voice off, or already rendered
uv run dms run <mission dir> --install                     # voice on and under the cap
```
`run` does validate -> voice -> plan -> build -> check. It writes `out/<id>-ramp.miz`,
`out/<id>-air.miz` and `out/<id>.miz` (a copy of the first variant), checks every variant, and
`--install` copies them all to `Saved Games\DCS[.openbeta]\Missions\DMS\<slug>\`.
- `--dcs auto` (the default) picks the Saved Games folder with the newest `Logs\dcs.log`. Pass
  `--dcs openbeta` / `--dcs stable` if the user says otherwise.
- To preview the copy first: `uv run dms install <mission dir> --dry-run`.
- A check WARNING about "voice lines have no audio (subtitles only)" is expected without voice.
  Any other check finding goes back to the dms-build skill (step 6) before you hand anything over.
- For several missions, run `dms run ... --install` for each one. They share the campaign folder in DCS.

## 7. The fly card (print exactly this shape, at most 20 lines)

Fill it from `out/plan.json` (player group `radio_callsign`, `frequency_mhz`, support radios),
the spec and the install output:

```
READY: <title> (<campaign slug> / <mission id>)   implemented, not flown
DCS:    Mission > Open > Missions\DMS\<slug>\
        <id>-ramp.miz  cold start on the ramp at <base>
        <id>-air.miz   air start <alt>/<kts>, <N> NM short of <IP>
Slot:   <radio_callsign> (lead = you, wingman AI)   loadout <preset or DCS default>
Radios: flight <MHz AM> | AWACS <callsign> <MHz> | JTAC <callsign> <MHz FM> | tanker <..> TACAN <..>
Flow:   <3-5 word phases, e.g. IP MULE -> Darkstar -> Bulldog 9-line -> column -> Shilka -> RTB>
F10:    JTAC marks and targets appear on the F10 map; kneeboard RShift+K
Log:    <Saved Games>\DCS\Logs\dcs.log  look for "[DMS]" banner, no "[DMS][..] ERROR",
        "[DMS.OUTCOME]" lines at the end
After:  say "debrief m01" (debriefer skill) BEFORE relaunching DCS
```

Then stop. Don't claim the mission works: until someone flies it, report "implemented, not flown".

## What the user types

1. `/dms make me a mission: A10C CAS over Caucasus` (or any one-line premise)
2. (only if asked) `defaults` / `go`, or the answers to the one batched question
3. after flying: `debrief m01`

## Checklist

- [ ] `dms doctor` has no FAIL
- [ ] At most one question round; the answers are recorded in premise.md
- [ ] Player coalition from the catalog rule, recorded in `canon_rules`
- [ ] bible, arc (`dms validate arc.yaml`) and qualities validate; m01 (or all missions) `dms validate` OK with lint warnings fixed or accepted (max 3 loops)
- [ ] Voice rendered only if the user opted in and the estimate was under the cap
- [ ] `dms run --install` DONE; every variant checked; install path printed
- [ ] Fly card printed and marked "implemented, not flown"; debriefer suggested
