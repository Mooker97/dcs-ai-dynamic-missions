"""ArmaMissionSpec <-> fn_config.sqf.

`emit_config` writes the file deterministically (same spec -> same bytes). `spec_from_config`
is the inverse over the parsed file and is how a spec is reconstructed from a hand-tuned mission.
Comments and layout of the hand-written file are not preserved; values are.
"""

from __future__ import annotations

from collections.abc import Sequence
from dataclasses import dataclass, field
from typing import Any

from .spec import ArmaMissionSpec, Wave
from .sqf import WRAPPER, SqfValue, parse_config, sqf_format, sqf_string

LINE_WIDTH = 130
"""Emitted lines wider than this (tab = 4 columns) break arrays one element per line."""

Entry = tuple[str, SqfValue, str]
"""(SQF key, value, trailing comment or '')."""


@dataclass
class Section:
    """A commented group of config entries."""

    title: str
    notes: list[str] = field(default_factory=list)
    entries: list[Entry] = field(default_factory=list)


def _xy(v: Sequence[float]) -> list[SqfValue]:
    return [v[0], v[1]]


def _wave(w: Wave) -> list[SqfValue]:
    return [
        list(w.vehicle_classes),
        list(w.infantry_classes),
        w.infantry_count,
        _xy(w.dismount_distance),
    ]


