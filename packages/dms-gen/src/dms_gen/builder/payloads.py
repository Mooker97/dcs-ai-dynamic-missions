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
