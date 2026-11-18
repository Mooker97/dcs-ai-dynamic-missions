"""Comms plan: a deterministic, non-colliding frequency for every radio agency.

See docs/CONTRACTS.md "Planner comms plan". Spec values always win; the planner fills the
gaps (Ops, Tower, JTAC, AWACS/tanker without a ``frequency_mhz``) in a band the player
aircraft can tune, writes them back to the support groups and ``DMS_CONFIG.speakers``, and
puts every agency on the client aircraft's radio presets.
"""

from __future__ import annotations

import re
from collections.abc import Sequence
from dataclasses import dataclass, field
from typing import Literal

from dms_core.schemas.mission import MissionSpec, Support
from dms_core.schemas.plan import PlanComm, PlanGroup, PlanRadioPreset
from dms_core.schemas.runtime import Speaker
from dms_core.schemas.story import Character, StoryBible

Band = Literal["uhf", "vhf", "fm"]
Role = Literal["flight", "tower", "awacs", "tanker", "ground", "agency"]

#: Band limits (MHz) and the planner's 25 kHz grid.
BAND_RANGE: dict[Band, tuple[float, float]] = {
    "fm": (30.0, 87.975),
    "vhf": (118.0, 151.975),
    "uhf": (225.0, 399.975),
}
#: role -> preferred bands, each with (first frequency, step) for assignments.
ROLE_BANDS: dict[Role, tuple[tuple[Band, float, float], ...]] = {
    "awacs": (("uhf", 251.0, 1.0), ("vhf", 140.0, 0.5)),
    "tanker": (("uhf", 276.0, 1.0), ("vhf", 145.0, 0.5)),
    "ground": (("fm", 41.0, 0.5), ("vhf", 133.0, 0.5), ("uhf", 280.0, 1.0)),
    "agency": (("vhf", 124.0, 0.5), ("uhf", 260.0, 1.0)),
    "tower": (("uhf", 300.0, 1.0), ("vhf", 120.0, 0.5)),
}
#: preset order: the command net first so it lands on channel 1 of a second radio.
PRESET_ORDER: dict[Role, int] = {"agency": 0, "awacs": 1, "ground": 2, "tanker": 3, "tower": 4}

#: Multi-band radios pydcs can't express by channel 1: type -> {radio id: bands}.
MULTIBAND: dict[str, dict[int, frozenset[Band]]] = {
    "A-10C_2": {1: frozenset({"uhf", "vhf", "fm"})},  # ARC-210
    "A-10C": {1: frozenset({"uhf"}), 2: frozenset({"vhf", "fm"})},
    "FA-18C_hornet": {1: frozenset({"uhf", "vhf", "fm"}), 2: frozenset({"uhf", "vhf", "fm"})},
    "F-14B": {2: frozenset({"uhf", "vhf", "fm"})},  # ARC-182
    "F-14A-135-GR": {2: frozenset({"uhf", "vhf", "fm"})},
    "AV8BNA": {1: frozenset({"uhf", "vhf", "fm"}), 2: frozenset({"uhf", "vhf", "fm"})},
    "Ka-50": {2: frozenset({"vhf", "uhf"})},  # R-800
    "Ka-50_3": {2: frozenset({"vhf", "uhf"})},
    "Mi-8MT": {1: frozenset({"vhf", "uhf"})},  # R-863
    "Mi-24P": {1: frozenset({"vhf", "uhf"})},
    "CH-47Fbl1": {1: frozenset({"fm", "vhf", "uhf"}), 2: frozenset({"uhf", "vhf", "fm"})},
}
#: Bands a type can tune on radios pydcs has no presets for (manual tuning only).
EXTRA_BANDS: dict[str, frozenset[Band]] = {
    "UH-1H": frozenset({"fm", "vhf"}),  # ARC-131 FM, ARC-134 VHF AM
}

