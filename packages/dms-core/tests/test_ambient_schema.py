"""DMS_CONFIG.ambient models (RuntimeConfig.ambient) and MissionSpec.ambient."""

from __future__ import annotations

from typing import Any

import pytest
from dms_core.schemas import (
    Ambient,
    AmbientAvoid,
    AmbientLayer,
    AmbientLayers,
    AmbientSite,
    AmbientSpec,
    RuntimeConfig,
)
from dms_core.schemas.runtime import XY
from dms_core.schemas.runtime import TestCheck as Check
from pydantic import ValidationError


def _site(**kw: Any) -> AmbientSite:
    base: dict[str, Any] = {"id": "hatay", "airbase": "Hatay", "country": "USA"}
    base.update(kw)
    return AmbientSite(**base)


def _ambient() -> Ambient:
    return Ambient(
        sites=[
            _site(
                point=XY(x=147687.5, y=39418.7),
                avoid=[AmbientAvoid(x=1, y=2)],
                layers=AmbientLayers(
                    departures=AmbientLayer(
                        types=["C-130"],
                        category="airplane",
                        interval_sec=(240, 480),
                        distance_m=40000,
                        alt_m=1500,
                        speed=120,
                    ),
                    ground=AmbientLayer(count=3, types=["M978 HEMTT Tanker"], radius_m=500),
                    helo=AmbientLayer(types=["UH-60A"], templates=["helo_tpl"], radius_m=3000),
                    statics=AmbientLayer(count=2, types=["Hummer"], category="Unarmed"),
                ),
            )
        ]
    )


def test_defaults_match_contract() -> None:
    a = Ambient()
    assert (a.enabled, a.check_sec, a.grace_sec, a.stagger_sec) == (True, 5, 30, 3)
    assert (a.departure_delay_sec, a.max_groups, a.max_units, a.sites) == (600, 12, 24, [])
    s = _site()
    assert (s.coalition, s.active_radius_m, s.despawn_radius_m) == (2, 8000, 12000)
    assert (s.max_groups, s.max_units, s.avoid) == (8, 16, [])
    assert s.layers == AmbientLayers()
    assert AmbientLayer().count == 1 and AmbientLayer().types == []
    assert AmbientAvoid(x=0, y=0).radius_m == 60
    assert RuntimeConfig(mission_id="m").ambient is None


def test_site_validators() -> None:
    with pytest.raises(ValidationError, match="despawn_radius_m"):
        _site(active_radius_m=8000, despawn_radius_m=8000)
    with pytest.raises(ValidationError, match="airbase or a point"):
        AmbientSite(id="x", country="USA")
    assert _site(airbase=None, point=XY(x=0, y=0)).airbase is None
    with pytest.raises(ValidationError):
        AmbientLayer(count=-1)
    with pytest.raises(ValidationError):
        _site(coalition=0)
    with pytest.raises(ValidationError, match="duplicate ambient site"):
        Ambient(sites=[_site(), _site()])
    with pytest.raises(ValidationError):
        AmbientLayer(bogus=1)  # type: ignore[call-arg]


def test_lua_table_camel_case_and_round_trip() -> None:
    rt = RuntimeConfig(mission_id="m01", ambient=_ambient())
    t = rt.to_lua_table()["ambient"]
    assert t["checkSec"] == 5 and t["departureDelaySec"] == 600 and t["maxGroups"] == 12
    site = t["sites"][0]
    assert site["activeRadiusM"] == 8000 and site["despawnRadiusM"] == 12000
    assert site["avoid"] == [{"x": 1, "y": 2, "radiusM": 60}]
    dep = site["layers"]["departures"]
    assert dep["intervalSec"] == [240, 480] and dep["distanceM"] == 40000 and dep["altM"] == 1500
    assert "arrivals" not in site["layers"]  # unset layers are dropped
    assert RuntimeConfig.from_lua_table(rt.to_lua_table()) == rt
    luaio = pytest.importorskip("dms_core.luaio")
    back = luaio.loads(rt.to_lua_source(), "DMS_CONFIG", arrays=True)
    assert RuntimeConfig.from_lua_table(back) == rt


def test_ambient_cycle_check_kind() -> None:
    c = Check(kind="ambient_cycle", site="hatay", deadline_sec=100)
    assert c.site == "hatay"
    assert Check(kind="ambient_cycle").site is None


def test_mission_spec_ambient() -> None:
    a = AmbientSpec()
    assert a.enabled is True and a.density == "low"
    with pytest.raises(ValidationError):
        AmbientSpec(density="extreme")  # type: ignore[arg-type]
