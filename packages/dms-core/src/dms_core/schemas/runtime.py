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
from types import UnionType
from typing import Annotated, Any, Literal, Union, get_args, get_origin

from pydantic import BaseModel, Field, model_validator

from ._common import DirectorState, DMSModel, Ident, Skill
from .beats import Beat

Range = float | tuple[float, float]
"""A number or a [min, max] pair; Lua rolls a uniform value (DMS.Rng.range)."""


class Budgets(DMSModel):
    """Hard caps on live units and spawn rate."""

    max_active_ground: int = Field(default=150, ge=0, description="Max active ground units.")
    max_active_air: int = Field(default=16, ge=0, description="Max active air units.")
    spawns_per_min: float = Field(default=3, ge=0, description="Max spawns per minute.")
    max_active_ship: int | None = Field(
        default=None, ge=0, description="Max active ship units (unset = unlimited)."
    )


class Adapt(DMSModel):
    """Clamp for hidden difficulty adaptation, in skill tiers."""

    min: int = Field(default=-1, ge=-3, le=0, description="Lowest tier offset.")
    max: int = Field(default=1, ge=0, le=3, description="Highest tier offset.")


class DirectorGain(DMSModel):
    """Intensity added per event (unset keys keep the runtime defaults)."""

    hit: float | None = Field(default=None, ge=0, description="Player hit (default 25).")
    near_shot: float | None = Field(
        default=None, ge=0, description="Enemy shot near a player (default 5)."
    )
    sam_launch: float | None = Field(
        default=None, ge=0, description="Ground launch near a player (default 15)."
    )
    near_kill: float | None = Field(
        default=None, ge=0, description="Kill near a player (default 8)."
    )
    player_dead: float | None = Field(default=None, ge=0, description="Player killed (default 40).")


class Director(DMSModel):
    """Intensity director settings."""

    enabled: bool = Field(default=True, description="Run the director.")
    peak: float = Field(default=70, ge=0, le=100, description="Intensity that triggers RELAX.")
    relax_sec: tuple[float, float] = Field(
        default=(40, 90), description="[min, max] RELAX duration."
    )
    decay_per_sec: float = Field(default=1.5, ge=0, description="Intensity decay per second.")
    adapt: Adapt = Field(default_factory=Adapt, description="Hidden difficulty clamp.")
    peak_hold_sec: float | None = Field(
        default=None, ge=0, description="Seconds held in PEAK before RELAX (default 15)."
    )
    max_intensity: float | None = Field(
        default=None, gt=0, description="Intensity ceiling (default 100)."
    )
    near_m: float | None = Field(
        default=None, gt=0, description="'Near a player' radius for shots/kills (default 10000)."
    )
    calm_sec: float | None = Field(
        default=None, gt=0, description="Calm stretch that nudges difficulty up (default 300)."
    )
    gain: DirectorGain | None = Field(default=None, description="Intensity gains per event.")


class TemplateUnit(DMSModel):
    """One unit within a group template, offset from the group anchor (meters)."""

    type: str = Field(description="DCS unit type id, e.g. 'Osa 9A33 ln'.")
    dx: float = Field(default=0, description="Offset north (DCS x), meters.")
    dy: float = Field(default=0, description="Offset east (DCS y), meters.")
    heading: float = Field(
        default=0, description="Heading in DEGREES, relative to the group heading."
    )
    skill: Skill | None = Field(default=None, description="Per-unit skill override.")
    payload: dict[str, Any] | None = Field(
        default=None, description="DCS payload table for aircraft units."
    )
    livery: str | None = Field(default=None, description="Livery id.")


class Template(DMSModel):
    """A spawnable group template."""

    country: str = Field(description="DCS country name, e.g. 'RUSSIA'.")
    category: Literal["ground", "air", "airplane", "helicopter", "ship"] = Field(
        description="Group category ('air' = airplane)."
    )
    skill: Skill = Field(default="Good", description="AI skill.")
    units: list[TemplateUnit] = Field(min_length=1, description="Units in the group.")
    task: str | None = Field(
        default=None, description="DCS group task, e.g. 'CAP' (default by category)."
    )
    alt_m: float | None = Field(default=None, ge=0, description="Spawn altitude for air groups.")


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
    pick: tuple[int, int] | int = Field(
        default=(1, 1), description="[min, max] groups per draw (or a fixed count)."
    )
    zones: list[Ident] = Field(min_length=1, description="Zone ids to spawn in.")


