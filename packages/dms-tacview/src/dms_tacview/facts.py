"""FlightSummary -> flat debrief facts that can enrich a DMS ``MissionOutcome``.

Fact keys match the arc ``quality_effects`` condition grammar (``[a-z][a-z0-9_]*``) and all carry
the ``tv_`` prefix, so they never collide with Lua-reported outcome keys. Proposed integration is
in docs/ideas/tacview.md; ``dms_core.outcomes`` is not changed by this package.
"""

from __future__ import annotations

import re
from collections import Counter
from typing import Any

from dms_core.schemas import MissionOutcome
from pydantic import BaseModel, ConfigDict, Field

from .summary import Confidence, Fate, FlightSummary, Kill, KillMethod, SelectedBy

__all__ = [
    "FACT_PREFIX",
    "KillFact",
    "PlayerFacts",
    "ShotFact",
    "TacviewFacts",
    "TimeOverTarget",
    "WeaponReleased",
    "attach_tacview",
    "enrich_outcome",
    "fact_key",
    "outcome_facts",
    "tacview_facts",
]

FACT_PREFIX = "tv_"

Fact = bool | int | float | str


def fact_key(*parts: str, prefix: str = FACT_PREFIX) -> str:
    """``fact_key("SAM Site 1", "min_m")`` -> ``tv_sam_site_1_min_m``."""
    body = "_".join(re.sub(r"[^a-z0-9]+", "_", p.lower()).strip("_") for p in parts if p)
    body = re.sub(r"_+", "_", body).strip("_") or "unnamed"
    key = f"{prefix}{body}"
    return key if key[0].isalpha() else f"tv_{key}"


def _kill_class(k: Kill) -> str:
    tags = set((k.victim_type or "").split("+"))
    for cls, name in (("Air", "air"), ("Sea", "sea"), ("Ground", "ground")):
        if cls in tags:
            return name
    return "other"


def outcome_facts(summary: FlightSummary, *, prefix: str = FACT_PREFIX) -> dict[str, Fact]:
    """Flat, deterministic facts about the player's flight (empty-ish when no player is found)."""
    f: dict[str, Fact] = {fact_key("player_found", prefix=prefix): summary.player is not None}
    f[fact_key("duration_s", prefix=prefix)] = round(summary.duration_s, 1)
    p = summary.player
    if p is None:
        return f
    coal = p.coalition
    mine = [k for k in summary.kills if k.killer_id == p.object_id]
    f.update(
        {
            fact_key("flight_time_s", prefix=prefix): round(p.flight_time_s, 1),
            fact_key("distance_km", prefix=prefix): round(p.distance_km, 1),
            fact_key("player_destroyed", prefix=prefix): p.fate == "destroyed",
            fact_key("player_landed", prefix=prefix): bool(p.landings),
            fact_key("player_shots", prefix=prefix): summary.player_shots,
            fact_key("player_hits", prefix=prefix): summary.player_hits,
            fact_key("player_kills", prefix=prefix): len(mine),
            fact_key("player_kills_confident", prefix=prefix): sum(
                1 for k in mine if k.confidence in ("high", "medium")
            ),
        }
    )
    if p.max_alt_m is not None:
        f[fact_key("max_alt_m", prefix=prefix)] = p.max_alt_m
    if p.min_alt_m is not None:
        f[fact_key("min_alt_m", prefix=prefix)] = p.min_alt_m
    for cls in ("air", "ground", "sea"):
        f[fact_key("player_kills", cls, prefix=prefix)] = sum(
            1 for k in mine if _kill_class(k) == cls
        )
    if coal:
        f[fact_key("friendly_losses", prefix=prefix)] = sum(
            1 for k in summary.kills if k.victim_coalition == coal and k.victim_id != p.object_id
        )
        f[fact_key("enemy_losses", prefix=prefix)] = sum(
            1 for k in summary.kills if k.victim_coalition and k.victim_coalition != coal
        )
    zones = [pt for pt in summary.points if pt.time_inside_s is not None]
    if zones:
        f[fact_key("time_over_target_s", prefix=prefix)] = round(
            sum(pt.time_inside_s or 0.0 for pt in zones), 1
        )
    if summary.threats:
        f[fact_key("closest_threat_m", prefix=prefix)] = summary.threats[0].min_slant_m
    for pt in summary.points:
        f[fact_key(pt.name, "min_m", prefix=prefix)] = pt.min_distance_m
        if pt.entered is not None:
            f[fact_key(pt.name, "entered", prefix=prefix)] = pt.entered
        if pt.time_inside_s is not None:
            f[fact_key(pt.name, "time_inside_s", prefix=prefix)] = pt.time_inside_s
    return f


