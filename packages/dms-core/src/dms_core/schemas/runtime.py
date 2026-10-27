# ruff: noqa: E501
"""RuntimeConfig: Python model of the DMS_CONFIG Lua table (see docs/CONTRACTS.md).

Field names are snake_case here and camelCase in Lua. Only *field names* are converted; keys of
user maps (template/zone/pool/voice ids, outcome keys) are preserved as authored.
"""

from __future__ import annotations

import importlib
import json
import re
from collections.abc import Callable
from typing import Annotated, Any, Literal

from pydantic import BaseModel, Field

from ._common import DMSModel, Ident, Skill
from .beats import Beat


class Budgets(DMSModel):
    """Hard caps on live units and spawn rate."""

    max_active_ground: int = Field(default=150, ge=0, description="Max active ground units.")
    max_active_air: int = Field(default=16, ge=0, description="Max active air units.")
    spawns_per_min: float = Field(default=3, ge=0, description="Max spawns per minute.")


class Adapt(DMSModel):
    """Clamp for hidden difficulty adaptation, in skill tiers."""

    min: int = Field(default=-1, ge=-3, le=0, description="Lowest tier offset.")
    max: int = Field(default=1, ge=0, le=3, description="Highest tier offset.")


class Director(DMSModel):
    """Intensity director settings."""

    enabled: bool = Field(default=True, description="Run the director.")
    peak: float = Field(default=70, ge=0, le=100, description="Intensity that triggers RELAX.")
    relax_sec: tuple[float, float] = Field(
        default=(40, 90), description="[min, max] RELAX duration."
    )
    decay_per_sec: float = Field(default=1.5, ge=0, description="Intensity decay per second.")
    adapt: Adapt = Field(default_factory=Adapt, description="Hidden difficulty clamp.")


class TemplateUnit(DMSModel):
    """One unit within a group template, offset from the group anchor (meters)."""

    type: str = Field(description="DCS unit type id, e.g. 'Osa 9A33 ln'.")
    dx: float = Field(default=0, description="Offset north (DCS x), meters.")
    dy: float = Field(default=0, description="Offset east (DCS y), meters.")
    heading: float = Field(default=0, description="Heading in radians.")


class Template(DMSModel):
    """A spawnable group template."""

    country: str = Field(description="DCS country name, e.g. 'RUSSIA'.")
    category: Literal["ground", "air", "ship"] = Field(description="Group category.")
    skill: Skill = Field(default="Good", description="AI skill.")
    units: list[TemplateUnit] = Field(min_length=1, description="Units in the group.")


class XY(DMSModel):
    """DCS map coordinates (x = north, y = east, meters)."""

    x: float = Field(description="DCS x (north), meters.")
    y: float = Field(description="DCS y (east), meters.")


class CircleZone(DMSModel):
    """Circular zone."""

    kind: Literal["circle"] = Field(default="circle", description="Zone shape.")
    x: float = Field(description="Center DCS x.")
    y: float = Field(description="Center DCS y.")
    radius: float = Field(gt=0, description="Radius in meters.")


class PolygonZone(DMSModel):
    """Polygon zone."""

    kind: Literal["polygon"] = Field(default="polygon", description="Zone shape.")
    points: list[XY] = Field(min_length=3, description="Vertices in DCS x/y.")


Zone = Annotated[CircleZone | PolygonZone, Field(discriminator="kind")]


class PoolMember(DMSModel):
    """Weighted reference to a template."""

    tpl: Ident = Field(description="Template id.")
    w: float = Field(default=1, gt=0, description="Weight.")


class Pool(DMSModel):
    """Weighted template pool."""

    members: list[PoolMember] = Field(min_length=1, description="Weighted templates.")
    pick: tuple[int, int] = Field(default=(1, 1), description="[min, max] groups per draw.")
    zones: list[Ident] = Field(min_length=1, description="Zone ids to spawn in.")


class EncounterTrigger(DMSModel):
    """When an encounter starts."""

    type: Literal["proximity", "beat", "director", "time"] = Field(description="Trigger kind.")
    zone: Ident | None = Field(default=None, description="Zone id (proximity).")
    radius_m: float | None = Field(default=None, gt=0, description="Radius in meters (proximity).")
    beat: Ident | None = Field(default=None, description="Beat id (beat).")
    after_sec: float | None = Field(default=None, ge=0, description="Seconds after start (time).")


class Encounter(DMSModel):
    """A runtime encounter."""

    id: Ident = Field(description="Encounter id.")
    kind: Literal["ambush_sam", "waves", "hunt", "convoy", "cap", "pool"] = Field(
        description="Encounter behaviour."
    )
    pool: Ident = Field(description="Pool id.")
    trigger: EncounterTrigger = Field(description="Start condition.")
    chance: int = Field(default=100, ge=0, le=100, description="Percent chance per play.")
    telegraph: str | None = Field(default=None, description="Warning, e.g. 'beat:sam_spike'.")
    hunt: bool = Field(default=False, description="Spawned groups hunt players.")
    waves: int | None = Field(default=None, ge=1, description="Wave count (kind=waves).")
    gap_sec: tuple[float, float] | None = Field(default=None, description="[min, max] wave gap.")