class EncounterTrigger(DMSModel):
    """When an encounter starts."""

    type: Literal["proximity", "beat", "director", "time", "event", "manual"] = Field(
        description="Trigger kind. manual: only started by a beat effect / DMS.Encounters.trigger."
    )
    zone: Ident | None = Field(default=None, description="Zone id (proximity).")
    radius_m: float | None = Field(
        default=None,
        gt=0,
        description="Radius in meters around the zone centre/point (proximity); unset = inside the zone.",
    )
    beat: Ident | None = Field(default=None, description="Beat id (beat).")
    after_sec: Range | None = Field(
        default=None, description="Seconds after start, or [min, max] (time)."
    )
    state: DirectorState | None = Field(default=None, description="Director state (director).")
    event: str | None = Field(default=None, description="Bus event name (event).")
    group: str | None = Field(default=None, description="Event payload group filter (event).")
    coalition: Literal[0, 1, 2] | None = Field(
        default=None,
        description="proximity: coalition whose units count (default players); event: payload filter.",
    )
    point: XY | None = Field(
        default=None, description="Centre point instead of a zone (proximity)."
    )
    check_sec: float | None = Field(
        default=None, gt=0, description="Proximity poll interval (default 5)."
    )


class Encounter(DMSModel):
    """A runtime encounter."""

    id: Ident = Field(description="Encounter id.")
    kind: Literal["ambush_sam", "waves", "hunt", "convoy", "cap", "pool"] = Field(
        description="Encounter behaviour."
    )
    pool: Ident | None = Field(
        default=None, description="Pool id (one of pool / template / group is required)."
    )
    trigger: EncounterTrigger = Field(description="Start condition.")
    chance: int = Field(default=100, ge=0, le=100, description="Percent chance per play.")
    telegraph: str | None = Field(
        default=None,
        description="Warning: 'beat:<id>' (asks narrative to fire that beat), 'event:<name>' or '<name>'.",
    )
    hunt: bool | str = Field(
        default=False, description="Spawned groups hunt players (true) or this named group."
    )
    waves: int | tuple[int, int] | None = Field(
        default=None, description="Wave count or [min, max] (kind=waves)."
    )
    gap_sec: tuple[float, float] | None = Field(default=None, description="[min, max] wave gap.")
    once: bool | None = Field(default=None, description="Fire at most once (default true).")
    engage_radius_m: float | None = Field(
        default=None,
        gt=0,
        description="ambush_sam: player distance that arms the site (default 15000).",
    )
    hot_chance: int | None = Field(
        default=None, ge=0, le=100, description="ambush_sam: percent chance an armed site goes hot."
    )
    telegraph_sec: Range | None = Field(
        default=None, description="Delay between telegraph and going hot (default [30, 60])."
    )
    react_sec: Range | None = Field(
        default=None, description="Go-hot delay without a telegraph (default [2, 8])."
    )
    check_sec: float | None = Field(
        default=None, gt=0, description="ambush_sam poll interval (default 2)."
    )
    gated: bool | None = Field(
        default=None, description="Ask the director before spawning (default true)."
    )
    cost: float | None = Field(default=None, gt=0, description="Spawn-budget cost (default 1).")
    max_defer_sec: float | None = Field(
        default=None,
        ge=0,
        description="Longest director deferral before spawning anyway (default 300).",
    )
    gate_retry_sec: float | None = Field(
        default=None, gt=0, description="Retry interval while deferred (default 15)."
    )
    hunt_interval_sec: float | None = Field(
        default=None, gt=0, description="Hunter re-route interval (default 30)."
    )
    hunt_speed: float | None = Field(
        default=None, gt=0, description="Hunter speed m/s (default 8)."
    )
    hunt_radius_m: float | None = Field(
        default=None, gt=0, description="Hunters only chase players within this radius."
    )
    target: str | None = Field(
        default=None, description="Group name hunters chase instead of players."
    )
    spawn_zone: Ident | None = Field(
        default=None, description="Spawn in this zone instead of the pool's zones."
    )
    template: Ident | None = Field(default=None, description="Template id (when no pool).")
    zone: Ident | None = Field(default=None, description="Zone for a template spawn.")
    group: str | None = Field(
        default=None, description="convoy: existing (mission editor) group to use as the convoy."
    )
    destination: Ident | XY | None = Field(
        default=None, description="convoy: zone id or point the convoy drives to."
    )
    resume_after_sec: Range | None = Field(
        default=None, description="convoy: resume delay after being hit (default [60, 120])."
    )
    escort_radius_m: float | None = Field(
        default=None, gt=0, description="convoy: escort scatter radius (default 500)."
    )
    speed: float | None = Field(default=None, gt=0, description="convoy speed m/s (default 10).")
    action: str | None = Field(
        default=None, description="convoy route action, e.g. 'On Road' (default) or 'Off Road'."
    )

    @model_validator(mode="after")
    def _source(self) -> Encounter:
        if self.pool is None and self.template is None and self.group is None:
            raise ValueError(f"encounter '{self.id}' needs one of pool, template or group")
        return self