_FLIGHT_RE = re.compile(r"wing ?man|intercom|crew|flight engineer|co-?pilot|sister.?ship", re.I)
_TOWER_RE = re.compile(r"tower|air traffic|\batc\b|ground control|approach control", re.I)
_AWACS_RE = re.compile(r"awacs|e-3|e-2|weapons controller|gci|airborne control", re.I)
_GROUND_RE = re.compile(
    r"\b(jtac|fac|observation post|convoy|outpost|company|platoon|ground forces|squad|"
    r"infantry|loading party|section leader|patrol leader|team leader)\b",
    re.I,
)
_SUPPORT_ROLE: dict[str, Role] = {
    "awacs": "awacs",
    "tanker": "tanker",
    "jtac": "ground",
    "convoy": "ground",
    "friendly_ground": "ground",
    "medevac": "ground",
    "farp": "ground",
    "cas": "agency",
}


def band_of(freq_mhz: float) -> Band:
    """< 88 MHz FM, < 225 MHz VHF (AM), else UHF."""
    if freq_mhz < 88.0:
        return "fm"
    if freq_mhz < 225.0:
        return "vhf"
    return "uhf"


def modulation_of(band: Band) -> Literal["AM", "FM"]:
    return "FM" if band == "fm" else "AM"


def aircraft_radios(type_id: str) -> list[tuple[int, frozenset[Band], int]]:
    """``[(radio id, bands, channel count)]`` of the presettable radios (pydcs ``panel_radio``).

    A radio's band is that of its channel 1 unless :data:`MULTIBAND` lists it. Falls back to
    one radio in the band of the type's ``radio_frequency`` (or UHF).
    """
    try:
        from ..builder.mission import aircraft_type

        ac = aircraft_type(type_id)
    except Exception:  # unknown type: assume a single UHF radio
        return [(1, frozenset({"uhf"}), 20)]
    panel = getattr(ac, "panel_radio", None) or {}
    multi = MULTIBAND.get(type_id, {})
    out: list[tuple[int, frozenset[Band], int]] = []
    for rid in sorted(panel):
        chans = panel[rid].get("channels") or {}
        if not chans:
            continue
        first = chans.get(1, next(iter(chans.values())))
        bands = multi.get(int(rid), frozenset({band_of(float(first))}))
        out.append((int(rid), bands, len(chans)))
    if not out:
        rf = float(getattr(ac, "radio_frequency", 0) or 0)
        out.append((1, frozenset({band_of(rf) if rf > 0 else "uhf"}), 20))
    return out


def tunable_bands(type_id: str) -> set[Band]:
    """Every band ``type_id`` can tune (presettable radios plus :data:`EXTRA_BANDS`)."""
    out: set[Band] = set(EXTRA_BANDS.get(type_id, frozenset()))
    for _rid, bands, _n in aircraft_radios(type_id):
        out |= bands
    return out


def character_role(ch: Character) -> Role:
    text = f"{ch.role} {ch.name}"
    if _FLIGHT_RE.search(text):
        return "flight"
    if _TOWER_RE.search(text):
        return "tower"
    if _AWACS_RE.search(text):
        return "awacs"
    if _GROUND_RE.search(text):
        return "ground"
    return "agency"


@dataclass
class _Agency:
    id: str
    kind: Literal["flight", "support", "agency", "tower"]
    role: Role
    callsign: str
    speaker: str | None = None
    freq: float | None = None
    modulation: Literal["AM", "FM"] | None = None
    source: Literal["spec", "planner", "airbase", "aircraft"] = "planner"
    support: Support | None = None
    speakers: list[str] = field(default_factory=list)


@dataclass
class CommsPlan:
    """Result of :func:`plan_comms`."""

    comms: list[PlanComm]
    speakers: dict[str, Speaker]


def _atc(theater: str, airbase: str | None) -> tuple[float | None, float | None]:
    """(UHF, VHF) ATC frequencies of ``airbase`` from the catalog; (None, None) if unknown."""
    if not airbase:
        return None, None
    try:
        from dms_core import catalog

        for ab in catalog.find_airbases(theater):
            if ab.name == airbase:
                return ab.uhf_mhz, ab.vhf_mhz
    except Exception:  # pydcs/terrain unavailable
        return None, None
    return None, None


def _key(freq: float) -> int:
    return round(freq * 1000)


