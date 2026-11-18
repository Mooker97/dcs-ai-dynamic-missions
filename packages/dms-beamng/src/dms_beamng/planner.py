"""Spec -> ScenarioPlan. Pure and deterministic: same (spec, variant) -> same plan, byte for byte.

All randomness comes from one ``random.Random`` seeded from ``sha256(seed:variant:id)`` and is
drawn in a fixed order (start, time of day, traffic, pursuit, objectives), so adding a field
at the end of the order never reshuffles earlier picks.
"""

from __future__ import annotations

import hashlib
import math
import random

from dms_core.schemas._common import DMSModel, Ident
from pydantic import Field

from .locations import lookup
from .spec import (
    DriveBeat,
    DrivingMissionSpec,
    EscalationStep,
    MissionKind,
    ObjectiveType,
    Place,
    Range,
)

__all__ = [
    "PlannedObjective",
    "PlannedPursuit",
    "PlannedTraffic",
    "PlannedVehicle",
    "ScenarioPlan",
    "derive_seed",
    "heading_to_quat",
    "plan",
]

Vec3 = tuple[float, float, float]
Quat = tuple[float, float, float, float]


class PlannedVehicle(DMSModel):
    """A vehicle with resolved placement."""

    vid: str = Field(description="Vehicle id in the scenario, e.g. 'player'.")
    model: str = Field(description="Vehicle model id.")
    config: str | None = Field(default=None, description="Part config path.")
    license: str | None = Field(default=None, description="Licence plate text.")
    location: str = Field(description="Location name it was placed at.")
    pos: Vec3 = Field(description="World position (m).")
    rot_quat: Quat = Field(description="Rotation quaternion (x, y, z, w).")


class PlannedTraffic(DMSModel):
    """Resolved traffic numbers."""

    amount: int = Field(ge=0, description="Active traffic vehicles.")
    police_ratio: float = Field(ge=0, le=1, description="Police share of traffic.")
    parked: int = Field(ge=0, description="Parked vehicles.")


class PlannedPursuit(DMSModel):
    """Resolved pursuit timing and escalation ladder (sorted by after_sec)."""

    start_after_sec: float = Field(ge=0, description="Pursuit start (mission seconds).")
    evade_sec: float = Field(gt=0, description="Seconds unseen to evade.")
    arrest_sec: float = Field(gt=0, description="Seconds stopped near police to be arrested.")
    escalation: list[EscalationStep] = Field(description="Escalation steps, level = index + 1.")


class PlannedObjective(DMSModel):
    """An objective with its place resolved."""

    id: Ident = Field(description="Objective id.")
    type: ObjectiveType = Field(description="Objective type.")
    location: str | None = Field(default=None, description="Chosen location name.")
    pos: Vec3 | None = Field(default=None, description="Target position (m).")
    radius_m: float = Field(description="Arrival radius (m).")
    hold_sec: float = Field(description="Hold time (s).")
    max_damage: float | None = Field(default=None, description="Damage ceiling.")
    after: Ident | None = Field(default=None, description="Prerequisite objective.")
    optional: bool = Field(description="Not required for success.")


class ScenarioPlan(DMSModel):
    """Everything a builder needs; no randomness left."""

    mission_id: Ident = Field(description="Mission id.")
    title: str = Field(description="Mission title.")
    kind: MissionKind = Field(description="Mission archetype.")
    level: str = Field(description="BeamNG level.")
    variant: int = Field(ge=0, description="Variant number requested.")
    seed: int = Field(description="Effective seed (derived).")
    player: PlannedVehicle = Field(description="Player vehicle.")
    time_of_day: float = Field(ge=0, le=1, description="Time of day 0..1.")
    time_limit_sec: float | None = Field(default=None, description="Time limit (s).")
    traffic: PlannedTraffic = Field(description="Traffic.")
    pursuit: PlannedPursuit | None = Field(default=None, description="Pursuit, if any.")
    objectives: list[PlannedObjective] = Field(description="Objectives in spec order.")
    beats: list[DriveBeat] = Field(description="Beats, copied from the spec.")
    picks: dict[str, str] = Field(description="Place picks: 'start' / objective id -> location.")
    ai_driver: bool = Field(description="AI drives the player car.")
    plan_hash: str = Field(default="", description="sha256 of the plan without this field.")