def enrich_outcome(
    outcome: MissionOutcome,
    summary: FlightSummary,
    *,
    merge_into_outcomes: bool = False,
    recording_time: str | None = None,
    prefix: str = FACT_PREFIX,
) -> MissionOutcome:
    """Return a copy of ``outcome`` with Tacview facts under ``extra["tacview"]`` (pure).

    With ``merge_into_outcomes`` the facts are also added to ``outcomes`` (never overwriting a
    key the Lua runtime reported), which makes them visible to arc ``quality_effects``.
    """
    block = tacview_facts(summary, recording_time=recording_time, prefix=prefix)
    return attach_tacview(outcome, block, merge_into_outcomes=merge_into_outcomes)


class _Model(BaseModel):
    model_config = ConfigDict(extra="forbid")


class PlayerFacts(_Model):
    """The player's aircraft over the recording (``extra.tacview.player``)."""

    object_id: str = Field(description="ACMI object id of the player aircraft (lower-case hex).")
    name: str | None = Field(default=None, description="Aircraft Name property (unit type).")
    pilot: str | None = Field(default=None, description="Pilot property.")
    coalition: str | None = Field(default=None, description="Coalition property.")
    selected_by: SelectedBy = Field(description="How the player aircraft was chosen.")
    first_seen: float = Field(description="First appearance (s from ReferenceTime).")
    last_seen: float = Field(description="Last appearance (s from ReferenceTime).")
    flight_time_s: float = Field(description="last_seen - first_seen (s).")
    distance_km: float = Field(description="Ground distance covered (km).")
    min_alt_m: float | None = Field(default=None, description="Lowest altitude MSL (m).")
    max_alt_m: float | None = Field(default=None, description="Highest altitude MSL (m).")
    takeoffs: list[float] = Field(default_factory=list, description="TakenOff event times (s).")
    landings: list[float] = Field(default_factory=list, description="Landed event times (s).")
    landed: bool = Field(description="At least one Landed event for the player.")
    destroyed: bool = Field(description="The player aircraft was destroyed.")
    fate: Fate = Field(description="How the player aircraft's life ended.")


class WeaponReleased(_Model):
    """Player weapons released, grouped by weapon Name."""

    weapon: str = Field(description="Weapon Name property ('unknown' when absent).")
    count: int = Field(ge=0, description="Number released.")
    hits: int = Field(ge=0, description="How many of them were judged to hit.")


class ShotFact(_Model):
    """One weapon released by the player, attributed by object ids."""

    weapon_id: str = Field(description="Weapon object id.")
    weapon: str | None = Field(default=None, description="Weapon Name property.")
    t_fired: float = Field(description="Release time (s).")
    t_end: float = Field(description="Weapon removal / last time (s).")
    launcher_method: str = Field(description="How the launcher was found (see summary docs).")
    target_id: str | None = Field(default=None, description="Object id hit, if any.")
    target: str | None = Field(default=None, description="Name property of the object hit.")
    hit: bool = Field(description="Whether the weapon is judged to have hit something.")
    hit_method: str = Field(description="How the hit was decided.")


class KillFact(_Model):
    """One destroyed combatant with its credited killer (any side)."""

    victim_id: str = Field(description="Destroyed object id.")
    victim: str = Field(description="Victim Name property, else its id.")
    victim_type: str | None = Field(default=None, description="Victim Type tags.")
    victim_coalition: str | None = Field(default=None, description="Victim Coalition.")
    killer_id: str | None = Field(default=None, description="Credited object id, if any.")
    killer: str | None = Field(default=None, description="Killer Pilot, else Name, else id.")
    by_player: bool = Field(description="The credited killer is the player aircraft.")
    weapon_id: str | None = Field(default=None, description="Credited weapon object id.")
    weapon: str | None = Field(default=None, description="Credited weapon Name property.")
    t: float = Field(description="Destruction time (s).")
    method: KillMethod = Field(description="How the kill was attributed.")
    confidence: Confidence = Field(
        description="Attribution confidence; never state a 'low' kill as fact."
    )


class TimeOverTarget(_Model):
    """Player proximity to one named point / zone."""

    name: str = Field(description="Point or zone name.")
    min_distance_m: float = Field(description="Closest ground distance (m).")
    t_min: float = Field(description="Time of the closest approach (s).")
    radius_m: float | None = Field(default=None, description="Zone radius (m), if a zone.")
    entered: bool | None = Field(default=None, description="Came within radius_m (zones only).")
    first_entry_t: float | None = Field(default=None, description="First time inside (s).")
    time_inside_s: float | None = Field(default=None, description="Time inside the zone (s).")


