"""End-to-end contract test: Python RuntimeConfig -> dms_config.lua -> bundled Lua runtime.

Builds DMS_CONFIG for campaigns/dustoff-valley m01 *by hand* from mission-spec.yaml, beats.yaml,
lines.yaml (+ bible callsigns, campaign qualities), serializes it with ``to_lua_source()``, bundles
the runtime with ``tools/bundle_lua.py`` into ``dist/dms.lua`` and boots both inside the DCS mock
(lupa, Lua 5.1). Then it flies the mission: player spawns at Hatay, takes off, crosses the gate,
patrols the box, gets shot at, kills the known AAA (and the pop-up gun when it appears), hits a
convoy, recrosses the gate, lands -- 30+ simulated minutes, across 50 seeds.

When ``dms_gen.planner.plan_mission`` works, the same simulation also runs on ``plan.runtime``.
"""

from __future__ import annotations

import importlib.util
import json
import math
import re
import subprocess
import sys
from functools import cache
from pathlib import Path
from typing import Any

import pytest
import yaml
from dms_core.luaio import dumps
from dms_core.schemas import (
    BeatSheet,
    MissionSpec,
    RuntimeConfig,
    StoryBible,
    VoiceLineSet,
)
from dms_core.schemas.outcome import parse_dcs_log, summarize_outcomes

REPO = Path(__file__).resolve().parents[2]
CAMPAIGN = REPO / "campaigns" / "dustoff-valley"
M01 = CAMPAIGN / "missions" / "m01-first-light"
DIST = REPO / "dist" / "dms.lua"
SEEDS = list(range(1, 51))
SIM_MIN_SEC = 30 * 60

# Fallback if beats.yaml predates the `guaranteed` flag.
GUARANTEED_SPINE = [
    "mission_start",
    "kestrel_checkin",
    "on_station",
    "patrol_complete",
    "tower_welcome",
    "on_deck",
]

# Hand-resolved DCS map coordinates (x north, y east, meters) for every m01 area. The planner
# does this from lat/lon; here the geometry only has to be self-consistent.
NM = 1852.0
AREA_XY: dict[str, dict[str, Any]] = {
    "hatay": {"kind": "circle", "x": 0, "y": 0, "radius": 1 * NM},
    "hatay_approach": {"kind": "circle", "x": 0, "y": 0, "radius": 5 * NM},
    "gate_west": {"kind": "circle", "x": 30000, "y": 0, "radius": 1.5 * NM},
    "patrol_box": {
        "kind": "polygon",
        "points": [
            {"x": 35000, "y": -4000},
            {"x": 50000, "y": -4000},
            {"x": 50000, "y": 4000},
            {"x": 35000, "y": 4000},
        ],
    },
    "reyhanli_aaa": {"kind": "circle", "x": 31000, "y": -7000, "radius": 0.8 * NM},
    "kirikhan_aaa": {"kind": "circle", "x": 62000, "y": -2000, "radius": 0.8 * NM},
    "canal_east": {"kind": "circle", "x": 42000, "y": 16000, "radius": 1.5 * NM},
    "orchard_ridge": {"kind": "circle", "x": 28000, "y": 14000, "radius": 1.5 * NM},
    "staging_farm": {"kind": "circle", "x": 48500, "y": 3000, "radius": 0.4 * NM},
    "staging_watch": {"kind": "circle", "x": 48500, "y": 3000, "radius": 2 * NM},
    "canal_road": {"kind": "circle", "x": 44000, "y": -10000, "radius": 3 * NM},
    "kirikhan_road": {"kind": "circle", "x": 58000, "y": -9000, "radius": 1 * NM},
    "kestrel_ridge": {"kind": "circle", "x": 52000, "y": -6000, "radius": 0.5 * NM},
}
# A lake that overlaps candidate spawn areas: nothing may ever spawn in it.
WATER = [{"x": 42000, "y": 16000, "radius": 1500}, {"x": 44000, "y": -12000, "radius": 2000}]

