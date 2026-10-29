"""BuildPlan (plan.json): the exact, fully-resolved mission the pydcs builder consumes.

Produced by ``dms plan`` from a MissionSpec. Everything here is concrete: DCS map x/y in meters
(x = north, y = east), DCS unit type ids, unique group/unit names, pylon CLSIDs, frequencies,
triggers and resource files. No LLM should need to write this by hand.
"""

from __future__ import annotations

import datetime as _dt
from typing import Any, Literal

from pydantic import Field, model_validator

from ._common import Coalition, DMSModel, Ident, MissionType, Theater
from .runtime import RuntimeConfig

Skill = Literal["Average", "Good", "High", "Excellent", "Random", "Client", "Player"]


class Pylon(DMSModel):
    """One loaded pylon."""

    num: int = Field(ge=1, le=30, description="Pylon station number.")
    clsid: str = Field(description="Store CLSID, e.g. '{88D18A5E-99C8-4B04-B40B-1C02F2018B6E}'.")
    name: str | None = Field(default=None, description="Human-readable store name (informational).")


class Payload(DMSModel):
    """Aircraft payload."""

    pylons: list[Pylon] = Field(default_factory=list, description="Loaded pylons.")
    fuel_kg: float | None = Field(
        default=None, ge=0, description="Internal fuel in kg; null = full."
    )
    flare: int | None = Field(default=None, ge=0, description="Flare count.")
    chaff: int | None = Field(default=None, ge=0, description="Chaff count.")
    gun_pct: int = Field(default=100, ge=0, le=100, description="Gun ammo percent.")

    @model_validator(mode="after")
    def _unique_pylons(self) -> Payload:
        nums = [p.num for p in self.pylons]
        if len(nums) != len(set(nums)):
            raise ValueError(f"duplicate pylon numbers: {nums}")
        return self


class PlanUnit(DMSModel):
    """One unit, exact."""

    name: str = Field(description="Unique unit name.")
    type: str = Field(description="DCS unit type id.")
    x: float = Field(description="DCS x (north), meters.")
    y: float = Field(description="DCS y (east), meters.")
    alt_m: float | None = Field(default=None, description="Altitude in meters (air units).")
    heading_deg: float = Field(default=0, ge=0, lt=360, description="Heading, degrees true.")
    skill: Skill = Field(default="Good", description="AI skill, or Client/Player for slots.")
    payload: Payload | None = Field(default=None, description="Aircraft payload.")
    livery: str | None = Field(default=None, description="Livery id.")
    onboard_num: str | None = Field(default=None, description="Side number / tail code.")
    parking_id: str | None = Field(default=None, description="Parking spot id for ramp starts.")


class PlanTask(DMSModel):
    """A DCS task attached to a waypoint (pydcs task id + params)."""

    id: str = Field(description="Task id, e.g. 'EngageTargets', 'Orbit', 'Hold'.")
    params: dict[str, Any] = Field(default_factory=dict, description="Task parameters.")


class PlanWaypoint(DMSModel):
    """One route point, exact."""

    x: float = Field(description="DCS x, meters.")
    y: float = Field(description="DCS y, meters.")
    alt_m: float = Field(default=0, description="Altitude in meters.")
    alt_type: Literal["BARO", "RADIO"] = Field(default="BARO", description="Altitude reference.")
    speed_kmh: float = Field(default=0, ge=0, description="Speed in km/h.")
    action: Literal[
        "Turning Point",
        "Fly Over Point",
        "From Parking Area",
        "From Parking Area Hot",
        "From Runway",
        "Landing",
        "Off Road",
        "On Road",
    ] = Field(default="Turning Point", description="DCS waypoint action.")
    name: str | None = Field(default=None, description="Waypoint name.")
    airbase: str | None = Field(default=None, description="Airbase for takeoff/landing points.")
    tasks: list[PlanTask] = Field(default_factory=list, description="Tasks at this point.")


class PlanRadioPreset(DMSModel):
    """One radio preset channel on a client aircraft."""

    radio: int = Field(ge=1, description="Aircraft radio index (pydcs panel_radio key), e.g. 2.")
    channel: int = Field(ge=1, description="Preset channel number on that radio.")
    frequency_mhz: float = Field(gt=0, description="Preset frequency, MHz.")
    name: str | None = Field(default=None, description="Agency on this channel, e.g. 'Ops'.")


