"""Explicit aircraft loadouts built from pydcs pylon data.

pydcs ships every aircraft's legal pylon/weapon combinations as nested ``PylonN`` classes on
the aircraft type, e.g. ``AH_64D_BLK_II.Pylon1.M299___4_x_AGM_114K_Hellfire == (1, {...})``.
This module reads those classes, so a loadout can be written as pylon -> weapon attribute name
or pylon -> CLSID and validated against what the airframe can carry.

Named presets in ``PRESETS`` are deterministic and do not depend on a DCS installation. If
``configure_dcs_environment(install_dir=...)`` was used, the DCS payload files are also
searched by name as a fallback.
"""

# mypy: disallow-untyped-calls=False

from __future__ import annotations

from collections.abc import Mapping
from typing import Any

from dcs.unittype import FlyingType

#: A resolved loadout: pylon number -> CLSID.
Loadout = dict[int, str]

#: Built-in named presets: aircraft id -> preset name -> pylon -> pydcs weapon attribute name.
PRESETS: dict[str, dict[str, dict[int, str]]] = {
    "AH-64D_BLK_II": {
        # 8x Hellfire outboard, 38x M151 HE rockets inboard. No external fuel.
        "hellfire_rockets": {
            1: "M299___4_x_AGM_114K_Hellfire",
            2: "M261___19_x_UnGd_Rkts__70_mm_Hydra_70_M151_HE__M433_RC_Fuze",
            3: "M261___19_x_UnGd_Rkts__70_mm_Hydra_70_M151_HE__M433_RC_Fuze",
            4: "M299___4_x_AGM_114K_Hellfire",
        },
        # 16x Hellfire (mix of K and L).
        "hellfire_heavy": {
            1: "M299___2_x_AGM_114K__2_x_AGM_114L_Hellfire",
            2: "M299___4_x_AGM_114K_Hellfire",
            3: "M299___4_x_AGM_114K_Hellfire",
            4: "M299___2_x_AGM_114K__2_x_AGM_114L_Hellfire",
        },
        # 76x rockets.
        "rockets": {
            1: "M261___19_x_UnGd_Rkts__70_mm_Hydra_70_M151_HE__M433_RC_Fuze",
            2: "M261___19_x_UnGd_Rkts__70_mm_Hydra_70_M151_HE__M433_RC_Fuze",
            3: "M261___19_x_UnGd_Rkts__70_mm_Hydra_70_M151_HE__M433_RC_Fuze",
            4: "M261___19_x_UnGd_Rkts__70_mm_Hydra_70_M151_HE__M433_RC_Fuze",
        },
    },
    # F-16C Block 50. Stations: 1/9 wingtips, 2/8 and 3/7 wing, 4/6 inboard wet,
    # 5 centreline, 10 left chin (HTS), 11 right chin (targeting pod).
    "F-16C_50": {
        # SEAD/DEAD: 2x HARM on 3/7, 2x GBU-12 on 4/6, HTS + LITENING, ALQ-184 on the
        # centreline, 2x AIM-120C + 2x AIM-9X for self-defence. No external tanks.
        "sead": {
            1: "AIM_9X_Sidewinder_IR_AAM",
            2: "AIM_120C_AMRAAM___Active_Radar_AAM",
            3: "AGM_88C_HARM___High_Speed_Anti_Radiation_Missile_",
            4: "GBU_12___500lb_Laser_Guided_Bomb",
            5: "ALQ_184",
            6: "GBU_12___500lb_Laser_Guided_Bomb",
            7: "AGM_88C_HARM___High_Speed_Anti_Radiation_Missile_",
            8: "AIM_120C_AMRAAM___Active_Radar_AAM",
            9: "AIM_9X_Sidewinder_IR_AAM",
            10: "AN_ASQ_213_HTS___HARM_Targeting_System",
            11: "AN_AAQ_28_LITENING___Targeting_Pod_",
        },
        # Precision strike: 4x GBU-12 on TER-9/A racks (3/7), 2x 370 gal tanks (4/6),
        # ALQ-184 centreline, LITENING, 2x AIM-120C + 2x AIM-9X.
        "lgb_strike": {
            1: "AIM_9X_Sidewinder_IR_AAM",
            2: "AIM_120C_AMRAAM___Active_Radar_AAM",
            3: "TER_9_A___2_x_GBU_12___500lb_Laser_Guided_Bomb",
            4: "Fuel_tank_370_gal",
            5: "ALQ_184",
            6: "Fuel_tank_370_gal",
            7: "TER_9_A___2_x_GBU_12___500lb_Laser_Guided_Bomb_",  # right-hand rack name
            8: "AIM_120C_AMRAAM___Active_Radar_AAM",
            9: "AIM_9X_Sidewinder_IR_AAM",
            11: "AN_AAQ_28_LITENING___Targeting_Pod_",
        },
        # CAS: 2x 370 gal tanks (4/6) for loiter, ALQ-184 centreline, LITENING.
        # Only 3/7 carry A/G stores alongside tanks, so: 3 = TER-9/A 2x GBU-12,
        # 7 = LAU-88 2x AGM-65D (IIR, usable at night). 2x AIM-120C + 2x AIM-9X.
        "cas": {
            1: "AIM_9X_Sidewinder_IR_AAM",
            2: "AIM_120C_AMRAAM___Active_Radar_AAM",
            3: "TER_9_A___2_x_GBU_12___500lb_Laser_Guided_Bomb",
            4: "Fuel_tank_370_gal",
            5: "ALQ_184",
            6: "Fuel_tank_370_gal",
            7: "LAU_88___2_x_AGM_65D___Maverick_D__IIR_ASM__",  # right-hand rack name
            8: "AIM_120C_AMRAAM___Active_Radar_AAM",
            9: "AIM_9X_Sidewinder_IR_AAM",
            11: "AN_AAQ_28_LITENING___Targeting_Pod_",
        },
    },
}