class VoiceTurn(DMSModel):
    """One speaker's part of a multi-speaker voice file."""

    speaker: Ident = Field(description="Character id.")
    text: str = Field(description="Subtitle text for this turn.")


class VoiceEntry(DMSModel):
    """Rendered audio for a voice line id."""

    file: str | None = Field(
        default=None,
        description="File name inside the .miz (l10n/DEFAULT/); omit for subtitle-only lines.",
    )
    text: str = Field(description="Subtitle text.")
    dur_sec: float = Field(gt=0, description="Duration in seconds.")
    speaker: Ident = Field(description="Character id.")
    turns: list[VoiceTurn] | None = Field(
        default=None,
        description="Multi-speaker exchange in this one file; subtitles show one line per turn.",
    )


class Speaker(DMSModel):
    """Radio identity of a character."""

    callsign: str = Field(description="Callsign shown in subtitles, e.g. 'Kestrel Two-Two'.")
    frequency: float | None = Field(
        default=None, gt=0, description="Transmit frequency in MHz (unset = coalition-wide audio)."
    )
    modulation: Literal[0, 1] | None = Field(default=None, description="0 = AM, 1 = FM.")


class NarrativeSettings(DMSModel):
    """Beat engine pacing."""

    min_gap_sec: float = Field(default=8, ge=0, description="Minimum seconds between beats.")
    pending_ttl_sec: float = Field(
        default=45, gt=0, description="Triggered beats wait this long for their requires."
    )
    zone_poll_sec: float = Field(default=3, gt=0, description="Player zone polling interval.")


class Intel(DMSModel):
    """Fog-of-war / intel settings."""

    fog_of_war: bool = Field(default=True, description="Hide enemies; reveal by F10 marks.")
    reveal_radius_m: float = Field(default=5000, gt=0, description="Detection reveal radius.")
    mark_refresh_sec: float = Field(default=15, gt=0, description="Mark refresh interval.")
    stale_sec: float = Field(default=120, gt=0, description="Mark goes stale after this long.")
    scan_sec: float | None = Field(
        default=None, gt=0, description="Detection scan interval (default 5)."
    )
    remove_sec: float | None = Field(
        default=None,
        gt=0,
        description="Stale marks are removed after this long (default 3x stale_sec).",
    )
    mark_radius_m: float | None = Field(
        default=None, gt=0, description="Contact circle radius (default 600)."
    )
    sensors: bool | None = Field(
        default=None, description="Also reveal what player-side sensors detect (default true)."
    )


class Players(DMSModel):
    """Player side."""

    coalition: Literal[1, 2] = Field(default=2, description="1 = red, 2 = blue.")


