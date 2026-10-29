"""Kneeboard map page drawn from plan.json (dms_gen.builder.kneeboard_map, CONTRACTS "Map page")."""

from __future__ import annotations

import datetime as dt
import hashlib
import io
import zipfile
from pathlib import Path

from dms_core.schemas import MissionSpec
from dms_core.schemas.plan import (
    BuildPlan,
    PlanGroup,
    PlanOptions,
    PlanUnit,
    PlanWaypoint,
    PlanZone,
)
from dms_core.schemas.runtime import Intel, RuntimeConfig
from dms_gen.builder import build_from_plan, map_features, render_map_page
from dms_gen.builder.kneeboard import PAGE_H, PAGE_W
from dms_gen.builder.kneeboard_map import NM, ddm
from dms_gen.planner import plan_mission
from PIL import Image

MAP_PNG = "KNEEBOARD/IMAGES/m01-map-kneeboard-map-01.png"


def _red(name: str, x: float, y: float, type_id: str = "Osa 9A33 ln", **kw: object) -> PlanGroup:
    return PlanGroup(
        name=name,
        category="vehicle",
        coalition="red",
        country="Insurgents",
        units=[PlanUnit(name=f"{name}-1", type=type_id, x=x, y=y)],
        **kw,  # type: ignore[arg-type]
    )


def _plan(*extra: PlanGroup, **kw: object) -> BuildPlan:
    return BuildPlan(
        mission_id="m01-map",
        seed=7,
        theater="Syria",
        date=dt.date(2012, 4, 11),
        start_time_sec=6 * 3600,
        blue_countries=["USA"],
        red_countries=["Insurgents"],
        groups=[
            PlanGroup(
                name="Dusty 1",
                category="helicopter",
                coalition="blue",
                country="USA",
                client=True,
                units=[
                    PlanUnit(
                        name="Dusty 1-1", type="AH-64D_BLK_II", x=147687, y=39418, skill="Client"
                    )
                ],
                route=[
                    PlanWaypoint(x=147687, y=39418, action="From Parking Area", airbase="Hatay"),
                    PlanWaypoint(x=140000, y=60000, name="IP"),
                    PlanWaypoint(x=135000, y=82000, name="TGT"),
                    PlanWaypoint(x=147687, y=39418, action="Landing", airbase="Hatay", name="HOME"),
                ],
            ),
            _red("known_sam_1", 138000, 75000),
            *extra,
        ],
        zones=[
            PlanZone(name="no_strike_hospital", kind="circle", x=136000, y=86000, radius_m=1500),
            PlanZone(name="sam_area", kind="circle", x=120000, y=70000, radius_m=3000),
        ],
        **kw,  # type: ignore[arg-type]
    )


HIDDEN = _red("hidden_sam_1", 120000, 70000, hidden=True)
LATE = _red("late_sam_1", 125000, 50000, late_activation=True)


def test_map_png_is_deterministic_and_kneeboard_sized() -> None:
    a = render_map_page(_plan())
    b = render_map_page(_plan())
    assert a is not None and b is not None
    assert hashlib.sha256(a).hexdigest() == hashlib.sha256(b).hexdigest()
    img = Image.open(io.BytesIO(a))
    assert img.format == "PNG" and img.size == (PAGE_W, PAGE_H)
    assert len(img.getcolors(maxcolors=1 << 16) or []) > 4


def test_features_route_airbase_threat_ring_and_no_strike() -> None:
    f = map_features(_plan())
    assert len(f.routes) == 1
    names = [s.name for s in f.routes[0][1]]
    assert names == ["Hatay", "IP", "TGT", "HOME"]
    assert [a[0] for a in f.airbases] == ["Hatay"]
    assert [t.group for t in f.threats] == ["known_sam_1"]
    assert f.threats[0].radius_m >= 3 * NM  # SA-8: a real ring, not a dot
    assert [z.name for z in f.no_strike] == ["no_strike_hospital"]  # sam_area is not drawn


def test_hidden_threats_never_drawn() -> None:
    f = map_features(_plan(HIDDEN, LATE))
    assert [t.group for t in f.threats] == ["known_sam_1"]
    # Hidden / late groups don't even move the extent: the page is byte-identical without them.
    assert render_map_page(_plan(HIDDEN, LATE)) == render_map_page(_plan())


def test_fog_of_war_requires_known_groups() -> None:
    fog = RuntimeConfig(mission_id="m01-map", intel=Intel(fog_of_war=True, known_groups=[]))
    assert map_features(_plan(runtime=fog)).threats == ()
    known = RuntimeConfig(
        mission_id="m01-map", intel=Intel(fog_of_war=True, known_groups=["known_sam_1"])
    )
    assert [t.group for t in map_features(_plan(runtime=known)).threats] == ["known_sam_1"]


def test_no_client_group_no_page() -> None:
    plan = _plan().model_copy(update={"groups": [_red("known_sam_1", 0, 0)]})
    assert render_map_page(plan) is None


def test_ddm_format() -> None:
    assert ddm(36.5, -0.25) == "N36°30.000' W000°15.000'"


def _kneeboards(path: Path) -> dict[str, bytes]:
    with zipfile.ZipFile(path) as z:
        return {n: z.read(n) for n in z.namelist() if n.startswith("KNEEBOARD/")}


def test_map_page_in_built_miz_and_reproducible(tmp_path: Path) -> None:
    mdir = tmp_path / "m"
    mdir.mkdir()
    out = build_from_plan(_plan(HIDDEN), tmp_path / "a.miz", base_dir=mdir)
    kb = _kneeboards(out)
    assert list(kb) == [MAP_PNG]
    img = Image.open(io.BytesIO(kb[MAP_PNG]))
    img.verify()
    assert img.size == (PAGE_W, PAGE_H)
    assert kb[MAP_PNG] == render_map_page(_plan())  # hidden threat left no trace
    out2 = build_from_plan(_plan(HIDDEN), tmp_path / "b.miz", base_dir=mdir)
    assert _kneeboards(out2) == kb


def test_map_page_can_be_turned_off(tmp_path: Path) -> None:
    mdir = tmp_path / "m"
    mdir.mkdir()
    plan = _plan(options=PlanOptions(kneeboard_map=False))
    out = build_from_plan(plan, tmp_path / "off.miz", base_dir=mdir)
    assert _kneeboards(out) == {}


def test_spec_option_defaults_on_and_planner_copies_it() -> None:
    from test_planner import convoy_spec

    assert PlanOptions().kneeboard_map is True
    assert plan_mission(convoy_spec()).options.kneeboard_map is True
    off = convoy_spec(kneeboard={"map": False})
    assert isinstance(off, MissionSpec) and off.kneeboard.map is False
    assert plan_mission(off).options.kneeboard_map is False
