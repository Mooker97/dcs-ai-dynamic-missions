# ruff: noqa: E501
"""Shared base model, closed vocabularies and small reusable models for DMS schemas."""

from __future__ import annotations

from typing import Annotated, Literal, get_args

from pydantic import BaseModel, ConfigDict, Field


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


class Requires(DMSModel):
    """Preconditions. ALL listed conditions must hold. Empty means 'always eligible'."""

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
