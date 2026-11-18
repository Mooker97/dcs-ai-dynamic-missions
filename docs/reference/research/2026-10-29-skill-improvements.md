# Skill improvements from mission-quality research (2026-10-29)

These are proposed edits only. The skills are being edited by other agents right now, so this
file does not change them. The background, sources and lint rules are in
[`../mission-design-guide.md`](../mission-design-guide.md) (called "the guide" below). Section
numbers in brackets point into the guide.

Current practice is already strong. The viper-detachment m03 has a real 9-line, talk-on,
readback-free brevity, danger-close initials, conditional briefings and a guaranteed spine
reachable from both start variants. The gaps are mostly **robustness against stalls**,
**pacing discipline**, **radio density**, and **turning the quality bar into mechanical checks**.

## mission-designer (`.claude/skills/mission-designer/`)

### SKILL.md

1. **Step 2, "Shape the flight"**: require a timeline in `notes` as `T+min: event` lines, measured
   from the first guaranteed beat, not from mission start. Add these targets:
   - hook within 3 min
   - first engagement by T+5 to T+10
   - 2–3 rising peaks, with the climax last
   - on-station time stated
   - expected total flight time stated for each variant
   Reason: interest curve and transit complaints [§0.3, §4.1].
2. **Step 3, encounters**: add the rule that set pieces bypass the director. The pinned objective
   and the arc's guaranteed threat are `threats` or `chance: 100` encounters. Only filler (`waves`,
   `hunt`, `cap`) is director-gated. Also cap it at 6 or fewer encounters that can be live in one
   20-min on-station window [§4.3, §4.4].
3. **Step 4, beats**: add a **"no single point of failure"** bullet. Every guaranteed beat that
   waits on a kill, a landing or a flag needs a timeout sibling: a `timer` or `beats_fired` beat
   that sets the same flag, or a retask. Also add a "say status" / "still waiting" nudge beat after
   about 4 min of no progress. m03 already does this with its 8-min retask, so cite it as the
   pattern [§0.1, §0.2].
4. **Step 4**: add **generic fallback plus specific variants** (Ruskin salience). For each reactive
   event (player hit, SAM launch, first kill), write one ungated, low-priority beat and then the
   state-gated beats at higher priority. The guarantee is coverage; the specific beat wins
   [§5 last bullet].
5. **Step 4**: add **"Story in RELAX, brevity in PEAK"**. Character and continuity lines get
   `when: {event: director.state, state: RELAX}` or chain off a kill or BDA beat. Anything that
   can fire mid-fight stays at 12 words or fewer [§4.2].
6. **Step 4, outcome keys**: emit **counts** for multi-target objectives (`targets_destroyed: N`)
   and a partial-success key, so the arc can branch on degree. Avoid binary-only outcomes [§0.7].
7. **Step 6, briefing**: add the **expected duration per variant**, a **stakes** sentence (what
   happens if we fail, which is fail forward said aloud) and, for each known threat, **the cue the
   player will get** (RWR symbol / none / JTAC report) [§3].
8. **Step 7, validate**: once `dms_core.lint` exists, run `uv run dms validate --strict`, and
   treat lint warnings as repairable inside the same ≤3-loop budget. Until then, add a manual
   "lint by reading" pass over the guide's §6 table.
9. **Quality bar**: add "No beat that progresses the mission depends on exactly one event" and
   "Briefing names the stakes and the expected flight time".
10. **Checklist**: add `[ ] Timeline in notes (hook ≤3 min, peaks, climax last)`,
    `[ ] Every gating beat has a timeout path`, and `[ ] Set pieces not director-gated`.

### references/radio-realism.md

11. Add the **verified brevity words** that are missing: magnum, mud spike (with clock and type),
    nails, singer, buddy spike, defending, fence in/out, judy, pop-up, fade/vanished, merged,
    commit, leaker, scram, angels/cherubs, IN/OFF with direction, continue / continue dry, cleared
    to engage (Type 3), "good readback". Mark **pickle** and **shack** as slang that is not in
    ATP 1-02.1 [§2].
12. Add **"bullseye, never bulls"** and the BRAA format with no "for"/"at" (Hoggit GCI) [§1.4].
13. Add a **net discipline** rule: AWACS goes quiet when the player is engaged ("judy" logic). No
    picture calls during PEAK unless they carry a pop-up or a threat.
14. Add the **laser sequence** (ten seconds → laser on → lasing → spot → terminate, marked unv)
    and the **readback rule** (lines 4, 6 and restrictions) [§1.3].

### references/beats-and-encounters.md

15. Add a **"Per-role spines"** section that links to the guide §1, or inlines the beat tables for
    SEAD, strike, CAS, CAP, CSAR and air assault, with T+ offsets and outcome keys.
16. Add the **director table** (calm/moderate/intense → peak, relax, spawns/min) with "use for"
    guidance, and "intense at most 1 in 3 missions" [§4].

### references/briefing-format.md

17. Add **Duration** and **Stakes** lines to the header.
18. Add **lineup-card items** to the kneeboard list: time hacks, bullseye, joker *and* bingo, laser
    code, abort codeword, RWR cue per threat, and a 9-line copy block (lines 4/6/8 blank) for CAS
    missions [§3].

