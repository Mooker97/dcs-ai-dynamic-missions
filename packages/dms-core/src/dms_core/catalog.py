"""Typed access to the DMS catalog (``data/catalog/*.yaml``) and pydcs terrain data.

The catalog grounds LLM-written specs: the mission-designer picks *roles, eras and areas*;
this module turns those into concrete DCS unit types, group templates and airbases.

Usage::

    from dms_core import catalog

    cat = catalog.load_catalog()                       # cached; finds data/catalog upward
    catalog.find_units(era="modern", coalition="red", role="sam_short")
    catalog.get_template("sa8").to_runtime()           # DMS_CONFIG `templates` entry
    catalog.mission_type("sead").threats["heavy"]
    catalog.find_airbases("Syria", near="Ramat David")[:3]
    catalog.suggest("Tunguska", "unit")

Airbase lookups need pydcs (``dcs``), which is a dependency of dms-gen, not dms-core; it is
imported lazily and a clear error is raised when it is missing.
"""

from __future__ import annotations

import difflib
import math
import os
from functools import lru_cache
from pathlib import Path
from typing import Any, Literal

import yaml  # type: ignore[import-untyped, unused-ignore]
from pydantic import BaseModel, ConfigDict, Field

__all__ = [
    "Airbase",
    "Catalog",
    "CatalogLookupError",
    "EncounterHint",
    "Era",
    "GroupTemplate",
    "MissionObjective",
    "MissionType",
    "Package",
    "PackageMember",
    "TemplateUnit",
    "UnitType",
    "find_airbases",
    "find_units",
    "get_template",
    "list_theaters",
    "load_catalog",
    "mission_type",
    "suggest",
]

Category = Literal["ground", "plane", "helicopter", "ship"]
Coalition = Literal["red", "blue", "neutral"]
SuggestKind = Literal["unit", "template", "package", "mission_type", "era", "theater", "airbase"]

# MissionSpec theater name -> pydcs dcs.terrain class name
_THEATERS: dict[str, str] = {
    "caucasus": "Caucasus",
    "syria": "Syria",
    "persiangulf": "PersianGulf",
    "nevada": "Nevada",
    "normandy": "Normandy",
    "thechannel": "TheChannel",
    "marianaislands": "MarianaIslands",
    "falklands": "Falklands",
    "sinai": "Sinai",
    "kola": "Kola",
    "afghanistan": "Afghanistan",
    "germany": "Germany",
    "germanycw": "Germany",
}


_THREAT_REF_KEYS = ("templates", "aa", "cap_templates", "packages")


class CatalogLookupError(KeyError):
    """Unknown catalog id. ``suggestions`` holds close matches for repair loops."""

    def __init__(self, kind: str, name: str, suggestions: list[str]) -> None:
        self.kind = kind
        self.name = name
        self.suggestions = suggestions
        hint = f"; did you mean {', '.join(repr(s) for s in suggestions)}?" if suggestions else ""
        super().__init__(f"unknown {kind} {name!r}{hint}")

    def __str__(self) -> str:
        return str(self.args[0])


class _Model(BaseModel):
    model_config = ConfigDict(extra="forbid", frozen=True)


class UnitType(_Model):
    id: str = Field(description="DCS type string, e.g. 'Osa 9A33 ln'.")
    name: str = Field(description="Human-readable name.")
    category: Category = Field(description="DCS domain.")
    role: str = Field(description="Primary role, e.g. sam_short, mbt, attack_helo.")
    threat: Literal["none", "low", "medium", "high"] = Field(description="Threat to aircraft.")
    eras: list[str] = Field(description="Plausible service eras (see eras.yaml).")
    coalitions: list[Coalition] = Field(description="Typical sides (hint).")
    countries: list[str] = Field(description="Typical DCS country.id keys (hint).")
    tags: list[str] = Field(default_factory=list, description="Secondary roles/traits.")
    description: str = Field(default="", description="Short description.")
    pydcs_id: str = Field(description="pydcs unit id (== DCS type string).")
    pydcs_class: str = Field(description="pydcs class path relative to `dcs.`.")

    def has_role(self, role: str) -> bool:
        """True if ``role`` is the primary role or one of the tags."""
        return role == self.role or role in self.tags


class TemplateUnit(_Model):
    type: str = Field(description="DCS unit type (unit_types.yaml id).")
    dx: float = Field(default=0.0, description="Offset north (DCS x) from the anchor, metres.")
    dy: float = Field(default=0.0, description="Offset east (DCS y) from the anchor, metres.")
    heading: float = Field(default=0.0, description="Heading in radians.")
    loadout: str | None = Field(default=None, description="Named loadout (resolved by dms-gen).")


