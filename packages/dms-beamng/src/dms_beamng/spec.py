"""Driving-mission spec: the declarative YAML an LLM (or a human) writes for a BeamNG mission.

Places are *names* from :mod:`dms_beamng.locations`; the planner turns them into coordinates.
Variation is declared as candidate lists (``one_of``) and ranges; the planner picks by seed.
Beats reuse the DMS idea (trigger -> effects: outcome facts, quality deltas, speak, end mission).
"""

from __future__ import annotations

from pathlib import Path
from typing import Literal

import yaml
from dms_core.schemas._common import DMSModel, Ident, OutcomeValue
from dms_core.schemas.beats import BeatSpeak
from pydantic import Field, model_validator

__all__ = [
    "DriveBeat",
    "DriveBeatEffects",
    "DriveBeatTrigger",
    "DrivingMissionSpec",
    "EscalationStep",
    "Level",
    "Objective",
    "Place",
    "PlayerVehicle",
    "Pursuit",
    "Range",
    "Traffic",
    "load_spec",
]

#: Stock levels found in ``content/levels`` of the installed BeamNG.drive 0.40.3.
Level = Literal[
    "automation_test_track",
    "Cliff",
    "derby",
    "driver_training",
    "east_coast_usa",
    "gridmap_v2",
    "hirochi_raceway",
    "Industrial",
    "italy",
    "johnson_valley",
    "jungle_rock_island",
    "small_island",
    "smallgrid",
    "Utah",
    "west_coast_usa",
]

MissionKind = Literal["getaway", "tow_shift", "courier", "rally", "patrol", "free"]
ObjectiveType = Literal["reach", "stop_at", "evade", "survive", "max_damage"]
TriggerEvent = Literal[
    "start",
    "time",
    "objective.complete",
    "pursuit.level",
    "damage.above",
    "arrested",
    "evaded",
    "time_limit",
]


class Range(DMSModel):
    """Inclusive numeric range; the planner draws a value by seed."""

    min: float = Field(description="Lower bound (inclusive).")
    max: float = Field(description="Upper bound (inclusive).")

    @model_validator(mode="after")
    def _ordered(self) -> Range:
        if self.max < self.min:
            raise ValueError("range max < min")
        return self


class Place(DMSModel):
    """A location by name, or a seeded pick among candidate names. Exactly one field."""

    at: str | None = Field(default=None, description="Location name, e.g. 'downtown_bank'.")
    one_of: list[str] | None = Field(
        default=None, min_length=1, description="Candidate location names; one picked by seed."
    )

    @model_validator(mode="after")
    def _exactly_one(self) -> Place:
        if (self.at is None) == (self.one_of is None):
            raise ValueError("place needs exactly one of 'at' or 'one_of'")
        return self

    def candidates(self) -> list[str]:
        """Location names this place may resolve to."""
        return [self.at] if self.at is not None else list(self.one_of or [])


class PlayerVehicle(DMSModel):
    """The vehicle the player (or the AI proxy driver in tests) drives."""

    model: str = Field(description="Vehicle model id, e.g. 'etk800', 'flatbed'.")
    config: str | None = Field(
        default=None, description="Part config path, e.g. 'vehicles/etk800/854t_A.pc' [?]."
    )
    license: str | None = Field(default=None, max_length=10, description="Licence plate text.")


class Traffic(DMSModel):
    """Ambient traffic (BeamNG ``gameplay_traffic``)."""

    amount: int | Range = Field(default=8, description="Active traffic vehicles (or a range).")
    police_ratio: float = Field(
        default=0.0, ge=0, le=1, description="Share of traffic that is police (0..1)."
    )
    parked: int = Field(default=0, ge=0, description="Parked vehicles to spawn.")


class EscalationStep(DMSModel):
    """One Director escalation step during a pursuit."""

    after_sec: float = Field(ge=0, description="Seconds after the pursuit starts.")
    police_units: int = Field(default=1, ge=0, description="Extra police units to add.")
    roadblocks: int = Field(default=0, ge=0, description="Roadblocks to place ahead.")
    aggression: float | None = Field(
        default=None, ge=0, le=1, description="Police AI aggression (0..1), None = unchanged."
    )


class Pursuit(DMSModel):
    """Police pursuit (BeamNG ``gameplay_police``) and its escalation ladder."""

    enabled: bool = Field(default=True, description="Whether police pursue the player.")
    start_after_sec: float | Range = Field(
        default=0, description="Seconds after mission start the pursuit begins."
    )
    evade_sec: float = Field(
        default=30, gt=0, description="Out of police sight this long counts as evaded."
    )
    arrest_sec: float = Field(
        default=8, gt=0, description="Stopped next to police this long counts as arrested."
    )
    escalation: list[EscalationStep] = Field(
        default_factory=list, description="Escalation steps, applied in after_sec order."
    )


