"""Pool template pinning, player flight routes, support radios/callsigns, FM for low band."""

from __future__ import annotations

import zipfile
from pathlib import Path
from typing import Any

import pytest
from dms_core.luaio import loads
from dms_core.schemas import MissionSpec
from dms_core.schemas.plan import BuildPlan, PlanGroup
from dms_gen.builder import build_from_plan
from dms_gen.builder.mission import support_callsign_names
from dms_gen.check import check_miz
from dms_gen.planner import has_errors, plan_mission, validate, write_runtime_config
from dms_gen.planner.planning import build_speakers, radio_modulation, split_callsign


def spec(**over: Any) -> MissionSpec:
    data: dict[str, Any] = {
        "id": "t01-routes",
        "title": "Routes",
        "theater": "Syria",
        "era": 2016,
        "date": "2016-11-03",
        "mission_type": "SEAD",
        "blue_countries": ["USA"],
        "red_countries": ["Insurgents"],
        "cast": ["magic_ctl", "jtac_ctl"],
        "areas": [
            {
                "id": "incirlik",
                "where": {"kind": "near_airbase", "airbase": "Incirlik", "radius_nm": 1},
            },
            {"id": "ip_arrow", "where": {"kind": "near_named_place", "place": "Kilis"}},
            {"id": "al_bab", "where": {"kind": "near_named_place", "place": "Al-Bab"}},
            {
                "id": "sam_west",
                "where": {
                    "kind": "near_named_place",
                    "place": "Al-Bab",
                    "bearing_deg": 260,
                    "distance_nm": 4,
                },
            },
            {
                "id": "egress_north",
                "where": {
                    "kind": "near_named_place",
                    "place": "Al-Bab",
                    "bearing_deg": 0,
                    "distance_nm": 15,
                },
            },
            {
                "id": "magic_orbit",
                "where": {
                    "kind": "near_airbase",
                    "airbase": "Gaziantep",
                    "radius_nm": 10,
                    "distance_nm": 25,
                    "bearing_deg": 0,
                },
            },
        ],
        "player_flights": [
            {
                "callsign": "Python",
                "aircraft": "F-16C_50",
                "count": 2,
                "start_area": "incirlik",
                "start_type": "parking_cold",
            }
        ],
        "objectives": [
            {"id": "cover", "kind": "protect", "description": "Cover.", "area": "al_bab"},
            {"id": "kill", "kind": "destroy", "description": "Kill.", "target": "sa8_pop"},
            {"id": "rtb", "kind": "land", "description": "Recover.", "area": "incirlik"},
            {"id": "live", "kind": "survive", "description": "Live."},
        ],
        "support": [
            {
                "id": "magic",
                "role": "awacs",
                "callsign": "Magic",
                "area": "magic_orbit",
                "frequency_mhz": 255.5,
                "speaker": "magic_ctl",
            },
            {
                "id": "shell",
                "role": "tanker",
                "callsign": "Shell 2",
                "area": "magic_orbit",
                "frequency_mhz": 276.1,
                "tacan": "51Y",
            },
            {
                "id": "jtac",
                "role": "jtac",
                "callsign": "Axeman",
                "area": "al_bab",
                "frequency_mhz": 41.5,
                "speaker": "jtac_ctl",
            },
        ],
        "dynamic": {
            "pools": [
                {
                    "id": "sa8_pop",
                    "roles": ["sam_short"],
                    "areas": ["sam_west"],
                    "pick": [1, 1],
                    "templates": ["sa8", "sa8_section"],
                }
            ]
        },
    }
    data.update(over)
    return MissionSpec.model_validate(data)


def _lua(tmp: Path) -> Path:
    p = tmp / "dms.lua"
    p.write_text('DMS = DMS or {}\nenv.info("[DMS] dummy")\n', encoding="utf-8")
    return p


def _plan(tmp: Path, s: MissionSpec | None = None) -> BuildPlan:
    p = plan_mission(s or spec(), seed=3, dms_lua=str(_lua(tmp)))
    write_runtime_config(p, tmp)
    return p


def _group(p: BuildPlan, source: str) -> PlanGroup:
    return next(g for g in p.groups if g.source == source)


def _miz(path: Path) -> dict[str, Any]:
    with zipfile.ZipFile(path) as z:
        m: dict[str, Any] = loads(z.read("mission"), "mission")
    return m


