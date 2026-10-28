"""F-16C Block 50 presets, mission-type loadout selection and full internal fuel."""

from __future__ import annotations

import pytest
from dcs.planes import F_16C_50
from dms_gen.builder import MissionBuilder, pylon_options, resolve_payload
from dms_gen.builder.payloads import PRESETS, is_fuel_tank
from dms_gen.planner.loadouts import choose_loadout, payload_for

F16 = "F-16C_50"
HARM = "AGM_88C_HARM___High_Speed_Anti_Radiation_Missile_"
GBU12 = "GBU_12___500lb_Laser_Guided_Bomb"
AIM9X = "AIM_9X_Sidewinder_IR_AAM"
AIM120C = "AIM_120C_AMRAAM___Active_Radar_AAM"
TANK = "Fuel_tank_370_gal"
M01_INTENT = (
    "SEAD/DEAD, F-16C Block 50: 2x AGM-88C HARM, 2x GBU-12, 2x AIM-120C, 2x AIM-9X, "
    "ALQ-184, HTS, LITENING"
)


def _clsid(pylon: int, attr: str) -> str:
    return str(pylon_options(F_16C_50)[pylon][attr]["clsid"])


@pytest.mark.parametrize("name", sorted(PRESETS[F16]))
def test_every_f16_preset_resolves(name: str) -> None:
    lo = resolve_payload(F_16C_50, name)
    assert lo is not None
    assert lo == {p: _clsid(p, w) for p, w in PRESETS[F16][name].items()}
    # Self-defence and pods on every preset.
    for p in (1, 9):
        assert lo[p] == _clsid(p, AIM9X)
    for p in (2, 8):
        assert lo[p] == _clsid(p, AIM120C)
    assert lo[5] == _clsid(5, "ALQ_184")
    assert lo[11] == _clsid(11, "AN_AAQ_28_LITENING___Targeting_Pod_")


def test_sead_preset_pylons() -> None:
    lo = resolve_payload(F_16C_50, "sead")
    assert lo is not None
    assert lo[3] == lo[7] == _clsid(3, HARM)
    assert lo[4] == lo[6] == _clsid(4, GBU12)
    assert lo[10] == _clsid(10, "AN_ASQ_213_HTS___HARM_Targeting_System")
    assert not any(is_fuel_tank(c) for c in lo.values())


def test_strike_and_cas_presets_carry_tanks_inboard() -> None:
    for name in ("lgb_strike", "cas"):
        lo = resolve_payload(F_16C_50, name)
        assert lo is not None
        assert lo[4] == lo[6] == _clsid(4, TANK)
        assert is_fuel_tank(lo[4])
        assert 10 not in lo
    strike = resolve_payload(F_16C_50, "lgb_strike")
    assert strike is not None
    assert strike[3] == _clsid(3, "TER_9_A___2_x_GBU_12___500lb_Laser_Guided_Bomb")
    assert strike[7] == _clsid(7, "TER_9_A___2_x_GBU_12___500lb_Laser_Guided_Bomb_")
    cas = resolve_payload(F_16C_50, "cas")
    assert cas is not None
    assert cas[3] == _clsid(3, "TER_9_A___2_x_GBU_12___500lb_Laser_Guided_Bomb")
    assert cas[7] == _clsid(7, "LAU_88___2_x_AGM_65D___Maverick_D__IIR_ASM__")


@pytest.mark.parametrize(
    ("mission_type", "preset"),
    [
        ("SEAD", "sead"),
        ("DEAD", "sead"),
        ("STRIKE", "lgb_strike"),
        ("CAS", "cas"),
        ("CAP", None),
        (None, None),
    ],
)
def test_auto_picks_by_mission_type(mission_type: str | None, preset: str | None) -> None:
    choice = choose_loadout(F16, "auto", mission_type)
    assert choice.preset == preset
    assert choice.note == "auto"


@pytest.mark.parametrize(
    ("intent", "preset"),
    [
        (M01_INTENT, "sead"),
        ("2x HARM and pods", "sead"),
        ("AGM-88 hunter-killer", "sead"),
        ("CAS with Mavericks", "cas"),
        ("AGM-65D x2", "cas"),
        ("4x GBU-12", "lgb_strike"),
        ("laser guided strike", "lgb_strike"),
    ],
)
def test_free_text_intents(intent: str, preset: str) -> None:
    choice = choose_loadout(F16, intent, "CAP")
    assert choice.preset == preset
    assert choice.ok
    assert choice.note == f"interpreted: {preset}"


def test_exact_preset_name() -> None:
    assert choose_loadout(F16, "cas", "SEAD").note == "exact"


def test_unrecognised_intent_falls_back_to_mission_type_preset() -> None:
    choice = choose_loadout(F16, "whatever the crew chief hung", "DEAD")
    assert choice.preset == "sead"
    assert not choice.ok
    assert choice.note.startswith("unresolved:") and "using preset sead" in choice.note


def test_payload_for_f16_has_no_fuel_override() -> None:
    payload, choice = payload_for(F16, "auto", "SEAD")
    assert choice.preset == "sead"
    assert payload is not None
    assert payload.fuel_kg is None  # None = full internal fuel
    assert {p.num for p in payload.pylons} == set(range(1, 12))


def test_apache_unchanged() -> None:
    apache = "AH-64D_BLK_II"
    assert choose_loadout(apache, "auto").preset == "hellfire_rockets"
    assert choose_loadout(apache, "auto", "CAS").preset == "hellfire_rockets"
    assert choose_loadout(apache, "Hellfires and rockets", "CAS").preset == "hellfire_rockets"
    assert choose_loadout(apache, "16 hellfire").preset == "hellfire_heavy"
    eight = choose_loadout(apache, "8x Hellfire")
    assert eight.preset is None and eight.weapons is not None
    unknown = choose_loadout(apache, "gun only", "SEAD")
    assert unknown.preset == "hellfire_rockets" and not unknown.ok


def test_built_f16_has_full_internal_fuel() -> None:
    b = MissionBuilder("Syria", seed=7)
    group = b.add_player_flight(
        "blue",
        "USA",
        F16,
        "Incirlik",
        name="Viper 1",
        start="cold",
        count=2,
        payload="sead",
    )
    for u in group.units:
        assert u.fuel == F_16C_50.fuel_max
