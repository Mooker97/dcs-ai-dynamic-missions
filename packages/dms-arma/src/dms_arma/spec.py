"""ArmaMissionSpec: the declarative input of the Arma 3 backend.

It covers every tunable The Hill's `functions/fn_config.sqf` parameterises. Field names are
snake_case; `dms_arma.config` maps them to the camelCase SQF keys. Positions are world [x, y]
metres, angles are compass degrees, durations are seconds. A `Range` is a [min, max] pair the
mission rolls a seeded uniform value from (`DMS_fnc_rng "RANGE"`).
"""

from __future__ import annotations

from typing import Annotated, Literal

from pydantic import BaseModel, ConfigDict, Field, model_validator

XY = tuple[float, float]
"""World position [x, y] in metres (x west->east, y south->north)."""

Range = tuple[float, float]
"""[min, max]; the runtime rolls a seeded uniform value in it."""

ClassName = Annotated[str, Field(pattern=r"^[A-Za-z_][A-Za-z0-9_]*$")]
"""An Arma config class name (CfgVehicles, CfgAmmo, ...)."""

Bearing = Annotated[float, Field(ge=0, lt=360)]
Distance = Annotated[float, Field(ge=0)]
Seconds = Annotated[float, Field(ge=0)]

SkillName = Literal[
    "general",
    "aimingAccuracy",
    "aimingShake",
    "aimingSpeed",
    "endurance",
    "spotDistance",
    "spotTime",
    "courage",
    "reloadSpeed",
    "commanding",
]
"""Sub-skills accepted by `setSkill [name, value]`."""


class ArmaModel(BaseModel):
    """Base: unknown fields are errors."""

    model_config = ConfigDict(extra="forbid")


def _check_range(name: str, value: Range) -> None:
    if value[0] > value[1]:
        raise ValueError(f"{name}: min {value[0]} > max {value[1]}")


class Site(ArmaModel):
    """One candidate objective; the seed (or the DMS_site param) picks one."""

    name: str = Field(min_length=1, description="Display name used in tasks and the log.")
    center: XY = Field(description="Compound centre (OUTPOST: centroid of the cargo structures).")
    compound_dir: Bearing = Field(description="Compound frame heading; +y of composition offsets.")
    start_bearing: Bearing = Field(
        description="Bearing compound -> squad start; also the safe side for the LZ and exfil."
    )
    qrf_spawns: tuple[XY, XY] = Field(description="QRF origins A and B (snapped to nearest road).")
    qrf_names: tuple[str, str] = Field(description="Names of the QRF origins (usually towns).")
    mode: Literal["OUTPOST", "BUILD"] = Field(
        description=(
            "OUTPOST garrisons the vanilla terrain outpost at `center` (no snap); BUILD snaps to"
            " flat open ground and builds `compound.composition`."
        )
    )


class OutpostItem(ArmaModel):
    """Prop placed at a seeded clear spot inside a terrain outpost (OUTPOST mode)."""

    kind: Literal["INTEL", "OVER", "OBJ", "STATIC", "SENTRY"] = Field(
        description="INTEL table, OVER (placed on the intel spot), OBJ prop, STATIC, SENTRY post."
    )
    class_name: ClassName | Literal[""] = Field(description="Class to create; '' for SENTRY.")
    radius: Range = Field(description="[min, max] distance from the site centre, metres.")
    clear_radius: Distance = Field(description="No terrain objects within this radius, metres.")

    @model_validator(mode="after")
    def _valid(self) -> OutpostItem:
        _check_range("radius", self.radius)
        if (self.kind == "SENTRY") != (self.class_name == ""):
            raise ValueError("class_name must be '' exactly for SENTRY items")
        return self


class CompoundItem(ArmaModel):
    """Object of the BUILD-mode composition, in the compound frame."""

    kind: Literal["BLD", "OBJ", "STATIC", "SENTRY", "INTEL"] = Field(
        description=(
            "BLD garrisoned building, OBJ terrain-aligned prop, STATIC crewed static weapon,"
            " SENTRY fixed post (class unused), INTEL table for the intel item."
        )
    )
    class_name: ClassName | Literal[""] = Field(description="Class to create; '' for SENTRY.")
    offset: XY = Field(description="[dx, dy] metres in the compound frame (+y = compound_dir).")
    rel_dir: float = Field(ge=0, lt=360, description="Heading relative to compound_dir, degrees.")

    @model_validator(mode="after")
    def _valid(self) -> CompoundItem:
        if (self.kind == "SENTRY") != (self.class_name == ""):
            raise ValueError("class_name must be '' exactly for SENTRY items")
        return self


