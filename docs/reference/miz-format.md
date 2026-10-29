# .miz format reference

This is condensed from `legacy/knowledge/miz-file-manipulation.md`. The legacy regex workflow is
retired ([ADR 0011](../adr/0011-retire-regex-mizparser.md)). To edit missions, use the lupa dict
round-trip ([ADR 0002](../adr/0002-lupa-dict-round-trip-for-editing.md)). To create them, use
pydcs ([ADR 0001](../adr/0001-pydcs-for-generation-only.md)).

## Archive layout

A `.miz` is a plain ZIP archive. You can inspect one with `unzip -l mission.miz`.

| Entry | Contents |
|---|---|
| `mission` | Lua source assigning `mission = { ... }`, which holds everything below |
| `options` | Lua table of mission options |
| `warehouses` | Lua table of airbase and warehouse stock |
| `theatre` | Plain text holding the map name |
| `l10n/DEFAULT/dictionary` | Lua table of localized strings (`DictKey_*`), such as briefing text |
| `l10n/DEFAULT/mapResource` | Lua table mapping `ResKey_*` to file names in `l10n/DEFAULT/` |
| `l10n/DEFAULT/*` | Embedded resources: scripts, `.ogg`/`.wav` audio, kneeboard images |
| `KNEEBOARD/IMAGES/*` | Mission kneeboard pages, at the archive root (verified in ED-shipped quickstart missions; the ME keeps root files as sim files) |

When you re-zip, copy every entry you didn't change **byte for byte**.

## Mission table hierarchy

```lua
mission = {
  ["coalition"] = {
    ["blue"] = {                       -- also "red", "neutrals"
      ["country"] = {
        [1] = {
          ["id"] = 2, ["name"] = "USA",
          ["plane"]      = { ["group"] = { [1] = { ...group... } } },
          ["helicopter"] = { ["group"] = { ... } },
          ["vehicle"]    = { ["group"] = { ... } },
          ["ship"]       = { ["group"] = { ... } },
          ["static"]     = { ["group"] = { ... } },
        },
      },
    },
  },
  ["triggers"] = { ["zones"] = { ... } },        -- trigger zones (type 0 circle, 2 quad with "verticies")
  ["trig"] = { ["actions"]={}, ["conditions"]={}, ["func"]={}, ["flag"]={}, ["custom"]={} },  -- compiled triggers
  ["trigrules"] = { ... },                       -- editor-side trigger definitions
  ["weather"] = { ... }, ["date"] = { ... }, ["start_time"] = 28800,
  ["maxDictId"] = 0, ["version"] = 23,
}
```

### Group template (vehicle example)

```lua
{
  ["groupId"] = 123, ["name"] = "Armor-1", ["x"] = -50000, ["y"] = 30000,
  ["hidden"] = false, ["visible"] = false, ["uncontrolled"] = false,
  ["lateActivation"] = false, ["start_time"] = 0, ["tasks"] = {},
  ["units"] = {
    [1] = { ["unitId"] = 456, ["name"] = "Armor-1-1", ["type"] = "T-72B",
            ["skill"] = "Average", ["x"] = -50000, ["y"] = 30000, ["heading"] = 0 },
  },
  ["route"] = { ["points"] = { ... } },
}
```

The required fields differ by category:

| Category | Typical extra fields |
|---|---|
| plane | `alt`, `alt_type`, `speed` (m/s), `task` (e.g. "CAP"), `payload`, `callsign`, `onboard_num` |
| helicopter | as plane; `task` such as "Transport" or "CAS" |
| vehicle | `task = "Ground Nothing"` (group), `playerCanDrive` |
| ship | `frequency` (Hz), `modulation` |

## Identifiers

- `groupId` and `unitId` are integers that must be unique across the whole mission. When adding
  units, start from the current maximum plus 1.
- Group and unit **names** must also be unique. At runtime, a `coalition.addGroup` call with a
  clashing name replaces the existing group.
- `maxDictId` must be greater than every `DictKey_N` in use.

## Coordinates

- DCS map coordinates are in metres relative to a theater origin.
  - **`x` points north.**
  - **`y` points east**. In Lua runtime Vec3 terms this is `z`, and Vec3 `y` is altitude.
  - (The legacy doc had these axes swapped.)
- Headings are in radians, clockwise from true north.
- To offset a position: `x += d·cos(h)`, `y += d·sin(h)`.
- Altitude types: `"BARO"` is above mean sea level and `"RADIO"` is above ground level.
- Converting lat/lon uses a theater-specific transverse Mercator projection (pyproj; pydcs
  terrain classes include the parameters).

## Triggers and scripts

- A DO SCRIPT FILE action references a `ResKey_*`. Its file sits in `l10n/DEFAULT/` and is
  registered in `mapResource`.
- The `trig` table holds **compiled Lua strings** (`actions`, `conditions`, `func`). If you edit
  `trigrules`, regenerate them too, or DCS will run stale logic.
- Audio files need a trigger that references them, or the Mission Editor strips them on the next save.

## Safety checklist

- Work on copies. Never overwrite the user's input `.miz`.
- Test the round-trip first: parse, serialize, then diff against the original.
- Before adding anything, check that the names and IDs are unique.
- After building, run `dms check out.miz`, then load the mission in DCS and check `dcs.log`
  (see [ADR 0009](../adr/0009-definition-of-done-requires-flight.md)).