def _flying(m: dict[str, Any]) -> dict[str, dict[str, Any]]:
    out: dict[str, dict[str, Any]] = {}
    for coal in m["coalition"].values():
        for c in (coal.get("country") or {}).values():
            for cat in ("plane", "helicopter"):
                for g in (c.get(cat) or {}).get("group", {}).values():
                    out[g["name"]] = g
    return out


def _points(g: dict[str, Any]) -> list[dict[str, Any]]:
    return [pt for _k, pt in sorted(g["route"]["points"].items())]


# ---------------------------------------------------------------- 1. pool templates


def test_pool_templates_pin_runtime_members(tmp_path: Path) -> None:
    p = _plan(tmp_path)
    assert p.runtime is not None
    assert [m.tpl for m in p.runtime.pools["sa8_pop"].members] == ["sa8", "sa8_section"]
    unpinned = spec(
        dynamic={"pools": [{"id": "sa8_pop", "roles": ["sam_short"], "areas": ["sam_west"]}]}
    )
    p2 = plan_mission(unpinned, seed=3)
    assert p2.runtime is not None
    assert len(p2.runtime.pools["sa8_pop"].members) > 2


def test_pool_templates_validate() -> None:
    def pool(templates: list[str]) -> MissionSpec:
        return spec(
            dynamic={
                "pools": [
                    {
                        "id": "sa8_pop",
                        "roles": ["sam_short"],
                        "areas": ["sam_west"],
                        "templates": templates,
                    }
                ]
            }
        )

    ok = validate(pool(["sa8"]))
    assert not [i for i in ok if i.path.endswith(".templates")]
    bad = validate(pool(["zu23_emplacement", "nope"]))
    errs = [i for i in bad if i.path.endswith("dynamic.pools[0].templates")]
    assert errs and errs[0].severity == "error" and has_errors(bad)
    assert "sa8" in errs[0].suggestions
    mixed = validate(pool(["sa8", "nope"]))
    warns = [i for i in mixed if i.path.endswith("dynamic.pools[0].templates")]
    assert warns and warns[0].severity == "warning" and "nope" in warns[0].problem


# ---------------------------------------------------------------- 2. player routes


def test_ramp_flight_route_ip_tgt_egress_home(tmp_path: Path) -> None:
    p = _plan(tmp_path)
    g = next(g for g in p.groups if g.client)
    names = [w.name for w in g.route]
    # al_bab (protect) then sam_west (single-area pool target); rtb/survive skipped
    assert names == [None, "IP", "TGT1", "TGT2", "EGRESS", "HOME"]
    assert g.route[0].action == "From Parking Area"
    assert g.route[-1].action == "Landing" and g.route[-1].airbase == "Incirlik"
    for w in g.route[1:-1]:
        assert w.alt_m == pytest.approx(20000 * 0.3048, abs=1)
        assert w.alt_type == "BARO"
        assert w.speed_kmh == pytest.approx(450 * 1.852, abs=1)

    out = build_from_plan(p, tmp_path / "t.miz", base_dir=tmp_path)
    assert check_miz(out).ok
    fg = _flying(_miz(out))[g.name]
    pts = _points(fg)
    assert [pt.get("name", "") for pt in pts[1:]] == ["IP", "TGT1", "TGT2", "EGRESS", "HOME"]
    assert pts[-1]["type"] == "Land"


def test_route_without_ip_or_egress_goes_straight_to_target(tmp_path: Path) -> None:
    s = spec()
    areas = [a.model_dump() for a in s.areas if a.id not in ("ip_arrow", "egress_north")]
    p = plan_mission(spec(areas=areas), seed=3)
    g = next(g for g in p.groups if g.client)
    assert [w.name for w in g.route] == [None, "TGT1", "TGT2", "HOME"]


def test_air_start_heads_to_ip_area_without_toward() -> None:
    flights = [
        {
            "callsign": "Python",
            "aircraft": "F-16C_50",
            "count": 2,
            "start_area": "incirlik",
            "start_type": "air",
        }
    ]
    p = plan_mission(spec(player_flights=flights), seed=3)
    g = next(g for g in p.groups if g.client)
    assert [w.name for w in g.route] == [None, "IP", "TGT1", "TGT2", "EGRESS", "HOME"]
    ip = p.zones[[z.name for z in p.zones].index("ip_arrow")]
    assert (g.route[1].x, g.route[1].y) == pytest.approx((ip.x, ip.y), abs=1)


