# Mission design guide: making DMS missions good, not just valid

`dms validate` proves that a mission is consistent. This guide covers whether it is worth flying.
Read it alongside `.claude/skills/mission-designer/references/` (radio-realism, beats-and-encounters,
briefing-format). Where this guide is stricter, it wins. Sources are linked inline. Tags:
**[doc]** doctrine or a doctrine excerpt, **[sim]** sim-community practice, **[forum]** player
feedback (mostly read from search snippets, because forum.dcs.world blocks fetches), **[unv]**
standard practice not confirmed by a fetched source. Research date: 2026-10-29.

## 0. The seven rules that matter most

1. **No single point of failure.** Every gating beat needs a time-based or alternative fallback
   (a "retask", "Ops: say status", or move on at bingo). The biggest complaint about DCS campaigns
   is a mission that stalls "with no in-mission feedback" when a trigger never fires
   ([forum 281112](https://forum.dcs.world/topic/281112-my-review-and-rundown-of-each-mission-spoilers-galore),
   [forum 310953](https://forum.dcs.world/topic/310953-mission-4-missing-scripting-for-breaking-roe/)).
   See "Spine timeout pattern" below. A landing (`unit.landed`) is never a guaranteed beat on its
   own: the air variant may never land, and players divert. Give it a timeout or make it optional.
2. **Gate on wide conditions.** Use big zones, time windows or "any of" conditions, never one
   exact steerpoint. Narrow start zones leave wingmen and AWACS silent
   ([forum 200386](https://forum.dcs.world/topic/200386-mission-13-script-not-firing/)).
3. **Hook within 3 minutes of the first guaranteed beat, and reach the action within 20 minutes.**
   Players tolerate up to about 30 minutes of transit if they can skip it. A long transit
   followed by a 2-minute death is the top reason players quit
   ([forum 121975](https://forum.dcs.world/topic/121975-speeding-up-missions),
   [forum 36263](https://forum.dcs.world/topic/36263-do-you-like-realistic-mission-lengh-in-campaigns)).
   DMS's air-start variant is the checkpoint. Keep it close enough to the action.
4. **Telegraph, then punish.** "The Su-33 appears literally from the void" is a typical complaint
   ([forum 257951](https://forum.dcs.world/topic/257951-mission-15-issue)). Cue each threat with a
   radio call, an RWR cue or a briefing line, 30–60 s before it can engage.
5. **Every transmission has a function.** Baltic Dragon (3,000–4,000 lines per campaign) calls
   random chatter in quiet stretches "not very realistic"
   ([stormbirds Q&A](https://stormbirds.blog/2024/05/09/community-qa-with-dcs-campaign-author-baltic-dragon/)).
   Silence is fine. Filler is not.
6. **Failure branches forward.** Wing Commander players reloaded rather than fly the losing path,
   so that content went unseen ([filfre](https://www.filfre.net/2018/03/wing-commander-ii/)).
   A failure has to be a *different, interesting* mission, not a punishment. State the stakes
   before the attempt ("fail forward",
   [Burning Wheel forum](https://forums.burningwheel.com/t/when-to-call-a-mission-failed-questions-on-failing-forward/15629)).
7. **Partial success counts.** A nearly finished intercept that scores the same as doing nothing
   is a known complaint ([forum 338199](https://forum.dcs.world/topic/338199-feedback-struggle-with-manpads-and-friendly-ai)).
   Emit counts (`sa6_launchers_destroyed: 2`) as well as booleans, and branch on thresholds.

### Spine timeout pattern

A guaranteed beat that waits on a kill, a landing or a flag gets a sibling that sets the **same
flag** after a timeout, and the next spine beat waits on that flag. This is what the lint rule
`spine_no_fallback` looks for (a sibling setting the same flag, or a timely beat with
`requires.beats_not_fired: [<it>]`). viper-detachment m03's `jtac_retask` is the worked example.
Time the fallback from a spine beat (`beat.fired` + `delay_sec`), not from mission start, so it
is the same in the ramp and air variants.

```yaml
  - id: column_destroyed_call       # the kill path
    guaranteed: true
    when: {event: group.dead, group_prefix: column}
    priority: 85
    speaker: jtac
    text: "Python, Jackal, good effect, column destroyed."
    effects: {set_flag: fight_over, outcome: {column_destroyed: true}}
  - id: fight_timeout               # the timeout path: same flag
    when: {event: beat.fired, beat: jtac_checkin}
    delay_sec: 1200
    requires: {beats_not_fired: [column_destroyed_call]}
    priority: 80
    speaker: jtac
    text: "Python, Jackal, enemy breaking contact. Cease fire, stand by for check-out."
    effects: {set_flag: fight_over, outcome: {column_destroyed: false}}
  - id: jtac_checkout               # the spine continues either way
    guaranteed: true
    when: {event: flag, flag: fight_over}
    delay_sec: 15
    priority: 90
    speaker: jtac
    text: "Python, Jackal, BDA follows. Cleared to RTB."
    effects: {set_flag: checkout_done}
```

Add a "say status" nudge (an Ops beat with `requires.beats_not_fired` on the next spine beat)
after about 4 minutes with no progress.

### Setup rules the lint can't see

- **Player coalition = the catalog side of the player aircraft**, whatever the politics.
  `uv run dms catalog units --era <year>` lists each type's coalition (Mi-8MT, Mi-24P and Ka-50
  are red; F-16C, A-10C, AH-64D, UH-1H and CH-47 are blue). Record it in the bible's
  `canon_rules` ("Player coalition red: the Mi-8MT is red-only in DCS") and put the enemies on
  the other side, even if that puts, say, Abkhazia on blue.
- **Frequencies are authored, never `TBD (plan)`.** Every `frequency_mhz` in the spec (flight,
  support, JTAC) goes straight into the briefing comms table and the kneeboard. Towers use the
  airbase catalog frequencies (`uv run dms catalog airbases`); an Ops speaker with no unit uses
  a frequency you choose and state.
- **Pin what the briefing names.** If the briefing says "ZU-23", pin `templates` (check with
  `uv run dms catalog templates --role <ThreatRole>`), then confirm the type in `out/plan.json`.
- **Quick-mission size:** a one-off quickstart mission is about 15–20 beats with 3 variants
  each. A campaign mission can go bigger, but every beat still needs a function.

## 1. Per-role templates

Times are **T+min from the first guaranteed beat** (CP or push check-in), which is the same in
the ramp and air variants. Ramp-only extras (Ground, Tower, departure) come before T+0 and are
never guaranteed. Each template lists the beat spine (G = guaranteed), the comms flow, typical
threats, and the outcome keys to emit.

### 1.1 SEAD / DEAD (F-16C, F/A-18C)

Doctrine: SEAD pushes about 2 min ahead of the strikers and stays until they are off target.
Flights are spaced about 2 min apart, each with push, IP and TOT times
([vcaw1](https://vcaw1.com/forum/viewtopic.php?p=853),
[BMS forum](https://forum.falcon-bms.com/post/184338)) [sim]. Time HARMs to the strike TOT.
Two shooters staggering shots about 5 s apart keep roughly 45 s of HARMs in the air
([BMS forum](https://forum.falcon-bms.com/post/303124)) [sim]. SEAD succeeds when the strikers
take no losses.

| T+ | Beat | Speaker / line shape |
|---|---|---|
| 0 | G `checkin` | AWACS: "Python, Magic, radar contact, picture clean." |
| 1 | `fence_in` | wingman: "Two, fence in." |
| 2–4 | `elint_cue` (telegraph) | Ops/ELINT: "Python, Ops, SA-6 search radar active, bullseye one-four-zero, twelve." |
| 4 | G `vul_open` | Ops: "Window open. Striker push in two minutes." |
| 5–14 | reactions: `mud_spike`, `magnum`, `defending`, `singer` | wingman: "Two, mud spike, two o'clock, Six." / "Two, magnum." |
| on kill | G-or-timeout `emitter_down` | Ops: "SA-6 radar off the air." |
| 14 | G `vul_close` (fallback by timer) | Ops: "Window closed, strikers off target." Outcome: `window_held`. |
| 15+ | DEAD phase (optional) | visual BDA, GBU follow-up |
| egress | G `rtb` | Ops or AWACS |

Threats: one pinned radar SAM (sa6/sa8/sa11 template) plus a pop-up (`ambush_sam`) plus AAA.
Never give the pop-up a line of sight to the spawn point of a jet below 10,000 ft. Keys:
`radar_destroyed`, `launchers_destroyed: N`, `window_held`, `striker_lost`.
Common mistake: a "window held" beat that waits for a kill. Hold the window on a timer, and make
the kill a separate optional beat.

### 1.2 Strike / interdiction

Flow: push at time, then IP, then TOT, then egress. Brief the FROTIES (formation, roles,
ordnance, timing, ingress/egress, sort; [UOAF codex](https://codex.uoaf.net/index.php/Doctrine)) [sim].

Beats:
- G `push` ("Python, Ops, push. TOT one-four-three-zero.")
- `ip_inbound`
- telegraphs: `aaa_active`, `mud_spike`
- G `tot` or `target_destroyed` (timeout fallback: `tot_missed`, with a re-attack or retask)
- `bda` ("Ops copies, two of three bunkers destroyed.")
- G `egress` / `rtb`

Threats: point-defence AAA and MANPADS at the target, a SHORAD on the egress axis, an optional
enemy CAP (telegraph through AWACS "pop-up group" calls). Keys: `targets_destroyed: N`,
`collateral_hits: N`, `tot_met`.

### 1.3 CAS with a JTAC (the richest template; see m03 for a worked example)

**Aircrew check-in** [doc/sim]: mission number, number and type of aircraft, position and
altitude, ordnance, playtime, capabilities, abort code
([JTF Fatal](https://joint-task-force-fatal.readthedocs.io/en/latest/aviation/jtac_communications.html),
[Fighter Sweep](https://fightersweep.com/3889/what-close-air-support-is-and-isnt-part-two/)).
The player says this, so don't voice it. Have the JTAC reply as if he heard it ("Python, Jackal,
copy two Vipers, playtime four-zero").

**JTAC situation update**: target, enemy threats, friendlies, ordnance, restrictions, remarks,
SEAD and hazards. **Game plan**: type of control plus method ("Type 2, bomb on target").

**9-line** (line numbers are understood and not spoken):
1. IP/BP
2. heading and offset
3. distance
4. target elevation (ft MSL)
5. target description
6. location (grid, or "per talk-on")
7. mark type and laser code
8. friendlies (cardinal direction plus metres)
9. egress

Then **remarks/restrictions**: final attack heading, danger close, hazards, TOT.

**Readback**: lines 4, 6 and the restrictions. The JTAC answers "good readback"
([legalclarity](https://legalclarity.org/9-line-cas-brief-standard-close-air-support-request-format/)) [doc excerpt].

**Control types**:
- Type 1: JTAC sees both the aircraft and the target. "Cleared hot".
- Type 2: JTAC sees one of them. "Cleared hot".
- Type 3: multiple attacks inside a window. "Cleared to engage".

**Attack calls**:
- "Python one-one, IN from the west, tally target." Answers: "Cleared hot" / "Continue" /
  "Abort, abort, abort".
- "One-one OFF north."
- Corrections from the last hits: "From lead's hits, fifty metres north."

**Laser** [unv sequence]: aircraft "TEN SECONDS" → "LASER ON" → JTAC "LASING" → aircraft "SPOT"
→ after impact "TERMINATE".

| T+ | Beat |
|---|---|
| 0 | G `ops_tasking` (TIC, contact the JTAC) |
| 1 | G `awacs_handoff` |
| 2 | G `jtac_checkin` + situation update (breathless; gunfire is audible in the text) |
| 4 | G `nine_line_1` |
| 5 | `readback_ok` |
| 6 | G `talk_on_1` |
| 8 | G `cleared_hot_1` |
| 9 | `bda_1` |
| fallback | `retask` at +8 min if there is no hit, so the spine never stalls |
| 10–20 | `nine_line_2` (escalation: danger close, initials); assault waves; `check_fire` reaction on a civilian or friendly hit |
| 20–25 | G `checkout`: BDA summary ("two compounds destroyed, assault broken") |
| egress | G `rtb` |

Rotary-wing CAS uses a **5-line** from a battle position (warning order; friendly location and
mark; target location; target description and mark; remarks) (JTF Fatal) [sim].
Threats: MANPADS (no RWR cue, so telegraph through the JTAC: "possible SAM team, south farms"),
AAA, an IR SHORAD. Keys: `assault_broken`, `targets_destroyed: N`, `fratricide`, `civilians_hit: N`.

### 1.4 CAP / escort / sweep

AWACS phraseology ([Hoggit GCI](https://wiki.hoggitworld.com/view/Gci)) [sim]:

- **Picture** in bullseye format: "Python, Magic, picture, two groups azimuth one-five. North
  group bullseye zero-four-zero, three-five, two-five thousand, hot, hostile."
- **BRAA** to one flight: "BRAA one-eight-three, ten, two thousand, hot". There is no "for" or
  "at". Aspect is hot, flank, beam or drag.
- **Answers to a declare**: friendly, bogey, bandit, hostile, clean.
- **Event words**: "Pop-up group", "Fade", "Merged", "Commit", "Leaker", "Scram".
- Always say "bullseye", never "bulls".

Beats:
- G `on_cap`
- `picture_clean`, re-called every 5–8 min as ambient (a heartbeat; prevents dead-air anxiety)
- telegraph `pop_up_group` (AWACS, 40–60 NM out)
- `commit` (Ops or AWACS: "Python, commit, north group")
- `merged`, `splash` (A2A), `fade`
- G `vul_end` (timer)
- G `rtb`

Escort adds `package_push` and `striker_off_target`.
Keys: `bandits_killed: N`, `leakers: N`, `asset_lost` (HVAA or striker).
Spawn rule: enemy air at least 20 NM away and out of the player's radar cone at spawn
(an existing DMS rule).

### 1.5 CSAR

- Sandy 1 is the rescue mission commander (RMC) and on-scene commander. Sandies find the
  survivor, bring the helos forward, and sit between the survivor and the threat
  ([Defense News](https://www.defensenews.com/news/your-military/2026/04/16/combat-search-and-rescues-uncertain-future-as-a-10s-phase-out-us-air-force-faces-questions-of-what-comes-next/)) [doc/press].
- AWACS coordinates.
- The survivor authenticates with ISOPREP data: personal questions and a 4-digit number with no
  zeros, no repeated digits and no runs of three
  ([NPS ISOPREP](https://nps.edu/documents/103449429/109534689/1.1+CCMR+ISOPREP+Instructions_2017.pdf)) [doc].
- "Word/number of the day" codes come from the SPINS [unv].

Beats:
- G `survivor_beacon`
- G `survivor_voice` (a whisper: "Sandy, Hammer two-one, in the treeline, I hear trucks.")
- `authenticate` (Sandy asks an ISOPREP question; the survivor answers)
- `threat_near_survivor` (a hunt encounter, telegraphed by the survivor)
- G `helo_inbound` ("Jolly one-one, five minutes")
- `pickup` (`unit.landed` near the survivor, with a timeout fallback: "survivor moved, new
  position")
- G `rtb`

Keys: `survivor_recovered`, `survivor_captured`, `helo_lost`. Failure branch: a
hostage/recovery mission, never game over.

### 1.6 Helicopter air assault / insertion (AH-64D, UH-1H, Mi-8, CH-47)

The Air Mission Brief covers route, PZ/LZ and landing points, loads and chalks, formation,
lighting, lost comms, IIMC breakup, downed-aircrew pickup points, escort and FARP
([229 hub](https://229.gitbook.io/229-hub/knowledge/army-aviation-fundamentals/multi-aircraft-operations/planning-considerations-and-responsibilities)) [sim].
REDCON 1 is reported in reverse chalk order. Lift needs at least 5 s of warning [flashcard, unv].

Beats:
- G `pz_lift` ("Chalk one, lift")
- `sp_passed`
- `rp_one_minute` [unv: "one minute"]
- telegraph `lz_hot` (escort or pathfinder: "LZ taking sporadic fire, east treeline")
- G `wheels_down` (`unit.landed` in LZ, with a timeout fallback "go around, alternate LZ")
- `troops_off`
- G `lift_lz`, G `rtb_farp`

Threats: small arms, RPG, ZU-23, MANPADS on the route. Keep everything at least 5 km away and out
of line of sight at spawn. Keys: `troops_delivered: N`, `lz_used` (primary/alternate),
`aircraft_damaged`.

## 2. Radio cheat-sheet (verified definitions, Wikipedia paraphrase of ATP 1-02.1)

Source: [Multi-service tactical brevity code](https://en.wikipedia.org/wiki/Multi-service_tactical_brevity_code).
The authoritative text is ATP 1-02.1 (Apr 2025) at [alssa.mil](https://www.alssa.mil/MTTPs/Brevity/).

| Word | Meaning | Word | Meaning |
|---|---|---|---|
| MAGNUM | friendly anti-radiation missile launched | MUD SPIKE | RWR: surface threat tracking ("mud spike two o'clock, Six") |
| SPIKE | RWR: airborne radar track | NAILS | RWR: airborne radar search |
| BUDDY SPIKE | RWR: friendly radar | SINGER | RWR: SAM launch |
| NAKED | no RWR indications | DEFENDING | defensive manoeuvre ("defending south, missile") |
| RIFLE | A/S missile launch | FOX 1/2/3 | SARH / IR / active A/A missile |
| SPLASH | A/A kill, or A/G weapon impact | TRASHED | friendly missile defeated |
| WINCHESTER | no ordnance | JOKER / BINGO | fuel to start leaving / to recover |
| TALLY / NO JOY | enemy or target seen / not seen | VISUAL / BLIND | friendly seen / not seen |
| CONTACT | sensor contact, or a reference point found | CAPTURED | target acquired in a sensor [unv] |
| FENCE IN / OUT | combat checks on / off | PUSH | switch frequency, or proceed |
| SORTED | sort complete | COMMIT | intercept the group |
| JUDY | aircrew has the intercept (controller goes quiet) | POP-UP | group appearing inside threat range |
| FADED / VANISHED | contact lost / lost and correlated to a shot | MERGED | in the visual fight |
| LEAKER | threat through the defensive layer | SCRAM | withdraw now |
| ANGELS / CHERUBS | thousands MSL / hundreds AGL | BUSTER / GATE | max continuous / afterburner |
| PUMP / BUGOUT | turn away to re-engage / leave for good | BENT / SWEET | system inoperative / working |
| SKIP IT | do not engage | IN / OFF | attack run starting / finished, plus direction |

- **Not in the ATP list**: "pickle" and "shack" (old slang, so avoid them in crisp professional
  voices). Also "punch out", "Texaco" (a callsign), "Sandy" (a role or callsign), "Atoll" (a
  NATO missile name), "splash one, hell yeah" (never).
- **Formats**: callsign of the station called, then your own, then the message. Numbers digit by
  digit ("one-four-zero"). Altitudes "angels two-five" or "two-five thousand". AWACS gives
  bullseye bearing and range.
- **Frequency**: limit AWACS calls on the net to the picture, threat calls and handoffs. When
  the player is "judy" or engaged, AWACS goes quiet.

## 3. Briefing and kneeboard checklists

The current DMS format (intel narrative plus the 5 paragraphs) is right. Players praise briefings
that look like real intel ([forum 366107](https://forum.dcs.world/topic/366107-finished-campaign-summary-review)).
Fighter briefs run admin → mission → threats → tactics → contingencies, and flight leads brief
deviations from SOP ([AFMAN 11-2F-15V3 supp](https://static.e-publishing.af.mil/production/1/kadenaab/publication/afman11-2f-15v3_kadenaabsup/afman11-2f-15v3_kadenaabsup.pdf)).

**Briefing must have:**
- [ ] Expected flight time for each variant ("air start ~35 min, ramp ~60 min"). Players asked
  authors for this ([forum 227316](https://forum.dcs.world/topic/227316-a-humble-request-for-campaign-creators-expected-mission-duration)).
- [ ] What changed since last mission, as a conditional block.
- [ ] **Stakes**: what happens if we fail. This is fail forward, said aloud.
- [ ] Every known threat: type, location, and the cue the player gets (RWR / none / JTAC report).
- [ ] Most likely and most dangerous enemy course of action.
- [ ] Timeline: push, vul/TOT window, playtime.
- [ ] ROE including PID, no-fire areas, danger-close procedure.
- [ ] Abort criteria, joker/bingo, divert, CSAR plan.
- [ ] Comms table, codewords, lost-comms procedure.
- [ ] One "what we don't know" line, which seeds the optional encounters.

**Kneeboard must have** (lineup card plus mission data card,
[DCS data card template](https://forum.dcs.world/applications/core/interface/file/attachment.php?id=25101)) [sim]:
- [ ] callsigns and flight positions
- [ ] time hacks (push / TOT / vul)
- [ ] steerpoint table with names
- [ ] frequencies with modulation
- [ ] TACAN for the tanker
- [ ] joker and bingo (tied to the divert)
- [ ] laser code
- [ ] threats with their RWR symbol or "no RWR"
- [ ] bullseye
- [ ] abort codeword
- [ ] divert
- [ ] CAS missions: a 9-line block with lines 4, 6 and 8 left blank to copy
- [ ] CSAR: survivor callsign, authentication number placeholder, word of the day [unv]

## 4. Pacing rules and the DMS director

The [L4D director (Booth, AIIDE 2009)](https://cdn.fastly.steamstatic.com/apps/valve/2009/ai_systems_of_l4d_mike_booth.pdf)
runs Build Up → Sustain Peak → **Peak Fade** → Relax:
- Intensity decays **only while no enemy is engaging** the survivor.
- Relax does not start "until a natural break in the action occurs".
- Relax ends on time **or** progress toward the next safe room.
- Mobs arrive at random **90–180 s** intervals on Normal.
- Boss encounters are **not** paced by the director.

Sustain-peak of ~3–5 s and relax of ~30–45 s are widely quoted but not confirmed from the slides.

DMS today (`lua/src/dms/director.lua`, `planner/planning.py` `_INTENSITY`):

| `intensity` | peak | relax_sec | spawns/min | Use for |
|---|---|---|---|---|
| calm | 50 | 60–120 | 2 | first mission, recon, transport, night. Player is learning the area |
| moderate | 70 | 40–90 | 3 | default SEAD/strike/CAP |
| intense | 85 | 25–60 | 5 | CAS/TIC, defend-the-base, act climaxes. At most 1 in 3 missions |

Default gains: hit 25, nearShot 5, samLaunch 15, nearKill 8, playerDead 40, decay 1.5/s, peak hold 15 s.

Rules:
1. **Fly the interest curve** ([Schell](https://www.routledge.com/The-Art-of-Game-Design-A-Book-of-Lenses-Third-Edition/Schell/p/book/9781138632059)):
   hook in the first 3 min, then 2–3 rising peaks, the scripted climax last, and a short resolution
   (check-out plus RTB). Write the curve in `notes` as `T+min: event` lines.
2. **Story in RELAX, brevity in PEAK.** Character lines (`priority` 10–30, `director.state:
   RELAX` or after a kill) go in valleys. In PEAK, only terse calls of 12 words or fewer.
3. **Set pieces bypass the director** (L4D bosses). Pinned objectives, the guaranteed SAM and
   story spawns are `threats` or encounters with `chance: 100`. Only fillers (`waves`, `hunt`,
   `cap`) are director-gated.
4. **Major event cadence**: about one major threat event (wave, pop-up, CAP) per 2–4 min of
   on-station time at `moderate`. More than 6 encounters in a 20-minute vul is clutter.
5. **Telegraph lead time** is 30–60 s. A pop-up with no `telegraph_beat` is a lint error unless
   it is an IR threat that the briefing explicitly warns has no cue.
6. **Engine gaps (proposed, not built):** decay currently runs even while the player is
   engaged, and PEAK exits after a fixed 15 s. L4D-style improvements would be to suppress decay
   while a missile is in flight or a player was hit in the last N s, and to add a Peak Fade
   sub-state. RELAX already waits for intensity < 0.5 × peak, which partly covers this.
7. **Adaptive stays hidden and small** (±1 tier, the existing clamp). Never adapt the scripted
   climax.

## 5. Campaign branching patterns

From [Emily Short on QBN/salience](https://emshort.blog/2016/04/12/beyond-branching-quality-based-and-salience-based-narrative-structures/),
[storylets](https://emshort.blog/2019/11/29/storylets-you-want-them/),
[Failbetter structures 2](http://www.failbettergames.com/echo-bazaar-narrative-structures-part-two/)/[3](http://www.failbettergames.com/echo-bazaar-narrative-structures-part-three/)
and [Ashwell's patterns](https://heterogenoustasks.wordpress.com/2015/01/26/standard-patterns-in-choice-based-games/):

**Core rule: diverge in state, converge in structure.** Arc branches rejoin within 1–2 missions.
Qualities carry the difference into briefings, beats, threat strength and the director.

| Pattern | DMS shape | When |
|---|---|---|
| **Branch and bottleneck** (default) | a failure mission `mNNb` rejoins at `mNN+1` | every act |
| **Progress + menace qualities** | one progress quality (e.g. `intel`) and 1–2 menaces (`sam_threat`, `collateral`) | every campaign |
| **Midnight Staircase** (prep vs act) | optional recon/SEAD missions raise `intel` and lower `sam_threat` before the big strike; a clock quality (`enemy_advance`, FTL-style pursuit) rises with each optional sortie | mid-act |
| **Menace threshold** | `collateral >= 3` forces a consequence mission (inquiry, tighter ROE, a partner refusing to work with us), not game over | always |
| **Mark of Cain** | an exclusive flag closes the opposing side-plot (`sided_with_nbb`) | one per campaign |
| **Waypoint** | story events that must happen by mission N via *some* branch; branches choose the route | act turns |
| **Sorting hat** (expensive) | an act-1 outcome picks one of two act-2 tracks | at most once |
| **Loop and grow** | a recurring patrol whose beats change with qualities (callbacks) | breathers |
| **Time cave** (avoid) | branches that never re-merge | never |

Other rules:
- **Callbacks need two setups** (rule of three): an intel mention, a radio aside, then the payoff.
- **Show cause and effect.** QBN's weakness is that players lose track of why things happen, so
  every briefing's "what changed" paragraph names the outcome that caused it.
- **Never gate on grind**: each step of a quality comes from distinct content.
- **Persist world damage** (Falcon 4): a destroyed site stays destroyed, and briefings say so.
  Cap any single mission's swing at ±2 per quality.
- **Salience-based beats** (Ruskin,
  [GDC 2012 notes](https://emshort.blog/2012/03/16/gdc-2012-talk-on-dynamic-dialogue/)): for
  each reactive event, write a generic fallback beat (no `requires`, low priority) plus specific
  variants gated on state (higher priority). The most specific beat wins and the generic one
  guarantees coverage. `once` and `cooldown_sec` are the anti-repeat memory.

## 6. Lint list: quality checks for `dms validate`

**Implemented** in `dms_core.lint`. `uv run dms validate <mission dir|arc.yaml>` runs it by
default (`--no-lint` to skip, `--strict` to fail on warnings), and so does MCP `validate`.
Findings read `[<code>] <message>. Fix: <hint>`. `RULES` in the module and CONTRACTS
"Mission-quality lint" are the source of truth for what each rule checks today; the table
below is the original design rationale, and a few rules were narrowed when built. Skills fix all
errors and every warning they can inside the ≤3-loop repair budget. None needs a flight.

| id | sev | Rule |
|---|---|---|
| `spine_no_fallback` | warn | A guaranteed beat triggered by `group.dead` / `unit.dead` / `flag` with no sibling beat (same `set_flag`, or a `timer` / `beats_fired` alternative) can stall the mission. Require a timeout path |
| `guaranteed_on_takeoff` | error | A guaranteed beat on `unit.takeoff`, or gated on a ramp-only zone, when an `air` variant exists |
| `hook_late` | warn | The first voiced beat comes more than 180 s after the start (timer) or after the first guaranteed check-in |
| `popup_no_telegraph` | error | An `ambush_sam`, `cap` or `waves` encounter without a `telegraph_beat`, unless its notes contain `no-cue:` and the briefing mentions the threat |
| `telegraph_too_short` | warn | Telegraph beat `delay_sec` plus trigger geometry gives under 30 s of warning. Approximate by requiring the telegraph to fire on the encounter's trigger, with the encounter delayed by 30 s or more |
| `line_too_long` | warn | Words over the speaker's `brevity` limit (terse 12, normal 20, chatty 30), or estimated duration over 8 s (about 2.6 words/s) |
| `callsign_first` | warn | `text` does not start with a cast callsign, a flight callsign or an allowed short form ("Two,", "One-one,"). Exceptions: lines in a chain and talk-on continuations |
| `banned_phrases` | warn | Matches a list: "over and out", "hell yeah", "let's do this", "bulls " (bullseye), "roger that, over", "copy that" on tactical nets, all-caps words over 3 letters, more than 1 "!" |
| `brevity_misuse` | warn | "splash" in an A/G line with no weapon-impact sense, "tally" for friendlies, "visual" for enemies, "winchester"/"bingo" from a non-aircrew speaker |
| `variants_too_similar` | warn | Two variants of a beat with token Jaccard over 0.8, meaning a synonym swap rather than new information or rhythm |
| `too_few_variants` | warn | A beat that can fire more than once (`once: false`) with fewer than 3 variants |
| `reaction_no_cooldown` | warn | `once: false` with `cooldown_sec` under 30 on `unit.hit` / `unit.shot` / `unit.dead` |
| `radio_density` | warn | More than 3 voiced beats sharing one trigger event, or estimated voiced seconds per on-station minute over 25 (clutter). Use line durations or the word estimate |
| `peak_chatter` | warn | A beat with `priority` 30 or lower and over 15 words that can fire in PEAK (no `director.state: RELAX` / post-kill gating) |
| `no_generic_fallback` | info | A reactive event type (`unit.hit` players_only, `unit.shot` SAM) that has only `requires`-gated beats and no generic one |
| `outcome_partial` | warn | A destroy objective covering more than one unit or group has only boolean outcome keys. Suggest a count key |
| `failure_dead_end` | error (arc) | A mission whose failure flag (`mNN_player_lost`, an objective `failure_flag`) has no branch and whose next mission doesn't read it in `requires` or the briefing |
| `branch_never_rejoins` | warn (arc) | An optional branch mission whose chain does not reach a main-line mission within 2 hops |
| `quality_unread` / `quality_unmoved` | warn (arc) | Already a quality bar item. Make it mechanical |
| `quality_swing` | warn (arc) | `quality_effects` can move one quality by more than ±2 in one mission |
| `intensity_streak` | warn (arc) | More than 2 consecutive missions with director `intense`, or none `calm` per act |
| `briefing_threat_mismatch` | error | Threats with `hidden_on_map: false`, or with a telegraph, that are absent from briefing.md. Fuzzy-match the role or template name |
| `briefing_missing_sections` | warn | No `## 1.`–`## 5.`, no "Abort", no "Bingo", no expected-duration line, no stakes line |
| `kneeboard_contradiction` | error | Frequencies, laser code, bingo or callsigns that differ between briefing and kneeboard (regex the numbers) |
| `kneeboard_too_long` | warn | More than 25 lines, or no comms table |
| `transit_too_long` | warn | Planned route length from the start to the IP over 30 min at the cruise speed (ramp) or 8 min (air variant). Needs plan output, so it belongs in `dms check` or a plan stage |
| `vul_overload` | warn | More than 6 encounters that can be active inside one 20-minute on-station window |
| `spawn_in_view` | error | Already a runtime rule. Statically check that pool areas lie at least 5 km (ground) or 20 NM (air) from the guaranteed trigger zones that can wake them |

Not built as lint: `hook_late` uses the first radio call after mission start (not the
check-in), `spawn_in_view` stays a runtime rule, `outcome_partial` is guidance only, and
`transit_too_long` runs only once `out/plan.json` exists (re-validate after `dms plan`).
