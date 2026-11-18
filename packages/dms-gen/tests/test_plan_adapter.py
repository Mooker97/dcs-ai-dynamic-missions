from __future__ import annotations

import datetime as dt
from pathlib import Path

import pytest
from dms_gen.builder import build_from_plan, inspect

plan_mod = pytest.importorskip("dms_core.schemas.plan")
runtime_mod = pytest.importorskip("dms_core.schemas.runtime")


def test_build_from_plan(tmp_path: Path) -> None:
    (tmp_path / "dms.lua").write_text('env.info("dms")\n', encoding="utf-8")
    P = plan_mod
    plan = P.BuildPlan(
        mission_id="m01-test",
        seed=7,
        theater="Syria",
        date=dt.date(2004, 6, 1),
        start_time_sec=6 * 3600,
        blue_countries=["USA"],
        red_countries=["Insurgents"],
        groups=[
            P.PlanGroup(
                name="Dustoff 1",
                category="helicopter",
                coalition="blue",
                country="USA",
                client=True,
                units=[
                    P.PlanUnit(name="Dustoff 1-1", type="AH-64D_BLK_II", x=0, y=0, skill="Client"),
                ],
                route=[P.PlanWaypoint(x=0, y=0, action="From Parking Area", airbase="Ramat David")],
            ),
            P.PlanGroup(
                name="Red 1",
                category="vehicle",
                coalition="red",
                country="Insurgents",
                hidden=True,
                units=[
                    P.PlanUnit(name="Red 1-1", type="BMP-2", x=-262000, y=-60000),
                    P.PlanUnit(name="Red 1-2", type="BMP-2", x=-262030, y=-60030),
                ],
                route=[P.PlanWaypoint(x=-263000, y=-58000, speed_kmh=30, action="On Road")],
            ),
        ],
        zones=[
            P.PlanZone(name="Z1", kind="circle", x=-262000, y=-60000, radius_m=1000),
            P.PlanZone(
                name="Q1", kind="polygon", points=[(0, 0), (0, 1000), (1000, 1000), (1000, 0)]
            ),
        ],
        resources=[P.PlanResource(path="l10n/DEFAULT/dms.lua", source="dms.lua", kind="script")],
        runtime=runtime_mod.RuntimeConfig(seed=7, mission_id="m01-test"),
    )
    s = inspect(build_from_plan(plan, tmp_path / "p.miz", base_dir=tmp_path))
    assert [p["unit"] for p in s.player_slots] == ["Dustoff 1-1"]
    red = s.groups["red"][0]
    assert red.hidden and [u["name"] for u in red.units] == ["Red 1-1", "Red 1-2"]
    start = next(t for t in s.triggers if t["comment"] == "DMS: load scripts")
    files = [s.resources[a["file"]] for a in start["actions"]]
    assert files == ["dms_config.lua", "dms.lua"]  # contract: config before dms.lua
    assert {z["name"] for z in s.zones} == {"Z1", "Q1"}