class TestCheck(DMSModel):
    """One in-mission assertion for a headless test run (lua/src/dms/test.lua)."""

    kind: Literal[
        "booted", "spawns", "beats_in_order", "beat", "comms", "encounter", "convoy_halt", "outcome"
    ] = Field(description="Check kind.")
    name: str | None = Field(default=None, description="Name in [DMS.TEST] lines (default kind).")
    deadline_sec: float | None = Field(
        default=None, ge=0, description="Model seconds after start before a pending check fails."
    )
    min: int | None = Field(default=None, ge=0, description="spawns / comms: minimum count.")
    beats: list[Ident] | None = Field(
        default=None, description="beats_in_order: beat ids expected in this order."
    )
    id: Ident | None = Field(default=None, description="beat / encounter: the id to watch.")
    result: Literal["success", "failure"] | None = Field(
        default=None, description="outcome: expected end result (unset = any end)."
    )


class TestSettings(DMSModel):
    """DMS_CONFIG.test: headless test mode, set only by `dms build --test` (dms_test.lua)."""

    enabled: bool = Field(default=True, description="false keeps test mode inert.")
    player_proxy: str | None = Field(
        default=None, description="AI group name treated as the player by every module."
    )
    minutes: float | None = Field(
        default=None,
        gt=0,
        description="Model minutes; pending checks fail and DONE is logged then.",
    )
    checks: list[TestCheck] = Field(default_factory=list, description="Assertions to run.")


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
    qualities: dict[str, float] = Field(
        default_factory=dict,
        description="Campaign quality values at plan time (state/qualities.yaml); seed beat requires.",
    )
    speakers: dict[str, Speaker] = Field(
        default_factory=dict, description="Character id -> radio identity."
    )
    narrative: NarrativeSettings | None = Field(
        default=None, description="Beat engine pacing (unset = runtime defaults)."
    )
    test: TestSettings | None = Field(
        default=None, description="Headless test mode (only in `dms build --test` builds)."
    )

    @classmethod
    def from_lua_table(cls, table: Any) -> RuntimeConfig:
        """Validate a DMS_CONFIG table read back from Lua (camelCase field names)."""
        return cls.model_validate(from_lua(cls, table))

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


def from_lua(annotation: Any, value: Any) -> Any:
    """Inverse of the camelCase conversion, guided by the model type ``annotation``.

    Renames camelCase *field names* back to snake_case (user map keys are kept) and turns empty
    Lua tables into ``[]`` / ``{}`` as the field type expects. Unknown keys are left alone so
    ``extra="forbid"`` still reports them.
    """
    origin = get_origin(annotation)
    if origin is Annotated:
        return from_lua(get_args(annotation)[0], value)
    if origin in (Union, UnionType):
        args = get_args(annotation)
        models = [a for a in args if isinstance(a, type) and issubclass(a, BaseModel)]
        if isinstance(value, dict) and models:
            return _model_from_lua(models, value)
        for a in args:
            o = get_origin(a)
            if o in (list, tuple) or o is dict or o is Annotated:
                return from_lua(a, value)
        return value
    if isinstance(annotation, type) and issubclass(annotation, BaseModel):
        return _model_from_lua([annotation], value) if isinstance(value, dict) else value
    if origin is dict:
        if value == []:
            return {}
        if isinstance(value, dict):
            vt = get_args(annotation)[1] if get_args(annotation) else Any
            return {k: from_lua(vt, v) for k, v in value.items()}
        return value
    if origin in (list, tuple):
        if value == {}:
            return []
        if isinstance(value, list):
            items = [a for a in get_args(annotation) if a is not Ellipsis]
            if origin is tuple and len(items) == len(value):
                return [from_lua(a, v) for a, v in zip(items, value, strict=True)]
            et = items[0] if items else Any
            return [from_lua(et, v) for v in value]
    return value


def _model_from_lua(models: list[type[BaseModel]], value: dict[Any, Any]) -> dict[Any, Any]:
    fields: dict[str, tuple[str, Any]] = {}
    for m in models:
        for name, f in m.model_fields.items():
            fields.setdefault(name, (name, f.annotation))
            fields.setdefault(snake_to_camel(name), (name, f.annotation))
    out: dict[Any, Any] = {}
    for k, v in value.items():
        if isinstance(k, str) and k in fields:
            name, ann = fields[k]
            out[name] = from_lua(ann, v)
        else:
            out[k] = v
    return out


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
