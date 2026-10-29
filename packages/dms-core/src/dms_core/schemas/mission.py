# ruff: noqa: E501
"""MissionSpec: the declarative, LLM-facing description of one mission (mission-spec.yaml).

Describe *areas by reference* and *forces by role*. Never write DCS x/y coordinates, unit ids or
group ids here; ``dms plan`` resolves areas to coordinates and roles to unit types (BuildPlan).
"""

from __future__ import annotations

import datetime as _dt
from typing import Annotated, Any, Literal

from pydantic import Field, model_validator

from ._common import (
    Coalition,
    ContentMode,
    DMSModel,
    EncounterKind,
    Ident,
    LatLon,
    MissionType,
    Skill,
    Theater,
)
from .beats import BeatTrigger

# ---------------------------------------------------------------------------
# Areas (by reference)
# ---------------------------------------------------------------------------


class NearAirbase(DMSModel):
    """An area around (or offset from) a DCS airbase."""

    kind: Literal["near_airbase"] = Field(
        default="near_airbase", description="Area reference type (discriminator)."
    )
    airbase: str = Field(
        description="Airbase name as DCS knows it, e.g. 'Incirlik', 'Hatay', 'Kutaisi'. Use find_airbase."
    )
    radius_nm: float = Field(default=3, gt=0, le=200, description="Area radius in nautical miles.")
    bearing_deg: float | None = Field(
        default=None, ge=0, lt=360, description="Optional true bearing to offset the area center."
    )
    distance_nm: float | None = Field(
        default=None, ge=0, le=300, description="Offset distance along bearing_deg."
    )


class NearNamedPlace(DMSModel):
    """An area around a town, landmark or map label."""

    kind: Literal["near_named_place"] = Field(
        default="near_named_place", description="Area reference type (discriminator)."
    )
    place: str = Field(
        description="Town or landmark name on the DCS map, e.g. 'Idlib', 'Jisr al-Shughur'."
    )
    radius_nm: float = Field(default=2, gt=0, le=200, description="Area radius in nautical miles.")
    bearing_deg: float | None = Field(
        default=None, ge=0, lt=360, description="Optional offset bearing."
    )
    distance_nm: float | None = Field(default=None, ge=0, le=300, description="Offset distance.")


class LatLonArea(DMSModel):
    """A circle around an explicit lat/lon. Use when no named place fits."""

    kind: Literal["latlon"] = Field(
        default="latlon", description="Area reference type (discriminator)."
    )
    lat: float = Field(ge=-90, le=90, description="Latitude, decimal degrees.")
    lon: float = Field(ge=-180, le=180, description="Longitude, decimal degrees.")
    radius_nm: float = Field(default=2, gt=0, le=200, description="Area radius in nautical miles.")


class PolygonArea(DMSModel):
    """A polygon zone given as lat/lon vertices (at least 3), in order."""

    kind: Literal["zone"] = Field(
        default="zone", description="Area reference type (discriminator)."
    )
    points: list[LatLon] = Field(min_length=3, description="Polygon vertices, clockwise or not.")


AreaRef = Annotated[
    NearAirbase | NearNamedPlace | LatLonArea | PolygonArea,
    Field(discriminator="kind"),
]


class Area(DMSModel):
    """A named area other parts of the spec refer to by id (objectives, threats, routes, pools)."""

    id: Ident = Field(description="Area id, e.g. 'ridge_north', 'fob_lion', 'hospital'.")
    description: str | None = Field(default=None, description="What this place is in the story.")
    where: AreaRef = Field(description="How to locate the area on the map.")
    terrain: Literal["any", "road", "open", "urban", "high_ground", "water"] = Field(
        default="any", description="Placement hint the planner uses when choosing spawn points."
    )


# ---------------------------------------------------------------------------
# Forces
# ---------------------------------------------------------------------------