class SitesSpec(ArmaModel):
    """Objective sites, the outpost garrison props and how start/LZ/AO are derived."""

    sites: list[Site] = Field(min_length=1, description="Candidate sites, in DMS_site order.")
    outpost_classes: list[ClassName] = Field(
        min_length=1, description="Terrain structures counted as the outpost (garrisoned)."
    )
    outpost_radius: Distance = Field(description="Outpost structure search radius, metres.")
    outpost_composition: list[OutpostItem] = Field(description="Props added inside an outpost.")
    site_snap_radius: Distance = Field(description="BUILD: search radius for flat ground.")
    clear_radius: Distance = Field(description="BUILD: required clear radius, metres.")
    start_distance: Distance = Field(description="Squad start distance from the compound.")
    lz_distance: Distance = Field(description="Extraction LZ distance from the compound.")
    ao_marker_radius: Distance = Field(description="Radius of the approximate AO marker.")
    ao_marker_fuzz: Range = Field(description="Random offset of the AO marker centre, metres.")

    @model_validator(mode="after")
    def _valid(self) -> SitesSpec:
        _check_range("ao_marker_fuzz", self.ao_marker_fuzz)
        return self


class SquadSpec(ArmaModel):
    """The player's squad (player is the leader)."""

    leader_class: ClassName = Field(description="Class of the squad leader (the player slot).")
    classes: list[ClassName] = Field(min_length=1, description="AI squad members, in order.")
    skill: float = Field(ge=0, le=1, description="setSkill for every AI squad member.")


class CompoundSpec(ArmaModel):
    """BUILD-mode composition and the intel item."""

    composition: list[CompoundItem] = Field(description="Objects built for a BUILD site.")
    intel_class: ClassName = Field(description="Intel object placed on the INTEL table.")
    intel_hold_seconds: Seconds = Field(description="Hold-action duration to take the intel.")


class EnemySpec(ArmaModel):
    """Garrison, patrol and AI skill of the defenders."""

    sentry_class: ClassName = Field(description="Class for SENTRY posts.")
    garrison_classes: list[ClassName] = Field(
        min_length=1, description="Garrison pool (repeat a class to weight it)."
    )
    garrison_count: int = Field(ge=0, description="Garrison riflemen placed in building positions.")
    patrol_size: int = Field(ge=0, description="Units in the compound patrol (0 = none).")
    patrol_radius: Distance = Field(description="Patrol loop radius, metres.")
    skill: dict[SkillName, Annotated[float, Field(ge=0, le=1)]] = Field(
        description="Sub-skill values for every enemy unit, applied in order."
    )
    alarm_knows_about: float = Field(
        ge=0, le=4, description="knowsAbout of the player side that raises the alarm."
    )


class Wave(ArmaModel):
    """A QRF wave."""

    vehicle_classes: list[ClassName] = Field(
        min_length=1, description="Vehicle candidates; the first one that exists is used."
    )
    infantry_classes: list[ClassName] = Field(min_length=1, description="Infantry pool.")
    infantry_count: int = Field(ge=1, description="Infantry carried.")
    dismount_distance: Range = Field(
        description="Dismount [min, max] metres short of the objective."
    )

    @model_validator(mode="after")
    def _valid(self) -> Wave:
        _check_range("dismount_distance", self.dismount_distance)
        return self


class QrfSpec(ArmaModel):
    """Quick reaction force timing and flanking."""

    wave1: Wave = Field(description="First wave (on alarm or intel pickup).")
    wave2: Wave = Field(description="Second wave (only if the fight drags on).")
    wave1_delay: Range = Field(description="Seconds from trigger to wave 1 departure.")
    wave2_delay: Range = Field(description="Seconds from the drag trigger to wave 2 departure.")
    wave2_drag_time: Seconds = Field(description="Fight length after which wave 2 is sent.")
    wave2_quick_kill: Seconds = Field(description="Wave 1 killed this fast also sends wave 2.")
    flank_offset: Distance = Field(description="Lateral flank offset of the dismount, metres.")
    flank_angle: float = Field(ge=0, le=180, description="Flank angle off the direct line, deg.")

    @model_validator(mode="after")
    def _valid(self) -> QrfSpec:
        _check_range("wave1_delay", self.wave1_delay)
        _check_range("wave2_delay", self.wave2_delay)
        return self