def config_sections(spec: ArmaMissionSpec) -> list[Section]:
    """The fn_config.sqf content of `spec`, in The Hill's key order."""
    s, sq, c, e, q, a, x, t = (
        spec.sites,
        spec.squad,
        spec.compound,
        spec.enemy,
        spec.qrf,
        spec.artillery,
        spec.exfil,
        spec.test,
    )
    return [
        Section(
            "sites",
            [
                "[name, centerXY, compoundDir, startBearing, [qrfSpawnA_XY, qrfSpawnB_XY],"
                " [qrfNameA, qrfNameB], mode]",
                "mode OUTPOST garrisons the terrain outpost at centerXY; BUILD snaps to flat"
                " ground and builds composition.",
                "outpostComposition: [kind, class, [minR, maxR], clearR]",
            ],
            [
                (
                    "sites",
                    [
                        [
                            i.name,
                            _xy(i.center),
                            i.compound_dir,
                            i.start_bearing,
                            [_xy(i.qrf_spawns[0]), _xy(i.qrf_spawns[1])],
                            list(i.qrf_names),
                            i.mode,
                        ]
                        for i in s.sites
                    ],
                    "",
                ),
                ("outpostClasses", list(s.outpost_classes), ""),
                ("outpostRadius", s.outpost_radius, ""),
                (
                    "outpostComposition",
                    [
                        [i.kind, i.class_name, _xy(i.radius), i.clear_radius]
                        for i in s.outpost_composition
                    ],
                    "",
                ),
                ("siteSnapRadius", s.site_snap_radius, ""),
                ("clearRadius", s.clear_radius, ""),
                ("startDistance", s.start_distance, ""),
                ("lzDistance", s.lz_distance, ""),
                ("aoMarkerRadius", s.ao_marker_radius, ""),
                ("aoMarkerFuzz", _xy(s.ao_marker_fuzz), ""),
            ],
        ),
        Section(
            "player squad",
            [],
            [
                ("squadLeaderClass", sq.leader_class, ""),
                ("squadClasses", list(sq.classes), ""),
                ("squadSkill", sq.skill, ""),
            ],
        ),
        Section(
            "built compound (mode BUILD)",
            [
                "[kind, class, [dx, dy], relDir]; dx/dy in metres in the compound frame"
                " (+y = compoundDir)",
            ],
            [
                (
                    "composition",
                    [[i.kind, i.class_name, _xy(i.offset), i.rel_dir] for i in c.composition],
                    "",
                ),
                ("intelClass", c.intel_class, ""),
                ("intelHoldSeconds", c.intel_hold_seconds, ""),
            ],
        ),
        Section(
            "enemy",
            [],
            [
                ("sentryClass", e.sentry_class, ""),
                ("garrisonClasses", list(e.garrison_classes), ""),
                ("garrisonCount", e.garrison_count, ""),
                ("patrolSize", e.patrol_size, ""),
                ("patrolRadius", e.patrol_radius, ""),
                ("enemySkill", [[k, v] for k, v in e.skill.items()], ""),
                ("alarmKnowsAbout", e.alarm_knows_about, ""),
            ],
        ),
        Section(
            "QRF",
            [
                "wave: [vehicleClasses (first existing wins), infantryClasses, infantryCount,"
                " dismountDistance [min, max]]"
            ],
            [
                ("wave1", _wave(q.wave1), ""),
                ("wave2", _wave(q.wave2), ""),
                ("wave1Delay", _xy(q.wave1_delay), ""),
                ("wave2Delay", _xy(q.wave2_delay), ""),
                ("wave2DragTime", q.wave2_drag_time, ""),
                ("wave2QuickKill", q.wave2_quick_kill, ""),
                ("qrfFlankOffset", q.flank_offset, ""),
                ("qrfFlankAngle", q.flank_angle, ""),
            ],
        ),
        Section(
            "artillery",
            [],
            [
                ("artyMissions", a.missions, ""),
                ("artyRoundsFFE", a.rounds_ffe, ""),
                ("artySpotRounds", a.spot_rounds, ""),
                ("artyProcessTime", a.process_time, ""),
                ("artyTimeOfFlight", a.time_of_flight, ""),
                ("artyCEP", a.cep, ""),
                ("artyAdjustedCEP", a.adjusted_cep, ""),
                ("artyAdjustWindow", a.adjust_window, ""),
                ("artyDangerClose", a.danger_close, ""),
                ("artyAmmo", a.ammo, ""),
                ("artyInterval", _xy(a.interval), ""),
            ],
        ),
        Section(
            "extraction",
            [],
            [
                ("exfilHeliClass", x.heli_class, ""),
                ("exfilSpawnDistance", x.spawn_distance, ""),
                ("exfilHoldDistance", x.hold_distance, ""),
                ("exfilFlyHeight", x.fly_height, ""),
                ("exfilHotRadius", x.hot_radius, ""),
                ("exfilHotVehicleRadius", x.hot_vehicle_radius, "armed enemy vehicle radius"),
                ("exfilReadyRadius", x.ready_radius, "player/squad distance to call the heli in"),
                ("exfilReadyMaxWait", x.ready_max_wait, "s at the hold point"),
                ("exfilHotMaxHold", x.hot_max_hold, "s off a hot LZ before RTB"),
                ("exfilHotCount", x.hot_count, ""),
                ("exfilWaitOnGround", x.wait_on_ground, ""),
                ("exfilBoardRadius", x.board_radius, ""),
                ("exfilDepartDistance", x.depart_distance, ""),
            ],
        ),
        Section(
            "test mode",
            [],
            [
                ("testArtyAt", t.arty_at, ""),
                ("testAlarmTimeout", t.alarm_timeout, ""),
                ("testIntelTimeout", t.intel_timeout, ""),
                ("testExpected", list(t.expected), ""),
            ],
        ),
    ]


def config_values(spec: ArmaMissionSpec) -> dict[str, SqfValue]:
    """The config as a key -> value dict (what `parse_config` returns for the emitted file)."""
    return {k: v for sec in config_sections(spec) for k, v, _ in sec.entries}