class AirStart(DMSModel):
    """Where and how an air-start player flight appears (start_type 'air')."""

    altitude_ft: float = Field(
        default=20000, gt=0, le=60000, description="Start altitude in feet MSL (BARO)."
    )
    speed_kts: float = Field(
        default=420, gt=0, le=1200, description="Start speed in knots (true airspeed)."
    )
    distance_nm_before_first_wp: float = Field(
        default=20,
        ge=0,
        le=200,
        description="How far short of the first route point (IP / ingress area) the flight starts, NM.",
    )
    toward: Ident | None = Field(
        default=None,
        description="Area id of the first route point (IP). Null = the first area whose id names an IP (ip/ingress/push), else the first objective area. The flight starts on the line from start_area to it, heading toward it.",
    )


class PlayerFlight(DMSModel):
    """A flight of player aircraft (single-player 'player' lead + AI wingmen, or MP 'client' slots)."""

    callsign: str = Field(description="Flight callsign, e.g. 'Dustoff', 'Gunfighter'.")
    aircraft: str = Field(
        description="DCS aircraft type id, e.g. 'AH-64D_BLK_II', 'F-16C_50', 'UH-60L'. Use list_units."
    )
    count: int = Field(default=2, ge=1, le=4, description="Number of client slots in the flight.")
    coalition: Coalition = Field(default="blue", description="Side the players fly for.")
    country: str = Field(default="USA", description="DCS country of the aircraft.")
    start_area: Ident = Field(
        description="Area id where the flight starts (usually near_airbase/FARP)."
    )
    start_type: Literal["runway", "parking_hot", "parking_cold", "air"] = Field(
        default="parking_cold", description="How the flight starts."
    )
    loadout: str = Field(
        default="auto",
        description="Loadout intent, e.g. 'anti-armor: 8 Hellfire + rockets', or 'auto' for role default.",
    )
    frequency_mhz: float | None = Field(
        default=None, gt=0, description="Flight frequency in MHz; null lets the planner choose."
    )
    tasking: str | None = Field(default=None, description="What this flight is told to do.")
    variant: str | None = Field(
        default=None,
        pattern=r"^[a-z0-9][a-z0-9_-]*$",
        description="Start option, e.g. 'ramp' or 'air'. Flights with the same variant are built together; each distinct variant produces its own .miz '<id>-<variant>.miz'; flights without variant appear in every variant.",
    )
    slot: Literal["player", "client"] = Field(
        default="player",
        description="'player': lead unit is the single-player Player, the other count-1 units are AI wingmen (skill High) that spawn and fly in SP. 'client': all units are Client slots (multiplayer). One 'player' flight per variant.",
    )
    air_start: AirStart | None = Field(
        default=None,
        description="Air-start placement (start_type 'air' only; defaults apply when omitted): altitude_ft, speed_kts, distance_nm_before_first_wp, toward.",
    )

    @model_validator(mode="after")
    def _check_air_start(self) -> PlayerFlight:
        if self.air_start is not None and self.start_type != "air":
            raise ValueError("air_start is only valid with start_type 'air'")
        return self


ThreatRole = Literal[
    "sam_short",
    "sam_medium",
    "sam_long",
    "aaa",
    "manpads",
    "armor",
    "ifv",
    "technicals",
    "infantry",
    "artillery",
    "fighters",
    "attack_helicopters",
    "ship",
    "hvt",
    "civilian",
]
"""Threat roles. 'civilian' = unarmed civilian vehicles/people only (traffic, buses, farm trucks):
pair it with a neutral faction; the planner must never pick armed types for it."""


class Threat(DMSModel):
    """Static (pre-placed) enemy presence, described by role and area."""

    id: Ident = Field(description="Threat id, e.g. 'ridge_aaa'.")
    role: ThreatRole = Field(description="What kind of threat this is.")
    area: Ident = Field(description="Area id where it is placed.")
    strength: Literal["light", "medium", "heavy"] = Field(
        default="medium", description="Rough size; the planner maps it to unit counts."
    )
    faction: Ident | None = Field(
        default=None, description="Bible faction id; sets country/equipment."
    )
    skill: Skill = Field(default="Good", description="AI skill.")
    hidden_on_map: bool = Field(
        default=True, description="Hide on the F10 map until detected (fog of war)."
    )
    templates: list[str] = Field(
        default_factory=list,
        description="Pin the threat to these catalog template ids (e.g. ['sa8', 'sa8_section'] to guarantee a radar SAM / HARM target); the planner picks only among them. They must be templates for the role and era (dms catalog templates --role). Empty = any template for the role/era/faction.",
    )
    notes: str | None = Field(default=None, description="Placement or behaviour hints.")


