# ruff: noqa: E501
"""Shared base model, closed vocabularies and small reusable models for DMS schemas."""

from __future__ import annotations

import re
from typing import Annotated, Any, Literal, get_args

from pydantic import BaseModel, ConfigDict, Field, model_validator


class DMSModel(BaseModel):
    """Base for every DMS schema model: unknown keys are rejected so typos surface early."""

    model_config = ConfigDict(extra="forbid", validate_assignment=True)


# ---------------------------------------------------------------------------
# Identifiers
# ---------------------------------------------------------------------------

Ident = Annotated[
    str,
    Field(
        pattern=r"^[A-Za-z0-9][A-Za-z0-9_.\-]*$",
        max_length=64,
        description=(
            "Stable identifier. Use lower_snake_case for authored ids (e.g. 'ops_mustang', "
            "'convoy_hit'); letters, digits, '_', '.', '-' only, no spaces."
        ),
    ),
]

# ---------------------------------------------------------------------------
# Closed vocabularies
# ---------------------------------------------------------------------------

Theater = Literal[
    "Caucasus",
    "Syria",
    "PersianGulf",
    "Nevada",
    "MarianaIslands",
    "Sinai",
    "Kola",
    "Afghanistan",
    "Normandy",
    "TheChannel",
    "Falklands",
    "GermanyCW",
]
THEATERS: tuple[str, ...] = get_args(Theater)

MissionType = Literal[
    "CAS",
    "SEAD",
    "DEAD",
    "CAP",
    "STRIKE",
    "ESCORT",
    "CSAR",
    "RECON",
    "TRANSPORT",
    "CONVOY_ESCORT",
]
MISSION_TYPES: tuple[str, ...] = get_args(MissionType)

ContentMode = Literal["historical", "adapted", "fictional"]
Coalition = Literal["blue", "red", "neutral"]
Skill = Literal["Average", "Good", "High", "Excellent", "Random"]
RadioFxPreset = Literal["uhf_clean", "vhf_noisy", "intercom", "none"]
Confidence = Literal["high", "medium", "low"]
DirectorState = Literal["BUILD_UP", "PEAK", "RELAX"]
CompareOp = Literal["==", "!=", ">", ">=", "<", "<="]

# Scalars allowed as outcome / flag values (they must survive the Lua JSON encoder).
OutcomeValue = bool | int | float | str


# ---------------------------------------------------------------------------
# Small reusable models
# ---------------------------------------------------------------------------


class LatLon(DMSModel):
    """A geographic point in WGS84 decimal degrees."""

    lat: float = Field(ge=-90, le=90, description="Latitude in decimal degrees (north positive).")
    lon: float = Field(ge=-180, le=180, description="Longitude in decimal degrees (east positive).")


class QualityCheck(DMSModel):
    """Compare a campaign quality (a named integer that persists across missions) to a value."""

    quality: Ident = Field(description="Quality id declared in the campaign arc, e.g. 'trust'.")
    op: CompareOp = Field(default=">=", description="Comparison operator.")
    value: float = Field(description="Value to compare the quality against.")


_QUALITY_SPEC = re.compile(r"^\s*(==|!=|~=|>=|<=|>|<|=)\s*(-?\d+(?:\.\d+)?)\s*$")
_OP_ALIASES = {"=": "==", "~=": "!="}


def _as_list(v: Any) -> list[Any]:
    if v is None:
        return []
    if isinstance(v, list | tuple):
        return list(v)
    return [v]