def derive_seed(base: int, variant: int, mission_id: str) -> int:
    """Stable 63-bit seed from (base seed, variant, mission id)."""
    digest = hashlib.sha256(f"{base}:{variant}:{mission_id}".encode()).digest()
    return int.from_bytes(digest[:8], "big") >> 1


def heading_to_quat(heading_deg: float) -> Quat:
    """Yaw-only quaternion about +Z. Sign convention vs BeamNG heading is unverified [?]."""
    half = math.radians(heading_deg) / 2
    return (0.0, 0.0, round(math.sin(half), 7), round(math.cos(half), 7))


def _draw(rng: random.Random, value: float | Range, digits: int = 3) -> float:
    if isinstance(value, Range):
        return round(rng.uniform(value.min, value.max), digits)
    return float(value)


def _pick(rng: random.Random, level: str, place: Place, avoid: set[str]) -> str:
    names = place.candidates()
    for name in names:
        lookup(level, name)  # fail early with the valid names
    pool = [n for n in names if n not in avoid] or names
    return pool[0] if len(pool) == 1 else rng.choice(pool)


def plan(spec: DrivingMissionSpec, variant: int = 0) -> ScenarioPlan:
    """Resolve a spec into a concrete, deterministic scenario plan."""
    seed = derive_seed(spec.seed, variant, spec.id)
    rng = random.Random(seed)
    picks: dict[str, str] = {}

    start_name = _pick(rng, spec.level, spec.start, set())
    picks["start"] = start_name
    start = lookup(spec.level, start_name)
    player = PlannedVehicle(
        vid="player",
        model=spec.player.model,
        config=spec.player.config,
        license=spec.player.license,
        location=start_name,
        pos=start.pos,
        rot_quat=heading_to_quat(start.heading_deg),
    )

    tod = _draw(rng, spec.time_of_day)
    amount = spec.traffic.amount
    traffic = PlannedTraffic(
        amount=round(_draw(rng, amount)) if isinstance(amount, Range) else amount,
        police_ratio=spec.traffic.police_ratio,
        parked=spec.traffic.parked,
    )

    pursuit = None
    if spec.pursuit is not None and spec.pursuit.enabled:
        pursuit = PlannedPursuit(
            start_after_sec=_draw(rng, spec.pursuit.start_after_sec, 1),
            evade_sec=spec.pursuit.evade_sec,
            arrest_sec=spec.pursuit.arrest_sec,
            escalation=sorted(spec.pursuit.escalation, key=lambda s: s.after_sec),
        )

    used = {start_name}
    objectives: list[PlannedObjective] = []
    for obj in spec.objectives:
        loc_name = None
        pos = None
        if obj.place is not None:
            loc_name = _pick(rng, spec.level, obj.place, used)
            used.add(loc_name)
            picks[obj.id] = loc_name
            pos = lookup(spec.level, loc_name).pos
        objectives.append(
            PlannedObjective(
                id=obj.id,
                type=obj.type,
                location=loc_name,
                pos=pos,
                radius_m=obj.radius_m,
                hold_sec=obj.hold_sec,
                max_damage=obj.max_damage,
                after=obj.after,
                optional=obj.optional,
            )
        )

    result = ScenarioPlan(
        mission_id=spec.id,
        title=spec.title,
        kind=spec.kind,
        level=spec.level,
        variant=variant,
        seed=seed,
        player=player,
        time_of_day=tod,
        time_limit_sec=spec.time_limit_sec,
        traffic=traffic,
        pursuit=pursuit,
        objectives=objectives,
        beats=list(spec.beats),
        picks=picks,
        ai_driver=spec.ai_driver,
    )
    digest = hashlib.sha256(result.model_dump_json(exclude={"plan_hash"}).encode()).hexdigest()
    result.plan_hash = digest
    return result