class TacviewFacts(_Model):
    """``MissionOutcome.extra["tacview"]``: facts from one Tacview ACMI recording."""

    source: str | None = Field(default=None, description="ACMI file path.")
    title: str | None = Field(default=None, description="Global Title.")
    data_source: str | None = Field(default=None, description="Global DataSource (sim).")
    reference_time: str | None = Field(default=None, description="Global ReferenceTime (UTC).")
    recording_time: str | None = Field(default=None, description="Global RecordingTime (UTC).")
    duration_s: float = Field(default=0.0, description="Recording duration (s).")
    player: PlayerFacts | None = Field(default=None, description="Player aircraft, if found.")
    weapons_released: list[WeaponReleased] = Field(
        default_factory=list, description="Player weapons by Name (projectiles excluded)."
    )
    shots: list[ShotFact] = Field(default_factory=list, description="Player weapons, in order.")
    kills: list[KillFact] = Field(default_factory=list, description="All destroyed combatants.")
    time_over_target: list[TimeOverTarget] = Field(
        default_factory=list, description="Player proximity to each named point / zone."
    )
    closest_threat_m: float | None = Field(
        default=None, description="Closest 3-D distance to a hostile AntiAircraft object (m)."
    )
    facts: dict[str, Fact] = Field(
        default_factory=dict, description="Flat tv_* facts (arc condition grammar keys)."
    )
    merged_into_outcomes: bool = Field(
        default=False, description="Facts were also merged into MissionOutcome.outcomes."
    )
    warnings: list[str] = Field(default_factory=list, description="Non-fatal issues.")
    error: str | None = Field(
        default=None, description="Why the ACMI could not be used (then no facts)."
    )


def tacview_facts(
    summary: FlightSummary,
    *,
    recording_time: str | None = None,
    prefix: str = FACT_PREFIX,
) -> TacviewFacts:
    """Structured facts for ``extra["tacview"]`` (pure)."""
    p = summary.player
    pid = p.object_id if p else None
    player = (
        PlayerFacts(
            object_id=p.object_id,
            name=p.name,
            pilot=p.pilot,
            coalition=p.coalition,
            selected_by=p.selected_by,
            first_seen=p.first_seen,
            last_seen=p.last_seen,
            flight_time_s=p.flight_time_s,
            distance_km=p.distance_km,
            min_alt_m=p.min_alt_m,
            max_alt_m=p.max_alt_m,
            takeoffs=list(p.takeoffs),
            landings=list(p.landings),
            landed=bool(p.landings),
            destroyed=p.fate == "destroyed",
            fate=p.fate,
        )
        if p
        else None
    )
    mine = [s for s in summary.shots if pid is not None and s.launcher_id == pid]
    counts: Counter[str] = Counter()
    hits: Counter[str] = Counter()
    for s in mine:
        w = s.weapon_name or "unknown"
        counts[w] += 1
        hits[w] += int(s.hit)
    return TacviewFacts(
        source=summary.source,
        title=summary.title,
        data_source=summary.data_source,
        reference_time=summary.reference_time,
        recording_time=recording_time,
        duration_s=round(summary.duration_s, 1),
        player=player,
        weapons_released=[
            WeaponReleased(weapon=w, count=n, hits=hits[w]) for w, n in sorted(counts.items())
        ],
        shots=[
            ShotFact(
                weapon_id=s.weapon_id,
                weapon=s.weapon_name,
                t_fired=s.t_fired,
                t_end=s.t_end,
                launcher_method=s.launcher_method,
                target_id=s.target_id,
                target=s.target_name,
                hit=s.hit,
                hit_method=s.hit_method,
            )
            for s in mine
        ],
        kills=[
            KillFact(
                victim_id=k.victim_id,
                victim=k.victim_name or k.victim_id,
                victim_type=k.victim_type,
                victim_coalition=k.victim_coalition,
                killer_id=k.killer_id,
                killer=k.killer_pilot or k.killer_name or k.killer_id,
                by_player=pid is not None and k.killer_id == pid,
                weapon_id=k.weapon_id,
                weapon=k.weapon_name,
                t=k.t,
                method=k.method,
                confidence=k.confidence,
            )
            for k in summary.kills
        ],
        time_over_target=[
            TimeOverTarget(
                name=pt.name,
                min_distance_m=pt.min_distance_m,
                t_min=pt.t_min,
                radius_m=pt.radius_m,
                entered=pt.entered,
                first_entry_t=pt.first_entry_t,
                time_inside_s=pt.time_inside_s,
            )
            for pt in summary.points
        ],
        closest_threat_m=summary.threats[0].min_slant_m if summary.threats else None,
        facts=outcome_facts(summary, prefix=prefix),
        warnings=list(summary.warnings),
    )


def attach_tacview(
    outcome: MissionOutcome, block: TacviewFacts, *, merge_into_outcomes: bool = False
) -> MissionOutcome:
    """Return a copy of ``outcome`` with ``block`` under ``extra["tacview"]``.

    With ``merge_into_outcomes`` the ``tv_*`` facts are also added to ``outcomes``, never
    overwriting a key the Lua runtime reported, so arc ``quality_effects`` can use them.
    """
    merging = merge_into_outcomes and bool(block.facts)
    block = block.model_copy(update={"merged_into_outcomes": merging})
    extra: dict[str, Any] = dict(outcome.extra)
    extra["tacview"] = block.model_dump(mode="json")
    update: dict[str, Any] = {"extra": extra}
    if merging:
        merged = dict(outcome.outcomes)
        for k, v in block.facts.items():
            merged.setdefault(k, v)
        update["outcomes"] = merged
    return outcome.model_copy(update=update)