def _quality_checks(q: str, spec: Any) -> list[dict[str, Any]]:
    """Expand one Lua-style quality spec (number | '>=2' | {min,max} | {op,value}) into checks."""
    if isinstance(spec, bool):
        raise ValueError(f"quality '{q}': boolean is not a valid comparison")
    if isinstance(spec, int | float):
        return [{"quality": q, "op": ">=", "value": spec}]
    if isinstance(spec, str):
        m = _QUALITY_SPEC.match(spec)
        if not m:
            raise ValueError(f"quality '{q}': cannot parse comparison '{spec}' (use e.g. '>=2')")
        return [
            {
                "quality": q,
                "op": _OP_ALIASES.get(m.group(1), m.group(1)),
                "value": float(m.group(2)),
            }
        ]
    if isinstance(spec, dict):
        if "op" in spec:
            op = _OP_ALIASES.get(str(spec["op"]), spec["op"])
            return [{"quality": q, "op": op, "value": spec.get("value")}]
        out: list[dict[str, Any]] = []
        if "min" in spec:
            out.append({"quality": q, "op": ">=", "value": spec["min"]})
        if "max" in spec:
            out.append({"quality": q, "op": "<=", "value": spec["max"]})
        if "eq" in spec:
            out.append({"quality": q, "op": "==", "value": spec["eq"]})
        if out:
            return out
    raise ValueError(f"quality '{q}': unsupported comparison {spec!r}")


class Requires(DMSModel):
    """Preconditions. ALL listed conditions must hold. Empty means 'always eligible'.

    Canonical form uses lists. Lua-style aliases are accepted and normalised: ``flags`` as a map
    ``{flag: true|false}``, ``flags_set`` (= flags), ``not_flags`` / ``flags_not_set`` (= flags_not)
    and ``qualities`` as a map ``{trust: 2 | '>=2' | {min: 1, max: 3} | {op: '<', value: 0}}``.
    """

    flags: list[Ident] = Field(
        default_factory=list, description="Flags that must be set (true) for this to apply."
    )
    flags_not: list[Ident] = Field(default_factory=list, description="Flags that must NOT be set.")
    qualities: list[QualityCheck] = Field(
        default_factory=list,
        description="Quality comparisons, e.g. [{quality: trust, op: '>=', value: 2}].",
    )
    beats_fired: list[Ident] = Field(
        default_factory=list, description="Beat ids that must already have fired this mission."
    )
    beats_not_fired: list[Ident] = Field(
        default_factory=list, description="Beat ids that must NOT have fired yet."
    )
    chance: int = Field(
        default=100,
        ge=0,
        le=100,
        description="Percent chance (rolled once per evaluation) that this is eligible. 100 = always.",
    )

    @model_validator(mode="before")
    @classmethod
    def _normalise_aliases(cls, data: Any) -> Any:
        if not isinstance(data, dict):
            return data
        d = dict(data)
        flags = _as_list(None)
        flags_not = _as_list(None)
        raw_flags = d.pop("flags", None)
        if isinstance(raw_flags, dict):
            for k, v in raw_flags.items():
                if v is True:
                    flags.append(k)
                elif v is False:
                    flags_not.append(k)
                else:
                    raise ValueError(f"flag '{k}': map form only supports true/false")
        else:
            flags.extend(_as_list(raw_flags))
        flags.extend(_as_list(d.pop("flags_set", None)))
        flags.extend(_as_list(d.pop("flagsSet", None)))
        flags_not.extend(_as_list(d.pop("flags_not", None)))
        for alias in ("flagsNot", "not_flags", "notFlags", "flags_not_set", "flagsNotSet"):
            flags_not.extend(_as_list(d.pop(alias, None)))
        if flags or raw_flags is not None:
            d["flags"] = list(dict.fromkeys(flags))
        if flags_not:
            d["flags_not"] = list(dict.fromkeys(flags_not))
        for camel, snake in (("beatsFired", "beats_fired"), ("beatsNotFired", "beats_not_fired")):
            if camel in d and snake not in d:
                d[snake] = d.pop(camel)
        q = d.get("qualities")
        if isinstance(q, dict):
            checks: list[dict[str, Any]] = []
            for name, spec in q.items():
                checks.extend(_quality_checks(str(name), spec))
            d["qualities"] = checks
        return d
