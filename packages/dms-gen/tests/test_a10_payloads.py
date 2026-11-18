"""A-10C II CAS preset: resolves against pydcs pylons and is the default for loadout: auto."""

from __future__ import annotations

from dcs.planes import A_10C_2
from dms_gen.builder import pylon_options, resolve_payload
from dms_gen.builder.payloads import PRESETS
from dms_gen.planner.loadouts import choose_loadout

A10 = "A-10C_2"


def test_a10_cas_preset_resolves() -> None:
    lo = resolve_payload(A_10C_2, "cas")
    assert lo is not None
    opts = pylon_options(A_10C_2)
    assert lo == {p: str(opts[p][w]["clsid"]) for p, w in PRESETS[A10]["cas"].items()}
    assert 6 not in lo  # centreline stays empty when 5/7 are loaded
    assert lo[10] == str(opts[10]["AN_AAQ_28_LITENING___Targeting_Pod_"]["clsid"])


def test_a10_auto_loadout_is_never_clean() -> None:
    for mission_type in ("CAS", "STRIKE", None):
        choice = choose_loadout(A10, "auto", mission_type)
        assert choice.preset == "cas"
        assert choice.ok
