"""Per-variant builds (ramp/air), SP player + AI wingmen, air-start geometry, test proxy choice,
radio callsigns, neutral countries, support faction country and pinned threat templates."""

from __future__ import annotations

import math
import zipfile
from pathlib import Path
from typing import Any

import pytest
import yaml
from dms_core.luaio import loads
from dms_core.schemas import BeatSheet, MissionSpec, StoryBible
from dms_core.schemas.plan import BuildPlan
from dms_core.variants import pick_test_proxy, plan_variants, variant_miz_name, variant_plan
from dms_gen.builder import build_from_plan
from dms_gen.builder.mission import callsign_names, closest_callsign
from dms_gen.check import check_miz
from dms_gen.planner import (
    has_errors,
    make_test_plan,
    plan_mission,
    validate,
    write_runtime_config,
    write_test_lua,
)
from dms_gen.planner.context import NM

REPO = Path(__file__).resolve().parents[3]
UN = "United Nations Peacekeepers"
GOLDEN_BIBLE = REPO / "evals" / "specs" / "g08-syria-oh58-convoy" / "bible.yaml"


def bible() -> StoryBible:
    data: dict[str, Any] = yaml.safe_load(GOLDEN_BIBLE.read_text(encoding="utf-8"))
    data["factions"] = [
        {
            "id": "rook",
            "name": "Rook",
            "dcs": {"country": "USA", "coalition": "blue", "units": ["F-16C_50"]},
        },
        {
            "id": "partner",
            "name": "Partner force",
            "dcs": {
                "country": "CJTF Blue",
                "coalition": "blue",
                "units": ["Soldier M4", "Hummer", "M-113"],
            },
        },
        {
            "id": "npf",
            "name": "NPF",
            "dcs": {"country": "Insurgents", "coalition": "red", "units": ["tt_ZU-23"]},
        },
        {
            "id": "civs",
            "name": "Civilians",
            "dcs": {
                "country": "UN Peacekeepers",
                "coalition": "neutral",
                "units": ["GAZ-3307", "VAZ Car", "IKARUS Bus"],
            },
        },
    ]
    for ch in data["characters"]:
        ch["faction"] = "partner" if ch["id"] == "convoy_lead" else "rook"
    return StoryBible.model_validate(data)


def viper_spec(**over: Any) -> MissionSpec:
    data: dict[str, Any] = {
        "id": "v01-umbrella",
        "title": "Umbrella",
        "theater": "Syria",
        "era": 2016,
        "date": "2016-11-03",
        "mission_type": "SEAD",
        "blue_countries": ["USA", "Combined Joint Task Forces Blue"],
        "red_countries": ["Insurgents"],
        "areas": [
            {
                "id": "incirlik",
                "where": {"kind": "near_airbase", "airbase": "Incirlik", "radius_nm": 1},
            },
            {"id": "ip_arrow", "where": {"kind": "near_named_place", "place": "Kilis"}},
            {"id": "al_bab", "where": {"kind": "near_named_place", "place": "Al-Bab"}},
            {
                "id": "al_bab_road",
                "where": {
                    "kind": "near_named_place",
                    "place": "Al-Bab",
                    "bearing_deg": 250,
                    "distance_nm": 5,
                },
                "terrain": "road",
            },
        ],
        "player_flights": [
            {
                "callsign": "Python",
                "aircraft": "F-16C_50",
                "count": 2,
                "start_area": "incirlik",
                "start_type": "parking_cold",
                "variant": "ramp",
            },
            {
                "callsign": "Python",
                "aircraft": "F-16C_50",
                "count": 2,
                "start_area": "incirlik",
                "start_type": "air",
                "variant": "air",
                "air_start": {"toward": "ip_arrow"},
            },
        ],
        "objectives": [
            {"id": "sead", "kind": "destroy", "description": "Kill the SAM.", "area": "al_bab"},
            {"id": "rtb", "kind": "land", "description": "Recover.", "area": "incirlik"},
        ],
        "threats": [
            {
                "id": "sam",
                "role": "sam_short",
                "area": "al_bab",
                "strength": "light",
                "faction": "npf",
                "templates": ["sa8"],
            },
            {
                "id": "civilians",
                "role": "civilian",
                "area": "al_bab_road",
                "strength": "light",
                "faction": "civs",
            },
        ],
        "support": [
            {
                "id": "partner_team",
                "role": "friendly_ground",
                "area": "ip_arrow",
                "faction": "partner",
                "composition": "2x Hummer",
            },
        ],
    }
    data.update(over)
    return MissionSpec.model_validate(data)


def dummy_lua(tmp: Path) -> Path:
    p = tmp / "dms.lua"
    p.write_text('DMS = DMS or {}\nenv.info("[DMS] dummy")\n', encoding="utf-8")
    return p


