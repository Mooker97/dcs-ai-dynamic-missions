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
    # A-10C II. Stations 1-11 left to right: 1/11 outboard, 3/9 Maverick rails, 6 centreline
    # (left empty when 5/7 carry stores), 10 targeting pod. pydcs/DCS default is clean pylons.
    "A-10C_2": {
        # CAS: ALQ-131, 7x M151 rockets, 4x AGM-65D (IIR), 2x GBU-12,
        # 2x GBU-38, LITENING, 2x AIM-9M.
        "cas": {
            1: "ALQ_131___ECM_Pod",
            2: "LAU_131___7_x_UnGd_Rkts__70_mm_Hydra_70_M151_HE",
            3: "LAU_88___2_x_AGM_65D___Maverick_D__IIR_ASM_",
            4: "GBU_12___500lb_Laser_Guided_Bomb",
            5: "GBU_38_V_1_B___JDAM__500lb_GPS_Guided_Bomb",
            7: "GBU_38_V_1_B___JDAM__500lb_GPS_Guided_Bomb",
            8: "GBU_12___500lb_Laser_Guided_Bomb",
            9: "LAU_88___2_x_AGM_65D___Maverick_D__IIR_ASM__",  # right-hand rack name
            10: "AN_AAQ_28_LITENING___Targeting_Pod_",
            11: "LAU_105___2_x_AIM_9M_Sidewinder_IR_AAM",
        },
    },
}


# --- Player-flyable helicopters (catalog `tags: [player]`). Weapon names are pydcs
# ``PylonN`` attributes, so every preset resolves to real CLSIDs (tests check this).
_B8 = "B_8V20A___20_x_UnGd_Rkts__80_mm_S_8KOM_HEAT_Frag"  # B-8V20A, 20x S-8KOM
_B13 = "B_13L___5_x_UnGd_Rkts__122_mm_S_13OF_Blast_Fragmentation"
_VIKHR = "APU_6___6_x_9M127_Vikhr___ATGM__LOSBR__Tandem_HEAT_Frag"
_UB32 = "UB_32A_24___32_x_UnGd_Rkts__57_mm_S_5KO_HEAT_Frag"
_MI24_GUNS = {7: "KORD_12_7_MI24_L", 8: "KORD_12_7_MI24_R"}  # cabin window KORDs

PRESETS.update(
    {
        # Mi-8MTV2. Pylons 1-6 are the outrigger racks, 7 = nose/tail KORD 12.7 mm,
        # 8 = door PKT 7.62 mm. Transport: clean racks, defensive guns only.
        "Mi-8MT": {
            "transport": {7: "KORD_12_7", 8: "PKT_7_62"},
            # Armed escort / CAS: 4x B-8V20A (80x S-8KOM) on the outer racks, guns.
            "rockets": {1: _B8, 2: _B8, 5: _B8, 6: _B8, 7: "KORD_12_7", 8: "PKT_7_62"},
        },
        # UH-1H. 1/6 = fixed M134 (gunship), 2/5 = rocket racks, 3/4 = door guns.
        "UH-1H": {
            # Slick: two M60D door guns.
            "transport": {3: "M60_SIDE_L", 4: "M60_SIDE_R"},
            # Gunship: 2x M134 fixed, 2x XM158 (14x M151 HE), M60D doors.
            "rockets": {
                1: "M134_L",
                2: "XM158_M151",
                3: "M60_SIDE_L",
                4: "M60_SIDE_R",
                5: "XM158_M151",
                6: "M134_R",
            },
        },
        # CH-47F: three M240H crew-served guns (left door, right window, ramp).
        "CH-47Fbl1": {"transport": {1: "M240H", 2: "M240H_", 3: "M240H__"}},
        # Mi-24P. 1/6 = ATGM rails, 2-5 = wing racks, 7/8 = cabin KORD.
        "Mi-24P": {
            # Anti-armour: 4x 9M120 Ataka, 2x B-8V20A + 2x UB-32 rockets.
            "atgm_rockets": {
                1: "_2_x_9M120_Ataka__AT_9_Spiral_2____ATGM__SACLOS__Tandem_HEAT",
                2: _B8,
                3: _UB32,
                4: _UB32,
                5: _B8,
                6: "_2_x_9M120_Ataka__AT_9_Spiral_2____ATGM__SACLOS__Tandem_HEAT",
                **_MI24_GUNS,
            },
            # Rocket CAS: 4x B-8V20A (80x S-8KOM), empty ATGM rails.
            "rockets": {2: _B8, 3: _B8, 4: _B8, 5: _B8, **_MI24_GUNS},
            # Troop lift with self-defence: 2x B-8V20A outboard, inboard racks clean.
            "transport": {2: _B8, 5: _B8, **_MI24_GUNS},
        },
        # Ka-50 (2011 and III). 1/4 = outer (Vikhr capable), 2/3 = inner.
        "Ka-50": {
            "atgm_rockets": {1: _VIKHR, 2: _B8, 3: _B8, 4: _VIKHR},
            "rockets": {1: _B8, 2: _B13, 3: _B13, 4: _B8},
        },
        "Ka-50_3": {
            # Ka-50 III adds 5/6 = Igla (9S846 Strelets) launchers.
            "atgm_rockets": {
                1: _VIKHR,
                2: _B8,
                3: _B8,
                4: _VIKHR,
                5: "_9S846_Strelets___2_x_9M39_Igla",
                6: "_9S846_Strelets___2_x_9M39_Igla",
            },
            "rockets": {1: _B8, 2: _B13, 3: _B13, 4: _B8},
        },
        # SA342M Gazelle: 4x HOT 3 plus IR deflector and sand filter.
        "SA342M": {
            "atgm": {
                1: "_2_x_HOT_3___ATGM__SACLOS__HEAT__",
                2: "_2_x_HOT_3___ATGM__SACLOS__HEAT",
                3: "Sand_Filter",
                4: "IR_Deflector",
            },
        },
        # OH-58D Kiowa Warrior: 1 = left, 5 = right weapons station.
        "OH58D": {
            "hellfire_rockets": {
                1: "OH58D_AGM_114_L",
                5: "M260___7_x_UnGd_Rkts__70_mm_Hydra_70_M151_HE",
            },
            "hellfire": {1: "OH58D_AGM_114_L", 5: "OH58D_AGM_114_R"},
            "rockets": {
                1: "M260___7_x_UnGd_Rkts__70_mm_Hydra_70_M151_HE",
                5: "M260___7_x_UnGd_Rkts__70_mm_Hydra_70_M151_HE",
            },
        },
    }
)

#: Aircraft that must never get a silent default loadout (pydcs/DCS default is fuel tanks
#: or bare pylons).
DEFAULT_PRESET: dict[str, str] = {
    "AH-64D_BLK_II": "hellfire_rockets",
    "A-10C_2": "cas",
    "Mi-8MT": "transport",
    "UH-1H": "transport",
    "CH-47Fbl1": "transport",
    "Mi-24P": "atgm_rockets",
    "Ka-50": "atgm_rockets",
    "Ka-50_3": "atgm_rockets",
    "SA342M": "atgm",
    "OH58D": "hellfire_rockets",
}


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
