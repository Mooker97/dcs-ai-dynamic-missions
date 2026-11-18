# DCS scripting unknowns: research, 2026-10-29

This note works through the `[?]` items in [dcs-scripting-gotchas.md](../dcs-scripting-gotchas.md),
CONTRACTS (`unit.ejected` / `unit.pilot_dead`) and [miz-format.md](../miz-format.md). No DCS was
launched, so nothing here was flown or run headless.

## Sources and their weight

The sources, from strongest to weakest:

1. **The installed DCS** (`E:\SteamLibrary\steamapps\common\DCSWorld`, a current Steam build) has
   plain-text Lua for the Mission Editor and the sandbox:
   - `Scripts/MissionScripting.lua`
   - `Scripts/ScriptingSystem.lua`
   - `Scripts/dictionary.lua`
   - `MissionEditor/modules/me_trigrules.lua` and `me_mission.lua`

   I also scanned 1387 ED-shipped `.miz` files. This is the strongest evidence for ME behaviour.
   The engine side (for example `trigger.action.*`) is compiled C++ and can't be read.
2. **MOOSE / MIST source** on GitHub: real call patterns used by thousands of missions.
3. **Hoggit wiki**: community-maintained and usually right, but sometimes stale.
4. **ED forum threads**: anecdotal. Each one is dated below.

The old `C:\Program Files\Eagle Dynamics\DCS World OpenBeta` install is 2.8.4 (2023) and was not used.

## 1. `world.getMarkPanels()`: shapes, fields, script-mark initiator

**Verdict:** shapes are included (verified from Hoggit). Whether `initiator` is nil for script marks
is **still unknown**.