def plan(tmp: Path, spec: MissionSpec | None = None) -> BuildPlan:
    p = plan_mission(spec or viper_spec(), seed=7, bible=bible(), dms_lua=str(dummy_lua(tmp)))
    write_runtime_config(p, tmp)
    return p


def miz_mission(path: Path) -> dict[str, Any]:
    with zipfile.ZipFile(path) as z:
        src = z.read("mission")
    m: dict[str, Any] = loads(src, "mission")
    return m


def flying_groups(m: dict[str, Any]) -> list[dict[str, Any]]:
    out: list[dict[str, Any]] = []
    for coal in m["coalition"].values():
        for c in (coal.get("country") or {}).values():
            for cat in ("plane", "helicopter"):
                out.extend((c.get(cat) or {}).get("group", {}).values())
    return out


# ---------------------------------------------------------------- schema / validate


def test_air_start_only_with_air_start_type() -> None:
    with pytest.raises(ValueError, match="air_start"):
        viper_spec(
            player_flights=[
                {
                    "callsign": "Python",
                    "aircraft": "F-16C_50",
                    "start_area": "incirlik",
                    "air_start": {},
                }
            ]
        )


def test_validate_clean_and_warns_on_second_player_slot() -> None:
    spec = viper_spec()
    issues = validate(spec, bible=bible())
    assert not has_errors(issues), [i.problem for i in issues]
    assert not [i for i in issues if "callsign" in i.path or "neutral" in i.problem]
    flights = [f.model_dump() for f in spec.player_flights]
    for f in flights:
        f["variant"] = None
    clash = validate(viper_spec(player_flights=flights), bible=bible())
    assert any(i.path.endswith("player_flights[1].slot") for i in clash)


def test_callsign_names_and_closest() -> None:
    names = callsign_names("F-16C_50", "USA")
    assert names[:3] == ["Enfield", "Springfield", "Uzi"] and names[7] == "Pontiac"
    assert names.index("Viper") == 8 and "Python" in names
    assert closest_callsign("python", names) == "Python"
    assert closest_callsign("Vipr", names) == "Viper"
    assert callsign_names("Ka-50_3", "Russia") == []
    flights = [f.model_dump() for f in viper_spec().player_flights]
    flights[0]["callsign"] = "Rattlesnake"
    issues = validate(viper_spec(player_flights=flights), bible=bible())
    warn = [i for i in issues if i.path.endswith("player_flights[0].callsign")]
    assert warn and "not available for F-16C_50" in warn[0].problem


def test_pinned_templates_validated() -> None:
    threats = [t.model_dump() for t in viper_spec().threats]
    threats[0]["templates"] = ["zu23_section_nope"]
    issues = validate(viper_spec(threats=threats), bible=bible())
    assert any(i.path.endswith("threats[0].templates") and i.severity == "error" for i in issues)


# ---------------------------------------------------------------- planner


def test_plan_player_groups_slots_variants_callsigns(tmp_path: Path) -> None:
    p = plan(tmp_path)
    clients = [g for g in p.groups if g.client]
    assert [g.variant for g in clients] == ["ramp", "air"]
    for g in clients:
        assert [u.skill for u in g.units] == ["Player", "High"]
        assert g.radio_callsign == "Python 1-1"  # numbered per variant
        assert g.units[0].payload is not None  # auto + SEAD -> sead preset
        assert len(g.units[0].payload.pylons) == 11
    assert plan_variants(p) == ["ramp", "air"]
    client_slot = viper_spec(
        player_flights=[
            {
                "callsign": "Python",
                "aircraft": "F-16C_50",
                "count": 2,
                "start_area": "incirlik",
                "slot": "client",
            }
        ]
    )
    cp = plan(tmp_path, client_slot)
    assert [u.skill for g in cp.groups if g.client for u in g.units] == ["Client", "Client"]


def test_air_start_geometry(tmp_path: Path) -> None:
    p = plan(tmp_path)
    air = next(g for g in p.groups if g.variant == "air")
    start, ip = air.route[0], air.route[1]
    assert start.alt_m == pytest.approx(20000 * 0.3048, abs=0.1)
    assert start.speed_kmh == pytest.approx(420 * 1.852, abs=0.1)
    assert ip.name == "IP" and ip.alt_m == start.alt_m
    assert math.hypot(ip.x - start.x, ip.y - start.y) == pytest.approx(20 * NM, abs=1)
    lead = air.units[0]
    assert (lead.x, lead.y) == (start.x, start.y)
    hdg = math.degrees(math.atan2(ip.y - start.y, ip.x - start.x)) % 360
    assert lead.heading_deg == pytest.approx(hdg, abs=0.05)
    assert lead.alt_m == start.alt_m
    # on the line from the start area (Incirlik) to the IP, short of the IP
    base = next(g for g in p.groups if g.variant == "ramp").route[0]
    d_base_ip = math.hypot(ip.x - base.x, ip.y - base.y)
    d_base_start = math.hypot(start.x - base.x, start.y - base.y)
    assert d_base_start == pytest.approx(d_base_ip - 20 * NM, abs=5)
    wing = air.units[1]
    assert math.hypot(wing.x - lead.x, wing.y - lead.y) > 100