class ArtillerySpec(ArmaModel):
    """Virtual mortar section on the comm menu."""

    missions: int = Field(ge=0, description="Fire missions available.")
    rounds_ffe: int = Field(ge=1, description="Rounds per fire-for-effect.")
    spot_rounds: int = Field(ge=0, description="Spotting rounds available.")
    process_time: Seconds = Field(description="Request processing delay.")
    time_of_flight: Seconds = Field(description="Time of flight.")
    cep: Distance = Field(description="CEP of an unadjusted mission, metres.")
    adjusted_cep: Distance = Field(description="CEP after a spotting round, metres.")
    adjust_window: Distance = Field(description="A spot round within this distance adjusts FFE.")
    danger_close: Distance = Field(description="Missions closer than this to friendlies refused.")
    ammo: ClassName = Field(description="CfgAmmo class created per round.")
    interval: Range = Field(description="Seconds between rounds.")

    @model_validator(mode="after")
    def _valid(self) -> ArtillerySpec:
        _check_range("interval", self.interval)
        return self


class ExfilSpec(ArmaModel):
    """Extraction helicopter behaviour."""

    heli_class: ClassName = Field(description="Extraction helicopter class.")
    spawn_distance: Distance = Field(description="Heli spawn distance from the LZ.")
    hold_distance: Distance = Field(description="Hold point distance from the LZ.")
    fly_height: Distance = Field(description="flyInHeight, metres.")
    hot_radius: Distance = Field(description="Known enemies within this radius make the LZ hot.")
    hot_vehicle_radius: Distance = Field(
        description="A known armed enemy vehicle this close also makes the LZ hot."
    )
    ready_radius: Distance = Field(
        description="Heli comes in once the player (or any squad member) is this close to the LZ."
    )
    ready_max_wait: Seconds = Field(description="Max wait at the hold point for the squad.")
    hot_max_hold: Seconds = Field(description="Max hold off a hot LZ before returning to base.")
    hot_count: int = Field(ge=1, description="Known enemies needed for a hot LZ.")
    wait_on_ground: Seconds = Field(description="Time the heli waits on the ground.")
    board_radius: Distance = Field(description="Squad members within this radius must board.")
    depart_distance: Distance = Field(description="Distance from the LZ that counts as extracted.")


class TestModeSpec(ArmaModel):
    """Unattended test-mode timings and the expected event checklist."""

    arty_at: Seconds = Field(description="Test mode calls artillery this many seconds in.")
    alarm_timeout: Seconds = Field(description="Fail the alarm check after this many seconds.")
    intel_timeout: Seconds = Field(description="Fail the intel check after this many seconds.")
    expected: list[Annotated[str, Field(pattern=r"^[a-z0-9_]+$")]] = Field(
        min_length=1, description="Event ids test mode must see (harness PASS list)."
    )


class ArmaMissionSpec(ArmaModel):
    """A whole Arma mission's tunables. Emitted as `functions/fn_config.sqf`."""

    template: Literal["the_hill"] = Field(
        description="Mission template whose scripts read this config (only The Hill so far)."
    )
    world: str = Field(pattern=r"^[A-Za-z0-9_]+$", description="Terrain (worldName), e.g. Altis.")
    name: str = Field(min_length=1, description="Mission display name.")
    sites: SitesSpec = Field(description="Objective sites and derived positions.")
    squad: SquadSpec = Field(description="Player squad.")
    compound: CompoundSpec = Field(description="BUILD composition and intel.")
    enemy: EnemySpec = Field(description="Defenders.")
    qrf: QrfSpec = Field(description="Quick reaction force.")
    artillery: ArtillerySpec = Field(description="Mortar support.")
    exfil: ExfilSpec = Field(description="Extraction.")
    test: TestModeSpec = Field(description="Test mode.")

    def class_names(self) -> list[tuple[str, str]]:
        """Every (spec path, class name) this spec references, in a stable order."""
        out: list[tuple[str, str]] = []

        def add(path: str, names: list[str]) -> None:
            out.extend((f"{path}[{i}]", n) for i, n in enumerate(names) if n)

        add("sites.outpost_classes", list(self.sites.outpost_classes))
        add("sites.outpost_composition", [i.class_name for i in self.sites.outpost_composition])
        add("squad.leader_class", [self.squad.leader_class])
        add("squad.classes", list(self.squad.classes))
        add("compound.composition", [i.class_name for i in self.compound.composition])
        add("compound.intel_class", [self.compound.intel_class])
        add("enemy.sentry_class", [self.enemy.sentry_class])
        add("enemy.garrison_classes", list(self.enemy.garrison_classes))
        for w in ("wave1", "wave2"):
            wave: Wave = getattr(self.qrf, w)
            add(f"qrf.{w}.vehicle_classes", list(wave.vehicle_classes))
            add(f"qrf.{w}.infantry_classes", list(wave.infantry_classes))
        add("artillery.ammo", [self.artillery.ammo])
        add("exfil.heli_class", [self.exfil.heli_class])
        return out
