"""Small built-in gazetteer of towns and landmarks per theater (WGS84 lat/lon).

pydcs ships no town data, so ``near_named_place`` areas are resolved against this table and
against the theater's airbase names. Extend ``PLACES`` (or pass ``extra`` to :func:`find_place`)
when a spec needs a place that is missing; validation suggests close matches.
"""

from __future__ import annotations

import difflib
import unicodedata

#: theater -> place name -> (lat, lon)
PLACES: dict[str, dict[str, tuple[float, float]]] = {
    "Syria": {
        "Reyhanli": (36.2689, 36.5672),
        "Kirikhan": (36.4997, 36.3575),
        "Antakya": (36.2025, 36.1606),
        "Iskenderun": (36.5872, 36.1735),
        "Adana": (37.0000, 35.3213),
        "Kilis": (36.7184, 37.1212),
        "Gaziantep": (37.0662, 37.3833),
        "Afrin": (36.5119, 36.8695),
        "Azaz": (36.5863, 37.0441),
        "Aleppo": (36.2021, 37.1343),
        "Al-Bab": (36.3705, 37.5157),
        "Manbij": (36.5281, 37.9549),
        "Idlib": (35.9306, 36.6339),
        "Saraqib": (35.8645, 36.8006),
        "Ariha": (35.8126, 36.6086),
        "Jisr al-Shughur": (35.8126, 36.3176),
        "Maarrat al-Numan": (35.6444, 36.6747),
        "Latakia": (35.5236, 35.7917),
        "Baniyas": (35.1825, 35.9497),
        "Tartus": (34.8890, 35.8866),
        "Hama": (35.1318, 36.7578),
        "Homs": (34.7324, 36.7137),
        "Palmyra": (34.5560, 38.2690),
        "Damascus": (33.5138, 36.2765),
        "Beirut": (33.8938, 35.5018),
        "Tripoli": (34.4367, 35.8497),
        "Baalbek": (34.0047, 36.2110),
        "Haifa": (32.7940, 34.9896),
        "Tiberias": (32.7959, 35.5300),
        "Quneitra": (33.1256, 35.8240),
        "Nicosia": (35.1856, 33.3823),
        "Larnaca": (34.9003, 33.6232),
    },
    "Caucasus": {
        "Tbilisi": (41.7151, 44.8271),
        "Kutaisi": (42.2679, 42.6946),
        "Batumi": (41.6168, 41.6367),
        "Sukhumi": (43.0015, 41.0234),
        "Gori": (41.9842, 44.1158),
        "Zugdidi": (42.5088, 41.8709),
        "Senaki": (42.2700, 42.0670),
        "Poti": (42.1462, 41.6719),
        "Kobuleti": (41.8214, 41.7792),
        "Ochamchire": (42.7123, 41.4683),
        "Gudauta": (43.1052, 40.6216),
        "Gagra": (43.2786, 40.2711),
        "Sochi": (43.6028, 39.7342),
        "Tskhinvali": (42.2257, 43.9706),
        "Nalchik": (43.4853, 43.6071),
        "Beslan": (43.1936, 44.5338),
        "Vladikavkaz": (43.0205, 44.6819),
        "Mineralnye Vody": (44.2107, 43.1353),
        "Maykop": (44.6098, 40.1006),
        "Krasnodar": (45.0355, 38.9753),
        "Novorossiysk": (44.7239, 37.7708),
        "Anapa": (44.8945, 37.3165),
        "Krymsk": (44.9289, 37.9861),
    },
    "PersianGulf": {
        "Dubai": (25.2048, 55.2708),
        "Abu Dhabi": (24.4539, 54.3773),
        "Sharjah": (25.3463, 55.4209),
        "Ras Al Khaimah": (25.8007, 55.9762),
        "Fujairah": (25.1288, 56.3265),
        "Al Ain": (24.2075, 55.7447),
        "Khasab": (26.1797, 56.2475),
        "Bandar Abbas": (27.1832, 56.2666),
        "Qeshm": (26.9581, 56.2719),
        "Bandar Lengeh": (26.5579, 54.8807),
    },
    "Nevada": {
        "Las Vegas": (36.1699, -115.1398),
        "Henderson": (36.0395, -114.9817),
        "Boulder City": (35.9786, -114.8325),
        "Pahrump": (36.2083, -115.9839),
        "Beatty": (36.9086, -116.7592),
        "Tonopah": (38.0672, -117.2301),
        "Caliente": (37.6150, -114.5119),
        "Alamo": (37.3647, -115.1647),
        "Mesquite": (36.8055, -114.0672),
    },
    "Afghanistan": {
        "Kabul": (34.5553, 69.2075),
        "Kandahar": (31.6289, 65.7372),
        "Bagram": (34.9461, 69.2650),
        "Jalalabad": (34.4265, 70.4515),
        "Ghazni": (33.5536, 68.4269),
        "Lashkar Gah": (31.5938, 64.3700),
    },
    "Sinai": {
        "Cairo": (30.0444, 31.2357),
        "Ismailia": (30.5965, 32.2715),
        "Suez": (29.9668, 32.5498),
        "Port Said": (31.2653, 32.3019),
        "El Arish": (31.1316, 33.7984),
        "Beersheba": (31.2520, 34.7915),
    },
}


def _norm(s: str) -> str:
    s = unicodedata.normalize("NFKD", s).encode("ascii", "ignore").decode()
    return "".join(ch for ch in s.lower() if ch.isalnum())


def places_for(theater: str) -> dict[str, tuple[float, float]]:
    """Known places for ``theater`` (empty dict when none are listed)."""
    return dict(PLACES.get(theater, {}))


def find_place(
    theater: str, name: str, extra: dict[str, tuple[float, float]] | None = None
) -> tuple[float, float] | None:
    """(lat, lon) of ``name`` (accent/case/punctuation-insensitive), or None."""
    table = places_for(theater)
    if extra:
        table.update(extra)
    key = _norm(name)
    for pname, ll in table.items():
        if _norm(pname) == key:
            return ll
    return None


def suggest_place(theater: str, name: str, also: list[str] | None = None, n: int = 3) -> list[str]:
    """Close matches for ``name`` among known places (plus ``also``, e.g. airbase names)."""
    pool = list(places_for(theater)) + list(also or [])
    normed = {_norm(p): p for p in pool}
    hits = difflib.get_close_matches(_norm(name), list(normed), n=n, cutoff=0.5)
    return [normed[h] for h in hits]
