# Rebuild research notes (2026-10-27)

Condensed findings from parallel research agents. They feed `ARCHITECTURE-PROPOSAL.md`.
Items marked [?] were not verified.

## DCS scripting gotchas (verified against the Hoggit wiki, ED forums and MOOSE source)

- **Lua 5.1**: no `goto`, no `table.unpack` (use `unpack`), no `//`. `os`, `io`, `lfs`, `require`
  and `package.loadlib` are sanitized. Use `timer.getTime()` / `timer.getAbsTime()` and `env.mission.date`.
- **Timers**: an error inside a `timer.scheduleFunction` callback kills that loop permanently.
  Always pcall the body and return the next time. Wrap `onEvent` in pcall too.
- **Ground ROE**: only OPEN_FIRE(2), RETURN_FIRE(3), WEAPON_HOLD(4). `WEAPON_FREE` exists for air only.
  Alarm state: `AI.Option.Ground.id.ALARM_STATE` with AUTO/GREEN/RED. `DISPERSE_ON_ATTACK` takes
  seconds (0 = off).
- **Ground routes**: `setTask({id='Mission', params={route={points={...}}}})`. Use ≥2 points with
  the current position first [? community lore]. `y` = Vec3 `z`; speed is in m/s. Actions: Off Road,
  On Road, Cone, Rank, Diamond, Vee, EchelonL/R.
  - `StopRoute`: `setCommand({id='StopRoute', params={value=true/false}})`.
  - Others: `SwitchWaypoint`, `Hold`, and
    `FireAtPoint {point={x,y}, radius, expendQty, expendQtyEnabled}`.
  - AttackGroup/AttackUnit are broken for ground units.
- **Spawning**: `coalition.addGroup(country.id.X, Group.Category.GROUND, data)`.
  - Omit groupId/unitId and DCS assigns them.
  - A name clash **replaces** the existing group, so names must be unique.
  - Delay about 1 s before touching a new group's controller.
  - Late activation: the group exists but `unit:isActive()` is false. Activate with `grp:activate()`.
  - `hidden` / `hiddenOnMFD` / `hiddenOnPlanner` can only be set at spawn time.
- **Surface**: `land.getSurfaceType({x,y})` returns LAND / SHALLOW_WATER / WATER / ROAD / RUNWAY.
  Check for obstacles with `world.searchObjects(Object.Category.SCENERY, sphere, cb)`.
- **F10**: there is no runtime hide or reveal, and the map view mode can't be scripted.
  - Marks: `markToAll` / `markToCoalition` / `markToGroup`, `circleToAll(coal,id,center,r,color,fill,lineType,ro,msg)`,
    plus `lineToAll`, `quadToAll`, `textToAll`, `setMarkupText` / `Color` / `PositionStart`, `removeMark`.
  - Mark IDs share one global namespace with player marks, so start the counter at about 10000.
- **Events**: DEAD is unreliable, so subscribe to DEAD + UNIT_LOST(30) + KILL(28) and deduplicate.
  Cache positions, because the unit may be invalid inside DEAD. Initiator and target can be nil,
  Static, Scenery or Weapon: check `getCategory` under pcall. PLAYER_ENTER_UNIT is unreliable, so
  detect players on BIRTH with `getPlayerName() ~= nil`.
- **Menus**: use `missionCommands.add*ForGroup`. Rebuild on BIRTH and pass gid / unit name in `arg`.
- **Sound**: play with `trigger.action.outSound('l10n/DEFAULT/x.ogg')` or the ForCoalition /
  ForGroup / ForUnit variants. The file must be in `l10n/DEFAULT/` and listed in mapResource
  (`ResKey_*`), and a dummy trigger should reference it so the Mission Editor doesn't strip it.
  `trigger.action.radioTransmission(file, vec3, mod, loop, freqHz, power, name)` [? new subtitle param].
- **Zones**: `trigger.misc.getZone` returns only `{point, radius}`. Quad zones come from
  `env.mission.triggers.zones[i]` with `type==2` and `verticies` (sic). Use point-in-polygon.
- **Detection**: `ctrl:getDetectedTargets(...)` and `ctrl:isTargetDetected(obj, ...)`.
  `land.isVisible(p1,p2)` checks terrain only.
- **Skill** cannot change at runtime. **Weather** cannot change at runtime.
- **Performance**: about 150–300 active ground units and 20–40 AI aircraft. Run schedulers every
  5–15 s. In MP, stagger spawns 1–3 s apart.

## pydcs (hands-on, probe in the session scratchpad)

- **Version**: `pip install pydcs` 1.0.0 (2026-10-25), Python ≥3.11. The PyPI package `dcs` is
  unrelated. No Iraq terrain. Retribution pins a fork.
- **Generation works**: `flight_group_from_airport(...)` + `set_client()`, `vehicle_group` +
  `add_waypoint(OnRoad)`, `add_triggerzone` / `_quad`,
  `DoScriptFile(m.map_resource.add_resource_file(path))`, `PartOfGroupInZone`, briefing setters.
  The default CAS loadout for the AH-64 is 4 fuel tanks, so set pylons explicitly.
- **Livery scanner** finds DCS through the registry and picked the OpenBeta profile. Set paths explicitly.
- **Load/save is lossy**:
  - Verbose and unit-reference fail with `KeyError: 'enable_fog'`.
  - Others lose `trig.custom`, `start_delay` and passwords, the version drops from 23 to 20, and
    inline DO SCRIPT may be mangled.
  - **Never round-trip user missions through pydcs.**
- **Lua parsers**: lupa (real Lua) + our own serializer gives an exact round-trip on all 5 missions.
  `dcs.lua` loads/dumps is OK as a pure-Python fallback. slpp mangles escapes: do not use.