- [Hoggit getMarkPanels](https://wiki.hoggitworld.com/view/DCS_func_getMarkPanels): the function
  returns "mark panels and drawn shapes". The panel "is designed with the mark points in mind, but
  still returns data for shapes created via markups".
  - The fields are `idx, time, initiator, coalition (-1 or side), groupID (-1 or id), text, pos`.
  - Markup shapes made for all coalitions can report `coalition = 255`.
  - A shape's `pos` appears to be the average of its points.
- [Hoggit markupToAll](https://wiki.hoggitworld.com/view/DCS_func_markupToAll): shape IDs share the
  mark-panel ID space, and `removeMark` removes shapes.
- Mark IDs:
  - Player marks are in the 251,000,000+ range
    ([forum 2021](https://forum.dcs.world/topic/276775-getting-next-marker-idx)). Frameworks pick a
    high fixed start: MOOSE uses 1, OzDeaDMeaT's MapMarkerCommands uses 2,000,000, and the forum
    poster uses 100k.
  - Bug report, still open: an ID removed with `removeMark` and then reused fires MARK_ADDED but
    doesn't render
    ([forum 2023](https://forum.dcs.world/topic/319761-triggeraction-bug-dcs-backend-remembers-old-id-numbers-even-after-youve-done-removemark)).
- Evidence on `initiator`:
  - DCS-gRPC's exporter (`lua/DCS-gRPC/exporters/object.lua`) guards with
    `if markPanel.initiator then`, so it expects nil for some panels.
  - VEAF `veafShortcuts.lua` also guards `panel.initiator`.
  - Nobody documents the value for script marks.
  - In multiplayer, the MARK_* *event* initiator is known to be wrong or missing
    ([forum 2020](https://forum.dcs.world/topic/244684-scripting-engine-bug-with-mark-related-events-in-multiplayer/)).
- **Headless test:** draw one `markToAll` and one `circleToAll` (coalition -1) from a script. Then
  `env.info` every panel's `idx`, `tostring(initiator)`, `coalition`, `groupID` and `text`. The
  test settles three things: whether initiator is nil, whether the circle shows coalition 255, and
  what the circle's text is.

## 2. `trigger.action.radioTransmission`: range, LOS, power, altitude, subtitles

**Verdict:** the qualitative behaviour is verified from several sources. The exact model is
**still unknown**.

- [Hoggit](https://wiki.hoggitworld.com/view/DCS_func_radioTransmission) gives the signature
  `(filename, point vec3, modulation 0/1, loop, frequency Hz, power W, name)`. Its example uses
  124 MHz at 100 W.
- MOOSE `Sound/Radio.lua` doc comment: "If the player gets too far from the transmitter, or if the
  antenna is too weak, the transmission will fade and become noisier. This an automated DCS
  calculation." For reference it gives VOR 100 W, TACAN 120 W and ATC 300–500 W. A subtitle (unit
  `TransmitMessage` command only) stays readable whatever the signal quality.
- [Forum, Apr 2025](https://forum.dcs.world/topic/372080-not-a-bug-but-a-question-comm-distance-from-ground-unit):
  - Range depends on power and "especially on the altitude of the transmitter and the receiver.
    Since it's line of sight..."
  - 50 W ground emitters that worked beyond 50 nm in 2.8 cut out at about 35 nm in 2.9.
- [Forum, Nov 2025](https://forum.dcs.world/topic/381336-radio-transmission-degradation-how-to-solve):
  - The degradation is deliberate, and campaign authors work around it.
  - The fix that worked: place the transmission point within about 1 nm of the player, at 10000 W.
  - Cloud layers seemed to degrade quality.
  - The source stays where it started for the whole clip.
  - Don't place it exactly on the player (`y = p.y + 1`).
- The installed `me_trigrules.lua` sets the RADIO TRANSMISSION action's power spin to min 1,
  max 10000 and default 100.
- Subtitles:
  - DCS 2.9.25.21123 added "Subtitles to Radio Transmission Trigger Action"
    ([changelog](https://www.digitalcombatsimulator.com/en/news/changelog/release/2.9.25.21123/)).
  - The ME serializes it as `a_radio_transmission(file, zoneId, mod, loop, freqKHz, power, name,
    startDelay, mic_effects, squelch_effects, text, subtitles_duration)` (from the F-16C GermanyCW
    quickstart miz). This is the trigger-action wrapper, not `trigger.action.radioTransmission`.
  - MOOSE calls the scripting function with 7 arguments and says non-unit transmissions "can't be
    subtitled".
  - Whether the scripting function takes extra arguments is **unknown**.
  - MOOSE also notes that beacons in MP only run for about 30 s straight.
- Per-receiver LOS: every report is consistent with LOS and range being evaluated per listener, but
  nothing states it outright.
- **Tests:**
  - Headless: `pcall(trigger.action.radioTransmission, f, p, 0, false, hz, 10000, "n", "text", 5)`
    and log ok/err. This only shows that the call doesn't error.
  - Range and fade need a cockpit A/B at 5, 20 and 50 km, 1000 W vs 10000 W, with and without an
    overcast between source and receiver.

## 3. Events: ejection, pilot death, leave

**Verdict:** the initiators are verified. The order relative to PLAYER_LEAVE_UNIT is **still unknown**.

- [EJECTION](https://wiki.hoggitworld.com/view/DCS_event_ejection):
  - `initiator` is the unit that ejected, which is the aircraft.
  - `target` is the seat for ejection-seat aircraft, and DISCARD_CHAIR_AFTER_EJECTION then gives
    the pilot. Without an ejection seat, `target` is the pilot.
  - The target "isn't a normal object".
- [PILOT_DEAD](https://wiki.hoggitworld.com/view/DCS_event_pilot_dead): `initiator = Unit`. The cfrag
  thread below confirms that this is the aircraft.
- [LANDING_AFTER_EJECTION](https://wiki.hoggitworld.com/view/DCS_event_landing_after_ejection):
  - `initiator` is the pilot object and `place` is the aircraft. `place` may be invalid once the
    aircraft has crashed.
  - The event doesn't fire when the pilot lands in water.
- [Forum 2021 (SoW server log)](https://forum.dcs.world/topic/273075-players-can-eject-bail-out-after-death/):
  - The sequence was `pilot dead` t=9110.25, `eject` t=9113.06, `crash` t=9131.92. A mortally
    wounded player can eject *after* PILOT_DEAD.
  - This is WW2 damage-model territory, but the order is clearly not fixed.
- [Forum 2021 (cfrag)](https://forum.dcs.world/topic/288749-player-ejecting-the-parachute-guy-isnt-recognized-as-player-unit-but-does-create-pilot_dead-event-when-deleted):
  - A player who stays with the parachute isn't reported by `getPlayerName()` on the parachute unit.
  - Deleting that unit raises PILOT_DEAD for the aircraft, which can be minutes after ejection.
  - If the player re-slots first, the delete raises no PILOT_DEAD.
- [Forum 2024](https://forum.dcs.world/topic/345478-onevent-bug-eventinitiator-for-unit-on-death-or-on-leave-unit-is-broken-because-its-already-been-destroyed):
  - In PLAYER_LEAVE_UNIT and pilot-death handlers, the initiator may already be destroyed, so
    `Unit.getByName(initiator:getName())` errors.
  - On a slot or coalition change, the new aircraft's BIRTH fires **before** the old aircraft's
    PLAYER_LEAVE_UNIT.
- [Hoggit PLAYER_LEAVE_UNIT](https://wiki.hoggitworld.com/view/DCS_event_player_leave_unit) says
  the event fires "when any player relieves control of a unit to the AI". It says nothing about
  ejection.
- The DMS headless `debrief.log` (2026-10-28) has no eject, pilot-dead or leave events, so it gives
  no evidence either way.
- **Test:** this needs a cockpit run. Log every event with `timer.getTime()`, then eject: once
  staying in the parachute, once re-slotting immediately, and once dying in the crash. Headless can
  only cover AI (`trigger.action.explosion` on an AI jet).

## 4. Sound files: `l10n/DEFAULT`, `mapResource`, keeper trigger

**Verdict:** the ME-save behaviour is verified from the installed source. The sim-side need for
`mapResource` is **still unknown**.

- [Hoggit outSoundForGroup](https://wiki.hoggitworld.com/view/DCS_func_outSoundForGroup): "The
  sound file must be placed inside of the miz file". Since 1.5 you may need the `l10n/DEFAULT/`
  prefix.
- Installed `Scripts/dictionary.lua`:
  - `unpackFiles` extracts every archive entry on load. Entries outside `l10n/`, and
    `l10n/*/KNEEBOARD/*`, go into `resourceFilesSim` and are always re-packed on save.
  - `packMissionResources` re-packs only the `l10n/<dict>/<file>` paths listed in `mapResource`.
    So a sound in `l10n/DEFAULT/` without a ResKey is **dropped on the next ME save**, and a file
    with a ResKey is kept.
  - `removeFileFromMission` / `removeResource` drop the key and delete the file. They run when a
    trigger action that owns the file is edited or deleted (`me_trigrules.lua:3393`,
    `me_action_edit_panel.lua:383`, ...).
- A keeper trigger therefore isn't strictly needed for an ME save as long as the ResKey exists. It
  still protects against the action-edit paths, and it is the community's standard fix
  ([forum](https://forum.dcs.world/topic/291580-add-a-sound-file-to-be-used-by-triggeraction-outsound),
  [forum](https://forum.dcs.world/topic/134452-me-deletes-sound-files-by-saving)). Our builder
  (`packages/dms-gen/src/dms_gen/builder/mission.py:826-835`) does both, which is correct.
- Users report that files in another miz folder survive ME saves. This matches `resourceFilesSim`.
- **Headless test for the sim side:** build a miz with `l10n/DEFAULT/t.ogg` and no ResKey, call
  `outSoundForCoalition(2, "l10n/DEFAULT/t.ogg")`, then grep dcs.log for a sound/file error.

## 5. `hidden` on `coalition.addGroup`

**Verdict:** verified (documented).
[Hoggit addGroup](https://wiki.hoggitworld.com/view/DCS_func_addGroup) lists `hidden`,
`hiddenOnPlanner` and `hiddenOnMFD` as optional group-level booleans. `hiddenOnMFD` keeps the
group off avionics such as F-16/F-18 SAM rings and AH-64 threat pages. No runtime setter exists.
`spawner.lua:403-406` sets all three at group level, which is correct. The CPG in DCS 2.9.25 can
"find, aim and engage hidden units" (changelog), so `hidden` is a map-only effect.

## 6. Other `[?]` items

| Item | Finding |
|---|---|
| Sandbox list | Installed `MissionScripting.lua` sets `os`, `io`, `lfs`, `require`, `loadlib` and `package` to nil. Verified. |
| Route: 2 points, current first | MOOSE `CONTROLLABLE:RouteGroundTo` builds `{FromWP (current), ToWP}`. This is the convention, but a 1-point failure isn't proven. Headless test: give a group a 1-point route and log its movement. |
| RNG seeding | Neither `MissionScripting.lua` nor `ScriptingSystem.lua` calls `math.randomseed`, so whether the C side seeds it is unknown. `DMS.Rng` is independent of it (`rng.lua:2`). Headless test: log `math.random()` at t=0 on two launches. |
| `KNEEBOARD/IMAGES/*` (miz-format) | Verified: 76 entries under `KNEEBOARD/IMAGES/` in ED-shipped AH-64D quickstart missions, at the archive root. The ME keeps root files as sim files. |
| CONTRACTS `unit.ejected` initiator = aircraft | Verified (Hoggit EJECTION and PILOT_DEAD, cfrag thread). |
| `Airbase:getParking(true)` (lua-api-notes) | Hoggit: passing `available` returns only free spots. Term_Type 16 = runway, 40 = helo, 68 = HAS (Caucasus only), 72 = open/shelter, 100 = small shelter (Syria/Sinai), 104 = open air. 104 doesn't guarantee a C-130 fits. The size filter is still unverified. |
| `Unit.getDescByName(type).fuelMassMax` | Hoggit: exists since 1.2.4 and the type doesn't need to be in the mission. The A-10C example shows `fuelMassMax = 5029`. Verified that it exists, but the units aren't documented (kg by convention). |
| CAP / ambient behaviour items (lua-api-notes) | Not researched. These are AI-behaviour questions that only a run can settle. |

## Contradictions with current code

1. **Mock `world.getMarkPanels` omits shapes** (`lua/mocks/dcs.lua:1443-1449`, `PANEL_KINDS`).
   DCS returns circles and text shapes too. `DMS.Test.verifyMarks` (`lua/src/dms/test.lua:518-580`)
   tolerates both, so the risk is only that the mock under-reports and a spec could assume the
   absence of shapes. No current spec asserts it (`lua/spec/test_spec.lua:444`,
   `intel_spec.lua:714`). The mock should include shapes, with coalition 255 when made for all.
2. **`Intel.bumpPastExisting` can jump into the player-mark range** (`lua/src/dms/intel.lua:906-919`).
   It raises `_nextId` to the highest existing `idx`. If a player mark exists at start or restart
   (IDs around 251,000,000+), our next IDs follow it directly and can collide with the next player
   mark. Fix: only consider panels inside our own band (for example `FIRST_MARK_ID` up to
   `FIRST_MARK_ID + 10^7`), or skip panels whose `initiator` isn't nil.
3. **Radio power and placement** (`lua/src/dms/comms.lua:146-208` and `:222`).
   - The default is `target.power or 1000`.
   - Coalition lines come from 10 km above the players' centroid. With spread-out players, low
     players, or players under cloud, that is many km of slant range and likely to fade.
   - Field reports recommend 10000 W, which is the ME maximum, and a source near each listener.
   - Suggested fix: default `power = 10000`, and for coalition lines transmit once per player group
     from just above that group's player. The cost is overlapping audio if two groups share a
     frequency, so de-duplicate by frequency and proximity.
4. **`PLAYER_LEAVE_UNIT` name lookup** (`lua/src/dms/bus.lua:356-363`). `nameOf(e.initiator)` can
   return nil when the unit is already destroyed. The player then stays in `Bus._players` and the
   Director flight is never orphaned. Fix: fall back to a map from object id (`e.initiator.id_`) to
   unit name, filled at BIRTH.
5. **Late PILOT_DEAD** (`lua/src/dms/director.lua:86-89`, `LEFT_GRACE_SEC = 10`). A player who stays
   in the parachute can trigger PILOT_DEAD minutes later when the parachute unit is removed. That
   isn't a double count, because the first death event unmaps the unit. But a re-slot more than
   10 s after leaving without EJECTION loses the death. This is acceptable, and is noted only so
   nobody "fixes" it by lengthening the window.
