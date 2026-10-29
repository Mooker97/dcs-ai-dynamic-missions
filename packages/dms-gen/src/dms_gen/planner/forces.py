"""Role -> catalog group template selection (era, faction equipment, strength)."""

from __future__ import annotations

import math
import random
import re
from dataclasses import dataclass, field

from dms_core import catalog as cat

#: Spec threat role -> catalog template ids, roughly light -> heavy (defined in dms_core so
#: ``dms catalog templates --role <ThreatRole>`` agrees with the planner).
ROLE_TEMPLATES: dict[str, list[str]] = cat.THREAT_ROLE_TEMPLATES

#: Spec threat role -> catalog *unit* roles usable to synthesize a faction template.
ROLE_UNIT_ROLES: dict[str, list[str]] = {
    "sam_short": ["sam_short"],
    "sam_medium": ["sam_medium", "sam_radar"],
    "sam_long": ["sam_long", "sam_radar"],
    "aaa": ["aaa"],
    "manpads": ["manpads"],
    "armor": ["mbt", "apc", "recon"],
    "ifv": ["ifv", "apc"],
    "technicals": ["technical"],
    "infantry": ["infantry", "emplacement"],
    "artillery": ["artillery", "mlrs"],
    "hvt": ["transport", "logistics", "ballistic_missile"],
}

AIR_DEFENSE_ROLES = {"sam_short", "sam_medium", "sam_long", "aaa", "manpads"}
SAM_ROLES = {"sam_short", "sam_medium", "sam_long"}
AIR_ROLES = {"fighters", "attack_helicopters"}

_THREAT_WEIGHT = {"none": 3.0, "low": 3.0, "medium": 2.0, "high": 1.0}


@dataclass
class TemplateChoice:
    """A template usable for a role (catalog or synthesized from faction equipment)."""

    id: str
    category: str  # ground | plane | helicopter | ship
    units: list[tuple[str, float, float, float]]  # type, dx, dy, heading(rad)
    skill: str = "Random"
    weight: float = 1.0
    synthesized: bool = False
    tags: list[str] = field(default_factory=list)

    @property
    def size(self) -> int:
        return len(self.units)


def _from_catalog(t: cat.GroupTemplate) -> TemplateChoice:
    c = cat.load_catalog()
    threats = [c.units[u.type].threat for u in t.units if u.type in c.units]
    worst = max(threats, key=lambda s: ["none", "low", "medium", "high"].index(s), default="low")
    return TemplateChoice(
        id=t.id,
        category=t.category,
        units=[(u.type, u.dx, u.dy, u.heading) for u in t.units],
        skill=t.skill,
        weight=_THREAT_WEIGHT.get(worst, 1.0),
    )


def _synth(
    role: str, faction: str, units: list[str], strength: str, rng: random.Random | None
) -> TemplateChoice | None:
    c = cat.load_catalog()
    roles = ROLE_UNIT_ROLES.get(role)
    if roles is None:
        return None
    pick = [u for u in units if u in c.units and c.units[u].category == "ground"]
    pick = [u for u in pick if c.units[u].role in roles]
    if not pick:
        return None
    n = {"light": 2, "medium": 3, "heavy": 4}.get(strength, 2)
    if role in ("sam_medium", "sam_long"):
        n = max(n, len(pick))
    types = [pick[i % len(pick)] for i in range(n)]
    if rng is not None and role not in ("sam_medium", "sam_long"):
        types = [rng.choice(pick) for _ in range(n)]
    out = [(t, -40.0 * i, 20.0 * (i % 2), 0.0) for i, t in enumerate(types)]
    return TemplateChoice(
        id=f"f_{faction}_{role}", category="ground", units=out, weight=2.0, synthesized=True
    )


