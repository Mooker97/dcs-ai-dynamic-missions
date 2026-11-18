# Pedal rudder bridge

Use two racing pedals as DCS rudder pedals, with no vJoy and no virtual device. Clutch is left
rudder and throttle is right rudder. The brake stays a normal DCS binding (wheel brakes).

Status: implemented, not flown. Unit-tested (mixer, installer, Lua bridge under Lua 5.1), and the
Windows start-up was smoke-tested. It has not yet run against the real pedals or in a cockpit.

## How it works

1. `pedal_rudder.py` runs on Windows Python. It reads the pedals through SDL (pygame-ce) with
   background input on, so DCS can keep focus. It works out rudder = right minus left (-1 to +1)
   and sends it about 100 times a second over UDP to 127.0.0.1:47801.
2. `PedalRudder.lua` is loaded by one line at the end of `Saved Games\DCS\Scripts\Export.lua`.
   Every frame it calls `LoSetCommand(2003, value)`, the generic rudder axis.
3. If the script stops, DCS gets 0 once after half a second and then the rudder is left alone.
4. It wraps the existing export callbacks and calls them first, so DCS-BIOS keeps working.

Nothing is installed in Windows, so Forza and other games never see an extra device.

## Setup (once)

Run these from the repo root in a Windows terminal, or from WSL with `uv.exe` in place of `uv`.

1. **Install the DCS half.** This copies the Lua file to `Scripts\DMS\` and adds the
   Export.lua line. The first install backs up your old file as `Export.lua.dms-backup`.

        uv run --script tools/pedal_rudder/pedal_rudder.py install

2. **Calibrate.** Turn the MOZA base on, then press the pedals when prompted. It finds which
   axis each pedal uses and its range, then saves them to `%USERPROFILE%\.dms\pedal-rudder.json`.

        uv run --script tools/pedal_rudder/pedal_rudder.py calibrate

3. **Check it.** This shows a live bar for every axis and the mixed rudder value.

        uv run --script tools/pedal_rudder/pedal_rudder.py monitor

4. **In DCS** (Options, Controls, for each aircraft): clear any bindings on the MOZA base's
   clutch and throttle axes, and leave the rudder axis unbound. If you don't, DCS reads them
   directly as well.

## Every flight

Double-click `tools/pedal_rudder/pedal-rudder.cmd`, or run:

    uv run --script tools/pedal_rudder/pedal_rudder.py

Leave it open while you fly. The status line shows both pedals, the rudder bar and the send
rate. When DCS has a mission running and receives the values, it shows `DCS linked`.

## Tuning

Edit `%USERPROFILE%\.dms\pedal-rudder.json`:

| Key | Default | Meaning |
|---|---|---|
| `deadzone` | 0.03 | fraction of pedal travel ignored at the rest end |
| `curve` | 1.0 | above 1 softens small inputs (1.5 to 2 is a typical rudder curve) |
| `invert` | false | swap rudder direction |
| `hz` | 100 | send rate |
| `port` | 47801 | must match `PORT` in PedalRudder.lua |

## Uninstall

    uv run --script tools/pedal_rudder/pedal_rudder.py uninstall

This removes the Export.lua line and the Lua file.

## Open checks (cockpit)

- Confirm that command 2003 moves the pedals in each module you fly, starting with the AH-64D.
  Most modules accept it, but some read the rudder through their own input path.
- In multiplayer, a server's export restrictions may block it.
- In `dcs.log`, look for `DMS.PedalRudder` lines: `listening on 127.0.0.1:47801` and then
  `pedals linked, feeding rudder`.