## campaign-planner (`.claude/skills/campaign-planner/`)

19. **Step 3, qualities**: frame them as **one progress quality plus 1–2 menace qualities**, with the
    rest optional (Short/Failbetter). Add **"never gate on grind"**: each quality step comes from
    distinct content [§5].
20. **Step 4, branches**: name the allowed patterns: **branch and bottleneck** (default; failure
    missions rejoin within 2 hops), **menace threshold** missions (e.g. `collateral >= 3` → an
    inquiry or ROE-tightening mission), **Midnight Staircase** (optional prep sorties versus a
    clock quality), and **at most one sorting hat**. Ban the time cave [§5 table].
21. **New rule: "Diverge in state, converge in structure."** Branch per act or series rather than
    per mission (the Wing Commander lesson). Let qualities carry the difference.
22. **Quality bar**: replace "Failure is never a dead end" with a checkable form. Every mission's
    failure flag is read by a branch *or* by the next mission's briefing or beats. Each failure
    branch is a different mission type or situation, not a replay at higher difficulty.
23. **Step 5, rhythm**: add a director cadence across the arc. Use `calm` for the first mission,
    no more than 2 `intense` in a row, at least one `calm` per act, and keep the act climax
    `intense`. Vary mission length like a golf course (par 3/4/5): 30/45/60-minute missions
    ([forum 273980](https://forum.dcs.world/topic/273980-mission-length-tolerancepreference-i-need-your-feedback/)).
24. **Waypoints**: allow `key_beats` that must happen by mission N through any branch. The
    debriefer then checks that the waypoint was reached [§5 table].
25. **Cap the swing**: no `quality_effects` clause set may move one quality by more than ±2 in a
    mission. Persisted world damage (destroyed SAM sites) goes into flags that later briefings
    must mention.

## story-writer (`.claude/skills/story-writer/`)

26. **Characters**: give each recurring speaker a **verbal habit** and a **procedural tell** (a
    controller who always says "welcome back", a JTAC who counts down impacts), so character
    lives inside procedure. Already implied in radio-realism, but the bible is where it should be
    seeded. Add a `notes` example.
27. **Interview**: add a question on **mission length and skip tolerance** (default: 45 min, air
    start offered, transit 20 min or less) and a question on **failure tolerance** (fail forward
    default, permadeath opt-in).
28. **Canon rules**: seed the campaign's **stakes vocabulary**, meaning what losing looks like in
    this world (villages fall, the partner force withdraws), so planner and designer can state
    stakes consistently.
29. **Quality bar**: include at least one character whose fate is a quality outcome (alive,
    wounded or captured, by mission N), so qualities have faces.

## voice-director (`.claude/skills/voice-director/`)

30. **Duration targets by director state**: PEAK lines 4 s or less, normal 8 s or less, RELAX
    character lines up to 10 s. Flag any beat whose longest variant is over 2× its shortest,
    because it skews queue timing.
31. **Radio density check** before rendering: total voiced seconds per on-station minute (aim for
    25 or less) from the dry-run durations. Report beats sharing one trigger that would queue
    more than 3 lines (the guide's `radio_density` lint).
32. **Stress delivery**: fewer words and faster cadence, never louder or shouting. Map `[urgent]`
    only to PEAK-eligible beats. The JTAC in contact may get a `[breathless]`-style tag on the
    check-in only, not on every line.
33. **Subtitle persistence**: keep subtitle text at most as long as the speech so it clears fast.
    DCS ties radio static to subtitle length, and lingering messages have hidden the F10 menu
    ([forum 370260](https://forum.dcs.world/topic/370260-wishing-messages-be-displayed-much-longer-on-screen),
    [forum 278646](https://forum.dcs.world/topic/278646-)).
34. **Coverage**: every speaker in `cast` must have every voiced beat rendered, or the beat must be
    subtitle-only by design. Missing lines fall back badly, and players notice
    ([forum 336299](https://forum.dcs.world/topic/336299-campaign-feedback/)).

## Tooling follow-ups (not skills; for the owners of `dms-core` / `lua`)

- **`dms_core.lint`** implementing the guide's §6 table, plus `dms validate --strict`, exposed in
  MCP `validate`. Start with these, which give the most value for the least effort:
  `spine_no_fallback`, `guaranteed_on_takeoff`, `popup_no_telegraph`, `line_too_long`,
  `banned_phrases`, `briefing_threat_mismatch`, `kneeboard_contradiction` and `failure_dead_end`.
- **Director (Lua)**: suppress decay while a player was hit or had a SAM shot at them within the
  last ~10 s, and add Peak Fade, meaning PEAK does not exit while hits or launches are recent.
  Spec it in CONTRACTS first. This is implemented in neither design nor code, and unflown.
- **Stall watchdog (Lua)**: an optional `DMS_CONFIG.watchdog {silentSec}` that fires a
  `mission.stalled` event when no beat has fired for N s while players are airborne. Beats can
  hook "Ops: say status" to it.
