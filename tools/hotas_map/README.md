# HOTAS bindings (Thrustmaster Warthog in DCS)

Start here when Mook says "I want to work on my bindings". This folder reads Mook's real DCS
bindings for the Warthog stick and throttle. It shows them on a web page with photos, finds
buttons that fire two commands, and can safely unbind leftover defaults.

Status on 2026-11-02: bindings extracted, 8 leftover defaults cleared, page published. Nothing is
committed yet, and no new bindings have been planned or set.

## Session checklist

1. Make sure DCS is closed. DCS rewrites the binding files when it exits, so it would overwrite edits.
   Check with `tasklist.exe | grep -i dcs`. `DCS-COINS.exe` is unrelated and can be ignored.
2. Refresh the data and the page (commands below), then ask which aircraft to work on.
3. Agree changes with Mook, button by button. Use the exact DCS command names (see "Finding
   command names").
4. Apply the changes (see "Changing bindings"). Run `--clear-conflicts --dry-run`, then run it for
   real, so that no default is left firing alongside a new binding.
5. Re-extract, republish the page, and tell Mook what changed. It counts as done only once he has
   checked it in the DCS controls screen or in the cockpit.

## Where things live

| What | Path |
|---|---|
| Extractor, conflict cleaner | `tools/hotas_map/extract.py` (tests: `tools/tests/test_hotas_map.py`) |
| Page template | `tools/hotas_map/template.html` |
| Drawn art (fallback) | `tools/hotas_map/art/stick.svg`, `throttle.svg` |
| Photo art (used on the page) | `~/.dms/hotas_map/art/` (built from `~/.dms/hotas_map/photos/`) |
| Photo pin positions | `~/.dms/hotas_map/photos/anchors.json` (pixel x, y in the original photo, callout side) |
| Published page | https://claude.ai/artifact/1ao7wm6JQHN1vzSvwXQB2i ("Warthog Bindings") |
| Mook's bindings (user diffs) | `C:\Users\mook\Saved Games\DCS\Config\Input\{profile}\joystick\{device} {GUID}.diff.lua` |
| DCS install (Steam) | `E:\SteamLibrary\steamapps\common\DCSWorld` (WSL: `/mnt/e/SteamLibrary/...`) |
| Module defaults | `{install}\Mods\aircraft\{module}\Input\{profile}\joystick\` |

The photos are Thrustmaster product images, so they stay out of git.

Profiles with Warthog bindings: `AH-64D_BLK_II_PLT`, `AH-64D_BLK_II_AI_Menu`, `F-16C_50`,
`FA-18C_hornet`, `UiLayer`. The devices are `Joystick - HOTAS Warthog` (stick) and
`Throttle - HOTAS Warthog`. A MOZA R3 wheel/pedals profile and an old vJoy profile also exist in
some folders.

## Commands

Run from the repo root in WSL.

```bash
S=/tmp/hotas   # any scratch folder
uv run python tools/hotas_map/extract.py --out $S/bindings.json --html $S/warthog-bindings.html --art-dir ~/.dms/hotas_map/art
uv run python tools/hotas_map/extract.py --clear-conflicts --dry-run   # list leftover defaults
uv run python tools/hotas_map/extract.py --clear-conflicts             # unbind them (writes .bak first)
uv run --with pillow python ~/.dms/hotas_map/photos/build_art.py       # after editing anchors.json
```

To update the page, publish `$S/warthog-bindings.html` with the Artifact tool, passing the URL
above as `url` (read it first). Leave out `--art-dir` to use the drawn art instead of the photos.

## How DCS stores bindings

The effective bindings are built up in three layers:

1. **Base**: the module's `joystick/default.lua`, plus `Config/Input/Aircrafts/common_joystick_binding.lua`
   (POV1 slow views) and `Scripts/Input/DefaultAssignments.lua` (default axes per device).
2. **Module device diff**: `{device}.diff.lua` in the module folder. This is the Warthog's
   default profile for that aircraft.
3. **User diff**: the `{device} {GUID}.diff.lua` file in Saved Games. This is what Mook changed.

Each diff is keyed by a command hash: `d{down}p{pressed}u{up}cd{device}vd..vp..vu..` for buttons
and `a{action}cd{device}` for axes. Each entry has a `name` and `added`, `removed` or `changed`
lists of `{key = "JOY_BTN7", reformers = {"JOY_BTN5"}}`. `reformers` are modifiers: buttons
held at the same time.

The merge rule comes from `Scripts/Input/Data.lua` (`applyDiffToCommands_`), and
`extract.py apply_diff` mirrors it. If a diff binds a button to command X while a default
already uses that button for command Y, DCS keeps both, and the button fires both commands. This
is a "clash". The fix is a `removed` entry for Y in the user diff, which is exactly what
`--clear-conflicts` writes.

## Changing bindings

The safest way is for Mook to bind the button in the DCS controls screen and then run the
extractor. If Claude edits the files instead:

- Get the command hash for the name from any diff that already mentions it. Search
  `{install}\Mods\aircraft\{module}\Input\{profile}\joystick\*.diff.lua`, where the module ships
  profiles for many devices, and the user diffs.
- Load the user diff with `extract.load_diff`, add `{"key": ...}` to the command's `added` list,
  and write it back with `extract.lua_serialize`. Copy the pattern from `clear_conflicts`: it
  writes a timestamped `.bak` next to the file, checks the round trip, and keeps LF line endings
  with no trailing newline.
- Then run `--clear-conflicts`, so the default that used to sit on that button no longer fires.
- To undo, rename the `.bak` over the `.diff.lua`.

## Finding command names

The pilot commands for the Apache cyclic come from the module's `joystick/default.lua`:

```bash
grep -o "name = _('[^']*'),[^}]*Cyclic Stick" "/mnt/e/SteamLibrary/steamapps/common/DCSWorld/Mods/aircraft/AH-64D/Input/AH-64D_PLT/joystick/default.lua" | sed "s/name = _('\([^']*\)').*/\1/" | sort -u
```

For other aircraft, swap the module and profile folders and the category, such as `HOTAS`,
`Throttle Grip` or `Stick`.

## History

- 2026-11-02: cleared 8 leftover defaults. Mook's own bindings were verified intact against the
  backups (Apache throttle 24 of 24, Viper throttle 26 of 26). The backups end in
  `.20261102-100117.bak`.
  - Viper: mic switch right/left (Transmit IFF out/in), coolie up/down (ANT ELEV), throttle
    button 24 (AIR REFUEL).
  - Apache: boat switch fwd/aft (Boresight/Polarity), friction slider (Zoom View).

## Next up: Apache stick proposal (not applied, to discuss)

The Apache pilot stick only uses the trigger, S2 (George AI) and H2 (Force Trim/Hold). These cyclic
functions are unbound. This is a starting point modelled on the real cyclic. Mook decides.

| Warthog control | Proposed command (exact DCS name) |
|---|---|
| H3 up / down | CMDS Switch - Fwd/Center, CMDS Switch - Aft/Center |
| H3 left / right | PTT/RTS Switch - RADIO/Left (call radio menu), PTT/RTS Switch - ICS/Right (call radio menu) |
| H4 up / down / push | Symbology Select Switch - Up, - Down, - Depress |
| H4 left / right | Chaff Dispense Button - Depress, Flare Dispense Button - Depress |
| S4 paddle | FMC Release Button - Depress |
| S1 index | ATA Missile Cage/Uncage Button - Depress |
| S3 pinky | Weapons Trigger Guard - OPEN/CLOSE |

The Viper and Hornet already have fuller layouts. Review them on the page for gaps.

## Open items

- **Photo pins are best guesses** for H2, H3, H4, S1 and S3 on the stick, all the throttle grip
  controls, the ENG OPER and APU toggles, and EAC versus the radar altimeter toggle. When Mook
  says where a control really is, fix it in `anchors.json`, rebuild the art and republish.
- The stick photo crop cuts through the desk plate. Crop above it if Mook minds.
- The racing-pedal rudder bridge is in `tools/pedal_rudder/` (see its README). Its install into
  Saved Games is still waiting on Mook, and nothing about it has been tested with the pedals or
  flown.