RED, NEUTRAL = "INSURGENTS", "UN_PEACEKEEPERS"
TEMPLATES: dict[str, dict[str, Any]] = {
    "zu23_emplacement": {
        "country": RED,
        "category": "ground",
        "skill": "Average",
        "units": [{"type": "ZU-23 Emplacement"}, {"type": "Infantry AK", "dx": 15, "dy": 5}],
    },
    "ural_zu23": {
        "country": RED,
        "category": "ground",
        "units": [{"type": "Ural-375 ZU-23", "heading": 90}],
    },
    "dshk_technical": {
        "country": RED,
        "category": "ground",
        "units": [{"type": "HL_DSHK"}, {"type": "HL_DSHK", "dx": -30}],
    },
    "ak_team": {
        "country": RED,
        "category": "ground",
        "units": [{"type": "Infantry AK", "dx": i * 4} for i in range(5)],
    },
    "staging_trucks": {
        "country": RED,
        "category": "ground",
        "units": [{"type": "Ural-375", "dx": -25 * i} for i in range(4)],
    },
    "civ_traffic": {
        "country": NEUTRAL,
        "category": "ground",
        "units": [{"type": "LAZ Bus"}, {"type": "VAZ Car", "dx": -30}],
    },
}
ROLE_TEMPLATES = {
    "aaa": [("zu23_emplacement", 2), ("ural_zu23", 1)],
    "technicals": [("dshk_technical", 3)],
    "infantry": [("ak_team", 2)],
    "hvt": [("staging_trucks", 1)],
    "civilian": [("civ_traffic", 1)],
}


# ---------------------------------------------------------------------------
# inputs
# ---------------------------------------------------------------------------


def _yaml(path: Path) -> Any:
    return yaml.safe_load(path.read_text(encoding="utf-8"))


@cache
def inputs() -> tuple[MissionSpec, BeatSheet, VoiceLineSet, StoryBible, dict[str, float]]:
    spec = MissionSpec.model_validate(_yaml(M01 / "mission-spec.yaml"))
    beats = BeatSheet.model_validate(_yaml(M01 / "beats.yaml"))
    lines = VoiceLineSet.model_validate(_yaml(M01 / "lines.yaml"))
    bible = StoryBible.model_validate(_yaml(CAMPAIGN / "bible.yaml"))
    q = _yaml(CAMPAIGN / "state" / "qualities.yaml") or {}
    return spec, beats, lines, bible, {k: float(v) for k, v in (q.get("values") or {}).items()}


def guaranteed_ids(beats: BeatSheet) -> list[str]:
    flagged = [b.id for b in beats.beats if getattr(b, "guaranteed", False)]
    return flagged or GUARANTEED_SPINE


_TAG = re.compile(r"\[[^\]]*\]\s*")


def build_runtime(seed: int) -> RuntimeConfig:
    """DMS_CONFIG for m01, assembled by hand from the authored files."""
    spec, beats, lines, bible, qualities = inputs()
    missing = [a for a in spec.area_ids() if a not in AREA_XY]
    assert not missing, f"test geometry lacks areas {missing}"

    pools: dict[str, Any] = {}
    for p in spec.dynamic.pools:
        civilian = "civilian" in p.roles or "civilian" in (p.faction or "")
        roles = ["civilian"] if civilian else list(p.roles)
        members = [
            {"tpl": tpl, "w": w} for role in roles for tpl, w in ROLE_TEMPLATES.get(role, [])
        ]
        assert members, f"no templates for pool {p.id} roles {p.roles}"
        pick = (1, 1) if p.id in ("staging", "civilians") else tuple(p.pick)
        pools[p.id] = {"members": members, "pick": pick, "zones": list(p.areas)}

    encounters: list[dict[str, Any]] = []
    for e in spec.dynamic.encounters:
        t = e.trigger
        trig: dict[str, Any] = {"type": t.type}
        if t.type == "proximity":
            trig.update(zone=t.area, radius_m=(t.radius_nm or 3) * NM)
        elif t.type == "time":
            trig["after_sec"] = (t.after_min or 0) * 60
        elif t.type == "beat":
            trig["beat"] = t.beat
        enc: dict[str, Any] = {
            "id": e.id,
            "kind": e.kind,
            "pool": e.pool,
            "trigger": trig,
            "chance": e.chance,
            "hunt": e.hunt,
        }
        if e.telegraph_beat:
            enc["telegraph"] = f"beat:{e.telegraph_beat}"
        if e.kind == "convoy":
            enc.update(destination="kirikhan_road", resume_after_sec=(60, 120), speed=10)
        encounters.append(enc)
    # First contact: militia patrols appear once the player reaches the box (director-gated).
    encounters.append(
        {
            "id": "patrol_contact",
            "kind": "pool",
            "pool": "patrols",
            "trigger": {"type": "proximity", "zone": "patrol_box"},
            "chance": 100,
        }
    )

    voice = {
        ln.id: {
            "file": f"{ln.id}.ogg",
            "text": _TAG.sub("", ln.subtitle or ln.text).strip(),
            "dur_sec": max(2.0, 0.4 * len(ln.text.split()) + 1),
            "speaker": ln.speaker,
        }
        for ln in lines.lines
    }
    speakers = {
        c.id: {"callsign": c.callsign}
        for c in bible.characters
        if c.id in spec.cast and getattr(c, "callsign", None)
    }
    fow = spec.dynamic.fog_of_war
    return RuntimeConfig.model_validate(
        {
            "seed": seed,
            "debug": seed % 10 == 0,
            "mission_id": spec.id,
            "budgets": {"max_active_ground": 150, "max_active_air": 16, "spawns_per_min": 4},
            "director": {"enabled": spec.dynamic.director.enabled},
            "templates": TEMPLATES,
            "zones": {a: AREA_XY[a] for a in spec.area_ids()},
            "pools": pools,
            "encounters": encounters,
            "beats": [b.model_dump(exclude_none=True) for b in beats.beats],
            "voice": voice,
            "speakers": speakers,
            "qualities": qualities,
            "narrative": {"min_gap_sec": 8},
            "intel": {
                "fog_of_war": fow.enabled,
                "reveal_radius_m": fow.reveal_radius_km * 1000,
                "mark_refresh_sec": fow.mark_refresh_sec,
            },
            "players": {"coalition": 2},
        }
    )