def _pick(role: Role, bands: set[Band], used: set[int]) -> tuple[float, Band]:
    prefs = ROLE_BANDS.get(role, ROLE_BANDS["agency"])
    usable = [p for p in prefs if p[0] in bands] or [prefs[0]]
    for band, start, step in usable:
        lo, hi = BAND_RANGE[band]
        f = start
        while lo <= f <= hi:
            if _key(f) not in used:
                return round(f, 3), band
            f = round(f + step, 3)
    band = usable[0][0]  # band exhausted (never in practice): first free 25 kHz step
    f = BAND_RANGE[band][0]
    while _key(f) in used:
        f = round(f + 0.025, 3)
    return f, band


def _support_agency(s: Support, cid_callsign: dict[str, str]) -> _Agency | None:
    role = _SUPPORT_ROLE.get(s.role, "agency")
    always = s.role in ("awacs", "tanker", "jtac")
    if not always and not (s.speaker or s.callsign or s.frequency_mhz):
        return None
    callsign = s.callsign or (cid_callsign.get(s.speaker, "") if s.speaker else "") or s.id
    return _Agency(
        id=s.id,
        kind="support",
        role=role,
        callsign=callsign,
        speaker=s.speaker,
        freq=s.frequency_mhz,
        modulation=s.modulation,
        source="spec" if s.frequency_mhz else "planner",
        support=s,
    )


def plan_comms(
    spec: MissionSpec,
    bible: StoryBible | None,
    speaker_ids: Sequence[str],
    groups: list[PlanGroup],
    speakers: dict[str, Speaker],
    *,
    start_airbases: Sequence[str | None] = (),
) -> CommsPlan:
    """Assign frequencies and return the comms list; mutates support/client ``groups``.

    ``speaker_ids``: characters that talk in this mission (cast + line speakers).
    ``speakers``: the runtime speaker map (callsigns); frequencies are filled in place.
    ``start_airbases``: the player flights' start airbases (first one is the tower's).
    """
    from .planning import radio_modulation

    chars = {c.id: c for c in bible.characters} if bible is not None else {}
    factions = {f.id: f for f in bible.factions} if bible is not None else {}
    from .flights import flight_support

    focus = next(
        (f for f in spec.flights if spec.watch is not None and f.id == spec.watch.focus), None
    )
    if spec.player_flights:
        side: str = spec.player_flights[0].coalition
        first_aircraft = spec.player_flights[0].aircraft
    elif focus is not None:  # watch mission: the focus flight stands in for the players
        side, first_aircraft = focus.coalition, focus.aircraft
    else:
        side, first_aircraft = "blue", ""
    cid_callsign = {cid: (ch.callsign or ch.name) for cid, ch in chars.items()}
    clients = [g for g in groups if g.client]
    radios = aircraft_radios(first_aircraft) if first_aircraft else []
    bands: set[Band] = tunable_bands(first_aircraft) if first_aircraft else {"uhf", "vhf", "fm"}

    used: set[int] = set()
    flights: list[_Agency] = []
    for f in spec.player_flights:
        g = next(
            (c for c in clients if c.source == f.callsign or c.name.startswith(f.callsign)), None
        )
        freq = f.frequency_mhz or (g.frequency_mhz if g is not None else None)
        if freq is None:
            continue
        if any(a.id == f.callsign for a in flights):
            continue
        flights.append(
            _Agency(
                id=f.callsign,
                kind="flight",
                role="flight",
                callsign=f.callsign,
                freq=freq,
                modulation=radio_modulation(freq),  # type: ignore[arg-type]
                source="spec" if f.frequency_mhz else "aircraft",
            )
        )
        used.add(_key(freq))
    for ab in start_airbases:
        for atc in _atc(spec.theater, ab):
            if atc:
                used.add(_key(atc))

    agencies: list[_Agency] = []
    support_speakers: set[str] = set()
    for s in [*spec.support, *flight_support(spec)]:
        a = _support_agency(s, cid_callsign)
        if a is None:
            continue
        if s.speaker:
            support_speakers.add(s.speaker)
        agencies.append(a)
    flight_speakers: dict[str, float] = {}
    for cid in speaker_ids:
        if cid in support_speakers:
            continue
        ch = chars.get(cid)
        if ch is None:
            continue
        fac = factions.get(ch.faction) if ch.faction else None
        if fac is not None and fac.dcs.coalition != side:
            continue  # enemy voices keep coalition-wide audio
        role = character_role(ch)
        if role == "flight":
            if flights and flights[0].freq is not None:
                flight_speakers[cid] = flights[0].freq
            continue
        agencies.append(
            _Agency(
                id=cid,
                kind="tower" if role == "tower" else "agency",
                role=role,
                callsign=ch.callsign or ch.name,
                speaker=cid,
            )
        )
    for a in agencies:  # spec frequencies first, so assignments avoid them
        if a.freq is not None:
            used.add(_key(a.freq))
    tower_uhf, tower_vhf = _atc(spec.theater, start_airbases[0] if start_airbases else None)
    for a in agencies:
        if a.freq is not None:
            continue
        if a.role == "tower":
            atc = tower_uhf if (tower_uhf and "uhf" in bands) else tower_vhf or tower_uhf
            if atc:
                a.freq, a.source = round(atc, 3), "airbase"
                used.add(_key(atc))
                continue
        a.freq, band = _pick(a.role, bands, used)
        a.modulation = modulation_of(band)
        a.source = "planner"
        used.add(_key(a.freq))

    # write back: support groups and runtime speakers
    for a in agencies:
        assert a.freq is not None
        mod = radio_modulation(a.freq, a.modulation)
        a.modulation = mod  # type: ignore[assignment]
        if a.support is not None:
            for g in groups:
                if g.source == a.support.id and not g.client:
                    g.frequency_mhz = a.freq
                    g.modulation = mod  # type: ignore[assignment]
        if a.speaker and a.speaker in speakers:
            sp = speakers[a.speaker]
            sp.frequency = a.freq
            sp.modulation = 1 if mod == "FM" else 0
    for cid, freq in flight_speakers.items():
        if cid in speakers:
            speakers[cid].frequency = freq
            speakers[cid].modulation = 1 if radio_modulation(freq) == "FM" else 0

    presets, flight_label = _presets(radios, flights, agencies)
    for g in clients:
        g.radio_presets = [p for p, _a in presets]
    preset_of = {id(a): f"radio {p.radio} ch {p.channel}" for p, a in presets}
    first_flight = flights[0] if flights else None
    comms = [
        PlanComm(
            id=a.id,
            kind=a.kind,
            callsign=a.callsign,
            frequency_mhz=float(a.freq or 0),
            modulation=radio_modulation(a.freq, a.modulation),  # type: ignore[arg-type]
            band=band_of(float(a.freq or 0)),
            speaker=a.speaker,
            source=a.source,
            preset=preset_of.get(id(a)) or (flight_label if a is first_flight else None),
        )
        for a in [*flights, *agencies]
        if a.freq
    ]
    return CommsPlan(comms=comms, speakers=speakers)