def test_neutral_countries_support_faction_and_pinned_sam(tmp_path: Path) -> None:
    p = plan(tmp_path)
    assert p.neutral_countries == [UN]
    civ = [g for g in p.groups if g.source == "civilians"]
    assert civ and all(g.coalition == "neutral" and g.country == UN for g in civ)
    partner = [g for g in p.groups if g.source == "partner_team"]
    assert partner and partner[0].country == "Combined Joint Task Forces Blue"
    sam = [g for g in p.groups if g.source == "sam"]
    assert sam and all(u.type == "Osa 9A33 ln" for g in sam for u in g.units)


# ---------------------------------------------------------------- variants + build


def test_variant_plan_filters_player_groups(tmp_path: Path) -> None:
    p = plan(tmp_path)
    for v in ("ramp", "air"):
        vp = variant_plan(p, v)
        assert [g.variant for g in vp.groups if g.client] == [v]
        assert len(vp.groups) == len(p.groups) - 1
    assert variant_miz_name("v01", "air") == "v01-air.miz"
    assert variant_miz_name("v01", None) == "v01.miz"
    with pytest.raises(ValueError, match="unknown variant"):
        variant_plan(p, "hot")


def test_each_variant_builds_and_checks(tmp_path: Path) -> None:
    p = plan(tmp_path)
    for v in plan_variants(p):
        vp = variant_plan(p, v)
        out = build_from_plan(vp, tmp_path / variant_miz_name(p.mission_id, v), base_dir=tmp_path)
        rep = check_miz(out)
        assert rep.ok, rep.model_dump_json(indent=1)
        assert rep.stats["player_slots"] == 1
        m = miz_mission(out)
        assert UN in {c["name"] for c in m["coalition"]["neutrals"]["country"].values()}
        players = [
            g
            for g in flying_groups(m)
            if any(u.get("skill") in ("Player", "Client") for u in g["units"].values())
        ]
        assert len(players) == 1
        units = sorted(players[0]["units"].values(), key=lambda u: u["name"])
        assert [u["skill"] for u in units] == ["Player", "High"]
        assert units[0]["callsign"]["name"] == "Python11"
        assert units[0]["callsign"][1] == callsign_names("F-16C_50", "USA").index("Python") + 1
        assert float(units[0]["payload"]["fuel"]) == pytest.approx(3249, abs=1)
        pts = [pt for _k, pt in sorted(players[0]["route"]["points"].items())]
        # start -> IP (ip_arrow) -> TGT (al_bab) -> HOME (land Incirlik)
        assert [pt.get("name", "") for pt in pts[1:]] == ["IP", "TGT", "HOME"]
        assert pts[-1]["type"] == "Land"
        assert [pt["alt"] for pt in pts[1:3]] == pytest.approx([6096, 6096], abs=1)
        if v == "air":
            assert units[0]["alt"] == pytest.approx(6096, abs=1)
            assert units[0]["speed"] == pytest.approx(420 * 1.852 / 3.6, abs=0.5)
            assert len(pts) == 4
            assert math.degrees(units[0]["heading"]) % 360 == pytest.approx(
                vp.groups[[g.variant for g in vp.groups].index("air")].units[0].heading_deg,
                abs=0.1,
            )
        else:
            assert pts[0]["type"] == "TakeOffParking"


# ---------------------------------------------------------------- test mode


def test_test_proxy_prefers_ramp_and_honours_variant(tmp_path: Path) -> None:
    spec = viper_spec()
    p = plan(tmp_path, spec)
    beats = BeatSheet.model_validate([])
    assert pick_test_proxy(p).variant == "ramp"
    assert pick_test_proxy(p, "air").variant == "air"
    tb = make_test_plan(p, spec, beats)
    assert tb.proxy == "Proxy Python 1"
    assert not [g for g in tb.plan.groups if g.client]
    tb_air = make_test_plan(p, spec, beats, variant="air")
    assert tb_air.proxy == "Proxy Python 2"
    # the air-start proxy variant also builds
    tdir = tmp_path / "test"
    lua = write_test_lua(tb_air, tdir)
    for r in tb_air.plan.resources:
        if Path(r.path).name == lua.name:
            r.source = str(lua)
    out = build_from_plan(tb_air.plan, tdir / "air-test.miz", base_dir=tmp_path)
    rep = check_miz(out)
    assert rep.ok, rep.model_dump_json(indent=1)