SupportRole = Literal[
    "convoy",
    "friendly_ground",
    "jtac",
    "awacs",
    "tanker",
    "escort",
    "cap",
    "cas",
    "medevac",
    "farp",
]


class Support(DMSModel):
    """Friendly assets: convoys to protect, JTACs, AWACS, tankers, FARPs."""

    id: Ident = Field(description="Asset id, e.g. 'convoy_main'.")
    role: SupportRole = Field(description="Kind of friendly asset.")
    callsign: str | None = Field(default=None, description="Radio callsign, e.g. 'Ripper 2-1'.")
    area: Ident | None = Field(default=None, description="Area id where it is placed or starts.")
    route: list[Ident] = Field(
        default_factory=list,
        description="Ordered area ids for moving assets (convoys, orbits). First = start.",
    )
    composition: str | None = Field(
        default=None, description="Free-text composition, e.g. '4x M1126 Stryker, 2x HEMTT'."
    )
    faction: Ident | None = Field(
        default=None,
        description="Bible faction id (friendly side); its DCS country is used for the asset's units. Null = the speaker's faction if it is on the players' side, else the first country of the players' side.",
    )
    speaker: Ident | None = Field(
        default=None, description="Bible character who talks for this asset."
    )
    frequency_mhz: float | None = Field(
        default=None,
        gt=0,
        description="Radio frequency in MHz (AWACS/tanker: their tuned frequency in DCS; JTAC/ground: the speaker's radio, e.g. 41.5 FM).",
    )
    modulation: Literal["AM", "FM"] | None = Field(
        default=None,
        description="Radio modulation. Null = automatic: FM below 87.995 MHz (VHF-FM band, e.g. JTAC 30-88 MHz), else AM.",
    )
    tacan: str | None = Field(
        default=None,
        pattern=r"^([1-9]|[1-9][0-9]|1[0-1][0-9]|12[0-6])[XY]$",
        description="Tanker TACAN channel, e.g. '51Y'. Null = the builder default ('10X'). Ignored for other roles.",
    )


class Objective(DMSModel):
    """A mission objective, checkable at runtime via flags."""

    id: Ident = Field(description="Objective id, e.g. 'convoy_arrives'.")
    kind: Literal[
        "destroy", "protect", "escort", "reach", "recon", "rescue", "survive", "land", "troops"
    ] = Field(
        description=(
            "Objective type. troops (contract v0.9, not implemented yet): carry the friendly "
            "ground group `target` (a support id) from where it waits to `area` (the drop zone); "
            "succeeds when they are unloaded inside `area`."
        )
    )
    description: str = Field(description="Briefing text for this objective.")
    primary: bool = Field(default=True, description="Primary objectives decide success.")
    area: Ident | None = Field(default=None, description="Area id where it happens.")
    target: Ident | None = Field(
        default=None, description="Threat or support id this objective is about."
    )
    success_flag: Ident | None = Field(
        default=None, description="Flag a beat sets when the objective succeeds."
    )
    failure_flag: Ident | None = Field(
        default=None, description="Flag a beat sets when the objective fails."
    )


# ---------------------------------------------------------------------------
# Dynamic intent (compiled by the planner into DMS_CONFIG pools/encounters/director/intel)
# ---------------------------------------------------------------------------


