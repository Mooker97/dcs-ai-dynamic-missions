# ruff: noqa: E501
"""MissionSpec: the declarative, LLM-facing description of one mission (mission-spec.yaml).

Describe *areas by reference* and *forces by role*. Never write DCS x/y coordinates, unit ids or
group ids here; ``dms plan`` resolves areas to coordinates and roles to unit types (BuildPlan).
"""

from __future__ import annotations

import datetime as _dt
from typing import Annotated, Literal

from pydantic import Field, model_validator

from ._common import (
    Coalition,
    ContentMode,
    DMSModel,
    Ident,
    LatLon,
    MissionType,
    Skill,
    Theater,
)

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


class PlayerFlight(DMSModel):
    """A flight of player (client) aircraft."""

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
    speaker: Ident | None = Field(
        default=None, description="Bible character who talks for this asset."
    )
    frequency_mhz: float | None = Field(default=None, gt=0, description="Radio frequency in MHz.")


class Objective(DMSModel):
    """A mission objective, checkable at runtime via flags."""

    id: Ident = Field(description="Objective id, e.g. 'convoy_arrives'.")
    kind: Literal["destroy", "protect", "escort", "reach", "recon", "rescue", "survive", "land"] = (
        Field(description="Objective type.")
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
    kind: Literal["ambush_sam", "waves", "hunt", "convoy", "cap", "pool"] = Field(
        description="Encounter behaviour."
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
    player_flights: list[PlayerFlight] = Field(min_length=1, description="Client flights.")
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
    notes: str | None = Field(default=None, description="Designer notes; not compiled.")

    @model_validator(mode="after")
    def _check_refs(self) -> MissionSpec:
        area_ids = [a.id for a in self.areas]
        dupes = {i for i in area_ids if area_ids.count(i) > 1}
        if dupes:
            raise ValueError(f"duplicate area ids: {sorted(dupes)}")
        return self

    def area_ids(self) -> list[str]:
        """Ids of all declared areas."""
        return [a.id for a in self.areas]

    def referenced_areas(self) -> list[tuple[str, str]]:
        """(json-path, area id) for every area reference in the spec."""
        refs: list[tuple[str, str]] = []
        for i, f in enumerate(self.player_flights):
            refs.append((f"player_flights[{i}].start_area", f.start_area))
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
        return refs
