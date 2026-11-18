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
      toward: ip_arrow          # area id of the IP; default = an ip_* area, else the first objective area
    loadout: auto
    tasking: "AIR START. Airborne 20 NM short of IP ARROW, ... RTB Incirlik."
```

Rules:

- **coalition / country**: the player's coalition is the side the catalog gives the aircraft
  (`uv run dms catalog units --era <year>`: Mi-8MT, Mi-24P, Ka-50 are red; F-16C_50, A-10C_2,
  AH-64D_BLK_II, UH-1H are blue), as the bible's `canon_rules` record. `country` is a full DCS
  country name (`Combined Joint Task Forces Blue`, `Russia`, `Georgia`, ...).

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
  **Helicopters ignore `air_start`** (validate warns): a helicopter with `start_type: air` starts
  airborne over its `start_area` at 150 m AGL and 200 km/h and flies its low-level route from
  there. Omit `air_start` for them; a helicopter "air variant" saves start-up, not transit.
- **Route** (planned for every flight from your areas): departure -> `IP` (`air_start.toward`, or
  the first area whose id contains `ip`/`ingress`/`push`, e.g. `ip_arrow`) -> `TGT`/`TGT1..n`
  (objective areas in spec order; a target threat/support/single-area pool stands in for a
  missing area) -> `EGRESS` (first area id containing `egress`) -> `HOME` (landing at the `land`
  objective's airbase, else the start airbase). Jets fly it at 20,000 ft, helicopters at 150 m
  AGL. Name an IP and an egress area if you want those steerpoints.
- **Loadouts**: `loadout: auto` uses the aircraft's mission-type preset; a preset name is exact;
  free text (HARM/SEAD, CAS/Maverick, GBU/LGB/strike, hellfire, rockets) maps to a preset. Fuel is
  always full internal. Presets (`packages/dms-gen/src/dms_gen/builder/payloads.py`):

  | Aircraft | Presets (`auto` default first where mapped) |
  |---|---|
  | F-16C_50 | `sead` (SEAD/DEAD), `lgb_strike` (STRIKE), `cas` (CAS) |
  | A-10C_2 | `cas` |
  | AH-64D_BLK_II | `hellfire_rockets`, `hellfire_heavy`, `rockets` |
  | Mi-8MT, UH-1H | `transport` (TRANSPORT/CSAR), `rockets` (CAS) |
  | CH-47Fbl1 | `transport` |
  | Mi-24P | `atgm_rockets` (CAS), `rockets`, `transport` (TRANSPORT/CSAR) |
  | Ka-50, Ka-50_3 | `atgm_rockets`, `rockets` |
  | SA342M | `atgm` |
  | OH58D | `hellfire_rockets`, `hellfire`, `rockets` |

  Any other airframe gets the **DCS default payload, often clean pylons** (validate warns "no
  presets for X"). Say so in the briefing ("rearm on the ramp") and prefer the ramp variant.
  There is no cargo/passenger model: troops or kilos carried are fiction in lines and briefing.
- **Test builds**: `dms build --test` replaces a ramp/runway flight with the AI proxy (so on-deck
  and landing beats are reachable); `--variant air` tests the air start instead.
