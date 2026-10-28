"""Ambient base traffic: planner generation, test-mode check and `dms check` rules."""

from __future__ import annotations

import datetime as dt
from pathlib import Path
from typing import Any

import pytest
import yaml
from dms_core import catalog as cat
from dms_core.schemas import BeatSheet, MissionSpec, StoryBible, VoiceLineSet
from dms_core.schemas.plan import BuildPlan, PlanGroup, PlanResource, PlanUnit, PlanWaypoint
from dms_core.schemas.runtime import (
    Ambient,
    AmbientLayer,
    AmbientLayers,
    AmbientSite,
    RuntimeConfig,
    Template,
    TemplateUnit,
)
from dms_gen.builder import build_from_plan
from dms_gen.check import CheckReport, check_miz
from dms_gen.planner import make_test_plan, plan_mission
from dms_gen.planner.ambient import candidate_types, site_id
from dms_gen.planner.context import find_airbase
from dms_gen.planner.testmode import default_checks

REPO = Path(__file__).resolve().parents[3]
M01 = REPO / "campaigns" / "dustoff-valley" / "missions" / "m01-first-light"
BIBLE = REPO / "campaigns" / "dustoff-valley" / "bible.yaml"


def _yaml(p: Path) -> Any:
    return yaml.safe_load(p.read_text(encoding="utf-8"))


@pytest.fixture(scope="module")
def m01() -> tuple[MissionSpec, BeatSheet, VoiceLineSet, StoryBible]:
    return (
        MissionSpec.model_validate(_yaml(M01 / "mission-spec.yaml")),
        BeatSheet.model_validate(_yaml(M01 / "beats.yaml")),
        VoiceLineSet.model_validate(_yaml(M01 / "lines.yaml")),
        StoryBible.model_validate(_yaml(BIBLE)),
    )


def _plan(m01: Any, density: str | None = None, enabled: bool = True, seed: int = 7) -> BuildPlan:
    spec, beats, lines, bible = m01
    spec = spec.model_copy(deep=True)
    if density is not None:
        spec.ambient.density = density
    spec.ambient.enabled = enabled
    return plan_mission(spec, beats, lines, seed=seed, bible=bible)


def _layer_counts(a: Ambient) -> dict[str, int]:
    layers = a.sites[0].layers
    return {
        k: (getattr(layers, k).count if getattr(layers, k) is not None else 0)
        for k in AmbientLayers.model_fields
    }


# ------------------------------------------------------------------------------ planner


def test_m01_site_at_hatay(m01: Any) -> None:
    plan = _plan(m01)
    assert plan.runtime is not None and plan.runtime.ambient is not None
    a = plan.runtime.ambient
    assert len(a.sites) == 1
    s = a.sites[0]
    ab = find_airbase("Syria", "Hatay")
    assert ab is not None and s.point is not None
    assert (s.id, s.airbase, s.coalition, s.country) == ("hatay", "Hatay", 2, "AUSTRALIA")
    assert (s.point.x, s.point.y) == (round(ab.x, 1), round(ab.y, 1))
    client = next(g for g in plan.groups if g.client)
    assert [(v.x, v.y) for v in s.avoid] == [(u.x, u.y) for u in client.units]
    assert all(v.radius_m == 60 for v in s.avoid)
    assert s.despawn_radius_m > s.active_radius_m


def test_m01_types_are_catalog_and_era_appropriate(m01: Any) -> None:
    a = _plan(m01, "high").runtime.ambient  # type: ignore[union-attr]
    assert a is not None
    units = cat.load_catalog().units
    layers = a.sites[0].layers
    assert layers.departures is not None and layers.departures.category == "airplane"
    assert layers.helo is not None and layers.helo.category == "helicopter"
    assert layers.statics is not None and layers.statics.category == "Unarmed"
    for name in AmbientLayers.model_fields:
        layer = getattr(layers, name)
        assert layer is not None and layer.types, name
        for t in layer.types:
            u = units[t]
            assert "modern" in u.eras and "blue" in u.coalitions, t
            assert u.threat in ("none", "low"), t
    for t in layers.ground.types + layers.statics.types:  # type: ignore[union-attr]
        assert units[t].pydcs_class.startswith("vehicles.Unarmed."), t
    for t in layers.departures.types:
        assert units[t].category == "plane" and units[t].role == "transport"


def test_density_scaling_and_off(m01: Any) -> None:
    low = _plan(m01).runtime.ambient  # type: ignore[union-attr]
    med = _plan(m01, "medium").runtime.ambient  # type: ignore[union-attr]
    high = _plan(m01, "high").runtime.ambient  # type: ignore[union-attr]
    assert low is not None and med is not None and high is not None
    assert _layer_counts(low) == {
        "departures": 1,
        "arrivals": 1,
        "ground": 2,
        "helo": 0,
        "statics": 2,
    }
    assert _layer_counts(med) == {
        "departures": 1,
        "arrivals": 1,
        "ground": 3,
        "helo": 1,
        "statics": 3,
    }
    assert _layer_counts(high) == {
        "departures": 2,
        "arrivals": 2,
        "ground": 4,
        "helo": 1,
        "statics": 5,
    }
    assert low.sites[0].max_groups < med.sites[0].max_groups < high.sites[0].max_groups
    assert low.max_units < med.max_units < high.max_units
    assert _plan(m01, "off").runtime.ambient is None  # type: ignore[union-attr]
    assert _plan(m01, enabled=False).runtime.ambient is None  # type: ignore[union-attr]