- **Editing existing missions**: parse → dict → edit (must also update compiled
  `trig.actions` / `conditions` / `func` strings) → serialize → rezip, copying other files byte for byte.

## Prior art

- **MOOSE**: GPL-3, 2.9.19 (Oct 2026), very active, single `Moose_.lua`. Covers SPAWN, ZONE_POLYGON,
  MANTIS/SHORAD, INTEL, AUFTRAG/CHIEF, EasyGCICAP, CTLD, CSAR, ATIS, SRS, Scoring.
- **MIST**: maintenance only. Needed by Skynet, classic CTLD and Hound.
- **Skynet-IADS** (Apache-2, needs MIST): realistic SAM network. **Hound**: ELINT radar triangulation.
- **DML** (cfrag): configured through Mission Editor zone attributes. Awkward for generation.
- **Liberation / Retribution** (LGPL-3, pydcs): their plugin manifest (`plugin.json`, ordered
  DO SCRIPT FILE, options as Lua globals) is the model for our bundling.
- **BriefingRoom** (GPL-3, C#): the closest generator. Template/INI data model is worth studying.
- **No mature NL → .miz tool exists.** DCS-ME-gateway (MCP) needs a running Mission Editor.

## Replayability (AI Director)

- L4D director: intensity per player (damage, near misses, kills) with decay, cycling
  BUILD_UP → PEAK → RELAX (30–90 s).
- Guaranteed beats + random fill from weighted tables, using a shuffle-bag / pity counter.
  Randomise *which* and *where*, never *whether it's winnable*.
- Telegraph before punishing: intel call or RWR spike 30–60 s before a pop-up threat.
  Never spawn in sight; minimum distances are about 20 nm for air and 5 km for ground, out of LOS.
- Hidden adaptation: spawn frequency, pool size, skill of **new** spawns, SAM reaction delay. Clamp to ±1 tier.
- RNG seed: `os` is sanitized, so mix in sub-second `timer.getTime()` at the first player birth
  [? our recommendation].

## Story pipeline

- **Briefing**: 5-paragraph order (Situation, Mission, Execution with commander's intent,
  Admin/logistics, Command & signal) plus an intel narrative. The kneeboard repeats 3–5.
  Baltic Dragon: "pilots don't talk nonsense"; story lives in the gaps around procedure.
- **Storylets / quality-based narrative**: beats with preconditions on qualities/flags, effects,
  priority and cooldown. A drama manager picks the most salient eligible beat.
- **Persistence**:
  - (a) native `.cmp` score-based stages
  - (b) `env.info("[DMS.OUTCOME] {json}")` → debriefer parses dcs.log
  - (c) manual questionnaire
  - (d) opt-in de-sanitized `io` only
- **LLM hygiene**: files are memory (bible, arc, append-only continuity ledger). Historical claims
  carry `{claim, source_url, confidence}`, `mode` is historical / adapted / fictional, and real
  people are never given invented quotes. Fiction maps factions to DCS country / units / theater
  with a "tech veneer".
- **ElevenLabs 2026**: Eleven v3 GA (audio tags such as `[shouts]`), Text-to-Dialogue (multi-speaker
  JSON), Voice Design v3, Sound Effects v2, Flash v2.5 for drafts.
  Radio FX via ffmpeg (300–3400 Hz band-pass, compression, squelch) → `.ogg`.

### Schemas (sketch)

```yaml
# bible.yaml
mode: adapted
setting: {era: 2004, theater: Syria, premise_summary: ...}
tone: {register: professional-terse, themes: [attrition, trust]}
factions: [{id: red_militia, name: "Free Valley Front", dcs: {country: Insurgents, coalition: red, units: [...]}}]
characters: [{id: ops_mustang, callsign: Mustang, voice: {eleven_voice_id: ..., design_prompt: ...}, arc: ...}]
timeline: [{date: ..., event: ..., source: url, fictional: false}]

# beats.yaml (compiled into DMS_CONFIG.beats)
- id: aaa_spotted
  when: {event: unit_detected, group_prefix: AAA_KIRK}
  requires: {flag_not: aaa_spotted}
  priority: 70
  cooldown_s: 60
  once: true
  speaker: ops_mustang
  lines: [aaa_spotted_v1, aaa_spotted_v2]
  text: "..."
  mark: {type: circle, at: group:AAA_KIRK}
  effects: {set_flag: aaa_spotted, outcome: {aaa_found: true}}
```

## Tooling

- **Python**: uv workspace (virtual root, packages/*, src layout, underscores), ruff, mypy strict,
  pytest, pydantic v2.
- **Lua**:
  - Linting: selene + `dcs-world-selene.yml` from YoloWingPixie/dcs-world-schema (or luacheck with
    a DCS read_globals list).
  - StyLua `syntax=Lua51`; LuaLS defs from omltcat/dcs-lua-definitions.
  - Tests: busted + our own `mocks/dcs.lua`.
  - Bundling: a Python concatenator, because `require` is nil in DCS.
- **CI**:
  - Python job: `astral-sh/setup-uv`.
  - Lua job: `leafo/gh-actions-lua` 5.1.5 + luarocks busted, plus `luac -p dist/dms.lua`.
- **Headless smoke test** (local only):
  - `DCS_server.exe --norender --server -w DCS.dms_test` with a hook that loads the mission, waits,
    then calls `DCS.exitProcess()`.
  - Then scrape dcs.log.
  - DCS-gRPC is available for state queries.
- **MCP**: `mcp` SDK FastMCP over stdio, with pydantic return types for structured output. Use
  coarse write tools and fine search tools; no CRUD tools. Build the CLI + skill first.
- **CLAUDE.md**: keep it under 200 lines with commands, hard rules and links. Enforce hard rules
  with hooks and put procedures in skills.