class PoolIntent(DMSModel):
    """A weighted set of enemy group types that the runtime draws from."""

    id: Ident = Field(description="Pool id, e.g. 'aaa', 'qrf_btr'.")
    roles: list[ThreatRole] = Field(min_length=1, description="Roles the pool's templates fill.")
    areas: list[Ident] = Field(min_length=1, description="Area ids where pool members may spawn.")
    pick: tuple[int, int] = Field(
        default=(1, 3), description="[min, max] groups drawn each time the pool is used."
    )
    faction: Ident | None = Field(default=None, description="Bible faction id.")
    templates: list[str] | None = Field(
        default=None,
        description="Pin the pool to these catalog template ids (e.g. ['sa8', 'sa8_section'] to guarantee an SA-8); the runtime draws only among them. They must be templates for one of the pool's roles and the era (dms catalog templates --role). Null/empty = any template for the roles/era/faction.",
    )
    notes: str | None = Field(
        default=None, description="Weighting hints, e.g. 'mostly ZU-23, rare SA-8'."
    )


class EncounterTriggerIntent(DMSModel):
    """When an encounter starts."""

    type: Literal["proximity", "beat", "director", "time"] = Field(
        description="proximity: players near an area; beat: a beat fires; director: pacing; time: after N minutes."
    )
    area: Ident | None = Field(default=None, description="Area id (proximity).")
    radius_nm: float | None = Field(
        default=None, gt=0, description="Trigger radius in nm (proximity)."
    )
    beat: Ident | None = Field(default=None, description="Beat id (beat).")
    after_min: float | None = Field(default=None, ge=0, description="Minutes after start (time).")

    @model_validator(mode="after")
    def _check(self) -> EncounterTriggerIntent:
        need = {"proximity": "area", "beat": "beat", "time": "after_min"}.get(self.type)
        if need and getattr(self, need) is None:
            raise ValueError(f"trigger type '{self.type}' requires '{need}'")
        return self


class EncounterIntent(DMSModel):
    """A dynamic event: pop-up SAM, reinforcement waves, hunters, enemy CAP."""

    id: Ident = Field(description="Encounter id, e.g. 'popup_sam', 'qrf'.")
    kind: EncounterKind = Field(
        description=(
            "Encounter behaviour. artillery, csar and ground_war are contract v0.9 kinds "
            "(DMS.Encounters.registerKind, enc_<kind>.lua), not implemented yet: the runtime "
            "logs 'unknown kind' and skips them until they land."
        )
    )
    pool: Ident = Field(description="Pool id it draws from.")
    trigger: EncounterTriggerIntent = Field(description="What starts the encounter.")
    chance: int = Field(
        default=100, ge=0, le=100, description="Percent chance it happens per play."
    )
    telegraph_beat: Ident | None = Field(
        default=None,
        description="Beat that warns players 30-60 s before (e.g. RWR spike call). Strongly recommended.",
    )
    waves: int | None = Field(
        default=None, ge=1, le=10, description="Number of waves (kind=waves)."
    )
    gap_min: tuple[float, float] | None = Field(
        default=None, description="[min, max] minutes between waves."
    )
    hunt: bool = Field(default=False, description="Spawned groups actively hunt the players.")
    per_flight: bool | None = Field(
        default=None,
        description=(
            "Multiplayer (contract v0.9, not implemented yet): true = run once per player flight "
            "(a late joiner gets their own), within the director spawn budget. Unset/false = "
            "once per mission."
        ),
    )
    notes: str | None = Field(default=None, description="Design intent.")


class DirectorIntent(DMSModel):
    """AI-director pacing intent."""

    enabled: bool = Field(default=True, description="Use the intensity director.")
    intensity: Literal["calm", "moderate", "intense"] = Field(
        default="moderate", description="Target peak intensity."
    )
    adaptive: bool = Field(
        default=True, description="Allow hidden difficulty adaptation (clamped to +-1 tier)."
    )


class FogOfWarIntent(DMSModel):
    """Fog-of-war intent: enemies hidden until detected, then shown as F10 marks."""

    enabled: bool = Field(default=True, description="Hide enemies and reveal via F10 marks.")
    reveal_radius_km: float = Field(default=5, gt=0, description="Detection reveal radius.")
    mark_refresh_sec: int = Field(default=15, gt=0, description="How often marks update.")


