# Arma 3 knowledge base

Verified reference material for building Arma 3 missions. Prefer these files over memory. Mark
anything not backed by them as TO-VERIFY.

| File | What | Source |
|---|---|---|
| [functions.txt](functions.txt) | All 2,062 `BIS_fnc_*` / `BIN_fnc_*` function names, one per line | BI wiki "Arma 3: Functions" category, pasted by the user 2026-10-27 |
| [wiki-pages.md](wiki-pages.md) | Scripting intro, getting started, Editing and Eden Editor category indexes | BI wiki, pasted by the user 2026-10-27 |
| [../RESEARCH.md](../RESEARCH.md) | MVP research: mission structure, headless server, class names (unverified), build plan | Agent research, partly from memory |

## Confirmed facts (from these pages)
- Scenario folder: `Documents\Arma 3\missions\<Name>.<World>\` (single-player/editor) or `mpmissions\`.
  `description.ext` and event scripts (`initServer.sqf`, `initPlayerLocal.sqf`) sit next to `mission.sqm`.
  Functions conventionally live in `functions\fn_*.sqf`.
- Positions are `[x, y, z]` with x = west→east, y = south→north, z = altitude. ASL and AGL differ.
- Scripts are SQF. Arma Reforger uses Enforce Script instead, so its scripting is not compatible.

## Enforcement
`arma/tools/test_kb_functions.py` fails if any mission file calls a `BIS_fnc_*`/`BIN_fnc_*` that is
not in `functions.txt`.

## Wanted next (paste into this folder when convenient)
- https://community.bistudio.com/wiki/Arma_3:_CfgVehicles_WEST and `_EAST` (unit/vehicle class names)
- https://community.bistudio.com/wiki/Arma_3:_Communication_Menu
- https://community.bistudio.com/wiki/Arma_3:_Task_Framework
- https://community.bistudio.com/wiki/Arma_3:_Dedicated_Server