class Tacan(_Model):
    channel: int
    callsign: str = ""


class GroupTemplate(_Model):
    id: str = Field(description="Template id (the YAML key).")
    name: str
    description: str = ""
    role: str = Field(description="air_defense, armor, infantry, qrf, convoy, hvt, fighter...")
    tags: list[str] = Field(default_factory=list)
    country: str = Field(description="DCS country.id key.")
    coalition: Coalition
    category: Category
    skill: str = "Random"
    eras: list[str] = Field(default_factory=list)
    source: str = ""
    units: list[TemplateUnit]
    static: bool = False
    threat: str | None = None
    max_range_nm: float | None = None
    alarm_state: Literal["red", "green", "auto"] | None = None
    engage_range_m: float | None = None
    frequency: float | None = None
    modulation: Literal["AM", "FM"] | None = None
    tacan: Tacan | None = None
    callsign: str | None = None

    def to_runtime(self) -> dict[str, Any]:
        """The DMS_CONFIG ``templates`` entry (snake_case; the Lua serializer camelCases)."""
        return {
            "country": self.country,
            "category": self.category,
            "skill": self.skill,
            "units": [
                {"type": u.type, "dx": u.dx, "dy": u.dy, "heading": u.heading} for u in self.units
            ],
        }


class PackageMember(_Model):
    template: str
    dx: float = 0.0
    dy: float = 0.0
    role: str = ""


class Package(_Model):
    id: str
    name: str
    description: str = ""
    country: str
    groups: list[PackageMember]
    threat: str | None = None
    source: str = ""


class MissionObjective(_Model):
    kind: str
    description: str


class EncounterHint(_Model):
    kind: str = Field(description="DMS encounter kind: pool, ambush_sam, waves, hunt, convoy, cap.")
    pool: list[str] = Field(description="Group template ids the pool usually draws from.")
    note: str = ""


class MissionType(_Model):
    id: str
    name: str
    description: str
    player_roles: list[str]
    typical_aircraft: list[str]
    loadouts: dict[str, str] = Field(default_factory=dict)
    objectives: list[MissionObjective]
    threats: dict[str, dict[str, Any]] = Field(description="intensity -> threat composition.")
    support: dict[str, Literal["required", "recommended", "optional"]]
    dynamic_encounters: list[EncounterHint]
    beats: list[str] = Field(default_factory=list)
    duration_min: tuple[int, int]
    briefing_hints: str = ""

    def threat_templates(self, intensity: str | None = None) -> list[str]:
        """All group/package template ids referenced in ``threats`` (optionally one intensity)."""
        out: list[str] = []
        levels = [intensity] if intensity else list(self.threats)
        for lvl in levels:
            for key, val in self.threats.get(lvl, {}).items():
                if key in _THREAT_REF_KEYS and isinstance(val, list):
                    out.extend(str(v) for v in val if str(v) not in out)
        return out


class Era(_Model):
    id: str
    name: str
    years: tuple[int, int]
    units: dict[str, dict[str, list[str]]] = Field(description="coalition -> role -> unit ids.")


class Airbase(_Model):
    theater: str
    name: str
    id: int
    x: float = Field(description="DCS map x (north), metres.")
    y: float = Field(description="DCS map y (east), metres.")
    lat: float
    lon: float
    runways: list[str] = Field(default_factory=list)
    civilian: bool = False
    uhf_mhz: float | None = None
    vhf_mhz: float | None = None
    distance_m: float | None = Field(default=None, description="Distance to `near`, if given.")