class Objective(DMSModel):
    """A mission objective; required ones gate success, optional ones only add outcome facts."""

    id: Ident = Field(description="Objective id, also its outcome key, e.g. 'reach_safehouse'.")
    type: ObjectiveType = Field(description="What completes it.")
    place: Place | None = Field(default=None, description="Target place (reach / stop_at).")
    radius_m: float = Field(default=15, gt=0, description="Arrival radius in metres.")
    hold_sec: float = Field(default=0, ge=0, description="Seconds to stay inside (stop_at).")
    max_damage: float | None = Field(
        default=None, ge=0, description="Damage ceiling (max_damage), in BeamNG damage units [?]."
    )
    after: Ident | None = Field(
        default=None, description="Objective that must complete first (ordering)."
    )
    optional: bool = Field(default=False, description="Not required for success.")

    @model_validator(mode="after")
    def _shape(self) -> Objective:
        if self.type in ("reach", "stop_at") and self.place is None:
            raise ValueError(f"objective {self.id}: type {self.type} needs a place")
        if self.type == "max_damage" and self.max_damage is None:
            raise ValueError(f"objective {self.id}: type max_damage needs max_damage")
        return self


class DriveBeatTrigger(DMSModel):
    """When a beat fires."""

    event: TriggerEvent = Field(description="Trigger event.")
    objective: Ident | None = Field(default=None, description="Objective id (objective.complete).")
    level: int | None = Field(default=None, ge=1, description="Escalation level (pursuit.level).")
    after_sec: float | None = Field(default=None, ge=0, description="Mission time (time).")
    damage: float | None = Field(default=None, ge=0, description="Damage threshold (damage.above).")


class DriveBeatEffects(DMSModel):
    """What a beat changes (subset of DMS BeatEffects that makes sense on the road)."""

    outcome: dict[str, OutcomeValue] = Field(
        default_factory=dict, description="Outcome facts to record, e.g. {loot_dropped: true}."
    )
    quality_deltas: dict[str, int] = Field(
        default_factory=dict, description="Campaign quality changes, e.g. {heat: 1}."
    )
    speak: BeatSpeak | None = Field(default=None, description="Radio/dispatcher call.")
    end_mission: Literal["success", "failure"] | None = Field(
        default=None, description="End the mission with this result."
    )


class DriveBeat(DMSModel):
    """A story beat: trigger -> effects. Same idea as DMS beats.yaml."""

    id: Ident = Field(description="Beat id.")
    when: DriveBeatTrigger = Field(description="Trigger.")
    once: bool = Field(default=True, description="Fire at most once.")
    effects: DriveBeatEffects = Field(
        default_factory=DriveBeatEffects, description="Effects when it fires."
    )


class DrivingMissionSpec(DMSModel):
    """One BeamNG driving mission."""

    schema_version: Literal[1] = Field(default=1, description="Spec format version.")
    id: Ident = Field(description="Mission id, e.g. 'b01_getaway'.")
    title: str = Field(description="Human title.")
    kind: MissionKind = Field(description="Mission archetype.")
    seed: int = Field(default=0, description="Base seed; the planner mixes it with the variant.")
    level: Level = Field(description="BeamNG level.")
    player: PlayerVehicle = Field(description="Player vehicle.")
    start: Place = Field(description="Where the player starts.")
    time_limit_sec: float | None = Field(
        default=None, gt=0, description="Mission fails when exceeded (None = no limit)."
    )
    time_of_day: float | Range = Field(
        default=0.5, description="BeamNG time of day 0..1 (0.5 = noon [?]) or a range."
    )
    traffic: Traffic = Field(default_factory=Traffic, description="Ambient traffic.")
    pursuit: Pursuit | None = Field(default=None, description="Police pursuit, if any.")
    objectives: list[Objective] = Field(min_length=1, description="Objectives.")
    beats: list[DriveBeat] = Field(default_factory=list, description="Story beats.")
    ai_driver: bool = Field(
        default=False, description="Let BeamNG AI drive the player car (headless tests)."
    )

    @model_validator(mode="after")
    def _refs(self) -> DrivingMissionSpec:
        ids = [o.id for o in self.objectives]
        if len(set(ids)) != len(ids):
            raise ValueError("duplicate objective ids")
        for o in self.objectives:
            if o.after is not None and o.after not in ids:
                raise ValueError(f"objective {o.id}: unknown 'after' {o.after}")
        beat_ids = [b.id for b in self.beats]
        if len(set(beat_ids)) != len(beat_ids):
            raise ValueError("duplicate beat ids")
        for b in self.beats:
            if b.when.event == "objective.complete" and b.when.objective not in ids:
                raise ValueError(f"beat {b.id}: unknown objective {b.when.objective}")
        if any(o.type == "evade" for o in self.objectives) and self.pursuit is None:
            raise ValueError("an 'evade' objective needs a pursuit block")
        return self


def load_spec(path: str | Path) -> DrivingMissionSpec:
    """Read and validate a spec YAML file."""
    data = yaml.safe_load(Path(path).read_text(encoding="utf-8"))
    return DrivingMissionSpec.model_validate(data)