#: Aircraft that must never get a silent default loadout (pydcs/DCS default is fuel tanks).
DEFAULT_PRESET: dict[str, str] = {"AH-64D_BLK_II": "hellfire_rockets"}


def pylon_options(aircraft: type[FlyingType]) -> dict[int, dict[str, dict[str, Any]]]:
    """Return pylon -> weapon attribute name -> weapon dict (``clsid``, ``name``, ``weight``)."""
    out: dict[int, dict[str, dict[str, Any]]] = {}
    for attr in dir(aircraft):
        if not attr.startswith("Pylon"):
            continue
        pylon_cls = getattr(aircraft, attr)
        if not isinstance(pylon_cls, type):
            continue
        for wname, val in vars(pylon_cls).items():
            if isinstance(val, tuple) and len(val) == 2 and isinstance(val[1], dict):
                out.setdefault(int(val[0]), {})[wname] = val[1]
    return out


def resolve_weapon(aircraft: type[FlyingType], pylon: int, weapon: str) -> str:
    """Resolve a weapon attribute name or CLSID to a CLSID valid for ``pylon``."""
    options = pylon_options(aircraft).get(pylon)
    if options is None:
        raise ValueError(f"{aircraft.id} has no pylon {pylon}")
    if weapon in options:
        return str(options[weapon]["clsid"])
    for w in options.values():
        if w["clsid"] == weapon:
            return weapon
    raise ValueError(f"{weapon!r} is not allowed on {aircraft.id} pylon {pylon}")


def resolve_payload(
    aircraft: type[FlyingType], payload: Mapping[int, str] | str | None
) -> Loadout | None:
    """Resolve a payload spec to pylon -> CLSID.

    ``payload`` is a mapping pylon -> (attribute name or CLSID), a preset name from
    ``PRESETS``, a DCS payload name (only if DCS payload dirs are configured), or ``None``
    (use ``DEFAULT_PRESET`` if the aircraft has one, else leave pylons empty).
    """
    if payload is None:
        preset = DEFAULT_PRESET.get(aircraft.id)
        if preset is None:
            return None
        payload = preset
    if isinstance(payload, str):
        preset_map = PRESETS.get(aircraft.id, {}).get(payload)
        if preset_map is not None:
            return {p: resolve_weapon(aircraft, p, w) for p, w in preset_map.items()}
        dcs_payload = aircraft.loadout_by_name(payload)
        if dcs_payload:
            return {int(num): str(data["clsid"]) for num, data in dcs_payload}
        known = sorted(PRESETS.get(aircraft.id, {}))
        raise ValueError(f"Unknown payload preset {payload!r} for {aircraft.id}; known: {known}")
    return {int(p): resolve_weapon(aircraft, int(p), w) for p, w in payload.items()}


def is_fuel_tank(clsid: str) -> bool:
    """Best-effort check for external/internal fuel tank CLSIDs."""
    from dcs.weapons_data import Weapons

    low = clsid.lower()
    if "fuel" in low or "tank" in low or "eft" in low or "ptb" in low:
        return True
    for name, val in vars(Weapons).items():
        if isinstance(val, dict) and val.get("clsid") == clsid:
            return "fuel" in name.lower() or "fuel" in str(val.get("name", "")).lower()
    return False