def emit_config(spec: ArmaMissionSpec, source: str = "") -> str:
    """Render `functions/fn_config.sqf` for `spec`. Deterministic; tabs; LF line endings."""
    header = [
        "/*",
        "\tDMS_fnc_config",
        "\tGENERATED by dms-arma (packages/dms-arma). Edit the spec, not this file.",
        f"\tTemplate: {spec.template}   World: {spec.world}   Mission: {spec.name}",
    ]
    if source:
        header.append(f"\tSpec: {source}")
    header += [
        f"\tReturns a HashMap. Positions are {spec.world} world [x, y] in metres.",
        "*/",
        "",
        f"{WRAPPER} [",
    ]
    lines = list(header)
    sections = config_sections(spec)
    for si, sec in enumerate(sections):
        if si:
            lines.append("")
        lines.append("\t// " + ("-" * 64) + " " + sec.title)
        lines.extend("\t// " + note for note in sec.notes)
        for ei, (key, value, comment) in enumerate(sec.entries):
            last = si == len(sections) - 1 and ei == len(sec.entries) - 1
            prefix = "[" + sqf_string(key) + ", "
            body = sqf_format(value, indent=1, width=LINE_WIDTH, prefix=len(prefix) + 1)
            line = "\t" + prefix + body + "]" + ("" if last else ",")
            if comment:
                line += " // " + comment
            lines.append(line)
    lines += ["]", ""]
    return "\n".join(lines)


# ------------------------------------------------------------------------------- inverse

CONFIG_KEYS: tuple[str, ...] = (
    "sites", "outpostClasses", "outpostRadius", "outpostComposition", "siteSnapRadius",
    "clearRadius", "startDistance", "lzDistance", "aoMarkerRadius", "aoMarkerFuzz",
    "squadLeaderClass", "squadClasses", "squadSkill",
    "composition", "intelClass", "intelHoldSeconds",
    "sentryClass", "garrisonClasses", "garrisonCount", "patrolSize", "patrolRadius",
    "enemySkill", "alarmKnowsAbout",
    "wave1", "wave2", "wave1Delay", "wave2Delay", "wave2DragTime", "wave2QuickKill",
    "qrfFlankOffset", "qrfFlankAngle",
    "artyMissions", "artyRoundsFFE", "artySpotRounds", "artyProcessTime", "artyTimeOfFlight",
    "artyCEP", "artyAdjustedCEP", "artyAdjustWindow", "artyDangerClose", "artyAmmo",
    "artyInterval",
    "exfilHeliClass", "exfilSpawnDistance", "exfilHoldDistance", "exfilFlyHeight",
    "exfilHotRadius", "exfilHotVehicleRadius", "exfilReadyRadius", "exfilReadyMaxWait",
    "exfilHotMaxHold", "exfilHotCount", "exfilWaitOnGround", "exfilBoardRadius",
    "exfilDepartDistance",
    "testArtyAt", "testAlarmTimeout", "testIntelTimeout", "testExpected",
)  # fmt: skip
"""Every fn_config key the spec covers, in emission order."""


def _wave_raw(v: Any) -> dict[str, Any]:
    veh, inf, count, dismount = v
    return {
        "vehicle_classes": veh,
        "infantry_classes": inf,
        "infantry_count": count,
        "dismount_distance": dismount,
    }