class PlanComm(DMSModel):
    """One radio agency in the mission's comms plan (briefing / kneeboard comms table)."""

    id: str = Field(description="Agency id: flight callsign, support id or speaker id.")
    kind: Literal["flight", "support", "agency", "tower"] = Field(description="Agency kind.")
    callsign: str = Field(description="Radio callsign, e.g. 'Magic', 'Hatay Ops'.")
    frequency_mhz: float = Field(gt=0, description="Frequency, MHz.")
    modulation: Literal["AM", "FM"] = Field(description="Modulation.")
    band: Literal["uhf", "vhf", "fm"] = Field(description="Radio band.")
    speaker: Ident | None = Field(default=None, description="Character id who talks on it.")
    source: Literal["spec", "planner", "airbase", "aircraft"] = Field(
        description=(
            "Where the number came from: the spec, the planner, the airbase ATC, or the "
            "aircraft default."
        )
    )
    preset: str | None = Field(
        default=None, description="Preset on the first player flight, e.g. 'radio 2 ch 1'."
    )


class PlanGroup(DMSModel):
    """One group, exact."""

    name: str = Field(description="Unique group name; beats/encounters refer to it.")
    category: Literal["plane", "helicopter", "vehicle", "ship", "static"] = Field(
        description="DCS group category."
    )
    coalition: Coalition = Field(description="Side.")
    country: str = Field(description="DCS country name.")
    task: MissionType | str | None = Field(default=None, description="Main task (air groups).")
    units: list[PlanUnit] = Field(min_length=1, description="Units.")
    route: list[PlanWaypoint] = Field(default_factory=list, description="Waypoints.")
    frequency_mhz: float | None = Field(default=None, gt=0, description="Radio frequency, MHz.")
    modulation: Literal["AM", "FM"] = Field(default="AM", description="Radio modulation.")
    late_activation: bool = Field(default=False, description="Spawn only when activated.")
    hidden: bool = Field(default=False, description="Hidden on the F10 map.")
    uncontrolled: bool = Field(default=False, description="Air group sits uncontrolled.")
    client: bool = Field(default=False, description="True if units are player/client slots.")
    source: Ident | None = Field(
        default=None, description="MissionSpec id this group realises (threat/support/flight)."
    )
    variant: str | None = Field(
        default=None,
        description=(
            "Player-flight start variant; client groups of other variants are left out of "
            "that variant's .miz. Null = in every variant."
        ),
    )
    tacan: str | None = Field(
        default=None,
        description="TACAN channel of a tanker, e.g. '51Y'. Null = builder default ('10X').",
    )
    radio_presets: list[PlanRadioPreset] = Field(
        default_factory=list,
        description=(
            "Client groups: radio preset channels for the mission's agencies (every unit)."
        ),
    )
    radio_callsign: str | None = Field(
        default=None,
        description=(
            "DCS radio callsign of the lead applied by the builder, e.g. 'Python 1-1', "
            "'Magic 1-1' (AWACS), 'Shell 1-1' (tanker) "
            "(name flight-unit)."
        ),
    )
    ai_flight: bool = Field(
        default=False,
        description=(
            "AI flight driven at runtime by DMS.Flights (MissionSpec.flights): built as a plain "
            "route flight (start point + optional first leg) with `task` as its DCS main task."
        ),
    )
    immortal: bool = Field(
        default=False, description="Air groups: SetImmortal start command on the first waypoint."
    )
    invisible: bool = Field(
        default=False, description="Air groups: SetInvisible start command on the first waypoint."
    )


class PlanZone(DMSModel):
    """A mission editor trigger zone."""

    name: str = Field(description="Zone name (area id from the spec).")
    kind: Literal["circle", "polygon"] = Field(description="Shape.")
    x: float | None = Field(default=None, description="Center x (circle).")
    y: float | None = Field(default=None, description="Center y (circle).")
    radius_m: float | None = Field(default=None, gt=0, description="Radius (circle).")
    points: list[tuple[float, float]] = Field(
        default_factory=list, description="[x, y] vertices (polygon)."
    )

    @model_validator(mode="after")
    def _shape(self) -> PlanZone:
        if self.kind == "circle" and (self.x is None or self.y is None or self.radius_m is None):
            raise ValueError(f"circle zone '{self.name}' needs x, y, radius_m")
        if self.kind == "polygon" and len(self.points) < 3:
            raise ValueError(f"polygon zone '{self.name}' needs >= 3 points")
        return self


class PlanTriggerItem(DMSModel):
    """A trigger condition or action."""

    type: str = Field(description="pydcs condition/action name, e.g. 'TimeAfter', 'DoScriptFile'.")
    params: dict[str, Any] = Field(default_factory=dict, description="Parameters.")


class PlanTrigger(DMSModel):
    """A mission editor trigger rule."""

    name: str = Field(description="Rule comment/name.")
    kind: Literal["once", "continuous", "mission_start", "switched"] = Field(
        default="once", description="Trigger rule type."
    )
    conditions: list[PlanTriggerItem] = Field(default_factory=list, description="Conditions (AND).")
    actions: list[PlanTriggerItem] = Field(min_length=1, description="Actions.")