class Catalog(BaseModel):
    """All catalog data, loaded from one ``data/catalog`` directory."""

    model_config = ConfigDict(extra="forbid", frozen=True)

    root: Path
    units: dict[str, UnitType]
    templates: dict[str, GroupTemplate]
    packages: dict[str, Package]
    mission_types: dict[str, MissionType]
    eras: dict[str, Era]

    # ---- queries -------------------------------------------------------------------------

    def find_units(
        self,
        era: str | None = None,
        coalition: str | None = None,
        role: str | None = None,
        category: str | None = None,
    ) -> list[UnitType]:
        """Units matching all given filters; ``role`` matches the role or any tag."""
        if era is not None and era not in self.eras:
            raise CatalogLookupError("era", era, _close(era, self.eras))
        return [
            u
            for u in self.units.values()
            if (era is None or era in u.eras)
            and (coalition is None or coalition in u.coalitions)
            and (role is None or u.has_role(role))
            and (category is None or u.category == category)
        ]

    def unit(self, type_id: str) -> UnitType:
        try:
            return self.units[type_id]
        except KeyError:
            raise CatalogLookupError("unit", type_id, self.suggest(type_id, "unit")) from None

    def get_template(self, template_id: str) -> GroupTemplate:
        try:
            return self.templates[template_id]
        except KeyError:
            sugg = self.suggest(template_id, "template")
            raise CatalogLookupError("template", template_id, sugg) from None

    def get_package(self, package_id: str) -> Package:
        try:
            return self.packages[package_id]
        except KeyError:
            sugg = self.suggest(package_id, "package")
            raise CatalogLookupError("package", package_id, sugg) from None

    def find_templates(
        self,
        role: str | None = None,
        coalition: str | None = None,
        era: str | None = None,
        category: str | None = None,
    ) -> list[GroupTemplate]:
        return [
            t
            for t in self.templates.values()
            if (role is None or role == t.role or role in t.tags)
            and (coalition is None or t.coalition == coalition)
            and (era is None or era in t.eras)
            and (category is None or t.category == category)
        ]

    def mission_type(self, mission_type_id: str) -> MissionType:
        key = mission_type_id.strip().upper().replace("-", "_").replace(" ", "_")
        try:
            return self.mission_types[key]
        except KeyError:
            sugg = self.suggest(mission_type_id, "mission_type")
            raise CatalogLookupError("mission type", mission_type_id, sugg) from None

    def suggest(
        self, name: str, kind: SuggestKind, *, theater: str | None = None, n: int = 5
    ) -> list[str]:
        """Close matches for ``name`` among ids of ``kind`` (difflib, case-insensitive)."""
        pool: list[str]
        if kind == "unit":
            pool = list(self.units)
            pool += [u.name for u in self.units.values()]
        elif kind == "template":
            pool = list(self.templates)
        elif kind == "package":
            pool = list(self.packages)
        elif kind == "mission_type":
            pool = list(self.mission_types)
        elif kind == "era":
            pool = list(self.eras)
        elif kind == "theater":
            pool = list_theaters()
        elif kind == "airbase":
            if theater is None:
                raise ValueError("suggest(kind='airbase') needs theater=")
            pool = [a.name for a in _airbases(_theater_class(theater))]
        else:  # pragma: no cover - guarded by Literal
            raise ValueError(f"unknown kind {kind!r}")
        matches = _close(name, pool, n=n)
        if kind == "unit":  # map display names back to ids, keep order, dedupe
            by_name = {u.name: u.id for u in self.units.values()}
            matches = list(dict.fromkeys(by_name.get(m, m) for m in matches))
        return matches


# ---- loading -------------------------------------------------------------------------------


def _default_root() -> Path:
    env = os.environ.get("DMS_CATALOG_DIR")
    if env:
        return Path(env)
    here = Path(__file__).resolve()
    for parent in here.parents:
        cand = parent / "data" / "catalog"
        if (cand / "unit_types.yaml").is_file():
            return cand
    raise FileNotFoundError("data/catalog not found; pass root= or set DMS_CATALOG_DIR")


def _read(path: Path) -> dict[str, Any]:
    with path.open(encoding="utf-8") as fh:
        data = yaml.safe_load(fh)
    if not isinstance(data, dict):
        raise ValueError(f"{path}: expected a mapping at top level")
    return data


@lru_cache(maxsize=8)
def _load(root: Path) -> Catalog:
    units_raw = _read(root / "unit_types.yaml")["units"]
    units = {u["id"]: UnitType(**u) for u in units_raw}
    if len(units) != len(units_raw):
        raise ValueError("unit_types.yaml: duplicate unit ids")
    tpl_raw = _read(root / "group_templates.yaml")
    templates = {k: GroupTemplate(id=k, **v) for k, v in tpl_raw["templates"].items()}
    packages = {k: Package(id=k, **v) for k, v in (tpl_raw.get("packages") or {}).items()}
    mt_raw = _read(root / "mission_types.yaml")["mission_types"]
    mission_types = {k: MissionType(id=k, **v) for k, v in mt_raw.items()}
    eras_raw = _read(root / "eras.yaml")["eras"]
    eras = {k: Era(id=k, **v) for k, v in eras_raw.items()}
    return Catalog(
        root=root,
        units=units,
        templates=templates,
        packages=packages,
        mission_types=mission_types,
        eras=eras,
    )


