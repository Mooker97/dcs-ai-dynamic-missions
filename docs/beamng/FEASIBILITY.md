# BeamNG.drive backend: feasibility

Status: research only, 2026-10-27. Checked the install on disk without launching anything.
`[?]` = not verified yet (needs the game running, or the source was unclear).

## Verdict

**Feasible, and easier than expected.** BeamNG.drive 0.40 ships its **own MCP server**
(`lua/ge/extensions/mcp/`). It can run any GE Lua, spawn vehicles, set AI, read damage and electrics,
pause and step physics, change time of day and tail `beamng.log`. That gives us a harness for the
Steam game with no licence needed. BeamNGpy is the fallback, and on .drive it is probably
**not usable**: see below.

## 1. What's installed

| Item | Finding |
|---|---|
| Install | `E:\SteamLibrary\steamapps\common\BeamNG.drive` |
| Version | `integrity.json` → **0.40.3.0** (buildbot 290897). Last launch logged 0.38.6 on 2026-07-28, so the Steam update hasn't been run yet. |
| User folder | `C:\Users\mook\AppData\Local\BeamNG\BeamNG.drive\current\`: `mods\`, `settings\`, `beamng.log` (+ `.1–.3` rotations). Old per-version folders (0.24–0.36) are under `AppData\Local\BeamNG.drive\`. |
| Levels (`content\levels\*.zip`) | automation_test_track, autotest, Cliff, derby, driver_training, east_coast_usa, garage_v2, glow_city, gridmap_v2, hirochi_raceway, Industrial, italy, johnson_valley, jungle_rock_island, showroom_v2(+lighting_simple), smallgrid, small_island, template, Utah, west_coast_usa |
| `-tcom` | Handled in `lua/ge/client/parseArgs.lua`. It runs `extensions.load('tech/techCore')` and logs `Cannot load techCore extension` on failure. **`lua/ge/extensions/tech/` is not shipped** (and `integrity.json` doesn't list it), so `-tcom` will fail on .drive [? confirm in log]. `-tcom-listen-ip` and `-tport` don't appear in the exe. |
| Other flags | `-level`, `-lua`, `-luafile`, `-onLevelLoad_ext`, `-vehicle`, `-vehicleConfig`, `-log` (parseArgs). The strings `headless`, `console`, `nosteam`, `userpath` and `gfx` are in `Bin64\BeamNG.drive.x64.exe` [? behaviour untested]. `Bin64\console.x64.exe` exists. |
| **MCP** | Setting `enableMcp` (default `false`, `settings/defaults.json`). It serves `http://127.0.0.1:29292/mcp` (Streamable HTTP, protocol 2025-11-25). Flags: `-mcpport N`, `-mcpremote`. Tools include `run_lua`, `get_logs`, `spawn`, `set_ai`/`get_ai`/`drive_to`, `get_vehicle_damage`, `get_electrics`, `pause_physics`/`step_physics`/`set_simulation_speed`, `set_time_of_day`, `load_level`, `set_position`, `screenshot`, `write_file`. Release notes not found online [?]. |

### Install re-check, 2026-10-29 (detection only, nothing launched)