class DynamicIntent(DMSModel):
    """High-level description of runtime randomness. Python decides the space; Lua picks the instance."""

    pools: list[PoolIntent] = Field(default_factory=list, description="Enemy spawn pools.")
    encounters: list[EncounterIntent] = Field(
        default_factory=list, description="Dynamic encounters."
    )
    director: DirectorIntent = Field(default_factory=DirectorIntent, description="Pacing intent.")
    fog_of_war: FogOfWarIntent = Field(
        default_factory=FogOfWarIntent, description="Fog-of-war intent."
    )


# ---------------------------------------------------------------------------
# MissionSpec
# ---------------------------------------------------------------------------


class AmbientSpec(DMSModel):
    """Friendly base traffic around the player flights' airbases (planner-generated)."""

    enabled: bool = Field(default=True, description="Generate ambient traffic at player bases.")
    density: Literal["off", "low", "medium", "high"] = Field(
        default="low", description="How busy the bases look; 'off' disables ambient traffic."
    )


# ---------------------------------------------------------------------------
# AI flights and watch missions (CONTRACTS "AI flights and watch missions (v0.9)")
# ---------------------------------------------------------------------------

SpecRange = float | tuple[float, float]
"""A number or a [min, max] pair; the runtime rolls one value per order (DMS.Rng.range)."""

OrderKind = Literal["fly", "hold", "land", "escort", "engage", "strike", "rtb"]
TargetKind = Literal["ground", "armor", "aaa", "infantry", "air"]
StrikeWeapon = Literal["guided_bomb", "bomb", "missile", "rockets", "gun", "any"]

# order kind -> field it must set
_ORDER_NEEDS: dict[str, str] = {
    "fly": "to",
    "hold": "at",
    "land": "at",
    "escort": "flight",
    "engage": "at",
    "strike": "at",
}
# field -> order kinds that may set it
_ORDER_ONLY: dict[str, tuple[str, ...]] = {
    "pickup": ("land",),
    "ground_min": ("land",),
    "group": ("strike",),
    "weapon": ("strike",),
    "until": ("hold", "escort", "engage"),
}


class FlightOrder(DMSModel):
    """One order of an AI flight. Orders run in sequence; each starts when the previous is done."""

    do: OrderKind = Field(
        description=(
            "fly: route to area `to`. hold: orbit area `at`. land: land in area `at` (an airbase "
            "area means that airfield). escort: follow flight `flight` and engage threats to it. "
            "engage: orbit `at` and attack `targets` within radius_nm. strike: one attack run on "
            "threat/pool `group` in area `at` with `weapon` (no group = bomb the area centre). "
            "rtb: fly to the start airbase and land."
        ),
    )
    to: Ident | None = Field(default=None, description="fly: destination area id.")
    at: Ident | None = Field(
        default=None, description="hold / land / engage / strike: area id where it happens."
    )
    flight: Ident | None = Field(default=None, description="escort: id of the flight to escort.")
    group: Ident | None = Field(
        default=None,
        description="strike: threat or pool id whose first live group is the target (DMS_ prefix allowed).",
    )
    weapon: StrikeWeapon | None = Field(
        default=None, description="strike: weapon class (default guided_bomb)."
    )
    targets: list[TargetKind] | None = Field(
        default=None, description="escort / engage: target classes (default [ground])."
    )
    alt_ft: float | None = Field(
        default=None, gt=0, le=60000, description="Altitude in feet (AGL helicopters, MSL planes)."
    )
    speed_kts: float | None = Field(default=None, gt=0, le=1200, description="Speed in knots.")
    radius_nm: float | None = Field(
        default=None, gt=0, le=50, description="escort / engage: engagement radius (default 1.5)."
    )
    ground_min: SpecRange | None = Field(
        default=None,
        description="land: minutes on the ground before the next order (default 1); number or [min, max].",
    )
    max_min: SpecRange | None = Field(
        default=None,
        description="Order ends after this many minutes even if `until` never happens (default 15 hold/escort/engage, 6 strike); number or [min, max].",
    )
    pickup: Ident | None = Field(
        default=None,
        description="land: support/flight id of a friendly ground group that boards (removed after ground time if within 300 m).",
    )
    until: BeatTrigger | None = Field(
        default=None,
        description="hold / escort / engage: end condition in beat `when` form, e.g. {beat: lz_cold} or {event: flight.lifted, flight: dustoff}.",
    )
    when: BeatTrigger | None = Field(
        default=None,
        description="Start condition in beat `when` form (default: right after the previous order).",
    )

    @model_validator(mode="before")
    @classmethod
    def _kind_alias(cls, data: Any) -> Any:
        """Accept the Lua spelling `kind` for `do`."""
        if isinstance(data, dict) and "do" not in data and "kind" in data:
            d = dict(data)
            d["do"] = d.pop("kind")
            return d
        return data

    @model_validator(mode="after")
    def _check(self) -> FlightOrder:
        need = _ORDER_NEEDS.get(self.do)
        if need and getattr(self, need) is None:
            raise ValueError(f"order '{self.do}' requires '{need}'")
        for fld, kinds in _ORDER_ONLY.items():
            if getattr(self, fld) is not None and self.do not in kinds:
                raise ValueError(f"'{fld}' is only valid for {'/'.join(kinds)} orders")
        for fld in ("ground_min", "max_min"):
            v = getattr(self, fld)
            if isinstance(v, tuple):
                if v[0] < 0 or v[1] < v[0]:
                    raise ValueError(f"{fld} range must be [min, max] with 0 <= min <= max")
            elif v is not None and v < 0:
                raise ValueError(f"{fld} must be >= 0")
        return self