def load_catalog(root: str | Path | None = None) -> Catalog:
    """Load (and cache) the catalog from ``root`` (default: ``data/catalog`` found upward)."""
    path = Path(root) if root is not None else _default_root()
    return _load(path.resolve())


# ---- module-level conveniences (default catalog) -------------------------------------------


def find_units(
    era: str | None = None,
    coalition: str | None = None,
    role: str | None = None,
    category: str | None = None,
) -> list[UnitType]:
    return load_catalog().find_units(era=era, coalition=coalition, role=role, category=category)


def get_template(template_id: str) -> GroupTemplate:
    return load_catalog().get_template(template_id)


def mission_type(mission_type_id: str) -> MissionType:
    return load_catalog().mission_type(mission_type_id)


def suggest(name: str, kind: SuggestKind, *, theater: str | None = None, n: int = 5) -> list[str]:
    return load_catalog().suggest(name, kind, theater=theater, n=n)


# ---- airbases (pydcs terrain) --------------------------------------------------------------


def list_theaters() -> list[str]:
    """Theater names accepted by :func:`find_airbases`."""
    return sorted(set(_THEATERS.values()))


def _theater_class(theater: str) -> str:
    key = theater.replace(" ", "").replace("_", "").replace("-", "").lower()
    if key not in _THEATERS:
        raise CatalogLookupError("theater", theater, _close(theater, list_theaters()))
    return _THEATERS[key]


@lru_cache(maxsize=16)
def _airbases(class_name: str) -> tuple[Airbase, ...]:
    try:
        import dcs.terrain
    except ImportError as exc:  # pragma: no cover - environment dependent
        raise RuntimeError("airbase lookup needs pydcs (`dcs`); install dms-gen") from exc
    terrain = getattr(dcs.terrain, class_name)()
    out = []
    for ap in terrain.airports.values():
        ll = ap.position.latlng()
        radio = getattr(ap, "atc_radio", None)
        out.append(
            Airbase(
                theater=class_name,
                name=ap.name,
                id=int(ap.id),
                x=float(ap.position.x),
                y=float(ap.position.y),
                lat=float(ll.lat),
                lon=float(ll.lng),
                runways=[str(getattr(r, "name", r)) for r in ap.runways],
                civilian=bool(getattr(ap, "civilian", False)),
                uhf_mhz=radio.uhf_hz / 1e6 if radio and radio.uhf_hz else None,
                vhf_mhz=radio.vhf_high_hz / 1e6 if radio and radio.vhf_high_hz else None,
            )
        )
    return tuple(sorted(out, key=lambda a: a.name))


def find_airbases(
    theater: str,
    near: str | tuple[float, float] | None = None,
    *,
    limit: int | None = None,
    max_distance_m: float | None = None,
) -> list[Airbase]:
    """Airbases on ``theater`` (pydcs data), optionally sorted by distance to ``near``.

    ``near`` is an airbase name (fuzzy-matched) or a DCS map ``(x, y)`` tuple in metres.
    Results carry ``distance_m`` when ``near`` is given.
    """
    bases = list(_airbases(_theater_class(theater)))
    if near is None:
        return bases[:limit] if limit else bases
    if isinstance(near, str):
        by_name = {a.name.lower(): a for a in bases}
        ref = by_name.get(near.lower())
        if ref is None:
            cands = _close(near, [a.name for a in bases])
            if not cands:
                raise CatalogLookupError("airbase", near, [])
            ref = by_name[cands[0].lower()]
        origin = (ref.x, ref.y)
    else:
        origin = (float(near[0]), float(near[1]))
    ranked = sorted(
        (a.model_copy(update={"distance_m": math.dist(origin, (a.x, a.y))}) for a in bases),
        key=lambda a: a.distance_m or 0.0,
    )
    if max_distance_m is not None:
        ranked = [a for a in ranked if (a.distance_m or 0.0) <= max_distance_m]
    return ranked[:limit] if limit else ranked


# ---- helpers -------------------------------------------------------------------------------


def _close(name: str, pool: Any, n: int = 5, cutoff: float = 0.5) -> list[str]:
    items = [str(p) for p in pool]
    lowered = {p.lower(): p for p in items}
    q = name.lower()
    hits = difflib.get_close_matches(q, list(lowered), n=n, cutoff=cutoff)
    subs = [p for lp, p in lowered.items() if q and q in lp and p not in hits]
    out = [lowered[h] for h in hits] + subs
    return list(dict.fromkeys(out))[:n]