def spec_from_config(
    cfg: dict[str, SqfValue],
    *,
    template: str = "the_hill",
    world: str = "Altis",
    name: str = "The Hill",
) -> ArmaMissionSpec:
    """Rebuild a spec from a parsed fn_config. Unknown or missing keys raise `ValueError`.

    Structural mismatches (wrong tuple arity, wrong types) surface as pydantic errors or
    `ValueError` from unpacking.
    """
    unknown = [k for k in cfg if k not in CONFIG_KEYS]
    missing = [k for k in CONFIG_KEYS if k not in cfg]
    if unknown or missing:
        raise ValueError(f"config keys not covered by the spec: {unknown}; missing: {missing}")
    g: dict[str, Any] = dict(cfg)
    raw: dict[str, Any] = {
        "template": template,
        "world": world,
        "name": name,
        "sites": {
            "sites": [
                {
                    "name": n,
                    "center": ctr,
                    "compound_dir": d,
                    "start_bearing": b,
                    "qrf_spawns": qs,
                    "qrf_names": qn,
                    "mode": m,
                }
                for n, ctr, d, b, qs, qn, m in g["sites"]
            ],
            "outpost_classes": g["outpostClasses"],
            "outpost_radius": g["outpostRadius"],
            "outpost_composition": [
                {"kind": k, "class_name": c, "radius": r, "clear_radius": cr}
                for k, c, r, cr in g["outpostComposition"]
            ],
            "site_snap_radius": g["siteSnapRadius"],
            "clear_radius": g["clearRadius"],
            "start_distance": g["startDistance"],
            "lz_distance": g["lzDistance"],
            "ao_marker_radius": g["aoMarkerRadius"],
            "ao_marker_fuzz": g["aoMarkerFuzz"],
        },
        "squad": {
            "leader_class": g["squadLeaderClass"],
            "classes": g["squadClasses"],
            "skill": g["squadSkill"],
        },
        "compound": {
            "composition": [
                {"kind": k, "class_name": c, "offset": o, "rel_dir": r}
                for k, c, o, r in g["composition"]
            ],
            "intel_class": g["intelClass"],
            "intel_hold_seconds": g["intelHoldSeconds"],
        },
        "enemy": {
            "sentry_class": g["sentryClass"],
            "garrison_classes": g["garrisonClasses"],
            "garrison_count": g["garrisonCount"],
            "patrol_size": g["patrolSize"],
            "patrol_radius": g["patrolRadius"],
            "skill": {k: v for k, v in g["enemySkill"]},
            "alarm_knows_about": g["alarmKnowsAbout"],
        },
        "qrf": {
            "wave1": _wave_raw(g["wave1"]),
            "wave2": _wave_raw(g["wave2"]),
            "wave1_delay": g["wave1Delay"],
            "wave2_delay": g["wave2Delay"],
            "wave2_drag_time": g["wave2DragTime"],
            "wave2_quick_kill": g["wave2QuickKill"],
            "flank_offset": g["qrfFlankOffset"],
            "flank_angle": g["qrfFlankAngle"],
        },
        "artillery": {
            "missions": g["artyMissions"],
            "rounds_ffe": g["artyRoundsFFE"],
            "spot_rounds": g["artySpotRounds"],
            "process_time": g["artyProcessTime"],
            "time_of_flight": g["artyTimeOfFlight"],
            "cep": g["artyCEP"],
            "adjusted_cep": g["artyAdjustedCEP"],
            "adjust_window": g["artyAdjustWindow"],
            "danger_close": g["artyDangerClose"],
            "ammo": g["artyAmmo"],
            "interval": g["artyInterval"],
        },
        "exfil": {
            "heli_class": g["exfilHeliClass"],
            "spawn_distance": g["exfilSpawnDistance"],
            "hold_distance": g["exfilHoldDistance"],
            "fly_height": g["exfilFlyHeight"],
            "hot_radius": g["exfilHotRadius"],
            "hot_vehicle_radius": g["exfilHotVehicleRadius"],
            "ready_radius": g["exfilReadyRadius"],
            "ready_max_wait": g["exfilReadyMaxWait"],
            "hot_max_hold": g["exfilHotMaxHold"],
            "hot_count": g["exfilHotCount"],
            "wait_on_ground": g["exfilWaitOnGround"],
            "board_radius": g["exfilBoardRadius"],
            "depart_distance": g["exfilDepartDistance"],
        },
        "test": {
            "arty_at": g["testArtyAt"],
            "alarm_timeout": g["testAlarmTimeout"],
            "intel_timeout": g["testIntelTimeout"],
            "expected": g["testExpected"],
        },
    }
    return ArmaMissionSpec.model_validate(raw, strict=False)


def spec_from_sqf(text: str, *, world: str = "Altis", name: str = "The Hill") -> ArmaMissionSpec:
    """Parse fn_config.sqf text and rebuild the spec."""
    return spec_from_config(parse_config(text), world=world, name=name)