def test_deterministic_and_rest_of_plan_unchanged(m01: Any) -> None:
    a, b = _plan(m01, "high", seed=11), _plan(m01, "high", seed=11)
    assert a.model_dump_json() == b.model_dump_json()
    off = _plan(m01, "off", seed=11)
    assert off.model_dump_json(exclude={"runtime": {"ambient"}}) == a.model_dump_json(
        exclude={"runtime": {"ambient"}}
    )


def test_air_start_has_no_site(m01: Any) -> None:
    spec, beats, lines, bible = m01
    spec = spec.model_copy(deep=True)
    for f in spec.player_flights:
        f.start_type = "air"
    plan = plan_mission(spec, beats, lines, seed=7, bible=bible)
    assert plan.runtime is not None and plan.runtime.ambient is None


def test_candidate_types_and_site_id() -> None:
    assert candidate_types("departures", "modern", "red", "RUSSIA") == ["An-26B"]
    assert candidate_types("helo", "early_cold_war", "blue", "USA") == ["UH-1H"]
    assert "Land_Rover_101_FC" not in candidate_types("ground", "modern", "blue", "USA")
    assert candidate_types("departures", "modern", "neutral", "X") == []
    assert site_id("Rafic Hariri Beirut") == "rafic_hariri_beirut"
    assert site_id("Al-Dumayr") == "al_dumayr"


# ------------------------------------------------------------------------------ test mode


def test_testmode_adds_ambient_cycle(m01: Any) -> None:
    spec, beats, _lines, _bible = m01
    tb = make_test_plan(_plan(m01), spec, beats, minutes=40)
    assert '{ kind = "ambient_cycle", name = "ambient_cycle", deadlineSec = 2370 }' in tb.lua
    tb_off = make_test_plan(_plan(m01, "off"), spec, beats, minutes=40)
    assert "ambient_cycle" not in tb_off.lua


def test_default_checks_backward_compatible() -> None:
    kinds = [c["kind"] for c in default_checks(10, [], [])]
    assert "ambient_cycle" not in kinds
    with_ambient = default_checks(10, [], [], ambient=True)
    cyc = [c for c in with_ambient if c["kind"] == "ambient_cycle"]
    assert cyc == [{"kind": "ambient_cycle", "name": "ambient_cycle", "deadlineSec": 570}]


# ------------------------------------------------------------------------------ dms check


def _check(tmp: Path, rt: RuntimeConfig, name: str) -> CheckReport:
    (tmp / "dms_config.lua").write_text(rt.to_lua_source(), encoding="utf-8")
    (tmp / "dms.lua").write_text("x = 1", encoding="utf-8")
    plan = BuildPlan(
        mission_id="a01",
        seed=1,
        theater="Syria",
        date=dt.date(2012, 4, 1),
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
                units=[PlanUnit(name="Dusty 1-1", type="AH-64D_BLK_II", x=0, y=0, skill="Client")],
                route=[PlanWaypoint(x=0, y=0, action="From Parking Area", airbase="Hatay")],
            )
        ],
        resources=[
            PlanResource(
                path="l10n/DEFAULT/dms_config.lua", source="dms_config.lua", kind="script"
            ),
            PlanResource(path="l10n/DEFAULT/dms.lua", source="dms.lua", kind="script"),
        ],
    )
    return check_miz(build_from_plan(plan, tmp / name, base_dir=tmp))


def _rt(ground_types: list[str], helo_templates: list[str] | None) -> RuntimeConfig:
    return RuntimeConfig(
        mission_id="a01",
        templates={
            "uh60": Template(
                country="USA", category="helicopter", units=[TemplateUnit(type="UH-60A")]
            )
        },
        ambient=Ambient(
            sites=[
                AmbientSite(
                    id="hatay",
                    airbase="Hatay",
                    country="USA",
                    layers=AmbientLayers(
                        ground=AmbientLayer(types=ground_types),
                        helo=AmbientLayer(templates=helo_templates),
                    ),
                )
            ]
        ),
    )


def test_check_ambient_ok(tmp_path: Path) -> None:
    rep = _check(tmp_path, _rt(["M978 HEMTT Tanker", "Hummer"], ["uh60"]), "ok.miz")
    codes = {i.code for i in rep.issues}
    assert not codes & {"ambient_bad_type", "ambient_bad_template"}, rep.issues
    assert rep.stats.get("ambient_sites") == 1


def test_check_ambient_bad_type_and_template(tmp_path: Path) -> None:
    rep = _check(tmp_path, _rt(["Hummer", "Flying Bathtub"], ["uh60", "nope"]), "bad.miz")
    bad = [i for i in rep.issues if i.code in ("ambient_bad_type", "ambient_bad_template")]
    assert {(i.code, i.severity) for i in bad} == {
        ("ambient_bad_type", "error"),
        ("ambient_bad_template", "error"),
    }
    assert any("Flying Bathtub" in i.message for i in bad)
    assert any("'nope'" in i.message for i in bad)
    assert all(i.where and i.where.startswith("ambient.sites.hatay.layers.") for i in bad)
    assert not rep.ok


def test_m01_build_checks_clean(m01: Any, tmp_path: Path) -> None:
    from dms_gen.planner import write_runtime_config

    plan = _plan(m01, "high")
    (tmp_path / "dms.lua").write_text("x = 1", encoding="utf-8")
    plan.resources = [
        r.model_copy(update={"source": "dms.lua"}) if r.path.endswith("/dms.lua") else r
        for r in plan.resources
    ]
    write_runtime_config(plan, tmp_path)
    rep = check_miz(build_from_plan(plan, tmp_path / "m01.miz", base_dir=tmp_path))
    codes = {i.code for i in rep.issues}
    assert not codes & {"ambient_bad_type", "ambient_bad_template", "config_schema"}, rep.issues
    assert rep.stats.get("ambient_sites") == 1