class VoiceEntry(DMSModel):
    """Rendered audio for a voice line id."""

    file: str = Field(description="File name inside the .miz (l10n/DEFAULT/).")
    text: str = Field(description="Subtitle text.")
    dur_sec: float = Field(gt=0, description="Duration in seconds.")
    speaker: Ident = Field(description="Character id.")


class Intel(DMSModel):
    """Fog-of-war / intel settings."""

    fog_of_war: bool = Field(default=True, description="Hide enemies; reveal by F10 marks.")
    reveal_radius_m: float = Field(default=5000, gt=0, description="Detection reveal radius.")
    mark_refresh_sec: float = Field(default=15, gt=0, description="Mark refresh interval.")
    stale_sec: float = Field(default=120, gt=0, description="Mark goes stale after this long.")


class Players(DMSModel):
    """Player side."""

    coalition: Literal[1, 2] = Field(default=2, description="1 = red, 2 = blue.")


class RuntimeConfig(DMSModel):
    """DMS_CONFIG: everything the Lua runtime needs; generated by `dms plan`."""

    version: Literal[1] = Field(default=1, description="Config format version.")
    seed: int = Field(default=0, description="Planner seed; Lua mixes it with timer entropy.")
    debug: bool = Field(default=False, description="Enable DMS debug logging.")
    mission_id: Ident = Field(description="Mission id, echoed in [DMS.OUTCOME] lines.")
    budgets: Budgets = Field(default_factory=Budgets, description="Unit/spawn caps.")
    director: Director = Field(default_factory=Director, description="Pacing director.")
    templates: dict[str, Template] = Field(
        default_factory=dict, description="Template id -> template."
    )
    zones: dict[str, Zone] = Field(default_factory=dict, description="Zone id -> zone.")
    pools: dict[str, Pool] = Field(default_factory=dict, description="Pool id -> pool.")
    encounters: list[Encounter] = Field(default_factory=list, description="Encounters.")
    beats: list[Beat] = Field(default_factory=list, description="Compiled beats (beats.yaml).")
    voice: dict[str, VoiceEntry] = Field(default_factory=dict, description="Line id -> audio.")
    intel: Intel = Field(default_factory=Intel, description="Fog of war / intel.")
    players: Players = Field(default_factory=Players, description="Player side.")

    def to_lua_table(self) -> dict[str, Any]:
        """Plain dict with camelCase field names (user map keys preserved), None values dropped."""
        result = _to_lua(self)
        assert isinstance(result, dict)
        return result

    def to_lua_source(self) -> str:
        """Lua source text: 'DMS_CONFIG = {...}'."""
        table = self.to_lua_table()
        dumps: Callable[[Any], str]
        try:
            dumps = importlib.import_module("dms_core.luaio").dumps
        except (ImportError, AttributeError):  # pragma: no cover - only while luaio is missing
            dumps = _fallback_dumps
        return "DMS_CONFIG = " + dumps(table)


def snake_to_camel(name: str) -> str:
    """'max_active_ground' -> 'maxActiveGround'."""
    head, *rest = name.split("_")
    return head + "".join(p[:1].upper() + p[1:] for p in rest)


def _to_lua(value: Any) -> Any:
    if isinstance(value, BaseModel):
        out: dict[str, Any] = {}
        for name in type(value).model_fields:
            v = getattr(value, name)
            if v is None:
                continue
            out[snake_to_camel(name)] = _to_lua(v)
        return out
    if isinstance(value, dict):
        return {k: _to_lua(v) for k, v in value.items() if v is not None}
    if isinstance(value, list | tuple):
        return [_to_lua(v) for v in value if v is not None]
    return value


_LUA_IDENT = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*$")
_LUA_KEYWORDS = frozenset(
    [
        "and",
        "break",
        "do",
        "else",
        "elseif",
        "end",
        "false",
        "for",
        "function",
        "if",
        "in",
        "local",
        "nil",
        "not",
        "or",
        "repeat",
        "return",
        "then",
        "true",
        "until",
        "while",
    ]
)


def _fallback_dumps(obj: Any) -> str:
    """Minimal Lua table-literal serializer, used only if dms_core.luaio is missing."""
    if obj is None:
        return "nil"
    if isinstance(obj, bool):
        return "true" if obj else "false"
    if isinstance(obj, int | float):
        return repr(obj)
    if isinstance(obj, str):
        # JSON escapes (\" \\ \n \t) are valid Lua; keep non-ASCII raw (Lua 5.1 lacks unicode escapes).
        return json.dumps(obj, ensure_ascii=False)
    if isinstance(obj, list | tuple):
        return "{" + ", ".join(_fallback_dumps(v) for v in obj) + "}"
    if isinstance(obj, dict):
        parts = []
        for k, v in obj.items():
            if isinstance(k, str) and _LUA_IDENT.match(k) and k not in _LUA_KEYWORDS:
                key = k
            else:
                key = f"[{_fallback_dumps(k)}]"
            parts.append(f"{key} = {_fallback_dumps(v)}")
        return "{" + ", ".join(parts) + "}"
    raise TypeError(f"cannot serialize {type(obj).__name__} to Lua")