| Check | Result |
|---|---|
| Steam libraries (`C:\Steam\steamapps\libraryfolders.vdf`) | `C:\Steam`, `P:\SteamLibrary`, `H:\SteamLibrary`, `E:\SteamLibrary`. App 284160 (BeamNG.drive) is only in **E:** (`appmanifest_284160.acf`, buildid 26137019, StateFlags 4 = fully installed). |
| `integrity.json` | `"version": "0.40.3.0"`, buildbot 290897 |
| Registry `HKCU\Software\BeamNG\BeamNG.drive` | `rootpath` = `E:\SteamLibrary\steamapps\common\BeamNG.drive\`, `version` = `0.36.4.0` (stale, written by an older launch). `HKCU\Software\Valve\Steam\Apps\284160`: Installed=1, Updating=0, Running=0. No `HKLM\SOFTWARE\BeamNG`. |
| Last run | `beamng.log` was last written 2026-07-28 and saved version `0.38.6.0`, so 0.40.3 has never been launched. |
| BeamNG.tech | **Not installed.** There are no `BeamNG.tech*` folders on C:/D:/E: and no tech registry key. The install-root `tech\` folder only holds `annotations.json` and `part_annotation_config.json` (semantic annotation data), and there is no `lua/ge/extensions/tech/`. |
| Built-in MCP | Present: `lua/ge/extensions/mcp/{server,shared,tools}.lua` + `tools/` |
| beamngpy | **Not installed**: not in the workspace venv (`uv pip show`), the system Python 3.13 or `pip`. It is declared as the optional extra `dms-beamng[beamngpy]` and imported lazily. |

## 2. BeamNGpy

- Latest is **1.36**, paired with **BeamNG.tech 0.39** ([README](https://github.com/BeamNG/BeamNGpy),
  [compat table](https://documentation.beamng.com/api/beamngpy/master/readme.html)). It describes itself as
  "Python API to interact with BeamNG.tech".
- It launches `<binary> -nosteam -tcom -tport 25252 [-console] [-headless] [-gfx null] [-userpath]`. The
  binary list includes `BeamNG.drive.exe`, but the pip package ships **no Lua**: it relies on the game's
  `tech/techCore`. Old docs said Steam .drive was "compatible to an extent (no camera/LiDAR)". That was
  written before techCore was removed from .drive builds [?].
- Licensing: BeamNG.tech is free for academic/research use ([register.beamng.tech](https://register.beamng.tech)),
  and commercial use goes through licensing@beamng.gmbh. A hobby project doesn't clearly qualify [?]. .drive's
  EULA (`EULA.pdf` in the install) covers personal use. Scripting your own game for personal play is normal modding [?].
- APIs (read from the 1.36 docstrings), which are useful as a map of what the engine can do:
  `vehicle.ai.set_mode('disabled|random|traffic|span|manual|chase|flee|stopping')`, `set_waypoint`,
  `set_target`, `drive_in_lane`, `drive_using_waypoints`, `set_script`, `set_aggression`;
  `bng.traffic.spawn(max_amount, police_ratio, extra_amount, parked_amount)`;
  `bng.control.step/pause/resume/queue_lua_command`; `bng.settings.set_deterministic(steps_per_second)`;
  `bng.env.set_tod/set_weather_preset`; `bng.scenario.load/start/get_road_network`; Damage and Electrics sensors.
  All of these wrap GE/vehicle Lua that **also exists in .drive**, so we call the Lua directly.

## 3. Mission formats (on disk)

- **Career/freeroam missions:** `gameplay/missions/<level>/<type>/<id>/info.json`. Each mission layers on a
  type template in `gameplay/missionTypes/<type>/`. 27 types, including **`evade`** (police escape:
  `arrestLimit`, `evadeLimit`, `goalRoadblocks`, `hideoutActive`, `chasers.vehGroup.json`), **`chase`**,
  `arrive`, `delivery`, `freeformDelivery`, `garageToGarage`, `flowgraph`. A custom mission can be the `flowgraph`
  type with a `.flow.json`. `"isAvailableAsScenario": true` makes it launchable outside career.
- **Legacy scenarios:** `levels/<level>/scenarios/<name>.json` (array: name, vehicles, uilayout,
  lapConfig, extensions), plus `.prefab` (objects and waypoints) and a `.lua` module using `scenario/scenariohelper`.
  The simplest format to generate, and needs no flowgraph [?].
- **Flowgraph nodes** (`lua/ge/extensions/flowgraph/nodes/gameplay/traffic/`): `trafficSpawnGroup`,
  `trafficParams`, `trafficActivate`, `setupPursuitGameplay`, `pursuitMode`, `pursuitParams`, **`pursuitRoadblock`**,
  `pursuitInformation`, `parkingParams`. Plus `gameplay/delivery`, `career/customTowAction` (career "tow" is a
  teleport-to-garage, not a physical hook).
- **Police API** (`gameplay_police`): `setPursuitMode`, `setPursuitVars`, `placeRoadblock`/`setupRoadblock`,
  `setSuspect`, `arrestVehicle`, `evadeVehicle`, `getPursuitData`, `getNearestPoliceVehicle`; **traffic**
  (`gameplay_traffic`): `setupTraffic`, `insertTraffic`, `activate`, `forceTeleport`. These are exactly the levers a Director needs.
- **Towing:** `electricWinch`/`hydraulicWinch` and jbeam `vropes` exist. Vehicles include `flatbed`, `tiltdeck`,
  `dolly` and `md_series`/`us_semi`. A physical hook-and-tow needs a winch or rope part on a tow vehicle [? which stock config has one].
- **Mods:** a zip in `<user>\current\mods\` that mirrors game paths (`levels/...`, `gameplay/...`,
  `lua/ge/extensions/...`). The install has `NOTE_FOR_MODDERS.md`, and its readme says not to install mods in the game folder.

## 4. Testing loop

1. Python generates a mod zip (scenario JSON, prefab and a Lua director extension `dms_director`) into `mods\`.
2. Launch `BeamNG.drive.x64.exe -level west_coast_usa/main.level.json -lua "..."` with `enableMcp` on. Or
   start the scenario through MCP `run_lua` (`scenario_scenariosLoader.start(...)` [?]).
3. The player car runs on AI (`set_ai mode=manual` + waypoint, or `drive_to`). For The Getaway, use `flee` from the nearest police car.
4. The Director logs `[DMS.OUTCOME] {...}` lines. Python polls `get_logs`, `get_vehicle_damage`, `get_position`
   and `gameplay_police.getPursuitData()`, then asserts.
5. Speed: `set_simulation_speed` >1, or deterministic stepping via `pause_physics`/`step_physics`. Log is
   `<user>\current\beamng.log`. Expected wall time: about 60–90 s level load plus a 3–8 min run at 1×, maybe 2–4× faster with time scale [?].
   True headless/`-gfx null` on .drive is unconfirmed [?]: assume a visible window.

## 5. MVP recommendation

**Architecture** (same shape as DCS/Arma): `dms beamng build` → generator writes a mod zip
(`levels/<lvl>/scenarios/dms_<id>.json/.prefab/.lua` + `lua/ge/extensions/dms/director.lua` + voice OGGs) →
the runtime Lua Director (seeded RNG, traffic/police levers, `[DMS.OUTCOME]` logging) → a Python harness
over the **built-in MCP** (HTTP JSON-RPC, no extra dependency).

- **The Getaway first.** The stock `evade` type plus the police API already provide pursuit, roadblocks and
  arrest/evade scoring. The Director only escalates (`setPursuitVars`, `placeRoadblock`, police ratio) and picks
  the safe house. Test it with AI in `flee` mode. More exciting, and needs less new physics work.
- **Tow Truck Shift second.** Dispatch is easy with a waypoint and traffic. The hard part is "hook the wreck". MVP shortcut:
  the wreck is "loaded" by parking the truck at a marker for N seconds (a flatbed/tiltdeck), then add physical winching later.

**Risks**
1. BeamNGpy can't drive .drive 0.40 (no techCore). Mitigation: built-in MCP or our own GE extension.
2. The MCP server is new and undocumented. Its tool names may change between patches.
3. Police and AI behaviour isn't deterministic, so assertions must be tolerant (outcome classes, not exact times).
4. No true headless mode, so tests need the GPU and a free PC.
5. Physical towing is fiddly (rope/winch coupling, jbeam instability).
6. Patch churn: career/flowgraph formats change between versions. Prefer legacy scenario JSON + Lua.

**First 3 experiments (when the PC is free)**
1. Update via Steam to 0.40.3, enable MCP (Options or `enableMcp`), and connect from Python: `tools/list`,
   `run_lua("return 1+1")`, `load_level west_coast_usa`, `spawn`, `drive_to`, `get_logs`. Also try `-tcom` once
   and grep the log for "Cannot load techCore" to settle BeamNGpy.
2. Drop a hand-written mod (one legacy scenario + a `dms_director` extension that prints `[DMS.OUTCOME]`) into `mods\`.
   Start it via MCP, let AI drive A→B, and read the outcome back. Time the loop at 1× and 4×.
3. Getaway spike: in freeroam, `gameplay_traffic.setupTraffic` with police, `gameplay_police.setSuspect(player)`,
   AI `flee`, then escalate with `placeRoadblock`. Log `getPursuitData()` every 5 s to see whether evade/arrest ends cleanly.
