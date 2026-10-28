"""Ambient friendly base traffic: player departure airbases -> ``DMS_CONFIG.ambient`` sites.

One site per distinct airbase a player (client) group starts at. Unit types come from the
catalog only (era + coalition, unarmed/support roles), so ``dms check`` (``ambient_bad_type``)
always passes for planner output. Deterministic for a given seed; uses its own RNG stream so the
rest of the plan is unaffected.
"""

from __future__ import annotations

import random
import re
import zlib
from collections.abc import Sequence
from dataclasses import dataclass

from dms_core import catalog as cat
from dms_core.schemas.mission import AmbientSpec
from dms_core.schemas.plan import PlanGroup
from dms_core.schemas.runtime import (
    XY,
    Ambient,
    AmbientAvoid,
    AmbientLayer,
    AmbientLayers,
    AmbientSite,
)

from .context import country_key, find_airbase

AVOID_RADIUS_M = 60.0
MAX_TYPES = 3


@dataclass(frozen=True)
class Density:
    """Per-density layer counts and caps."""

    departures: int
    arrivals: int
    ground: int
    helo: int
    statics: int
    site_groups: int
    site_units: int
    global_groups: int
    global_units: int


DENSITY: dict[str, Density] = {
    "low": Density(1, 1, 2, 0, 2, 6, 12, 8, 16),
    "medium": Density(1, 1, 3, 1, 3, 8, 16, 12, 24),
    "high": Density(2, 2, 4, 1, 5, 12, 24, 16, 32),
}


def site_id(airbase: str) -> str:
    """'Hatay' -> 'hatay'; 'Rafic Hariri Beirut' -> 'rafic_hariri_beirut'."""
    slug = re.sub(r"[^a-z0-9]+", "_", airbase.lower()).strip("_")
    return slug or "site"


def _usable(u: cat.UnitType, era: str | None, side: str) -> bool:
    return (era is None or era in u.eras) and side in u.coalitions and u.threat in ("none", "low")


def _prefer_country(units: list[cat.UnitType], country: str) -> list[cat.UnitType]:
    """Units hinted for ``country`` if there are any, else all of them."""
    local = [u for u in units if country in u.countries]
    return local or units


def candidate_types(layer: str, era: str | None, side: str, country: str) -> list[str]:
    """Catalog unit ids suitable for ambient ``layer`` (sorted; empty if none)."""
    units = list(cat.load_catalog().units.values())
    if layer in ("departures", "arrivals"):
        pool = [u for u in units if u.category == "plane" and u.role == "transport"]
    elif layer == "helo":
        pool = [
            u
            for u in units
            if u.category == "helicopter" and u.role in ("utility_helo", "transport_helo")
        ]
    else:  # ground / statics: unarmed service vehicles
        pool = [
            u
            for u in units
            if u.category == "ground"
            and u.role in ("transport", "logistics")
            and u.pydcs_class.startswith("vehicles.Unarmed.")
        ]
    pool = [u for u in pool if _usable(u, era, side)]
    return sorted(u.id for u in _prefer_country(pool, country))


def _pick(cands: list[str], rng: random.Random) -> list[str]:
    picked = list(cands)
    rng.shuffle(picked)
    return sorted(picked[:MAX_TYPES])


def _layers(
    d: Density, era: str | None, side: str, country: str, rng: random.Random
) -> AmbientLayers:
    def types(layer: str) -> list[str]:
        return _pick(candidate_types(layer, era, side, country), rng)

    out = AmbientLayers()
    if d.departures and (t := types("departures")):
        out.departures = AmbientLayer(
            count=d.departures,
            types=t,
            category="airplane",
            interval_sec=(240, 480),
            distance_m=40000,
            alt_m=1500,
            speed=120,
        )
    if d.arrivals and (t := types("arrivals")):
        out.arrivals = AmbientLayer(
            count=d.arrivals,
            types=t,
            category="airplane",
            interval_sec=(300, 600),
            distance_m=25000,
            alt_m=1000,
            speed=110,
        )
    if d.ground and (t := types("ground")):
        out.ground = AmbientLayer(count=d.ground, types=t, radius_m=500, speed=4)
    if d.helo and (t := types("helo")):
        out.helo = AmbientLayer(
            count=d.helo, types=t, category="helicopter", radius_m=3000, alt_m=150, speed=45
        )
    if d.statics and (t := types("statics")):
        # Unarmed vehicles placed as statics: DCS static category "Unarmed".
        out.statics = AmbientLayer(count=d.statics, types=t, category="Unarmed", radius_m=400)
    return out


def plan_ambient(
    spec_ambient: AmbientSpec,
    groups: Sequence[PlanGroup],
    *,
    theater: str,
    era: str | None,
    seed: int,
) -> Ambient | None:
    """``DMS_CONFIG.ambient`` for the client groups' departure airbases (None when off/empty)."""
    if not spec_ambient.enabled or spec_ambient.density == "off":
        return None
    d = DENSITY[spec_ambient.density]
    rng = random.Random(seed ^ zlib.crc32(b"dms.ambient"))
    by_base: dict[str, list[PlanGroup]] = {}
    for g in groups:
        if not g.client or not g.route:
            continue
        wp = g.route[0]
        if not wp.airbase or wp.action == "Turning Point":
            continue  # air start / not at an airbase
        by_base.setdefault(wp.airbase, []).append(g)
    sites: list[AmbientSite] = []
    for name, gs in by_base.items():
        ab = find_airbase(theater, name)
        if ab is None:
            continue
        side = gs[0].coalition
        if side not in ("blue", "red"):
            continue
        country = country_key(gs[0].country)
        layers = _layers(d, era, side, country, rng)
        if not any(getattr(layers, k) is not None for k in AmbientLayers.model_fields):
            continue
        avoid = [
            AmbientAvoid(x=round(u.x, 1), y=round(u.y, 1), radius_m=AVOID_RADIUS_M)
            for g in gs
            for u in g.units
        ]
        sid = site_id(ab.name)
        n = sum(1 for s in sites if s.id == sid or s.id.startswith(sid + "_"))
        sites.append(
            AmbientSite(
                id=sid if n == 0 else f"{sid}_{n + 1}",
                airbase=ab.name,
                point=XY(x=round(ab.x, 1), y=round(ab.y, 1)),
                coalition=2 if side == "blue" else 1,
                country=country,
                max_groups=d.site_groups,
                max_units=d.site_units,
                avoid=avoid,
                layers=layers,
            )
        )
    if not sites:
        return None
    return Ambient(max_groups=d.global_groups, max_units=d.global_units, sites=sites)