class FlightSpec(DMSModel):
    """An AI flight that follows a list of orders (any mission; a watch mission's actors)."""

    id: Ident = Field(
        description="Flight id, e.g. 'dustoff'. The planner picks the DCS group name (plan.json / DMS_CONFIG.flights[].group)."
    )
    callsign: str = Field(description="Radio callsign, e.g. 'Dustoff 3-1'.")
    aircraft: str = Field(description="DCS aircraft type id, e.g. 'UH-60A', 'F-16C_50'.")
    count: int = Field(default=1, ge=1, le=4, description="Aircraft in the flight.")
    coalition: Literal["blue", "red"] = Field(default="blue", description="Side.")
    country: str = Field(default="USA", description="DCS country of the aircraft.")
    skill: Literal["Average", "Good", "High", "Excellent"] = Field(
        default="High", description="AI skill."
    )
    start_area: Ident = Field(
        description="Area id where the flight starts; an airbase area with parking_hot/runway starts there, else airborne."
    )
    start_type: Literal["air", "parking_hot", "runway"] = Field(
        default="air", description="How the flight starts."
    )
    start_alt_ft: float | None = Field(
        default=None,
        gt=0,
        le=60000,
        description="Air start altitude in feet (AGL helicopters, default 500; MSL planes, default 15000).",
    )
    start_speed_kts: float | None = Field(
        default=None,
        gt=0,
        le=1200,
        description="Air start speed in knots (default 100 helicopters, 350 planes).",
    )
    heading_toward: Ident | None = Field(
        default=None,
        description="Air start: area id the flight initially heads toward (default: the first order's area).",
    )
    loadout: str | None = Field(
        default=None,
        description="Loadout keyword (same as player flights), e.g. 'medevac', 'strike'; omit for the default.",
    )
    speaker: Ident | None = Field(
        default=None, description="Bible character id who talks for this flight."
    )
    frequency_mhz: float | None = Field(
        default=None, gt=0, description="Radio frequency in MHz (as for Support)."
    )
    modulation: Literal["AM", "FM"] | None = Field(
        default=None, description="Radio modulation; null = FM below 87.995 MHz, else AM."
    )
    immortal: bool = Field(default=False, description="Units cannot be destroyed.")
    invisible: bool = Field(default=False, description="AI enemies do not see the flight.")
    orders: list[FlightOrder] = Field(
        default_factory=list, description="Orders run in sequence; empty = just fly the start."
    )

    @model_validator(mode="after")
    def _check(self) -> FlightSpec:
        if self.heading_toward is not None and self.start_type != "air":
            raise ValueError("heading_toward is only valid with start_type 'air'")
        return self