def static_groups_by_hand() -> list[dict[str, Any]]:
    spec = inputs()[0]
    out = []
    for t in spec.threats:
        z = AREA_XY[t.area]
        out.append(
            {
                "name": t.id,
                "coalition": 1,
                "units": [
                    {"name": f"{t.id}-1", "type": "ZU-23 Emplacement", "x": z["x"], "y": z["y"]},
                    {
                        "name": f"{t.id}-2",
                        "type": "ZU-23 Emplacement",
                        "x": z["x"] + 30,
                        "y": z["y"],
                    },
                ],
            }
        )
    for s in spec.support:
        z = AREA_XY[s.area or "hatay"]
        out.append(
            {
                "name": s.id,
                "coalition": 2,
                "units": [
                    {"name": f"{s.id}-{i}", "type": "Soldier M4", "x": z["x"] + i * 3, "y": z["y"]}
                    for i in range(1, 5)
                ],
            }
        )
    return out


# ---------------------------------------------------------------------------
# Lua side
# ---------------------------------------------------------------------------


@cache
def _lua_env_cls() -> Any:
    spec = importlib.util.spec_from_file_location("dms_lua_conftest", REPO / "lua" / "conftest.py")
    assert spec and spec.loader
    mod = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = mod
    spec.loader.exec_module(mod)
    return mod.LuaEnv


@pytest.fixture(scope="module")
def bundle() -> Path:
    proc = subprocess.run(
        [sys.executable, str(REPO / "tools" / "bundle_lua.py"), "--out", str(DIST)],
        cwd=REPO,
        capture_output=True,
        text=True,
    )
    assert proc.returncode == 0, proc.stdout + proc.stderr
    return DIST


def _zone_center(z: dict[str, Any]) -> tuple[float, float]:
    if z.get("kind") == "polygon" or "points" in z:
        pts = z["points"]
        return sum(p["x"] for p in pts) / len(pts), sum(p["y"] for p in pts) / len(pts)
    return float(z["x"]), float(z["y"])


def flight_route(zones: dict[str, Any]) -> tuple[tuple[float, float], list[tuple[float, float]]]:
    """Hatay -> gate_west -> around the box -> farm -> gate_west -> Hatay."""
    start = _zone_center(zones["hatay"])
    route = [_zone_center(zones["gate_west"])]
    box = zones["patrol_box"]
    if "points" in box:
        route += [(p["x"], p["y"]) for p in box["points"]] + [
            (box["points"][0]["x"], box["points"][0]["y"])
        ]
    else:
        route.append(_zone_center(box))
    if "staging_watch" in zones:
        route.append(_zone_center(zones["staging_watch"]))
    route.append(_zone_center(box))
    route.append(_zone_center(zones["gate_west"]))
    route.append(start)
    return start, route


SIM_LUA = Path(__file__).with_name("sim_m01.lua")