def test_helicopter_route_is_low(tmp_path: Path) -> None:
    flights = [
        {
            "callsign": "Gunfighter",
            "aircraft": "AH-64D_BLK_II",
            "count": 2,
            "start_area": "incirlik",
            "start_type": "parking_hot",
        }
    ]
    p = plan_mission(spec(player_flights=flights, mission_type="CAS"), seed=3)
    g = next(g for g in p.groups if g.client)
    legs = g.route[1:-1]
    assert legs and all(w.alt_m == 150 and w.alt_type == "RADIO" for w in legs)
    assert all(w.speed_kmh == 200 for w in legs)


# ---------------------------------------------------------------- 3. support radios


def test_support_frequency_callsign_tacan_in_plan(tmp_path: Path) -> None:
    p = _plan(tmp_path)
    magic, shell = _group(p, "magic"), _group(p, "shell")
    assert magic.frequency_mhz == 255.5 and magic.radio_callsign == "Magic 1-1"
    assert shell.frequency_mhz == 276.1 and shell.radio_callsign == "Shell 2-1"
    assert shell.tacan == "51Y" and magic.tacan is None
    assert magic.modulation == "AM"

    out = build_from_plan(p, tmp_path / "t.miz", base_dir=tmp_path)
    assert check_miz(out).ok
    fl = _flying(_miz(out))
    for g, freq, cs in ((magic, 255.5, "Magic11"), (shell, 276.1, "Shell21")):
        mg = fl[g.name]
        assert float(mg["frequency"]) == pytest.approx(freq)
        assert mg["modulation"] == 0
        u = next(iter(mg["units"].values()))
        assert u["callsign"]["name"] == cs
        tasks = [
            t
            for pt in _points(mg)
            for t in pt.get("task", {}).get("params", {}).get("tasks", {}).values()
        ]
        actions = [t.get("params", {}).get("action", {}) for t in tasks]
        setf = next(a for a in actions if a.get("id") == "SetFrequency")
        assert setf["params"]["frequency"] == pytest.approx(freq * 1e6)
        if g is shell:
            beacon = next(a for a in actions if a.get("id") == "ActivateBeacon")
            assert beacon["params"]["channel"] == 51
            assert beacon["params"]["modeChannel"] == "Y"


def test_support_callsign_names_and_closest() -> None:
    assert support_callsign_names("E-3A", "USA") == [
        "Overlord",
        "Magic",
        "Wizard",
        "Focus",
        "Darkstar",
    ]
    assert support_callsign_names("KC-135", "USA") == ["Texaco", "Arco", "Shell"]
    assert support_callsign_names("F-16C_50", "USA") == []
    assert split_callsign("Texaco 6") == ("Texaco", 6)
    assert split_callsign("Magic") == ("Magic", None)
    s = spec()
    sup = [x.model_dump() for x in s.support]
    sup[0]["callsign"] = "Wizzard"
    s2 = spec(support=sup)
    p = plan_mission(s2, seed=3)
    assert _group(p, "magic").radio_callsign == "Wizard 1-1"
    warns = [i for i in validate(s2) if i.path.endswith("support[0].callsign")]
    assert warns and warns[0].severity == "warning" and "Wizard" in warns[0].problem
    assert not [i for i in validate(s) if i.path.endswith(".callsign")]


# ---------------------------------------------------------------- 4. FM for low band


def test_low_band_is_fm_unless_explicit() -> None:
    assert radio_modulation(41.5) == "FM"
    assert radio_modulation(87.99) == "FM"
    assert radio_modulation(118.0) == "AM"
    assert radio_modulation(251.0) == "AM"
    assert radio_modulation(None) == "AM"
    assert radio_modulation(41.5, "AM") == "AM"
    assert radio_modulation(251.0, "FM") == "FM"

    s = spec()
    p = plan_mission(s, seed=3)
    assert _group(p, "jtac").modulation == "FM"
    spk = build_speakers(s, None, None)
    assert spk["jtac_ctl"].frequency == 41.5 and spk["jtac_ctl"].modulation == 1
    assert spk["magic_ctl"].modulation == 0

    sup = [x.model_dump() for x in s.support]
    sup[2]["modulation"] = "AM"
    s2 = spec(support=sup)
    assert _group(plan_mission(s2, seed=3), "jtac").modulation == "AM"
    assert build_speakers(s2, None, None)["jtac_ctl"].modulation == 0