class WatchSpec(DMSModel):
    """Spectator mission: no client slots; every actor is AI (CONTRACTS v0.9)."""

    focus: Ident = Field(
        description="Id of the flight that stands in for the player (zone.entered, director, ambient, comms position)."
    )
    cues: bool = Field(default=True, description="Show beat `cue` text as 'CAMERA: <text>'.")


class MissionTestHints(DMSModel):
    """Hints for headless test builds (`dms build --test`); never affect normal play."""

    __test__ = False

    require_result: Literal["success", "failure"] | None = Field(
        default=None,
        description="outcome_end must see this result (unset = any mission end passes).",
    )


PluginName = Literal["mist", "skynet", "moose"]
"""Optional pinned Lua plugins (lua/plugins/, docs/CONTRACTS.md "Optional plugins")."""


class KneeboardOptions(DMSModel):
    """Generated kneeboard pages (CONTRACTS "Briefing and kneeboard in the miz")."""

    map: bool = Field(
        default=True,
        description=(
            "Add the generated map page (route, steerpoints, bullseye, friendly airbases, known "
            "threat rings, no-strike areas; hidden threats are never drawn)."
        ),
    )


class MissionSpec(DMSModel):
    """Declarative mission spec (mission-spec.yaml). Areas by reference, forces by role."""

    schema_version: Literal[1] = Field(default=1, description="Schema version; always 1.")
    id: Ident = Field(description="Mission id, e.g. 'm01-first-light'.")
    title: str = Field(description="Mission title.")
    campaign: Ident | None = Field(default=None, description="Campaign slug, if part of one.")
    content_mode: ContentMode = Field(default="fictional", description="Inherited from the bible.")
    theater: Theater = Field(description="DCS map.")
    era: int = Field(ge=1900, le=2100, description="Year; the planner filters units/weapons by it.")
    date: _dt.date = Field(description="In-game date, YYYY-MM-DD.")
    start_time: str = Field(
        default="06:00",
        pattern=r"^([01]\d|2[0-3]):[0-5]\d$",
        description="Local start time HH:MM (24h).",
    )
    weather_preset: Literal[
        "clear", "scattered", "broken", "overcast", "rain", "storm", "dust", "fog", "night_clear"
    ] = Field(default="clear", description="Weather preset.")
    mission_type: MissionType = Field(description="Primary mission type.")
    duration_min: int = Field(default=60, ge=10, le=360, description="Intended mission length.")
    blue_countries: list[str] = Field(
        default_factory=lambda: ["USA"], description="DCS blue countries."
    )
    red_countries: list[str] = Field(
        default_factory=lambda: ["Insurgents"], description="DCS red countries."
    )
    cast: list[Ident] = Field(
        default_factory=list,
        description="Bible character ids who speak in this mission; beat/line speakers must be among them.",
    )
    areas: list[Area] = Field(min_length=1, description="Named areas used throughout the spec.")
    player_flights: list[PlayerFlight] = Field(
        default_factory=list,
        description="Client flights (at least one, unless `watch` is set).",
    )
    watch: WatchSpec | None = Field(
        default=None,
        description="Spectator (watch) mission: no client slots needed; `focus` names the stand-in flight.",
    )
    flights: list[FlightSpec] = Field(
        default_factory=list, description="AI flights that follow orders (any mission)."
    )
    objectives: list[Objective] = Field(min_length=1, description="Objectives, primary first.")
    threats: list[Threat] = Field(default_factory=list, description="Pre-placed enemy presence.")
    support: list[Support] = Field(default_factory=list, description="Friendly assets.")
    dynamic: DynamicIntent = Field(default_factory=DynamicIntent, description="Runtime randomness.")
    ambient: AmbientSpec = Field(
        default_factory=AmbientSpec,
        description="Friendly base traffic at the player flights' departure airbases.",
    )
    seed: int | None = Field(
        default=None, description="Planner seed; null picks one and records it."
    )
    plugins: list[PluginName] = Field(
        default_factory=list,
        description=(
            "Optional pinned Lua plugins to embed before dms.lua (opt-in; the DMS core never needs"
            " them): 'mist', 'skynet' (Skynet-IADS; pulls in mist and the DMS Skynet adapter),"
            " 'moose'. Order and versions are fixed by the generator."
        ),
    )
    test: MissionTestHints | None = Field(
        default=None, description="Headless test-build hints (dms build --test)."
    )
    kneeboard: KneeboardOptions = Field(
        default_factory=KneeboardOptions, description="Generated kneeboard pages."
    )
    notes: str | None = Field(default=None, description="Designer notes; not compiled.")

    @model_validator(mode="after")
    def _check_refs(self) -> MissionSpec:
        area_ids = [a.id for a in self.areas]
        dupes = {i for i in area_ids if area_ids.count(i) > 1}
        if dupes:
            raise ValueError(f"duplicate area ids: {sorted(dupes)}")
        twice = sorted({p for p in self.plugins if self.plugins.count(p) > 1})
        if twice:
            raise ValueError(f"duplicate plugins: {twice}")
        if not self.player_flights and self.watch is None:
            raise ValueError("player_flights needs at least one flight (unless `watch` is set)")
        flight_ids = [f.id for f in self.flights]
        dup_f = sorted({i for i in flight_ids if flight_ids.count(i) > 1})
        if dup_f:
            raise ValueError(f"duplicate flight ids: {dup_f}")
        if self.watch is not None and self.watch.focus not in flight_ids:
            raise ValueError(
                f"watch.focus '{self.watch.focus}' is not a flight id (flights: {flight_ids})"
            )
        pickups = set(flight_ids) | {s.id for s in self.support}
        for i, f in enumerate(self.flights):
            for j, o in enumerate(f.orders):
                path = f"flights[{i}].orders[{j}]"
                if o.flight is not None and o.flight not in flight_ids:
                    raise ValueError(f"{path}.flight: unknown flight '{o.flight}'")
                if o.flight is not None and o.flight == f.id:
                    raise ValueError(f"{path}.flight: a flight cannot escort itself")
                if o.pickup is not None and o.pickup not in pickups:
                    raise ValueError(f"{path}.pickup: unknown support/flight id '{o.pickup}'")
        return self

    def area_ids(self) -> list[str]:
        """Ids of all declared areas."""
        return [a.id for a in self.areas]

    def referenced_areas(self) -> list[tuple[str, str]]:
        """(json-path, area id) for every area reference in the spec."""
        refs: list[tuple[str, str]] = []
        for i, f in enumerate(self.player_flights):
            refs.append((f"player_flights[{i}].start_area", f.start_area))
            if f.air_start is not None and f.air_start.toward:
                refs.append((f"player_flights[{i}].air_start.toward", f.air_start.toward))
        for i, o in enumerate(self.objectives):
            if o.area:
                refs.append((f"objectives[{i}].area", o.area))
        for i, t in enumerate(self.threats):
            refs.append((f"threats[{i}].area", t.area))
        for i, s in enumerate(self.support):
            if s.area:
                refs.append((f"support[{i}].area", s.area))
            refs.extend((f"support[{i}].route[{j}]", a) for j, a in enumerate(s.route))
        for i, p in enumerate(self.dynamic.pools):
            refs.extend((f"dynamic.pools[{i}].areas[{j}]", a) for j, a in enumerate(p.areas))
        for i, e in enumerate(self.dynamic.encounters):
            if e.trigger.area:
                refs.append((f"dynamic.encounters[{i}].trigger.area", e.trigger.area))
        for i, fl in enumerate(self.flights):
            refs.append((f"flights[{i}].start_area", fl.start_area))
            if fl.heading_toward:
                refs.append((f"flights[{i}].heading_toward", fl.heading_toward))
            for j, fo in enumerate(fl.orders):
                if fo.to:
                    refs.append((f"flights[{i}].orders[{j}].to", fo.to))
                if fo.at:
                    refs.append((f"flights[{i}].orders[{j}].at", fo.at))
        return refs
