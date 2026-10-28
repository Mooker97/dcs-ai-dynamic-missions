"""Turn a spec's loadout intent ('auto', a preset name, or free text) into exact pylons."""

# mypy: disallow-untyped-calls=False

from __future__ import annotations

import re
from dataclasses import dataclass

from dms_core.schemas.plan import Payload, Pylon

from ..builder.mission import aircraft_type
from ..builder.payloads import DEFAULT_PRESET, PRESETS, pylon_options, resolve_payload

_HF4 = "M299___4_x_AGM_114K_Hellfire"

#: Per aircraft: mission type (``dms_core`` ``MissionType``) -> preset for ``loadout: auto``.
MISSION_TYPE_PRESET: dict[str, dict[str, str]] = {
    "F-16C_50": {
        "SEAD": "sead",
        "DEAD": "sead",
        "STRIKE": "lgb_strike",
        "INTERDICTION": "lgb_strike",
        "CAS": "cas",
    },
}

#: Per aircraft: ordered (keyword regex, preset) rules for free-text intents. First match wins,
#: so SEAD keywords beat the LGB keywords in "SEAD/DEAD ... 2x AGM-88C HARM ..., 2x GBU-12".
INTENT_RULES: dict[str, tuple[tuple[str, str], ...]] = {
    "F-16C_50": (
        (r"\bharm\b|\bsead\b|\bdead\b|agm-?88", "sead"),
        (r"\bcas\b|maverick|agm-?65", "cas"),
        (r"gbu|\blgb|strike|laser", "lgb_strike"),
    ),
}


@dataclass
class LoadoutChoice:
    """Resolved loadout: a preset name or an explicit pylon->weapon map, plus how it was chosen."""

    preset: str | None
    weapons: dict[int, str] | None
    note: str  # 'exact' | 'auto' | 'interpreted: ...' | 'unresolved: ...'

    @property
    def ok(self) -> bool:
        return not self.note.startswith("unresolved")


def preset_for_mission_type(aircraft: str, mission_type: str | None) -> str | None:
    """Preset for ``aircraft`` on ``mission_type``, else the aircraft's DEFAULT_PRESET (or None)."""
    if mission_type is not None:
        preset = MISSION_TYPE_PRESET.get(aircraft, {}).get(mission_type.strip().upper())
        if preset is not None:
            return preset
    return DEFAULT_PRESET.get(aircraft)


def choose_loadout(aircraft: str, loadout: str, mission_type: str | None = None) -> LoadoutChoice:
    presets = PRESETS.get(aircraft, {})
    if loadout in presets:
        return LoadoutChoice(loadout, None, "exact")
    if loadout.strip().lower() == "auto":
        return LoadoutChoice(preset_for_mission_type(aircraft, mission_type), None, "auto")
    if not presets:
        return LoadoutChoice(
            None, None, f"unresolved: no presets for {aircraft}; DCS default payload used"
        )
    low = loadout.lower()
    for pattern, preset in INTENT_RULES.get(aircraft, ()):
        if preset in presets and re.search(pattern, low):
            return LoadoutChoice(preset, None, f"interpreted: {preset}")
    hellfire = "hellfire" in low or "agm-114" in low or "agm114" in low
    no_rockets = bool(re.search(r"\bno rockets?\b", low))
    rockets = ("rocket" in low or "hydra" in low or "m151" in low) and not no_rockets
    if aircraft == "AH-64D_BLK_II" and hellfire and not rockets and re.search(r"\b8\s*x", low):
        return LoadoutChoice(None, {1: _HF4, 4: _HF4}, "interpreted: 8x AGM-114K on pylons 1/4")
    if hellfire and rockets and "hellfire_rockets" in presets:
        return LoadoutChoice("hellfire_rockets", None, "interpreted: hellfire_rockets")
    if hellfire and "hellfire_heavy" in presets:
        return LoadoutChoice("hellfire_heavy", None, "interpreted: hellfire_heavy")
    if rockets and "rockets" in presets:
        return LoadoutChoice("rockets", None, "interpreted: rockets")
    default = preset_for_mission_type(aircraft, mission_type)
    return LoadoutChoice(
        default, None, f"unresolved: '{loadout}' not understood; using preset {default}"
    )


def payload_for(
    aircraft: str, loadout: str, mission_type: str | None = None
) -> tuple[Payload | None, LoadoutChoice]:
    """Exact Payload (pylon CLSIDs) for the plan, or None to keep the DCS default.

    Fuel is never set here (``Payload.fuel_kg`` stays None = full internal fuel).
    """
    choice = choose_loadout(aircraft, loadout, mission_type)
    spec: dict[int, str] | str | None = choice.weapons or choice.preset
    if spec is None:
        return None, choice
    ac = aircraft_type(aircraft)
    resolved = resolve_payload(ac, spec)
    if not resolved:
        return None, choice
    opts = pylon_options(ac)
    pylons = []
    for num, clsid in sorted(resolved.items()):
        name = next(
            (w.get("name") for w in opts.get(num, {}).values() if w["clsid"] == clsid), None
        )
        pylons.append(Pylon(num=num, clsid=clsid, name=str(name) if name else None))
    return Payload(pylons=pylons), choice
