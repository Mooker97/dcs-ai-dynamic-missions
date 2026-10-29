"""Helicopter loadout presets: every preset resolves to real pydcs CLSIDs on legal pylons."""

from __future__ import annotations

import pytest
from dcs.weapons_data import Weapons
from dms_core import catalog
from dms_gen.builder.mission import aircraft_type
from dms_gen.builder.payloads import DEFAULT_PRESET, PRESETS, pylon_options, resolve_payload
from dms_gen.planner.loadouts import choose_loadout, payload_for

HELIS = ["Mi-8MT", "UH-1H", "CH-47Fbl1", "Mi-24P", "Ka-50", "Ka-50_3", "SA342M", "OH58D"]


def _pydcs_clsids() -> set[str]:
    return {str(v["clsid"]) for v in vars(Weapons).values() if isinstance(v, dict) and "clsid" in v}


def test_every_player_helicopter_has_presets() -> None:
    players = [
        u.id
        for u in catalog.load_catalog().units.values()
        if u.category == "helicopter" and "player" in u.tags
    ]
    assert players
    missing = [h for h in players if not PRESETS.get(h)]
    assert not missing, f"player helicopters without loadout presets: {missing}"
    assert all(h in DEFAULT_PRESET for h in players)


@pytest.mark.parametrize(
    ("aircraft", "preset"), [(a, p) for a in HELIS for p in sorted(PRESETS[a])]
)
def test_heli_preset_resolves_to_real_clsids(aircraft: str, preset: str) -> None:
    ac = aircraft_type(aircraft)
    lo = resolve_payload(ac, preset)
    assert lo, (aircraft, preset)
    opts = pylon_options(ac)
    known = _pydcs_clsids()
    for pylon, clsid in lo.items():
        assert clsid in {str(w["clsid"]) for w in opts[pylon].values()}
        assert clsid in known, (aircraft, preset, pylon, clsid)


@pytest.mark.parametrize("aircraft", HELIS)
def test_heli_auto_loadout_resolves(aircraft: str) -> None:
    payload, choice = payload_for(aircraft, "auto")
    assert choice.ok and payload is not None and payload.pylons
    assert choice.preset == DEFAULT_PRESET[aircraft]


def test_mi8_transport_and_intents() -> None:
    assert choose_loadout("Mi-8MT", "auto", "TRANSPORT").preset == "transport"
    assert choose_loadout("Mi-8MT", "auto", "CAS").preset == "rockets"
    c = choose_loadout("Mi-8MT", "2,000 kg ammunition, troops and refugees out")
    assert c.preset == "transport" and c.ok
    c = choose_loadout("Mi-8MT", "CSAR: empty cabin, medic aboard, no rocket pods")
    assert c.preset == "transport" and c.ok
    assert choose_loadout("Mi-8MT", "4x B-8 rockets").preset == "rockets"
    assert choose_loadout("Mi-24P", "Ataka ATGMs and rockets").preset == "atgm_rockets"
    assert choose_loadout("SA342M", "HOT missiles").preset == "atgm"
    # The Mi-8MT rocket preset carries only 80 mm pods, never fuel tanks.
    assert "Fuel" not in " ".join(PRESETS["Mi-8MT"]["rockets"].values())
