# Player flights: start options, slots, air starts, loadouts

The user flies mostly single player and wants each mission to offer **start on the ramp OR
already airborne**. Do that with start *variants*: the same flight declared twice.

```yaml
player_flights:
  - callsign: Python            # a DCS callsign name for the type (see below)
    aircraft: F-16C_50
    count: 2                    # lead = Player, #2 = AI wingman (slot: player)
    start_area: incirlik        # near_airbase area
    start_type: parking_cold
    variant: ramp               # -> out/<id>-ramp.miz
    slot: player
    loadout: auto               # SEAD mission -> preset 'sead'
    tasking: "RAMP START. Cold start at Incirlik, ... RTB Incirlik."
  - callsign: Python
    aircraft: F-16C_50
    count: 2
    start_area: incirlik        # the line start_area -> air_start.toward sets the axis
    start_type: air
    variant: air                # -> out/<id>-air.miz
    slot: player
    air_start:
      altitude_ft: 20000        # default 20000
      speed_kts: 420            # default 420
      distance_nm_before_first_wp: 20   # default 20
      toward: ip_arrow          # area id of the IP; default = first objective with an area
    loadout: auto
    tasking: "AIR START. Airborne 20 NM short of IP ARROW, ... RTB Incirlik."
```

Rules:

- **variant**: flights with the same variant are built together; each distinct variant is its
  own `.miz` named `<id>-<variant>.miz`; flights without a variant appear in every variant.
  `<id>.miz` is also written as a copy of the first variant. Use lowercase ids (`ramp`, `air`,
  `hot`, `runway`).
- **slot**: `player` (default) makes the lead unit the single-player `Player` and the other
  `count-1` units AI wingmen (skill High) that spawn and fly with the player. `client` makes every
  unit a multiplayer `Client` slot. Only one `player` flight per variant; a second one is planned
  as `client` and validate warns. AI wingmen never count as players at runtime, so `players_only`
  beats and `player.spawned` only react to the lead.
- **Group names**: the planner names flights `<callsign> <n>` in spec order (`Python 1` = ramp,
  `Python 2` = air). Beats that filter on a group or unit name (`group: "Python 1"`,
  `unit: "Python 2-2"`) only fire in the variant that has that group. Prefer `players_only: true`
  or `group_prefix: Python` for beats that must work in every variant.
- **Radio callsign**: both variants are `Python 1-1` in the cockpit (numbered per variant). If the
  spec callsign is not a DCS name for the type, validate warns and the closest valid name is used;
  put the real cockpit callsign in the briefing and kneeboard.
- **air_start**: only with `start_type: air`. The flight starts `distance_nm_before_first_wp`
  short of `toward` on the line from `start_area`, heading toward it, at `altitude_ft` (BARO) and
  `speed_kts`, wingmen in echelon right, full internal fuel. Its route continues to the IP.
- **Loadouts**: `loadout: auto` uses the aircraft's mission-type preset. F-16C_50 presets:
  `sead` (2x AGM-88C, 2x GBU-12, ALQ-184, HTS, LITENING, 2x AIM-120C, 2x AIM-9X), `lgb_strike`
  (4x GBU-12 on TERs, 2x 370 gal tanks, ALQ-184, LITENING, AIM-120C/AIM-9X), `cas` (2x GBU-12 TER
  + 2x AGM-65D, tanks, ALQ-184, LITENING, AIM-120C/AIM-9X). A preset name is exact; free text with
  HARM/SEAD, CAS/Maverick or GBU/LGB/strike maps to those presets. Fuel is always full internal.
- **Test builds**: `dms build --test` replaces a ramp/runway flight with the AI proxy (so on-deck
  and landing beats are reachable); `--variant air` tests the air start instead.