class PlanResource(DMSModel):
    """A file embedded into the .miz."""

    path: str = Field(description="Path inside the .miz, e.g. 'l10n/DEFAULT/dms.lua'.")
    source: str = Field(description="Local source path when building.")
    kind: Literal["script", "sound", "kneeboard", "briefing_image", "other"] = Field(
        description="Resource kind."
    )


class PlanWeather(DMSModel):
    """Exact weather."""

    cloud_preset: str | None = Field(default=None, description="DCS cloud preset, e.g. 'Preset3'.")
    cloud_base_m: float | None = Field(default=None, ge=0, description="Cloud base, meters.")
    wind_dir_deg: float = Field(default=0, ge=0, lt=360, description="Ground wind from, degrees.")
    wind_speed_mps: float = Field(default=0, ge=0, description="Ground wind speed, m/s.")
    temperature_c: float = Field(default=20, description="Ground temperature, Celsius.")
    qnh_mmhg: float = Field(default=760, description="QNH in mmHg.")
    visibility_m: float = Field(default=80000, gt=0, description="Visibility, meters.")
    fog_visibility_m: float | None = Field(default=None, gt=0, description="Fog visibility.")
    dust_visibility_m: float | None = Field(default=None, gt=0, description="Dust visibility.")
    precipitation: Literal["none", "rain", "thunderstorm", "snow"] = Field(
        default="none", description="Precipitation."
    )


class PlanBriefing(DMSModel):
    """Mission editor briefing texts."""

    title: str = Field(description="Mission title.")
    description: str = Field(default="", description="Situation text.")
    blue_task: str = Field(default="", description="Blue task text.")
    red_task: str = Field(default="", description="Red task text.")


class PlanOptions(DMSModel):
    """Mission options."""

    fog_of_war_map: bool = Field(default=True, description="F10 map option 'Fog of War'.")
    labels: Literal["none", "abbreviated", "full", "dot"] = Field(
        default="none", description="Labels."
    )
    civil_traffic: Literal["off", "low", "medium", "high"] = Field(
        default="off", description="Civ traffic."
    )
    external_views: bool = Field(default=True, description="Allow F2 external views.")
    kneeboard_map: bool = Field(
        default=True,
        description="Add the generated kneeboard map page (MissionSpec.kneeboard.map).",
    )


class PlanSkynet(DMSModel):
    """Options for the Skynet-IADS adapter, emitted as ``DMS_SKYNET`` in dms_config.lua."""

    prefixes: list[str] = Field(
        min_length=1,
        description=(
            "Group name prefixes the adapter registers: 'DMS_' (runtime spawns) plus the planned"
            " SAM threat group names."
        ),
    )


class BuildPlan(DMSModel):
    """Exact build plan (plan.json). Seeded and reproducible."""

    schema_version: Literal[1] = Field(default=1, description="Schema version.")
    mission_id: Ident = Field(description="Mission id.")
    seed: int = Field(description="Seed used by the planner.")
    theater: Theater = Field(description="DCS map.")
    date: _dt.date = Field(description="Mission date.")
    start_time_sec: int = Field(ge=0, lt=86400, description="Start time, seconds after midnight.")
    weather: PlanWeather = Field(default_factory=PlanWeather, description="Weather.")
    blue_countries: list[str] = Field(default_factory=list, description="Blue coalition countries.")
    red_countries: list[str] = Field(default_factory=list, description="Red coalition countries.")
    neutral_countries: list[str] = Field(
        default_factory=list,
        description="DCS countries placed in the neutral coalition (civilian / neutral factions).",
    )
    groups: list[PlanGroup] = Field(default_factory=list, description="All groups.")
    zones: list[PlanZone] = Field(default_factory=list, description="Trigger zones.")
    triggers: list[PlanTrigger] = Field(default_factory=list, description="Trigger rules.")
    resources: list[PlanResource] = Field(default_factory=list, description="Embedded files.")
    briefing: PlanBriefing | None = Field(default=None, description="Briefing texts.")
    comms: list[PlanComm] = Field(
        default_factory=list, description="Comms plan: every radio agency and its frequency."
    )
    options: PlanOptions = Field(default_factory=PlanOptions, description="Mission options.")
    runtime: RuntimeConfig | None = Field(
        default=None, description="DMS_CONFIG to emit as dms_config.lua."
    )
    skynet: PlanSkynet | None = Field(
        default=None,
        description="DMS_SKYNET to append to dms_config.lua (set when the spec lists 'skynet').",
    )

    @model_validator(mode="after")
    def _unique_names(self) -> BuildPlan:
        for label, names in (
            ("group", [g.name for g in self.groups]),
            ("unit", [u.name for g in self.groups for u in g.units]),
            ("zone", [z.name for z in self.zones]),
            ("resource path", [r.path for r in self.resources]),
        ):
            dupes = {n for n in names if names.count(n) > 1}
            if dupes:
                raise ValueError(f"duplicate {label} names: {sorted(dupes)}")
        return self