def civil_template(faction: str, units: list[str]) -> TemplateChoice | None:
    """Template of a neutral (civilian) faction's ground vehicles, ignoring roles."""
    from dcs import vehicles

    pick = [u for u in units if u in vehicles.vehicle_map]
    if not pick:
        return None
    out = [(t, -40.0 * i, 0.0, 0.0) for i, t in enumerate(pick[:3])]
    return TemplateChoice(
        id=f"f_{faction}_civil", category="ground", units=out, weight=1.0, synthesized=True
    )


def candidates(
    role: str,
    era: str | None,
    faction: tuple[str, str, list[str]] | None = None,
    faction_id: str | None = None,
    strength: str = "medium",
) -> list[TemplateChoice]:
    """Templates for ``role`` in ``era``; faction equipment narrows (or synthesizes) the set."""
    c = cat.load_catalog()
    ids = [i for i in ROLE_TEMPLATES.get(role, []) if i in c.templates]
    tpls = [c.templates[i] for i in ids if era is None or era in c.templates[i].eras]
    base = [_from_catalog(t) for t in tpls]
    if faction is None:
        return base
    _country, coalition, units = faction
    if coalition == "neutral":
        civ = civil_template(faction_id or "civ", units)
        return [civ] if civ else base
    fu = set(units)
    full = [b for b in base if all(u[0] in fu for u in b.units)]
    if full:
        return full
    synth = _synth(role, faction_id or "fac", units, strength, None)
    if synth is not None:
        return [synth]
    half = [b for b in base if sum(u[0] in fu for u in b.units) * 2 >= b.size]
    return half or base


def pinned(role: str, era: str | None, ids: list[str]) -> list[TemplateChoice]:
    """Catalog templates among ``ids`` that ``role`` uses and that fit ``era`` (in ``ids`` order).

    Faction equipment does not narrow a pinned set: the designer asked for these templates.
    """
    c = cat.load_catalog()
    allowed = set(ROLE_TEMPLATES.get(role, []))
    out: list[TemplateChoice] = []
    for i in ids:
        t = c.templates.get(i)
        if t is None or i not in allowed or (era is not None and era not in t.eras):
            continue
        out.append(_from_catalog(t))
    return out


def pick_for_strength(
    choices: list[TemplateChoice], strength: str, rng: random.Random
) -> TemplateChoice:
    """Deterministic (seeded) pick biased to light/heavy end of the candidate list."""
    if not choices:
        raise ValueError("no template choices")
    n = len(choices)
    lo, hi = {
        "light": (0, max(1, math.ceil(n / 2))),
        "medium": (0, n),
        "heavy": (n // 2, n),
    }.get(strength, (0, n))
    return choices[rng.randrange(lo, hi)]


def group_count(role: str, strength: str) -> int:
    """How many groups a static threat of ``strength`` becomes."""
    if role in ("sam_medium", "sam_long"):
        return 1
    return {"light": 1, "medium": 2, "heavy": 3}.get(strength, 1)


_COMP = re.compile(r"(\d+)\s*[x\u00d7]\s*([^,;()]+)", re.IGNORECASE)


def parse_composition(text: str | None) -> tuple[list[str], list[str]]:
    """'4x M1126 Stryker, 2x HEMTT' -> (unit type ids, unresolved tokens)."""
    if not text:
        return [], []
    c = cat.load_catalog()
    by_name = {u.name.lower(): u.id for u in c.units.values()}
    by_id = {u.id.lower(): u.id for u in c.units.values()}
    types: list[str] = []
    bad: list[str] = []
    for m in _COMP.finditer(text):
        n = min(int(m.group(1)), 12)
        token = m.group(2).strip().rstrip(".")
        tid = by_id.get(token.lower()) or by_name.get(token.lower())
        if tid is None:
            sugg = c.suggest(token, "unit", n=1)
            tid = sugg[0] if sugg else None
            if tid is None:
                # substring match on id/name
                low = token.lower()
                hits = [
                    u.id for u in c.units.values() if low in u.id.lower() or low in u.name.lower()
                ]
                tid = hits[0] if hits else None
        if tid is None:
            bad.append(token)
        else:
            types.extend([tid] * n)
    return types, bad