def _presets(
    radios: list[tuple[int, frozenset[Band], int]], flights: list[_Agency], agencies: list[_Agency]
) -> tuple[list[tuple[PlanRadioPreset, _Agency]], str | None]:
    """Agency presets on the first player aircraft's radios (see CONTRACTS), and the radio
    label of the flight frequency (channel 1 of its first compatible radio, set by DCS)."""
    nxt: dict[int, int] = {rid: 1 for rid, _b, _n in radios}
    size = {rid: n for rid, _b, n in radios}
    flight_label: str | None = None
    if flights and flights[0].freq is not None:
        fb = band_of(flights[0].freq)
        r = next((rid for rid, b, _n in radios if fb in b), None)
        if r is not None:
            nxt[r] = 2  # DCS puts the flight frequency on channel 1 of its first radio
            flight_label = f"radio {r} ch 1"
    order = sorted(
        (a for a in agencies if a.freq is not None),
        key=lambda a: PRESET_ORDER.get(a.role, 9),
    )
    out: list[tuple[PlanRadioPreset, _Agency]] = []
    for a in order:
        assert a.freq is not None
        band = band_of(a.freq)
        cands = [rid for rid, b, _n in radios if band in b and nxt[rid] <= size[rid]]
        if not cands:
            continue
        rid = min(cands, key=lambda r: (nxt[r], r))  # emptiest radio of that band
        out.append(
            (
                PlanRadioPreset(radio=rid, channel=nxt[rid], frequency_mhz=a.freq, name=a.callsign),
                a,
            )
        )
        nxt[rid] += 1
    return out, flight_label
