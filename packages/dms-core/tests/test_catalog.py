from __future__ import annotations

from pathlib import Path
from typing import Any

import pytest
import yaml
from dms_core import catalog
from dms_core.catalog import CatalogLookupError

CATALOG_DIR = Path(__file__).resolve().parents[3] / "data" / "catalog"


@pytest.fixture(scope="module")
def cat() -> catalog.Catalog:
    return catalog.load_catalog(CATALOG_DIR)


@pytest.mark.parametrize("name", sorted(p.name for p in CATALOG_DIR.glob("*.yaml")))
def test_yaml_parses(name: str) -> None:
    data = yaml.safe_load((CATALOG_DIR / name).read_text(encoding="utf-8"))
    assert isinstance(data, dict)
    assert data.get("version") == 1


def test_loads_everything(cat: catalog.Catalog) -> None:
    assert len(cat.units) > 100
    assert len(cat.templates) > 50
    assert {"SEAD", "CAS", "CAP", "STRIKE", "CSAR", "CONVOY_ESCORT", "RECON", "TRANSPORT"} <= set(
        cat.mission_types
    )
    assert set(cat.eras) == {"early_cold_war", "late_cold_war", "modern"}


def test_default_root_finds_repo_catalog() -> None:
    assert catalog.load_catalog().root == CATALOG_DIR.resolve()


def test_every_pydcs_id_resolves(cat: catalog.Catalog) -> None:
    pytest.importorskip("dcs")
    import dcs
    import dcs.helicopters
    import dcs.planes
    import dcs.ships
    import dcs.vehicles

    maps: dict[str, Any] = {
        "ground": dcs.vehicles.vehicle_map,
        "plane": dcs.planes.plane_map,
        "helicopter": dcs.helicopters.helicopter_map,
        "ship": dcs.ships.ship_map,
    }
    for u in cat.units.values():
        assert u.pydcs_id == u.id
        assert u.pydcs_id in maps[u.category], u.id
        obj: object = dcs
        for part in u.pydcs_class.split("."):
            obj = getattr(obj, part)
        assert getattr(obj, "id", None) == u.id


def test_template_units_and_references_are_known(cat: catalog.Catalog) -> None:
    for t in cat.templates.values():
        assert t.units, t.id
        for u in t.units:
            assert u.type in cat.units, (t.id, u.type)
        assert t.eras, f"{t.id}: members share no era"
    for p in cat.packages.values():
        for g in p.groups:
            assert g.template in cat.templates, (p.id, g.template)
    for mt in cat.mission_types.values():
        for ref in mt.threat_templates():
            assert ref in cat.templates or ref in cat.packages, (mt.id, ref)
        for enc in mt.dynamic_encounters:
            for ref in enc.pool:
                assert ref in cat.templates, (mt.id, ref)
        for ac in [*mt.typical_aircraft, *mt.loadouts]:
            assert ac in cat.units, (mt.id, ac)


def test_eras_consistent_with_units(cat: catalog.Catalog) -> None:
    for era in cat.eras.values():
        for coal, roles in era.units.items():
            for role, ids in roles.items():
                for uid in ids:
                    u = cat.units[uid]
                    assert era.id in u.eras and coal in u.coalitions and u.role == role


def test_find_units(cat: catalog.Catalog) -> None:
    red_shorad = catalog.find_units(era="modern", coalition="red", role="sam_short")
    ids = {u.id for u in red_shorad}
    assert {"Osa 9A33 ln", "Tor 9A331", "2S6 Tunguska"} <= ids
    assert all(u.category == "ground" for u in red_shorad)
    helos = cat.find_units(category="helicopter", coalition="blue", role="cas")
    assert "AH-64D_BLK_II" in {u.id for u in helos}
    # tag match
    assert "F-16C_50" in {u.id for u in cat.find_units(role="sead")}
    assert not cat.find_units(era="early_cold_war", role="sam_short", coalition="blue")
    with pytest.raises(CatalogLookupError):
        cat.find_units(era="moden")


def test_get_template_and_runtime_shape() -> None:
    t = catalog.get_template("sa8")
    rt = t.to_runtime()
    assert rt == {
        "country": "RUSSIA",
        "category": "ground",
        "skill": "Random",
        "units": [{"type": "Osa 9A33 ln", "dx": 0.0, "dy": 0.0, "heading": 0.0}],
    }
    assert catalog.get_template("zu23_technical").country == "INSURGENTS"
    assert len(catalog.get_template("bmp_section").units) == 2
    sa3 = catalog.get_template("sa3_goa_battery")
    assert "snr s-125 tr" in {u.type for u in sa3.units}
    with pytest.raises(CatalogLookupError) as ei:
        catalog.get_template("bmp_sectoin")
    assert "bmp_section" in ei.value.suggestions


def test_mission_type() -> None:
    sead = catalog.mission_type("sead")
    assert sead.id == "SEAD"
    assert "sa10_grumble_battalion" in sead.threat_templates("heavy")
    assert catalog.mission_type("convoy escort").id == "CONVOY_ESCORT"
    with pytest.raises(CatalogLookupError) as ei:
        catalog.mission_type("STIKE")
    assert "STRIKE" in ei.value.suggestions


def test_suggest() -> None:
    assert catalog.suggest("Tunguska", "unit")[0] == "2S6 Tunguska"
    assert "FA-18C_hornet" in catalog.suggest("F/A-18C_hornet", "unit")
    assert "shilka" in catalog.suggest("shilk", "template")
    assert catalog.suggest("syira", "theater")[0] == "Syria"


def test_airbases_syria() -> None:
    pytest.importorskip("dcs")
    bases = catalog.find_airbases("Syria")
    names = {a.name for a in bases}
    assert {"Ramat David", "Incirlik", "Damascus"} <= names
    rd = next(a for a in bases if a.name == "Ramat David")
    assert 32.5 < rd.lat < 32.8 and 35.0 < rd.lon < 35.3
    assert rd.runways
    near = catalog.find_airbases("syria", near="ramat david", limit=3)
    assert near[0].name == "Ramat David" and near[0].distance_m == 0.0
    assert near[1].distance_m is not None and near[1].distance_m > 0
    by_xy = catalog.find_airbases("Syria", near=(rd.x, rd.y), max_distance_m=50_000)
    assert by_xy[0].name == "Ramat David"
    assert all((a.distance_m or 0) <= 50_000 for a in by_xy)
    assert "Ramat David" in catalog.suggest("Ramat Dvid", "airbase", theater="Syria")
    with pytest.raises(CatalogLookupError):
        catalog.find_airbases("Syrai")


def test_threat_role_aliases(cat: catalog.Catalog) -> None:
    from typing import get_args

    from dms_core.schemas.mission import ThreatRole

    assert set(get_args(ThreatRole)) == set(catalog.THREAT_ROLE_TEMPLATES)
    for role, ids in catalog.THREAT_ROLE_TEMPLATES.items():
        assert all(i in cat.templates for i in ids), (role, ids)
        found = {t.id for t in cat.find_templates(role=role)}
        assert set(ids) <= found
    aaa = {t.id for t in cat.find_templates(role="aaa")}
    assert "zu23_emplacement" in aaa and "sa10_grumble_battalion" not in aaa
    assert {t.id for t in cat.find_templates(role="technicals")} >= {"technical_mg"}
    assert "air_defense" in cat.template_roles() and "manpads" in cat.template_roles()