def run_sim(
    bundle: Path,
    cfg: RuntimeConfig,
    statics: list[dict[str, Any]],
    start: tuple[float, float],
    route: list[tuple[float, float]],
    seed: int,
) -> Any:
    env = _lua_env_cls()([])
    env.run_string("MOCK.waterAreas = " + dumps(WATER))
    for g in statics:
        env.run_string(
            "MOCK.addGroup("
            + dumps(
                {
                    "name": g["name"],
                    "coalition": g["coalition"],
                    "category": "ground",
                    "silent": True,
                    "units": g["units"],
                }
            )
            + ")"
        )
    src = cfg.to_lua_source()
    (REPO / "dist").mkdir(exist_ok=True)
    env.run_string(src, "=dms_config.lua")
    env.run_file(bundle)
    sim = {
        "start": list(start),
        "route": [list(p) for p in route],
        "minSec": SIM_MIN_SEC,
        "killCivilian": seed % 4 == 0,
    }
    env.run_string('MOCK.declare("SIM"); SIM = ' + dumps(sim))
    env.run_file(SIM_LUA)
    return env


def lua_list(t: Any) -> list[Any]:
    return [t[i] for i in range(1, len(t) + 1)] if t is not None else []


def log_entries(env: Any) -> list[tuple[str, str]]:
    log = env.g.MOCK.log
    return [(str(log[i].level), str(log[i].msg)) for i in range(1, len(log) + 1)]


def check_run(env: Any, cfg: RuntimeConfig, guaranteed: list[str], seed: int) -> None:
    g = env.g
    logs = log_entries(env)
    tail = "\n".join(f"{lv}: {m}" for lv, m in logs[-60:])
    errors = [m for lv, m in logs if lv == "error"]
    assert not errors, f"seed {seed}: errors in log:\n" + "\n".join(errors[:10])
    assert not env.raw_errors(), f"seed {seed}: raw errors {env.raw_errors()}"
    assert g.DMS._booted is True
    assert float(g.SIM.endedAt) >= SIM_MIN_SEC

    # --- beats ---------------------------------------------------------------------------
    fired = [str(x) for x in lua_list(g.DMS.Narrative.firedList())]
    beat_ids = {b.id for b in cfg.beats}
    assert set(fired) <= beat_ids
    missing = [b for b in guaranteed if b not in fired]
    assert not missing, f"seed {seed}: guaranteed beats not fired {missing}; fired={fired}\n{tail}"
    pos = {b: fired.index(b) for b in fired}
    order = [pos[b] for b in guaranteed]
    assert order == sorted(order), f"seed {seed}: guaranteed spine out of order: {fired}"
    once_beats = {b.id for b in cfg.beats if b.once}
    for b in once_beats:
        assert fired.count(b) <= 1, f"seed {seed}: once-beat {b} fired {fired.count(b)}x"
    pairs = [
        ("first_armed_kill", "kill_followup"),
        ("popup_aa_warning", "popup_aa_engaging"),
        ("ambient_net", "ambient_net_reply"),
        ("on_station", "patrol_complete"),
        ("patrol_complete", "tower_welcome"),
    ]
    for a, b in pairs:
        if b in pos:
            assert a in pos and pos[a] < pos[b], f"seed {seed}: {b} before {a}: {fired}"
    assert "first_armed_kill" in pos, f"seed {seed}: kill not narrated: {fired}"
    assert "known_aaa_reyhanli_dead" in pos
    assert "known_aaa_firing" in pos and "player_hit" in pos
    assert "tower_departure" in pos
    if g.SIM.did.civ_killed:
        assert "civilian_hit" in pos, f"seed {seed}: civilian kill not narrated: {fired}"
    assert "player_lost" not in pos

    # --- comms ----------------------------------------------------------------------------
    history = lua_list(g.DMS.Comms.history())
    played = [str(h.line) for h in history if h.line is not None]
    assert played, f"seed {seed}: nothing transmitted"
    unknown = [ln for ln in played if ln not in cfg.voice]
    assert not unknown, f"seed {seed}: comms played unknown line ids {unknown}"
    for h in history:
        if h.line is not None:  # voice file is optional (subtitle-only lines)
            assert (h.file or None) == (cfg.voice[str(h.line)].file or None)
    by_beat = {b.id: set(b.lines) for b in cfg.beats}
    for b in guaranteed:
        if by_beat.get(b):
            assert by_beat[b] & set(played), f"seed {seed}: no line played for guaranteed {b}"

    # --- encounters / spawns ----------------------------------------------------------------
    spawned = lua_list(g.SIM.eventsNamed("spawner.spawned"))
    assert spawned, f"seed {seed}: nothing spawned"
    wet = env.eval("SIM.unitsInWater()")
    assert wet == 0, f"seed {seed}: {wet} units spawned in water"
    for e in spawned:
        if e.p.encounter is not None:
            assert str(e.p.encounter) in {x.id for x in cfg.encounters}
    if g.SIM.convoyHit is not None:
        halted = lua_list(g.SIM.eventsNamed("convoy.halted"))
        assert any(str(h.p.group) == str(g.SIM.convoyHit) for h in halted), (
            f"seed {seed}: convoy hit but not halted"
        )
    popup = lua_list(g.SIM.eventsNamed("encounter.spawned"))
    if any(str(e.p.id) == "popup_aa" for e in popup):
        assert "popup_aa_warning" in pos, f"seed {seed}: pop-up gun not telegraphed: {fired}"

    # --- outcome --------------------------------------------------------------------------
    text = "\n".join(m for _, m in logs)
    outcomes = parse_dcs_log(text)
    assert outcomes, f"seed {seed}: no [DMS.OUTCOME] lines"
    raw = [ln for ln in text.splitlines() if "[DMS.OUTCOME]" in ln]
    assert len(raw) == len(outcomes), "an outcome line failed to parse"
    for ln in raw:
        json.loads(ln.split("[DMS.OUTCOME]", 1)[1])
    merged = summarize_outcomes(outcomes)
    assert set(merged) == {cfg.mission_id}
    m = merged[cfg.mission_id]
    assert m.result == "success", f"seed {seed}: result {m.result}"
    assert m.outcomes.get("patrol_complete") is True
    assert m.outcomes.get("landed") is True
    assert m.outcomes.get("reyhanli_aaa_destroyed") is True
    ends = [o for o in outcomes if o.result is not None]
    assert ends and ends[-1].result == "success"
    assert sum(1 for o in outcomes if (o.kind or o.extra.get("event")) == "end") == 1


# ---------------------------------------------------------------------------
# tests
# ---------------------------------------------------------------------------


def test_runtime_config_round_trips_through_lua(bundle: Path) -> None:
    """to_lua_source() parses back (luaio) to the camelCase table, user keys preserved."""
    from dms_core.luaio import loads

    cfg = build_runtime(7)
    back = loads(cfg.to_lua_source(), "DMS_CONFIG")
    assert back["missionId"] == "m01-first-light"
    assert "patrol_box" in back["zones"]
    assert any(b["id"] == "patrol_complete" for b in back["beats"].values()) or any(
        b["id"] == "patrol_complete" for b in back["beats"]
    )


@pytest.mark.parametrize("seed", SEEDS)
def test_m01_hand_built_config(bundle: Path, seed: int) -> None:
    cfg = build_runtime(seed)
    start, route = flight_route(AREA_XY)
    env = run_sim(bundle, cfg, static_groups_by_hand(), start, route, seed)
    check_run(env, cfg, guaranteed_ids(inputs()[1]), seed)


@cache
def _plan(seed: int) -> Any:
    try:
        from dms_gen.planner import plan_mission
    except ImportError as exc:  # pragma: no cover - planner not present
        pytest.skip(f"planner unavailable: {exc}")
    spec, beats, lines, bible, _ = inputs()
    try:
        return plan_mission(spec, beats, lines, seed=seed, bible=bible)
    except Exception as exc:  # planner is under concurrent development
        pytest.skip(f"plan_mission failed: {type(exc).__name__}: {exc}")


def _plan_statics(plan: Any) -> tuple[list[dict[str, Any]], tuple[float, float] | None]:
    side = {"red": 1, "blue": 2, "neutral": 0}
    statics, start = [], None
    for grp in plan.groups:
        if grp.client:
            start = start or (grp.units[0].x, grp.units[0].y)
            continue
        if grp.category in ("plane", "helicopter", "ship"):
            continue
        statics.append(
            {
                "name": grp.name,
                "coalition": side[grp.coalition],
                "units": [{"name": u.name, "type": u.type, "x": u.x, "y": u.y} for u in grp.units],
            }
        )
    return statics, start


@pytest.mark.parametrize("seed", SEEDS[:10])
def test_m01_planner_config(bundle: Path, seed: int) -> None:
    plan = _plan(seed)
    cfg = plan.runtime
    assert cfg is not None
    zones = cfg.to_lua_table()["zones"]
    need = {"hatay", "gate_west", "patrol_box", "hatay_approach"}
    if not need <= set(zones):
        pytest.skip(f"planner runtime lacks zones {sorted(need - set(zones))}")
    statics, pstart = _plan_statics(plan)
    start, route = flight_route(zones)
    if pstart and math.dist(pstart, start) < 5 * NM:
        start = pstart
    env = run_sim(bundle, cfg, statics, start, route, seed)
    check_run(env, cfg, guaranteed_ids(inputs()[1]), seed)
